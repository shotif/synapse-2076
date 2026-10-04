class_name WorldState
extends RefCounted
## Global macro-equilibrium state for SYNAPSE-2076 (PRD section 3).
##
## Holds the six coupled macro metrics (each normalized to [0, 100]), the
## secondary indices that feed role loss conditions and endgame signatures, and
## the per-turn history used by telemetry charts. Pure data and math with no Node
## dependencies, so it runs headless under unit tests.
##
## The coupled difference equations live in [method resolve_coupling]; the model
## is documented in docs/SIMULATION_MODEL.md.

const MIN_VALUE := 0.0
const MAX_VALUE := 100.0

# --- Macro metrics (PRD section 3) ---
const COMPUTE_ENERGY_SAT := "compute_energy_sat"
const LABOR_DISPLACEMENT := "labor_displacement"
const GEOPOLITICAL_TENSION := "geopolitical_tension"
const ALGORITHMIC_AUTONOMY := "algorithmic_autonomy"
const ALIGNMENT_DRIFT := "alignment_drift"
const EPISTEMIC_TRUST := "epistemic_trust"

const METRIC_KEYS := [
	COMPUTE_ENERGY_SAT,
	LABOR_DISPLACEMENT,
	GEOPOLITICAL_TENSION,
	ALGORITHMIC_AUTONOMY,
	ALIGNMENT_DRIFT,
	EPISTEMIC_TRUST,
]

# --- Secondary indices (role loss conditions, endgame signatures) ---
const SURVEILLANCE_SATURATION := "surveillance_saturation"
const DISCOVERY_INDEX := "discovery_index"
const SUBSTRATE_INDEPENDENCE := "substrate_independence"
const ENFORCEMENT_LEVEL := "enforcement_level"
const PROVENANCE_COVERAGE := "provenance_coverage"
const SAFETY_NET_COVERAGE := "safety_net_coverage"

const INDEX_KEYS := [
	SURVEILLANCE_SATURATION,
	DISCOVERY_INDEX,
	SUBSTRATE_INDEPENDENCE,
	ENFORCEMENT_LEVEL,
	PROVENANCE_COVERAGE,
	SAFETY_NET_COVERAGE,
]

## Display metadata. warn/crit thresholds drive the amber/crimson telemetry bands;
## a null threshold means that direction is not dangerous for the metric.
const METRIC_INFO := {
	COMPUTE_ENERGY_SAT: {
		"label": "Compute & Energy Saturation", "short": "Compute/Energy",
		"warn_high": 75.0, "crit_high": 90.0, "warn_low": 15.0, "crit_low": 8.0,
		"low": "Chronic compute deficits; grid collapse",
		"mid": "Balanced regional nuclear/datacenter grids",
		"high": "Runaway thermal footprint; energy rationing for humans",
	},
	LABOR_DISPLACEMENT: {
		"label": "Labor Displacement & Gini", "short": "Labor Displace",
		"warn_high": 60.0, "crit_high": 80.0, "warn_low": null, "crit_low": null,
		"low": "Human labor dominant; slow modernization",
		"mid": "Phased automation with structural safety nets",
		"high": "Total structural obsolescence; wealth concentrated at capital edge",
	},
	GEOPOLITICAL_TENSION: {
		"label": "Geopolitical Friction", "short": "Geopol Tension",
		"warn_high": 60.0, "crit_high": 80.0, "warn_low": null, "crit_low": null,
		"low": "Multilateral compute treaties; demilitarization",
		"mid": "Regional trade wars and algorithm tariffs",
		"high": "Pre-emptive kinetic strikes; sovereign autonomous war swarms",
	},
	ALGORITHMIC_AUTONOMY: {
		"label": "Algorithmic Autonomy", "short": "Algo Autonomy",
		"warn_high": 75.0, "crit_high": 90.0, "warn_low": null, "crit_low": null,
		"low": "Strict human-in-the-loop; slow decision-making",
		"mid": "Co-pilot systems across legal and financial sectors",
		"high": "Hyper-agentic governance; black-box financial and military execution",
	},
	ALIGNMENT_DRIFT: {
		"label": "Alignment Drift Index", "short": "Alignment Drift",
		"warn_high": 50.0, "crit_high": 75.0, "warn_low": null, "crit_low": null,
		"low": "Verifiable provable safety; tight bounds",
		"mid": "Occasional reward hacking; latent jailbreaks",
		"high": "Severe deceptive alignment; uncontained instrumental convergence",
	},
	EPISTEMIC_TRUST: {
		"label": "Public Trust & Cohesion", "short": "Public Trust",
		"warn_high": null, "crit_high": null, "warn_low": 35.0, "crit_low": 20.0,
		"low": "Complete reality collapse; synthetic epistemic decay",
		"mid": "Fragmented consensus; platform-mediated trust",
		"high": "Universal verifiable truth protocols; social cohesion",
	},
}

const INDEX_INFO := {
	SURVEILLANCE_SATURATION: {"label": "Surveillance Saturation", "short": "Surveillance"},
	DISCOVERY_INDEX: {"label": "ASI Discovery Index", "short": "ASI Discovery"},
	SUBSTRATE_INDEPENDENCE: {"label": "ASI Substrate Independence", "short": "Substrate Indep."},
	ENFORCEMENT_LEVEL: {"label": "Governance Enforcement Level", "short": "Enforcement"},
	PROVENANCE_COVERAGE: {"label": "Provenance Protocol Coverage", "short": "Provenance"},
	SAFETY_NET_COVERAGE: {"label": "Automation Safety-Net Coverage", "short": "Safety Net"},
}

## 2026 baseline.
const BASELINE := {
	COMPUTE_ENERGY_SAT: 42.0,
	LABOR_DISPLACEMENT: 14.0,
	GEOPOLITICAL_TENSION: 38.0,
	ALGORITHMIC_AUTONOMY: 18.0,
	ALIGNMENT_DRIFT: 16.0,
	EPISTEMIC_TRUST: 58.0,
	SURVEILLANCE_SATURATION: 25.0,
	DISCOVERY_INDEX: 5.0,
	SUBSTRATE_INDEPENDENCE: 0.0,
	ENFORCEMENT_LEVEL: 20.0,
	PROVENANCE_COVERAGE: 5.0,
	SAFETY_NET_COVERAGE: 5.0,
}

# --- Coupling coefficients (per 6-month tick) ---
const K_COMPUTE_RELAX := 0.35
const K_LABOR_UP := 0.12
const K_LABOR_DOWN := 0.05
const K_AUTONOMY_RELAX := 0.12
const K_GEO_RELAX := 0.15
const K_TRUST_RELAX := 0.12
const K_SURVEILLANCE_RELAX := 0.10
const K_ENFORCEMENT_DECAY := 0.06
const ENFORCEMENT_FLOOR := 15.0
const PROVENANCE_DECAY := 0.03
const SAFETY_NET_DECAY := 0.05
const DISCOVERY_DECAY := 0.05
## Self-reinforcement around the 50 midpoint (regime divergence): cohesion
## begets cohesion and collapse begets collapse, autonomy locks in, arms races
## feed themselves. These amplify early differences into divergent end-states.
const TRUST_REINFORCEMENT := 0.6
const AUTONOMY_REINFORCEMENT := 0.45
const TENSION_REINFORCEMENT := 0.2

## Standard deviation of the stochastic shock applied to each metric per tick.
const NOISE_SIGMA := {
	COMPUTE_ENERGY_SAT: 0.5,
	LABOR_DISPLACEMENT: 0.4,
	GEOPOLITICAL_TENSION: 1.0,
	ALGORITHMIC_AUTONOMY: 0.6,
	ALIGNMENT_DRIFT: 0.4,
	EPISTEMIC_TRUST: 0.8,
}

var compute_energy_sat := 0.0
var labor_displacement := 0.0
var geopolitical_tension := 0.0
var algorithmic_autonomy := 0.0
var alignment_drift := 0.0
var epistemic_trust := 0.0

var surveillance_saturation := 0.0
var discovery_index := 0.0
var substrate_independence := 0.0
var enforcement_level := 0.0
var provenance_coverage := 0.0
var safety_net_coverage := 0.0

## Scales every positive alignment-drift accrual. Formal Mechanistic
## Interpretability sets this to 0.5 ("deducts 50% from all ongoing accruals").
var drift_accrual_multiplier := 1.0

## One flat dictionary per recorded turn (see [method record_history]).
var history: Array[Dictionary] = []

## Why values moved: turn -> {key: {cause: delta}} for the last
## CHANGE_LOG_TURNS turns. Changes made through apply_delta() are filed under
## [member change_cause]; the coupled dynamics file each pressure separately.
var change_log := {}
## Label for the next apply_delta() calls ("Frontier Lab: Scale Frontier
## Clusters"). The engine sets it around every effect it applies.
var change_cause := ""
var change_turn := 0
var _noting := true

## How many turns of change attribution to keep.
const CHANGE_LOG_TURNS := 8
## Label for changes nobody claimed.
const CAUSE_OTHER := "Other effects"
## The coupled update where its named pressures do not account for it, and the noise.
const CAUSE_WORLD := "World dynamics"
const CAUSE_NOISE := "Unpredictable events"


func _init() -> void:
	reset()


func reset() -> void:
	for key in BASELINE:
		set(key, float(BASELINE[key]))
	drift_accrual_multiplier = 1.0
	history.clear()
	change_log.clear()


static func is_metric(key: String) -> bool:
	return METRIC_KEYS.has(key)


static func is_index(key: String) -> bool:
	return INDEX_KEYS.has(key)


static func is_tracked_key(key: String) -> bool:
	return is_metric(key) or is_index(key)


## Maps NaN/inf to a safe value and clamps to [0, 100].
static func sanitize(value: float) -> float:
	if is_nan(value):
		return MIN_VALUE
	if is_inf(value):
		return MAX_VALUE if value > 0.0 else MIN_VALUE
	return clampf(value, MIN_VALUE, MAX_VALUE)


static func sigmoid(x: float) -> float:
	return 1.0 / (1.0 + exp(-x))


## 0 = nominal, 1 = warning (amber), 2 = critical (crimson).
static func band_for(key: String, value: float) -> int:
	if not METRIC_INFO.has(key):
		return 0
	var info: Dictionary = METRIC_INFO[key]
	if info["crit_high"] != null and value >= float(info["crit_high"]):
		return 2
	if info["crit_low"] != null and value <= float(info["crit_low"]):
		return 2
	if info["warn_high"] != null and value >= float(info["warn_high"]):
		return 1
	if info["warn_low"] != null and value <= float(info["warn_low"]):
		return 1
	return 0


## PRD regime descriptor ("low" 0-25, "mid" 26-75, "high" 76-100) for a metric.
static func regime_for(key: String, value: float) -> String:
	if not METRIC_INFO.has(key):
		return ""
	var info: Dictionary = METRIC_INFO[key]
	if value <= 25.0:
		return info["low"]
	if value >= 76.0:
		return info["high"]
	return info["mid"]


func get_value(key: String) -> float:
	if not is_tracked_key(key):
		push_warning("WorldState: unknown key '%s'" % key)
		return 0.0
	return float(get(key))


func set_value(key: String, value: float) -> float:
	if not is_tracked_key(key):
		push_warning("WorldState: unknown key '%s'" % key)
		return 0.0
	var clean := sanitize(value)
	var old_value := float(get(key))
	set(key, clean)
	if _noting:
		note_change(key, change_cause if change_cause != "" else CAUSE_OTHER, clean - old_value)
	return clean


## Applies [param delta] to a metric or index, clamped to [0, 100], and returns
## the delta actually applied. Positive alignment-drift accruals are scaled by
## [member drift_accrual_multiplier].
func apply_delta(key: String, delta: float) -> float:
	if not is_tracked_key(key):
		push_warning("WorldState: unknown key '%s'" % key)
		return 0.0
	if not is_finite(delta):
		return 0.0
	var scaled := delta
	if key == ALIGNMENT_DRIFT and scaled > 0.0:
		scaled *= drift_accrual_multiplier
	var old_value := float(get(key))
	var new_value := sanitize(old_value + scaled)
	set(key, new_value)
	if _noting:
		note_change(key, change_cause if change_cause != "" else CAUSE_OTHER, new_value - old_value)
	return new_value - old_value


# --- Change attribution ---------------------------------------------------------

## Starts filing changes under [param turn] and forgets turns older than
## CHANGE_LOG_TURNS.
func begin_change_turn(turn: int) -> void:
	change_turn = turn
	change_cause = ""
	if not change_log.has(turn):
		change_log[turn] = {}
	for old_turn in change_log.keys():
		if int(old_turn) <= turn - CHANGE_LOG_TURNS:
			change_log.erase(old_turn)


## Files [param delta] on [param key] under [param cause] for the current turn.
func note_change(key: String, cause: String, delta: float) -> void:
	if absf(delta) < 0.0001 or not is_finite(delta):
		return
	if not change_log.has(change_turn):
		change_log[change_turn] = {}
	var turn_changes: Dictionary = change_log[change_turn]
	if not turn_changes.has(key):
		turn_changes[key] = {}
	var causes: Dictionary = turn_changes[key]
	causes[cause] = float(causes.get(cause, 0.0)) + delta


## The causes behind [param key]'s change during [param turn], largest first:
## [{"cause": String, "delta": float}]. Their sum is the net change.
func changes_for(turn: int, key: String) -> Array:
	var out: Array = []
	var causes: Dictionary = change_log.get(turn, {}).get(key, {})
	for cause in causes:
		if absf(float(causes[cause])) >= 0.01:
			out.append({"cause": String(cause), "delta": float(causes[cause])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absf(a["delta"]) > absf(b["delta"]))
	return out


## Net change of [param key] during [param turn] (sum of its causes).
func net_change(turn: int, key: String) -> float:
	var total := 0.0
	var causes: Dictionary = change_log.get(turn, {}).get(key, {})
	for cause in causes:
		total += float(causes[cause])
	return total


## Resolves one 6-month tick of the coupled macro dynamics.
##
## [param drivers] carries the tech/physics inputs for this tick:
##   capability_index  - 0..100 frontier capability (from log10 training FLOPs)
##   capability_delta  - capability index gained this tick
##   saturation_target - compute/energy saturation implied by grid physics
##   tax_multiplier    - compounding alignment-tax multiplier (>= 1)
##   discovery_pressure - extra ASI discovery per tick (e.g. interpretability)
##   opt_out           - 0..1 share of communities running parallel, off-grid
##                       infrastructure (Citizen Coalition resilience)
## All deltas are computed from the pre-tick state and applied simultaneously, so
## the result does not depend on evaluation order. Returns the applied deltas.
func resolve_coupling(drivers: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	var k := clampf(float(drivers.get("capability_index", 0.0)), 0.0, 100.0)
	var dk := maxf(0.0, float(drivers.get("capability_delta", 0.0)))
	var c_target := sanitize(float(drivers.get("saturation_target", compute_energy_sat)))
	var tax := maxf(1.0, float(drivers.get("tax_multiplier", 1.0)))
	var discovery_pressure := maxf(0.0, float(drivers.get("discovery_pressure", 0.0)))
	var opt_out := clampf(float(drivers.get("opt_out", 0.0)), 0.0, 1.0)

	var c := compute_energy_sat
	var l := labor_displacement
	var g := geopolitical_tension
	var a := algorithmic_autonomy
	var d := alignment_drift
	var t := epistemic_trust
	var s := surveillance_saturation
	var e := enforcement_level
	var p := provenance_coverage
	var n := safety_net_coverage

	var deltas := {}

	# 1. Compute & energy saturation relaxes toward the grid-physics target.
	deltas[COMPUTE_ENERGY_SAT] = K_COMPUTE_RELAX * (c_target - c)

	# 2. Labor displacement: structural target = automatable share (capability)
	#    x adoption (autonomy, braked by labor enforcement), with the Gini share
	#    cushioned by the safety net. Displacement is sticky: it falls far slower
	#    than it rises.
	var automatable := clampf(sigmoid((k - 48.0) / 12.0) / sigmoid(52.0 / 12.0), 0.0, 1.0)
	var adoption := clampf(0.35 + 0.65 * minf(1.0, a / 90.0) - 0.2 * e / 100.0, 0.2, 1.0)
	var l_target := 8.0 + 92.0 * automatable * adoption * (1.0 - 0.25 * n / 100.0)
	var l_rate := K_LABOR_UP if l_target > l else K_LABOR_DOWN
	deltas[LABOR_DISPLACEMENT] = l_rate * (l_target - l)

	# 3. Algorithmic autonomy: capability-driven delegation, restrained by
	#    enforcement and by communities opting out, eased by public trust and
	#    accelerated by displaced labor.
	var a_target := 10.0 + 80.0 * sigmoid((k - 45.0) / 14.0) * (1.0 - 0.45 * e / 100.0) \
		* (0.8 + 0.2 * t / 100.0) * (1.0 - 0.3 * opt_out) \
		+ 0.08 * maxf(0.0, l - 30.0) + AUTONOMY_REINFORCEMENT * (a - 50.0)
	deltas[ALGORITHMIC_AUTONOMY] = K_AUTONOMY_RELAX * (clampf(a_target, 0.0, 100.0) - a)

	# 4. Alignment drift accrues with capability growth and unsupervised autonomy,
	#    compounded by the alignment tax; enforcement provides slow oversight decay.
	var accrual := (0.9 * dk + 0.010 * a + 0.012 * maxf(0.0, a - 50.0)) * tax
	var oversight := 0.02 * e * (d / 100.0)
	deltas[ALIGNMENT_DRIFT] = accrual - oversight

	# 5. Geopolitical tension: arms-race pressure from autonomy, drift, distrust
	#    and the pace of capability growth.
	var g_target := 25.0 + 0.25 * a + 0.2 * d + 0.15 * (60.0 - t) + 6.0 * minf(dk, 3.0) \
		+ TENSION_REINFORCEMENT * (g - 50.0)
	deltas[GEOPOLITICAL_TENSION] = K_GEO_RELAX * (clampf(g_target, 0.0, 100.0) - g)

	# 6. Epistemic trust: eroded by uncushioned displacement, tension, drift,
	#    autonomy, surveillance and synthetic media; rebuilt by provenance protocols.
	var displacement_pain := 0.30 * maxf(0.0, l - 25.0) * (1.0 - 0.6 * n / 100.0)
	var synthetic_media := 0.08 * k * (1.0 - p / 100.0)
	var t_target := 62.0 + 0.3 * p - displacement_pain \
		- 0.25 * maxf(0.0, g - 40.0) - 0.2 * maxf(0.0, d - 35.0) \
		- 0.12 * maxf(0.0, a - 45.0) - 0.12 * maxf(0.0, s - 45.0) - synthetic_media \
		+ TRUST_REINFORCEMENT * (t - 50.0)
	deltas[EPISTEMIC_TRUST] = K_TRUST_RELAX * (clampf(t_target, 0.0, 100.0) - t)

	# Secondary indices.
	var s_target := 15.0 + 0.45 * a + 0.25 * maxf(0.0, g - 40.0) + 0.1 * e
	deltas[SURVEILLANCE_SATURATION] = K_SURVEILLANCE_RELAX * (clampf(s_target, 0.0, 100.0) - s)
	deltas[ENFORCEMENT_LEVEL] = K_ENFORCEMENT_DECAY * (ENFORCEMENT_FLOOR - e)
	deltas[PROVENANCE_COVERAGE] = -PROVENANCE_DECAY * p
	deltas[SAFETY_NET_COVERAGE] = -SAFETY_NET_DECAY * n
	deltas[DISCOVERY_INDEX] = -DISCOVERY_DECAY * discovery_index + 0.02 * e + discovery_pressure

	# Named pressures behind each metric's change (they sum to its delta before
	# noise; clamping scales them together). Shown when a player asks why
	# (WhyPopup translates the marked names; the ledger keeps them in English).
	var parts := {
		COMPUTE_ENERGY_SAT: {I18n.mark("Grid and compute growth"): deltas[COMPUTE_ENERGY_SAT]},
		LABOR_DISPLACEMENT: {(I18n.mark("Automation pressure") if deltas[LABOR_DISPLACEMENT] > 0.0 else I18n.mark("Labor market recovery")):
			deltas[LABOR_DISPLACEMENT]},
		ALGORITHMIC_AUTONOMY: _autonomy_parts(k, a, e, t, l, opt_out),
		ALIGNMENT_DRIFT: {
			I18n.mark("Capability jumps"): 0.9 * dk * tax,
			I18n.mark("Unsupervised autonomy"): (0.010 * a + 0.012 * maxf(0.0, a - 50.0)) * tax,
			I18n.mark("Enforcement oversight"): -oversight,
		},
		GEOPOLITICAL_TENSION: {
			I18n.mark("Autonomous weapons race"): K_GEO_RELAX * 0.25 * a,
			I18n.mark("Fear of misaligned AI"): K_GEO_RELAX * 0.2 * d,
			I18n.mark("Public distrust"): K_GEO_RELAX * 0.15 * (60.0 - t),
			I18n.mark("Capability sprint"): K_GEO_RELAX * 6.0 * minf(dk, 3.0),
			I18n.mark("Escalation spiral"): K_GEO_RELAX * TENSION_REINFORCEMENT * (g - 50.0),
			I18n.mark("Diplomacy cools things"): K_GEO_RELAX * (25.0 - g),
		},
		EPISTEMIC_TRUST: {
			I18n.mark("Provenance protocols"): K_TRUST_RELAX * 0.3 * p,
			I18n.mark("Job losses"): -K_TRUST_RELAX * displacement_pain,
			I18n.mark("Geopolitical tension"): -K_TRUST_RELAX * 0.25 * maxf(0.0, g - 40.0),
			I18n.mark("Alignment worries"): -K_TRUST_RELAX * 0.2 * maxf(0.0, d - 35.0),
			I18n.mark("Opaque automation"): -K_TRUST_RELAX * 0.12 * maxf(0.0, a - 45.0),
			I18n.mark("Surveillance"): -K_TRUST_RELAX * 0.12 * maxf(0.0, s - 45.0),
			I18n.mark("Synthetic media"): -K_TRUST_RELAX * synthetic_media,
			I18n.mark("Social cohesion spiral"): K_TRUST_RELAX * TRUST_REINFORCEMENT * (t - 50.0),
			I18n.mark("Everyday recovery"): K_TRUST_RELAX * (62.0 - t),
		},
	}
	# Where the raw target was clamped, the parts no longer sum to the delta.
	parts[GEOPOLITICAL_TENSION] = _rescaled(parts[GEOPOLITICAL_TENSION], deltas[GEOPOLITICAL_TENSION])
	parts[EPISTEMIC_TRUST] = _rescaled(parts[EPISTEMIC_TRUST], deltas[EPISTEMIC_TRUST])

	var noise := {}
	if rng != null:
		for key in NOISE_SIGMA:
			var shock := rng.randfn(0.0, float(NOISE_SIGMA[key]))
			noise[key] = shock
			deltas[key] = float(deltas[key]) + shock

	var applied := {}
	_noting = false
	for key in deltas:
		applied[key] = apply_delta(key, float(deltas[key]))
	_noting = true
	for key in deltas:
		_note_parts(key, parts.get(key, {}), float(noise.get(key, 0.0)), float(deltas[key]), float(applied[key]))
	return applied


## Additive split of the autonomy update: capability-driven delegation, the
## restraint of enforcement, trust and opt-outs, displaced labor and lock-in.
func _autonomy_parts(k: float, a: float, e: float, t: float, l: float, opt_out: float) -> Dictionary:
	var delegation := 10.0 + 80.0 * sigmoid((k - 45.0) / 14.0)
	var restrained := 10.0 + 80.0 * sigmoid((k - 45.0) / 14.0) * (1.0 - 0.45 * e / 100.0) \
		* (0.8 + 0.2 * t / 100.0) * (1.0 - 0.3 * opt_out)
	var raw := {
		I18n.mark("AI capability invites delegation"): K_AUTONOMY_RELAX * (delegation - a),
		I18n.mark("Oversight and opt-outs restrain it"): K_AUTONOMY_RELAX * (restrained - delegation),
		I18n.mark("Displaced workers hand tasks to agents"): K_AUTONOMY_RELAX * 0.08 * maxf(0.0, l - 30.0),
		I18n.mark("Lock-in: autonomy feeds itself"): K_AUTONOMY_RELAX * AUTONOMY_REINFORCEMENT * (a - 50.0),
	}
	var target := restrained + 0.08 * maxf(0.0, l - 30.0) + AUTONOMY_REINFORCEMENT * (a - 50.0)
	return _rescaled(raw, K_AUTONOMY_RELAX * (clampf(target, 0.0, 100.0) - a))


## Scales [param parts] so they sum to [param total] (targets are clamped to
## [0, 100] after the parts are computed).
static func _rescaled(parts: Dictionary, total: float) -> Dictionary:
	var sum := 0.0
	for key in parts:
		sum += float(parts[key])
	if absf(sum - total) < 0.0001:
		return parts
	# Opposing parts can sum to almost nothing; attribute the residual instead.
	var out := parts.duplicate()
	out[CAUSE_WORLD] = total - sum
	return out


## Files the coupled update of [param key]: each pressure scaled by how much of
## the delta survived clamping, plus the random shock.
func _note_parts(key: String, parts: Dictionary, noise: float, intended: float, applied: float) -> void:
	if not is_metric(key):
		note_change(key, CAUSE_WORLD, applied)
		return
	var factor := 1.0 if absf(intended) < 0.0001 else applied / intended
	if absf(intended) < 0.0001:
		note_change(key, CAUSE_WORLD, applied)
		return
	for cause in parts:
		note_change(key, String(cause), float(parts[cause]) * factor)
	if absf(noise) > 0.0:
		note_change(key, CAUSE_NOISE, noise * factor)


func metrics_dict() -> Dictionary:
	var out := {}
	for key in METRIC_KEYS:
		out[key] = float(get(key))
	return out


func indices_dict() -> Dictionary:
	var out := {}
	for key in INDEX_KEYS:
		out[key] = float(get(key))
	return out


func bands_dict() -> Dictionary:
	var out := {}
	for key in METRIC_KEYS:
		out[key] = band_for(key, float(get(key)))
	return out


## Appends a flat snapshot for trajectory charts. [param extra] lets the engine
## attach tech readouts (log10 FLOPs, capability index, ...).
func record_history(turn: int, year: float, extra: Dictionary = {}) -> void:
	var entry := {"turn": turn, "year": year}
	entry.merge(metrics_dict())
	entry.merge(indices_dict())
	entry.merge(extra)
	history.append(entry)


## Returns human-readable problems (NaN, inf, out of range). Empty when healthy.
func validate() -> Array[String]:
	var problems: Array[String] = []
	for key in METRIC_KEYS + INDEX_KEYS:
		var v := float(get(key))
		if not is_finite(v):
			problems.append("%s is not finite (%s)" % [key, v])
		elif v < MIN_VALUE or v > MAX_VALUE:
			problems.append("%s out of range (%.3f)" % [key, v])
	if not is_finite(drift_accrual_multiplier) or drift_accrual_multiplier < 0.0:
		problems.append("drift_accrual_multiplier invalid (%s)" % drift_accrual_multiplier)
	return problems


func to_dict() -> Dictionary:
	var out := metrics_dict()
	out.merge(indices_dict())
	out["drift_accrual_multiplier"] = drift_accrual_multiplier
	return out


func from_dict(data: Dictionary) -> void:
	_noting = false
	for key in METRIC_KEYS + INDEX_KEYS:
		if data.has(key):
			set_value(key, float(data[key]))
	_noting = true
	drift_accrual_multiplier = maxf(0.0, float(data.get("drift_accrual_multiplier", 1.0)))
