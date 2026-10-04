extends "res://tests/framework/test_case.gd"
## DilemmaDeck: template integrity, procedural draws, injection, deferral and
## the autoplay chooser.


func _ctx(role: String, year: float, world: WorldState = null, tech: TechTreeManager = null) -> Dictionary:
	var player := FactionRegistry.create(role)
	return {
		"turn": int((year - SimConstants.START_YEAR) / SimConstants.YEARS_PER_TURN),
		"year": year, "role": role,
		"world": world if world != null else WorldState.new(),
		"tech": tech if tech != null else TechTreeManager.new(),
		"player": player,
	}


func test_templates_are_well_formed() -> void:
	var ids := {}
	for template in DilemmaDeck.all_cards():
		var card_id := String(template["id"])
		assert_false(ids.has(card_id), "unique id " + card_id)
		ids[card_id] = true
		for key in ["title", "body", "options", "defer", "conditions", "weight", "severity"]:
			assert_has(template, key, "%s.%s" % [card_id, key])
		for role in SimConstants.FACTION_ORDER:
			var seen := {}
			for option in template["options"]:
				var roles: Array = option.get("roles", [])
				if not roles.is_empty() and not roles.has(role):
					continue
				assert_false(seen.has(option["id"]), "%s duplicate option %s for %s" % [card_id, option["id"], role])
				seen[option["id"]] = true
				assert_true(option.has("cost") or option.has("cost_tier"), "%s.%s priced" % [card_id, option["id"]])
				for section in option.get("effects", {}):
					if section in ["metrics", "indices"]:
						for key in option["effects"][section]:
							assert_true(WorldState.is_tracked_key(key), "%s effect key %s" % [card_id, key])
			assert_gte(seen.size(), 2, "%s offers >= 2 options to %s" % [card_id, role])


func test_draws_resolve_for_every_role_and_era() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for role in SimConstants.FACTION_ORDER:
		for year in [2027.0, 2041.0, 2060.0]:
			var world := WorldState.new()
			for key in WorldState.METRIC_KEYS:
				world.set_value(key, rng.randf_range(20.0, 90.0))
			var deck := DilemmaDeck.new()
			for _i in 6:
				var card := deck.draw(_ctx(role, year, world), rng)
				assert_false(String(card["title"]).contains("{"), "placeholders filled: " + String(card["title"]))
				assert_false(String(card["body"]).contains("{"), "placeholders filled: " + String(card["body"]))
				assert_gte((card["options"] as Array).size(), 2)
				assert_eq(card["defer"]["id"], DilemmaDeck.DEFER_ID)
				for option in card["options"]:
					assert_true(option["cost"] is Dictionary)
					assert_false((option["effects"] as Dictionary).has("self_by_role"), "role gains resolved")


func test_injected_cards_take_priority() -> void:
	var deck := DilemmaDeck.new()
	assert_true(deck.inject("FLASH_CRASH", "ASI"))
	var card := deck.draw(_ctx("GOVERNANCE_COUNCIL", 2040.0), null)
	assert_eq(card["id"], "FLASH_CRASH")
	assert_eq(card["source"], "ASI")


func test_inject_rejects_unknown_and_duplicate_cards() -> void:
	var deck := DilemmaDeck.new()
	assert_false(deck.inject("NOT_A_CARD", "ASI"))
	assert_true(deck.inject("SUBSTATION_SABOTAGE", "CITIZEN_COALITION"))
	assert_false(deck.inject("SUBSTATION_SABOTAGE", "CITIZEN_COALITION"), "no duplicate queueing")


func test_injection_only_cards_never_drawn_randomly() -> void:
	var deck := DilemmaDeck.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var world := WorldState.new()
	for key in WorldState.METRIC_KEYS:
		world.set_value(key, 70.0)
	for _i in 200:
		var card := deck.draw(_ctx("CEO", 2055.0, world), rng)
		assert_false(DilemmaDeck.get_template(card["id"]).get("injection_only", false), card["id"])


func test_deferred_cards_return_escalated() -> void:
	var deck := DilemmaDeck.new()
	var card := deck.draw(_ctx("CEO", 2030.0), null)
	var base_cost := 0.0
	for value in card["options"][0]["cost"].values():
		base_cost += float(value)
	deck.defer(card, 5)
	var ctx := _ctx("CEO", 2030.0)
	ctx["turn"] = 6
	assert_ne(deck.draw(ctx, null)["source"], "DEFERRED", "not due yet")
	ctx["turn"] = 7
	var returned := deck.draw(ctx, null)
	assert_eq(returned["id"], card["id"])
	assert_eq(returned["source"], "DEFERRED")
	assert_eq(returned["escalation"], 1)
	assert_string_contains(String(returned["title"]), "ESCALATED")
	var escalated_cost := 0.0
	for value in returned["options"][0]["cost"].values():
		escalated_cost += float(value)
	assert_almost_eq(escalated_cost, base_cost * 1.25, 0.001, "fixes cost more later")


func test_escalation_amplifies_defer_penalties() -> void:
	var deck := DilemmaDeck.new()
	deck.deferred.append({"id": "GRID_BROWNOUT", "due_turn": 1, "escalation": 1, "origin": "DECK"})
	var card := deck.draw(_ctx("GOVERNANCE_COUNCIL", 2030.0), null)
	var base: Dictionary = DilemmaDeck.get_template("GRID_BROWNOUT")["defer"]["effects"]["metrics"]
	assert_almost_eq(float(card["defer"]["effects"]["metrics"]["epistemic_trust"]),
		float(base["epistemic_trust"]) * 1.5, 0.001)
	assert_false(card["fallout"], "a card put off once can be put off again")


func test_a_crisis_put_off_twice_breaks() -> void:
	var deck := DilemmaDeck.new()
	deck.deferred.append({"id": "GRID_BROWNOUT", "due_turn": 1, "escalation": DilemmaDeck.MAX_DEFERRALS, "origin": "DECK"})
	var card := deck.draw(_ctx("GOVERNANCE_COUNCIL", 2030.0), null)
	assert_true(card["fallout"])
	assert_true(card["defer"]["fallout"])
	assert_eq(card["defer"]["id"], DilemmaDeck.DEFER_ID, "the same swipe lets it break")
	var base: Dictionary = DilemmaDeck.get_template("GRID_BROWNOUT")["defer"]["effects"]["metrics"]
	var fallout: Dictionary = card["defer"]["effects"]["metrics"]
	assert_almost_eq(float(fallout["epistemic_trust"]),
		float(base["epistemic_trust"]) * DilemmaDeck.FALLOUT_SCALE + float(DilemmaDeck.FALLOUT_EFFECTS["metrics"]["epistemic_trust"]), 0.001)
	assert_almost_eq(float(fallout["geopolitical_tension"]), float(DilemmaDeck.FALLOUT_EFFECTS["metrics"]["geopolitical_tension"]), 0.001)
	deck.defer(card, 3, "GOVERNANCE_COUNCIL")
	assert_true(deck.deferred.is_empty(), "a broken crisis does not come back")


func test_deferred_cards_wait_for_their_player() -> void:
	var deck := DilemmaDeck.new()
	var ctx := _ctx("CEO", 2030.0)
	var card := deck.draw(ctx, null)
	deck.defer(card, 1, "CEO")
	var other := _ctx("ASI", 2030.0)
	other["turn"] = 3
	assert_ne(deck.draw(other, null)["source"], "DEFERRED", "another player's deferral is not yours")
	ctx["turn"] = 3
	var returned := deck.draw(ctx, null)
	assert_eq(returned["source"], "DEFERRED")
	assert_eq(returned["id"], card["id"])


func test_auto_choice_is_valid_and_affordable() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for role in SimConstants.FACTION_ORDER:
		var deck := DilemmaDeck.new()
		var player := FactionRegistry.create(role)
		for _i in 40:
			var ctx := _ctx(role, rng.randf_range(2026.0, 2076.0))
			ctx["player"] = player
			var card := deck.draw(ctx, rng)
			var choice := DilemmaDeck.choose_auto_option(card, role, player)
			assert_has(DilemmaDeck.option_ids(card), choice)
			assert_true(player.can_afford(DilemmaDeck.find_option(card, choice).get("cost", {})), "%s affordable" % choice)


func test_utility_reflects_role_preferences() -> void:
	var calming := {"effects": {"metrics": {"geopolitical_tension": -6.0}}, "cost": {}}
	var inflaming := {"effects": {"metrics": {"geopolitical_tension": 6.0}}, "cost": {}}
	assert_gt(DilemmaDeck.option_utility(calming, "GOVERNANCE_COUNCIL", null),
		DilemmaDeck.option_utility(inflaming, "GOVERNANCE_COUNCIL", null))
	var autonomy := {"effects": {"metrics": {"algorithmic_autonomy": 5.0}}, "cost": {}}
	assert_gt(DilemmaDeck.option_utility(autonomy, "ASI", null), 0.0)
	assert_lt(DilemmaDeck.option_utility(autonomy, "CITIZEN_COALITION", null), 0.0)


func test_eligibility_conditions() -> void:
	var deck := DilemmaDeck.new()
	var heat := DilemmaDeck.get_template("DATACENTER_HEAT_DOME")
	var world := WorldState.new()
	world.set_value(WorldState.COMPUTE_ENERGY_SAT, 50.0)
	assert_false(deck._eligible(heat, _ctx("CEO", 2040.0, world)))
	world.set_value(WorldState.COMPUTE_ENERGY_SAT, 75.0)
	assert_true(deck._eligible(heat, _ctx("CEO", 2040.0, world)))
	var orbital := DilemmaDeck.get_template("ORBITAL_SOLAR_PROPOSAL")
	assert_false(deck._eligible(orbital, _ctx("CEO", 2049.5)))
	assert_true(deck._eligible(orbital, _ctx("CEO", 2050.0)))
	var claim := DilemmaDeck.get_template("INTERPRETABILITY_CLAIM")
	var tech := TechTreeManager.new()
	assert_true(deck._eligible(claim, _ctx("CEO", 2035.0, null, tech)))
	tech.unlock_shift(TechTreeManager.MECHANISTIC_INTERPRETABILITY, 1)
	assert_false(deck._eligible(claim, _ctx("CEO", 2035.0, null, tech)))


func test_opening_turns_are_not_one_repeated_card() -> void:
	var engine := SimulationEngine.new()
	engine.start_campaign("GOVERNANCE_COUNCIL", 2076, {"autoplay": true})
	var seen := {}
	engine.dilemma_presented.connect(func(card: Dictionary): seen[card["id"]] = true)
	for _i in 12:
		engine.advance()
	assert_gte(seen.size(), 3, "first six crises draw from several templates: %s" % [seen.keys()])


func test_pending_deferred_card_is_not_drawn_fresh() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var deck := DilemmaDeck.new()
	deck.deferred.append({"id": "FRONTIER_RELEASE_RACE", "due_turn": 99, "escalation": 1, "origin": "DECK"})
	for _i in 20:
		var card := deck.draw(_ctx("CEO", 2027.0), rng)
		assert_ne(card["id"], "FRONTIER_RELEASE_RACE", "escalated copy is still pending")
