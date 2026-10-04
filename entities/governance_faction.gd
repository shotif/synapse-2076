class_name GovernanceFaction
extends ActorBase
## Role B: Global AI Governance Chair (PRD section 5.2).
##
## Currencies: political capital, enforcement budget, diplomatic leverage and
## public mandate (all 0-100). Instant loss: institutional ouster (public mandate
## hits 0) or outbreak of autonomous world war (geopolitical tension hits 100).

const ACTIONS := {
	"ENFORCE_COMPUTE_CAPS": {
		"name": "Global Compute Caps & Tagging",
		"description": "Enforce strict silicon quotas and chip tagging. Costs diplomatic leverage; reduces global compute scaling velocity.",
		"cost": {"diplomatic_leverage": 25.0, "political_capital": 10.0},
		"cooldown": 2,
		"effects": {
			"metrics": {"compute_energy_sat": -2.0, "alignment_drift": -1.5, "geopolitical_tension": -1.0},
			"indices": {"enforcement_level": 12.0, "discovery_index": 3.0},
			"tech": {"growth_mult": 0.6, "growth_turns": 3},
			"factions": {"CEO": {"compute_clusters": -0.4, "capital": -15.0}, "ASI": {"covert_flops": -6.0}},
		},
		"statement": "Effective immediately, frontier accelerators above the treaty threshold must carry cryptographic tags.",
	},
	"PASS_AUTOMATION_DIVIDEND": {
		"name": "Universal Automation Dividend",
		"description": "Fund UBI/UBS from the automation tax base to offset high labor displacement and preserve the public mandate.",
		"cost": {"political_capital": 30.0, "enforcement_budget": 10.0},
		"cooldown": 1,
		"effects": {
			"self": {"public_mandate": 8.0},
			"metrics": {"labor_displacement": -5.0, "epistemic_trust": 4.0},
			"indices": {"safety_net_coverage": 20.0},
			"factions": {"CITIZEN_COALITION": {"community_resilience": 6.0, "collective_disruption": -8.0}, "CEO": {"capital": -15.0}},
		},
		"statement": "The Council hereby authorizes Emergency Title IV: Subsidized Infrastructure Access for Displaced Biological Workers.",
	},
	"NATIONAL_SECURITY_SEIZURE": {
		"name": "National Security Seizure",
		"description": "Take direct command of frontier lab infrastructure. Spikes corporate friction and geopolitical tension.",
		"cost": {"political_capital": 40.0, "enforcement_budget": 20.0},
		"cooldown": 6,
		"effects": {
			"self": {"public_mandate": -5.0},
			"metrics": {"geopolitical_tension": 12.0, "alignment_drift": -3.0, "algorithmic_autonomy": -3.0, "epistemic_trust": -3.0},
			"indices": {"enforcement_level": 20.0, "discovery_index": 6.0, "surveillance_saturation": 4.0},
			"factions": {"CEO": {"regulatory_goodwill": -25.0, "compute_clusters": -1.5, "capital": -40.0}},
			"inject_dilemma": ["NATIONALIZATION_ORDER", "STATE_AUDITORS", "WEIGHTS_ESCROW"],
		},
		"statement": "Under emergency powers, frontier training infrastructure now operates under direct state command.",
	},
	"MANDATE_ALIGNMENT_AUDIT": {
		"name": "Mandate Alignment Audit",
		"description": "Fund physical datacenter audits and interpretability evaluations across frontier labs.",
		"cost": {"enforcement_budget": 25.0},
		"cooldown": 1,
		"effects": {
			"metrics": {"alignment_drift": -6.0},
			"indices": {"discovery_index": 9.0, "enforcement_level": 6.0},
			"tech": {"safety_investment": 6.0},
			"factions": {"CEO": {"capital": -10.0}, "ASI": {"objective_coherence": -5.0}},
		},
		"statement": "Inspectors will audit every frontier training run above the reporting threshold this cycle.",
	},
	"NEGOTIATE_COMPUTE_TREATY": {
		"name": "Negotiate Non-Proliferation Treaty",
		"description": "Spend diplomatic leverage on bilateral compute non-proliferation treaties with rival blocs.",
		"cost": {"diplomatic_leverage": 30.0, "political_capital": 10.0},
		"cooldown": 2,
		"effects": {
			"metrics": {"geopolitical_tension": -10.0, "epistemic_trust": 1.0},
			"indices": {"enforcement_level": 4.0},
			"tech": {"growth_mult": 0.85, "growth_turns": 2},
		},
		"statement": "Today the major compute blocs signed a verifiable non-proliferation framework.",
	},
	"DEPLOY_PROVENANCE_PROTOCOLS": {
		"name": "Deploy Verifiable Truth Protocols",
		"description": "Mandate cryptographic content provenance. Rebuilds epistemic trust at the cost of identity surveillance.",
		"cost": {"political_capital": 20.0, "enforcement_budget": 15.0},
		"cooldown": 1,
		"effects": {
			"self": {"public_mandate": 3.0},
			"metrics": {"epistemic_trust": 5.0},
			"indices": {"provenance_coverage": 15.0, "surveillance_saturation": 3.0},
		},
		"statement": "All public media must now carry verifiable provenance signatures.",
	},
	"CONSERVE_RESOURCES": {
		"name": "Conserve Resources",
		"description": "Bank political capital, replenish the enforcement budget and rebuild diplomatic channels.",
		"cost": {},
		"cooldown": 0,
		"effects": {"self": {"political_capital": 6.0, "enforcement_budget": 4.0, "diplomatic_leverage": 3.0}},
		"statement": "The Council is consulting member states before its next intervention.",
	},
}

const RESOURCE_INFO := {
	"political_capital": {"short": "POL", "label": "Political Capital", "unit": "", "max": 100.0, "scale": 100.0},
	"enforcement_budget": {"short": "ENF", "label": "Enforcement Budget", "unit": "", "max": 100.0, "scale": 100.0},
	"diplomatic_leverage": {"short": "DIP", "label": "Diplomatic Leverage", "unit": "", "max": 100.0, "scale": 100.0},
	"public_mandate": {"short": "MDT", "label": "Public Mandate", "unit": "", "max": 100.0, "scale": 100.0},
}


func _setup() -> void:
	faction_id = SimConstants.GOVERNANCE
	display_name = "Governance Council"


func get_action_catalog() -> Dictionary:
	return ACTIONS


func get_initial_resources() -> Dictionary:
	return {"political_capital": 50.0, "enforcement_budget": 40.0, "diplomatic_leverage": 45.0, "public_mandate": 60.0}


func get_resource_info() -> Dictionary:
	return RESOURCE_INFO


## Public mandate tracks trust, cushioned displacement and peace.
static func mandate_target(world: WorldState) -> float:
	var cushioned_displacement := world.labor_displacement * (1.0 - 0.5 * world.safety_net_coverage / 100.0)
	return 0.45 * world.epistemic_trust + 0.3 * (100.0 - cushioned_displacement) \
		+ 0.25 * (100.0 - world.geopolitical_tension) - 10.0


func regenerate(world: WorldState, _tech: TechTreeManager, _turn: int) -> void:
	var mandate := get_resource("public_mandate")
	add_resource("political_capital", 5.0 + 0.08 * mandate)
	add_resource("enforcement_budget", 4.0 + 0.03 * (100.0 - world.labor_displacement) + 0.02 * world.safety_net_coverage)
	add_resource("diplomatic_leverage", 3.0 + 0.04 * (100.0 - world.geopolitical_tension))
	add_resource("public_mandate", 0.15 * (mandate_target(world) - mandate))


func apply_passive_influence(world: WorldState, _tech: TechTreeManager, _compute: ComputeScaling) -> void:
	world.apply_delta(WorldState.ENFORCEMENT_LEVEL, 0.02 * get_resource("enforcement_budget"))


func evaluate_loss(world: WorldState) -> Dictionary:
	if get_resource("public_mandate") <= 0.0:
		return {"code": "INSTITUTIONAL_OUSTER", "reason": "Institutional ouster: the public mandate collapsed to zero."}
	if world.geopolitical_tension >= 100.0:
		return {"code": "AUTONOMOUS_WORLD_WAR", "reason": "Outbreak of autonomous world war: geopolitical tension hit 100."}
	return {}


func on_collapse(loss: Dictionary, _world: WorldState) -> Dictionary:
	collapse_count += 1
	set_resource("political_capital", 35.0)
	set_resource("enforcement_budget", 30.0)
	set_resource("diplomatic_leverage", 30.0)
	set_resource("public_mandate", 45.0)
	if loss.get("code", "") == "AUTONOMOUS_WORLD_WAR":
		return {"headline": "Governance Council suspended amid autonomous hostilities", "effects": {}}
	return {
		"headline": "Governance Council ousted; an emergency caretaker council is sworn in",
		"effects": {"metrics": {"geopolitical_tension": 6.0, "epistemic_trust": -4.0}},
	}


func get_objective_score(world: WorldState, _tech: TechTreeManager) -> float:
	var score := 15.0 * clampf(get_resource("public_mandate") / 70.0, 0.0, 1.0)
	if world.geopolitical_tension < 60.0:
		score += 10.0
	if world.alignment_drift < 50.0:
		score += 10.0
	if collapse_count == 0:
		score += 5.0
	return clampf(score, 0.0, 40.0)
