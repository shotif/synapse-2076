class_name RoleSelect
extends Control
## Campaign setup overlay: choose one of the four asymmetric perspectives
## (PRD section 1), a seed, and whether to spectate (AI plays your role).
## Campaigns open in Era I, so this screen wears the Era I look. On phones
## the roles stack in one column and only the selected role shows its
## details.

signal start_requested(role: String, seed_value: int, spectate: bool)
signal llm_settings_requested

const CARD_WIDTH := 470.0
## A press that moves further than this (px) is a scroll, not a role pick.
const TAP_SLOP := 12.0
## Height of the bar that pins the start button to the bottom on phones.
const STICKY_HEIGHT := 62.0
const SUBTITLE := "A hard-systems simulation of AI, energy, labor and alignment: 100 half-year turns, 2026–2076.\nPick a perspective. The other three factions act on their own (an LLM when one is online, heuristics otherwise)."
const SUBTITLE_COMPACT := "AI, energy, labor and alignment: 100 turns, 2026–2076. Pick a perspective; the other three factions act on their own."

var selected_role := SimConstants.GOVERNANCE
var _compact := false
var _cards := {}
var _details := {}
var _taglines: Array[Label] = []
var _frame: MarginContainer
var _scroll: ScrollContainer
var _panel: PanelContainer
var _box: VBoxContainer
var _start: Button
var _sticky: PanelContainer
var _grid: GridContainer
var _options: HFlowContainer
var _title: Label
var _subtitle: Label
var _seed_edit: LineEdit
var _spectate_check: CheckBox
var _llm_label: Label
var _fullscreen_button: Button
var _press_position := Vector2.INF
var _marks := {}
var _names := {}
var _era := 0


func _ready() -> void:
	_frame = UiLayout.build_overlay(self, Color(0, 0, 0, 0.96))
	_scroll = get_node("OverlayScroll")
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "OverlayPanel"
	_frame.add_child(_panel)
	var box := VBoxContainer.new()
	_box = box
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)

	_title = Label.new()
	_title.theme_type_variation = "HeaderTitle"
	_title.add_theme_font_size_override("font_size", 34)
	_title.text = "SYNAPSE-2076"
	box.add_child(_title)
	_subtitle = Label.new()
	_subtitle.theme_type_variation = "DimLabel"
	_subtitle.add_theme_font_size_override("font_size", 13)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.text = SUBTITLE
	box.add_child(_subtitle)

	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	box.add_child(_grid)
	for role in SimConstants.FACTION_ORDER:
		var card := _role_card(role)
		_cards[role] = card
		_grid.add_child(card)

	var options := HFlowContainer.new()
	_options = options
	options.add_theme_constant_override("h_separation", 14)
	options.add_theme_constant_override("v_separation", 10)
	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_label.theme_type_variation = "DimLabel"
	options.add_child(seed_label)
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(int(ProjectSettings.get_setting("synapse/simulation/default_seed", 2076)))
	_seed_edit.custom_minimum_size = Vector2(120, 0)
	options.add_child(_seed_edit)
	var randomize_button := Button.new()
	randomize_button.text = "Random"
	randomize_button.pressed.connect(func(): _seed_edit.text = str(randi() % 1000000))
	options.add_child(randomize_button)
	_spectate_check = CheckBox.new()
	_spectate_check.text = "Spectate (the AI plays your role)"
	options.add_child(_spectate_check)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_child(spacer)
	_llm_label = Label.new()
	_llm_label.theme_type_variation = "DimLabel"
	options.add_child(_llm_label)
	var llm_button := Button.new()
	llm_button.text = "AI settings"
	llm_button.pressed.connect(func(): llm_settings_requested.emit())
	options.add_child(llm_button)
	# Browsers on phones lose a sixth of the screen to their own toolbars.
	_fullscreen_button = Button.new()
	_fullscreen_button.text = "Full screen"
	_fullscreen_button.visible = OS.has_feature("web")
	_fullscreen_button.pressed.connect(_toggle_fullscreen)
	options.add_child(_fullscreen_button)
	box.add_child(options)

	_start = Button.new()
	_start.theme_type_variation = "AccentButton"
	_start.text = "Start campaign"
	_start.custom_minimum_size = Vector2(0, 46)
	_start.pressed.connect(_on_start_pressed)
	box.add_child(_start)
	# Phones: the start button stays on screen below the scrolling role list.
	_sticky = PanelContainer.new()
	_sticky.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_sticky.offset_top = -STICKY_HEIGHT
	_sticky.visible = false
	add_child(_sticky)
	_scroll.scroll_started.connect(func(): _press_position = Vector2.INF)
	UiLayout.pass_touch_through(_panel)
	resized.connect(_apply_layout)
	_restyle()
	select_role(selected_role)
	_apply_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _sticky != null and EraTheme.style_of(self).era != _era:
		_restyle()


func _restyle() -> void:
	var s := EraTheme.style_of(self)
	_era = s.era
	(get_child(0) as ColorRect).color = Color(s.bg, 0.96)
	var bar := EraTheme.box(s.bg, s.border_strong, 0, 0, 8, 8)
	bar.border_width_top = 1
	_sticky.add_theme_stylebox_override("panel", bar)
	for role in _marks:
		(_marks[role] as TextureRect).texture = _role_mark(s, role)
		(_names[role] as Label).add_theme_font_override("font", s.font_ui_bold)
		(_names[role] as Label).add_theme_color_override("font_color", s.text_bright)


func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	_apply_layout()


func select_role(role: String) -> void:
	selected_role = role
	for other in _cards:
		(_cards[other] as PanelContainer).theme_type_variation = "CardPanelSelected" if other == role else "CardPanel"
		# Phones show the objective and loss conditions of the selected role only.
		for label in _details.get(other, []):
			(label as Control).visible = not _compact or other == role


func set_llm_status(text: String) -> void:
	if _llm_label != null:
		_llm_label.text = text
		_fit_options_row()


func set_seed(seed_value: int) -> void:
	_seed_edit.text = str(seed_value)


func _apply_layout() -> void:
	if _panel == null:
		return
	_grid.columns = 1 if _compact else 2
	var width := UiLayout.panel_width(size.x, 0.0, _compact)
	_panel.custom_minimum_size = Vector2(width if _compact else 0.0, 0)
	for role in _cards:
		(_cards[role] as Control).custom_minimum_size = Vector2(0.0 if _compact else CARD_WIDTH, 0)
	for tagline in _taglines:
		tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if _compact else TextServer.AUTOWRAP_OFF
	_title.add_theme_font_size_override("font_size", 26 if _compact else 34)
	_subtitle.add_theme_font_size_override("font_size", 12 if _compact else 13)
	_subtitle.text = SUBTITLE_COMPACT if _compact else SUBTITLE
	var start_parent: Node = _sticky if _compact else _box
	if _start.get_parent() != start_parent:
		_start.reparent(start_parent, false)
	_sticky.visible = _compact
	_scroll.offset_bottom = -STICKY_HEIGHT if _compact else 0.0
	# Desktop keeps the original two-line subtitle; phones wrap it to the panel.
	_subtitle.custom_minimum_size = Vector2.ZERO
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if _compact else TextServer.AUTOWRAP_OFF
	UiLayout.set_overlay_margin(_frame, _compact)
	_fit_options_row()
	select_role(selected_role)


## Desktop keeps the options on one line; phones let them wrap.
func _fit_options_row() -> void:
	if _options == null:
		return
	var width := 0.0
	if not _compact:
		var count := 0
		for child in _options.get_children():
			if (child as Control).visible:
				width += (child as Control).get_combined_minimum_size().x
				count += 1
		width += _options.get_theme_constant("h_separation") * maxi(count - 1, 0)
	_options.custom_minimum_size = Vector2(width, 0)


func _toggle_fullscreen() -> void:
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _role_card(role: String) -> PanelContainer:
	var info: Dictionary = SimConstants.ROLE_INFO[role]
	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Pick on release, and only when the finger did not drag (a drag scrolls the list).
	card.gui_input.connect(func(event: InputEvent):
		if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
			return
		if event.pressed:
			_press_position = event.global_position
		elif _press_position != Vector2.INF and event.global_position.distance_to(_press_position) <= TAP_SLOP:
			_press_position = Vector2.INF
			select_role(role))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var mark := TextureRect.new()
	mark.custom_minimum_size = Vector2(40, 40)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(mark)
	_marks[role] = mark
	var name_label := Label.new()
	name_label.text = UiFormat.role_title(role)
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(name_label)
	_names[role] = name_label
	box.add_child(head)
	var tagline := Label.new()
	tagline.text = String(info["tagline"])
	tagline.add_theme_font_size_override("font_size", 13)
	box.add_child(tagline)
	_taglines.append(tagline)
	var currencies: Array[String] = []
	for key in FactionRegistry.resource_info_for(role):
		currencies.append(UiFormat.resource_label(role, key))
	var details: Array = []
	for line in ["Currencies · " + ", ".join(currencies), "Objective · " + String(info["objective"]), "Loss · " + String(info["loss"])]:
		var label := Label.new()
		label.text = line
		label.theme_type_variation = "DimLabel"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 11)
		box.add_child(label)
		details.append(label)
	_details[role] = details
	for child in box.find_children("*", "Control", true, false):
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card


## The faction's glyph on a tile in its color.
func _role_mark(s: EraStyle, role: String) -> Texture2D:
	return Glyphs.tile(Glyphs.for_faction(role), 40, s.faction_color(role), s.bg, 10 if s.era != 3 else 18, 0.6)


func _on_start_pressed() -> void:
	var seed_value := int(_seed_edit.text) if _seed_edit.text.is_valid_int() else hash(_seed_edit.text)
	start_requested.emit(selected_role, seed_value, _spectate_check.button_pressed)
