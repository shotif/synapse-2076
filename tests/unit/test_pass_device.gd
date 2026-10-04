extends "res://tests/framework/test_case.gd"
## PassDevice, the pass-and-play hand-off screen: an opaque cover above the
## whole interface that swallows input, names the next player with their
## faction's glyph and color, lists what happened while they were away,
## reveals their desk on request (revealed(role)) and fits a 412 px phone and
## the desktop in every era.

const LONG_HEADLINES: Array[String] = [
	"Governance Council brokers an emergency compute-rationing accord across the Global South Data Alliance",
	"Frontier Lab ships Frontier Model-17 hours after its own safety team resigns in protest",
	"Grid operators in the Oregon High Desert ration power as datacenter heat domes spread",
	"Unattributed signal claims a self-modifying model has slipped its sandbox",
	"Citizen Coalition votes to strike across insurance underwriting and logistics",
	"A sixth headline that should not fit in the box",
]

## Counts key presses that reach nodes behind the cover.
class KeyProbe extends Node:
	var keys := 0

	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.is_pressed():
			keys += 1


var settings: GameSettings
var host: Control
var cover: PassDevice
var probe: KeyProbe
var below: Button
var below_presses := 0
var revealed: Array[String] = []
var pulses: Array = []


func before_each() -> void:
	settings = GameSettings.new()
	settings.path = ""
	GameSettings.use(settings)
	pulses.clear()
	Haptics.vibrate_func = func(duration_ms: int, amplitude: float) -> void: pulses.append([duration_ms, amplitude])
	Haptics.touch_func = func() -> bool: return true
	host = Control.new()
	host.theme = EraTheme.get_theme(1)
	host.position = Vector2.ZERO
	host.size = Vector2(1600, 900)
	tree.root.add_child(host)
	# The desk underneath: a full-screen button and a node that listens for keys.
	below = Button.new()
	below.text = "Desk"
	below.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	below_presses = 0
	below.pressed.connect(func(): below_presses += 1)
	host.add_child(below)
	probe = KeyProbe.new()
	host.add_child(probe)
	cover = PassDevice.new()
	host.add_child(cover)
	revealed.clear()
	cover.revealed.connect(func(role: String): revealed.append(role))
	await tree.process_frame


func after_each() -> void:
	host.queue_free()
	Haptics.vibrate_func = Callable()
	Haptics.touch_func = Callable()
	GameSettings.use(null)
	await tree.process_frame


func _headlines(count: int) -> Array[String]:
	var out: Array[String] = []
	out.assign(LONG_HEADLINES.slice(0, count))
	return out


func _text(node_name: String) -> String:
	return (cover.find_child(node_name, true, false) as Control).get("text")


func _click(at: Vector2) -> void:
	for is_pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = is_pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if is_pressed else 0
		event.position = at
		event.global_position = at
		tree.root.push_input(event, true)


func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	tree.root.push_input(event, true)


# --- Content ---------------------------------------------------------------------------

func test_present_names_the_next_player() -> void:
	assert_false(cover.visible, "hidden until a hand-off")
	cover.present(SimConstants.CEO, SimConstants.year_for_turn(10), _headlines(2))
	await tree.process_frame
	assert_true(cover.visible)
	assert_eq(cover.role, SimConstants.CEO)
	assert_eq(cover.turn, 10, "the turn comes from the year")
	assert_eq(_text("Lead"), "Pass the device to the")
	assert_eq(_text("RoleTitle"), "Frontier Lab CEO")
	assert_string_contains(_text("Kicker"), "Turn 10")
	assert_string_contains(_text("Kicker"), "H1 2031")
	assert_eq(_text("Reveal"), "I'm the Frontier Lab CEO. Show my desk")
	var mark := cover.find_child("Mark", true, false) as TextureRect
	assert_eq(mark.texture, Glyphs.tile(Glyphs.for_faction(SimConstants.CEO), PassDevice.MARK_SIZE,
		EraStyle.for_era(1).faction_color(SimConstants.CEO), EraStyle.for_era(1).bg, 18, 0.56), "the faction's glyph on its color")
	var title := cover.find_child("RoleTitle", true, false) as Label
	assert_eq(title.get_theme_color("font_color"), EraStyle.for_era(1).faction_color(SimConstants.CEO).lerp(EraStyle.for_era(1).text_bright, 0.15),
		"the name in the faction's color")


func test_while_you_were_away_lists_up_to_five_headlines() -> void:
	cover.present(SimConstants.ASI, 2050.5, _headlines(2), 49)
	await tree.process_frame
	assert_eq(cover.turn, 49, "an explicit turn wins")
	var box := cover.find_child("WhileAway", true, false) as Control
	assert_true(box.visible)
	var shown: Array[String] = []
	for label in cover.find_children("Headline", "Label", true, false):
		shown.append((label as Label).text)
	assert_eq(shown, _headlines(2))
	cover.present(SimConstants.ASI, 2050.5, _headlines(6))
	await tree.process_frame
	assert_eq(cover.find_children("Headline", "Label", true, false).size(), PassDevice.MAX_HEADLINES, "five at most")
	cover.present(SimConstants.ASI, 2050.5, [] as Array[String])
	await tree.process_frame
	assert_false(box.visible, "no box when nothing happened")


func test_headlines_since_picks_the_news_another_player_missed() -> void:
	var event_log: Array = []
	var severities := ["INFO", "CRITICAL", "INFO", "WARN", "INFO"]
	for i in severities.size():
		event_log.append({"turn": 3, "year": 2027.5, "category": "ACTION", "severity": severities[i], "faction": SimConstants.GOVERNANCE,
			"action": "UNKNOWN_%d" % i, "text": "GOVERNANCE COUNCIL :: Headline %d" % i})
	event_log.append({"turn": 3, "year": 2027.5, "category": "ACTION", "severity": "CRITICAL", "faction": SimConstants.CEO,
		"action": "UNKNOWN_MINE", "text": "FRONTIER LAB :: My own move"})
	event_log.append({"turn": 3, "year": 2027.5, "category": "SYSTEM", "severity": "INFO", "faction": "", "text": "Bookkeeping."})
	event_log.append({"turn": 3, "year": 2027.5, "category": "ACTION", "severity": "INFO", "faction": SimConstants.ASI,
		"action": SimulationEngine.CONSERVE, "text": "EMERGENT ASI :: Conserve"})
	var lines := PassDevice.headlines_since(event_log, 1, SimConstants.CEO, 3)
	assert_eq(lines, ["Governance Council: Headline 1", "Governance Council: Headline 3", "Governance Council: Headline 4"] as Array[String],
		"critical and warning first, then the latest, told in order; not the viewer's own move or routine notes")
	assert_eq(PassDevice.headlines_since(event_log, event_log.size(), SimConstants.CEO).size(), 0, "nothing new")
	assert_eq(PassDevice.headlines_since(event_log, 0, SimConstants.GOVERNANCE).size(), 1, "the Council's own moves are not news to it")

	var engine := SimulationEngine.new()
	engine.start_campaign(SimConstants.CITIZEN, 2076, {"autoplay": true})
	engine.run_headless(12)
	var news := PassDevice.headlines_since(engine.event_log, 0, SimConstants.CITIZEN)
	assert_between(news.size(), 1, PassDevice.MAX_HEADLINES, "a real campaign has news")
	for line in news:
		assert_false(line.strip_edges().is_empty())


# --- Cover and input --------------------------------------------------------------------

func test_the_cover_is_opaque_and_above_everything() -> void:
	cover.present(SimConstants.GOVERNANCE, 2040.0, _headlines(1))
	await tree.process_frame
	assert_gt(cover.z_index, 3, "above the era upgrade (z 3), the front page and menus (z 2)")
	assert_eq(cover.mouse_filter, Control.MOUSE_FILTER_STOP)
	var shade := cover.find_child("Cover", false, false) as ColorRect
	assert_not_null(shade)
	assert_eq(shade.color.a, 1.0, "nothing of the desk shows through")
	assert_eq(shade.color, Color(EraStyle.for_era(1).bg, 1.0))
	assert_eq(shade.get_global_rect(), host.get_global_rect(), "covers the whole screen")
	assert_eq(cover.get_global_rect(), host.get_global_rect())
	host.theme = EraTheme.get_theme(3)
	await tree.process_frame
	assert_eq(shade.color, Color(EraStyle.for_era(3).bg, 1.0), "the cover follows the era")
	assert_eq(_text("Kicker"), _text("Kicker").to_lower(), "Era III speaks in lower case")


func test_clicks_and_keys_never_reach_the_desk() -> void:
	cover.present(SimConstants.CITIZEN, 2033.0, _headlines(3))
	await tree.process_frame
	# Corners: away from the reveal button, over the bare cover.
	_click(Vector2(40, 40))
	_click(Vector2(1560, 40))
	_key(KEY_LEFT)
	_key(KEY_1)
	await tree.process_frame
	assert_true(cover.visible)
	assert_eq(below_presses, 0, "the desk button never sees a click")
	assert_eq(probe.keys, 0, "keys stop at the cover")
	assert_eq(revealed.size(), 0)
	cover.close()
	_click(Vector2(40, 40))
	_key(KEY_LEFT)
	await tree.process_frame
	assert_eq(below_presses, 1, "once lifted, the desk works again")
	assert_eq(probe.keys, 1)


## Scrolls the reveal button into view (headless text runs tall) and returns it.
func _reveal_button() -> Button:
	var button := cover.find_child("Reveal", true, false) as Button
	(cover.get_node("OverlayScroll") as ScrollContainer).ensure_control_visible(button)
	await wait_frames(2)
	return button


func test_reveal_emits_the_role() -> void:
	cover.present(SimConstants.ASI, 2052.0, _headlines(2))
	await tree.process_frame
	var button: Button = await _reveal_button()
	assert_true(host.get_global_rect().has_point(button.get_global_rect().get_center()), "the button is on screen")
	_click(button.get_global_rect().get_center())
	await tree.process_frame
	assert_eq(revealed, [SimConstants.ASI] as Array[String])
	assert_false(cover.visible, "the cover lifts")
	assert_eq(pulses, [[Haptics.duration_ms("confirm"), 0.55]], "a confirming tick")
	assert_eq(below_presses, 0, "the click that lifts it does not fall through")
	cover.reveal()
	assert_eq(revealed.size(), 1, "revealing twice does nothing")

	cover.present(SimConstants.CEO, 2052.5, _headlines(0))
	_key(KEY_ENTER)
	assert_eq(revealed.size(), 1, "a key held over from the last player does not reveal")
	await wait_seconds(PassDevice.KEY_DELAY + 0.1)
	_key(KEY_ENTER)
	assert_eq(revealed, [SimConstants.ASI, SimConstants.CEO] as Array[String], "Enter reveals after a moment")


# --- Layouts ---------------------------------------------------------------------------

## Every visible control in the cover stays within [param width].
func _assert_fits(width: float, context: String) -> void:
	var overflowing: Array[String] = []
	for node in cover.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect()
		if rect.end.x > width + 0.5 or rect.position.x < -0.5:
			overflowing.append("%s (%s) spans %.0f-%.0f" % [control.name, control.get_class(), rect.position.x, rect.end.x])
	assert_eq(overflowing.size(), 0, "%s fits %.0f px: %s" % [context, width, ", ".join(overflowing.slice(0, 5))])


func test_fits_a_phone_in_every_era_and_role() -> void:
	host.size = Vector2(412, 915)
	cover.set_compact(true)
	for era_number in [1, 2, 3]:
		host.theme = EraTheme.get_theme(era_number)
		for role in SimConstants.FACTION_ORDER:
			cover.present(role, 2075.5, _headlines(5))
			await wait_frames(2)
			_assert_fits(412.0, "era %d %s" % [era_number, role])
	var column := cover.find_child("Column", true, false) as Control
	assert_almost_eq(column.get_global_rect().get_center().x, 206.0, 1.0, "centered")
	var button := cover.find_child("Reveal", true, false) as Button
	assert_gte(button.size.y, 44.0, "a finger-sized button")


func test_desktop_layout_is_a_centered_column() -> void:
	cover.present(SimConstants.GOVERNANCE, 2026.5, _headlines(4))
	await wait_frames(2)
	_assert_fits(1600.0, "desktop")
	var column := cover.find_child("Column", true, false) as Control
	assert_almost_eq(column.size.x, PassDevice.DESKTOP_WIDTH, 0.5, "a 560 px column")
	# Centered in the scroll area (headless text runs tall, so a scroll bar may take a few pixels).
	var area := (cover.get_node("OverlayScroll") as ScrollContainer).get_child(0) as Control
	assert_almost_eq(column.get_global_rect().get_center().x, area.get_global_rect().get_center().x, 1.0, "centered")
	assert_almost_eq(column.get_global_rect().get_center().x, 800.0, 8.0)
	cover.set_compact(true)
	host.size = Vector2(412, 915)
	await wait_frames(2)
	_assert_fits(412.0, "desktop cover moved to a phone")
	cover.set_compact(false)
	host.size = Vector2(1600, 900)
	await wait_frames(2)
	assert_almost_eq(column.size.x, PassDevice.DESKTOP_WIDTH, 0.5, "and back")


func test_present_before_ready_shows_once_built() -> void:
	var late := PassDevice.new()
	late.present(SimConstants.CITIZEN, 2030.0, _headlines(1))
	host.add_child(late)
	await tree.process_frame
	assert_true(late.visible, "presented as soon as it is in the tree")
	assert_eq((late.find_child("RoleTitle", true, false) as Label).text, "Post-Work Citizen Coalition")
	late.queue_free()
