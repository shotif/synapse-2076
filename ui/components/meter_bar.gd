class_name MeterBar
extends Control
## Vector trend bar for one macro metric: label, value readout, delta arrow,
## threshold ticks, banded fill (cyan / amber / crimson) and a sparkline of the
## recent trajectory (PRD section 8.2, telemetry meters).

@export var metric_key := ""
@export var label_text := "METRIC"
@export_range(0.0, 100.0) var value := 0.0

var history := PackedFloat32Array()
var band := 0
var delta := 0.0
var _display_value := 0.0
var _flash := 0.0

const BAR_TOP := 20.0
const BAR_HEIGHT := 12.0
const SPARK_TOP := 36.0
const SPARK_HEIGHT := 14.0
const HISTORY_LENGTH := 32


func _ready() -> void:
	custom_minimum_size = Vector2(240, 54)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_display_value = value
	if metric_key != "" and WorldState.METRIC_INFO.has(metric_key):
		label_text = WorldState.METRIC_INFO[metric_key]["short"]


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


func _process(delta_time: float) -> void:
	var moving := absf(_display_value - value) > 0.05
	if moving:
		_display_value = lerpf(_display_value, value, clampf(delta_time * 6.0, 0.0, 1.0))
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta_time * 1.5)
	if moving or _flash > 0.0:
		queue_redraw()


func _draw() -> void:
	var font := CyberPalette.MONO_FONT
	var bold := CyberPalette.MONO_BOLD
	var w := size.x
	var color := CyberPalette.band_color(band)

	# Header row: label, delta arrow, value.
	draw_string(font, Vector2(0, 14), label_text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w * 0.6, 12, CyberPalette.TEXT_DIM)
	var readout := "[%d%%]" % int(round(_display_value))
	draw_string(bold, Vector2(0, 14), readout, HORIZONTAL_ALIGNMENT_RIGHT, w, 13, color)
	if absf(delta) >= 0.05:
		var arrow := "▲" if delta > 0.0 else "▼"
		var arrow_text := "%s%.1f" % [arrow, absf(delta)]
		draw_string(font, Vector2(0, 14), arrow_text, HORIZONTAL_ALIGNMENT_RIGHT, w - 52, 11, Color(color, 0.8))

	# Bar.
	var bar := Rect2(0, BAR_TOP, w, BAR_HEIGHT)
	draw_rect(bar, CyberPalette.PANEL_RAISED)
	var fill_w := w * _display_value / 100.0
	if fill_w > 0.5:
		var fill := Rect2(0, BAR_TOP, fill_w, BAR_HEIGHT)
		draw_rect(fill, Color(color, 0.28))
		draw_rect(Rect2(0, BAR_TOP, fill_w, 3), Color(color, 0.9))
		draw_rect(Rect2(fill_w - 2, BAR_TOP - 2, 2, BAR_HEIGHT + 4), color)
	for tick in [25.0, 50.0, 75.0]:
		var x: float = w * tick / 100.0
		draw_line(Vector2(x, BAR_TOP), Vector2(x, BAR_TOP + BAR_HEIGHT), Color(CyberPalette.BORDER_BRIGHT, 0.9), 1.0)
	_draw_threshold_marks(w)
	draw_rect(bar, Color(color, 0.25 + 0.5 * _flash), false, 1.0)

	# Sparkline of the recent trajectory.
	if history.size() >= 2:
		var points := PackedVector2Array()
		var count := history.size()
		for i in count:
			var x := w * float(i) / float(HISTORY_LENGTH - 1)
			var y := SPARK_TOP + SPARK_HEIGHT * (1.0 - history[i] / 100.0)
			points.append(Vector2(x, y))
		draw_polyline(points, Color(color, 0.55), 1.2, true)
		draw_circle(points[-1], 2.0, color)


func _draw_threshold_marks(w: float) -> void:
	if not WorldState.METRIC_INFO.has(metric_key):
		return
	var info: Dictionary = WorldState.METRIC_INFO[metric_key]
	for key in ["warn_high", "warn_low"]:
		if info[key] != null:
			var x := w * float(info[key]) / 100.0
			draw_line(Vector2(x, BAR_TOP - 3), Vector2(x, BAR_TOP + BAR_HEIGHT + 3), Color(CyberPalette.AMBER, 0.7), 1.0)
	for key in ["crit_high", "crit_low"]:
		if info[key] != null:
			var x := w * float(info[key]) / 100.0
			draw_line(Vector2(x, BAR_TOP - 3), Vector2(x, BAR_TOP + BAR_HEIGHT + 3), Color(CyberPalette.CRIMSON, 0.8), 1.0)


func _refresh_tooltip() -> void:
	if not WorldState.METRIC_INFO.has(metric_key):
		return
	var info: Dictionary = WorldState.METRIC_INFO[metric_key]
	tooltip_text = "%s: %.1f\n%s" % [info["label"], value, WorldState.regime_for(metric_key, value)]
