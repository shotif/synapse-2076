class_name Portrait
extends Control
## A recurring character's portrait (Characters.ROSTER), drawn with Godot's
## drawing primitives as a flat editorial illustration: head and shoulders,
## the character's hair and accessory, and an outfit tinted by their accent
## that changes with the stage of their life.
##
## Portraits age with the campaign year (Characters.age_in): children have
## rounder faces with smaller features, hair grays from about 45 and is white
## by 80 (hair_color_for), lines appear in bands (wrinkle_level: eye corners,
## then smile lines and the forehead, then deeper folds), and past 70 the jaw
## softens and the head settles lower between the shoulders. A score from
## DilemmaDeck.characters shows as a subtle expression (set_mood). The machine
## (ARIA) has no face: it is a glyph of rings, nodes and orbits that grows more
## intricate with each model generation (Characters.version_in).
##
## The frame follows the era (EraTheme.style_of, or set_era_override): a soft
## rounded square with a gradient in Era I, a chamfered duotone plate with
## scan lines in Era II, an organic cell with a luminous edge and rim light in
## Era III. Size it with custom_minimum_size (40 to 240 px; it draws the
## largest centered square); fine lines drop out at small sizes.
##
##   var face := Portrait.new()
##   face.custom_minimum_size = Vector2(96, 96)
##   face.set_character("maya", engine.get_year())
##   face.set_mood(engine.deck.character_score("maya"))
##
## Drawing is split in two: paint() records the portrait as draw operations
## in a Sketch (pure, so tests can inspect it) and _draw() replays them.

## Below SMALL px a portrait keeps only its shapes; below SIMPLE px eyes are
## simple dots; from FINE px it gets lines (wrinkles, lashes, strands) and
## from LARGE px extra texture.
const SMALL := 56.0
const SIMPLE := 80.0
const FINE := 88.0
const LARGE := 150.0
## Beards grow in from this age.
const BEARD_AGE := 18
## Graying starts at GRAY_START and is complete at GRAY_FULL. The target is a
## neutral white, so graying only ever lightens and desaturates.
const GRAY_START := 45.0
const GRAY_FULL := 80.0
const WHITE_HAIR := 0.9
const GOLD := Color("#d8b25c")
const GRAPHITE := Color("#2a2d33")
## What each character wears in hardware eras I, II and III (the stage of
## their life); others dress by faction. A look may set "outfit" itself.
const OUTFITS := {
	"maya": ["crew", "blazer", "shawl"],
	"jonas": ["collar", "blazer", "crew"],
	"lin": ["turtleneck", "turtleneck", "mandarin"],
	"sam": ["hoodie", "crew", "mandarin"],
	"victor": ["blazer", "blazer", "mandarin"],
	"nadia": ["blazer", "blazer", "shawl"],
}
const FACTION_OUTFITS := {"CEO": "blazer", "GOVERNANCE_COUNCIL": "blazer", "CITIZEN_COALITION": "crew", "ASI": "mandarin"}

## The character on show ("" draws an anonymous figure).
var character_id := ""
## The campaign year the portrait shows them in.
var year := SimConstants.START_YEAR
## How they feel about the players (DilemmaDeck.characters); see mood_curve().
var score := 0.0
## 1-3 to force an era's frame; 0 follows the inherited theme.
var era_override := 0
## A ring of [member ring_color] around the frame, [member ring_width] px wide
## (cuts the portrait out of an illustration it overlaps).
var ring_color := Color(0, 0, 0, 0)
var ring_width := 0.0
## Completed draw passes, and shapes the last pass had to skip because they
## could not be triangulated (tests read both; the second should stay 0).
var draws := 0
var invalid_shapes := 0

var _era := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(64, 64)


## Shows [param id] as they are in [param year_value].
func set_character(id: String, year_value: float) -> void:
	var value := year_value if is_finite(year_value) else SimConstants.START_YEAR
	if id == character_id and is_equal_approx(value, year):
		return
	character_id = id
	year = value
	queue_redraw()


## Shows how the character feels about the players: warm from 1, wary or
## hostile from -1 (see Characters.stance).
func set_mood(value: float) -> void:
	var mood_value := value if is_finite(value) else 0.0
	if is_equal_approx(mood_value, score):
		return
	score = mood_value
	queue_redraw()


## Forces the frame of hardware era [param era] (1-3); 0 follows the theme.
func set_era_override(era: int) -> void:
	var value := clampi(era, 0, 3)
	if value == era_override:
		return
	era_override = value
	queue_redraw()


## Draws a [param width] px ring of [param color] around the frame.
func set_ring(color: Color, width: float) -> void:
	ring_color = color
	ring_width = maxf(width, 0.0)
	queue_redraw()


## The age shown (years since first deployment for the machine).
func get_age() -> int:
	return Characters.age_in(character_id, year)


## The era whose frame is drawn.
func get_era() -> int:
	return era_override if era_override > 0 else EraTheme.style_of(self).era


func _notification(what: int) -> void:
	# Only an era change restyles the portrait (see CLAUDE.md gotcha 14).
	if what == NOTIFICATION_THEME_CHANGED and get_era() != _era:
		_era = get_era()
		queue_redraw()


func _draw() -> void:
	var side := minf(size.x, size.y)
	if side < 4.0:
		return
	_era = get_era()
	var origin := ((size - Vector2(side, side)) * 0.5).floor()
	var sketch := paint(character_id, year, score, EraStyle.for_era(_era), side, origin, ring_color, ring_width)
	sketch.render(self)
	invalid_shapes = sketch.invalid
	draws += 1


# --- Pure helpers ---------------------------------------------------------------------------

## The hair color of [param look] at [param age]: the look's color until 45,
## grayer every year after, white by 80. Bald looks keep their color.
static func hair_color_for(look: Dictionary, age: int) -> Color:
	var base := Color.from_string(String(look.get("hair", "#2a2420")), Color("#2a2420"))
	if String(look.get("hair_style", "")) == "bald":
		return base
	var t := clampf((float(age) - GRAY_START) / (GRAY_FULL - GRAY_START), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	var white := clampf(maxf(WHITE_HAIR, base.get_luminance() + 0.03), 0.0, 1.0)
	return base.lerp(Color(white, white, white, base.a), t)


## How lined a face of [param age] is: 0 (smooth) to 4 (deeply lined).
static func wrinkle_level(age: int) -> int:
	if age < 32:
		return 0
	if age < 45:
		return 1
	if age < 60:
		return 2
	if age < 75:
		return 3
	return 4


## Rings of the machine's glyph at model generation [param version].
static func machine_rings(version: int) -> int:
	return clampi(version, 1, 7)


## Expression for a character score: 0 in the neutral band, 0.4 to 1 for warm
## to loyal (from 1), -0.4 to -1 for wary to hostile (from -1).
static func mood_curve(value: float) -> float:
	if not is_finite(value):
		return 0.0
	if value >= 1.0:
		return clampf(0.4 + 0.3 * (value - 1.0), 0.4, 1.0)
	if value <= -1.0:
		return -clampf(0.4 + 0.3 * (-value - 1.0), 0.4, 1.0)
	return value * 0.1


## [param color] scaled to [param target] luminance, keeping its hue and saturation.
static func with_luminance(color: Color, target: float) -> Color:
	var factor := clampf(target, 0.0, 1.0) / maxf(color.get_luminance(), 0.001)
	return Color(clampf(color.r * factor, 0.0, 1.0), clampf(color.g * factor, 0.0, 1.0), clampf(color.b * factor, 0.0, 1.0), color.a)


## 1 for a young child, falling to 0 at 16.
static func childness(age: int) -> float:
	return clampf((16.0 - float(age)) / 11.0, 0.0, 1.0)


## What [param character_id] wears in [param year_value].
static func outfit_for(character_id: String, year_value: float) -> String:
	var person := Characters.get_character(character_id)
	var look: Dictionary = person.get("look", {})
	if look.has("outfit"):
		return String(look["outfit"])
	var era := SimConstants.era_for_year(year_value)
	if OUTFITS.has(character_id):
		return String((OUTFITS[character_id] as Array)[era - 1])
	return String(FACTION_OUTFITS.get(String(person.get("faction", "")), "crew"))


## Records the portrait of [param character_id] in [param year_value] as a
## [param side] px square at [param origin] in [param style]'s frame.
static func paint(character_id: String, year_value: float, mood_score: float, style: EraStyle, side: float,
		origin: Vector2 = Vector2.ZERO, ring: Color = Color(0, 0, 0, 0), ring_px: float = 0.0) -> Sketch:
	var painter := Painter.new()
	painter.sketch = Sketch.new()
	painter.sketch.origin = origin
	painter.sketch.scale = side / 100.0
	painter.s = style
	painter.id = character_id
	painter.person = Characters.get_character(character_id)
	painter.look = painter.person.get("look", {})
	painter.year = year_value
	painter.age = Characters.age_in(character_id, year_value) if not painter.person.is_empty() else 35
	painter.mood = mood_curve(mood_score)
	painter.side = side
	painter.ring_color = ring
	painter.ring_width = ring_px
	painter.paint()
	return painter.sketch


# --- Geometry (design units: the portrait is a 100 x 100 square) ------------------------------

## The frame of era [param era] as a polygon.
static func frame_shape(era: int) -> PackedVector2Array:
	var rect := Rect2(0, 0, 100, 100)
	match era:
		2:
			return chamfer(rect, 15.0)
		3:
			return rounded_rect(rect, [30.0, 19.0, 34.0, 23.0], 9)
	return superellipse(rect, 5.0, 112)


## Shapes inside this box never cross the frame of [param era].
static func safe_box(era: int) -> Rect2:
	return Rect2(11, 11, 78, 78) if era == 3 else Rect2(8, 8, 84, 84)


## A closed centripetal Catmull-Rom curve through [param points] (open when
## [param closed] is false), [param steps] samples per span.
static func spline(points: PackedVector2Array, closed: bool, steps: int = 6) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := points.size()
	if n < 3:
		return points.duplicate()
	var spans := n if closed else n - 1
	for i in spans:
		var p0 := points[(i - 1 + n) % n] if (closed or i > 0) else points[0]
		var p1 := points[i]
		var p2 := points[(i + 1) % n]
		var p3 := points[(i + 2) % n] if (closed or i + 2 < n) else points[n - 1]
		for step in steps:
			out.append(_catmull(p0, p1, p2, p3, float(step) / float(steps)))
	if not closed:
		out.append(points[n - 1])
	return out


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t1 := sqrt(maxf(p0.distance_to(p1), 0.0001))
	var t2 := t1 + sqrt(maxf(p1.distance_to(p2), 0.0001))
	var t3 := t2 + sqrt(maxf(p2.distance_to(p3), 0.0001))
	var u := lerpf(t1, t2, t)
	var a1 := p0 * (t1 - u) / t1 + p1 * u / t1
	var a2 := p1 * (t2 - u) / (t2 - t1) + p2 * (u - t1) / (t2 - t1)
	var a3 := p2 * (t3 - u) / (t3 - t2) + p3 * (u - t2) / (t3 - t2)
	var b1 := a1 * (t2 - u) / t2 + a2 * u / t2
	var b2 := a2 * (t3 - u) / (t3 - t1) + a3 * (u - t1) / (t3 - t1)
	return b1 * (t2 - u) / (t2 - t1) + b2 * (u - t1) / (t2 - t1)


## A quadratic Bezier from [param a] to [param b] bent toward [param control].
static func bezier(a: Vector2, control: Vector2, b: Vector2, count: int = 8) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in count + 1:
		var t := float(i) / float(count)
		out.append(a.lerp(control, t).lerp(control.lerp(b, t), t))
	return out


static func ellipse(center: Vector2, radii: Vector2, count: int = 24, rotation: float = 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in count:
		var angle := TAU * float(i) / float(count)
		out.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y).rotated(rotation))
	return out


## Points along a circular arc from [param from] to [param to] (radians).
static func arc(center: Vector2, radius: float, from: float, to: float, count: int = 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in count + 1:
		var angle := lerpf(from, to, float(i) / float(count))
		out.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return out


## A rounded rectangle with corner radii [top-left, top-right, bottom-right, bottom-left].
static func rounded_rect(rect: Rect2, radii: Array, steps: int = 8) -> PackedVector2Array:
	var out := PackedVector2Array()
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var limit := minf(rect.size.x, rect.size.y) * 0.5
	for i in 4:
		var radius := clampf(float(radii[i]), 0.0, limit)
		var corner: Vector2 = corners[i]
		var inward := Vector2(1.0 if i == 0 or i == 3 else -1.0, 1.0 if i < 2 else -1.0)
		var center := corner + inward * radius
		var start := PI + PI * 0.5 * float(i)
		for step in steps + 1:
			var angle := start + PI * 0.5 * float(step) / float(steps)
			var point := center + Vector2(cos(angle), sin(angle)) * radius
			# Corners that meet (radius = half a side) share a point.
			if out.is_empty() or not point.is_equal_approx(out[out.size() - 1]):
				out.append(point)
	if out.size() > 1 and out[0].is_equal_approx(out[out.size() - 1]):
		out.remove_at(out.size() - 1)
	return out


## A squircle: |x|^n + |y|^n = 1 fitted to [param rect].
static func superellipse(rect: Rect2, exponent: float, count: int = 96) -> PackedVector2Array:
	var out := PackedVector2Array()
	var center := rect.get_center()
	var half := rect.size * 0.5
	for i in count:
		var angle := TAU * float(i) / float(count)
		var c := cos(angle)
		var s := sin(angle)
		out.append(center + Vector2(signf(c) * pow(absf(c), 2.0 / exponent) * half.x,
			signf(s) * pow(absf(s), 2.0 / exponent) * half.y))
	return out


static func chamfer(rect: Rect2, cut: float) -> PackedVector2Array:
	var a := rect.position
	var b := rect.end
	return PackedVector2Array([Vector2(a.x + cut, a.y), Vector2(b.x - cut, a.y), Vector2(b.x, a.y + cut),
		Vector2(b.x, b.y - cut), Vector2(b.x - cut, b.y), Vector2(a.x + cut, b.y), Vector2(a.x, b.y - cut),
		Vector2(a.x, a.y + cut)])


## A strip [param start_width] wide at the start of [param line] and
## [param end_width] at its end, with rounded ends.
static func ribbon(line: PackedVector2Array, start_width: float, end_width: float) -> PackedVector2Array:
	var n := line.size()
	if n < 2:
		return PackedVector2Array()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var normals := PackedVector2Array()
	for i in n:
		var tangent := (line[mini(i + 1, n - 1)] - line[maxi(i - 1, 0)]).normalized()
		var normal := tangent.orthogonal()
		normals.append(normal)
		var half := lerpf(start_width, end_width, float(i) / float(n - 1)) * 0.5
		left.append(line[i] + normal * half)
		right.append(line[i] - normal * half)
	# Round caps sweep around each end, from one side to the other.
	var out := PackedVector2Array()
	out.append_array(left)
	var end_half := end_width * 0.5
	var end_angle := normals[n - 1].angle()
	for step in range(1, 6):
		out.append(line[n - 1] + Vector2.from_angle(end_angle + PI * float(step) / 6.0) * end_half)
	right.reverse()
	out.append_array(right)
	var start_half := start_width * 0.5
	var start_angle := (-normals[0]).angle()
	for step in range(1, 6):
		out.append(line[0] + Vector2.from_angle(start_angle + PI * float(step) / 6.0) * start_half)
	return out


## [param points] mirrored across x = [param axis], in reverse order.
static func mirrored(points: PackedVector2Array, axis: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(points.size() - 1, -1, -1):
		out.append(Vector2(axis * 2.0 - points[i].x, points[i].y))
	return out


## [param polygon] grown by [param delta] (shrunk when negative).
static func grow(polygon: PackedVector2Array, delta: float) -> PackedVector2Array:
	return _largest(Geometry2D.offset_polygon(polygon, delta, Geometry2D.JOIN_MITER))


## The outer polygons of [param a] ∩ [param b].
static func intersect(a: PackedVector2Array, b: PackedVector2Array) -> Array[PackedVector2Array]:
	return _outers(Geometry2D.intersect_polygons(a, b))


## The largest outer polygon of [param a] ∪ [param b].
static func merge(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	return _largest(Geometry2D.merge_polygons(a, b))


static func _outers(polygons: Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for item in polygons:
		var polygon: PackedVector2Array = item
		# Clipper returns holes with the opposite winding; the shapes here have none.
		if polygon.size() >= 3 and not Geometry2D.is_polygon_clockwise(polygon):
			out.append(polygon)
	return out


static func _largest(polygons: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := -1.0
	for polygon in _outers(polygons):
		var area := absf(_area(polygon))
		if area > best_area:
			best_area = area
			best = polygon
	return best


static func _area(polygon: PackedVector2Array) -> float:
	var total := 0.0
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		total += a.x * b.y - b.x * a.y
	return total * 0.5


static func _bounds(points: PackedVector2Array) -> Rect2:
	var box := Rect2(points[0], Vector2.ZERO)
	for point in points:
		box = box.expand(point)
	return box


# --- Recording and replaying ----------------------------------------------------------------

## Draw operations in pixels: ["fill", tag, points, color],
## ["grad", tag, points, colors], ["fan", tag, center, points, center color,
## colors] and ["line", tag, points, color, width]. Figure shapes are clipped
## to the frame and pass through the era tint.
class Sketch extends RefCounted:
	## Anti-aliasing seam drawn around opaque shapes, in px.
	const EDGE := 1.0
	const MIN_LINE := 0.9
	## Shapes smaller than this (px²) are not drawn.
	const MIN_AREA := 0.2
	## Intersecting an outline with this box lets Clipper untangle it.
	const UNTANGLE := [Vector2(-1000, -1000), Vector2(1000, -1000), Vector2(1000, 1000), Vector2(-1000, 1000)]

	var ops: Array = []
	var origin := Vector2.ZERO
	## Pixels per design unit.
	var scale := 1.0
	var clip := PackedVector2Array()
	var clip_box := Rect2()
	## Era tint for the figure: colors move [member tint_amount] toward a
	## duotone between [member tint_dark] and [member tint_light] by luminance.
	var tinting := false
	var tint_dark := Color.BLACK
	var tint_light := Color.WHITE
	var tint_amount := 0.0
	## Shapes skipped because they could not be triangulated even after
	## untangling (tests expect 0), and outlines that had to be untangled.
	var invalid := 0
	var invalid_tags: Array[String] = []
	var healed := 0
	var healed_tags: Array[String] = []

	func px(point: Vector2) -> Vector2:
		return origin + point * scale

	func px_all(points: PackedVector2Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		out.resize(points.size())
		for i in points.size():
			out[i] = origin + points[i] * scale
		return out

	func tone(color: Color) -> Color:
		if not tinting or tint_amount <= 0.0:
			return color
		var duo := tint_dark.lerp(tint_light, clampf(color.get_luminance() * 1.1, 0.0, 1.0))
		duo.a = color.a
		return color.lerp(duo, tint_amount)

	## Operations recorded with [param tag].
	func tagged(tag: String) -> int:
		var total := 0
		for op in ops:
			if String(op[1]) == tag:
				total += 1
		return total

	func fill(points: PackedVector2Array, color: Color, tag: String = "", clipped: bool = true) -> void:
		for part in _shapes(points, clipped, tag):
			ops.append(["fill", tag, px_all(part), tone(color)])

	## A linear gradient from [param top] at y = [param y0] to [param bottom] at [param y1].
	func gradient(points: PackedVector2Array, top: Color, bottom: Color, y0: float, y1: float, tag: String = "",
			clipped: bool = true) -> void:
		for part in _shapes(points, clipped, tag):
			var pixels := px_all(part)
			var colors := PackedColorArray()
			colors.resize(part.size())
			for i in part.size():
				colors[i] = tone(top.lerp(bottom, clampf((part[i].y - y0) / maxf(y1 - y0, 0.001), 0.0, 1.0)))
			ops.append(["grad", tag, pixels, colors])

	## A radial gradient over [param points] (a shape star-shaped around [param center]).
	func radial(points: PackedVector2Array, center: Vector2, radius: float, inner: Color, outer: Color, tag: String = "") -> void:
		var colors := PackedColorArray()
		for point in points:
			colors.append(tone(inner.lerp(outer, clampf(point.distance_to(center) / radius, 0.0, 1.0))))
		ops.append(["fan", tag, px(center), px_all(points), tone(inner), colors])

	func circle(center: Vector2, radius: float, color: Color, tag: String = "", clipped: bool = false) -> void:
		var count := clampi(int(radius * scale * 1.3) + 10, 12, 40)
		fill(Portrait.ellipse(center, Vector2(radius, radius), count), color, tag, clipped)

	## A polyline [param width] design units wide (at least MIN_LINE px).
	func stroke(points: PackedVector2Array, color: Color, width: float, tag: String = "", closed: bool = false,
			clipped: bool = false) -> void:
		if points.size() < 2:
			return
		var line := points.duplicate()
		if closed:
			line.append(points[0])
		var parts: Array = [line]
		if clipped and not clip.is_empty() and not clip_box.encloses(Portrait._bounds(line)):
			parts = Geometry2D.intersect_polyline_with_polygon(line, clip)
		for part in parts:
			var piece: PackedVector2Array = part
			if piece.size() >= 2:
				ops.append(["line", tag, px_all(piece), tone(color), maxf(width * scale, MIN_LINE)])

	## Replays the operations on [param item] (inside its _draw()).
	func render(item: CanvasItem) -> void:
		for op in ops:
			var kind := String(op[0])
			if kind == "fill":
				var points: PackedVector2Array = op[2]
				var color: Color = op[3]
				item.draw_colored_polygon(points, color)
				if color.a > 0.999:
					var loop := points.duplicate()
					loop.append(points[0])
					item.draw_polyline(loop, color, EDGE, true)
			elif kind == "grad":
				var points: PackedVector2Array = op[2]
				var colors: PackedColorArray = op[3]
				item.draw_polygon(points, colors)
				if colors[0].a > 0.999:
					var loop := points.duplicate()
					loop.append(points[0])
					var loop_colors := colors.duplicate()
					loop_colors.append(colors[0])
					item.draw_polyline_colors(loop, loop_colors, EDGE, true)
			elif kind == "fan":
				var center: Vector2 = op[2]
				var points: PackedVector2Array = op[3]
				var center_color: Color = op[4]
				var colors: PackedColorArray = op[5]
				for i in points.size():
					var j := (i + 1) % points.size()
					item.draw_polygon(PackedVector2Array([center, points[i], points[j]]),
						PackedColorArray([center_color, colors[i], colors[j]]))
				var loop := points.duplicate()
				loop.append(points[0])
				var loop_colors := colors.duplicate()
				loop_colors.append(colors[0])
				item.draw_polyline_colors(loop, loop_colors, EDGE, true)
			elif kind == "line":
				item.draw_polyline(op[2], op[3], op[4], true)

	## [param points] as drawable shapes: clipped to the frame when asked,
	## invisible slivers dropped, self-intersecting outlines untangled.
	func _shapes(points: PackedVector2Array, clipped: bool, tag: String) -> Array[PackedVector2Array]:
		var out: Array[PackedVector2Array] = []
		if points.size() < 3:
			return out
		var parts: Array[PackedVector2Array] = [points]
		if clipped and not clip.is_empty() and not clip_box.encloses(Portrait._bounds(points)):
			parts = Portrait.intersect(points, clip)
		for part in parts:
			if _visible(part):
				if Geometry2D.triangulate_polygon(px_all(part)).is_empty():
					healed += 1
					healed_tags.append(tag)
					for untangled in Portrait.intersect(part, PackedVector2Array(UNTANGLE)):
						if not _visible(untangled):
							continue
						if Geometry2D.triangulate_polygon(px_all(untangled)).is_empty():
							invalid += 1
							invalid_tags.append(tag)
						else:
							out.append(untangled)
				else:
					out.append(part)
		return out

	## Whether a shape covers enough of a pixel to be seen.
	func _visible(part: PackedVector2Array) -> bool:
		return part.size() >= 3 and absf(Portrait._area(part)) * scale * scale >= MIN_AREA


## Paints one portrait into a Sketch.
class Painter extends RefCounted:
	var sketch: Sketch
	var s: EraStyle
	var id := ""
	var person := {}
	var look := {}
	var year := 2026.0
	var age := 30
	var mood := 0.0
	var side := 96.0
	var ring_color := Color(0, 0, 0, 0)
	var ring_width := 0.0

	var tiny := false
	var simple := false
	var fine := false
	var large := false
	var frame := PackedVector2Array()
	var accent := Color.WHITE
	var outfit := "crew"
	var world_era := 1
	# Face geometry in design units.
	var kid := 0.0
	var old := 0.0
	var grown := 0.0
	var he := false
	var she := false
	var cx := 50.0
	var cy := 45.0
	var w := 16.4
	var top := 22.0
	var chin := 67.0
	var jaw_y := 58.0
	var jaw_w := 13.0
	var chin_w := 4.8
	var eye_y := 46.0
	var eye_dx := 6.9
	var eye_w := 2.9
	var eye_h := 1.4
	var brow_y := 41.0
	var nose_y := 56.0
	var nose_w := 2.5
	var mouth_y := 61.0
	var mouth_w := 5.0
	var lip_h := 1.4
	var ear_y := 48.0
	var ear_w := 2.3
	var ear_h := 4.3
	var neck_w := 6.6
	var shoulder_y := 80.0
	var shoulder_w := 39.0
	var slope := 3.0
	var head := PackedVector2Array()
	## Outer shapes of the figure, for the Era III rim light.
	var outline: Array[PackedVector2Array] = []
	# Colors.
	var skin := Color.WHITE
	var skin_shadow := Color.WHITE
	var skin_deep := Color.WHITE
	var skin_light := Color.WHITE
	var hair := Color.BLACK
	var hair_dark := Color.BLACK
	var hair_light := Color.BLACK
	var brow := Color.BLACK
	var lip := Color.WHITE
	var iris := Color.BLACK
	var garment := Color.GRAY
	var garment_dark := Color.GRAY
	var garment_light := Color.GRAY

	func paint() -> void:
		tiny = side < Portrait.SMALL
		simple = side < Portrait.SIMPLE
		fine = side >= Portrait.FINE
		large = side >= Portrait.LARGE
		accent = Color.from_string(String(look.get("accent", "")), s.accent)
		_frame()
		if Characters.is_machine(id):
			_machine()
		elif person.is_empty():
			_anonymous()
		else:
			_human()
		_finish()

	# --- Frame ---------------------------------------------------------------------------

	func _frame() -> void:
		frame = Portrait.frame_shape(s.era)
		var sk := sketch
		if ring_width > 0.0 and ring_color.a > 0.0:
			sk.fill(Portrait.grow(frame, ring_width / sk.scale), ring_color, "ring", false)
		match s.era:
			2:
				sk.gradient(frame, Color("#0c3245").lerp(accent, 0.1), Color("#03101a"), 0.0, 100.0, "background", false)
			3:
				sk.radial(frame, Vector2(50, 40), 72.0, s.raised.lerp(accent, 0.2).lightened(0.04), s.bg, "background")
				if fine:
					# A few motes of light, clear of the head.
					for i in 8:
						var spot := Vector2(8.0 + 84.0 * fposmod(float(i) * 0.618034 + 0.12, 1.0), 7.0 + 36.0 * fposmod(float(i) * 0.754878 + 0.4, 1.0))
						if absf(spot.x - 50.0) > 21.0 or spot.y < 12.0:
							sk.circle(spot, 0.4 + 0.22 * float(i % 3), Color(s.accent, 0.16 + 0.08 * float(i % 2)), "particle")
			_:
				# A muted backdrop in the character's accent, lighter behind dark
				# hair and darker behind light hair so the head always stands out.
				var hair_lum := 0.2
				var muted := accent.lerp(Color(0.55, 0.55, 0.57), 0.6)
				if Characters.is_machine(id):
					# The machine glows on a deep ground.
					hair_lum = 1.0
					muted = Color.from_string(String(look.get("skin", "#0d1424")), Color("#0d1424")).lerp(accent, 0.25)
				elif not person.is_empty():
					hair_lum = Portrait.hair_color_for(look, age).get_luminance()
				var light := lerpf(0.4, 0.19, smoothstep(0.22, 0.62, hair_lum)) - (0.06 if Characters.is_machine(id) else 0.0)
				sk.gradient(frame, Portrait.with_luminance(muted, light + 0.04), Portrait.with_luminance(muted, light - 0.09),
					0.0, 100.0, "background", false)
		sk.clip = frame
		sk.clip_box = Portrait.safe_box(s.era)
		match s.era:
			2:
				sk.tint_dark = Color("#04182a")
				sk.tint_light = Color("#c4f8ff")
				sk.tint_amount = 0.42
			3:
				sk.tint_dark = Color("#1d0b33")
				sk.tint_light = Color("#fff4fb")
				sk.tint_amount = 0.12
			_:
				sk.tint_amount = 0.0

	func _finish() -> void:
		var sk := sketch
		sk.tinting = false
		match s.era:
			2:
				if side >= 64.0:
					var y := 2.0
					while y < 100.0:
						var inset := maxf(maxf(15.0 - y, y - 85.0), 0.0)
						sk.stroke(PackedVector2Array([Vector2(inset, y), Vector2(100.0 - inset, y)]), Color(s.accent, 0.05),
							0.0, "scanline")
						y += 3.0
				sk.stroke(frame, Color(s.accent, 0.55 if not simple else 0.4), 0.0, "frame", true)
				# Corner brackets, lighter on small plates.
				var cut := 15.0
				var arm := 9.0 if not simple else 6.0
				var bracket := 1.6 if not simple else 1.1
				for corner in [
						[Vector2(0, cut + arm), Vector2(0, cut), Vector2(cut, 0), Vector2(cut + arm, 0)],
						[Vector2(100 - cut - arm, 0), Vector2(100 - cut, 0), Vector2(100, cut), Vector2(100, cut + arm)],
						[Vector2(100, 100 - cut - arm), Vector2(100, 100 - cut), Vector2(100 - cut, 100), Vector2(100 - cut - arm, 100)],
						[Vector2(cut + arm, 100), Vector2(cut, 100), Vector2(0, 100 - cut), Vector2(0, 100 - cut - arm)]]:
					sk.stroke(PackedVector2Array(corner), s.accent, bracket / sk.scale, "frame")
			3:
				_rim_light()
				var drift := s.metric_color("alignment_drift")
				var shifted := PackedVector2Array()
				for point in frame:
					shifted.append(point + Vector2(0.5, 0.35))
				sk.stroke(shifted, Color(drift, 0.35), 0.0, "frame", true)
				var inner := Portrait.grow(frame, -2.2 / sk.scale)
				if not inner.is_empty() and not tiny:
					sk.stroke(inner, Color(s.accent, 0.12), 3.0 / sk.scale, "frame", true)
				sk.stroke(frame, Color(s.accent, 0.9), (1.3 if not simple else 1.0) / sk.scale, "frame", true)

	## Era III: a luminous edge along the figure's silhouette.
	func _rim_light() -> void:
		if outline.is_empty():
			return
		var shape := outline[0]
		for i in range(1, outline.size()):
			var merged := Portrait.merge(shape, outline[i])
			if not merged.is_empty():
				shape = merged
		# Lit from the upper left: the rim runs over the crown and down the left side.
		var lit := PackedVector2Array([Vector2(-10, -10), Vector2(80, -10), Vector2(44, 40), Vector2(30, 104), Vector2(-10, 104)])
		var inside := Portrait.intersect(Portrait.grow(frame, -1.2), lit)
		if inside.is_empty():
			return
		var loop := shape.duplicate()
		loop.append(shape[0])
		var widths: Array[float] = [0.6]
		var alphas: Array[float] = [0.45]
		if not tiny:
			widths = [2.4, 1.1, 0.4]
			alphas = [0.06, 0.15, 0.6]
		for part in Geometry2D.intersect_polyline_with_polygon(loop, inside[0]):
			var piece: PackedVector2Array = part
			for k in widths.size():
				sketch.stroke(piece, Color(s.accent, alphas[k]), widths[k], "rim")

	# --- The machine -----------------------------------------------------------------------

	func _machine() -> void:
		var sk := sketch
		sk.tinting = true
		var version := Characters.version_in(id, year)
		var rings := Portrait.machine_rings(version)
		var center := Vector2(50, 50)
		# Wariness dims the rings and turns the core's light toward the warning color.
		var tint := accent.lerp(Color(accent.v * 0.55, accent.v * 0.55, accent.v * 0.6), clampf(-mood, 0.0, 1.0) * 0.35)
		var core_tint := accent.lerp(s.bad.lerp(s.critical, 0.4), clampf((-mood - 0.2) / 0.8, 0.0, 1.0))
		# A soft glow behind the core.
		for i in 4:
			sk.circle(center, 15.0 - 3.0 * float(i), Color(core_tint, 0.035 + 0.02 * float(i)), "glow")
		var radii: Array[float] = []
		for i in rings:
			radii.append(13.0 + 28.0 * float(i + 1) / (float(rings) + 0.4))
		# Rings: arcs with gaps, thinner and fainter outward.
		for i in rings:
			var radius := radii[i]
			var gaps := 1 + i % 3
			var turn := float(i) * 2.39996 + float(version) * 0.21 + mood * 0.25 * float(i % 2 * 2 - 1)
			var gap := 0.42 - 0.04 * float(gaps)
			var fade := float(i) / maxf(float(rings - 1), 1.0)
			for g in gaps:
				var from := turn + TAU * float(g) / float(gaps) + gap * 0.5
				var to := turn + TAU * float(g + 1) / float(gaps) - gap * 0.5
				sk.stroke(Portrait.arc(center, radius, from, to, maxi(12, int(radius * 1.2) / gaps)),
					Color(tint, lerpf(0.9, 0.42, fade)), lerpf(1.5, 0.55, fade), "ring")
		# Nodes on the rings, joined into a lattice from version 3.
		var nodes := PackedVector2Array()
		var node_count := mini(2 + version * 2, 18)
		for k in node_count:
			var ring_index := k % rings
			var angle := float(k) * 2.39996 + 0.7 + float(ring_index) * 0.5
			nodes.append(center + Vector2.from_angle(angle) * radii[ring_index])
		if version >= 3 and not tiny:
			for k in node_count - 1:
				if (k + version) % 3 != 0:
					sk.stroke(PackedVector2Array([nodes[k], nodes[k + 1]]), Color(tint, 0.22), 0.35, "link")
		if version >= 5 and not tiny:
			for k in range(0, node_count, 4):
				sk.stroke(PackedVector2Array([center, nodes[k]]), Color(tint, 0.16), 0.3, "link")
		# Orbits: bright arcs with a head, between the rings.
		if version >= 2:
			for k in mini(version - 1, 4):
				var radius := (radii[mini(k, rings - 1)] + 3.5) if rings > 1 else radii[0] + 4.0
				var start := float(k) * 1.9 + 0.4 + float(version) * 0.3
				var trail := Portrait.arc(center, radius, start, start + 0.9, 10)
				sk.stroke(trail, Color(s.text_bright.lerp(tint, 0.4), 0.85), 0.6, "orbit")
				sk.circle(trail[trail.size() - 1], 1.1, s.text_bright.lerp(tint, 0.3), "orbit")
		# A dial of ticks from version 5.
		if version >= 5 and fine:
			var outer := radii[rings - 1] + 3.0
			for t in 48:
				var direction := Vector2.from_angle(TAU * float(t) / 48.0)
				var length := 2.2 if t % 4 == 0 else 1.0
				sk.stroke(PackedVector2Array([center + direction * outer, center + direction * (outer + length)]),
					Color(tint, 0.35), 0.3, "tick")
		# A star lattice inside the core ring from version 6.
		if version >= 6 and not tiny:
			var star := PackedVector2Array()
			for p in 7:
				star.append(center + Vector2.from_angle(-PI * 0.5 + TAU * float(p * 3) / 7.0) * (radii[0] - 3.5))
			sk.stroke(star, Color(tint, 0.45), 0.4, "lattice", true)
		for k in node_count:
			var big := k % 3 == 0
			if not tiny:
				sk.circle(nodes[k], 2.4 if big else 1.8, Color(tint, 0.16), "node")
			sk.circle(nodes[k], 1.25 if big else 0.85, s.text_bright.lerp(tint, 0.35) if big else tint, "node")
		# The core: a round aperture when warm, an eye-like slit when hostile.
		var open := clampf(1.0 + mood * 0.5, 0.25, 1.4)
		var core := Vector2(4.6, 4.6 * open) if mood < 0.0 else Vector2(4.6 + mood * 0.9, 4.6 + mood * 0.9)
		sk.fill(Portrait.ellipse(center, core * 1.9, 32), Color(core_tint, 0.18), "core")
		sk.fill(Portrait.ellipse(center, core, 32), core_tint, "core")
		sk.fill(Portrait.ellipse(center, core * Vector2(0.42, 0.42 * maxf(open, 0.6)), 24), s.text_bright, "core")
		outline = []

	# --- An unknown person -------------------------------------------------------------------

	func _anonymous() -> void:
		var sk := sketch
		sk.tinting = true
		var tone := s.text_dim.lerp(s.surface, 0.35)
		var body := Portrait.spline(PackedVector2Array([Vector2(12, 104), Vector2(16, 84), Vector2(34, 74), Vector2(50, 72),
			Vector2(66, 74), Vector2(84, 84), Vector2(88, 104)]), false, 6)
		sk.fill(body, tone, "body")
		sk.fill(Portrait.ellipse(Vector2(50, 46), Vector2(15.5, 19.0), 40), tone, "head")
		outline = [Portrait.ellipse(Vector2(50, 46), Vector2(15.5, 19.0), 40), body]

	# --- People ------------------------------------------------------------------------------

	func _human() -> void:
		_setup()
		_colors()
		sketch.tinting = true
		_hair_back()
		_torso()
		_outfit_back()
		_neck()
		_outfit_front()
		_ears()
		_face()
		_wrinkles()
		_eyes()
		_brows()
		_nose()
		_beard()
		_mouth()
		_mustache()
		_hair_front()
		_accessory()

	func _setup() -> void:
		var pronoun := String(person.get("pronoun", "they"))
		he = pronoun == "he"
		she = pronoun == "she"
		kid = Portrait.childness(age)
		old = clampf((float(age) - 68.0) / 24.0, 0.0, 1.0)
		grown = clampf((float(age) - 30.0) / 50.0, 0.0, 1.0)
		world_era = SimConstants.era_for_year(year)
		outfit = Portrait.outfit_for(id, year)
		var h := hash(id)
		var j0 := _jitter(h, 0)
		var j1 := _jitter(h, 1)
		var j2 := _jitter(h, 2)
		var male := 1.0 if he else 0.0
		cx = 50.0
		cy = 45.0 + 1.0 * kid + 2.4 * old
		w = 16.2 + 0.5 * j0 + 1.0 * kid + 0.5 * male
		top = cy - 23.0 - 1.2 * kid
		eye_y = cy + 0.8 - 0.4 * kid
		nose_y = eye_y + lerpf(10.0, 6.4, kid) + 0.8 * grown
		mouth_y = nose_y + lerpf(5.2, 4.0, kid) + 0.3 * old
		chin = mouth_y + lerpf(6.0, 5.0, kid) + 0.7 * male + 0.5 * old
		jaw_y = chin - lerpf(9.0, 6.0, kid) + 0.5 * old
		jaw_w = w * (0.78 + 0.07 * male + 0.14 * kid + 0.06 * old) + 0.35 * j1
		chin_w = 4.4 + 1.3 * male + 3.2 * kid + 1.0 * old
		eye_dx = 6.9 + 0.3 * j2 - 0.3 * kid
		eye_w = 2.85 + 0.5 * kid - 0.2 * old
		eye_h = 1.4 + 0.55 * kid - 0.12 * old
		brow_y = eye_y - lerpf(4.7, 5.0, kid) + 0.3 * old
		nose_w = 2.4 + 0.5 * grown - 0.8 * kid + 0.3 * male + 0.15 * j1
		mouth_w = 5.0 - 1.4 * kid + 0.25 * j0 - 0.3 * old
		lip_h = (1.45 if she else 1.15) * (1.0 - 0.4 * clampf((float(age) - 55.0) / 35.0, 0.0, 1.0)) * (1.0 - 0.2 * kid)
		ear_y = eye_y + 2.8
		ear_w = 2.3 + 0.35 * grown
		ear_h = 4.2 + 0.8 * grown - 0.6 * kid
		neck_w = 6.3 + 1.2 * male - 1.6 * kid + 0.6 * old
		shoulder_y = 80.5 + 1.5 * kid + 1.0 * old
		shoulder_w = 39.0 - 10.0 * kid - 2.5 * old + 1.5 * male
		slope = 3.0 + 3.5 * old
		# A child's head is large for their body: scale it about its center.
		var k := 1.0 + 0.1 * kid
		for key in ["top", "eye_y", "nose_y", "mouth_y", "chin", "jaw_y", "brow_y", "ear_y"]:
			set(key, cy + (float(get(key)) - cy) * k)
		for key in ["w", "jaw_w", "chin_w", "eye_dx", "eye_w", "eye_h", "nose_w", "mouth_w", "lip_h", "ear_w", "ear_h"]:
			set(key, float(get(key)) * k)
		head = _head_shape()

	static func _jitter(h: int, k: int) -> float:
		return float((h >> (k * 5)) & 31) / 15.5 - 1.0

	func _head_shape() -> PackedVector2Array:
		var right := PackedVector2Array([
			Vector2(cx + w * 0.7, top + (cy - top) * 0.13),
			Vector2(cx + w * 0.97, top + (cy - top) * 0.52),
			Vector2(cx + w, cy + 1.0),
			Vector2(cx + lerpf(w, jaw_w, 0.6), lerpf(cy + 1.0, jaw_y, 0.62)),
			Vector2(cx + jaw_w, jaw_y),
			Vector2(cx + chin_w, chin - 1.2),
		])
		var keys := PackedVector2Array([Vector2(cx, top)])
		keys.append_array(right)
		keys.append(Vector2(cx, chin))
		keys.append_array(Portrait.mirrored(right, cx))
		return Portrait.spline(keys, true, 7)

	func _colors() -> void:
		skin = Color.from_string(String(look.get("skin", "#c8a080")), Color("#c8a080"))
		skin_shadow = skin.darkened(0.13).lerp(Color(0.42, 0.14, 0.12), 0.07)
		skin_deep = skin.darkened(0.34).lerp(Color(0.32, 0.1, 0.1), 0.1)
		skin_light = skin.lightened(0.07)
		hair = Portrait.hair_color_for(look, age)
		hair_dark = hair.darkened(0.3)
		hair_light = hair.lightened(0.16)
		brow = Portrait.hair_color_for(look, age - 6).darkened(0.18 if hair.get_luminance() > 0.35 else 0.0)
		lip = skin.lerp(Color(0.68, 0.3, 0.3), 0.32).darkened(0.05)
		if not she:
			lip = skin.lerp(lip, 0.55)
		iris = Color.from_string(String(look.get("eyes", "#3a2a1c")), Color("#3a2a1c"))
		garment = accent.lerp(Color(0.15, 0.15, 0.18), 0.22)
		garment_dark = garment.darkened(0.22)
		garment_light = garment.lightened(0.1)

	# --- Body ----------------------------------------------------------------------------

	func _torso() -> void:
		var base := neck_w + 2.0
		var right := PackedVector2Array([
			Vector2(cx + base, shoulder_y - 4.5),
			Vector2(cx + base + (shoulder_w - base) * 0.5, shoulder_y - 3.0 + slope * 0.4),
			Vector2(cx + shoulder_w - 4.0, shoulder_y + slope * 0.7),
			Vector2(cx + shoulder_w, shoulder_y + 6.0 + slope),
			Vector2(cx + shoulder_w + 1.6, shoulder_y + 17.0),
			Vector2(cx + shoulder_w + 2.6, 108.0),
		])
		var curve := Portrait.spline(right, false, 6)
		var body := Portrait.mirrored(curve, cx)
		body.append_array(curve)
		sketch.gradient(body, garment_light, garment_dark, shoulder_y - 5.0, 102.0, "torso")
		outline.append(body)
		if fine and outfit != "shawl":
			# Where the arms meet the chest.
			for sgn: float in [-1.0, 1.0]:
				var x := cx + sgn * (shoulder_w - 6.5)
				sketch.stroke(Portrait.bezier(Vector2(x, shoulder_y + 7.0 + slope), Vector2(x - sgn * 1.2, shoulder_y + 14.0),
					Vector2(x - sgn * 0.6, 101.0), 8), Color(garment_dark, 0.55), 0.45, "fold", false, true)

	func _neck() -> void:
		var neck_top := jaw_y - 4.0
		var neck_bottom := shoulder_y + 3.0
		var neck := Portrait.spline(PackedVector2Array([
			Vector2(cx - neck_w, neck_top), Vector2(cx + neck_w, neck_top),
			Vector2(cx + neck_w + 0.4, neck_bottom - 6.0), Vector2(cx + neck_w + 4.0, neck_bottom),
			Vector2(cx - neck_w - 4.0, neck_bottom), Vector2(cx - neck_w - 0.4, neck_bottom - 6.0)]), true, 4)
		sketch.gradient(neck, skin_shadow, skin, neck_top + 6.0, neck_bottom, "neck")
		outline.append(neck)
		# The shadow under the jaw.
		var dropped := PackedVector2Array()
		for point in head:
			dropped.append(point + Vector2(0.0, 2.6 + 0.6 * old))
		for part in Portrait.intersect(dropped, neck):
			sketch.fill(part, skin_shadow.lerp(skin_deep, 0.35), "neck_shadow")
		if fine and Portrait.wrinkle_level(age) >= 3 and outfit != "turtleneck":
			for k in 2:
				var y := chin + 4.5 + 3.2 * float(k)
				sketch.stroke(Portrait.bezier(Vector2(cx - neck_w * 0.55, y), Vector2(cx, y + 1.2), Vector2(cx + neck_w * 0.55, y), 6),
					Color(skin_deep, 0.45), 0.4, "wrinkle")

	## The garment over the neck below a neckline running through [param through]
	## (left to right), shaded like the torso.
	func _cover_below(through: PackedVector2Array) -> void:
		var cover := through.duplicate()
		cover.append(Vector2(through[through.size() - 1].x + 6.0, 104.0))
		cover.append(Vector2(through[0].x - 6.0, 104.0))
		sketch.gradient(cover, garment_light, garment_dark, shoulder_y - 5.0, 102.0, "torso")

	func _outfit_back() -> void:
		if outfit == "hoodie":
			var hood := Portrait.bezier(Vector2(cx - neck_w - 9.5, shoulder_y - 1.0), Vector2(cx, shoulder_y + 7.0),
				Vector2(cx + neck_w + 9.5, shoulder_y - 1.0), 14)
			sketch.fill(Portrait.ribbon(hood, 6.0, 6.0), garment_dark, "outfit")

	func _outfit_front() -> void:
		var base := neck_w + 2.0
		var y0 := shoulder_y - 4.6
		match outfit:
			"crew":
				var neckline := Portrait.bezier(Vector2(cx - base, y0), Vector2(cx, y0 + 6.5), Vector2(cx + base, y0), 12)
				_cover_below(neckline)
				sketch.stroke(neckline, garment_dark, 1.1, "outfit")
			"hoodie":
				var neckline := Portrait.bezier(Vector2(cx - base, y0), Vector2(cx, y0 + 7.5), Vector2(cx + base, y0), 12)
				_cover_below(neckline)
				sketch.stroke(neckline, garment_dark, 1.4, "outfit")
				if not tiny:
					for sgn: float in [-1.0, 1.0]:
						var x := cx + sgn * 2.6
						sketch.stroke(PackedVector2Array([Vector2(x, y0 + 5.0), Vector2(x + sgn * 0.4, y0 + 13.0)]),
							garment_light.lightened(0.35), 0.55, "outfit")
						sketch.circle(Vector2(x + sgn * 0.4, y0 + 13.4), 0.7, garment_light.lightened(0.45), "outfit")
			"turtleneck":
				var collar_top := jaw_y + 3.6
				var collar := Portrait.spline(PackedVector2Array([
					Vector2(cx - neck_w - 1.6, collar_top + 1.0), Vector2(cx, collar_top - 0.4), Vector2(cx + neck_w + 1.6, collar_top + 1.0),
					Vector2(cx + neck_w + 3.6, shoulder_y - 2.5), Vector2(cx, shoulder_y), Vector2(cx - neck_w - 3.6, shoulder_y - 2.5)]), true, 5)
				sketch.gradient(collar, garment_light, garment, collar_top, shoulder_y, "outfit")
				if not tiny:
					for k in 2:
						var y := collar_top + 3.4 + 3.0 * float(k)
						sketch.stroke(Portrait.bezier(Vector2(cx - neck_w - 1.0, y), Vector2(cx, y + 1.3), Vector2(cx + neck_w + 1.0, y), 8),
							Color(garment_dark, 0.7), 0.5, "fold")
			"blazer":
				_blazer(base, y0)
			"collar":
				var opening := PackedVector2Array([Vector2(cx - base + 0.5, y0), Vector2(cx, y0 + 8.0), Vector2(cx + base - 0.5, y0)])
				_cover_below(opening)
				if not tiny:
					sketch.stroke(PackedVector2Array([Vector2(cx, y0 + 8.0), Vector2(cx, 101.0)]), garment_dark, 0.5, "outfit", false, true)
					if fine:
						for k in 2:
							sketch.circle(Vector2(cx + 1.0, y0 + 12.0 + 6.0 * float(k)), 0.55, garment_light.lightened(0.3), "outfit")
				for sgn: float in [-1.0, 1.0]:
					var wing := PackedVector2Array([Vector2(cx + sgn * (neck_w - 0.5), y0 - 2.4), Vector2(cx + sgn * 0.6, y0 + 7.4),
						Vector2(cx + sgn * (base + 3.8), y0 + 4.6), Vector2(cx + sgn * (base + 1.2), y0 - 0.6)])
					sketch.fill(wing, garment_light.lightened(0.06), "outfit")
					sketch.stroke(PackedVector2Array([wing[1], wing[2]]), Color(garment_dark, 0.6), 0.35, "outfit")
			"shawl":
				# A woven stole around the neck, its ends hanging down the front.
				var neckline := Portrait.bezier(Vector2(cx - base, y0), Vector2(cx, y0 + 6.0), Vector2(cx + base, y0), 12)
				_cover_below(neckline)
				var wrap := accent.lerp(Color("#efe3cc"), 0.55)
				var band := accent.darkened(0.15)
				for sgn: float in [-1.0, 1.0]:
					var stole := Portrait.spline(PackedVector2Array([
						Vector2(cx + sgn * (neck_w - 0.8), y0 - 3.2), Vector2(cx + sgn * (neck_w + 6.5), y0 - 2.4 + slope * 0.3),
						Vector2(cx + sgn * (neck_w + 8.6), y0 + 5.0), Vector2(cx + sgn * (neck_w + 6.8), 104.0),
						Vector2(cx + sgn * (neck_w - 2.0), 104.0), Vector2(cx + sgn * (neck_w - 1.6), y0 + 5.0)]), true, 5)
					sketch.gradient(stole, wrap.lightened(0.06), wrap.darkened(0.1), y0, 102.0, "outfit")
					if not tiny:
						for k in 2:
							var y := 90.0 + 4.0 * float(k)
							var stripe := Portrait.ribbon(PackedVector2Array([Vector2(cx + sgn * (neck_w - 3.0), y),
								Vector2(cx + sgn * (neck_w + 9.0), y - 0.6)]), 1.2 - 0.5 * float(k), 1.2 - 0.5 * float(k))
							for part in Portrait.intersect(stripe, stole):
								sketch.fill(part, band, "outfit")
					if fine:
						sketch.stroke(Portrait.bezier(Vector2(cx + sgn * (neck_w + 4.0), y0 + 1.0), Vector2(cx + sgn * (neck_w + 3.4), 88.0),
							Vector2(cx + sgn * (neck_w + 2.6), 103.0), 8), Color(wrap.darkened(0.25), 0.6), 0.45, "outfit", false, true)
			"mandarin":
				var band := Portrait.bezier(Vector2(cx - neck_w - 1.4, y0 - 2.6), Vector2(cx, y0 + 2.6), Vector2(cx + neck_w + 1.4, y0 - 2.6), 12)
				_cover_below(band)
				sketch.stroke(band, garment_dark, 2.2, "outfit")
				sketch.stroke(PackedVector2Array([Vector2(cx, y0 + 1.6), Vector2(cx, 101.0)]),
					Color(s.accent if s.era == 3 else accent.lightened(0.3), 0.8), 0.45, "seam", false, true)

	func _blazer(base: float, y0: float) -> void:
		var inner := Color(0.93, 0.92, 0.89) if not she else accent.lightened(0.62)
		var front := PackedVector2Array([Vector2(cx - base - 1.0, y0 - 0.5), Vector2(cx + base + 1.0, y0 - 0.5),
			Vector2(cx + 2.4, 104.0), Vector2(cx - 2.4, 104.0)])
		sketch.gradient(front, inner, inner.darkened(0.12), y0, 102.0, "outfit")
		if he:
			# An open collar.
			var skin_v := PackedVector2Array([Vector2(cx - neck_w + 0.6, y0 - 1.0), Vector2(cx + neck_w - 0.6, y0 - 1.0),
				Vector2(cx, y0 + 6.5)])
			sketch.fill(skin_v, skin, "outfit")
			for sgn: float in [-1.0, 1.0]:
				sketch.fill(PackedVector2Array([Vector2(cx + sgn * (neck_w - 0.2), y0 - 3.0), Vector2(cx + sgn * 0.4, y0 + 6.8),
					Vector2(cx + sgn * (base + 2.8), y0 + 3.4)]), inner.lightened(0.04), "outfit")
		else:
			sketch.fill(Portrait.bezier(Vector2(cx - neck_w - 0.6, y0 - 0.6), Vector2(cx, y0 + 6.0),
				Vector2(cx + neck_w + 0.6, y0 - 0.6), 10), skin, "outfit")
		for sgn: float in [-1.0, 1.0]:
			var lapel := PackedVector2Array([Vector2(cx + sgn * (base + 1.0), y0 - 1.0), Vector2(cx + sgn * (base + 4.8), y0 + 1.0),
				Vector2(cx + sgn * (base + 2.6), y0 + 9.0), Vector2(cx + sgn * (base + 6.0), y0 + 10.0),
				Vector2(cx + sgn * 6.5, 104.0), Vector2(cx + sgn * 2.2, 104.0)])
			sketch.gradient(lapel, garment.lightened(0.04), garment_dark.lightened(0.04), y0, 102.0, "outfit")
			if not tiny:
				sketch.stroke(PackedVector2Array([lapel[1], lapel[2], lapel[3]]), Color(garment_dark, 0.8), 0.45, "outfit")

	# --- Head ----------------------------------------------------------------------------

	func _ears() -> void:
		for sgn: float in [-1.0, 1.0]:
			var center := Vector2(cx + sgn * (w + ear_w * 0.35), ear_y)
			var ear := Portrait.ellipse(center, Vector2(ear_w, ear_h), 20, sgn * 0.14)
			sketch.fill(ear, skin.lerp(skin_shadow, 0.35), "ear")
			outline.append(ear)
			if not tiny:
				sketch.fill(Portrait.ellipse(center + Vector2(sgn * 0.2, 0.2), Vector2(ear_w * 0.42, ear_h * 0.58), 14, sgn * 0.14),
					skin_shadow.lerp(skin_deep, 0.3), "ear")

	func _face() -> void:
		var sk := sketch
		sk.gradient(head, skin_light, skin.darkened(0.03), top, chin, "head")
		outline.append(head)
		# Light from the left: the right side of the face falls into shadow.
		var shade := Portrait.spline(PackedVector2Array([Vector2(cx + w * 0.42, top - 6.0), Vector2(cx + w * 0.66, cy - 7.0),
			Vector2(cx + w * 0.6, cy + 6.0), Vector2(cx + w * 0.3, chin + 2.0)]), false, 6)
		shade.append(Vector2(cx + w + 8.0, chin + 4.0))
		shade.append(Vector2(cx + w + 8.0, top - 6.0))
		for part in Portrait.intersect(head, shade):
			sk.fill(part, skin.lerp(skin_shadow, 0.5), "shade")
		# Cheeks: rosy on children and when warm.
		var blush := 0.08 * kid + 0.06 * maxf(mood, 0.0)
		if blush > 0.0 and not tiny:
			for sgn: float in [-1.0, 1.0]:
				sk.fill(Portrait.ellipse(Vector2(cx + sgn * w * 0.56, mouth_y - 4.2), Vector2(3.2, 1.9), 18),
					Color(0.92, 0.38, 0.36, blush * (0.6 + skin.get_luminance())), "blush")

	func _wrinkles() -> void:
		var level := Portrait.wrinkle_level(age)
		if tiny or level == 0:
			return
		var sk := sketch
		var line := Color(skin_deep, 0.14 + 0.1 * float(level))
		var faint := Color(skin_deep, 0.16 + 0.04 * float(level))
		var width := 0.42 + 0.04 * float(level)
		for sgn: float in [-1.0, 1.0]:
			var ex := cx + sgn * eye_dx
			var outer := ex + sgn * eye_w
			if fine:
				# Crow's feet: one line from level 1, two from 2, three from 4.
				var feet := 1 + (1 if level >= 2 else 0) + (1 if level >= 4 else 0)
				for k in feet:
					var dy := -0.9 + 1.1 * float(k)
					sk.stroke(Portrait.bezier(Vector2(outer + sgn * 1.0, eye_y + dy * 0.4), Vector2(outer + sgn * 2.0, eye_y + dy * 0.8 - 0.2),
						Vector2(outer + sgn * 2.9, eye_y + dy * 1.4), 4), faint, width * 0.85, "wrinkle")
				# Under the eyes.
				var bag := 1.4 if level >= 3 else 1.0
				sk.stroke(Portrait.bezier(Vector2(ex - sgn * eye_w * 0.6, eye_y + eye_h + bag), Vector2(ex, eye_y + eye_h + bag + 0.9),
					Vector2(ex + sgn * eye_w * 0.85, eye_y + eye_h + bag - 0.2), 6), faint, width * 0.8, "wrinkle")
			if level >= 2:
				# Smile lines from the nose to past the mouth corners.
				var start := Vector2(cx + sgn * (nose_w + 1.0), nose_y - 1.6)
				var finish := Vector2(cx + sgn * (mouth_w + 1.5 + 0.3 * maxf(mood, 0.0)), mouth_y + 1.8 + 0.4 * float(level - 2))
				sk.stroke(Portrait.bezier(start, Vector2(cx + sgn * (mouth_w + 2.2), mouth_y - 2.6), finish, 8), line,
					width * (1.0 + 0.15 * float(level - 2)), "wrinkle")
			if level >= 3:
				# Marionette lines.
				sk.stroke(Portrait.bezier(Vector2(cx + sgn * (mouth_w + 0.4), mouth_y + 1.4),
					Vector2(cx + sgn * (mouth_w + 0.9), mouth_y + 3.4), Vector2(cx + sgn * (mouth_w + 0.6), mouth_y + 5.2), 5),
					faint, width * 0.9, "wrinkle")
			if level >= 4 and fine:
				# Hollow cheeks and a softer jaw.
				sk.fill(Portrait.ellipse(Vector2(cx + sgn * (w * 0.7), nose_y + 0.5), Vector2(2.6, 4.2), 16, sgn * 0.3),
					Color(skin_shadow, 0.35), "wrinkle")
		if level >= 2 and (fine or level >= 3):
			# Forehead lines.
			var count := 1 if level == 2 else (2 if level == 3 else 3)
			for k in count:
				var y := brow_y - 4.2 - 2.4 * float(k)
				var half := 6.5 - 0.8 * float(k)
				sk.stroke(Portrait.bezier(Vector2(cx - half, y + 0.4), Vector2(cx, y - 0.9), Vector2(cx + half, y + 0.4), 8),
					faint if k > 0 else line, width * 0.9, "wrinkle")
		if level >= 3 and fine:
			# Frown lines between the brows.
			for sgn: float in [-1.0, 1.0]:
				sk.stroke(PackedVector2Array([Vector2(cx + sgn * 1.0, brow_y + 0.4), Vector2(cx + sgn * 0.8, brow_y - 1.8)]),
					faint, width * 0.8, "wrinkle")
		if level >= 4 and large:
			for k in 3:
				sk.circle(Vector2(cx - w * 0.55 + float(k) * 1.7, top + 9.0 + float(k % 2) * 1.4), 0.45, Color(skin_deep, 0.22), "wrinkle")

	func _eyes() -> void:
		var sk := sketch
		var warm := maxf(mood, 0.0)
		var cold := maxf(-mood, 0.0)
		var lash := skin.darkened(0.72).lerp(hair_dark, 0.25)
		for sgn: float in [-1.0, 1.0]:
			var ex := cx + sgn * eye_dx
			var inner := Vector2(ex - sgn * eye_w, eye_y + 0.25)
			var outer := Vector2(ex + sgn * eye_w, eye_y - 0.15)
			var up := eye_h * (1.25 - 0.35 * cold)
			var down := eye_h * (1.0 - 0.45 * warm)
			if simple:
				# Small portraits: a dark dot reads better than a drawn eye.
				var dot := maxf(eye_h * (0.72 + 0.2 * kid) * (1.0 - 0.25 * cold), (0.55 if tiny else 0.8) / sk.scale)
				sk.fill(Portrait.ellipse(Vector2(ex, eye_y + 0.1), Vector2(dot * 1.2, dot), 14), lash, "eye")
				continue
			var upper := Portrait.bezier(inner, Vector2(ex - sgn * eye_w * 0.15, eye_y - up * 1.6), outer, 10)
			var lower := Portrait.bezier(outer, Vector2(ex + sgn * eye_w * 0.1, eye_y + down * 1.5), inner, 10)
			var almond := upper.duplicate()
			almond.remove_at(almond.size() - 1)
			lower.remove_at(lower.size() - 1)
			almond.append_array(lower)
			sk.fill(almond, Color(0.96, 0.95, 0.93).lerp(skin, 0.12), "eye")
			var iris_r := eye_h * (1.08 + 0.22 * kid)
			var look_at := Vector2(ex + sgn * 0.12, eye_y + 0.1)
			for part in Portrait.intersect(Portrait.ellipse(look_at, Vector2(iris_r, iris_r), 20), almond):
				sk.fill(part, iris, "eye")
			for part in Portrait.intersect(Portrait.ellipse(look_at, Vector2(iris_r * 0.46, iris_r * 0.46), 14), almond):
				sk.fill(part, iris.darkened(0.75), "eye")
			if fine:
				sk.circle(look_at + Vector2(-0.45, -0.5), 0.36, Color(1, 1, 1, 0.9), "eye")
			# Hooded lids from about sixty.
			var hood := clampf((float(age) - 58.0) / 25.0, 0.0, 1.0)
			if hood >= 0.12:
				var lid := Portrait.bezier(inner + Vector2(0, -0.2), Vector2(ex, eye_y - up * (1.6 - 0.7 * hood)), outer + Vector2(sgn * 0.4, 0.2), 10)
				var cap := upper.duplicate()
				cap.reverse()
				lid.append_array(cap)
				for part in Portrait.intersect(lid, Portrait.grow(almond, 0.3)):
					sk.fill(part, skin.lerp(skin_shadow, 0.25), "eye")
			sk.stroke(upper, lash, 0.55 if not she else 0.7, "eye")
			if she and fine:
				sk.stroke(PackedVector2Array([outer, outer + Vector2(sgn * 0.9, -0.55)]), lash, 0.45, "eye")
			if fine and kid < 0.5:
				# The crease above the lid.
				sk.stroke(Portrait.bezier(inner + Vector2(sgn * 0.6, -1.4), Vector2(ex, eye_y - up * 1.6 - 1.4 - 0.3 * float(Portrait.wrinkle_level(age))),
					outer + Vector2(-sgn * 0.3, -1.3), 8), Color(skin_deep, 0.35), 0.4, "eye")

	func _brows() -> void:
		# Too small to keep brows apart from the eyes.
		if tiny:
			return
		var lift := 0.5 * maxf(mood, 0.0) + (0.7 if simple else 0.0)
		var knit := maxf(-mood, 0.0)
		var thick := (1.4 if he else (1.0 if she else 1.15)) * (1.0 - 0.3 * kid) * (1.0 - 0.18 * old) * (0.6 if simple else 1.0)
		var color := brow.lerp(skin, 0.35) if simple else brow
		for sgn: float in [-1.0, 1.0]:
			var inner := Vector2(cx + sgn * (3.0 - 0.4 * knit), brow_y + 0.9 + 1.5 * knit - 0.3 * lift)
			var peak := Vector2(cx + sgn * (eye_dx + 0.7), brow_y - 0.5 - lift - 0.2 * knit)
			var outer := Vector2(cx + sgn * (eye_dx + eye_w + 2.3), brow_y + 0.8 - 0.2 * lift - 0.3 * knit)
			var lower := Portrait.bezier(inner, peak, outer, 10)
			var upper := PackedVector2Array()
			for i in range(lower.size() - 1, -1, -1):
				var t := float(i) / float(lower.size() - 1)
				var width := thick * lerpf(1.0, 0.35, t * t)
				upper.append(lower[i] + Vector2(0.0, -width) + Vector2(-sgn * 0.25 * (1.0 - t), 0.0))
			var shape := lower.duplicate()
			shape.append_array(upper)
			sketch.fill(shape, color, "brow")

	func _nose() -> void:
		var sk := sketch
		var bottom := nose_y
		if tiny:
			sk.stroke(Portrait.bezier(Vector2(cx - nose_w * 0.6, bottom - 0.6), Vector2(cx, bottom + 0.5), Vector2(cx + nose_w * 0.6, bottom - 0.6), 6),
				Color(skin_deep, 0.7), 0.6, "nose")
			return
		var bridge := Portrait.spline(PackedVector2Array([Vector2(cx + 0.9, eye_y + 1.0), Vector2(cx + 1.7, bottom - 4.2),
			Vector2(cx + nose_w * 0.95, bottom - 1.1), Vector2(cx + nose_w * 0.4, bottom - 0.1), Vector2(cx + 0.5, bottom - 1.4),
			Vector2(cx + 0.35, eye_y + 2.4)]), true, 4)
		sk.fill(bridge, skin.lerp(skin_shadow, 0.6), "nose")
		sk.stroke(Portrait.spline(PackedVector2Array([Vector2(cx - nose_w, bottom - 1.0), Vector2(cx - nose_w * 0.55, bottom + 0.15),
			Vector2(cx, bottom - 0.15), Vector2(cx + nose_w * 0.55, bottom + 0.15), Vector2(cx + nose_w, bottom - 1.0)]), false, 4),
			Color(skin_deep, 0.75), 0.5, "nose")

	func _mouth() -> void:
		var sk := sketch
		var warm := maxf(mood, 0.0)
		var cold := maxf(-mood, 0.0)
		var half := mouth_w * (1.0 + 0.07 * warm - 0.08 * cold)
		var corner_y := mouth_y - 1.3 * warm + 0.8 * cold
		var dip := 0.15 + 0.9 * warm - 0.5 * cold
		var line := Portrait.bezier(Vector2(cx - half, corner_y), Vector2(cx, mouth_y + dip * 1.4), Vector2(cx + half, corner_y), 14)
		var dark := lip.darkened(0.45)
		if tiny:
			sk.stroke(line, dark, 0.7, "mouth")
			return
		# The lips are the mouth line pushed up and down, thinning to the
		# corners; the upper one dips in the middle (the cupid's bow).
		var bow := lip_h * (0.7 if not she else 0.85)
		var fullness := lip_h * 2.1 * (1.0 - 0.25 * cold)
		var upper := PackedVector2Array()
		var lower := PackedVector2Array()
		var last := line.size() - 1
		for i in range(last, -1, -1):
			var t := float(i) / float(last)
			var taper := pow(sin(t * PI), 0.6)
			var notch := 1.0 - 0.35 * exp(-pow((t - 0.5) / 0.09, 2.0))
			upper.append(line[i] + Vector2(0.0, -bow * notch * taper))
			lower.append(line[i] + Vector2(0.0, fullness * pow(sin(t * PI), 0.8)))
		var upper_lip := line.duplicate()
		upper_lip.append_array(upper.slice(1, upper.size() - 1))
		sk.fill(upper_lip, lip.darkened(0.1), "mouth")
		var lower_lip := line.duplicate()
		lower_lip.append_array(lower.slice(1, lower.size() - 1))
		sk.fill(lower_lip, lip, "mouth")
		if fine:
			sk.fill(Portrait.ellipse(Vector2(cx - half * 0.15, mouth_y + dip * 0.9 + lip_h * 0.75), Vector2(half * 0.32, lip_h * 0.25), 12),
				Color(1, 1, 1, 0.12), "mouth")
		sk.stroke(line, dark, 0.5, "mouth")

	func _beard() -> void:
		if String(look.get("accessory", "")) != "beard" or age < Portrait.BEARD_AGE:
			return
		var color := Portrait.hair_color_for(look, age + 4)
		var region := PackedVector2Array([
			Vector2(cx - w - 6.0, ear_y - 1.0), Vector2(cx - w + 0.8, ear_y - 1.0), Vector2(cx - w + 1.6, nose_y - 1.6),
			Vector2(cx - mouth_w - 2.2, nose_y + 0.4), Vector2(cx - 2.2, nose_y + 1.4), Vector2(cx, nose_y + 1.1),
			Vector2(cx + 2.2, nose_y + 1.4), Vector2(cx + mouth_w + 2.2, nose_y + 0.4), Vector2(cx + w - 1.6, nose_y - 1.6),
			Vector2(cx + w - 0.8, ear_y - 1.0), Vector2(cx + w + 6.0, ear_y - 1.0), Vector2(cx + w + 6.0, chin + 9.0),
			Vector2(cx - w - 6.0, chin + 9.0)])
		var beard := Portrait.grow(head, 1.1 + 0.4 * old)
		var parts := Portrait.intersect(beard, region)
		for part in parts:
			sketch.gradient(part, color.lerp(skin, 0.18), color.darkened(0.08), nose_y, chin + 2.0, "beard")
			outline.append(part)
		if fine:
			# A little texture, kept inside the beard.
			for k in 9:
				var x := cx - w * 0.75 + w * 1.5 * float(k) / 8.0
				var y := lerpf(chin - 2.6, mouth_y + 1.5, absf(x - cx) / w) + 0.6 * float(k % 2)
				for part in parts:
					for piece in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + 0.3, y + 1.4)]), part):
						sketch.stroke(piece, Color(color.darkened(0.25), 0.5), 0.4, "beard")

	func _mustache() -> void:
		if String(look.get("accessory", "")) != "beard" or age < Portrait.BEARD_AGE:
			return
		var color := Portrait.hair_color_for(look, age + 4)
		var stache := Portrait.spline(PackedVector2Array([Vector2(cx - mouth_w - 1.1, mouth_y + 0.7), Vector2(cx - nose_w - 0.6, nose_y + 1.0),
			Vector2(cx, nose_y + 1.5), Vector2(cx + nose_w + 0.6, nose_y + 1.0), Vector2(cx + mouth_w + 1.1, mouth_y + 0.7),
			Vector2(cx + mouth_w * 0.5, mouth_y - 0.9), Vector2(cx, mouth_y - 0.5), Vector2(cx - mouth_w * 0.5, mouth_y - 0.9)]), true, 4)
		sketch.fill(stache, color.darkened(0.04), "beard")

	# --- Hair ------------------------------------------------------------------------------

	func _style() -> String:
		return String(look.get("hair_style", "short"))

	## Hair behind the head and shoulders.
	func _hair_back() -> void:
		var sk := sketch
		match _style():
			"bob":
				var shape := _bob_shape()
				sk.gradient(shape, hair.darkened(0.08), hair.darkened(0.2), top, chin, "hair")
				outline.append(shape)
			"long":
				var shape := _long_shape()
				sk.gradient(shape, hair.darkened(0.08), hair.darkened(0.2), top, 100.0, "hair")
				outline.append(shape)
			"curly":
				var cloud := _curly_cloud()
				sk.gradient(cloud, hair, hair_dark, top - 6.0, jaw_y, "hair")
				outline.append(cloud)
			"braids":
				var above := PackedVector2Array([Vector2(-20, -20), Vector2(120, -20), Vector2(120, ear_y + 1.0), Vector2(-20, ear_y + 1.0)])
				for crown in Portrait.intersect(Portrait.grow(head, 2.0), above):
					sk.fill(crown, hair_dark, "hair")
				for sgn: float in [-1.0, 1.0]:
					for k in 7:
						_braid(_braid_line(sgn, k, false), hair_dark.lerp(hair, 0.3 + 0.25 * float(k % 2)), false)

	## Hair in front of the face: the cap, fringe and locks.
	func _hair_front() -> void:
		var sk := sketch
		var style := _style()
		if style == "bald":
			if fine:
				sk.fill(Portrait.ellipse(Vector2(cx - w * 0.3, top + 4.0), Vector2(4.5, 1.6), 16, -0.3), Color(1, 1, 1, 0.1), "hair")
			return
		var cap := PackedVector2Array()
		match style:
			"short", "slick":
				cap = _hairline_cap(1.3 if style == "short" else 0.9, style == "slick")
			"braids":
				cap = _hairline_cap(1.8, false)
			"bob":
				cap = _bob_shape()
			"long":
				cap = _long_shape()
			"curly":
				cap = _curly_cloud()
		var parts := Portrait.intersect(cap, _front_region(style))
		for part in parts:
			sk.gradient(part, hair.lightened(0.07) if style != "curly" else hair, hair.darkened(0.04), top - 3.0, chin, "hair")
			outline.append(part)
		match style:
			"long":
				_long_lock()
			"braids":
				_braid_rows(parts)
				_front_braids()
			"curly":
				_curls(parts)
			"slick":
				_comb_lines()
			"bob":
				_fringe_strands(parts)
		if not tiny:
			# A soft sheen across the crown.
			var sheen := Portrait.bezier(Vector2(cx - w * 0.75, top + 6.0), Vector2(cx - w * 0.1, top - 0.8), Vector2(cx + w * 0.55, top + 3.0), 10)
			var band := Portrait.ribbon(sheen, 1.6, 0.6)
			for part in parts:
				for piece in Portrait.intersect(band, part):
					sk.fill(piece, Color(hair_light.lightened(0.25), 0.2), "hair")

	## How far a man's hairline has receded (0-1).
	func _recede() -> float:
		if not he:
			return 0.0
		return clampf((float(age) - 48.0) / 38.0, 0.0, 1.0)

	func _hairline_cap(volume: float, slick: bool) -> PackedVector2Array:
		var cap := Portrait.grow(head, volume)
		if _style() == "braids":
			cap = Portrait.merge(cap, Portrait.ellipse(Vector2(cx, top + 3.0), Vector2(w * 0.85, 6.5), 28))
		if slick:
			cap = Portrait.merge(cap, Portrait.ellipse(Vector2(cx - 1.0, top + 1.0), Vector2(w * 0.8, 3.2), 24))
		return cap

	## Where the hair covers the head: above the hairline, beside the face.
	func _front_region(style: String) -> PackedVector2Array:
		var r := _recede()
		match style:
			"bob":
				# A fringe with a few uneven ends, and curtains beside the face.
				var fringe_y := brow_y - 2.4
				return PackedVector2Array([Vector2(-20, -20), Vector2(120, -20), Vector2(120, 120), Vector2(cx + w - 1.6, 120),
					Vector2(cx + w - 1.6, cy), Vector2(cx + w - 2.4, fringe_y + 0.6), Vector2(cx + 5.6, fringe_y),
					Vector2(cx + 3.6, fringe_y - 0.8), Vector2(cx + 2.2, fringe_y + 0.1), Vector2(cx - 0.4, fringe_y - 0.9),
					Vector2(cx - 2.4, fringe_y + 0.1), Vector2(cx - 4.0, fringe_y - 0.6), Vector2(cx - 5.6, fringe_y),
					Vector2(cx - w + 2.4, fringe_y + 0.6), Vector2(cx - w + 1.6, cy), Vector2(cx - w + 1.6, 120), Vector2(-20, 120)])
			"long":
				# A side part: the hair sweeps across the left of the forehead,
				# frames the left of the face and is tucked behind the right ear.
				var part_x := cx + 3.2
				return PackedVector2Array([Vector2(-20, -20), Vector2(120, -20), Vector2(120, ear_y - ear_h - 1.0),
					Vector2(cx + w + 0.6, ear_y - ear_h - 1.0), Vector2(cx + w - 1.4, brow_y - 3.6), Vector2(cx + w * 0.55, top + 8.5),
					Vector2(part_x + 1.2, top + 6.6), Vector2(part_x, top + 7.2), Vector2(part_x - 2.0, top + 8.6),
					Vector2(cx - w * 0.45, brow_y - 4.4), Vector2(cx - w + 2.6, eye_y - 2.4), Vector2(cx - w + 1.5, cy + 2.0),
					Vector2(cx - w + 1.2, jaw_y), Vector2(-20, jaw_y)])
			"curly":
				var fringe := PackedVector2Array([Vector2(120, ear_y - 1.0), Vector2(cx + w - 0.8, ear_y - 1.0)])
				var count := 9
				for i in count + 1:
					var t := float(i) / float(count)
					var x := lerpf(cx + w - 1.6, cx - w + 1.6, t)
					var curve := sin(t * PI)
					var y := lerpf(eye_y - 3.0, brow_y - 3.2, curve) + (1.3 if i % 2 == 0 else -0.6) * (0.4 + 0.6 * curve)
					fringe.append(Vector2(x, y))
				fringe.append(Vector2(cx - w + 0.8, ear_y - 1.0))
				fringe.append(Vector2(-20, ear_y - 1.0))
				fringe.append(Vector2(-20, -20))
				fringe.append(Vector2(120, -20))
				return fringe
		# Short, slick and braided hair: a hairline that recedes with age.
		var center_y := lerpf(top + 7.2, top + 4.0, r)
		if r > 0.6:
			center_y = lerpf(center_y, top - 7.0, clampf((r - 0.6) / 0.4, 0.0, 1.0))
		var temple := Vector2(cx + lerpf(w - 3.4, w * 0.55, r * r), lerpf(top + 9.0, top + 4.0, r))
		if _style() == "braids":
			center_y = top + 8.2
			temple = Vector2(cx + w - 3.6, top + 9.6)
		var side_y := ear_y - 1.6 - (0.0 if _style() != "slick" else 1.0)
		var right := PackedVector2Array([Vector2(120, side_y), Vector2(cx + w - 0.7, side_y), Vector2(cx + w - 1.3, eye_y - 3.6 - r * 2.5),
			temple, Vector2(cx + w * 0.3, center_y + 0.4 + r * 0.6)])
		var region := right.duplicate()
		region.append(Vector2(cx, center_y))
		region.append_array(Portrait.mirrored(right, cx))
		region.append(Vector2(-20, -20))
		region.append(Vector2(120, -20))
		return region

	func _bob_shape() -> PackedVector2Array:
		var crown := Portrait.grow(head, 2.4)
		var sides := Portrait.spline(PackedVector2Array([Vector2(cx - w - 2.4, cy - 10.0), Vector2(cx + w + 2.4, cy - 10.0),
			Vector2(cx + w + 3.3, cy + 4.0), Vector2(cx + w + 3.0, chin - 2.4), Vector2(cx + w + 0.6, chin - 0.4),
			Vector2(cx - w - 0.6, chin - 0.4), Vector2(cx - w - 3.0, chin - 2.4), Vector2(cx - w - 3.3, cy + 4.0)]), true, 5)
		var shape := Portrait.merge(crown, sides)
		var cut := PackedVector2Array([Vector2(-20, -20), Vector2(120, -20), Vector2(120, chin - 0.4), Vector2(-20, chin - 0.4)])
		var parts := Portrait.intersect(shape, cut)
		return parts[0] if not parts.is_empty() else shape

	## A few strands from the fringe up into the bob.
	func _fringe_strands(parts: Array[PackedVector2Array]) -> void:
		if not fine:
			return
		for k in 3:
			var x := cx - 3.0 + 3.4 * float(k)
			var strand := Portrait.bezier(Vector2(x, brow_y - 3.4), Vector2(x - 2.2, brow_y - 6.5), Vector2(x - 4.6, brow_y - 8.4), 8)
			for part in parts:
				for piece in Geometry2D.intersect_polyline_with_polygon(strand, part):
					sketch.stroke(piece, Color(hair_dark, 0.28), 0.35, "hair")

	func _long_length() -> float:
		return lerpf(97.0, 79.0, clampf((float(age) - 70.0) / 14.0, 0.0, 1.0))

	func _long_shape() -> PackedVector2Array:
		var crown := Portrait.grow(head, 2.2)
		var length := _long_length()
		var fall := PackedVector2Array([Vector2(cx - w - 2.4, cy - 9.0), Vector2(cx + w + 2.4, cy - 9.0), Vector2(cx + w + 4.4, chin + 2.0),
			Vector2(cx + w + 6.0, length - 5.0), Vector2(cx + w + 3.4, length), Vector2(cx - w - 3.4, length),
			Vector2(cx - w - 6.0, length - 5.0), Vector2(cx - w - 4.4, chin + 2.0)])
		return Portrait.merge(crown, Portrait.spline(fall, true, 4))

	## A lock that falls from the sweep over the left shoulder.
	func _long_lock() -> void:
		var length := maxf(_long_length(), chin + 12.0)
		# Keep the outline running down one side and up the other as the hair shortens.
		var inner := maxf(length - 9.0, chin + 5.0)
		var outer := maxf(length - 12.0, chin + 4.0)
		var lock := Portrait.spline(PackedVector2Array([Vector2(cx - w + 2.2, brow_y - 1.0), Vector2(cx - w + 1.4, jaw_y - 2.0),
			Vector2(cx - w + 0.4, chin + 3.0), Vector2(cx - w - 1.2, inner), Vector2(cx - w - 3.0, length),
			Vector2(cx - w - 5.4, length - 4.0), Vector2(cx - w - 7.2, outer), Vector2(cx - w - 6.6, chin + 1.0),
			Vector2(cx - w - 5.0, jaw_y - 3.0), Vector2(cx - w - 3.6, cy - 7.0)]), true, 5)
		sketch.gradient(lock, hair.lightened(0.07), hair.darkened(0.04), top - 3.0, chin, "hair")
		outline.append(lock)
		if fine:
			for k in 3:
				var x := cx - w - 1.6 - 1.7 * float(k)
				sketch.stroke(Portrait.bezier(Vector2(x + 1.6, jaw_y - 4.0), Vector2(x - 1.2, chin + 9.0), Vector2(x - 0.4 + float(k) * 0.3, length - 3.0), 10),
					Color(hair_dark if k == 1 else hair_light, 0.4), 0.4, "hair")

	## Box braids: a centerline from the side of the head down past the shoulders.
	func _braid_line(sgn: float, k: int, front: bool) -> PackedVector2Array:
		var fk := float(k)
		var start := Vector2(cx + sgn * (w - 3.8 + fk * 1.05), ear_y - 6.5 + fk * 2.1)
		var length := lerpf(97.0, 88.0, clampf((float(age) - 60.0) / 20.0, 0.0, 1.0)) - fk * 1.3
		if front:
			start = Vector2(cx + sgn * (w + 0.2 + fk * 2.3), ear_y - 1.0 + fk * 1.8)
			length -= 2.0 + fk * 1.5
		var bend := sgn * (2.6 + fk * 1.3)
		return Portrait.bezier(start, Vector2(start.x + bend * 1.35, lerpf(start.y, length, 0.55)), Vector2(start.x + bend, length), 10)

	## One braid: a strip with plaits marked across it at larger sizes.
	func _braid(line: PackedVector2Array, color: Color, front: bool) -> void:
		var braid := Portrait.ribbon(line, 2.1, 1.8)
		sketch.fill(braid, color, "hair")
		outline.append(braid)
		if not fine:
			return
		sketch.stroke(braid, Color(hair_dark.darkened(0.35), 0.5), 0.3, "hair", true, true)
		if front:
			for i in range(1, line.size() - 1):
				var dir := (line[i + 1] - line[i - 1]).normalized()
				var normal := dir.orthogonal()
				var tick := PackedVector2Array([line[i] - normal * 0.9 - dir * 0.5, line[i] + normal * 0.9 + dir * 0.5])
				sketch.stroke(tick, Color(hair_dark, 0.55), 0.3, "hair", false, true)

	## Braids over the left shoulder, each finished with a bead in the accent color.
	func _front_braids() -> void:
		for k in 3:
			var line := _braid_line(-1.0, k, true)
			_braid(line, hair.lerp(hair_dark, 0.12 * float(k)), true)
			sketch.circle(line[line.size() - 1] + Vector2(0, -0.4), 1.2 if not tiny else 1.5, accent.darkened(0.05), "bead", true)

	## The rows the braids are parted into, running back over the crown.
	func _braid_rows(parts: Array[PackedVector2Array]) -> void:
		if not fine:
			return
		for i in 7:
			var offset := float(i) - 3.0
			var start := Vector2(cx + offset * w * 0.27, top + 8.9 + absf(offset) * 0.45)
			var finish := Vector2(cx + offset * w * 0.1, top - 1.5)
			var row := Portrait.bezier(start, Vector2(start.x * 0.75 + finish.x * 0.25 + offset * 0.5, top + 3.0), finish, 8)
			for part in parts:
				for piece in Geometry2D.intersect_polyline_with_polygon(row, part):
					sketch.stroke(piece, Color(hair_light.lightened(0.1), 0.32), 0.35, "hair")

	func _curly_cloud() -> PackedVector2Array:
		var center := Vector2(cx, cy - 5.0)
		var radii := Vector2(w + 5.6 + 0.6 * kid, (cy - top) + 6.5)
		var points := PackedVector2Array()
		var count := 64
		for i in count + 1:
			var angle := lerpf(PI * 0.88, TAU + PI * 0.12, float(i) / float(count))
			var bump := 1.0 + 0.075 * pow(absf(sin(angle * 8.0 + 0.6)), 0.7)
			points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y) * bump)
		points.append(Vector2(cx + w - 2.0, jaw_y - 2.0))
		points.append(Vector2(cx - w + 2.0, jaw_y - 2.0))
		return points

	## Rows of small curls across the cloud.
	func _curls(parts: Array[PackedVector2Array]) -> void:
		if not fine:
			return
		var center := Vector2(cx, cy - 5.0)
		var radii := Vector2(w + 5.6, cy - top + 6.5)
		for ring_index in 3:
			var ring := 0.6 + 0.17 * float(ring_index)
			var count := 6 + ring_index * 2
			for i in count:
				var t := (float(i) + (0.5 if ring_index % 2 == 1 else 0.0)) / float(count)
				var angle := lerpf(PI * 1.0, PI * 2.0, t) + 0.12
				var spot := center + Vector2(cos(angle) * radii.x * ring, sin(angle) * radii.y * ring)
				var curl := Portrait.arc(spot, 1.2, angle + 0.5, angle + 3.5, 7)
				var shine := Portrait.arc(spot + Vector2(0.3, -0.3), 0.9, angle - 2.4, angle - 0.8, 5)
				for part in parts:
					for piece in Geometry2D.intersect_polyline_with_polygon(curl, part):
						sketch.stroke(piece, Color(hair_dark, 0.5), 0.4, "hair")
					for piece in Geometry2D.intersect_polyline_with_polygon(shine, part):
						sketch.stroke(piece, Color(hair_light.lightened(0.15), 0.35), 0.35, "hair")

	func _comb_lines() -> void:
		if not fine:
			return
		for k in 4:
			var x := cx - w * 0.5 + w * 0.35 * float(k)
			var start := Vector2(x, top + 7.0 - absf(x - cx) * 0.05 + _recede() * 3.0)
			sketch.stroke(Portrait.bezier(start, Vector2(x + 2.5, top + 2.0), Vector2(x + 5.0, top - 0.5), 8),
				Color(hair_dark, 0.45), 0.4, "hair", false, true)

	# --- Accessories -----------------------------------------------------------------------

	func _accessory() -> void:
		match String(look.get("accessory", "")):
			"glasses":
				_glasses()
			"headset":
				_headset()
			"earrings":
				_earrings()

	func _glasses() -> void:
		var sk := sketch
		var frame_color := Color("#16171b") if world_era == 1 else Color("#3a3f47").lerp(accent, 0.25)
		var width := 0.8 if world_era == 1 else 0.5
		if world_era == 3:
			# Frameless smart lenses with a fine rim in her color.
			frame_color = Color(accent.darkened(0.15), 0.9)
			width = 0.4
		var lens_tint := Color(1, 1, 1, 0.07) if world_era == 1 else Color(accent, 0.13)
		var lenses: Array[PackedVector2Array] = []
		for sgn: float in [-1.0, 1.0]:
			var center := Vector2(cx + sgn * eye_dx, eye_y + 0.3)
			var half := Vector2(eye_w + 1.9, eye_h + 2.0)
			var lens := Portrait.rounded_rect(Rect2(center - half, half * 2.0), [2.4, 2.4, 2.6, 2.6], 4)
			lenses.append(lens)
			sk.fill(lens, lens_tint, "glasses")
			if not tiny:
				sk.stroke(PackedVector2Array([center + Vector2(-half.x * 0.5, half.y * 0.2), center + Vector2(-half.x * 0.05, -half.y * 0.5)]),
					Color(1, 1, 1, 0.22), 0.4, "glasses")
			sk.stroke(lens, frame_color, width, "glasses", true)
			sk.stroke(PackedVector2Array([center + Vector2(sgn * half.x, -half.y * 0.6), Vector2(cx + sgn * (w + 0.2), eye_y - 0.6)]),
				frame_color, width * 0.85, "glasses")
		sk.stroke(Portrait.bezier(Vector2(cx - eye_dx + eye_w + 1.9, eye_y - 0.4), Vector2(cx, eye_y - 1.6),
			Vector2(cx + eye_dx - eye_w - 1.9, eye_y - 0.4), 6), frame_color, width, "glasses")

	func _headset() -> void:
		var sk := sketch
		var led := accent
		match world_era:
			1:
				var band := Portrait.arc(Vector2(cx, ear_y - 3.0), 1.0, PI, TAU, 24)
				var reach := Vector2(w + 1.7, ear_y - 3.0 - (top - 3.0))
				for i in band.size():
					band[i] = Vector2(cx, ear_y - 3.0) + (band[i] - Vector2(cx, ear_y - 3.0)) * reach
				var strap := Portrait.ribbon(band, 1.6, 1.6)
				sk.fill(strap, GRAPHITE, "headset")
				outline.append(strap)
				for sgn: float in [-1.0, 1.0]:
					var cup := Portrait.rounded_rect(Rect2(Vector2(cx + sgn * (w + 0.9) - 2.1, ear_y - 3.6), Vector2(4.2, 7.2)),
						[2.1, 2.1, 2.1, 2.1], 4)
					sk.gradient(cup, GRAPHITE.lightened(0.18), GRAPHITE.darkened(0.1), ear_y - 3.6, ear_y + 3.6, "headset")
					outline.append(cup)
				var boom := Portrait.bezier(Vector2(cx - w - 0.6, ear_y + 2.5), Vector2(cx - w + 1.0, mouth_y + 2.8),
					Vector2(cx - mouth_w - 1.6, mouth_y + 0.8), 10)
				sk.stroke(boom, GRAPHITE.lightened(0.1), 0.8, "headset")
				sk.circle(boom[boom.size() - 1], 1.0, GRAPHITE.lightened(0.2), "headset")
				if fine:
					sk.circle(Vector2(cx + w + 0.9, ear_y + 2.2), 0.45, led.lightened(0.3), "headset")
			2:
				var bud := Vector2(cx + w + 0.8, ear_y + 0.5)
				sk.fill(Portrait.ellipse(bud, Vector2(1.6, 2.2), 14), Color("#d9dde3").lerp(accent, 0.2), "headset")
				sk.stroke(Portrait.bezier(bud + Vector2(0, 1.6), Vector2(cx + w - 1.0, mouth_y + 1.5), Vector2(cx + mouth_w + 2.0, mouth_y + 0.4), 8),
					Color(accent, 0.55), 0.35, "headset")
			_:
				var node := Vector2(cx + w + 0.8, ear_y - 0.8)
				sk.circle(node, 2.4, Color(accent, 0.2), "headset")
				sk.circle(node, 1.0, accent.lightened(0.3), "headset")

	func _earrings() -> void:
		for sgn: float in [-1.0, 1.0]:
			var lobe := Vector2(cx + sgn * (w + ear_w * 0.4), ear_y + ear_h - 0.9)
			var metal := GOLD if world_era != 3 else GOLD.lerp(s.accent, 0.4)
			if tiny:
				sketch.circle(lobe + Vector2(0, 1.0), 0.9, metal, "earring")
			else:
				var hoop := Portrait.arc(lobe + Vector2(0, 1.7), 1.7, -PI * 0.45, PI * 1.45, 16)
				sketch.stroke(hoop, metal, 0.55, "earring")
