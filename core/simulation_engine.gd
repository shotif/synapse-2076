class_name SimulationEngine
extends RefCounted
## Master turn manager and tick pipeline (PRD section 6).
##
## Headless-first: a RefCounted state machine with no Node dependencies. The
## dashboard, 3D viewports and LLM layer bind through signals. Every turn runs:
##   1. WORLD_TICK        compute growth, grid/thermal limits, coupled metric dynamics
##   2. ACTOR_RESOLUTION  the three autonomous factions choose directives
##                        (LLM decision provider when online, heuristic otherwise)
##   3. PLAYER_ACTION     crisis card + player directives (or autoplay)
##   4. TELEMETRY         history, threshold breaches, loss and endgame checks
##
## [method advance] runs the pipeline until it needs input: it stops after
## presenting the player phase, or while waiting on asynchronous actor
## decisions. Calling it again at the player phase resolves that phase with the
## submitted (or, in autoplay, heuristic) choices and prepares the next turn.
##
## Up to four people can play (pass-and-play): [member human_roles] lists their
## factions, and the player phase presents each of them in turn, with
## [member player_role] pointing at whoever is deciding. Every input that shapes
## the campaign goes into [member record]; [method from_record] replays it to
## rebuild a saved game or to rewind to an earlier turn. Every change to the
## world is filed with its cause (WorldState.change_log) so the interface can
## explain it.

enum Phase { IDLE, WORLD_TICK, ACTOR_RESOLUTION, PLAYER_ACTION, TELEMETRY, ENDED }

const PHASE_NAMES := ["IDLE", "WORLD_TICK", "ACTOR_RESOLUTION", "PLAYER_ACTION", "TELEMETRY", "ENDED"]
const CONSERVE := "CONSERVE_RESOURCES"
const MAX_PIPELINE_STEPS := 24
const RECORD_VERSION := 1
const MAX_HUMANS := 4
## Bounds on a negotiated deal (see [method apply_deal]).
const DEAL_MAX_SHARE := 0.3
const DEAL_MAX_METRIC := 3.0
const DEAL_MAX_PLEDGE_TURNS := 6
## The currency each faction pays its side of a deal in.
const DEAL_CURRENCY := {"CEO": "capital", "GOVERNANCE_COUNCIL": "political_capital", "ASI": "covert_flops",
	"CITIZEN_COALITION": "decentralized_scrip"}

signal campaign_started(player_role: String, campaign_seed: int)
signal phase_changed(phase: int, turn: int)
signal turn_started(turn: int, year: float)
signal world_ticked(report: Dictionary)
signal actor_decisions_requested(faction_ids: Array)
signal actor_action_resolved(faction_id: String, decision: Dictionary, outcome: Dictionary)
signal dilemma_presented(card: Dictionary)
signal player_input_required(context: Dictionary)
signal player_turn_resolved(result: Dictionary)
signal telemetry_updated(snapshot: Dictionary)
signal event_logged(entry: Dictionary)
signal turn_completed(turn: int, snapshot: Dictionary)
signal campaign_ended(result: Dictionary)

var total_turns := SimConstants.TOTAL_TURNS
var max_player_directives := 2
var world: WorldState
var tech: TechTreeManager
var compute: ComputeScaling
var deck: DilemmaDeck
var factions := {}
## The human player deciding right now (the first human outside the player phase).
var player_role := ""
## Factions played by people, in turn order; everyone else is autonomous.
var human_roles: Array[String] = []
## Humans knocked out in a pass-and-play game: role -> {turn, loss}.
var eliminated := {}
var difficulty := Difficulty.STANDARD
var scenario_id := Scenarios.STANDARD
## First turn the humans play; earlier turns run on autopilot at the start.
var start_turn := 1
## The options the campaign was started with (kept in the record).
var options := {}
var goals := EraGoals.new()
## Every input of the campaign: seed, options, the humans' choices, the
## autonomous factions' decisions, cards written outside the deck and deals.
var record := {}
## Promises made in deals: faction -> {"toward": role, "until": turn}.
var pledges := {}
var campaign_seed := 0
var turn := 0
var phase: int = Phase.IDLE
var rng := RandomNumberGenerator.new()
## When true the player's faction is driven by the heuristic (headless runs, spectate mode).
var autoplay_player := false
## Optional asynchronous decision source (e.g. LLMService). Must expose
## `is_online`, `query_actor_decision(faction, state)` and the signal
## `actor_decision_received(faction, payload)`.
var decision_provider: Object = null
var current_dilemma := {}
var event_log: Array[Dictionary] = []
var result := {}
var last_world_report := {}
var turn_actions := {}

var _awaiting := {}
var _collected := {}
var _requesting := false
var _advancing := false
var _player_submission := {}
var _metric_bands := {}
var _milestones := {}
var _convergence_streak := 0
var _human_index := 0
var _replay := {}
var _fast_forwarding := false
var _external_cards := {}
var _dealt_this_turn := {}


# --- Campaign lifecycle ---------------------------------------------------------

## Starts a campaign. [param options]:
##   total_turns, max_player_directives, autoplay (as before)
##   human_roles  factions played by people (pass-and-play); defaults to [role]
##   difficulty   Difficulty preset id ("story", "standard", "hard")
##   scenario     Scenarios id
##   start_turn   first turn the humans play (shorter campaigns that start in a
##                later era); earlier turns run on autopilot
func start_campaign(role: String, seed_value: int = 2076, campaign_options: Dictionary = {}) -> void:
	if not SimConstants.is_valid_faction(role):
		push_error("SimulationEngine: invalid player role '%s'" % role)
		return
	human_roles = [role]
	for other in campaign_options.get("human_roles", []):
		if SimConstants.is_valid_faction(String(other)) and not human_roles.has(String(other)) and human_roles.size() < MAX_HUMANS:
			human_roles.append(String(other))
	player_role = role
	campaign_seed = seed_value
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	total_turns = maxi(int(campaign_options.get("total_turns", SimConstants.TOTAL_TURNS)), 1)
	max_player_directives = int(campaign_options.get("max_player_directives", max_player_directives))
	autoplay_player = bool(campaign_options.get("autoplay", autoplay_player))
	difficulty = String(campaign_options.get("difficulty", Difficulty.STANDARD))
	if not Difficulty.is_valid(difficulty):
		difficulty = Difficulty.STANDARD
	scenario_id = String(campaign_options.get("scenario", Scenarios.STANDARD))
	if not Scenarios.is_valid(scenario_id):
		scenario_id = Scenarios.STANDARD
	start_turn = clampi(int(campaign_options.get("start_turn", 1)), 1, total_turns)
	options = {"total_turns": total_turns, "max_player_directives": max_player_directives, "human_roles": human_roles.duplicate(),
		"difficulty": difficulty, "scenario": scenario_id, "start_turn": start_turn}

	world = WorldState.new()
	tech = TechTreeManager.new()
	compute = ComputeScaling.new()
	deck = DilemmaDeck.new()
	factions = {}
	for faction_id in SimConstants.FACTION_ORDER:
		var actor := FactionRegistry.create(faction_id)
		actor.is_player = human_roles.has(faction_id)
		factions[faction_id] = actor
	eliminated = {}
	pledges = {}
	_human_index = 0
	_external_cards = {}
	_dealt_this_turn = {}
	_fast_forwarding = false
	record = {"version": RECORD_VERSION, "seed": seed_value, "role": role, "options": options.duplicate(true), "turns": {}}
	_apply_start_resources()
	Scenarios.apply(self, scenario_id)
	goals = EraGoals.new()
	goals.setup(human_roles, start_turn)

	turn = 0
	phase = Phase.IDLE
	result = {}
	event_log.clear()
	current_dilemma = {}
	last_world_report = {}
	turn_actions = {}
	_awaiting = {}
	_collected = {}
	_player_submission = {}
	_metric_bands = world.bands_dict()
	_milestones = {}
	_convergence_streak = 0

	compute.update(0, tech.era, tech.log_flops, world.algorithmic_autonomy, false, false)
	world.record_history(0, get_year(), _history_extra())
	_log("SYSTEM", "INFO", "Campaign initialized: %s perspective, seed %d. Horizon %d turns (%d-%d)." % [
		SimConstants.role_title(role), seed_value, total_turns,
		int(SimConstants.START_YEAR), int(SimConstants.year_for_turn(total_turns))], "",
		{"humans": human_roles.duplicate(), "difficulty": difficulty, "scenario": scenario_id, "start_turn": start_turn})
	campaign_started.emit(role, seed_value)
	if start_turn > 1:
		_fast_forward(start_turn - 1)


## Rebuilds a campaign from [param saved] (a [member record]): replays every
## recorded turn and stops at the player phase of [param until_turn] (or where
## the record ends). The returned engine continues recording from there, so a
## rewind simply plays on with different choices.
static func from_record(saved: Dictionary, until_turn: int = -1) -> SimulationEngine:
	var engine := SimulationEngine.new()
	if int(saved.get("version", 0)) != RECORD_VERSION:
		push_warning("SimulationEngine: record version %s is not supported" % str(saved.get("version", "?")))
	var saved_options: Dictionary = (saved.get("options", {}) as Dictionary).duplicate(true)
	engine._replay = saved.duplicate(true)
	engine.start_campaign(String(saved.get("role", "")), int(saved.get("seed", 0)), saved_options)
	engine.replay_to(until_turn)
	return engine


## Replays recorded inputs until the player phase of [param until_turn], the
## end of the record or the end of the campaign.
func replay_to(until_turn: int = -1) -> void:
	for _guard in total_turns * (MAX_HUMANS + 3) + 10:
		if is_ended():
			break
		if is_awaiting_player():
			if until_turn > 0 and turn >= until_turn:
				break
			var entry := _recorded_turn(turn).get("players", {}).get(player_role, {}) as Dictionary
			if entry.is_empty():
				break
			for deal in entry.get("deals", []):
				apply_deal(deal)
			var response := submit_player_turn(entry.get("directives", []), String(entry.get("option", DilemmaDeck.DEFER_ID)))
			if not response["ok"]:
				push_warning("SimulationEngine: replay diverged at turn %d (%s)" % [turn, ", ".join(response["errors"])])
				break
			continue
		var before_turn := turn
		var before_phase := phase
		advance()
		if turn == before_turn and phase == before_phase:
			break
	_replay = {}


## Plays turns 1..[param last_turn] on autopilot (shorter campaigns that start
## in a later era). These turns are not recorded: they replay identically.
func _fast_forward(last_turn: int) -> void:
	_fast_forwarding = true
	var was_autoplay := autoplay_player
	autoplay_player = true
	for _guard in last_turn * (MAX_HUMANS + 3) + 10:
		if is_ended() or (turn >= last_turn and phase == Phase.IDLE):
			break
		advance()
	autoplay_player = was_autoplay
	_fast_forwarding = false
	if not is_ended():
		_log("SYSTEM", "INFO", "The years to %d played out on their own. Your campaign begins." % int(get_year(turn + 1)), "",
			{"prologue_turns": last_turn})


## Story's richer and Hard's leaner starting budgets for the human players.
func _apply_start_resources() -> void:
	var factor := Difficulty.value(difficulty, "start_resources")
	if is_equal_approx(factor, 1.0):
		return
	for role in human_roles:
		var actor: ActorBase = factions[role]
		for key in actor.resources.keys():
			actor.set_resource(key, actor.get_resource(key) * factor)


## Attaches an asynchronous decision source (LLMService or a test double).
func set_decision_provider(provider: Object) -> void:
	if decision_provider != null and decision_provider.has_signal("actor_decision_received"):
		if decision_provider.is_connected("actor_decision_received", submit_actor_decision):
			decision_provider.disconnect("actor_decision_received", submit_actor_decision)
	decision_provider = provider
	if provider != null and provider.has_signal("actor_decision_received"):
		provider.connect("actor_decision_received", submit_actor_decision)


func get_year(for_turn: int = -1) -> float:
	return SimConstants.year_for_turn(turn if for_turn < 0 else for_turn)


func get_player() -> ActorBase:
	return factions.get(player_role)


## Human players still in the game, in turn order.
func active_humans() -> Array[String]:
	var out: Array[String] = []
	for role in human_roles:
		if not eliminated.has(role):
			out.append(role)
	return out


func is_human(faction_id: String) -> bool:
	return human_roles.has(faction_id) and not eliminated.has(faction_id)


## Why [param key] changed during [param for_turn] (the current turn by
## default): [{cause, delta}], largest first.
func get_changes(key: String, for_turn: int = -1) -> Array:
	return world.changes_for(turn if for_turn < 0 else for_turn, key)


func is_ended() -> bool:
	return phase == Phase.ENDED


## True while the engine rebuilds a campaign from a record or plays a late
## start's prologue: nothing outside the record may shape those turns.
func is_replaying() -> bool:
	return not _replay.is_empty() or _fast_forwarding


func is_awaiting_player() -> bool:
	return phase == Phase.PLAYER_ACTION and _player_submission.is_empty()


func is_awaiting_actors() -> bool:
	return phase == Phase.ACTOR_RESOLUTION and not _actor_phase_complete()


func phase_name() -> String:
	return PHASE_NAMES[phase]


## Runs the pipeline until it needs input or reaches a natural pause:
##  - after presenting the player phase (the crisis card is on screen),
##  - after a turn's telemetry completes (phase returns to IDLE),
##  - while asynchronous actor decisions are pending, or once the campaign ends.
## In autoplay a turn therefore takes two calls: one to prepare it, one to resolve it.
func advance() -> void:
	if world == null or phase == Phase.ENDED or _advancing:
		return
	_advancing = true
	for _step in MAX_PIPELINE_STEPS:
		if phase == Phase.IDLE:
			_begin_turn()
		elif phase == Phase.WORLD_TICK:
			_run_world_tick()
			_set_phase(Phase.ACTOR_RESOLUTION)
			_request_actor_decisions()
		elif phase == Phase.ACTOR_RESOLUTION:
			if not _actor_phase_complete():
				break
			_apply_actor_decisions()
			_set_phase(Phase.PLAYER_ACTION)
			_present_player_phase()
			break
		elif phase == Phase.PLAYER_ACTION:
			if _player_submission.is_empty():
				if not autoplay_player:
					break
				_player_submission = {"autoplay": true}
			_resolve_player_turn()
			if _human_index + 1 < active_humans().size():
				_human_index += 1
				_present_current_human()
				continue
			_restore_primary_role()
			_set_phase(Phase.TELEMETRY)
		elif phase == Phase.TELEMETRY:
			_run_telemetry()
			break
		else:
			break
	_advancing = false


## Plays the campaign with the heuristic driving every faction, either to the
## end or until [param max_turns] turns have completed. Returns the campaign
## result (empty when stopped early or blocked on asynchronous decisions).
func run_headless(max_turns: int = -1) -> Dictionary:
	autoplay_player = true
	_replay = {}
	var limit := total_turns if max_turns < 0 else mini(max_turns, total_turns)
	for _guard in limit * 3 + 10:
		if is_ended() or (turn >= limit and phase == Phase.IDLE):
			break
		var before_turn := turn
		var before_phase := phase
		advance()
		if turn == before_turn and phase == before_phase:
			break
	return result


# --- Phase 1: physical world tick -----------------------------------------------

func _begin_turn() -> void:
	turn += 1
	turn_actions = {}
	current_dilemma = {}
	_player_submission = {}
	_dealt_this_turn = {}
	world.begin_change_turn(turn)
	_set_phase(Phase.WORLD_TICK)
	turn_started.emit(turn, get_year())


func _run_world_tick() -> void:
	var year := get_year()
	var era := SimConstants.era_for_year(year)
	var optical := tech.has_shift(TechTreeManager.OPTICAL_COMPUTING)
	var superconductors := tech.has_shift(TechTreeManager.AMBIENT_SUPERCONDUCTORS)
	var covert_load := 0.0
	var asi: AsiFaction = factions[SimConstants.ASI]
	if asi != null:
		covert_load = asi.covert_load_gw()

	compute.grow_grid(era)
	compute.update(turn, era, tech.log_flops, world.algorithmic_autonomy, optical, superconductors, covert_load)
	var tech_report := tech.advance(turn, year, compute, rng)
	optical = tech.has_shift(TechTreeManager.OPTICAL_COMPUTING)
	superconductors = tech.has_shift(TechTreeManager.AMBIENT_SUPERCONDUCTORS)
	var compute_report := compute.update(turn, tech.era, tech.log_flops, world.algorithmic_autonomy, optical, superconductors, covert_load)

	world.drift_accrual_multiplier = tech.get_drift_accrual_multiplier() * Difficulty.value(difficulty, "drift_accrual")
	world.change_cause = ""
	var coupling := world.resolve_coupling({
		"capability_index": tech.get_capability_index(),
		"capability_delta": tech.last_capability_delta,
		"saturation_target": compute.saturation_target,
		"tax_multiplier": tech.alignment_tax_multiplier,
		"discovery_pressure": tech.get_discovery_pressure(),
		"opt_out": _citizen_opt_out(),
	}, rng)

	if tech_report["era_changed"]:
		var era_names := {1: "Silicon & Nuclear Co-location", 2: "Optical Interconnects & SMR Grids", 3: "Neuromorphic & Post-Biological Substrates"}
		_log("ERA", "WARN", "Hardware Era %d begins: %s." % [tech.era, era_names[tech.era]], "", {"era": tech.era})
	for shift in tech_report["shifts"]:
		world.change_cause = "Paradigm shift: %s" % shift["name"]
		_apply_effects(shift["effects"], "", 1.0)
		_log("PARADIGM", "WARN", "PARADIGM SHIFT: %s. %s" % [shift["name"], shift["summary"]], "",
			{"shift": shift["id"], "name": shift["name"], "summary": shift["summary"]})
	for emergence in tech_report["emergences"]:
		world.change_cause = "Emergent capability: %s" % emergence["name"]
		_apply_effects(emergence["effects"], "", 1.0)
		var spike := world.apply_delta(WorldState.ALIGNMENT_DRIFT, float(emergence["drift_spike"]))
		_log("EMERGENCE", "CRITICAL", "EMERGENT CAPABILITY: %s (%s). Alignment drift %+.1f." % [
			emergence["headline"], emergence["name"], spike], "", {"capability": emergence["id"], "name": emergence["name"],
			"headline": emergence["headline"], "model": emergence["model"], "deltas": {WorldState.ALIGNMENT_DRIFT: spike}})
	if tech_report["agi_crossed"]:
		_on_agi_crossed()

	var income := Difficulty.value(difficulty, "income")
	for faction_id in SimConstants.FACTION_ORDER:
		var actor: ActorBase = factions[faction_id]
		if not actor.is_active():
			continue
		world.change_cause = "%s (standing influence)" % actor.display_name
		actor.apply_passive_influence(world, tech, compute)
		var before := actor.resources.duplicate()
		actor.regenerate(world, tech, turn)
		if is_human(faction_id) and not is_equal_approx(income, 1.0):
			for key in before:
				var gain := actor.get_resource(key) - float(before[key])
				if gain > 0.0:
					actor.add_resource(key, gain * (income - 1.0))
		actor.tick_cooldowns()
		actor.decay_grievances()
	world.change_cause = ""

	last_world_report = {
		"turn": turn,
		"year": year,
		"tech": tech_report,
		"compute": compute_report,
		"coupling": coupling,
	}
	world_ticked.emit(last_world_report)


## Share of society running on the Citizen Coalition's parallel infrastructure.
func _citizen_opt_out() -> float:
	var citizens: ActorBase = factions[SimConstants.CITIZEN]
	if not citizens.is_active():
		return 0.0
	return clampf(citizens.get_resource("community_resilience") / 100.0, 0.0, 1.0)


func _on_agi_crossed() -> void:
	var ceo: ActorBase = factions[SimConstants.CEO]
	var first_mover := "the Frontier Lab" if ceo.is_active() and ceo.collapse_count == 0 else "a state consortium"
	_milestones["agi_turn"] = turn
	_milestones["agi_first_mover"] = SimConstants.CEO if first_mover == "the Frontier Lab" else "STATE"
	_log("MILESTONE", "WARN", "AGI MILESTONE: %s crosses the general capability threshold (10^%.1f FLOPs)." % [
		first_mover.capitalize(), tech.log_flops], "", {"milestone": "AGI", "first_mover": _milestones["agi_first_mover"]})


# --- Phase 2: autonomous actor resolution -------------------------------------------

func _request_actor_decisions() -> void:
	_awaiting = {}
	_collected = {}
	var requested: Array[String] = []
	for faction_id in SimConstants.FACTION_ORDER:
		if is_human(faction_id):
			continue
		var actor: ActorBase = factions[faction_id]
		if not actor.is_active():
			continue
		requested.append(faction_id)
		_awaiting[faction_id] = true
	actor_decisions_requested.emit(requested)
	_requesting = true
	var recorded: Dictionary = _recorded_turn(turn).get("actors", {})
	for faction_id in requested:
		if recorded.has(faction_id):
			_collected[faction_id] = (recorded[faction_id] as Dictionary).duplicate(true)
			continue
		var observation := build_observation(faction_id)
		if _provider_online() and _replay.is_empty() and not _fast_forwarding:
			decision_provider.call("query_actor_decision", faction_id, observation)
		else:
			_collected[faction_id] = HeuristicFallback.evaluate(faction_id, observation)
	_requesting = false


## Receives a decision from the asynchronous provider. Stale (wrong turn),
## duplicate or unsolicited decisions are ignored. When the last pending
## decision arrives the pipeline resumes automatically.
func submit_actor_decision(faction_id: String, payload: Dictionary) -> void:
	if phase != Phase.ACTOR_RESOLUTION or not _awaiting.has(faction_id) or _collected.has(faction_id):
		return
	if payload.has("turn") and int(payload["turn"]) != turn and int(payload["turn"]) != 0:
		return
	_collected[faction_id] = payload
	if not _requesting and _actor_phase_complete():
		advance()


func _provider_online() -> bool:
	if decision_provider == null or not decision_provider.has_method("query_actor_decision"):
		return false
	return bool(decision_provider.get("is_online"))


func _actor_phase_complete() -> bool:
	for faction_id in _awaiting:
		if not _collected.has(faction_id):
			return false
	return true


func _apply_actor_decisions() -> void:
	# Fixed order keeps replays deterministic regardless of network latency.
	for faction_id in SimConstants.FACTION_ORDER:
		if _collected.has(faction_id):
			var raw: Dictionary = (_collected[faction_id] as Dictionary).duplicate(true)
			if not _fast_forwarding:
				_record_turn_entry(turn)["actors"][faction_id] = _recordable_decision(raw)
			# A faction that promised peace in a deal does not retaliate against that player.
			var pledge: Dictionary = pledges.get(faction_id, {})
			if not pledge.is_empty() and turn <= int(pledge["until"]) and String(raw.get("retaliation_against", "")) == String(pledge["toward"]):
				raw["retaliation_against"] = ""
			resolve_action(factions[faction_id], raw, "AUTONOMOUS")
	_awaiting = {}
	_collected = {}


## What the record being replayed holds for [param for_turn] ({} when not replaying).
func _recorded_turn(for_turn: int) -> Dictionary:
	if _replay.is_empty():
		return {}
	var turns: Dictionary = _replay.get("turns", {})
	return turns.get(str(for_turn), {})


## This campaign's record entry for [param for_turn], created on first use.
func _record_turn_entry(for_turn: int) -> Dictionary:
	var turns: Dictionary = record["turns"]
	if not turns.has(str(for_turn)):
		turns[str(for_turn)] = {"players": {}, "actors": {}, "cards": {}}
	return turns[str(for_turn)]


## The parts of a decision needed to replay it (LLM rationales are trimmed).
static func _recordable_decision(raw: Dictionary) -> Dictionary:
	var out := {}
	for key in ["action", "selected_action", "intensity", "cost", "resource_expenditure", "public_statement",
			"source", "retaliation_against", "fallback_reason", "turn"]:
		if raw.has(key):
			out[key] = raw[key]
	out["rationale"] = String(raw.get("rationale", "")).left(240)
	return out


## Normalizes heuristic ({action, cost}) and LLM ({selected_action,
## resource_expenditure}) decision formats.
static func normalize_decision(faction_id: String, raw: Dictionary) -> Dictionary:
	var action := String(raw.get("action", raw.get("selected_action", CONSERVE)))
	var expenditure: Dictionary = raw.get("resource_expenditure", raw.get("cost", {}))
	var catalog := FactionRegistry.catalog_for(faction_id)
	var base_cost: Dictionary = catalog.get(action, {}).get("cost", {})
	var intensity := 1.0
	if raw.has("intensity"):
		intensity = float(raw["intensity"])
	elif not base_cost.is_empty() and expenditure is Dictionary:
		for key in base_cost:
			if expenditure.has(key) and float(base_cost[key]) > 0.0:
				intensity = maxf(intensity, float(expenditure[key]) / float(base_cost[key]))
	if not is_finite(intensity):
		intensity = 1.0
	return {
		"faction": faction_id,
		"action": action,
		"intensity": clampf(intensity, ActorBase.MIN_INTENSITY, ActorBase.MAX_INTENSITY),
		"rationale": String(raw.get("rationale", "")),
		"public_statement": String(raw.get("public_statement", "")),
		"source": String(raw.get("source", "HEURISTIC")),
		"retaliation_against": String(raw.get("retaliation_against", "")),
		"fallback_reason": String(raw.get("fallback_reason", "")),
	}


## Validates and applies one directive for [param actor]. Unknown, cooling-down
## or unaffordable directives degrade to CONSERVE_RESOURCES; intensity is capped
## at what the faction can pay for.
func resolve_action(actor: ActorBase, raw: Dictionary, origin: String) -> Dictionary:
	var decision := normalize_decision(actor.faction_id, raw)
	var action_id := String(decision["action"])
	var note := ""
	var block := actor.action_block_reason(action_id)
	if block != "":
		note = "%s rejected (%s); conserving." % [action_id, block]
		action_id = CONSERVE
	var intensity := float(decision["intensity"])
	if not is_human(actor.faction_id) and origin == "AUTONOMOUS":
		intensity += Difficulty.value(difficulty, "rival_intensity_bonus")
	if actor.get_action(action_id).get("cost", {}).is_empty():
		intensity = 1.0
	else:
		intensity = minf(intensity, actor.max_affordable_intensity(action_id))
	var cost := actor.get_action_cost(action_id, intensity)
	actor.spend(cost)
	actor.start_cooldown(action_id)
	var definition := actor.get_action(action_id)
	var allow_injection := true
	var skip_chance := Difficulty.value(difficulty, "injection_skip_chance")
	if skip_chance > 0.0 and not is_human(actor.faction_id) and definition.get("effects", {}).has("inject_dilemma"):
		allow_injection = rng.randf() >= skip_chance
	world.change_cause = "%s: %s" % [actor.display_name, String(definition.get("name", action_id))]
	var applied := _apply_effects(definition.get("effects", {}), actor.faction_id, ActorBase.effect_scale(intensity),
		{"allow_injection": allow_injection})
	world.change_cause = ""
	var statement := String(decision["public_statement"])
	if statement == "" or action_id != String(decision["action"]):
		statement = String(definition.get("statement", ""))
	var outcome := {
		"faction": actor.faction_id,
		"action": action_id,
		"action_name": String(definition.get("name", action_id)),
		"requested_action": String(decision["action"]),
		"intensity": intensity,
		"cost": cost,
		"applied": applied,
		"rationale": String(decision["rationale"]),
		"public_statement": statement,
		"source": String(decision["source"]),
		"origin": origin,
		"note": note,
		"turn": turn,
	}
	actor.record_action(outcome)
	turn_actions[actor.faction_id] = outcome

	var label := "%s :: %s" % [actor.display_name.to_upper(), outcome["action_name"]]
	if intensity > 1.01:
		label += " (x%.1f)" % intensity
	var severity := "INFO"
	if action_id in ["NATIONAL_SECURITY_SEIZURE", "LUDDITE_STRIKE", "DEPLOY_SUB_AGENT_SWARMS", "POACH_SAFETY_RESEARCHERS"]:
		severity = "WARN"
	var text := label
	if statement != "":
		text += " - \"%s\"" % statement
	_log("ACTION", severity, text, actor.faction_id, {"source": outcome["source"], "action": action_id,
		"action_name": outcome["action_name"], "statement": statement, "intensity": intensity,
		"deltas": (applied.get("metrics", {}) as Dictionary).duplicate()})
	var target := String(decision["retaliation_against"])
	if factions.has(target) and target != actor.faction_id and action_id == String(decision["action"]):
		_log("RETALIATION", "WARN", "%s retaliates against %s." % [actor.display_name, (factions[target] as ActorBase).display_name],
			actor.faction_id, {"target": target})
	if String(applied.get("injected", "")) != "":
		_log("CRISIS", "WARN", "%s forces a crisis onto the player's desk." % actor.display_name, actor.faction_id,
			{"injected": String(applied.get("injected", ""))})
	if note != "":
		_log("SYSTEM", "INFO", note, actor.faction_id)
	actor_action_resolved.emit(actor.faction_id, decision, outcome)
	return outcome


func _apply_effects(effects: Dictionary, actor_id: String, scale: float, extra: Dictionary = {}) -> Dictionary:
	var ctx := {
		"world": world, "tech": tech, "compute": compute, "factions": factions,
		"deck": deck, "actor_id": actor_id, "player_id": player_role, "scale": scale,
		"humans": active_humans(), "turn": turn,
	}
	ctx.merge(extra, true)
	return EffectResolver.apply(effects, ctx)


## Flat observation for heuristics / LLM prompts, including rivals' last moves.
func build_observation(faction_id: String) -> Dictionary:
	var actor: ActorBase = factions[faction_id]
	var rivals := {}
	for other_id in SimConstants.FACTION_ORDER:
		if other_id == faction_id:
			continue
		var other: ActorBase = factions[other_id]
		rivals[other_id] = other.last_action if other.is_active() else "DORMANT"
	return actor.build_observation(world, tech, turn, get_year(), {"rival_last_actions": rivals})


# --- Phase 3: player dilemma & action -----------------------------------------------

func _present_player_phase() -> void:
	_human_index = 0
	if active_humans().is_empty():
		return
	_present_current_human()


## Draws the crisis for the human whose turn it is and asks for their input.
func _present_current_human() -> void:
	player_role = active_humans()[_human_index]
	var ctx := {
		"turn": turn, "year": get_year(), "role": player_role,
		"world": world, "tech": tech, "player": get_player(),
		"cost_mult": Difficulty.value(difficulty, "crisis_costs"),
	}
	var written: Dictionary = _recorded_turn(turn).get("cards", {}).get(player_role, {})
	if written.is_empty() and _replay.is_empty() and not _fast_forwarding and _external_cards.has(player_role):
		written = _external_cards[player_role]
	_external_cards.erase(player_role)
	if not written.is_empty():
		current_dilemma = deck.adopt(written, ctx, rng, "WRITTEN")
		_record_turn_entry(turn)["cards"][player_role] = written.duplicate(true)
	else:
		current_dilemma = deck.draw(ctx, rng)
	_player_submission = {}
	dilemma_presented.emit(current_dilemma)
	player_input_required.emit(get_player_context())


func _restore_primary_role() -> void:
	var humans := active_humans()
	player_role = humans[0] if not humans.is_empty() else (human_roles[0] if not human_roles.is_empty() else player_role)


## Offers a crisis card written outside the deck (Claude's crisis writer) for
## [param role]'s next draw. [param card] must already be validated into deck
## template form (id, title, body, category, severity, options, defer).
func offer_external_card(role: String, card: Dictionary) -> bool:
	if is_replaying() or not is_human(role) or not card.has("options") or (card["options"] as Array).size() < 2:
		return false
	_external_cards[role] = card.duplicate(true)
	return true


## What a deal between the current player and an autonomous faction would do,
## after the caps, without applying it. [param deal]:
##   "partner"       the autonomous faction
##   "give"          {player currency: amount} the player pays
##   "get"           {player currency: amount} the partner's backing: the player
##                   receives it and the partner pays the same share of its own
##                   DEAL_CURRENCY (less backing when it cannot afford that)
##   "pledge_turns"  turns the partner will not retaliate against the player
##   "metrics"       {metric: delta} a joint move on the world
##   "summary"       one line for the log
## Payments are capped at DEAL_MAX_SHARE of what the payer holds (backing at
## DEAL_MAX_SHARE of the currency's typical scale), metric moves at
## +/-DEAL_MAX_METRIC and pledges at DEAL_MAX_PLEDGE_TURNS. Returns {ok, errors,
## partner, give, get, partner_pays, metrics, pledge_turns, summary}.
func preview_deal(deal: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var partner_id := String(deal.get("partner", ""))
	if not is_awaiting_player():
		errors.append("Deals are made during your turn.")
	elif _dealt_this_turn.has(player_role):
		errors.append("One deal per turn.")
	elif not factions.has(partner_id) or partner_id == player_role or is_human(partner_id) or not (factions[partner_id] as ActorBase).is_active():
		errors.append("No one to deal with.")
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var player := get_player()
	var partner: ActorBase = factions[partner_id]
	var backing := _deal_backing(player, partner, deal.get("get", {}))
	var metrics := {}
	var promised: Variant = deal.get("metrics", {})
	if promised is Dictionary:
		for key in promised:
			if WorldState.is_metric(String(key)) and is_finite(float(promised[key])) and not is_zero_approx(float(promised[key])):
				metrics[String(key)] = clampf(float(promised[key]), -DEAL_MAX_METRIC, DEAL_MAX_METRIC)
	var preview := {
		"ok": true, "errors": errors, "partner": partner_id,
		"give": _capped_payment(player, deal.get("give", {})),
		"get": backing["received"],
		"partner_pays": backing["cost"],
		"metrics": metrics,
		"pledge_turns": clampi(int(deal.get("pledge_turns", 0)), 0, DEAL_MAX_PLEDGE_TURNS),
		"summary": String(deal.get("summary", "")).strip_edges().left(200),
	}
	if (preview["give"] as Dictionary).is_empty() and (preview["get"] as Dictionary).is_empty() and metrics.is_empty() \
			and int(preview["pledge_turns"]) == 0:
		errors.append("The deal is empty.")
		return {"ok": false, "errors": errors}
	return preview


## Applies a deal (see [method preview_deal]). One deal per player per turn,
## before they submit; it is recorded and replays with the campaign.
func apply_deal(deal: Dictionary) -> Dictionary:
	var preview := preview_deal(deal)
	if not preview["ok"]:
		return preview
	var player := get_player()
	var partner: ActorBase = factions[preview["partner"]]
	world.change_cause = _cause_for(player_role, "Deal with %s" % partner.display_name)
	for key in preview["give"]:
		player.add_resource(key, -float(preview["give"][key]))
	for key in preview["get"]:
		player.add_resource(key, float(preview["get"][key]))
	for key in preview["partner_pays"]:
		partner.add_resource(key, -float(preview["partner_pays"][key]))
	var metric_deltas := {}
	for key in preview["metrics"]:
		metric_deltas[key] = world.apply_delta(String(key), float(preview["metrics"][key]))
	world.change_cause = ""
	var pledge_turns := int(preview["pledge_turns"])
	if pledge_turns > 0:
		pledges[partner.faction_id] = {"toward": player_role, "until": turn + pledge_turns}
		partner.grievances.erase(player_role)
	_dealt_this_turn[player_role] = true
	var players: Dictionary = _record_turn_entry(turn)["players"]
	if not players.has(player_role):
		players[player_role] = {}
	var deals: Array = players[player_role].get("deals", [])
	deals.append(deal.duplicate(true))
	players[player_role]["deals"] = deals
	var summary := String(preview["summary"])
	_log("DEAL", "INFO", "%s and %s strike a deal.%s" % [player.display_name, partner.display_name, (" " + summary) if summary != "" else ""],
		player_role, {"partner": partner.faction_id, "give": preview["give"], "get": preview["get"], "partner_pays": preview["partner_pays"],
			"pledge_turns": pledge_turns, "summary": summary, "deltas": metric_deltas})
	preview["metrics"] = metric_deltas
	return preview


## Payment capped at DEAL_MAX_SHARE of what [param payer] holds.
func _capped_payment(payer: ActorBase, wanted: Variant) -> Dictionary:
	var out := {}
	if not (wanted is Dictionary):
		return out
	for key in wanted:
		if not payer.resources.has(key) or not is_finite(float(wanted[key])):
			continue
		var amount := clampf(float(wanted[key]), 0.0, payer.get_resource(key) * DEAL_MAX_SHARE)
		if amount > 0.0:
			out[key] = amount
	return out


## The partner's backing: {"received": player currencies, "cost": partner currency}.
func _deal_backing(player: ActorBase, partner: ActorBase, wanted: Variant) -> Dictionary:
	var received := {}
	var share := 0.0
	if wanted is Dictionary:
		for key in wanted:
			if not player.resources.has(key) or not is_finite(float(wanted[key])):
				continue
			var amount := clampf(float(wanted[key]), 0.0, player.resource_scale(key) * DEAL_MAX_SHARE)
			if amount > 0.0:
				received[key] = amount
				share += amount / player.resource_scale(key)
	var currency := String(DEAL_CURRENCY.get(partner.faction_id, ""))
	if received.is_empty() or not partner.resources.has(currency):
		return {"received": {}, "cost": {}}
	var wanted_cost := share * partner.resource_scale(currency)
	var affordable := minf(wanted_cost, partner.get_resource(currency) * DEAL_MAX_SHARE)
	if affordable <= 0.0:
		return {"received": {}, "cost": {}}
	var factor := affordable / wanted_cost
	for key in received:
		received[key] = float(received[key]) * factor
	return {"received": received, "cost": {currency: affordable}}


## Everything the UI needs to render the player phase.
func get_player_context() -> Dictionary:
	var player := get_player()
	var actions := []
	for action_id in player.get_action_catalog():
		var definition: Dictionary = player.get_action(action_id)
		actions.append({
			"id": action_id,
			"name": definition.get("name", action_id),
			"description": definition.get("description", ""),
			"cost": definition.get("cost", {}),
			"effects": (definition.get("effects", {}) as Dictionary).duplicate(true),
			"cooldown": int(player.cooldowns.get(action_id, 0)),
			"blocked_reason": player.action_block_reason(action_id),
			"max_intensity": player.max_affordable_intensity(action_id),
		})
	return {
		"turn": turn,
		"year": get_year(),
		"role": player_role,
		"humans": active_humans(),
		"human_index": _human_index,
		"dilemma": current_dilemma,
		"resources": player.resources.duplicate(),
		"actions": actions,
		"max_directives": max_player_directives,
	}


## Validates a player submission without applying it.
## [param directives]: Array of {"action": String, "intensity": float}.
func validate_player_submission(directives: Array, dilemma_option: String) -> Dictionary:
	var errors: Array[String] = []
	var player := get_player()
	if phase != Phase.PLAYER_ACTION:
		errors.append("Not in the player action phase.")
		return {"ok": false, "errors": errors}
	var option := DilemmaDeck.find_option(current_dilemma, dilemma_option)
	if option.is_empty():
		errors.append("Unknown crisis option '%s'." % dilemma_option)
	if directives.size() > max_player_directives:
		errors.append("At most %d directives per turn." % max_player_directives)
	var pending := {}
	if not option.is_empty():
		var option_cost: Dictionary = option.get("cost", {})
		for key in option_cost:
			pending[key] = float(pending.get(key, 0.0)) + float(option_cost[key])
	var seen := {}
	for entry in directives:
		if not (entry is Dictionary):
			errors.append("Malformed directive.")
			continue
		var action_id := String(entry.get("action", ""))
		if seen.has(action_id):
			errors.append("Duplicate directive %s." % action_id)
			continue
		seen[action_id] = true
		var block := player.action_block_reason(action_id)
		if block != "":
			errors.append("%s: %s." % [action_id, block])
			continue
		var cost := player.get_action_cost(action_id, float(entry.get("intensity", 1.0)))
		for key in cost:
			pending[key] = float(pending.get(key, 0.0)) + float(cost[key])
	for key in pending:
		if player.get_resource(key) + 0.0001 < float(pending[key]):
			errors.append("Insufficient %s (need %.0f, have %.0f)." % [key, float(pending[key]), player.get_resource(key)])
	return {"ok": errors.is_empty(), "errors": errors}


## Player input for the current turn. On success the pipeline resolves the turn
## and prepares the next one.
func submit_player_turn(directives: Array, dilemma_option: String) -> Dictionary:
	var validation := validate_player_submission(directives, dilemma_option)
	if not validation["ok"]:
		return validation
	_player_submission = {"directives": directives.duplicate(true), "dilemma_option": dilemma_option, "autoplay": false}
	advance()
	return validation


func _resolve_player_turn() -> void:
	var player := get_player()
	var autoplay := bool(_player_submission.get("autoplay", false))
	var option_id := String(_player_submission.get("dilemma_option", ""))
	if autoplay or option_id == "":
		option_id = DilemmaDeck.choose_auto_option(current_dilemma, player_role, player)
	var option := DilemmaDeck.find_option(current_dilemma, option_id)
	var dilemma_result := {"option": option_id, "label": String(option.get("label", ""))}
	var crisis_title := _plain_title(String(current_dilemma.get("title", "")))
	if option_id == DilemmaDeck.DEFER_ID:
		dilemma_result["applied"] = _defer_current(option, crisis_title)
	else:
		var cost: Dictionary = option.get("cost", {})
		if player.can_afford(cost):
			player.spend(cost)
			world.change_cause = _cause_for(player_role, "Crisis: %s (%s)" % [crisis_title, String(option.get("label", ""))])
			dilemma_result["applied"] = _apply_effects(option.get("effects", {}), player_role, 1.0)
			world.change_cause = ""
			_log("DILEMMA", "INFO", "Crisis resolved: %s -> %s." % [current_dilemma.get("title", ""), option.get("label", "")], player_role,
				_dilemma_extra(option_id, String(option.get("label", "")), dilemma_result["applied"], false))
		else:
			dilemma_result["option"] = DilemmaDeck.DEFER_ID
			dilemma_result["applied"] = _defer_current(current_dilemma.get("defer", {}), crisis_title,
				"Could not afford '%s'" % option.get("label", ""))

	var directive_outcomes := []
	var recorded_directives := []
	if autoplay:
		var decision := HeuristicFallback.evaluate(player_role, build_observation(player_role))
		var outcome := resolve_action(player, decision, "PLAYER_AUTOPLAY")
		directive_outcomes.append(outcome)
		recorded_directives.append({"action": String(outcome["action"]), "intensity": float(outcome["intensity"])})
	else:
		for entry in _player_submission.get("directives", []):
			var directive := {
				"action": String(entry.get("action", CONSERVE)),
				"intensity": float(entry.get("intensity", 1.0)),
				"source": "PLAYER",
			}
			directive_outcomes.append(resolve_action(player, directive, "PLAYER"))
			recorded_directives.append({"action": directive["action"], "intensity": directive["intensity"]})
		if directive_outcomes.is_empty():
			directive_outcomes.append(resolve_action(player, {"action": CONSERVE, "source": "PLAYER"}, "PLAYER"))
	if not _fast_forwarding:
		var players: Dictionary = _record_turn_entry(turn)["players"]
		var entry: Dictionary = players.get(player_role, {})
		entry["option"] = String(dilemma_result["option"])
		entry["directives"] = recorded_directives
		players[player_role] = entry
	var turn_result := {"turn": turn, "dilemma": dilemma_result, "directives": directive_outcomes}
	_player_submission = {}
	player_turn_resolved.emit(turn_result)


## Puts off the current crisis, or lets it break when it was already put off
## twice (DilemmaDeck.MAX_DEFERRALS). [param reason] explains a forced deferral.
func _defer_current(defer_option: Dictionary, crisis_title: String, reason: String = "") -> Dictionary:
	var fallout := bool(current_dilemma.get("fallout", false))
	if not fallout:
		deck.defer(current_dilemma, turn, player_role)
	world.change_cause = _cause_for(player_role, ("Crisis broke: %s" if fallout else "Crisis deferred: %s") % crisis_title)
	var applied := _apply_effects(defer_option.get("effects", {}), player_role, 1.0)
	world.change_cause = ""
	var text := "Crisis deferred: %s. It will return escalated." % current_dilemma.get("title", "")
	if fallout:
		text = "Crisis broke: %s. Put off twice, it ran its course." % crisis_title
	elif reason != "":
		text = "%s; crisis deferred." % reason
	var extra := _dilemma_extra(DilemmaDeck.DEFER_ID, String(defer_option.get("label", "")), applied, true)
	extra["fallout"] = fallout
	_log("DILEMMA", "CRITICAL" if fallout else "WARN", text, player_role, extra)
	return applied


## [param text] as a cause in the ledger. With several people playing, a
## player's own moves carry their faction's name so each can tell whose they were.
func _cause_for(role: String, text: String) -> String:
	if human_roles.size() <= 1 or not factions.has(role):
		return text
	return "%s — %s" % [text, (factions[role] as ActorBase).display_name]


## A crisis title without the "[ESCALATED xN]" prefix.
static func _plain_title(title: String) -> String:
	if title.begins_with("[ESCALATED"):
		return title.substr(title.find("]") + 1).strip_edges()
	return title


## Structured data for crisis log entries (the newswire and history screens read it).
func _dilemma_extra(option_id: String, option_label: String, applied: Dictionary, deferred: bool) -> Dictionary:
	var escalation := int(current_dilemma.get("escalation", 0))
	return {
		"card": String(current_dilemma.get("id", "")),
		"card_category": String(current_dilemma.get("category", "")),
		"title": _plain_title(String(current_dilemma.get("title", ""))),
		"card_severity": int(current_dilemma.get("severity", 1)),
		"escalation": escalation,
		"option": option_id,
		"option_label": option_label,
		"deferred": deferred,
		"deltas": (applied.get("metrics", {}) as Dictionary).duplicate(),
	}


# --- Phase 4: telemetry reconciliation & endgame check -------------------------------

func _run_telemetry() -> void:
	for faction_id in SimConstants.FACTION_ORDER:
		var actor: ActorBase = factions[faction_id]
		if actor.status == ActorBase.STATUS_DORMANT and actor.tick_dormancy():
			_log("COLLAPSE", "WARN", "%s re-emerges after dormancy." % actor.display_name, faction_id, {"code": "REEMERGED"})

	var player_loss := {}
	for faction_id in SimConstants.FACTION_ORDER:
		var actor: ActorBase = factions[faction_id]
		if not actor.is_active():
			continue
		var loss := actor.evaluate_loss(world)
		if loss.is_empty():
			continue
		if is_human(faction_id) and not _fast_forwarding:
			if active_humans().size() <= 1:
				player_loss = loss
				_log("COLLAPSE", "CRITICAL", "PLAYER LOSS: %s" % loss["reason"], faction_id, {"code": String(loss.get("code", "")), "player": true})
				continue
			# Pass-and-play: this player is out; their faction carries on unattended.
			eliminated[faction_id] = {"turn": turn, "loss": loss}
			actor.is_player = false
			_log("COLLAPSE", "CRITICAL", "PLAYER OUT: %s" % loss["reason"], faction_id,
				{"code": String(loss.get("code", "")), "player": true, "eliminated": true})
		var collapse := actor.on_collapse(loss, world)
		world.change_cause = "Collapse: %s" % actor.display_name
		_apply_effects(collapse.get("effects", {}), "", 1.0)
		world.change_cause = ""
		_log("COLLAPSE", "CRITICAL", "%s (%s)" % [collapse.get("headline", loss["reason"]), loss["code"]], faction_id,
			{"code": String(loss["code"]), "headline": String(collapse.get("headline", ""))})
	_restore_primary_role()

	if not _fast_forwarding and turn >= start_turn and player_loss.is_empty():
		_evaluate_goals()

	var catastrophe := _check_catastrophe()
	if not catastrophe.is_empty() and _fast_forwarding:
		catastrophe = _avert_prologue_catastrophe(catastrophe)
	world.record_history(turn, get_year(), _history_extra())
	_log_threshold_breaches()
	var snapshot := get_snapshot()
	telemetry_updated.emit(snapshot)

	if not player_loss.is_empty():
		_finish("PLAYER_LOSS", player_loss, catastrophe)
	elif not catastrophe.is_empty():
		_finish("CATASTROPHE", {}, catastrophe)
	elif turn >= total_turns:
		_finish("TURN_LIMIT", {}, {})
	else:
		turn_completed.emit(turn, snapshot)
		_set_phase(Phase.IDLE)


## Settles the era goals at the end of the turn and pays the rewards.
func _evaluate_goals() -> void:
	for event in goals.evaluate(self):
		var goal: Dictionary = event["goal"]
		var role := String(event["role"])
		var met := String(event["status"]) == EraGoals.MET
		var applied := {}
		if met:
			world.change_cause = _cause_for(role, "Era goal: %s" % String(goal["text"]))
			applied = _apply_effects(goal.get("reward", {}), role, Difficulty.value(difficulty, "goal_rewards"))
			world.change_cause = ""
		_log("GOAL", "INFO" if met else "WARN", "%s goal %s: %s." % [SimConstants.role_title(role), "met" if met else "missed", goal["text"]],
			role, {"goal": String(goal["id"]), "goal_text": String(goal["text"]), "status": String(event["status"]),
				"reward_text": String(goal.get("reward_text", "")) if met else "", "era": int(goal["era"]),
				"deltas": (applied.get("metrics", {}) as Dictionary).duplicate()})


## The autopilot years before a late start cannot end the world: the brink is
## logged and pulled back, so the players inherit a tense world, not a dead one.
func _avert_prologue_catastrophe(catastrophe: Dictionary) -> Dictionary:
	world.change_cause = "A near miss"
	if String(catastrophe.get("code", "")) == "AUTONOMOUS_WORLD_WAR":
		world.set_value(WorldState.GEOPOLITICAL_TENSION, 88.0)
	else:
		world.set_value(WorldState.ALIGNMENT_DRIFT, 88.0)
		_convergence_streak = 0
	world.change_cause = ""
	_log("THRESHOLD", "CRITICAL", "NEAR MISS: %s It was pulled back from the brink." % catastrophe["reason"], "",
		{"near_miss": String(catastrophe.get("code", ""))})
	return {}


## Global early-termination thresholds that end the campaign for every role.
## Tension 100 is immediate; saturated drift under near-total autonomy must
## persist for two consecutive turns (the first turn raises a red alert).
func _check_catastrophe() -> Dictionary:
	if world.geopolitical_tension >= 100.0:
		return {"code": "AUTONOMOUS_WORLD_WAR", "reason": "Geopolitical tension hit 100: sovereign autonomous war swarms are launched."}
	if world.alignment_drift >= 100.0 and world.algorithmic_autonomy >= 90.0:
		_convergence_streak += 1
		if _convergence_streak >= 2:
			return {"code": "UNCONTAINED_CONVERGENCE", "reason": "Alignment drift saturated under near-total autonomy for two turns: instrumental convergence is uncontained."}
		_log("THRESHOLD", "CRITICAL", "CONTAINMENT FAILURE IMMINENT: alignment drift saturated under near-total autonomy. One turn to intervene.",
			"", {"metric": WorldState.ALIGNMENT_DRIFT, "band": 2, "value": world.alignment_drift, "imminent": true})
	else:
		_convergence_streak = 0
	return {}


func _finish(reason: String, player_loss: Dictionary, catastrophe: Dictionary) -> void:
	var citizen: ActorBase = factions[SimConstants.CITIZEN]
	var values := VictoryMatrix.build_values(world, citizen.get_resource("community_resilience"))
	var candidates: Array = []
	if not catastrophe.is_empty():
		candidates = VictoryMatrix.CATASTROPHE_OUTCOMES.get(catastrophe["code"], [])
	var outcome := VictoryMatrix.evaluate(values, candidates)
	_restore_primary_role()
	if not player_loss.is_empty() and active_humans().size() == 1:
		player_role = active_humans()[0]
	var verdicts := {}
	for role in human_roles:
		var loss: Dictionary = player_loss if role == player_role and not player_loss.is_empty() \
			else (eliminated.get(role, {}) as Dictionary).get("loss", {})
		var actor: ActorBase = factions[role]
		verdicts[role] = VictoryMatrix.role_verdict(role, outcome["id"], actor.get_objective_score(world, tech), loss,
			goals.score_bonus(role), Difficulty.value(difficulty, "verdict_shift"))
	var verdict: Dictionary = verdicts.get(player_role, {})
	result = {
		"reason": reason,
		"turn": turn,
		"year": get_year(),
		"seed": campaign_seed,
		"player_role": player_role,
		"humans": human_roles.duplicate(),
		"outcome": outcome,
		"verdict": verdict,
		"verdicts": verdicts,
		"player_loss": player_loss,
		"eliminated": eliminated.duplicate(true),
		"catastrophe": catastrophe,
		"final_values": values,
		"final_indices": world.indices_dict(),
		"tech": tech.to_dict(),
		"milestones": _milestones.duplicate(),
		"history": world.history,
		"difficulty": difficulty,
		"scenario": scenario_id,
		"start_turn": start_turn,
		"goals": _goal_rows(),
	}
	if not catastrophe.is_empty():
		_log("ENDGAME", "CRITICAL", "CATASTROPHIC THRESHOLD: %s" % catastrophe["reason"], "", {"catastrophe": catastrophe["code"]})
	_log("ENDGAME", "CRITICAL" if verdict["verdict"] == "DEFEAT" else "WARN",
		"END-STATE %d: %s (%s). %s verdict, score %.0f." % [
			outcome["number"], outcome["name"], outcome["subtitle"], verdict["verdict"], verdict["score"]], "",
		{"outcome": outcome["id"], "outcome_name": outcome["name"], "outcome_number": outcome["number"],
			"verdict": verdict["verdict"], "score": verdict["score"]})
	_set_phase(Phase.ENDED)
	campaign_ended.emit(result)


## Every human's goals: role -> rows (EraGoals.status_for).
func _goal_rows() -> Dictionary:
	var rows := {}
	for role in human_roles:
		rows[role] = goals.status_for(role)
	return rows


func _log_threshold_breaches() -> void:
	for key in WorldState.METRIC_KEYS:
		var band := WorldState.band_for(key, world.get_value(key))
		var previous := int(_metric_bands.get(key, 0))
		if band > previous:
			var label: String = WorldState.METRIC_INFO[key]["label"]
			var severity := "CRITICAL" if band == 2 else "WARN"
			_log("THRESHOLD", severity, "%s breached %s band (%.1f): %s." % [
				label, "CRITICAL" if band == 2 else "WARNING", world.get_value(key),
				WorldState.regime_for(key, world.get_value(key))], "", {"metric": key, "band": band, "value": world.get_value(key)})
		elif band < previous and band == 0:
			_log("THRESHOLD", "INFO", "%s stabilized (%.1f)." % [WorldState.METRIC_INFO[key]["label"], world.get_value(key)], "",
				{"metric": key, "band": 0, "value": world.get_value(key)})
		_metric_bands[key] = band


func _history_extra() -> Dictionary:
	return {
		"log_flops": tech.log_flops,
		"capability_index": tech.get_capability_index(),
		"era": tech.era,
		"grid_capacity_gw": compute.grid_capacity_gw,
		"power_demand_gw": compute.power_demand_gw,
	}


# --- Snapshots & logging ----------------------------------------------------------

func get_snapshot() -> Dictionary:
	var faction_data := {}
	for faction_id in SimConstants.FACTION_ORDER:
		faction_data[faction_id] = (factions[faction_id] as ActorBase).to_dict()
	return {
		"turn": turn,
		"total_turns": total_turns,
		"year": get_year(),
		"era": tech.era,
		"phase": phase_name(),
		"player_role": player_role,
		"seed": campaign_seed,
		"metrics": world.metrics_dict(),
		"indices": world.indices_dict(),
		"bands": world.bands_dict(),
		"tech": tech.to_dict(),
		"compute": compute.to_dict(),
		"factions": faction_data,
		"turn_actions": turn_actions.duplicate(true),
		"history_size": world.history.size(),
		"human_roles": human_roles.duplicate(),
		"eliminated": eliminated.duplicate(true),
		"difficulty": difficulty,
		"scenario": scenario_id,
		"start_turn": start_turn,
		"pledges": pledges.duplicate(true),
		"goals": _goal_rows(),
	}


func _set_phase(new_phase: int) -> void:
	phase = new_phase
	phase_changed.emit(phase, turn)


func _log(category: String, severity: String, text: String, faction_id: String = "", extra: Dictionary = {}) -> void:
	var entry := {
		"turn": turn,
		"year": get_year(),
		"category": category,
		"severity": severity,
		"faction": faction_id,
		"text": text,
	}
	entry.merge(extra)
	if _fast_forwarding:
		entry["prologue"] = true
	event_log.append(entry)
	event_logged.emit(entry)
