class_name SettingsDialog
extends Control
## The player's settings, saved through GameSettings:
##   LLM       the language model On or Off (LLMSwitch), with what it is doing
##             now (bind_llm(); without a service the switch is greyed out)
##   Display   text size (three "A" buttons: 100%, 115%, 130%), color-blind
##             friendly colors, plain language, visual effects
##   Sound     effects and music volume, vibration
##   Language  the interface language (set_languages() lists the choices;
##             a note says the news stays English when another is picked)
##   Help      replay the tutorial (tutorial_requested), the glossary
##
##   settings.tutorial_requested.connect(_replay_tutorial)
##   settings.set_languages([{"code": "en", "name": "English"}, ...])
##   settings.bind_llm(llm)
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
var _llm: LLMService
var _llm_switch: LLMSwitch
var _llm_status: Label
var _language: OptionButton
var _language_note: Label
var _tutorial_button: Button
var _glossary_button: Button
var _done: Button
var _glossary: GlossaryDialog
var _section_titles: Array[Label] = []
var _section_icons: Array[TextureRect] = []
var _restyle_queued := false
var _relabel_queued := false


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

	_build_llm()
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
	elif what == NOTIFICATION_TRANSLATION_CHANGED and _panel != null and not _relabel_queued:
		_relabel_queued = true
		_relabel.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if visible and not _glossary.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func set_compact(compact: bool) -> void:
	_compact = compact
	if _glossary != null:
		_glossary.set_compact(compact)
	_apply_layout()


## Shows [param llm]'s state under the LLM switch and greys the switch out on
## a build without a backend.
func bind_llm(llm: LLMService) -> void:
	_llm = llm
	if _llm != null and not _llm.llm_status_changed.is_connected(_on_llm_status_changed):
		_llm.llm_status_changed.connect(_on_llm_status_changed)
	_sync_llm()


func get_llm_switch() -> LLMSwitch:
	return _llm_switch


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
	UiLayout.reflow_wrapped_buttons(_panel)


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

func _build_llm() -> void:
	var section := _section(I18n.mark("LLM"), "spark")
	var row := HBoxContainer.new()
	row.name = "LLMRow"
	row.add_theme_constant_override("separation", 8)
	row.add_child(_row_label(I18n.mark("Language model")))
	_llm_switch = LLMSwitch.new()
	_llm_switch.name = "LLMSwitch"
	_llm_switch.caption = ""
	row.add_child(_llm_switch)
	section.add_child(row)
	var note := Label.new()
	note.name = "LLMNote"
	note.text = "On: a language model plays the other factions, writes some of your crises and answers when you call a leader. Off: the built-in rules play them."
	note.theme_type_variation = "Caption"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(note)
	_llm_status = Label.new()
	_llm_status.name = "LLMStatus"
	# LLMStatusBadge.status_line() is already translated (gotcha 20).
	_llm_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_llm_status.theme_type_variation = "DimLabel"
	_llm_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section.add_child(_llm_status)
	_sync_llm()


func _build_display() -> void:
	var section := _section(I18n.mark("Display"), "layers")
	var size_row := HBoxContainer.new()
	size_row.name = "TextSize"
	size_row.add_theme_constant_override("separation", 8)
	var size_label := _row_label(I18n.mark("Text size"))
	size_row.add_child(size_label)
	var group := ButtonGroup.new()
	for i in GameSettings.TEXT_SCALES.size():
		var button := Button.new()
		button.name = "TextSize%d" % i
		button.text = "A"
		button.toggle_mode = true
		button.button_group = group
		button.theme_type_variation = "ChipButton"
		button.tooltip_text = _size_tip(i)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", TEXT_SIZE_SAMPLES[i])
		button.custom_minimum_size = Vector2(48, 44)
		button.pressed.connect(_set_setting.bind(float(GameSettings.TEXT_SCALES[i]), "text_scale"))
		size_row.add_child(button)
		_size_buttons.append(button)
	section.add_child(size_row)
	_colorblind = _check(section, I18n.mark("Color-blind friendly colors"),
		I18n.mark("Better is blue and worse is orange in every era, with clearer warnings."), "colorblind")
	_plain = _check(section, I18n.mark("Plain language"),
		I18n.mark("Everyday words instead of the model's jargon (drift becomes “off-script AI”)."), "plain_language")
	_effects = _check(section, I18n.mark("Visual effects"), I18n.mark("Glitches, animated backgrounds and the tearing era transition."),
		"effects")


func _build_sound() -> void:
	var section := _section(I18n.mark("Sound"), "disruption")
	var sound := _slider(section, I18n.mark("Effects volume"), "sound_volume")
	_sound = sound[0]
	_sound_value = sound[1]
	var music := _slider(section, I18n.mark("Music volume"), "music_volume")
	_music = music[0]
	_music_value = music[1]
	_vibration = _check(section, I18n.mark("Vibration"), I18n.mark("Short buzzes on swipes and alerts (phones)."), "vibration")


func _build_language() -> void:
	var section := _section(I18n.mark("Language"), "world")
	_language = OptionButton.new()
	_language.name = "Language"
	# Each language keeps its own name in every language.
	_language.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_language.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_language.custom_minimum_size = Vector2(0, 42)
	_language.fit_to_longest_item = false
	_language.item_selected.connect(func(index: int) -> void:
		_set_setting(String(_language.get_item_metadata(index)), "language"))
	section.add_child(_language)
	_language_note = Label.new()
	_language_note.name = "LanguageNote"
	_language_note.text = "News and history pages are written in English."
	_language_note.theme_type_variation = "Caption"
	_language_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_language_note.visible = false
	section.add_child(_language_note)
	_fill_languages()


func _build_help() -> void:
	var section := _section(I18n.mark("Help"), "book")
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


func _on_llm_status_changed(_online: bool, _provider: String) -> void:
	_sync_llm()


func _sync_llm() -> void:
	if _llm_switch == null:
		return
	_llm_switch.set_available(_llm != null and _llm.has_backend())
	_llm_status.text = LLMStatusBadge.status_line(_llm)


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
	_sync_llm()


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
	# The generated news and history stay English in every language.
	if _language_note != null:
		_language_note.visible = I18n.resolve(current) != I18n.SOURCE


# --- Style ----------------------------------------------------------------------------------

func _restyle() -> void:
	_restyle_queued = false
	_style = EraTheme.style_of(self)
	var s := _style
	_shade.color = Color(s.shade, maxf(s.shade.a, 0.7))
	for icon in _section_icons:
		icon.self_modulate = s.accent
	for label in _section_titles:
		label.text = s.label(tr(String(label.get_meta("title", label.text))))


## Text composed from translated parts, set again when the language changes.
func _relabel() -> void:
	_relabel_queued = false
	for i in _size_buttons.size():
		_size_buttons[i].tooltip_text = _size_tip(i)
	_sync_llm()
	_restyle()


func _size_tip(index: int) -> String:
	return "%s (%d%%)" % [tr(String(TEXT_SIZE_NAMES[index])), roundi(float(GameSettings.TEXT_SCALES[index]) * 100.0)]


func _apply_layout() -> void:
	if _panel == null:
		return
	_panel.custom_minimum_size = Vector2(UiLayout.panel_width(size.x if size.x > 1.0 else get_viewport_rect().size.x,
		DESKTOP_WIDTH, _compact), 0)
	UiLayout.set_overlay_margin(_frame, _compact)
	_done.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _compact else Control.SIZE_SHRINK_END
	_llm_switch.set_compact(_compact)
	for button in [_tutorial_button, _glossary_button, _done]:
		(button as Control).custom_minimum_size.y = 46 if _compact else 42
