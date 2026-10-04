class_name GoalsPanel
extends PanelContainer
## The current player's era goals (EraGoals): for each goal of this era, the
## goal, its condition in plain words ("Keep capital at $150B or more through
## 2035", "Reach community strength 60 before 2036", "End the era with ..."),
## a bar with the live value against the threshold, the reward and the status
## (coming up, in play, met or missed) in the era's good and bad colors. The
## next era's goals follow as "coming up".
##
##   panel.refresh(engine)      # after each telemetry update and player phase
##   panel.set_compact(true)    # phones: one line per goal
##
## Desktop draws a card; compact layouts draw one line per goal (status dot,
## condition, bar and value). Colors, shapes and text size follow the era
## theme; subject names follow the plain-language setting. Text is in the
## interface language (the dashboard refreshes the panel when it changes).

const ACTIVE_LABELS := {
	EraGoals.UPCOMING: "Coming up", EraGoals.ACTIVE: "In play", EraGoals.MET: "Met", EraGoals.FAILED: "Missed",
}
## Last calendar year of each era, and the year the next one begins.
const ERA_LAST_YEAR := {1: 2035, 2: 2049, 3: 2076}
const ERA_END_YEAR := {1: 2036, 2: 2050, 3: 2076}
const COMPACT_BAR_WIDTH := 44.0

var compact := false

var _style: EraStyle
var _rows: Array = []
var _role := ""
var _era := 1
var _box: VBoxContainer
var _restyle_queued := false


func _init() -> void:
	name = "GoalsPanel"
	theme_type_variation = "CardPanel"
	_box = VBoxContainer.new()
	_box.name = "Goals"
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)
	GameSettings.instance().changed.connect(_on_setting_changed)


func _ready() -> void:
	_style = EraTheme.style_of(self)
	_rebuild()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready() and EraTheme.style_of(self) != _style and not _restyle_queued:
		_restyle_queued = true
		_restyle.call_deferred()


func _restyle() -> void:
	_restyle_queued = false
	_style = EraTheme.style_of(self)
	_rebuild()


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "plain_language" and is_node_ready():
		_rebuild()


## One line per goal (phones and tablets) or the full card (desktop).
func set_compact(enabled: bool) -> void:
	if compact == enabled:
		return
	compact = enabled
	theme_type_variation = "InsetPanel" if compact else "CardPanel"
	if is_node_ready():
		_rebuild()


## Reads the player's goals from [param engine]: this era's and the next's.
func refresh(engine: SimulationEngine) -> void:
	_rows = []
	if engine == null or engine.world == null:
		_role = ""
		_rebuild()
		return
	_role = engine.player_role
	_era = SimConstants.era_for_year(engine.get_year())
	for era in [_era, _era + 1]:
		if era > 3:
			continue
		for row in engine.goals.status_for(_role, era):
			var info: Dictionary = (row as Dictionary).duplicate()
			info["display_status"] = display_status(info, _era)
			info["current"] = EraGoals.subject_value(info, engine, _role)
			info.merge(progress(info, float(info["current"]), _role), true)
			info["condition"] = condition_text(info, _role)
			info["condition_short"] = condition_text(info, _role, true)
			_rows.append(info)
	_rebuild()


## The rows on show: EraGoals.status_for() rows plus display_status, current
## (the subject's value now), fraction, threshold_fraction, holds, scale,
## condition and condition_short.
func get_rows() -> Array:
	return _rows.duplicate(true)


## Goal rows of this era (the rest are coming up).
func current_rows() -> Array:
	return _rows.filter(func(row: Dictionary) -> bool: return int(row["era"]) == _era)


# --- Wording and progress ------------------------------------------------------------

## "upcoming", "active", "met" or "failed" for a row while [param current_era]
## is playing (a goal of the current era is in play until it settles).
static func display_status(row: Dictionary, current_era: int) -> String:
	var status := String(row.get("status", EraGoals.UPCOMING))
	if status == EraGoals.MET or status == EraGoals.FAILED:
		return status
	var era := int(row.get("era", current_era))
	if era == current_era:
		return EraGoals.ACTIVE
	return EraGoals.UPCOMING if era > current_era else EraGoals.FAILED


static func status_label(status: String) -> String:
	return I18n.t(String(ACTIVE_LABELS.get(status, status.capitalize())))


## The condition in plain words: "Keep capital at $150B or more through 2035",
## "Reach community strength 60 before 2036", "End the era with goodwill at 40
## or more". [param short] uses ≥/≤ for one-line layouts.
static func condition_text(row: Dictionary, role: String, short: bool = false) -> String:
	var era := int(row.get("era", 1))
	var values := {"subject": subject_name(row.get("subject", {})),
		"amount": format_value(row.get("subject", {}), float(row.get("value", 0.0)), role)}
	var at_least := String(row.get("op", ">=")) == ">="
	var template := ""
	match String(row.get("type", "end")):
		"hold":
			values["year"] = int(ERA_LAST_YEAR[era])
			if short:
				template = I18n.t("Keep {subject} ≥ {amount} to {year}") if at_least else I18n.t("Keep {subject} ≤ {amount} to {year}")
			else:
				template = I18n.t("Keep {subject} at {amount} or more through {year}") if at_least \
					else I18n.t("Keep {subject} at {amount} or below through {year}")
		"reach":
			values["year"] = int(ERA_END_YEAR[era])
			if at_least:
				template = I18n.t("Reach {subject} {amount} before {year}") if era < 3 else I18n.t("Reach {subject} {amount} by {year}")
			else:
				template = I18n.t("Bring {subject} down to {amount} before {year}") if era < 3 \
					else I18n.t("Bring {subject} down to {amount} by {year}")
		_:
			if short:
				template = I18n.t("End era with {subject} ≥ {amount}") if at_least else I18n.t("End era with {subject} ≤ {amount}")
			else:
				template = I18n.t("End the era with {subject} at {amount} or more") if at_least \
					else I18n.t("End the era with {subject} at {amount} or below")
	return template.format(values)


## The subject's name in running text ("capital", "ASI discovery", "public
## trust"), plain when the plain-language setting is on.
static func subject_name(subject: Dictionary) -> String:
	var text := ""
	if subject.has("resource"):
		text = UiFormat.resource_name(String(subject["resource"]))
	elif subject.has("metric"):
		text = UiFormat.metric_name(String(subject["metric"]))
	else:
		text = UiFormat.metric_short(String(subject.get("index", "")))
	# German writes its nouns with a capital.
	if I18n.current() == "de":
		return text
	var words: Array[String] = []
	for word in text.split(" ", false):
		# Lower-case ordinary capitalized words; keep acronyms like ASI or FLOPs.
		var rest := word.substr(1)
		words.append(word.to_lower() if rest == rest.to_lower() else word)
	return " ".join(words)


## A subject value as the interface prints it ("$150B", "60", "4.5").
static func format_value(subject: Dictionary, amount: float, role: String) -> String:
	if subject.has("resource"):
		var key := String(subject["resource"])
		if String(UiFormat.resource_info(role, key).get("unit", "")) == "$B":
			return UiFormat.format_resource(role, key, amount)
	if absf(amount - roundf(amount)) < 0.05:
		return "%d" % roundi(amount)
	return "%.1f" % amount


## {fraction, threshold_fraction, holds, scale}: where [param amount] and the
## goal's threshold sit on the bar, and whether the condition holds now.
static func progress(row: Dictionary, amount: float, role: String) -> Dictionary:
	var threshold := float(row.get("value", 0.0))
	var subject: Dictionary = row.get("subject", {})
	var scale := 100.0
	if subject.has("resource"):
		var info := UiFormat.resource_info(role, String(subject["resource"]))
		if float(info.get("max", 100.0)) > 100.0:
			scale = maxf(maxf(threshold * 2.0, amount * 1.15), 1.0)
	var holds := amount >= threshold if String(row.get("op", ">=")) == ">=" else amount <= threshold
	return {"fraction": clampf(amount / scale, 0.0, 1.0), "threshold_fraction": clampf(threshold / scale, 0.0, 1.0),
		"holds": holds, "scale": scale}


# --- Building ---------------------------------------------------------------------------

func _rebuild() -> void:
	if _style == null:
		_style = EraTheme.style_of(self)
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	_box.add_theme_constant_override("separation", 4 if compact else 8)
	var s := _style
	if not compact:
		_box.add_child(_header(s))
	var current := current_rows()
	var coming := _rows.filter(func(row: Dictionary) -> bool: return int(row["era"]) > _era)
	if current.is_empty():
		var empty := _text(s, tr("No goals this era.") if _role != "" else tr("Goals appear when a campaign starts."), 12, s.text_dim, false)
		_box.add_child(empty)
	for row in current:
		_box.add_child(_compact_row(s, row) if compact else _full_row(s, row))
	for row in coming:
		_box.add_child(_coming_row(s, row))
	UiLayout.pass_touch_through(self)


func _header(s: EraStyle) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(Glyphs.icon("flag", 16, s.accent))
	var title := _text(s, s.label(tr("Era %s goal") % EraStyle.ROMAN.get(_era, "I")), 14, s.text_bright, false, s.font_ui_bold)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(title)
	row.add_child(_text(s, String(EraStyle.SPANS.get(_era, "")), 11, s.text_dim, false, s.font_mono))
	return row


## Desktop: status chip and condition, the goal, the bar with the value, the reward.
func _full_row(s: EraStyle, row: Dictionary) -> Control:
	var status := String(row["display_status"])
	var tone := _status_color(s, status, bool(row["holds"]))
	var card := VBoxContainer.new()
	card.name = "Goal_" + String(row["id"])
	card.add_theme_constant_override("separation", 5)
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 8)
	meta.add_child(_chip(s, status))
	var condition := _text(s, String(row["condition"]), 11, s.text_dim, false, s.font_mono)
	condition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	condition.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	condition.tooltip_text = String(row["condition"])
	condition.mouse_filter = Control.MOUSE_FILTER_PASS
	meta.add_child(condition)
	card.add_child(meta)
	card.add_child(_text(s, tr(String(row["text"])), 14, s.text_bright, true, s.font_ui_bold))
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 10)
	var bar := GoalBar.new()
	bar.name = "Bar"
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.configure(s, float(row["fraction"]), float(row["threshold_fraction"]), tone, 6.0)
	bar_row.add_child(bar)
	bar_row.add_child(_text(s, _value_line(row), 11, s.text, false, s.font_mono))
	card.add_child(bar_row)
	var reward := tr(String(row.get("reward_text", "")))
	if reward != "":
		var reward_row := HBoxContainer.new()
		reward_row.add_theme_constant_override("separation", 6)
		reward_row.add_child(Glyphs.icon("seal_check" if status == EraGoals.MET else "seal", 14,
			s.good if status == EraGoals.MET else s.text_dim, 1.6))
		var reward_label := _text(s, (tr("Reward paid: %s") if status == EraGoals.MET else tr("Reward: %s")) % reward, 12,
			s.good if status == EraGoals.MET else s.text_dim, true)
		reward_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reward_row.add_child(reward_label)
		card.add_child(reward_row)
	return card


## Phones: status dot, the short condition, a small bar and the value.
func _compact_row(s: EraStyle, row: Dictionary) -> Control:
	var status := String(row["display_status"])
	var tone := _status_color(s, status, bool(row["holds"]))
	var line := HBoxContainer.new()
	line.name = "Goal_" + String(row["id"])
	line.add_theme_constant_override("separation", 8)
	line.custom_minimum_size = Vector2(0, 26)
	line.tooltip_text = "%s · %s · %s" % [status_label(status), tr(String(row["text"])), tr(String(row.get("reward_text", "")))]
	line.add_child(_dot(tone, true))
	var text := _text(s, String(row["condition_short"]), 12, s.text_bright, false)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(text)
	var bar := GoalBar.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(COMPACT_BAR_WIDTH, 0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.configure(s, float(row["fraction"]), float(row["threshold_fraction"]), tone, 5.0)
	line.add_child(bar)
	var value := _text(s, _value_text(row), 12, tone if status != EraGoals.ACTIVE else s.text, false, s.font_mono)
	line.add_child(value)
	return line


## Next era's goal, one line: "Next era · End Era II with ...".
func _coming_row(s: EraStyle, row: Dictionary) -> Control:
	var line := HBoxContainer.new()
	line.name = "Coming_" + String(row["id"])
	line.add_theme_constant_override("separation", 8)
	line.add_child(_dot(s.text_dim, false))
	var text := _text(s, "%s · %s" % [s.label(tr("Next era")), tr(String(row["text"]))], 11 if not compact else 12, s.text_dim, false)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.tooltip_text = tr("%s · Reward: %s") % [String(row["condition"]), tr(String(row.get("reward_text", "")))]
	text.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_child(text)
	return line


func _value_line(row: Dictionary) -> String:
	var status := String(row["display_status"])
	var now := _value_text(row)
	if status == EraGoals.MET or status == EraGoals.FAILED:
		var turn := int(row.get("turn", -1))
		var when := (" · %d" % int(floor(SimConstants.year_for_turn(turn)))) if turn >= 0 else ""
		return tr("%s%s · now %s") % [status_label(status), when, now]
	var need := format_value(row["subject"], float(row["value"]), _role)
	return tr("now %s · need %s %s") % [now, ("≥" if String(row["op"]) == ">=" else "≤"), need]


func _value_text(row: Dictionary) -> String:
	return format_value(row["subject"], float(row["current"]), _role)


static func _status_color(s: EraStyle, status: String, holds: bool) -> Color:
	match status:
		EraGoals.MET:
			return s.good
		EraGoals.FAILED:
			return s.bad
		EraGoals.ACTIVE:
			return s.good if holds else s.bad
	return s.text_dim


func _chip(s: EraStyle, status: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = "Status"
	var color := s.accent
	match status:
		EraGoals.MET:
			color = s.good
		EraGoals.FAILED:
			color = s.bad
		EraGoals.UPCOMING:
			color = s.text_dim
	chip.add_theme_stylebox_override("panel", EraTheme.box(Color(color, 0.14), Color(color, 0.5), 1, 999, 8, 2, s.corner_detail))
	var label := _text(s, s.label(status_label(status)), 10, color, false, s.font_ui_bold)
	label.name = "StatusLabel"
	chip.add_child(label)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return chip


func _dot(color: Color, filled: bool) -> Control:
	var dot := GoalDot.new()
	dot.color = color
	dot.filled = filled
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return dot


static func _text(s: EraStyle, value: String, base_size: int, color: Color, wrap: bool, font: Font = null) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font", font if font != null else s.font_ui)
	EraTheme.set_scaled_font_size(label, base_size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


# --- Parts -------------------------------------------------------------------------------

## A thin bar: the value as a fill and the threshold as a tick.
class GoalBar extends Control:
	var fraction := 0.0
	var threshold := 0.0
	var color := Color.WHITE
	var track := Color(1, 1, 1, 0.12)
	var tick := Color.WHITE
	var thickness := 6.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func configure(s: EraStyle, value_fraction: float, threshold_fraction: float, fill: Color, height: float) -> void:
		fraction = clampf(value_fraction, 0.0, 1.0)
		threshold = clampf(threshold_fraction, 0.0, 1.0)
		color = fill
		track = Color(s.text, 0.12)
		tick = s.text_bright
		thickness = height
		custom_minimum_size.y = height + 6.0
		queue_redraw()

	func _draw() -> void:
		var y := (size.y - thickness) * 0.5
		var radius := thickness * 0.5
		var bar := Rect2(0.0, y, size.x, thickness)
		_capsule(bar, track, radius)
		if fraction > 0.0:
			_capsule(Rect2(bar.position, Vector2(maxf(thickness, size.x * fraction), thickness)), color, radius)
		var x := clampf(size.x * threshold, 1.0, size.x - 1.0)
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), tick, 2.0)

	func _capsule(rect: Rect2, fill: Color, radius: float) -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = fill
		box.set_corner_radius_all(roundi(radius))
		box.anti_aliasing = true
		draw_style_box(box, rect)


## A status dot (filled) or ring (coming up).
class GoalDot extends Control:
	var color := Color.WHITE
	var filled := true

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 1.0
		if filled:
			draw_circle(center, radius, color)
		else:
			draw_arc(center, radius, 0.0, TAU, 20, color, 1.5, true)
