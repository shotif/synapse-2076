class_name RoleSelect
extends Control
## Campaign setup overlay: choose one of the four asymmetric perspectives
## (PRD section 1), a seed, and whether to spectate (AI plays your role).

signal start_requested(role: String, seed_value: int, spectate: bool)
signal llm_settings_requested

var selected_role := SimConstants.GOVERNANCE
var _cards := {}
var _seed_edit: LineEdit
var _spectate_check: CheckBox
var _llm_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(CyberPalette.BG, 0.94)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "OverlayPanel"
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.theme_type_variation = "HeaderTitle"
	title.add_theme_font_size_override("font_size", 34)
	title.text = "[SYNAPSE-2076]"
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.theme_type_variation = "DimLabel"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.text = "Hard-systems simulation of AI, energy, labor and alignment // 100 semi-annual turns, 2026-2076.\nSelect your perspective. The other three factions act autonomously (LLM when online, heuristic otherwise)."
	box.add_child(subtitle)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	for role in SimConstants.FACTION_ORDER:
		var card := _role_card(role)
		_cards[role] = card
		grid.add_child(card)

	var options := HBoxContainer.new()
	options.add_theme_constant_override("separation", 14)
	var seed_label := Label.new()
	seed_label.text = "SEED"
	seed_label.theme_type_variation = "DimLabel"
	options.add_child(seed_label)
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(int(ProjectSettings.get_setting("synapse/simulation/default_seed", 2076)))
	_seed_edit.custom_minimum_size = Vector2(120, 0)
	options.add_child(_seed_edit)
	var randomize_button := Button.new()
	randomize_button.text = "RANDOM"
	randomize_button.pressed.connect(func(): _seed_edit.text = str(randi() % 1000000))
	options.add_child(randomize_button)
	_spectate_check = CheckBox.new()
	_spectate_check.text = "SPECTATE (AI plays your role)"
	options.add_child(_spectate_check)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_child(spacer)
	_llm_label = Label.new()
	_llm_label.theme_type_variation = "DimLabel"
	options.add_child(_llm_label)
	var llm_button := Button.new()
	llm_button.text = "LLM SETTINGS"
	llm_button.pressed.connect(func(): llm_settings_requested.emit())
	options.add_child(llm_button)
	box.add_child(options)

	var start := Button.new()
	start.theme_type_variation = "AccentButton"
	start.text = "[ INITIALIZE CAMPAIGN ]"
	start.custom_minimum_size = Vector2(0, 46)
	start.pressed.connect(_on_start_pressed)
	box.add_child(start)
	select_role(selected_role)


func select_role(role: String) -> void:
	selected_role = role
	for other in _cards:
		(_cards[other] as PanelContainer).theme_type_variation = "CardPanelSelected" if other == role else "CardPanel"


func set_llm_status(text: String) -> void:
	if _llm_label != null:
		_llm_label.text = text


func set_seed(seed_value: int) -> void:
	_seed_edit.text = str(seed_value)


func _role_card(role: String) -> PanelContainer:
	var info: Dictionary = SimConstants.ROLE_INFO[role]
	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	card.custom_minimum_size = Vector2(470, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			select_role(role))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var name_label := Label.new()
	name_label.text = String(info["title"])
	name_label.add_theme_font_override("font", CyberPalette.SANS_BOLD)
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", CyberPalette.faction_color(role))
	box.add_child(name_label)
	var tagline := Label.new()
	tagline.text = String(info["tagline"])
	tagline.add_theme_font_size_override("font_size", 13)
	box.add_child(tagline)
	var currencies: Array[String] = []
	for key in FactionRegistry.resource_info_for(role):
		currencies.append(UiFormat.resource_label(role, key))
	for line in ["CURRENCIES: " + ", ".join(currencies), "OBJECTIVE: " + String(info["objective"]), "LOSS: " + String(info["loss"])]:
		var label := Label.new()
		label.text = line
		label.theme_type_variation = "DimLabel"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 11)
		box.add_child(label)
	for child in box.get_children():
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card


func _on_start_pressed() -> void:
	var seed_value := int(_seed_edit.text) if _seed_edit.text.is_valid_int() else hash(_seed_edit.text)
	start_requested.emit(selected_role, seed_value, _spectate_check.button_pressed)
