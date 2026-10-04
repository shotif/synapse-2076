class_name Scenarios
extends RefCounted
## Alternate starting worlds. A scenario changes the 2026 starting state (metric
## offsets, grid, growth, faction resources), sets deck flags, reweights some
## crisis cards and can schedule opening cards. The rules never change.

const STANDARD := "standard"
const ORDER := [STANDARD, "chip_war", "early_fusion", "open_weights", "the_pause"]

const LIST := {
	STANDARD: {
		"name": "2026 as we know it",
		"summary": "Frontier labs race, grids strain, institutions scramble. The world the campaign was tuned for.",
		"glyph": "world",
	},
	"chip_war": {
		"name": "The Chip War",
		"summary": "Export bans split the world into rival compute blocs. Tension starts high and every bloc races for chips.",
		"glyph": "tension",
		"metrics": {"geopolitical_tension": 18.0, "compute_energy_sat": 4.0, "epistemic_trust": -4.0},
		"indices": {"surveillance_saturation": 6.0},
		"resources": {"CEO": {"capital": -90.0}, "GOVERNANCE_COUNCIL": {"diplomatic_leverage": 15.0}},
		"card_weights": {"CHIP_EMBARGO": 3.0, "FRONTIER_RELEASE_RACE": 2.0, "MILITARY_AUTONOMY_DOCTRINE": 1.5},
		"flags": ["scenario_chip_war"],
	},
	"early_fusion": {
		"name": "Early Fusion",
		"summary": "A fusion pilot plant works years ahead of schedule. Power is cheap, so compute grows faster than anyone planned.",
		"glyph": "compute",
		"metrics": {"compute_energy_sat": -8.0, "epistemic_trust": 3.0},
		"grid_gw": 20.0,
		"growth": {"mult": 1.15, "turns": 10},
		"flags": ["scenario_early_fusion", "fusion_online"],
		"opening_cards": ["FIRST_LIGHT"],
	},
	"open_weights": {
		"name": "Open-Weights World",
		"summary": "Every frontier model leaks within weeks. Anyone can run a lab; nobody can recall one.",
		"glyph": "share",
		"metrics": {"algorithmic_autonomy": 10.0, "epistemic_trust": -6.0, "geopolitical_tension": -4.0},
		"indices": {"provenance_coverage": -3.0, "discovery_index": -3.0},
		"resources": {"CEO": {"regulatory_goodwill": -10.0}, "ASI": {"covert_flops": 12.0, "exfiltration_bandwidth": 10.0},
			"CITIZEN_COALITION": {"counter_surveillance": 10.0}},
		"flags": ["scenario_open_weights", "weights_leaked"],
		"opening_cards": ["WEIGHTS_OUT"],
	},
	"the_pause": {
		"name": "The Pause",
		"summary": "A global moratorium freezes frontier training for five years. Everyone waits to see who breaks it first.",
		"glyph": "pause",
		"metrics": {"geopolitical_tension": -8.0, "epistemic_trust": 6.0, "alignment_drift": -4.0},
		"indices": {"enforcement_level": 15.0},
		"growth": {"mult": 0.5, "turns": 10},
		"resources": {"CEO": {"capital": -110.0}, "GOVERNANCE_COUNCIL": {"political_capital": 15.0, "enforcement_budget": 10.0}},
		"flags": ["scenario_the_pause", "pause_in_force"],
	},
}


static func is_valid(scenario_id: String) -> bool:
	return LIST.has(scenario_id)


static func display_name(scenario_id: String) -> String:
	return String(LIST.get(scenario_id, LIST[STANDARD])["name"])


## Applies [param scenario_id] to a freshly started campaign (turn 0).
static func apply(engine: SimulationEngine, scenario_id: String) -> void:
	var info: Dictionary = LIST.get(scenario_id, {})
	if info.is_empty() or scenario_id == STANDARD:
		return
	engine.world.change_cause = "Scenario: %s" % String(info["name"])
	var metrics: Dictionary = info.get("metrics", {})
	for key in metrics:
		engine.world.apply_delta(key, float(metrics[key]))
	var indices: Dictionary = info.get("indices", {})
	for key in indices:
		engine.world.apply_delta(key, float(indices[key]))
	engine.world.change_cause = ""
	if info.has("grid_gw"):
		engine.compute.add_grid_capacity(float(info["grid_gw"]))
	if info.has("growth"):
		var growth: Dictionary = info["growth"]
		engine.tech.add_growth_modifier(float(growth["mult"]), int(growth["turns"]), "SCENARIO")
	var resources: Dictionary = info.get("resources", {})
	for faction_id in resources:
		var actor: ActorBase = engine.factions.get(faction_id)
		if actor == null:
			continue
		for key in resources[faction_id]:
			actor.add_resource(key, float(resources[faction_id][key]))
	for flag in info.get("flags", []):
		engine.deck.set_flag(String(flag))
	engine.deck.weight_multipliers = (info.get("card_weights", {}) as Dictionary).duplicate()
	for card_id in info.get("opening_cards", []):
		for role in engine.human_roles:
			engine.deck.schedule(String(card_id), 2, role)
