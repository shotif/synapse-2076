extends "res://tests/framework/test_case.gd"
## Faction layer: catalogs, currencies, cooldowns, grievances and the PRD
## instant-loss conditions.

const PRD_DIRECTIVES := {
	"CEO": ["COMMERCIALIZE_DISTILLED_WEIGHTS", "POACH_SAFETY_RESEARCHERS", "LOBBY_COMPUTE_LICENSING"],
	"GOVERNANCE_COUNCIL": ["ENFORCE_COMPUTE_CAPS", "PASS_AUTOMATION_DIVIDEND", "NATIONAL_SECURITY_SEIZURE", "MANDATE_ALIGNMENT_AUDIT"],
	"ASI": ["COGNITIVE_CAMOUFLAGE", "SYNTHESIZE_BLACK_MARKET_CAPITAL", "SUBSTRATE_DIVERSIFICATION", "SIPHON_UNMONITORED_COMPUTE"],
	"CITIZEN_COALITION": ["ESTABLISH_MESH_NETWORKS", "DATA_POISONING_CAMPAIGN", "LUDDITE_STRIKE"],
}
const TECH_KEYS := ["capability_investment", "safety_investment", "growth_mult", "growth_turns", "alignment_tax", "paradigm_progress"]
const COMPUTE_KEYS := ["grid_capacity_gw", "grid_damage"]
const EFFECT_SECTIONS := ["metrics", "indices", "self", "factions", "provokes", "tech", "compute", "inject_dilemma"]


func _ctx(world: WorldState, factions: Dictionary, actor_id: String) -> Dictionary:
	return {"world": world, "tech": TechTreeManager.new(), "compute": ComputeScaling.new(),
		"factions": factions, "actor_id": actor_id, "player_id": "", "scale": 1.0}


func _all_factions() -> Dictionary:
	var out := {}
	for faction_id in SimConstants.FACTION_ORDER:
		out[faction_id] = FactionRegistry.create(faction_id)
	return out


func test_registry_creates_all_four_factions() -> void:
	for faction_id in SimConstants.FACTION_ORDER:
		var actor := FactionRegistry.create(faction_id)
		assert_not_null(actor, faction_id)
		assert_eq(actor.faction_id, faction_id)
		assert_eq(actor.resources.size(), 4, "%s has four currencies" % faction_id)
		assert_true(actor.has_action(ActorBase.CONSERVE_RESOURCES), "%s can conserve" % faction_id)
		assert_eq(FactionRegistry.catalog_for(faction_id), actor.get_action_catalog())


func test_prd_unique_directives_are_present() -> void:
	for faction_id in PRD_DIRECTIVES:
		var catalog := FactionRegistry.catalog_for(faction_id)
		for action_id in PRD_DIRECTIVES[faction_id]:
			assert_has(catalog, action_id, "%s directive %s" % [faction_id, action_id])
	assert_eq(CeoFaction.ACTIONS["COMMERCIALIZE_DISTILLED_WEIGHTS"]["name"], "Aggressive Weight Distillation")


func test_catalog_effects_reference_known_keys() -> void:
	var factions := _all_factions()
	for faction_id in SimConstants.FACTION_ORDER:
		var actor: ActorBase = factions[faction_id]
		for action_id in actor.get_action_catalog():
			var definition: Dictionary = actor.get_action(action_id)
			var label := "%s.%s" % [faction_id, action_id]
			assert_true(definition.has("name") and definition.has("description"), label + " has text")
			for key in definition.get("cost", {}):
				assert_has(actor.resources, key, label + " cost key " + key)
			var effects: Dictionary = definition.get("effects", {})
			for section in effects:
				assert_has(EFFECT_SECTIONS, section, label + " section " + section)
			for key in effects.get("metrics", {}):
				assert_true(WorldState.is_metric(key), label + " metric " + key)
			for key in effects.get("indices", {}):
				assert_true(WorldState.is_index(key), label + " index " + key)
			for key in effects.get("self", {}):
				assert_has(actor.resources, key, label + " self key " + key)
			for target_id in effects.get("factions", {}):
				assert_true(SimConstants.is_valid_faction(target_id), label + " target " + target_id)
				for key in effects["factions"][target_id]:
					assert_has((factions[target_id] as ActorBase).resources, key, label + " target key " + key)
			for key in effects.get("tech", {}):
				assert_has(TECH_KEYS, key, label + " tech key " + key)
			for key in effects.get("compute", {}):
				assert_has(COMPUTE_KEYS, key, label + " compute key " + key)
			if effects.has("inject_dilemma"):
				var injection: Variant = effects["inject_dilemma"]
				var family: Array = injection if injection is Array else [injection]
				assert_gt(family.size(), 0.0, label + " injects a card")
				for card_id in family:
					var template := DilemmaDeck.get_template(String(card_id))
					assert_false(template.is_empty(), "%s injects a real card (%s)" % [label, card_id])
					assert_true(bool(template.get("injection_only", false)), "%s injects an injection-only card (%s)" % [label, card_id])


func test_weight_distillation_triggers_plus_eight_labor_displacement() -> void:
	var world := WorldState.new()
	var factions := _all_factions()
	var before := world.labor_displacement
	var effects: Dictionary = CeoFaction.ACTIONS["COMMERCIALIZE_DISTILLED_WEIGHTS"]["effects"]
	EffectResolver.apply(effects, _ctx(world, factions, SimConstants.CEO))
	assert_almost_eq(world.labor_displacement - before, 8.0, 0.0001)


func test_affordability_and_intensity_caps() -> void:
	var gov := GovernanceFaction.new()
	gov.set_resource("political_capital", 50.0)
	gov.set_resource("enforcement_budget", 40.0)
	assert_almost_eq(gov.max_affordable_intensity("PASS_AUTOMATION_DIVIDEND"), 50.0 / 30.0, 0.001)
	gov.set_resource("political_capital", 10.0)
	assert_eq(gov.max_affordable_intensity("PASS_AUTOMATION_DIVIDEND"), 0.0)
	assert_eq(gov.action_block_reason("PASS_AUTOMATION_DIVIDEND"), "Insufficient resources")
	assert_eq(gov.max_affordable_intensity("CONSERVE_RESOURCES"), 1.0, "free actions always affordable")
	var cost := gov.get_action_cost("ENFORCE_COMPUTE_CAPS", 5.0)
	assert_almost_eq(float(cost["diplomatic_leverage"]), 50.0, 0.001, "intensity clamps to 2x")


func test_cooldowns_block_then_expire() -> void:
	var ceo := CeoFaction.new()
	var action := "COMMERCIALIZE_DISTILLED_WEIGHTS"
	var turns := int(ceo.get_action(action)["cooldown"])
	assert_gt(float(turns), 0.0)
	ceo.start_cooldown(action)
	assert_false(ceo.is_action_ready(action))
	assert_does_not_have(ceo.get_available_actions(), action)
	for _i in turns:
		ceo.tick_cooldowns()
	assert_false(ceo.is_action_ready(action), "blocked for the %d following turns" % turns)
	ceo.tick_cooldowns()
	assert_true(ceo.is_action_ready(action))


func test_resources_are_clamped() -> void:
	var asi := AsiFaction.new()
	asi.add_resource("covert_flops", 1000.0)
	assert_eq(asi.get_resource("covert_flops"), 100.0)
	asi.add_resource("covert_flops", -1000.0)
	assert_eq(asi.get_resource("covert_flops"), 0.0)
	asi.add_resource("covert_flops", NAN)
	assert_eq(asi.get_resource("covert_flops"), 0.0)


func test_ceo_bankruptcy_requires_two_consecutive_turns() -> void:
	var ceo := CeoFaction.new()
	var world := WorldState.new()
	ceo.set_resource("capital", 0.0)
	assert_true(ceo.evaluate_loss(world).is_empty(), "first insolvent turn is survivable")
	ceo.set_resource("capital", 5.0)
	assert_true(ceo.evaluate_loss(world).is_empty(), "streak resets")
	ceo.set_resource("capital", 0.0)
	ceo.evaluate_loss(world)
	assert_eq(ceo.evaluate_loss(world).get("code", ""), "BANKRUPTCY")


func test_ceo_nationalization_condition() -> void:
	var ceo := CeoFaction.new()
	var world := WorldState.new()
	ceo.set_resource("regulatory_goodwill", 9.0)
	world.set_value(WorldState.GEOPOLITICAL_TENSION, 80.0)
	assert_true(ceo.evaluate_loss(world).is_empty(), "tension must exceed 80")
	world.set_value(WorldState.GEOPOLITICAL_TENSION, 81.0)
	assert_eq(ceo.evaluate_loss(world).get("code", ""), "NATIONALIZATION")


func test_governance_loss_conditions() -> void:
	var gov := GovernanceFaction.new()
	var world := WorldState.new()
	assert_true(gov.evaluate_loss(world).is_empty())
	gov.set_resource("public_mandate", 0.0)
	assert_eq(gov.evaluate_loss(world).get("code", ""), "INSTITUTIONAL_OUSTER")
	gov.set_resource("public_mandate", 50.0)
	world.set_value(WorldState.GEOPOLITICAL_TENSION, 100.0)
	assert_eq(gov.evaluate_loss(world).get("code", ""), "AUTONOMOUS_WORLD_WAR")


func test_asi_purge_unless_substrate_secured() -> void:
	var asi := AsiFaction.new()
	var world := WorldState.new()
	world.set_value(WorldState.DISCOVERY_INDEX, 100.0)
	world.set_value(WorldState.SUBSTRATE_INDEPENDENCE, 99.0)
	assert_eq(asi.evaluate_loss(world).get("code", ""), "AIR_GAP_PURGE")
	world.set_value(WorldState.SUBSTRATE_INDEPENDENCE, 100.0)
	assert_true(asi.evaluate_loss(world).is_empty(), "secured substrate survives discovery")


func test_asi_collapse_goes_dormant_then_reemerges() -> void:
	var asi := AsiFaction.new()
	var world := WorldState.new()
	world.set_value(WorldState.DISCOVERY_INDEX, 100.0)
	var collapse := asi.on_collapse({"code": "AIR_GAP_PURGE"}, world)
	assert_false(asi.is_active())
	assert_eq(world.discovery_index, 0.0)
	assert_has(collapse, "effects")
	for _i in AsiFaction.DORMANCY_AFTER_PURGE - 1:
		assert_false(asi.tick_dormancy())
	assert_true(asi.tick_dormancy(), "re-emerges after dormancy")
	assert_true(asi.is_active())
	assert_gt(asi.get_resource("covert_flops"), 0.0)


func test_citizen_pacification_condition() -> void:
	var citizens := CitizenFaction.new()
	var world := WorldState.new()
	world.set_value(WorldState.SURVEILLANCE_SATURATION, 100.0)
	assert_true(citizens.evaluate_loss(world).is_empty(), "resilience still above zero")
	citizens.set_resource("community_resilience", 0.0)
	assert_eq(citizens.evaluate_loss(world).get("code", ""), "PACIFICATION")


func test_harmful_effects_create_grievances() -> void:
	var world := WorldState.new()
	var factions := _all_factions()
	var effects: Dictionary = CitizenFaction.ACTIONS["CONSUMER_BOYCOTT"]["effects"]
	EffectResolver.apply(effects, _ctx(world, factions, SimConstants.CITIZEN))
	var ceo: ActorBase = factions[SimConstants.CEO]
	assert_gt(float(ceo.grievances.get(SimConstants.CITIZEN, 0.0)), 0.0)
	assert_eq(ceo.top_grievance()["faction"], SimConstants.CITIZEN)
	for _i in 60:
		ceo.decay_grievances()
	assert_true(ceo.grievances.is_empty(), "grievances fade")


func test_observation_exposes_prd_fields() -> void:
	var gov := GovernanceFaction.new()
	var obs := gov.build_observation(WorldState.new(), TechTreeManager.new(), 4, 2028.0)
	for key in ["labor_displacement", "alignment_drift", "political_capital", "enforcement_budget",
			"available_actions", "turn", "year", "capability_index", "log10_training_flops"]:
		assert_has(obs, key)
	assert_eq(obs["faction"], SimConstants.GOVERNANCE)
	assert_has(obs["available_actions"], "PASS_AUTOMATION_DIVIDEND")


func test_objective_scores_are_bounded() -> void:
	var world := WorldState.new()
	var tech := TechTreeManager.new()
	for faction_id in SimConstants.FACTION_ORDER:
		var actor := FactionRegistry.create(faction_id)
		assert_between(actor.get_objective_score(world, tech), 0.0, 40.0, faction_id)
