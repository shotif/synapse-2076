class_name EndingsGallery
extends Control
## The endings collection: the eight end-states, each reached (or not yet) as
## each of the four factions. A reached ending shows its glyph and name, the
## best verdict's seal and the date it was first reached; a locked one is a
## "?" silhouette. Every end-state carries its rarity (EndingsBook.rarity) and
## the header counts "n of 32".
##
##   gallery.open(endings_book)                 # or open(book, fresh) to mark new ones
##   gallery.closed.connect(...)
##
## Desktop: one row per end-state, the four roles as columns. Compact: each
## end-state above a two-column grid, one scrolling column that fits a 412 px
## phone. Era-styled; rebuilt when the era changes while it is open.

signal closed

const DESKTOP_WIDTH := 1240.0
const HEADER_WIDTH := 300.0
const CELL_HEIGHT := 96.0
## Glyphs for the end-states and the verdict seals (also used by ShareCard).
const OUTCOME_GLYPHS := {
	VictoryMatrix.ALGORITHMIC_FEUDALISM: "capital",
	VictoryMatrix.CO_EVOLUTIONARY_SYMBIOSIS: "diplomacy",
	VictoryMatrix.SYNTHETIC_EDEN: "resilience",
	VictoryMatrix.BALKANIZED_CYBER_ANARCHY: "tension",
	VictoryMatrix.ROGUE_ASI_CONTAINMENT: "lock",
	VictoryMatrix.NEO_LUDDITE_DECOUPLING: "disruption",
	VictoryMatrix.INSTRUMENTAL_CONVERGENCE: "coherence",
	VictoryMatrix.POST_BIOLOGICAL_DIASPORA: "spark",
}
const VERDICT_SEALS := {"VICTORY": "seal_check", "PYRRHIC": "seal_crack", "DEFEAT": "seal_broken"}

var book: EndingsBook
var _compact := false
var _era := 0
var _fresh := {}
var _frame: MarginContainer
var _panel: PanelContainer
var _box: VBoxContainer


func _ready() -> void:
	# Fill the parent however we were created (scene or code).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame = UiLayout.build_overlay(self, Color(0.0, 0.0, 0.0, 0.82))
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.theme_type_variation = "OverlayPanel"
	_frame.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	_panel.add_child(_box)
	resized.connect(_apply_layout)
	visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _panel != null:
		(get_child(0) as ColorRect).color = Color(EraTheme.style_of(self).shade, 0.9)
		if book != null and EraTheme.style_of(self).era != _era:
			_build.call_deferred()


static func outcome_glyph(outcome_id: String) -> String:
	return String(OUTCOME_GLYPHS.get(outcome_id, "flag"))


static func verdict_seal(verdict: String) -> String:
	return String(VERDICT_SEALS.get(verdict, "seal"))


## End-states in their numbered order (1-8).
static func outcomes_by_number() -> Array:
	var out: Array = VictoryMatrix.OUTCOMES.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["number"]) < int(b["number"]))
	return out


## Shows [param endings_book]. [param fresh] (EndingsBook.record_result's
## return) marks the endings this campaign unlocked.
func open(endings_book: EndingsBook, fresh: Array = []) -> void:
	if not is_node_ready():
		ready.connect(open.bind(endings_book, fresh), CONNECT_ONE_SHOT)
		return
	book = endings_book
	_fresh = {}
	for item in fresh:
		if item is Dictionary:
			_fresh[EndingsBook.key(String(item.get("outcome", "")), String(item.get("role", "")))] = true
	_build()
	_apply_layout()
	var scroll: ScrollContainer = get_node_or_null("OverlayScroll")
	if scroll != null:
		scroll.scroll_vertical = 0
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	if book != null:
		_build()
	_apply_layout()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _apply_layout() -> void:
	if _panel == null:
		return
	_panel.custom_minimum_size = Vector2(UiLayout.panel_width(size.x, DESKTOP_WIDTH, _compact), 0)
	UiLayout.set_overlay_margin(_frame, _compact)


# --- Building ------------------------------------------------------------------------

func _build() -> void:
	if book == null or _box == null:
		return
	var s := EraTheme.style_of(self)
	_era = s.era
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	_box.add_child(_header(s))
	if not _compact:
		_box.add_child(_column_heads(s))
	for outcome in outcomes_by_number():
		_box.add_child(_outcome_row(outcome, s))
	var note := Label.new()
	note.theme_type_variation = "Caption"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Rarity is how often the end-state comes up when the machines play every side: Common in 15% of campaigns or more, Uncommon 10%, Rare 2%, Legendary less."
	_box.add_child(note)
	UiLayout.pass_touch_through(_panel)


func _header(s: EraStyle) -> Control:
	var progress := book.progress()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var mark := Glyphs.icon("book", 26 if _compact else 30, s.accent)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(mark)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	var title := Label.new()
	title.theme_type_variation = "HeaderTitle"
	title.text = "Endings"
	title.add_theme_font_size_override("font_size", 22 if _compact else 26)
	titles.add_child(title)
	var subtitle := Label.new()
	subtitle.theme_type_variation = "DimLabel"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.text = "Eight end-states, reached as each of the four factions."
	titles.add_child(subtitle)
	head.add_child(titles)
	var count := Label.new()
	count.name = "Progress"
	count.theme_type_variation = "ValueLabel"
	count.text = "%d of %d" % [progress.x, progress.y]
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(count)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.theme_type_variation = "GhostButton"
	close_button.icon = Glyphs.texture("close", 18)
	close_button.tooltip_text = "Close"
	close_button.custom_minimum_size = Vector2(44, 44)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close)
	head.add_child(close_button)
	box.add_child(head)
	var bar := ProgressBar.new()
	bar.name = "ProgressBar"
	bar.show_percentage = false
	bar.max_value = float(progress.y)
	bar.value = float(progress.x)
	bar.custom_minimum_size = Vector2(0, 6)
	box.add_child(bar)
	return box


## Desktop: the four roles above their columns.
func _column_heads(s: EraStyle) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(HEADER_WIDTH, 0)
	row.add_child(spacer)
	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 8)
	for role in SimConstants.FACTION_ORDER:
		var head := HBoxContainer.new()
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.size_flags_stretch_ratio = 1.0
		head.add_theme_constant_override("separation", 6)
		head.add_child(Glyphs.icon(Glyphs.for_faction(role), 16, s.faction_color(role)))
		var label := Label.new()
		label.text = s.label(UiFormat.role_name(role))
		label.theme_type_variation = "PanelTitle"
		label.add_theme_font_size_override("font_size", 13)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		head.add_child(label)
		columns.add_child(head)
	row.add_child(columns)
	return row


func _outcome_row(outcome: Dictionary, s: EraStyle) -> Control:
	var outcome_id := String(outcome["id"])
	var row := BoxContainer.new()
	row.name = "Row_%s" % outcome_id
	row.vertical = _compact
	row.add_theme_constant_override("separation", 8 if _compact else 12)
	var header := VBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 2)
	header.custom_minimum_size = Vector2(0.0 if _compact else HEADER_WIDTH, 0)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _compact else Control.SIZE_FILL
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var number := Label.new()
	number.theme_type_variation = "Kicker"
	number.text = s.label("End-state %d" % int(outcome["number"]))
	top.add_child(number)
	top.add_child(_rarity_badge(outcome_id, s))
	header.add_child(top)
	var name_label := Label.new()
	name_label.name = "OutcomeName"
	name_label.text = String(outcome["name"])
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_override("font", s.font_ui_bold)
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", s.text_bright)
	header.add_child(name_label)
	var subtitle := Label.new()
	subtitle.theme_type_variation = "DimLabel"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.text = String(outcome["subtitle"])
	header.add_child(subtitle)
	header.tooltip_text = String(outcome["description"])
	row.add_child(header)
	var cells := GridContainer.new()
	cells.name = "Cells"
	cells.columns = 2 if _compact else 4
	cells.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cells.add_theme_constant_override("h_separation", 8)
	cells.add_theme_constant_override("v_separation", 8)
	for role in SimConstants.FACTION_ORDER:
		cells.add_child(_cell(outcome, String(role), s))
	row.add_child(cells)
	return row


func _rarity_badge(outcome_id: String, s: EraStyle) -> Control:
	var rarity := EndingsBook.rarity(outcome_id)
	var color := rarity_color(rarity, s)
	var badge := PanelContainer.new()
	badge.name = "Rarity"
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_theme_stylebox_override("panel", EraTheme.box(Color(color, 0.14), Color(color, 0.6), 1, 999, 8, 1, s.corner_detail))
	badge.tooltip_text = "%.1f%% of autoplay campaigns end here" % EndingsBook.share(outcome_id)
	var label := Label.new()
	label.text = rarity.to_upper()
	label.add_theme_font_override("font", s.font_mono)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", color)
	badge.add_child(label)
	return badge


## Era colors for the rarities: dim, green, violet, gold.
static func rarity_color(rarity: String, s: EraStyle) -> Color:
	match rarity:
		"Uncommon":
			return s.metric_color(WorldState.EPISTEMIC_TRUST)
		"Rare":
			return s.metric_color(WorldState.ALGORITHMIC_AUTONOMY)
		EndingsBook.LEGENDARY:
			return s.warn
	return s.text_dim


static func verdict_color(verdict: String, s: EraStyle) -> Color:
	match verdict:
		"VICTORY":
			return s.good
		"PYRRHIC":
			return s.warn
	return s.critical


func _cell(outcome: Dictionary, role: String, s: EraStyle) -> PanelContainer:
	var outcome_id := String(outcome["id"])
	var unlocked := book.is_unlocked(outcome_id, role)
	var fresh := _fresh.has(EndingsBook.key(outcome_id, role))
	var tint := s.faction_color(role)
	var card := PanelContainer.new()
	card.name = "Cell_%s_%s" % [outcome_id, role]
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, CELL_HEIGHT)
	var style := EraTheme.panel(s, s.raised if unlocked else Color(s.raised, 0.35),
		Color(tint, 0.85) if fresh else (Color(tint, 0.45) if unlocked else Color(s.border, 0.5)), s.control_radius + 2, 10)
	style.set_border_width_all(2 if fresh else 1)
	card.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)
	var role_line := HBoxContainer.new()
	role_line.add_theme_constant_override("separation", 5)
	role_line.add_child(Glyphs.icon(Glyphs.for_faction(role), 14, tint if unlocked else Color(s.text_dim, 0.6)))
	var role_label := Label.new()
	role_label.text = UiFormat.role_name(role)
	role_label.theme_type_variation = "Caption"
	role_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	role_label.clip_text = true
	role_line.add_child(role_label)
	if fresh:
		var new_label := Label.new()
		new_label.name = "New"
		new_label.text = "NEW"
		new_label.add_theme_font_override("font", s.font_mono_bold)
		new_label.add_theme_font_size_override("font_size", 10)
		new_label.add_theme_color_override("font_color", s.accent)
		role_line.add_child(new_label)
	box.add_child(role_line)
	if not unlocked:
		var mystery := Label.new()
		mystery.name = "Locked"
		mystery.text = "?"
		mystery.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mystery.size_flags_vertical = Control.SIZE_EXPAND_FILL
		mystery.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mystery.add_theme_font_override("font", s.font_display)
		mystery.add_theme_font_size_override("font_size", 30)
		mystery.add_theme_color_override("font_color", Color(s.text_dim, 0.45))
		box.add_child(mystery)
		card.tooltip_text = "Not yet reached as the %s." % UiFormat.role_name(role)
		return card
	var entry := book.entry(outcome_id, role)
	var verdict := String(entry.get("best", "DEFEAT"))
	var title_line := HBoxContainer.new()
	title_line.add_theme_constant_override("separation", 6)
	title_line.add_child(Glyphs.icon(outcome_glyph(outcome_id), 18, s.text_bright))
	var title := Label.new()
	title.name = "OutcomeName"
	title.text = String(outcome["name"])
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", s.font_ui_bold)
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", s.text_bright)
	title_line.add_child(title)
	box.add_child(title_line)
	var verdict_line := HBoxContainer.new()
	verdict_line.add_theme_constant_override("separation", 5)
	var color := verdict_color(verdict, s)
	verdict_line.add_child(Glyphs.icon(verdict_seal(verdict), 16, color))
	var verdict_label := Label.new()
	verdict_label.name = "Verdict"
	verdict_label.text = "%s %d" % [verdict.capitalize(), int(round(float(entry.get("best_score", 0.0))))]
	verdict_label.add_theme_font_override("font", s.font_mono_bold)
	verdict_label.add_theme_font_size_override("font_size", 12)
	verdict_label.add_theme_color_override("font_color", color)
	verdict_line.add_child(verdict_label)
	box.add_child(verdict_line)
	var date := Label.new()
	date.name = "Date"
	date.theme_type_variation = "Caption"
	date.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var count := int(entry.get("count", 1))
	date.text = "First %s%s" % [String(entry.get("first", "")), " · ×%d" % count if count > 1 else ""]
	box.add_child(date)
	card.tooltip_text = String(outcome["description"])
	return card
