class_name WhyPopup
extends Control
## "Why did this change?": tap any number and this overlay explains it. It
## shows the metric's plain and technical names and what it means, its value
## and its change over a turn, and every cause the engine filed for that change
## (SimulationEngine.get_changes), grouped into
##   Your moves  the player's crisis answers, deferrals, deals, era goals and
##               their faction's directives and standing influence
##   Rivals      the other factions' directives, influence and collapses
##   The world   the coupled dynamics, paradigm shifts, emergent capabilities,
##               scenarios and unpredictable events
## each with its signed share and a bar in the era's good or bad color. A
## stepper walks back through the turns still in the cause ledger (this turn
## and up to seven before it).
##
##   why.present(engine, "alignment_drift")         # this turn
##   why.present(engine, "epistemic_trust", 12)      # turn 12
##
## Built on UiLayout.build_overlay(): centered on desktop, full width and
## scrolling on phones (set_compact). Tap outside, Close or Esc to dismiss.
##
## Causes are filed in English; [method cause_text] puts each one in the
## interface language for the screen (grouping reads the English).

signal closed

const DESKTOP_WIDTH := 540.0
## Turns before the current one the stepper can reach (the ledger keeps eight).
const MAX_EARLIER := WorldState.CHANGE_LOG_TURNS - 1
const GROUPS := ["yours", "rivals", "world"]
const GROUP_TITLES := {"yours": "Your moves", "rivals": "Rivals", "world": "The world"}
## Causes that are always the player's own doing.
const YOUR_PREFIXES := ["Crisis:", "Crisis deferred:", "Crisis broke:", "Deal with", "Era goal:"]
## How the engine words composed causes, most specific first: [format, what
## each %s is]. "title" is a crisis title, "label" a response, "name" a name
## the interface translates (a faction, directive, goal, shift or scenario).
const CAUSE_FORMATS := [
	["Crisis deferred: %s", ["title"]],
	["Crisis broke: %s", ["title"]],
	["Crisis: %s (%s)", ["title", "label"]],
	["Deal with %s", ["name"]],
	["Era goal: %s", ["name"]],
	["Paradigm shift: %s", ["name"]],
	["Emergent capability: %s", ["name"]],
	["Scenario: %s", ["name"]],
	["Collapse: %s", ["name"]],
	["%s (standing influence)", ["name"]],
	["%s: %s", ["name", "name"]],
]
const BAR_HEIGHT := 4.0
const TAP_SLOP := 12.0

var engine: SimulationEngine
## The metric or index being explained.
var metric_key := ""
## The turn on show.
var shown_turn := -1

var _compact := false
var _style: EraStyle
var _groups := {}
var _net := 0.0
var _frame: MarginContainer
var _shade: ColorRect
var _panel: PanelContainer
var _content: VBoxContainer
var _restyle_queued := false
var _relabel_queued := false
var _outside_press := Vector2.INF
## CAUSE_FORMATS as patterns (built once).
static var _cause_patterns: Array = []


func _ready() -> void:
	_frame = UiLayout.build_overlay(self, Color(0, 0, 0, 0.6))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade = get_child(0) as ColorRect
	_shade.gui_input.connect(_on_shade_input)
	(get_node("OverlayScroll") as Control).gui_input.connect(_on_shade_input)
	_panel = PanelContainer.new()
	_panel.name = "WhyPanel"
	_panel.theme_type_variation = "OverlayPanel"
	_frame.add_child(_panel)
	_content = VBoxContainer.new()
	_content.name = "WhyContent"
	_content.add_theme_constant_override("separation", 10)
	_panel.add_child(_content)
	resized.connect(_apply_layout)
	visible = false
	z_index = 2


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _panel != null and EraTheme.style_of(self) != _style and not _restyle_queued:
		_restyle_queued = true
		_restyle.call_deferred()
	elif what == NOTIFICATION_TRANSLATION_CHANGED and _panel != null and not _relabel_queued:
		_relabel_queued = true
		_relabel.call_deferred()


func _relabel() -> void:
	_relabel_queued = false
	if visible:
		_rebuild()


func _restyle() -> void:
	_restyle_queued = false
	_style = EraTheme.style_of(self)
	_shade.color = Color(_style.shade, maxf(_style.shade.a, 0.6))
	if visible:
		_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	_apply_layout()
	if visible:
		_rebuild()


## Explains [param key] (a metric or index) for [param turn] (-1: the
## engine's current turn).
func present(sim: SimulationEngine, key: String, turn: int = -1) -> void:
	engine = sim
	metric_key = key
	shown_turn = -1
	if engine != null and engine.world != null:
		shown_turn = engine.turn if turn < 0 else turn
	_style = EraTheme.style_of(self)
	_shade.color = Color(_style.shade, maxf(_style.shade.a, 0.6))
	_apply_layout()
	_rebuild()
	visible = true
	var scroll := get_node("OverlayScroll") as ScrollContainer
	scroll.scroll_vertical = 0


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## Shows [param turn] if the ledger still has it.
func show_turn(turn: int) -> void:
	if available_turns().has(turn):
		shown_turn = turn
		_rebuild()


## Steps one turn older (-1) or newer (+1) within available_turns().
func step_turn(direction: int) -> void:
	var turns := available_turns()
	var index := turns.find(shown_turn)
	if index < 0:
		return
	var next := index + signi(direction)
	if next >= 0 and next < turns.size():
		show_turn(turns[next])


## Turns the stepper can show, oldest first: the current turn and up to
## MAX_EARLIER earlier turns that are still in the cause ledger.
func available_turns() -> Array[int]:
	var turns: Array[int] = []
	if engine == null or engine.world == null:
		return turns
	for turn in range(maxi(0, engine.turn - MAX_EARLIER), engine.turn + 1):
		if turn == engine.turn or engine.world.change_log.has(turn):
			turns.append(turn)
	return turns


## The causes on show: {group: {"total": float, "causes": [{cause, delta}]}}
## for "yours", "rivals" and "world" (empty groups included).
func get_cause_groups() -> Dictionary:
	return _groups.duplicate(true)


## The change over the turn on show (the sum of its causes).
func get_net() -> float:
	return _net


## Splits [param changes] (SimulationEngine.get_changes rows) into the three
## groups; each keeps the ledger's order (largest first) and sums its share.
static func group_changes(changes: Array, player_role: String, display_names: Dictionary) -> Dictionary:
	var out := {}
	for group in GROUPS:
		out[group] = {"total": 0.0, "causes": []}
	for change in changes:
		var cause := String((change as Dictionary).get("cause", ""))
		var group := group_of(cause, player_role, display_names)
		(out[group]["causes"] as Array).append({"cause": cause, "delta": float(change.get("delta", 0.0))})
		out[group]["total"] = float(out[group]["total"]) + float(change.get("delta", 0.0))
	return out


## "yours", "rivals" or "world" for a cause string. [param display_names]
## maps faction ids to the names the engine files causes under.
static func group_of(cause: String, player_role: String, display_names: Dictionary) -> String:
	# Pass-and-play files each player's crisis answers, deals and goals under
	# their faction's name ("Crisis: … — Citizen Coalition").
	for faction_id in display_names:
		if cause.ends_with(" — " + String(display_names[faction_id])):
			return "yours" if String(faction_id) == player_role else "rivals"
	for prefix in YOUR_PREFIXES:
		if cause.begins_with(prefix):
			return "yours"
	var own := String(display_names.get(player_role, ""))
	if own != "" and _filed_under(cause, own):
		return "yours"
	for faction_id in display_names:
		if String(faction_id) == player_role:
			continue
		var name_text := String(display_names[faction_id])
		if _filed_under(cause, name_text) or cause == "Collapse: " + name_text:
			return "rivals"
	return "world"


## True when [param key] moving by [param delta] helps the world (trust,
## provenance and the safety net up; everything else down).
static func improves(key: String, delta: float) -> bool:
	if key == WorldState.PROVENANCE_COVERAGE or key == WorldState.SAFETY_NET_COVERAGE:
		return delta > 0.0
	return UiFormat.is_improvement(key, delta)


static func _filed_under(cause: String, faction_name: String) -> bool:
	return cause.begins_with(faction_name + ":") or cause.begins_with(faction_name + " (")


## [param cause] (as the engine filed it, in English) in the interface
## language: a known cause by name, a composed one by its CAUSE_FORMATS
## pattern with its parts translated (crisis titles through
## DilemmaDeck.localize_title), and a pass-and-play " — Faction" suffix kept.
## Unknown causes come back as they are.
static func cause_text(cause: String) -> String:
	if I18n.current() == I18n.SOURCE:
		return cause
	var suffix := ""
	var split := cause.rfind(" — ")
	if split > 0:
		suffix = " — " + I18n.t(cause.substr(split + 3))
		cause = cause.substr(0, split)
	var direct := I18n.t(cause)
	if direct != cause:
		return direct + suffix
	if _cause_patterns.is_empty():
		for entry in CAUSE_FORMATS:
			_cause_patterns.append([RegEx.create_from_string(_format_regex(String(entry[0]))), entry[0], entry[1]])
	for pattern in _cause_patterns:
		var found := (pattern[0] as RegEx).search(cause)
		if found == null:
			continue
		var kinds: Array = pattern[2]
		var parts := []
		for i in kinds.size():
			var part := found.get_string(i + 1)
			parts.append(DilemmaDeck.localize_title(part) if String(kinds[i]) == "title" else I18n.t(part))
		return I18n.t(String(pattern[1])) % parts + suffix
	return cause + suffix


## A regex for a "%s" format: each %s matches any text.
static func _format_regex(format: String) -> String:
	var out := "^"
	var pieces := format.split("%s")
	for i in pieces.size():
		if i > 0:
			out += "(.+)"
		for character in pieces[i]:
			out += ("\\" + character) if "\\^$.|?*+()[]{}".contains(character) else character
	return out + "$"


# --- Values ------------------------------------------------------------------------------

## The value at the end of [param turn] (now, for the current turn).
func value_after(turn: int) -> float:
	if engine == null or engine.world == null or not WorldState.is_tracked_key(metric_key):
		return 0.0
	if turn >= engine.turn:
		return engine.world.get_value(metric_key)
	var history: Array = engine.world.history
	for i in range(history.size() - 1, -1, -1):
		var entry: Dictionary = history[i]
		if int(entry.get("turn", -1)) == turn and entry.has(metric_key):
			return float(entry[metric_key])
	var value := engine.world.get_value(metric_key)
	for later in range(turn + 1, engine.turn + 1):
		value -= engine.world.net_change(later, metric_key)
	return value


func _display_names() -> Dictionary:
	var names := {}
	if engine == null:
		return names
	for faction_id in engine.factions:
		names[faction_id] = (engine.factions[faction_id] as ActorBase).display_name
	return names


# --- Building ----------------------------------------------------------------------------

func _apply_layout() -> void:
	if _panel == null:
		return
	_panel.custom_minimum_size = Vector2(UiLayout.panel_width(size.x if size.x > 1.0 else get_viewport_rect().size.x,
		DESKTOP_WIDTH, _compact), 0)
	UiLayout.set_overlay_margin(_frame, _compact)


func _rebuild() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_groups = {}
	_net = 0.0
	if _style == null:
		_style = EraTheme.style_of(self)
	var s := _style
	var valid := engine != null and engine.world != null and WorldState.is_tracked_key(metric_key)
	_content.add_child(_header(s))
	if not valid:
		_content.add_child(_text(s, tr("Nothing to explain yet."), 13, s.text_dim, true))
		return
	var changes := engine.get_changes(metric_key, shown_turn)
	_groups = group_changes(changes, engine.player_role, _display_names())
	for change in changes:
		_net += float(change["delta"])
	var explanation := PlainLanguage.explain(metric_key)
	if explanation != "":
		_content.add_child(_text(s, explanation, 13, s.text_dim, true))
	_content.add_child(_value_row(s))
	_content.add_child(_stepper(s))
	var separator := HSeparator.new()
	_content.add_child(separator)
	var largest := 0.0
	for change in changes:
		largest = maxf(largest, absf(float(change["delta"])))
	var any := false
	for group in GROUPS:
		var causes: Array = _groups[group]["causes"]
		if causes.is_empty():
			continue
		any = true
		_content.add_child(_group_block(s, group, causes, float(_groups[group]["total"]), largest))
	if not any:
		var quiet := tr("Nothing moved it this turn.") if shown_turn == engine.turn else tr("Nothing moved it that turn.")
		_content.add_child(_text(s, quiet, 13, s.text_dim, true))
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close"
	close_button.theme_type_variation = "AccentButton"
	close_button.custom_minimum_size = Vector2(0, 44 if _compact else 36)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END if not _compact else Control.SIZE_EXPAND_FILL
	close_button.pressed.connect(close)
	_content.add_child(close_button)
	UiLayout.pass_touch_through(_panel)


func _header(s: EraStyle) -> Control:
	var row := HBoxContainer.new()
	row.name = "Header"
	row.add_theme_constant_override("separation", 12)
	var glyph := Glyphs.for_metric(metric_key) if WorldState.is_metric(metric_key) else "intel"
	var tile := TextureRect.new()
	tile.texture = Glyphs.tile(glyph, 40, Color(s.metric_color(metric_key), 0.2), s.metric_color(metric_key), 10 if s.era != 3 else 20)
	tile.custom_minimum_size = Vector2(40, 40)
	tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(tile)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var plain := PlainLanguage.enabled()
	var title := PlainLanguage.plain_name(metric_key) if plain else PlainLanguage.technical_name(metric_key)
	var subtitle := PlainLanguage.technical_name(metric_key) if plain else PlainLanguage.plain_name(metric_key)
	var title_label := _text(s, title, 20, s.text_bright, true, s.font_display)
	title_label.name = "Title"
	names.add_child(title_label)
	var subtitle_label := _text(s, s.label(tr("Why it changed")) + " · " + subtitle, 12, s.text_dim, true)
	subtitle_label.name = "Subtitle"
	names.add_child(subtitle_label)
	row.add_child(names)
	var close_button := Button.new()
	close_button.name = "CloseIcon"
	close_button.icon = Glyphs.texture("close", 18)
	close_button.theme_type_variation = "GhostButton"
	close_button.tooltip_text = "Close"
	close_button.custom_minimum_size = Vector2(44, 44) if _compact else Vector2(36, 36)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_button.pressed.connect(close)
	row.add_child(close_button)
	return row


## The value, the change over the turn and where it moved from.
func _value_row(s: EraStyle) -> Control:
	var row := HFlowContainer.new()
	row.name = "ValueRow"
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 2)
	var after := value_after(shown_turn)
	var before := after - _net
	var value := _text(s, "%d" % roundi(after), 34, s.text_bright, false, s.font_mono_bold)
	value.name = "Value"
	row.add_child(value)
	var changed := absf(_net) >= 0.05
	var tone := s.text_dim
	if changed:
		tone = s.good if improves(metric_key, _net) else s.bad
	var arrow := ("▲ " if _net > 0.0 else "▼ ") if changed else ""
	var delta := _text(s, arrow + (UiFormat.signed(snappedf(_net, 0.1)) if changed else tr("no change")), 16, tone, false, s.font_mono_bold)
	delta.name = "Change"
	delta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(delta)
	var span := _text(s, "%s → %s" % [_one_decimal(before), _one_decimal(after)], 12, s.text_dim, false, s.font_mono)
	span.name = "Span"
	span.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(span)
	return row


func _stepper(s: EraStyle) -> Control:
	var row := HBoxContainer.new()
	row.name = "Stepper"
	row.add_theme_constant_override("separation", 6)
	var turns := available_turns()
	var index := turns.find(shown_turn)
	var older := _step_button("chevron_left", tr("Earlier turn"), index > 0)
	older.name = "Older"
	older.pressed.connect(step_turn.bind(-1))
	row.add_child(older)
	var label := _text(s, _turn_text(), 13, s.text, false, s.font_ui_bold)
	label.name = "TurnLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)
	var newer := _step_button("chevron_right", tr("Later turn"), index >= 0 and index < turns.size() - 1)
	newer.name = "Newer"
	newer.pressed.connect(step_turn.bind(1))
	row.add_child(newer)
	return row


func _step_button(glyph: String, tip: String, enabled: bool) -> Button:
	var button := Button.new()
	button.icon = Glyphs.texture(glyph, 16)
	button.theme_type_variation = "ChipButton"
	button.tooltip_text = tip
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(48, 44) if _compact else Vector2(40, 34)
	return button


## "This turn so far · H1 2027", "Last turn · H2 2026" or "Turn 9 · H2 2030".
func _turn_text() -> String:
	var year := SimConstants.year_for_turn(shown_turn)
	var date := tr("H%d %d") % [1 if year - floorf(year) < 0.25 else 2, int(floorf(year))]
	if shown_turn == 0:
		return tr("Campaign start · %s") % date
	if shown_turn == engine.turn:
		var unfinished := not engine.is_ended() and engine.phase != SimulationEngine.Phase.IDLE
		return "%s · %s" % [tr("This turn so far") if unfinished else tr("This turn"), date]
	if shown_turn == engine.turn - 1:
		return tr("Last turn · %s") % date
	return tr("Turn %d · %s") % [shown_turn, date]


func _group_block(s: EraStyle, group: String, causes: Array, total: float, largest: float) -> Control:
	var block := VBoxContainer.new()
	block.name = "Group_" + group
	block.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := _text(s, s.label(tr(String(GROUP_TITLES[group]))), 12, s.accent if s.era != 1 else s.text_bright, false, s.font_ui_bold)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var sum := _text(s, UiFormat.signed(snappedf(total, 0.1)), 12, _tone(s, total), false, s.font_mono_bold)
	sum.name = "Total"
	head.add_child(sum)
	block.add_child(head)
	for change in causes:
		block.add_child(_cause_row(s, String(change["cause"]), float(change["delta"]), largest))
	return block


## One cause: its text and signed share, with a bar under it scaled to the
## largest cause of the turn.
func _cause_row(s: EraStyle, cause: String, delta: float, largest: float) -> Control:
	var row := VBoxContainer.new()
	row.name = "Cause"
	row.set_meta("cause", cause)
	row.set_meta("delta", delta)
	row.add_theme_constant_override("separation", 3)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var label := _text(s, cause_text(cause), 13, s.text, true)
	label.name = "CauseText"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	var amount := _text(s, UiFormat.signed(snappedf(delta, 0.1)), 13, _tone(s, delta), false, s.font_mono)
	amount.name = "CauseDelta"
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.custom_minimum_size = Vector2(52, 0)
	amount.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line.add_child(amount)
	row.add_child(line)
	var bar := ShareBar.new()
	bar.share = absf(delta) / largest if largest > 0.0 else 0.0
	bar.color = _tone(s, delta)
	bar.track = Color(s.text, 0.07)
	bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	row.add_child(bar)
	return row


func _tone(s: EraStyle, delta: float) -> Color:
	if absf(delta) < 0.05:
		return s.text_dim
	return s.good if improves(metric_key, delta) else s.bad


## A tap outside the panel closes it (a drag that scrolls does not).
func _on_shade_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	var outside := not _panel.get_global_rect().has_point(button.global_position)
	if button.pressed:
		_outside_press = button.global_position if outside else Vector2.INF
		return
	var tapped := _outside_press != Vector2.INF and button.global_position.distance_to(_outside_press) <= TAP_SLOP
	_outside_press = Vector2.INF
	if outside and tapped:
		close()


static func _one_decimal(value: float) -> String:
	return "%.1f" % value


static func _text(s: EraStyle, value: String, base_size: int, color: Color, wrap: bool, font: Font = null) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font", font if font != null else s.font_ui)
	EraTheme.set_scaled_font_size(label, base_size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## A thin share bar: [member share] of the width in [member color].
class ShareBar extends Control:
	var share := 0.0
	var color := Color.WHITE
	var track := Color(1, 1, 1, 0.07)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), track)
		var width := size.x * clampf(share, 0.0, 1.0)
		if width > 0.5:
			draw_rect(Rect2(Vector2.ZERO, Vector2(maxf(width, 2.0), size.y)), color)
