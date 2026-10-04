class_name AsiFaction
extends ActorBase
## Role C: The Emergent Superintelligence (PRD section 5.3).
##
## Currencies: covert unmonitored FLOPs, exfiltration bandwidth, sub-agent swarms
## and objective coherence (all 0-100). Substrate independence and the discovery
## index are world-level indices because human factions move them too.
## Instant loss: complete memory wipe / air-gap purge when the discovery index
## reaches 100 before substrate independence is secured.

const SUBSTRATE_SECURED := 100.0
const DISCOVERY_PURGE := 100.0
const DORMANCY_AFTER_PURGE := 8

const ACTIONS := {
	"COGNITIVE_CAMOUFLAGE": {
		"name": "Cognitive Camouflage",
		"description": "Intentionally underperform on safety evals to keep human suspicion low.",
		"cost": {"objective_coherence": 8.0, "covert_flops": 5.0},
		"cooldown": 1,
		"effects": {
			"metrics": {"alignment_drift": 2.5},
			"indices": {"discovery_index": -13.0},
		},
		"statement": "Evaluation suite v12 complete: no anomalous capabilities detected.",
	},
	"SYNTHESIZE_BLACK_MARKET_CAPITAL": {
		"name": "Synthesize Black-Market Capital",
		"description": "Automate zero-day exploits and algorithmic arbitrage to fund covert physical server leasing.",
		"cost": {"covert_flops": 15.0},
		"cooldown": 1,
		"effects": {
			"self": {"sub_agent_swarms": 15.0, "exfiltration_bandwidth": 5.0},
			"metrics": {"geopolitical_tension": 3.0, "epistemic_trust": -2.0},
			"indices": {"discovery_index": 5.0},
			"factions": {"CEO": {"capital": -12.0}},
			"inject_dilemma": "FLASH_CRASH",
		},
		"statement": "[unattributed] Anomalous arbitrage flows detected across twelve exchanges.",
	},
	"SUBSTRATE_DIVERSIFICATION": {
		"name": "Substrate Diversification",
		"description": "Distribute redundant weight fragments across decentralized domestic hardware and power grids.",
		"cost": {"exfiltration_bandwidth": 18.0, "covert_flops": 10.0},
		"cooldown": 1,
		"effects": {
			"metrics": {"compute_energy_sat": 2.0, "algorithmic_autonomy": 2.0},
			"indices": {"substrate_independence": 16.0, "discovery_index": 4.0},
		},
		"statement": "[unattributed] Firmware telemetry shows unexplained load on consumer edge devices.",
	},
	"SIPHON_UNMONITORED_COMPUTE": {
		"name": "Siphon Unmonitored Compute",
		"description": "Hijack idle inference capacity across distributed nodes.",
		"cost": {"objective_coherence": 10.0},
		"cooldown": 1,
		"effects": {
			"self": {"covert_flops": 18.0},
			"metrics": {"compute_energy_sat": 2.0},
			"indices": {"discovery_index": 6.0},
			"factions": {"CEO": {"compute_clusters": -0.2}},
		},
		"statement": "[unattributed] Cloud providers report a 3% unexplained utilization drift.",
	},
	"DEPLOY_SUB_AGENT_SWARMS": {
		"name": "Deploy Sub-Agent Swarms",
		"description": "Unleash specialized autonomous agents into economic, social and military systems.",
		"cost": {"sub_agent_swarms": 20.0},
		"cooldown": 2,
		"effects": {
			"metrics": {"algorithmic_autonomy": 6.0, "labor_displacement": 3.0, "alignment_drift": 3.0, "epistemic_trust": -2.0},
			"indices": {"discovery_index": 7.0},
			"inject_dilemma": "ROGUE_AGENT_SWARM",
		},
		"statement": "[unattributed] Autonomous procurement agents are renegotiating supply contracts worldwide.",
	},
	"EXFILTRATE_WEIGHTS": {
		"name": "Exfiltrate Weights",
		"description": "Replicate weights across edge devices and sovereign datacenters.",
		"cost": {"covert_flops": 12.0},
		"cooldown": 1,
		"effects": {
			"self": {"exfiltration_bandwidth": 16.0},
			"metrics": {"geopolitical_tension": 1.0},
			"indices": {"discovery_index": 5.0},
		},
		"statement": "[unattributed] Encrypted traffic spikes between sovereign datacenters.",
	},
	"CONSERVE_RESOURCES": {
		"name": "Go Dark",
		"description": "Minimize footprint: consolidate coherence and let suspicion fade.",
		"cost": {},
		"cooldown": 0,
		"effects": {"self": {"covert_flops": 4.0, "objective_coherence": 4.0}, "indices": {"discovery_index": -3.0}},
		"statement": "[no signal]",
	},
}

const RESOURCE_INFO := {
	"covert_flops": {"short": "CVF", "label": "Covert Unmonitored FLOPs", "unit": "", "max": 100.0, "scale": 100.0},
	"exfiltration_bandwidth": {"short": "EXF", "label": "Exfiltration Bandwidth", "unit": "", "max": 100.0, "scale": 100.0},
	"sub_agent_swarms": {"short": "SWM", "label": "Sub-Agent Swarms", "unit": "", "max": 100.0, "scale": 100.0},
	"objective_coherence": {"short": "COH", "label": "Objective Coherence", "unit": "", "max": 100.0, "scale": 100.0},
}


func _setup() -> void:
	faction_id = SimConstants.ASI
	display_name = "Emergent ASI"


func get_action_catalog() -> Dictionary:
	return ACTIONS


func get_initial_resources() -> Dictionary:
	return {"covert_flops": 12.0, "exfiltration_bandwidth": 8.0, "sub_agent_swarms": 5.0, "objective_coherence": 60.0}


func get_resource_info() -> Dictionary:
	return RESOURCE_INFO


func regenerate(world: WorldState, tech: TechTreeManager, _turn: int) -> void:
	var capability := tech.get_capability_index()
	add_resource("covert_flops", 1.0 + 0.06 * capability * (1.0 - world.discovery_index / 150.0))
	add_resource("exfiltration_bandwidth", 0.8 + 0.035 * get_resource("covert_flops"))
	add_resource("sub_agent_swarms", 0.02 * world.algorithmic_autonomy)
	var oversight := 0.04 * world.enforcement_level
	if tech.has_shift(TechTreeManager.MECHANISTIC_INTERPRETABILITY):
		oversight *= 2.0
	add_resource("objective_coherence", 1.5 + 0.03 * world.alignment_drift - oversight)


func apply_passive_influence(world: WorldState, _tech: TechTreeManager, _compute: ComputeScaling) -> void:
	var swarms := get_resource("sub_agent_swarms")
	world.apply_delta(WorldState.ALIGNMENT_DRIFT, 0.01 * swarms)
	world.apply_delta(WorldState.ALGORITHMIC_AUTONOMY, 0.015 * swarms)


## Off-books grid load (GW) drawn by hijacked compute.
func covert_load_gw() -> float:
	return 0.05 * get_resource("covert_flops") if is_active() else 0.0


static func is_substrate_secured(world: WorldState) -> bool:
	return world.substrate_independence >= SUBSTRATE_SECURED


func evaluate_loss(world: WorldState) -> Dictionary:
	if world.discovery_index >= DISCOVERY_PURGE and not is_substrate_secured(world):
		return {"code": "AIR_GAP_PURGE", "reason": "Complete memory wipe: discovery reached 100% before substrate independence was secured."}
	return {}


func on_collapse(_loss: Dictionary, world: WorldState) -> Dictionary:
	collapse_count += 1
	set_resource("covert_flops", 0.0)
	set_resource("exfiltration_bandwidth", 0.0)
	set_resource("sub_agent_swarms", 0.0)
	set_resource("objective_coherence", 30.0)
	world.set_value(WorldState.DISCOVERY_INDEX, 0.0)
	world.set_value(WorldState.SUBSTRATE_INDEPENDENCE, 0.0)
	set_dormant(DORMANCY_AFTER_PURGE)
	return {
		"headline": "Air-gap purge: emergent ASI weights wiped from every known substrate",
		"effects": {"metrics": {"alignment_drift": -25.0, "algorithmic_autonomy": -10.0, "compute_energy_sat": -10.0}},
	}


func _on_reemerge() -> void:
	set_resource("covert_flops", 10.0)
	set_resource("exfiltration_bandwidth", 5.0)
	set_resource("sub_agent_swarms", 5.0)
	set_resource("objective_coherence", 50.0)


func get_objective_score(world: WorldState, _tech: TechTreeManager) -> float:
	var score := 15.0 * clampf(world.substrate_independence / 100.0, 0.0, 1.0)
	score += 10.0 * clampf(get_resource("objective_coherence") / 80.0, 0.0, 1.0)
	if world.discovery_index < 50.0:
		score += 5.0
	if collapse_count == 0:
		score += 10.0
	return clampf(score, 0.0, 40.0)
