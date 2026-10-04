extends "res://tests/framework/test_case.gd"
## The era goals panel (GoalsPanel) and the goal banner (GoalToast): rows
## from a real engine, statuses and progress toward the threshold, the
## condition in plain words, phone and desktop layouts.

const PHONE := Vector2(412, 915)

var settings: GameSettings
var host: Control


func before_each() -> void:
	settings = GameSettings.new()
	settings.path = ""
	GameSettings.use(settings)
	host = Control.new()
	host.theme = EraTheme.get_theme(1)
	host.size = PHONE
	tree.root.add_child(host)


func after_each() -> void:
	host.queue_free()
	await tree.process_frame
	GameSettings.use(null)
	EraTheme.invalidate()


func _engine(role: String, seed_value: int = 14, options: Dictionary = {}) -> SimulationEngine:
	var engine := SimulationEngine.new()
	engine.start_campaign(role, seed_value, options)
	engine.advance()
	return engine


func _panel(compact: bool = false) -> GoalsPanel:
	var panel := GoalsPanel.new()
	panel.size = Vector2(PHONE.x if compact else 404.0, 0)
	host.add_child(panel)
	panel.set_compact(compact)
	return panel


func test_rows_come_from_the_engine() -> void:
	var engine := _engine(SimConstants.CEO)
	var panel := _panel()
	panel.refresh(engine)
	var rows := panel.get_rows()
	assert_eq(rows.size(), 2, "this era's goal and the next era's")
	var current: Dictionary = rows[0]
	assert_eq(current["id"], "E1_CEO_RUNWAY")
	assert_eq(current["display_status"], EraGoals.ACTIVE, "an era-one goal is in play from the first turn")
	assert_eq(current["status"], EraGoals.UPCOMING, "the engine has not settled it yet")
	assert_almost_eq(float(current["current"]), engine.get_player().get_resource("capital"), 0.001, "live value")
	assert_true(current["holds"], "the lab starts above $150B")
	assert_eq(current["condition"], "Keep capital at $150B or more through 2035")
	assert_eq(current["condition_short"], "Keep capital ≥ $150B to 2035")
	var coming: Dictionary = rows[1]
	assert_eq(coming["id"], "E2_CEO_GOODWILL")
	assert_eq(coming["display_status"], EraGoals.UPCOMING)
	assert_eq(panel.current_rows().size(), 1)
	assert_not_null(panel.find_child("Goal_E1_CEO_RUNWAY", true, false), "a row for the goal")
	assert_not_null(panel.find_child("Coming_E2_CEO_GOODWILL", true, false), "next era's goal as coming up")
	var chip := panel.find_child("StatusLabel", true, false) as Label
	assert_eq(chip.text, "In play")


func test_met_and_missed_goals() -> void:
	var citizens := _engine(SimConstants.CITIZEN)
	citizens.get_player().set_resource("community_resilience", 70.0)
	citizens.submit_player_turn([], DilemmaDeck.DEFER_ID)
	var panel := _panel()
	panel.refresh(citizens)
	var met: Dictionary = panel.current_rows()[0]
	assert_eq(met["display_status"], EraGoals.MET)
	assert_true(met["holds"])
	assert_almost_eq(float(met["threshold_fraction"]), 0.6, 0.001, "the threshold tick at 60 of 100")
	assert_eq(met["condition"], "Reach resilience 60 before 2036")
	assert_eq((panel.find_child("StatusLabel", true, false) as Label).text, "Met")
	var bar := panel.find_child("Bar", true, false) as GoalsPanel.GoalBar
	assert_eq(bar.color, EraTheme.style_of(panel).good, "met goals use the era's good color")

	var lab := _engine(SimConstants.CEO, 14, {"difficulty": Difficulty.HARD})
	lab.get_player().set_resource("capital", 100.0)
	lab.submit_player_turn([], DilemmaDeck.DEFER_ID)
	panel.refresh(lab)
	var missed: Dictionary = panel.current_rows()[0]
	assert_eq(missed["display_status"], EraGoals.FAILED)
	assert_false(missed["holds"])
	assert_eq((panel.find_child("StatusLabel", true, false) as Label).text, "Missed")
	bar = panel.find_child("Bar", true, false) as GoalsPanel.GoalBar
	assert_eq(bar.color, EraTheme.style_of(panel).bad, "missed goals use the era's bad color")


func test_progress_toward_the_threshold() -> void:
	var quiet := {"value": 35.0, "op": "<=", "subject": {"index": "discovery_index"}, "type": "hold", "era": 1}
	var under := GoalsPanel.progress(quiet, 20.0, SimConstants.ASI)
	assert_true(under["holds"])
	assert_almost_eq(float(under["fraction"]), 0.2, 0.001)
	assert_almost_eq(float(under["threshold_fraction"]), 0.35, 0.001)
	assert_false(GoalsPanel.progress(quiet, 40.0, SimConstants.ASI)["holds"])
	var runway := {"value": 150.0, "op": ">=", "subject": {"resource": "capital"}, "type": "hold", "era": 1}
	var rich := GoalsPanel.progress(runway, 450.0, SimConstants.CEO)
	assert_true(rich["holds"])
	assert_lt(float(rich["fraction"]), 1.0, "a big runway still fits the bar")
	assert_gt(float(rich["fraction"]), float(rich["threshold_fraction"]))
	var poor := GoalsPanel.progress(runway, 90.0, SimConstants.CEO)
	assert_false(poor["holds"])
	assert_lt(float(poor["fraction"]), float(poor["threshold_fraction"]))


func test_conditions_in_plain_words() -> void:
	var rows := {}
	for goal in EraGoals.GOALS:
		rows[goal["id"]] = goal
	assert_eq(GoalsPanel.condition_text(rows["E1_ASI_QUIET"], SimConstants.ASI), "Keep ASI discovery at 35 or below through 2035")
	assert_eq(GoalsPanel.condition_text(rows["E2_CEO_GOODWILL"], SimConstants.CEO), "End the era with goodwill at 40 or more")
	assert_eq(GoalsPanel.condition_text(rows["E2_ASI_SUBSTRATE"], SimConstants.ASI), "Reach substrate 50 before 2050")
	assert_eq(GoalsPanel.condition_text(rows["E3_ASI_AUTONOMY"], SimConstants.ASI), "Reach autonomy 85 by 2076")
	assert_eq(GoalsPanel.condition_text(rows["E2_GOV_TENSION"], SimConstants.GOVERNANCE, true), "Keep tension ≤ 70 to 2049")
	settings.set_value("plain_language", true)
	assert_eq(GoalsPanel.condition_text(rows["E2_GOV_TENSION"], SimConstants.GOVERNANCE), "Keep conflict risk at 70 or below through 2049",
		"plain words for the subject")
	for goal in EraGoals.GOALS:
		var text := GoalsPanel.condition_text(goal, String(goal["roles"][0]))
		assert_true(text.begins_with("Keep") or text.begins_with("Reach") or text.begins_with("End") or text.begins_with("Bring"), text)


func test_compact_shows_one_line_per_goal_and_fits_a_phone() -> void:
	var engine := _engine(SimConstants.GOVERNANCE)
	var panel := _panel(true)
	panel.refresh(engine)
	await wait_frames(2)
	var line := panel.find_child("Goal_E1_GOV_MANDATE", true, false)
	assert_true(line is HBoxContainer, "one line")
	assert_not_null(panel.find_child("Coming_E2_GOV_TENSION", true, false))
	assert_null(panel.find_child("StatusLabel", true, false), "a dot instead of a chip")
	_assert_fits(host, PHONE.x, "compact goals")
	for era_number in [2, 3]:
		host.theme = EraTheme.get_theme(era_number)
		await wait_frames(2)
		_assert_fits(host, PHONE.x, "compact goals, era %d" % era_number)
	panel.set_compact(false)
	await wait_frames(2)
	assert_not_null(panel.find_child("StatusLabel", true, false), "the desktop card has a status chip")
	_assert_fits(host, PHONE.x, "full goals card")


func test_follows_color_blind_colors() -> void:
	var engine := _engine(SimConstants.CEO, 3)
	var panel := _panel()
	panel.refresh(engine)
	var bar := panel.find_child("Bar", true, false) as GoalsPanel.GoalBar
	assert_eq(bar.color, EraStyle.for_era(1).good, "a goal on track is drawn in the good color")
	settings.set_value("colorblind", true)
	EraTheme.invalidate()
	host.theme = EraTheme.get_theme(1)
	await wait_frames(2)
	bar = panel.find_child("Bar", true, false) as GoalsPanel.GoalBar
	assert_eq(bar.color, EraStyle.COLORBLIND[1]["good"], "the panel restyles with color-blind friendly colors")


func test_without_an_engine() -> void:
	var panel := _panel()
	panel.refresh(null)
	assert_eq(panel.get_rows().size(), 0)
	assert_string_contains(_labels_text(panel), "Goals appear when a campaign starts")


# --- Goal banner ---------------------------------------------------------------------

func _goal_entry(status: String, text: String = "Build community resilience to 60 before 2036") -> Dictionary:
	return {"turn": 3, "year": 2027.5, "category": "GOAL", "severity": "INFO", "faction": SimConstants.CITIZEN,
		"text": "goal", "goal": "E1_CIT_RESILIENCE", "goal_text": text, "status": status,
		"reward_text": "+10 scrip" if status == EraGoals.MET else "", "era": 1}


func test_toast_announces_goals_and_hides() -> void:
	var toast := GoalToast.new()
	host.add_child(toast)
	await tree.process_frame
	toast.show_entry({"category": "ACTION", "text": "not a goal"})
	assert_false(toast.is_showing(), "only GOAL entries")
	toast.show_entry(_goal_entry(EraGoals.MET))
	assert_true(toast.is_showing())
	var texts := toast.get_texts()
	assert_string_contains(String(texts["kicker"]), "Goal met")
	assert_string_contains(String(texts["detail"]), "+10 scrip")
	assert_eq(texts["title"], "Build community resilience to 60 before 2036")
	toast.show_entry(_goal_entry(EraGoals.FAILED, "Keep your public mandate at 45 or more through 2035"))
	assert_eq(toast.pending_count(), 1, "a second goal waits its turn")
	toast._timer.timeout.emit()
	await wait_seconds(GoalToast.FADE + 0.15)
	assert_true(toast.is_showing(), "the queued goal follows")
	assert_string_contains(String(toast.get_texts()["kicker"]), "Goal missed")
	assert_eq(toast.pending_count(), 0)
	toast.dismiss()
	await wait_seconds(GoalToast.FADE + 0.15)
	assert_false(toast.is_showing(), "dismissed")


func test_toast_fits_a_phone_in_every_era() -> void:
	var toast := GoalToast.new()
	host.add_child(toast)
	await tree.process_frame
	var long_goal := "Keep your public mandate at 45 or more through 2035 while every rival pushes the other way, all of them at once"
	for era_number in [1, 2, 3]:
		host.theme = EraTheme.get_theme(era_number)
		toast.clear()
		toast.show_entry(_goal_entry(EraGoals.MET, long_goal))
		await wait_frames(3)
		var banner := toast.get_banner().get_global_rect()
		assert_gte(banner.position.x, 0.0, "era %d banner starts on screen" % era_number)
		assert_lte(banner.end.x, PHONE.x + 0.5, "era %d banner fits a phone" % era_number)
		_assert_fits(toast, PHONE.x, "toast era %d" % era_number)


func _labels_text(node: Node) -> String:
	var parts: Array[String] = []
	for label in node.find_children("*", "Label", true, false):
		parts.append((label as Label).text)
	return "\n".join(parts)


func _assert_fits(root: Control, width: float, context: String) -> void:
	var overflowing: Array[String] = []
	for node in root.find_children("*", "Control", true, false):
		var control := node as Control
		if control.is_visible_in_tree() and control.get_global_rect().end.x > width + 0.5:
			overflowing.append("%s (%s) ends at %.0f" % [control.name, control.get_class(), control.get_global_rect().end.x])
	assert_eq(overflowing.size(), 0, "%s fits %.0f px: %s" % [context, width, ", ".join(overflowing.slice(0, 5))])
