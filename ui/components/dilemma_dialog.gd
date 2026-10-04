class_name DilemmaDialog
extends Control
## Crisis card overlay (PRD section 6, phase 3). Presents the procedural crisis
## with each option's cost and effect preview; the player resolves it or
## defers it (the card returns two turns later, escalated). On phones the card
## spans the screen, scrolls, and each option gets a full-width button.

signal option_chosen(option_id: String)

const SEVERITY_LABELS := {1: "LOW", 2: "ELEVATED", 3: "SEVERE"}
const DESKTOP_WIDTH := 820.0

var current_card := {}
var _compact := false
var _resources := {}
var _role := ""
var _frame: MarginContainer
var _panel: PanelContainer
var _panel_style: StyleBoxFlat
var _tag_label: RichTextLabel
var _title_label: Label
var _body_label: RichTextLabel
var _options_box: VBoxContainer


func _ready() -> void:
	_frame = UiLayout.build_overlay(self, Color(0.02, 0.03, 0.05, 0.72))
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(DESKTOP_WIDTH, 0)
	_panel_style = CyberTheme.box(CyberPalette.BG, CyberPalette.AMBER, 2, 6, 22)
	_panel_style.shadow_color = Color(0, 0, 0, 0.7)
	_panel_style.shadow_size = 24
	_panel.add_theme_stylebox_override("panel", _panel_style)
	_frame.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	_tag_label = RichTextLabel.new()
	_tag_label.bbcode_enabled = true
	_tag_label.fit_content = true
	_tag_label.scroll_active = false
	box.add_child(_tag_label)
	_title_label = Label.new()
	_title_label.theme_type_variation = "HeaderTitle"
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.custom_minimum_size = Vector2(770, 0)
	box.add_child(_title_label)
	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.scroll_active = false
	_body_label.custom_minimum_size = Vector2(770, 0)
	_body_label.add_theme_font_size_override("normal_font_size", 14)
	box.add_child(_body_label)
	box.add_child(HSeparator.new())
	_options_box = VBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 8)
	box.add_child(_options_box)
	UiLayout.pass_touch_through(_panel)
	resized.connect(_apply_layout)
	visible = false


func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	_apply_layout()
	if visible and not current_card.is_empty():
		_build_options()


## Shows [param card] for [param role]; options the player cannot afford are disabled.
func present(card: Dictionary, resources: Dictionary, role: String) -> void:
	current_card = card
	var severity := int(card.get("severity", 1))
	var accent := CyberPalette.CRIMSON if severity >= 3 else CyberPalette.AMBER
	_panel_style.border_color = accent
	var source := String(card.get("source", "DECK"))
	var source_text := "PROCEDURAL INTELLIGENCE FEED"
	if source == "DEFERRED":
		source_text = "DEFERRED CRISIS RETURNS (ESCALATION %d)" % int(card.get("escalation", 0))
	elif SimConstants.is_valid_faction(source):
		source_text = "INJECTED BY %s" % SimConstants.role_title(source)
	_tag_label.text = "[color=%s]CRISIS CARD[/color] // %s // SEVERITY [color=%s]%s %s[/color] // [color=%s]%s[/color]" % [
		CyberPalette.hex(accent), String(card.get("category", "CRISIS")), CyberPalette.hex(accent),
		"■".repeat(severity) + "□".repeat(3 - severity), SEVERITY_LABELS.get(severity, ""),
		CyberPalette.hex(CyberPalette.TEXT_DIM), source_text]
	_title_label.text = String(card.get("title", ""))
	_body_label.text = CyberPalette.escape_bbcode(String(card.get("body", "")))
	_resources = resources
	_role = role
	_build_options()
	_apply_layout()
	var scroll: ScrollContainer = get_node_or_null("OverlayScroll")
	if scroll != null:
		scroll.scroll_vertical = 0
	visible = true


func close() -> void:
	visible = false


## Programmatic choice (tests / screenshot tooling).
func choose(option_id: String) -> void:
	_on_option_pressed(option_id)


func _build_options() -> void:
	for child in _options_box.get_children():
		_options_box.remove_child(child)
		child.queue_free()
	for option in current_card.get("options", []):
		_options_box.add_child(_option_row(option, _resources, _role, false))
	_options_box.add_child(_option_row(current_card.get("defer", {}), _resources, _role, true))
	UiLayout.pass_touch_through(_options_box)


func _apply_layout() -> void:
	if _panel == null:
		return
	var width := UiLayout.panel_width(size.x, DESKTOP_WIDTH, _compact)
	_panel.custom_minimum_size = Vector2(width, 0)
	_panel_style.content_margin_left = 14 if _compact else 22
	_panel_style.content_margin_right = 14 if _compact else 22
	_panel_style.content_margin_top = 14 if _compact else 22
	_panel_style.content_margin_bottom = 14 if _compact else 22
	_title_label.custom_minimum_size = Vector2(0 if _compact else 770, 0)
	_body_label.custom_minimum_size = Vector2(0 if _compact else 770, 0)
	_title_label.add_theme_font_size_override("font_size", 18 if _compact else 20)
	UiLayout.set_overlay_margin(_frame, _compact)


func _option_row(option: Dictionary, resources: Dictionary, role: String, is_defer: bool) -> Control:
	var option_id := String(option.get("id", DilemmaDeck.DEFER_ID))
	var cost: Dictionary = option.get("cost", {})
	var affordable := true
	for key in cost:
		if float(resources.get(key, 0.0)) + 0.0001 < float(cost[key]):
			affordable = false

	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	# Text and button side by side on desktop; a full-width button below on phones.
	var row := BoxContainer.new()
	row.vertical = _compact
	row.add_theme_constant_override("separation", 8 if _compact else 12)
	card.add_child(row)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)

	var label := Label.new()
	label.text = ("DEFER: " if is_defer else "") + String(option.get("label", ""))
	label.theme_type_variation = "ValueLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(label)
	var detail_text := String(option.get("detail", ""))
	if detail_text != "":
		var detail := Label.new()
		detail.theme_type_variation = "DimLabel"
		detail.text = detail_text
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(detail)
	var effects := RichTextLabel.new()
	effects.bbcode_enabled = true
	effects.fit_content = true
	effects.scroll_active = false
	effects.add_theme_font_size_override("normal_font_size", 12)
	var cost_color := CyberPalette.TEXT_DIM if affordable else CyberPalette.CRIMSON
	effects.text = "[color=%s]COST %s[/color]  [color=%s]%s[/color]" % [
		CyberPalette.hex(cost_color), UiFormat.format_cost(role, cost),
		CyberPalette.hex(CyberPalette.CYAN.darkened(0.1)),
		CyberPalette.escape_bbcode(UiFormat.effects_summary(option.get("effects", {}), role))]
	texts.add_child(effects)

	var button := Button.new()
	button.text = "[ DEFER ]" if is_defer else "[ %s ] ENACT" % option_id
	if _compact:
		button.custom_minimum_size = Vector2(0, 42)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		button.custom_minimum_size = Vector2(120, 0)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.disabled = not affordable
	if not affordable:
		button.tooltip_text = "Insufficient resources"
	button.pressed.connect(_on_option_pressed.bind(option_id))
	row.add_child(button)
	return card


func _on_option_pressed(option_id: String) -> void:
	visible = false
	option_chosen.emit(option_id)
