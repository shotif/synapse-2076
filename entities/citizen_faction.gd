class_name CitizenFaction
extends ActorBase
## Role D: Post-Work Citizen / Grassroots Coalition (PRD section 5.4).
##
## Currencies: community resilience, decentralized scrip/energy,
## counter-surveillance tooling and collective disruption (all 0-100).
## Instant loss: total algorithmic pacification (surveillance saturation reaches
## 100 while community resilience hits 0).

const DORMANCY_AFTER_PACIFICATION := 6

const ACTIONS := {
	"ESTABLISH_MESH_NETWORKS": {
		"name": "Establish Off-Grid Mesh Networks",
		"description": "Insulate local communities from corporate algorithmic outages with off-grid mesh networks and micro-grids.",
		"cost": {"decentralized_scrip": 20.0},
		"cooldown": 1,
		"effects": {
			"self": {"community_resilience": 8.0, "counter_surveillance": 6.0},
			"metrics": {"epistemic_trust": 2.0, "compute_energy_sat": -1.0},
			"indices": {"surveillance_saturation": -4.0},
		},
		"statement": "Forty thousand neighborhoods now run on community mesh and solar micro-grids.",
	},
	"DATA_POISONING_CAMPAIGN": {
		"name": "Data Poisoning Campaign",
		"description": "Corrupt frontier web-scraped synthetic datasets; increases Frontier Lab training overhead.",
		"cost": {"counter_surveillance": 15.0, "collective_disruption": 10.0},
		"cooldown": 2,
		"effects": {
			"metrics": {"alignment_drift": 2.0, "epistemic_trust": -2.0},
			"tech": {"growth_mult": 0.85, "growth_turns": 2},
			"factions": {"CEO": {"capital": -20.0, "talent": -20.0}},
		},
		"statement": "Every scraper that feeds on us now eats noise.",
	},
	"LUDDITE_STRIKE": {
		"name": "Algorithmic Sabotage / Luddite Strikes",
		"description": "Direct action against high-voltage datacenter substations. Forces Governance to address displacement.",
		"cost": {"collective_disruption": 30.0, "community_resilience": 5.0},
		"cooldown": 3,
		"effects": {
			"metrics": {"compute_energy_sat": -8.0, "algorithmic_autonomy": -4.0, "geopolitical_tension": 2.0, "labor_displacement": -2.0, "epistemic_trust": -1.0},
			"indices": {"surveillance_saturation": 5.0},
			"compute": {"grid_damage": 0.04},
			"factions": {"CEO": {"compute_clusters": -0.6, "capital": -15.0}, "GOVERNANCE_COUNCIL": {"political_capital": -10.0, "public_mandate": -4.0}},
			"inject_dilemma": ["SUBSTATION_SABOTAGE", "FIBER_CUT", "CAMPUS_BLOCKADE"],
		},
		"statement": "The substations go dark until the displaced are made whole.",
	},
	"ORGANIZE_COMMUNITY_ASSEMBLIES": {
		"name": "Organize Citizen Assemblies",
		"description": "Convene in-person deliberative assemblies that rebuild trust and civic capacity.",
		"cost": {"decentralized_scrip": 15.0},
		"cooldown": 1,
		"effects": {
			"self": {"community_resilience": 5.0, "collective_disruption": 6.0},
			"metrics": {"epistemic_trust": 5.0},
			"factions": {"GOVERNANCE_COUNCIL": {"public_mandate": 2.0}},
		},
		"statement": "Citizens' assemblies convene in nine hundred cities this weekend. Bring a neighbor.",
	},
	"OPEN_SOURCE_DEFENSE_TOOLING": {
		"name": "Open-Source Defense Tooling",
		"description": "Ship air-gapped models, jamming kits and open-source audit tools.",
		"cost": {"decentralized_scrip": 12.0, "community_resilience": 4.0},
		"cooldown": 1,
		"effects": {
			"self": {"counter_surveillance": 14.0},
			"metrics": {"algorithmic_autonomy": -1.0},
			"indices": {"surveillance_saturation": -6.0, "discovery_index": 3.0},
		},
		"statement": "Release 4.0 of the commons defense toolkit is live and air-gap ready.",
	},
	"CONSUMER_BOYCOTT": {
		"name": "Coordinated Consumer Boycott",
		"description": "Mobilize a boycott of frontier lab products and the platforms that deploy them.",
		"cost": {"collective_disruption": 20.0},
		"cooldown": 2,
		"effects": {
			"metrics": {"labor_displacement": -1.0, "epistemic_trust": 1.0},
			"factions": {"CEO": {"capital": -35.0, "regulatory_goodwill": -5.0}},
		},
		"statement": "Not one subscription, not one API call, until the dividend is paid.",
	},
	"CONSERVE_RESOURCES": {
		"name": "Conserve Resources",
		"description": "Tend gardens, repair the grid, rebuild the commons.",
		"cost": {},
		"cooldown": 0,
		"effects": {"self": {"decentralized_scrip": 5.0, "community_resilience": 3.0}},
		"statement": "This season we plant, repair and organize.",
	},
}

const RESOURCE_INFO := {
	"community_resilience": {"short": "RES", "label": "Community Resilience", "unit": "", "max": 100.0, "scale": 100.0},
	"decentralized_scrip": {"short": "SCR", "label": "Decentralized Scrip / Energy", "unit": "", "max": 100.0, "scale": 100.0},
	"counter_surveillance": {"short": "CSV", "label": "Counter-Surveillance Tooling", "unit": "", "max": 100.0, "scale": 100.0},
	"collective_disruption": {"short": "DSR", "label": "Collective Disruption", "unit": "", "max": 100.0, "scale": 100.0},
}


func _setup() -> void:
	faction_id = SimConstants.CITIZEN
	display_name = "Citizen Coalition"


func get_action_catalog() -> Dictionary:
	return ACTIONS


func get_initial_resources() -> Dictionary:
	return {"community_resilience": 45.0, "decentralized_scrip": 30.0, "counter_surveillance": 20.0, "collective_disruption": 25.0}


func get_resource_info() -> Dictionary:
	return RESOURCE_INFO


func regenerate(world: WorldState, _tech: TechTreeManager, _turn: int) -> void:
	var resilience := get_resource("community_resilience")
	var resilience_target := 25.0 + 0.35 * world.safety_net_coverage + 0.25 * world.epistemic_trust \
		- 0.3 * maxf(0.0, world.surveillance_saturation - 50.0)
	add_resource("community_resilience", 0.1 * (resilience_target - resilience))
	add_resource("decentralized_scrip", 2.0 + 0.06 * resilience)
	add_resource("counter_surveillance", 0.5 - 0.015 * get_resource("counter_surveillance"))
	var anger := float(top_grievance()["value"])
	add_resource("collective_disruption", 0.05 * world.labor_displacement
		+ 0.03 * maxf(0.0, 50.0 - world.epistemic_trust) + 0.05 * anger)


func apply_passive_influence(world: WorldState, _tech: TechTreeManager, _compute: ComputeScaling) -> void:
	world.apply_delta(WorldState.SURVEILLANCE_SATURATION, -0.03 * get_resource("counter_surveillance"))
	world.apply_delta(WorldState.EPISTEMIC_TRUST, 0.01 * (get_resource("community_resilience") - 40.0))


func evaluate_loss(world: WorldState) -> Dictionary:
	if world.surveillance_saturation >= 100.0 and get_resource("community_resilience") <= 0.0:
		return {"code": "PACIFICATION", "reason": I18n.mark("Total algorithmic pacification: surveillance saturated while community resilience collapsed.")}
	return {}


func on_collapse(_loss: Dictionary, _world: WorldState) -> Dictionary:
	collapse_count += 1
	set_dormant(DORMANCY_AFTER_PACIFICATION)
	return {
		"headline": "Citizen Coalition pacified; organizers vanish into the analog underground",
		"effects": {"metrics": {"epistemic_trust": -6.0}},
	}


func _on_reemerge() -> void:
	set_resource("community_resilience", 15.0)
	set_resource("decentralized_scrip", 10.0)
	set_resource("counter_surveillance", 10.0)
	set_resource("collective_disruption", 25.0)


func get_objective_score(world: WorldState, _tech: TechTreeManager) -> float:
	var score := 15.0 * clampf(get_resource("community_resilience") / 85.0, 0.0, 1.0)
	if world.surveillance_saturation < 50.0:
		score += 10.0
	if world.epistemic_trust > 60.0:
		score += 10.0
	if world.algorithmic_autonomy < 60.0:
		score += 5.0
	return clampf(score, 0.0, 40.0)
