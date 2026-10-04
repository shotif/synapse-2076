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
	dashboard.saves.delete()
	dashboard.endings.reset()
	await tree.process_frame


func after_each() -> void:
	dashboard.saves.delete()
	dashboard.endings.reset()
	GameSettings.instance().set_value("text_scale", 1.0)
	GameSettings.instance().set_value("coach_done", false)
	ProjectSettings.set_setting("synapse/onboarding/coach", false)
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
	var cover: PassDevice = dashboard._pass_device
	var dialog: DilemmaDialog = dashboard.get_node("%DilemmaDialog")
	assert_eq(engine.player_role, SimConstants.CEO)
	assert_true(cover.visible, "the device goes to the first player")
	assert_false(dialog.visible, "nothing shows under the cover")
	cover.reveal()
	await tree.process_frame
	assert_false(cover.visible)
	assert_true(dialog.visible)
	assert_eq(dashboard._lens.role, SimConstants.CEO)
	_answer()
	await tree.process_frame
	assert_eq(engine.turn, 1, "same turn")
	assert_eq(engine.player_role, SimConstants.CITIZEN, "the Coalition decides next")
	assert_true(cover.visible, "the device is passed on")
	assert_eq(dashboard._lens.role, SimConstants.CITIZEN, "with the Coalition's lens")
	assert_eq(dashboard._newswire.player_role, SimConstants.CITIZEN)
	cover.reveal()
	await tree.process_frame
	assert_true(dialog.visible)
	_answer()
	await tree.process_frame
	assert_eq(engine.phase, SimulationEngine.Phase.IDLE)
	dashboard._begin_next_turn()
	await tree.process_frame
	assert_eq(engine.turn, 2)
	assert_eq(dashboard._lens.role, SimConstants.CEO, "the first player opens every turn")
	assert_true(cover.visible, "and gets the device back")


func test_the_setup_screen_starts_the_campaign_it_describes() -> void:
	var setup: RoleSelect = dashboard.get_node("%RoleSelect")
	setup.select_role(SimConstants.GOVERNANCE)
	setup.select_mode("decade_2")
	setup.select_scenario("the_pause")
	setup.select_difficulty(Difficulty.STORY)
	setup.set_seat(SimConstants.ASI, true)
	setup._on_start_pressed()
	await tree.process_frame
	var engine: SimulationEngine = dashboard.engine
	assert_not_null(engine)
	assert_eq(engine.scenario_id, "the_pause")
	assert_eq(engine.difficulty, Difficulty.STORY)
	assert_eq(engine.start_turn, 20)
	assert_eq(engine.total_turns, 39)
	assert_eq(engine.human_roles, [SimConstants.GOVERNANCE, SimConstants.ASI] as Array[String])
	assert_eq(dashboard._meta["mode"], "decade_2")
	assert_false(setup.visible)


func test_autosave_continue_and_the_end_of_a_campaign() -> void:
	dashboard.start_campaign(SimConstants.CITIZEN, 33, false)
	await tree.process_frame
	assert_true(dashboard.saves.has_save(), "saved at the first decision")
	for _turn in 2:
		_answer()
		dashboard._begin_next_turn()
		await tree.process_frame
	var engine: SimulationEngine = dashboard.engine
	dashboard._show_role_select()
	var setup: RoleSelect = dashboard.get_node("%RoleSelect")
	assert_true(setup.has_continue(), "the setup screen offers Continue")
	dashboard._continue_campaign()
	await tree.process_frame
	assert_ne(dashboard.engine, engine, "a fresh engine rebuilt from the save")
	assert_eq(dashboard.engine.turn, engine.turn)
	assert_eq(dashboard.engine.current_dilemma["id"], engine.current_dilemma["id"])
	assert_true(dashboard.get_node("%DilemmaDialog").visible)
	# Play the rest on autopilot to the end.
	dashboard.engine.autoplay_player = true
	dashboard.engine.run_headless()
	await tree.process_frame
	assert_true(dashboard.engine.is_ended())
	assert_false(dashboard.saves.has_save(), "an ended campaign cannot be continued")
	assert_eq(dashboard.endings.progress().x, 1, "its ending joins the collection")
	assert_true(dashboard.get_node("%EndgameDebrief").visible)
	dashboard._open_endings()
	assert_true(dashboard._endings_gallery.visible)
	dashboard._endings_gallery.close()
	dashboard._rewind_to(4)
	await tree.process_frame
	assert_eq(dashboard.engine.turn, 4, "what if: back at turn 4")
	assert_true(dashboard.engine.is_awaiting_player())
	assert_false(dashboard.get_node("%EndgameDebrief").visible)


func test_tapping_a_number_explains_it() -> void:
	dashboard.start_campaign(SimConstants.GOVERNANCE, 5, false)
	await tree.process_frame
	_answer()
	dashboard._begin_next_turn()
	await tree.process_frame
	var strip: VitalsStrip = dashboard._vitals_strip
	strip.metric_pressed.emit(WorldState.EPISTEMIC_TRUST)
	assert_true(dashboard._why.visible, "the why popup opens")
	dashboard._why.close()
	(dashboard._meters[WorldState.ALIGNMENT_DRIFT] as MeterBar).metric_pressed.emit(WorldState.ALIGNMENT_DRIFT)
	assert_true(dashboard._why.visible)


func test_goals_toasts_and_calls() -> void:
	dashboard.start_campaign(SimConstants.CITIZEN, 14, false)
	await tree.process_frame
	assert_gt(dashboard._goals.get_rows().size(), 0, "the ACT column shows this era's goal")
	assert_true(dashboard._call_button.visible, "a leader can be called during the turn")
	dashboard._open_call()
	assert_true(dashboard._negotiation.visible)
	var negotiator: Negotiator = dashboard._negotiation.get_negotiator()
	negotiator.send_quick("calm")
	if not negotiator.offer.is_empty():
		var applied := negotiator.accept()
		assert_true(applied["ok"], "the scripted offer goes through: %s" % str(applied.get("errors", [])))
		var deals: Array = dashboard.engine.event_log.filter(func(e: Dictionary) -> bool: return e["category"] == "DEAL")
		assert_eq(deals.size(), 1)
	dashboard._negotiation.hang_up()
	dashboard.engine.get_player().set_resource("community_resilience", 70.0)
	_answer()
	await tree.process_frame
	assert_true(dashboard._goal_toast.is_showing(), "a met goal gets a banner")
	assert_false(dashboard._call_button.visible, "no calls between turns")


func test_settings_and_the_first_campaign_coach() -> void:
	var base := dashboard.theme.default_font_size
	GameSettings.instance().set_value("text_scale", 1.3)
	await tree.process_frame
	assert_gt(dashboard.theme.default_font_size, base, "bigger text everywhere")
	dashboard._open_settings()
	assert_true(dashboard._settings_dialog.visible)
	dashboard._settings_dialog.close()
	ProjectSettings.set_setting("synapse/onboarding/coach", true)
	GameSettings.instance().set_value("coach_done", false)
	dashboard.start_campaign(SimConstants.CEO, 2, false)
	await tree.process_frame
	assert_true(dashboard._coach.is_running(), "the first campaign is coached")
	dashboard._coach.skip()
	assert_true(bool(GameSettings.value("coach_done")))
