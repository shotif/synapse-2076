class_name Newswire
extends BoxContainer
## The newswire: the event log as headline cards, newest first. Replaces the
## old LOG feed. Each card shows a category tile (glyph on a tinted square), a
## kicker, the headline in the serif news face, a byline with the faction's
## color and the story's effects as metric glyphs with ▲/▼ pips.
##
## Desktop: one row of fixed-width cards that scrolls sideways (the footer
## strip, about 1580x170). Compact (the phone's NEWS tab): a vertical list
## with a masthead, filter chips (All / Labs / Council / Street / Machines)
## and the newest story set as the lead.
##
##   wire.player_role = engine.player_role
##   engine.event_logged.connect(wire.add_entry)
##   wire.set_public_trust(snapshot.metrics.epistemic_trust)   # each turn
##
## Statements are untrusted LLM text and only ever go into Label nodes, so any
## markup in them is shown literally. The chrome follows the era theme; the
## serif headline face stays the same in every era.

signal filter_changed(desk: String)

const MAX_CARDS := 200
const STRIP_CARD_WIDTH := 304.0
## Height to give the desktop strip (its cards need about 140 px).
const STRIP_HEIGHT := 150.0
const MASTHEAD_WIDTH := 128.0
const LEAD_ART_HEIGHT := 92.0
const MAX_PIPS := 3
## Below this public trust the wire prints the official version of contested
## stories (their counter headline) under a broken seal.
const DISINFORMATION_TRUST := 35.0
## Below this every story carries a cracked "unconfirmed" seal.
const UNCONFIRMED_TRUST := 50.0
const FILTERS := ["", "CEO", "GOVERNANCE_COUNCIL", "CITIZEN_COALITION", "ASI"]
const SERIF := "Newsreader-SemiBold.ttf"

## The player's faction: their own stories carry "· you" in the byline.
var player_role := ""
var _compact := false
var _horizontal := true
var _filter := ""
var _trust := 100.0
var _newest_turn := -1
var _newest_year := SimConstants.START_YEAR
var _masthead: BoxContainer
var _title_label: Label
var _meta_label: Label
var _rule: DoubleRule
var _chips_row: HFlowContainer
var _chip_buttons := {}
var _scroll: ScrollContainer
var _list: BoxContainer
var _empty_label: Label
var _restyle_queued := false

static var _kicker_fonts := {}


## The node tree is built at construction so the wire takes entries and
## layout calls before it joins the scene; styling follows in _ready().
func _init() -> void:
	add_theme_constant_override("separation", 10)
	_masthead = BoxContainer.new()
	_masthead.name = "Masthead"
	_masthead.add_theme_constant_override("separation", 6)
	add_child(_masthead)
	var title_row := BoxContainer.new()
	title_row.name = "TitleRow"
	title_row.add_theme_constant_override("separation", 4)
	_masthead.add_child(title_row)
	_title_label = Label.new()
	_title_label.text = "The Wire"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title_label)
	_meta_label = Label.new()
	_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_meta_label.size_flags_vertical = Control.SIZE_SHRINK_END
	title_row.add_child(_meta_label)
	_rule = DoubleRule.new()
	_masthead.add_child(_rule)

	_chips_row = HFlowContainer.new()
	_chips_row.name = "Filters"
	_chips_row.add_theme_constant_override("h_separation", 6)
	_chips_row.add_theme_constant_override("v_separation", 6)
	add_child(_chips_row)
	var group := ButtonGroup.new()
	for desk in FILTERS:
		var chip := Button.new()
		chip.theme_type_variation = "ChipButton"
		chip.toggle_mode = true
		chip.button_group = group
		chip.focus_mode = Control.FOCUS_NONE
		chip.text = "All" if desk == "" else HeadlineWriter.desk_name(desk)
		chip.button_pressed = desk == ""
		chip.pressed.connect(set_filter.bind(desk))
		_chip_buttons[desk] = chip
		_chips_row.add_child(chip)

	_scroll = ScrollContainer.new()
	_scroll.name = "WireScroll"
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	_list = BoxContainer.new()
	_list.name = "Cards"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_empty_label = Label.new()
	_empty_label.name = "Empty"
	_empty_label.text = "No stories yet. The wire fills as the turns resolve."
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_empty_label)
	_apply_mode()
	_after_change()


func _ready() -> void:
	UiLayout.pass_touch_through(self)
	_restyle()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready() and not _restyle_queued:
		_restyle_queued = true
		_restyle.call_deferred()


# --- Public API ---------------------------------------------------------------------

## Adds one engine log entry as a headline card (skips what is not news).
func add_entry(entry: Dictionary) -> void:
	var h := HeadlineWriter.headline(entry, player_role)
	if not bool(h["newsworthy"]):
		return
	if int(h["turn"]) >= _newest_turn:
		_newest_turn = int(h["turn"])
		_newest_year = float(h["year"])
		_update_meta()
	if bool(h["attach"]) and _attach(h):
		return
	h["printed_trust"] = _trust
	var card := _card(h, false)
	_list.add_child(card)
	_list.move_child(card, 0)
	card.visible = _matches(h)
	while _card_count() > MAX_CARDS:
		var oldest := _list.get_child(_list.get_child_count() - 1)
		_list.remove_child(oldest)
		oldest.queue_free()
	_after_change()


func clear() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_newest_turn = -1
	_newest_year = SimConstants.START_YEAR
	_update_meta()
	_after_change()


func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	_restyle()


## Desktop strip (true) or vertical list with masthead and filters (false).
func set_horizontal(horizontal: bool) -> void:
	if _horizontal == horizontal:
		return
	_horizontal = horizontal
	if horizontal and _filter != "":
		_set_filter_silent("")
	_apply_mode()
	_restyle()


## Public trust as of now (0-100). Stories printed while it is low carry an
## unconfirmed seal, and contested ones print the official counter-story.
func set_public_trust(value: float) -> void:
	_trust = clampf(value, 0.0, 100.0) if is_finite(value) else _trust


## Shows only one desk's stories ("" for all; otherwise a faction id).
func set_filter(desk: String) -> void:
	if not FILTERS.has(desk):
		desk = ""
	_set_filter_silent(desk)
	filter_changed.emit(desk)


func entry_count() -> int:
	return _card_count()


## Titles as printed, newest first.
func get_headline_titles() -> Array:
	var out: Array = []
	for child in _list.get_children():
		if child.has_meta("headline"):
			out.append(String(child.get_meta("shown_title", "")))
	return out


## Headline dictionaries of the cards, newest first.
func get_headlines() -> Array:
	var out: Array = []
	for child in _list.get_children():
		if child.has_meta("headline"):
			out.append(child.get_meta("headline"))
	return out


func is_horizontal() -> bool:
	return _horizontal


# --- Layout ---------------------------------------------------------------------------

func _apply_mode() -> void:
	vertical = not _horizontal
	_masthead.vertical = true
	var title_row: BoxContainer = _masthead.get_node("TitleRow")
	title_row.vertical = _horizontal
	# Desktop masthead stacks title, rule, date; the phone puts the rule under the row.
	if _horizontal and _rule.get_parent() != title_row:
		_rule.reparent(title_row, false)
		title_row.move_child(_rule, 1)
	elif not _horizontal and _rule.get_parent() != _masthead:
		_rule.reparent(_masthead, false)
	_meta_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if _horizontal else TextServer.AUTOWRAP_OFF
	_masthead.custom_minimum_size = Vector2(MASTHEAD_WIDTH if _horizontal else 0.0, 0.0)
	_masthead.size_flags_horizontal = Control.SIZE_FILL if _horizontal else Control.SIZE_EXPAND_FILL
	_chips_row.visible = not _horizontal
	_list.vertical = not _horizontal
	_list.add_theme_constant_override("separation", 10 if _horizontal else 8)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if _horizontal else ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if _horizontal else \
		(ScrollContainer.SCROLL_MODE_SHOW_NEVER if _compact else ScrollContainer.SCROLL_MODE_AUTO)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if _horizontal else HORIZONTAL_ALIGNMENT_CENTER
	_update_meta()


func _restyle() -> void:
	_restyle_queued = false
	if _title_label == null:
		return
	var s := EraTheme.style_of(self)
	_title_label.add_theme_font_override("font", EraStyle.font(SERIF))
	_title_label.add_theme_font_size_override("font_size", 24 if _horizontal else (28 if _compact else 30))
	_title_label.add_theme_color_override("font_color", s.text_bright)
	_title_label.add_theme_constant_override("line_spacing", 0)
	_meta_label.add_theme_font_override("font", s.font_ui)
	_meta_label.add_theme_font_size_override("font_size", 12)
	_meta_label.add_theme_color_override("font_color", s.text_dim)
	_meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if _horizontal else HORIZONTAL_ALIGNMENT_RIGHT
	_rule.color = Color(s.text, 0.85)
	_rule.queue_redraw()
	_empty_label.add_theme_color_override("font_color", s.text_dim)
	_empty_label.add_theme_font_override("font", s.font_ui)
	_empty_label.add_theme_font_size_override("font_size", 13)
	for desk in _chip_buttons:
		var chip: Button = _chip_buttons[desk]
		chip.custom_minimum_size = Vector2(0, 44 if _compact else 34)
		chip.icon = null if desk == "" else _dot_texture(s.faction_color(desk))
		chip.add_theme_constant_override("h_separation", 6)
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
			chip.add_theme_color_override(state, Color.WHITE)
		# Slimmer side padding than stock chips so all five fit one phone row.
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			chip.remove_theme_stylebox_override(state)
			var box := chip.get_theme_stylebox(state).duplicate() as StyleBox
			box.content_margin_left = 9.0
			box.content_margin_right = 11.0
			chip.add_theme_stylebox_override(state, box)
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if _horizontal else \
		(ScrollContainer.SCROLL_MODE_SHOW_NEVER if _compact else ScrollContainer.SCROLL_MODE_AUTO)
	_rebuild_cards()


func _rebuild_cards() -> void:
	var lead_card := _first_visible_card()
	for child in _list.get_children():
		if child.has_meta("headline"):
			_replace_card(child, not _horizontal and child == lead_card)


func _replace_card(card: Control, lead: bool) -> void:
	var index := card.get_index()
	var fresh := _card(card.get_meta("headline"), lead)
	fresh.visible = card.visible
	_list.add_child(fresh)
	_list.move_child(fresh, index)
	_list.remove_child(card)
	card.queue_free()


func _after_change() -> void:
	var empty := _card_count() == 0
	_empty_label.visible = empty
	_scroll.visible = not empty
	_refresh_lead()


## In the vertical list the first visible story is the lead.
func _refresh_lead() -> void:
	var lead_card := _first_visible_card()
	for child in _list.get_children():
		if not child.has_meta("headline"):
			continue
		var want := not _horizontal and child == lead_card
		if bool(child.get_meta("lead", false)) != want:
			_replace_card(child, want)


func _first_visible_card() -> Control:
	for child in _list.get_children():
		if child.has_meta("headline") and (child as Control).visible:
			return child
	return null


func _card_count() -> int:
	return _list.get_child_count()


func _set_filter_silent(desk: String) -> void:
	_filter = desk
	for key in _chip_buttons:
		(_chip_buttons[key] as Button).set_pressed_no_signal(key == desk)
	for child in _list.get_children():
		if child.has_meta("headline"):
			(child as Control).visible = _matches(child.get_meta("headline"))
	_refresh_lead()


func _matches(h: Dictionary) -> bool:
	return _filter == "" or String(h.get("desk", "")) == _filter


func _update_meta() -> void:
	if _meta_label == null:
		return
	if _newest_turn < 0:
		_meta_label.text = "No stories yet" if _horizontal else ""
		return
	var year := int(floor(_newest_year))
	var half := "first half" if _newest_year - float(year) < 0.25 else "second half"
	if _horizontal:
		_meta_label.text = "%d · %s\nTurn %d" % [year, half, _newest_turn]
	else:
		_meta_label.text = "%d · %s · turn %d" % [year, half, _newest_turn]


## Folds an "incoming crisis" note into the story that caused it.
func _attach(h: Dictionary) -> bool:
	for i in mini(2, _list.get_child_count()):
		var card := _list.get_child(i)
		if not card.has_meta("headline"):
			continue
		var other: Dictionary = card.get_meta("headline")
		if int(other["turn"]) != int(h["turn"]) or String(other["faction"]) != String(h["faction"]):
			continue
		if not String(other["kicker"]).ends_with("INCOMING"):
			other["kicker"] = "%s · INCOMING" % other["kicker"]
		other["incoming"] = String(h["title"])
		_replace_card(card, bool(card.get_meta("lead", false)))
		return true
	return false


# --- Cards ----------------------------------------------------------------------------

func _card(h: Dictionary, lead: bool) -> PanelContainer:
	var s := EraTheme.style_of(self)
	var tone := _tone(h, s)
	var trust := float(h.get("printed_trust", 100.0))
	var contested := trust < DISINFORMATION_TRUST and String(h.get("counter", "")) != ""
	var shown_title := String(h["counter"]) if contested else String(h["title"])
	var card := PanelContainer.new()
	card.set_meta("headline", h)
	card.set_meta("lead", lead)
	card.set_meta("shown_title", shown_title)
	var style := EraTheme.panel(s, s.raised, s.border, s.control_radius + 4, 12)
	if _horizontal:
		style.content_margin_top = 9
		style.content_margin_bottom = 9
	card.add_theme_stylebox_override("panel", style)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	if _horizontal:
		card.custom_minimum_size = Vector2(STRIP_CARD_WIDTH, 0)
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.add_child(_strip_body(h, s, tone, shown_title, contested, trust))
	else:
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(_list_body(h, s, tone, shown_title, contested, trust, lead))
	return card


func _strip_body(h: Dictionary, s: EraStyle, tone: Color, title: String, contested: bool, trust: float) -> Control:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.add_child(_tile(String(h["glyph"]), tone, s, 30, 17))
	var heads := VBoxContainer.new()
	heads.add_theme_constant_override("separation", 0)
	heads.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heads.add_child(_kicker_row(h, s, contested, trust))
	heads.add_child(_meta(h, s))
	top.add_child(heads)
	body.add_child(top)
	var headline := _headline_label(title, s, 16)
	headline.max_lines_visible = 3
	body.add_child(headline)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(spacer)
	body.add_child(_byline_row(h, s, contested))
	return body


func _list_body(h: Dictionary, s: EraStyle, tone: Color, title: String, contested: bool, trust: float, lead: bool) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if lead:
		var art := WireArt.new()
		art.custom_minimum_size = Vector2(0, LEAD_ART_HEIGHT)
		art.tint = tone
		art.ground = s.bg.lerp(tone, 0.08)
		art.line_color = Color(tone, 0.22)
		art.seed_value = hash("%s|%d" % [h["title"], h["turn"]])
		art.stamp = "NO HUMAN AUTHOR" if bool(h["unattributed"]) else ""
		art.stamp_font = s.font_ui_bold
		column.add_child(art)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not lead:
		var tile := _tile(String(h["glyph"]), tone, s, 52, 26)
		tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(tile)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 4)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kicker_row := _kicker_row(h, s, contested, trust, true)
	text.add_child(kicker_row)
	text.add_child(_headline_label(title, s, 22 if lead else 17))
	if lead and String(h["dek"]) != "" and not contested:
		var dek := Label.new()
		dek.text = String(h["dek"])
		dek.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dek.add_theme_font_override("font", s.font_ui)
		dek.add_theme_font_size_override("font_size", 14)
		dek.add_theme_color_override("font_color", s.text_dim)
		text.add_child(dek)
	if String(h.get("incoming", "")) != "":
		var incoming := Label.new()
		incoming.text = "▸ " + String(h["incoming"])
		incoming.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		incoming.add_theme_font_override("font", s.font_ui)
		incoming.add_theme_font_size_override("font_size", 12)
		incoming.add_theme_color_override("font_color", s.warn)
		text.add_child(incoming)
	text.add_child(_byline_row(h, s, contested))
	row.add_child(text)
	column.add_child(row)
	return column


func _tile(glyph: String, tone: Color, s: EraStyle, size_px: int, glyph_px: int) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(size_px, size_px)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := EraTheme.box(s.raised.lerp(tone, 0.2), Color(tone, 0.45), 1 if s.border_width > 0 else 0,
		maxi(6, s.control_radius - 1), 0.0, 0.0, s.corner_detail)
	tile.add_theme_stylebox_override("panel", box)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(Glyphs.icon(glyph, glyph_px, tone, 1.6))
	tile.add_child(center)
	return tile


func _kicker_row(h: Dictionary, s: EraStyle, contested: bool, trust: float, with_meta: bool = false) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kicker := Label.new()
	kicker.text = String(h["kicker"])
	kicker.clip_text = true
	kicker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kicker.add_theme_font_override("font", _kicker_font(s))
	kicker.add_theme_font_size_override("font_size", 11)
	kicker.add_theme_color_override("font_color", _severity_color(String(h["severity"]), s))
	row.add_child(kicker)
	if trust < UNCONFIRMED_TRUST:
		var seal := Glyphs.icon("seal_broken" if contested else "seal_crack", 14, s.critical if contested else s.warn, 1.5)
		seal.tooltip_text = "Conflicting reports" if contested else "Unconfirmed: one source"
		seal.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(seal)
	if with_meta:
		row.add_child(_meta(h, s))
	return row


func _meta(h: Dictionary, s: EraStyle) -> Label:
	var meta := Label.new()
	meta.text = "%d · T%d" % [int(floor(float(h["year"]))), int(h["turn"])]
	meta.add_theme_font_override("font", s.font_mono)
	meta.add_theme_font_size_override("font_size", 11)
	meta.add_theme_color_override("font_color", s.text_dim)
	return meta


func _headline_label(title: String, s: EraStyle, font_size: int) -> Label:
	var label := Label.new()
	label.text = title
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_override("font", EraStyle.font(SERIF))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", s.text_bright)
	label.add_theme_constant_override("line_spacing", 0)
	return label


func _byline_row(h: Dictionary, s: EraStyle, contested: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var faction := String(h["faction"])
	var dot := Dot.new()
	dot.color = s.faction_color(faction) if faction != "" else s.text_dim
	dot.custom_minimum_size = Vector2(7, 7)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var byline := Label.new()
	var text := "Official channels" if contested else String(h["byline"])
	if bool(h.get("mine", false)) and not contested:
		text += " · you"
	byline.text = text
	byline.clip_text = true
	byline.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	byline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	byline.add_theme_font_override("font", s.font_ui)
	byline.add_theme_font_size_override("font_size", 12)
	byline.add_theme_color_override("font_color", s.text_dim)
	row.add_child(byline)
	if not contested:
		row.add_child(_pips(h["deltas"], s))
	return row


## Up to three metric glyphs with ▲/▼ pips, blue for help and orange for harm.
func _pips(deltas: Dictionary, s: EraStyle) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var keys: Array = deltas.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		var da := absf(float(deltas[a]))
		var db := absf(float(deltas[b]))
		return da > db if not is_equal_approx(da, db) else a < b)
	for key in keys.slice(0, MAX_PIPS):
		var delta := float(deltas[key])
		var marks := UiFormat.pips(delta)
		if marks.is_empty():
			continue
		var color := s.good if UiFormat.is_improvement(String(key), delta) else s.bad
		var pip := HBoxContainer.new()
		pip.add_theme_constant_override("separation", 0)
		pip.mouse_filter = Control.MOUSE_FILTER_PASS
		pip.tooltip_text = "%s %s" % [UiFormat.metric_name(String(key)), UiFormat.signed(delta)]
		pip.add_child(Glyphs.icon(Glyphs.for_metric(String(key)), 15, color, 1.9))
		var label := Label.new()
		label.text = marks
		label.add_theme_font_override("font", EraStyle.SYMBOL_FONT)
		label.add_theme_font_size_override("font_size", 8)
		label.add_theme_color_override("font_color", color)
		label.add_theme_constant_override("line_spacing", 0)
		pip.add_child(label)
		box.add_child(pip)
	return box


func _tone(h: Dictionary, s: EraStyle) -> Color:
	var faction := String(h["faction"])
	if faction != "":
		return s.faction_color(faction)
	match String(h["category"]):
		"THRESHOLD":
			return s.metric_color(String(h.get("metric", ""))) if h.has("metric") else s.warn
		"EMERGENCE":
			return s.metric_color(WorldState.ALIGNMENT_DRIFT)
		"COLLAPSE":
			return s.critical
		"ENDGAME":
			return s.critical if String(h["glyph"]) != "seal_check" else s.good
	return s.accent


func _severity_color(severity: String, s: EraStyle) -> Color:
	match severity:
		"CRITICAL":
			return s.critical
		"WARN":
			return s.warn
	return s.text_dim


## The era's bold UI face, letter-spaced for kickers.
static func _kicker_font(s: EraStyle) -> Font:
	if not _kicker_fonts.has(s.era):
		var variation := FontVariation.new()
		variation.base_font = s.font_ui_bold
		variation.spacing_glyph = 1
		_kicker_fonts[s.era] = variation
	return _kicker_fonts[s.era]


static func _dot_texture(color: Color) -> Texture2D:
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20\" height=\"20\" viewBox=\"0 0 20 20\"><circle cx=\"10\" cy=\"10\" r=\"7\" fill=\"#%s\"/></svg>" % color.to_html(false)
	var texture := Glyphs.svg_texture(svg)
	if texture is ImageTexture:
		(texture as ImageTexture).set_size_override(Vector2i(8, 8))
	return texture


## A small filled circle (byline faction dot).
class Dot:
	extends Control
	var color := Color.WHITE

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(size * 0.5, minf(size.x, size.y) * 0.5, color)


## The newspaper double rule under the masthead (2 px over 1 px).
class DoubleRule:
	extends Control
	var color := Color.WHITE

	func _ready() -> void:
		custom_minimum_size = Vector2(0, 5)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		draw_rect(Rect2(0, 0, size.x, 2), color)
		draw_rect(Rect2(0, 4, size.x, 1), color)


## The lead story's illustration: a lattice of agents in the story's color,
## stamped when no human signed the story.
class WireArt:
	extends Control
	var tint := Color.WHITE
	var ground := Color.BLACK
	var line_color := Color(1, 1, 1, 0.2)
	var seed_value := 0
	var stamp := ""
	var stamp_font: Font

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		resized.connect(queue_redraw)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), ground)
		for i in range(1, 4):
			var y := size.y * float(i) / 4.0
			draw_line(Vector2(0, y), Vector2(size.x, y), line_color, 1.0)
		var columns := maxi(3, int(size.x / 60.0))
		for i in range(1, columns):
			var x := size.x * float(i) / float(columns)
			draw_line(Vector2(x, 0), Vector2(x, size.y), line_color, 1.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var nodes := PackedVector2Array()
		var count := clampi(int(size.x / 34.0), 6, 14)
		for i in count:
			var x := (float(i) + 0.5) / float(count) * size.x + rng.randf_range(-12.0, 12.0)
			nodes.append(Vector2(x, rng.randf_range(14.0, size.y - 14.0)))
		for i in nodes.size() - 1:
			draw_line(nodes[i], nodes[i + 1], Color(tint, 0.7), 1.0, true)
			if i + 2 < nodes.size() and rng.randf() < 0.45:
				draw_line(nodes[i], nodes[i + 2], Color(tint, 0.45), 1.0, true)
		for i in nodes.size():
			draw_circle(nodes[i], 2.5 + float(i % 3), tint.lightened(0.45))
		for i in count:
			draw_circle(Vector2(rng.randf_range(0.0, size.x), rng.randf_range(0.0, size.y)), 1.5, Color(tint, 0.55))
		if stamp != "" and stamp_font != null:
			var font_size := 10
			var text_size := stamp_font.get_string_size(stamp, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var box := Vector2(text_size.x + 16.0, 22.0)
			var at := Vector2(size.x - box.x - 12.0, size.y - box.y - 10.0)
			var ink := tint.lightened(0.6)
			draw_set_transform(at + box * 0.5, deg_to_rad(-3.0))
			draw_rect(Rect2(-box * 0.5, box), ink, false, 1.5)
			draw_string(stamp_font, Vector2(-text_size.x * 0.5, 4.0), stamp, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
			draw_set_transform(Vector2.ZERO)
