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


# --- Library-wide rules ------------------------------------------------------------------

func test_every_card_leaves_each_role_a_cheap_response() -> void:
	assert_eq(DilemmaDeck.cheap_response_gaps(), [] as Array[String], "every card, every role: an answer at tier-1 prices")
	var template := {"id": "T", "options": [
		{"id": "A", "label": "a", "cost_tier": 2, "effects": {}},
		{"id": "B", "label": "b", "cost": {"covert_flops": 7.0}, "roles": ["ASI"], "effects": {}},
		{"id": "C", "label": "c", "cost": {"objective_coherence": 1.0}, "roles": ["ASI"], "effects": {}},
		{"id": "D", "label": "d", "cost_tier": 1, "conditions": {"requires_flags": ["x"]}, "effects": {}},
		{"id": "E", "label": "e", "cost": {"capital": 25.0}, "roles": ["CEO"], "effects": {}},
		{"id": "F", "label": "f", "cost": {}, "roles": ["CITIZEN_COALITION"], "effects": {}},
	]}
	assert_false(DilemmaDeck.has_cheap_response(template, SimConstants.ASI), "7 covert FLOPs is over tier 1; coherence is not a tier-1 currency")
	assert_false(DilemmaDeck.has_cheap_response(template, SimConstants.GOVERNANCE), "an option that needs a flag does not count")
	assert_true(DilemmaDeck.has_cheap_response(template, SimConstants.CEO), "exactly the tier-1 price")
	assert_true(DilemmaDeck.has_cheap_response(template, SimConstants.CITIZEN), "free")
	assert_eq(DilemmaDeck.cheap_response_gaps([template]), ["T/GOVERNANCE_COUNCIL", "T/ASI"] as Array[String])


func test_every_card_has_copy_hints_and_known_characters() -> void:
	for template in DilemmaDeck.all_cards():
		var card_id := String(template["id"])
		var copy := StoryCopy.card(card_id)
		for key in ["topic", "glyph", "subject", "event", "one", "plural", "options"]:
			assert_true(copy.has(key), "%s copy has %s" % [card_id, key])
		assert_true(Glyphs.has_glyph(String(copy.get("glyph", ""))), "%s glyph" % card_id)
		if template.has("swipe_hints"):
			assert_eq((template["swipe_hints"] as Array).size(), 2, card_id + " has left and right swipe hints")
			for hint in template["swipe_hints"]:
				assert_between(float(String(hint).length()), 1.0, 12.0, "%s hint '%s'" % [card_id, hint])
		else:
			assert_true(CrisisCard.SWIPE_HINTS.has(card_id), card_id + " has swipe hints")
		var character := String(template.get("character", ""))
		if character != "":
			assert_true(Characters.exists(character), "%s names a real character (%s)" % [card_id, character])
		if template.get("injection_only", false):
			var head := StoryCopy.injection_head(card_id)
			assert_true(head.length() > 0 and head.length() <= 76, "%s injection headline '%s'" % [card_id, head])
			assert_false(StoryCopy.has_placeholder(head), card_id + " injection headline has no placeholders")
		for option in template["options"]:
			if (option.get("effects", {}) as Dictionary).has("follow_up"):
				var follow_up := String(option["effects"]["follow_up"]["card"])
				assert_false(DilemmaDeck.get_template(follow_up).is_empty(), "%s schedules a real card (%s)" % [card_id, follow_up])
			for character_id in (option.get("effects", {}) as Dictionary).get("characters", {}):
				assert_true(Characters.exists(String(character_id)), "%s moves a real character (%s)" % [card_id, character_id])
		for role in SimConstants.FACTION_ORDER:
			var unconditional := 0
			for option in template["options"]:
				var roles: Array = option.get("roles", [])
				if (roles.is_empty() or roles.has(role)) and (option.get("conditions", {}) as Dictionary).is_empty():
					unconditional += 1
			assert_gte(unconditional, 2, "%s offers %s two answers that need no story flags" % [card_id, role])


# --- Injection families and cooldowns -------------------------------------------------------

func test_injecting_directives_name_their_families() -> void:
	for key in InjectionCards.FAMILIES:
		var faction_id := String(key).get_slice("/", 0)
		var action_id := String(key).get_slice("/", 1)
		var effects: Dictionary = FactionRegistry.catalog_for(faction_id)[action_id]["effects"]
		assert_eq(effects["inject_dilemma"], InjectionCards.FAMILIES[key], key)
		var family: Array = InjectionCards.FAMILIES[key]
		assert_between(float(family.size()), 3.0, 4.0, key + " injects a family of three or four")
		# The newer members answer only the roles that can receive them.
		for card_id in family.slice(1):
			for option in DilemmaDeck.get_template(String(card_id))["options"]:
				assert_false((option.get("roles", []) as Array).has(faction_id), "%s: no %s answer on its own injection" % [card_id, faction_id])


func test_a_family_rotates_and_cools_down_per_player() -> void:
	var family: Array = InjectionCards.FAMILIES["ASI/DEPLOY_SUB_AGENT_SWARMS"]
	var deck := DilemmaDeck.new()
	var seen: Array[String] = []
	for turn in range(1, 5):
		assert_true(deck.inject(family, SimConstants.ASI, turn, [SimConstants.GOVERNANCE]), "turn %d queues a member" % turn)
		assert_false(deck.inject(family, SimConstants.ASI, turn, [SimConstants.GOVERNANCE]), "one member of a family waits at a time")
		var card := deck.draw(_ctx(SimConstants.GOVERNANCE, SimConstants.year_for_turn(turn)), null)
		assert_eq(card["source"], SimConstants.ASI)
		assert_false(seen.has(String(card["id"])), "a new member each time: " + String(card["id"]))
		seen.append(String(card["id"]))
	assert_eq(seen.size(), family.size(), "the whole family came round")
	assert_false(deck.inject(family, SimConstants.ASI, 5, [SimConstants.GOVERNANCE]), "every member drawn within %d turns: nothing" % DilemmaDeck.INJECTION_COOLDOWN_TURNS)
	assert_false(deck.inject(family, SimConstants.ASI, 8, [SimConstants.GOVERNANCE]), "turn 8 is still within the cooldown of turn 1")
	assert_true(deck.inject(family, SimConstants.ASI, 9, [SimConstants.GOVERNANCE]), "eight turns after the first, it can come back")
	assert_eq(deck.injected[-1]["id"], seen[0], "the least recent member returns first")
	assert_true(deck.inject(family, SimConstants.ASI, 9, [SimConstants.CITIZEN]), "another player's cooldown is their own")
	assert_eq(deck.injected[-1]["id"], family[0], "the Coalition has seen none of them")


func test_injections_wait_for_each_other_player() -> void:
	var deck := DilemmaDeck.new()
	var family: Array = InjectionCards.FAMILIES["CEO/POACH_SAFETY_RESEARCHERS"]
	assert_true(deck.inject(family, SimConstants.CEO, 3, [SimConstants.CEO, SimConstants.GOVERNANCE, SimConstants.CITIZEN]))
	assert_eq(deck.injected.size(), 2, "one for each human but the sender")
	assert_false(deck.inject(family, SimConstants.CEO, 3, [SimConstants.CEO]), "nobody else to send it to")
	assert_ne(deck.draw(_ctx(SimConstants.CEO, 2027.5), null)["source"], SimConstants.CEO, "the sender draws its own deck")
	var council := deck.draw(_ctx(SimConstants.GOVERNANCE, 2027.5), null)
	var coalition := deck.draw(_ctx(SimConstants.CITIZEN, 2027.5), null)
	assert_eq(council["source"], SimConstants.CEO)
	assert_eq(coalition["source"], SimConstants.CEO)
	assert_true(deck.injected.is_empty())
	assert_true(family.has(council["id"]) and family.has(coalition["id"]))
	for i in DilemmaDeck.MAX_INJECTED + 1:
		var families: Array = InjectionCards.FAMILIES.values()
		deck.inject(families[i], "SOMEONE", 4, [SimConstants.ASI])
	assert_eq(deck.injected.size(), DilemmaDeck.MAX_INJECTED, "a desk holds at most %d" % DilemmaDeck.MAX_INJECTED)


func test_the_effect_resolver_injects_with_the_turn() -> void:
	var deck := DilemmaDeck.new()
	var ctx := {"deck": deck, "actor_id": SimConstants.ASI, "player_id": SimConstants.CEO, "humans": [SimConstants.CEO], "turn": 30}
	var applied := EffectResolver.apply(AsiFaction.ACTIONS["DEPLOY_SUB_AGENT_SWARMS"]["effects"], ctx)
	assert_eq(applied["injected"], "ROGUE_AGENT_SWARM")
	assert_eq(deck.injected[0]["role"], SimConstants.CEO)
	deck.draw(_ctx(SimConstants.CEO, SimConstants.year_for_turn(30)), null)
	assert_eq(deck.injection_draws[SimConstants.CEO]["ROGUE_AGENT_SWARM"], 30, "drawn on the context's turn")
	ctx["turn"] = 31
	assert_ne(EffectResolver.apply(AsiFaction.ACTIONS["DEPLOY_SUB_AGENT_SWARMS"]["effects"], ctx)["injected"], "ROGUE_AGENT_SWARM",
		"on cooldown, another member comes")


# --- Repetition ------------------------------------------------------------------------------

func test_no_card_repeats_within_eight_turns_while_others_are_eligible() -> void:
	var world := WorldState.new()
	for pair in [[WorldState.COMPUTE_ENERGY_SAT, 64.0], [WorldState.LABOR_DISPLACEMENT, 52.0], [WorldState.GEOPOLITICAL_TENSION, 58.0],
			[WorldState.ALGORITHMIC_AUTONOMY, 52.0], [WorldState.ALIGNMENT_DRIFT, 40.0], [WorldState.EPISTEMIC_TRUST, 55.0]]:
		world.set_value(String(pair[0]), float(pair[1]))
	for role in SimConstants.FACTION_ORDER:
		var rng := RandomNumberGenerator.new()
		rng.seed = 404
		var deck := DilemmaDeck.new()
		var last := {}
		var fallbacks := 0
		for turn in range(1, 101):
			var ctx := _ctx(role, SimConstants.year_for_turn(turn), world)
			ctx["turn"] = turn
			var fresh: Array = []
			var least_recent := DilemmaDeck.NEVER
			for template in DilemmaDeck.all_cards():
				if template.get("injection_only", false) or template.get("follow_up_only", false) or float(template["weight"]) <= 0.0 \
						or not deck._eligible(template, ctx):
					continue
				var drawn_at := int(last.get(template["id"], DilemmaDeck.NEVER))
				if drawn_at == DilemmaDeck.NEVER or turn - drawn_at >= DilemmaDeck.NO_REPEAT_TURNS:
					fresh.append(template["id"])
				elif least_recent == DilemmaDeck.NEVER or drawn_at < least_recent:
					least_recent = drawn_at
			var card := deck.draw(ctx, rng)
			assert_eq(card["source"], "DECK")
			if fresh.is_empty():
				fallbacks += 1
				assert_eq(int(last.get(card["id"], DilemmaDeck.NEVER)), least_recent, "%s turn %d: the least recent card returns" % [role, turn])
			else:
				assert_has(fresh, card["id"], "%s turn %d: %s was drawn less than %d turns ago" % [role, turn, card["id"], DilemmaDeck.NO_REPEAT_TURNS])
			last[card["id"]] = turn
		assert_lt(float(fallbacks), 10.0, "%s: the pool almost always allows a fresh card" % role)


func test_deferred_returns_and_follow_ups_ignore_the_repeat_rule() -> void:
	var deck := DilemmaDeck.new()
	var ctx := _ctx("CEO", 2030.0)
	var card := deck._instantiate(DilemmaDeck.get_template("FRONTIER_RELEASE_RACE"), ctx, null, "DECK", 0)
	deck._remember(String(card["id"]), "CEO", 8)
	deck.defer(card, 8, "CEO")
	deck.schedule(String(card["id"]), 9, "CEO")
	ctx["turn"] = 9
	assert_eq(deck.draw(ctx, null)["source"], "FOLLOW_UP", "a scheduled card arrives even right after its draw")
	ctx["turn"] = 10
	var returned := deck.draw(ctx, null)
	assert_eq(returned["source"], "DEFERRED")
	assert_eq(returned["id"], card["id"])


# --- Story mechanics -------------------------------------------------------------------------

func _story_template(character: String = "") -> Dictionary:
	return {"id": "STORY_TEST", "title": "A test", "body": "A body.", "character": character, "options": [
		{"id": "A", "label": "a", "cost_tier": 1, "effects": {}},
		{"id": "B", "label": "b", "cost_tier": 1, "effects": {}},
		{"id": "D", "label": "d", "cost_tier": 1, "conditions": {"requires_flags": ["helped"]}, "effects": {}},
		{"id": "E", "label": "e", "cost_tier": 1, "conditions": {"lacks_flags": ["helped"], "character_max": {"jonas": -2.0}}, "effects": {}},
		{"id": "F", "label": "f", "cost_tier": 1, "conditions": {"character_min": {"jonas": 2.0}}, "roles": ["CEO"], "effects": {}},
	], "defer": {"label": "Wait", "effects": {}}}


func test_options_with_story_conditions_appear_only_when_they_hold() -> void:
	var deck := DilemmaDeck.new()
	var ids := DilemmaDeck.option_ids(deck._instantiate(_story_template(), _ctx("CEO", 2032.0), null, "FOLLOW_UP", 0))
	assert_eq(ids, ["A", "B", DilemmaDeck.DEFER_ID] as Array[String], "no history, no extra answers")
	deck.set_flag("helped")
	ids = DilemmaDeck.option_ids(deck._instantiate(_story_template(), _ctx("CEO", 2032.0), null, "FOLLOW_UP", 0))
	assert_eq(ids, ["A", "B", "D", DilemmaDeck.DEFER_ID] as Array[String], "a flag opens an answer")
	deck.clear_flag("helped")
	deck.adjust_character("jonas", -2.0)
	ids = DilemmaDeck.option_ids(deck._instantiate(_story_template(), _ctx("CEO", 2032.0), null, "FOLLOW_UP", 0))
	assert_eq(ids, ["A", "B", "E", DilemmaDeck.DEFER_ID] as Array[String], "so does a grudge")
	deck.adjust_character("jonas", 4.0)
	assert_eq(DilemmaDeck.option_ids(deck._instantiate(_story_template(), _ctx("CEO", 2032.0), null, "FOLLOW_UP", 0)),
		["A", "B", "F", DilemmaDeck.DEFER_ID] as Array[String], "or a friendship, for the role it is written for")
	assert_eq(DilemmaDeck.option_ids(deck._instantiate(_story_template(), _ctx("ASI", 2032.0), null, "FOLLOW_UP", 0)),
		["A", "B", DilemmaDeck.DEFER_ID] as Array[String])


func test_characters_met_are_recorded() -> void:
	var deck := DilemmaDeck.new()
	var ctx := _ctx("CEO", 2030.0)
	deck._instantiate(_story_template("jonas"), ctx, null, "DECK", 0)
	ctx["turn"] = 15
	deck._instantiate(_story_template("jonas"), ctx, null, "FOLLOW_UP", 0)
	deck._instantiate(_story_template(), ctx, null, "DECK", 0)
	assert_eq(deck.characters_met, {"jonas": {"first_turn": 8, "last_turn": 15, "count": 2}})
	assert_eq(deck.to_dict()["characters_met"], deck.characters_met, "saved with the deck")
