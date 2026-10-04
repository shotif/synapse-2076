class_name MeterBar
extends Control
## One macro metric in the active era's idiom (PRD section 8.2, telemetry):
##   Era I   a grouped card: glyph and name, large value, change, sparkline.
##   Era II  a ring gauge with the value inside and the name below.
##   Era III a living cell whose size follows the value.
## Every variant marks the warning and critical bands. The compact variant is
## a slim tile (glyph, value, bar) for tight spaces. Text follows the player's
## text size and the name their plain-language setting; a click or tap emits
## metric_pressed (the dashboard explains the change in a WhyPopup).

## Emitted when the player clicks or taps the meter (not when a drag scrolls).
signal metric_pressed(metric_key: String)

@export var metric_key := ""
@export var label_text := "Metric"
@export_range(0.0, 100.0) var value := 0.0
@export var compact := false

var history := PackedFloat32Array()
var band := 0
var delta := 0.0
var _display_value := 0.0
var _flash := 0.0
var _phase := 0.0
var _style: EraStyle

const HISTORY_LENGTH := 32
## Minimum sizes per era (card, ring, cell) and for the compact tile.
const SIZES := {1: Vector2(150, 92), 2: Vector2(96, 112), 3: Vector2(96, 118)}
const COMPACT_SIZE := Vector2(92, 40)
## A press that moves further than this is a drag, not a tap.
const TAP_SLOP := 12.0

var _press_at := Vector2.INF


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_display_value = value
	_phase = randf() * TAU
	_refresh_label()
	_apply_style()
	GameSettings.instance().changed.connect(_on_setting_changed)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_press_at = button.position
	elif _press_at != Vector2.INF:
		var tapped := button.position.distance_to(_press_at) <= TAP_SLOP
		_press_at = Vector2.INF
		if tapped and metric_key != "":
			metric_pressed.emit(metric_key)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "plain_language":
		_refresh_label()
		_refresh_tooltip()
		queue_redraw()


func _refresh_label() -> void:
	if metric_key != "" and WorldState.METRIC_INFO.has(metric_key):
		label_text = UiFormat.metric_name(metric_key)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_apply_style()


## Sets the new value; tracks history, band and change since the last update.
func set_value(new_value: float, record: bool = true) -> void:
	var clean := clampf(new_value if is_finite(new_value) else 0.0, 0.0, 100.0)
	delta = clean - value if not history.is_empty() else 0.0
	value = clean
	if record:
		history.append(clean)
		if history.size() > HISTORY_LENGTH:
			history = history.slice(history.size() - HISTORY_LENGTH)
	var new_band := WorldState.band_for(metric_key, clean)
	if new_band > band:
		_flash = 1.0
	band = new_band
	_refresh_tooltip()
	queue_redraw()


func set_history(values: Array) -> void:
	history = PackedFloat32Array()
	for v in values:
		history.append(float(v))
	if history.size() > HISTORY_LENGTH:
		history = history.slice(history.size() - HISTORY_LENGTH)
	queue_redraw()


func _apply_style() -> void:
	_style = EraTheme.style_of(self)
	var base: Vector2 = COMPACT_SIZE if compact else SIZES[_style.era]
	# Larger text needs a little more height; the width stays on the grid.
	custom_minimum_size = Vector2(base.x, roundf(base.y * (1.0 + (_style.text_scale - 1.0) * 0.6)))
	queue_redraw()


func _process(delta_time: float) -> void:
	var moving := absf(_display_value - value) > 0.05
	if moving:
		_display_value = lerpf(_display_value, value, clampf(delta_time * 6.0, 0.0, 1.0))
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta_time * 1.5)
	var alive := _style != null and _style.era == 3 and not compact
	if alive:
		_phase = fmod(_phase + delta_time, TAU * 100.0)
	if moving or _flash > 0.0 or alive:
		queue_redraw()


func _draw() -> void:
	if _style == null:
		_style = EraTheme.style_of(self)
	if compact:
		_draw_tile()
		return
	match _style.era:
		1:
			_draw_card()
		2:
			_draw_ring()
		_:
			_draw_cell()


func _metric_color() -> Color:
	return _style.metric_color(metric_key)


func _band_color() -> Color:
	match band:
		1:
			return _style.warn
		2:
			return _style.critical
	return _metric_color()


## Signed change in the era's good/bad colors: "▲ 8" / "▼ 1".
func _delta_text() -> String:
	if absf(delta) < 0.5:
		return "–"
	return "%s %d" % ["▲" if delta > 0.0 else "▼", int(round(absf(delta)))]


func _delta_color() -> Color:
	if absf(delta) < 0.5:
		return _style.text_dim
	return _style.good if UiFormat.is_improvement(metric_key, delta) else _style.bad


func _readout() -> String:
	return str(int(round(_display_value)))


# --- Era I: grouped card ------------------------------------------------------------

func _draw_card() -> void:
	var s := _style
	var w := size.x
	var h := size.y
	var color := _metric_color()
	draw_style_box(EraTheme.box(s.surface, Color(_band_color(), 0.6 * _flash), 1 if _flash > 0.0 else 0, 18), Rect2(Vector2.ZERO, size))
	draw_texture_rect(Glyphs.texture(Glyphs.for_metric(metric_key), 16, 2.0), Rect2(14, 12, 16, 16), false, color)
	draw_string(s.font_ui_bold, Vector2(36, 25), label_text, HORIZONTAL_ALIGNMENT_LEFT, w - 64, s.scaled(13), color)
	if band > 0:
		draw_circle(Vector2(w - 18, 20), 4.0, _band_color())
	draw_string(s.font_ui_bold, Vector2(14, h - 26), _readout(), HORIZONTAL_ALIGNMENT_LEFT, -1, s.scaled(28), s.text)
	draw_string(s.font_ui, Vector2(14, h - 10), _delta_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, s.scaled(12), _delta_color())
	_draw_sparkline(Rect2(w - 78, h - 40, 64, 26), color, 1.8)


# --- Era II: ring gauge -------------------------------------------------------------

func _draw_ring() -> void:
	var s := _style
	var color := _metric_color()
	var radius := minf(size.x, size.y - 30.0) * 0.5 - 6.0
	var center := Vector2(size.x * 0.5, radius + 6.0)
	draw_arc(center, radius, 0.0, TAU, 64, Color(color, 0.12), 5.0, true)
	var sweep := TAU * _display_value / 100.0
	if sweep > 0.01:
		var start := -PI / 2.0
		draw_arc(center, radius, start, start + sweep, 64, Color(color, 0.22 + 0.3 * _flash), 11.0, true)
		draw_arc(center, radius, start, start + sweep, 64, color, 5.0, true)
	_draw_ring_marks(center, radius)
	var value_font_size := s.scaled(18 if radius > 26.0 else 15)
	draw_string(s.font_mono, Vector2(0, center.y + 6), _readout(), HORIZONTAL_ALIGNMENT_CENTER, size.x, value_font_size, s.text_bright)
	var name_y := center.y + radius + 22.0
	var label := s.label(label_text)
	var name_size := s.scaled(11)
	var label_width := minf(s.font_ui_bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x, size.x - 18.0)
	var x0 := maxf(0.0, (size.x - label_width - 16.0) * 0.5)
	draw_texture_rect(Glyphs.texture(Glyphs.for_metric(metric_key), 12, 2.0), Rect2(x0, name_y - 11, 12, 12), false, color)
	draw_string(s.font_ui_bold, Vector2(x0 + 16.0, name_y), label, HORIZONTAL_ALIGNMENT_LEFT, label_width + 1.0, name_size, color)
	if absf(delta) >= 0.5:
		draw_string(s.font_mono, Vector2(0, name_y + 14), _delta_text(), HORIZONTAL_ALIGNMENT_CENTER, size.x, s.scaled(10), _delta_color())


## Warning and critical thresholds as short ticks across the ring.
func _draw_ring_marks(center: Vector2, radius: float) -> void:
	if not WorldState.METRIC_INFO.has(metric_key):
		return
	var info: Dictionary = WorldState.METRIC_INFO[metric_key]
	for key in ["warn_high", "warn_low", "crit_high", "crit_low"]:
		if info[key] == null:
			continue
		var angle := -PI / 2.0 + TAU * float(info[key]) / 100.0
		var direction := Vector2(cos(angle), sin(angle))
		var tick_color := _style.critical if key.begins_with("crit") else _style.warn
		draw_line(center + direction * (radius - 6.0), center + direction * (radius + 6.0), Color(tick_color, 0.85), 1.5, true)


# --- Era III: living cell -----------------------------------------------------------

func _draw_cell() -> void:
	var s := _style
	var color := _metric_color()
	var limit := minf(size.x, size.y - 4.0) * 0.5
	# Cells grow with the value: 60% of the room at 0, all of it at 100.
	var radius := limit * (0.6 + 0.4 * _display_value / 100.0)
	radius *= 1.0 + 0.025 * sin(_phase * (1.6 + 0.2 * float(metric_key.length() % 5)))
	var center := size * 0.5
	var points := PackedVector2Array()
	var steps := 40
	for i in steps:
		var a := TAU * float(i) / float(steps)
		var wobble := 1.0 + 0.07 * sin(a * 3.0 + _phase * 0.7) + 0.04 * sin(a * 2.0 - _phase * 0.45 + 1.3)
		points.append(center + Vector2(cos(a), sin(a)) * radius * wobble)
	var glow := points.duplicate()
	for i in glow.size():
		glow[i] = center + (glow[i] - center) * 1.08
	draw_colored_polygon(glow, Color(color, 0.05 + 0.12 * _flash))
	draw_colored_polygon(points, Color(color, 0.13))
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color(_band_color(), 0.6), 1.0, true)
	draw_texture_rect(Glyphs.texture(Glyphs.for_metric(metric_key), 16, 1.8), Rect2(center.x - 8, center.y - 30, 16, 16), false, color)
	draw_string(s.font_mono, Vector2(0, center.y + 7), _readout(), HORIZONTAL_ALIGNMENT_CENTER, size.x, s.scaled(19), s.text_bright)
	draw_string(s.font_ui_bold, Vector2(0, center.y + 22), label_text.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, size.x, s.scaled(9), color)


# --- Compact tile -------------------------------------------------------------------

func _draw_tile() -> void:
	var s := _style
	var w := size.x
	var color := _metric_color()
	draw_style_box(EraTheme.box(s.surface, Color(_band_color(), 0.25 + 0.5 * _flash), maxi(s.border_width, 1) if band > 0 else s.border_width,
		s.control_radius, 0, 0, s.corner_detail), Rect2(Vector2.ZERO, size))
	draw_texture_rect(Glyphs.texture(Glyphs.for_metric(metric_key), 13, 2.0), Rect2(6, 6, 13, 13), false, color)
	draw_string(s.font_ui_bold, Vector2(23, 17), s.label(label_text), HORIZONTAL_ALIGNMENT_LEFT, w - 50, s.scaled(10), s.text_dim)
	draw_string(s.font_mono_bold, Vector2(0, 17), _readout(), HORIZONTAL_ALIGNMENT_RIGHT, w - 6, s.scaled(13), _band_color() if band > 0 else s.text_bright)
	var bar := Rect2(6, size.y - 11, w - 12, 4)
	draw_rect(bar, Color(color, 0.16))
	var fill := bar.size.x * _display_value / 100.0
	if fill > 0.5:
		draw_rect(Rect2(bar.position, Vector2(fill, bar.size.y)), color)
	_draw_threshold_marks(bar)


func _draw_threshold_marks(bar: Rect2) -> void:
	if not WorldState.METRIC_INFO.has(metric_key):
		return
	var info: Dictionary = WorldState.METRIC_INFO[metric_key]
	for key in ["warn_high", "warn_low", "crit_high", "crit_low"]:
		if info[key] == null:
			continue
		var x := bar.position.x + bar.size.x * float(info[key]) / 100.0
		var tick_color := _style.critical if key.begins_with("crit") else _style.warn
		draw_line(Vector2(x, bar.position.y - 2), Vector2(x, bar.end.y + 2), Color(tick_color, 0.8), 1.0)


func _draw_sparkline(rect: Rect2, color: Color, width: float) -> void:
	if history.size() < 2:
		draw_line(Vector2(rect.position.x, rect.end.y - 2), Vector2(rect.end.x, rect.end.y - 2), Color(color, 0.25), 1.0)
		return
	var low := 100.0
	var high := 0.0
	for v in history:
		low = minf(low, v)
		high = maxf(high, v)
	# Scale to the recent range so small trends stay visible.
	var span := maxf(high - low, 6.0)
	var mid := (high + low) * 0.5
	var points := PackedVector2Array()
	var count := history.size()
	for i in count:
		var x := rect.position.x + rect.size.x * float(i) / float(maxi(count - 1, 1))
		var y := rect.position.y + rect.size.y * (0.5 - (history[i] - mid) / span)
		points.append(Vector2(x, clampf(y, rect.position.y, rect.end.y)))
	draw_polyline(points, color, width, true)


func _refresh_tooltip() -> void:
	if not WorldState.METRIC_INFO.has(metric_key):
		return
	tooltip_text = "%s: %.1f\n%s" % [PlainLanguage.display_name(metric_key), value, WorldState.regime_for(metric_key, value)]
