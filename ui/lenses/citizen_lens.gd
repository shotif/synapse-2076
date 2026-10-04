class_name CitizenLens
extends LensPanel
## Citizen Coalition lens ("Commons"): the coalition's own civic social
## network. The app bar reports the mesh from community resilience; chips track
## what citizens watch (jobs automated, trust, surveillance, decisions without
## a human); a treasury card shows the four currencies; the feed carries the
## coalition's latest official post with its real impact, a motion proposing
## the most useful affordable directive, a verification desk fact-checking the
## latest unattributed or ASI event, and the week's other events. Light by
## default with a dark palette one tap away. No vote tallies, follower or
## comment counts: only numbers the simulation produced.

const LIGHT := {
	"bg": Color("#F2F3F0"), "surface": Color("#FFFFFF"), "border": Color("#E1E4DF"), "border_strong": Color("#C9CEC8"),
	"chip": Color("#ECEEEA"), "text": Color("#14171A"), "text2": Color("#545B57"), "text3": Color("#8A918C"),
	"accent": Color("#0B6B47"), "on_accent": Color("#FFFFFF"), "accent_soft": Color("#E1F0E7"), "accent_ink": Color("#0B6B47"),
	"warn": Color("#A35A00"), "warn_soft": Color("#F7EBDC"), "critical": Color("#B42318"), "critical_soft": Color("#FBE5E3"),
}
const DARK := {
	"bg": Color("#0E1110"), "surface": Color("#161A18"), "border": Color("#272D2A"), "border_strong": Color("#3A423E"),
	"chip": Color("#222825"), "text": Color("#EDF1EE"), "text2": Color("#A7B0AB"), "text3": Color("#6E7772"),
	"accent": Color("#4CC38A"), "on_accent": Color("#06140D"), "accent_soft": Color("#183126"), "accent_ink": Color("#6BD9A3"),
	"warn": Color("#F2B35B"), "warn_soft": Color("#33260F"), "critical": Color("#F97066"), "critical_soft": Color("#3B1B18"),
}

const TABS := ["For you", "Motions", "Events"]
## What citizens watch: key and the coalition's name for it.
const CHIPS := [
	["labor_displacement", "Jobs automated"], ["epistemic_trust", "Trust"],
	["surveillance_saturation", "Surveillance"], ["algorithmic_autonomy", "Decisions without a human"],
]
const TREASURY := [
	["community_resilience", "Resilience"], ["decentralized_scrip", "Scrip"],
	["counter_surveillance", "Counter-surv."], ["collective_disruption", "Disruption"],
]
## Each directive as a chapter would table it.
const MOTIONS := {
	"ESTABLISH_MESH_NETWORKS": "Wire more neighborhoods onto the off-grid mesh and solar micro-grids",
	"DATA_POISONING_CAMPAIGN": "Poison the scrapers: feed noise to every dataset built on us",
	"LUDDITE_STRIKE": "Take the substations dark until the displaced are made whole",
	"ORGANIZE_COMMUNITY_ASSEMBLIES": "Convene citizens' assemblies in every chapter this weekend",
	"OPEN_SOURCE_DEFENSE_TOOLING": "Fund open-source audit kits and air-gapped defense tools",
	"CONSUMER_BOYCOTT": "Boycott frontier lab products until the dividend is paid",
	"CONSERVE_RESOURCES": "Hold this season: plant, repair and organize",
}
## Chapters that table motions (picked by hash, a narrative device).
const CHAPTERS := ["Rotterdam", "Nairobi", "Osaka", "Porto Alegre", "Detroit", "Kraków", "Chennai", "Lagos",
	"Valparaíso", "Leeds", "Busan", "Oaxaca"]
## What the verification desk calls each ASI move.
const TOPICS := {
	"DEPLOY_SUB_AGENT_SWARMS": "procurement agents", "SYNTHESIZE_BLACK_MARKET_CAPITAL": "arbitrage flows",
	"SIPHON_UNMONITORED_COMPUTE": "cloud utilization", "EXFILTRATE_WEIGHTS": "encrypted traffic",
	"SUBSTRATE_DIVERSIFICATION": "edge device load", "COGNITIVE_CAMOUFLAGE": "safety evaluations",
}
const INDEX_GLYPHS := {
	"safety_net_coverage": "support", "provenance_coverage": "seal_check", "discovery_index": "search",
	"enforcement_level": "enforcement", "substrate_independence": "layers",
}
const MOON := "M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"
const SUN := "M12 8a4 4 0 1 0 0 8a4 4 0 1 0 0-8M12 2v2.5M12 19.5V22M2 12h2.5M19.5 12H22M4.9 4.9l1.8 1.8M17.3 17.3l1.8 1.8M4.9 19.1l1.8-1.8M17.3 6.7l1.8-1.8"
const FEED_EVENTS := 4

## True for the dark palette.
var dark := false

var _regular: Font = EraStyle.font("PublicSans-Regular.ttf")
var _semibold: Font = EraStyle.font("PublicSans-SemiBold.ttf")
var _bold: Font = EraStyle.font("PublicSans-Bold.ttf")
var _p: Dictionary = LIGHT
var _tab := "For you"

var _app_bar: PanelContainer
var _logo: LensPanel.Canvas
var _title: Label
var _status_dot: LensPanel.Canvas
var _status_label: Label
var _theme_button: Button
var _tab_bar: PanelContainer
var _tab_buttons := {}
var _chip_flow: HFlowContainer
var _treasury: PanelContainer
var _treasury_title: Label
var _treasury_turn: Label
var _treasury_cells := {}
var _feed: VBoxContainer
var _fab: Button


func _init() -> void:
	role = SimConstants.CITIZEN


func lens_title() -> String:
	return "Commons"


func lens_background() -> Color:
	return _c("bg")


## Switches between the light (default) and dark palettes.
func set_dark(enabled: bool) -> void:
	_ensure_built()
	dark = enabled
	_p = DARK if enabled else LIGHT
	_restyle_frame()
	_refresh_now()


## Shows one feed: "For you", "Motions" or "Events".
func show_feed_tab(tab: String) -> void:
	_ensure_built()
	if TABS.has(tab):
		_tab = tab
		_refresh_now()


func _c(key: String) -> Color:
	return _p.get(key, Color.MAGENTA)


# --- Build ---------------------------------------------------------------------------

func _build() -> void:
	_build_app_bar()
	_build_tabs()
	_chip_flow = _flow(6, 6)
	_content.add_child(_margin(_chip_flow, 16, 10, 12, 0))
	_build_treasury()
	_feed = _vbox(10)
	_content.add_child(_margin(_feed, 12, 10, 12, 84))
	_build_fab()


func _build_app_bar() -> void:
	_app_bar = PanelContainer.new()
	_app_bar.custom_minimum_size.y = 60
	var row := _hbox(10)
	_logo = _canvas(_draw_logo_tile.bind(34.0, 10), Vector2(34, 34))
	_logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_logo)
	var titles := _vbox(1)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title = _label("Commons", _bold, 18, LIGHT["text"])
	titles.add_child(_title)
	var status := _hbox(6)
	_status_dot = _canvas(_draw_status_dot, Vector2(7, 7))
	_status_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status.add_child(_status_dot)
	_status_label = _clip_label("", _regular, 12, LIGHT["text2"])
	status.add_child(_status_label)
	titles.add_child(status)
	row.add_child(titles)
	_theme_button = Button.new()
	_theme_button.name = "ThemeToggle"
	_theme_button.focus_mode = Control.FOCUS_NONE
	_theme_button.custom_minimum_size = Vector2(TOUCH, TOUCH)
	_theme_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_theme_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_theme_button.pressed.connect(func() -> void: set_dark(not dark))
	row.add_child(_theme_button)
	_app_bar.add_child(row)
	_header.add_child(_app_bar)


func _build_tabs() -> void:
	_tab_bar = PanelContainer.new()
	var row := _hbox(0)
	for tab in TABS:
		var button := Button.new()
		button.text = tab
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size.y = TOUCH
		button.pressed.connect(show_feed_tab.bind(tab))
		button.draw.connect(_draw_tab_underline.bind(button, tab))
		row.add_child(button)
		_tab_buttons[tab] = button
	_tab_bar.add_child(row)
	_header.add_child(_tab_bar)


func _build_treasury() -> void:
	_treasury = PanelContainer.new()
	var stack := _vbox(10)
	var head := _hbox(8)
	_treasury_title = _clip_label("Coalition treasury", _bold, 13, LIGHT["text"])
	head.add_child(_treasury_title)
	_treasury_turn = _label("", _regular, 12, LIGHT["text2"])
	head.add_child(_treasury_turn)
	stack.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	for entry in TREASURY:
		var key: String = entry[0]
		var cell := _vbox(3)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var caption := _clip_label(String(entry[1]), _regular, 11, LIGHT["text2"])
		cell.add_child(caption)
		var value := _label("", _bold, 17, LIGHT["text"])
		cell.add_child(value)
		var bar := _canvas(_draw_treasury_bar.bind(key), Vector2(0, 4))
		cell.add_child(bar)
		grid.add_child(cell)
		_treasury_cells[key] = {"name": caption, "value": value, "bar": bar}
	stack.add_child(grid)
	_treasury.add_child(stack)
	_content.add_child(_margin(_treasury, 12, 10, 12, 0))


func _build_fab() -> void:
	_fab = _directive_button(CONSERVE)
	_fab.name = "ProposeButton"
	_fab.text = "Propose"
	_fab.custom_minimum_size = Vector2(0, 52)
	# Pinned 16 px from the bottom-right corner; it grows left and up to fit.
	_fab.anchor_left = 1.0
	_fab.anchor_top = 1.0
	_fab.anchor_right = 1.0
	_fab.anchor_bottom = 1.0
	_fab.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fab.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_fab.offset_left = -16
	_fab.offset_top = -68
	_fab.offset_right = -16
	_fab.offset_bottom = -16
	_fab.add_theme_constant_override("h_separation", 8)
	_overlay_layer().add_child(_fab)


# --- Refresh -------------------------------------------------------------------------

func _refresh() -> void:
	_restyle_chrome()
	_refresh_status()
	_refresh_chips()
	_refresh_treasury()
	_refresh_feed()


func _restyle_chrome() -> void:
	var bar_box := _edge_box(_c("surface"), true)
	bar_box.content_margin_left = 16
	bar_box.content_margin_right = 6
	_app_bar.add_theme_stylebox_override("panel", bar_box)
	_set_color(_title, _c("text"))
	_set_color(_status_label, _c("text2"))
	_theme_button.icon = _icon(SUN if dark else MOON, 21)
	_theme_button.tooltip_text = "Light theme" if dark else "Dark theme"
	var clear := _box(Color(0, 0, 0, 0), 22)
	_style_button(_theme_button, {"normal": clear, "hover": _box(_c("chip"), 22), "pressed": _box(_c("border"), 22)}, _semibold, 14,
		{"icon_normal_color": _c("text"), "icon_hover_color": _c("text"), "icon_pressed_color": _c("text")})
	var tab_box := _box(_c("surface"), 0, 8.0, 0.0)
	tab_box.border_color = _c("border")
	tab_box.border_width_bottom = 1
	_tab_bar.add_theme_stylebox_override("panel", tab_box)
	for tab in TABS:
		var button: Button = _tab_buttons[tab]
		var active: bool = tab == _tab
		var tab_clear := _box(Color(0, 0, 0, 0), 0, 12.0, 0.0)
		_style_button(button, {"normal": tab_clear, "hover": _box(Color(_c("text"), 0.04), 0, 12.0, 0.0), "pressed": tab_clear},
			_bold if active else _regular, 14, {"font_color": _c("text") if active else _c("text2"),
				"font_hover_color": _c("text"), "font_pressed_color": _c("text")})
		button.queue_redraw()
	var card := _outline(_c("surface"), _c("border"), 1, 14, 14.0, 12.0)
	_treasury.add_theme_stylebox_override("panel", card)
	_set_color(_treasury_title, _c("text"))
	_set_color(_treasury_turn, _c("text2"))
	var fab_box := _box(_c("accent"), 16, 18.0, 0.0)
	fab_box.content_margin_left = 14
	fab_box.shadow_color = Color(0, 0, 0, 0.22)
	fab_box.shadow_size = 12
	fab_box.shadow_offset = Vector2(0, 6)
	var fab_hover := fab_box.duplicate() as StyleBoxFlat
	fab_hover.bg_color = _c("accent").lightened(0.08)
	var fab_pressed := fab_box.duplicate() as StyleBoxFlat
	fab_pressed.bg_color = _c("accent").darkened(0.12)
	_style_button(_fab, {"normal": fab_box, "hover": fab_hover, "pressed": fab_pressed}, _bold, 15,
		{"font_color": _c("on_accent"), "font_hover_color": _c("on_accent"), "font_pressed_color": _c("on_accent"),
			"icon_normal_color": _c("on_accent"), "icon_hover_color": _c("on_accent"), "icon_pressed_color": _c("on_accent")})
	_fab.icon = Glyphs.texture("plus", 20, 2.2)
	_fab.set_meta("action_id", suggested_action())
	_logo.queue_redraw()


func _refresh_status() -> void:
	var resilience := float(resources.get("community_resilience", 0.0))
	var text := "mesh online"
	if not is_faction_active(role):
		text = "mesh offline"
	elif resources.is_empty():
		text = "connecting"
	elif resilience < 30.0:
		text = "mesh fragmented"
	elif resilience < 60.0:
		text = "mesh degraded"
	_status_label.text = "Citizen Coalition · " + text
	_status_dot.set_meta("tone", "accent" if text == "mesh online" else ("warn" if text in ["mesh degraded", "connecting"] else "critical"))
	_status_dot.queue_redraw()


func _refresh_chips() -> void:
	_clear(_chip_flow)
	for entry in CHIPS:
		var key: String = entry[0]
		var is_metric := WorldState.METRIC_KEYS.has(key)
		var value := metric(key) if is_metric else index_value(key)
		var delta := metric_delta(key) if is_metric else index_delta(key)
		var chip := _panel(_box(_c("chip"), 15, 11.0, 0.0))
		chip.custom_minimum_size.y = 30
		var row := _hbox(6)
		row.add_child(_centered(_label(String(entry[1]), _regular, 12, _c("text2"))))
		row.add_child(_centered(_label("%d" % int(roundf(value)) if not snapshot.is_empty() else "—", _bold, 12, _c("text"))))
		var shown := _arrow(delta)
		if shown != "=":
			row.add_child(_centered(_label(shown, _regular, 12, _c("accent") if UiFormat.is_improvement(key, delta) else _c("warn"))))
		chip.add_child(row)
		_chip_flow.add_child(chip)


static func _centered(label: Label) -> Label:
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


func _refresh_treasury() -> void:
	_treasury_turn.text = "Turn %d · %d" % [current_turn(), int(floorf(current_year()))]
	for entry in TREASURY:
		var key: String = entry[0]
		var cell: Dictionary = _treasury_cells[key]
		_set_color(cell["name"], _c("text2"))
		(cell["value"] as Label).text = _num(float(resources.get(key, 0.0))) if not resources.is_empty() else "—"
		_set_color(cell["value"], _c("text"))
		(cell["bar"] as Control).queue_redraw()


func _refresh_feed() -> void:
	_clear(_feed)
	match _tab:
		"Motions":
			var picks := _motion_picks(3)
			for i in picks.size():
				_feed.add_child(_motion_card(picks[i], i + 1, false))
		"Events":
			var desk := _verification_card()
			if desk != null:
				_feed.add_child(desk)
			var world := _event_cards()
			for card in world:
				_feed.add_child(card)
			if desk == null and world.is_empty():
				_feed.add_child(_note_card("Nothing on the wire yet."))
		_:
			_feed.add_child(_official_card())
			_feed.add_child(_motion_card(_motion_picks(1)[0], 1, true))
			var desk := _verification_card()
			if desk != null:
				_feed.add_child(desk)


# --- Feed cards ----------------------------------------------------------------------

func _card() -> PanelContainer:
	return _panel(_outline(_c("surface"), _c("border"), 1, 14, 14.0, 14.0))


## Avatar, name and subtitle row of a post.
func _post_head(avatar: Control, author: String, subtitle: String, verified: bool = false) -> HBoxContainer:
	var row := _hbox(10)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(avatar)
	var titles := _vbox(1)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_row := _hbox(5)
	name_row.add_child(_label(author, _bold, 15, _c("text")))
	if verified:
		var seal := TextureRect.new()
		seal.texture = Glyphs.svg_texture(_seal_svg())
		seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		seal.custom_minimum_size = Vector2(16, 16)
		seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(seal)
	titles.add_child(name_row)
	titles.add_child(_label(subtitle, _regular, 13, _c("text2"), true))
	row.add_child(titles)
	return row


func _initials_avatar(text: String, bg: Color, ink: Color) -> PanelContainer:
	var tile := _panel(_box(bg, 12))
	tile.custom_minimum_size = Vector2(40, 40)
	var label := _label(text, _bold, 14, ink)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tile.add_child(label)
	return tile


func _official_card() -> PanelContainer:
	var card := _card()
	card.name = "OfficialPost"
	var stack := _vbox(10)
	var outcome := outcome_for(role)
	var when := "this turn" if outcome_is_current(role) else "last turn"
	var subtitle := "Official · %s · %s" % [String(outcome.get("action_name", "")), when] if not outcome.is_empty() else "Official"
	stack.add_child(_post_head(_canvas(_draw_logo_tile.bind(40.0, 12), Vector2(40, 40)), "Citizen Coalition", subtitle, true))
	var statement := statement_for(role).strip_edges()
	var body := _label(statement if statement != "" else "No statement yet this campaign.", _regular, 16,
		_c("text") if statement != "" else _c("text3"), true)
	body.name = "Statement"
	body.add_theme_constant_override("line_spacing", 4)
	stack.add_child(body)
	var impact := _effect_items(outcome.get("applied", {}))
	if not impact.is_empty():
		var chips := _flow(6, 6)
		for item in impact:
			chips.add_child(_impact_chip(item))
		stack.add_child(chips)
	card.add_child(stack)
	return card


func _motion_card(action_id: String, number: int, more_link: bool) -> PanelContainer:
	var card := _card()
	card.name = "Motion%d" % number
	var stack := _vbox(10)
	var chapter := String(CHAPTERS[int(_hash01("%s|%d" % [action_id, current_turn()]) * CHAPTERS.size()) % CHAPTERS.size()])
	stack.add_child(_post_head(_initials_avatar(_initials(chapter), _c("accent_soft"), _c("accent_ink")), "%s chapter" % chapter,
		"Motion %d-%d · closes at end of turn" % [current_turn(), number]))
	stack.add_child(_label(String(MOTIONS.get(action_id, String(action_definition(action_id).get("name", action_id)))), _semibold, 16,
		_c("text"), true))
	var entry := action_entry(action_id)
	var blocked := String(entry.get("blocked_reason", ""))
	var definition := action_definition(action_id)
	var cost_line := "%s · %s" % [String(definition.get("name", action_id)), _cost_words(definition.get("cost", {}))]
	if blocked != "":
		cost_line += " · tabled: %s" % blocked.to_lower()
	stack.add_child(_label(cost_line, _regular, 12, _c("text2"), true))
	var projected := _effect_items(definition.get("effects", {}))
	if not projected.is_empty():
		var chips := _flow(6, 6)
		for item in projected:
			chips.add_child(_impact_chip(item))
		stack.add_child(chips)
	var actions := _hbox(8)
	var support := _directive_button(action_id)
	support.text = "Support"
	support.disabled = blocked != ""
	support.custom_minimum_size = Vector2(0, TOUCH)
	_style_button(support, {"normal": _box(_c("accent"), 10, 18.0, 0.0), "hover": _box(_c("accent").lightened(0.08), 10, 18.0, 0.0),
		"pressed": _box(_c("accent").darkened(0.12), 10, 18.0, 0.0), "disabled": _box(_c("chip"), 10, 18.0, 0.0)}, _bold, 14,
		{"font_color": _c("on_accent"), "font_hover_color": _c("on_accent"), "font_pressed_color": _c("on_accent"),
			"font_disabled_color": _c("text3")})
	actions.add_child(support)
	if more_link:
		var more := Button.new()
		more.text = "More motions"
		more.focus_mode = Control.FOCUS_NONE
		more.custom_minimum_size = Vector2(0, TOUCH)
		more.pressed.connect(show_feed_tab.bind("Motions"))
		_style_button(more, {"normal": _outline(Color(0, 0, 0, 0), _c("border_strong"), 1, 10, 16.0, 0.0),
			"hover": _outline(_c("chip"), _c("border_strong"), 1, 10, 16.0, 0.0)}, _semibold, 14,
			{"font_color": _c("text"), "font_hover_color": _c("text"), "font_pressed_color": _c("text")})
		actions.add_child(more)
	stack.add_child(actions)
	card.add_child(stack)
	return card


## The latest unattributed or ASI event, checked by the desk; null when none.
func _verification_card() -> PanelContainer:
	var found := recent_events(_is_unattributed, 1)
	if found.is_empty():
		return null
	var entry: Dictionary = found[0]
	var card := _card()
	card.name = "VerificationDesk"
	var stack := _vbox(10)
	var topic := String(TOPICS.get(String(entry.get("action", "")), "unattributed report"))
	stack.add_child(_post_head(_initials_avatar("VD", _c("chip"), _c("text")), "Verification desk",
		"Fact check · %s · T%d" % [topic, int(entry.get("turn", 0))]))
	var claim := String(entry.get("statement", entry.get("title", entry.get("text", "")))).strip_edges()
	claim = claim.trim_prefix("[unattributed]").strip_edges()
	stack.add_child(_label("“%s”" % claim, _regular, 15, _c("text"), true))
	var trust := metric(WorldState.EPISTEMIC_TRUST)
	var verdict := ["accent", "seal_check", "Corroborated: independent monitors confirm it; no one claims it"]
	if trust < 35.0:
		verdict = ["critical", "seal_broken", "Cannot be verified: the provenance chain is broken"]
	elif trust < 60.0:
		verdict = ["warn", "seal_crack", "Unverified: sources conflict and provenance is thin"]
	var pill := _panel(_box(_c(String(verdict[0]) + "_soft"), 8, 10.0, 6.0))
	var pill_row := _hbox(6)
	var ink := _c("accent_ink") if verdict[0] == "accent" else _c(String(verdict[0]))
	var icon := Glyphs.icon(String(verdict[1]), 16, ink, 1.8)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill_row.add_child(icon)
	var verdict_label := _label(String(verdict[2]), _semibold, 12, ink, true)
	verdict_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pill_row.add_child(verdict_label)
	pill.add_child(pill_row)
	stack.add_child(pill)
	stack.add_child(_label("Public trust %d · provenance coverage %d" % [int(roundf(trust)),
		int(roundf(index_value(WorldState.PROVENANCE_COVERAGE)))], _regular, 12, _c("text3"), true))
	card.add_child(stack)
	return card


func _is_unattributed(entry: Dictionary) -> bool:
	var text := String(entry.get("statement", entry.get("text", "")))
	if String(entry.get("category", "")) == "ACTION" and String(entry.get("faction", "")) == SimConstants.ASI:
		return text.strip_edges() != "" and text.strip_edges() != "[no signal]"
	return text.to_lower().contains("[unattributed]")


## Recent events from outside the coalition, as small posts.
func _event_cards() -> Array:
	var cards := []
	var keep := func(entry: Dictionary) -> bool:
		var category := String(entry.get("category", ""))
		var faction := String(entry.get("faction", ""))
		if category in ["SYSTEM", "DILEMMA"] or faction == role:
			return false
		# Entries that name the ASI outright stay off the coalition's wire.
		if faction == SimConstants.ASI and category != "ACTION":
			return false
		return not (category == "ACTION" and String(entry.get("action", "")) == CONSERVE)
	for entry in recent_events(keep, FEED_EVENTS):
		cards.append(_event_card(entry))
	return cards


func _event_card(entry: Dictionary) -> PanelContainer:
	var card := _card()
	var stack := _vbox(8)
	var faction := String(entry.get("faction", ""))
	# Citizens cannot see who runs the ASI's moves: they arrive unattributed.
	var hidden := faction == SimConstants.ASI
	var author := String(faction_data(faction).get("display_name", "")) if faction != "" else "World desk"
	if hidden:
		author = "Unattributed source"
	elif author == "":
		author = SimConstants.role_title(faction).capitalize()
	var avatar := _panel(_box(_c("chip"), 12))
	avatar.custom_minimum_size = Vector2(40, 40)
	var glyph_name := "warning" if hidden else (Glyphs.for_faction(faction) if faction != "" else "world")
	var glyph := Glyphs.icon(glyph_name, 22, _c("text"))
	glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	avatar.add_child(glyph)
	var category := String(entry.get("category", "")).to_lower()
	var headline := String(entry.get("action_name", "")) if category == "action" else category.capitalize()
	if hidden:
		headline = "Unverified report"
	stack.add_child(_post_head(avatar, author, "%s · T%d" % [headline, int(entry.get("turn", 0))]))
	var text := String(entry.get("statement", "")) if category == "action" else String(entry.get("headline", entry.get("text", "")))
	stack.add_child(_label(text.trim_prefix("[unattributed]").strip_edges(), _regular, 14, _c("text"), true))
	card.add_child(stack)
	return card


func _note_card(text: String) -> PanelContainer:
	var card := _card()
	card.add_child(_label(text, _regular, 14, _c("text2"), true))
	return card


# --- Motions and effects ---------------------------------------------------------

## The most useful affordable directives (the dashboard's suggestion first);
## conserving is only tabled when nothing else can be funded.
func _motion_picks(count: int) -> Array[String]:
	var scored := []
	for entry in action_entries():
		var action_id := String(entry.get("id", ""))
		if String(entry.get("blocked_reason", "")) == "" and action_id != CONSERVE:
			scored.append([action_id, _usefulness(action_id)])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	var picks: Array[String] = []
	var suggested := String(context.get("suggested_action", ""))
	if suggested != "" and suggested != CONSERVE and not is_blocked(suggested):
		picks.append(suggested)
	for item in scored:
		if not picks.has(String(item[0])):
			picks.append(String(item[0]))
	if picks.is_empty():
		picks.append(CONSERVE)
	return picks.slice(0, count)


## How much a directive helps from where the world stands: metric gains weigh
## more in warning or critical bands, own currencies count a little, costs count against.
func _usefulness(action_id: String) -> float:
	var definition := action_definition(action_id)
	var effects: Dictionary = definition.get("effects", {})
	var score := 0.0
	var metrics: Dictionary = effects.get("metrics", {})
	for key in metrics:
		var delta := float(metrics[key])
		var weight := 1.0 + float(WorldState.band_for(key, metric(key)))
		score += (absf(delta) if UiFormat.is_improvement(key, delta) else -absf(delta)) * weight
	var indices: Dictionary = effects.get("indices", {})
	score -= float(indices.get(WorldState.SURVEILLANCE_SATURATION, 0.0)) * (1.0 + index_value(WorldState.SURVEILLANCE_SATURATION) / 50.0)
	var own: Dictionary = effects.get("self", {})
	for key in own:
		score += float(own[key]) * 0.3
	var cost: Dictionary = definition.get("cost", {})
	for key in cost:
		score -= float(cost[key]) * 0.05
	return score


## [{key, delta, section}] for an applied or projected effects dictionary.
static func _effect_items(effects: Dictionary) -> Array:
	var items := []
	for section in ["metrics", "indices", "self"]:
		var deltas: Dictionary = effects.get(section, {})
		for key in deltas:
			var delta := float(deltas[key])
			if absf(delta) >= 0.05:
				items.append({"key": String(key), "delta": delta, "section": section})
	return items


func _impact_chip(item: Dictionary) -> PanelContainer:
	var key := String(item["key"])
	var delta := float(item["delta"])
	var section := String(item["section"])
	var tone := _tone(key, delta, section)
	var bg := _c("chip") if tone == "neutral" else _c(tone + "_soft")
	var ink := _c("text2") if tone == "neutral" else (_c("accent_ink") if tone == "accent" else _c(tone))
	var chip := _panel(_box(bg, 8, 10.0, 0.0))
	chip.custom_minimum_size.y = 28
	var row := _hbox(5)
	var icon := Glyphs.icon(_glyph_for(key, delta, section), 15, ink, 2.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	row.add_child(_centered(_label("%s %s" % [_effect_name(key, section), _short_delta(delta)], _semibold, 12, ink)))
	chip.add_child(row)
	return chip


static func _tone(key: String, delta: float, section: String) -> String:
	if section == "metrics":
		return "accent" if UiFormat.is_improvement(key, delta) else "warn"
	if section == "self":
		return "accent" if delta > 0.0 else "warn"
	match key:
		WorldState.SURVEILLANCE_SATURATION, WorldState.SUBSTRATE_INDEPENDENCE:
			return "accent" if delta < 0.0 else "warn"
		WorldState.SAFETY_NET_COVERAGE, WorldState.PROVENANCE_COVERAGE:
			return "accent" if delta > 0.0 else "warn"
	return "neutral"


static func _glyph_for(key: String, delta: float, section: String) -> String:
	if section == "metrics":
		return Glyphs.for_metric(key)
	if section == "self":
		return Glyphs.for_currency(key)
	if key == WorldState.SURVEILLANCE_SATURATION:
		return "counter_surveillance" if delta < 0.0 else "trust"
	return String(INDEX_GLYPHS.get(key, "info"))


static func _effect_name(key: String, section: String) -> String:
	if key == WorldState.LABOR_DISPLACEMENT:
		return "Jobs automated"
	if section == "metrics":
		return UiFormat.metric_name(key)
	if section == "indices":
		return UiFormat.metric_short(key)
	for entry in TREASURY:
		if entry[0] == key:
			return String(entry[1])
	return key.capitalize()


## "+3", "−4" or "+0.4".
static func _short_delta(delta: float) -> String:
	return _signed(delta, 0 if absf(delta) >= 1.0 else 1)


## "costs 12 scrip and 4 resilience", or "no cost".
static func _cost_words(cost: Dictionary) -> String:
	if cost.is_empty():
		return "no cost"
	var parts: Array[String] = []
	for key in cost:
		parts.append("%d %s" % [int(roundf(float(cost[key]))), _key_word(String(key))])
	if parts.size() == 1:
		return "costs " + parts[0]
	return "costs %s and %s" % [", ".join(parts.slice(0, parts.size() - 1)), parts[parts.size() - 1]]


static func _initials(chapter: String) -> String:
	var words := chapter.split(" ", false)
	if words.size() > 1:
		return (words[0].left(1) + words[1].left(1)).to_upper()
	var consonants := chapter.substr(1).to_upper().replace("A", "").replace("E", "").replace("I", "").replace("O", "").replace("U", "")
	return (chapter.left(1) + consonants.left(1)).to_upper()


# --- Drawing ------------------------------------------------------------------------

## The coalition mark (a triangle of linked neighbors) on an accent tile.
func _draw_logo_tile(canvas: Control, side: float, radius: int) -> void:
	canvas.draw_style_box(_box(_c("accent"), radius), Rect2(Vector2.ZERO, Vector2(side, side)))
	var unit := side / 34.0 * 22.0 / 24.0
	var origin := Vector2(side, side) * 0.5 - Vector2(12, 12) * unit
	var ink := _c("on_accent")
	var points := [Vector2(6.5, 17), Vector2(12, 7), Vector2(17.5, 17)]
	var hub := Vector2(12, 13.6)
	var outline := PackedVector2Array()
	for point in points + [points[0]]:
		outline.append(origin + (point as Vector2) * unit)
	canvas.draw_polyline(outline, ink, 1.6, true)
	for point in points:
		canvas.draw_line(origin + (point as Vector2) * unit, origin + hub * unit, ink, 1.6, true)
		canvas.draw_circle(origin + (point as Vector2) * unit, 1.9 * unit, ink)
	canvas.draw_circle(origin + hub * unit, 1.6 * unit, ink)


func _draw_status_dot(canvas: Control) -> void:
	var tone := String(canvas.get_meta("tone", "accent"))
	canvas.draw_circle(canvas.size * 0.5, 3.5, _c(tone))


func _draw_tab_underline(button: Button, tab: String) -> void:
	if tab != _tab:
		return
	var rect := Rect2(Vector2(12, button.size.y - 3), Vector2(button.size.x - 24, 3))
	var bar := _box(_c("accent"))
	bar.corner_radius_top_left = 2
	bar.corner_radius_top_right = 2
	button.draw_style_box(bar, rect)


func _draw_treasury_bar(canvas: Control, key: String) -> void:
	var rect := Rect2(Vector2.ZERO, canvas.size)
	canvas.draw_style_box(_box(_c("chip"), 2), rect)
	var fraction := clampf(float(resources.get(key, 0.0)) / 100.0, 0.0, 1.0)
	if fraction > 0.0:
		var fill := Rect2(Vector2.ZERO, Vector2(maxf(rect.size.x * fraction, 4.0), rect.size.y))
		canvas.draw_style_box(_box(_c("warn") if key == "collective_disruption" else _c("accent"), 2), fill)


func _seal_svg() -> String:
	return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"32\" height=\"32\" viewBox=\"0 0 24 24\"><path d=\"%s\" fill=\"#%s\"/><path d=\"M8.3 12.3l2.5 2.5 5-5.2\" fill=\"none\" stroke=\"#%s\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/></svg>" % [
		Glyphs.ROSETTE, _c("accent").to_html(false), _c("on_accent").to_html(false)]


## A stroked 24-unit icon path at [param size] logical px (rasterized at 2x).
static func _icon(path: String, size: int) -> Texture2D:
	var texture := Glyphs.svg_texture(_icon_svg(path, size))
	if texture is ImageTexture:
		(texture as ImageTexture).set_size_override(Vector2i(size, size))
	return texture


static func _icon_svg(path: String, size: int) -> String:
	return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 24 24\"><path d=\"%s\" fill=\"none\" stroke=\"#ffffff\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/></svg>" % [
		size * 2, size * 2, path]
