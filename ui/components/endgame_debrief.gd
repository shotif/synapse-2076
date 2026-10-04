class_name EndgameDebrief
extends Control
## The debrief as a history book: "A History of the Algorithmic Century", one
## chapter per hardware era the campaign reached (written by EraChronicle from
## the campaign's own record) and an epilogue. Each spread has the chapter on
## the left (Cinzel label, EB Garamond italic title, drop cap, footnotes,
## navigation) and on the right a figure of trust and drift over the chapter's
## years and the "How it ended" verdict. Below, "Appendix: the full record" in
## the era's own chrome: the trajectory chart, the eight end-state affinities,
## final statistics and the buttons.
##
## The epilogue lists the campaign's turning points (TurningPoints: the
## player's weightiest crisis choices, crises that broke, the moments that
## changed the era and collapses), each with a "What if?" button that asks
## to rewind to the last decision before it, and offers Share (the ending as
## a front page) and Endings (the collection).
##
##   debrief.present(result, engine.event_log)
##   debrief.rewind_requested.connect(func(turn): ...)   # SimulationEngine.from_record(record, turn)
##
## Desktop: a two-page spread about 1300 px wide. Compact: one column. The book
## keeps its typography in every era; the appendix follows the era theme.

signal new_campaign_requested
signal closed
## "What if?": rebuild the campaign at the player phase of [param turn].
signal rewind_requested(turn: int)
signal share_requested
signal endings_requested

const SPREAD_WIDTH := 1300.0
const PAPER := Color("#FBF7EF")
const INK := Color("#1F1B16")
const OXBLOOD := Color("#7A2E2E")
const DIM := Color("#6B6055")
const CAPTION := Color("#4A4239")
const NOTE := Color("#5C5248")
const RULE := Color("#D9CFBF")
const BOX_RULE := Color("#CDBFA8")
const GRID := Color("#B9AE9C")
const GUTTER := Color("#E3D8C6")
const JUSTIFY := TextServer.JUSTIFICATION_WORD_BOUND | TextServer.JUSTIFICATION_KASHIDA \
	| TextServer.JUSTIFICATION_TRIM_EDGE_SPACES | TextServer.JUSTIFICATION_SKIP_LAST_LINE \
	| TextServer.JUSTIFICATION_SKIP_LAST_LINE_WITH_VISIBLE_CHARS
const BOOK_TITLE := "A HISTORY OF THE ALGORITHMIC CENTURY"
const REASONS := {"TURN_LIMIT": "The century ran its course", "PLAYER_LOSS": "Instant loss",
	"CATASTROPHE": "Catastrophic threshold"}
const MAX_TURNING_POINTS := 5
const KIND_LABELS := {TurningPoints.CHOICE: "YOUR CHOICE", TurningPoints.FALLOUT: "LEFT TOO LONG",
	TurningPoints.MOMENT: "THE ERA TURNS", TurningPoints.COLLAPSE: "COLLAPSE"}

## Show the "What if?" buttons (the dashboard turns them off when it cannot
## rewind, e.g. for a campaign without a record). Takes effect at once.
var allow_rewind := true:
	set(value):
		allow_rewind = value
		if not _result.is_empty() and _left_box != null:
			_show_page(_page_index)
var _compact := false
var _result := {}
var _chapters: Array = []
var _epilogue := {}
var _turning_points: Array = []
var _page_index := 0
var _frame: MarginContainer
var _book: VBoxContainer
var _spread: BoxContainer
var _left: PanelContainer
var _right: PanelContainer
var _left_box: VBoxContainer
var _right_box: VBoxContainer
var _appendix: PanelContainer
var _appendix_title: Label
var _appendix_caption: Label
var _columns: BoxContainer
var _right_column: VBoxContainer
var _affinity_title: Label
var _stats_title: Label
var _chart: TrajectoryChart
var _affinity_box: VBoxContainer
var _stats_grid: GridContainer
var _buttons: BoxContainer


func _ready() -> void:
	# Fill the parent however we were created (scene or code).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame = UiLayout.build_overlay(self, Color(0.02, 0.02, 0.03, 0.86))
	_book = VBoxContainer.new()
	_book.name = "Book"
	_book.add_theme_constant_override("separation", 18)
	_frame.add_child(_book)
	_spread = BoxContainer.new()
	_spread.name = "Spread"
	_spread.add_theme_constant_override("separation", 0)
	_book.add_child(_spread)
	_left = _paper()
	_left.name = "LeftPage"
	_spread.add_child(_left)
	_right = _paper()
	_right.name = "RightPage"
	_spread.add_child(_right)
	_left_box = VBoxContainer.new()
	_left_box.add_theme_constant_override("separation", 10)
	_left.add_child(_left_box)
	_right_box = VBoxContainer.new()
	_right_box.add_theme_constant_override("separation", 12)
	_right.add_child(_right_box)
	_build_appendix()
	UiLayout.pass_touch_through(_book)
	resized.connect(_apply_layout)
	visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _appendix != null and not _result.is_empty():
		_restyle_appendix.call_deferred()


func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	if not _result.is_empty():
		_show_page(_page_index)
	_apply_layout()


## Opens the book on the last chapter. [param event_log] is the engine's log
## (chapters are written from it); without it the chapters fall back to the
## history snapshots.
func present(result: Dictionary, event_log: Array = []) -> void:
	if not is_node_ready():
		ready.connect(present.bind(result, event_log), CONNECT_ONE_SHOT)
		return
	_result = result
	var history: Array = result.get("history", [])
	_chapters = EraChronicle.chapters(event_log, history, result)
	_epilogue = EraChronicle.epilogue(result)
	var humans: Array = result.get("humans", [])
	if humans.is_empty():
		humans = [String(result.get("player_role", ""))]
	_turning_points = TurningPoints.find_for(event_log, humans, MAX_TURNING_POINTS)
	_chart.set_history(history)
	_build_affinities(result.get("outcome", {}))
	_build_stats(result)
	_restyle_appendix()
	_page_index = maxi(0, _chapters.size() - 1)
	_show_page(_page_index)
	_apply_layout()
	var scroll: ScrollContainer = get_node_or_null("OverlayScroll")
	if scroll != null:
		scroll.scroll_vertical = 0
	visible = true


## Turns to chapter [param index] (0 = chapter I); the page after the last
## chapter is the epilogue.
func show_chapter(index: int) -> void:
	if _result.is_empty():
		return
	_show_page(clampi(index, 0, _chapters.size()))


func page_count() -> int:
	return _chapters.size() + 1


func current_page() -> int:
	return _page_index


## The turning points the epilogue lists (TurningPoints.find_for).
func turning_points() -> Array:
	return _turning_points.duplicate()


## Opens the epilogue (the page after the last chapter).
func show_epilogue() -> void:
	show_chapter(_chapters.size())


func _apply_layout() -> void:
	if _book == null:
		return
	var width := UiLayout.panel_width(size.x, SPREAD_WIDTH, _compact)
	_book.custom_minimum_size = Vector2(width, 0)
	_spread.vertical = _compact
	_spread.add_theme_constant_override("separation", 12 if _compact else 0)
	for page in [_left, _right]:
		var box: StyleBoxFlat = (page as PanelContainer).get_theme_stylebox("panel")
		var margin_h := 18.0 if _compact else 44.0
		box.content_margin_left = margin_h
		box.content_margin_right = margin_h
		box.content_margin_top = 16.0 if _compact else 30.0
		box.content_margin_bottom = 14.0 if _compact else 26.0
		(page as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_spine()
	_columns.vertical = _compact
	_chart.custom_minimum_size = Vector2(0, 240) if _compact else Vector2(760, 320)
	_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _compact else Control.SIZE_FILL
	_right_column.custom_minimum_size = Vector2(0.0 if _compact else 420.0, 0)
	_right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_grid.columns = 2 if _compact else 4
	_buttons.vertical = _compact
	for button in _buttons.get_children():
		(button as Control).custom_minimum_size = Vector2(0, 44)
	for row in _affinity_box.get_children():
		_style_affinity_row(row)
	UiLayout.set_overlay_margin(_frame, _compact)


## Desktop pages meet at a spine; stacked pages on phones are separate leaves.
func _style_spine() -> void:
	var left: StyleBoxFlat = _left.get_theme_stylebox("panel")
	var right: StyleBoxFlat = _right.get_theme_stylebox("panel")
	for box in [left, right]:
		(box as StyleBoxFlat).set_corner_radius_all(3)
		(box as StyleBoxFlat).set_border_width_all(0)
	if not _compact:
		left.corner_radius_top_right = 0
		left.corner_radius_bottom_right = 0
		left.border_width_right = 1
		right.corner_radius_top_left = 0
		right.corner_radius_bottom_left = 0
		right.border_width_left = 1


# --- Pages ---------------------------------------------------------------------------

func _show_page(index: int) -> void:
	_page_index = clampi(index, 0, _chapters.size())
	var epilogue := _page_index >= _chapters.size()
	var page: Dictionary = _epilogue if epilogue else _chapters[_page_index]
	_clear(_left_box)
	_clear(_right_box)
	_build_left(page, epilogue)
	_build_right(page, epilogue)
	UiLayout.pass_touch_through(_left)
	UiLayout.pass_touch_through(_right)


func _build_left(page: Dictionary, epilogue: bool) -> void:
	var folio := _folio()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(_text(BOOK_TITLE, "Cinzel-SemiBold.ttf", 9 if _compact else 10, DIM, HORIZONTAL_ALIGNMENT_LEFT, 2, true))
	head.add_child(_text(str(folio), "EBGaramond-Regular.ttf", 13 if _compact else 14, DIM, HORIZONTAL_ALIGNMENT_RIGHT))
	_left_box.add_child(head)
	_left_box.add_child(_rule(RULE))
	_left_box.add_child(_tabs())

	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 2)
	var label := "EPILOGUE" if epilogue else "CHAPTER %s" % page.get("number", "")
	heading.add_child(_text(label, "Cinzel-SemiBold.ttf", 12 if _compact else 13, OXBLOOD, HORIZONTAL_ALIGNMENT_CENTER, 4))
	var title := _wrapped(String(page.get("title", "")), "EBGaramond-Italic.ttf", 30 if _compact else 36, INK,
		HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_constant_override("line_spacing", -2)
	heading.add_child(title)
	var years := String(page.get("years", "")).replace("–", " – ")
	heading.add_child(_text(years, "EBGaramond-Regular.ttf", 14 if _compact else 15, DIM, HORIZONTAL_ALIGNMENT_CENTER, 1))
	heading.add_child(_ornament())
	_left_box.add_child(heading)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	var text_width := UiLayout.panel_width(size.x, SPREAD_WIDTH, _compact) - 36.0 if _compact else SPREAD_WIDTH * 0.5 - 88.0
	var chars_per_line := text_width / (0.45 * (15.0 if _compact else 16.0))
	var paragraphs := FrontPage.merge_short_lead(page.get("paragraphs", []), chars_per_line)
	for i in paragraphs.size():
		var text := String(paragraphs[i])
		body.add_child(_paragraph(text, i == 0, i > 0 or FrontPage.wraps_drop_cap(text, chars_per_line)))
	_left_box.add_child(body)

	var notes: Array = page.get("footnotes", [])
	if not notes.is_empty():
		_left_box.add_child(_rule(RULE))
		for i in notes.size():
			_left_box.add_child(_wrapped("%s %s" % [_superscript(i + 1), notes[i]], "EBGaramond-Regular.ttf",
				12 if _compact else 13, NOTE, HORIZONTAL_ALIGNMENT_LEFT))
	if epilogue and not _turning_points.is_empty():
		_left_box.add_child(_turning_points_section())
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left_box.add_child(spacer)
	_left_box.add_child(_navigation())


func _build_right(page: Dictionary, epilogue: bool) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(_text(str(_folio() + 1), "EBGaramond-Regular.ttf", 13 if _compact else 14, DIM, HORIZONTAL_ALIGNMENT_LEFT))
	head.add_child(_text(String(page.get("title", "")).to_upper(), "Cinzel-SemiBold.ttf", 9 if _compact else 10, DIM,
		HORIZONTAL_ALIGNMENT_RIGHT, 2, true))
	head.visible = not _compact
	_right_box.add_child(head)
	if not _compact:
		_right_box.add_child(_rule(RULE))

	var figure := VBoxContainer.new()
	figure.add_theme_constant_override("separation", 6)
	figure.add_child(_figure_chart(page, epilogue))
	figure.add_child(_caption(page, epilogue))
	_right_box.add_child(figure)
	var stats: Array = page.get("stats", [])
	if not stats.is_empty():
		var parts: Array[String] = []
		for item in stats:
			var stat: Dictionary = item
			parts.append("%s %d → %d" % [stat.get("label", ""), int(round(float(stat.get("from", 0.0)))),
				int(round(float(stat.get("to", 0.0))))])
		var line := _wrapped("The era in figures: " + " · ".join(parts) + ".", "EBGaramond-Italic.ttf", 13 if _compact else 14,
			CAPTION, HORIZONTAL_ALIGNMENT_LEFT)
		_right_box.add_child(line)
	_right_box.add_child(_verdict_box())
	if epilogue:
		_right_box.add_child(_epilogue_actions())
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_box.add_child(spacer)
	if not _compact:
		_right_box.add_child(_text("Fig. %d is drawn from the campaign's telemetry, one point per half-year." % _figure_number(epilogue),
			"EBGaramond-Italic.ttf", 12, DIM, HORIZONTAL_ALIGNMENT_RIGHT))


func _figure_chart(page: Dictionary, epilogue: bool) -> InkChart:
	var history: Array = _result.get("history", [])
	var chart := InkChart.new()
	chart.custom_minimum_size = Vector2(0, 130 if _compact else 220)
	chart.ink = INK
	chart.rule_color = GRID
	chart.mark_color = OXBLOOD
	chart.label_font = EraStyle.font("Cinzel-SemiBold.ttf")
	chart.label_size = 9
	chart.mark_font = EraStyle.font("EBGaramond-Italic.ttf")
	chart.mark_size = 11
	chart.top_pad = 14.0
	var from_turn := 0
	var to_turn := int(_result.get("turn", SimConstants.TOTAL_TURNS))
	if not history.is_empty():
		to_turn = int((history[-1] as Dictionary).get("turn", to_turn))
	var figure: Dictionary = page.get("figure", {})
	if not epilogue and not figure.is_empty():
		from_turn = int(figure.get("from_turn", 0))
		to_turn = int(figure.get("to_turn", to_turn))
	else:
		chart.dividers = [{"x": 0.0, "label": "I"}, {"x": float(EraChronicle.era_turns(2).x) - 0.5, "label": "II"},
			{"x": float(EraChronicle.era_turns(3).x) - 0.5, "label": "III"}].filter(
				func(d: Dictionary) -> bool: return float(d["x"]) <= float(to_turn))
	chart.set_range(float(from_turn), float(maxi(to_turn, from_turn + 1)))
	var trust := InkChart.history_points(history, WorldState.EPISTEMIC_TRUST, from_turn, to_turn)
	var drift := InkChart.history_points(history, WorldState.ALIGNMENT_DRIFT, from_turn, to_turn)
	chart.set_series([
		{"points": trust, "color": INK, "width": 1.4, "dash": Vector2.ZERO},
		{"points": drift, "color": OXBLOOD, "width": 1.2, "dash": Vector2(4.0, 2.0)},
	])
	var mark_turn := int(figure.get("mark_turn", -1)) if not epilogue else _campaign_mark_turn()
	if mark_turn >= from_turn and mark_turn <= to_turn:
		for point in drift:
			if int((point as Vector2).x) == mark_turn:
				chart.marks = [{"x": float(mark_turn), "y": (point as Vector2).y,
					"label": str(int(floor(SimConstants.year_for_turn(mark_turn))))}]
	return chart


## The turn of the campaign's largest drift jump (the epilogue figure's mark).
func _campaign_mark_turn() -> int:
	for chapter in _chapters:
		if not (chapter as Dictionary).get("footnotes", []).is_empty():
			return int(chapter["figure"].get("mark_turn", -1))
	return -1


func _caption(page: Dictionary, epilogue: bool) -> RichTextLabel:
	var caption := _rich(13 if _compact else 14, CAPTION, "EBGaramond-Italic.ttf")
	caption.push_font(EraStyle.font("Cinzel-SemiBold.ttf", 1), 10)
	caption.push_color(OXBLOOD)
	caption.add_text("FIG. %d  " % _figure_number(epilogue))
	caption.pop()
	caption.pop()
	var years := String(page.get("years", ""))
	if epilogue:
		var last := int(floor(float(_result.get("year", 2076.0))))
		caption.add_text("Public trust (solid) and alignment drift (dashed), 2026–%d, across the hardware eras." % last)
	else:
		caption.add_text("Public trust (solid) and alignment drift (dashed), %s." % years)
	return caption


func _figure_number(epilogue: bool) -> int:
	return _chapters.size() + 1 if epilogue else _page_index + 1


func _verdict_box() -> PanelContainer:
	var outcome: Dictionary = _result.get("outcome", {})
	var verdict: Dictionary = _result.get("verdict", {})
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(PAPER.darkened(0.015), 1.0)
	style.border_color = BOX_RULE
	style.set_border_width_all(1)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	box.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.add_child(_wrapped("HOW IT ENDED · %s" % String(verdict.get("verdict", "DEFEAT")), "Cinzel-SemiBold.ttf",
		10, OXBLOOD, HORIZONTAL_ALIGNMENT_CENTER, 3))
	column.add_child(_wrapped(String(outcome.get("name", "")), "EBGaramond-Italic.ttf", 21 if _compact else 24, INK,
		HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_wrapped(String(outcome.get("description", outcome.get("subtitle", ""))), "EBGaramond-Regular.ttf",
		13 if _compact else 14, CAPTION, HORIZONTAL_ALIGNMENT_CENTER))
	var role := String(_result.get("player_role", ""))
	column.add_child(_wrapped("End-state %d of 8 · directive score %d of 100 for %s" % [int(outcome.get("number", 0)),
		int(round(float(verdict.get("score", 0.0)))), StoryCopy.actor_the(role)], "EBGaramond-Italic.ttf", 12 if _compact else 13,
		DIM, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(column)
	return box


## "Turning points": the moments the campaign turned on, oldest first, each
## with a "What if?" button.
func _turning_points_section() -> Control:
	var section := VBoxContainer.new()
	section.name = "TurningPoints"
	section.add_theme_constant_override("separation", 8)
	section.add_child(_rule(RULE))
	section.add_child(_text("TURNING POINTS", "Cinzel-SemiBold.ttf", 11 if _compact else 12, OXBLOOD, HORIZONTAL_ALIGNMENT_CENTER, 3))
	var intro := "Go back to any of these moments and choose again." if allow_rewind else "The moments the century turned on."
	section.add_child(_wrapped(intro, "EBGaramond-Italic.ttf", 13 if _compact else 14, DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var several := (_result.get("humans", []) as Array).size() > 1
	for i in _turning_points.size():
		var point: Dictionary = _turning_points[i]
		if i > 0:
			section.add_child(_rule(GUTTER))
		var row := HBoxContainer.new()
		row.name = "Point%d" % i
		row.add_theme_constant_override("separation", 10)
		var text_box := VBoxContainer.new()
		text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_box.add_theme_constant_override("separation", 1)
		var kind := String(point.get("kind", ""))
		var kicker := "%d · %s" % [int(floor(float(point.get("year", 2026.0)))), KIND_LABELS.get(kind, "TURNING POINT")]
		if several and kind in [TurningPoints.CHOICE, TurningPoints.FALLOUT]:
			kicker += " · " + UiFormat.role_name(String(point.get("faction", ""))).to_upper()
		text_box.add_child(_wrapped(kicker, "Cinzel-SemiBold.ttf", 9 if _compact else 10, OXBLOOD if kind == TurningPoints.COLLAPSE else DIM,
			HORIZONTAL_ALIGNMENT_LEFT, 2))
		text_box.add_child(_wrapped(point_title(point), "EBGaramond-Italic.ttf", 16 if _compact else 18, INK,
			HORIZONTAL_ALIGNMENT_LEFT))
		text_box.add_child(_wrapped(String(point.get("summary", "")), "EBGaramond-Regular.ttf", 13 if _compact else 14, CAPTION,
			HORIZONTAL_ALIGNMENT_LEFT))
		row.add_child(text_box)
		if allow_rewind:
			var rewind_turn := int(point.get("rewind_turn", point.get("turn", 1)))
			var button := _book_button("What if?", "WhatIf%d" % i)
			button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			button.tooltip_text = "Go back to %s and choose differently" % UiFormat.year_label(SimConstants.year_for_turn(rewind_turn))
			button.pressed.connect(_on_what_if.bind(rewind_turn))
			row.add_child(button)
		section.add_child(row)
	return section


func _on_what_if(turn: int) -> void:
	rewind_requested.emit(turn)


## A turning point's title as the book prints it: crises in sentence case with
## their proper nouns ("Rolling brownouts across the Nordic Arctic corridor").
static func point_title(point: Dictionary) -> String:
	var title := String(point.get("title", ""))
	var card := String(point.get("card", ""))
	if card != "" and String(point.get("kind", "")) in [TurningPoints.CHOICE, TurningPoints.FALLOUT]:
		return StoryCopy.sentence_case_title(card, title)
	return title


## Share (the ending as a front page) and Endings (the collection).
func _epilogue_actions() -> Control:
	var row := HBoxContainer.new()
	row.name = "EpilogueActions"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var share := _book_button("Share", "ShareButton", "share")
	share.tooltip_text = "Save the ending as a front page of The Ledger"
	share.pressed.connect(func(): share_requested.emit())
	row.add_child(share)
	var endings := _book_button("Endings", "EndingsButton", "book")
	endings.tooltip_text = "Every ending you have reached"
	endings.pressed.connect(func(): endings_requested.emit())
	row.add_child(endings)
	for button in [share, endings]:
		(button as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL if _compact else Control.SIZE_SHRINK_CENTER
		(button as Button).custom_minimum_size = Vector2(0.0 if _compact else 150.0, 44.0)
	return row


## A ruled button in the book's ink: Cinzel capitals, oxblood border.
func _book_button(text: String, node_name: String, glyph: String = "") -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 44 if _compact else 36)
	button.add_theme_font_override("font", EraStyle.font("Cinzel-SemiBold.ttf", 1))
	button.add_theme_font_size_override("font_size", 12)
	for state in ["font_color", "font_focus_color", "font_hover_color", "font_disabled_color"]:
		button.add_theme_color_override(state, OXBLOOD)
	for state in ["font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, PAPER)
	if glyph != "":
		button.icon = Glyphs.texture(glyph, 16)
		for state in ["icon_normal_color", "icon_focus_color", "icon_hover_color", "icon_disabled_color"]:
			button.add_theme_color_override(state, OXBLOOD)
		for state in ["icon_pressed_color", "icon_hover_pressed_color"]:
			button.add_theme_color_override(state, PAPER)
	var styles := {"normal": Color(OXBLOOD, 0.0), "hover": Color(OXBLOOD, 0.08), "pressed": OXBLOOD, "hover_pressed": OXBLOOD,
		"disabled": Color(OXBLOOD, 0.0)}
	for state in styles:
		var box := StyleBoxFlat.new()
		box.bg_color = styles[state]
		box.border_color = OXBLOOD
		box.set_border_width_all(1)
		box.set_corner_radius_all(2)
		box.content_margin_left = 12
		box.content_margin_right = 12
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		button.add_theme_stylebox_override(state, box)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button


## I · II · III · Epilogue.
func _tabs() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 2)
	for i in _chapters.size() + 1:
		var tab_name := "EPILOGUE" if i >= _chapters.size() else String((_chapters[i] as Dictionary).get("number", ""))
		var tab := _nav_button(tab_name, i == _page_index)
		tab.custom_minimum_size = Vector2(44, 44 if _compact else 32)
		tab.pressed.connect(_show_page.bind(i))
		row.add_child(tab)
	return row


## ‹ previous · Appendix: the full record · next ›
func _navigation() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var previous := _page_index - 1
	var next := _page_index + 1
	var back := _nav_button("‹ " + _page_name(previous) if previous >= 0 else "", false)
	back.disabled = previous < 0
	back.pressed.connect(_show_page.bind(maxi(previous, 0)))
	row.add_child(back)
	var appendix := _nav_button("Appendix" if _compact else "Appendix: the full record", false, true)
	appendix.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	appendix.pressed.connect(_scroll_to_appendix)
	row.add_child(appendix)
	var forward := _nav_button(_page_name(next) + " ›" if next <= _chapters.size() else "", false)
	forward.disabled = next > _chapters.size()
	forward.pressed.connect(_show_page.bind(mini(next, _chapters.size())))
	row.add_child(forward)
	if _compact:
		# Phones share the row three ways; long names trim instead of pushing wider.
		for button in [back, appendix, forward]:
			(button as Button).clip_text = true
			(button as Button).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			(button as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row


func _page_name(index: int) -> String:
	if index >= _chapters.size():
		return "EPILOGUE"
	if index < 0:
		return ""
	return "CHAPTER %s" % (_chapters[index] as Dictionary).get("number", "")


func _scroll_to_appendix() -> void:
	var scroll: ScrollContainer = get_node_or_null("OverlayScroll")
	if scroll != null:
		scroll.ensure_control_visible(_appendix)


func _nav_button(text: String, current: bool, italic: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 44)
	var font := EraStyle.font("EBGaramond-Italic.ttf") if italic else EraStyle.font("Cinzel-SemiBold.ttf", 2)
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", (14 if _compact else 15) if italic else 11)
	var color := OXBLOOD if italic or current else INK
	for state in ["font_color", "font_focus_color"]:
		button.add_theme_color_override(state, color)
	for state in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, OXBLOOD)
	button.add_theme_color_override("font_disabled_color", Color(DIM, 0.0))
	var clear := StyleBoxEmpty.new()
	clear.content_margin_left = 6
	clear.content_margin_right = 6
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, clear)
	if current:
		var underline := StyleBoxFlat.new()
		underline.bg_color = Color(0, 0, 0, 0)
		underline.border_color = OXBLOOD
		underline.border_width_bottom = 1
		underline.content_margin_left = 6
		underline.content_margin_right = 6
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			button.add_theme_stylebox_override(state, underline)
	return button


func _folio() -> int:
	var start := 0
	if _page_index < _chapters.size():
		start = int((_chapters[_page_index] as Dictionary).get("era_start_turn", 0))
	else:
		start = int(_result.get("turn", 100))
	return 12 + start * 4 - (start * 4) % 2


# --- Book typography ---------------------------------------------------------------

func _paper() -> PanelContainer:
	var page := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = PAPER
	box.border_color = GUTTER
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 18
	page.add_theme_stylebox_override("panel", box)
	return page


func _paragraph(text: String, drop_cap: bool, justify: bool = true) -> RichTextLabel:
	var label := _rich(15 if _compact else 16, INK, "EBGaramond-Regular.ttf")
	label.add_theme_constant_override("line_separation", 2)
	label.push_paragraph(HORIZONTAL_ALIGNMENT_FILL if justify else HORIZONTAL_ALIGNMENT_LEFT, Control.TEXT_DIRECTION_AUTO, "",
		TextServer.STRUCTURED_TEXT_DEFAULT, JUSTIFY)
	var body := text.strip_edges()
	if drop_cap and body.length() > 1:
		# A negative bottom margin keeps the cap two lines deep.
		label.push_dropcap(body.left(1), EraStyle.font("Cinzel-SemiBold.ttf"), 44 if _compact else 50,
			Rect2(0, 0, 6 if _compact else 7, -28 if _compact else -34), OXBLOOD)
		body = body.substr(1)
	elif not drop_cap:
		# A first-line indent: the zero-width space keeps the em space from
		# being trimmed as an edge space.
		body = "​ " + body
	label.add_text(body + " ")
	label.pop()
	return label


func _rich(font_size: int, color: Color, font_file: String) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.add_theme_font_override("normal_font", EraStyle.font(font_file))
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_color_override("default_color", color)
	return label


func _text(value: String, font_file: String, font_size: int, color: Color, align: HorizontalAlignment,
		spacing: int = 0, expand: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = align
	label.add_theme_font_override("font", EraStyle.font(font_file, spacing))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


func _wrapped(value: String, font_file: String, font_size: int, color: Color, align: HorizontalAlignment,
		spacing: int = 0) -> Label:
	var label := _text(value, font_file, font_size, color, align, spacing)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _rule(color: Color) -> ColorRect:
	var rule := ColorRect.new()
	rule.color = color
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


## The line-diamond-line ornament under a chapter heading.
func _ornament() -> Control:
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"128\" height=\"24\" viewBox=\"0 0 64 12\"><path d=\"M2 6h22M40 6h22M32 1.5l4.5 4.5L32 10.5 27.5 6z\" fill=\"none\" stroke=\"#%s\" stroke-width=\"1\"/></svg>" % OXBLOOD.to_html(false)
	var texture := Glyphs.svg_texture(svg)
	if texture is ImageTexture:
		(texture as ImageTexture).set_size_override(Vector2i(64, 12))
	var rect := TextureRect.new()
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	rect.custom_minimum_size = Vector2(64, 16)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func _superscript(number: int) -> String:
	return {1: "¹", 2: "²", 3: "³"}.get(number, str(number))


static func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


# --- Appendix: the full record ---------------------------------------------------------

func _build_appendix() -> void:
	_appendix = PanelContainer.new()
	_appendix.name = "Appendix"
	_appendix.theme_type_variation = "OverlayPanel"
	_book.add_child(_appendix)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_appendix.add_child(box)
	_appendix_title = Label.new()
	_appendix_title.text = "Appendix: the full record"
	_appendix_title.theme_type_variation = "HeaderTitle"
	_appendix_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_appendix_title.add_theme_font_override("font", EraStyle.font("EBGaramond-Italic.ttf"))
	_appendix_title.add_theme_font_size_override("font_size", 26)
	box.add_child(_appendix_title)
	_appendix_caption = Label.new()
	_appendix_caption.theme_type_variation = "DimLabel"
	_appendix_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_appendix_caption)
	_columns = BoxContainer.new()
	_columns.add_theme_constant_override("separation", 18)
	box.add_child(_columns)
	_chart = TrajectoryChart.new()
	_chart.custom_minimum_size = Vector2(760, 320)
	_columns.add_child(_chart)
	_right_column = VBoxContainer.new()
	_right_column.add_theme_constant_override("separation", 6)
	_columns.add_child(_right_column)
	_affinity_title = Label.new()
	_affinity_title.theme_type_variation = "PanelTitle"
	_right_column.add_child(_affinity_title)
	_affinity_box = VBoxContainer.new()
	_affinity_box.add_theme_constant_override("separation", 4)
	_right_column.add_child(_affinity_box)
	_stats_title = Label.new()
	_stats_title.theme_type_variation = "PanelTitle"
	_right_column.add_child(_stats_title)
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 4
	_stats_grid.add_theme_constant_override("h_separation", 12)
	_stats_grid.add_theme_constant_override("v_separation", 4)
	_right_column.add_child(_stats_grid)
	_buttons = BoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	_buttons.add_theme_constant_override("separation", 10)
	var inspect := Button.new()
	inspect.text = "Inspect final state"
	inspect.theme_type_variation = "GhostButton"
	inspect.pressed.connect(func():
		visible = false
		closed.emit())
	_buttons.add_child(inspect)
	var restart := Button.new()
	restart.text = "New campaign"
	restart.theme_type_variation = "AccentButton"
	restart.pressed.connect(func(): new_campaign_requested.emit())
	_buttons.add_child(restart)
	box.add_child(_buttons)


## Era-dependent text and colors of the appendix.
func _restyle_appendix() -> void:
	var s := EraTheme.style_of(self)
	_affinity_title.text = s.label("End-state affinity")
	_stats_title.text = s.label("Final record")
	var outcome: Dictionary = _result.get("outcome", {})
	var reason := String(_result.get("reason", ""))
	var detail := String(REASONS.get(reason, reason.capitalize()))
	if reason == "PLAYER_LOSS":
		detail += ": " + String((_result.get("player_loss", {}) as Dictionary).get("reason", ""))
	elif reason == "CATASTROPHE":
		detail += ": " + String((_result.get("catastrophe", {}) as Dictionary).get("reason", ""))
	_appendix_caption.text = "End-state %d of 8 · %s · turn %d · %d · %s%s" % [int(outcome.get("number", 0)),
		outcome.get("name", ""), int(_result.get("turn", 0)), int(floor(float(_result.get("year", 2026.0)))), detail,
		"" if bool(outcome.get("strict_match", true)) else " · nearest attractor"]
	for row in _affinity_box.get_children():
		_style_affinity_row(row)


func _build_affinities(outcome: Dictionary) -> void:
	_clear(_affinity_box)
	var affinities: Dictionary = outcome.get("affinities", {})
	for candidate in VictoryMatrix.OUTCOMES:
		var outcome_id := String(candidate["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.set_meta("chosen", outcome_id == String(outcome.get("id", "")))
		var name_label := Label.new()
		name_label.name = "Name"
		name_label.text = "%d. %s" % [int(candidate["number"]), candidate["name"]]
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(name_label)
		var bar := ProgressBar.new()
		bar.name = "Bar"
		bar.show_percentage = false
		bar.max_value = 100.0
		bar.value = float(affinities.get(outcome_id, 0.0))
		bar.custom_minimum_size = Vector2(80, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var value := Label.new()
		value.name = "Value"
		value.text = "%d%%" % int(round(float(affinities.get(outcome_id, 0.0))))
		value.custom_minimum_size = Vector2(38, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 12)
		row.add_child(value)
		_affinity_box.add_child(row)
		_style_affinity_row(row)
	UiLayout.pass_touch_through(_affinity_box)


## Fixed-width names on desktop; on phones the name takes what the bar leaves.
## The chosen end-state is drawn in the accent color, the others dimmed.
func _style_affinity_row(row: Node) -> void:
	var s := EraTheme.style_of(self)
	var chosen := bool(row.get_meta("chosen", false))
	var name_label: Label = row.get_node("Name")
	name_label.custom_minimum_size = Vector2(0.0 if _compact else 230.0, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _compact else Control.SIZE_FILL
	name_label.clip_text = _compact
	name_label.add_theme_color_override("font_color", s.text_bright if chosen else s.text_dim)
	name_label.add_theme_font_override("font", s.font_ui_bold if chosen else s.font_ui)
	var value: Label = row.get_node("Value")
	value.add_theme_font_override("font", s.font_mono)
	value.add_theme_color_override("font_color", s.accent if chosen else s.text_dim)
	var bar: ProgressBar = row.get_node("Bar")
	var fill := EraTheme.box(s.accent if chosen else Color(s.text_dim, 0.45), Color(0, 0, 0, 0), 0, 3)
	bar.add_theme_stylebox_override("fill", fill)


func _build_stats(result: Dictionary) -> void:
	_clear(_stats_grid)
	var values: Dictionary = result.get("final_values", {})
	var tech: Dictionary = result.get("tech", {})
	var rows: Array = []
	for key in WorldState.METRIC_KEYS:
		rows.append([UiFormat.metric_name(key), "%.1f" % float(values.get(key, 0.0))])
	rows.append(["Enforcement", "%.1f" % float(values.get("enforcement_level", 0.0))])
	rows.append(["Citizen resilience", "%.1f" % float(values.get("citizen_resilience", 0.0))])
	rows.append(["Training FLOPs", "10^%.1f" % float(tech.get("log_flops", 26.0))])
	var milestones: Dictionary = result.get("milestones", {})
	rows.append(["AGI milestone", str(int(SimConstants.year_for_turn(int(milestones["agi_turn"])))) if milestones.has("agi_turn") else "—"])
	rows.append(["Paradigm shifts", "%d of 4" % (tech.get("unlocked_shifts", []) as Array).size()])
	rows.append(["Emergences", str((tech.get("emerged_capabilities", []) as Array).size())])
	rows.append(["Alignment taxes", str(int(tech.get("alignment_tax_events", 0)))])
	for row in rows:
		var label := Label.new()
		label.text = String(row[0])
		label.theme_type_variation = "DimLabel"
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		_stats_grid.add_child(label)
		var value := Label.new()
		value.text = String(row[1])
		value.theme_type_variation = "ValueLabel"
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_stats_grid.add_child(value)
