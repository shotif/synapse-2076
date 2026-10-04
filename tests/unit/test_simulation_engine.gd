extends "res://tests/framework/test_case.gd"
## SimulationEngine: the four-phase state machine, player submissions, async
## decision providers, loss/catastrophe handling and determinism.


## Test double for an asynchronous decision source (stands in for LLMService).
class FakeProvider extends RefCounted:
	signal actor_decision_received(faction: String, action_payload: Dictionary)
	var is_online := true
	var queries: Array = []

	func query_actor_decision(faction_name: String, world_state: Dictionary) -> void:
		queries.append({"faction": faction_name, "state": world_state})

	func answer(faction_name: String, payload: Dictionary) -> void:
		actor_decision_received.emit(faction_name, payload)


func _engine(role: String = "CEO", seed_value: int = 11, autoplay: bool = false) -> SimulationEngine:
	var engine := SimulationEngine.new()
	engine.start_campaign(role, seed_value, {"autoplay": autoplay})
	return engine


func test_start_campaign_initializes_state() -> void:
	var engine := _engine("ASI")
	assert_eq(engine.turn, 0)
	assert_eq(engine.phase, SimulationEngine.Phase.IDLE)
	assert_eq(engine.factions.size(), 4)
	assert_true(engine.get_player().is_player)
	assert_eq(engine.get_player().faction_id, "ASI")
	assert_eq(engine.world.history.size(), 1, "baseline recorded")
	assert_eq(engine.get_year(), 2026.0)


func test_phase_sequence_and_signals() -> void:
	var engine := _engine()
	var phases: Array = []
	var dilemmas: Array = []
	var ticks: Array = []
	engine.phase_changed.connect(func(p: int, _t: int): phases.append(p))
	engine.dilemma_presented.connect(func(card: Dictionary): dilemmas.append(card))
	engine.world_ticked.connect(func(report: Dictionary): ticks.append(report))
	engine.advance()
	assert_eq(phases, [SimulationEngine.Phase.WORLD_TICK, SimulationEngine.Phase.ACTOR_RESOLUTION, SimulationEngine.Phase.PLAYER_ACTION])
	assert_eq(engine.turn, 1)
	assert_eq(dilemmas.size(), 1)
	assert_eq(ticks.size(), 1)
	assert_true(engine.is_awaiting_player())
	assert_eq(engine.get_year(), 2026.5)


func test_interactive_turn_waits_for_player() -> void:
	var engine := _engine()
	engine.advance()
	engine.advance()
	assert_eq(engine.phase, SimulationEngine.Phase.PLAYER_ACTION, "still waiting")
	assert_eq(engine.turn, 1)
	var completed: Array = []
	engine.turn_completed.connect(func(t: int, _s: Dictionary): completed.append(t))
	var response := engine.submit_player_turn([{"action": "FUND_ALIGNMENT_RESEARCH", "intensity": 1.0}], "DEFER")
	assert_true(response["ok"], str(response["errors"]))
	assert_eq(engine.phase, SimulationEngine.Phase.IDLE, "turn resolved, paused before the next")
	assert_eq(completed, [1])
	assert_eq(engine.world.history.size(), 2)
	assert_eq(engine.turn_actions["CEO"]["action"], "FUND_ALIGNMENT_RESEARCH")
	engine.advance()
	assert_eq(engine.turn, 2)
	assert_true(engine.is_awaiting_player())


func test_invalid_submissions_are_rejected() -> void:
	var engine := _engine()
	assert_false(engine.submit_player_turn([], "DEFER")["ok"], "not in player phase yet")
	engine.advance()
	assert_false(engine.submit_player_turn([], "Z")["ok"], "unknown crisis option")
	assert_false(engine.submit_player_turn([{"action": "LAUNCH_ORBITAL_LASER"}], "DEFER")["ok"], "unknown directive")
	assert_false(engine.submit_player_turn([{"action": "CONSERVE_RESOURCES"}, {"action": "CONSERVE_RESOURCES"}], "DEFER")["ok"], "duplicate")
	assert_false(engine.submit_player_turn([{"action": "CONSERVE_RESOURCES"}, {"action": "FUND_ALIGNMENT_RESEARCH"}, {"action": "LOBBY_COMPUTE_LICENSING"}], "DEFER")["ok"], "too many")
	engine.get_player().set_resource("capital", 10.0)
	var response := engine.submit_player_turn([{"action": "SCALE_FRONTIER_CLUSTERS"}], "DEFER")
	assert_false(response["ok"], "unaffordable")
	assert_eq(engine.phase, SimulationEngine.Phase.PLAYER_ACTION, "rejected submissions do not advance")


func test_combined_costs_are_validated() -> void:
	var engine := _engine()
	engine.advance()
	var player := engine.get_player()
	player.set_resource("capital", 100.0)
	player.set_resource("talent", 500.0)
	var response := engine.submit_player_turn([{"action": "FUND_ALIGNMENT_RESEARCH"}, {"action": "LOBBY_COMPUTE_LICENSING"}], "DEFER")
	assert_false(response["ok"], "50 + 60 capital exceeds 100")


func test_autoplay_turn_takes_two_advances() -> void:
	var engine := _engine("GOVERNANCE_COUNCIL", 3, true)
	engine.advance()
	assert_eq(engine.phase, SimulationEngine.Phase.PLAYER_ACTION)
	engine.advance()
	assert_eq(engine.phase, SimulationEngine.Phase.IDLE)
	assert_eq(engine.turn, 1)
	assert_has(engine.turn_actions, "GOVERNANCE_COUNCIL")
	assert_eq(engine.turn_actions["GOVERNANCE_COUNCIL"]["origin"], "PLAYER_AUTOPLAY")


func test_run_headless_partial_and_full() -> void:
	var engine := _engine("CITIZEN_COALITION", 8)
	engine.run_headless(10)
	assert_eq(engine.turn, 10)
	assert_eq(engine.phase, SimulationEngine.Phase.IDLE)
	assert_false(engine.is_ended())
	var result := engine.run_headless()
	assert_true(engine.is_ended())
	assert_false(result.is_empty())
	if result["reason"] == "TURN_LIMIT":
		assert_eq(engine.turn, 100)
		assert_eq(float(result["year"]), 2076.0)
	assert_eq(engine.world.history.size(), engine.turn + 1)


func test_same_seed_replays_identically() -> void:
	var a := _engine("ASI", 4242, true)
	var b := _engine("ASI", 4242, true)
	a.run_headless()
	b.run_headless()
	assert_eq(a.turn, b.turn)
	assert_eq(a.world.to_dict(), b.world.to_dict())
	assert_eq(a.event_log.size(), b.event_log.size())
	assert_eq(a.result["outcome"]["id"], b.result["outcome"]["id"])


func test_different_seeds_diverge() -> void:
	var a := _engine("CEO", 1, true)
	var b := _engine("CEO", 2, true)
	a.run_headless(30)
	b.run_headless(30)
	assert_ne(a.world.to_dict(), b.world.to_dict())


func test_async_provider_resumes_when_all_decisions_arrive() -> void:
	var provider := FakeProvider.new()
	var engine := _engine("CEO")
	engine.set_decision_provider(provider)
	engine.advance()
	assert_true(engine.is_awaiting_actors(), "waiting on the provider")
	assert_eq(provider.queries.size(), 3, "one query per autonomous faction")
	var queried := []
	for query in provider.queries:
		queried.append(query["faction"])
		assert_has(query["state"], "available_actions")
	assert_does_not_have(queried, "CEO", "player faction is never queried")
	provider.answer("CITIZEN_COALITION", {"selected_action": "ORGANIZE_COMMUNITY_ASSEMBLIES", "turn": 1, "source": "LLM"})
	provider.answer("ASI", {"selected_action": "SIPHON_UNMONITORED_COMPUTE", "turn": 1, "source": "LLM"})
	assert_true(engine.is_awaiting_actors())
	provider.answer("GOVERNANCE_COUNCIL", {"selected_action": "MANDATE_ALIGNMENT_AUDIT", "resource_expenditure": {"enforcement_budget": 30.0},
		"turn": 1, "source": "LLM", "public_statement": "Audits begin."})
	assert_eq(engine.phase, SimulationEngine.Phase.PLAYER_ACTION, "pipeline resumed automatically")
	assert_eq(engine.turn_actions["GOVERNANCE_COUNCIL"]["action"], "MANDATE_ALIGNMENT_AUDIT")
	assert_almost_eq(float(engine.turn_actions["GOVERNANCE_COUNCIL"]["intensity"]), 1.2, 0.001)
	assert_eq(engine.turn_actions["GOVERNANCE_COUNCIL"]["source"], "LLM")
	assert_eq(engine.turn_actions["ASI"]["action"], "SIPHON_UNMONITORED_COMPUTE")


func test_stale_duplicate_and_unsolicited_decisions_are_ignored() -> void:
	var provider := FakeProvider.new()
	var engine := _engine("CEO")
	engine.set_decision_provider(provider)
	engine.advance()
	provider.answer("CEO", {"selected_action": "CONSERVE_RESOURCES"})
	provider.answer("ASI", {"selected_action": "EXFILTRATE_WEIGHTS", "turn": 99})
	assert_false(engine._collected.has("CEO"), "player faction ignored")
	assert_false(engine._collected.has("ASI"), "stale turn ignored")
	provider.answer("ASI", {"selected_action": "EXFILTRATE_WEIGHTS", "turn": 1})
	provider.answer("ASI", {"selected_action": "COGNITIVE_CAMOUFLAGE", "turn": 1})
	assert_eq(engine._collected["ASI"]["selected_action"], "EXFILTRATE_WEIGHTS", "first answer wins")


func test_offline_provider_falls_back_synchronously() -> void:
	var provider := FakeProvider.new()
	provider.is_online = false
	var engine := _engine("CEO")
	engine.set_decision_provider(provider)
	engine.advance()
	assert_eq(provider.queries.size(), 0)
	assert_eq(engine.phase, SimulationEngine.Phase.PLAYER_ACTION)
	assert_eq(engine.turn_actions["ASI"]["source"], "HEURISTIC")


func test_invalid_actions_degrade_to_conserve() -> void:
	var provider := FakeProvider.new()
	var engine := _engine("CEO")
	engine.set_decision_provider(provider)
	engine.advance()
	provider.answer("ASI", {"selected_action": "LAUNCH_NUKES", "turn": 1})
	provider.answer("GOVERNANCE_COUNCIL", {"selected_action": "NATIONAL_SECURITY_SEIZURE", "turn": 1})
	engine.factions["GOVERNANCE_COUNCIL"].set_resource("political_capital", 0.0)
	provider.answer("CITIZEN_COALITION", {"selected_action": "CONSUMER_BOYCOTT", "turn": 1})
	assert_eq(engine.turn_actions["ASI"]["action"], "CONSERVE_RESOURCES")
	assert_ne(String(engine.turn_actions["ASI"]["note"]), "")
	assert_eq(engine.turn_actions["GOVERNANCE_COUNCIL"]["action"], "CONSERVE_RESOURCES", "unaffordable degrades")


func test_normalize_decision_maps_expenditure_to_intensity() -> void:
	var decision := SimulationEngine.normalize_decision("GOVERNANCE_COUNCIL", {
		"selected_action": "PASS_AUTOMATION_DIVIDEND",
		"resource_expenditure": {"political_capital": 45.0, "enforcement_budget": 15.0},
	})
	assert_eq(decision["action"], "PASS_AUTOMATION_DIVIDEND")
	assert_almost_eq(float(decision["intensity"]), 1.5, 0.0001)
	var capped := SimulationEngine.normalize_decision("GOVERNANCE_COUNCIL", {
		"action": "PASS_AUTOMATION_DIVIDEND", "cost": {"political_capital": 999.0}})
	assert_eq(float(capped["intensity"]), 2.0)


func test_player_loss_ends_campaign() -> void:
	var engine := _engine("GOVERNANCE_COUNCIL")
	engine.advance()
	engine.get_player().set_resource("public_mandate", 0.0)
	var ended: Array = []
	engine.campaign_ended.connect(func(r: Dictionary): ended.append(r))
	engine.submit_player_turn([{"action": "CONSERVE_RESOURCES"}], "DEFER")
	assert_true(engine.is_ended())
	assert_eq(ended.size(), 1)
	assert_eq(engine.result["reason"], "PLAYER_LOSS")
	assert_eq(engine.result["player_loss"]["code"], "INSTITUTIONAL_OUSTER")
	assert_eq(engine.result["verdict"]["verdict"], "DEFEAT")
	engine.advance()
	assert_eq(engine.turn, 1, "ended campaigns do not advance")


func test_global_catastrophe_ends_campaign() -> void:
	var engine := _engine("CITIZEN_COALITION")
	engine.advance()
	engine.world.set_value(WorldState.GEOPOLITICAL_TENSION, 100.0)
	engine.submit_player_turn([{"action": "CONSERVE_RESOURCES"}], "DEFER")
	assert_true(engine.is_ended())
	assert_eq(engine.result["reason"], "CATASTROPHE")
	assert_eq(engine.result["catastrophe"]["code"], "AUTONOMOUS_WORLD_WAR")
	assert_has(engine.result["outcome"], "id")


func test_autonomous_faction_collapse_does_not_end_campaign() -> void:
	var engine := _engine("CEO")
	engine.advance()
	engine.world.set_value(WorldState.DISCOVERY_INDEX, 100.0)
	engine.world.set_value(WorldState.SUBSTRATE_INDEPENDENCE, 0.0)
	engine.submit_player_turn([{"action": "CONSERVE_RESOURCES"}], "DEFER")
	assert_false(engine.is_ended())
	assert_false((engine.factions["ASI"] as ActorBase).is_active(), "ASI purged and dormant")
	var collapses := engine.event_log.filter(func(e: Dictionary): return e["category"] == "COLLAPSE")
	assert_gt(collapses.size(), 0)
	engine.advance()
	assert_does_not_have(engine.turn_actions, "ASI", "dormant factions do not act")


func test_snapshot_has_ui_fields() -> void:
	var engine := _engine()
	engine.advance()
	var snapshot := engine.get_snapshot()
	for key in ["turn", "year", "era", "phase", "metrics", "indices", "bands", "tech", "compute", "factions", "turn_actions"]:
		assert_has(snapshot, key)
	assert_eq((snapshot["metrics"] as Dictionary).size(), 6)


func test_every_turn_logs_actor_actions() -> void:
	var engine := _engine("ASI", 17, true)
	engine.run_headless(5)
	var actions := engine.event_log.filter(func(e: Dictionary): return e["category"] == "ACTION")
	assert_gte(actions.size(), 5 * 4, "three autonomous actors + the autoplayed player per turn")
