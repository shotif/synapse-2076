extends "res://tests/framework/test_case.gd"
## Accessibility: the text size scales every theme font size and the explicit
## overrides made through EraTheme; color-blind friendly colors replace good,
## bad, warn and critical in every era and reach the widgets; the settings
## dialog reads and writes GameSettings and fits a phone; the dashboard still
## fits a phone with the largest text and plain language on.

const PHONE := Vector2(412, 915)
const PHONE_PX := Vector2i(1081, 2202)
const DashboardScene := preload("res://ui/main_dashboard.tscn")

var settings: GameSettings
var host: Control
var _saved_root_size := Vector2i.ZERO


func before_all() -> void:
	ProjectSettings.set_setting("synapse/llm/probe_on_start", false)


func before_each() -> void:
	settings = GameSettings.new()
	settings.path = ""
	GameSettings.use(settings)
	EraTheme.invalidate()
	host = Control.new()
	host.theme = EraTheme.get_theme(1)
	host.size = PHONE
	tree.root.add_child(host)


func after_each() -> void:
	host.queue_free()
	if _saved_root_size != Vector2i.ZERO:
		tree.root.size = _saved_root_size
		tree.root.content_scale_size = UiLayout.DESKTOP_SIZE
		_saved_root_size = Vector2i.ZERO
	await tree.process_frame
	GameSettings.use(null)
	EraTheme.invalidate()


func _change_setting(key: String, value: Variant) -> void:
	settings.set_value(key, value)
	EraTheme.invalidate()


# --- Text size --------------------------------------------------------------------------

func test_text_size_scales_the_theme() -> void:
	var normal := EraTheme.get_theme(1)
	assert_eq(EraTheme.get_theme(1), normal, "cached per era and settings")
	assert_eq(normal.default_font_size, 14)
	assert_eq(normal.get_font_size("font_size", "PanelTitle"), 15)
	assert_eq(normal.get_font_size("font_size", "DimLabel"), 12)
	assert_eq(normal.get_font_size("normal_font_size", "RichTextLabel"), 13)
	assert_eq(normal.get_constant("text_scale_pct", "Era"), 100)
	_change_setting("text_scale", 1.3)
	var large := EraTheme.get_theme(1)
	assert_ne(large, normal, "a new theme for the new size")
	assert_eq(large.default_font_size, 18)
	assert_eq(large.get_font_size("font_size", "PanelTitle"), 20)
	assert_eq(large.get_font_size("font_size", "DimLabel"), 16)
	assert_eq(large.get_font_size("font_size", "ChipButton"), 17)
	assert_eq(large.get_font_size("normal_font_size", "RichTextLabel"), 17)
	assert_eq(large.get_font_size("font_size", "TooltipLabel"), 16)
	assert_eq(large.get_constant("text_scale_pct", "Era"), 130)
	assert_eq(EraTheme.get_theme(2).get_font_size("font_size", "PanelTitle"), 17, "Era II's capitals scale too")
	assert_eq(EraTheme.scaled(10), 13)
	_change_setting("text_scale", 1.15)
	assert_eq(EraTheme.get_theme(1).default_font_size, 16)
	assert_almost_eq(EraTheme.text_scale(), 1.15, 0.0001)
	_change_setting("text_scale", 1.0)
	assert_eq(EraTheme.get_theme(1).default_font_size, 14, "back to normal")


func test_explicit_sizes_follow_the_setting() -> void:
	var label := Label.new()
	EraTheme.set_scaled_font_size(label, 12)
	host.add_child(label)
	var rich := RichTextLabel.new()
	EraTheme.set_scaled_font_size(rich, 13, &"normal_font_size")
	host.add_child(rich)
	var card_label := Label.new()
	CrisisCard.style_label(card_label, EraStyle.for_era(1).font_ui, 20, Color.WHITE)
	host.add_child(card_label)
	assert_eq(label.get_theme_font_size("font_size"), 12)
	assert_eq(card_label.get_theme_font_size("font_size"), 20)
	_change_setting("text_scale", 1.3)
	EraTheme.rescale_tree(host)
	assert_eq(label.get_theme_font_size("font_size"), 16, "rescale_tree follows the new size")
	assert_eq(rich.get_theme_font_size("normal_font_size"), 17)
	assert_eq(card_label.get_theme_font_size("font_size"), 26, "crisis cards read the size")
	var style := EraStyle.for_era(1)
	assert_almost_eq(style.text_scale, 1.3, 0.0001)
	assert_eq(style.scaled(10), 13, "custom-drawn widgets scale through the style")
	var meter := MeterBar.new()
	meter.metric_key = "epistemic_trust"
	host.add_child(meter)
	assert_gt(meter.custom_minimum_size.y, float(MeterBar.SIZES[1].y), "meters grow taller for larger text")
	_change_setting("text_scale", 1.0)
	EraTheme.rescale_tree(host)
	assert_eq(label.get_theme_font_size("font_size"), 12)


# --- Color-blind friendly colors --------------------------------------------------------

func test_colorblind_changes_good_and_bad_in_every_era() -> void:
	var normal := {}
	for era in [1, 2, 3]:
		var s := EraStyle.for_era(era)
		normal[era] = {"good": s.good, "bad": s.bad, "warn": s.warn, "critical": s.critical}
		assert_false(s.colorblind)
	_change_setting("colorblind", true)
	for era in [1, 2, 3]:
		var cb := EraStyle.for_era(era)
		assert_true(cb.colorblind, "era %d variant" % era)
		assert_ne(cb.good, normal[era]["good"], "era %d good" % era)
		assert_ne(cb.bad, normal[era]["bad"], "era %d bad" % era)
		assert_ne(cb.critical, normal[era]["critical"], "era %d critical" % era)
		assert_gt(cb.good.b, cb.good.r, "era %d: better is blue" % era)
		assert_gt(cb.bad.r, cb.bad.b, "era %d: worse is orange" % era)
		assert_gt(cb.bad.g, cb.bad.b, "era %d: orange, not red or magenta" % era)
		assert_gt(absf(cb.warn.get_luminance() - cb.critical.get_luminance()), 0.1, "era %d: warn and critical differ in lightness" % era)
		var theme := EraTheme.get_theme(era)
		assert_eq(theme.get_color("good", "Era"), cb.good, "era %d theme publishes the variant" % era)
		assert_eq(theme.get_constant("colorblind", "Era"), 1)
		assert_eq(cb.metric_color("epistemic_trust"), EraStyle.for_era(era).metric_color("epistemic_trust"), "metric colors stay")
	_change_setting("colorblind", false)
	for era in [1, 2, 3]:
		assert_eq(EraStyle.for_era(era).good, normal[era]["good"], "era %d back to its palette" % era)


func test_colorblind_reaches_the_widgets() -> void:
	var ceo := CeoLens.new()
	host.add_child(ceo)
	var citizens := CitizenLens.new()
	host.add_child(citizens)
	assert_eq(ceo._change_color(2.0, 0), CeoLens.UP)
	assert_eq(citizens._tone_color("accent"), CitizenLens.LIGHT["accent"])
	_change_setting("colorblind", true)
	host.theme = EraTheme.get_theme(1)
	await wait_frames(2)
	assert_eq(EraStyle.for_era(1).good, EraStyle.COLORBLIND[1]["good"])
	assert_eq(ceo._change_color(2.0, 0), CeoLens.UP_COLORBLIND, "the trading terminal drops red and green")
	assert_eq(ceo._change_color(-2.0, 0), CeoLens.DOWN_COLORBLIND)
	assert_eq(citizens._tone_color("accent"), CitizenLens.LIGHT_COLORBLIND["good"], "the Commons too")
	assert_eq(citizens._tone_color("warn", "_soft"), CitizenLens.LIGHT_COLORBLIND["bad_soft"])
	var strip := VitalsStrip.new()
	strip.size = Vector2(400, 64)
	strip.set_compact(true)
	host.add_child(strip)
	strip.set_values({"alignment_drift": 40.0})
	strip.set_preview({"alignment_drift": 5.0})
	assert_eq(strip._tone(EraTheme.style_of(strip), "alignment_drift"), EraStyle.COLORBLIND[1]["bad"], "previews use the variant")


# --- Settings dialog --------------------------------------------------------------------

func test_settings_dialog_reads_and_writes_game_settings() -> void:
	var dialog := SettingsDialog.new()
	host.add_child(dialog)
	settings.set_value("music_volume", 0.25)
	dialog.open()
	assert_true(dialog.visible)
	var music := dialog.find_child("MusicVolume", true, false).find_child("Slider", true, false) as HSlider
	assert_almost_eq(music.value, 0.25, 0.001, "opens with the stored values")
	var sizes: Array[Button] = []
	for i in GameSettings.TEXT_SCALES.size():
		sizes.append(dialog.find_child("TextSize%d" % i, true, false) as Button)
	assert_true(sizes[0].button_pressed, "normal text selected")
	sizes[2].pressed.emit()
	assert_almost_eq(float(settings.get_value("text_scale")), 1.3, 0.0001, "the third A is the largest text")
	assert_true(sizes[2].button_pressed)
	assert_false(sizes[0].button_pressed)
	(dialog.find_child("Colorblind", true, false) as CheckBox).button_pressed = true
	assert_true(bool(settings.get_value("colorblind")))
	(dialog.find_child("PlainLanguage", true, false) as CheckBox).button_pressed = true
	assert_true(bool(settings.get_value("plain_language")))
	(dialog.find_child("Effects", true, false) as CheckBox).button_pressed = false
	assert_false(bool(settings.get_value("effects")))
	(dialog.find_child("Vibration", true, false) as CheckBox).button_pressed = false
	assert_false(bool(settings.get_value("vibration")))
	var sound := dialog.find_child("SoundVolume", true, false).find_child("Slider", true, false) as HSlider
	sound.value = 0.35
	assert_almost_eq(float(settings.get_value("sound_volume")), 0.35, 0.001)
	music.value = 0.5
	assert_almost_eq(float(settings.get_value("music_volume")), 0.5, 0.001)
	assert_eq((dialog.find_child("SoundVolume", true, false).find_child("Value", true, false) as Label).text, "35%")
	var language := dialog.find_child("Language", true, false) as OptionButton
	assert_eq(language.item_count, 1, "English by default")
	dialog.set_languages([{"code": "en", "name": "English"}, {"code": "fr", "name": "Français"}])
	assert_eq(language.item_count, 2)
	language.select(1)
	language.item_selected.emit(1)
	assert_eq(String(settings.get_value("language")), "fr")
	settings.set_value("colorblind", false)
	assert_false((dialog.find_child("Colorblind", true, false) as CheckBox).button_pressed, "follows changes made elsewhere")
	(dialog.find_child("GlossaryButton", true, false) as Button).pressed.emit()
	assert_true(dialog.get_glossary().visible, "the glossary opens over the settings")
	dialog.get_glossary().close()
	var replay := [false]
	dialog.tutorial_requested.connect(func() -> void: replay[0] = true)
	var closed := [false]
	dialog.closed.connect(func() -> void: closed[0] = true)
	(dialog.find_child("TutorialButton", true, false) as Button).pressed.emit()
	assert_true(replay[0], "tutorial_requested emitted")
	assert_true(closed[0], "the dialog closes for the tutorial")
	assert_false(dialog.visible)


func test_settings_dialog_fits_a_phone() -> void:
	var dialog := SettingsDialog.new()
	host.add_child(dialog)
	dialog.set_compact(true)
	for scale in [1.0, 1.3]:
		_change_setting("text_scale", scale)
		for era_number in [1, 2, 3]:
			host.theme = EraTheme.get_theme(era_number)
			EraTheme.rescale_tree(host)
			dialog.open()
			await wait_frames(3)
			_assert_fits(host, PHONE.x, "settings, era %d at %d%%" % [era_number, roundi(scale * 100.0)])
	(dialog.find_child("GlossaryButton", true, false) as Button).pressed.emit()
	await wait_frames(3)
	_assert_fits(host, PHONE.x, "glossary over the settings")


# --- The dashboard with large text and plain words ---------------------------------------

func test_dashboard_fits_a_phone_with_large_text_and_plain_words() -> void:
	settings.set_value("text_scale", 1.3)
	settings.set_value("plain_language", true)
	settings.set_value("colorblind", true)
	EraTheme.invalidate()
	var dashboard: Control = DashboardScene.instantiate()
	tree.root.add_child(dashboard)
	await tree.process_frame
	_saved_root_size = tree.root.size
	tree.root.size = PHONE_PX
	dashboard.apply_layout(UiLayout.compute(Vector2(PHONE_PX), 2.625, true))
	await wait_frames(3)
	var width: float = dashboard.get_viewport_rect().size.x
	dashboard.start_campaign("GOVERNANCE_COUNCIL", 2076, false)
	await wait_frames(3)
	_assert_fits(dashboard, width, "crisis card, large text")
	dashboard.get_node("%DilemmaDialog").choose(DilemmaDeck.DEFER_ID)
	await wait_frames(2)
	for tab in ["act", "world", "lens", "news"]:
		dashboard.show_tab(tab)
		await wait_frames(2)
		_assert_fits(dashboard, width, tab + " tab, large text")
	dashboard.show_left_view("intel")
	dashboard.show_tab("lens")
	await wait_frames(2)
	_assert_fits(dashboard, width, "intel, large text")
	dashboard.queue_free()
	await tree.process_frame


func _assert_fits(root: Control, width: float, context: String) -> void:
	var overflowing: Array[String] = []
	for node in root.find_children("*", "Control", true, false):
		var control := node as Control
		if control.is_visible_in_tree() and control.get_global_rect().end.x > width + 0.5:
			overflowing.append("%s (%s) ends at %.0f" % [control.name, control.get_class(), control.get_global_rect().end.x])
	assert_eq(overflowing.size(), 0, "%s fits %.0f px: %s" % [context, width, ", ".join(overflowing.slice(0, 5))])
