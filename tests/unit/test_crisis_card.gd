extends "res://tests/framework/test_case.gd"
## The crisis card overlay (DilemmaDialog), its card (CrisisCard), its vitals
## strip (VitalsStrip) and the category illustrations (CrisisArt): response rows and affordability,
## swipes, holds, hovers and keys, effect previews, escalation, and the phone,
## tablet and desktop layouts. Pointer input goes through the viewport like a
## real mouse or touch screen (in viewport coordinates: the headless window is
## tiny and scaled).

const DialogScene := preload("res://ui/components/dilemma_dialog.tscn")
const METRICS := {
	"compute_energy_sat": 51.0, "labor_displacement": 72.0, "geopolitical_tension": 69.0,
	"algorithmic_autonomy": 100.0, "alignment_drift": 71.0, "epistemic_trust": 62.0,
}
const RICH := {"capital": 500.0, "regulatory_goodwill": 60.0, "talent": 800.0, "compute_clusters": 8.0}
const POOR := {"capital": 30.0, "regulatory_goodwill": 0.0}

var host: Control
var dialog: DilemmaDialog
var chosen: Array[String] = []


func before_each() -> void:
	host = Control.new()
	host.theme = EraTheme.get_theme(1)
	host.position = Vector2.ZERO
	host.size = Vector2(1600, 900)
	tree.root.add_child(host)
	dialog = DialogScene.instantiate()
	host.add_child(dialog)
	chosen.clear()
	dialog.option_chosen.connect(func(option_id: String): chosen.append(option_id))
	await tree.process_frame


func after_each() -> void:
	host.queue_free()
	await tree.process_frame


func _card(card_id: String, source: String = "DECK", escalation: int = 0, role: String = "CEO") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	return DilemmaDeck.new()._instantiate(DilemmaDeck.get_template(card_id),
		{"role": role, "turn": 60, "year": SimConstants.year_for_turn(60)}, rng, source, escalation)


func _present(card: Dictionary, resources: Dictionary = RICH) -> void:
	dialog.present(card, resources, "CEO", METRICS)
	await wait_seconds(DilemmaDialog.ENTER_TIME + 0.1)


func _rows() -> Array[Button]:
	var rows: Array[Button] = []
	for node in dialog.find_children("Option*", "Button", true, false):
		rows.append(node as Button)
	return rows


func _card_center() -> Vector2:
	return dialog.get_card().get_global_rect().get_center()


func _text(label_name: String) -> String:
	return (dialog.find_child(label_name, true, false) as Label).text


# --- Pointer input through the viewport ---------------------------------------------------

func _button(at: Vector2, pressed: bool, touch: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.position = at
	event.global_position = at
	if touch:
		event.device = InputEvent.DEVICE_ID_EMULATION
	tree.root.push_input(event, true)


func _motion(at: Vector2, dragging: bool = false, touch: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if dragging else 0
	if touch:
		event.device = InputEvent.DEVICE_ID_EMULATION
	tree.root.push_input(event, true)


## Presses on the card, drags it [param dx] px sideways and, unless
## [param release] is false, lets go.
func _drag(dx: float, release: bool = true) -> void:
	var start := _card_center()
	_button(start, true)
	for step in [0.25, 0.5, 0.75, 1.0]:
		_motion(start + Vector2(dx * float(step), 3.0 * float(step)), true)
	if release:
		_button(start + Vector2(dx, 3.0), false)


func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	tree.root.push_input(event, true)


func _assert_preview(expected: Dictionary, message: String) -> void:
	var preview := dialog.get_vitals().get_preview()
	assert_eq(preview.size(), expected.size(), message + ": previewed metrics")
	for key in expected:
		assert_almost_eq(float(preview.get(key, 0.0)), float(expected[key]), 0.001, "%s: %s" % [message, key])


# --- Rows and choices ----------------------------------------------------------------------

func test_present_builds_a_row_per_response_and_disables_unaffordable() -> void:
	var card := _card("SELF_MODIFICATION_SIGNAL")
	await _present(card, POOR)
	assert_true(dialog.visible)
	var rows := _rows()
	var options: Array = card["options"]
	assert_eq(rows.size(), options.size() + 1, "a Button per response plus Defer")
	assert_eq(String(rows[0].get_meta("option_id")), "A")
	assert_eq(String(rows[1].get_meta("option_id")), "B")
	assert_eq(String(rows[2].get_meta("option_id")), DilemmaDeck.DEFER_ID)
	assert_true(rows[0].disabled, "the $90B pause is out of reach")
	assert_false(rows[1].disabled, "$25B is affordable")
	assert_false(rows[2].disabled, "deferring is free")
	var keys: Array[String] = []
	for row in rows:
		keys.append(String(row.find_child("Key", true, false).get_meta("key")))
	assert_eq(keys, ["←", "→", "↓"] as Array[String], "key badges")
	assert_string_contains((rows[0].find_child("Sub", true, false) as Label).text, "Needs $90B")
	assert_string_contains((rows[1].find_child("Sub", true, false) as Label).text, "capability +10")
	assert_not_null(rows[0].find_child("Effect_alignment_drift", true, false), "drift glyph on the pause")
	assert_true(dialog.get_vitals().visible)
	assert_almost_eq(dialog.get_vitals().get_value("alignment_drift"), 71.0, 0.001)


func test_role_only_response_gets_a_c_key() -> void:
	await _present(_card("CHIP_EMBARGO"))
	var rows := _rows()
	assert_eq(rows.size(), 4, "A, B, the CEO-only C and Defer")
	assert_eq(String(rows[2].find_child("Key", true, false).get_meta("key")), "C")
	assert_string_contains((rows[2].find_child("Sub", true, false) as Label).text, "Frontier Lab only")


func test_present_without_metrics_hides_the_vitals() -> void:
	dialog.present(_card("GRID_BROWNOUT"), RICH, "CEO")
	await tree.process_frame
	assert_true(dialog.visible)
	assert_false(dialog.get_vitals().visible, "no metrics, no strip")


func test_choose_hides_and_emits_synchronously() -> void:
	await _present(_card("SELF_MODIFICATION_SIGNAL"))
	dialog.choose("B")
	assert_false(dialog.visible)
	assert_eq(chosen, ["B"] as Array[String])
	dialog.close()
	assert_false(dialog.visible)


func test_click_commits_after_the_card_leaves() -> void:
	await _present(_card("SELF_MODIFICATION_SIGNAL"))
	var row := _rows()[1]
	var center := row.get_global_rect().get_center()
	_motion(center)
	_button(center, true)
	_button(center, false)
	assert_eq(chosen.size(), 0, "the card flies off first")
	await wait_seconds(DilemmaDialog.FLY_TIME + 0.15)
	assert_eq(chosen, ["B"] as Array[String])
	assert_false(dialog.visible)


# --- Swipes --------------------------------------------------------------------------------

func test_swipe_past_the_threshold_commits_the_first_or_second_response() -> void:
	var card := _card("SELF_MODIFICATION_SIGNAL")
	await _present(card)
	_drag(-170.0)
	await wait_seconds(DilemmaDialog.FLY_TIME + 0.15)
	assert_eq(chosen, ["A"] as Array[String], "left commits options[0]")
	assert_false(dialog.visible)
	await _present(card)
	_drag(170.0)
	await wait_seconds(DilemmaDialog.FLY_TIME + 0.15)
	assert_eq(chosen, ["A", "B"] as Array[String], "right commits options[1]")


func test_short_drag_snaps_back() -> void:
	await _present(_card("SELF_MODIFICATION_SIGNAL"))
	_drag(-70.0)
	await wait_seconds(DilemmaDialog.SNAP_TIME + 0.15)
	assert_eq(chosen.size(), 0, "nothing chosen")
	assert_true(dialog.visible)
	assert_almost_eq(dialog._slot.offset.x, 0.0, 0.5, "card back in place")
	assert_almost_eq(dialog._slot.tilt, 0.0, 0.001, "card upright")
	assert_eq(dialog.get_vitals().get_preview().size(), 0, "preview cleared")


func test_drag_previews_the_response_on_the_vitals_and_the_card() -> void:
	var card := _card("SELF_MODIFICATION_SIGNAL")
	await _present(card)
	var start := _card_center()
	_drag(-70.0, false)
	await tree.process_frame
	_assert_preview({"alignment_drift": -5.0}, "dragging left previews A")
	var tag: Control = dialog.find_child("SwipeTag", true, false)
	assert_true(tag.visible, "the card names the response")
	assert_eq((tag.get_child(0) as Label).text, "Emergency training pause")
	assert_lt(dialog._slot.offset.x, -60.0, "card follows the pointer")
	assert_lt(dialog._slot.tilt, 0.0, "and tilts")
	_motion(start + Vector2(-40.0, 0.0), true)
	_motion(start + Vector2(-12.0, 0.0), true)
	await tree.process_frame
	assert_eq(dialog.get_vitals().get_preview().size(), 0, "no preview within 30 px")
	assert_false(tag.visible)
	_motion(start + Vector2(64.0, 0.0), true)
	await tree.process_frame
	_assert_preview({"alignment_drift": 4.0}, "dragging right previews B")
	assert_true(tag.visible)
	assert_eq((tag.get_child(0) as Label).text, "Allow it under monitoring")
	_motion(start + Vector2(10.0, 0.0), true)
	_button(start + Vector2(10.0, 0.0), false)
	await wait_seconds(DilemmaDialog.SNAP_TIME + 0.1)
	assert_eq(chosen.size(), 0)


func test_unaffordable_response_cannot_be_swiped() -> void:
	await _present(_card("SELF_MODIFICATION_SIGNAL"), POOR)
	_drag(-170.0)
	await wait_seconds(0.7)
	assert_eq(chosen.size(), 0, "the pause costs $90B")
	assert_true(dialog.visible)
	assert_almost_eq(dialog._slot.offset.x, 0.0, 0.5, "shaken back into place")


# --- Holds, hovers and keys ------------------------------------------------------------------

func test_hold_previews_and_release_does_not_commit() -> void:
	var card := _card("SELF_MODIFICATION_SIGNAL")
	await _present(card)
	var center := _rows()[1].get_global_rect().get_center()
	_button(center, true, true)
	await wait_seconds(DilemmaDialog.HOLD_TIME + 0.1)
	_assert_preview({"alignment_drift": 4.0}, "holding B")
	_button(center, false, true)
	await wait_seconds(DilemmaDialog.FLY_TIME + 0.1)
	assert_eq(chosen.size(), 0, "releasing a hold does not commit")
	assert_true(dialog.visible)
	assert_eq(dialog.get_vitals().get_preview().size(), 0, "release clears the preview")
	_button(center, true, true)
	_button(center, false, true)
	await wait_seconds(DilemmaDialog.FLY_TIME + 0.15)
	assert_eq(chosen, ["B"] as Array[String], "a quick tap still commits")


func test_hover_previews_and_leaving_clears() -> void:
	await _present(_card("SELF_MODIFICATION_SIGNAL"))
	var rows := _rows()
	_motion(rows[0].get_global_rect().get_center())
	await tree.process_frame
	_assert_preview({"alignment_drift": -5.0}, "hovering A")
	_motion(rows[2].get_global_rect().get_center())
	await tree.process_frame
	_assert_preview({"alignment_drift": 3.0}, "hovering Defer")
	_motion(Vector2(4, 4))
	await tree.process_frame
	assert_eq(dialog.get_vitals().get_preview().size(), 0, "leaving the rows clears the preview")
	assert_eq(chosen.size(), 0)


func test_keys_choose_by_side_and_row() -> void:
	var card := _card("SELF_MODIFICATION_SIGNAL")
	await _present(card)
	_key(KEY_RIGHT)
	await wait_seconds(DilemmaDialog.FLY_TIME + 0.15)
	assert_eq(chosen, ["B"] as Array[String], "→ picks options[1]")
	await _present(card)
	_key(KEY_3)
	await wait_seconds(DilemmaDialog.FLY_TIME + 0.15)
	assert_eq(chosen, ["B", DilemmaDeck.DEFER_ID] as Array[String], "3 is the third row, Defer")
	await _present(card, POOR)
	_key(KEY_LEFT)
	await wait_seconds(DilemmaDialog.FLY_TIME + 0.15)
	assert_eq(chosen.size(), 2, "← cannot pick what the player cannot afford")
	assert_true(dialog.visible)


# --- Card content --------------------------------------------------------------------------

func test_escalation_prefix_becomes_a_chip() -> void:
	var card := _card("GRID_BROWNOUT", "DEFERRED", 2)
	assert_true(String(card["title"]).begins_with("[ESCALATED x2]"))
	await _present(card)
	var title := (dialog.find_child("Title", true, false) as Label).text
	assert_false(title.contains("ESCALATED"), "prefix stripped: " + title)
	assert_eq(title, UiFormat.strip_escalation(String(card["title"])))
	var chip: Control = dialog.find_child("EscalationChip", true, false)
	assert_true(chip.visible)
	assert_string_contains((chip.get_child(0) as Label).text, "Escalated ×2")
	assert_eq(_text("Kicker"), "Returns after deferral")
	assert_string_contains(_text("HintLeft"), "Ration")
	assert_string_contains(_text("HintRight"), "Run hot")
	await _present(_card("GRID_BROWNOUT"))
	assert_false(chip.visible, "fresh cards have no chip")
	assert_false((dialog.find_child("KickerRow", true, false) as Control).visible, "nor a source kicker")


func test_injected_card_names_its_source_and_brief_is_one_sentence() -> void:
	var card := _card("CHIP_EMBARGO", "ASI")
	await _present(card)
	assert_eq(_text("Kicker"), "Injected by Emergent ASI")
	var brief := (dialog.find_child("Brief", true, false) as Label).text
	assert_true(String(card["body"]).begins_with(brief), "first sentence of the body")
	assert_false(brief.contains(". "), "one sentence: " + brief)
	assert_eq(CrisisCard.first_sentence("One. Two."), "One.")
	assert_eq(CrisisCard.first_sentence("Draws 3.5 GW now"), "Draws 3.5 GW now")


func test_swipe_hints_cover_the_deck() -> void:
	for card_id in CrisisCard.SWIPE_HINTS:
		assert_false(DilemmaDeck.get_template(card_id).is_empty(), "hint for a real card: " + card_id)
	for template in DilemmaDeck.all_cards():
		var label := String(template["options"][0]["label"])
		assert_ne(CrisisCard.short_label(String(template["id"]), 0, label), "", template["id"])
	assert_eq(CrisisCard.short_label("UNKNOWN", 1, "Keep the training runs hot"), "Keep the training")


func test_era_theme_restyles_the_card() -> void:
	await _present(_card("GRID_BROWNOUT", "DEFERRED", 1))
	host.theme = EraTheme.get_theme(2)
	await tree.process_frame
	assert_eq(EraTheme.style_of(dialog).era, 2)
	assert_eq(_text("EscalationLabel"), "ESCALATED ×1", "Era II speaks in capitals")
	host.theme = EraTheme.get_theme(3)
	await tree.process_frame
	assert_eq(_text("EscalationLabel"), "escalated ×1", "Era III in lower case")
	assert_true(dialog.visible)


# --- Art and vitals ------------------------------------------------------------------------

func test_crisis_art_draws_every_category_in_every_era() -> void:
	var categories: Array[String] = []
	for template in DilemmaDeck.all_cards():
		var category := String(template.get("category", "CRISIS"))
		if not categories.has(category):
			categories.append(category)
	for category in categories:
		assert_true(CrisisArt.CATEGORIES.has(category), "an illustration for " + category)
	categories.append_array(["CRISIS", "NOT_A_CATEGORY"] as Array[String])
	for category in categories:
		for era in [1, 2, 3]:
			var texture := CrisisArt.texture_for(category, era, Vector2i(220, 90))
			assert_not_null(texture, "%s era %d" % [category, era])
			assert_eq(Vector2i(texture.get_size()), Vector2i(220, 90), "%s logical size" % category)
			var svg := CrisisArt.svg(category, era, Vector2i(220, 90), Vector2(12, 12))
			assert_false(svg.contains("<text"), "ThorVG draws no text")
			var image := Image.new()
			assert_eq(image.load_svg_from_string(svg), OK, "%s era %d parses" % [category, era])
			assert_eq(image.get_size(), Vector2i(440, 180), "rendered at twice the size")
	assert_eq(CrisisArt.category_key("energy"), "ENERGY")
	assert_eq(CrisisArt.category_key("???"), "CRISIS")
	assert_eq(CrisisArt.texture_for("ENERGY", 2, Vector2i(220, 90)), CrisisArt.texture_for("ENERGY", 2, Vector2i(220, 90)), "cached")


func test_vitals_preview_math() -> void:
	var strip := VitalsStrip.new()
	strip.size = Vector2(980, VitalsStrip.DESKTOP_HEIGHT)
	host.add_child(strip)
	strip.set_values({"alignment_drift": 71.0, "epistemic_trust": 98.0, "labor_displacement": 1.0, "compute_energy_sat": 40.0})
	assert_almost_eq(strip.get_value("alignment_drift"), 71.0, 0.001)
	strip.set_preview({"alignment_drift": -5.0, "epistemic_trust": 4.0, "labor_displacement": -3.0,
		"compute_energy_sat": 12.0, "discovery_index": 8.0, "geopolitical_tension": 0.01})
	var preview := strip.get_preview()
	assert_eq(preview.size(), 4, "indices and tiny changes are not previewed")
	assert_false(preview.has("discovery_index"))
	assert_almost_eq(strip.get_predicted("alignment_drift"), 66.0, 0.001)
	assert_almost_eq(strip.get_predicted("epistemic_trust"), 100.0, 0.001, "clamped at 100")
	assert_almost_eq(strip.get_predicted("labor_displacement"), 0.0, 0.001, "clamped at 0")
	assert_eq(strip.get_ghost_range("compute_energy_sat"), Vector2(40, 52), "current to predicted")
	assert_eq(strip.get_ghost_range("alignment_drift"), Vector2(65, 71), "small drops widen downward")
	assert_eq(strip.get_ghost_range("epistemic_trust"), Vector2(94, 100), "rises at the top widen downward")
	assert_eq(strip.get_ghost_range("labor_displacement"), Vector2(0, 6), "drops at the bottom widen upward")
	assert_eq(strip.get_ghost_range("algorithmic_autonomy"), Vector2.ZERO, "nothing previewed")
	await wait_frames(2)
	strip.set_compact(true)
	assert_eq(strip.get_combined_minimum_size().y, VitalsStrip.COMPACT_HEIGHT, "one 64 px row on phones")
	await wait_frames(2)
	strip.set_preview({})
	assert_eq(strip.get_preview().size(), 0, "{} clears")
	var pressed: Array[String] = []
	strip.metric_pressed.connect(func(key: String): pressed.append(key))
	strip.size = Vector2(396, VitalsStrip.COMPACT_HEIGHT)
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	tap.position = Vector2(396.0 / 6.0 * 4.5, 30.0)
	strip._gui_input(tap)
	var lift := tap.duplicate() as InputEventMouseButton
	lift.pressed = false
	strip._gui_input(lift)
	assert_eq(pressed, ["alignment_drift"] as Array[String], "tapping the fifth meter")


# --- Layouts --------------------------------------------------------------------------------

## Every visible control inside the dialog stays within [param width].
func _assert_fits(width: float, context: String) -> void:
	var overflowing: Array[String] = []
	for node in dialog.find_children("*", "Control", true, false):
		var control := node as Control
		if control.is_visible_in_tree() and control.get_global_rect().end.x > width + 0.5:
			overflowing.append("%s ends at %.0f" % [control.name, control.get_global_rect().end.x])
	assert_eq(overflowing.size(), 0, "%s fits %.0f px: %s" % [context, width, ", ".join(overflowing.slice(0, 5))])


func test_phone_layout_stacks_and_fits_412_px() -> void:
	host.size = Vector2(412, 915)
	dialog.set_compact(true)
	await _present(_card("ZERO_DAY_CASCADE", "DEFERRED", 1))
	await wait_frames(3)
	_assert_fits(412.0, "phone crisis card")
	var card_rect := (dialog.find_child("Card", true, false) as Control).get_global_rect()
	var rows := _rows()
	assert_lte(card_rect.end.y, rows[0].get_global_rect().position.y, "responses below the card")
	assert_almost_eq(card_rect.position.x, 412.0 - card_rect.end.x, 1.0, "card centered")
	assert_almost_eq((dialog.find_child("Art", true, false) as Control).size.y, DilemmaDialog.COMPACT_ART_HEIGHT, 0.5, "150 px art")
	assert_eq(dialog.get_vitals().get_combined_minimum_size().y, VitalsStrip.COMPACT_HEIGHT)
	for row in rows:
		assert_gte(row.size.y, 44.0, "finger-sized rows")
	_drag(-70.0)
	await wait_seconds(DilemmaDialog.SNAP_TIME + 0.15)
	_assert_fits(412.0, "phone card after a drag")


func test_tablet_layout_centers_a_narrower_card() -> void:
	host.size = Vector2(640, 900)
	dialog.set_compact(true)
	await _present(_card("SELF_MODIFICATION_SIGNAL"))
	await wait_frames(3)
	_assert_fits(640.0, "tablet crisis card")
	var card_rect := (dialog.find_child("Card", true, false) as Control).get_global_rect()
	assert_lte(card_rect.size.x, DilemmaDialog.CARD_MAX_WIDTH + 0.5)
	assert_almost_eq(card_rect.position.x, 640.0 - card_rect.end.x, 1.0, "card centered")
	assert_lte(card_rect.end.y, _rows()[0].get_global_rect().position.y, "still stacked")


func test_desktop_layout_puts_the_card_beside_the_responses() -> void:
	await _present(_card("SELF_MODIFICATION_SIGNAL"))
	await wait_frames(3)
	var column: Control = dialog.find_child("CrisisColumn", true, false)
	assert_almost_eq(column.size.x, DilemmaDialog.DESKTOP_WIDTH, 0.5, "980 px composition")
	var card_rect := (dialog.find_child("Card", true, false) as Control).get_global_rect()
	assert_almost_eq(card_rect.size.x, DilemmaDialog.DESKTOP_CARD_WIDTH, 0.5)
	assert_lt(card_rect.end.x, _rows()[0].get_global_rect().position.x, "card on the left")
	assert_lt(dialog.get_vitals().get_global_rect().end.y, card_rect.position.y, "vitals across the top")
	_assert_fits(1600.0, "desktop crisis card")
