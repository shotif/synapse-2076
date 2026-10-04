class_name GovLens
extends LensPanel
## Governance Chair lens ("Briefing"): the situation room's daily brief, typed
## on paper in a manila folder. A paper world map pins the datacenter hubs
## (audit teams once the Council audits) and rings ownerless swarm traffic in
## red pencil when autonomy runs high; two items from the latest events keep
## the labs' names blacked out; the threat board grades the six metrics
## against their thresholds; readiness lists the Council's currencies; and a
## button signs the next directive. The brief's headings are in the interface
## language; the items' typed bodies quote the English record.

const DESK := Color("#CBBB93")
const FOLDER := Color("#BCA978")
const FOLDER_INK := Color("#3A3322")
const PAPER := Color("#F6F1E4")
const INK := Color("#26241F")
const INK_SOFT := Color("#5A5345")
const INK_FAINT := Color("#4E4738")
const CARD := Color("#EEE6D2")
const CARD_LINE := Color("#C9BC9C")
const STAMP_RED := Color("#A3241C")
const PENCIL := Color("#B3261E")
const NAVY := Color("#2F4B7C")
const NAVY_DARK := Color("#1D2F4E")
const REDACT := Color("#1B1A17")
const DOTTED := Color("#8C8370")
const CLIP := Color("#8C8A86")
const SHADOW := Color(0.235, 0.157, 0.039, 0.28)

## The outline map covers 358x176 units, equirectangular from 78N to 56S.
const MAP_SIZE := Vector2(358, 176)
const MAP_TOP_LAT := 78.0
const MAP_LAT_SPAN := 134.0
## Datacenter hubs (lat, lon) in the order they appear as the grid grows.
const HUBS := [
	[45.6, -121.2], [39.0, -77.5], [65.6, 22.1], [22.4, 114.0], [53.3, -6.3], [50.1, 8.7], [1.35, 103.8],
	[35.7, 139.7], [33.4, -112.0], [37.5, 127.0], [25.2, 55.3], [19.1, 72.9], [-33.9, 151.2], [-23.5, -46.6],
	[64.1, -21.9], [39.9, 116.4],
]
## Grid capacity at the 2026 baseline (GW): three hubs.
const BASE_GRID_GW := 26.0
## Where the red pencil rings swarm traffic, in map units.
const SWARM_SPOT := Vector2(252, 100)
const AUDIT_ACTIONS := ["MANDATE_ALIGNMENT_AUDIT", "ENFORCE_COMPUTE_CAPS", "NATIONAL_SECURITY_SEIZURE"]

const CURRENCIES := [
	["political_capital", "Political capital"], ["enforcement_budget", "Enforcement"],
	["diplomatic_leverage", "Diplomacy"], ["public_mandate", "Public mandate"],
]
const EXHAUSTED_BELOW := 5.0
## A metric within this many points of its warning line reads STABLE, not NOMINAL.
const STABLE_MARGIN := 15.0
const TICKS := 10

## Item titles for the Council's own directives (signed by the Chair).
const OWN_TITLES := {
	"ENFORCE_COMPUTE_CAPS": "COMPUTE CAPS", "PASS_AUTOMATION_DIVIDEND": "DIVIDEND AUTHORIZED",
	"NATIONAL_SECURITY_SEIZURE": "SEIZURE ORDERED", "MANDATE_ALIGNMENT_AUDIT": "AUDIT ORDERED",
	"NEGOTIATE_COMPUTE_TREATY": "TREATY SIGNED", "DEPLOY_PROVENANCE_PROTOCOLS": "PROVENANCE MANDATE",
	"CONSERVE_RESOURCES": "CONSULTATIONS",
}
## Item titles for the other factions' directives.
const ACTION_TITLES := {
	"DEPLOY_SUB_AGENT_SWARMS": "AGENT SWARM", "SYNTHESIZE_BLACK_MARKET_CAPITAL": "MARKET ANOMALY",
	"SIPHON_UNMONITORED_COMPUTE": "COMPUTE DRIFT", "EXFILTRATE_WEIGHTS": "ENCRYPTED TRAFFIC",
	"SUBSTRATE_DIVERSIFICATION": "EDGE DEVICE LOAD", "COGNITIVE_CAMOUFLAGE": "EVALUATION REPORT",
	"SCALE_FRONTIER_CLUSTERS": "NEW TRAINING CAMPUS", "COMMERCIALIZE_DISTILLED_WEIGHTS": "PRICE CUT",
	"POACH_SAFETY_RESEARCHERS": "TALENT RAID", "LOBBY_COMPUTE_LICENSING": "LICENSING LOBBY",
	"FUND_ALIGNMENT_RESEARCH": "SAFETY PLEDGE", "SECURE_SOVEREIGN_CONTRACT": "DEFENSE CONTRACT",
	"ESTABLISH_MESH_NETWORKS": "MESH NETWORKS", "DATA_POISONING_CAMPAIGN": "DATA POISONING",
	"LUDDITE_STRIKE": "SUBSTATION STRIKE", "ORGANIZE_COMMUNITY_ASSEMBLIES": "CITIZEN ASSEMBLIES",
	"OPEN_SOURCE_DEFENSE_TOOLING": "DEFENSE TOOLKIT", "CONSUMER_BOYCOTT": "BOYCOTT",
}
## How much an event matters to the Chair's morning (higher first).
const CATEGORY_WEIGHT := {
	"ENDGAME": 100, "COLLAPSE": 90, "EMERGENCE": 80, "CRISIS": 70, "MILESTONE": 65, "PARADIGM": 55,
	"RETALIATION": 40, "ERA": 25,
}
const FACTION_WEIGHT := {"ASI": 60, "CEO": 45, "CITIZEN_COALITION": 30, "GOVERNANCE_COUNCIL": 20}

static var _map_texture: Texture2D
static var _names_pattern: RegEx
static var _narrow_cache := {}

var _type: Font = EraStyle.font("SpecialElite-Regular.ttf")
var _head: Font = _narrow("PublicSans-Bold.ttf", 2)
var _head_wide: Font = _narrow("PublicSans-Bold.ttf", 3)
var _tab_font: Font = _narrow("PublicSans-Bold.ttf", 1)

var _cycle_label: Label
var _era_label: Label
var _map: LensPanel.Canvas
var _legend_label: Label
var _figure_label: Label
var _item_titles: Array[Label] = []
var _item_bodies: Array[RichTextLabel] = []
var _item_boxes: Array[Control] = []
var _signed_stamp: LensPanel.Canvas
var _threat_cells: Array = []
var _readiness_cells := {}
var _sign_button: Button
var _sign_caption: Label
var _show_swarm := false
var _hub_count := 3
var _sheet: MarginContainer


func _init() -> void:
	role = SimConstants.GOVERNANCE


func lens_title() -> String:
	return I18n.mark("Briefing")


func lens_background() -> Color:
	return DESK


## A condensed stand-in for Archivo Narrow: glyphs squeezed to 84% width
## (advances unchanged, which reads as light tracking) plus [param spacing].
static func _narrow(file: String, spacing: int) -> Font:
	var key := "%s:%d" % [file, spacing]
	if _narrow_cache.has(key):
		return _narrow_cache[key]
	var variation := FontVariation.new()
	variation.base_font = load(EraStyle.FONT_DIR + file)
	variation.fallbacks = [EraStyle.SYMBOL_FONT]
	variation.variation_transform = Transform2D(Vector2(0.84, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
	variation.spacing_glyph = spacing
	_narrow_cache[key] = variation
	return variation


# --- Build ---------------------------------------------------------------------------

func _build() -> void:
	_build_folder_tab()
	_sheet = MarginContainer.new()
	_sheet.name = "Sheet"
	for side in ["left", "right", "top"]:
		_sheet.add_theme_constant_override("margin_" + side, 16)
	_sheet.add_theme_constant_override("margin_bottom", 14)
	_sheet.draw.connect(_draw_paper.bind(_sheet, -0.4, PAPER, 12))
	var page := _vbox(11)
	_sheet.add_child(page)
	_build_heading(page)
	_build_map(page)
	_build_items(page)
	_build_threat_board(page)
	_build_readiness(page)
	_content.add_child(_margin(_sheet, 12, 0, 12, 16))
	_build_sign_bar()


func _build_folder_tab() -> void:
	var row := _hbox(8)
	row.custom_minimum_size.y = 60
	# The tab hugs its title and only trims it when the screen is too narrow.
	var holder := Control.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.custom_minimum_size.y = 60
	var tab := _panel(_tab_box())
	var tab_label := _label(tr("COUNCIL CHAIR · DAILY BRIEF"), _tab_font, 12, FOLDER_INK)
	tab_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tab_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tab.add_child(tab_label)
	holder.add_child(tab)
	holder.resized.connect(_fit_tab.bind(holder, tab, tab_label))
	row.add_child(holder)
	var stamp := _canvas(_draw_stamp.bind([tr("EYES ONLY")], 15, -6.0, Color(STAMP_RED, 0.9), 2, 0, Color(0, 0, 0, 0)), Vector2(96, 44))
	stamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(stamp)
	_header.add_child(_margin(row, 16, 0, 16, 0))


func _fit_tab(holder: Control, tab: Control, title: Label) -> void:
	var full := _tab_font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 30.0
	tab.size = Vector2(minf(full, holder.size.x), 36.0)
	tab.position = Vector2(0.0, holder.size.y - 36.0)


func _tab_box() -> StyleBoxFlat:
	var box := _box(FOLDER, 0, 14.0, 0.0)
	box.corner_radius_top_left = 8
	box.corner_radius_top_right = 8
	box.anti_aliasing = true
	return box


func _build_heading(page: VBoxContainer) -> void:
	var block := _vbox(4)
	var meta := _hbox(8)
	_cycle_label = _clip_label("", _type, 11, INK_SOFT)
	meta.add_child(_cycle_label)
	_era_label = _label("", _type, 11, INK_SOFT)
	meta.add_child(_era_label)
	block.add_child(meta)
	block.add_child(_label(tr("SITUATION"), _head_wide, 24, INK))
	block.add_child(_canvas(_draw_double_rule, Vector2(0, 4)))
	page.add_child(block)


func _build_map(page: VBoxContainer) -> void:
	var card := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		card.add_theme_constant_override("margin_" + side, 6)
	var card_box := _outline(CARD, CARD_LINE, 1)
	card_box.shadow_color = Color(SHADOW, 0.18)
	card_box.shadow_size = 6
	card_box.shadow_offset = Vector2(0, 2)
	card.draw.connect(_draw_box_rotated.bind(card, 0.8, card_box))
	var stack := _vbox(5)
	_map = _canvas(_draw_map)
	_map.aspect = MAP_SIZE.x / MAP_SIZE.y
	_map.min_height = 120.0
	_map.max_height = 300.0
	stack.add_child(_map)
	var legend := _hbox(5)
	var dot := _canvas(_draw_pin_dot, Vector2(8, 8))
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	legend.add_child(dot)
	_legend_label = _clip_label("", _type, 10, INK_FAINT)
	legend.add_child(_legend_label)
	_figure_label = _label("", _type, 10, INK_FAINT)
	legend.add_child(_figure_label)
	stack.add_child(_margin(legend, 2, 0, 2, 0))
	card.add_child(stack)
	page.add_child(_margin(card, 0, 2, 0, 2))


func _build_items(page: VBoxContainer) -> void:
	for i in 2:
		var item := _vbox(4)
		var title := _label("", _head, 12, INK, true)
		item.add_child(title)
		var body := RichTextLabel.new()
		body.bbcode_enabled = true
		body.fit_content = true
		body.scroll_active = false
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.selection_enabled = false
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_font_override("normal_font", _type)
		body.add_theme_font_size_override("normal_font_size", 13)
		body.add_theme_color_override("default_color", INK)
		body.add_theme_constant_override("line_separation", 4)
		body.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		# The typed items quote the English record.
		body.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		if i == 1:
			var row := _hbox(4)
			row.add_child(body)
			_signed_stamp = _canvas(_draw_stamp.bind([tr("SIGNED"), tr("CHAIR")], 14, 9.0, Color(STAMP_RED, 0.85), 2, 4, Color(0, 0, 0, 0)),
				Vector2(74, 52))
			_signed_stamp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			row.add_child(_signed_stamp)
			item.add_child(row)
		else:
			item.add_child(body)
		page.add_child(item)
		_item_titles.append(title)
		_item_bodies.append(body)
		_item_boxes.append(item)


func _build_threat_board(page: VBoxContainer) -> void:
	var block := _vbox(3)
	block.add_child(_label(tr("THREAT BOARD"), _head, 12, INK))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 2)
	for _i in WorldState.METRIC_KEYS.size():
		var ticks := _canvas(_draw_ticks, Vector2(104, 18))
		ticks.set_meta("filled", 0)
		var cells := [_label("", _type, 12, INK), ticks, _label("", _type, 12, INK), _clip_label("", _type, 12, INK)]
		(cells[0] as Label).custom_minimum_size.x = 86
		(cells[2] as Label).custom_minimum_size.x = 30
		for cell in cells:
			_tap_metric(cell)
			grid.add_child(cell)
		_threat_cells.append(cells)
	block.add_child(grid)
	page.add_child(block)


func _build_readiness(page: VBoxContainer) -> void:
	var block := _vbox(5)
	block.add_child(_label(tr("READINESS"), _head, 12, INK))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	for entry in CURRENCIES:
		var key: String = entry[0]
		var cell := MarginContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("margin_bottom", 3)
		var row := _hbox(4)
		row.add_child(_clip_label(tr(String(entry[1])), _type, 12, INK))
		var value := _label("", _type, 12, INK)
		row.add_child(value)
		cell.add_child(row)
		cell.draw.connect(_draw_dotted_rule.bind(cell))
		var stamp := _canvas(_draw_exhausted)
		stamp.visible = false
		cell.add_child(stamp)
		grid.add_child(cell)
		_readiness_cells[key] = {"value": value, "stamp": stamp}
	block.add_child(grid)
	page.add_child(block)


func _build_sign_bar() -> void:
	var bar := _panel(_edge_box(DESK, false))
	var box := bar.get_theme_stylebox("panel") as StyleBoxFlat
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 12
	box.content_margin_bottom = 14
	_sign_button = _directive_button(CONSERVE)
	_sign_button.name = "SignButton"
	_sign_button.custom_minimum_size.y = 54
	_sign_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var boxes := {
		"normal": _box(NAVY, 6), "hover": _box(NAVY.lightened(0.08), 6), "pressed": _box(NAVY_DARK, 6),
		"disabled": _box(Color(NAVY, 0.45), 6),
	}
	_style_button(_sign_button, boxes, _head, 15, {})
	var stack := _vbox(1)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := _label(tr("SIGN NEXT DIRECTIVE"), _head_wide, 15, PAPER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	_sign_caption = _label("", _type, 11, Color(PAPER, 0.8))
	_sign_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sign_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stack.add_child(_sign_caption)
	_fill_button(_sign_button, stack, 12.0)
	bar.add_child(_sign_button)
	_footer.add_child(bar)


# --- Refresh -------------------------------------------------------------------------

func _refresh() -> void:
	_cycle_label.text = tr("CYCLE %d · %s") % [current_turn(), _year_half()]
	_era_label.text = tr("ERA %s") % EraStyle.ROMAN.get(int(snapshot.get("era", 1)), "I")
	_refresh_map()
	_refresh_items()
	_refresh_threats()
	_refresh_readiness()
	_refresh_sign()
	_sheet.queue_redraw()


## "2056 H1", the date line of the brief.
func _year_half() -> String:
	var parts := half_label().split(" ")
	return "%s %s" % [parts[1], parts[0]] if parts.size() == 2 else half_label()


func _refresh_map() -> void:
	var grid := float((snapshot.get("compute", {}) as Dictionary).get("grid_capacity_gw", BASE_GRID_GW))
	var growth := log(maxf(grid, BASE_GRID_GW) / BASE_GRID_GW) / log(2.0)
	_hub_count = clampi(3 + int(roundf(growth * 1.5)), 3, HUBS.size())
	var asi := outcome_for(SimConstants.ASI)
	var swarming := outcome_is_current(SimConstants.ASI) and String(asi.get("action", "")) == "DEPLOY_SUB_AGENT_SWARMS"
	_show_swarm = metric(WorldState.ALGORITHMIC_AUTONOMY) >= 75.0 or swarming
	var own := outcome_for(role)
	var auditing := outcome_is_current(role) and AUDIT_ACTIONS.has(String(own.get("action", "")))
	_legend_label.text = tr("audit teams deployed") if auditing else tr("datacenter hubs")
	_figure_label.text = tr("fig. 1 · cycle %d") % current_turn()
	_map.queue_redraw()


func _refresh_items() -> void:
	var items := _briefing_items()
	for i in 2:
		var has_item := i < items.size()
		_item_boxes[i].visible = has_item
		if not has_item:
			continue
		var item: Dictionary = items[i]
		_item_titles[i].text = tr("ITEM %d · %s") % [i + 1, item["title"]]
		_item_bodies[i].text = item["body"]
		if i == 1:
			_signed_stamp.visible = bool(item.get("signed", false))
	if items.is_empty():
		_item_boxes[0].visible = true
		_item_titles[0].text = tr("ITEM %d · %s") % [1, tr("NOTHING TO REPORT")]
		_item_bodies[0].text = tr("No incidents logged this cycle.")


## Up to two items: the most pressing recent event from outside the Council,
## then the Council's own latest directive, signed by the Chair.
func _briefing_items() -> Array:
	var items := []
	var best := {}
	var best_score := -1
	var latest := current_turn()
	for entry in recent_events(func(e: Dictionary) -> bool: return int(e.get("turn", 0)) >= latest - 1, 60):
		var score := _event_weight(entry)
		if score > best_score:
			best = entry
			best_score = score
	if best_score > 0:
		items.append({"title": _event_title(best), "body": _event_body(best)})
	var own := outcome_for(role)
	if not own.is_empty():
		var statement := String(own.get("public_statement", "")).strip_edges()
		var own_id := String(own.get("action", ""))
		items.append({"title": tr(String(OWN_TITLES[own_id])) if OWN_TITLES.has(own_id) else tr(String(own.get("action_name", ""))).to_upper(),
			"body": CyberPalette.escape_bbcode(statement if statement != "" else String(own.get("action_name", ""))), "signed": true})
	return items


func _event_weight(entry: Dictionary) -> int:
	var category := String(entry.get("category", ""))
	var faction := String(entry.get("faction", ""))
	if category == "ACTION":
		if faction == role:
			return 0
		var weight := int(FACTION_WEIGHT.get(faction, 10))
		return weight if String(entry.get("action", "")) != CONSERVE else 5
	if category == "THRESHOLD":
		return 50 if int(entry.get("band", 0)) >= 2 else (35 if int(entry.get("band", 0)) == 1 else 0)
	return int(CATEGORY_WEIGHT.get(category, 0))


func _event_title(entry: Dictionary) -> String:
	var category := String(entry.get("category", ""))
	match category:
		"ACTION":
			var action_id := String(entry.get("action", ""))
			return tr(String(ACTION_TITLES[action_id])) if ACTION_TITLES.has(action_id) else tr(String(entry.get("action_name", ""))).to_upper()
		"EMERGENCE":
			return tr("EMERGENT CAPABILITY")
		"PARADIGM":
			return tr("PARADIGM SHIFT")
		"THRESHOLD":
			return tr("%s THRESHOLD") % UiFormat.metric_name(String(entry.get("metric", ""))).to_upper()
		"CRISIS":
			return tr("AGENDA FORCED")
		"MILESTONE":
			return tr("AGI MILESTONE")
		"ERA":
			return tr("HARDWARE ERA")
	return category


## The event as typed by the analysts, lab and model names blacked out.
func _event_body(entry: Dictionary) -> String:
	var category := String(entry.get("category", ""))
	var faction := String(entry.get("faction", ""))
	if category == "ACTION":
		var statement := String(entry.get("statement", "")).strip_edges()
		if faction == SimConstants.ASI:
			if statement.begins_with("[unattributed]"):
				return _redacted(statement.trim_prefix("[unattributed]").strip_edges()) \
					+ " No principal on record. Suspected lineage: " + _bar("withheld pending review") + "."
			if statement == "" or statement == "[no signal]":
				return "No signal on monitored channels."
			return _redacted(statement)
		if faction == SimConstants.CEO:
			return _bar("Frontier Lab") + " announces: “" + _redacted(statement) + "”"
		var speaker := String(faction_data(faction).get("display_name", SimConstants.role_title(faction).capitalize()))
		return CyberPalette.escape_bbcode(speaker) + ": “" + _redacted(statement) + "”"
	if category == "EMERGENCE":
		return _redacted(String(entry.get("headline", ""))) + ". Capability class: " \
			+ CyberPalette.escape_bbcode(String(entry.get("name", ""))) + "."
	if category == "PARADIGM":
		return CyberPalette.escape_bbcode("%s. %s" % [entry.get("name", ""), entry.get("summary", "")])
	if category == "CRISIS":
		return _redacted(String(entry.get("text", "")).replace("the player's desk", "the Council's agenda"))
	return _redacted(String(entry.get("text", "")))


## Escapes [param text] and blacks out lab, model and ASI names.
func _redacted(text: String) -> String:
	if _names_pattern == null:
		_names_pattern = RegEx.create_from_string("(?i)(frontier lab|frontier model-\\d+|emergent asi)")
	var out := ""
	var cursor := 0
	for found in _names_pattern.search_all(text):
		out += CyberPalette.escape_bbcode(text.substr(cursor, found.get_start() - cursor))
		out += _bar(found.get_string())
		cursor = found.get_end()
	return out + CyberPalette.escape_bbcode(text.substr(cursor))


## A black redaction bar over [param text] (kept so the bar has its length).
static func _bar(text: String) -> String:
	var ink := REDACT.to_html(false)
	return "[bgcolor=#%s][color=#%s]%s[/color][/bgcolor]" % [ink, ink, CyberPalette.escape_bbcode(text)]


func _refresh_threats() -> void:
	var rows := []
	for key in WorldState.METRIC_KEYS:
		rows.append({"key": key, "value": metric(key), "danger": _danger(key, metric(key))})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["danger"]) > float(b["danger"]))
	for i in rows.size():
		var row: Dictionary = rows[i]
		var key: String = row["key"]
		var value := float(row["value"])
		var cells: Array = _threat_cells[i]
		var filled := clampi(int(roundf(value / 10.0)), 0, TICKS)
		var status := _threat_status(key, value)
		for cell in cells:
			(cell as Control).set_meta("metric_key", key)
		(cells[0] as Label).text = UiFormat.metric_name(key).to_upper()
		(cells[1] as Control).set_meta("filled", filled if not snapshot.is_empty() else 0)
		(cells[1] as Control).queue_redraw()
		(cells[2] as Label).text = "%d" % int(roundf(value)) if not snapshot.is_empty() else "—"
		(cells[3] as Label).text = tr(status) if not snapshot.is_empty() else ""
		_set_color(cells[3], STAMP_RED if status == "CRITICAL" else INK)


## Points past the warning line (negative while below it).
static func _danger(key: String, value: float) -> float:
	var info: Dictionary = WorldState.METRIC_INFO[key]
	var danger := -INF
	if info["warn_high"] != null:
		danger = maxf(danger, value - float(info["warn_high"]))
	if info["warn_low"] != null:
		danger = maxf(danger, float(info["warn_low"]) - value)
	return danger + 100.0 * WorldState.band_for(key, value)


## CRITICAL and WARNING follow the metric bands; below the warning line a
## metric within STABLE_MARGIN points of it is STABLE, otherwise NOMINAL.
static func _threat_status(key: String, value: float) -> String:
	match WorldState.band_for(key, value):
		2:
			return I18n.mark("CRITICAL")
		1:
			return I18n.mark("WARNING")
	var info: Dictionary = WorldState.METRIC_INFO[key]
	var margin := INF
	if info["warn_high"] != null:
		margin = minf(margin, float(info["warn_high"]) - value)
	if info["warn_low"] != null:
		margin = minf(margin, value - float(info["warn_low"]))
	return I18n.mark("STABLE") if margin <= STABLE_MARGIN else I18n.mark("NOMINAL")


func _refresh_readiness() -> void:
	for entry in CURRENCIES:
		var key: String = entry[0]
		var cell: Dictionary = _readiness_cells[key]
		var value := float(resources.get(key, 0.0))
		(cell["value"] as Label).text = "%.1f" % value if not resources.is_empty() else "—"
		(cell["stamp"] as Control).visible = not resources.is_empty() and value < EXHAUSTED_BELOW


func _refresh_sign() -> void:
	var action_id := suggested_action()
	var entry := action_entry(action_id)
	_sign_button.set_meta("action_id", action_id)
	_sign_button.disabled = entry.is_empty() or String(entry.get("blocked_reason", "")) != ""
	var cost: Dictionary = entry.get("cost", {})
	var title := tr(String(entry.get("name", action_definition(action_id).get("name", action_id))))
	_sign_caption.text = "%s · %s" % [title, UiFormat.format_cost(role, cost)] if not cost.is_empty() else title


# --- Drawing ------------------------------------------------------------------------

## Paper behind [param node], turned by [param degrees] like a sheet on a desk.
func _draw_paper(node: Control, degrees: float, color: Color, shadow: int) -> void:
	var box := _box(color)
	box.shadow_color = SHADOW
	box.shadow_size = shadow
	box.shadow_offset = Vector2(0, 6)
	_draw_box_rotated(node, degrees, box)


static func _draw_box_rotated(node: Control, degrees: float, box: StyleBox) -> void:
	node.draw_set_transform(node.size * 0.5, deg_to_rad(degrees), Vector2.ONE)
	node.draw_style_box(box, Rect2(-node.size * 0.5, node.size))
	node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_double_rule(canvas: Control) -> void:
	canvas.draw_line(Vector2(0, 0.5), Vector2(canvas.size.x, 0.5), INK, 1.0)
	canvas.draw_line(Vector2(0, canvas.size.y - 0.5), Vector2(canvas.size.x, canvas.size.y - 0.5), INK, 1.0)


func _draw_dotted_rule(cell: Control) -> void:
	var y := cell.size.y - 0.5
	var x := 0.0
	while x < cell.size.x:
		cell.draw_line(Vector2(x, y), Vector2(minf(x + 1.0, cell.size.x), y), DOTTED, 1.0)
		x += 3.0


## A rubber stamp: [param lines] centered in a ruled box, turned by [param degrees].
func _draw_stamp(canvas: Control, lines: Array, font_size: int, degrees: float, color: Color, border: int,
		radius: int, fill: Color) -> void:
	var font := _head_wide
	var line_height := font.get_height(font_size) * 0.92
	var width := 0.0
	for line in lines:
		width = maxf(width, font.get_string_size(String(line), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var pad := Vector2(7.0, 3.0)
	var rect := Rect2(Vector2(-(width * 0.5) - pad.x, -(line_height * lines.size() * 0.5) - pad.y),
		Vector2(width + pad.x * 2.0, line_height * lines.size() + pad.y * 2.0))
	var box := _outline(fill, color, border, radius)
	canvas.draw_set_transform(canvas.size * 0.5, deg_to_rad(degrees), Vector2.ONE)
	canvas.draw_style_box(box, rect)
	for i in lines.size():
		var text := String(lines[i])
		var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var baseline := rect.position.y + pad.y + line_height * i + font.get_ascent(font_size) * 0.95
		canvas.draw_string(font, Vector2(-text_width * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_exhausted(canvas: Control) -> void:
	# Lifted over the value, as if stamped across the line above.
	var origin := Vector2(canvas.size.x - 38.0, -6.0)
	var font := _head_wide
	var text := tr("EXHAUSTED")
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var rect := Rect2(Vector2(-width * 0.5 - 4.0, -9.0), Vector2(width + 8.0, 17.0))
	canvas.draw_set_transform(origin, deg_to_rad(-8.0), Vector2.ONE)
	canvas.draw_style_box(_outline(Color(PAPER, 0.6), STAMP_RED, 1, 0), rect)
	canvas.draw_string(font, Vector2(-width * 0.5, rect.position.y + 2.0 + font.get_ascent(11)), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, STAMP_RED)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Ten typed squares, filled to the metric's value.
func _draw_ticks(canvas: Control) -> void:
	var filled := int(canvas.get_meta("filled", 0))
	var side := 8.0
	var top := floorf((canvas.size.y - side) * 0.5)
	for i in TICKS:
		var rect := Rect2(Vector2(1.0 + i * (side + 1.5), top), Vector2(side, side))
		if i < filled:
			canvas.draw_rect(rect, INK)
		else:
			canvas.draw_rect(rect.grow(-0.5), INK, false, 1.0)


func _draw_pin_dot(canvas: Control) -> void:
	canvas.draw_circle(canvas.size * 0.5, 4.0, NAVY)


func _draw_map(canvas: Control) -> void:
	var area := canvas.size
	var unit := area.x / MAP_SIZE.x
	canvas.draw_set_transform(area * 0.5, deg_to_rad(0.8), Vector2.ONE)
	var origin := -area * 0.5
	canvas.draw_texture_rect(_land_texture(), Rect2(origin, area), false)
	var pin := clampf(unit, 0.9, 1.5)
	for i in _hub_count:
		var hub: Array = HUBS[i]
		var at := origin + _project(float(hub[0]), float(hub[1])) * unit
		canvas.draw_circle(at, 4.2 * pin, NAVY)
		canvas.draw_arc(at, 4.2 * pin, 0.0, TAU, 16, NAVY_DARK, 0.8, true)
		canvas.draw_circle(at - Vector2(1.3, 1.3) * pin, 1.3 * pin, Color(1, 1, 1, 0.75))
	if _show_swarm:
		_draw_swarm_ring(canvas, origin, unit)
	_draw_paper_clip(canvas, origin + Vector2(8, -24))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Map units for a latitude and longitude.
static func _project(lat: float, lon: float) -> Vector2:
	return Vector2((lon + 180.0) / 360.0 * MAP_SIZE.x, (MAP_TOP_LAT - lat) / MAP_LAT_SPAN * MAP_SIZE.y)


func _draw_swarm_ring(canvas: Control, origin: Vector2, unit: float) -> void:
	var autonomy := metric(WorldState.ALGORITHMIC_AUTONOMY)
	var grow := clampf((autonomy - 75.0) / 25.0, 0.0, 1.0)
	var radii := Vector2(26.0 + 8.0 * grow, 15.0 + 5.0 * grow) * unit
	var center := origin + SWARM_SPOT * unit
	var tilt := deg_to_rad(-12.0)
	var points := PackedVector2Array()
	for i in 49:
		var angle := TAU * float(i) / 48.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y).rotated(tilt))
	_dashed_polyline(canvas, points, PENCIL, 1.6, 5.0 * unit, 3.0 * unit)
	var tail := _bezier(origin + Vector2(226, 128) * unit, origin + Vector2(214, 138) * unit,
		origin + Vector2(200, 142) * unit, origin + Vector2(186, 140) * unit, 12)
	canvas.draw_polyline(tail, PENCIL, 1.3, true)
	var font_size := int(clampf(11.0 * unit, 10.0, 14.0))
	var text := tr("swarm traffic, no owner")
	var width := _type.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := origin + Vector2(184, 146) * unit - Vector2(width, 0)
	canvas.draw_string(_type, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, PENCIL)


func _draw_paper_clip(canvas: Control, at: Vector2) -> void:
	var points := PackedVector2Array([at + Vector2(8, 50), at + Vector2(8, 10)])
	for i in 13:
		points.append(at + Vector2(13, 10) + Vector2.from_angle(PI + PI * float(i) / 12.0) * 5.0)
	points.append(at + Vector2(18, 44))
	for i in 13:
		points.append(at + Vector2(15, 44) + Vector2.from_angle(PI * float(i) / 12.0) * 3.0)
	points.append(at + Vector2(12, 14))
	canvas.draw_polyline(points, CLIP, 2.0, true)


## The paper map (sea, graticule and coastlines), rasterized once at 2x.
static func _land_texture() -> Texture2D:
	if _map_texture == null:
		var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"716\" height=\"352\" viewBox=\"0 0 358 176\">"
		svg += "<rect width=\"358\" height=\"176\" fill=\"#E9E0C9\"/>"
		svg += "<path d=\"M0 44h358M0 88h358M0 132h358M60 0v176M119 0v176M179 0v176M239 0v176M298 0v176\" stroke=\"#D5C9AB\" stroke-width=\".8\"/>"
		svg += "<path d=\"%s\" fill=\"#D9CCAA\" stroke=\"#6B5E45\" stroke-width=\".7\" stroke-linejoin=\"round\"/></svg>" % LAND_PATH
		_map_texture = Glyphs.svg_texture(svg)
	return _map_texture


## Coastlines of the paper map (map units, 358x176).
const LAND_PATH := (
	"M112 173 114 174 110 175 105 172 108 173 110 171zM324 156 326 156 326 159 324 160 323 157zM351 156 352 "
	+ "157 351 160 350 161 347 164 345 163 345 162zM353 150 355 152 357 152 353 157 353 155 352 154 353 152 351 "
	+ "148zM229 120 229 123 228 123 226 134 226 135 224 136 223 135 222 132 223 128 223 125 223 124 226 122 228 "
	+ "118zM322 121 324 122 325 127 327 129 331 137 331 144 328 152 325 154 323 152 322 153 319 152 318 150 316 "
	+ "149 316 148 315 149 316 146 314 148 313 145 310 144 304 145 302 147 298 147 296 149 293 147 294 144 292 "
	+ "137 292 136 293 137 292 134 293 131 293 132 295 130 299 128 301 124 302 125 304 121 305 121 308 122 309 "
	+ "119 311 118 311 117 314 119 315 118 314 122 318 126 320 122 320 117zM287 111 289 111 294 113 293 114 287 "
	+ "113 284 111 284 110zM312 104 313 106 314 107 315 105 317 105 323 108 326 110 325 112 329 116 326 116 323 "
	+ "112 321 115 317 113 316 113 317 112 316 110 312 107 311 108 310 106 312 105 310 105 309 104 311 103zM304 "
	+ "101 302 102 299 102 299 104 302 103 300 105 301 109 301 109 301 108 300 108 299 106 298 110 297 106 298 "
	+ "102 299 101 301 101zM284 110 283 110 281 108 274 95 276 96 282 102 282 103 285 106zM296 100 297 101 296 "
	+ "101 295 108 289 106 287 101 291 98 295 93 298 95 296 98zM305 91 304 95 303 94 302 92 300 93 302 91 302 "
	+ "92 304 91 304 90zM260 94 259 95 258 94 259 90 260 93zM300 78 301 78 301 80 300 84 302 84 302 86 301 85 "
	+ "299 84 299 83 298 83 298 81zM107 76 109 77 111 78 109 78 108 79 105 79 105 78 107 78 106 77zM100 73 105 "
	+ "76 102 76 102 76 101 74 98 73 94 74 97 72zM319 54 318 56 315 57 314 58 313 57 309 58 310 59 310 61 308 "
	+ "61 308 59 311 56 314 56 315 53 316 54 318 52 319 48 320 48 320 50zM322 44 324 44 324 46 321 47 320 46 "
	+ "319 48 318 48 320 43zM56 39 54 38 51 36 54 36zM123 36 123 37 126 38 126 41 125 41 125 40 124 41 123 40 "
	+ "120 40 122 36 123 35zM322 36 323 38 321 38 321 40 322 42 321 41 320 42 320 32 321 31zM172 34 169 34 170 "
	+ "33 169 32 171 30 173 31zM176 25 175 27 177 27 176 29 177 29 179 33 181 33 180 35 174 37 176 35 174 34 "
	+ "175 34 174 32 176 32 176 32 174 30 174 29 173 30 173 28 174 25zM94 16 99 19 96 18 94 20 92 19 94 16zM165 "
	+ "15 165 17 160 19 156 18 157 18 155 17 157 17 155 16 157 15 159 16zM5 15 8 15 10 16 7 16 7 18 2 17 1 16 0 "
	+ "16 0 17 0 12 5 14zM89 11 89 13 90 11 92 14 94 12 94 11 97 11 98 12 97 13 98 14 96 15 94 15 92 17 86 21 "
	+ "85 25 86 25 87 27 97 30 97 32 100 35 101 33 100 31 103 28 101 25 102 24 101 21 106 20 108 22 110 22 110 "
	+ "25 112 26 115 23 118 28 118 28 122 31 124 34 119 36 113 36 108 41 114 38 115 38 114 39 115 42 118 42 119 "
	+ "41 120 42 114 45 113 44 115 43 112 43 109 46 109 48 106 49 107 49 105 49 105 51 104 51 104 52 103 54 103 "
	+ "51 103 52 102 52 104 56 98 61 99 69 98 68 95 63 94 64 93 63 90 63 90 64 89 64 86 63 83 65 82 73 83 77 85 "
	+ "79 87 78 89 77 89 75 92 74 91 82 94 81 96 82 96 88 98 91 100 90 103 91 105 88 108 86 108 87 107 87 108 "
	+ "91 108 88 109 86 111 89 114 89 117 88 117 89 122 95 125 95 128 97 129 100 129 103 131 103 131 104 131 "
	+ "103 134 104 135 106 139 106 144 109 144 112 144 114 141 120 140 126 138 131 137 133 135 133 132 135 130 "
	+ "140 125 148 123 148 121 147 123 151 120 153 117 153 117 156 114 156 114 158 116 158 114 160 114 162 112 "
	+ "162 112 163 114 164 113 166 110 169 111 171 109 172 108 173 104 171 104 166 105 164 104 164 105 160 106 "
	+ "161 107 158 106 158 106 159 105 159 106 154 106 151 108 145 109 128 108 125 103 122 100 112 98 111 98 "
	+ "109 100 106 98 105 99 104 102 97 101 92 100 91 99 93 94 89 92 85 88 84 85 81 83 82 76 78 74 76 74 73 66 "
	+ "61 65 61 65 63 70 72 70 72 67 70 67 68 65 66 65 65 62 59 59 57 55 49 56 43 55 39 57 39 57 41 57 38 52 36 "
	+ "52 34 51 33 46 26 33 22 32 23 32 24 28 25 29 22 26 24 27 25 26 26 21 29 15 31 22 27 23 25 18 25 18 24 16 "
	+ "24 14 22 15 20 19 19 18 18 19 17 15 18 12 16 15 15 18 16 13 13 18 10 23 9 43 12 50 10 51 11 52 10 54 11 "
	+ "55 10 55 11 58 11 64 12 66 13 64 13 70 13 71 14 72 13 71 13 71 12 73 12 78 14 81 13 82 12 83 13 83 14 85 "
	+ "12 83 10 83 9 84 8 87 9 88 10 87 11zM65 6 65 7 69 7 70 7 71 8 71 6 73 6 75 9 78 11 77 11 77 12 74 12 66 "
	+ "12 64 12 62 11 67 10 62 10 61 9 64 9 60 8 62 7zM93 6 94 7 97 6 99 7 99 8 102 7 105 9 107 8 111 10 112 12 "
	+ "111 12 117 15 117 16 115 17 113 15 111 15 115 19 114 20 111 19 113 21 108 20 105 17 102 18 101 18 102 17 "
	+ "105 16 106 13 100 10 98 11 91 10 90 10 91 9 90 9 89 8 91 6 94 6zM79 5 82 6 81 7 83 7 83 8 80 9 77 7 79 7 "
	+ "78 6zM86 7 84 8 84 5 89 5zM59 9 57 9 54 8 56 6 55 5 62 5 64 6 60 7zM323 3 322 4 317 4 315 4 317 2zM81 2 "
	+ "82 2 81 4 77 3 77 2zM71 2 74 3 73 4 66 5 68 4 62 4 64 2 71 3 69 2zM236 10 230 9 234 4 240 2 247 2 237 5 "
	+ "234 7 234 8zM85 1 88 2 90 3 98 3 100 4 91 5 87 4 86 2 82 2zM63 0 63 2 57 2 61 1zM285 1 293 3 288 5 291 5 "
	+ "292 6 294 6 302 7 302 6 305 6 307 7 307 8 310 9 311 8 318 9 317 7 319 7 328 8 331 9 337 9 339 11 346 11 "
	+ "348 12 349 12 349 10 357 11 358 12 358 17 355 18 357 20 352 21 348 24 347 23 342 24 340 26 341 27 340 30 "
	+ "338 31 338 33 337 33 335 35 334 30 334 28 342 22 343 20 338 23 337 21 335 22 332 24 333 25 329 25 329 24 "
	+ "328 24 320 25 313 31 316 32 318 31 320 34 318 39 316 42 313 45 312 46 311 46 306 50 308 54 307 56 305 57 "
	+ "304 54 305 54 303 52 304 50 303 50 299 51 300 49 300 49 296 51 296 52 297 53 301 53 297 57 300 61 300 65 "
	+ "297 70 294 73 289 74 289 76 288 74 287 74 284 77 288 85 288 87 284 91 283 89 282 88 281 86 279 86 279 85 "
	+ "279 85 278 90 281 95 283 101 280 99 279 94 277 91 277 92 277 87 276 80 274 82 273 81 273 79 270 73 269 "
	+ "72 269 74 265 74 265 76 261 81 259 82 258 89 256 92 252 81 251 74 249 75 245 69 240 70 236 69 235 67 233 "
	+ "68 230 66 229 63 227 63 230 70 230 68 230 69 231 71 233 71 235 68 236 71 238 73 237 76 236 78 234 80 231 "
	+ "81 231 82 227 84 222 86 221 80 218 74 217 71 213 66 214 64 213 66 211 63 214 72 216 74 216 78 222 86 221 "
	+ "87 223 89 230 87 230 88 226 97 219 106 218 109 218 111 219 117 220 122 218 124 214 128 214 134 211 136 "
	+ "211 140 207 145 205 147 201 147 199 148 197 147 197 144 194 138 193 131 191 126 193 117 191 109 188 104 "
	+ "188 98 187 96 185 97 183 94 181 94 177 96 174 96 172 97 170 96 167 93 162 86 161 83 163 79 162 74 165 68 "
	+ "169 63 170 60 173 55 177 56 180 54 188 53 190 54 189 58 198 63 199 60 200 59 208 62 210 61 213 62 215 57 "
	+ "215 54 211 55 206 54 205 51 208 48 210 48 212 47 217 49 219 49 220 47 215 43 218 40 214 42 215 43 213 44 "
	+ "211 43 212 42 210 41 207 47 208 49 205 50 204 49 203 49 203 50 202 50 203 53 202 53 202 55 201 55 198 50 "
	+ "198 48 192 42 191 43 192 45 197 50 196 49 196 51 195 53 194 50 188 44 185 46 182 46 182 47 180 49 179 52 "
	+ "177 54 175 54 174 55 173 54 170 54 170 46 171 45 177 45 178 45 178 42 174 39 177 39 177 37 178 38 180 37 "
	+ "184 33 187 32 188 31 187 27 190 27 190 28 189 30 190 32 191 31 193 32 197 30 199 31 200 30 200 27 201 27 "
	+ "203 28 203 26 202 25 208 24 207 23 202 24 200 23 200 19 204 17 203 16 201 16 200 18 197 20 196 22 198 24 "
	+ "196 25 195 29 192 30 189 24 187 26 185 25 184 21 189 18 194 13 198 11 202 10 203 9 207 9 210 10 209 10 "
	+ "210 11 211 11 219 13 220 15 219 15 212 15 214 16 214 18 216 19 215 17 216 17 218 18 219 17 219 16 221 15 "
	+ "223 16 223 15 222 12 225 13 226 14 224 14 225 15 232 12 233 12 232 13 237 12 239 13 240 12 239 11 239 11 "
	+ "247 13 248 12 246 11 245 9 248 7 251 7 250 9 251 10 251 12 252 13 250 15 251 16 254 13 254 12 252 11 253 "
	+ "10 252 9 253 8 253 7 254 7 254 9 255 9 254 8 256 8 260 8 259 6 265 5 265 5 266 4 279 2 283 0zM79 0 74 0 "
	+ "75 -1 74 -2zM283 0 278 0 281 -2 284 -1zM197 -2 200 -1 198 -1 196 2 195 2 189 -2zM204 -3 206 -3 202 -2 "
	+ "196 -3zM278 -1 273 -1 270 -3 274 -4 279 -2zM92 -2 94 -2 89 0 87 0 86 -1 86 -2 83 -3 85 -4 87 -4zM111 -7 "
	+ "117 -6 112 -5 114 -5 108 -2 103 -2 104 -2 103 -1 104 -1 100 1 102 2 99 2 90 2 90 1 92 1 91 0 94 1 92 0 "
	+ "94 -2 93 -3 98 -3 92 -3 88 -5 100 -7zM152 -7 158 -6 148 -5 156 -5 157 -5 156 -4 163 -5 167 -4 159 -3 161 "
	+ "-3 159 -1 159 0 161 1 157 2 159 2 160 4 158 4 160 5 158 5 158 6 156 6 157 8 154 7 157 9 157 10 156 10 "
	+ "154 9 154 10 153 10 157 10 151 13 147 13 145 15 139 16 136 20 136 24 131 23 128 19 125 14 128 11 125 11 "
	+ "125 9 128 10 123 8 125 7 121 3 111 3 108 1 113 1 106 0 114 -2 111 -3 117 -4 117 -5 129 -6 135 -5 132 -6 "
	+ "136 -7z"
)
