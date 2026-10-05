class_name FrontPage
extends Control
## "The Ledger" special edition, printed when a hardware era closes: a
## blackletter masthead, the era's headline and deck in the news serif, the
## story in two justified columns with a drop cap, the era "in three lines"
## (trust, compute, drift) and "Also in this edition". "Turn the page ▸"
## dismisses it.
##
##   front_page.present(EraChronicle.summarize_era(engine.event_log,
##       engine.world.history, closing_era, engine.player_role))
##
## Desktop: a broadsheet about 900 px wide. Compact: one scrolling column that
## fits a 412 px phone. The paper keeps its own typography in every era; only
## the shade and the page's glow follow the era theme.

signal dismissed

const DESKTOP_WIDTH := 900.0
const PAPER := Color("#F2EFE8")
const INK := Color("#161411")
const INK_SOFT := Color("#3B3630")
const RED := Color("#9E1B1B")
const RULE_LIGHT := Color("#CFC8BA")
const RULE_ITEM := Color("#D8D1C3")
const PRICES := {1: "ONE CREDIT", 2: "TWO CREDITS", 3: "NO CHARGE"}
## Extra weight for the drop-cap column when balancing the body.
const DROP_CAP_CHARS := 60
## Justified columns: no stretched last lines, no spaces at line edges.
const JUSTIFY := TextServer.JUSTIFICATION_WORD_BOUND | TextServer.JUSTIFICATION_KASHIDA \
	| TextServer.JUSTIFICATION_TRIM_EDGE_SPACES | TextServer.JUSTIFICATION_SKIP_LAST_LINE \
	| TextServer.JUSTIFICATION_SKIP_LAST_LINE_WITH_VISIBLE_CHARS

var summary := {}
var _compact := false
var _built_width := 0.0
var _frame: MarginContainer
var _page: PanelContainer
var _page_style: StyleBoxFlat
var _content: VBoxContainer
var _turn_button: Button


func _ready() -> void:
	# Fill the parent however we were created (scene or code).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame = UiLayout.build_overlay(self, Color(0.02, 0.02, 0.03, 0.78))
	_page = PanelContainer.new()
	_page.name = "Page"
	# The Ledger is printed in English (EraChronicle); only its button is interface.
	_page.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_page_style = StyleBoxFlat.new()
	_page_style.bg_color = PAPER
	_page_style.set_corner_radius_all(2)
	_page_style.shadow_color = Color(0, 0, 0, 0.55)
	_page_style.shadow_size = 28
	_page.add_theme_stylebox_override("panel", _page_style)
	_frame.add_child(_page)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	_page.add_child(_content)
	resized.connect(_apply_layout)
	visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _page_style != null:
		_apply_era_glow()
	elif what == NOTIFICATION_TRANSLATION_CHANGED and _turn_button != null and is_instance_valid(_turn_button):
		_turn_button.text = tr("Turn the page ▸")


func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	if not summary.is_empty():
		_build()
	_apply_layout()


## Prints the edition for [param era_summary] (see EraChronicle.summarize_era).
func present(era_summary: Dictionary) -> void:
	if not is_node_ready():
		ready.connect(present.bind(era_summary), CONNECT_ONE_SHOT)
		return
	summary = era_summary
	_build()
	_apply_layout()
	var scroll: ScrollContainer = get_node_or_null("OverlayScroll")
	if scroll != null:
		scroll.scroll_vertical = 0
	visible = true


func close() -> void:
	visible = false


func _turn_page() -> void:
	visible = false
	dismissed.emit()


func _apply_layout() -> void:
	if _page == null:
		return
	var width := UiLayout.panel_width(size.x, DESKTOP_WIDTH, _compact)
	# Balanced headlines are measured for one width: set them again for another.
	if not summary.is_empty() and absf(width - _built_width) > 1.0:
		_build()
	_page.custom_minimum_size = Vector2(width, 0)
	var margin_h := 16.0 if _compact else 36.0
	var margin_v := 14.0 if _compact else 28.0
	_page_style.content_margin_left = margin_h
	_page_style.content_margin_right = margin_h
	_page_style.content_margin_top = margin_v
	_page_style.content_margin_bottom = margin_v + 2.0
	UiLayout.set_overlay_margin(_frame, _compact)
	_apply_era_glow()


## The page glows faintly in the era's accent where the era glows.
func _apply_era_glow() -> void:
	var s := EraTheme.style_of(self)
	_page_style.shadow_color = Color(s.accent, 0.22) if s.glow > 0.0 else Color(0, 0, 0, 0.55)


# --- Building the page --------------------------------------------------------------

func _build() -> void:
	_built_width = UiLayout.panel_width(size.x, DESKTOP_WIDTH, _compact)
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	var era := int(summary.get("era", 1))
	var edition: Dictionary = summary.get("edition", {})
	var small := 10 if _compact else 11

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.add_child(_label("VOL. %s · NO. %d" % [edition.get("volume", "I"), int(edition.get("number", 1))],
		"Newsreader-Medium.ttf", small, INK, HORIZONTAL_ALIGNMENT_LEFT, 1, true))
	top.add_child(_label("SPECIAL EDITION", "Newsreader-SemiBold.ttf", small, RED, HORIZONTAL_ALIGNMENT_CENTER, 1))
	top.add_child(_label("%d · %s" % [int(edition.get("year", 2036)), PRICES.get(era, "ONE CREDIT")],
		"Newsreader-Medium.ttf", small, INK, HORIZONTAL_ALIGNMENT_RIGHT, 1, true))
	_content.add_child(top)
	_content.add_child(_rule(1.0, INK))
	var masthead := _label("The Ledger", "UnifrakturCook-Bold.ttf", 48 if _compact else 68, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_content.add_child(masthead)
	_content.add_child(_double_rule())

	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var kicker := "ERA %s · %s · %s" % [StoryCopy.ROMAN.get(era, str(era)), String(summary.get("era_name", "")).to_upper(),
		summary.get("years", "")]
	head.add_child(_wrapped(kicker, "Newsreader-SemiBold.ttf", 11 if _compact else 12, RED, HORIZONTAL_ALIGNMENT_CENTER, 2))
	var width := _content_width()
	var title := _wrapped(String(summary.get("title", "")), "Newsreader-SemiBold.ttf", 38 if _compact else 56, INK,
		HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_constant_override("line_spacing", -4)
	head.add_child(_balanced(title, width))
	var deck := _wrapped(String(summary.get("deck", "")), "Newsreader-MediumItalic.ttf", 15 if _compact else 19, INK_SOFT,
		HORIZONTAL_ALIGNMENT_CENTER)
	head.add_child(_balanced(deck, minf(width, 760.0)))
	_content.add_child(head)
	_content.add_child(_rule(1.0, INK))
	_content.add_child(_body())
	_content.add_child(_rule(1.0, INK))
	_content.add_child(_bottom())
	_content.add_child(_rule(2.0, INK))
	_content.add_child(_footer())
	UiLayout.pass_touch_through(_page)


## Width inside the page margins.
func _content_width() -> float:
	var page := UiLayout.panel_width(size.x, DESKTOP_WIDTH, _compact)
	return maxf(200.0, page - (32.0 if _compact else 72.0))


## Wraps [param label] at an even width so its last line is not a lone word
## (CSS text-wrap: balance), centered within [param max_width].
static func _balanced(label: Label, max_width: float) -> Control:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var full := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var lines := _line_count(font, label.text, font_size, max_width)
	# The narrowest width that still needs no more lines than the full width.
	var low := full / float(lines)
	var high := max_width
	while lines > 1 and high - low > 2.0:
		var middle := (low + high) * 0.5
		if _line_count(font, label.text, font_size, middle) <= lines:
			high = middle
		else:
			low = middle
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.custom_minimum_size = Vector2(minf(max_width, (high if lines > 1 else full) + 4.0), 0)
	var holder := CenterContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(label)
	return holder


## Lines [param text] takes at [param width], broken the way Label breaks it.
static func _line_count(font: Font, text: String, font_size: int, width: float) -> int:
	var paragraph := TextParagraph.new()
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE \
		| TextServer.BREAK_TRIM_EDGE_SPACES
	paragraph.add_string(text, font, font_size)
	paragraph.width = width
	return maxi(1, paragraph.get_line_count())


## The story: one justified column on phones, two balanced columns on desktop.
func _body() -> Control:
	var columns := 1 if _compact else 2
	var chars_per_line := _content_width() / (0.47 * 13.0) if _compact else (_content_width() - 28.0) * 0.5 / (0.47 * 15.0)
	var paragraphs := merge_short_lead(summary.get("paragraphs", []), chars_per_line)
	var split := _split_columns(paragraphs, columns, chars_per_line)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	for i in split.size():
		if i > 0:
			var gap := HBoxContainer.new()
			gap.add_theme_constant_override("separation", 0)
			gap.custom_minimum_size = Vector2(28, 0)
			var rule := ColorRect.new()
			rule.color = RULE_LIGHT
			rule.custom_minimum_size = Vector2(1, 0)
			rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			rule.size_flags_vertical = Control.SIZE_FILL
			gap.alignment = BoxContainer.ALIGNMENT_CENTER
			gap.add_child(rule)
			row.add_child(gap)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 6)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_stretch_ratio = 1.0
		var chunks: Array = split[i]
		for j in chunks.size():
			var lead := i == 0 and j == 0
			column.add_child(_paragraph(String(chunks[j]), lead, not lead or wraps_drop_cap(String(chunks[j]), chars_per_line)))
		row.add_child(column)
	return row


## True when [param text] runs past a two-line drop cap; shorter leads are set
## ragged, since justification would stretch their last line beside the cap.
static func wraps_drop_cap(text: String, chars_per_line: float) -> bool:
	return float(text.length()) >= chars_per_line * 2.6


func _paragraph(text: String, drop_cap: bool, justify: bool = true) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	var body_font := EraStyle.font("Newsreader-Medium.ttf")
	var font_size := 13 if _compact else 15
	label.add_theme_font_override("normal_font", body_font)
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_color_override("default_color", INK)
	label.add_theme_constant_override("line_separation", 1)
	label.push_paragraph(HORIZONTAL_ALIGNMENT_FILL if justify else HORIZONTAL_ALIGNMENT_LEFT, Control.TEXT_DIRECTION_AUTO, "",
		TextServer.STRUCTURED_TEXT_DEFAULT, JUSTIFY)
	var body := text.strip_edges()
	if drop_cap and body.length() > 1:
		# A negative bottom margin keeps the cap two lines deep.
		label.push_dropcap(body.left(1), EraStyle.font("Newsreader-SemiBold.ttf"), 40 if _compact else 46,
			Rect2(0, 1, 5 if _compact else 6, -20 if _compact else -22), RED)
		body = body.substr(1)
	# The trailing space stops Godot (seen in 4.3) from wrapping a
	# drop-capped paragraph's last character onto a line of its own.
	label.add_text(body + " ")
	label.pop()
	return label


## A drop cap is two lines deep: a lead paragraph that would end beside it
## gets stretched by justification, so a short lead runs on into the next.
static func merge_short_lead(paragraphs: Array, chars_per_line: float) -> Array:
	var out: Array = paragraphs.duplicate()
	if out.size() >= 2 and not wraps_drop_cap(String(out[0]), chars_per_line):
		out[0] = String(out[0]) + " " + String(out[1])
		out.remove_at(1)
	return out


## Splits paragraphs into two columns of about equal height (estimated in
## lines of [param chars_per_line]), breaking between sentences; the first
## column may run a line longer, as newspapers do.
static func _split_columns(paragraphs: Array, columns: int, chars_per_line: float = 56.0) -> Array:
	if columns <= 1:
		return [paragraphs.duplicate()]
	var sentences: Array = []
	for p in range(paragraphs.size()):
		for sentence in _sentences(String(paragraphs[p])):
			sentences.append({"text": sentence, "paragraph": p})
	var best := 0
	var best_score := INF
	for split in sentences.size() + 1:
		var left := _chunks(sentences, 0, split)
		var right := _chunks(sentences, split, sentences.size())
		var difference := _lines(left, chars_per_line, true) - _lines(right, chars_per_line, false)
		var score := absf(difference) + (0.0 if difference >= 0.0 else 0.5)
		if score < best_score:
			best_score = score
			best = split
	return [_chunks(sentences, 0, best), _chunks(sentences, best, sentences.size())]


## Sentences [start, stop) regrouped into paragraph chunks.
static func _chunks(sentences: Array, start: int, stop: int) -> Array:
	var out: Array = []
	var chunk := ""
	var current := -1
	for i in range(start, stop):
		var item: Dictionary = sentences[i]
		if int(item["paragraph"]) != current and chunk != "":
			out.append(chunk)
			chunk = ""
		current = int(item["paragraph"])
		chunk = (chunk + " " + String(item["text"])).strip_edges()
	if chunk != "":
		out.append(chunk)
	return out


## Estimated height of paragraph chunks in lines (gaps count a third of a line).
static func _lines(chunks: Array, chars_per_line: float, drop_cap: bool) -> float:
	var total := 0.0
	for i in chunks.size():
		var length := float(String(chunks[i]).length()) + (float(DROP_CAP_CHARS) * 0.2 if drop_cap and i == 0 else 0.0)
		total += ceilf(length / maxf(10.0, chars_per_line)) + (0.33 if i > 0 else 0.0)
	return total


static func _sentences(text: String) -> Array:
	var out: Array = []
	var start := 0
	for i in range(1, text.length() - 1):
		if text[i] == " " and ".!?¹".contains(text[i - 1]) and text[i + 1] == text[i + 1].to_upper() \
				and text[i + 1] != text[i + 1].to_lower():
			out.append(text.substr(start, i - start))
			start = i + 1
	out.append(text.substr(start))
	return out


## "The decade in three lines" and "Also in this edition".
func _bottom() -> Control:
	var row := BoxContainer.new()
	row.add_theme_constant_override("separation", 14 if _compact else 28)
	var chart_box := VBoxContainer.new()
	chart_box.add_theme_constant_override("separation", 4)
	chart_box.custom_minimum_size = Vector2(164 if _compact else 330, 0)
	var period := String(summary.get("period", "era")).to_upper()
	chart_box.add_child(_wrapped("THE %s IN THREE LINES" % period, "Newsreader-SemiBold.ttf", 9 if _compact else 11, INK,
		HORIZONTAL_ALIGNMENT_LEFT, 1))
	var chart := InkChart.new()
	chart.custom_minimum_size = Vector2(0, 78 if _compact else 120)
	chart.ink = INK
	chart.set_range(float(maxi(0, int(summary.get("era_start_turn", 0)) - 1)), float(summary.get("era_end_turn", 20)))
	var lines: Array = summary.get("lines", [])
	var styles := {
		WorldState.EPISTEMIC_TRUST: {"color": INK, "width": 1.5, "dash": Vector2.ZERO, "mark": "—"},
		WorldState.COMPUTE_ENERGY_SAT: {"color": INK, "width": 1.1, "dash": Vector2(1.5, 2.2), "mark": "···"},
		WorldState.ALIGNMENT_DRIFT: {"color": RED, "width": 1.3, "dash": Vector2(4.0, 2.2), "mark": "- -"},
	}
	var series: Array = []
	for item in lines:
		var line: Dictionary = item
		var style: Dictionary = styles.get(String(line.get("key", "")), {})
		series.append({"points": line.get("points", []), "color": style.get("color", INK),
			"width": style.get("width", 1.2), "dash": style.get("dash", Vector2.ZERO)})
	chart.set_series(series)
	chart_box.add_child(chart)
	var legend := VBoxContainer.new()
	legend.add_theme_constant_override("separation", 1)
	for item in summary.get("stats", []):
		var stat: Dictionary = item
		var style: Dictionary = styles.get(String(stat.get("key", "")), {})
		var text := "%s %s %d → %d" % [style.get("mark", "—"), stat.get("label", ""), int(round(float(stat.get("from", 0.0)))),
			int(round(float(stat.get("to", 0.0))))]
		legend.add_child(_wrapped(text, "Newsreader-Medium.ttf", 11 if _compact else 13, style.get("color", INK),
			HORIZONTAL_ALIGNMENT_LEFT))
	chart_box.add_child(legend)
	row.add_child(chart_box)

	var also_box := VBoxContainer.new()
	also_box.add_theme_constant_override("separation", 5)
	also_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	also_box.add_child(_wrapped("ALSO IN THIS EDITION", "Newsreader-SemiBold.ttf", 9 if _compact else 11, INK,
		HORIZONTAL_ALIGNMENT_LEFT, 1))
	var items: Array = summary.get("also", [])
	for i in items.size():
		also_box.add_child(_wrapped(String(items[i]), "Newsreader-Medium.ttf", 12 if _compact else 14, INK,
			HORIZONTAL_ALIGNMENT_LEFT))
		if i < items.size() - 1:
			also_box.add_child(_rule(1.0, RULE_ITEM))
	row.add_child(also_box)
	return row


func _footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var next_line := String(summary.get("next_line", ""))
	if next_line.is_empty():
		next_line = "The last edition of the century."
	var note := _wrapped(next_line, "Newsreader-MediumItalic.ttf", 12 if _compact else 14, INK_SOFT, HORIZONTAL_ALIGNMENT_LEFT)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(note)
	_turn_button = Button.new()
	_turn_button.name = "TurnPage"
	_turn_button.text = tr("Turn the page ▸")
	_turn_button.custom_minimum_size = Vector2(0, 46)
	_turn_button.focus_mode = Control.FOCUS_NONE
	_turn_button.add_theme_font_override("font", EraStyle.font("Newsreader-SemiBold.ttf"))
	_turn_button.add_theme_font_size_override("font_size", 14 if _compact else 15)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		_turn_button.add_theme_color_override(state, PAPER)
	var normal := _flat_box(INK)
	_turn_button.add_theme_stylebox_override("normal", normal)
	_turn_button.add_theme_stylebox_override("hover", _flat_box(INK.lightened(0.15)))
	_turn_button.add_theme_stylebox_override("pressed", _flat_box(RED))
	_turn_button.add_theme_stylebox_override("hover_pressed", _flat_box(RED))
	_turn_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_turn_button.pressed.connect(_turn_page)
	row.add_child(_turn_button)
	return row


# --- Small parts ---------------------------------------------------------------------

func _label(text: String, font_file: String, font_size: int, color: Color, align: HorizontalAlignment,
		spacing: int = 0, expand: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_override("font", EraStyle.font(font_file, spacing))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


func _wrapped(text: String, font_file: String, font_size: int, color: Color, align: HorizontalAlignment,
		spacing: int = 0) -> Label:
	var label := _label(text, font_file, font_size, color, align, spacing)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _rule(thickness: float, color: Color) -> ColorRect:
	var rule := ColorRect.new()
	rule.color = color
	rule.custom_minimum_size = Vector2(0, thickness)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


func _double_rule() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.add_child(_rule(2.0, INK))
	box.add_child(_rule(1.0, INK))
	return box


static func _flat_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box
