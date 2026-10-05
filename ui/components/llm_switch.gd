class_name LLMSwitch
extends HBoxContainer
## The player's LLM choice, On or Off, as two chips bound to GameSettings
## "llm". The settings dialog and the campaign setup each hold one; both follow
## the setting, so a change made anywhere (the header badge, a #llm=off link)
## shows at once. On a build without a backend [method set_available] greys
## the chips out and shows Off, without touching the stored choice.
##
##   var llm_switch := LLMSwitch.new()
##   llm_switch.caption = I18n.mark("LLM")   # "" for no label
##   parent.add_child(llm_switch)
##   llm_switch.set_available(llm.has_backend())

const KEY := "llm"

## Text before the chips ("" hides it). Set before the switch enters the tree.
var caption := I18n.mark("LLM")

var _label: Label
var _on: Button
var _off: Button
var _available := true
var _compact := false


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_label = Label.new()
	_label.name = "Caption"
	_label.text = caption
	_label.visible = caption != ""
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_label)
	var group := ButtonGroup.new()
	_on = _chip(I18n.mark("On"), "LLMOn", true, group)
	_off = _chip(I18n.mark("Off"), "LLMOff", false, group)
	GameSettings.instance().changed.connect(_on_setting_changed)
	_apply_sizes()
	_sync()


## The label in front of the chips (the setup screen's "LLM").
func get_caption_label() -> Label:
	return _label


func is_on() -> bool:
	return _on != null and _on.button_pressed


## False on a build without a backend: the chips show Off and do nothing.
func set_available(available: bool) -> void:
	_available = available
	_sync()


func set_compact(compact: bool) -> void:
	_compact = compact
	_apply_sizes()


func _chip(text: String, node_name: String, value: bool, group: ButtonGroup) -> Button:
	var chip := Button.new()
	chip.name = node_name
	chip.text = text
	chip.toggle_mode = true
	chip.button_group = group
	chip.theme_type_variation = "ChipButton"
	chip.focus_mode = Control.FOCUS_NONE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.pressed.connect(func() -> void: GameSettings.instance().set_value(KEY, value))
	add_child(chip)
	return chip


func _apply_sizes() -> void:
	if _on == null:
		return
	for chip in [_on, _off]:
		(chip as Control).custom_minimum_size = Vector2(56, 44 if _compact else 36)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == KEY:
		_sync()


func _sync() -> void:
	if _on == null:
		return
	var on := _available and bool(GameSettings.value(KEY))
	_on.set_pressed_no_signal(on)
	_off.set_pressed_no_signal(not on)
	for chip in [_on, _off]:
		(chip as Button).disabled = not _available
	tooltip_text = "" if _available else I18n.mark("This version has no LLM: the built-in rules play the other factions.")
