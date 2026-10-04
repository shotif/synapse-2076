class_name PassDevice
extends Control
## Pass-and-play hand-off. Between two players' turns an opaque cover hides
## the desk and names who takes the device next: "Pass the device to the
## Frontier Lab CEO" over the faction's glyph in its color, the turn and the
## half-year, and a short "While you were away" list of headlines. The button
## "I'm the Frontier Lab CEO. Show my desk" (or Enter) lifts the cover and
## emits [signal revealed].
##
##   pass_device.present(role, engine.get_year(),
##       PassDevice.headlines_since(engine.event_log, seen_until, role))
##   pass_device.revealed.connect(_on_desk_revealed)
##
## While it is up it takes every click, touch and key. It draws above the
## rest of the interface (z_index Z); add it as the dashboard's last child so
## it is also first in line for input. It follows the era theme (EraTheme)
## and fits a 412 px phone (set_compact(true)) as well as the desktop.

signal revealed(role: String)

## Above the swiped crisis card (1), the front page and menus (2) and the
## era upgrade (3).
const Z := 4
const DESKTOP_WIDTH := 560.0
const MAX_HEADLINES := 5
## A key still held by the last player must not lift the cover: keys count
## only this long (seconds) after present().
const KEY_DELAY := 0.4
const MARK_SIZE := 76

## The faction taking the device.
var role := ""
var year := SimConstants.START_YEAR
var turn := 0
var headlines: Array[String] = []

var _compact := false
var _era := 0
var _shown_at := 0
var _pending := false
var _shade: ColorRect
var _glow: TextureRect
var _frame: MarginContainer
var _pad: MarginContainer
var _column: VBoxContainer
var _kicker: Label
var _mark: TextureRect
var _lead: Label
var _title: Label
var _away: PanelContainer
var _away_title: Label
var _away_list: VBoxContainer
var _reveal: Button
var _hint: Label

static var _glow_texture: GradientTexture2D


func _ready() -> void:
	z_index = Z
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame = UiLayout.build_overlay(self, Color.BLACK)
	_shade = get_child(0) as ColorRect
	_shade.name = "Cover"
	# A soft halo of the faction's color behind the glyph.
	_glow = TextureRect.new()
	_glow.name = "Glow"
	_glow.texture = _halo()
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_glow)
	move_child(_glow, 1)

	_pad = MarginContainer.new()
	_pad.name = "Pad"
	_frame.add_child(_pad)
	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.add_theme_constant_override("separation", 14)
	_pad.add_child(_column)
	_kicker = _label("Kicker", HORIZONTAL_ALIGNMENT_CENTER)
	_column.add_child(_kicker)
	_mark = TextureRect.new()
	_mark.name = "Mark"
	_mark.custom_minimum_size = Vector2(MARK_SIZE, MARK_SIZE)
	_mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_column.add_child(_mark)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 2)
	_column.add_child(names)
	_lead = _label("Lead", HORIZONTAL_ALIGNMENT_CENTER)
	names.add_child(_lead)
	_title = _label("RoleTitle", HORIZONTAL_ALIGNMENT_CENTER)
	names.add_child(_title)

	_away = PanelContainer.new()
	_away.name = "WhileAway"
	_away.theme_type_variation = "InsetPanel"
	_column.add_child(_away)
	var away_box := VBoxContainer.new()
	away_box.add_theme_constant_override("separation", 8)
	_away.add_child(away_box)
	_away_title = _label("AwayTitle", HORIZONTAL_ALIGNMENT_LEFT)
	away_box.add_child(_away_title)
	_away_list = VBoxContainer.new()
	_away_list.name = "Headlines"
	_away_list.add_theme_constant_override("separation", 6)
	away_box.add_child(_away_list)

	_reveal = Button.new()
	_reveal.name = "Reveal"
	_reveal.theme_type_variation = "AccentButton"
	_reveal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reveal.custom_minimum_size = Vector2(0, 52)
	_reveal.pressed.connect(reveal)
	_column.add_child(_reveal)
	_hint = _label("Hint", HORIZONTAL_ALIGNMENT_CENTER)
	_column.add_child(_hint)

	UiLayout.pass_touch_through(_pad)
	resized.connect(_apply_layout)
	visible = false
	_restyle()
	if _pending:
		_pending = false
		present(role, year, headlines, turn)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _column != null and EraTheme.style_of(self).era != _era:
		_restyle()


## Covers the screen for [param for_role]'s turn. [param at_year] is the
## campaign year (SimulationEngine.get_year()), [param recent] the headlines
## for "While you were away" (at most MAX_HEADLINES; the box hides when there
## are none) and [param at_turn] the turn (worked out from the year when -1).
func present(for_role: String, at_year: float, recent: Array[String] = [], at_turn: int = -1) -> void:
	role = for_role
	year = at_year
	turn = at_turn if at_turn >= 0 else roundi((at_year - SimConstants.START_YEAR) / SimConstants.YEARS_PER_TURN)
	headlines.assign(recent.slice(0, MAX_HEADLINES))
	if _column == null:
		# Not built yet: show once _ready() has run.
		_pending = true
		return
	_fill()
	_apply_layout()
	var scroll: ScrollContainer = get_node_or_null("OverlayScroll")
	if scroll != null:
		scroll.scroll_vertical = 0
	visible = true
	_shown_at = Time.get_ticks_msec()
	# Nothing behind the cover keeps keyboard focus.
	if is_inside_tree():
		get_viewport().gui_release_focus()


## Lifts the cover and emits [signal revealed] (the button, Enter, tests).
func reveal() -> void:
	if not visible:
		return
	visible = false
	Haptics.pulse("confirm")
	revealed.emit(role)


## Hides the cover without revealing anyone (a new campaign, the debrief).
func close() -> void:
	visible = false


func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	if _column != null:
		_apply_fonts(EraTheme.style_of(self))
		_apply_layout()


## Up to [param limit] headline titles for [param viewer_role] from the
## entries of [param event_log] at index [param from_index] and later: the
## newsworthy ones (HeadlineWriter), critical first and then the latest,
## listed in the order they happened. The viewer's own moves are left out.
static func headlines_since(event_log: Array, from_index: int, viewer_role: String, limit: int = MAX_HEADLINES) -> Array[String]:
	var picked: Array = []
	for i in range(maxi(from_index, 0), event_log.size()):
		if not (event_log[i] is Dictionary):
			continue
		var h := HeadlineWriter.headline(event_log[i], viewer_role)
		var title := String(h.get("title", "")).strip_edges()
		if not bool(h.get("newsworthy", false)) or bool(h.get("mine", false)) or title.is_empty():
			continue
		var rank: int = {"CRITICAL": 2, "WARN": 1}.get(String(h.get("severity", "INFO")), 0)
		picked.append([rank, i, title])
	picked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] > b[1]))
	picked = picked.slice(0, maxi(limit, 0))
	picked.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
	var out: Array[String] = []
	for item in picked:
		if not out.has(String(item[2])):
			out.append(String(item[2]))
	return out


# --- Content and style -----------------------------------------------------------------

func _fill() -> void:
	var s := EraTheme.style_of(self)
	var color := s.faction_color(role)
	var title := UiFormat.role_title(role)
	var half := "H1" if year - floorf(year) < 0.25 else "H2"
	_kicker.text = _voice(s, "Pass and play · Turn %d · %s %d" % [turn, half, int(floor(year))])
	var radius := 18 if s.era == 1 else (6 if s.era == 2 else MARK_SIZE / 2)
	_mark.texture = Glyphs.tile(Glyphs.for_faction(role), MARK_SIZE, color, s.bg, radius, 0.56)
	_glow.self_modulate = Color(color, 0.2 if s.era != 1 else 0.14)
	_lead.text = _voice(s, "Pass the device to the")
	_title.text = title
	_title.add_theme_color_override("font_color", color.lerp(s.text_bright, 0.15))
	_away_title.text = _voice(s, "While you were away")
	for child in _away_list.get_children():
		_away_list.remove_child(child)
		child.queue_free()
	for line in headlines:
		_away_list.add_child(_headline_row(s, line))
	_away.visible = not headlines.is_empty()
	_reveal.text = "I'm the %s. Show my desk" % title
	_hint.text = _voice(s, "Everyone else, look away.")
	_apply_fonts(s)
	UiLayout.pass_touch_through(_pad)


func _headline_row(s: EraStyle, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var icon := Glyphs.icon("news", 14, s.text_dim)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	var label := _label("Headline", HORIZONTAL_ALIGNMENT_LEFT)
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	CrisisCard.style_label(label, s.font_ui, 13 if _compact else 14, s.text)
	row.add_child(label)
	return row


## Era colors and the cover itself (opaque: nothing of the desk shows).
func _restyle() -> void:
	var s := EraTheme.style_of(self)
	_era = s.era
	_shade.color = Color(s.bg, 1.0)
	if not role.is_empty():
		_fill()
	else:
		_apply_fonts(s)


func _apply_fonts(s: EraStyle) -> void:
	CrisisCard.style_label(_kicker, s.font_mono, 11 if _compact else 12, s.accent)
	CrisisCard.style_label(_lead, s.font_ui, 15 if _compact else 17, s.text_dim)
	# Syne ExtraBold runs very wide, so Era III uses the bold face.
	var title_font := s.font_ui_bold if s.era == 3 else s.font_display
	_title.add_theme_font_override("font", title_font)
	_title.add_theme_font_size_override("font_size", 26 if _compact else 34)
	_title.add_theme_color_override("font_shadow_color", Color(s.accent, 0.35) if s.era == 2 else Color(0, 0, 0, 0))
	_title.add_theme_constant_override("shadow_outline_size", 6 if s.era == 2 else 0)
	CrisisCard.style_label(_away_title, s.font_ui_bold, 12 if _compact else 13, s.text_bright)
	CrisisCard.style_label(_hint, s.font_ui, 12, s.text_dim)
	_reveal.add_theme_font_override("font", s.font_ui_bold)
	_reveal.add_theme_font_size_override("font_size", 15 if _compact else 16)
	for row in _away_list.get_children():
		var label := row.get_child(1) as Label
		if label != null:
			CrisisCard.style_label(label, s.font_ui, 13 if _compact else 14, s.text)


func _apply_layout() -> void:
	if _column == null:
		return
	UiLayout.set_overlay_margin(_frame, _compact)
	var side := 8 if _compact else 0
	for edge in ["left", "right"]:
		_pad.add_theme_constant_override("margin_" + edge, side)
	_pad.add_theme_constant_override("margin_top", 16 if _compact else 0)
	_pad.add_theme_constant_override("margin_bottom", 16 if _compact else 0)
	var width := UiLayout.panel_width(size.x, DESKTOP_WIDTH, _compact) - side * 2.0
	_column.custom_minimum_size = Vector2(maxf(width, 200.0), 0)


## Small labels in the era's voice: as written in Era I, capitals in Era II,
## lower case in Era III.
static func _voice(s: EraStyle, text: String) -> String:
	match s.era:
		2:
			return text.to_upper()
		3:
			return text.to_lower()
	return text


static func _label(label_name: String, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.name = label_name
	label.horizontal_alignment = align
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func _halo() -> GradientTexture2D:
	if _glow_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		_glow_texture = GradientTexture2D.new()
		_glow_texture.gradient = gradient
		_glow_texture.fill = GradientTexture2D.FILL_RADIAL
		_glow_texture.fill_from = Vector2(0.5, 0.3)
		_glow_texture.fill_to = Vector2(0.5, 0.95)
		_glow_texture.width = 256
		_glow_texture.height = 256
	return _glow_texture


func _input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	var key := event as InputEventKey
	if key == null:
		return
	# Keys never reach the desk underneath.
	get_viewport().set_input_as_handled()
	if key.pressed and not key.echo and key.is_action("ui_accept") and Time.get_ticks_msec() - _shown_at >= int(KEY_DELAY * 1000.0):
		reveal()
