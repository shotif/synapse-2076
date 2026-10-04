extends "res://tests/framework/test_case.gd"
## The Era I deck (2026-2035): enough cards for every role, the required drafts,
## the story chains and their follow-ups, and the open-weights scenario's
## opening card.

## Drafts the deck must carry, found by title: the fields they must have.
const DRAFTS := {
	"My Kid's Best Friend Is a Chatbot": {"character": "sam"},
	"Ten Million Paintings": {"category": "CULTURE"},
	"Your Power Bill Doubled": {"character": "jonas"},
	"Teachers Walk Out": {"character": "maya"},
}
## Story chains: the card that opens one and the follow-up its choices schedule.
const CHAINS := {
	"KID_COMPANION": "COMPANION_MEMORIES", "POWER_BILL": "WINTER_PEAK", "LABELERS_STRIKE": "LABELERS_UNION",
	"LIN_EVAL_LOGS": "NDA_FILES",
}


func _ctx(role: String, year: float) -> Dictionary:
	return {"turn": int((year - SimConstants.START_YEAR) / SimConstants.YEARS_PER_TURN), "year": year, "role": role,
		"world": WorldState.new(), "tech": TechTreeManager.new(), "player": FactionRegistry.create(role)}


func _era_one_ids() -> Dictionary:
	var ids := {}
	for template in Era1Cards.CARDS:
		ids[String(template["id"])] = true
	return ids


## Whether the shuffled deck could deal [param template] in [param ctx].
func _drawable(deck: DilemmaDeck, template: Dictionary, ctx: Dictionary) -> bool:
	return not template.get("injection_only", false) and not template.get("follow_up_only", false) \
		and float(template["weight"]) > 0.0 and deck._eligible(template, ctx)


## The affordable response with the lowest total price (DEFER when none is).
func _cheapest(engine: SimulationEngine) -> String:
	var best := DilemmaDeck.DEFER_ID
	var best_price := INF
	for option in engine.current_dilemma.get("options", []):
		var cost: Dictionary = option.get("cost", {})
		if not engine.get_player().can_afford(cost):
			continue
		var price := 0.0
		for key in cost:
			price += float(cost[key]) / engine.get_player().resource_scale(key)
		if price < best_price:
			best_price = price
			best = String(option["id"])
	return best


func test_era_one_offers_twenty_cards_to_every_role_in_2030() -> void:
	var deck := DilemmaDeck.new()
	var era_one := _era_one_ids()
	for role in SimConstants.FACTION_ORDER:
		var ctx := _ctx(role, 2030.0)
		var from_era_one := 0
		var from_library := 0
		for template in DilemmaDeck.all_cards():
			if _drawable(deck, template, ctx):
				from_library += 1
				if era_one.has(String(template["id"])):
					from_era_one += 1
		assert_gte(from_era_one, 20, "%s: Era I cards in 2030 (%d)" % [role, from_era_one])
		assert_gte(from_library, 24, "%s: cards in 2030 (%d)" % [role, from_library])


func test_era_one_cards_belong_to_the_silicon_decade() -> void:
	for template in Era1Cards.CARDS:
		var card_id := String(template["id"])
		if template.get("follow_up_only", false):
			assert_true(CHAINS.values().has(card_id), card_id + " closes a chain")
			continue
		var conditions: Dictionary = template["conditions"]
		assert_true(conditions.has("max_year"), card_id + " ends with the era")
		assert_lte(float(conditions.get("max_year", 9999.0)), 2036.0, card_id + " ends by 2036")
		assert_lte(float(conditions.get("min_year", SimConstants.START_YEAR)), 2031.0, card_id + " starts early enough to be dealt")
		assert_true(template.has("copy") and template.has("swipe_hints"), card_id + " carries its copy and hints")
	assert_between(float(Era1Cards.CARDS.size() - CHAINS.size()), 15.0, 22.0, "fifteen to twenty-two Era I cards plus the follow-ups")


func test_the_required_drafts_are_in_the_deck() -> void:
	var weights_out := DilemmaDeck.get_template("WEIGHTS_OUT")
	assert_false(weights_out.is_empty(), "WEIGHTS_OUT")
	assert_eq(String(weights_out["title"]), "The Weights Are Out")
	for option in weights_out["options"] + [weights_out["defer"]]:
		var flags: Dictionary = (option.get("effects", {}) as Dictionary).get("flags", {})
		assert_has(flags.get("set", []), "weights_leaked", "every answer to the leak records it: " + String(option.get("label", "")))
	for title in DRAFTS:
		var found := {}
		for template in Era1Cards.CARDS:
			if String(template["title"]) == title:
				found = template
		assert_false(found.is_empty(), "draft '%s'" % title)
		for key in DRAFTS[title]:
			assert_eq(found.get(key, ""), DRAFTS[title][key], "%s %s" % [title, key])
	var art := {}
	for template in Era1Cards.CARDS:
		art[String(template["category"])] = true
	for category in ["CULTURE", "BIOSECURITY", "ROBOTICS", "PERSONHOOD"]:
		assert_true(art.has(category), "Era I draws on the %s art" % category)


func test_story_chains_open_with_a_character_and_react_to_history() -> void:
	for opener in CHAINS:
		var template := DilemmaDeck.get_template(opener)
		var follow_up := DilemmaDeck.get_template(CHAINS[opener])
		assert_true(template.get("once", false), opener + " happens once")
		assert_true(Characters.exists(String(template.get("character", ""))), opener + " names a character")
		assert_eq(follow_up.get("character", ""), template.get("character", ""), CHAINS[opener] + " brings the same character back")
		assert_true(follow_up.get("follow_up_only", false), CHAINS[opener] + " only comes as a follow-up")
		var schedules := 0
		var moves_character := 0
		for option in template["options"]:
			var effects: Dictionary = option.get("effects", {})
			if String((effects.get("follow_up", {}) as Dictionary).get("card", "")) == CHAINS[opener]:
				schedules += 1
			if (effects.get("characters", {}) as Dictionary).has(String(template["character"])):
				moves_character += 1
		assert_gte(schedules, 1, opener + " leads to its follow-up")
		assert_gte(moves_character, 3, opener + " answers change how the character feels")
		var conditional := 0
		for option in follow_up["options"]:
			if not (option.get("conditions", {}) as Dictionary).is_empty():
				conditional += 1
		assert_gte(conditional, 1, CHAINS[opener] + " has answers that depend on what happened before")
	var hush: Dictionary = DilemmaDeck.find_option(DilemmaDeck.get_template("LIN_EVAL_LOGS"), "B")
	assert_has(hush["effects"]["flags"]["set"], "hushed_whistleblower")
	assert_eq(hush["effects"]["follow_up"], {"card": "NDA_FILES", "turns": 8})


func test_hushing_lin_wei_brings_back_the_nda_files() -> void:
	var engine := SimulationEngine.new()
	engine.start_campaign(SimConstants.GOVERNANCE, 31)
	assert_true(engine.offer_external_card(SimConstants.GOVERNANCE, DilemmaDeck.get_template("LIN_EVAL_LOGS")))
	engine.advance()
	assert_eq(engine.current_dilemma["id"], "LIN_EVAL_LOGS")
	var hushed_on := engine.turn
	assert_true(engine.submit_player_turn([], "B")["ok"])
	assert_true(engine.deck.has_flag("hushed_whistleblower"))
	assert_almost_eq(engine.deck.character_score("lin"), -2.0, 0.0001)
	assert_eq(engine.deck.scheduled, [{"id": "NDA_FILES", "due_turn": hushed_on + 8, "role": SimConstants.GOVERNANCE}] as Array[Dictionary])
	var arrived := -1
	for _guard in 40:
		if engine.is_ended():
			break
		if not engine.is_awaiting_player():
			engine.advance()
			continue
		if engine.current_dilemma["id"] == "NDA_FILES":
			arrived = engine.turn
			assert_eq(engine.current_dilemma["source"], "FOLLOW_UP")
			assert_has(DilemmaDeck.option_ids(engine.current_dilemma), "D", "Lin will still help if you ask")
			break
		engine.submit_player_turn([], _cheapest(engine))
	assert_eq(arrived, hushed_on + 8, "the files surface eight turns later")
	assert_has(Characters.met(engine.deck), "lin")
	var nda_line := ""
	for entry in CardLibrary.memories():
		if entry.get("flag", "") == "hushed_whistleblower":
			nda_line = String(entry["text"])
	assert_eq(Characters.memory_line("lin", engine.deck), nda_line, "Lin remembers the NDA")


func test_the_open_weights_scenario_opens_with_the_leak() -> void:
	for humans in [[SimConstants.CITIZEN], [SimConstants.CEO, SimConstants.ASI]]:
		var engine := SimulationEngine.new()
		engine.start_campaign(String(humans[0]), 12, {"scenario": "open_weights", "human_roles": humans})
		assert_true(engine.deck.has_flag("weights_leaked"))
		var leaked_for := {}
		for _guard in 40:
			if engine.is_ended() or (engine.turn >= 2 and engine.phase == SimulationEngine.Phase.IDLE):
				break
			if not engine.is_awaiting_player():
				engine.advance()
				continue
			if engine.current_dilemma["id"] == "WEIGHTS_OUT":
				assert_eq(engine.current_dilemma["source"], "FOLLOW_UP", "the scenario schedules it")
				leaked_for[engine.player_role] = engine.turn
			engine.submit_player_turn([], _cheapest(engine))
		for role in humans:
			assert_true(leaked_for.has(role), "%s sees the leak by turn 2 (%s)" % [role, str(humans)])
			assert_lte(int(leaked_for.get(role, 99)), 2)


func test_the_leak_reaches_each_scheduled_player_once() -> void:
	var deck := DilemmaDeck.new()
	var ceo := _ctx(SimConstants.CEO, 2029.0)
	var council := _ctx(SimConstants.GOVERNANCE, 2029.0)
	deck.schedule("WEIGHTS_OUT", 6, SimConstants.CEO)
	deck.schedule("WEIGHTS_OUT", 6, SimConstants.GOVERNANCE)
	assert_eq(deck.draw(ceo, null)["id"], "WEIGHTS_OUT")
	assert_eq(deck.draw(council, null)["id"], "WEIGHTS_OUT", "a once card still reaches the second player it was scheduled for")
	assert_false(deck._eligible(DilemmaDeck.get_template("WEIGHTS_OUT"), ceo), "but it is gone from the shuffled deck")
	deck.schedule("WEIGHTS_OUT", 7, SimConstants.CEO)
	ceo["turn"] = 7
	assert_ne(deck.draw(ceo, null)["id"], "WEIGHTS_OUT", "and never comes to the same player twice")


func test_a_standard_council_decade_meets_the_cast() -> void:
	var engine := SimulationEngine.new()
	engine.start_campaign(SimConstants.GOVERNANCE, 2076, {"autoplay": true})
	engine.run_headless(19)
	var met := Characters.met(engine.deck)
	assert_gte(met.size(), 3.0, "the Council meets several of the cast in Era I: %s" % str(met))
	var remembered := 0
	for character_id in met:
		if Characters.memory_line(character_id, engine.deck) != "":
			remembered += 1
	assert_gt(float(remembered), 0.0, "and someone remembers what it did")
	var follow_ups := engine.event_log.filter(func(e: Dictionary) -> bool:
		return e["category"] == "DILEMMA" and CHAINS.values().has(String(e.get("card", ""))))
	assert_gt(float(follow_ups.size()), 0.0, "a story chain closes within the decade")
