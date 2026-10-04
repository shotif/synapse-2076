class_name EraStyle
extends RefCounted
## The visual language of each hardware era ("fifty years should look like
## fifty years"). Era I (2026-2035) looks like a present-day native dark app,
## Era II (2036-2049) like layered holographic glass, Era III (2050-2076) like
## a living interface that the machines arrange. EraTheme turns a style into a
## Theme and publishes every value under the "Era" theme type, so custom-drawn
## widgets read the same palette and restyle when the dashboard swaps themes.

const NAMES := {1: "Silicon & Nuclear", 2: "Optical & SMR Grids", 3: "Neuromorphic"}
const SPANS := {1: "2026–2035", 2: "2036–2049", 3: "2050–2076"}
const ROMAN := {1: "I", 2: "II", 3: "III"}
const FONT_DIR := "res://ui/fonts/"
## Covers arrows, triangles, check marks and box drawing that the display
## faces lack.
const SYMBOL_FONT := preload("res://ui/fonts/JetBrainsMono-Regular.ttf")

var era := 1
var name := ""

# Surfaces.
var bg := Color.BLACK
var surface := Color.BLACK
var raised := Color.BLACK
var overlay := Color.BLACK
var border := Color.WHITE
var border_strong := Color.WHITE
var shade := Color(0, 0, 0, 0.7)

# Text and signals.
var text := Color.WHITE
var text_dim := Color.GRAY
var text_bright := Color.WHITE
var accent := Color.CYAN
var accent_hover := Color.CYAN
var on_accent := Color.BLACK
## A change that helps the world (blue family) or hurts it (orange family);
## kept apart in lightness as well as hue.
var good := Color.CYAN
var bad := Color.ORANGE
var warn := Color.ORANGE
var critical := Color.RED

## metric key -> color, faction id -> color.
var metric := {}
var faction := {}

# Typography.
var font_ui: Font
var font_ui_bold: Font
var font_display: Font
var font_mono: Font
var font_mono_bold: Font
## Small section labels in capitals (Era II) or sentence case (Eras I, III).
var labels_upper := false

# Shape.
var radius := 14
var control_radius := 10
## 1 bevels corners into chamfers (Era II); higher values round them.
var corner_detail := 8
var border_width := 0
## Era III panels get uneven, cell-like corner radii.
var organic := false
## Accent glow around focused and accent controls (0 = none).
var glow := 0.0

## Globe palette: core sphere, landmass dots, graticule, atmosphere rim, city
## lights and datacenter heat.
var globe := {}

static var _styles := {}
static var _fonts := {}


static func for_era(era_number: int) -> EraStyle:
	var key := clampi(era_number, 1, 3)
	if not _styles.has(key):
		_styles[key] = _build(key)
	return _styles[key]


## A font face from res://ui/fonts with the symbol fallback attached.
static func font(file: String, spacing: int = 0) -> Font:
	var key := "%s:%d" % [file, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var variation := FontVariation.new()
	variation.base_font = load(FONT_DIR + file)
	variation.fallbacks = [SYMBOL_FONT]
	if spacing != 0:
		variation.spacing_glyph = spacing
	_fonts[key] = variation
	return variation


func metric_color(key: String) -> Color:
	return metric.get(key, text)


func faction_color(faction_id: String) -> Color:
	return faction.get(faction_id, text_dim)


## Text for a small section label in this era's convention.
func label(text_value: String) -> String:
	return text_value.to_upper() if labels_upper else text_value


static func _build(era_number: int) -> EraStyle:
	var s := EraStyle.new()
	s.era = era_number
	s.name = NAMES[era_number]
	match era_number:
		1:
			_build_native(s)
		2:
			_build_holographic(s)
		_:
			_build_neuromorphic(s)
	return s


## Era I: today's dark native apps. Black canvas, grouped surfaces, system
## blue, soft rounded cards, no outlines.
static func _build_native(s: EraStyle) -> void:
	s.bg = Color("#000000")
	s.surface = Color("#1C1C1E")
	s.raised = Color("#2C2C2E")
	s.overlay = Color("#1C1C1E")
	s.border = Color(1, 1, 1, 0.08)
	s.border_strong = Color(1, 1, 1, 0.16)
	s.shade = Color(0, 0, 0, 0.62)
	s.text = Color("#F5F5F7")
	s.text_dim = Color("#98989F")
	s.text_bright = Color("#FFFFFF")
	s.accent = Color("#0A84FF")
	s.accent_hover = Color("#409CFF")
	s.on_accent = Color("#FFFFFF")
	s.good = Color("#409CFF")
	s.bad = Color("#FF9F0A")
	s.warn = Color("#FF9F0A")
	s.critical = Color("#FF453A")
	s.metric = {
		"compute_energy_sat": Color("#64D2FF"), "labor_displacement": Color("#FF9F0A"),
		"geopolitical_tension": Color("#FF6961"), "algorithmic_autonomy": Color("#BF5AF2"),
		"alignment_drift": Color("#FF6482"), "epistemic_trust": Color("#30D158"),
	}
	s.faction = {"CEO": Color("#64D2FF"), "GOVERNANCE_COUNCIL": Color("#409CFF"),
		"ASI": Color("#BF5AF2"), "CITIZEN_COALITION": Color("#30D158")}
	s.font_ui = font("Geist-Regular.ttf")
	s.font_ui_bold = font("Geist-SemiBold.ttf")
	s.font_display = font("Geist-Bold.ttf")
	s.font_mono = font("GeistMono-Regular.ttf")
	s.font_mono_bold = font("GeistMono-SemiBold.ttf")
	s.labels_upper = false
	s.radius = 16
	s.control_radius = 10
	s.corner_detail = 8
	s.border_width = 0
	s.organic = false
	s.glow = 0.0
	s.globe = {
		"core": Color("#030407"), "land": Color(0.36, 0.45, 0.58, 0.62), "grid": Color(0.42, 0.52, 0.68, 0.22),
		"atmosphere": Color("#3D7BFF"), "lights": Color("#FFD27A"), "heat": Color("#64D2FF"),
	}


## Era II: layered holographic glass. Cyan light on deep navy, chamfered
## frames, monospaced data and capitals for labels.
static func _build_holographic(s: EraStyle) -> void:
	s.bg = Color("#02070F")
	s.surface = Color("#051420")
	s.raised = Color("#0A1E2C")
	s.overlay = Color("#03101A")
	s.border = Color(0.0, 0.9, 1.0, 0.24)
	s.border_strong = Color(0.0, 0.9, 1.0, 0.55)
	s.shade = Color(0.0, 0.03, 0.06, 0.72)
	s.text = Color("#CFEFFA")
	s.text_dim = Color("#7FA6B8")
	s.text_bright = Color("#F0FDFF")
	s.accent = Color("#00E5FF")
	s.accent_hover = Color("#5CF0FF")
	s.on_accent = Color("#02070F")
	s.good = Color("#00E5FF")
	s.bad = Color("#FFB300")
	s.warn = Color("#FFB300")
	s.critical = Color("#FF3D6E")
	s.metric = {
		"compute_energy_sat": Color("#00E5FF"), "labor_displacement": Color("#FFB300"),
		"geopolitical_tension": Color("#FF3D6E"), "algorithmic_autonomy": Color("#C77DFF"),
		"alignment_drift": Color("#FF7AB6"), "epistemic_trust": Color("#6FF7C5"),
	}
	s.faction = {"CEO": Color("#00E5FF"), "GOVERNANCE_COUNCIL": Color("#58A6FF"),
		"ASI": Color("#D16BFF"), "CITIZEN_COALITION": Color("#7EE787")}
	s.font_ui = font("ChakraPetch-Medium.ttf")
	s.font_ui_bold = font("ChakraPetch-SemiBold.ttf")
	s.font_display = font("ChakraPetch-Bold.ttf")
	s.font_mono = font("JetBrainsMono-Regular.ttf")
	s.font_mono_bold = font("JetBrainsMono-Bold.ttf")
	s.labels_upper = true
	s.radius = 8
	s.control_radius = 6
	s.corner_detail = 1
	s.border_width = 1
	s.organic = false
	s.glow = 0.28
	s.globe = {
		"core": Color("#02060C"), "land": Color(0.0, 0.82, 0.95, 0.55), "grid": Color(0.0, 0.9, 1.0, 0.5),
		"atmosphere": Color("#00E5FF"), "lights": Color("#A8F6FF"), "heat": Color("#00E5FF"),
	}


## Era III: neuromorphic. Violet-black ground, bioluminescent teal, magenta
## and amber, uneven cell-like corners and a monospaced machine voice.
static func _build_neuromorphic(s: EraStyle) -> void:
	s.bg = Color("#0B0612")
	s.surface = Color("#150C21")
	s.raised = Color("#1F1230")
	s.overlay = Color("#120A1C")
	s.border = Color(0.93, 0.89, 0.97, 0.15)
	s.border_strong = Color(0.31, 0.94, 0.78, 0.5)
	s.shade = Color(0.04, 0.02, 0.07, 0.72)
	s.text = Color("#EDE3F7")
	s.text_dim = Color("#A897C0")
	s.text_bright = Color("#F6EEFF")
	s.accent = Color("#4FF0C8")
	s.accent_hover = Color("#8CF7DD")
	s.on_accent = Color("#0B0612")
	s.good = Color("#4FF0C8")
	s.bad = Color("#FFC266")
	s.warn = Color("#FFC266")
	s.critical = Color("#FF6F91")
	s.metric = {
		"compute_energy_sat": Color("#4FF0C8"), "labor_displacement": Color("#FFC266"),
		"geopolitical_tension": Color("#FF8FAE"), "algorithmic_autonomy": Color("#B98CFF"),
		"alignment_drift": Color("#FF5FD2"), "epistemic_trust": Color("#A8FFB4"),
	}
	s.faction = {"CEO": Color("#4FF0C8"), "GOVERNANCE_COUNCIL": Color("#8FB8FF"),
		"ASI": Color("#FF5FD2"), "CITIZEN_COALITION": Color("#A8FFB4")}
	s.font_ui = font("Syne-Medium.ttf")
	s.font_ui_bold = font("Syne-Bold.ttf")
	s.font_display = font("Syne-ExtraBold.ttf")
	s.font_mono = font("FragmentMono-Regular.ttf")
	s.font_mono_bold = font("FragmentMono-Regular.ttf")
	s.labels_upper = false
	s.radius = 26
	s.control_radius = 22
	s.corner_detail = 12
	s.border_width = 1
	s.organic = true
	s.glow = 0.18
	s.globe = {
		"core": Color("#07030C"), "land": Color(0.73, 0.55, 1.0, 0.5), "grid": Color(1.0, 0.37, 0.82, 0.3),
		"atmosphere": Color("#4FF0C8"), "lights": Color("#FFC266"), "heat": Color("#4FF0C8"),
	}
