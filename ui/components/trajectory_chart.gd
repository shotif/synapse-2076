class_name TrajectoryChart
extends Control
## Historical trajectory line chart (the debrief's appendix). Plots each macro
## metric over the campaign with the hardware-era boundaries, a 0-100 grid and
## a hover crosshair that reads out every series at the pointed turn. Colors,
## fonts, text size and corner shape follow the era theme (EraTheme.style_of)
## and the chart redraws when the dashboard swaps themes.

var history: Array = []
var series_keys: Array = WorldState.METRIC_KEYS
var title := "Historical trajectory · 2026–2076"

const MARGIN_LEFT := 38.0
const MARGIN_RIGHT := 14.0
const MARGIN_TOP := 40.0
const MARGIN_BOTTOM := 24.0

var _hover_index := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(640, 260)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_THEME_CHANGED:
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			if _hover_index != -1:
				_hover_index = -1
				queue_redraw()


func set_history(entries: Array, keys: Array = WorldState.METRIC_KEYS) -> void:
	history = entries
	series_keys = keys
	queue_redraw()


func _plot_rect() -> Rect2:
	var items := _legend_items(EraTheme.style_of(self))
	var legend_bottom: float = (items[-1]["pos"] as Vector2).y if not items.is_empty() else 24.0
	var top := maxf(MARGIN_TOP, legend_bottom + 16.0)
	return Rect2(MARGIN_LEFT, top, maxf(10.0, size.x - MARGIN_LEFT - MARGIN_RIGHT),
		maxf(10.0, size.y - top - MARGIN_BOTTOM))


## Legend entries laid out left to right, wrapping onto extra rows when narrow.
func _legend_items(s: EraStyle) -> Array:
	var items := []
	var x := 12.0
	var y := 26.0
	for key in series_keys:
		var series_name := s.label(UiFormat.metric_name(key))
		var width := 24.0 + s.font_ui.get_string_size(series_name, HORIZONTAL_ALIGNMENT_LEFT, -1, s.scaled(11)).x
		if x > 12.0 and x + width > size.x - 6.0:
			x = 12.0
			y += 4.0 + float(s.scaled(11))
		items.append({"key": key, "name": series_name, "pos": Vector2(x, y)})
		x += width
	return items


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and history.size() >= 2:
		var plot := _plot_rect()
		var t := clampf((event.position.x - plot.position.x) / plot.size.x, 0.0, 1.0)
		var index := int(round(t * float(history.size() - 1)))
		if index != _hover_index:
			_hover_index = index
			queue_redraw()


func _x_for_turn(plot: Rect2, turn: float) -> float:
	return plot.position.x + plot.size.x * turn / float(SimConstants.TOTAL_TURNS)


func _draw() -> void:
	var s := EraTheme.style_of(self)
	var mono := s.font_mono
	var plot := _plot_rect()
	draw_style_box(EraTheme.panel(s, s.bg.lerp(s.surface, 0.6), s.border, s.control_radius + 2, 0.0), Rect2(Vector2.ZERO, size))
	draw_string(s.font_ui_bold, Vector2(12, 18), s.label(title), HORIZONTAL_ALIGNMENT_LEFT, -1, s.scaled(12),
		s.accent if s.era == 2 else s.text_bright)

	# Legend.
	for item in _legend_items(s):
		var color := s.metric_color(item["key"])
		var pos: Vector2 = item["pos"]
		draw_rect(Rect2(pos.x, pos.y - 1.0, 12, 3), color)
		draw_string(s.font_ui, Vector2(pos.x + 16, pos.y + 4), item["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, s.scaled(11), s.text_dim)

	# Hardware eras: a faint band for each and its numeral.
	for era in [1, 2, 3]:
		var span := EraChronicle.era_turns(era)
		var x0 := _x_for_turn(plot, float(maxi(span.x - 1, 0)) + (0.5 if era > 1 else 0.0))
		var x1 := _x_for_turn(plot, float(span.y) + (0.5 if era < 3 else 0.0))
		if era % 2 == 0:
			draw_rect(Rect2(x0, plot.position.y, x1 - x0, plot.size.y), Color(s.accent, 0.05))
		draw_string(mono, Vector2(x0 + 5, plot.end.y - 5), "ERA %s" % EraStyle.ROMAN[era], HORIZONTAL_ALIGNMENT_LEFT, -1,
			s.scaled(9), Color(s.accent, 0.7))

	# Grid.
	for level in [0.0, 25.0, 50.0, 75.0, 100.0]:
		var y: float = plot.end.y - plot.size.y * level / 100.0
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(s.border, s.border.a * (1.6 if level == 0.0 else 0.9)), 1.0)
		draw_string(mono, Vector2(6, y + 4), "%3d" % int(level), HORIZONTAL_ALIGNMENT_LEFT, -1, s.scaled(10), s.text_dim)
	var span_years := SimConstants.YEARS_PER_TURN * float(SimConstants.TOTAL_TURNS)
	for year in [2026, 2036, 2046, 2056, 2066, 2076]:
		var yx: float = plot.position.x + plot.size.x * (float(year) - SimConstants.START_YEAR) / span_years
		var label := str(year)
		var width := mono.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, s.scaled(10)).x
		draw_string(mono, Vector2(clampf(yx - width * 0.5, 2.0, size.x - width - 2.0), size.y - 7), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, s.scaled(10), s.text_dim)

	if history.size() < 2:
		var empty := s.label("No telemetry")
		draw_string(s.font_ui, plot.get_center() - Vector2(s.font_ui.get_string_size(empty, HORIZONTAL_ALIGNMENT_LEFT, -1, s.scaled(12)).x * 0.5, 0),
			empty, HORIZONTAL_ALIGNMENT_LEFT, -1, s.scaled(12), s.text_dim)
		return

	# Series.
	var last_turn := float((history[-1] as Dictionary).get("turn", history.size() - 1))
	for key in series_keys:
		var color := s.metric_color(key)
		var points := PackedVector2Array()
		for entry in history:
			var py := plot.end.y - plot.size.y * clampf(float(entry.get(key, 0.0)), 0.0, 100.0) / 100.0
			points.append(Vector2(_x_for_turn(plot, float(entry.get("turn", 0))), py))
		if s.glow > 0.0:
			draw_polyline(points, Color(color, s.glow * 0.6), 4.0, true)
		draw_polyline(points, color, 1.8, true)
		draw_circle(points[points.size() - 1], 3.0, color)

	if last_turn < float(SimConstants.TOTAL_TURNS):
		var end_x := _x_for_turn(plot, last_turn)
		draw_line(Vector2(end_x, plot.position.y), Vector2(end_x, plot.end.y), Color(s.critical, 0.7), 1.0)

	# Hover crosshair with readouts.
	if _hover_index >= 0 and _hover_index < history.size():
		var entry: Dictionary = history[_hover_index]
		var hx := _x_for_turn(plot, float(entry.get("turn", 0)))
		draw_line(Vector2(hx, plot.position.y), Vector2(hx, plot.end.y), Color(s.text_bright, 0.5), 1.0)
		var line := 4.0 + float(s.scaled(11))
		var box_width := 178.0 * s.text_scale
		var box_x := hx + 8.0 if hx < plot.get_center().x else hx - box_width - 8.0
		var box := Rect2(box_x, plot.position.y + 6, box_width, 20 + line * series_keys.size())
		draw_style_box(EraTheme.box(Color(s.overlay, 0.94), s.border_strong, 1, s.control_radius, 0.0, 0.0, s.corner_detail), box)
		draw_string(mono, box.position + Vector2(8, 15), "T%d · %d" % [int(entry.get("turn", 0)), int(float(entry.get("year", 2026.0)))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, s.scaled(11), s.text_bright)
		var row := 1
		for key in series_keys:
			draw_string(mono, box.position + Vector2(8, 15 + line * row), "%-10s %5.1f" % [UiFormat.metric_name(key), float(entry.get(key, 0.0))],
				HORIZONTAL_ALIGNMENT_LEFT, -1, s.scaled(10), s.metric_color(key))
			row += 1
