extends "res://tests/framework/test_case.gd"
## Headless UI smoke tests: the dashboard, its components and the 3D viewports
## instantiate under the dummy renderer and stay bound to the engine.

const DashboardScene := preload("res://ui/main_dashboard.tscn")

var dashboard: Control


func before_all() -> void:
	# Keep the suite hermetic: no startup probe against a local LLM endpoint.
	ProjectSettings.set_setting("synapse/llm/probe_on_start", false)


func before_each() -> void:
	dashboard = DashboardScene.instantiate()
	tree.root.add_child(dashboard)
	await tree.process_frame


func after_each() -> void:
	dashboard.queue_free()
	if _saved_root_size != Vector2i.ZERO:
		tree.root.size = _saved_root_size
		tree.root.content_scale_size = UiLayout.DESKTOP_SIZE
		_saved_root_size = Vector2i.ZERO
	await tree.process_frame


func test_dashboard_builds_all_zones() -> void:
	assert_eq(dashboard._meters.size(), 6, "six telemetry meters")
	for key in WorldState.METRIC_KEYS:
		assert_has(dashboard._meters, key)
	assert_not_null(dashboard.get_node("%Globe"))
	assert_not_null(dashboard.get_node("%Lattice"))
	assert_true(dashboard.get_node("%RoleSelect").visible, "role select shown first")
	assert_false(dashboard.get_node("%DilemmaDialog").visible)
	assert_string_contains(dashboard.get_node("%LLMStatusBadge").get_text(), "LLM OFFLINE - RUNNING HEURISTIC FALLBACK ENGINE")


func test_interactive_turn_through_widgets() -> void:
	dashboard.start_campaign("GOVERNANCE_COUNCIL", 314, false)
	await tree.process_frame
	var engine: SimulationEngine = dashboard.engine
	assert_true(engine.is_awaiting_player())
	var dialog: DilemmaDialog = dashboard.get_node("%DilemmaDialog")
	var panel: DirectivePanel = dashboard.get_node("%DirectivePanel")
	assert_true(dialog.visible, "crisis card presented")
	assert_false(panel.is_execute_enabled(), "locked until the crisis is resolved")
	dialog.choose(DilemmaDeck.DEFER_ID)
	assert_false(dialog.visible)
	assert_true(panel.has_crisis_choice())
	assert_true(panel.select_directive("MANDATE_ALIGNMENT_AUDIT", 1.2))
	assert_true(panel.is_execute_enabled())
	panel._on_execute_pressed()
	assert_eq(engine.phase, SimulationEngine.Phase.IDLE, "turn resolved")
	assert_eq(engine.turn_actions["GOVERNANCE_COUNCIL"]["action"], "MANDATE_ALIGNMENT_AUDIT")
	assert_almost_eq(float(engine.turn_actions["GOVERNANCE_COUNCIL"]["intensity"]), 1.2, 0.001)
	await wait_seconds(0.6)
	assert_eq(engine.turn, 2, "next turn started automatically")
	assert_true(dialog.visible, "next crisis presented")
	assert_string_contains(dashboard.get_node("%YearLabel").text, "T:2/100")
	var meter: MeterBar = dashboard._meters["alignment_drift"]
	assert_almost_eq(meter.value, engine.world.alignment_drift, 0.001, "meters track the world")
	assert_gt(dashboard._feed_entries.size(), 3, "event feed populated")


func test_unaffordable_crisis_options_are_disabled() -> void:
	dashboard.start_campaign("CEO", 5, false)
	await tree.process_frame
	var engine: SimulationEngine = dashboard.engine
	engine.get_player().set_resource("capital", 0.0)
	var dialog: DilemmaDialog = dashboard.get_node("%DilemmaDialog")
	dialog.present(engine.current_dilemma, engine.get_player().resources, "CEO")
	var disabled := 0
	for button in dialog.find_children("*", "Button", true, false):
		if (button as Button).disabled:
			disabled += 1
	assert_gt(disabled, 0, "options costing capital are disabled")


func test_spectate_mode_reaches_debrief() -> void:
	dashboard.start_campaign("ASI", 77, true)
	var engine: SimulationEngine = dashboard.engine
	for _i in 400:
		if engine.is_ended():
			break
		engine.advance()
	await tree.process_frame
	assert_true(engine.is_ended())
	var debrief: EndgameDebrief = dashboard.get_node("%EndgameDebrief")
	assert_true(debrief.visible, "debrief shown")
	assert_eq((debrief._chart.history as Array).size(), engine.world.history.size(), "trajectory chart bound to history")
	assert_eq(debrief._affinity_box.get_child_count(), 8, "eight end-state affinities")


func test_viewports_accept_snapshots() -> void:
	var globe: GlobeViewport = dashboard.get_node("%Globe")
	var lattice: NeuralLattice = dashboard.get_node("%Lattice")
	var snapshot := {"metrics": {"compute_energy_sat": 92.0, "geopolitical_tension": 88.0, "epistemic_trust": 10.0,
		"alignment_drift": 90.0, "algorithmic_autonomy": 95.0}, "tech": {"capability_index": 100.0, "emerged_capabilities": ["A", "B"]}}
	globe.update_from_snapshot(snapshot)
	lattice.update_from_snapshot(snapshot)
	assert_eq(lattice.layer_count, NeuralLattice.MAX_LAYERS, "capability deepens the lattice")
	await wait_frames(30)
	assert_gt(lattice.get_drift_level(), 0.2, "drift level eases toward the target")
	dashboard.show_view("lattice")
	assert_true(dashboard.get_node("%LatticeContainer").visible)
	assert_false(dashboard.get_node("%GlobeContainer").visible)


func test_badge_reflects_llm_status() -> void:
	var badge: LLMStatusBadge = dashboard.get_node("%LLMStatusBadge")
	var llm: LLMService = dashboard.llm
	llm.configure({"enabled": true, "model_name": "claude-sonnet-5-5", "endpoint_url": "https://api.anthropic.com/v1/chat/completions"})
	llm.set_online(true)
	assert_true(badge.is_showing_online())
	assert_eq(badge.get_text(), "● [LLM ONLINE: CLAUDE-SONNET-5-5 / ANTHROPIC]")
	llm.set_online(false)
	assert_eq(badge.get_text(), "▲ [LLM OFFLINE - RUNNING HEURISTIC FALLBACK ENGINE]")


func test_event_text_is_bbcode_escaped() -> void:
	dashboard.start_campaign("CITIZEN_COALITION", 1, false)
	dashboard._on_event_logged({"turn": 1, "year": 2026.5, "category": "ACTION", "severity": "INFO",
		"faction": "ASI", "text": "[color=red]injected[/color] [url=x]link[/url]"})
	assert_string_contains(dashboard._feed.get_parsed_text(), "[color=red]injected[/color]", "markup rendered literally")


# --- Responsive layout ----------------------------------------------------------

const PHONE_PX := Vector2i(1081, 2202)  # 412 x 839 CSS px at device pixel ratio 2.625

var _saved_root_size := Vector2i.ZERO


## Turns the test window into a phone; after_each puts the window back.
func _use_phone_screen() -> Vector2:
	_saved_root_size = tree.root.size
	tree.root.size = PHONE_PX
	dashboard.apply_layout(UiLayout.compute(Vector2(PHONE_PX), 2.625, true))
	await wait_frames(3)
	return dashboard.get_viewport_rect().size


## Every visible control must stay inside the screen width: phones have no
## horizontal scrolling, so one wide label pushes the whole layout off-screen.
func _assert_fits(width: float, context: String) -> void:
	var overflowing: Array[String] = []
	for node in dashboard.find_children("*", "Control", true, false):
		var control := node as Control
		if control.is_visible_in_tree() and control.get_global_rect().end.x > width + 0.5:
			overflowing.append("%s (%s) ends at %.0f" % [control.name, control.get_class(), control.get_global_rect().end.x])
	assert_eq(overflowing.size(), 0, "%s fits %.0f px: %s" % [context, width, ", ".join(overflowing.slice(0, 5))])


func test_layout_breakpoints() -> void:
	var phone := UiLayout.compute(Vector2(1080, 2400), 2.625, true)
	assert_true(phone["compact"], "portrait phone")
	assert_false(phone["landscape"])
	assert_eq(phone["content_size"], Vector2i(411, 914), "about one logical px per CSS px")
	var landscape := UiLayout.compute(Vector2(2400, 1080), 2.625, true)
	assert_true(landscape["compact"], "landscape phone")
	assert_true(landscape["landscape"])
	assert_eq(UiLayout.compute(Vector2(640, 1136), 2.0, true)["content_size"], Vector2i(360, 639), "tiny phones zoom out to 360 px")
	assert_eq(UiLayout.compute(Vector2(1620, 2160), 2.0, true)["content_size"], Vector2i(640, 853), "tablets zoom in")
	assert_true(UiLayout.compute(Vector2(2160, 1620), 2.0, true)["compact"], "landscape tablet: touch needs room")
	assert_false(UiLayout.compute(Vector2(2160, 1620), 2.0, false)["compact"], "the same screen with a mouse")
	for desktop in [Vector2(1920, 1080), Vector2(1280, 720), Vector2(2880, 1800)]:
		var layout := UiLayout.compute(desktop, 2.0 if desktop.x > 2000 else 1.0, false)
		assert_false(layout["compact"], "desktop %s" % desktop)
		assert_eq(layout["content_size"], UiLayout.DESKTOP_SIZE)
	assert_true(UiLayout.compute(Vector2(800, 600), 1.0, false)["compact"], "small window")
	assert_true(UiLayout.compute(Vector2(1000, 1400), 1.0, false)["compact"], "portrait window")
	assert_false(UiLayout.compute(Vector2.ZERO, 1.0, false)["compact"], "unknown size keeps the desktop layout")


func test_desktop_layout_is_the_default() -> void:
	assert_false(dashboard.compact)
	assert_false(dashboard.get_node("Margin/Layout/TabBar").visible)
	assert_false(dashboard.get_node("Margin/Layout/VitalsStrip").visible)
	for panel in ["%TelemetryPanel", "%CenterPanel", "%DirectivePanel", "%Footer"]:
		assert_true(dashboard.get_node(panel).visible, panel)


func test_phone_layout_fits_and_switches_tabs() -> void:
	var screen := await _use_phone_screen()
	assert_true(dashboard.compact)
	assert_almost_eq(screen.x, 412.0, 1.0, "logical width matches the phone's CSS width")
	assert_true(dashboard.get_node("Margin/Layout/TabBar").visible)
	assert_eq(dashboard._vitals.size(), 6, "vitals strip shows all six metrics")
	_assert_fits(screen.x, "role select")

	dashboard.start_campaign("CEO", 2076, false)
	await wait_frames(3)
	assert_eq(dashboard.active_tab, "act", "a decision opens the ACT tab")
	_assert_fits(screen.x, "crisis card")
	var dialog: DilemmaDialog = dashboard.get_node("%DilemmaDialog")
	dialog.choose(DilemmaDeck.DEFER_ID)
	await wait_frames(2)
	for tab in ["act", "world", "intel", "log"]:
		dashboard.show_tab(tab)
		await wait_frames(2)
		_assert_fits(screen.x, tab + " tab")
	assert_false(dashboard.get_node("%Body").visible, "LOG replaces the panels")
	assert_true(dashboard.get_node("%Footer").visible)
	dashboard.show_tab("world")
	assert_true(dashboard.get_node("%CenterPanel").visible)
	assert_false(dashboard.get_node("%DirectivePanel").visible)
	var engine: SimulationEngine = dashboard.engine
	assert_almost_eq((dashboard._vitals["epistemic_trust"] as MeterBar).value, engine.world.epistemic_trust, 0.001,
		"vitals track the world")


func test_phone_debrief_and_settings_fit() -> void:
	var screen := await _use_phone_screen()
	dashboard.start_campaign("ASI", 77, true)
	var engine: SimulationEngine = dashboard.engine
	for _i in 400:
		if engine.is_ended():
			break
		engine.advance()
	await wait_frames(3)
	assert_true(dashboard.get_node("%EndgameDebrief").visible)
	_assert_fits(screen.x, "debrief")
	dashboard.get_node("%EndgameDebrief").visible = false
	dashboard._open_llm_settings()
	await wait_frames(3)
	_assert_fits(screen.x, "LLM settings")
