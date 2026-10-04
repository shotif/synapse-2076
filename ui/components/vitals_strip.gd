class_name VitalsStrip
extends Control
## Six glyph meters, one per macro metric (WorldState.METRIC_KEYS): a tile
## filled to the metric's level in its color, the metric glyph on top and the
## value underneath. set_preview() shows what a choice would do: a striped
## ghost segment from the current to the predicted value, pulsing ▲/▼ pips and
## a ring, in the era's good or bad color (UiFormat.is_improvement).
##
## Compact (phones): one row of six small tiles, 64 px tall; the dashboard can
## use it as the phone vitals header. Desktop: each tile has the metric name,
## value and predicted value beside it (needs about 720 px). Colors, fonts and
## tile shapes follow the era theme the control inherits (EraTheme), its text
## the player's text size, and the names their plain-language setting. Drawn in
## one pass with no child nodes; it only processes while values ease or a
## preview pulses.

## Emitted when the player taps or clicks a meter.
signal metric_pressed(metric_key: String)

const COMPACT_TILE := 38.0
const COMPACT_GAP := 6.0
const COMPACT_HEIGHT := 64.0
## Height of the pip band above a compact tile (clear of the preview ring).
const PIP_BAND := 13.0
const DESKTOP_TILE := 48.0
const DESKTOP_GAP := 12.0
const DESKTOP_HEIGHT := 54.0
const DESKTOP_CELL_MIN := 110.0
## The ghost segment is at least this many metric points tall, so small
## changes stay visible.
const MIN_GHOST := 6.0
const STRIPE_WIDTH := 3.0
const STRIPE_PERIOD := 6.0
const RING_GAP := 2.0
const FILL_ALPHA := 0.36
const EASE_RATE := 7.0
const PULSE_PERIOD := 1.0
const TAP_SLOP := 12.0

var compact := false

var _values := {}
var _shown := {}
var _preview := {}
var _has_values := false
var _pulse := 0.0
var _press_index := -1
var _press_at := Vector2.ZERO
## Polygons per metric (fill, ghost stripes, wash, target line); rebuilt when
## values, the preview, the size or the era change.
var _shapes := {}
var _shapes_dirty := true
## StyleBoxes per metric (tile, edge, rings); rebuilt when the size or era change.
var _boxes := {}
var _boxes_key := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_NONE
	for key in WorldState.METRIC_KEYS:
		_values[key] = 0.0
		_shown[key] = 0.0
	set_process(false)
	GameSettings.instance().changed.connect(_on_setting_changed)


func _get_minimum_size() -> Vector2:
	if compact:
		return Vector2(COMPACT_TILE * 6.0 + COMPACT_GAP * 5.0, COMPACT_HEIGHT)
	return Vector2(DESKTOP_CELL_MIN * 6.0 + DESKTOP_GAP * 5.0, DESKTOP_HEIGHT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_TRANSLATION_CHANGED:
		_shapes_dirty = true
		queue_redraw()


## Names follow the plain-language setting; colors and sizes follow the theme.
func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "plain_language" or key in EraTheme.SETTING_KEYS:
		_shapes_dirty = true
		queue_redraw()


## Phone layout (one row of small tiles) or desktop layout (tiles with text).
func set_compact(enabled: bool) -> void:
	if compact == enabled:
		return
	compact = enabled
	_shapes_dirty = true
	update_minimum_size()
	queue_redraw()


## Sets the six metric values (0-100); missing keys keep their value. The
## first call jumps to the values, later calls ease toward them.
func set_values(metrics: Dictionary) -> void:
	for key in WorldState.METRIC_KEYS:
		if metrics.has(key):
			var value := float(metrics[key])
			_values[key] = clampf(value if is_finite(value) else 0.0, 0.0, 100.0)
	if not _has_values and not metrics.is_empty():
		_shown = _values.duplicate()
		_has_values = true
	_shapes_dirty = true
	_update_processing()
	queue_redraw()


## Previews metric changes {metric_key: delta}; other keys and changes under
## 0.05 are ignored. Pass {} to clear.
func set_preview(deltas: Dictionary) -> void:
	_preview.clear()
	for key in WorldState.METRIC_KEYS:
		if deltas.has(key):
			var delta := float(deltas[key])
			if is_finite(delta) and absf(delta) >= 0.05:
				_preview[key] = delta
	_pulse = 0.0
	_shapes_dirty = true
	_update_processing()
	queue_redraw()


## The previewed deltas currently shown ({} when none).
func get_preview() -> Dictionary:
	return _preview.duplicate()


func get_value(key: String) -> float:
	return float(_values.get(key, 0.0))


## The value [param key] would have after the previewed change.
func get_predicted(key: String) -> float:
	return clampf(get_value(key) + float(_preview.get(key, 0.0)), 0.0, 100.0)


## The striped segment for [param key] as (low, high) metric values, or
## Vector2.ZERO when nothing is previewed for it.
func get_ghost_range(key: String) -> Vector2:
	if not _preview.has(key):
		return Vector2.ZERO
	return ghost_range(get_value(key), float(_preview[key]))


## Segment between [param value] and value + [param delta] (clamped to
## 0-100), widened to MIN_GHOST points in the direction of the change.
static func ghost_range(value: float, delta: float) -> Vector2:
	var target := clampf(value + delta, 0.0, 100.0)
	var low := minf(value, target)
	var high := maxf(value, target)
	if high - low < MIN_GHOST:
		if delta > 0.0:
			high = minf(100.0, low + MIN_GHOST)
			low = high - MIN_GHOST
		else:
			low = maxf(0.0, high - MIN_GHOST)
			high = low + MIN_GHOST
	return Vector2(low, high)


## Corner radii [top-left, top-right, bottom-right, bottom-left] of a tile
## [param side] px wide in the era's shape language.
static func tile_radii(s: EraStyle, side: float) -> Array[float]:
	var radii: Array[float] = []
	match s.era:
		2:
			radii.assign([side * 0.17, side * 0.17, side * 0.17, side * 0.17])
		3:
			radii.assign([side * 0.42, side * 0.28, side * 0.46, side * 0.32])
		_:
			radii.assign([side * 0.27, side * 0.27, side * 0.27, side * 0.27])
	return radii


## Outline of [param rect] with per-corner radii [tl, tr, br, bl];
## [param detail] segments per corner (1 = chamfer), like StyleBoxFlat.
static func rounded_polygon(rect: Rect2, radii: Array[float], detail: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var limit := minf(rect.size.x, rect.size.y) * 0.5
	var corners := [
		[Vector2(rect.position.x, rect.position.y), Vector2(1, 1), PI],
		[Vector2(rect.end.x, rect.position.y), Vector2(-1, 1), PI * 1.5],
		[Vector2(rect.end.x, rect.end.y), Vector2(-1, -1), 0.0],
		[Vector2(rect.position.x, rect.end.y), Vector2(1, -1), PI * 0.5],
	]
	var steps := maxi(detail, 1)
	for i in 4:
		var corner: Vector2 = corners[i][0]
		var inward: Vector2 = corners[i][1]
		var start: float = corners[i][2]
		var radius := clampf(radii[i], 0.0, limit)
		if radius < 0.5:
			points.append(corner)
			continue
		var center := corner + inward * radius
		for step in steps + 1:
			var angle := start + PI * 0.5 * float(step) / float(steps)
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _process(delta: float) -> void:
	var moving := false
	for key in WorldState.METRIC_KEYS:
		var target := float(_values[key])
		var shown := float(_shown[key])
		if absf(target - shown) > 0.05:
			_shown[key] = lerpf(shown, target, clampf(delta * EASE_RATE, 0.0, 1.0))
			moving = true
		else:
			_shown[key] = target
	if moving:
		_shapes_dirty = true
	if not _preview.is_empty():
		_pulse = fmod(_pulse + delta / PULSE_PERIOD, 1.0)
	queue_redraw()
	if not moving:
		_update_processing()


func _update_processing() -> void:
	var moving := false
	for key in WorldState.METRIC_KEYS:
		if absf(float(_values[key]) - float(_shown[key])) > 0.05:
			moving = true
	set_process(moving or not _preview.is_empty())


# --- Layout ---------------------------------------------------------------------------

func _cell_rect(index: int) -> Rect2:
	var gap := COMPACT_GAP if compact else DESKTOP_GAP
	var width := maxf(0.0, (size.x - gap * 5.0) / 6.0)
	return Rect2(float(index) * (width + gap), 0.0, width, size.y)


func _tile_rect(cell: Rect2) -> Rect2:
	if compact:
		var side := minf(COMPACT_TILE, cell.size.x - RING_GAP * 2.0)
		return Rect2(cell.position.x + (cell.size.x - side) * 0.5, PIP_BAND, side, side)
	var top := (size.y - DESKTOP_TILE) * 0.5
	return Rect2(cell.position.x + RING_GAP, top, DESKTOP_TILE, DESKTOP_TILE)


func _cell_at(point: Vector2) -> int:
	for i in WorldState.METRIC_KEYS.size():
		if _cell_rect(i).has_point(point):
			return i
	return -1


# --- Drawing ----------------------------------------------------------------------------

func _draw() -> void:
	var s := EraTheme.style_of(self)
	_ensure_boxes(s)
	if _shapes_dirty:
		_rebuild_shapes(s)
	var pulse_alpha := 0.45 + 0.55 * (0.5 + 0.5 * cos(TAU * _pulse))
	for i in WorldState.METRIC_KEYS.size():
		var key: String = WorldState.METRIC_KEYS[i]
		var cell := _cell_rect(i)
		var tile := _tile_rect(cell)
		_draw_tile(s, key, tile)
		if compact:
			_draw_compact_text(s, key, cell, tile, pulse_alpha)
		else:
			_draw_desktop_text(s, key, cell, tile, pulse_alpha)


func _draw_tile(s: EraStyle, key: String, tile: Rect2) -> void:
	var boxes: Dictionary = _boxes[key]
	var shapes: Dictionary = _shapes.get(key, {})
	draw_style_box(boxes["tile"], tile)
	var color := s.metric_color(key)
	for polygon in shapes.get("fill", []):
		draw_colored_polygon(polygon, Color(color, FILL_ALPHA))
	if _preview.has(key):
		var tone := _tone(s, key)
		for polygon in shapes.get("wash", []):
			draw_colored_polygon(polygon, Color(tone, 0.16))
		for polygon in shapes.get("stripes", []):
			draw_colored_polygon(polygon, Color(tone, 0.85))
		for polygon in shapes.get("target", []):
			draw_colored_polygon(polygon, tone)
	draw_style_box(boxes["edge"], tile)
	var glyph := roundf(tile.size.x * 0.46)
	var glyph_rect := Rect2(tile.get_center() - Vector2(glyph, glyph) * 0.5, Vector2(glyph, glyph))
	draw_texture_rect(Glyphs.texture(Glyphs.for_metric(key), int(glyph)), glyph_rect, false, Color(s.text_bright, 0.94))
	if _preview.has(key):
		var ring: StyleBoxFlat = boxes["ring_good"] if UiFormat.is_improvement(key, float(_preview[key])) else boxes["ring_bad"]
		draw_style_box(ring, tile.grow(RING_GAP))


func _draw_compact_text(s: EraStyle, key: String, cell: Rect2, tile: Rect2, pulse_alpha: float) -> void:
	var mono := s.font_mono
	if _preview.has(key):
		var pips := UiFormat.pips(float(_preview[key]))
		draw_string(mono, Vector2(cell.position.x, PIP_BAND - 4.0), pips, HORIZONTAL_ALIGNMENT_CENTER, cell.size.x, s.scaled(10),
			Color(_tone(s, key), pulse_alpha))
	var value := "%d" % roundi(float(_shown[key]))
	draw_string(mono, Vector2(cell.position.x, minf(tile.end.y + 12.0, size.y - 1.0)), value, HORIZONTAL_ALIGNMENT_CENTER, cell.size.x,
		s.scaled(11), s.text_dim)


func _draw_desktop_text(s: EraStyle, key: String, cell: Rect2, tile: Rect2, pulse_alpha: float) -> void:
	var x := tile.end.x + RING_GAP + 10.0
	var width := cell.end.x - x
	if width < 24.0:
		return
	var name_text := s.label(UiFormat.metric_name(key))
	draw_string(s.font_ui, Vector2(x, tile.position.y + 15.0), name_text, HORIZONTAL_ALIGNMENT_LEFT, width, s.scaled(12), s.text_dim)
	var value := "%d" % roundi(float(_shown[key]))
	var value_font := s.font_mono_bold
	var baseline := tile.end.y - 6.0
	var value_size := s.scaled(22)
	draw_string(value_font, Vector2(x, baseline), value, HORIZONTAL_ALIGNMENT_LEFT, width, value_size, s.text_bright)
	if not _preview.has(key):
		return
	var tone := _tone(s, key)
	var pips := UiFormat.pips(float(_preview[key]))
	draw_string(s.font_mono, Vector2(x, tile.position.y + 15.0), pips, HORIZONTAL_ALIGNMENT_RIGHT, width, s.scaled(11), Color(tone, pulse_alpha))
	var after := value_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, value_size).x + 6.0
	var predicted := "→ %d" % roundi(get_predicted(key))
	draw_string(s.font_mono, Vector2(x + after, baseline), predicted, HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, width - after), s.scaled(14), tone)


func _tone(s: EraStyle, key: String) -> Color:
	return s.good if UiFormat.is_improvement(key, float(_preview.get(key, 0.0))) else s.bad


func _ensure_boxes(s: EraStyle) -> void:
	var side := _tile_rect(_cell_rect(0)).size.x
	var key := "%s|%.1f" % [s.variant_key(), side]
	if key == _boxes_key and not _boxes.is_empty():
		return
	_boxes_key = key
	_boxes.clear()
	var radii := tile_radii(s, side)
	for metric_key in WorldState.METRIC_KEYS:
		var color := s.metric_color(metric_key)
		var tile := _box(radii, s.corner_detail)
		tile.bg_color = s.surface.lerp(color, 0.08) if s.era == 3 else s.surface.lerp(s.raised, 0.35)
		var edge := _box(radii, s.corner_detail)
		edge.draw_center = false
		edge.set_border_width_all(1)
		edge.border_color = s.border if s.era == 1 else Color(color, 0.5)
		_boxes[metric_key] = {"tile": tile, "edge": edge, "ring_good": _ring(radii, s, s.good), "ring_bad": _ring(radii, s, s.bad)}
	_shapes_dirty = true


func _box(radii: Array[float], detail: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.corner_radius_top_left = roundi(radii[0])
	box.corner_radius_top_right = roundi(radii[1])
	box.corner_radius_bottom_right = roundi(radii[2])
	box.corner_radius_bottom_left = roundi(radii[3])
	box.corner_detail = detail
	box.anti_aliasing = true
	return box


func _ring(radii: Array[float], s: EraStyle, color: Color) -> StyleBoxFlat:
	var grown: Array[float] = []
	for radius in radii:
		grown.append(radius + RING_GAP)
	var ring := _box(grown, s.corner_detail)
	ring.draw_center = false
	ring.set_border_width_all(2)
	ring.border_color = color
	return ring


## Fill, ghost and target polygons for every tile, clipped to the tile shape.
func _rebuild_shapes(s: EraStyle) -> void:
	_shapes_dirty = false
	_shapes.clear()
	for i in WorldState.METRIC_KEYS.size():
		var key: String = WorldState.METRIC_KEYS[i]
		var tile := _tile_rect(_cell_rect(i))
		if tile.size.x < 4.0:
			continue
		var inner_rect := tile.grow(-1.0 if s.border_width > 0 or s.era != 1 else -0.5)
		var radii: Array[float] = []
		for radius in tile_radii(s, tile.size.x):
			radii.append(maxf(0.0, radius - 1.0))
		var inner := rounded_polygon(inner_rect, radii, s.corner_detail)
		var shown := float(_shown[key])
		if not _preview.has(key):
			_shapes[key] = {"fill": _clip(inner, _band(tile, 0.0, shown))}
			continue
		# The solid fill stops at the lower of the two levels; the change
		# between them is striped over the empty tile, so a drop reads as
		# fill being taken away and a rise as fill being added.
		var span := ghost_range(shown, float(_preview[key]))
		var band := _band(tile, span.x, span.y)
		var ghost := _clip(inner, band)
		var target := clampf(shown + float(_preview[key]), 0.0, 100.0)
		var line_y := _level_y(tile, target)
		_shapes[key] = {
			"fill": _clip(inner, _band(tile, 0.0, minf(span.x, minf(shown, target)))),
			"wash": ghost,
			"stripes": _stripes(ghost, tile, band),
			"target": _clip(inner, Rect2(tile.position.x, clampf(line_y - 0.75, tile.position.y, tile.end.y - 1.5), tile.size.x, 1.5)),
		}


func _level_y(tile: Rect2, value: float) -> float:
	return tile.end.y - tile.size.y * clampf(value, 0.0, 100.0) / 100.0


func _band(tile: Rect2, low: float, high: float) -> Rect2:
	var top := _level_y(tile, high)
	var bottom := _level_y(tile, low)
	return Rect2(tile.position.x, top, tile.size.x, maxf(0.0, bottom - top))


static func _clip(shape: PackedVector2Array, rect: Rect2) -> Array:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return []
	var box := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	return Geometry2D.intersect_polygons(shape, box)


## Diagonal stripes (top-left to bottom-right) inside [param regions],
## anchored to the tile so they hold still while the band changes.
static func _stripes(regions: Array, tile: Rect2, band: Rect2) -> Array:
	var out := []
	if regions.is_empty() or band.size.y <= 0.0:
		return out
	var period := STRIPE_PERIOD * sqrt(2.0)
	var thickness := STRIPE_WIDTH * sqrt(2.0)
	var first := tile.position.x - tile.end.y - period
	var last := tile.end.x - tile.position.y
	var top := band.position.y
	var bottom := band.end.y
	var offset := first
	while offset < last:
		var stripe := PackedVector2Array([
			Vector2(offset + top, top), Vector2(offset + thickness + top, top),
			Vector2(offset + thickness + bottom, bottom), Vector2(offset + bottom, bottom)])
		for region in regions:
			out.append_array(Geometry2D.intersect_polygons(region, stripe))
		offset += period
	return out


# --- Input ------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_press_index = _cell_at(button.position)
		_press_at = button.position
	elif _press_index >= 0:
		if _cell_at(button.position) == _press_index and button.position.distance_to(_press_at) <= TAP_SLOP:
			metric_pressed.emit(String(WorldState.METRIC_KEYS[_press_index]))
		_press_index = -1


func _get_tooltip(at_position: Vector2) -> String:
	var index := _cell_at(at_position)
	# Touch screens raise tooltips while a finger rests, so phones get none.
	if index < 0 or compact:
		return ""
	var key: String = WorldState.METRIC_KEYS[index]
	var text := "%s: %d" % [PlainLanguage.display_name(key), roundi(get_value(key))]
	if _preview.has(key):
		text += "  →  %d (%s)" % [roundi(get_predicted(key)), UiFormat.signed(float(_preview[key]))]
	return text
