class_name CyberPalette
extends RefCounted
## Cyber-Telemetry palette and fonts (PRD section 8.1).

const BG := Color("#0D1117")
const PANEL := Color("#10151C")
const PANEL_RAISED := Color("#161B22")
const BORDER := Color("#21262D")
const BORDER_BRIGHT := Color("#30363D")
const CYAN := Color("#00E5FF")
const AMBER := Color("#FFB300")
const CRIMSON := Color("#FF1744")
const TEXT := Color("#C9D1D9")
const TEXT_DIM := Color("#8B949E")
const TEXT_BRIGHT := Color("#E6EDF3")

## Secondary accents used only to tag factions in feeds and charts.
const FACTION_COLORS := {
	"CEO": Color("#00E5FF"),
	"GOVERNANCE_COUNCIL": Color("#58A6FF"),
	"ASI": Color("#D16BFF"),
	"CITIZEN_COALITION": Color("#7EE787"),
}

## Trajectory-chart colors for the six macro metrics.
const METRIC_COLORS := {
	"compute_energy_sat": Color("#00E5FF"),
	"labor_displacement": Color("#FFB300"),
	"geopolitical_tension": Color("#FF1744"),
	"algorithmic_autonomy": Color("#D16BFF"),
	"alignment_drift": Color("#FF7AB6"),
	"epistemic_trust": Color("#7EE787"),
}

const MONO_FONT := preload("res://ui/fonts/JetBrainsMono-Regular.ttf")
const MONO_BOLD := preload("res://ui/fonts/JetBrainsMono-Bold.ttf")
const SANS_FONT := preload("res://ui/fonts/Geist-Regular.ttf")
const SANS_BOLD := preload("res://ui/fonts/Geist-SemiBold.ttf")


static func band_color(band: int) -> Color:
	match band:
		1:
			return AMBER
		2:
			return CRIMSON
	return CYAN


static func severity_color(severity: String) -> Color:
	match severity:
		"WARN":
			return AMBER
		"CRITICAL":
			return CRIMSON
	return TEXT


static func faction_color(faction_id: String) -> Color:
	return FACTION_COLORS.get(faction_id, TEXT_DIM)


static func hex(color: Color) -> String:
	return "#" + color.to_html(false)


## Escapes text for safe insertion into a BBCode RichTextLabel (LLM output is untrusted).
static func escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")
