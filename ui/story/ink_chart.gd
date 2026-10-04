class_name InkChart
extends Control
## A small line chart drawn like ink on paper, for the front page ("the decade
## in three lines") and the history book's figures: solid, dotted or dashed
## series over turns, optional era dividers and a circled, labelled mark.
##
##   chart.set_series([{"points": [Vector2(turn, value), ...], "color": ink,
##       "width": 1.4, "dash": Vector2.ZERO}])   # dash = (on, off) in px

## [{points: Array of Vector2(turn, value), color, width, dash: Vector2}].
var series: Array = []
var x_from := 0.0
var x_to := 100.0
var y_min := 0.0
var y_max := 100.0
## [{x: turn, label: "II"}]: dashed verticals with a label at the top.
var dividers: Array = []
## [{x: turn, y: value, label: "2057"}]: circled points.
var marks: Array = []
var ink := Color("#161411")
var rule_color := Color("#B9AE9C")
var mark_color := Color("#7A2E2E")
var label_font: Font
var label_size := 9
var mark_font: Font
var mark_size := 10
## Space kept above the plot for divider labels.
var top_pad := 4.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func set_series(new_series: Array) -> void:
	series = new_series
	queue_redraw()


func set_range(from_turn: float, to_turn: float) -> void:
	x_from = from_turn
	x_to = maxf(to_turn, from_turn + 1.0)
	queue_redraw()


## Points (turn, value) of [param key] from history snapshots between two turns.
static func history_points(history: Array, key: String, from_turn: int, to_turn: int) -> Array:
	var out: Array = []
	for item in history:
		var entry: Dictionary = item
		var turn := int(entry.get("turn", 0))
		if turn < from_turn or turn > to_turn:
			continue
		out.append(Vector2(float(turn), float(entry.get(key, 0.0))))
	return out


func _to_px(point: Vector2) -> Vector2:
	var plot := _plot_rect()
	var tx := (point.x - x_from) / maxf(0.001, x_to - x_from)
	var ty := (clampf(point.y, y_min, y_max) - y_min) / maxf(0.001, y_max - y_min)
	return Vector2(plot.position.x + tx * plot.size.x, plot.end.y - ty * plot.size.y)


func _plot_rect() -> Rect2:
	return Rect2(Vector2(1.0, top_pad), Vector2(maxf(1.0, size.x - 2.0), maxf(1.0, size.y - top_pad - 1.0)))


func _draw() -> void:
	var plot := _plot_rect()
	draw_line(Vector2(0.0, plot.end.y), Vector2(size.x, plot.end.y), ink, 1.0)
	for item in dividers:
		var divider: Dictionary = item
		var x := _to_px(Vector2(float(divider.get("x", 0.0)), y_min)).x
		draw_dashed_polyline(self, PackedVector2Array([Vector2(x, plot.position.y), Vector2(x, plot.end.y)]),
			rule_color, 1.0, Vector2(2.0, 2.0))
		var text := String(divider.get("label", ""))
		if text != "" and label_font != null:
			draw_string(label_font, Vector2(x + 4.0, plot.position.y + float(label_size)), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, Color(ink, 0.55))
	for item in series:
		var line: Dictionary = item
		var points := PackedVector2Array()
		for point in line.get("points", []):
			points.append(_to_px(point))
		if points.size() < 2:
			continue
		var color: Color = line.get("color", ink)
		var width := float(line.get("width", 1.2))
		var dash: Vector2 = line.get("dash", Vector2.ZERO)
		if dash == Vector2.ZERO:
			draw_polyline(points, color, width, true)
		else:
			draw_dashed_polyline(self, points, color, width, dash)
	for item in marks:
		var mark: Dictionary = item
		var at := _to_px(Vector2(float(mark.get("x", 0.0)), float(mark.get("y", 0.0))))
		draw_arc(at, 4.0, 0.0, TAU, 24, mark_color, 1.2, true)
		var text := String(mark.get("label", ""))
		if text != "" and mark_font != null:
			var width := mark_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, mark_size).x
			var x := at.x + 7.0 if at.x + 7.0 + width < size.x else at.x - 7.0 - width
			draw_string(mark_font, Vector2(x, maxf(at.y - 5.0, float(mark_size))), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				mark_size, mark_color)


## Draws [param points] as a dashed line: [param dash] is (on, off) in pixels.
static func draw_dashed_polyline(canvas: CanvasItem, points: PackedVector2Array, color: Color, width: float,
		dash: Vector2) -> void:
	var on := true
	var remaining := maxf(0.5, dash.x)
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		var travelled := 0.0
		while travelled < length - 0.001:
			var step := minf(remaining, length - travelled)
			if on:
				canvas.draw_line(a.lerp(b, travelled / length), a.lerp(b, (travelled + step) / length), color, width, true)
			travelled += step
			remaining -= step
			if remaining <= 0.001:
				on = not on
				remaining = maxf(0.5, dash.x if on else dash.y)
