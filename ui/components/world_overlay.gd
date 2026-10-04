class_name WorldOverlay
extends Container
## Layer chips, caption and news ticker for the globe ("the world is the
## interface").
##
##   chips    one per macro metric: glyph, value and a small bar in the
##            metric's color. Tapping a chip focuses that globe layer (the
##            others dim to about 10%); tapping it again shows every layer.
##   caption  while a layer is focused, one sentence on what that layer shows.
##   ticker   the latest headline under a provenance seal that follows public
##            trust: verified (>= 60), unconfirmed (>= 38) or conflicting.
##            When the seal is not verified and a counter-headline exists, the
##            two alternate every 2.8 s.
##
## Above alignment drift 55 the instruments misreport: for brief moments (up
## to about 35% of the time at drift 100) two chips show a wrong number in the
## drift color. [method misreport_value] gives the dashboard the same lie for
## its other readouts (meters, the year).
##
## Layout. Floating (default; desktop and phones): the overlay covers the
## globe (lay it over the SubViewportContainer, e.g. both children of one
## MarginContainer). The chips row and ticker sit at its bottom edge, side by
## side from 720 px wide and stacked below that, the caption floats above them,
## and the bound globe re-centers in the space above (GlobeViewport
## .set_view_inset). Stacked ([method set_stacked]): the overlay is a block to
## place under the globe in a VBoxContainer instead; its minimum height fits
## the chips and ticker, and the caption floats above its top edge, over the
## bottom of the globe. Only the chips take input; drags elsewhere reach the
## globe.

signal layer_focus_changed(metric_key: String)

const METRIC_KEYS := ["compute_energy_sat", "labor_displacement", "geopolitical_tension",
	"algorithmic_autonomy", "alignment_drift", "epistemic_trust"]
## One sentence per layer (title "Name 57." is added in front).
const CAPTIONS := {
	"compute_energy_sat": "Datacenter heat blooms grow with energy use. A flicker means the grid is throttling.",
	"labor_displacement": "Cities pulse at every shift change. As work automates the pulses stop, offices go dark and crowds gather at the campuses.",
	"geopolitical_tension": "Bloc borders rise into walls and glow with friction. Past 75, launch arcs.",
	"algorithmic_autonomy": "Agent swarms ride the trade routes. As autonomy grows they stop following them.",
	"alignment_drift": "The map grid warps with alignment drift, and the instruments start to misreport.",
	"epistemic_trust": "Undersea cables pulse in step while people trust what they read. Low trust breaks the rhythm.",
}
## Official denials shown against threshold news when trust is low.
const DENIALS := {
	"compute_energy_sat": "Grid operators report ample reserve capacity",
	"labor_displacement": "Frontier Lab reports record employment",
	"geopolitical_tension": "Ministry calls war-swarm reports a foreign fabrication",
	"algorithmic_autonomy": "Network reports no unusual agent activity",
	"alignment_drift": "Lab says its models have never been more aligned",
	"epistemic_trust": "Platforms report record engagement with verified news",
}
const SEAL_VERIFIED := "verified"
const SEAL_UNCONFIRMED := "unconfirmed"
const SEAL_CONFLICTING := "conflicting"
const SEAL_GLYPHS := {"verified": "seal_check", "unconfirmed": "seal_crack", "conflicting": "seal_broken"}
const SEAL_TEXT := {"verified": "VERIFIED · 3 SOURCES", "unconfirmed": "UNCONFIRMED · 1 SOURCE", "conflicting": "CONFLICTING REPORTS"}
## The wire until the first news arrives (or after set_headline with an empty title).
const OPENING_HEADLINE := "Frontier labs race for the next order of magnitude of compute"
## Seconds between headline and counter-headline.
const ALTERNATE_SEC := 2.8
## Major news stays up this many turns before a routine headline replaces it.
const NEWS_HOLD_TURNS := 4
const MISREPORT_FROM := 55.0
const CHIP_HEIGHT := 64.0
## Chip width beside the ticker; stacked chips share the full width (at least 44 px).
const CHIP_WIDTH := 58.0
const CHIP_GAP := 6.0
const TICKER_MIN_HEIGHT := 84.0
## Floating docks put chips and ticker side by side from this width.
const SIDE_BY_SIDE_WIDTH := 720.0
const CAPTION_MAX_WIDTH := 520.0

## The metric whose layer is focused ("" = every layer).
var focused_layer: String:
	get:
		return _focused
	set(value):
		set_focus(value)
var compact := false
var stacked := false
## Show numbers on the chips (an expert toggle; the bars always show).
var show_numbers := true:
	set(value):
		show_numbers = value
		_render_chips()
## Seconds since the overlay started; drives the headline alternation and the
## misreport schedule. Tests may set it and call refresh().
var clock := 0.0

var _globe: GlobeViewport
var _focused := ""
var _metrics := {}
var _turn := 0
var _kicker := "WIRE"
var _title := ""
var _counter := ""
var _news_priority := 0
var _news_turn := -1000
var _lying := false
var _alternate := 0
var _chips := {}
var _dock: BoxContainer
var _chip_row: HBoxContainer
var _ticker: PanelContainer
var _seal: TextureRect
var _meta: Label
var _headline: Label
var _caption: PanelContainer
var _caption_text: RichTextLabel
var _style: EraStyle


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key in METRIC_KEYS:
		_metrics[key] = float(GlobeViewport.DEFAULT_METRICS[key])
	_build()


func _ready() -> void:
	_restyle()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_SORT_CHILDREN:
			_layout()
		NOTIFICATION_THEME_CHANGED:
			if is_node_ready():
				_restyle()


func _process(delta: float) -> void:
	clock += delta
	_update_clock_state()


func _get_minimum_size() -> Vector2:
	if not stacked or _dock == null:
		return Vector2.ZERO
	return Vector2(0.0, _dock.get_combined_minimum_size().y + _pad() * 2.0)


# --- Public API ----------------------------------------------------------------------

## Connects the chips to [param globe]'s layer focus and keeps its colors on
## this control's era.
func bind_globe(globe: GlobeViewport) -> void:
	_globe = globe
	if _globe != null:
		_globe.set_layer_focus(focused_layer)
		_globe.set_era(_style_now().era)
		queue_sort()


## Reads snapshot["metrics"] (0-100; missing keys keep their value) and
## snapshot["turn"].
func update_snapshot(snapshot: Dictionary) -> void:
	var metrics: Dictionary = snapshot.get("metrics", {})
	for key in METRIC_KEYS:
		if metrics.has(key) and is_finite(float(metrics[key])):
			_metrics[key] = clampf(float(metrics[key]), 0.0, 100.0)
	_turn = int(snapshot.get("turn", _turn))
	_update_clock_state(true)
	_render_ticker()
	_render_caption()


## Shows a headline in the ticker. [param counter] is the contradicting
## version shown in turns while the seal is not verified (plain text; it is
## never parsed as markup).
func set_headline(kicker: String, title: String, counter: String = "") -> void:
	_kicker = kicker.strip_edges()
	_title = title.strip_edges()
	_counter = counter.strip_edges()
	_news_priority = 0
	_render_ticker()


## Feeds a log entry (engine.event_logged). Major news (priority >= 2, see
## [method headline_for_entry]) always takes the ticker; a routine crisis
## resolution waits until the major headline is NEWS_HOLD_TURNS turns old.
## Returns true when the ticker changed.
func show_log_entry(entry: Dictionary) -> bool:
	var news := headline_for_entry(entry)
	if news.is_empty():
		return false
	var turn := int(entry.get("turn", _turn))
	var priority := int(news["priority"])
	var fresh := turn >= _news_turn and turn - _news_turn < NEWS_HOLD_TURNS
	if priority < 2 and _news_priority >= 2 and fresh:
		return false
	set_headline(news["kicker"], news["title"], news["counter"])
	_news_priority = priority
	_news_turn = turn
	return true


## Focuses one metric's globe layer ("" shows every layer).
func set_focus(metric_key: String) -> void:
	var key := metric_key if METRIC_KEYS.has(metric_key) else ""
	var changed := key != _focused
	_focused = key
	if _globe != null:
		_globe.set_layer_focus(key)
	_render_chips()
	_render_caption()
	if changed:
		layer_focus_changed.emit(key)


## Touch-friendly sizes and fonts for phones and tablets.
func set_compact(enabled: bool) -> void:
	compact = enabled
	_restyle()


## true: a block for under the globe (minimum height = chips + ticker);
## false: chips and ticker float over the bottom of this control.
func set_stacked(enabled: bool) -> void:
	stacked = enabled
	_arrange_dock()
	update_minimum_size()
	queue_sort()


## What the HUD should display for [param metric_key] right now: the true
## value, or a wrong one while drift makes the instruments misreport. The key
## "year" misreports a calendar year.
func misreport_value(metric_key: String, true_value: float) -> float:
	if not is_misreporting(metric_key):
		return true_value
	if metric_key == "year":
		return true_value - 7.0 + float(_turn % 5)
	return wrong_value(true_value)


## True while [param metric_key] (or, with "", any readout) is misreporting.
func is_misreporting(metric_key: String = "") -> bool:
	if not _lying:
		return false
	if metric_key == "" or metric_key == "year":
		return true
	return misreported_keys(_turn).has(metric_key)


func get_seal() -> String:
	return seal_for_trust(float(_metrics["epistemic_trust"]))


## The headline text on screen right now.
func get_headline_text() -> String:
	return _headline.text


## The value text a chip shows right now.
func get_chip_text(metric_key: String) -> String:
	return (_chips[metric_key]["number"] as Label).text


## Re-renders time-dependent text after [member clock] was set by hand.
func refresh() -> void:
	_update_clock_state(true)


# --- Pure rules (tested directly) ------------------------------------------------

static func seal_for_trust(trust: float) -> String:
	if trust >= 60.0:
		return SEAL_VERIFIED
	if trust >= 38.0:
		return SEAL_UNCONFIRMED
	return SEAL_CONFLICTING


## The ticker's meta line: "PARADIGM · VERIFIED · 3 SOURCES".
static func seal_meta(kicker: String, seal: String) -> String:
	var text := String(SEAL_TEXT.get(seal, SEAL_TEXT[SEAL_CONFLICTING]))
	return text if kicker == "" else "%s · %s" % [kicker.to_upper(), text]


## The headline shown at [param at_clock] seconds: the title, or the counter
## during every other 2.8 s window while the seal is not verified.
static func headline_shown(title: String, counter: String, seal: String, at_clock: float) -> String:
	if seal == SEAL_VERIFIED or counter == "":
		return title
	return counter if int(floor(at_clock / ALTERNATE_SEC)) % 2 == 1 else title


## Whether the instruments misreport at [param at_clock] seconds: never at
## drift 55 or below; up to 35% of 0.32 s ticks at drift 100.
static func misreport_active(drift: float, at_clock: float) -> bool:
	if drift <= MISREPORT_FROM:
		return false
	return _hash(floor(at_clock * 3.1)) < (drift - MISREPORT_FROM) / 45.0 * 0.35


## The two metrics that misreport during [param turn].
static func misreported_keys(turn: int) -> Array:
	var count := METRIC_KEYS.size()
	return [METRIC_KEYS[posmod(turn * 7, count)], METRIC_KEYS[posmod(turn * 11 + 3, count)]]


## A plausible wrong reading: high values read low and low values read high.
static func wrong_value(value: float) -> float:
	return clampf(value + (-38.0 if value > 50.0 else 33.0), 0.0, 100.0)


## Headline for a log entry: {kicker, title, counter, priority}, or {} when
## the entry is not news (routine actions, system notes, stabilizations).
## Priority: 1 crisis resolutions, 2 paradigms, eras, collapses and warning
## thresholds, 3 milestones, emergences and critical thresholds, 4 the
## containment alert, 5 the end state.
static func headline_for_entry(entry: Dictionary) -> Dictionary:
	var text := _sentence(String(entry.get("text", "")))
	match String(entry.get("category", "")):
		"DILEMMA":
			var title := String(entry.get("title", ""))
			return {} if title == "" else _news(String(entry.get("card_category", "CRISIS")), title, "", 1)
		"PARADIGM":
			return _news("PARADIGM", String(entry.get("name", text)), "", 2)
		"ERA":
			return _news("ERA " + String(EraStyle.ROMAN.get(int(entry.get("era", 1)), "I")), text, "", 2)
		"EMERGENCE":
			return _news("EMERGENCE", String(entry.get("headline", text)), DENIALS["algorithmic_autonomy"], 3)
		"MILESTONE":
			return _news("MILESTONE", _strip_parenthetical(text.trim_prefix("AGI MILESTONE: ")), "", 3)
		"THRESHOLD":
			if bool(entry.get("imminent", false)):
				return _news("ALERT", "Containment failure imminent: one turn to intervene", "All systems nominal", 4)
			var metric := String(entry.get("metric", ""))
			var band := int(entry.get("band", 0))
			if band <= 0 or not WorldState.METRIC_INFO.has(metric):
				return {}
			var label: String = WorldState.METRIC_INFO[metric]["label"]
			return _news("THRESHOLD", "%s enters the %s band" % [label, "critical" if band >= 2 else "warning"],
				String(DENIALS.get(metric, "")), 3 if band >= 2 else 2)
		"COLLAPSE":
			var headline := String(entry.get("headline", ""))
			return _news("COLLAPSE", headline if headline != "" else text, "", 2)
		"ENDGAME":
			if not entry.has("outcome_name"):
				return {}
			var title := String(entry["outcome_name"])
			var open := text.find("(")
			var close := text.find(")", open)
			if open >= 0 and close > open:
				title += ": " + text.substr(open + 1, close - open - 1)
			return _news("END-STATE %d" % int(entry.get("outcome_number", 0)), title, "All systems nominal", 5)
	return {}


static func _news(kicker: String, title: String, counter: String, priority: int) -> Dictionary:
	return {"kicker": kicker, "title": title, "counter": counter, "priority": priority}


static func _sentence(text: String) -> String:
	return text.strip_edges().trim_suffix(".")


## "Lowers drag (by 40%)" -> "Lowers drag".
static func _strip_parenthetical(text: String) -> String:
	var open := text.find(" (")
	return text if open < 0 else text.left(open)


static func _hash(n: float) -> float:
	var x := sin(n * 127.1 + 311.7) * 43758.5453
	return x - floor(x)


# --- Building ----------------------------------------------------------------------

func _build() -> void:
	_dock = BoxContainer.new()
	_dock.name = "Dock"
	_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dock)

	_chip_row = HBoxContainer.new()
	_chip_row.name = "Chips"
	_chip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip_row.add_theme_constant_override("separation", int(CHIP_GAP))
	_dock.add_child(_chip_row)
	for key in METRIC_KEYS:
		_chip_row.add_child(_build_chip(key))

	_ticker = PanelContainer.new()
	_ticker.name = "Ticker"
	_ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ticker.custom_minimum_size = Vector2(0, TICKER_MIN_HEIGHT)
	_ticker.draw.connect(_draw_brackets.bind(_ticker))
	_dock.add_child(_ticker)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	_ticker.add_child(row)
	_seal = TextureRect.new()
	_seal.name = "Seal"
	_seal.custom_minimum_size = Vector2(30, 30)
	_seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_seal.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_seal)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 4)
	row.add_child(text)
	_meta = Label.new()
	_meta.name = "Meta"
	_meta.clip_text = true
	_meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(_meta)
	_headline = Label.new()
	_headline.name = "Headline"
	# No overrun trimming: an autowrapped Label that may trim reports a
	# minimum height of one pixel and its container squeezes it away.
	_headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_headline.max_lines_visible = 3
	_headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_headline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(_headline)

	_caption = PanelContainer.new()
	_caption.name = "Caption"
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.visible = false
	_caption.draw.connect(_draw_brackets.bind(_caption))
	add_child(_caption)
	_caption_text = RichTextLabel.new()
	_caption_text.bbcode_enabled = true
	_caption_text.fit_content = true
	_caption_text.scroll_active = false
	_caption_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_child(_caption_text)
	_arrange_dock()


func _build_chip(key: String) -> Button:
	var chip := Button.new()
	chip.name = "Chip_" + key
	chip.toggle_mode = true
	chip.custom_minimum_size = Vector2(CHIP_WIDTH, CHIP_HEIGHT)
	chip.focus_mode = Control.FOCUS_NONE
	chip.pressed.connect(_on_chip_pressed.bind(key))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 5)
	chip.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var glyph := TextureRect.new()
	glyph.texture = Glyphs.texture(Glyphs.for_metric(key), 22)
	glyph.custom_minimum_size = Vector2(22, 22)
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(glyph)
	var number := Label.new()
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(number)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(30, 3)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.draw.connect(_draw_bar.bind(key))
	column.add_child(bar)
	_chips[key] = {"button": chip, "glyph": glyph, "number": number, "bar": bar, "shown": 0.0, "color": Color.WHITE}
	return chip


## Side by side when floating over a wide globe; otherwise chips above the ticker.
func _arrange_dock() -> void:
	if _dock == null:
		return
	var side_by_side := not stacked and size.x >= SIDE_BY_SIDE_WIDTH
	_dock.vertical = not side_by_side
	_dock.add_theme_constant_override("separation", 12 if side_by_side else 10)
	for key in METRIC_KEYS:
		var chip: Button = _chips[key]["button"]
		chip.size_flags_horizontal = Control.SIZE_FILL if side_by_side else Control.SIZE_EXPAND_FILL
		chip.custom_minimum_size = Vector2(CHIP_WIDTH if side_by_side else 44.0, CHIP_HEIGHT)
	_chip_row.size_flags_horizontal = Control.SIZE_FILL if side_by_side else Control.SIZE_EXPAND_FILL
	_chip_row.size_flags_vertical = Control.SIZE_SHRINK_END


func _layout() -> void:
	var pad := _pad()
	var was_side_by_side := not _dock.vertical
	if was_side_by_side != (not stacked and size.x >= SIDE_BY_SIDE_WIDTH):
		_arrange_dock()
	var width := maxf(0.0, size.x - pad * 2.0)
	var dock_height := _dock.get_combined_minimum_size().y
	var dock_top := pad if stacked else size.y - pad - dock_height
	fit_child_in_rect(_dock, Rect2(pad, dock_top, width, dock_height))
	var caption_width := width if stacked or compact else minf(width, CAPTION_MAX_WIDTH)
	_caption.size = Vector2(caption_width, 0.0)
	var caption_height := _caption.get_combined_minimum_size().y
	fit_child_in_rect(_caption, Rect2(pad, dock_top - 10.0 - caption_height, caption_width, caption_height))
	if _globe != null:
		# Floating over the globe: center it in the space above the dock.
		_globe.set_view_inset(0.0 if stacked else size.y - dock_top)


func _pad() -> float:
	return 12.0 if compact else 14.0


# --- Rendering ---------------------------------------------------------------------

func _style_now() -> EraStyle:
	return EraTheme.style_of(self)


func _restyle() -> void:
	_style = _style_now()
	var s := _style
	var radius: int = [0, 12, 6, 18][s.era]
	for key in METRIC_KEYS:
		var chip: Button = _chips[key]["button"]
		var metric := s.metric_color(key)
		var normal := _box(Color(s.surface, 0.9), s.border, radius)
		var hover := _box(Color(s.raised, 0.94), s.border_strong, radius)
		var active := _box(Color(s.surface.lerp(metric, 0.1), 0.95), metric, radius)
		if s.glow > 0.0:
			active.shadow_color = Color(metric, s.glow)
			active.shadow_size = 6
		for state in ["normal", "disabled", "focus"]:
			chip.add_theme_stylebox_override(state, normal if state != "focus" else StyleBoxEmpty.new())
		chip.add_theme_stylebox_override("hover", hover)
		chip.add_theme_stylebox_override("pressed", active)
		chip.add_theme_stylebox_override("hover_pressed", active)
		var number: Label = _chips[key]["number"]
		number.add_theme_font_override("font", s.font_mono)
		number.add_theme_font_size_override("font_size", 12)
	var ticker_box := _box(Color(s.surface, 0.94), s.border, [0, 14, 4, 20][s.era], 12.0, 14.0)
	_ticker.add_theme_stylebox_override("panel", ticker_box)
	_meta.add_theme_font_override("font", _meta_font(s))
	_meta.add_theme_font_size_override("font_size", 11 if s.era == 3 else 10)
	_headline.add_theme_font_override("font", EraStyle.font("Geist-Medium.ttf") if s.era == 1 else s.font_ui_bold)
	_headline.add_theme_font_size_override("font_size", 15 if compact else 14)
	_headline.add_theme_color_override("font_color", s.text_bright)
	_caption_text.add_theme_font_override("normal_font", s.font_ui)
	_caption_text.add_theme_font_override("bold_font", s.font_ui_bold)
	_caption_text.add_theme_font_size_override("normal_font_size", 13)
	_caption_text.add_theme_font_size_override("bold_font_size", 13)
	_caption_text.add_theme_color_override("default_color", s.text)
	if _globe != null:
		_globe.set_era(s.era)
	_render_chips()
	_render_ticker()
	_render_caption()
	update_minimum_size()
	queue_sort()


func _meta_font(s: EraStyle) -> Font:
	match s.era:
		2:
			return EraStyle.font("JetBrainsMono-Regular.ttf", 1)
		3:
			return s.font_mono
	return EraStyle.font("Geist-SemiBold.ttf", 1)


## A chip/card StyleBox in the era's shape: rounded (I), chamfered glass (II)
## or uneven cells (III).
func _box(bg: Color, border: Color, radius: int, margin_v: float = 4.0, margin_h: float = 4.0) -> StyleBoxFlat:
	var box := EraTheme.panel(_style, bg, border, radius, margin_h)
	box.set_border_width_all(1)
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	return box


func _on_chip_pressed(key: String) -> void:
	set_focus("" if focused_layer == key else key)


func _update_clock_state(force: bool = false) -> void:
	var lying := misreport_active(float(_metrics["alignment_drift"]), clock)
	var alternate := int(floor(clock / ALTERNATE_SEC)) % 2
	if not force and lying == _lying and alternate == _alternate:
		return
	_lying = lying
	_alternate = alternate
	_render_chips()
	_render_headline()


func _render_chips() -> void:
	if _style == null:
		return
	var s := _style
	var dim := Color(s.text_dim, 0.55)
	for key in METRIC_KEYS:
		var parts: Dictionary = _chips[key]
		var chip: Button = parts["button"]
		var value := float(_metrics[key])
		var shown := misreport_value(key, value)
		var wrong := not is_equal_approx(shown, value)
		var dimmed: bool = focused_layer != "" and focused_layer != key
		var color := dim if dimmed else s.metric_color(key)
		chip.set_pressed_no_signal(focused_layer == key)
		chip.tooltip_text = "%s %d. %s" % [UiFormat.metric_name(key), int(round(value)),
			"Show every layer" if focused_layer == key else "Show this layer only"]
		(parts["glyph"] as TextureRect).self_modulate = color
		var number: Label = parts["number"]
		number.visible = show_numbers
		number.text = "%d" % int(round(shown))
		number.add_theme_color_override("font_color",
			s.metric_color("alignment_drift") if wrong else (dim if dimmed else s.text))
		parts["shown"] = shown
		parts["color"] = color
		(parts["bar"] as Control).queue_redraw()


func _render_ticker() -> void:
	if _style == null:
		return
	var s := _style
	var seal := get_seal()
	var color := s.metric_color("epistemic_trust")
	var meta_color := s.text_dim
	if seal == SEAL_UNCONFIRMED:
		color = s.warn
		meta_color = s.warn
	elif seal == SEAL_CONFLICTING:
		color = s.metric_color("alignment_drift")
		meta_color = color
	_seal.texture = Glyphs.texture(SEAL_GLYPHS[seal], 30, 1.4)
	_seal.self_modulate = color
	var meta := seal_meta(_kicker, seal)
	_meta.text = meta.to_lower() if s.era == 3 else meta
	_meta.add_theme_color_override("font_color", meta_color)
	_render_headline()


func _render_headline() -> void:
	if _style == null:
		return
	_headline.text = headline_shown(_title if _title != "" else OPENING_HEADLINE, _counter, get_seal(), clock)
	_headline.add_theme_color_override("font_color", _style.text_bright)


func _render_caption() -> void:
	if _style == null:
		return
	_caption.visible = focused_layer != ""
	if focused_layer == "":
		return
	var color := _style.metric_color(focused_layer)
	_caption.add_theme_stylebox_override("panel", _box(Color(_style.overlay, 0.9), color, [0, 12, 4, 18][_style.era], 10.0, 12.0))
	_caption_text.text = "[b][color=#%s]%s %d.[/color][/b] %s" % [color.to_html(false), UiFormat.metric_name(focused_layer),
		int(round(float(_metrics[focused_layer]))), CyberPalette.escape_bbcode(String(CAPTIONS[focused_layer]))]
	queue_sort()


func _draw_bar(key: String) -> void:
	var parts: Dictionary = _chips[key]
	var bar: Control = parts["bar"]
	var rect := Rect2(Vector2.ZERO, bar.size)
	bar.draw_rect(rect, Color(_style.text, 0.12) if _style != null else Color(1, 1, 1, 0.12))
	var fill := clampf(float(parts["shown"]) / 100.0, 0.0, 1.0)
	if fill > 0.0:
		bar.draw_rect(Rect2(rect.position, Vector2(rect.size.x * fill, rect.size.y)), parts["color"])


## Era II cards get cyan corner brackets, as in the holographic mockup.
func _draw_brackets(panel: Control) -> void:
	if _style == null or _style.era != 2:
		return
	var color := _style.accent
	var length := 10.0
	var r := Rect2(Vector2.ZERO, panel.size)
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var c: Vector2 = corner
		var dx := length if c.x <= r.position.x else -length
		var dy := length if c.y <= r.position.y else -length
		panel.draw_line(c, c + Vector2(dx, 0), color, 2.0)
		panel.draw_line(c, c + Vector2(0, dy), color, 2.0)
