extends "res://tests/framework/test_case.gd"
## The recurring cast on screen: aging portraits (Portrait).

const PHONE := Vector2(412, 915)
const SIZES := [40.0, 96.0, 240.0]

var holder: Control


func before_each() -> void:
	holder = Control.new()
	holder.theme = EraTheme.get_theme(1)
	tree.root.add_child(holder)
	holder.position = Vector2.ZERO
	holder.size = PHONE


func after_each() -> void:
	holder.queue_free()
	await tree.process_frame


func _born(character_id: String) -> int:
	return int(Characters.get_character(character_id)["born"])


# --- Portrait -------------------------------------------------------------------------------

func test_every_character_draws_at_every_age_size_and_era() -> void:
	var portraits: Array[Portrait] = []
	for era in [1, 2, 3]:
		var x := 0.0
		for side in SIZES:
			var face := Portrait.new()
			face.custom_minimum_size = Vector2(side, side)
			face.size = Vector2(side, side)
			face.position = Vector2(x, 0.0)
			face.set_era_override(era)
			holder.add_child(face)
			portraits.append(face)
			x += float(side)
	for character_id in Characters.ids():
		for age in range(5, 101, 5):
			var before: Array[int] = []
			for face in portraits:
				face.set_character(character_id, float(_born(character_id) + age))
				before.append(face.draws)
			await tree.process_frame
			for i in portraits.size():
				var face := portraits[i]
				var context := "%s at %d, era %d, %d px" % [character_id, age, face.era_override, int(face.size.x)]
				assert_gt(face.draws, before[i], context + " drew")
				assert_eq(face.invalid_shapes, 0, context + ": every shape triangulates")
	assert_eq(portraits[0].get_age(), 100, "the last pass shows them at 100")


func test_every_mood_and_unknown_people_paint_cleanly() -> void:
	for era in [1, 2, 3]:
		var style := EraStyle.for_era(era)
		for character_id in Characters.ids():
			for mood in [-5.0, -1.0, 0.0, 1.0, 5.0]:
				var sketch := Portrait.paint(character_id, 2050.0, mood, style, 160.0)
				assert_eq(sketch.invalid, 0, "%s, mood %s, era %d" % [character_id, mood, era])
				assert_gt(sketch.ops.size(), 10, "%s draws something" % character_id)
		var stranger := Portrait.paint("nobody", 2050.0, 0.0, style, 96.0)
		assert_eq(stranger.invalid, 0, "an unknown id draws an anonymous figure")
		assert_gt(stranger.tagged("head"), 0)
		var ringed := Portrait.paint("maya", 2050.0, 0.0, style, 96.0, Vector2.ZERO, Color.WHITE, 4.0)
		assert_eq(ringed.tagged("ring"), 1, "a cut-out ring when asked")


func test_hair_grays_monotonically_with_age() -> void:
	for character_id in Characters.ids():
		var look: Dictionary = Characters.get_character(character_id)["look"]
		var base := Color(String(look["hair"]))
		if String(look["hair_style"]) == "bald":
			for age in [20, 60, 95]:
				assert_eq(Portrait.hair_color_for(look, age), base, "%s: bald looks keep their color" % character_id)
			continue
		assert_eq(Portrait.hair_color_for(look, 30), base, "%s: no gray at 30" % character_id)
		var last := Portrait.hair_color_for(look, 0)
		for age in range(1, 111):
			var color := Portrait.hair_color_for(look, age)
			assert_true(color.get_luminance() >= last.get_luminance() - 0.000001, "%s lighter or equal at %d" % [character_id, age])
			assert_true(color.s <= last.s + 0.000001, "%s no more saturated at %d" % [character_id, age])
			last = color
		var white := Portrait.hair_color_for(look, 85)
		assert_gt(white.get_luminance(), 0.85, "%s: white by 85" % character_id)
		assert_lt(white.s, 0.05, "%s: no color left at 85" % character_id)
		assert_gt(Portrait.hair_color_for(look, 62).get_luminance(), base.get_luminance() + 0.1, "%s: gray in their sixties" % character_id)


func test_wrinkles_come_in_bands() -> void:
	var last := 0
	var seen := {}
	for age in range(0, 111):
		var level := Portrait.wrinkle_level(age)
		assert_between(level, 0, 4, "level at %d" % age)
		assert_true(level >= last, "never fewer lines with age (%d)" % age)
		seen[level] = true
		last = level
	assert_eq(seen.size(), 5, "every band from smooth to deeply lined")
	assert_eq(Portrait.wrinkle_level(20), 0)
	assert_eq(Portrait.wrinkle_level(95), 4)
	var style := EraStyle.for_era(1)
	var young := Portrait.paint("jonas", 2010.0, 0.0, style, 240.0).tagged("wrinkle")
	var middle := Portrait.paint("jonas", 2036.0, 0.0, style, 240.0).tagged("wrinkle")
	var old := Portrait.paint("jonas", 2070.0, 0.0, style, 240.0).tagged("wrinkle")
	assert_eq(young, 0, "Jonas at 30 is unlined")
	assert_gt(middle, young, "lines at 56")
	assert_gt(old, middle, "more at 90")
	assert_eq(Portrait.paint("jonas", 2070.0, 0.0, style, 40.0).tagged("wrinkle"), 0, "fine lines drop out at 40 px")


func test_children_and_elders_are_drawn_differently() -> void:
	assert_eq(Portrait.childness(5), 1.0)
	assert_eq(Portrait.childness(16), 0.0)
	assert_between(Portrait.childness(11), 0.3, 0.6)
	var style := EraStyle.for_era(1)
	var child := Portrait.paint("sam", 2021.0, 0.0, style, 240.0)
	var adult := Portrait.paint("sam", 2050.0, 0.0, style, 240.0)
	assert_ne(_bounds(child, "head").size, _bounds(adult, "head").size, "a rounder child's face")
	assert_gt(_bounds(child, "head").size.x / _bounds(child, "head").size.y, _bounds(adult, "head").size.x / _bounds(adult, "head").size.y,
		"children's faces are rounder")
	assert_eq(Portrait.paint("jonas", 1990.0, 0.0, style, 240.0).tagged("beard"), 0, "no beard on a ten-year-old")
	assert_gt(Portrait.paint("jonas", 2030.0, 0.0, style, 240.0).tagged("beard"), 0, "Jonas's beard")
	# Past seventy the head settles lower between the shoulders.
	var settled := _bounds(Portrait.paint("victor", 2070.0, 0.0, style, 240.0), "head")
	var upright := _bounds(Portrait.paint("victor", 2030.0, 0.0, style, 240.0), "head")
	assert_gt(settled.position.y, upright.position.y, "an older posture")
	assert_eq(Portrait.outfit_for("sam", 2026.0), "hoodie", "Sam is a kid in 2026")
	assert_eq(Portrait.outfit_for("sam", 2060.0), "mandarin")
	assert_eq(Portrait.outfit_for("nobody", 2040.0), "crew")


func test_moods_change_the_face() -> void:
	assert_eq(Portrait.mood_curve(0.0), 0.0)
	assert_gt(Portrait.mood_curve(1.0), 0.3, "warm from 1")
	assert_lt(Portrait.mood_curve(-1.0), -0.3, "wary from -1")
	assert_eq(Portrait.mood_curve(9.0), 1.0)
	assert_eq(Portrait.mood_curve(NAN), 0.0)
	var style := EraStyle.for_era(1)
	var warm := _points(Portrait.paint("nadia", 2040.0, 3.0, style, 240.0), "mouth")
	var cold := _points(Portrait.paint("nadia", 2040.0, -3.0, style, 240.0), "mouth")
	assert_ne(warm, cold, "a smile and a frown")
	var calm := _points(Portrait.paint("aria", 2050.0, 2.0, style, 240.0), "core")
	var hostile := _points(Portrait.paint("aria", 2050.0, -3.0, style, 240.0), "core")
	assert_ne(calm, hostile, "the machine's aperture narrows")


func test_the_machine_grows_with_each_generation() -> void:
	var last := 0
	for version in range(1, 8):
		var rings := Portrait.machine_rings(version)
		assert_gt(rings, last, "more rings at v%d" % version)
		last = rings
	assert_eq(Portrait.machine_rings(0), 1)
	assert_eq(Portrait.machine_rings(30), Portrait.machine_rings(7), "capped")
	var style := EraStyle.for_era(3)
	var first := Portrait.paint("aria", 2030.0, 0.0, style, 240.0)
	var late := Portrait.paint("aria", 2075.0, 0.0, style, 240.0)
	assert_gt(late.tagged("ring"), first.tagged("ring"))
	assert_gt(late.tagged("node"), first.tagged("node"))
	assert_eq(late.tagged("eye") + late.tagged("head") + late.tagged("hair"), 0, "no human face")


func test_portrait_follows_the_era_theme() -> void:
	var face := Portrait.new()
	face.size = Vector2(96, 96)
	holder.add_child(face)
	face.set_character("lin", 2040.0)
	await tree.process_frame
	assert_eq(face.get_era(), 1)
	var drawn := face.draws
	holder.theme = EraTheme.get_theme(3)
	await tree.process_frame
	assert_eq(face.get_era(), 3, "restyled with the theme")
	assert_gt(face.draws, drawn, "redrawn for the new era")
	drawn = face.draws
	face.set_mood(0.0)
	face.set_character("lin", 2040.0)
	await tree.process_frame
	assert_eq(face.draws, drawn, "no redraw without a change")
	face.set_era_override(2)
	assert_eq(face.get_era(), 2, "an override wins")
	assert_eq(face.mouse_filter, Control.MOUSE_FILTER_IGNORE, "takes no input")


# --- Helpers ----------------------------------------------------------------------------------

## The bounding box of the shapes tagged [param tag].
func _bounds(sketch: Portrait.Sketch, tag: String) -> Rect2:
	var box := Rect2()
	var first := true
	for op in sketch.ops:
		if String(op[0]) == "fill" or String(op[0]) == "grad":
			if String(op[1]) != tag:
				continue
			for point in op[2] as PackedVector2Array:
				if first:
					box = Rect2(point, Vector2.ZERO)
					first = false
				else:
					box = box.expand(point)
	return box


## The points of the shapes tagged [param tag], as one array.
func _points(sketch: Portrait.Sketch, tag: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	for op in sketch.ops:
		if String(op[1]) == tag and (String(op[0]) == "fill" or String(op[0]) == "grad"):
			out.append_array(op[2] as PackedVector2Array)
	return out
