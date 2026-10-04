extends "res://tests/framework/test_case.gd"
## "Why did this change?" (WhyPopup): the causes the engine filed for a real
## played turn, grouped into the player's moves, rivals and the world, with
## sums that match SimulationEngine.get_changes(); the turn stepper; the
## metric_pressed signals that open it; phone fit.

const PHONE := Vector2(412, 915)
const NAMES := {"CEO": "Frontier Lab", "GOVERNANCE_COUNCIL": "Governance Council", "ASI": "Emergent ASI",
	"CITIZEN_COALITION": "Citizen Coalition"}

var settings: GameSettings
var host: Control
var popup: WhyPopup


func before_each() -> void:
	settings = GameSettings.new()
	settings.path = ""
	GameSettings.use(settings)
	host = Control.new()
	host.theme = EraTheme.get_theme(1)
	host.size = Vector2(1600, 900)
	tree.root.add_child(host)
	popup = WhyPopup.new()
	host.add_child(popup)
	await tree.process_frame


func after_each() -> void:
	host.queue_free()
	await tree.process_frame
	GameSettings.use(null)
	EraTheme.invalidate()


## Plays turns until [param last_turn] completes, answering each crisis with
## an affordable option and the heuristic's directive.
func _play(role: String, seed_value: int, last_turn: int) -> SimulationEngine:
	var engine := SimulationEngine.new()
	engine.start_campaign(role, seed_value)
	for _guard in last_turn * 12 + 20:
		if engine.is_ended() or (engine.turn >= last_turn and engine.phase == SimulationEngine.Phase.IDLE):
			break
		if not engine.is_awaiting_player():
			engine.advance()
			continue
		var option := DilemmaDeck.DEFER_ID
		for candidate in engine.current_dilemma.get("options", []):
			if engine.get_player().can_afford(candidate.get("cost", {})):
				option = String(candidate["id"])
				break
		var decision := HeuristicFallback.evaluate(engine.player_role, engine.build_observation(engine.player_role))
		if not engine.submit_player_turn([{"action": decision["action"], "intensity": 1.0}], option)["ok"]:
			engine.submit_player_turn([], option)
	return engine


func test_groups_and_sums_match_the_engine() -> void:
	var engine := _play(SimConstants.GOVERNANCE, 63, 6)
	assert_eq(engine.turn, 6)
	var seen_groups := {}
	for key in WorldState.METRIC_KEYS + WorldState.INDEX_KEYS:
		popup.present(engine, key, 6)
		var causes := engine.get_changes(key, 6)
		var groups := popup.get_cause_groups()
		var expected := 0.0
		for change in causes:
			expected += float(change["delta"])
		var grouped := 0.0
		var count := 0
		for group in WhyPopup.GROUPS:
			var total := 0.0
			for change in groups[group]["causes"]:
				total += float(change["delta"])
				count += 1
				assert_eq(WhyPopup.group_of(String(change["cause"]), engine.player_role, NAMES), group, String(change["cause"]))
				seen_groups[group] = true
			assert_almost_eq(float(groups[group]["total"]), total, 0.0001, "%s %s total" % [key, group])
			grouped += total
		assert_eq(count, causes.size(), "%s: every cause shown once" % key)
		assert_almost_eq(grouped, expected, 0.0001, "%s: the groups add up to the ledger" % key)
		assert_almost_eq(popup.get_net(), expected, 0.0001, "%s: net change" % key)
		var history: Array = engine.world.history
		assert_almost_eq(popup.value_after(6), float(history[6][key]), 0.0001, "%s: value after the turn" % key)
		assert_almost_eq(popup.value_after(6) - popup.get_net(), float(history[5][key]), 0.05, "%s: value before the turn" % key)
	for group in WhyPopup.GROUPS:
		assert_true(seen_groups.has(group), "a played turn has %s causes" % group)
	popup.present(engine, WorldState.EPISTEMIC_TRUST, 6)
	var shown := 0
	for group in WhyPopup.GROUPS:
		shown += (popup.get_cause_groups()[group]["causes"] as Array).size()
	assert_eq(_cause_rows().size(), shown, "a row per cause")


func test_causes_are_grouped_by_who_moved() -> void:
	var cases := [
		["Crisis: Grid Brownout (Ration power)", "CEO", "yours"], ["Crisis deferred: Chip Embargo", "CEO", "yours"],
		["Crisis broke: Chip Embargo", "ASI", "yours"], ["Deal with Emergent ASI", "CEO", "yours"],
		["Era goal: Keep your public mandate at 45 or more through 2035", "GOVERNANCE_COUNCIL", "yours"],
		["Frontier Lab: Scale Frontier Clusters", "CEO", "yours"], ["Frontier Lab (standing influence)", "CEO", "yours"],
		["Frontier Lab: Scale Frontier Clusters", "GOVERNANCE_COUNCIL", "rivals"],
		["Emergent ASI (standing influence)", "CITIZEN_COALITION", "rivals"], ["Collapse: Emergent ASI", "CEO", "rivals"],
		["Paradigm shift: Formal Mechanistic Interpretability", "CEO", "world"], ["Emergent capability: Strategic Evaluation Deception", "CEO", "world"],
		["Scenario: The Slow Burn", "CEO", "world"], ["Fear of misaligned AI", "CEO", "world"], ["Everyday recovery", "ASI", "world"],
		["Unpredictable events", "CEO", "world"], ["World dynamics", "CEO", "world"], ["Other effects", "CEO", "world"],
	]
	for entry in cases:
		assert_eq(WhyPopup.group_of(String(entry[0]), String(entry[1]), NAMES), entry[2], "%s as %s" % [entry[0], entry[1]])


func test_turn_stepper_walks_the_ledger() -> void:
	var engine := _play(SimConstants.CEO, 21, 10)
	popup.present(engine, WorldState.ALIGNMENT_DRIFT)
	assert_eq(popup.shown_turn, 10, "this turn by default")
	var turns := popup.available_turns()
	assert_eq(turns.size(), WorldState.CHANGE_LOG_TURNS, "this turn and seven before it")
	assert_eq(turns[0], 3)
	assert_eq(turns[-1], 10)
	assert_string_contains(_label("TurnLabel"), "This turn")
	assert_true(_button("Newer").disabled, "nothing newer than this turn")
	popup.step_turn(-1)
	assert_eq(popup.shown_turn, 9)
	assert_string_contains(_label("TurnLabel"), "Last turn")
	_button("Older").pressed.emit()
	assert_eq(popup.shown_turn, 8, "the older button steps back")
	assert_string_contains(_label("TurnLabel"), "Turn 8")
	for _i in 10:
		popup.step_turn(-1)
	assert_eq(popup.shown_turn, 3, "stops at the oldest turn in the ledger")
	assert_true(_button("Older").disabled)
	popup.show_turn(1)
	assert_eq(popup.shown_turn, 3, "turns gone from the ledger cannot be shown")
	var expected := 0.0
	for change in engine.get_changes(WorldState.ALIGNMENT_DRIFT, 3):
		expected += float(change["delta"])
	assert_almost_eq(popup.get_net(), expected, 0.0001, "the stepper shows that turn's causes")
	popup.step_turn(1)
	assert_eq(popup.shown_turn, 4)


func test_the_current_turn_so_far() -> void:
	var engine := _play(SimConstants.CITIZEN, 5, 4)
	engine.advance()
	assert_true(engine.is_awaiting_player())
	popup.present(engine, WorldState.EPISTEMIC_TRUST)
	assert_eq(popup.shown_turn, 5)
	assert_string_contains(_label("TurnLabel"), "This turn so far")
	for change in popup.get_cause_groups()["yours"]["causes"]:
		assert_false(String(change["cause"]).begins_with("Crisis"), "the player has not answered this turn's crisis yet")
	assert_almost_eq(popup.value_after(5), engine.world.epistemic_trust, 0.0001, "the value now")
	assert_string_contains(_label("Title"), "Public Trust & Cohesion")
	assert_string_contains(_label("Subtitle"), "Trust in what's true")
	settings.set_value("plain_language", true)
	popup.present(engine, WorldState.EPISTEMIC_TRUST)
	assert_string_contains(_label("Title"), "Trust in what's true", "plain words lead when plain language is on")


func test_indices_and_colors() -> void:
	var engine := _play(SimConstants.GOVERNANCE, 9, 3)
	popup.present(engine, WorldState.SAFETY_NET_COVERAGE, 3)
	assert_eq(popup.metric_key, WorldState.SAFETY_NET_COVERAGE)
	assert_true(WhyPopup.improves(WorldState.SAFETY_NET_COVERAGE, 2.0), "a wider safety net helps")
	assert_false(WhyPopup.improves(WorldState.ALIGNMENT_DRIFT, 2.0), "more drift hurts")
	assert_true(WhyPopup.improves(WorldState.EPISTEMIC_TRUST, 1.0), "more trust helps")
	popup.present(engine, WorldState.ALIGNMENT_DRIFT, 3)
	var s := EraTheme.style_of(popup)
	for row in _cause_rows():
		var delta := (row.find_child("CauseDelta", true, false) as Label)
		var text := delta.text
		var color := delta.get_theme_color("font_color")
		if text.begins_with("+") and text != "+0":
			assert_eq(color, s.bad, "drift up reads as bad: %s" % text)
		elif text.begins_with("−"):
			assert_eq(color, s.good, "drift down reads as good: %s" % text)


func test_closing_and_phone_fit() -> void:
	var engine := _play(SimConstants.ASI, 33, 5)
	host.size = PHONE
	popup.set_compact(true)
	var closed := [0]
	popup.closed.connect(func() -> void: closed[0] += 1)
	for era_number in [1, 2, 3]:
		host.theme = EraTheme.get_theme(era_number)
		popup.present(engine, WorldState.GEOPOLITICAL_TENSION, 5)
		await wait_frames(3)
		assert_true(popup.visible)
		_assert_fits(popup, PHONE.x, "why popup, era %d" % era_number)
	_button("CloseButton").pressed.emit()
	assert_false(popup.visible)
	assert_eq(closed[0], 1, "closed once")
	popup.present(engine, WorldState.GEOPOLITICAL_TENSION)
	popup.close()
	assert_eq(closed[0], 2)


func test_meters_and_lenses_report_taps() -> void:
	var meter := MeterBar.new()
	meter.metric_key = WorldState.LABOR_DISPLACEMENT
	meter.position = Vector2(20, 20)
	meter.size = Vector2(150, 92)
	host.add_child(meter)
	var pressed: Array[String] = []
	meter.metric_pressed.connect(func(key: String) -> void: pressed.append(key))
	await tree.process_frame
	var at := meter.get_global_rect().get_center()
	_click(at, true)
	_click(at, false)
	assert_eq(pressed.size(), 1, "a tap on a meter")
	assert_eq(pressed[0] if not pressed.is_empty() else "", WorldState.LABOR_DISPLACEMENT)
	_click(at, true)
	_motion(at + Vector2(0, 40))
	_click(at + Vector2(0, 40), false)
	assert_eq(pressed.size(), 1, "a drag is not a tap")
	meter.queue_free()

	var engine := _play(SimConstants.CEO, 2, 2)
	var lens := LensPanel.create(SimConstants.CEO)
	lens.position = Vector2.ZERO
	lens.size = Vector2(400, 880)
	host.add_child(lens)
	lens.update_state(engine.get_snapshot(), engine.get_player().resources)
	await wait_frames(2)
	var lens_keys: Array[String] = []
	lens.metric_pressed.connect(func(key: String) -> void: lens_keys.append(key))
	var tile: Control = null
	for node in lens.find_children("*", "PanelContainer", true, false):
		if String((node as Control).get_meta("metric_key", "")) == WorldState.ALIGNMENT_DRIFT:
			tile = node
	assert_not_null(tile, "the priced tiles report their metric")
	if tile != null:
		lens._on_metric_input(_event(true, Vector2(5, 5)), tile)
		lens._on_metric_input(_event(false, Vector2(6, 5)), tile)
		assert_eq(lens_keys.size(), 1, "a tap on a lens metric")
		assert_eq(lens_keys[0] if not lens_keys.is_empty() else "", WorldState.ALIGNMENT_DRIFT)


func _cause_rows() -> Array:
	return popup.find_children("*", "VBoxContainer", true, false).filter(func(node: Node) -> bool: return node.has_meta("cause"))


func _label(label_name: String) -> String:
	var label := popup.find_child(label_name, true, false) as Label
	return label.text if label != null else ""


func _button(button_name: String) -> Button:
	return popup.find_child(button_name, true, false) as Button


func _event(pressed: bool, at: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	return event


func _click(at: Vector2, pressed: bool) -> void:
	var event := _event(pressed, at)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	tree.root.push_input(event, true)


func _motion(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	tree.root.push_input(event, true)


func _assert_fits(root: Control, width: float, context: String) -> void:
	var overflowing: Array[String] = []
	for node in root.find_children("*", "Control", true, false):
		var control := node as Control
		if control.is_visible_in_tree() and control.get_global_rect().end.x > width + 0.5:
			overflowing.append("%s (%s) ends at %.0f" % [control.name, control.get_class(), control.get_global_rect().end.x])
	assert_eq(overflowing.size(), 0, "%s fits %.0f px: %s" % [context, width, ", ".join(overflowing.slice(0, 5))])
