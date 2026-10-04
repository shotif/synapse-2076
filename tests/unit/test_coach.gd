extends "res://tests/framework/test_case.gd"
## The guided first campaign (Coach): steps advance with Next or with game
## events, missing targets are skipped, tabs are requested before a target is
## lit, skipping or finishing persists "coach_done", the cutout follows its
## target, and the bubble stays on a phone's screen.

const PHONE := Vector2(412, 915)

var settings: GameSettings
var host: Control
var coach: Coach
var targets := {}
var tabs: Array[String] = []
var shown: Array[String] = []


func before_each() -> void:
	settings = GameSettings.new()
	settings.path = ""
	GameSettings.use(settings)
	host = Control.new()
	host.theme = EraTheme.get_theme(1)
	host.size = PHONE
	tree.root.add_child(host)
	targets = {
		"vitals": _box("Vitals", Rect2(8, 8, 396, 64)),
		"crisis_card": _box("Card", Rect2(16, 84, 380, 330)),
		"card_options": _box("Options", Rect2(16, 430, 380, 300)),
		"directives": _box("Directives", Rect2(8, 120, 396, 560)),
		"execute": _box("Execute", Rect2(8, 820, 396, 48)),
		"newswire": _box("Newswire", Rect2(8, 80, 396, 700)),
		"goals": _box("Goals", Rect2(8, 76, 396, 40)),
		"lens_tab": _box("LensTab", Rect2(206, 870, 100, 44)),
		"menu": _box("Menu", Rect2(360, 4, 44, 44)),
	}
	coach = Coach.new()
	host.add_child(coach)
	tabs.clear()
	shown.clear()
	coach.tab_requested.connect(func(tab: String) -> void: tabs.append(tab))
	coach.step_shown.connect(func(step_id: String) -> void: shown.append(step_id))
	await tree.process_frame


func after_each() -> void:
	host.queue_free()
	await tree.process_frame
	GameSettings.use(null)
	EraTheme.invalidate()


func _box(box_name: String, rect: Rect2) -> Control:
	var box := ColorRect.new()
	box.name = box_name
	box.color = Color(0.2, 0.3, 0.4)
	box.position = rect.position
	box.size = rect.size
	host.add_child(box)
	return box


## Presses Next until the step is [param step_id] (at most [param limit] times).
func _next_until(step_id: String, limit: int = 8) -> void:
	for _i in limit:
		if coach.current_step_id() == step_id:
			return
		coach.next()


func test_steps_advance_with_next_and_game_events() -> void:
	assert_true(Coach.should_run(), "a first campaign gets the tutorial")
	coach.begin(targets)
	assert_true(coach.is_running())
	assert_true(coach.visible)
	assert_eq(coach.current_step_id(), "crisis", "turn one opens on the crisis card")
	assert_eq(coach.get_target(), targets["crisis_card"])
	coach.next()
	assert_eq(coach.current_step_id(), "respond")
	coach.next()
	assert_eq(coach.current_step_id(), "pips")
	coach.next()
	assert_eq(coach.current_step_id(), "vitals")
	coach.next()
	assert_eq(coach.current_step_id(), "answer")
	assert_false((coach.find_child("NextButton", true, false) as Button).visible, "the player has to act")
	coach.next()
	assert_eq(coach.current_step_id(), "answer", "Next does not skip an action step")
	coach.advance_from("something_else")
	assert_eq(coach.current_step_id(), "answer", "unrelated events are ignored")
	coach.advance_from("crisis_answered")
	assert_eq(coach.current_step_id(), "execute_first")
	coach.advance_from("crisis_answered")
	assert_eq(coach.current_step_id(), "execute_first", "events never skip into the next turn")
	coach.advance_from("turn_submitted")
	assert_true(coach.is_waiting(), "between turns the coach waits")
	assert_false(coach.visible, "and stays out of the way")
	coach.advance_from("crisis_answered")
	assert_eq(coach.current_step_id(), "directives", "turn two: directives once the crisis is answered")
	coach.next()
	assert_eq(coach.current_step_id(), "costs")
	coach.next()
	assert_eq(coach.current_step_id(), "execute_second")
	coach.advance_from("turn_submitted")
	assert_true(coach.is_waiting())
	coach.advance_from("crisis_answered")
	assert_eq(coach.current_step_id(), "newswire")
	coach.next()
	assert_eq(coach.current_step_id(), "goals", "no WORLD tab here: that step is skipped")
	coach.next()
	assert_eq(coach.current_step_id(), "why")
	assert_eq(coach.get_target(), targets["vitals"])
	coach.next()
	assert_eq(coach.current_step_id(), "lens")
	coach.next()
	assert_eq(coach.current_step_id(), "menu")
	assert_eq((coach.find_child("NextButton", true, false) as Button).text, "Done", "the last step says Done")
	var finished := [false]
	coach.finished.connect(func() -> void: finished[0] = true)
	coach.next()
	assert_true(finished[0], "finished emitted")
	assert_false(coach.is_running())
	assert_false(coach.visible)
	assert_true(bool(settings.get_value("coach_done")), "completion is saved")
	assert_false(Coach.should_run())
	for step in Coach.STEPS:
		var sentences := String(step.get("text", "")).count(". ") + 1
		assert_lte(float(sentences), 2.0, "%s: two sentences at most" % step["id"])


func test_a_player_ahead_of_the_coach_is_followed() -> void:
	coach.begin(targets)
	assert_eq(coach.current_step_id(), "crisis")
	coach.advance_from("crisis_answered")
	assert_eq(coach.current_step_id(), "execute_first", "answered during the explanation: on to Execute")
	coach.advance_from("turn_submitted")
	coach.advance_from("crisis_answered")
	assert_eq(coach.current_step_id(), "directives")
	coach.advance_from("turn_submitted")
	assert_true(coach.is_waiting(), "executed during the explanation: wait for turn three")


func test_missing_and_hidden_targets_are_skipped() -> void:
	targets.erase("crisis_card")
	(targets["vitals"] as Control).visible = false
	coach.begin(targets)
	assert_eq(coach.current_step_id(), "respond", "no crisis card target: its step is skipped")
	_next_until("answer")
	assert_eq(coach.current_step_id(), "answer", "hidden vitals skipped")
	assert_false(shown.has("vitals"))
	coach.stop()
	assert_false(coach.is_running())
	assert_false(bool(settings.get_value("coach_done")), "stopping is not finishing")
	var late := _box("Late", Rect2(20, 100, 200, 100))
	coach.begin({"crisis_card": func() -> Control: return late, "card_options": targets["card_options"]})
	assert_eq(coach.get_target(), late, "a Callable target is resolved when its step starts")
	late.visible = false
	coach.refresh()
	assert_eq(coach.current_step_id(), "respond", "a target that goes away moves the tutorial on")
	coach.begin({})
	assert_true(coach.is_waiting(), "nothing to show this turn: wait for the next")
	coach.advance_from("crisis_answered")
	coach.advance_from("crisis_answered")
	assert_false(coach.is_running(), "nothing to show at all: the tutorial ends")
	assert_true(bool(settings.get_value("coach_done")))


func test_tabs_are_requested_before_highlighting() -> void:
	var news: Control = targets["newswire"]
	news.visible = false
	coach.tab_requested.connect(func(tab: String) -> void: news.visible = tab == "news")
	coach.begin(targets, {"goals": "lens"})
	coach.advance_from("crisis_answered")
	assert_eq(tabs.size(), 1, "one tab requested so far")
	assert_eq(tabs[0] if not tabs.is_empty() else "", "act", "Execute lives on the ACT tab")
	coach.advance_from("turn_submitted")
	coach.advance_from("crisis_answered")
	coach.advance_from("turn_submitted")
	coach.advance_from("crisis_answered")
	assert_eq(coach.current_step_id(), "newswire", "the requested tab showed the newswire")
	assert_eq(tabs[-1], "news")
	coach.next()
	assert_eq(coach.current_step_id(), "goals")
	assert_eq(tabs[-1], "lens", "the dashboard can say where a target lives")


func test_skipping_persists_and_replays() -> void:
	var skipped := [false]
	coach.skipped.connect(func() -> void: skipped[0] = true)
	coach.begin(targets)
	(coach.find_child("SkipButton", true, false) as Button).pressed.emit()
	assert_true(skipped[0], "skipped emitted")
	assert_false(coach.is_running())
	assert_true(bool(settings.get_value("coach_done")))
	assert_false(Coach.should_run(), "no tutorial in the next campaign")
	Coach.reset_progress()
	assert_true(Coach.should_run(), "replaying the tutorial resets it")


func test_cutout_follows_the_target() -> void:
	coach.begin(targets)
	var card: Control = targets["crisis_card"]
	assert_eq(coach.get_cutout(), card.get_global_rect().grow(Coach.PAD), "lit around the card")
	card.position += Vector2(0, 60)
	coach.refresh()
	assert_eq(coach.get_cutout(), card.get_global_rect().grow(Coach.PAD), "follows a moving target")
	card.position -= Vector2(0, 60)
	await wait_frames(2)
	assert_eq(coach.get_cutout(), card.get_global_rect().grow(Coach.PAD), "and keeps following every frame")
	var inside := coach.get_cutout().get_center()
	assert_false(coach._has_point(inside), "the target takes input through the cutout")
	assert_true(coach._has_point(Vector2(4, 900)), "a Next step holds the rest of the screen")
	_next_until("answer")
	assert_false(coach._has_point(Vector2(4, 900)), "an action step lets the player act anywhere")
	host.size = Vector2(1180, 820)
	await wait_frames(2)
	assert_eq(coach.size, host.size, "the coach covers the screen after a resize")
	assert_eq(coach.get_cutout(), (targets["card_options"] as Control).get_global_rect().grow(Coach.PAD))


func test_bubble_stays_on_a_phone_screen() -> void:
	for era_number in [1, 2, 3]:
		host.theme = EraTheme.get_theme(era_number)
		Coach.reset_progress()
		coach.begin(targets)
		for _step in 20:
			if not coach.is_running():
				break
			if coach.is_waiting():
				coach.advance_from("crisis_answered")
				continue
			await wait_frames(2)
			var bubble := coach.get_bubble().get_global_rect()
			var step := coach.current_step_id()
			assert_gte(bubble.position.x, 0.0, "era %d %s: bubble left edge" % [era_number, step])
			assert_lte(bubble.end.x, PHONE.x + 0.5, "era %d %s: bubble right edge" % [era_number, step])
			assert_gte(bubble.position.y, 0.0, "era %d %s: bubble top" % [era_number, step])
			assert_lte(bubble.end.y, PHONE.y + 0.5, "era %d %s: bubble bottom" % [era_number, step])
			_assert_fits(coach, PHONE.x, "era %d %s" % [era_number, step])
			if String(coach.current_step().get("advance", "")) == "signal":
				coach.advance_from(String(coach.current_step()["signal"]))
			else:
				coach.next()
	assert_true(bool(settings.get_value("coach_done")))
	var bubble_text := (coach.find_child("Text", true, false) as Label).text
	assert_false(bubble_text.contains("{"), "placeholders are filled")


func _assert_fits(root: Control, width: float, context: String) -> void:
	var overflowing: Array[String] = []
	for node in root.find_children("*", "Control", true, false):
		var control := node as Control
		if control.is_visible_in_tree() and control.get_global_rect().end.x > width + 0.5:
			overflowing.append("%s (%s) ends at %.0f" % [control.name, control.get_class(), control.get_global_rect().end.x])
	assert_eq(overflowing.size(), 0, "%s fits %.0f px: %s" % [context, width, ", ".join(overflowing.slice(0, 5))])
