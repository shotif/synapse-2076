extends "res://tests/framework/test_case.gd"
## The dashboard with the campaign foundation: options passed to the engine,
## resuming a rebuilt campaign, and several players taking turns.

const DashboardScene := preload("res://ui/main_dashboard.tscn")

var dashboard: Control


func before_all() -> void:
	ProjectSettings.set_setting("synapse/llm/probe_on_start", false)


func before_each() -> void:
	dashboard = DashboardScene.instantiate()
	tree.root.add_child(dashboard)
	await tree.process_frame


func after_each() -> void:
	dashboard.queue_free()
	await tree.process_frame


func _answer(option: String = DilemmaDeck.DEFER_ID) -> void:
	var dialog: DilemmaDialog = dashboard.get_node("%DilemmaDialog")
	dialog.choose(option)
	dashboard.get_node("%DirectivePanel")._on_execute_pressed()


func test_options_reach_the_engine() -> void:
	dashboard.start_campaign(SimConstants.CITIZEN, 9, false, {"difficulty": Difficulty.HARD, "scenario": "chip_war",
		"start_turn": 20, "total_turns": 39})
	await tree.process_frame
	var engine: SimulationEngine = dashboard.engine
	assert_eq(engine.difficulty, Difficulty.HARD)
	assert_eq(engine.scenario_id, "chip_war")
	assert_eq(engine.turn, 20, "the prologue ran and the first played turn waits")
	assert_true(engine.is_awaiting_player())
	assert_gt(dashboard._newswire.entry_count(), 3, "the prologue's news is on the wire")
	var front_page: FrontPage = dashboard.get_node("FrontPage")
	assert_true(front_page.visible, "the years played on autopilot get their front page")
	front_page._turn_page()
	(dashboard.get_node("EraUpgrade") as EraUpgrade).finish_now()
	await tree.process_frame
	assert_eq(dashboard.era, 2, "then the interface upgrades to the era the campaign starts in")
	assert_true(dashboard.get_node("%DilemmaDialog").visible, "and the first crisis waits")
	assert_string_contains(dashboard.get_node("%YearLabel").text, "20 / 39", "Era II counts turns its own way")


func test_a_rebuilt_campaign_resumes_where_it_stopped() -> void:
	dashboard.start_campaign(SimConstants.GOVERNANCE, 77, false)
	await tree.process_frame
	for _turn in 3:
		_answer()
		dashboard._begin_next_turn()
		await tree.process_frame
	var engine: SimulationEngine = dashboard.engine
	assert_eq(engine.turn, 4)
	var rebuilt := SimulationEngine.from_record(JSON.parse_string(JSON.stringify(engine.record)))
	dashboard.resume_campaign(rebuilt)
	await tree.process_frame
	assert_eq(dashboard.engine, rebuilt)
	assert_true(rebuilt.is_awaiting_player())
	assert_eq(rebuilt.current_dilemma["id"], engine.current_dilemma["id"])
	assert_true(dashboard.get_node("%DilemmaDialog").visible, "the waiting crisis is back on the desk")
	assert_false(dashboard.get_node("%RoleSelect").visible)
	assert_gt(dashboard._newswire.entry_count(), 3, "the wire shows the story so far")
	var meter: MeterBar = dashboard._meters["alignment_drift"]
	assert_gt(meter.history.size(), 3, "the meters remember the trend")
	assert_almost_eq(meter.value, rebuilt.world.alignment_drift, 0.001)
	_answer()
	assert_eq(rebuilt.phase, SimulationEngine.Phase.IDLE, "and play goes on")
	var rewound := SimulationEngine.from_record(rebuilt.record, 2)
	dashboard.resume_campaign(rewound)
	await tree.process_frame
	assert_eq(dashboard.engine.turn, 2, "a rewind lands on the earlier decision")
	assert_true(dashboard.get_node("%DilemmaDialog").visible)


func test_players_take_turns_with_their_own_lens() -> void:
	dashboard.start_campaign(SimConstants.CEO, 12, false, {"human_roles": [SimConstants.CITIZEN]})
	await tree.process_frame
	var engine: SimulationEngine = dashboard.engine
	assert_eq(engine.player_role, SimConstants.CEO)
	assert_eq(dashboard._lens.role, SimConstants.CEO)
	_answer()
	await tree.process_frame
	assert_eq(engine.turn, 1, "same turn")
	assert_eq(engine.player_role, SimConstants.CITIZEN, "the Coalition decides next")
	assert_eq(dashboard._lens.role, SimConstants.CITIZEN, "with the Coalition's lens")
	assert_eq(dashboard._newswire.player_role, SimConstants.CITIZEN)
	assert_true(dashboard.get_node("%DilemmaDialog").visible)
	_answer()
	await tree.process_frame
	assert_eq(engine.phase, SimulationEngine.Phase.IDLE)
	dashboard._begin_next_turn()
	await tree.process_frame
	assert_eq(engine.turn, 2)
	assert_eq(dashboard._lens.role, SimConstants.CEO, "the first player opens every turn")
