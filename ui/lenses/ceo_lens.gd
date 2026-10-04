class_name CeoLens
extends LensPanel
## Frontier Lab CEO lens ("Markets"): a trading terminal. The world arrives as
## a ticker tape and a price sheet, the company as a capital runway and a book
## of positions, the last move as a press release and the next directive as an
## order ticket. Rises print green and falls red, as a trader reads them; the
## price sheet is shaded by risk to the lab.

const BG := Color("#0A0C0F")
const PANEL_BG := Color("#0D1014")
const LINE := Color("#1E232A")
const LINE_SOFT := Color("#161B21")
const TEXT := Color("#D7DEE6")
const BRIGHT := Color("#F2F5F8")
const DIM := Color("#8A96A3")
const FAINT := Color("#5F6B78")
const UP := Color("#39FF88")
const DOWN := Color("#FF5C6C")
const BUTTON_LINE := Color("#2A313A")
const ON_ACCENT := Color("#04080B")

const TICKERS := {
	"compute_energy_sat": "CMPT", "labor_displacement": "LABR", "geopolitical_tension": "TNSN",
	"algorithmic_autonomy": "AUTO", "alignment_drift": "DRFT", "epistemic_trust": "TRST",
}
const TICKER_GAP := 22.0
## Seconds for the tape to move by one full set of quotes.
const TICKER_PERIOD := 22.0
const TICKER_SIZE := 12

## "The world, priced": what each metric costs or earns the lab. Upside tiles
## read a high value as opportunity; the rest are shaded by risk.
const PRICED := [
	{"label": "POWER COST", "metric": "compute_energy_sat", "upside": false},
	{"label": "AUTOMATION", "metric": "labor_displacement", "upside": true},
	{"label": "EXPORT RISK", "metric": "geopolitical_tension", "upside": false},
	{"label": "AGENT ECONOMY", "metric": "algorithmic_autonomy", "upside": true},
	{"label": "LIABILITY", "metric": "alignment_drift", "upside": false},
	{"label": "SENTIMENT", "metric": "epistemic_trust", "upside": false},
]
## [background, label] per shade.
const SHADE_UPSIDE := [Color("#0F2A1A"), Color("#7FE0A6")]
const SHADE_WATCH := [Color("#2A2412"), Color("#E8C77A")]
const SHADE_RISK := [Color("#33191C"), Color("#F29AA4")]
const SHADE_CRITICAL := [Color("#4A161D"), Color("#FFA3AE")]

const BOOK := [["compute_clusters", "COMPUTE"], ["talent", "TALENT"], ["regulatory_goodwill", "GOODWILL"]]

## Order-ticket names for the lab's directives.
const ORDER_NAMES := {
	"SCALE_FRONTIER_CLUSTERS": "SCALE CLUSTERS", "COMMERCIALIZE_DISTILLED_WEIGHTS": "DISTILL",
	"POACH_SAFETY_RESEARCHERS": "POACH TALENT", "LOBBY_COMPUTE_LICENSING": "LOBBY",
	"FUND_ALIGNMENT_RESEARCH": "SAFETY R&D", "SECURE_SOVEREIGN_CONTRACT": "DEFENSE DEAL",
	"CONSERVE_RESOURCES": "HOLD",
}
const ORDER_SLOTS := 4

var _mono: Font = EraStyle.font("JetBrainsMono-Regular.ttf")
var _mono_bold: Font = EraStyle.font("JetBrainsMono-Bold.ttf")
var _caps: Font = EraStyle.font("Geist-Bold.ttf", 2)
var _caps_small: Font = EraStyle.font("Geist-Bold.ttf", 1)
var _quote_font: Font = EraStyle.font("Geist-Medium.ttf")
var _accent := Color("#00E5FF")

var _logo: LensPanel.Canvas
var _turn_label: Label
var _live_dot: LensPanel.Canvas
var _live_label: Label
var _ticker: LensPanel.Canvas
var _ticker_items: Array = []
var _ticker_width := 0.0
var _capital_label: Label
var _capital_change: Label
var _capital_flows: Label
var _chart: LensPanel.Canvas
var _axis: Array[Label] = []
var _book_rows := {}
var _tiles: Array = []
var _press_caption: Label
var _press_quote: Label
var _order_dock: PanelContainer
var _order_grid: GridContainer
var _order_signature := ""


func _init() -> void:
	role = SimConstants.CEO


func lens_title() -> String:
	return "Markets"


func lens_background() -> Color:
	return BG


func _apply_era() -> void:
	_accent = era_style.faction_color(SimConstants.CEO)
	_order_signature = ""
	if _order_dock != null:
		_order_dock.add_theme_stylebox_override("panel", _dock_box())
	for canvas in [_logo, _chart]:
		if canvas != null:
			canvas.queue_redraw()


# --- Build ---------------------------------------------------------------------------

func _build() -> void:
	_build_top_bar()
	_build_ticker()
	_build_capital()
	_build_book()
	_build_priced()
	_build_press()
	_content.add_child(_spacer(16))
	_build_orders()


func _build_top_bar() -> void:
	var bar := _panel(_rule_box(Color(0, 0, 0, 0), false, 14.0, 0.0))
	bar.custom_minimum_size.y = 46
	var row := _hbox(8)
	bar.add_child(row)
	_logo = _canvas(_draw_logo, Vector2(14, 14))
	_logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_logo)
	var title := _clip_label("FRONTIER LAB", _caps, 13, BRIGHT)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)
	_turn_label = _label("", _mono, 11, DIM)
	_turn_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_turn_label)
	_live_dot = _canvas(_draw_live_dot, Vector2(10, 10))
	_live_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_live_dot.fps = 20.0
	row.add_child(_live_dot)
	_live_label = _label("LIVE", _mono, 11, UP)
	_live_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_live_label)
	_header.add_child(bar)


func _build_ticker() -> void:
	var tape := _panel(_rule_box(PANEL_BG, false, 0.0, 0.0))
	_ticker = _canvas(_draw_ticker, Vector2(0, 30))
	_ticker.animated = true
	tape.add_child(_ticker)
	_header.add_child(tape)


func _build_capital() -> void:
	var block := _vbox(2)
	block.add_child(_label("CAPITAL RUNWAY", _caps, 11, DIM))
	var row := _hbox(10)
	_capital_label = _label("", _mono_bold, 42, BRIGHT)
	row.add_child(_capital_label)
	_capital_change = _label("", _mono, 13, UP)
	# Sit on the big figure's baseline rather than below its descent.
	var lift := int(roundf(_mono_bold.get_descent(42) - _mono.get_descent(13)))
	var change_slot := _margin(_capital_change, 0, 0, 0, lift)
	change_slot.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(change_slot)
	block.add_child(row)
	_capital_flows = _label("", _mono, 11, DIM, true)
	block.add_child(_capital_flows)
	_content.add_child(_margin(block, 16, 14, 16, 0))

	var chart_box := _vbox(3)
	_chart = _canvas(_draw_chart, Vector2(0, 110))
	chart_box.add_child(_chart)
	var axis_row := _hbox(0)
	for alignment in [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_RIGHT]:
		var label := _label("", _mono, 10, FAINT)
		label.horizontal_alignment = alignment
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		axis_row.add_child(label)
		_axis.append(label)
	chart_box.add_child(axis_row)
	_content.add_child(_margin(chart_box, 16, 10, 16, 0))


func _build_book() -> void:
	var table := _vbox(0)
	var head := _panel(_rule_box(Color(0, 0, 0, 0), false, 0.0, 0.0))
	var head_row := _book_row_layout(_label("BOOK", _caps_small, 10, FAINT), _label("LAST", _caps_small, 10, FAINT),
		Control.new(), _label("CHG", _caps_small, 10, FAINT))
	head.add_child(_margin(head_row, 0, 0, 0, 6))
	table.add_child(head)
	for entry in BOOK:
		var key: String = entry[0]
		var name_label := _label(String(entry[1]), _mono, 13, DIM)
		var last := _label("", _mono, 13, BRIGHT)
		var spark := _canvas(_draw_spark.bind(key), Vector2(64, 18))
		var change := _label("", _mono, 13, UP)
		var row := _panel(_rule_box(Color(0, 0, 0, 0), false, 0.0, 0.0, LINE_SOFT))
		row.custom_minimum_size.y = 32
		row.add_child(_book_row_layout(name_label, last, spark, change))
		table.add_child(row)
		_book_rows[key] = {"last": last, "spark": spark, "change": change}
	_content.add_child(_margin(table, 16, 12, 16, 0))


## BOOK grid: 96 px name | value (right) | 64 px sparkline | 62 px change.
func _book_row_layout(name_label: Label, last: Label, spark: Control, change: Label) -> HBoxContainer:
	var row := _hbox(0)
	name_label.custom_minimum_size.x = 96
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)
	last.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	last.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	last.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(last)
	var spark_slot := _margin(spark, 10, 0, 0, 0)
	spark.custom_minimum_size = Vector2(64, 18)
	spark_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(spark_slot)
	change.custom_minimum_size.x = 62
	change.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	change.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(change)
	return row


func _build_priced() -> void:
	var block := _vbox(6)
	block.add_child(_label("THE WORLD, PRICED", _caps_small, 10, FAINT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for entry in PRICED:
		var tile := _panel(_box(SHADE_WATCH[0], 0, 8.0, 7.0))
		tile.custom_minimum_size.y = 50
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var stack := _vbox(0)
		var caption := _clip_label(String(entry["label"]), _mono, 10, SHADE_WATCH[1])
		stack.add_child(caption)
		var filler := Control.new()
		filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
		stack.add_child(filler)
		var values := _hbox(5)
		var value := _label("", _mono, 15, BRIGHT)
		values.add_child(value)
		var delta := _label("", _mono, 11, DIM)
		delta.size_flags_vertical = Control.SIZE_SHRINK_END
		values.add_child(delta)
		stack.add_child(values)
		tile.add_child(stack)
		grid.add_child(tile)
		_tiles.append({"entry": entry, "panel": tile, "caption": caption, "value": value, "delta": delta})
	block.add_child(grid)
	_content.add_child(_margin(block, 16, 12, 16, 0))


func _build_press() -> void:
	var card := _panel(_outline(PANEL_BG, LINE, 1, 0, 12.0, 10.0))
	var stack := _vbox(4)
	_press_caption = _label("", _caps_small, 10, FAINT, true)
	stack.add_child(_press_caption)
	_press_quote = _label("", _quote_font, 15, BRIGHT, true)
	stack.add_child(_press_quote)
	card.add_child(stack)
	_content.add_child(_margin(card, 16, 12, 16, 0))


func _build_orders() -> void:
	var dock := _panel(_dock_box())
	dock.name = "OrderDock"
	_order_dock = dock
	var stack := _vbox(8)
	stack.add_child(_label("NEXT ORDER", _caps_small, 10, FAINT))
	_order_grid = GridContainer.new()
	_order_grid.columns = 2
	_order_grid.add_theme_constant_override("h_separation", 6)
	_order_grid.add_theme_constant_override("v_separation", 6)
	stack.add_child(_order_grid)
	dock.add_child(stack)
	_footer.add_child(dock)


## The order dock: a band ruled on top whose lower corners follow the frame.
func _dock_box() -> StyleBoxFlat:
	var box := _rule_box(PANEL_BG, true, 16.0, 10.0)
	box.content_margin_bottom = 16
	return box


## A transparent or filled band with a one-pixel rule on its top or bottom edge.
func _rule_box(bg: Color, rule_on_top: bool, margin_h: float, margin_v: float, rule: Color = LINE) -> StyleBoxFlat:
	var box := _edge_box(bg, false) if rule_on_top else _box(bg, 0, margin_h, margin_v)
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	box.border_color = rule
	if rule_on_top:
		box.border_width_top = 1
	else:
		box.border_width_bottom = 1
	return box


static func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	return spacer


# --- Refresh -------------------------------------------------------------------------

func _refresh() -> void:
	var ended := String(snapshot.get("phase", "")) == "ENDED"
	_turn_label.text = "T%d · %s" % [current_turn(), half_label()] if not snapshot.is_empty() else "PRE-OPEN"
	_live_label.text = "CLOSED" if ended else "LIVE"
	_set_color(_live_label, FAINT if ended else UP)
	_live_dot.animated = not ended
	_live_dot.queue_redraw()
	_refresh_ticker()
	_refresh_capital()
	_refresh_book()
	_refresh_priced()
	_refresh_press()
	_refresh_orders()


func _refresh_ticker() -> void:
	_ticker_items.clear()
	_ticker_width = 0.0
	if snapshot.is_empty():
		_ticker.queue_redraw()
		return
	for key in WorldState.METRIC_KEYS:
		var delta := metric_delta(key)
		var parts := [
			[String(TICKERS[key]) + " ", DIM],
			["%d " % int(roundf(metric(key))), BRIGHT],
			[_arrow(delta), _change_color(delta, 0)],
		]
		var width := 0.0
		for part in parts:
			var part_width := _mono.get_string_size(String(part[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, TICKER_SIZE).x
			part.append(part_width)
			width += part_width
		_ticker_items.append({"parts": parts, "width": width})
		_ticker_width += width + TICKER_GAP
	_ticker.queue_redraw()


func _refresh_capital() -> void:
	var capital := float(resources.get("capital", 0.0))
	_capital_label.text = UiFormat.format_resource(role, "capital", capital) if not resources.is_empty() else "—"
	var change := resource_delta("capital")
	var amount := int(roundf(absf(change)))
	_capital_change.text = "=" if amount == 0 else "%s $%dB" % ["▲" if change > 0.0 else "▼", amount]
	_set_color(_capital_change, _change_color(change, 0))
	var flows := _capital_flow_items()
	_capital_flows.text = " · ".join(flows) if not flows.is_empty() else "no directive cash flows this turn"
	# Axis: first, middle and latest sample years.
	var marks := [-1, -1, -1]
	if not history.is_empty():
		marks[0] = 0
	if history.size() >= 2:
		marks[2] = history.size() - 1
	if history.size() >= 3:
		marks[1] = floori(history.size() / 2.0)
	for i in _axis.size():
		var index: int = marks[i]
		_axis[i].text = UiFormat.year_label(float(history[index].get("year", 2026.0))) if index >= 0 else ""
	_chart.queue_redraw()


## Capital moved by this turn's directives: the lab's own (net of cost) and
## every rival's hit or gift, e.g. "aggressive weight distillation +$70B".
func _capital_flow_items() -> Array[String]:
	var items: Array[String] = []
	var actions: Dictionary = snapshot.get("turn_actions", {})
	for faction_id in SimConstants.FACTION_ORDER:
		if not actions.has(faction_id):
			continue
		var outcome: Dictionary = actions[faction_id]
		var applied: Dictionary = outcome.get("applied", {})
		var amount := 0.0
		if faction_id == role:
			amount = float((applied.get("self", {}) as Dictionary).get("capital", 0.0)) \
				- float((outcome.get("cost", {}) as Dictionary).get("capital", 0.0))
		else:
			amount = float(((applied.get("factions", {}) as Dictionary).get(role, {}) as Dictionary).get("capital", 0.0))
		if absf(amount) >= 0.5:
			items.append("%s %s$%dB" % [String(outcome.get("action_name", "")).to_lower(), "+" if amount > 0.0 else "−",
				int(roundf(absf(amount)))])
	return items


func _refresh_book() -> void:
	for entry in BOOK:
		var key: String = entry[0]
		var row: Dictionary = _book_rows[key]
		var value := float(resources.get(key, 0.0))
		var text := "%.1f" % value if key == "regulatory_goodwill" else UiFormat.format_resource(role, key, value)
		(row["last"] as Label).text = text if not resources.is_empty() else "—"
		var change := resource_delta(key)
		(row["change"] as Label).text = _arrow(change, 1)
		_set_color(row["change"], _change_color(change, 1))
		(row["spark"] as Control).queue_redraw()


func _refresh_priced() -> void:
	for tile in _tiles:
		var entry: Dictionary = tile["entry"]
		var key: String = entry["metric"]
		var shade := _tile_shade(entry)
		(tile["panel"] as PanelContainer).add_theme_stylebox_override("panel", _box(shade[0], 0, 8.0, 7.0))
		_set_color(tile["caption"], shade[1])
		(tile["value"] as Label).text = "%d" % int(roundf(metric(key))) if not snapshot.is_empty() else "—"
		var delta := metric_delta(key)
		(tile["delta"] as Label).text = _arrow(delta)
		_set_color(tile["delta"], _change_color(delta, 0))


## Upside tiles are green; risk tiles amber until their warning line, then red,
## deepening toward the critical line.
func _tile_shade(entry: Dictionary) -> Array:
	if bool(entry["upside"]):
		return SHADE_UPSIDE
	var key: String = entry["metric"]
	var value := metric(key)
	var band := WorldState.band_for(key, value)
	if band == 0:
		return SHADE_WATCH
	if band >= 2:
		return SHADE_CRITICAL
	var info: Dictionary = WorldState.METRIC_INFO[key]
	var depth := 0.0
	if info["warn_high"] != null and value >= float(info["warn_high"]):
		depth = inverse_lerp(float(info["warn_high"]), float(info["crit_high"]), value)
	elif info["warn_low"] != null:
		depth = inverse_lerp(float(info["warn_low"]), float(info["crit_low"]), value)
	depth = clampf(depth, 0.0, 1.0) * 0.6
	return [(SHADE_RISK[0] as Color).lerp(SHADE_CRITICAL[0], depth), (SHADE_RISK[1] as Color).lerp(SHADE_CRITICAL[1], depth)]


func _refresh_press() -> void:
	var statement := statement_for(role).strip_edges()
	if statement == "":
		_press_caption.text = "YOUR PRESS RELEASE"
		_press_quote.text = "No statement on file."
		_set_color(_press_quote, DIM)
		return
	_press_caption.text = "YOUR PRESS RELEASE · %s" % ("THIS TURN" if outcome_is_current(role) else "LAST TURN")
	_press_quote.text = "“%s”" % statement
	_set_color(_press_quote, BRIGHT)


func _refresh_orders() -> void:
	var primary := suggested_action()
	var picks := _order_picks(primary)
	var parts: Array[String] = [primary, _accent.to_html()]
	for action_id in picks:
		var entry := action_entry(action_id)
		parts.append("%s|%s|%s" % [action_id, entry.get("blocked_reason", ""), _order_price(action_id)[0]])
	var signature := ";".join(parts)
	if signature == _order_signature:
		return
	_order_signature = signature
	_clear(_order_grid)
	for action_id in picks:
		_order_grid.add_child(_order_button(action_id, action_id == primary))


## Up to ORDER_SLOTS directives: the suggested one, then the available ones,
## then blocked ones so the ticket keeps its shape.
func _order_picks(primary: String) -> Array[String]:
	var picks: Array[String] = [primary]
	for pass_blocked in [false, true]:
		for entry in action_entries():
			var action_id := String(entry.get("id", ""))
			var blocked := String(entry.get("blocked_reason", "")) != ""
			if action_id == CONSERVE or blocked != pass_blocked or picks.has(action_id):
				continue
			picks.append(action_id)
	if picks.size() < ORDER_SLOTS and not picks.has(CONSERVE):
		picks.append(CONSERVE)
	return picks.slice(0, ORDER_SLOTS)


func _order_button(action_id: String, primary: bool) -> Button:
	var button := _directive_button(action_id)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var entry := action_entry(action_id)
	var blocked := String(entry.get("blocked_reason", "")) != ""
	button.disabled = blocked
	button.tooltip_text = String(entry.get("name", action_id))
	var fill := _accent if primary and not blocked else Color(0, 0, 0, 0)
	var boxes := {
		"normal": _outline(fill, _accent if primary else BUTTON_LINE, 0 if primary else 1),
		"hover": _outline(fill.lightened(0.12) if primary else Color(1, 1, 1, 0.04), _accent if primary else Color("#3A4350"), 0 if primary else 1),
		"pressed": _outline(fill.darkened(0.15) if primary else Color(_accent, 0.12), _accent, 0 if primary else 1),
		"disabled": _outline(Color(0, 0, 0, 0), LINE, 1),
	}
	_style_button(button, boxes, _mono, 12, {})
	var row := _hbox(6)
	var ink := ON_ACCENT if primary and not blocked else (FAINT if blocked else TEXT)
	var name_label := _clip_label(String(ORDER_NAMES.get(action_id, String(entry.get("name", action_id)).to_upper())),
		_mono_bold if primary else _mono, 12, ink)
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)
	var price := _order_price(action_id)
	var price_label := _label(_blocked_short(String(entry.get("blocked_reason", ""))) if blocked else String(price[0]),
		_mono_bold if primary else _mono, 11 if blocked else 12, ink if primary or blocked else price[1])
	price_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(price_label)
	_fill_button(button, row, 12.0)
	return button


## [text, color]: the capital it costs ("−$90B"), or what it earns ("+$70B").
func _order_price(action_id: String) -> Array:
	var definition := action_definition(action_id)
	var cost: Dictionary = definition.get("cost", {})
	var gain := float(((definition.get("effects", {}) as Dictionary).get("self", {}) as Dictionary).get("capital", 0.0))
	if cost.has("capital"):
		return ["−$%dB" % int(roundf(float(cost["capital"]))), TEXT]
	if gain > 0.0:
		return ["+$%dB" % int(roundf(gain)), UP]
	if cost.is_empty():
		return ["FREE", TEXT]
	return ["−" + UiFormat.format_cost(role, cost), TEXT]


static func _blocked_short(reason: String) -> String:
	if reason.begins_with("Cooldown"):
		return "COOLDOWN %sT" % reason.get_slice(" ", 1)
	if reason.begins_with("Insufficient"):
		return "NO FUNDS"
	if reason.begins_with("Faction dormant"):
		return "HALTED"
	return reason.to_upper()


func _change_color(delta: float, decimals: int) -> Color:
	var shown := roundf(absf(delta) * pow(10.0, decimals))
	if shown <= 0.0:
		return DIM
	return UP if delta > 0.0 else DOWN


# --- Drawing ------------------------------------------------------------------------

func _draw_logo(canvas: Control) -> void:
	var s := canvas.size
	canvas.draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), Vector2(s.x, s.y * 0.6),
		Vector2(s.x * 0.6, s.y), Vector2(0, s.y)]), _accent)


func _draw_live_dot(canvas: Control) -> void:
	var ended := String(snapshot.get("phase", "")) == "ENDED"
	var pulse := 1.0 if ended else 0.65 + 0.35 * cos((canvas as LensPanel.Canvas).time * TAU / 1.6)
	canvas.draw_circle(canvas.size * 0.5, 3.0, Color(FAINT if ended else UP, pulse))


func _draw_ticker(canvas: Control) -> void:
	var height := canvas.size.y
	var baseline := _baseline(_mono, TICKER_SIZE, 0.0, height)
	if _ticker_items.is_empty() or _ticker_width <= 0.0:
		canvas.draw_string(_mono, Vector2(14, baseline), "AWAITING MARKET DATA", HORIZONTAL_ALIGNMENT_LEFT, -1, TICKER_SIZE, FAINT)
		return
	var speed := _ticker_width / TICKER_PERIOD
	var x := 14.0 - fposmod((canvas as LensPanel.Canvas).time * speed, _ticker_width)
	while x < canvas.size.x:
		for item in _ticker_items:
			var cursor := x
			if cursor + float(item["width"]) > 0.0 and cursor < canvas.size.x:
				for part in item["parts"]:
					canvas.draw_string(_mono, Vector2(cursor, baseline), String(part[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, TICKER_SIZE, part[1])
					cursor += float(part[2])
			x += float(item["width"]) + TICKER_GAP


func _draw_chart(canvas: Control) -> void:
	var w := canvas.size.x
	var h := canvas.size.y
	if w < 2.0 or h < 20.0:
		return
	for i in [1, 2, 3]:
		var y := roundf(h * float(i) / 4.0) + 0.5
		canvas.draw_line(Vector2(0, y), Vector2(w, y), LINE_SOFT, 1.0)
	var values := resource_series("capital")
	if values.is_empty():
		return
	var low := values[0]
	var high := values[0]
	for value in values:
		low = minf(low, value)
		high = maxf(high, value)
	if high - low < 1.0:
		low -= 0.5
		high += 0.5
	var points := PackedVector2Array()
	var count := values.size()
	for i in count:
		var x := w * (float(i) / float(count - 1)) if count > 1 else 0.0
		points.append(Vector2(x, h - 8.0 - (values[i] - low) / (high - low) * (h - 16.0)))
	if count == 1:
		points.append(Vector2(w, points[0].y))
	var area := points.duplicate()
	area.append(Vector2(w, h))
	area.append(Vector2(0, h))
	canvas.draw_colored_polygon(area, Color(_accent, 0.08))
	canvas.draw_polyline(points, _accent, 1.6, true)
	var last := points[points.size() - 1]
	canvas.draw_circle(Vector2(minf(last.x, w - 4.0), last.y), 3.5, _accent)


func _draw_spark(canvas: Control, key: String) -> void:
	var values := resource_series(key)
	var w := canvas.size.x
	var h := canvas.size.y
	if values.size() < 2:
		canvas.draw_line(Vector2(0, h * 0.5), Vector2(w, h * 0.5), FAINT, 1.2, true)
		return
	var low := values[0]
	var high := values[0]
	for value in values:
		low = minf(low, value)
		high = maxf(high, value)
	var span := maxf(high - low, 0.0001)
	var points := PackedVector2Array()
	for i in values.size():
		points.append(Vector2(w * float(i) / float(values.size() - 1), h - 2.0 - (values[i] - low) / span * (h - 4.0)))
	canvas.draw_polyline(points, FAINT, 1.2, true)
