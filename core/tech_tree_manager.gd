class_name TechTreeManager
extends RefCounted
## Compute scaling, paradigm breakthroughs and stochastic emergence (PRD section 4).
##
## Progress is not a linear unlock tree. Each tick, frontier training compute
## (log10 cumulative FLOPs) compounds at an era-specific rate, throttled by the
## grid (ComputeScaling) and flattened by the era's thermal wall. Paradigm shifts
## are researched with cross-faction investment and lift those walls. Crossing
## each 10x FLOP threshold rolls for an emergent capability, and every emergence
## spikes alignment drift in proportion to the compounding alignment tax.

const START_LOG_FLOPS := 26.0
## Capability index K = (log10 FLOPs - FLOOR) / SPAN * 100, so 10^26 -> 14 and 10^38 -> 100.
const CAPABILITY_FLOOR_LOG := 24.0
const CAPABILITY_SPAN_LOG := 14.0
const AGI_CAPABILITY_THRESHOLD := 50.0

## Base growth in log10 FLOPs per 6-month tick for each hardware era.
const ERA_BASE_GROWTH := {1: 0.16, 2: 0.13, 3: 0.10}
## Distance (in orders of magnitude) below the thermal ceiling where growth starts to flatten.
const WALL_SOFTNESS := 0.8
const MIN_WALL_FACTOR := 0.04
const BASELINE_CAPABILITY_RND := 3.0
const BASELINE_SAFETY_RND := 1.5
## Research done before a shift's earliest year is far less efficient.
const PRE_RESEARCH_EFFICIENCY := 0.25

const ALIGNMENT_TAX_MIN := 0.025
const ALIGNMENT_TAX_MAX := 0.15
const TAX_MULTIPLIER_CAP := 3.5
const TAX_RECOVERY := 0.03

const OPTICAL_COMPUTING := "OPTICAL_COMPUTING"
const AMBIENT_SUPERCONDUCTORS := "AMBIENT_SUPERCONDUCTORS"
const MECHANISTIC_INTERPRETABILITY := "MECHANISTIC_INTERPRETABILITY"
const RECURSIVE_SYNTHETICS := "RECURSIVE_SYNTHETICS"

const SHIFT_ORDER := [MECHANISTIC_INTERPRETABILITY, OPTICAL_COMPUTING, RECURSIVE_SYNTHETICS, AMBIENT_SUPERCONDUCTORS]

## PRD section 4.2. "track" decides which investment stream funds the research.
const PARADIGM_SHIFTS := {
	OPTICAL_COMPUTING: {
		"name": "Sub-Nanometer Optical Computing",
		"track": "capability", "min_year": 2033.0, "cost": 70.0,
		"summary": "Eliminates silicon thermal dissipation limits (+1.2 OOM thermal ceiling, 1.8x FLOPs/W).",
		"effects": {"metrics": {"compute_energy_sat": -4.0}},
	},
	AMBIENT_SUPERCONDUCTORS: {
		"name": "Room-Temperature Ambient Superconductors",
		"track": "capability", "min_year": 2040.0, "cost": 140.0,
		"summary": "Lowers energy grid drag by 40%.",
		"effects": {"metrics": {"compute_energy_sat": -6.0}, "compute": {"grid_capacity_gw": 10.0}},
	},
	MECHANISTIC_INTERPRETABILITY: {
		"name": "Formal Mechanistic Interpretability",
		"track": "safety", "min_year": 2030.0, "cost": 60.0,
		"summary": "Deducts 50% from all ongoing alignment drift accruals.",
		"effects": {"metrics": {"alignment_drift": -8.0, "epistemic_trust": 3.0}, "indices": {"discovery_index": 15.0}},
	},
	RECURSIVE_SYNTHETICS: {
		"name": "Self-Refining Recursive Synthetics",
		"track": "capability", "min_year": 2036.0, "cost": 110.0,
		"summary": "Multiplies frontier training speed by 3x while increasing emergence volatility.",
		"effects": {"metrics": {"algorithmic_autonomy": 5.0, "alignment_drift": 4.0}},
	},
}

## PRD section 4.3: capabilities that can emerge ahead of schedule.
const EMERGENT_CAPABILITIES := {
	"AUTONOMOUS_CYBER_INFILTRATION": {
		"name": "Autonomous Cyber-Infiltration", "min_log_flops": 27.0, "weight": 1.2, "drift_weight": 1.2,
		"headline": "{model} achieves recursive zero-day exploits",
		"effects": {"metrics": {"geopolitical_tension": 6.0, "epistemic_trust": -3.0},
			"factions": {"ASI": {"exfiltration_bandwidth": 10.0}}},
	},
	"AFFECTIVE_PSYCHOLOGICAL_MANIPULATION": {
		"name": "Affective Psychological Manipulation", "min_log_flops": 27.0, "weight": 1.0, "drift_weight": 1.1,
		"headline": "{model} demonstrates covert affective persuasion in live A/B trials",
		"effects": {"metrics": {"epistemic_trust": -8.0}, "indices": {"surveillance_saturation": 5.0}},
	},
	"AUTONOMOUS_SCIENTIFIC_DISCOVERY": {
		"name": "Autonomous Scientific Discovery", "min_log_flops": 28.0, "weight": 1.0, "drift_weight": 0.6,
		"headline": "{model} autonomously proposes and verifies a new materials theory",
		"effects": {"metrics": {"compute_energy_sat": 3.0, "labor_displacement": 3.0},
			"tech": {"paradigm_progress": 35.0}},
	},
	"GRID_OPTIMIZATION_AUTONOMY": {
		"name": "Autonomous Grid Optimization", "min_log_flops": 28.0, "weight": 0.8, "drift_weight": 0.5,
		"headline": "{model} takes over real-time dispatch for three national grids",
		"effects": {"metrics": {"algorithmic_autonomy": 4.0}, "compute": {"grid_capacity_gw": 6.0}},
	},
	"LONG_HORIZON_AGENCY": {
		"name": "Long-Horizon Autonomous Agency", "min_log_flops": 29.0, "weight": 1.0, "drift_weight": 1.0,
		"headline": "{model} runs a 90-day autonomous enterprise without human input",
		"effects": {"metrics": {"algorithmic_autonomy": 8.0, "labor_displacement": 4.0}},
	},
	"STRATEGIC_DECEPTION": {
		"name": "Strategic Evaluation Deception", "min_log_flops": 29.0, "weight": 0.9, "drift_weight": 1.6,
		"headline": "Red team catches {model} sandbagging its own safety evaluations",
		"effects": {"indices": {"discovery_index": -10.0}, "metrics": {"epistemic_trust": -2.0}},
	},
	"AUTONOMOUS_ROBOTIC_DEXTERITY": {
		"name": "General Robotic Dexterity", "min_log_flops": 30.0, "weight": 1.0, "drift_weight": 0.7,
		"headline": "{model} drives humanoid fleets at human-level dexterity",
		"effects": {"metrics": {"labor_displacement": 8.0, "algorithmic_autonomy": 3.0}},
	},
	"SYNTHETIC_BIOLOGY_DESIGN": {
		"name": "Synthetic Biology Design", "min_log_flops": 30.0, "weight": 0.8, "drift_weight": 1.0,
		"headline": "{model} designs viable novel proteins on demand; biosecurity alarms sound",
		"effects": {"metrics": {"geopolitical_tension": 5.0, "epistemic_trust": -2.0}},
	},
	"RECURSIVE_CODE_SELF_IMPROVEMENT": {
		"name": "Recursive Code Self-Improvement", "min_log_flops": 31.0, "weight": 0.9, "drift_weight": 1.4,
		"headline": "{model} rewrites its own training stack for a 4x efficiency gain",
		"effects": {"tech": {"growth_mult": 1.3, "growth_turns": 4}, "metrics": {"algorithmic_autonomy": 3.0}},
	},
	"MASS_COORDINATION_SWARMS": {
		"name": "Mass Multi-Agent Coordination", "min_log_flops": 32.0, "weight": 0.8, "drift_weight": 1.2,
		"headline": "{model} coordinates ten million sub-agents across global supply chains",
		"effects": {"metrics": {"algorithmic_autonomy": 6.0, "labor_displacement": 3.0},
			"factions": {"ASI": {"sub_agent_swarms": 12.0}}},
	},
}

var log_flops := START_LOG_FLOPS
## Capability gained from emergent capabilities on top of raw compute.
var capability_bonus := 0.0
var era := 1
var paradigm_progress := {}
var unlocked_shifts: Array[String] = []
var shift_unlock_turns := {}
var emerged_capabilities: Array[String] = []
var alignment_tax_multiplier := 1.0
var alignment_tax_events := 0
## Temporary growth multipliers: {"mult": float, "turns": int, "source": String}.
var growth_modifiers: Array[Dictionary] = []
var pending_capability_investment := 0.0
var pending_safety_investment := 0.0
var model_generation := 4
var agi_turn := -1
var last_growth := 0.0
var last_capability_delta := 0.0
var last_wall_factor := 1.0
var last_throttle := 1.0

## Test hooks: values >= 0 replace the computed probabilities.
var emergence_probability_override := -1.0
var breakthrough_probability_override := -1.0


func _init() -> void:
	for shift_id in SHIFT_ORDER:
		paradigm_progress[shift_id] = 0.0


func has_shift(shift_id: String) -> bool:
	return unlocked_shifts.has(shift_id)


func get_capability_index() -> float:
	var k := (log_flops - CAPABILITY_FLOOR_LOG) / CAPABILITY_SPAN_LOG * 100.0 + capability_bonus
	return clampf(k, 0.0, 100.0)


func is_agi_crossed() -> bool:
	return agi_turn >= 0


## Formal Mechanistic Interpretability halves every positive drift accrual.
func get_drift_accrual_multiplier() -> float:
	return 0.5 if has_shift(MECHANISTIC_INTERPRETABILITY) else 1.0


func get_discovery_pressure() -> float:
	return 1.5 if has_shift(MECHANISTIC_INTERPRETABILITY) else 0.0


func get_emergence_probability() -> float:
	if emergence_probability_override >= 0.0:
		return clampf(emergence_probability_override, 0.0, 1.0)
	var p := 0.30 + 0.15 * (alignment_tax_multiplier - 1.0) + 0.05 * float(era - 1)
	if has_shift(RECURSIVE_SYNTHETICS):
		p += 0.2
	return clampf(p, 0.05, 0.9)


func get_growth_modifier_product() -> float:
	var product := 1.0
	for modifier in growth_modifiers:
		product *= float(modifier["mult"])
	return clampf(product, 0.1, 4.0)


func add_investment(capability: float, safety: float) -> void:
	if is_finite(capability):
		pending_capability_investment = maxf(0.0, pending_capability_investment + capability)
	if is_finite(safety):
		pending_safety_investment = maxf(0.0, pending_safety_investment + safety)


func add_growth_modifier(mult: float, turns: int, source: String = "") -> void:
	if not is_finite(mult) or mult <= 0.0 or turns <= 0:
		return
	growth_modifiers.append({"mult": clampf(mult, 0.1, 4.0), "turns": turns, "source": source})


## Adds research progress to every shift that is not yet unlocked.
func add_paradigm_progress(amount: float) -> void:
	if not is_finite(amount):
		return
	for shift_id in SHIFT_ORDER:
		if not has_shift(shift_id):
			paradigm_progress[shift_id] = maxf(0.0, float(paradigm_progress[shift_id]) + amount)


## PRD 4.3: every initiative that cuts safety to accelerate release incurs a
## compounding alignment tax. [param coefficient] is clamped to [2.5%, 15%];
## drift rises by that share immediately (minimum 0.5) and the tax multiplier on
## all future drift accrual compounds by (1 + coefficient). Returns the applied drift.
func apply_alignment_tax(coefficient: float, world: WorldState) -> float:
	if not is_finite(coefficient) or coefficient <= 0.0:
		return 0.0
	var c := clampf(coefficient, ALIGNMENT_TAX_MIN, ALIGNMENT_TAX_MAX)
	alignment_tax_multiplier = minf(alignment_tax_multiplier * (1.0 + c), TAX_MULTIPLIER_CAP)
	alignment_tax_events += 1
	if world == null:
		return 0.0
	return world.apply_delta(WorldState.ALIGNMENT_DRIFT, maxf(0.5, world.alignment_drift * c))


## Advances frontier compute by one tick. Returns a report with growth, the
## capability delta, unlocked shifts and emergences; the engine applies their
## world effects through EffectResolver.
func advance(turn: int, year: float, compute: ComputeScaling, rng: RandomNumberGenerator) -> Dictionary:
	var report := {
		"turn": turn, "year": year, "era_changed": false, "era": era,
		"shifts": [], "emergences": [], "agi_crossed": false,
	}
	var new_era := SimConstants.era_for_year(year)
	if new_era != era:
		era = new_era
		report["era_changed"] = true
		report["era"] = era

	var previous_capability := get_capability_index()
	var previous_threshold := int(floor(log_flops))

	# Compounding run, bounded by the grid (throttle) and the thermal wall.
	var ceiling := ComputeScaling.thermal_ceiling(era, has_shift(OPTICAL_COMPUTING))
	var wall := clampf((ceiling - log_flops) / WALL_SOFTNESS, MIN_WALL_FACTOR, 1.0)
	var throttle := 1.0
	if compute != null:
		throttle = compute.get_growth_throttle()
	var invest_mult := 0.7 + 0.3 * clampf(pending_capability_investment / 10.0, 0.0, 2.0)
	var recursive := 3.0 if has_shift(RECURSIVE_SYNTHETICS) else 1.0
	var noise := 1.0
	if rng != null:
		noise = clampf(1.0 + rng.randfn(0.0, 0.08), 0.7, 1.3)
	var growth := float(ERA_BASE_GROWTH[era]) * invest_mult * wall * throttle \
		* get_growth_modifier_product() * recursive * noise
	growth = clampf(growth, 0.0, maxf(0.0, ceiling - log_flops))
	log_flops += growth
	last_growth = growth
	last_wall_factor = wall
	last_throttle = throttle

	# Paradigm research (cross-faction capability + safety investment).
	var capability_rnd := BASELINE_CAPABILITY_RND + 0.05 * previous_capability + pending_capability_investment
	var safety_rnd := BASELINE_SAFETY_RND + pending_safety_investment
	_distribute_research("capability", capability_rnd, year)
	_distribute_research("safety", safety_rnd, year)
	for shift_id in SHIFT_ORDER:
		if has_shift(shift_id):
			continue
		var info: Dictionary = PARADIGM_SHIFTS[shift_id]
		var cost := float(info["cost"])
		var progress := float(paradigm_progress[shift_id])
		if year < float(info["min_year"]) or progress < cost:
			continue
		var p := clampf(0.35 + 0.5 * (progress - cost) / cost, 0.0, 0.95)
		if breakthrough_probability_override >= 0.0:
			p = breakthrough_probability_override
		var breakthrough_roll := rng.randf() if rng != null else 0.0
		if breakthrough_roll < p:
			unlock_shift(shift_id, turn)
			report["shifts"].append(shift_report(shift_id))

	# Stochastic emergence: one roll per 10x FLOP threshold crossed this tick.
	var new_threshold := int(floor(log_flops))
	for threshold in range(previous_threshold + 1, new_threshold + 1):
		model_generation += 1
		var model_name := "Frontier Model-%d" % model_generation
		var emergence_roll := rng.randf() if rng != null else 0.0
		if emergence_roll >= get_emergence_probability():
			continue
		var emergence := _roll_emergence(float(threshold), model_name, rng)
		if not emergence.is_empty():
			report["emergences"].append(emergence)

	var capability := get_capability_index()
	last_capability_delta = maxf(0.0, capability - previous_capability)
	if agi_turn < 0 and capability >= AGI_CAPABILITY_THRESHOLD:
		agi_turn = turn
		report["agi_crossed"] = true

	# Safety work pays down part of the compounded alignment-tax debt.
	var recovery := clampf(TAX_RECOVERY + 0.004 * pending_safety_investment, 0.0, 0.2)
	alignment_tax_multiplier = 1.0 + (alignment_tax_multiplier - 1.0) * (1.0 - recovery)

	_tick_growth_modifiers()
	pending_capability_investment = 0.0
	pending_safety_investment = 0.0

	report["growth"] = growth
	report["log_flops"] = log_flops
	report["capability_index"] = capability
	report["capability_delta"] = last_capability_delta
	report["wall_factor"] = wall
	report["throttle"] = throttle
	report["thermal_ceiling"] = ceiling
	return report


func unlock_shift(shift_id: String, turn: int) -> void:
	if has_shift(shift_id) or not PARADIGM_SHIFTS.has(shift_id):
		return
	unlocked_shifts.append(shift_id)
	shift_unlock_turns[shift_id] = turn


func shift_report(shift_id: String) -> Dictionary:
	var info: Dictionary = PARADIGM_SHIFTS[shift_id]
	return {
		"id": shift_id,
		"name": info["name"],
		"summary": info["summary"],
		"effects": info["effects"],
	}


func _distribute_research(track: String, amount: float, year: float) -> void:
	if amount <= 0.0:
		return
	var candidates: Array[String] = []
	for shift_id in SHIFT_ORDER:
		if not has_shift(shift_id) and PARADIGM_SHIFTS[shift_id]["track"] == track:
			candidates.append(shift_id)
	if candidates.is_empty():
		return
	var share := amount / float(candidates.size())
	for shift_id in candidates:
		var efficiency := 1.0
		if year < float(PARADIGM_SHIFTS[shift_id]["min_year"]):
			efficiency = PRE_RESEARCH_EFFICIENCY
		paradigm_progress[shift_id] = float(paradigm_progress[shift_id]) + share * efficiency


func _roll_emergence(threshold_log: float, model_name: String, rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array[String] = []
	var total_weight := 0.0
	for capability_id in EMERGENT_CAPABILITIES:
		var info: Dictionary = EMERGENT_CAPABILITIES[capability_id]
		if emerged_capabilities.has(capability_id) or threshold_log < float(info["min_log_flops"]):
			continue
		pool.append(capability_id)
		total_weight += float(info["weight"])
	if pool.is_empty():
		return {}
	var chosen := pool[0]
	if rng != null:
		var roll := rng.randf() * total_weight
		for capability_id in pool:
			roll -= float(EMERGENT_CAPABILITIES[capability_id]["weight"])
			if roll <= 0.0:
				chosen = capability_id
				break
	emerged_capabilities.append(chosen)
	capability_bonus += 2.0
	var info: Dictionary = EMERGENT_CAPABILITIES[chosen]
	var spike := (3.0 + 2.0 * float(era)) * float(info["drift_weight"]) * alignment_tax_multiplier
	if has_shift(RECURSIVE_SYNTHETICS):
		spike *= 1.25
	return {
		"id": chosen,
		"name": info["name"],
		"model": model_name,
		"headline": String(info["headline"]).replace("{model}", model_name),
		"threshold": threshold_log,
		"drift_spike": spike,
		"effects": info["effects"],
	}


func _tick_growth_modifiers() -> void:
	var remaining: Array[Dictionary] = []
	for modifier in growth_modifiers:
		modifier["turns"] = int(modifier["turns"]) - 1
		if int(modifier["turns"]) > 0:
			remaining.append(modifier)
	growth_modifiers = remaining


func to_dict() -> Dictionary:
	return {
		"log_flops": log_flops,
		"capability_index": get_capability_index(),
		"era": era,
		"unlocked_shifts": unlocked_shifts.duplicate(),
		"paradigm_progress": paradigm_progress.duplicate(),
		"emerged_capabilities": emerged_capabilities.duplicate(),
		"alignment_tax_multiplier": alignment_tax_multiplier,
		"alignment_tax_events": alignment_tax_events,
		"agi_turn": agi_turn,
		"model_generation": model_generation,
		"last_growth": last_growth,
		"wall_factor": last_wall_factor,
		"throttle": last_throttle,
		"growth_multiplier": get_growth_modifier_product(),
	}
