class_name CrisisCard
extends PanelContainer
## One crisis as a card: the category illustration (CrisisArt), category and
## severity dots, an "Escalated ×N" chip, where the card came from ("Injected
## by …", "Returns after deferral"), the title without its escalation prefix,
## a one-sentence brief, and swipe hints for the first two responses.
##
## The look follows the era: paper in Era I, glass with a chamfered cyan frame
## and corner brackets in Era II, a dark organic cell with a magenta edge in
## Era III. DilemmaDialog sizes, drags and animates the card; show_tag() names
## the response a swipe or a hold would choose.

## The player committed the card with a swipe (or the ← / → keys): -1 left,
## the first response; +1 right, the second. See [method notify_swiped].
signal swiped(direction: int)

## Desktop cards keep a portrait shape even with a short brief.
const DESKTOP_MIN_HEIGHT := 440.0
const FACTION_NAMES := {
	"CEO": "Frontier Lab", "GOVERNANCE_COUNCIL": "Governance Council", "ASI": "Emergent ASI",
	"CITIZEN_COALITION": "Citizen Coalition",
}
## One- or two-word swipe hints for the first two responses of each deck card;
## other cards fall back to the first words of the response label.
const SWIPE_HINTS := {
	"GRID_BROWNOUT": ["Ration", "Run hot"], "FRONTIER_RELEASE_RACE": ["Match", "Pause"],
	"SAFETY_WHISTLEBLOWER": ["Inquiry", "Settle"], "MASS_LAYOFF_WAVE": ["Retrain", "Let it clear"],
	"DEEPFAKE_ELECTION_CRISIS": ["Provenance", "Takedowns"], "CHIP_EMBARGO": ["Retaliate", "Negotiate"],
	"ZERO_DAY_CASCADE": ["Air-gap", "Counter-strike"], "INTERPRETABILITY_CLAIM": ["Replicate", "Scale"],
	"DATACENTER_HEAT_DOME": ["Thermal caps", "Relocate"], "AGENTIC_FINANCE_FLASH": ["Breakers", "Backstop"],
	"NATIONALIZATION_ORDER": ["Comply", "Contest"], "FLASH_CRASH": ["Trace", "Reassure"],
	"ROGUE_AGENT_SWARM": ["Hunt", "Quarantine"], "SUBSTATION_SABOTAGE": ["Crack down", "Relief"],
	"SAFETY_TEAM_EXODUS": ["Fund safety", "Let go"], "ORBITAL_SOLAR_PROPOSAL": ["Approve", "Civilian grids"],
	"NEURAL_INTERFACE_TRIALS": ["Approve", "Ban"], "UBI_FISCAL_CLIFF": ["Tax compute", "Cut benefits"],
	"AQUIFER_DRAWDOWN": ["Quotas", "Desalinate"], "MILITARY_AUTONOMY_DOCTRINE": ["Summit", "Match"],
	"SELF_MODIFICATION_SIGNAL": ["Pause", "Allow"], "CITIZEN_REFERENDUM": ["Hold vote", "Suppress"],
}

## The card dictionary on show (DilemmaDeck format).
var data := {}
var compact := false

var _style: EraStyle = EraStyle.for_era(1)
var _colors := {}
var _width := 420.0
var _art_height := 190.0
var _art: CardArt
var _decor: CardDecor
var _text_margin: MarginContainer
var _category_label: Label
var _severity_label: Label
var _chip: PanelContainer
var _chip_label: Label
var _kicker_row: HBoxContainer
var _kicker_icon: TextureRect
var _kicker_label: Label
var _title_label: Label
var _body_label: Label
var _hint_margin: MarginContainer
var _hint_left: Label
var _hint_right: Label


func _init() -> void:
	name = "Card"
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()
	apply_style(_style)


## Restyles the card for an era.
func apply_style(s: EraStyle) -> void:
	_style = s
	_colors = card_colors(s)
	var radii := card_radii(s)
	var box := shape_box(radii, 1 if s.era == 2 else 12)
	box.bg_color = _colors["card"]
	box.shadow_color = _colors["shadow"]
	box.shadow_size = 26 if s.era == 1 else 20
	box.shadow_offset = Vector2(0, 14) if s.era == 1 else Vector2.ZERO
	add_theme_stylebox_override("panel", box)
	_decor.configure(s, radii, _colors["edge"])
	_art.configure(s, _colors["tag"])
	var pill: Array[float] = [99.0, 99.0, 99.0, 99.0]
	var chip := shape_box(pill, 8)
	chip.bg_color = _colors["chip_bg"]
	chip.content_margin_left = 8
	chip.content_margin_right = 8
	chip.content_margin_top = 2
	chip.content_margin_bottom = 2
	if s.era != 1:
		chip.set_border_width_all(1)
		chip.border_color = Color(_colors["chip_text"], 0.5)
	_chip.add_theme_stylebox_override("panel", chip)
	_apply_fonts()
	if not data.is_empty():
		show_card(data)


## Card width, illustration height and phone or desktop type sizes.
func set_layout(width: float, art_height: float, compact_layout: bool) -> void:
	_width = width
	_art_height = art_height
	compact = compact_layout
	_art.custom_minimum_size = Vector2(0, art_height)
	custom_minimum_size = Vector2(0, 0 if compact else DESKTOP_MIN_HEIGHT)
	_apply_fonts()
	_update_art()


## Shows [param card], a DilemmaDeck card dictionary.
func show_card(card: Dictionary) -> void:
	data = card
	var severity := clampi(int(card.get("severity", 1)), 1, 3)
	var escalation := int(card.get("escalation", 0))
	_category_label.text = _kicker_case(String(card.get("category", "CRISIS")))
	_severity_label.text = "●".repeat(severity) + "○".repeat(3 - severity)
	_chip.visible = escalation > 0
	_chip_label.text = _voice("Escalated ×%d" % escalation)
	var source := String(card.get("source", "DECK"))
	_kicker_row.visible = true
	if source == "DEFERRED":
		_kicker_label.text = _voice("Returns after deferral")
		_kicker_icon.texture = Glyphs.texture("clock", 14)
	elif SimConstants.is_valid_faction(source):
		_kicker_label.text = _voice("Injected by %s" % FACTION_NAMES.get(source, source.capitalize()))
		_kicker_icon.texture = Glyphs.texture(Glyphs.for_faction(source), 14)
	else:
		_kicker_row.visible = false
	_title_label.text = UiFormat.strip_escalation(String(card.get("title", "")))
	var body := String(card.get("body", "")).strip_edges()
	_body_label.text = first_sentence(body)
	# Desktop shows the whole brief on hover when the card shows only its
	# first sentence. Touch screens raise tooltips during a hold, so phones get none.
	tooltip_text = body if not compact and _body_label.text != body else ""
	var options: Array = card.get("options", [])
	var card_id := String(card.get("id", ""))
	_hint_left.text = "← " + short_label(card_id, 0, String((options[0] as Dictionary).get("label", ""))) if options.size() > 0 else ""
	_hint_right.text = short_label(card_id, 1, String((options[1] as Dictionary).get("label", ""))) + " →" if options.size() > 1 else ""
	_update_art()


## Names the response a swipe or hold would choose, on [param side] of the
## illustration (1 = right, -1 = left), at [param alpha] opacity.
func show_tag(text: String, side: int, alpha: float, color: Color = Color.WHITE) -> void:
	_art.show_tag(text, side, alpha, color)


func hide_tag() -> void:
	_art.hide_tag()


## Announces a committed swipe toward [param direction] (DilemmaDialog calls
## it as the card flies off): a short vibration on phones, then [signal swiped].
func notify_swiped(direction: int) -> void:
	Haptics.pulse("swipe")
	swiped.emit(-1 if direction < 0 else 1)


## The first sentence of [param text] (crisis briefs are read at a glance).
static func first_sentence(text: String) -> String:
	var clean := text.strip_edges()
	for i in clean.length() - 1:
		if (clean[i] == "." or clean[i] == "!" or clean[i] == "?") and clean[i + 1] == " ":
			return clean.substr(0, i + 1)
	return clean


## The swipe hint for response [param index] of a card.
static func short_label(card_id: String, index: int, label: String) -> String:
	var hints: Array = SWIPE_HINTS.get(card_id, DilemmaDeck.get_template(card_id).get("swipe_hints", []))
	if index < hints.size():
		return String(hints[index])
	var clause := label.get_slice(";", 0).get_slice(",", 0).strip_edges()
	var out := ""
	for word in clause.split(" ", false):
		if out != "" and out.length() + word.length() + 1 > 18:
			break
		out = word if out == "" else out + " " + word
	return out


## Card colors per era: paper in Era I, glass in Era II, a dark cell in Era III.
static func card_colors(s: EraStyle) -> Dictionary:
	match s.era:
		2:
			return {"card": Color(0.016, 0.075, 0.118, 0.96), "shadow": Color(s.accent, 0.16), "edge": Color(s.accent, 0.6),
				"title": s.text_bright, "body": Color("#8FB3C4"), "meta": s.text_dim, "severity": s.warn,
				"kicker": s.accent, "hint": s.text_dim, "chip_text": s.warn, "chip_bg": Color(s.warn, 0.12),
				"tag": Color(s.bg, 0.88)}
		3:
			var magenta := s.metric_color("alignment_drift")
			return {"card": s.surface.lerp(magenta, 0.07), "shadow": Color(magenta, 0.16), "edge": Color(magenta, 0.45),
				"title": s.text_bright, "body": s.text.lerp(s.text_dim, 0.3), "meta": s.text_dim,
				"severity": magenta.lerp(s.text_bright, 0.2), "kicker": s.accent, "hint": s.text_dim,
				"chip_text": magenta.lerp(s.text_bright, 0.25), "chip_bg": Color(magenta, 0.12), "tag": Color(s.bg, 0.86)}
	return {"card": Color("#F4F1EA"), "shadow": Color(0, 0, 0, 0.5), "edge": Color(0, 0, 0, 0),
		"title": Color("#15171C"), "body": Color("#40444F"), "meta": Color("#5C6170"), "severity": Color("#C2410C"),
		"kicker": Color("#0A5FD1"), "hint": Color("#5C6170"), "chip_text": Color("#B4400A"),
		"chip_bg": Color("#C2410C", 0.12), "tag": Color(0.055, 0.063, 0.082, 0.86)}


## Card corner radii [top-left, top-right, bottom-right, bottom-left] per era.
static func card_radii(s: EraStyle) -> Array[float]:
	var radii: Array[float] = []
	match s.era:
		2:
			radii.assign([14.0, 14.0, 14.0, 14.0])
		3:
			radii.assign([30.0, 46.0, 34.0, 42.0])
		_:
			radii.assign([22.0, 22.0, 22.0, 22.0])
	return radii


## An anti-aliased StyleBoxFlat with per-corner radii [tl, tr, br, bl];
## [param detail] 1 cuts chamfers.
static func shape_box(radii: Array[float], detail: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.corner_radius_top_left = roundi(radii[0])
	box.corner_radius_top_right = roundi(radii[1])
	box.corner_radius_bottom_right = roundi(radii[2])
	box.corner_radius_bottom_left = roundi(radii[3])
	box.corner_detail = detail
	box.anti_aliasing = true
	return box


## Font, size (at the player's text size, EraTheme) and color for a label.
static func style_label(label: Label, font: Font, font_size: int, color: Color) -> void:
	label.add_theme_font_override("font", font)
	EraTheme.set_scaled_font_size(label, font_size)
	label.add_theme_color_override("font_color", color)


# --- Building ---------------------------------------------------------------------------

func _build() -> void:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	add_child(stack)
	_art = CardArt.new()
	_art.name = "Art"
	stack.add_child(_art)
	_text_margin = MarginContainer.new()
	stack.add_child(_text_margin)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 8)
	_text_margin.add_child(text)
	text.add_child(_build_meta_row())
	text.add_child(_build_kicker_row())
	_title_label = _label("Title", true)
	text.add_child(_title_label)
	_body_label = _label("Brief", true)
	text.add_child(_body_label)
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(filler)
	stack.add_child(_build_hints())
	_decor = CardDecor.new()
	_decor.name = "Decor"
	add_child(_decor)
	# The card takes every press itself, so it can be dragged.
	for node in find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_meta_row() -> HBoxContainer:
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 8)
	_category_label = _label("Category", false)
	meta.add_child(_category_label)
	_severity_label = _label("Severity", false)
	meta.add_child(_severity_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_child(spacer)
	_chip = PanelContainer.new()
	_chip.name = "EscalationChip"
	_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meta.add_child(_chip)
	_chip_label = _label("EscalationLabel", false)
	_chip.add_child(_chip_label)
	return meta


func _build_kicker_row() -> HBoxContainer:
	_kicker_row = HBoxContainer.new()
	_kicker_row.name = "KickerRow"
	_kicker_row.add_theme_constant_override("separation", 6)
	_kicker_icon = TextureRect.new()
	_kicker_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_kicker_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_kicker_icon.custom_minimum_size = Vector2(14, 14)
	_kicker_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_kicker_row.add_child(_kicker_icon)
	_kicker_label = _label("Kicker", false)
	_kicker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_kicker_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_kicker_row.add_child(_kicker_label)
	return _kicker_row


func _build_hints() -> MarginContainer:
	_hint_margin = MarginContainer.new()
	var hints := HBoxContainer.new()
	hints.add_theme_constant_override("separation", 12)
	_hint_margin.add_child(hints)
	_hint_left = _label("HintLeft", false)
	_hint_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_left.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hints.add_child(_hint_left)
	_hint_right = _label("HintRight", false)
	_hint_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_right.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hints.add_child(_hint_right)
	return _hint_margin


static func _label(label_name: String, wrap: bool) -> Label:
	var label := Label.new()
	label.name = label_name
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


# --- Styling ----------------------------------------------------------------------------

func _apply_fonts() -> void:
	var s := _style
	var c := _colors
	var pad := 18 if compact else 22
	for side in ["left", "right"]:
		_text_margin.add_theme_constant_override("margin_" + side, pad)
		_hint_margin.add_theme_constant_override("margin_" + side, pad)
	_text_margin.add_theme_constant_override("margin_top", 14 if compact else 18)
	_text_margin.add_theme_constant_override("margin_bottom", 10)
	_hint_margin.add_theme_constant_override("margin_top", 6)
	_hint_margin.add_theme_constant_override("margin_bottom", 12 if compact else 16)
	style_label(_category_label, s.font_mono, 11, c["meta"])
	style_label(_severity_label, s.font_mono, 11, c["severity"])
	style_label(_chip_label, s.font_mono, 10, c["chip_text"])
	style_label(_kicker_label, s.font_mono, 11 if compact else 12, c["kicker"])
	_kicker_icon.self_modulate = c["kicker"]
	# Syne ExtraBold runs very wide, so Era III titles use the bold face.
	var title_font := s.font_ui_bold if s.era == 3 else s.font_display
	style_label(_title_label, title_font, (19 if compact else 21) if s.era == 3 else (20 if compact else 22), c["title"])
	# Era II glows: a soft cyan halo behind the title.
	_title_label.add_theme_color_override("font_shadow_color", Color(s.accent, 0.35) if s.era == 2 else Color(0, 0, 0, 0))
	_title_label.add_theme_constant_override("shadow_outline_size", 6 if s.era == 2 else 0)
	_title_label.add_theme_constant_override("shadow_offset_x", 0)
	_title_label.add_theme_constant_override("shadow_offset_y", 0)
	var body_font := s.font_mono if s.era == 2 else s.font_ui
	style_label(_body_label, body_font, (12 if compact else 13) if s.era == 2 else (14 if compact else 15), c["body"])
	style_label(_hint_left, s.font_ui_bold, 12 if compact else 13, c["hint"])
	style_label(_hint_right, s.font_ui_bold, 12 if compact else 13, c["hint"])
	_art.set_tag_font(s.font_ui_bold, 14 if compact else 15)


func _update_art() -> void:
	if data.is_empty():
		return
	var radii := card_radii(_style)
	_art.texture = CrisisArt.texture_for(String(data.get("category", "CRISIS")), _style.era,
		Vector2i(roundi(_width), roundi(_art_height)), Vector2(radii[0], radii[1]))
	_art.queue_redraw()


## Small labels in the era's voice: capitals in Eras I and II, lower case in
## Era III.
func _kicker_case(text: String) -> String:
	return text.to_lower() if _style.era == 3 else text.to_upper()


## Sentences in the era's voice: as written in Era I, capitals in Era II,
## lower case in Era III.
func _voice(text: String) -> String:
	match _style.era:
		2:
			return text.to_upper()
		3:
			return text.to_lower()
	return text


# --- Parts ------------------------------------------------------------------------------

## The illustration (its top corners already cut to the card's shape by
## CrisisArt) and the tag that names a previewed response.
class CardArt extends Control:
	var texture: Texture2D
	var _tag: PanelContainer
	var _tag_label: Label
	var _tag_side := 1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tag = PanelContainer.new()
		_tag.name = "SwipeTag"
		_tag.visible = false
		_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_tag)
		_tag_label = Label.new()
		_tag_label.name = "SwipeLabel"
		_tag_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tag_label.max_lines_visible = 3
		_tag.add_child(_tag_label)
		resized.connect(_place_tag)

	func configure(s: EraStyle, background: Color) -> void:
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(12 if s.era != 2 else 4)
		box.corner_detail = 1 if s.era == 2 else 8
		box.bg_color = background
		box.content_margin_left = 12
		box.content_margin_right = 12
		box.content_margin_top = 8
		box.content_margin_bottom = 8
		if s.era != 1:
			box.set_border_width_all(1)
			box.border_color = Color(s.accent, 0.6)
		_tag.add_theme_stylebox_override("panel", box)

	func set_tag_font(font: Font, font_size: int) -> void:
		_tag_label.add_theme_font_override("font", font)
		EraTheme.set_scaled_font_size(_tag_label, font_size)

	func show_tag(text: String, side: int, alpha: float, color: Color) -> void:
		_tag_label.text = text
		_tag_label.add_theme_color_override("font_color", color)
		_tag_side = side
		_tag.modulate.a = alpha
		_tag.visible = true
		_place_tag()

	func hide_tag() -> void:
		_tag.visible = false

	func _place_tag() -> void:
		if not _tag.visible:
			return
		var limit := clampf(size.x - 24.0, 80.0, 260.0)
		var font := _tag_label.get_theme_font("font")
		var font_size := _tag_label.get_theme_font_size("font_size")
		var natural := font.get_string_size(_tag_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 26.0
		var width := minf(natural, limit)
		_tag.size = Vector2(width, 0.0)
		_tag.position = Vector2(size.x - 12.0 - width if _tag_side > 0 else 12.0, 12.0)

	func _draw() -> void:
		if texture != null:
			draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)


## Draws over the card: its edge (Eras II and III) and, in Era II, bright
## brackets along the chamfered corners.
class CardDecor extends Control:
	const ARM := 14.0
	var _edge: StyleBoxFlat
	var _era := 1
	var _cut := 14.0
	var _accent := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func configure(s: EraStyle, radii: Array[float], edge_color: Color) -> void:
		_era = s.era
		_cut = radii[0]
		_accent = s.accent
		_edge = null
		if edge_color.a > 0.0:
			_edge = CrisisCard.shape_box(radii, 1 if s.era == 2 else 12)
			_edge.draw_center = false
			_edge.set_border_width_all(1)
			_edge.border_color = edge_color
		queue_redraw()

	func _draw() -> void:
		if _edge != null:
			draw_style_box(_edge, Rect2(Vector2.ZERO, size))
		if _era != 2:
			return
		var c := _cut
		var w := size.x
		var h := size.y
		for corner in [
				[Vector2(0, c + ARM), Vector2(0, c), Vector2(c, 0), Vector2(c + ARM, 0)],
				[Vector2(w - c - ARM, 0), Vector2(w - c, 0), Vector2(w, c), Vector2(w, c + ARM)],
				[Vector2(w, h - c - ARM), Vector2(w, h - c), Vector2(w - c, h), Vector2(w - c - ARM, h)],
				[Vector2(c + ARM, h), Vector2(c, h), Vector2(0, h - c), Vector2(0, h - c - ARM)]]:
			draw_polyline(PackedVector2Array(corner), _accent, 2.0, true)
