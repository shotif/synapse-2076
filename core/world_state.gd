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
const K_LABOR_DOWN := 0.03
const K_AUTONOMY_RELAX := 0.12
const K_GEO_RELAX := 0.15
const K_TRUST_RELAX := 0.12
const K_SURVEILLANCE_RELAX := 0.10
const K_ENFORCEMENT_DECAY := 0.06
const ENFORCEMENT_FLOOR := 15.0
const PROVENANCE_DECAY := 0.03
const SAFETY_NET_DECAY := 0.05
const DISCOVERY_DECAY := 0.04

## Standard deviation of the stochastic shock applied to each metric per tick.
const NOISE_SIGMA := {
	COMPUTE_ENERGY_SAT: 0.5,
	LABOR_DISPLACEMENT: 0.4,
	GEOPOLITICAL_TENSION: 1.2,
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


func _init() -> void:
	reset()


func reset() -> void:
	for key in BASELINE:
		set(key, float(BASELINE[key]))
	drift_accrual_multiplier = 1.0
	history.clear()


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
	set(key, clean)
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
	return new_value - old_value


## Resolves one 6-month tick of the coupled macro dynamics.
##
## [param drivers] carries the tech/physics inputs for this tick:
##   capability_index  - 0..100 frontier capability (from log10 training FLOPs)
##   capability_delta  - capability index gained this tick
##   saturation_target - compute/energy saturation implied by grid physics
##   tax_multiplier    - compounding alignment-tax multiplier (>= 1)
##   discovery_pressure - extra ASI discovery per tick (e.g. interpretability)
## All deltas are computed from the pre-tick state and applied simultaneously, so
## the result does not depend on evaluation order. Returns the applied deltas.
func resolve_coupling(drivers: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	var k := clampf(float(drivers.get("capability_index", 0.0)), 0.0, 100.0)
	var dk := maxf(0.0, float(drivers.get("capability_delta", 0.0)))
	var c_target := sanitize(float(drivers.get("saturation_target", compute_energy_sat)))
	var tax := maxf(1.0, float(drivers.get("tax_multiplier", 1.0)))
	var discovery_pressure := maxf(0.0, float(drivers.get("discovery_pressure", 0.0)))

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
	#    x adoption (autonomy). Displacement is sticky: it falls far slower than it rises.
	var automatable := clampf(sigmoid((k - 40.0) / 12.0) / sigmoid(5.0), 0.0, 1.0)
	var adoption := 0.5 + 0.5 * minf(1.0, a / 85.0)
	var l_target := 10.0 + 90.0 * automatable * adoption
	var l_rate := K_LABOR_UP if l_target > l else K_LABOR_DOWN
	deltas[LABOR_DISPLACEMENT] = l_rate * (l_target - l)

	# 3. Algorithmic autonomy: capability-driven delegation, restrained by
	#    enforcement and accelerated by already-displaced labor.
	var a_target := 8.0 + 92.0 * sigmoid((k - 35.0) / 13.0) * (1.0 - 0.4 * e / 100.0) + 0.15 * (l - 50.0)
	deltas[ALGORITHMIC_AUTONOMY] = K_AUTONOMY_RELAX * (clampf(a_target, 0.0, 100.0) - a)

	# 4. Alignment drift accrues with capability growth and unsupervised autonomy,
	#    compounded by the alignment tax; enforcement provides slow oversight decay.
	var accrual := (0.9 * dk + 0.010 * a + 0.012 * maxf(0.0, a - 50.0)) * tax
	var oversight := 0.02 * e * (d / 100.0)
	deltas[ALIGNMENT_DRIFT] = accrual - oversight

	# 5. Geopolitical tension: arms-race pressure from autonomy, drift, distrust
	#    and the pace of capability growth.
	var g_target := 25.0 + 0.25 * a + 0.2 * d + 0.2 * (60.0 - t) + 6.0 * minf(dk, 3.0)
	deltas[GEOPOLITICAL_TENSION] = K_GEO_RELAX * (clampf(g_target, 0.0, 100.0) - g)

	# 6. Epistemic trust: eroded by uncushioned displacement, tension, drift,
	#    autonomy, surveillance and synthetic media; rebuilt by provenance protocols.
	var displacement_pain := 0.30 * maxf(0.0, l - 25.0) * (1.0 - 0.6 * n / 100.0)
	var synthetic_media := 0.08 * k * (1.0 - p / 100.0)
	var t_target := 62.0 + 0.3 * p - displacement_pain \
		- 0.25 * maxf(0.0, g - 40.0) - 0.2 * maxf(0.0, d - 35.0) \
		- 0.12 * maxf(0.0, a - 45.0) - 0.12 * maxf(0.0, s - 45.0) - synthetic_media
	deltas[EPISTEMIC_TRUST] = K_TRUST_RELAX * (clampf(t_target, 0.0, 100.0) - t)

	# Secondary indices.
	var s_target := 15.0 + 0.45 * a + 0.25 * maxf(0.0, g - 40.0) + 0.1 * e
	deltas[SURVEILLANCE_SATURATION] = K_SURVEILLANCE_RELAX * (clampf(s_target, 0.0, 100.0) - s)
	deltas[ENFORCEMENT_LEVEL] = K_ENFORCEMENT_DECAY * (ENFORCEMENT_FLOOR - e)
	deltas[PROVENANCE_COVERAGE] = -PROVENANCE_DECAY * p
	deltas[SAFETY_NET_COVERAGE] = -SAFETY_NET_DECAY * n
	deltas[DISCOVERY_INDEX] = -DISCOVERY_DECAY * discovery_index + 0.025 * e + discovery_pressure

	if rng != null:
		for key in NOISE_SIGMA:
			deltas[key] = float(deltas[key]) + rng.randfn(0.0, float(NOISE_SIGMA[key]))

	var applied := {}
	for key in deltas:
		applied[key] = apply_delta(key, float(deltas[key]))
	return applied


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
	for key in METRIC_KEYS + INDEX_KEYS:
		if data.has(key):
			set_value(key, float(data[key]))
	drift_accrual_multiplier = maxf(0.0, float(data.get("drift_accrual_multiplier", 1.0)))
