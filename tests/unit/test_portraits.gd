extends "res://tests/framework/test_case.gd"
## The recurring cast on screen: aging portraits (Portrait) and the
## character badge (CharacterBadge) on crisis cards (CrisisCard via
## DilemmaDialog).

const DialogScene := preload("res://ui/components/dilemma_dialog.tscn")
const PHONE := Vector2(412, 915)
const SIZES := [40.0, 96.0, 240.0]
const LONG_MEMORY := "Remembers that you funded the retraining program when nobody else in the Council would, and says so at every meeting."

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


## Every visible control under [param root_control] stays within [param width].
func _assert_fits(root_control: Control, width: float, context: String) -> void:
	var overflowing: Array[String] = []
	for node in root_control.find_children("*", "Control", true, false):
		var control := node as Control
		if control.is_visible_in_tree() and control.get_global_rect().end.x > width + 0.5:
			overflowing.append("%s (%s) ends at %.0f" % [control.name, control.get_class(), control.get_global_rect().end.x])
	assert_eq(overflowing.size(), 0, "%s fits %.0f px: %s" % [context, width, ", ".join(overflowing.slice(0, 5))])


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


# --- CharacterBadge ---------------------------------------------------------------------------

func test_badge_presents_a_character_and_fits_a_phone() -> void:
	var badge := CharacterBadge.new()
	holder.add_child(badge)
	badge.size = Vector2(340, 0)
	badge.position = Vector2(36, 120)
	assert_false(badge.visible, "hidden until a character is presented")
	badge.set_compact(true)
	badge.present("maya", 2040.0, 3.5, LONG_MEMORY)
	await wait_frames(3)
	assert_true(badge.visible)
	assert_eq((badge.find_child("BadgeName", true, false) as Label).text, "Maya Okafor")
	assert_eq((badge.find_child("BadgeRole", true, false) as Label).text, "Labor organizer · 41")
	assert_eq((badge.find_child("BadgeStanceLabel", true, false) as Label).text, "Loyal")
	var memory: Label = badge.find_child("BadgeMemory", true, false)
	assert_true(memory.visible)
	assert_eq(memory.text, LONG_MEMORY)
	assert_eq(badge.get_portrait().get_age(), 41)
	_assert_fits(holder, PHONE.x, "badge")
	badge.present("aria", 2052.0, -2.0, "")
	assert_eq((badge.find_child("BadgeRole", true, false) as Label).text, "Something else · v4")
	assert_eq((badge.find_child("BadgeStanceLabel", true, false) as Label).text, "Wary")
	assert_false(memory.visible, "no memory, no line")
	badge.present("", 2052.0, 0.0, "")
	assert_false(badge.visible, "an empty id hides the badge")
	badge.present("nobody", 2052.0, 0.0, "")
	assert_false(badge.visible, "so does an unknown one")
	assert_eq(CharacterBadge.role_line("jonas", 2070.0), "Retired grid elder · 90")


func test_badge_speaks_in_the_era_voice() -> void:
	var badge := CharacterBadge.new()
	holder.add_child(badge)
	badge.present("nadia", 2040.0, -4.0, "")
	holder.theme = EraTheme.get_theme(2)
	await wait_frames(2)
	assert_eq((badge.find_child("BadgeStanceLabel", true, false) as Label).text, "HOSTILE")
	holder.theme = EraTheme.get_theme(3)
	await wait_frames(2)
	assert_eq((badge.find_child("BadgeStanceLabel", true, false) as Label).text, "hostile")
	assert_eq(badge.get_portrait().get_era(), 3)


# --- The badge on the crisis card ------------------------------------------------------------

## A crisis dialog [param width] px wide; [param context] ([year, scores,
## memories]) is set before the dialog joins the tree.
func _dialog(width: float, context: Array = []) -> DilemmaDialog:
	holder.size = Vector2(width, 915)
	var dialog: DilemmaDialog = DialogScene.instantiate()
	if not context.is_empty():
		dialog.set_story_context(context[0], context[1], context[2])
	holder.add_child(dialog)
	return dialog


func _card(card_id: String, character_id: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var card := DilemmaDeck.new()._instantiate(DilemmaDeck.get_template(card_id),
		{"role": "CEO", "turn": 30, "year": SimConstants.year_for_turn(30)}, rng, "DECK", 0)
	card["character"] = character_id
	return card


func test_crisis_card_shows_the_badge_for_its_character() -> void:
	var dialog := _dialog(PHONE.x)
	await tree.process_frame
	dialog.set_compact(true)
	dialog.present(_card("GRID_BROWNOUT", "jonas"), {"capital": 500.0}, "CEO")
	await wait_frames(3)
	var badge := dialog.get_card().get_badge()
	assert_true(badge.is_visible_in_tree(), "the card names Jonas")
	assert_eq((badge.find_child("BadgeName", true, false) as Label).text, "Jonas Brandt")
	assert_eq(badge.get_portrait().get_age(), 61, "dated by the card's turn without a story context")
	assert_eq(badge.get_stance(), "Neutral", "neutral without a story context")
	assert_false((badge.find_child("BadgeMemory", true, false) as Label).visible, "and no memory")
	var art := dialog.get_card().find_child("Art", true, false) as Control
	assert_lt(badge.get_portrait().get_global_rect().position.y, art.get_global_rect().end.y, "the portrait sits on the illustration")
	_assert_fits(dialog, PHONE.x, "phone card with a badge")
	dialog.present(_card("GRID_BROWNOUT", ""), {"capital": 500.0}, "CEO")
	await wait_frames(2)
	assert_false(badge.is_visible_in_tree(), "no character, no badge")
	assert_false((dialog.find_child("BadgeMargin", true, false) as Control).visible)
	_assert_fits(dialog, PHONE.x, "phone card without a badge")


func test_story_context_updates_the_badge() -> void:
	var dialog := _dialog(PHONE.x, [2048.0, {"maya": 4.0}, {"maya": "Remembers the strike you backed."}])
	await tree.process_frame
	dialog.set_compact(true)
	dialog.present(_card("MASS_LAYOFF_WAVE", "maya"), {"capital": 500.0}, "CEO")
	await wait_frames(3)
	var badge := dialog.get_card().get_badge()
	assert_eq(badge.get_stance(), "Loyal", "context set before the dialog was ready")
	assert_eq(badge.get_portrait().get_age(), 49, "the context's year")
	assert_eq((badge.find_child("BadgeMemory", true, false) as Label).text, "Remembers the strike you backed.")
	dialog.set_story_context(2050.0, {"maya": -3.5}, {})
	await tree.process_frame
	assert_eq(badge.get_stance(), "Hostile", "updates the card on show")
	assert_eq((badge.find_child("BadgeStanceLabel", true, false) as Label).text, "Hostile")
	assert_false((badge.find_child("BadgeMemory", true, false) as Label).visible)
	assert_eq(badge.get_portrait().get_age(), 51)
	_assert_fits(dialog, PHONE.x, "phone card with a story context")


func test_desktop_card_keeps_its_layout_with_a_badge() -> void:
	var dialog := _dialog(1600.0)
	await tree.process_frame
	dialog.set_story_context(2061.0, {"aria": -2.0}, {"aria": LONG_MEMORY})
	dialog.present(_card("SELF_MODIFICATION_SIGNAL", "aria"), {"capital": 500.0}, "CEO")
	await wait_seconds(DilemmaDialog.ENTER_TIME + 0.1)
	var card := dialog.get_card()
	assert_true(card.get_badge().is_visible_in_tree())
	assert_almost_eq(card.get_global_rect().size.x, DilemmaDialog.DESKTOP_CARD_WIDTH, 0.5, "the card keeps its width")
	_assert_fits(card, card.get_global_rect().end.x, "the badge stays on the card")


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
