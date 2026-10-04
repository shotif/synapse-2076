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
