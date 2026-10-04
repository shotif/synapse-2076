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

enum Phase { IDLE, WORLD_TICK, ACTOR_RESOLUTION, PLAYER_ACTION, TELEMETRY, ENDED }

const PHASE_NAMES := ["IDLE", "WORLD_TICK", "ACTOR_RESOLUTION", "PLAYER_ACTION", "TELEMETRY", "ENDED"]
const CONSERVE := "CONSERVE_RESOURCES"
const MAX_PIPELINE_STEPS := 16

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
var player_role := ""
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


# --- Campaign lifecycle ---------------------------------------------------------

func start_campaign(role: String, seed_value: int = 2076, options: Dictionary = {}) -> void:
	if not SimConstants.is_valid_faction(role):
		push_error("SimulationEngine: invalid player role '%s'" % role)
		return
	player_role = role
	campaign_seed = seed_value
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	total_turns = int(options.get("total_turns", SimConstants.TOTAL_TURNS))
	max_player_directives = int(options.get("max_player_directives", max_player_directives))
	autoplay_player = bool(options.get("autoplay", autoplay_player))

	world = WorldState.new()
	tech = TechTreeManager.new()
	compute = ComputeScaling.new()
	deck = DilemmaDeck.new()
	factions = {}
	for faction_id in SimConstants.FACTION_ORDER:
		var actor := FactionRegistry.create(faction_id)
		actor.is_player = faction_id == role
		factions[faction_id] = actor

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
		int(SimConstants.START_YEAR), int(SimConstants.year_for_turn(total_turns))])
	campaign_started.emit(role, seed_value)


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


func is_ended() -> bool:
	return phase == Phase.ENDED


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

	world.drift_accrual_multiplier = tech.get_drift_accrual_multiplier()
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
		_apply_effects(shift["effects"], "", 1.0)
		_log("PARADIGM", "WARN", "PARADIGM SHIFT: %s. %s" % [shift["name"], shift["summary"]], "",
			{"shift": shift["id"], "name": shift["name"], "summary": shift["summary"]})
	for emergence in tech_report["emergences"]:
		_apply_effects(emergence["effects"], "", 1.0)
		var spike := world.apply_delta(WorldState.ALIGNMENT_DRIFT, float(emergence["drift_spike"]))
		_log("EMERGENCE", "CRITICAL", "EMERGENT CAPABILITY: %s (%s). Alignment drift %+.1f." % [
			emergence["headline"], emergence["name"], spike], "", {"capability": emergence["id"], "name": emergence["name"],
			"headline": emergence["headline"], "model": emergence["model"], "deltas": {WorldState.ALIGNMENT_DRIFT: spike}})
	if tech_report["agi_crossed"]:
		_on_agi_crossed()

	for faction_id in SimConstants.FACTION_ORDER:
		var actor: ActorBase = factions[faction_id]
		if not actor.is_active():
			continue
		actor.apply_passive_influence(world, tech, compute)
		actor.regenerate(world, tech, turn)
		actor.tick_cooldowns()
		actor.decay_grievances()

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
		if faction_id == player_role:
			continue
		var actor: ActorBase = factions[faction_id]
		if not actor.is_active():
			continue
		requested.append(faction_id)
		_awaiting[faction_id] = true
	actor_decisions_requested.emit(requested)
	_requesting = true
	for faction_id in requested:
		var observation := build_observation(faction_id)
		if _provider_online():
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
			resolve_action(factions[faction_id], _collected[faction_id], "AUTONOMOUS")
	_awaiting = {}
	_collected = {}


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
	if actor.get_action(action_id).get("cost", {}).is_empty():
		intensity = 1.0
	else:
		intensity = minf(intensity, actor.max_affordable_intensity(action_id))
	var cost := actor.get_action_cost(action_id, intensity)
	actor.spend(cost)
	actor.start_cooldown(action_id)
	var definition := actor.get_action(action_id)
	var applied := _apply_effects(definition.get("effects", {}), actor.faction_id, ActorBase.effect_scale(intensity))
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


func _apply_effects(effects: Dictionary, actor_id: String, scale: float) -> Dictionary:
	return EffectResolver.apply(effects, {
		"world": world, "tech": tech, "compute": compute, "factions": factions,
		"deck": deck, "actor_id": actor_id, "player_id": player_role, "scale": scale,
	})


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
	current_dilemma = deck.draw({
		"turn": turn, "year": get_year(), "role": player_role,
		"world": world, "tech": tech, "player": get_player(),
	}, rng)
	_player_submission = {}
	dilemma_presented.emit(current_dilemma)
	player_input_required.emit(get_player_context())


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
			"cooldown": int(player.cooldowns.get(action_id, 0)),
			"blocked_reason": player.action_block_reason(action_id),
			"max_intensity": player.max_affordable_intensity(action_id),
		})
	return {
		"turn": turn,
		"year": get_year(),
		"role": player_role,
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
	if option_id == DilemmaDeck.DEFER_ID:
		deck.defer(current_dilemma, turn)
		dilemma_result["applied"] = _apply_effects(option.get("effects", {}), player_role, 1.0)
		_log("DILEMMA", "WARN", "Crisis deferred: %s. It will return escalated." % current_dilemma.get("title", ""), player_role,
			_dilemma_extra(option_id, String(option.get("label", "")), dilemma_result["applied"], true))
	else:
		var cost: Dictionary = option.get("cost", {})
		if player.can_afford(cost):
			player.spend(cost)
			dilemma_result["applied"] = _apply_effects(option.get("effects", {}), player_role, 1.0)
			_log("DILEMMA", "INFO", "Crisis resolved: %s -> %s." % [current_dilemma.get("title", ""), option.get("label", "")], player_role,
				_dilemma_extra(option_id, String(option.get("label", "")), dilemma_result["applied"], false))
		else:
			deck.defer(current_dilemma, turn)
			dilemma_result["option"] = DilemmaDeck.DEFER_ID
			dilemma_result["applied"] = _apply_effects(current_dilemma.get("defer", {}).get("effects", {}), player_role, 1.0)
			_log("DILEMMA", "WARN", "Could not afford '%s'; crisis deferred." % option.get("label", ""), player_role,
				_dilemma_extra(DilemmaDeck.DEFER_ID, String(current_dilemma.get("defer", {}).get("label", "")), dilemma_result["applied"], true))

	var directive_outcomes := []
	if autoplay:
		var decision := HeuristicFallback.evaluate(player_role, build_observation(player_role))
		directive_outcomes.append(resolve_action(player, decision, "PLAYER_AUTOPLAY"))
	else:
		for entry in _player_submission.get("directives", []):
			var directive := {
				"action": String(entry.get("action", CONSERVE)),
				"intensity": float(entry.get("intensity", 1.0)),
				"source": "PLAYER",
			}
			directive_outcomes.append(resolve_action(player, directive, "PLAYER"))
		if directive_outcomes.is_empty():
			directive_outcomes.append(resolve_action(player, {"action": CONSERVE, "source": "PLAYER"}, "PLAYER"))
	var turn_result := {"turn": turn, "dilemma": dilemma_result, "directives": directive_outcomes}
	_player_submission = {}
	player_turn_resolved.emit(turn_result)


## Structured data for crisis log entries (the newswire and history screens read it).
func _dilemma_extra(option_id: String, option_label: String, applied: Dictionary, deferred: bool) -> Dictionary:
	var title := String(current_dilemma.get("title", ""))
	var escalation := int(current_dilemma.get("escalation", 0))
	if escalation > 0 and title.begins_with("[ESCALATED"):
		title = title.substr(title.find("]") + 1).strip_edges()
	return {
		"card": String(current_dilemma.get("id", "")),
		"card_category": String(current_dilemma.get("category", "")),
		"title": title,
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
		if faction_id == player_role:
			player_loss = loss
			_log("COLLAPSE", "CRITICAL", "PLAYER LOSS: %s" % loss["reason"], faction_id, {"code": String(loss.get("code", "")), "player": true})
		else:
			var collapse := actor.on_collapse(loss, world)
			_apply_effects(collapse.get("effects", {}), "", 1.0)
			_log("COLLAPSE", "CRITICAL", "%s (%s)" % [collapse.get("headline", loss["reason"]), loss["code"]], faction_id,
				{"code": String(loss["code"]), "headline": String(collapse.get("headline", ""))})

	var catastrophe := _check_catastrophe()
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
	var player := get_player()
	var verdict := VictoryMatrix.role_verdict(player_role, outcome["id"],
		player.get_objective_score(world, tech), player_loss)
	result = {
		"reason": reason,
		"turn": turn,
		"year": get_year(),
		"seed": campaign_seed,
		"player_role": player_role,
		"outcome": outcome,
		"verdict": verdict,
		"player_loss": player_loss,
		"catastrophe": catastrophe,
		"final_values": values,
		"final_indices": world.indices_dict(),
		"tech": tech.to_dict(),
		"milestones": _milestones.duplicate(),
		"history": world.history,
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
	event_log.append(entry)
	event_logged.emit(entry)
