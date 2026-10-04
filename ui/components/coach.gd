class_name Coach
extends Control
## The guided first campaign: coach marks over the real interface for the
## first three turns of a player's first campaign. Everything but the target
## is dimmed, the target sits in a lit cutout, and a speech bubble explains it
## with Next and "Skip tutorial".
##
##   if Coach.should_run():
##       coach.begin({"crisis_card": dilemma.get_card(), "card_options": dilemma.get_responses(), ...})
##   dilemma.option_chosen -> coach.advance_from("crisis_answered")
##   a submitted turn      -> coach.advance_from("turn_submitted")
##   coach.tab_requested   -> show_tab(tab)   (phones keep some targets on other tabs)
##
## Target ids: crisis_card, card_options, vitals, directives, execute,
## newswire, goals, lens_tab, act_tab, world_tab, news_tab, menu. A target is a
## Control or a Callable returning one (resolved when its step starts); steps
## whose target is missing or hidden are skipped. A step is {id, turn, target
## (an id or a list of ids, first visible wins), title, text, advance ("next":
## the Next button; "signal": an advance_from() event named by "signal"),
## tab (optional)}. A step with no target and a "signal" advance waits,
## hidden, for that event (the next turn's crisis being answered).
##
## "next" steps block input outside the cutout; "signal" steps let it through
## so the player can act. Finishing or skipping sets GameSettings
## "coach_done". Add the coach as the dashboard's last child (input follows
## tree order); it draws above the dialogs (z_index 4).

signal tab_requested(tab: String)
signal step_shown(step_id: String)
signal finished
signal skipped

## Cutout padding around the target, bubble margin from the screen edge and
## gap from the cutout.
const PAD := 6.0
const MARGIN := 8.0
const GAP := 14.0
const BUBBLE_WIDTH := 340.0
const POINTER := 9.0
const DIM_ALPHA := 0.62
const PULSE_PERIOD := 1.6

const STEPS := [
	# Turn 1: the crisis card, its answers and effect arrows, the vitals.
	{"id": "crisis", "turn": 1, "target": "crisis_card", "advance": "next", "title": "A crisis lands on your desk",
		"text": "Every turn opens with one crisis card. The title says what happened, and the dots show how serious it is."},
	{"id": "respond", "turn": 1, "target": "card_options", "advance": "next", "title": "Swipe or tap to answer",
		"text": "Swipe the card left or right for the first two answers, or tap any answer in the list. The last one puts the crisis off, but it comes back worse."},
	{"id": "pips", "turn": 1, "target": "card_options", "advance": "next", "title": "Read the arrows",
		"text": "Each glyph is a vital sign; ▲ and ▼ show which way an answer moves it, and more arrows mean a bigger change. {good} helps the world, {bad} hurts it."},
	{"id": "vitals", "turn": 1, "target": "vitals", "advance": "next", "title": "The world's vital signs",
		"text": "These six numbers are the health of the world. Hold or hover over an answer to preview how it would move them."},
	{"id": "answer", "turn": 1, "target": "card_options", "advance": "signal", "signal": "crisis_answered", "title": "Your call",
		"text": "Pick an answer now. There's no perfect choice, only trade-offs."},
	{"id": "execute_first", "turn": 1, "target": "execute", "tab": "act", "advance": "signal", "signal": "turn_submitted",
		"title": "End your turn", "text": "Press Execute to let half a year play out. Next turn you'll add moves of your own."},
	# Turn 2: directives, costs and cooldowns, Execute.
	{"id": "wait_second", "turn": 2, "target": "", "advance": "signal", "signal": "crisis_answered"},
	{"id": "directives", "turn": 2, "target": "directives", "tab": "act", "advance": "next", "title": "Directives are your moves",
		"text": "Pick up to two each turn. A slider appears when you pick one: spend more for a stronger effect."},
	{"id": "costs", "turn": 2, "target": "directives", "tab": "act", "advance": "next", "title": "Costs and cooldowns",
		"text": "Each directive costs your faction's currencies, shown on its card. Some need a few turns to recharge before you can use them again."},
	{"id": "execute_second", "turn": 2, "target": "execute", "tab": "act", "advance": "signal", "signal": "turn_submitted",
		"title": "Make your moves", "text": "Tick one or two directives, then press Execute. Your rivals move at the same time."},
	# Turn 3: the newswire, the world, goals, why things changed, the lens.
	{"id": "wait_third", "turn": 3, "target": "", "advance": "signal", "signal": "crisis_answered"},
	{"id": "newswire", "turn": 3, "target": "newswire", "tab": "news", "advance": "next", "title": "The newswire",
		"text": "Every move in the world becomes a headline here. Skim it to see what your rivals just did."},
	{"id": "world", "turn": 3, "target": "world_tab", "advance": "next", "title": "The world",
		"text": "The WORLD tab shows the globe, one layer per vital sign. Tap a chip on it to see a single layer."},
	{"id": "goals", "turn": 3, "target": "goals", "tab": "act", "advance": "next", "title": "Era goals",
		"text": "Each era sets your faction a goal. Meet it before the era ends for a reward and a better final score."},
	{"id": "why", "turn": 3, "target": "vitals", "tab": "act", "advance": "next", "title": "Why did that change?",
		"text": "Tap any number to see what moved it: your moves, your rivals, or the world itself."},
	{"id": "lens", "turn": 3, "target": "lens_tab", "advance": "next", "title": "Your lens",
		"text": "Your faction sees the world its own way. Open your lens any time for the view only you get."},
	{"id": "menu", "turn": 3, "target": "menu", "advance": "next", "title": "Settings and help",
		"text": "Text size, color-blind colors, plain words and this tour live in the menu. The next fifty years are yours."},
]
## Names for the good and bad colors per era (color-blind: blue and orange).
const COLOR_WORDS := {1: ["Blue", "orange"], 2: ["Cyan", "amber"], 3: ["Teal", "gold"]}
const ORDINALS := {1: "First turn", 2: "Second turn", 3: "Third turn"}

## Target id -> Control, or a Callable returning one.
var targets := {}
## Target id -> tab to show on phones before highlighting it (overrides the
## step's own "tab").
var target_tabs := {}
## The step on show (-1 before begin()).
var step_index := -1
var compact := false

var _running := false
var _target: Control
var _hole := Rect2()
var _passthrough := false
var _pulse := 0.0
var _style: EraStyle
var _ring: StyleBoxFlat
var _bubble: PanelContainer
var _title: Label
var _text: Label
var _counter: Label
var _skip_button: Button
var _next_button: Button


## True until the player has finished or skipped the tutorial once
## (GameSettings "coach_done").
static func should_run() -> bool:
	return not bool(GameSettings.value("coach_done"))


## Makes the tutorial run again in the next campaign (or now, via begin()).
static func reset_progress() -> void:
	GameSettings.instance().set_value("coach_done", false)


func _init() -> void:
	name = "Coach"
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 4
	visible = false
	set_process(false)
	_bubble = PanelContainer.new()
	_bubble.name = "Bubble"
	add_child(_bubble)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_bubble.add_child(box)
	_counter = _label("Counter", false)
	box.add_child(_counter)
	_title = _label("Title", true)
	box.add_child(_title)
	_text = _label("Text", true)
	box.add_child(_text)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	_skip_button = Button.new()
	_skip_button.name = "SkipButton"
	_skip_button.text = "Skip tutorial"
	_skip_button.theme_type_variation = "GhostButton"
	_skip_button.focus_mode = Control.FOCUS_NONE
	_skip_button.pressed.connect(skip)
	buttons.add_child(_skip_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.add_child(spacer)
	_next_button = Button.new()
	_next_button.name = "NextButton"
	_next_button.text = "Next"
	_next_button.theme_type_variation = "AccentButton"
	_next_button.focus_mode = Control.FOCUS_NONE
	_next_button.custom_minimum_size = Vector2(88, 0)
	_next_button.pressed.connect(next)
	buttons.add_child(_next_button)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(refresh)
	_apply_style()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _bubble != null and _running and step_index >= 0:
		_refill_bubble.call_deferred()
	if what == NOTIFICATION_THEME_CHANGED and _bubble != null and EraTheme.style_of(self) != _style:
		_apply_style.call_deferred()


# --- Public API ---------------------------------------------------------------------

## Starts the tutorial at its first step. [param new_targets] maps target ids
## to Controls (or Callables returning one); [param tabs] optionally names the
## tab each target lives on in the phone layout.
func begin(new_targets: Dictionary, tabs: Dictionary = {}) -> void:
	targets = new_targets.duplicate()
	if not tabs.is_empty():
		target_tabs = tabs.duplicate()
	_running = true
	step_index = -1
	_go_to(0)


## Adds or replaces one target while the tutorial runs.
func set_target(target_id: String, target: Variant) -> void:
	targets[target_id] = target


func is_running() -> bool:
	return _running


## The step on show ({} when the tutorial is not running).
func current_step() -> Dictionary:
	if not _running or step_index < 0 or step_index >= STEPS.size():
		return {}
	return STEPS[step_index]


func current_step_id() -> String:
	return String(current_step().get("id", ""))


## True while the coach is hidden, waiting for the next turn's event.
func is_waiting() -> bool:
	var step := current_step()
	return not step.is_empty() and String(step.get("target", "")) == ""


## The lit cutout in the coach's coordinates (empty while waiting).
func get_cutout() -> Rect2:
	return _hole


## The highlighted control (null while waiting).
func get_target() -> Control:
	return _target


func get_bubble() -> Control:
	return _bubble


## Goes on from a "next" step (the Next button).
func next() -> void:
	if not _running:
		return
	var step := current_step()
	if String(step.get("advance", "next")) != "next":
		return
	_go_to(step_index + 1)


## Something happened in the game ("crisis_answered", "turn_submitted"): a
## step waiting for it moves on, and so does the tutorial when the player got
## ahead of it within the same turn.
func advance_from(event: String) -> void:
	if not _running or step_index < 0:
		return
	var turn := int(STEPS[step_index].get("turn", 1))
	for i in range(step_index, STEPS.size()):
		var step: Dictionary = STEPS[i]
		if int(step.get("turn", 1)) != turn:
			break
		if String(step.get("advance", "")) == "signal" and String(step.get("signal", "")) == event:
			_go_to(i + 1)
			return


## Ends the tutorial for good (GameSettings "coach_done").
func skip() -> void:
	if not _running:
		return
	_stop()
	GameSettings.instance().set_value("coach_done", true)
	skipped.emit()


## Hides the tutorial without marking it done (a new campaign started).
func stop() -> void:
	_stop()


## Phone layout: a bubble as wide as the screen allows, larger buttons.
func set_compact(enabled: bool) -> void:
	compact = enabled
	for button in [_skip_button, _next_button]:
		(button as Control).custom_minimum_size.y = 44 if compact else 36
	refresh()


## Re-measures the target and places the cutout and the bubble.
func refresh() -> void:
	if not _running or _target == null:
		return
	if not is_instance_valid(_target) or not _target.is_visible_in_tree():
		# The target went away (a dialog closed, a tab changed): move on.
		_go_to(step_index + 1)
		return
	var rect := get_global_transform().affine_inverse() * _target.get_global_rect()
	_hole = rect.grow(PAD).intersection(Rect2(Vector2.ZERO, size)) if size.x > 0.0 and size.y > 0.0 else rect.grow(PAD)
	_place_bubble()
	queue_redraw()


# --- Steps ------------------------------------------------------------------------------

func _go_to(index: int) -> void:
	var i := index
	while i < STEPS.size():
		var step: Dictionary = STEPS[i]
		if String(step.get("target", "")) == "":
			# Wait, hidden, for the step's event.
			step_index = i
			_target = null
			_hole = Rect2()
			visible = false
			set_process(false)
			return
		var tab := _tab_for(step)
		if tab != "":
			tab_requested.emit(tab)
		var target := _resolve(step)
		if target == null:
			i += 1
			continue
		step_index = i
		_target = target
		_passthrough = String(step.get("advance", "next")) == "signal"
		_fill_bubble(step)
		_reveal(target)
		visible = true
		set_process(true)
		refresh()
		step_shown.emit(String(step["id"]))
		return
	_finish()


## Scrolls the nearest scroll container so [param target] is on screen
## (phones stack the crisis card above its answers).
static func _reveal(target: Control) -> void:
	var node := target.get_parent()
	while node != null:
		if node is ScrollContainer:
			(node as ScrollContainer).ensure_control_visible.call_deferred(target)
			return
		node = node.get_parent()


func _finish() -> void:
	_stop()
	GameSettings.instance().set_value("coach_done", true)
	finished.emit()


func _stop() -> void:
	_running = false
	_target = null
	_hole = Rect2()
	visible = false
	set_process(false)


func _tab_for(step: Dictionary) -> String:
	for target_id in _target_ids(step):
		if target_tabs.has(target_id):
			return String(target_tabs[target_id])
	return String(step.get("tab", ""))


static func _target_ids(step: Dictionary) -> Array:
	var raw: Variant = step.get("target", "")
	if raw is Array:
		return raw
	return [String(raw)] if String(raw) != "" else []


## The first of the step's targets that is on screen, or null.
func _resolve(step: Dictionary) -> Control:
	for target_id in _target_ids(step):
		var entry: Variant = targets.get(target_id)
		if entry is Callable:
			entry = (entry as Callable).call() if (entry as Callable).is_valid() else null
		var control := entry as Control
		if control != null and is_instance_valid(control) and control.is_inside_tree() and control.is_visible_in_tree():
			return control
	return null


## "Second turn · 1 of 3": the step's place among its turn's steps.
func _counter_text(step: Dictionary) -> String:
	var turn := int(step.get("turn", 1))
	var count := 0
	var position := 0
	for i in STEPS.size():
		var other: Dictionary = STEPS[i]
		if int(other.get("turn", 1)) != turn or String(other.get("target", "")) == "":
			continue
		count += 1
		if i == step_index:
			position = count
	return tr("%s · %d of %d") % [tr(String(ORDINALS.get(turn, str(turn)))), position, count]


func _fill_bubble(step: Dictionary) -> void:
	var s := EraTheme.style_of(self)
	var words: Array = ["Blue", "orange"] if s.colorblind else COLOR_WORDS.get(s.era, ["Blue", "orange"])
	_counter.text = s.label(_counter_text(step))
	_title.text = tr(String(step.get("title", "")))
	_text.text = tr(String(step.get("text", ""))).format({"good": tr(String(words[0])), "bad": tr(String(words[1]))})
	var last := step_index == _last_visible_step()
	_next_button.visible = not _passthrough
	_next_button.text = "Done" if last else "Next"
	_bubble.reset_size()


## The language changed while a step was on show.
func _refill_bubble() -> void:
	if _running and step_index >= 0 and step_index < STEPS.size():
		_fill_bubble(STEPS[step_index])


func _last_visible_step() -> int:
	for i in range(STEPS.size() - 1, -1, -1):
		if String((STEPS[i] as Dictionary).get("target", "")) != "":
			return i
	return -1


# --- Layout and drawing -------------------------------------------------------------------

## Below the cutout when it fits, else above it, else where there is more room;
## always inside the screen.
func _place_bubble() -> void:
	var width := minf(BUBBLE_WIDTH, maxf(size.x - MARGIN * 2.0, 160.0))
	if not is_equal_approx(_bubble.custom_minimum_size.x, width):
		_bubble.custom_minimum_size = Vector2(width, 0)
	# Wrapped text settles a frame after a width change; a Control grows to
	# its minimum on its own but never shrinks back, so size it every time.
	var height := _bubble.get_combined_minimum_size().y
	if not _bubble.size.is_equal_approx(Vector2(width, height)):
		_bubble.size = Vector2(width, height)
	var below := _hole.end.y + GAP
	var above := _hole.position.y - GAP - height
	var y := below
	if below + height > size.y - MARGIN:
		if above >= MARGIN:
			y = above
		else:
			var room_below := size.y - _hole.end.y
			var room_above := _hole.position.y
			y = below if room_below >= room_above else above
	y = clampf(y, MARGIN, maxf(MARGIN, size.y - height - MARGIN))
	var x := clampf(_hole.get_center().x - width * 0.5, MARGIN, maxf(MARGIN, size.x - width - MARGIN))
	var at := Vector2(roundf(x), roundf(y))
	if _bubble.position != at:
		_bubble.position = at


func _process(delta: float) -> void:
	if GameSettings.value("effects"):
		_pulse = fmod(_pulse + delta / PULSE_PERIOD, 1.0)
	refresh()


func _has_point(point: Vector2) -> bool:
	if not _running or not visible:
		return false
	if _bubble.visible and Rect2(_bubble.position, _bubble.size).has_point(point):
		return true
	if _hole.has_point(point):
		return false
	# "signal" steps let the player act anywhere; "next" steps hold the screen.
	return not _passthrough


func _draw() -> void:
	if not _running or _hole.size == Vector2.ZERO:
		return
	var s := _style if _style != null else EraTheme.style_of(self)
	var dim := Color(s.shade.r, s.shade.g, s.shade.b, DIM_ALPHA)
	var screen := Rect2(Vector2.ZERO, size)
	var hole := _hole
	# Four bands around the hole...
	draw_rect(Rect2(screen.position, Vector2(screen.size.x, hole.position.y)), dim)
	draw_rect(Rect2(Vector2(0.0, hole.end.y), Vector2(screen.size.x, screen.end.y - hole.end.y)), dim)
	draw_rect(Rect2(Vector2(0.0, hole.position.y), Vector2(hole.position.x, hole.size.y)), dim)
	draw_rect(Rect2(Vector2(hole.end.x, hole.position.y), Vector2(screen.end.x - hole.end.x, hole.size.y)), dim)
	# ...and its rounded corners.
	var radius := minf(float(s.control_radius) + PAD, minf(hole.size.x, hole.size.y) * 0.5)
	for corner in 4:
		draw_colored_polygon(_corner_fill(hole, corner, radius), dim)
	if _ring != null:
		var glow := 0.55 + 0.45 * (0.5 + 0.5 * cos(TAU * _pulse))
		_ring.border_color = Color(s.accent, glow)
		draw_style_box(_ring, hole)
	_draw_pointer(s)


## The dimmed area between a square corner of [param hole] and its arc.
static func _corner_fill(hole: Rect2, corner: int, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var at: Vector2
	var center: Vector2
	var start := 0.0
	match corner:
		0:
			at = hole.position
			center = hole.position + Vector2(radius, radius)
			start = PI
		1:
			at = Vector2(hole.end.x, hole.position.y)
			center = at + Vector2(-radius, radius)
			start = PI * 1.5
		2:
			at = hole.end
			center = hole.end - Vector2(radius, radius)
			start = 0.0
		_:
			at = Vector2(hole.position.x, hole.end.y)
			center = at + Vector2(radius, -radius)
			start = PI * 0.5
	points.append(at)
	var steps := 8
	for step in steps + 1:
		var angle := start + PI * 0.5 * float(step) / float(steps)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


## A small triangle from the bubble toward the cutout.
func _draw_pointer(s: EraStyle) -> void:
	var bubble := Rect2(_bubble.position, _bubble.size)
	if bubble.intersects(_hole):
		return
	var x := clampf(_hole.get_center().x, bubble.position.x + 18.0, bubble.end.x - 18.0)
	var points := PackedVector2Array()
	if bubble.position.y >= _hole.end.y:
		points = PackedVector2Array([Vector2(x - POINTER, bubble.position.y + 1.0), Vector2(x + POINTER, bubble.position.y + 1.0),
			Vector2(x, bubble.position.y - POINTER)])
	elif bubble.end.y <= _hole.position.y:
		points = PackedVector2Array([Vector2(x - POINTER, bubble.end.y - 1.0), Vector2(x + POINTER, bubble.end.y - 1.0),
			Vector2(x, bubble.end.y + POINTER)])
	if not points.is_empty():
		draw_colored_polygon(points, s.overlay)


func _apply_style() -> void:
	if _bubble == null:
		return
	_style = EraTheme.style_of(self)
	var s := _style
	var box := EraTheme.panel(s, s.overlay, s.accent, s.radius, 16)
	box.set_border_width_all(maxi(s.border_width, 1))
	box.content_margin_top = 14
	box.content_margin_bottom = 12
	box.shadow_color = Color(0, 0, 0, 0.5)
	box.shadow_size = 18
	_bubble.add_theme_stylebox_override("panel", box)
	_ring = StyleBoxFlat.new()
	_ring.draw_center = false
	_ring.set_border_width_all(2)
	_ring.set_corner_radius_all(s.control_radius + roundi(PAD))
	_ring.corner_detail = s.corner_detail
	_ring.anti_aliasing = true
	_counter.add_theme_font_override("font", s.font_mono)
	EraTheme.set_scaled_font_size(_counter, 11)
	_counter.add_theme_color_override("font_color", s.accent)
	_title.add_theme_font_override("font", s.font_ui_bold)
	EraTheme.set_scaled_font_size(_title, 17)
	_title.add_theme_color_override("font_color", s.text_bright)
	_text.add_theme_font_override("font", s.font_ui)
	EraTheme.set_scaled_font_size(_text, 14)
	_text.add_theme_color_override("font_color", s.text)
	if _running and step_index >= 0:
		_fill_bubble(STEPS[step_index])
	queue_redraw()


static func _label(label_name: String, wrap: bool) -> Label:
	var label := Label.new()
	label.name = label_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
