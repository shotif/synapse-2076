class_name SettingsDialog
extends Control
## The player's settings, saved through GameSettings:
##   Display   text size (three "A" buttons: 100%, 115%, 130%), color-blind
##             friendly colors, plain language, visual effects
##   Sound     effects and music volume, vibration
##   Language  the interface language (set_languages() lists the choices)
##   Help      replay the tutorial (tutorial_requested), the glossary
##
##   settings.tutorial_requested.connect(_replay_tutorial)
##   settings.set_languages([{"code": "en", "name": "English"}, ...])
##   settings.open()
##
## Every control writes its GameSettings key at once (GameSettings.changed
## tells the rest of the interface), and follows changes made elsewhere.
## Built on UiLayout.build_overlay(): centered on desktop, full width and
## scrolling on phones (set_compact). Era-styled.

signal closed
## The player asked to play the guided first campaign again.
signal tutorial_requested

const DESKTOP_WIDTH := 580.0
const DEFAULT_LANGUAGES := [{"code": "en", "name": "English"}]
const TEXT_SIZE_NAMES := ["Normal text", "Large text", "Largest text"]
## Font sizes of the three "A" buttons (they show the sizes, so they stay fixed).
const TEXT_SIZE_SAMPLES := [13, 17, 21]

var _compact := false
var _style: EraStyle
var _languages: Array = DEFAULT_LANGUAGES.duplicate(true)
var _frame: MarginContainer
var _shade: ColorRect
var _panel: PanelContainer
var _box: VBoxContainer
var _size_buttons: Array[Button] = []
var _colorblind: CheckBox
var _plain: CheckBox
var _effects: CheckBox
var _sound: HSlider
var _sound_value: Label
var _music: HSlider
var _music_value: Label
var _vibration: CheckBox
var _language: OptionButton
var _tutorial_button: Button
var _glossary_button: Button
var _done: Button
var _glossary: GlossaryDialog
var _section_titles: Array[Label] = []
var _section_icons: Array[TextureRect] = []
var _restyle_queued := false


func _ready() -> void:
	_frame = UiLayout.build_overlay(self, Color(0, 0, 0, 0.7))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade = get_child(0) as ColorRect
	_panel = PanelContainer.new()
	_panel.name = "SettingsPanel"
	_panel.theme_type_variation = "OverlayPanel"
	_frame.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 14)
	_panel.add_child(_box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "Settings"
	title.theme_type_variation = "DisplayTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_icon := Button.new()
	close_icon.name = "CloseIcon"
	close_icon.icon = Glyphs.texture("close", 18)
	close_icon.theme_type_variation = "GhostButton"
	close_icon.tooltip_text = "Close"
	close_icon.custom_minimum_size = Vector2(44, 44)
	close_icon.pressed.connect(close)
	head.add_child(close_icon)
	_box.add_child(head)

	_build_display()
	_build_sound()
	_build_language()
	_build_help()

	_done = Button.new()
	_done.name = "DoneButton"
	_done.text = "Done"
	_done.theme_type_variation = "AccentButton"
	_done.custom_minimum_size = Vector2(120, 42)
	_done.size_flags_horizontal = Control.SIZE_SHRINK_END
	_done.pressed.connect(close)
	_box.add_child(_done)

	_glossary = GlossaryDialog.new()
	_glossary.name = "Glossary"
	add_child(_glossary)
	_glossary.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	UiLayout.pass_touch_through(_panel)
	resized.connect(_apply_layout)
	GameSettings.instance().changed.connect(_on_setting_changed)
	visible = false
	z_index = 2


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _panel != null and EraTheme.style_of(self) != _style and not _restyle_queued:
		_restyle_queued = true
		_restyle.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if visible and not _glossary.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func set_compact(compact: bool) -> void:
	_compact = compact
	if _glossary != null:
		_glossary.set_compact(compact)
	_apply_layout()


## The languages the interface offers: [{code, name}] (code "" can stand for
## "follow the system"). Defaults to English only.
func set_languages(entries: Array) -> void:
	var clean := []
	for item in entries:
		if item is Dictionary and (item as Dictionary).has("code"):
			clean.append({"code": String(item["code"]), "name": String(item.get("name", item["code"]))})
	_languages = clean if not clean.is_empty() else DEFAULT_LANGUAGES.duplicate(true)
	if _language != null:
		_fill_languages()


func open() -> void:
	_restyle()
	_sync()
	_apply_layout()
	visible = true
	(get_node("OverlayScroll") as ScrollContainer).scroll_vertical = 0


func close() -> void:
	if _glossary != null and _glossary.visible:
		_glossary.close()
	if not visible:
		return
	# Volumes are saved when a drag ends; make sure the last value is on disk.
	GameSettings.instance().save_settings()
	visible = false
	closed.emit()


func get_glossary() -> GlossaryDialog:
	return _glossary


# --- Building -------------------------------------------------------------------------

func _build_display() -> void:
	var section := _section("Display", "layers")
	var size_row := HBoxContainer.new()
	size_row.name = "TextSize"
	size_row.add_theme_constant_override("separation", 8)
	var size_label := _row_label("Text size")
	size_row.add_child(size_label)
	var group := ButtonGroup.new()
	for i in GameSettings.TEXT_SCALES.size():
		var button := Button.new()
		button.name = "TextSize%d" % i
		button.text = "A"
		button.toggle_mode = true
		button.button_group = group
		button.theme_type_variation = "ChipButton"
		button.tooltip_text = "%s (%d%%)" % [TEXT_SIZE_NAMES[i], roundi(float(GameSettings.TEXT_SCALES[i]) * 100.0)]
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", TEXT_SIZE_SAMPLES[i])
		button.custom_minimum_size = Vector2(48, 44)
		button.pressed.connect(_set_setting.bind(float(GameSettings.TEXT_SCALES[i]), "text_scale"))
		size_row.add_child(button)
		_size_buttons.append(button)
	section.add_child(size_row)
	_colorblind = _check(section, "Color-blind friendly colors", "Better is blue and worse is orange in every era, with clearer warnings.",
		"colorblind")
	_plain = _check(section, "Plain language", "Everyday words instead of the model's jargon (drift becomes “off-script AI”).",
		"plain_language")
	_effects = _check(section, "Visual effects", "Glitches, animated backgrounds and the tearing era transition.", "effects")


func _build_sound() -> void:
	var section := _section("Sound", "disruption")
	var sound := _slider(section, "Effects volume", "sound_volume")
	_sound = sound[0]
	_sound_value = sound[1]
	var music := _slider(section, "Music volume", "music_volume")
	_music = music[0]
	_music_value = music[1]
	_vibration = _check(section, "Vibration", "Short buzzes on swipes and alerts (phones).", "vibration")


func _build_language() -> void:
	var section := _section("Language", "world")
	_language = OptionButton.new()
	_language.name = "Language"
	_language.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_language.custom_minimum_size = Vector2(0, 42)
	_language.fit_to_longest_item = false
	_language.item_selected.connect(func(index: int) -> void:
		_set_setting(String(_language.get_item_metadata(index)), "language"))
	section.add_child(_language)
	_fill_languages()


func _build_help() -> void:
	var section := _section("Help", "book")
	var row := HFlowContainer.new()
	row.name = "HelpButtons"
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	_tutorial_button = Button.new()
	_tutorial_button.name = "TutorialButton"
	_tutorial_button.text = "Replay the tutorial"
	_tutorial_button.icon = Glyphs.texture("play", 14)
	_tutorial_button.custom_minimum_size = Vector2(0, 42)
	_tutorial_button.pressed.connect(func() -> void:
		close()
		tutorial_requested.emit())
	row.add_child(_tutorial_button)
	_glossary_button = Button.new()
	_glossary_button.name = "GlossaryButton"
	_glossary_button.text = "Glossary"
	_glossary_button.icon = Glyphs.texture("book", 16)
	_glossary_button.custom_minimum_size = Vector2(0, 42)
	_glossary_button.pressed.connect(func() -> void: _glossary.open())
	row.add_child(_glossary_button)
	section.add_child(row)


## A titled card; returns the box its rows go in.
func _section(title: String, glyph: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.name = title + "Section"
	card.theme_type_variation = "CardPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var icon := TextureRect.new()
	icon.texture = Glyphs.texture(glyph, 16)
	icon.custom_minimum_size = Vector2(16, 16)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(icon)
	_section_icons.append(icon)
	var label := Label.new()
	label.text = title
	label.set_meta("title", title)
	label.theme_type_variation = "PanelTitle"
	head.add_child(label)
	_section_titles.append(label)
	box.add_child(head)
	_box.add_child(card)
	return box


func _row_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## A check box with a dim hint under it, bound to [param key].
func _check(parent: Control, text: String, hint: String, key: String) -> CheckBox:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var check := CheckBox.new()
	check.name = key.to_pascal_case()
	check.text = text
	check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	check.custom_minimum_size = Vector2(0, 40)
	check.toggled.connect(func(pressed: bool) -> void: _set_setting(pressed, key))
	box.add_child(check)
	var note := Label.new()
	note.text = hint
	note.theme_type_variation = "Caption"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	parent.add_child(box)
	return check


## A labelled 0-100% slider bound to [param key]: [HSlider, value label].
func _slider(parent: Control, text: String, key: String) -> Array:
	var row := HBoxContainer.new()
	row.name = key.to_pascal_case()
	row.add_theme_constant_override("separation", 10)
	var label := _row_label(text)
	label.size_flags_stretch_ratio = 0.8
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = "Slider"
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(110, 36)
	row.add_child(slider)
	var value := Label.new()
	value.name = "Value"
	value.theme_type_variation = "ValueLabel"
	value.custom_minimum_size = Vector2(46, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(value)
	slider.value_changed.connect(func(amount: float) -> void:
		value.text = "%d%%" % roundi(amount * 100.0)
		GameSettings.instance().set_value(key, amount, false))
	slider.drag_ended.connect(func(_changed: bool) -> void: GameSettings.instance().save_settings())
	parent.add_child(row)
	return [slider, value]


func _fill_languages() -> void:
	_language.clear()
	for i in _languages.size():
		var item: Dictionary = _languages[i]
		_language.add_item(String(item["name"]), i)
		_language.set_item_metadata(i, String(item["code"]))
	_sync_language()


# --- Values ---------------------------------------------------------------------------------

## Writes [param key]; argument order suits Callable.bind(key) after the value.
func _set_setting(value: Variant, key: String) -> void:
	GameSettings.instance().set_value(key, value)


func _on_setting_changed(_key: String, _value: Variant) -> void:
	if _panel != null:
		_sync()


## Puts every control in step with GameSettings without emitting changes.
func _sync() -> void:
	var settings := GameSettings.instance()
	var scale := float(settings.get_value("text_scale"))
	for i in _size_buttons.size():
		_size_buttons[i].set_pressed_no_signal(is_equal_approx(float(GameSettings.TEXT_SCALES[i]), scale))
	_colorblind.set_pressed_no_signal(bool(settings.get_value("colorblind")))
	_plain.set_pressed_no_signal(bool(settings.get_value("plain_language")))
	_effects.set_pressed_no_signal(bool(settings.get_value("effects")))
	_vibration.set_pressed_no_signal(bool(settings.get_value("vibration")))
	_sound.set_value_no_signal(float(settings.get_value("sound_volume")))
	_sound_value.text = "%d%%" % roundi(_sound.value * 100.0)
	_music.set_value_no_signal(float(settings.get_value("music_volume")))
	_music_value.text = "%d%%" % roundi(_music.value * 100.0)
	_sync_language()


func _sync_language() -> void:
	var current := String(GameSettings.value("language"))
	var index := -1
	for i in _language.item_count:
		if String(_language.get_item_metadata(i)) == current:
			index = i
	if index < 0:
		# Unset ("" = the system's language): show the system's language if listed.
		var system := OS.get_locale_language()
		for i in _language.item_count:
			if String(_language.get_item_metadata(i)) == system:
				index = i
	_language.select(maxi(index, 0) if _language.item_count > 0 else -1)


# --- Style ----------------------------------------------------------------------------------

func _restyle() -> void:
	_restyle_queued = false
	_style = EraTheme.style_of(self)
	var s := _style
	_shade.color = Color(s.shade, maxf(s.shade.a, 0.7))
	for icon in _section_icons:
		icon.self_modulate = s.accent
	for label in _section_titles:
		label.text = s.label(String(label.get_meta("title", label.text)))


func _apply_layout() -> void:
	if _panel == null:
		return
	_panel.custom_minimum_size = Vector2(UiLayout.panel_width(size.x if size.x > 1.0 else get_viewport_rect().size.x,
		DESKTOP_WIDTH, _compact), 0)
	UiLayout.set_overlay_margin(_frame, _compact)
	_done.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _compact else Control.SIZE_SHRINK_END
	for button in [_tutorial_button, _glossary_button, _done]:
		(button as Control).custom_minimum_size.y = 46 if _compact else 42
