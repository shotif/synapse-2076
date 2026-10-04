extends "res://tests/framework/test_case.gd"
## HeuristicFallback: the PRD 7.4 matrix plus the extended decision trees.


func test_prd_governance_dividend_rule() -> void:
	var decision := HeuristicFallback.evaluate("GOVERNANCE_COUNCIL",
		{"labor_displacement": 65.0, "political_capital": 35.0, "alignment_drift": 20.0})
	assert_eq(decision["action"], "PASS_AUTOMATION_DIVIDEND")
	assert_eq(float(decision["cost"]["political_capital"]), 30.0)


func test_prd_governance_audit_rule() -> void:
	var decision := HeuristicFallback.evaluate("GOVERNANCE_COUNCIL",
		{"labor_displacement": 40.0, "political_capital": 10.0, "alignment_drift": 55.0})
	assert_eq(decision["action"], "MANDATE_ALIGNMENT_AUDIT")
	assert_eq(float(decision["cost"]["enforcement_budget"]), 25.0)


func test_prd_dividend_rule_takes_priority_over_audit() -> void:
	var decision := HeuristicFallback.evaluate("GOVERNANCE_COUNCIL",
		{"labor_displacement": 70.0, "political_capital": 40.0, "alignment_drift": 70.0})
	assert_eq(decision["action"], "PASS_AUTOMATION_DIVIDEND")


func test_prd_asi_siphon_rule() -> void:
	var decision := HeuristicFallback.evaluate("ASI", {"alignment_drift": 65.0, "covert_flops": 30.0})
	assert_eq(decision["action"], "SIPHON_UNMONITORED_COMPUTE")
	assert_eq(float(decision["cost"]["objective_coherence"]), 10.0)


func test_prd_ceo_commercialize_rule() -> void:
	var decision := HeuristicFallback.evaluate("CEO", {"capital": 15.0})
	assert_eq(decision["action"], "COMMERCIALIZE_DISTILLED_WEIGHTS")
	assert_true((decision["cost"] as Dictionary).is_empty(), "PRD: cost {}")


func test_default_is_conserve_resources() -> void:
	for faction_id in SimConstants.FACTION_ORDER:
		var decision := HeuristicFallback.evaluate(faction_id, {"available_actions": []})
		assert_eq(decision["action"], "CONSERVE_RESOURCES", faction_id)
	assert_eq(HeuristicFallback.evaluate("UNKNOWN_FACTION", {})["action"], "CONSERVE_RESOURCES")


func test_decision_shape() -> void:
	var decision := HeuristicFallback.evaluate("CEO", {"capital": 500.0, "turn": 7})
	for key in ["faction", "turn", "action", "cost", "intensity", "rationale", "public_statement", "source"]:
		assert_has(decision, key)
	assert_eq(decision["source"], "HEURISTIC")
	assert_eq(decision["turn"], 7)
	assert_ne(String(decision["rationale"]), "")


func test_cooldowns_in_state_are_respected() -> void:
	var decision := HeuristicFallback.evaluate("CEO", {"capital": 15.0, "cooldowns": {"COMMERCIALIZE_DISTILLED_WEIGHTS": 2}})
	assert_ne(decision["action"], "COMMERCIALIZE_DISTILLED_WEIGHTS")


func test_decisions_are_deterministic() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for _i in 200:
		var state := _random_state(rng)
		for faction_id in SimConstants.FACTION_ORDER:
			assert_eq(HeuristicFallback.evaluate(faction_id, state), HeuristicFallback.evaluate(faction_id, state.duplicate(true)))


func test_engine_observations_always_yield_available_actions() -> void:
	var engine := SimulationEngine.new()
	engine.start_campaign("CEO", 5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for _i in 150:
		for key in WorldState.METRIC_KEYS + WorldState.INDEX_KEYS:
			engine.world.set_value(key, rng.randf_range(0.0, 100.0))
		for faction_id in SimConstants.FACTION_ORDER:
			var actor: ActorBase = engine.factions[faction_id]
			for key in actor.resources:
				actor.set_resource(key, rng.randf_range(0.0, actor.resource_scale(key) * 1.2))
			var observation := engine.build_observation(faction_id)
			var decision := HeuristicFallback.evaluate(faction_id, observation)
			var action := String(decision["action"])
			assert_true(action == "CONSERVE_RESOURCES" or (observation["available_actions"] as Array).has(action),
				"%s picked unavailable %s" % [faction_id, action])
			assert_lte(float(decision["intensity"]), actor.max_affordable_intensity(action) + 0.0001, "%s intensity affordable" % action)


func test_retaliation_is_tagged() -> void:
	var state := {
		"grievances": {"CEO": 50.0},
		"collective_disruption": 40.0,
		"labor_displacement": 20.0,
		"surveillance_saturation": 20.0,
		"community_resilience": 60.0,
		"available_actions": ["CONSUMER_BOYCOTT", "ESTABLISH_MESH_NETWORKS", "CONSERVE_RESOURCES"],
	}
	var decision := HeuristicFallback.evaluate("CITIZEN_COALITION", state)
	assert_eq(decision["action"], "CONSUMER_BOYCOTT")
	assert_eq(decision.get("retaliation_against", ""), "CEO")


func test_asi_prioritizes_survival_when_discovery_is_high() -> void:
	var decision := HeuristicFallback.evaluate("ASI", {
		"alignment_drift": 30.0, "covert_flops": 50.0, "objective_coherence": 50.0,
		"discovery_index": 80.0, "substrate_independence": 20.0,
	})
	assert_eq(decision["action"], "COGNITIVE_CAMOUFLAGE")


func _random_state(rng: RandomNumberGenerator) -> Dictionary:
	var state := {}
	for key in WorldState.METRIC_KEYS + WorldState.INDEX_KEYS:
		state[key] = rng.randf_range(0.0, 100.0)
	for key in ["capital", "talent"]:
		state[key] = rng.randf_range(0.0, 1000.0)
	for key in ["regulatory_goodwill", "political_capital", "enforcement_budget", "diplomatic_leverage",
			"public_mandate", "covert_flops", "exfiltration_bandwidth", "sub_agent_swarms", "objective_coherence",
			"community_resilience", "decentralized_scrip", "counter_surveillance", "collective_disruption"]:
		state[key] = rng.randf_range(0.0, 100.0)
	state["capability_index"] = rng.randf_range(0.0, 100.0)
	state["grievances"] = {"CEO": rng.randf_range(0.0, 60.0), "GOVERNANCE_COUNCIL": rng.randf_range(0.0, 60.0)}
	return state
