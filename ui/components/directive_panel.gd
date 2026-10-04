class_name DirectivePanel
extends PanelContainer
## The ACT panel (PRD section 8.2), drawn in the active era's style.
##
## Shows the player's currencies, the turn's crisis as an inline card and the
## role's directive catalog. Each directive is a card whose glyph tile works
## as its check box; selected directives get an intensity slider (1.0x-2.0x
## of the base cost, with diminishing returns on effect). Execute stays
## locked until the crisis is resolved and the combined spend is affordable.
## The compact variant (phones, tablets) enlarges every touch target. Text
## follows the player's text size, and names their plain-language setting.

signal execute_requested(directives: Array)
signal review_crisis_requested

## Crisis category -> glyph and the metric whose color tints its tile.
const CATEGORY_GLYPHS := {
	"ALIGNMENT": "drift", "ECONOMY": "capital", "ENERGY": "compute", "EPISTEMIC": "trust",
	"GEOPOLITICS": "tension", "LABOR": "labor", "RACE": "speed", "SECURITY": "lock",
	"SOCIETY": "person", "SOVEREIGNTY": "flag", "UNREST": "warning",
}
const CATEGORY_METRICS := {
	"ALIGNMENT": "alignment_drift", "ECONOMY": "labor_displacement", "ENERGY": "compute_energy_sat",
	"EPISTEMIC": "epistemic_trust", "GEOPOLITICS": "geopolitical_tension", "LABOR": "labor_displacement",
	"RACE": "algorithmic_autonomy", "SECURITY": "geopolitical_tension", "SOCIETY": "epistemic_trust",
	"SOVEREIGNTY": "algorithmic_autonomy", "UNREST": "geopolitical_tension",
}
const TILE_SIZE := 30

var max_directives := 2

var _role := ""
var _resources := {}
var _actions: Array = []
var _rows := {}
var _crisis_card := {}
var _crisis_option_id := ""
var _crisis_cost := {}
var _interactive := false
var _compact := false
var _focus_tween: Tween
## The style variant the panel was last styled with (era, colors, text size).
var _era_style: EraStyle
var _relabel_queued := false

var _title: Label
var _resource_box: GridContainer
var _crisis_panel: PanelContainer
var _crisis_tile: TextureRect
var _crisis_kicker: Label
var _crisis_meta: Label
var _crisis_title: Label
var _crisis_label: RichTextLabel
var _review_button: Button
var _directives_title: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _summary_label: Label
var _message_label: Label
var _execute_button: Button


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	_title = Label.new()
	_title.theme_type_variation = "PanelTitle"
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(_title)

	_resource_box = GridContainer.new()
	_resource_box.name = "Resources"
	_resource_box.columns = 4
	_resource_box.add_theme_constant_override("h_separation", 8)
	_resource_box.add_theme_constant_override("v_separation", 8)
	root.add_child(_resource_box)

	root.add_child(_build_crisis_card())

	_directives_title = Label.new()
	_directives_title.theme_type_variation = "DimLabel"
	_directives_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_directives_title)

	_scroll = ScrollContainer.new()
	_scroll.name = "DirectiveScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list)

	_summary_label = Label.new()
	_summary_label.theme_type_variation = "DimLabel"
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_summary_label)
	_message_label = Label.new()
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	EraTheme.set_scaled_font_size(_message_label, 12)
	root.add_child(_message_label)

	_execute_button = Button.new()
	_execute_button.name = "ExecuteButton"
	_execute_button.theme_type_variation = "AccentButton"
	_execute_button.custom_minimum_size = Vector2(0, 44)
	_execute_button.pressed.connect(_on_execute_pressed)
	root.add_child(_execute_button)
	_restyle()
	GameSettings.instance().changed.connect(_on_setting_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _title != null and EraTheme.style_of(self) != _era_style:
		_restyle()
	elif what == NOTIFICATION_TRANSLATION_CHANGED and _title != null and not _relabel_queued:
		_relabel_queued = true
		_relabel.call_deferred()


## The language changed: the crisis in its new words, the directives and the
## status line.
func _relabel() -> void:
	_relabel_queued = false
	if not _crisis_card.is_empty():
		_crisis_card = DilemmaDeck.localized(_crisis_card)
	_restyle_crisis()
	_rebuild_all()
	if has_crisis_choice():
		var option := DilemmaDeck.find_option(_crisis_card, _crisis_option_id)
		if not option.is_empty():
			set_crisis_choice(option)
	elif _interactive:
		_set_pending_status()


## Plain names show at once; colors and text size follow the theme.
func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "plain_language" and _title != null:
		_rebuild_all()


## The Execute button (the guided first campaign points at it).
func get_execute_button() -> Button:
	return _execute_button


## The scrolling list of directive cards.
func get_directive_list() -> Control:
	return _scroll


## Populates the panel for a new player phase (SimulationEngine.get_player_context()).
func setup(context: Dictionary) -> void:
	_role = String(context.get("role", ""))
	_resources = (context.get("resources", {}) as Dictionary).duplicate()
	_actions = context.get("actions", [])
	max_directives = int(context.get("max_directives", max_directives))
	_crisis_option_id = ""
	_crisis_cost = {}
	_message_label.text = ""
	set_crisis_card(context.get("dilemma", {}))
	_rebuild_resources()
	_rebuild_directives()
	_set_pending_status()
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
	_execute_button.custom_minimum_size = Vector2(0, 48 if compact else 44)
	_review_button.custom_minimum_size = Vector2(0, 44 if compact else 38)
	_rebuild_all()


func update_resources(role: String, resources: Dictionary) -> void:
	_role = role
	_resources = resources.duplicate()
	_update_title()
	_rebuild_resources()
	_update_state()


## Shows [param card] (a crisis-card dictionary) as the inline crisis card.
func set_crisis_card(card: Dictionary) -> void:
	_crisis_card = DilemmaDeck.localized(card)
	_restyle_crisis()


func set_crisis_choice(option: Dictionary) -> void:
	_crisis_option_id = String(option.get("id", ""))
	_crisis_cost = option.get("cost", {})
	var s := EraTheme.style_of(self)
	var label := CyberPalette.escape_bbcode(DilemmaDeck.local_text(option, "label"))
	var cost := UiFormat.format_cost(_role, _crisis_cost)
	set_crisis_status("[color=%s]%s[/color] %s [color=%s]· %s[/color]" % [
		CyberPalette.hex(s.accent), s.label(tr("Response:")), label, CyberPalette.hex(s.text_dim), cost])
	_update_state()


func set_crisis_status(bbcode: String) -> void:
	_crisis_label.text = bbcode


func has_crisis_choice() -> bool:
	return _crisis_option_id != ""


func get_crisis_option_id() -> String:
	return _crisis_option_id


func show_message(text: String, color: Color = Color.TRANSPARENT) -> void:
	_message_label.text = text
	var s := EraTheme.style_of(self)
	_message_label.add_theme_color_override("font_color", s.critical if color == Color.TRANSPARENT else color)


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


## Scrolls to [param action_id] and flashes its card (a lens asked for it).
## Returns false when the role has no such directive.
func focus_directive(action_id: String) -> bool:
	if not _rows.has(action_id):
		return false
	var card: Control = _rows[action_id]["card"]
	_scroll.ensure_control_visible.call_deferred(card)
	if _focus_tween != null:
		_focus_tween.kill()
	card.modulate = Color(1.6, 1.6, 1.6)
	_focus_tween = create_tween()
	_focus_tween.tween_property(card, "modulate", Color.WHITE, 0.9).set_ease(Tween.EASE_OUT)
	return true


func has_directive(action_id: String) -> bool:
	return _rows.has(action_id)


func is_execute_enabled() -> bool:
	return not _execute_button.disabled


# --- Building -----------------------------------------------------------------------

func _build_crisis_card() -> PanelContainer:
	_crisis_panel = PanelContainer.new()
	_crisis_panel.name = "CrisisCard"
	_crisis_panel.theme_type_variation = "CardPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_crisis_panel.add_child(box)
	var kicker_row := HBoxContainer.new()
	kicker_row.add_theme_constant_override("separation", 8)
	_crisis_tile = TextureRect.new()
	_crisis_tile.custom_minimum_size = Vector2(22, 22)
	_crisis_tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_crisis_tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	kicker_row.add_child(_crisis_tile)
	_crisis_kicker = Label.new()
	_crisis_kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crisis_kicker.clip_text = true
	_crisis_kicker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	kicker_row.add_child(_crisis_kicker)
	_crisis_meta = Label.new()
	kicker_row.add_child(_crisis_meta)
	box.add_child(kicker_row)
	_crisis_title = Label.new()
	_crisis_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_crisis_title)
	_crisis_label = RichTextLabel.new()
	_crisis_label.bbcode_enabled = true
	_crisis_label.fit_content = true
	_crisis_label.scroll_active = false
	_crisis_label.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_crisis_label)
	_review_button = Button.new()
	_review_button.name = "ReviewCrisisButton"
	_review_button.theme_type_variation = "AccentButton"
	_review_button.tooltip_text = "Open the crisis card"
	_review_button.pressed.connect(func(): review_crisis_requested.emit())
	box.add_child(_review_button)
	return _crisis_panel


func _rebuild_all() -> void:
	_update_title()
	_rebuild_resources()
	if not _actions.is_empty():
		var selected := get_selected_directives()
		_rebuild_directives()
		for entry in selected:
			select_directive(String(entry["action"]), float(entry["intensity"]))
	_update_state()


func _restyle() -> void:
	var s := EraTheme.style_of(self)
	_era_style = s
	_crisis_kicker.add_theme_font_override("font", s.font_mono if s.era == 3 else s.font_ui_bold)
	EraTheme.set_scaled_font_size(_crisis_kicker, 12)
	_crisis_kicker.add_theme_color_override("font_color", s.text_dim)
	_crisis_meta.add_theme_font_override("font", s.font_mono)
	EraTheme.set_scaled_font_size(_crisis_meta, 11)
	_crisis_title.add_theme_font_override("font", s.font_ui_bold)
	EraTheme.set_scaled_font_size(_crisis_title, 16 if s.era == 1 else 17)
	_crisis_title.add_theme_color_override("font_color", s.text_bright)
	EraTheme.set_scaled_font_size(_crisis_label, 13, &"normal_font_size")
	_crisis_label.add_theme_color_override("default_color", s.text_dim)
	_restyle_crisis()
	_rebuild_all()


func _restyle_crisis() -> void:
	if _crisis_panel == null:
		return
	var s := EraTheme.style_of(self)
	var category := String(_crisis_card.get("category", ""))
	var has_card := not _crisis_card.is_empty()
	var color := s.metric_color(String(CATEGORY_METRICS.get(category, "geopolitical_tension")))
	_crisis_tile.texture = Glyphs.tile(String(CATEGORY_GLYPHS.get(category, "warning")), 22, color, s.bg, 6 if s.era != 3 else 11)
	var kicker := tr("Crisis · %s") % UiFormat.category_name(category) if has_card else tr("No crisis")
	_crisis_kicker.text = kicker.to_lower() if s.era == 3 else kicker.to_upper()
	var escalation := int(_crisis_card.get("escalation", 0))
	var escalated := tr("Escalated ×%d") % escalation
	_crisis_meta.text = (escalated.to_lower() if s.era == 3 else escalated) if escalation > 0 else ""
	_crisis_meta.add_theme_color_override("font_color", s.warn)
	_crisis_title.text = UiFormat.strip_escalation(DilemmaDeck.local_text(_crisis_card, "title"))
	_crisis_title.visible = has_card


func _update_title() -> void:
	if _title == null:
		return
	var s := EraTheme.style_of(self)
	var heading := tr("Your move")
	if SimConstants.ROLE_INFO.has(_role):
		heading = tr("Directives · %s") % UiFormat.role_name(_role)
	_title.text = s.label(heading)
	_directives_title.text = s.label(tr("Choose up to %d") % max_directives) + ((" · " + tr("slide to raise intensity")) if not _compact else "")
	_execute_button.text = s.label(tr("Execute directives"))
	_review_button.text = s.label(tr("Change response") if has_crisis_choice() else tr("Review options"))


func _rebuild_resources() -> void:
	for child in _resource_box.get_children():
		_resource_box.remove_child(child)
		child.queue_free()
	var s := EraTheme.style_of(self)
	var info := FactionRegistry.resource_info_for(_role)
	_resource_box.columns = maxi(mini(info.size(), 4), 1)
	for key in info:
		_resource_box.add_child(_resource_cell(s, String(key), float(_resources.get(key, 0.0))))


## One currency: glyph and name above the value, in the era's frame.
func _resource_cell(s: EraStyle, key: String, amount: float) -> Control:
	var cell := PanelContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.tooltip_text = UiFormat.resource_label(_role, key)
	var frame: StyleBoxFlat
	match s.era:
		1:
			frame = EraTheme.box(s.raised, Color(0, 0, 0, 0), 0, 12, 8, 7)
		2:
			frame = EraTheme.box(Color(s.accent, 0.04), s.accent, 0, 0, 8, 4)
			frame.border_width_left = 2
		_:
			frame = EraTheme.panel(s, Color(s.accent, 0.05), Color(s.accent, 0.45), 18, 8)
			frame.content_margin_top = 8
			frame.content_margin_bottom = 8
	cell.add_theme_stylebox_override("panel", frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	cell.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	head.add_child(Glyphs.icon(Glyphs.for_currency(key), 12, s.text_dim))
	var name_label := Label.new()
	name_label.text = s.label(UiFormat.resource_name(key))
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_override("font", s.font_ui)
	EraTheme.set_scaled_font_size(name_label, 10 if s.labels_upper else 11)
	name_label.add_theme_color_override("font_color", s.text_dim)
	head.add_child(name_label)
	box.add_child(head)
	var value_label := Label.new()
	value_label.text = UiFormat.format_resource(_role, key, amount)
	value_label.clip_text = true
	value_label.add_theme_font_override("font", s.font_ui_bold if s.era == 1 else s.font_mono)
	EraTheme.set_scaled_font_size(value_label, 16 if s.era == 1 else 14)
	value_label.add_theme_color_override("font_color", s.text_bright)
	box.add_child(value_label)
	for child in [box, head, value_label]:
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cell


func _rebuild_directives() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows = {}
	var s := EraTheme.style_of(self)
	for action in _actions:
		_list.add_child(_directive_card(s, action))
	UiLayout.pass_touch_through(_list)


func _directive_card(s: EraStyle, action: Dictionary) -> PanelContainer:
	var action_id := String(action["id"])
	var card := PanelContainer.new()
	card.name = action_id
	card.theme_type_variation = "CardPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	# The glyph tile is the check box: tinted when selected.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var check := CheckBox.new()
	check.text = tr(String(action["name"]))
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	check.add_theme_font_override("font", s.font_ui_bold)
	EraTheme.set_scaled_font_size(check, 14)
	check.add_theme_constant_override("h_separation", 10)
	check.custom_minimum_size = Vector2(0, 40 if _compact else 34)
	var glyph := _action_glyph(action)
	var radius := 8 if s.era != 3 else 14
	check.add_theme_icon_override("unchecked", Glyphs.tile(glyph, TILE_SIZE, Color(s.accent, 0.18), s.accent, radius))
	check.add_theme_icon_override("checked", Glyphs.tile("check", TILE_SIZE, s.accent, s.on_accent, radius))
	check.add_theme_icon_override("unchecked_disabled", Glyphs.tile(glyph, TILE_SIZE, Color(s.text_dim, 0.12), Color(s.text_dim, 0.6), radius))
	check.add_theme_icon_override("checked_disabled", Glyphs.tile("check", TILE_SIZE, Color(s.text_dim, 0.4), s.bg, radius))
	header.add_child(check)
	var cost_label := Label.new()
	cost_label.add_theme_font_override("font", s.font_mono)
	EraTheme.set_scaled_font_size(cost_label, 12)
	cost_label.add_theme_color_override("font_color", s.text_dim)
	cost_label.text = UiFormat.format_cost(_role, action["cost"])
	header.add_child(cost_label)
	box.add_child(header)

	var description := Label.new()
	description.theme_type_variation = "DimLabel"
	description.text = tr(String(action["description"]))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	EraTheme.set_scaled_font_size(description, 12)
	box.add_child(description)
	var effects := _effect_chips(s, action.get("effects", {}))
	if effects != null:
		box.add_child(effects)

	var slider_row := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = 1.0
	slider.max_value = 2.0
	slider.step = 0.1
	slider.value = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 32 if _compact else 24)
	slider_row.add_child(slider)
	var intensity_label := Label.new()
	intensity_label.text = "×1.0"
	intensity_label.custom_minimum_size = Vector2(44, 0)
	intensity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	intensity_label.add_theme_font_override("font", s.font_mono)
	slider_row.add_child(intensity_label)
	slider_row.visible = false
	box.add_child(slider_row)

	var blocked := String(action.get("blocked_reason", ""))
	if blocked != "":
		check.disabled = true
		check.tooltip_text = UiFormat.block_reason(blocked)
		cost_label.text = UiFormat.block_reason(blocked)
		cost_label.add_theme_color_override("font_color", s.warn)
	if (action["cost"] as Dictionary).is_empty():
		slider.editable = false
	check.toggled.connect(func(pressed: bool):
		slider_row.visible = pressed and not (action["cost"] as Dictionary).is_empty()
		card.theme_type_variation = "CardPanelSelected" if pressed else "CardPanel"
		_update_state())
	slider.value_changed.connect(func(v: float):
		intensity_label.text = "×%.1f" % v
		_update_state())
	_rows[action_id] = {"check": check, "slider": slider, "cost_label": cost_label, "card": card,
		"blocked": blocked, "max_intensity": float(action.get("max_intensity", 1.0))}
	return card


## Glyph chips with pips for the metrics a directive moves ("Compute ▲▲").
func _effect_chips(s: EraStyle, effects: Dictionary) -> Control:
	var metrics: Dictionary = effects.get("metrics", {})
	if metrics.is_empty():
		return null
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 4)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key in WorldState.METRIC_KEYS:
		if not metrics.has(key) or absf(float(metrics[key])) < 0.05:
			continue
		var amount := float(metrics[key])
		var color := s.good if UiFormat.is_improvement(key, amount) else s.bad
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 3)
		chip.tooltip_text = "%s %s" % [UiFormat.metric_name(key), UiFormat.signed(amount)]
		chip.add_child(Glyphs.icon(Glyphs.for_metric(key), 13, s.metric_color(key)))
		var pips := Label.new()
		pips.text = UiFormat.pips(amount)
		pips.add_theme_font_override("font", s.font_mono)
		EraTheme.set_scaled_font_size(pips, 10)
		pips.add_theme_color_override("font_color", color)
		chip.add_child(pips)
		flow.add_child(chip)
	return flow


## The metric a directive moves most, else its first currency, as a glyph.
func _action_glyph(action: Dictionary) -> String:
	var metrics: Dictionary = (action.get("effects", {}) as Dictionary).get("metrics", {})
	var best := ""
	var best_size := 0.0
	for key in metrics:
		if absf(float(metrics[key])) > best_size:
			best_size = absf(float(metrics[key]))
			best = String(key)
	if best != "":
		return Glyphs.for_metric(best)
	var cost: Dictionary = action.get("cost", {})
	return Glyphs.for_currency(String(cost.keys()[0])) if not cost.is_empty() else "spark"


# --- State --------------------------------------------------------------------------

func _set_pending_status() -> void:
	var s := EraTheme.style_of(self)
	set_crisis_status("[color=%s]%s[/color] %s" % [CyberPalette.hex(s.warn), s.label(tr("Decision pending.")),
		tr("Resolve the crisis to unlock your directives.")])


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
	var s := EraTheme.style_of(self)
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
			shortfalls.append(UiFormat.resource_name(key))
	var summary := tr("%d of %d selected · spend %s") % [selected, max_directives, UiFormat.format_cost(_role, projected)]
	if not shortfalls.is_empty():
		summary += "\n" + tr("Not enough %s") % ", ".join(shortfalls)
	_summary_label.text = summary
	_summary_label.add_theme_color_override("font_color", s.critical if not shortfalls.is_empty() else s.text_dim)
	_execute_button.disabled = not _interactive or not has_crisis_choice() or not shortfalls.is_empty()
	_review_button.disabled = not _interactive
	_review_button.theme_type_variation = &"GhostButton" if has_crisis_choice() else &"AccentButton"
	_update_title()


func _on_execute_pressed() -> void:
	if _execute_button.disabled:
		return
	execute_requested.emit(get_selected_directives())
