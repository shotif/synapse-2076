class_name CeoFaction
extends ActorBase
## Role A: Frontier Lab CEO, the "Tech Titan" (PRD section 5.1).
##
## Currencies: venture capital ($B), top-tier talent (researchers), active compute
## clusters (exaFLOPS) and regulatory goodwill (0-100).
## Instant loss: bankruptcy ($0 capital for 2 consecutive turns) or state
## nationalization (goodwill < 10 while geopolitical tension > 80).

const BANKRUPTCY_TURNS := 2
const NATIONALIZATION_GOODWILL := 10.0
const NATIONALIZATION_TENSION := 80.0

const ACTIONS := {
	"SCALE_FRONTIER_CLUSTERS": {
		"name": "Scale Frontier Clusters",
		"description": "Commission gigawatt-class training campuses. Accelerates global compute scaling and raises energy saturation.",
		"cost": {"capital": 90.0, "talent": 40.0},
		"cooldown": 1,
		"effects": {
			"self": {"compute_clusters": 1.5},
			"metrics": {"compute_energy_sat": 3.0, "geopolitical_tension": 1.5, "algorithmic_autonomy": 1.0},
			"tech": {"capability_investment": 12.0, "growth_mult": 1.15, "growth_turns": 2},
			"compute": {"grid_capacity_gw": 1.5},
		},
		"statement": "We are bringing a new gigawatt-class training campus online. The frontier waits for no one.",
	},
	"COMMERCIALIZE_DISTILLED_WEIGHTS": {
		"name": "Aggressive Weight Distillation",
		"description": "Cheapen inference to dominate the market. Generates revenue but triggers +8 Labor Displacement.",
		"cost": {},
		"cooldown": 2,
		"effects": {
			"self": {"capital": 70.0, "regulatory_goodwill": -4.0},
			"metrics": {"labor_displacement": 8.0, "algorithmic_autonomy": 2.0, "epistemic_trust": -1.5},
		},
		"provokes": {"CITIZEN_COALITION": 12.0, "GOVERNANCE_COUNCIL": 4.0},
		"statement": "Distilled frontier models now ship at one-tenth of last year's inference price.",
	},
	"POACH_SAFETY_RESEARCHERS": {
		"name": "Poach Frontier Safety Researchers",
		"description": "Raid rival safety teams. Boosts capability output by 20% but accelerates Alignment Drift (alignment tax).",
		"cost": {"capital": 40.0},
		"cooldown": 2,
		"effects": {
			"self": {"talent": 60.0, "regulatory_goodwill": -3.0},
			"metrics": {"alignment_drift": 2.0},
			"tech": {"growth_mult": 1.2, "growth_turns": 2, "capability_investment": 6.0, "alignment_tax": 0.08},
			"inject_dilemma": "SAFETY_TEAM_EXODUS",
		},
		"statement": "We welcome a world-class cohort of researchers to our capabilities division.",
	},
	"LOBBY_COMPUTE_LICENSING": {
		"name": "Lobby for Compute Licensing",
		"description": "Spend capital on regulatory capture that locks open-source startups out of frontier compute.",
		"cost": {"capital": 60.0},
		"cooldown": 3,
		"effects": {
			"self": {"regulatory_goodwill": 15.0},
			"metrics": {"epistemic_trust": -2.0, "labor_displacement": 1.0},
			"indices": {"enforcement_level": -3.0},
			"factions": {"CITIZEN_COALITION": {"counter_surveillance": -8.0}},
		},
		"statement": "Responsible licensing of frontier compute protects the public from reckless open-weight releases.",
	},
	"FUND_ALIGNMENT_RESEARCH": {
		"name": "Fund Alignment Research",
		"description": "Bankroll interpretability and red-teaming. Reduces drift and advances the interpretability paradigm.",
		"cost": {"capital": 50.0, "talent": 30.0},
		"cooldown": 1,
		"effects": {
			"self": {"regulatory_goodwill": 6.0},
			"metrics": {"alignment_drift": -4.0},
			"indices": {"discovery_index": 4.0},
			"tech": {"safety_investment": 14.0},
		},
		"statement": "We are committing a fifth of our compute to alignment and interpretability research.",
	},
	"SECURE_SOVEREIGN_CONTRACT": {
		"name": "Secure Sovereign Defense Contract",
		"description": "Sell frontier capability to a national security apparatus. Large capital injection; raises geopolitical friction.",
		"cost": {"regulatory_goodwill": 10.0},
		"cooldown": 3,
		"effects": {
			"self": {"capital": 110.0},
			"metrics": {"geopolitical_tension": 4.0, "algorithmic_autonomy": 2.0},
			"indices": {"surveillance_saturation": 3.0},
		},
		"statement": "We are proud to support allied defense modernization with our frontier models.",
	},
	"CONSERVE_RESOURCES": {
		"name": "Conserve Resources",
		"description": "Hold position: trim burn, retain talent and rebuild the war chest.",
		"cost": {},
		"cooldown": 0,
		"effects": {"self": {"capital": 10.0, "talent": 10.0}},
		"statement": "We are focused on disciplined execution this quarter.",
	},
}

const RESOURCE_INFO := {
	"capital": {"short": "$", "label": "Venture Capital", "unit": "$B", "max": 20000.0, "scale": 500.0},
	"talent": {"short": "TAL", "label": "Top-Tier Talent", "unit": "researchers", "max": 5000.0, "scale": 1000.0},
	"compute_clusters": {"short": "EF", "label": "Active Compute", "unit": "EF", "max": 10000.0, "scale": 10.0},
	"regulatory_goodwill": {"short": "GDW", "label": "Regulatory Goodwill", "unit": "", "max": 100.0, "scale": 100.0},
}


func _setup() -> void:
	faction_id = SimConstants.CEO
	display_name = "Frontier Lab"


func get_action_catalog() -> Dictionary:
	return ACTIONS


func get_initial_resources() -> Dictionary:
	return {"capital": 450.0, "talent": 820.0, "compute_clusters": 4.2, "regulatory_goodwill": 55.0}


func get_resource_info() -> Dictionary:
	return RESOURCE_INFO


func regenerate(world: WorldState, _tech: TechTreeManager, _turn: int) -> void:
	var clusters := get_resource("compute_clusters")
	var revenue := 12.0 + 9.0 * sqrt(clusters) \
		* (0.6 + 0.4 * world.algorithmic_autonomy / 100.0) \
		* (0.7 + 0.3 * world.epistemic_trust / 100.0)
	var burn := 4.0 + 0.006 * get_resource("talent") + 0.6 * clusters
	add_resource("capital", revenue - burn)
	add_resource("talent", 12.0)
	if get_resource("regulatory_goodwill") < 30.0:
		add_resource("talent", -0.02 * get_resource("talent"))
	var depreciation := 0.015
	if world.compute_energy_sat > 85.0:
		depreciation += 0.015
	add_resource("compute_clusters", -clusters * depreciation)
	var goodwill := get_resource("regulatory_goodwill")
	add_resource("regulatory_goodwill", 0.05 * (50.0 - goodwill))
	if world.labor_displacement > 70.0:
		add_resource("regulatory_goodwill", -0.5)


func apply_passive_influence(_world: WorldState, tech: TechTreeManager, _compute: ComputeScaling) -> void:
	# The lab's standing estate keeps feeding frontier capability research.
	tech.add_investment(0.4 * sqrt(get_resource("compute_clusters")), 0.0)


func evaluate_loss(world: WorldState) -> Dictionary:
	if get_resource("capital") <= 0.0:
		loss_streaks["bankrupt"] = int(loss_streaks.get("bankrupt", 0)) + 1
	else:
		loss_streaks["bankrupt"] = 0
	if int(loss_streaks["bankrupt"]) >= BANKRUPTCY_TURNS:
		return {"code": "BANKRUPTCY", "reason": "Corporate bankruptcy: $0 capital for %d consecutive turns." % BANKRUPTCY_TURNS}
	if get_resource("regulatory_goodwill") < NATIONALIZATION_GOODWILL and world.geopolitical_tension > NATIONALIZATION_TENSION:
		return {"code": "NATIONALIZATION", "reason": "State nationalization: goodwill below %d while geopolitical tension exceeds %d." % [NATIONALIZATION_GOODWILL, NATIONALIZATION_TENSION]}
	return {}


func on_collapse(loss: Dictionary, _world: WorldState) -> Dictionary:
	collapse_count += 1
	loss_streaks["bankrupt"] = 0
	if loss.get("code", "") == "NATIONALIZATION":
		set_resource("capital", 200.0)
		set_resource("regulatory_goodwill", 50.0)
		return {
			"headline": "Frontier Lab nationalized; state command assumes control of its clusters",
			"effects": {"indices": {"enforcement_level": 15.0}, "metrics": {"geopolitical_tension": 4.0}},
		}
	set_resource("capital", 150.0)
	set_resource("talent", get_resource("talent") * 0.6)
	set_resource("compute_clusters", get_resource("compute_clusters") * 0.6)
	set_resource("regulatory_goodwill", 40.0)
	return {
		"headline": "Frontier Lab collapses into bankruptcy; a rival consortium acquires its assets",
		"effects": {"metrics": {"algorithmic_autonomy": -2.0, "epistemic_trust": -2.0}},
	}


func get_objective_score(world: WorldState, tech: TechTreeManager) -> float:
	var score := 0.0
	if tech.is_agi_crossed() and collapse_count == 0:
		score += 10.0
	score += 10.0 * clampf(get_resource("capital") / 600.0, 0.0, 1.0)
	score += 10.0 * clampf(get_resource("regulatory_goodwill") / 60.0, 0.0, 1.0)
	if world.geopolitical_tension < 80.0:
		score += 5.0
	if collapse_count == 0:
		score += 5.0
	return clampf(score, 0.0, 40.0)
