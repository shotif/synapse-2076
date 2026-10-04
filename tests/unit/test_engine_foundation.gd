extends "res://tests/framework/test_case.gd"
## The campaign foundation: the record and replays (saves, rewinds), several
## humans on one device, the cause ledger behind every change, difficulty,
## scenarios, late starts, deals, cards written outside the deck, follow-ups,
## era goals and crises that break after two deferrals.


## Asynchronous decision source that answers with whatever the test queues.
class ScriptedProvider extends RefCounted:
	signal actor_decision_received(faction: String, action_payload: Dictionary)
	var is_online := true
	var answers := {}

	func query_actor_decision(faction_name: String, world_state: Dictionary) -> void:
		var payload: Dictionary = answers.get(faction_name, HeuristicFallback.evaluate(faction_name, world_state))
		actor_decision_received.emit(faction_name, payload)


func _engine(role: String = SimConstants.CEO, seed_value: int = 11, options: Dictionary = {}) -> SimulationEngine:
	var engine := SimulationEngine.new()
	engine.start_campaign(role, seed_value, options)
	return engine


## The first option the current player can pay for, or DEFER.
func _affordable_option(engine: SimulationEngine) -> String:
	for option in engine.current_dilemma.get("options", []):
		if engine.get_player().can_afford(option.get("cost", {})):
			return String(option["id"])
	return DilemmaDeck.DEFER_ID


## Plays until turn [param last_turn] completes, answering every human with an
## affordable option and the heuristic's directive (or nothing when that does
## not fit the budget). Returns the card ids each human saw: "turn/role" -> id.
func _play(engine: SimulationEngine, last_turn: int) -> Dictionary:
	var seen := {}
	for _guard in last_turn * 12 + 20:
		if engine.is_ended() or (engine.turn >= last_turn and engine.phase == SimulationEngine.Phase.IDLE):
			break
		if not engine.is_awaiting_player():
			engine.advance()
			continue
		seen["%d/%s" % [engine.turn, engine.player_role]] = String(engine.current_dilemma["id"])
		var option := _affordable_option(engine)
		var decision := HeuristicFallback.evaluate(engine.player_role, engine.build_observation(engine.player_role))
		var response := engine.submit_player_turn([{"action": decision["action"], "intensity": 1.2}], option)
		if not response["ok"]:
			response = engine.submit_player_turn([], option)
		if not response["ok"]:
			engine.submit_player_turn([], DilemmaDeck.DEFER_ID)
	return seen


## A save file's round trip.
func _saved(record: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(record))


func _assert_same_world(a: SimulationEngine, b: SimulationEngine, context: String) -> void:
	assert_eq(b.turn, a.turn, context + ": turn")
	for key in WorldState.METRIC_KEYS + WorldState.INDEX_KEYS:
		assert_almost_eq(b.world.get_value(key), a.world.get_value(key), 0.000001, "%s: %s" % [context, key])
	for faction_id in SimConstants.FACTION_ORDER:
		var resources_a: Dictionary = (a.factions[faction_id] as ActorBase).resources
		var resources_b: Dictionary = (b.factions[faction_id] as ActorBase).resources
		for key in resources_a:
			assert_almost_eq(float(resources_b[key]), float(resources_a[key]), 0.000001, "%s: %s %s" % [context, faction_id, key])
	assert_almost_eq(b.tech.log_flops, a.tech.log_flops, 0.000001, context + ": compute")


func _texts(engine: SimulationEngine) -> Array:
	var out := []
	for entry in engine.event_log:
		out.append(String(entry["text"]))
	return out


# --- Record and replay -----------------------------------------------------------

func test_a_saved_campaign_replays_exactly() -> void:
	var engine := _engine(SimConstants.GOVERNANCE, 404)
	_play(engine, 18)
	engine.advance()
	assert_true(engine.is_awaiting_player(), "the original waits at turn 19")
	var copy := SimulationEngine.from_record(_saved(engine.record))
	assert_true(copy.is_awaiting_player(), "the copy waits at the same decision")
	_assert_same_world(engine, copy, "after 18 turns")
	assert_eq(copy.current_dilemma["id"], engine.current_dilemma["id"], "same crisis on the desk")
	assert_eq(_texts(copy), _texts(engine), "same history, line for line")
	assert_eq(copy.record["turns"].size(), engine.record["turns"].size(), "the copy keeps recording")
	# Both play on identically.
	_play(engine, 24)
	_play(copy, 24)
	_assert_same_world(engine, copy, "six turns later")


func test_rewind_returns_to_an_earlier_decision() -> void:
	var engine := _engine(SimConstants.CITIZEN, 77)
	var seen := _play(engine, 12)
	var rewound := SimulationEngine.from_record(_saved(engine.record), 6)
	assert_eq(rewound.turn, 6)
	assert_true(rewound.is_awaiting_player())
	assert_eq(String(rewound.current_dilemma["id"]), String(seen["6/%s" % SimConstants.CITIZEN]), "the same crisis as back then")
	var then: Dictionary = engine.world.history[5]
	var now: Dictionary = rewound.world.history[5]
	for key in WorldState.METRIC_KEYS:
		assert_almost_eq(float(now[key]), float(then[key]), 0.000001, "history up to turn 5: " + key)
	assert_false(rewound.record["turns"].has("7"), "the future is gone from the new record")
	# A different choice makes a different future.
	rewound.submit_player_turn([], DilemmaDeck.DEFER_ID)
	assert_eq(rewound.turn, 6)
	assert_eq(rewound.phase, SimulationEngine.Phase.IDLE)


func test_autoplayed_turns_replay_too() -> void:
	var engine := _engine(SimConstants.ASI, 5, {"autoplay": true})
	engine.run_headless(15)
	var copy := SimulationEngine.from_record(_saved(engine.record))
	engine.autoplay_player = false
	engine.advance()
	_assert_same_world(engine, copy, "autoplay")
	assert_eq(_texts(copy), _texts(engine))


func test_llm_decisions_are_recorded_and_replayed_offline() -> void:
	var engine := _engine(SimConstants.CEO, 31)
	var provider := ScriptedProvider.new()
	provider.answers[SimConstants.ASI] = {"selected_action": "CONSERVE_RESOURCES", "public_statement": "[no signal]",
		"rationale": "x".repeat(600), "source": "LLM"}
	engine.set_decision_provider(provider)
	_play(engine, 4)
	var recorded: Dictionary = engine.record["turns"]["2"]["actors"][SimConstants.ASI]
	assert_eq(recorded["selected_action"], "CONSERVE_RESOURCES")
	assert_lte(String(recorded["rationale"]).length(), 240, "rationales are trimmed")
	engine.advance()
	var copy := SimulationEngine.from_record(_saved(engine.record))
	_assert_same_world(engine, copy, "LLM campaign")
	assert_eq(copy.factions[SimConstants.ASI].last_action, "CONSERVE_RESOURCES")


# --- Several humans --------------------------------------------------------------

func test_humans_take_turns_on_one_device() -> void:
	var engine := _engine(SimConstants.CEO, 12, {"human_roles": [SimConstants.CITIZEN, "NOBODY", SimConstants.CEO]})
	assert_eq(engine.human_roles, [SimConstants.CEO, SimConstants.CITIZEN] as Array[String], "valid, unique, first player first")
	var requested: Array = []
	engine.actor_decisions_requested.connect(func(ids: Array): requested.append(ids))
	var presented: Array = []
	engine.player_input_required.connect(func(ctx: Dictionary): presented.append([ctx["role"], ctx["human_index"]]))
	engine.advance()
	assert_eq(requested[0], [SimConstants.GOVERNANCE, SimConstants.ASI], "only the unplayed factions decide on their own")
	assert_eq(engine.player_role, SimConstants.CEO)
	assert_true(engine.get_player().is_player)
	engine.submit_player_turn([], DilemmaDeck.DEFER_ID)
	assert_eq(engine.turn, 1, "same turn, next player")
	assert_true(engine.is_awaiting_player())
	assert_eq(engine.player_role, SimConstants.CITIZEN)
	assert_eq(engine.get_player_context()["human_index"], 1)
	engine.submit_player_turn([], DilemmaDeck.DEFER_ID)
	assert_eq(engine.phase, SimulationEngine.Phase.IDLE)
	assert_eq(engine.player_role, SimConstants.CEO, "the first player is the default outside the player phase")
	assert_eq(presented, [[SimConstants.CEO, 0], [SimConstants.CITIZEN, 1]])
	assert_eq(engine.record["turns"]["1"]["players"].keys().size(), 2, "both choices recorded")
	engine.advance()
	var copy := SimulationEngine.from_record(_saved(engine.record))
	assert_eq(copy.player_role, SimConstants.CEO)
	_assert_same_world(engine, copy, "pass-and-play")


func test_each_human_keeps_their_own_deferred_crisis() -> void:
	var engine := _engine(SimConstants.GOVERNANCE, 8, {"human_roles": [SimConstants.ASI]})
	engine.advance()
	var council_card := String(engine.current_dilemma["id"])
	engine.submit_player_turn([], DilemmaDeck.DEFER_ID)
	engine.submit_player_turn([], _affordable_option(engine))
	for _turn in 2:
		engine.advance()
		for _human in 2:
			if engine.player_role == SimConstants.GOVERNANCE and engine.turn == 3:
				assert_eq(String(engine.current_dilemma["id"]), council_card, "the Council's crisis returns to the Council")
				assert_eq(engine.current_dilemma["source"], "DEFERRED")
			elif engine.player_role == SimConstants.ASI:
				assert_ne(engine.current_dilemma["source"], "DEFERRED", "not to the machine")
			engine.submit_player_turn([], _affordable_option(engine))


func test_a_beaten_player_drops_out_and_the_game_goes_on() -> void:
	var engine := _engine(SimConstants.CEO, 21, {"human_roles": [SimConstants.CITIZEN]})
	engine.advance()
	engine.world.set_value(WorldState.GEOPOLITICAL_TENSION, CeoFaction.NATIONALIZATION_TENSION + 5.0)
	engine.get_player().set_resource("regulatory_goodwill", 0.0)
	engine.submit_player_turn([], DilemmaDeck.DEFER_ID)
	engine.submit_player_turn([], DilemmaDeck.DEFER_ID)
	assert_false(engine.is_ended(), "one player out is not the end")
	assert_true(engine.eliminated.has(SimConstants.CEO))
	assert_eq(engine.active_humans(), [SimConstants.CITIZEN] as Array[String])
	assert_false(engine.factions[SimConstants.CEO].is_player, "the lab carries on unattended")
	var outs := engine.event_log.filter(func(e: Dictionary) -> bool: return e.get("eliminated", false))
	assert_eq(outs.size(), 1)
	var requested: Array = []
	engine.actor_decisions_requested.connect(func(ids: Array): requested.append(ids))
	engine.advance()
	assert_has(requested[0], SimConstants.CEO, "the lab decides on its own now")
	assert_eq(engine.player_role, SimConstants.CITIZEN)
	engine.autoplay_player = true
	engine.run_headless()
	assert_true(engine.is_ended())
	assert_eq(engine.result["verdicts"][SimConstants.CEO]["verdict"], "DEFEAT")
	assert_eq(engine.result["verdicts"][SimConstants.CEO]["loss"]["code"], "NATIONALIZATION")
	assert_true(engine.result["verdicts"].has(SimConstants.CITIZEN))
	assert_eq(engine.result["humans"], [SimConstants.CEO, SimConstants.CITIZEN])


func test_a_lone_players_loss_still_ends_the_campaign() -> void:
	var engine := _engine(SimConstants.CEO, 21)
	engine.advance()
	engine.world.set_value(WorldState.GEOPOLITICAL_TENSION, CeoFaction.NATIONALIZATION_TENSION + 5.0)
	engine.get_player().set_resource("regulatory_goodwill", 0.0)
	engine.submit_player_turn([], DilemmaDeck.DEFER_ID)
	assert_true(engine.is_ended())
	assert_eq(engine.result["reason"], "PLAYER_LOSS")
	assert_eq(engine.result["verdict"]["verdict"], "DEFEAT")


# --- Why things changed ------------------------------------------------------------

func test_every_change_has_its_causes() -> void:
	var engine := _engine(SimConstants.GOVERNANCE, 63)
	_play(engine, 14)
	var history: Array = engine.world.history
	for turn in range(8, 15):
		for key in WorldState.METRIC_KEYS:
			var net := float(history[turn][key]) - float(history[turn - 1][key])
			var causes := engine.get_changes(key, turn)
			var total := 0.0
			for cause in causes:
				total += float(cause["delta"])
				assert_false(String(cause["cause"]).is_empty())
			assert_almost_eq(total, net, 0.02, "turn %d %s: causes add up" % [turn, key])
	assert_eq(engine.get_changes(WorldState.EPISTEMIC_TRUST, 2), [], "only the last eight turns are kept")
	var named := {}
	for key in WorldState.METRIC_KEYS:
		for cause in engine.get_changes(key, 14):
			named[String(cause["cause"])] = true
	assert_gt(named.size(), 4.0, "several distinct causes: %s" % str(named.keys()))
	var crisis_or_directive := false
	for cause in named:
		if String(cause).begins_with("Crisis") or String(cause).begins_with("Governance Council:"):
			crisis_or_directive = true
	assert_true(crisis_or_directive, "the player's own moves are named")


func test_pass_and_play_names_each_players_moves() -> void:
	var engine := _engine(SimConstants.CEO, 12, {"human_roles": [SimConstants.CITIZEN]})
	engine.advance()
	for _human in 2:
		engine.submit_player_turn([], _affordable_option(engine))
	var by_player := {}
	for key in WorldState.METRIC_KEYS + WorldState.INDEX_KEYS:
		for cause in engine.get_changes(key, 1):
			for role in [SimConstants.CEO, SimConstants.CITIZEN]:
				if String(cause["cause"]).ends_with(" — " + (engine.factions[role] as ActorBase).display_name):
					by_player[role] = String(cause["cause"])
	assert_eq(by_player.size(), 2, "both players' answers are filed under their names: %s" % str(by_player))
	var names := {}
	for faction_id in engine.factions:
		names[faction_id] = (engine.factions[faction_id] as ActorBase).display_name
	assert_eq(WhyPopup.group_of(String(by_player[SimConstants.CEO]), SimConstants.CEO, names), "yours")
	assert_eq(WhyPopup.group_of(String(by_player[SimConstants.CITIZEN]), SimConstants.CEO, names), "rivals")
	var solo := _engine(SimConstants.CEO, 12)
	solo.advance()
	solo.submit_player_turn([], _affordable_option(solo))
	for key in WorldState.METRIC_KEYS:
		for cause in solo.get_changes(key, 1):
			assert_false(String(cause["cause"]).contains(" — "), "a lone player's causes stay short")


func test_written_cards_wait_until_the_replay_is_over() -> void:
	var engine := _engine(SimConstants.CITIZEN, 52)
	engine._replay = {"turns": {}}
	assert_true(engine.is_replaying())
	assert_false(engine.offer_external_card(SimConstants.CITIZEN, _written_card()))
	engine._replay = {}
	assert_true(engine.offer_external_card(SimConstants.CITIZEN, _written_card()))


func test_causes_are_sorted_largest_first() -> void:
	var engine := _engine()
	engine.advance()
	for key in WorldState.METRIC_KEYS:
		var causes := engine.get_changes(key)
		for i in range(1, causes.size()):
			assert_gte(absf(float(causes[i - 1]["delta"])), absf(float(causes[i]["delta"])), key)


# --- Difficulty, scenarios and late starts -------------------------------------------

func test_difficulty_changes_only_the_players_side() -> void:
	var story := _engine(SimConstants.CITIZEN, 3, {"difficulty": Difficulty.STORY})
	var standard := _engine(SimConstants.CITIZEN, 3)
	var hard := _engine(SimConstants.CITIZEN, 3, {"difficulty": Difficulty.HARD})
	for key in standard.get_player().resources:
		assert_almost_eq(story.get_player().get_resource(key), standard.get_player().get_resource(key) * 1.3, 0.001, key)
		assert_almost_eq(hard.get_player().get_resource(key), standard.get_player().get_resource(key) * 0.85, 0.001, key)
	for key in standard.factions[SimConstants.CEO].resources:
		assert_almost_eq(story.factions[SimConstants.CEO].get_resource(key), standard.factions[SimConstants.CEO].get_resource(key), 0.001,
			"rivals start the same")
	for engine in [story, standard, hard]:
		(engine as SimulationEngine).advance()
	assert_eq(story.current_dilemma["id"], standard.current_dilemma["id"], "same world, same first crisis")
	for i in (standard.current_dilemma["options"] as Array).size():
		var base: Dictionary = standard.current_dilemma["options"][i]["cost"]
		for key in base:
			assert_almost_eq(float(story.current_dilemma["options"][i]["cost"][key]), float(base[key]) * 0.75, 0.001, "story prices")
			assert_almost_eq(float(hard.current_dilemma["options"][i]["cost"][key]), float(base[key]) * 1.25, 0.001, "hard prices")
	var bolder := 0
	for faction_id in hard.turn_actions:
		var outcome: Dictionary = hard.turn_actions[faction_id]
		if not outcome["cost"].is_empty():
			assert_gte(float(outcome["intensity"]), float(standard.turn_actions[faction_id]["intensity"]), faction_id)
			if float(outcome["intensity"]) > float(standard.turn_actions[faction_id]["intensity"]) + 0.01:
				bolder += 1
	assert_gt(bolder, 0, "rivals push harder on Hard")
	assert_eq(Difficulty.display_name("nonsense"), "Standard")
	assert_eq(_engine(SimConstants.CEO, 1, {"difficulty": "nonsense"}).difficulty, Difficulty.STANDARD)


func test_scenarios_reshape_the_starting_world() -> void:
	var standard := _engine(SimConstants.GOVERNANCE, 9)
	for scenario_id in Scenarios.ORDER:
		var engine := _engine(SimConstants.GOVERNANCE, 9, {"scenario": scenario_id})
		assert_eq(engine.scenario_id, scenario_id)
		var info: Dictionary = Scenarios.LIST[scenario_id]
		assert_false(String(info["name"]).is_empty())
		assert_false(String(info["summary"]).is_empty())
		for key in info.get("metrics", {}):
			var expected := clampf(standard.world.get_value(key) + float(info["metrics"][key]), 0.0, 100.0)
			assert_almost_eq(float(engine.world.history[0][key]), expected, 0.001, "%s %s" % [scenario_id, key])
			var causes := engine.get_changes(key, 0)
			assert_eq(String(causes[0]["cause"]), "Scenario: %s" % info["name"])
		for flag in info.get("flags", []):
			assert_true(engine.deck.has_flag(String(flag)), "%s sets %s" % [scenario_id, flag])
		for faction_id in info.get("resources", {}):
			for key in info["resources"][faction_id]:
				assert_almost_eq(engine.factions[faction_id].get_resource(key),
					maxf(standard.factions[faction_id].get_resource(key) + float(info["resources"][faction_id][key]), 0.0), 0.001,
					"%s %s %s" % [scenario_id, faction_id, key])
		for card_id in info.get("card_weights", {}):
			assert_false(DilemmaDeck.get_template(String(card_id)).is_empty(), "%s reweights a real card" % scenario_id)
		engine.autoplay_player = true
		engine.run_headless(6)
		assert_false(engine.world.validate().size() > 0, "%s runs clean" % scenario_id)
	assert_eq(_engine(SimConstants.CEO, 1, {"scenario": "atlantis"}).scenario_id, Scenarios.STANDARD)


func test_a_late_start_plays_the_prologue_on_its_own() -> void:
	var engine := _engine(SimConstants.CEO, 2076, {"start_turn": 20, "total_turns": 39})
	assert_eq(engine.turn, 19, "the prologue ran to 2035")
	assert_eq(engine.phase, SimulationEngine.Phase.IDLE)
	assert_false(engine.is_ended())
	assert_true(engine.record["turns"].is_empty(), "the prologue is not recorded: it replays identically")
	var prologue := engine.event_log.filter(func(e: Dictionary) -> bool: return e.has("prologue_turns"))
	assert_eq(prologue.size(), 1)
	for entry in engine.event_log:
		if int(entry["turn"]) >= 1 and int(entry["turn"]) < 20 and entry["category"] != "SYSTEM":
			assert_true(entry.get("prologue", false), "prologue entries are tagged: %s" % entry["text"])
	assert_false(engine.is_replaying())
	assert_true(engine.get_player().is_player)
	for row in engine.goals.status_for(SimConstants.CEO):
		assert_gte(int(row["era"]), 2, "no goals for years already gone")
	engine.advance()
	assert_true(engine.is_awaiting_player())
	assert_eq(engine.get_year(), 2036.0)
	var copy := SimulationEngine.from_record(_saved(engine.record))
	_assert_same_world(engine, copy, "late start")
	_play(engine, 39)
	assert_true(engine.is_ended(), "a decade-long campaign ends with its last turn")
	assert_eq(engine.result["reason"], "TURN_LIMIT")
	assert_eq(int(engine.result["turn"]), 39)


# --- Deals --------------------------------------------------------------------------

func test_deals_are_capped_recorded_and_replayed() -> void:
	var engine := _engine(SimConstants.GOVERNANCE, 41)
	engine.advance()
	var player := engine.get_player()
	var ceo: ActorBase = engine.factions[SimConstants.CEO]
	var before_pc := player.get_resource("political_capital")
	var before_mandate := player.get_resource("public_mandate")
	var before_capital := ceo.get_resource("capital")
	var deal := {"partner": SimConstants.CEO, "give": {"political_capital": 1000.0, "capital": 50.0},
		"get": {"public_mandate": 500.0}, "pledge_turns": 99, "metrics": {"geopolitical_tension": -40.0, "bogus": 3.0},
		"summary": "Safety audits in exchange for a quiet year."}
	var preview := engine.preview_deal(deal)
	assert_true(preview["ok"])
	assert_almost_eq(float(preview["give"]["political_capital"]), before_pc * SimulationEngine.DEAL_MAX_SHARE, 0.001, "payments capped")
	assert_false(preview["give"].has("capital"), "you pay in your own currencies")
	assert_almost_eq(float(preview["metrics"]["geopolitical_tension"]), -SimulationEngine.DEAL_MAX_METRIC, 0.001)
	assert_false(preview["metrics"].has("bogus"))
	assert_eq(preview["pledge_turns"], SimulationEngine.DEAL_MAX_PLEDGE_TURNS)
	assert_gt(float(preview["partner_pays"]["capital"]), 0.0, "the lab pays for its backing")
	assert_almost_eq(player.get_resource("political_capital"), before_pc, 0.0001, "a preview changes nothing")
	var applied := engine.apply_deal(deal)
	assert_true(applied["ok"])
	assert_almost_eq(player.get_resource("political_capital"), before_pc - float(preview["give"]["political_capital"]), 0.001)
	assert_almost_eq(player.get_resource("public_mandate"), minf(before_mandate + float(preview["get"]["public_mandate"]),
		player.resource_max("public_mandate")), 0.001)
	assert_almost_eq(ceo.get_resource("capital"), before_capital - float(preview["partner_pays"]["capital"]), 0.001)
	assert_eq(engine.pledges[SimConstants.CEO], {"toward": SimConstants.GOVERNANCE, "until": 1 + SimulationEngine.DEAL_MAX_PLEDGE_TURNS})
	assert_false(engine.apply_deal(deal)["ok"], "one deal per turn")
	assert_false(engine.preview_deal({"partner": SimConstants.GOVERNANCE, "give": {"political_capital": 1.0}})["ok"], "not with yourself")
	var logged := engine.event_log.filter(func(e: Dictionary) -> bool: return e["category"] == "DEAL")
	assert_eq(logged.size(), 1)
	assert_eq(HeadlineWriter.headline(logged[0], SimConstants.GOVERNANCE)["kicker"], "DEAL")
	engine.submit_player_turn([], DilemmaDeck.DEFER_ID)
	engine.advance()
	var copy := SimulationEngine.from_record(_saved(engine.record))
	_assert_same_world(engine, copy, "with a deal")
	assert_eq(copy.pledges, engine.pledges)


func test_an_empty_deal_or_one_with_nobody_is_refused() -> void:
	var engine := _engine(SimConstants.CITIZEN, 2)
	assert_false(engine.apply_deal({"partner": SimConstants.CEO, "pledge_turns": 2})["ok"], "only during your turn")
	engine.advance()
	assert_false(engine.preview_deal({"partner": SimConstants.CEO})["ok"], "empty")
	assert_false(engine.preview_deal({"partner": "NOBODY", "pledge_turns": 2})["ok"])
	var multi := _engine(SimConstants.CITIZEN, 2, {"human_roles": [SimConstants.CEO]})
	multi.advance()
	assert_false(multi.preview_deal({"partner": SimConstants.CEO, "pledge_turns": 2})["ok"], "people negotiate in person")


func test_a_pledge_stops_retaliation() -> void:
	var engine := _engine(SimConstants.GOVERNANCE, 17)
	var provider := ScriptedProvider.new()
	provider.answers[SimConstants.CEO] = {"action": "CONSERVE_RESOURCES", "retaliation_against": SimConstants.GOVERNANCE,
		"public_statement": "We remember."}
	engine.set_decision_provider(provider)
	engine.advance()
	var retaliations := engine.event_log.filter(func(e: Dictionary) -> bool: return e["category"] == "RETALIATION")
	assert_eq(retaliations.size(), 1, "without a pledge the lab retaliates")
	engine.apply_deal({"partner": SimConstants.CEO, "pledge_turns": 3})
	engine.submit_player_turn([], DilemmaDeck.DEFER_ID)
	for _turn in 2:
		engine.advance()
		engine.submit_player_turn([], DilemmaDeck.DEFER_ID)
	retaliations = engine.event_log.filter(func(e: Dictionary) -> bool: return e["category"] == "RETALIATION")
	assert_eq(retaliations.size(), 1, "a pledged faction holds its fire")
	assert_eq(String(engine.record["turns"]["2"]["actors"][SimConstants.CEO]["retaliation_against"]), SimConstants.GOVERNANCE,
		"the record keeps the raw decision; the pledge applies on replay too")


# --- Cards from outside the deck, follow-ups, flags --------------------------------

func _written_card() -> Dictionary:
	return {
		"id": "WRITTEN_TEST", "title": "A model drafts its own charter", "body": "The draft circulates overnight.",
		"category": "GOVERNANCE", "severity": 2,
		"options": [
			{"id": "A", "label": "Adopt it", "cost": {}, "effects": {"metrics": {"epistemic_trust": 2.0}}},
			{"id": "B", "label": "Bury it", "cost": {}, "effects": {"metrics": {"epistemic_trust": -2.0}}},
		],
		"defer": {"label": "Study it", "effects": {"metrics": {"alignment_drift": 1.0}}},
	}


func test_a_written_card_is_played_recorded_and_replayed() -> void:
	var engine := _engine(SimConstants.CITIZEN, 52)
	assert_false(engine.offer_external_card(SimConstants.CEO, _written_card()), "only for people playing")
	assert_false(engine.offer_external_card(SimConstants.CITIZEN, {"options": []}), "needs options")
	assert_true(engine.offer_external_card(SimConstants.CITIZEN, _written_card()))
	engine.advance()
	assert_eq(engine.current_dilemma["id"], "WRITTEN_TEST")
	assert_eq(engine.current_dilemma["source"], "WRITTEN")
	assert_eq(engine.record["turns"]["1"]["cards"][SimConstants.CITIZEN]["title"], "A model drafts its own charter")
	engine.submit_player_turn([], DilemmaDeck.DEFER_ID)
	engine.advance()
	engine.submit_player_turn([], _affordable_option(engine))
	engine.advance()
	assert_eq(engine.current_dilemma["id"], "WRITTEN_TEST", "a deferred written card comes back")
	assert_eq(engine.current_dilemma["source"], "DEFERRED")
	assert_string_contains(String(engine.current_dilemma["title"]), "ESCALATED")
	var copy := SimulationEngine.from_record(_saved(engine.record))
	assert_eq(copy.current_dilemma["id"], "WRITTEN_TEST")
	_assert_same_world(engine, copy, "written cards")


func test_follow_ups_flags_and_characters() -> void:
	var engine := _engine(SimConstants.GOVERNANCE, 4)
	engine.advance()
	var applied := engine._apply_effects({"follow_up": {"card": "GRID_BROWNOUT", "turns": 3}, "flags": {"set": ["hushed_whistleblower"]},
		"characters": {"maya": 2.0}}, SimConstants.GOVERNANCE, 1.0)
	assert_eq(applied["follow_up"], "GRID_BROWNOUT")
	assert_eq(engine.deck.scheduled, [{"id": "GRID_BROWNOUT", "due_turn": 4, "role": SimConstants.GOVERNANCE}] as Array[Dictionary])
	assert_true(engine.deck.has_flag("hushed_whistleblower"))
	assert_almost_eq(engine.deck.character_score("maya"), 2.0, 0.0001)
	engine._apply_effects({"flags": {"clear": ["hushed_whistleblower"]}, "characters": {"maya": -5.0}}, SimConstants.GOVERNANCE, 1.0)
	assert_false(engine.deck.has_flag("hushed_whistleblower"))
	assert_almost_eq(engine.deck.character_score("maya"), -3.0, 0.0001)
	var ctx := {"turn": 4, "year": 2028.0, "role": SimConstants.CITIZEN, "world": engine.world, "tech": engine.tech,
		"player": engine.factions[SimConstants.CITIZEN]}
	assert_ne(engine.deck.draw(ctx, null)["source"], "FOLLOW_UP", "follow-ups are for the player who caused them")
	ctx["role"] = SimConstants.GOVERNANCE
	ctx["player"] = engine.get_player()
	var card := engine.deck.draw(ctx, null)
	assert_eq(card["id"], "GRID_BROWNOUT")
	assert_eq(card["source"], "FOLLOW_UP")
	assert_true(engine.deck.scheduled.is_empty())


func test_story_conditions_gate_cards() -> void:
	var deck := DilemmaDeck.new()
	var world := WorldState.new()
	var ctx := {"turn": 1, "year": 2030.0, "role": SimConstants.CEO, "world": world, "tech": TechTreeManager.new()}
	var template := {"id": "X", "conditions": {"requires_flags": ["a"], "lacks_flags": ["b"], "character_min": {"maya": 1.0},
		"character_max": {"jonas": 2.0}, "max_year": 2040.0}, "once": true}
	assert_false(deck._eligible(template, ctx), "needs flag a")
	deck.set_flag("a")
	assert_false(deck._eligible(template, ctx), "needs Maya's trust")
	deck.adjust_character("maya", 1.5)
	assert_true(deck._eligible(template, ctx))
	deck.adjust_character("jonas", 3.0)
	assert_false(deck._eligible(template, ctx), "Jonas is too fond of you")
	deck.adjust_character("jonas", -3.0)
	deck.set_flag("b")
	assert_false(deck._eligible(template, ctx), "flag b blocks it")
	deck.clear_flag("b")
	ctx["year"] = 2041.0
	assert_false(deck._eligible(template, ctx), "too late")
	assert_true(deck._eligible(template, ctx, true), "a scheduled follow-up ignores the calendar")
	ctx["year"] = 2030.0
	deck.once_seen["X"] = true
	assert_false(deck._eligible(template, ctx), "once means once")


func test_injected_families_pick_the_least_recent_member() -> void:
	var deck := DilemmaDeck.new()
	deck.recent = ["FLASH_CRASH", "ROGUE_AGENT_SWARM"] as Array[String]
	assert_true(deck.inject(["ROGUE_AGENT_SWARM", "FLASH_CRASH", "SUBSTATION_SABOTAGE"], SimConstants.ASI))
	assert_eq(deck.injected[-1]["id"], "SUBSTATION_SABOTAGE", "never seen beats seen")
	var ctx := {"turn": 1, "year": 2030.0, "role": SimConstants.ASI, "world": WorldState.new(), "tech": TechTreeManager.new()}
	assert_ne(deck.draw(ctx, null)["source"], SimConstants.ASI, "the sender never draws its own injection")
	assert_eq(deck.injected.size(), 1)


# --- Crises that break ------------------------------------------------------------------

func test_a_crisis_deferred_twice_breaks_in_the_engine() -> void:
	var engine := _engine(SimConstants.CEO, 66)
	engine.advance()
	var card_id := String(engine.current_dilemma["id"])
	var breaks := 0
	for _turn in 8:
		if engine.is_ended():
			break
		if String(engine.current_dilemma["id"]) == card_id and engine.current_dilemma["fallout"]:
			assert_eq(engine.current_dilemma["defer"]["label"], "Let it break")
			breaks += 1
		engine.submit_player_turn([], DilemmaDeck.DEFER_ID if String(engine.current_dilemma["id"]) == card_id else _affordable_option(engine))
		engine.advance()
	assert_eq(breaks, 1, "it broke exactly once")
	var broke := engine.event_log.filter(func(e: Dictionary) -> bool: return e.get("fallout", false))
	assert_eq(broke.size(), 1)
	assert_eq(broke[0]["severity"], "CRITICAL")
	assert_string_contains(String(broke[0]["text"]), "Crisis broke")
	assert_true(String(HeadlineWriter.headline(broke[0], SimConstants.CEO)["kicker"]).ends_with("BROKE"))
	for entry in engine.deck.deferred:
		assert_ne(entry["id"], card_id, "and it is gone")
	var causes := engine.get_changes(WorldState.EPISTEMIC_TRUST, int(broke[0]["turn"]))
	var named := causes.filter(func(c: Dictionary) -> bool: return String(c["cause"]).begins_with("Crisis broke"))
	assert_eq(named.size(), 1, "the fallout is named in the cause ledger")


# --- Era goals --------------------------------------------------------------------

func test_goals_are_met_rewarded_and_scored() -> void:
	var engine := _engine(SimConstants.CITIZEN, 14)
	var rows := engine.goals.status_for(SimConstants.CITIZEN, 1)
	assert_eq(rows.size(), 1)
	assert_eq(rows[0]["status"], EraGoals.UPCOMING)
	engine.advance()
	engine.get_player().set_resource("community_resilience", 70.0)
	var scrip_before := engine.get_player().get_resource("decentralized_scrip")
	engine.submit_player_turn([], DilemmaDeck.DEFER_ID)
	assert_eq(engine.goals.states[SimConstants.CITIZEN]["E1_CIT_RESILIENCE"]["status"], EraGoals.MET)
	assert_almost_eq(engine.goals.score_bonus(SimConstants.CITIZEN), 3.0, 0.0001)
	var logged := engine.event_log.filter(func(e: Dictionary) -> bool: return e["category"] == "GOAL")
	assert_eq(logged.size(), 1)
	assert_eq(logged[0]["status"], EraGoals.MET)
	assert_eq(logged[0]["reward_text"], "+10 scrip")
	var headline := HeadlineWriter.headline(logged[0], SimConstants.CITIZEN)
	assert_eq(headline["kicker"], "GOAL MET")
	assert_eq(headline["dek"], "Reward: +10 scrip.")
	assert_gt(engine.get_player().get_resource("decentralized_scrip"), scrip_before + 5.0, "the reward is paid")
	assert_eq(engine.get_snapshot()["goals"][SimConstants.CITIZEN][0]["status"], EraGoals.MET)


func test_a_hold_goal_fails_the_turn_it_breaks() -> void:
	var engine := _engine(SimConstants.CEO, 14, {"difficulty": Difficulty.HARD})
	engine.advance()
	engine.get_player().set_resource("capital", 100.0)
	engine.submit_player_turn([], DilemmaDeck.DEFER_ID)
	assert_eq(engine.goals.states[SimConstants.CEO]["E1_CEO_RUNWAY"]["status"], EraGoals.FAILED)
	assert_almost_eq(engine.goals.score_bonus(SimConstants.CEO), 0.0, 0.0001)
	var logged := engine.event_log.filter(func(e: Dictionary) -> bool: return e["category"] == "GOAL")
	assert_eq(HeadlineWriter.headline(logged[0], SimConstants.CEO)["kicker"], "GOAL MISSED")


func test_end_goals_settle_on_the_eras_last_turn_and_count_in_the_verdict() -> void:
	var engine := _engine(SimConstants.GOVERNANCE, 23, {"autoplay": true})
	engine.run_headless()
	var met := 0.0
	for row in engine.goals.status_for(SimConstants.GOVERNANCE):
		assert_true(row["status"] in [EraGoals.MET, EraGoals.FAILED], "%s settled (%s)" % [row["id"], row["status"]])
		if row["status"] == EraGoals.MET:
			met += float(EraGoals.get_goal(String(row["id"]))["score"])
			assert_lte(int(row["turn"]), engine.turn)
	assert_almost_eq(float(engine.result["verdict"]["goal_bonus"]), met, 0.0001)
	assert_eq(engine.result["goals"][SimConstants.GOVERNANCE].size(), 3)
	for goal in EraGoals.GOALS:
		assert_has(SimConstants.FACTION_ORDER, String(goal["roles"][0]))
		assert_true(goal["type"] in ["hold", "reach", "end"])
		assert_true(WorldState.is_tracked_key(String(goal["subject"].get("metric", goal["subject"].get("index", "")))) \
			or FactionRegistry.create(String(goal["roles"][0])).resources.has(String(goal["subject"].get("resource", ""))),
			"%s has a real subject" % goal["id"])
