class_name EndgameDebrief
extends Control
## Endgame debrief (PRD milestone 6): the civilizational end-state, the role
## verdict, historical trajectory line charts and the affinity of the world to
## each of the eight end-states. On phones everything stacks in one scrolling
## column.

signal new_campaign_requested
signal closed

const DESCRIPTION_WIDTH := 1180.0

var _compact := false
var _frame: MarginContainer
var _panel: PanelContainer
var _columns: BoxContainer
var _right: VBoxContainer
var _buttons: BoxContainer
var _accent_style: StyleBoxFlat
var _kicker: RichTextLabel
var _title: Label
var _description: Label
var _verdict: RichTextLabel
var _chart: TrajectoryChart
var _affinity_box: VBoxContainer
var _stats: RichTextLabel


func _ready() -> void:
	_frame = UiLayout.build_overlay(self, Color(0.02, 0.03, 0.05, 0.86))
	_panel = PanelContainer.new()
	_accent_style = CyberTheme.box(CyberPalette.BG, CyberPalette.CYAN, 2, 6, 20)
	_accent_style.shadow_color = Color(0, 0, 0, 0.7)
	_accent_style.shadow_size = 24
	_panel.add_theme_stylebox_override("panel", _accent_style)
	_frame.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	_kicker = _rich(13)
	box.add_child(_kicker)
	_title = Label.new()
	_title.theme_type_variation = "HeaderTitle"
	_title.add_theme_font_size_override("font_size", 28)
	box.add_child(_title)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(DESCRIPTION_WIDTH, 0)
	box.add_child(_description)
	_verdict = _rich(15)
	box.add_child(_verdict)

	# Chart and matrix side by side on desktop; stacked on phones.
	_columns = BoxContainer.new()
	_columns.add_theme_constant_override("separation", 14)
	box.add_child(_columns)
	_chart = TrajectoryChart.new()
	_chart.custom_minimum_size = Vector2(760, 320)
	_columns.add_child(_chart)
	_right = VBoxContainer.new()
	_right.custom_minimum_size = Vector2(400, 0)
	_right.add_theme_constant_override("separation", 4)
	_columns.add_child(_right)
	var affinity_title := Label.new()
	affinity_title.theme_type_variation = "PanelTitle"
	affinity_title.text = "CIVILIZATIONAL MATRIX AFFINITY"
	_right.add_child(affinity_title)
	_affinity_box = VBoxContainer.new()
	_affinity_box.add_theme_constant_override("separation", 3)
	_right.add_child(_affinity_box)
	_stats = _rich(12)
	_right.add_child(_stats)

	var buttons := BoxContainer.new()
	_buttons = buttons
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	var close_button := Button.new()
	close_button.text = "INSPECT FINAL STATE"
	close_button.pressed.connect(func():
		visible = false
		closed.emit())
	buttons.add_child(close_button)
	var restart := Button.new()
	restart.theme_type_variation = "AccentButton"
	restart.text = "[ NEW CAMPAIGN ]"
	restart.pressed.connect(func(): new_campaign_requested.emit())
	buttons.add_child(restart)
	box.add_child(buttons)
	UiLayout.pass_touch_through(_panel)
	resized.connect(_apply_layout)
	visible = false


func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	_apply_layout()
	for row in _affinity_box.get_children():
		_style_affinity_row(row)


func _apply_layout() -> void:
	if _panel == null:
		return
	var width := UiLayout.panel_width(size.x, 0.0, _compact)
	_panel.custom_minimum_size = Vector2(width if _compact else 0.0, 0)
	for side in ["left", "right", "top", "bottom"]:
		_accent_style.set("content_margin_" + side, 14 if _compact else 20)
	_description.custom_minimum_size = Vector2(0.0 if _compact else DESCRIPTION_WIDTH, 0)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if _compact else TextServer.AUTOWRAP_OFF
	_title.add_theme_font_size_override("font_size", 20 if _compact else 28)
	_columns.vertical = _compact
	_chart.custom_minimum_size = Vector2(0, 240) if _compact else Vector2(760, 320)
	_right.custom_minimum_size = Vector2(0.0 if _compact else 400.0, 0)
	for label in [_kicker, _verdict, _stats]:
		(label as Control).custom_minimum_size = Vector2(0.0 if _compact else 380.0, 0)
	_buttons.vertical = _compact
	for button in _buttons.get_children():
		(button as Control).custom_minimum_size = Vector2(0, 44) if _compact else Vector2.ZERO
	UiLayout.set_overlay_margin(_frame, _compact)


func present(result: Dictionary) -> void:
	var outcome: Dictionary = result.get("outcome", {})
	var verdict: Dictionary = result.get("verdict", {})
	var verdict_name := String(verdict.get("verdict", "DEFEAT"))
	var accent := CyberPalette.CYAN
	if verdict_name == "PYRRHIC":
		accent = CyberPalette.AMBER
	elif verdict_name == "DEFEAT":
		accent = CyberPalette.CRIMSON
	_accent_style.border_color = accent

	var reason := String(result.get("reason", ""))
	var reason_text := "Turn limit reached"
	if reason == "PLAYER_LOSS":
		reason_text = "Instant loss: " + String(result.get("player_loss", {}).get("reason", ""))
	elif reason == "CATASTROPHE":
		reason_text = "Catastrophic threshold: " + String(result.get("catastrophe", {}).get("reason", ""))
	_kicker.text = "[color=%s]CIVILIZATIONAL END-STATE %d of 8[/color]  //  T%d  //  %d  //  %s%s" % [
		CyberPalette.hex(accent), int(outcome.get("number", 0)), int(result.get("turn", 0)), int(float(result.get("year", 2026.0))),
		CyberPalette.escape_bbcode(reason_text),
		"" if outcome.get("strict_match", false) else "  //  nearest attractor"]
	_title.text = "%s - %s" % [String(outcome.get("name", "")).to_upper(), outcome.get("subtitle", "")]
	_title.add_theme_color_override("font_color", accent)
	_description.text = String(outcome.get("description", ""))
	_verdict.text = "[color=%s][b]%s[/b][/color]  %s directive score [b]%.0f[/b] / 100   (end-state value %.0f + objectives %.0f)" % [
		CyberPalette.hex(accent), verdict_name, SimConstants.role_title(String(result.get("player_role", ""))),
		float(verdict.get("score", 0.0)), float(verdict.get("outcome_value", 0.0)), float(verdict.get("objective_score", 0.0))]

	_chart.set_history(result.get("history", []))
	_build_affinities(outcome)
	_build_stats(result)
	_apply_layout()
	(get_node("OverlayScroll") as ScrollContainer).scroll_vertical = 0
	visible = true


func _build_affinities(outcome: Dictionary) -> void:
	for child in _affinity_box.get_children():
		_affinity_box.remove_child(child)
		child.queue_free()
	var affinities: Dictionary = outcome.get("affinities", {})
	for candidate in VictoryMatrix.OUTCOMES:
		var outcome_id := String(candidate["id"])
		var affinity := float(affinities.get(outcome_id, 0.0))
		var chosen := outcome_id == String(outcome.get("id", ""))
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.name = "Name"
		name_label.text = "%d. %s" % [int(candidate["number"]), candidate["name"]]
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.add_theme_color_override("font_color", CyberPalette.CYAN if chosen else CyberPalette.TEXT_DIM)
		row.add_child(name_label)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 100.0
		bar.value = affinity
		bar.custom_minimum_size = Vector2(100, 10)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not chosen:
			bar.add_theme_stylebox_override("fill", CyberTheme.box(CyberPalette.TEXT_DIM.darkened(0.4), CyberPalette.TEXT_DIM, 0, 2))
		row.add_child(bar)
		var value := Label.new()
		value.text = "%3d%%" % int(round(affinity))
		value.add_theme_font_size_override("font_size", 12)
		row.add_child(value)
		_style_affinity_row(row)
		_affinity_box.add_child(row)
	UiLayout.pass_touch_through(_affinity_box)


## Fixed-width names on desktop; on phones the name takes what the bar leaves.
func _style_affinity_row(row: Node) -> void:
	var name_label: Label = row.get_node("Name")
	name_label.custom_minimum_size = Vector2(0.0 if _compact else 250.0, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _compact else Control.SIZE_FILL
	name_label.clip_text = _compact


func _build_stats(result: Dictionary) -> void:
	var values: Dictionary = result.get("final_values", {})
	var tech: Dictionary = result.get("tech", {})
	var lines: Array[String] = ["", "[color=%s]FINAL TELEMETRY[/color]" % CyberPalette.hex(CyberPalette.CYAN)]
	for key in WorldState.METRIC_KEYS:
		lines.append("%-16s %5.1f" % [UiFormat.metric_short(key), float(values.get(key, 0.0))])
	lines.append("%-16s %5.1f" % ["Enforcement", float(values.get("enforcement_level", 0.0))])
	lines.append("%-16s %5.1f" % ["Citizen Resil.", float(values.get("citizen_resilience", 0.0))])
	lines.append("Training FLOPs   10^%.1f" % float(tech.get("log_flops", 26.0)))
	var milestones: Dictionary = result.get("milestones", {})
	if milestones.has("agi_turn"):
		lines.append("AGI milestone    %d" % int(SimConstants.year_for_turn(int(milestones["agi_turn"]))))
	lines.append("Paradigm shifts  %d / 4" % (tech.get("unlocked_shifts", []) as Array).size())
	lines.append("Emergences       %d" % (tech.get("emerged_capabilities", []) as Array).size())
	lines.append("Alignment taxes  %d" % int(tech.get("alignment_tax_events", 0)))
	_stats.text = "\n".join(lines)


func _rich(font_size: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.custom_minimum_size = Vector2(380, 0)
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_font_size_override("bold_font_size", font_size)
	return label
