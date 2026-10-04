class_name ActorBase
extends RefCounted
## Base class for the four asymmetric factions (PRD section 5).
##
## A faction owns its operational currencies, a catalog of directives (actions),
## cooldowns, grievances toward rivals (which drive retaliatory moves) and its
## instant-loss bookkeeping. Subclasses declare data (ACTIONS, resources) and
## override the per-turn hooks. No Node dependencies.

signal resources_changed(faction_id: String, resources: Dictionary)

const CONSERVE_RESOURCES := "CONSERVE_RESOURCES"
const MIN_INTENSITY := 1.0
const MAX_INTENSITY := 2.0
## Effects scale with intensity^EFFECT_EXPONENT: doubling spend yields ~1.74x impact.
const EFFECT_EXPONENT := 0.8
const GRIEVANCE_DECAY := 0.1
const STATUS_ACTIVE := "ACTIVE"
const STATUS_DORMANT := "DORMANT"

var faction_id := ""
var display_name := ""
var is_player := false
var resources := {}
var cooldowns := {}
var grievances := {}
var status := STATUS_ACTIVE
var dormant_turns := 0
var collapse_count := 0
var last_action := ""
var last_statement := ""
var action_history: Array[Dictionary] = []
## Consecutive-turn counters for streak-based loss conditions (e.g. bankruptcy).
var loss_streaks := {}


func _init() -> void:
	_setup()
	reset()


# --- Subclass hooks -----------------------------------------------------------

## Set [member faction_id] and [member display_name].
func _setup() -> void:
	pass


func get_action_catalog() -> Dictionary:
	return {}


func get_initial_resources() -> Dictionary:
	return {}


## Per-currency metadata: {"label", "unit", "max", "scale"}. "scale" is a typical
## magnitude used to normalize grievances and UI bars across unlike units.
func get_resource_info() -> Dictionary:
	return {}


## Per-turn income and decay.
func regenerate(_world: WorldState, _tech: TechTreeManager, _turn: int) -> void:
	pass


## Passive pressure the faction exerts on the world each tick while active.
func apply_passive_influence(_world: WorldState, _tech: TechTreeManager, _compute: ComputeScaling) -> void:
	pass


## Evaluates instant-loss conditions. Called exactly once per turn (it updates
## streak counters). Returns {} or {"code": String, "reason": String}.
func evaluate_loss(_world: WorldState) -> Dictionary:
	return {}


## Restructures an autonomous (non-player) faction after it hits a loss
## condition. Returns an effects dictionary for the world plus a headline.
func on_collapse(_loss: Dictionary, _world: WorldState) -> Dictionary:
	return {}


## Role objective progress in [0, 40] used by the endgame verdict.
func get_objective_score(_world: WorldState, _tech: TechTreeManager) -> float:
	return 0.0


# --- Shared logic -------------------------------------------------------------

func reset() -> void:
	resources = get_initial_resources().duplicate(true)
	cooldowns = {}
	grievances = {}
	status = STATUS_ACTIVE
	dormant_turns = 0
	collapse_count = 0
	last_action = ""
	last_statement = ""
	action_history.clear()
	loss_streaks = {}


func is_active() -> bool:
	return status == STATUS_ACTIVE


func get_resource(key: String) -> float:
	return float(resources.get(key, 0.0))


func resource_max(key: String) -> float:
	var info: Dictionary = get_resource_info().get(key, {})
	return float(info.get("max", 100.0))


func resource_scale(key: String) -> float:
	var info: Dictionary = get_resource_info().get(key, {})
	return maxf(0.001, float(info.get("scale", 100.0)))


func set_resource(key: String, value: float) -> float:
	if not resources.has(key):
		push_warning("%s: unknown resource '%s'" % [faction_id, key])
		return 0.0
	var clean := value if is_finite(value) else 0.0
	resources[key] = clampf(clean, 0.0, resource_max(key))
	return float(resources[key])


## Adds [param delta] (clamped to [0, max]) and returns the applied change.
func add_resource(key: String, delta: float) -> float:
	if not resources.has(key) or not is_finite(delta):
		return 0.0
	var old_value := get_resource(key)
	return set_resource(key, old_value + delta) - old_value


func has_action(action_id: String) -> bool:
	return get_action_catalog().has(action_id)


func get_action(action_id: String) -> Dictionary:
	return get_action_catalog().get(action_id, {})


func get_action_cost(action_id: String, intensity: float = 1.0) -> Dictionary:
	var base: Dictionary = get_action(action_id).get("cost", {})
	var scale := clampf(intensity, MIN_INTENSITY, MAX_INTENSITY)
	var out := {}
	for key in base:
		out[key] = float(base[key]) * scale
	return out


func can_afford(cost: Dictionary) -> bool:
	for key in cost:
		if get_resource(key) + 0.0001 < float(cost[key]):
			return false
	return true


## Highest intensity in [1, 2] this faction can pay for, or 0.0 when even the
## base cost is unaffordable. Zero-cost actions always return 1.0.
func max_affordable_intensity(action_id: String) -> float:
	var base: Dictionary = get_action(action_id).get("cost", {})
	if base.is_empty():
		return MIN_INTENSITY
	var best := MAX_INTENSITY
	for key in base:
		var need := float(base[key])
		if need <= 0.0:
			continue
		best = minf(best, get_resource(key) / need)
	if best + 0.0001 < MIN_INTENSITY:
		return 0.0
	return clampf(best, MIN_INTENSITY, MAX_INTENSITY)


func is_action_ready(action_id: String) -> bool:
	return int(cooldowns.get(action_id, 0)) <= 0


## Why an action cannot be taken right now ("" when it can).
func action_block_reason(action_id: String) -> String:
	# English, like every record; UiFormat.block_reason() translates for the screen.
	if not has_action(action_id):
		return I18n.mark("Unknown directive")
	if not is_active():
		return I18n.mark("Faction dormant")
	if not is_action_ready(action_id):
		return I18n.mark("Cooldown %d turn(s)") % int(cooldowns[action_id])
	if max_affordable_intensity(action_id) <= 0.0:
		return I18n.mark("Insufficient resources")
	return ""


## Directives that are off cooldown and affordable at base intensity.
func get_available_actions() -> Array[String]:
	var out: Array[String] = []
	for action_id in get_action_catalog():
		if action_block_reason(action_id) == "":
			out.append(action_id)
	return out


func spend(cost: Dictionary) -> void:
	for key in cost:
		add_resource(key, -float(cost[key]))
	resources_changed.emit(faction_id, resources)


func start_cooldown(action_id: String) -> void:
	var turns := int(get_action(action_id).get("cooldown", 0))
	if turns > 0:
		# +1 because cooldowns tick down during the next world tick.
		cooldowns[action_id] = turns + 1


func tick_cooldowns() -> void:
	for action_id in cooldowns.keys():
		cooldowns[action_id] = maxi(0, int(cooldowns[action_id]) - 1)
		if int(cooldowns[action_id]) == 0:
			cooldowns.erase(action_id)


func add_grievance(other_faction: String, amount: float) -> void:
	if other_faction == "" or other_faction == faction_id or not is_finite(amount) or amount <= 0.0:
		return
	grievances[other_faction] = clampf(float(grievances.get(other_faction, 0.0)) + amount, 0.0, 100.0)


func decay_grievances() -> void:
	for other in grievances.keys():
		grievances[other] = float(grievances[other]) * (1.0 - GRIEVANCE_DECAY)
		if float(grievances[other]) < 0.5:
			grievances.erase(other)


## {"faction": String, "value": float} for the rival this faction resents most.
func top_grievance() -> Dictionary:
	var best := {"faction": "", "value": 0.0}
	for other in grievances:
		if float(grievances[other]) > float(best["value"]):
			best = {"faction": other, "value": float(grievances[other])}
	return best


func record_action(entry: Dictionary) -> void:
	last_action = String(entry.get("action", ""))
	last_statement = String(entry.get("public_statement", ""))
	action_history.append(entry)
	if action_history.size() > 24:
		action_history.pop_front()


func set_dormant(turns: int) -> void:
	status = STATUS_DORMANT
	dormant_turns = maxi(1, turns)


## Counts down dormancy. Returns true on the turn the faction re-emerges.
func tick_dormancy() -> bool:
	if status != STATUS_DORMANT:
		return false
	dormant_turns -= 1
	if dormant_turns <= 0:
		status = STATUS_ACTIVE
		dormant_turns = 0
		_on_reemerge()
		return true
	return false


func _on_reemerge() -> void:
	pass


static func effect_scale(intensity: float) -> float:
	return pow(clampf(intensity, MIN_INTENSITY, MAX_INTENSITY), EFFECT_EXPONENT)


## Flat observation for heuristics and LLM prompts: world metrics, indices, tech
## readouts and this faction's own currencies at the top level (the PRD
## heuristic reads e.g. state.labor_displacement and state.political_capital).
func build_observation(world: WorldState, tech: TechTreeManager, turn: int, year: float, extra: Dictionary = {}) -> Dictionary:
	var obs := {"faction": faction_id, "turn": turn, "year": year}
	obs.merge(world.metrics_dict())
	obs.merge(world.indices_dict())
	if tech != null:
		obs["era"] = tech.era
		obs["log10_training_flops"] = tech.log_flops
		obs["capability_index"] = tech.get_capability_index()
		obs["agi_crossed"] = tech.is_agi_crossed()
		obs["paradigm_shifts"] = tech.unlocked_shifts.duplicate()
		obs["alignment_tax_multiplier"] = tech.alignment_tax_multiplier
	for key in resources:
		obs[key] = float(resources[key])
	obs["resources"] = resources.duplicate()
	obs["cooldowns"] = cooldowns.duplicate()
	obs["grievances"] = grievances.duplicate()
	obs["available_actions"] = get_available_actions()
	obs.merge(extra, true)
	return obs


func to_dict() -> Dictionary:
	return {
		"faction_id": faction_id,
		"display_name": display_name,
		"is_player": is_player,
		"status": status,
		"dormant_turns": dormant_turns,
		"collapse_count": collapse_count,
		"resources": resources.duplicate(),
		"cooldowns": cooldowns.duplicate(),
		"grievances": grievances.duplicate(),
		"last_action": last_action,
		"last_statement": last_statement,
	}
