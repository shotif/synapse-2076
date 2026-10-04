class_name EndgameDebrief
extends Control
## Endgame debrief (PRD milestone 6): the civilizational end-state, the role
## verdict, historical trajectory line charts and the affinity of the world to
## each of the eight end-states.

signal new_campaign_requested
signal closed

var _accent_style: StyleBoxFlat
var _kicker: RichTextLabel
var _title: Label
var _description: Label
var _verdict: RichTextLabel
var _chart: TrajectoryChart
var _affinity_box: VBoxContainer
var _stats: RichTextLabel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.86)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	_accent_style = CyberTheme.box(CyberPalette.BG, CyberPalette.CYAN, 2, 6, 20)
	_accent_style.shadow_color = Color(0, 0, 0, 0.7)
	_accent_style.shadow_size = 24
	panel.add_theme_stylebox_override("panel", _accent_style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_kicker = _rich(13)
	box.add_child(_kicker)
	_title = Label.new()
	_title.theme_type_variation = "HeaderTitle"
	_title.add_theme_font_size_override("font_size", 28)
	box.add_child(_title)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(1180, 0)
	box.add_child(_description)
	_verdict = _rich(15)
	box.add_child(_verdict)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	box.add_child(columns)
	_chart = TrajectoryChart.new()
	_chart.custom_minimum_size = Vector2(760, 320)
	columns.add_child(_chart)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(400, 0)
	right.add_theme_constant_override("separation", 4)
	columns.add_child(right)
	var affinity_title := Label.new()
	affinity_title.theme_type_variation = "PanelTitle"
	affinity_title.text = "CIVILIZATIONAL MATRIX AFFINITY"
	right.add_child(affinity_title)
	_affinity_box = VBoxContainer.new()
	_affinity_box.add_theme_constant_override("separation", 3)
	right.add_child(_affinity_box)
	_stats = _rich(12)
	right.add_child(_stats)

	var buttons := HBoxContainer.new()
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
	visible = false


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
	visible = true


func _build_affinities(outcome: Dictionary) -> void:
	for child in _affinity_box.get_children():
		child.queue_free()
	var affinities: Dictionary = outcome.get("affinities", {})
	for candidate in VictoryMatrix.OUTCOMES:
		var outcome_id := String(candidate["id"])
		var affinity := float(affinities.get(outcome_id, 0.0))
		var chosen := outcome_id == String(outcome.get("id", ""))
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = "%d. %s" % [int(candidate["number"]), candidate["name"]]
		name_label.custom_minimum_size = Vector2(250, 0)
		name_label.add_theme_font_size_override("font_size", 12)
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
		_affinity_box.add_child(row)


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
