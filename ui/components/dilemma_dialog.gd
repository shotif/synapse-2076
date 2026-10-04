class_name DilemmaDialog
extends Control
## Crisis card overlay (PRD section 6, phase 3), built to be read at a glance:
## the six vitals on top (VitalsStrip), the crisis as a card (CrisisCard) and
## every response as a row with its key, cost and effect glyphs.
##
## Swipe or drag the card left or right (or press ← / →) for the first two
## responses, tap a row (or press C, ↓ or 1-4), and preview a response on the
## vitals by hovering its row (mouse), holding it (touch) or dragging the card
## part of the way. Deferring returns the card two turns later, escalated.
##
## Desktop: a 980 px composition with the vitals across the top, the card on
## the left and the responses on the right. Compact: vitals, card and
## responses stacked in the scrolling overlay (side by side again on wide
## landscape screens). Everything follows the era theme (EraTheme).

signal option_chosen(option_id: String)
## The card was swiped (or sent with ← / →) toward a response, as it starts
## to fly off: -1 left, +1 right (CrisisCard.swiped, passed on).
## option_chosen follows once the card has left.
signal swiped(direction: int)
## A response was tapped, clicked or picked with its key instead of swiped,
## as the card starts to leave; option_chosen follows.
signal option_pressed(option_id: String)

const DESKTOP_WIDTH := 980.0
const DESKTOP_CARD_WIDTH := 420.0
const DESKTOP_ART_HEIGHT := 190.0
const COMPACT_ART_HEIGHT := 150.0
const WIDE_ART_HEIGHT := 128.0
## Phones and portrait tablets stack the card above the responses, at most
## this wide; wider compact screens put them side by side.
const STACK_MAX_WIDTH := 560.0
const CARD_MAX_WIDTH := 520.0
const WIDE_COMPACT_WIDTH := 720.0
const ROW_HEIGHT := 56.0
## A swipe commits past SWIPE_THRESHOLD px or SWIPE_FRACTION of the card
## width, whichever is smaller; past PREVIEW_DRAG it previews the response.
const SWIPE_THRESHOLD := 110.0
const SWIPE_FRACTION := 0.3
const PREVIEW_DRAG := 30.0
## Movement before a drag picks an axis (horizontal swipes the card, vertical
## scrolls the overlay).
const DRAG_SLOP := 8.0
const TAP_SLOP := 12.0
const HOLD_TIME := 0.32
const FLY_TIME := 0.3
const SNAP_TIME := 0.25
const ENTER_TIME := 0.45
## Card tilt in degrees per pixel of horizontal drag.
const TILT_PER_PX := 1.0 / 18.0
const KEY_GLYPHS := {"←": "arrow_left", "→": "arrow_right", "↓": "arrow_down"}

enum Axis { NONE, HORIZONTAL, VERTICAL }

var current_card := {}

var _compact := false
var _resources := {}
var _role := ""
var _style: EraStyle
var _rows: Array[Button] = []
var _tween: Tween
var _leaving := false
# Card drag.
var _dragging := false
var _drag_axis := Axis.NONE
var _drag_start := Vector2.ZERO
var _drag_dx := 0.0
var _drag_pick := -1
# Row previews.
var _hover_row: Button
var _hold_row: Button
var _hold_shown := false
var _hold_origin := Vector2.ZERO
var _suppress_click := false
# Row styles, rebuilt for each era.
var _row_normal: StyleBoxFlat
var _row_on: StyleBoxFlat
var _row_disabled: StyleBoxFlat
var _row_focus: StyleBoxFlat
var _badge_box: StyleBoxFlat
var _badge_text := Color.WHITE
## [year, character scores, memories] for the card's character badge.
var _story_context: Array = []

var _shade: ColorRect
var _backdrop: Backdrop
var _scroll: ScrollContainer
var _frame: MarginContainer
var _column: VBoxContainer
var _vitals: VitalsStrip
var _info_row: HBoxContainer
var _info_label: Label
var _money_label: Label
var _body: BoxContainer
var _slot: CardSlot
var _card: CrisisCard
var _options: VBoxContainer
var _rows_box: VBoxContainer
var _help_label: Label
var _hold_timer: Timer


func _ready() -> void:
	_frame = UiLayout.build_overlay(self, Color(0, 0, 0, 0.86))
	for child in get_children():
		if child is ColorRect:
			_shade = child
			break
	_scroll = get_node("OverlayScroll")
	_backdrop = Backdrop.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	move_child(_backdrop, _scroll.get_index())

	_column = VBoxContainer.new()
	_column.name = "CrisisColumn"
	_frame.add_child(_column)
	_vitals = VitalsStrip.new()
	_vitals.name = "Vitals"
	_column.add_child(_vitals)
	_build_info_row()
	_body = BoxContainer.new()
	_body.name = "CrisisBody"
	_column.add_child(_body)
	_build_card()
	_build_options()

	_hold_timer = Timer.new()
	_hold_timer.one_shot = true
	_hold_timer.timeout.connect(_on_hold_timeout)
	add_child(_hold_timer)
	resized.connect(_apply_layout)
	visible = false
	_apply_style()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _column != null:
		_apply_style()
		if visible and not current_card.is_empty():
			_fill()
			_build_rows()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and _column != null and not visible:
		_reset_motion()


func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	_apply_layout()
	if visible and not current_card.is_empty():
		_fill()
		_build_rows()


## Shows [param card] for [param role]; responses the player cannot afford
## with [param resources] are disabled. [param metrics] (the six macro
## metrics) fills the vitals strip; without it the strip is hidden.
func present(card: Dictionary, resources: Dictionary, role: String, metrics: Dictionary = {}) -> void:
	_reset_motion()
	current_card = card
	_resources = resources
	_role = role
	_vitals.visible = not metrics.is_empty()
	if not metrics.is_empty():
		_vitals.set_values(metrics)
	_vitals.set_preview({})
	_fill()
	_build_rows()
	_apply_layout()
	if _scroll != null:
		_scroll.scroll_vertical = 0
	visible = true
	_play_entrance()


func close() -> void:
	_reset_motion()
	visible = false


## Commits a response at once (tests, tooling): hides the dialog and emits
## option_chosen synchronously.
func choose(option_id: String) -> void:
	_reset_motion()
	visible = false
	option_chosen.emit(option_id)


## The vitals strip above the card.
func get_vitals() -> VitalsStrip:
	return _vitals


## The card on show.
func get_card() -> CrisisCard:
	return _card


## The column of response rows and the help line under them.
func get_responses() -> Control:
	return _options


## Story context for the card's character badge (CrisisCard.set_story_context):
## call it before present() with the campaign year, DilemmaDeck.characters and
## {character id: memory line}.
func set_story_context(year: float, character_scores: Dictionary, memories: Dictionary) -> void:
	_story_context = [year, character_scores, memories]
	if _card != null:
		_card.set_story_context(year, character_scores, memories)


## Previews a response on the vitals as if its row were hovered (tests,
## tooling); "" clears it.
func preview_option(option_id: String) -> void:
	_hover_row = _row_for(option_id)
	_refresh_preview()


## Effects other than the six metrics, as short phrases ("growth ×0.5
## (2 turns)", "ASI Discovery +6", "EF +0.8").
static func other_effects(effects: Dictionary, role: String) -> Array[String]:
	var parts: Array[String] = []
	var indices: Dictionary = effects.get("indices", {})
	for key in indices:
		if absf(float(indices[key])) >= 0.05:
			parts.append("%s %s" % [UiFormat.metric_short(key), UiFormat.signed(float(indices[key]))])
	var own: Dictionary = effects.get("self", {})
	for key in own:
		parts.append(_resource_change(role, key, float(own[key])))
	var tech: Dictionary = effects.get("tech", {})
	if tech.has("growth_mult"):
		var turns := int(tech.get("growth_turns", 1))
		parts.append("growth ×%s (%d turn%s)" % [str(snappedf(float(tech["growth_mult"]), 0.01)), turns, "" if turns == 1 else "s"])
	if tech.has("capability_investment"):
		parts.append("capability %s" % UiFormat.signed(float(tech["capability_investment"])))
	if tech.has("safety_investment"):
		parts.append("safety %s" % UiFormat.signed(float(tech["safety_investment"])))
	if tech.has("alignment_tax"):
		parts.append("alignment tax %d%%" % roundi(float(tech["alignment_tax"]) * 100.0))
	var compute: Dictionary = effects.get("compute", {})
	if compute.has("grid_capacity_gw"):
		parts.append("grid %s GW" % UiFormat.signed(float(compute["grid_capacity_gw"])))
	if compute.has("grid_damage"):
		parts.append("grid −%d%%" % roundi(float(compute["grid_damage"]) * 100.0))
	var targets: Dictionary = effects.get("factions", {})
	for target_id in targets:
		var changes: Dictionary = targets[target_id]
		for key in changes:
			parts.append("%s %s" % [String(CrisisCard.FACTION_NAMES.get(target_id, String(target_id))),
				_resource_change(String(target_id), key, float(changes[key]))])
	return parts


static func _resource_change(role: String, key: String, amount: float) -> String:
	if role != "" and String(UiFormat.resource_info(role, key).get("unit", "")) == "$B":
		return "%s$%dB" % ["+" if amount >= 0.0 else "−", roundi(absf(amount))]
	var short := UiFormat.resource_short(role, key) if role != "" else key
	return "%s %s" % [short, UiFormat.signed(amount)]


# --- Building ------------------------------------------------------------------------

func _build_info_row() -> void:
	_info_row = HBoxContainer.new()
	_info_row.name = "InfoRow"
	_info_row.add_theme_constant_override("separation", 12)
	_column.add_child(_info_row)
	_info_label = Label.new()
	_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_info_row.add_child(_info_label)
	_money_label = Label.new()
	_money_label.name = "Holdings"
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_info_row.add_child(_money_label)


func _build_card() -> void:
	_slot = CardSlot.new()
	_slot.name = "CardSlot"
	# Drawn above the responses, which a swiped card passes over on desktop.
	_slot.z_index = 1
	_body.add_child(_slot)
	_card = CrisisCard.new()
	_card.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_card.gui_input.connect(_on_card_input)
	_card.swiped.connect(swiped.emit)
	_slot.card = _card
	_slot.add_child(_card)
	if not _story_context.is_empty():
		_card.set_story_context(_story_context[0], _story_context[1], _story_context[2])


func _build_options() -> void:
	_options = VBoxContainer.new()
	_options.name = "Responses"
	_options.add_theme_constant_override("separation", 12)
	_body.add_child(_options)
	_rows_box = VBoxContainer.new()
	_rows_box.name = "Rows"
	_rows_box.add_theme_constant_override("separation", 8)
	_options.add_child(_rows_box)
	_help_label = Label.new()
	_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_options.add_child(_help_label)


func _build_rows() -> void:
	_hover_row = null
	_hold_row = null
	_hold_shown = false
	for row in _rows:
		_rows_box.remove_child(row)
		row.queue_free()
	_rows.clear()
	var options: Array = current_card.get("options", [])
	for i in options.size():
		_rows.append(_make_row(options[i], i, false))
	_rows.append(_make_row(current_card.get("defer", {}), options.size(), true))
	for row in _rows:
		_rows_box.add_child(row)
	UiLayout.pass_touch_through(_column)


## A response row: a Button (disabled when unaffordable) holding the key
## badge, the label, a sub line (cost and other effects) and effect glyphs.
func _make_row(option: Dictionary, index: int, is_defer: bool) -> Button:
	var option_id := String(option.get("id", DilemmaDeck.DEFER_ID))
	var affordable := is_defer or _can_afford(option.get("cost", {}))
	var row := Button.new()
	row.name = "Option" + option_id
	row.set_meta("option_id", option_id)
	row.set_meta("index", index)
	row.disabled = not affordable
	row.focus_mode = Control.FOCUS_NONE if _compact else Control.FOCUS_ALL
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if affordable else Control.CURSOR_FORBIDDEN
	# Touch screens raise tooltips during a hold, so phones get none.
	row.tooltip_text = "" if _compact else _row_tooltip(option, affordable)
	_style_row(row, false)

	var content := HBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 12
	content.offset_right = -12
	content.offset_top = 6
	content.offset_bottom = -6
	content.add_theme_constant_override("separation", 10)
	row.add_child(content)
	content.add_child(_key_badge(_row_key(option_id, index, is_defer)))
	content.add_child(_row_texts(option, is_defer, affordable))
	var effects: Dictionary = option.get("effects", {})
	content.add_child(_effect_glyphs(effects.get("metrics", {})))
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for node in content.find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not affordable:
		content.modulate = Color(1, 1, 1, 0.55)

	content.minimum_size_changed.connect(_fit_row.bind(row, content))
	row.pressed.connect(_on_row_pressed.bind(row))
	row.gui_input.connect(_on_row_input.bind(row))
	row.mouse_exited.connect(_on_row_exited.bind(row))
	return row


func _row_texts(option: Dictionary, is_defer: bool, affordable: bool) -> VBoxContainer:
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.name = "Label"
	label.text = String(option.get("label", "Defer"))
	if _compact:
		# Two lines on phones. (An overrun mode would let an autowrapped
		# Label shrink to 1 px, so long labels are cut after line two.)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.max_lines_visible = 2
	else:
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	CrisisCard.style_label(label, _style.font_ui_bold, 14 if _compact else 15, _style.text_bright)
	texts.add_child(label)
	var sub := Label.new()
	sub.name = "Sub"
	sub.text = _sub_text(option, is_defer, affordable)
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	CrisisCard.style_label(sub, _style.font_mono, 10 if _compact else 11, _style.text_dim if affordable else _style.bad)
	texts.add_child(sub)
	return texts


func _fit_row(row: Button, content: Control) -> void:
	if is_instance_valid(row) and is_instance_valid(content):
		row.custom_minimum_size.y = maxf(ROW_HEIGHT, content.get_combined_minimum_size().y + 12.0)


func _key_badge(key: String) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.name = "Key"
	badge.custom_minimum_size = Vector2(26, 26)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_theme_stylebox_override("panel", _badge_box)
	if KEY_GLYPHS.has(key):
		badge.add_child(Glyphs.icon(String(KEY_GLYPHS[key]), 14, _badge_text, 2.0))
	else:
		var label := Label.new()
		label.text = key
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		CrisisCard.style_label(label, _style.font_mono_bold, 12, _badge_text)
		badge.add_child(label)
	badge.set_meta("key", key)
	return badge


func _effect_glyphs(metrics: Dictionary) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.name = "Effects"
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", 6)
	for key in WorldState.METRIC_KEYS:
		if not metrics.has(key):
			continue
		var delta := float(metrics[key])
		if absf(delta) < 0.05:
			continue
		var tone := _style.good if UiFormat.is_improvement(key, delta) else _style.bad
		var item := HBoxContainer.new()
		item.name = "Effect_" + key
		item.add_theme_constant_override("separation", 1)
		item.add_child(Glyphs.icon(Glyphs.for_metric(key), 16, tone, 1.9))
		var pips := Label.new()
		pips.text = UiFormat.pips(delta)
		CrisisCard.style_label(pips, _style.font_mono, 10, tone)
		item.add_child(pips)
		box.add_child(item)
	return box


func _row_key(option_id: String, index: int, is_defer: bool) -> String:
	if is_defer:
		return "↓"
	if index == 0:
		return "←"
	if index == 1:
		return "→"
	if option_id == "C":
		return "C"
	return str(index + 1)


# --- Content -------------------------------------------------------------------------

func _fill() -> void:
	_card.show_card(current_card)
	_info_label.text = _info_text()
	_money_label.text = _resource_text()


## "H1 2031 · Turn 10 · Frontier Lab" in the era's voice.
func _info_text() -> String:
	var turn := int(current_card.get("turn", 0))
	var year := SimConstants.year_for_turn(turn)
	var role_name := String(CrisisCard.FACTION_NAMES.get(_role, _role.capitalize()))
	match _style.era:
		2:
			return "T%d · %.1f · %s" % [turn, year, role_name.to_upper()]
		3:
			return "%d · turn %d · %s" % [int(year), turn, role_name.to_lower()]
	return "H%d %d · Turn %d · %s" % [1 if year - floorf(year) < 0.25 else 2, int(year), turn, role_name]


## The player's holdings of every currency the responses cost.
func _resource_text() -> String:
	if _role == "":
		return ""
	var keys: Array[String] = []
	for option in current_card.get("options", []):
		for key in (option as Dictionary).get("cost", {}):
			if not keys.has(String(key)):
				keys.append(String(key))
	var parts: Array[String] = []
	for key in keys:
		var value := float(_resources.get(key, 0.0))
		if String(UiFormat.resource_info(_role, key).get("unit", "")) == "$B":
			parts.append(UiFormat.format_resource(_role, key, value))
		else:
			parts.append("%s %s" % [UiFormat.resource_short(_role, key), UiFormat.format_resource(_role, key, value)])
	return " · ".join(parts)


## Cost, then the effects that have no metric glyph (growth, capability,
## indices, resources), e.g. "$90B + GDW 8 · growth ×0.5 (2 turns)".
func _sub_text(option: Dictionary, is_defer: bool, affordable: bool) -> String:
	var parts: Array[String] = []
	var cost: Dictionary = option.get("cost", {})
	if is_defer:
		parts.append("Returns in %d turns, escalated" % DilemmaDeck.DEFER_DELAY_TURNS)
	elif cost.is_empty():
		parts.append("Free")
	elif affordable:
		parts.append(UiFormat.format_cost(_role, cost))
	else:
		parts.append("Needs " + UiFormat.format_cost(_role, cost))
	parts.append_array(other_effects(option.get("effects", {}), _role))
	var exclusive := _exclusive_to(String(option.get("id", "")))
	if exclusive != "":
		parts.append("%s only" % exclusive)
	return " · ".join(parts)


## The faction name when the response is unique to the player's role.
func _exclusive_to(option_id: String) -> String:
	var template := DilemmaDeck.get_template(String(current_card.get("id", "")))
	for option in template.get("options", []):
		var roles: Array = (option as Dictionary).get("roles", [])
		if String(option.get("id", "")) == option_id and roles.has(_role):
			return String(CrisisCard.FACTION_NAMES.get(_role, _role))
	return ""


func _row_tooltip(option: Dictionary, affordable: bool) -> String:
	var lines: Array[String] = [String(option.get("label", ""))]
	var detail := String(option.get("detail", ""))
	if detail != "":
		lines.append(detail)
	lines.append(UiFormat.effects_summary(option.get("effects", {}), _role))
	if not affordable:
		lines.append("Not enough resources")
	return "\n".join(lines)


func _can_afford(cost: Dictionary) -> bool:
	for key in cost:
		if float(_resources.get(key, 0.0)) + 0.0001 < float(cost[key]):
			return false
	return true


func _option_at(index: int) -> Dictionary:
	var options: Array = current_card.get("options", [])
	if index >= 0 and index < options.size():
		return options[index]
	if index == options.size():
		return current_card.get("defer", {})
	return {}


func _row_for(option_id: String) -> Button:
	for row in _rows:
		if String(row.get_meta("option_id")) == option_id:
			return row
	return null


# --- Layout and style ------------------------------------------------------------------

func _apply_layout() -> void:
	if _column == null or _style == null:
		return
	var width := size.x if size.x > 1.0 else get_viewport_rect().size.x
	UiLayout.set_overlay_margin(_frame, _compact)
	_apply_shade()
	var content := minf(DESKTOP_WIDTH, width - 48.0) if not _compact else maxf(240.0, width - UiLayout.COMPACT_MARGIN * 2.0)
	var wide := not _compact or content >= WIDE_COMPACT_WIDTH
	_column.custom_minimum_size = Vector2(content, 0)
	_column.add_theme_constant_override("separation", 10 if _compact else 14)
	_body.vertical = not wide
	var card_width := DESKTOP_CARD_WIDTH
	var header := content
	var art_height := DESKTOP_ART_HEIGHT
	if wide:
		if _compact:
			card_width = clampf(content * 0.44, 300.0, DESKTOP_CARD_WIDTH)
			art_height = WIDE_ART_HEIGHT
		_slot.size_flags_horizontal = Control.SIZE_FILL
		_slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_options.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_options.custom_minimum_size = Vector2.ZERO
		_body.add_theme_constant_override("separation", 18 if _compact else 28)
	else:
		var stack := minf(content, STACK_MAX_WIDTH)
		header = stack
		card_width = minf(stack - 24.0, CARD_MAX_WIDTH)
		art_height = COMPACT_ART_HEIGHT
		_slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_options.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_options.custom_minimum_size = Vector2(stack, 0)
		_body.add_theme_constant_override("separation", 14)
	_slot.card_width = card_width
	_slot.update_minimum_size()
	_card.set_layout(card_width, art_height, _compact)
	for part in [_vitals, _info_row]:
		(part as Control).custom_minimum_size.x = header
		(part as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Wide landscape screens have room for the strip's names and predictions.
	_vitals.set_compact(_compact and not wide)
	_apply_fonts()
	_slot.queue_sort()


func _apply_fonts() -> void:
	var s := _style
	CrisisCard.style_label(_info_label, s.font_mono, 11, s.text_dim)
	CrisisCard.style_label(_money_label, s.font_mono, 11, s.text_dim)
	CrisisCard.style_label(_help_label, s.font_ui, 12, s.text_dim)
	_help_label.text = "Swipe the card, tap a response, or hold one to preview it" if _compact \
		else "Drag the card or press ← →, click a response or press its key, hover to preview"


func _apply_style() -> void:
	_style = EraTheme.style_of(self)
	var s := _style
	_backdrop.era = s.era
	_backdrop.colors = [s.accent, s.metric_color("alignment_drift")]
	_backdrop.queue_redraw()
	_card.apply_style(s)
	_row_normal = _row_box(s, false)
	_row_on = _row_box(s, true)
	_row_disabled = _row_box(s, false)
	_row_disabled.bg_color = _row_disabled.bg_color.darkened(0.3)
	_row_focus = _row_box(s, true)
	_row_focus.draw_center = false
	_badge_box = CrisisCard.shape_box(_badge_radii(s), 1 if s.era == 2 else 8)
	_badge_box.bg_color = s.raised if s.era == 1 else Color(s.accent, 0.1)
	if s.era != 1:
		_badge_box.set_border_width_all(1)
		_badge_box.border_color = Color(s.accent, 0.4)
	_badge_text = [s.text_dim, s.accent, s.text][s.era - 1]
	_apply_layout()


## The era's shade over the dashboard; nearly opaque on phones, where the
## stacked dialog covers the screen.
func _apply_shade() -> void:
	if _shade != null and _style != null:
		var s := _style
		_shade.color = Color(s.shade.r, s.shade.g, s.shade.b, 0.94 if _compact else maxf(s.shade.a, 0.86))


static func _badge_radii(s: EraStyle) -> Array[float]:
	var radii: Array[float] = []
	match s.era:
		2:
			radii.assign([5.0, 5.0, 5.0, 5.0])
		3:
			radii.assign([13.0, 10.0, 13.0, 11.0])
		_:
			radii.assign([8.0, 8.0, 8.0, 8.0])
	return radii


func _row_box(s: EraStyle, highlighted: bool) -> StyleBoxFlat:
	var radii: Array[float] = []
	match s.era:
		2:
			radii.assign([8.0, 8.0, 8.0, 8.0])
		3:
			radii.assign([22.0, 16.0, 24.0, 18.0])
		_:
			radii.assign([14.0, 14.0, 14.0, 14.0])
	var box := CrisisCard.shape_box(radii, 1 if s.era == 2 else 10)
	box.set_border_width_all(1)
	match s.era:
		1:
			box.bg_color = s.surface.lerp(s.accent, 0.14) if highlighted else s.surface
			box.border_color = s.accent if highlighted else Color(1, 1, 1, 0.07)
		2:
			box.bg_color = Color(s.surface.lerp(s.accent, 0.16 if highlighted else 0.05), 0.96)
			box.border_color = s.accent if highlighted else Color(s.accent, 0.24)
		_:
			box.bg_color = Color(s.surface.lerp(s.accent, 0.12) if highlighted else s.surface.lerp(s.text, 0.04), 0.96)
			box.border_color = s.accent if highlighted else Color(s.text, 0.18)
	if highlighted and s.glow > 0.0:
		box.shadow_color = Color(s.accent, s.glow * 0.6)
		box.shadow_size = 6
	return box


func _style_row(row: Button, highlighted: bool) -> void:
	row.add_theme_stylebox_override("normal", _row_on if highlighted else _row_normal)
	row.add_theme_stylebox_override("hover", _row_on)
	row.add_theme_stylebox_override("pressed", _row_on)
	row.add_theme_stylebox_override("hover_pressed", _row_on)
	row.add_theme_stylebox_override("focus", _row_focus)
	row.add_theme_stylebox_override("disabled", _row_on if highlighted else _row_disabled)


# --- Previews ----------------------------------------------------------------------------

## Shows the active preview: a held row, then a part-way drag, then a hovered row.
func _refresh_preview() -> void:
	if _leaving:
		return
	var index := -1
	if _hold_row != null and _hold_shown:
		index = int(_hold_row.get_meta("index"))
	elif _drag_pick >= 0:
		index = _drag_pick
	elif _hover_row != null and is_instance_valid(_hover_row):
		index = int(_hover_row.get_meta("index"))
	_show_preview(index)
	if _hold_row != null and _hold_shown:
		_card.show_tag(String(_option_at(index).get("label", "")), 1, 1.0)
	elif _drag_pick < 0:
		_card.hide_tag()


func _show_preview(index: int) -> void:
	var effects: Dictionary = _option_at(index).get("effects", {})
	_vitals.set_preview(effects.get("metrics", {}))
	for row in _rows:
		_style_row(row, int(row.get_meta("index")) == index)


# --- Card gestures ------------------------------------------------------------------------

func _on_card_input(event: InputEvent) -> void:
	if _leaving or current_card.is_empty():
		return
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_dragging = true
			_drag_axis = Axis.NONE
			_drag_start = button.global_position
			_card.mouse_default_cursor_shape = Control.CURSOR_CAN_DROP
		elif _dragging:
			_end_drag()
		return
	var motion := event as InputEventMouseMotion
	if motion == null or not _dragging:
		return
	var delta := motion.global_position - _drag_start
	if _drag_axis == Axis.NONE:
		if delta.length() < DRAG_SLOP:
			_card.accept_event()
			return
		_drag_axis = Axis.HORIZONTAL if absf(delta.x) >= absf(delta.y) else Axis.VERTICAL
		if _drag_axis == Axis.HORIZONTAL:
			_kill_tween()
			_slot.lift = 1.0
			_card.modulate.a = 1.0
	if _drag_axis == Axis.HORIZONTAL:
		# Horizontal drags move the card; vertical ones scroll the overlay.
		_card.accept_event()
		_set_drag(delta.x)


func _set_drag(dx: float) -> void:
	_drag_dx = dx
	_slot.offset = Vector2(dx, 0.0)
	_slot.tilt = deg_to_rad(dx * TILT_PER_PX)
	var options: Array = current_card.get("options", [])
	var pick := -1
	if absf(dx) > PREVIEW_DRAG:
		pick = 0 if dx < 0.0 else 1
	if pick >= options.size():
		pick = -1
	if pick != _drag_pick:
		_drag_pick = pick
		_refresh_preview()
	if pick >= 0:
		var label := String((options[pick] as Dictionary).get("label", ""))
		_card.show_tag(label, 1 if dx < 0.0 else -1, clampf(absf(dx) / _swipe_threshold(), 0.0, 1.0))


func _end_drag() -> void:
	_dragging = false
	_card.mouse_default_cursor_shape = Control.CURSOR_DRAG
	var horizontal := _drag_axis == Axis.HORIZONTAL
	_drag_axis = Axis.NONE
	if not horizontal:
		return
	var dx := _drag_dx
	var index := 0 if dx < 0.0 else 1
	var options: Array = current_card.get("options", [])
	if absf(dx) >= _swipe_threshold() and index < options.size():
		_commit(index, true)
		return
	_drag_pick = -1
	_drag_dx = 0.0
	_refresh_preview()
	_snap_back()


func _swipe_threshold() -> float:
	return minf(SWIPE_THRESHOLD, _slot.card_width * SWIPE_FRACTION)


# --- Rows ----------------------------------------------------------------------------------

func _on_row_input(event: InputEvent, row: Button) -> void:
	if _leaving:
		return
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_cancel_hold()
			_suppress_click = false
			if button.device == InputEvent.DEVICE_ID_EMULATION:
				_hold_row = row
				_hold_origin = button.global_position
				_hold_timer.start(HOLD_TIME)
		elif _hold_row == row:
			# Releasing a hold only ends the preview; the click that follows is ignored.
			_suppress_click = _suppress_click or _hold_shown
			_cancel_hold()
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	if motion.device == InputEvent.DEVICE_ID_EMULATION:
		if _hold_row == row and not _hold_shown and motion.global_position.distance_to(_hold_origin) > TAP_SLOP:
			_cancel_hold()
		return
	if _hover_row != row:
		_hover_row = row
		_refresh_preview()


func _on_row_exited(row: Button) -> void:
	if _hold_row == row:
		_cancel_hold()
	if _hover_row == row:
		_hover_row = null
		_refresh_preview()


func _on_hold_timeout() -> void:
	if _hold_row == null or _leaving or not visible:
		return
	_hold_shown = true
	_suppress_click = true
	_refresh_preview()


func _cancel_hold() -> void:
	_hold_timer.stop()
	var was_shown := _hold_shown
	_hold_row = null
	_hold_shown = false
	if was_shown:
		_refresh_preview()


func _on_row_pressed(row: Button) -> void:
	if _suppress_click:
		_suppress_click = false
		return
	Haptics.pulse("select")
	_commit(int(row.get_meta("index")))


func _input(event: InputEvent) -> void:
	if not visible or _leaving or current_card.is_empty() or not is_visible_in_tree():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var options: Array = current_card.get("options", [])
	var index := -1
	match key.keycode:
		KEY_LEFT:
			index = 0
		KEY_RIGHT:
			index = 1 if options.size() > 1 else -1
		KEY_DOWN:
			index = options.size()
		KEY_C:
			index = int(_row_for("C").get_meta("index")) if _row_for("C") != null else -1
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4:
			var number := (key.keycode - KEY_KP_1) if key.keycode >= KEY_KP_1 else (key.keycode - KEY_1)
			index = number if number <= options.size() else -1
	if index < 0:
		return
	get_viewport().set_input_as_handled()
	# ← and → send the card sideways like a swipe.
	_commit(index, key.keycode == KEY_LEFT or key.keycode == KEY_RIGHT)


# --- Motion ---------------------------------------------------------------------------------

## Flies the card off toward the response's side (or drops it for the rest)
## and then chooses it; unaffordable responses shake the card back instead.
## [param swipe]: the player swiped (or pressed ← / →) rather than picked a row.
func _commit(index: int, swipe: bool = false) -> void:
	if _leaving or not visible:
		return
	var option := _option_at(index)
	if option.is_empty():
		return
	if index < _rows.size() and _rows[index].disabled:
		_reject(index)
		return
	_cancel_hold()
	_drag_pick = -1
	_show_preview(index)
	_card.hide_tag()
	_leaving = true
	var option_id := String(option.get("id", DilemmaDeck.DEFER_ID))
	if swipe and index <= 1:
		_card.notify_swiped(-1 if index == 0 else 1)
	else:
		option_pressed.emit(option_id)
	var target := Vector2(_slot.offset.x, get_viewport_rect().size.y)
	var tilt := deg_to_rad(4.0)
	if index <= 1 and index < (current_card.get("options", []) as Array).size():
		var side := -1.0 if index == 0 else 1.0
		target = Vector2(side * (get_viewport_rect().size.x * 0.5 + _slot.card_width), _slot.offset.y + 40.0)
		tilt = deg_to_rad(24.0 * side)
	_kill_tween()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(_slot, "offset", target, FLY_TIME)
	_tween.tween_property(_slot, "tilt", tilt, FLY_TIME)
	_tween.tween_property(_card, "modulate:a", 0.0, FLY_TIME)
	_tween.chain().tween_callback(choose.bind(option_id))


func _reject(index: int) -> void:
	_drag_pick = -1
	_refresh_preview()
	var option := _option_at(index)
	_card.show_tag("Not enough resources · " + UiFormat.format_cost(_role, option.get("cost", {})), 1, 1.0, _style.bad)
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_slot, "offset", Vector2.ZERO, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_slot, "tilt", 0.0, 0.12)
	for shake in [12.0, -9.0, 6.0, -3.0, 0.0]:
		_tween.tween_property(_slot, "offset", Vector2(shake, 0.0), 0.05)
	_tween.tween_interval(0.7)
	_tween.tween_callback(_card.hide_tag)


func _snap_back() -> void:
	_kill_tween()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_slot, "offset", Vector2.ZERO, SNAP_TIME)
	_tween.tween_property(_slot, "tilt", 0.0, SNAP_TIME)
	_card.hide_tag()


func _play_entrance() -> void:
	_kill_tween()
	_slot.offset = Vector2(0.0, -26.0)
	_slot.lift = 0.94
	_card.modulate.a = 0.0
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_slot, "offset", Vector2.ZERO, ENTER_TIME)
	_tween.tween_property(_slot, "lift", 1.0, ENTER_TIME)
	_tween.tween_property(_card, "modulate:a", 1.0, ENTER_TIME * 0.6)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


## Puts the card back at rest and clears every preview and gesture.
func _reset_motion() -> void:
	_kill_tween()
	_leaving = false
	_dragging = false
	_drag_axis = Axis.NONE
	_drag_dx = 0.0
	_drag_pick = -1
	_hover_row = null
	_hold_row = null
	_hold_shown = false
	_suppress_click = false
	if _hold_timer != null:
		_hold_timer.stop()
	if _slot != null:
		_slot.offset = Vector2.ZERO
		_slot.tilt = 0.0
		_slot.lift = 1.0
		_card.modulate.a = 1.0
		_card.mouse_default_cursor_shape = Control.CURSOR_DRAG
		_card.hide_tag()
	if _vitals != null:
		_vitals.set_preview({})
	for row in _rows:
		if is_instance_valid(row):
			_style_row(row, false)


# --- Parts ---------------------------------------------------------------------------------

## Holds the card outside a container's layout rules so it can be dragged,
## tilted and animated; its minimum size follows the card's.
class CardSlot extends Container:
	var card: Control
	var card_width := 360.0
	var offset := Vector2.ZERO:
		set(value):
			offset = value
			place()
	var tilt := 0.0:
		set(value):
			tilt = value
			place()
	var lift := 1.0:
		set(value):
			lift = value
			place()

	func _get_minimum_size() -> Vector2:
		if card == null:
			return Vector2.ZERO
		return Vector2(card_width, card.get_combined_minimum_size().y)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			place()

	func place() -> void:
		if card == null:
			return
		card.size = Vector2(card_width, card.get_combined_minimum_size().y)
		card.pivot_offset = card.size * 0.5
		card.position = Vector2((size.x - card_width) * 0.5, 0.0) + offset
		card.rotation = tilt
		card.scale = Vector2(lift, lift)


## Era decoration between the shade and the dialog: a faint grid in Era II,
## two soft glows in Era III.
class Backdrop extends Control:
	const GRID := 26.0
	var era := 1
	var colors: Array = [Color.WHITE, Color.WHITE]
	static var _glow: GradientTexture2D

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		if era == 2:
			var lines := PackedVector2Array()
			var x := GRID
			while x < size.x:
				lines.append_array([Vector2(x, 0), Vector2(x, size.y)])
				x += GRID
			var y := GRID
			while y < size.y:
				lines.append_array([Vector2(0, y), Vector2(size.x, y)])
				y += GRID
			if not lines.is_empty():
				draw_multiline(lines, Color(colors[0], 0.045))
		elif era == 3:
			var glow := _glow_texture()
			var reach := maxf(size.x, size.y) * 0.45
			draw_texture_rect(glow, Rect2(Vector2(-reach * 0.4, size.y * 0.1), Vector2(reach, reach)), false, Color(colors[0], 0.1))
			draw_texture_rect(glow, Rect2(Vector2(size.x - reach * 0.6, size.y * 0.55), Vector2(reach, reach)), false, Color(colors[1], 0.1))

	static func _glow_texture() -> GradientTexture2D:
		if _glow == null:
			var gradient := Gradient.new()
			gradient.set_color(0, Color(1, 1, 1, 1))
			gradient.set_color(1, Color(1, 1, 1, 0))
			_glow = GradientTexture2D.new()
			_glow.gradient = gradient
			_glow.fill = GradientTexture2D.FILL_RADIAL
			_glow.fill_from = Vector2(0.5, 0.5)
			_glow.fill_to = Vector2(1.0, 0.5)
			_glow.width = 128
			_glow.height = 128
		return _glow
