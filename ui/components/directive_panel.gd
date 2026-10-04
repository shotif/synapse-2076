class_name DirectivePanel
extends PanelContainer
## Asymmetric action allocation grid (PRD section 8.2, right column).
##
## Shows the player's currencies, the crisis-card resolution status and the
## role's directive catalog. Each selected directive has an intensity slider
## (1.0x-2.0x of its base cost, with diminishing returns on effect). The
## Execute button stays locked until the crisis card is resolved and the
## combined spend is affordable. The compact variant (phone ACT tab) puts the
## currencies in two columns and enlarges every touch target.

signal execute_requested(directives: Array)
signal review_crisis_requested

var max_directives := 2

var _role := ""
var _resources := {}
var _actions: Array = []
var _rows := {}
var _crisis_option_id := ""
var _crisis_cost := {}
var _interactive := false
var _compact := false

var _title: Label
var _directives_title: Label
var _resource_box: GridContainer
var _crisis_label: RichTextLabel
var _review_button: Button
var _list: VBoxContainer
var _summary_label: Label
var _message_label: Label
var _execute_button: Button


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_title = Label.new()
	_title.theme_type_variation = "PanelTitle"
	_title.text = "ACTION / DIRECTIVE CONTROL PANEL"
	root.add_child(_title)

	_resource_box = GridContainer.new()
	_resource_box.columns = 1
	_resource_box.add_theme_constant_override("h_separation", 14)
	_resource_box.add_theme_constant_override("v_separation", 3)
	root.add_child(_resource_box)
	root.add_child(HSeparator.new())

	var crisis_row := HBoxContainer.new()
	_crisis_label = RichTextLabel.new()
	_crisis_label.bbcode_enabled = true
	_crisis_label.fit_content = true
	_crisis_label.scroll_active = false
	_crisis_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crisis_row.add_child(_crisis_label)
	_review_button = Button.new()
	_review_button.text = "CRISIS"
	_review_button.tooltip_text = "Re-open the crisis card"
	_review_button.pressed.connect(func(): review_crisis_requested.emit())
	crisis_row.add_child(_review_button)
	root.add_child(crisis_row)

	_directives_title = Label.new()
	_directives_title.theme_type_variation = "DimLabel"
	_directives_title.text = "DIRECTIVES (select up to %d, drag to set intensity)" % max_directives
	root.add_child(_directives_title)

	var scroll := ScrollContainer.new()
	scroll.name = "DirectiveScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	_summary_label = Label.new()
	_summary_label.theme_type_variation = "DimLabel"
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_summary_label)
	_message_label = Label.new()
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.add_theme_color_override("font_color", CyberPalette.CRIMSON)
	_message_label.add_theme_font_size_override("font_size", 12)
	root.add_child(_message_label)

	_execute_button = Button.new()
	_execute_button.theme_type_variation = "AccentButton"
	_execute_button.text = "[ EXECUTE DIRECTIVES ]"
	_execute_button.custom_minimum_size = Vector2(0, 40)
	_execute_button.pressed.connect(_on_execute_pressed)
	root.add_child(_execute_button)
	_update_state()


## Populates the panel for a new player phase (SimulationEngine.get_player_context()).
func setup(context: Dictionary) -> void:
	_role = String(context.get("role", ""))
	_resources = (context.get("resources", {}) as Dictionary).duplicate()
	_actions = context.get("actions", [])
	max_directives = int(context.get("max_directives", max_directives))
	_crisis_option_id = ""
	_crisis_cost = {}
	_message_label.text = ""
	_rebuild_resources()
	_rebuild_directives()
	set_crisis_status("[color=%s]CRISIS PENDING[/color] - resolve the crisis card to unlock directives." % CyberPalette.hex(CyberPalette.AMBER))
	_update_state()


func set_interactive(enabled: bool) -> void:
	_interactive = enabled
	_update_state()


func set_compact(compact: bool) -> void:
	if _compact == compact and _title != null:
		return
	_compact = compact
	if _title == null:
		return
	_resource_box.columns = 2 if compact else 1
	_directives_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if compact else TextServer.AUTOWRAP_OFF
	_execute_button.custom_minimum_size = Vector2(0, 46 if compact else 40)
	_review_button.custom_minimum_size = Vector2(76, 40) if compact else Vector2.ZERO
	_update_title()
	_rebuild_resources()
	if not _actions.is_empty():
		var selected := get_selected_directives()
		_rebuild_directives()
		for entry in selected:
			select_directive(String(entry["action"]), float(entry["intensity"]))
	_update_state()


func update_resources(role: String, resources: Dictionary) -> void:
	_role = role
	_resources = resources.duplicate()
	_update_title()
	_rebuild_resources()
	_update_state()


func set_crisis_choice(option: Dictionary) -> void:
	_crisis_option_id = String(option.get("id", ""))
	_crisis_cost = option.get("cost", {})
	var label := CyberPalette.escape_bbcode(String(option.get("label", "")))
	var cost := UiFormat.format_cost(_role, _crisis_cost)
	set_crisis_status("[color=%s]CRISIS RESPONSE:[/color] %s [color=%s](%s)[/color]" % [
		CyberPalette.hex(CyberPalette.CYAN), label, CyberPalette.hex(CyberPalette.TEXT_DIM), cost])
	_update_state()


func set_crisis_status(bbcode: String) -> void:
	_crisis_label.text = bbcode


func has_crisis_choice() -> bool:
	return _crisis_option_id != ""


func get_crisis_option_id() -> String:
	return _crisis_option_id


func show_message(text: String, color: Color = CyberPalette.CRIMSON) -> void:
	_message_label.text = text
	_message_label.add_theme_color_override("font_color", color)


## Currently selected directives as engine submissions.
func get_selected_directives() -> Array:
	var out := []
	for action in _actions:
		var row: Dictionary = _rows.get(action["id"], {})
		if row.is_empty() or not (row["check"] as CheckBox).button_pressed:
			continue
		out.append({"action": action["id"], "intensity": (row["slider"] as HSlider).value})
	return out


## Programmatic selection (used by tests and the screenshot tool).
func select_directive(action_id: String, intensity: float = 1.0) -> bool:
	if not _rows.has(action_id):
		return false
	var row: Dictionary = _rows[action_id]
	var check: CheckBox = row["check"]
	if check.disabled:
		return false
	check.button_pressed = true
	(row["slider"] as HSlider).value = intensity
	_update_state()
	return check.button_pressed


func is_execute_enabled() -> bool:
	return not _execute_button.disabled


func _update_title() -> void:
	if _title == null:
		return
	if _compact and SimConstants.ROLE_INFO.has(_role):
		_title.text = "DIRECTIVES // %s" % String(SimConstants.ROLE_INFO[_role]["header"])
	else:
		_title.text = "ACTION / DIRECTIVE CONTROL PANEL"


func _rebuild_resources() -> void:
	for child in _resource_box.get_children():
		_resource_box.remove_child(child)
		child.queue_free()
	var info := FactionRegistry.resource_info_for(_role)
	for key in info:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 3)
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = String(info[key]["label"]) + ":"
		name_label.theme_type_variation = "DimLabel"
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.clip_text = true
		row.add_child(name_label)
		var value_label := Label.new()
		value_label.theme_type_variation = "ValueLabel"
		value_label.text = UiFormat.format_resource(_role, key, float(_resources.get(key, 0.0)))
		row.add_child(value_label)
		cell.add_child(row)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 4)
		bar.max_value = float(info[key].get("scale", 100.0))
		bar.value = float(_resources.get(key, 0.0))
		cell.add_child(bar)
		_resource_box.add_child(cell)


func _rebuild_directives() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows = {}
	for action in _actions:
		var action_id := String(action["id"])
		var card := PanelContainer.new()
		card.theme_type_variation = "CardPanel"
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		card.add_child(box)

		# Name and cost side by side on desktop; stacked on phones.
		var header := BoxContainer.new()
		header.vertical = _compact
		var check := CheckBox.new()
		check.text = String(action["name"])
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		check.add_theme_font_size_override("font_size", 13)
		if _compact:
			check.custom_minimum_size = Vector2(0, 34)
			check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		header.add_child(check)
		var cost_label := Label.new()
		cost_label.theme_type_variation = "DimLabel"
		cost_label.text = UiFormat.format_cost(_role, action["cost"])
		header.add_child(cost_label)
		box.add_child(header)

		var description := Label.new()
		description.theme_type_variation = "DimLabel"
		description.text = String(action["description"])
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.add_theme_font_size_override("font_size", 12 if _compact else 11)
		box.add_child(description)

		var slider_row := HBoxContainer.new()
		var slider := HSlider.new()
		slider.min_value = 1.0
		slider.max_value = 2.0
		slider.step = 0.1
		slider.value = 1.0
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _compact:
			slider.custom_minimum_size = Vector2(0, 32)
			slider.add_theme_icon_override("grabber", CyberTheme.disc_texture(22, CyberPalette.CYAN))
			slider.add_theme_icon_override("grabber_highlight", CyberTheme.disc_texture(24, Color.WHITE))
		slider_row.add_child(slider)
		var intensity_label := Label.new()
		intensity_label.text = "x1.0"
		intensity_label.custom_minimum_size = Vector2(44, 0)
		slider_row.add_child(intensity_label)
		slider_row.visible = false
		box.add_child(slider_row)

		var blocked := String(action.get("blocked_reason", ""))
		if blocked != "":
			check.disabled = true
			check.tooltip_text = blocked
			cost_label.text = blocked.to_upper()
			cost_label.add_theme_color_override("font_color", CyberPalette.AMBER)
		if (action["cost"] as Dictionary).is_empty():
			slider.editable = false
		check.toggled.connect(func(pressed: bool):
			slider_row.visible = pressed and not (action["cost"] as Dictionary).is_empty()
			_update_state())
		slider.value_changed.connect(func(v: float):
			intensity_label.text = "x%.1f" % v
			_update_state())
		_rows[action_id] = {"check": check, "slider": slider, "cost_label": cost_label,
			"blocked": blocked, "max_intensity": float(action.get("max_intensity", 1.0))}
		_list.add_child(card)
	UiLayout.pass_touch_through(_list)


func _projected_cost() -> Dictionary:
	var total := _crisis_cost.duplicate()
	for action in _actions:
		var row: Dictionary = _rows.get(action["id"], {})
		if row.is_empty() or not (row["check"] as CheckBox).button_pressed:
			continue
		var intensity := (row["slider"] as HSlider).value
		for key in action["cost"]:
			total[key] = float(total.get(key, 0.0)) + float(action["cost"][key]) * intensity
	return total


func _update_state() -> void:
	if _execute_button == null:
		return
	var selected := get_selected_directives().size()
	for action_id in _rows:
		var row: Dictionary = _rows[action_id]
		var check: CheckBox = row["check"]
		var locked := not _interactive or not has_crisis_choice() or String(row["blocked"]) != ""
		if not check.button_pressed:
			locked = locked or selected >= max_directives
		check.disabled = locked
		(row["slider"] as HSlider).editable = _interactive and float(row["max_intensity"]) > 1.0
	var projected := _projected_cost()
	var shortfalls: Array[String] = []
	for key in projected:
		if float(_resources.get(key, 0.0)) + 0.0001 < float(projected[key]):
			shortfalls.append(UiFormat.resource_short(_role, key))
	var summary := "Selected %d/%d · total spend: %s" % [selected, max_directives, UiFormat.format_cost(_role, projected)]
	if not shortfalls.is_empty():
		summary += "\nINSUFFICIENT: " + ", ".join(shortfalls)
	_summary_label.text = summary
	_summary_label.add_theme_color_override("font_color", CyberPalette.CRIMSON if not shortfalls.is_empty() else CyberPalette.TEXT_DIM)
	_execute_button.disabled = not _interactive or not has_crisis_choice() or not shortfalls.is_empty()
	_review_button.disabled = not _interactive


func _on_execute_pressed() -> void:
	if _execute_button.disabled:
		return
	execute_requested.emit(get_selected_directives())
