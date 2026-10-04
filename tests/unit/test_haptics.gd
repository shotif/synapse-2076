extends "res://tests/framework/test_case.gd"
## Haptics: the pulse lengths, the "vibration" setting and the touch-device
## check (through the injected hooks), and the crisis card's cues: a swipe
## pulses and emits swiped(-1 / +1) on the card and the dialog, a tapped
## response pulses and emits option_pressed.

const DialogScene := preload("res://ui/components/dilemma_dialog.tscn")
const RICH := {"capital": 500.0, "regulatory_goodwill": 60.0, "talent": 800.0, "compute_clusters": 8.0}
const POOR := {"capital": 30.0, "regulatory_goodwill": 0.0}

var settings: GameSettings
var pulses: Array = []
var touch := true


func before_each() -> void:
	settings = GameSettings.new()
	settings.path = ""
	GameSettings.use(settings)
	pulses.clear()
	touch = true
	Haptics.vibrate_func = func(duration_ms: int, amplitude: float) -> void: pulses.append([duration_ms, amplitude])
	Haptics.touch_func = func() -> bool: return touch


func after_each() -> void:
	Haptics.vibrate_func = Callable()
	Haptics.touch_func = Callable()
	GameSettings.use(null)


func test_pulse_lengths() -> void:
	var expected := {"swipe": 20, "select": 12, "confirm": 35, "alert": 70, "era": 90}
	for kind in expected:
		assert_eq(Haptics.duration_ms(kind), int(expected[kind]), kind)
		assert_true(Haptics.pulse(kind), kind)
	assert_eq(pulses.size(), 5)
	for pulse in pulses:
		assert_between(float(pulse[1]), 0.1, 1.0, "amplitude in range")
	assert_eq(pulses[0], [20, 0.35], "swipe: 20 ms")
	assert_eq(int(pulses[3][0]), 70, "alert: 70 ms")
	assert_false(Haptics.pulse("buzz"), "unknown kinds are ignored")
	assert_false(Haptics.pulse(""))
	assert_eq(Haptics.duration_ms("buzz"), 0)
	assert_eq(pulses.size(), 5)


func test_the_vibration_setting_turns_pulses_off() -> void:
	settings.set_value("vibration", false)
	assert_false(Haptics.enabled())
	assert_false(Haptics.pulse("alert"))
	assert_eq(pulses.size(), 0)
	settings.set_value("vibration", true)
	assert_true(Haptics.pulse("alert"))
	assert_eq(pulses.size(), 1)


func test_only_touch_devices_vibrate() -> void:
	touch = false
	assert_false(Haptics.is_touch_device())
	assert_false(Haptics.pulse("confirm"), "no pulse without a touch screen")
	assert_eq(pulses.size(), 0)
	touch = true
	assert_true(Haptics.pulse("confirm"))
	# Without the hook: this headless desktop run is neither a phone nor a browser.
	Haptics.touch_func = Callable()
	assert_eq(Haptics.is_touch_device(), OS.has_feature("mobile") or (OS.has_feature("web") and DisplayServer.is_touchscreen_available()))
	assert_false(Haptics.pulse("confirm"), "desktop runs never vibrate")
	assert_eq(pulses.size(), 1)


# --- The crisis card's cues -------------------------------------------------------------------

var host: Control
var dialog: DilemmaDialog
var swipes: Array[int] = []
var card_swipes: Array[int] = []
var pressed: Array[String] = []
var chosen: Array[String] = []


func _open_dialog() -> void:
	host = Control.new()
	host.theme = EraTheme.get_theme(1)
	host.size = Vector2(1600, 900)
	tree.root.add_child(host)
	dialog = DialogScene.instantiate()
	host.add_child(dialog)
	swipes.clear()
	card_swipes.clear()
	pressed.clear()
	chosen.clear()
	dialog.swiped.connect(func(direction: int): swipes.append(direction))
	dialog.get_card().swiped.connect(func(direction: int): card_swipes.append(direction))
	dialog.option_pressed.connect(func(option_id: String): pressed.append(option_id))
	dialog.option_chosen.connect(func(option_id: String): chosen.append(option_id))
	await tree.process_frame


func _close_dialog() -> void:
	host.queue_free()
	await tree.process_frame


func _present(resources: Dictionary = RICH) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var card := DilemmaDeck.new()._instantiate(DilemmaDeck.get_template("SELF_MODIFICATION_SIGNAL"),
		{"role": "CEO", "turn": 60, "year": SimConstants.year_for_turn(60)}, rng, "DECK", 0)
	dialog.present(card, resources, "CEO")
	await wait_seconds(DilemmaDialog.ENTER_TIME + 0.1)
	pulses.clear()


func _mouse(at: Vector2, is_pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = is_pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if is_pressed else 0
	event.position = at
	event.global_position = at
	tree.root.push_input(event, true)


func _drag(dx: float) -> void:
	var start := dialog.get_card().get_global_rect().get_center()
	_mouse(start, true)
	for step in [0.25, 0.5, 0.75, 1.0]:
		var motion := InputEventMouseMotion.new()
		motion.position = start + Vector2(dx * float(step), 2.0)
		motion.global_position = motion.position
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		tree.root.push_input(motion, true)
	_mouse(start + Vector2(dx, 2.0), false)


func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	tree.root.push_input(event, true)


func test_a_committed_swipe_pulses_and_signals_its_side() -> void:
	await _open_dialog()
	await _present()
	_drag(-170.0)
	assert_eq(swipes, [-1] as Array[int], "the dialog passes the swipe on at once")
	assert_eq(card_swipes, [-1] as Array[int], "the card signals it")
	assert_eq(pulses, [[Haptics.duration_ms("swipe"), 0.35]], "one swipe tick")
	assert_eq(pressed.size(), 0, "a swipe is not a press")
	await wait_seconds(DilemmaDialog.FLY_TIME + 0.15)
	assert_eq(chosen, ["A"] as Array[String], "the choice still lands")
	await _present()
	_key(KEY_RIGHT)
	assert_eq(swipes, [-1, 1] as Array[int], "→ counts as a swipe right")
	await wait_seconds(DilemmaDialog.FLY_TIME + 0.15)
	await _present()
	_drag(-60.0)
	await wait_seconds(DilemmaDialog.SNAP_TIME + 0.1)
	assert_eq(swipes.size(), 2, "a short drag snaps back without a swipe")
	assert_eq(pulses.size(), 0)
	await _close_dialog()


func test_an_unaffordable_swipe_is_not_a_swipe() -> void:
	await _open_dialog()
	await _present(POOR)
	_drag(-170.0)
	await wait_seconds(0.2)
	assert_eq(swipes.size(), 0, "the card shakes back")
	assert_eq(pulses.size(), 0)
	await _close_dialog()


func test_a_tapped_response_pulses_and_signals_at_once() -> void:
	await _open_dialog()
	await _present()
	var rows: Array = dialog.find_children("Option*", "Button", true, false)
	var center: Vector2 = (rows[1] as Button).get_global_rect().get_center()
	_mouse(center, true)
	_mouse(center, false)
	assert_eq(pressed, ["B"] as Array[String], "option_pressed comes before the card leaves")
	assert_eq(pulses, [[Haptics.duration_ms("select"), 0.25]], "a select tick")
	assert_eq(swipes.size(), 0)
	assert_eq(chosen.size(), 0)
	await wait_seconds(DilemmaDialog.FLY_TIME + 0.15)
	assert_eq(chosen, ["B"] as Array[String])
	await _present()
	_key(KEY_3)
	assert_eq(pressed, ["B", DilemmaDeck.DEFER_ID] as Array[String], "keys for rows press them too")
	await wait_seconds(DilemmaDialog.FLY_TIME + 0.15)
	await _close_dialog()
