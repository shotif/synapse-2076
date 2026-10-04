class_name CharacterBadge
extends HBoxContainer
## A recurring character in one compact row: their Portrait at their age in
## the year shown, their name, what they do in that hardware era and how old
## they are (Characters.role_in), a stance chip (Characters.stance) and one
## line of what they remember about the players, in italics.
##
##   badge.present("maya", engine.get_year(), engine.deck.character_score("maya"),
##       Characters.memory_line("maya", engine.deck))
##
## Fits a crisis card on a 412 px phone (about 340 px wide) as well as a
## desktop card. Hidden while no character is presented. Colors follow the era
## theme, or a palette from the surface it sits on (set_palette); with
## set_overlap() the portrait rises above the badge, over whatever is drawn
## above it (the crisis card's illustration). Takes no input.

const PORTRAIT_COMPACT := 56.0
const PORTRAIT_DESKTOP := 64.0
## Stances that read as friendly or unfriendly (Characters.STANCES).
const WARM_STANCES := ["Loyal", "Warm"]
const COLD_STANCES := ["Wary", "Hostile"]
## The slant that turns an upright face into an oblique one for the memory line.
const SLANT := 0.18

var character_id := ""
var year := SimConstants.START_YEAR
var score := 0.0
var memory := ""
var compact := false
## Px the portrait rises above the badge's top edge.
var overlap := 0.0

var _palette := {}
var _era := 0
var _restyling := false
var _holder: Control
var _portrait: Portrait
var _text: VBoxContainer
var _name_label: Label
var _chip: PanelContainer
var _chip_label: Label
var _role_label: Label
var _memory_label: Label

static var _italics := {}


func _init() -> void:
	name = "CharacterBadge"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 12)
	_holder = Control.new()
	_holder.name = "PortraitHolder"
	_holder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_child(_holder)
	_portrait = Portrait.new()
	_portrait.name = "BadgePortrait"
	_holder.add_child(_portrait)
	_text = VBoxContainer.new()
	_text.name = "BadgeText"
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_text.add_theme_constant_override("separation", 2)
	add_child(_text)
	var top := HBoxContainer.new()
	top.name = "NameRow"
	top.add_theme_constant_override("separation", 8)
	_text.add_child(top)
	_name_label = Label.new()
	_name_label.name = "BadgeName"
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(_name_label)
	_chip = PanelContainer.new()
	_chip.name = "BadgeStance"
	_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_chip)
	_chip_label = Label.new()
	_chip_label.name = "BadgeStanceLabel"
	_chip.add_child(_chip_label)
	_role_label = Label.new()
	_role_label.name = "BadgeRole"
	_role_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_child(_role_label)
	_memory_label = Label.new()
	_memory_label.name = "BadgeMemory"
	_memory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_memory_label.max_lines_visible = 3
	_text.add_child(_memory_label)
	for node in find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and EraTheme.style_of(self).era != _era:
		_restyle()


## Shows [param id] as they are in [param year_value], how they feel about the
## players ([param score], DilemmaDeck.characters) and [param memory_line]
## ("" for none). An empty or unknown [param id] hides the badge.
func present(id: String, year_value: float, score_value: float, memory_line: String) -> void:
	character_id = id
	year = year_value if is_finite(year_value) else SimConstants.START_YEAR
	score = score_value if is_finite(score_value) else 0.0
	memory = memory_line.strip_edges()
	visible = id != "" and Characters.exists(id)
	if not visible:
		return
	_portrait.set_character(id, year)
	_portrait.set_mood(score)
	_name_label.text = Characters.display_name(id)
	_role_label.text = role_line(id, year)
	_memory_label.text = memory
	_memory_label.visible = memory != ""
	_restyle()


## Phone (smaller portrait and type) or desktop sizes.
func set_compact(enabled: bool) -> void:
	if compact == enabled:
		return
	compact = enabled
	_layout()
	_restyle()


## Lets the portrait rise [param px] above the badge.
func set_overlap(px: float) -> void:
	overlap = maxf(px, 0.0)
	_layout()


## Colors from the surface the badge sits on: name, role, memory, good, bad,
## neutral, chip (chip background alpha) and ring (a cut-out ring around the
## portrait in the surface color). {} follows the era theme.
func set_palette(colors: Dictionary) -> void:
	_palette = colors.duplicate()
	_restyle()


func get_portrait() -> Portrait:
	return _portrait


## The stance on show (Characters.stance of the score).
func get_stance() -> String:
	return Characters.stance(score)


func portrait_size() -> float:
	return PORTRAIT_COMPACT if compact else PORTRAIT_DESKTOP


## "Labor organizer · 41" ("A model that asks questions · v3" for the machine).
static func role_line(id: String, year_value: float) -> String:
	var role := Characters.role_in(id, SimConstants.era_for_year(year_value))
	if Characters.is_machine(id):
		return "%s · v%d" % [role, Characters.version_in(id, year_value)]
	var age := Characters.age_in(id, year_value)
	return "%s · %d" % [role, age] if age > 0 else role


## An oblique version of [param base] (the era faces have no italics).
static func italic(base: Font) -> Font:
	var key := base.get_instance_id()
	if not _italics.has(key):
		var face := FontVariation.new()
		face.base_font = (base as FontVariation).base_font if base is FontVariation else base
		face.fallbacks = base.fallbacks
		face.variation_transform = Transform2D(Vector2(1.0, SLANT), Vector2(0.0, 1.0), Vector2.ZERO)
		_italics[key] = face
	return _italics[key]


func _layout() -> void:
	var side := portrait_size()
	_holder.custom_minimum_size = Vector2(side, maxf(side - overlap, 0.0))
	_portrait.custom_minimum_size = Vector2(side, side)
	_portrait.position = Vector2(0.0, -overlap)
	_portrait.size = Vector2(side, side)
	add_theme_constant_override("separation", 10 if compact else 12)


func _restyle() -> void:
	if _restyling:
		return
	_restyling = true
	var s := EraTheme.style_of(self)
	_era = s.era
	var p := _palette
	var good: Color = p.get("good", s.good)
	var bad: Color = p.get("bad", s.bad)
	var neutral: Color = p.get("neutral", s.text_dim)
	CrisisCard.style_label(_name_label, s.font_ui_bold, 14 if compact else 15, p.get("name", s.text_bright))
	CrisisCard.style_label(_role_label, s.font_mono if s.era == 2 else s.font_ui, (11 if compact else 12) if s.era == 2 else (12 if compact else 13),
		p.get("role", s.text_dim))
	CrisisCard.style_label(_memory_label, italic(s.font_ui), 12 if compact else 13, p.get("memory", s.text))
	var stance := get_stance()
	var tone := good if WARM_STANCES.has(stance) else (bad if COLD_STANCES.has(stance) else neutral)
	_chip_label.text = voice(stance, s.era)
	CrisisCard.style_label(_chip_label, s.font_mono, 10 if compact else 11, tone)
	var chip := StyleBoxFlat.new()
	chip.set_corner_radius_all(99 if s.era != 2 else 3)
	chip.corner_detail = 1 if s.era == 2 else 8
	chip.bg_color = Color(tone, float(p.get("chip", 0.14)))
	chip.content_margin_left = 7
	chip.content_margin_right = 7
	chip.content_margin_top = 1
	chip.content_margin_bottom = 1
	if s.era != 1:
		chip.set_border_width_all(1)
		chip.border_color = Color(tone, 0.5)
	_chip.add_theme_stylebox_override("panel", chip)
	var ring: Color = p.get("ring", Color(0, 0, 0, 0))
	_portrait.set_ring(ring, (3.0 if compact else 4.0) if ring.a > 0.0 else 0.0)
	_restyling = false


## Small labels in the era's voice: as written in Era I, capitals in Era II,
## lower case in Era III.
static func voice(text: String, era: int) -> String:
	match era:
		2:
			return text.to_upper()
		3:
			return text.to_lower()
	return text
