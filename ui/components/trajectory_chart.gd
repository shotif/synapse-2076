class_name TrajectoryChart
extends Control
## Historical trajectory line chart (PRD milestone 6 debrief). Plots each macro
## metric over the campaign with era bands, a 0-100 grid and a hover crosshair
## that reads out every series at the pointed turn.

var history: Array = []
var series_keys: Array = WorldState.METRIC_KEYS
var title := "HISTORICAL TRAJECTORY // 2026-2076"

const MARGIN_LEFT := 38.0
const MARGIN_RIGHT := 12.0
const MARGIN_TOP := 40.0
const MARGIN_BOTTOM := 24.0

var _hover_index := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(640, 260)


func set_history(entries: Array, keys: Array = WorldState.METRIC_KEYS) -> void:
	history = entries
	series_keys = keys
	queue_redraw()


func _plot_rect() -> Rect2:
	var items := _legend_items()
	var legend_bottom: float = (items[-1]["pos"] as Vector2).y if not items.is_empty() else 24.0
	var top := maxf(MARGIN_TOP, legend_bottom + 16.0)
	return Rect2(MARGIN_LEFT, top, maxf(10.0, size.x - MARGIN_LEFT - MARGIN_RIGHT),
		maxf(10.0, size.y - top - MARGIN_BOTTOM))


## Legend entries laid out left to right, wrapping onto extra rows when narrow.
func _legend_items() -> Array:
	var font := CyberPalette.MONO_FONT
	var items := []
	var x := 8.0
	var y := 24.0
	for key in series_keys:
		var series_name := UiFormat.metric_short(key)
		var width := 22.0 + font.get_string_size(series_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		if x > 8.0 and x + width > size.x - 4.0:
			x = 8.0
			y += 13.0
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover_index != -1:
		_hover_index = -1
		queue_redraw()


func _draw() -> void:
	var font := CyberPalette.MONO_FONT
	var plot := _plot_rect()
	draw_rect(Rect2(Vector2.ZERO, size), CyberPalette.PANEL)
	draw_string(CyberPalette.SANS_BOLD, Vector2(8, 16), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CyberPalette.CYAN)

	# Legend.
	for item in _legend_items():
		var color: Color = CyberPalette.METRIC_COLORS.get(item["key"], CyberPalette.TEXT)
		var pos: Vector2 = item["pos"]
		draw_rect(Rect2(pos.x, pos.y, 10, 3), color)
		draw_string(font, Vector2(pos.x + 14, pos.y + 6), item["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, CyberPalette.TEXT_DIM)

	# Era bands (2036 and 2050 boundaries).
	var span_years := SimConstants.YEARS_PER_TURN * float(SimConstants.TOTAL_TURNS)
	for era_year in [2036.0, 2050.0]:
		var ex: float = plot.position.x + plot.size.x * (era_year - SimConstants.START_YEAR) / span_years
		draw_line(Vector2(ex, plot.position.y), Vector2(ex, plot.end.y), Color(CyberPalette.CYAN, 0.18), 1.0)
		draw_string(font, Vector2(ex + 3, plot.position.y + 10), "ERA %d" % (2 if era_year < 2050.0 else 3),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(CyberPalette.CYAN, 0.5))

	# Grid.
	for level in [0.0, 25.0, 50.0, 75.0, 100.0]:
		var y: float = plot.end.y - plot.size.y * level / 100.0
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(CyberPalette.BORDER, 1.0), 1.0)
		draw_string(font, Vector2(4, y + 4), "%3d" % int(level), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, CyberPalette.TEXT_DIM)
	for year in [2026, 2036, 2046, 2056, 2066, 2076]:
		var yx: float = plot.position.x + plot.size.x * (float(year) - SimConstants.START_YEAR) / span_years
		draw_string(font, Vector2(yx - 14, size.y - 6), str(year), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, CyberPalette.TEXT_DIM)
	draw_rect(plot, CyberPalette.BORDER_BRIGHT, false, 1.0)

	if history.size() < 2:
		draw_string(font, plot.get_center() - Vector2(60, 0), "NO TELEMETRY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CyberPalette.TEXT_DIM)
		return

	# Series.
	var last_turn := float((history[-1] as Dictionary).get("turn", history.size() - 1))
	for key in series_keys:
		var color: Color = CyberPalette.METRIC_COLORS.get(key, CyberPalette.TEXT)
		var points := PackedVector2Array()
		for entry in history:
			var turn := float(entry.get("turn", 0))
			var px := plot.position.x + plot.size.x * turn / float(SimConstants.TOTAL_TURNS)
			var py := plot.end.y - plot.size.y * clampf(float(entry.get(key, 0.0)), 0.0, 100.0) / 100.0
			points.append(Vector2(px, py))
		draw_polyline(points, color, 1.6, true)
		draw_circle(points[points.size() - 1], 2.5, color)

	if last_turn < float(SimConstants.TOTAL_TURNS):
		var end_x := plot.position.x + plot.size.x * last_turn / float(SimConstants.TOTAL_TURNS)
		draw_line(Vector2(end_x, plot.position.y), Vector2(end_x, plot.end.y), Color(CyberPalette.CRIMSON, 0.6), 1.0)

	# Hover crosshair with readouts.
	if _hover_index >= 0 and _hover_index < history.size():
		var entry: Dictionary = history[_hover_index]
		var hx := plot.position.x + plot.size.x * float(entry.get("turn", 0)) / float(SimConstants.TOTAL_TURNS)
		draw_line(Vector2(hx, plot.position.y), Vector2(hx, plot.end.y), Color(CyberPalette.TEXT_BRIGHT, 0.5), 1.0)
		var box_x := hx + 8.0 if hx < plot.get_center().x else hx - 178.0
		var box := Rect2(box_x, plot.position.y + 6, 170, 18 + 14 * series_keys.size())
		draw_rect(box, Color(CyberPalette.BG, 0.92))
		draw_rect(box, CyberPalette.BORDER_BRIGHT, false, 1.0)
		draw_string(font, box.position + Vector2(6, 14), "T%d  %d" % [int(entry.get("turn", 0)), int(float(entry.get("year", 2026.0)))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, CyberPalette.TEXT_BRIGHT)
		var row := 1
		for key in series_keys:
			var color: Color = CyberPalette.METRIC_COLORS.get(key, CyberPalette.TEXT)
			draw_string(font, box.position + Vector2(6, 14 + 14 * row), "%-15s %5.1f" % [UiFormat.metric_short(key), float(entry.get(key, 0.0))],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)
			row += 1
