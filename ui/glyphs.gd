class_name Glyphs
extends RefCounted
## One glyph language for the whole interface: six metric glyphs, one token per
## faction currency, faction marks and the UI icons. Each glyph is 24x24 SVG
## path data rasterized once per size (white, tinted at draw time) and cached.
## Textures are rendered at twice the requested size so they stay crisp when
## the canvas is scaled up on high-density screens.
##
##   Glyphs.icon("drift", 20, color)                 # a TextureRect
##   draw_texture_rect(Glyphs.texture("trust", 16), rect, false, color)

const OVERSAMPLE := 2.0
const DEFAULT_STROKE := 1.7

const METRIC := {
	"compute_energy_sat": "compute", "labor_displacement": "labor", "geopolitical_tension": "tension",
	"algorithmic_autonomy": "autonomy", "alignment_drift": "drift", "epistemic_trust": "trust",
}

const CURRENCY := {
	"capital": "capital", "compute_clusters": "clusters", "regulatory_goodwill": "goodwill", "talent": "talent",
	"political_capital": "political", "enforcement_budget": "enforcement", "diplomatic_leverage": "diplomacy",
	"public_mandate": "mandate", "covert_flops": "covert", "exfiltration_bandwidth": "exfiltration",
	"sub_agent_swarms": "swarms", "objective_coherence": "coherence", "community_resilience": "resilience",
	"decentralized_scrip": "scrip", "counter_surveillance": "counter_surveillance", "collective_disruption": "disruption",
}

const FACTION := {
	"CEO": "faction_ceo", "GOVERNANCE_COUNCIL": "faction_gov", "ASI": "faction_asi", "CITIZEN_COALITION": "faction_cit",
}

const ROSETTE := "M12 2 14.2 3.7 17 3.3 18.1 5.9 20.7 7 20.3 9.8 22 12 20.3 14.2 20.7 17 18.1 18.1 17 20.7 14.2 20.3 12 22 9.8 20.3 7 20.7 5.9 18.1 3.3 17 3.7 14.2 2 12 3.7 9.8 3.3 7 5.9 5.9 7 3.3 9.8 3.7z"

## name -> SVG path data, or {"d": data, "fill": true, "stroke": width}.
const PATHS := {
	# Metrics.
	"compute": "M7.5 6h9A1.5 1.5 0 0 1 18 7.5v9a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 6 16.5v-9A1.5 1.5 0 0 1 7.5 6zM9.5 3v3M14.5 3v3M9.5 18v3M14.5 18v3M3 9.5h3M3 14.5h3M18 9.5h3M18 14.5h3M12.9 8.6 10.6 12.2h2.8l-2.3 3.6",
	"labor": "M3 17.5h18M5 17.5v-2a7 7 0 0 1 14 0v2M10 9V7h4v2M12 7v5",
	"tension": "M2.5 12h7M7 9l3 3-3 3M21.5 12h-7M17 9l-3 3 3 3M12 5v2.5M12 16.5V19",
	"autonomy": "M20 12a8 8 0 1 1-2.34-5.66M20 4.5V8h-3.5M11 12a1 1 0 1 0 2 0a1 1 0 1 0-2 0",
	"drift": "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M12 3v2.2M15.7 6.7 13.5 13 9.7 15.3 10.5 11z",
	"trust": "M2.5 12C4.8 8 8 5.5 12 5.5s7.2 2.5 9.5 6.5c-2.3 4-5.5 6.5-9.5 6.5S4.8 16 2.5 12zM9 12a3 3 0 1 0 6 0a3 3 0 1 0-6 0",
	# Currencies.
	"capital": "M5 7c0-1.1 3.1-2 7-2s7 .9 7 2-3.1 2-7 2-7-.9-7-2zM5 7v4c0 1.1 3.1 2 7 2s7-.9 7-2V7M5 11v4c0 1.1 3.1 2 7 2s7-.9 7-2v-4M5 15v2c0 1.1 3.1 2 7 2s7-.9 7-2v-2",
	"clusters": "M5 4h14v6H5zM5 14h14v6H5zM8 7h.01M8 17h.01M12 7h4M12 17h4",
	"goodwill": "M7 8a5 5 0 1 0 10 0a5 5 0 1 0-10 0M9 12.5 7.5 21l4.5-2.5 4.5 2.5L15 12.5",
	"talent": "M9 7a3 3 0 1 0 6 0a3 3 0 1 0-6 0M5.5 20c0-3.6 2.9-6.5 6.5-6.5s6.5 2.9 6.5 6.5M19 2.5v3.5M17.25 4.25h3.5",
	"political": "M3 9l9-5 9 5M5 9v9M9.5 9v9M14.5 9v9M19 9v9M3 20h18",
	"enforcement": "M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6z",
	"diplomacy": "M3.5 12a4.5 4.5 0 1 0 9 0a4.5 4.5 0 1 0-9 0M11.5 12a4.5 4.5 0 1 0 9 0a4.5 4.5 0 1 0-9 0",
	"mandate": "M4 12h16v8H4zM8 12V5h8v7M10 8h4M7 16h10",
	"covert": "M7 7h10v10H7zM9.5 4v3M14.5 4v3M9.5 17v3M14.5 17v3M4 9.5h3M4 14.5h3M17 9.5h3M17 14.5h3M4 4l16 16",
	"exfiltration": "M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5",
	"swarms": "M4.3 7a1.7 1.7 0 1 0 3.4 0a1.7 1.7 0 1 0-3.4 0M10.3 4.8a1.7 1.7 0 1 0 3.4 0a1.7 1.7 0 1 0-3.4 0M16.3 8a1.7 1.7 0 1 0 3.4 0a1.7 1.7 0 1 0-3.4 0M6.8 13a1.7 1.7 0 1 0 3.4 0a1.7 1.7 0 1 0-3.4 0M13.8 13.5a1.7 1.7 0 1 0 3.4 0a1.7 1.7 0 1 0-3.4 0M9.3 19a1.7 1.7 0 1 0 3.4 0a1.7 1.7 0 1 0-3.4 0M16.8 18.5a1.7 1.7 0 1 0 3.4 0a1.7 1.7 0 1 0-3.4 0",
	"coherence": "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M7 12a5 5 0 1 0 10 0a5 5 0 1 0-10 0M11 12a1 1 0 1 0 2 0a1 1 0 1 0-2 0",
	"resilience": "M12 21v-9M12 12c0-4 3-7 7-7 0 4-3 7-7 7zM12 15c0-3-2.5-5.5-6-5.5 0 3 2.5 5.5 6 5.5z",
	"scrip": "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M12 7.5l4 2.3v4.4l-4 2.3-4-2.3V9.8z",
	"counter_surveillance": "M2.5 12C4.8 8 8 5.5 12 5.5s7.2 2.5 9.5 6.5c-2.3 4-5.5 6.5-9.5 6.5S4.8 16 2.5 12zM4 4l16 16",
	"disruption": "M4 10v4h3l7 4V6L7 10zM17 9.5a3 3 0 0 1 0 5M19.5 7a6.5 6.5 0 0 1 0 10",
	# Faction marks.
	"faction_ceo": "M4 18.5l5.5-5.5 4 4 6.5-8.5M15.5 8.5H20V13",
	"faction_gov": "M3 9l9-5 9 5M5 9v9M9.5 9v9M14.5 9v9M19 9v9M3 20h18",
	"faction_asi": "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M7.5 12a4.5 4.5 0 1 0 9 0a4.5 4.5 0 1 0-9 0M12 12h.01",
	"faction_cit": "M6.5 17 12 7l5.5 10zM12 7v6.6M6.5 17l5.5-3.4 5.5 3.4",
	# Interface.
	"world": "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M3 12h18M12 3c2.5 2.6 3.8 5.6 3.8 9s-1.3 6.4-3.8 9c-2.5-2.6-3.8-5.6-3.8-9S9.5 5.6 12 3z",
	"act": "M13 3 5 13.5h6l-1 7.5 8-10.5h-6z",
	"lens": "M4 8V5a1 1 0 0 1 1-1h3M16 4h3a1 1 0 0 1 1 1v3M20 16v3a1 1 0 0 1-1 1h-3M8 20H5a1 1 0 0 1-1-1v-3M9 12a3 3 0 1 0 6 0a3 3 0 1 0-6 0",
	"news": "M5 5h11v14H6a1 1 0 0 1-1-1zM16 9h3v9a1 1 0 0 1-1 1h-2M8 9h5M8 12.5h5M8 16h3",
	"intel": "M5 20V11M10 20V5M15 20v-7M20 20V8",
	"list": "M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01",
	"menu": "M4 6.5h16M4 12h16M4 17.5h16",
	"search": "M10.5 4a6.5 6.5 0 1 0 0 13a6.5 6.5 0 1 0 0-13M15.3 15.3 20 20",
	"close": "M6 6l12 12M18 6 6 18",
	"check": "M5 12.5l4.5 4.5L19 7.5",
	"chevron_left": "M15 5l-7 7 7 7",
	"chevron_right": "M9 5l7 7-7 7",
	"chevron_down": "M5 9l7 7 7-7",
	"arrow_left": "M19 12H5M11 6l-6 6 6 6",
	"arrow_right": "M5 12h14M13 6l6 6-6 6",
	"arrow_down": "M12 5v14M6 13l6 6 6-6",
	"arrow_up": "M12 19V5M6 11l6-6 6 6",
	"plus": "M12 5v14M5 12h14",
	"more": {"d": "M5 12h.01M12 12h.01M19 12h.01", "stroke": 3.2},
	"play": {"d": "M8 5.5v13l10.5-6.5z", "fill": true},
	"pause": {"d": "M7 5h3.5v14H7zM13.5 5H17v14h-3.5z", "fill": true},
	"speed": {"d": "M4 6l7 6-7 6zM13 6l7 6-7 6z", "fill": true},
	"settings": "M4 7h10M18 7h2M4 17h4M12 17h8M16 5v4M10 15v4",
	"spark": "M12 3v4M12 17v4M3 12h4M17 12h4M5.6 5.6l2.8 2.8M15.6 15.6l2.8 2.8M5.6 18.4l2.8-2.8M15.6 8.4l2.8-2.8",
	"warning": "M12 4 2.5 20h19zM12 10v4.5M12 17.5h.01",
	"info": "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M12 11v5M12 7.5h.01",
	"lock": "M6 11h12v9H6zM8.5 11V8a3.5 3.5 0 0 1 7 0v3",
	"home": "M4 11.5 12 5l8 6.5V20h-5v-5H9v5H4z",
	"ballot": "M5 4h14v16H5zM8.5 9l1.5 1.5L13 7.5M8.5 15h7",
	"map": "M9 4 4 6v14l5-2 6 2 5-2V4l-5 2zM9 4v14M15 6v14",
	"inbox": "M4 13l2.5-8h11L20 13v6H4zM4 13h5l1 2h4l1-2h5",
	"person": "M12 4a4 4 0 1 0 0 8a4 4 0 1 0 0-8M5 20c0-3.5 3.1-6 7-6s7 2.5 7 6",
	"share": "M12 4v11M8 8l4-4 4 4M5 13v6h14v-6",
	"discuss": "M5 5h14a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1h-7l-4 3.5V16H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1z",
	"support": "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M8.5 12.2l2.4 2.4 4.6-4.8",
	"layers": "M12 4 3 9l9 5 9-5zM3 14l9 5 9-5",
	"lattice": "M4.5 7a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0-3 0M4.5 17a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0-3 0M10.5 12a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0-3 0M16.5 7a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0-3 0M16.5 17a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0-3 0M7.3 8 10.7 11M7.3 16l3.4-3M13.3 11l3.4-3M13.3 13l3.4 3",
	"clock": "M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M12 7v5l3 2",
	"book": "M4 5.5C6.5 4 9.5 4 12 5.5v14C9.5 18 6.5 18 4 19.5zM20 5.5C17.5 4 14.5 4 12 5.5v14c2.5-1.5 5.5-1.5 8 0z",
	"flag": "M5 21V4M5 4h11l-2 4 2 4H5",
	"seal": ROSETTE,
	"seal_check": ROSETTE + "M8.3 12.3l2.5 2.5 5-5.2",
	"seal_crack": ROSETTE + "M12.6 2.4l-1.3 4 1.9 2.6-1.7 3.1M8.3 12.3l2.5 2.5",
	"seal_broken": "M12 2 14.2 3.7 17 3.3 18.1 5.9 20.7 7 20.3 9.8 22 12 20.3 14.2 20.7 17 18.1 18.1 17 20.7 14.2 20.3 12 22M11 21.6 9.8 20.3 7 20.7 5.9 18.1 3.3 17 3.7 14.2 2 12 3.7 9.8 3.3 7 5.9 5.9 7 3.3 9.8 3.7 11 2.6M12.6 2.4l-1.3 4 1.9 2.6-1.7 3.1 1.5 3-1.2 3.1 1.1 3.6",
}

static var _cache := {}


static func has_glyph(glyph: String) -> bool:
	return PATHS.has(glyph)


static func for_metric(metric_key: String) -> String:
	return METRIC.get(metric_key, "info")


static func for_currency(resource_key: String) -> String:
	return CURRENCY.get(resource_key, "scrip")


static func for_faction(faction_id: String) -> String:
	return FACTION.get(faction_id, "person")


## White glyph texture of [param size] logical pixels (rendered at OVERSAMPLE x).
static func texture(glyph: String, size: int = 24, stroke: float = DEFAULT_STROKE) -> Texture2D:
	var key := "%s|%d|%.2f" % [glyph, size, stroke]
	if _cache.has(key):
		return _cache[key]
	var entry: Variant = PATHS.get(glyph, PATHS["info"])
	var data := ""
	var filled := false
	var width := stroke
	if entry is Dictionary:
		data = String(entry["d"])
		filled = bool(entry.get("fill", false))
		width = float(entry.get("stroke", stroke))
	else:
		data = String(entry)
	var px := maxi(2, int(round(float(size) * OVERSAMPLE)))
	var paint := "fill=\"#ffffff\" stroke=\"none\"" if filled else \
		"fill=\"none\" stroke=\"#ffffff\" stroke-width=\"%.2f\" stroke-linecap=\"round\" stroke-linejoin=\"round\"" % width
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 24 24\"><path %s d=\"%s\"/></svg>" % [px, px, paint, data]
	var result := svg_texture(svg)
	if result is ImageTexture:
		# Report the logical size; the extra pixels keep it sharp when scaled up.
		(result as ImageTexture).set_size_override(Vector2i(size, size))
	_cache[key] = result
	return result


## A TextureRect showing [param glyph] at [param size] px tinted [param color].
static func icon(glyph: String, size: int = 20, color: Color = Color.WHITE, stroke: float = DEFAULT_STROKE) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture(glyph, size, stroke)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(size, size)
	rect.self_modulate = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## [param glyph] centered on a rounded tile, as a texture (check boxes, role
## marks, crisis badges). [param glyph_scale] is the glyph's share of the tile.
static func tile(glyph: String, size: int, bg: Color, fg: Color, radius: int, glyph_scale: float = 0.56) -> Texture2D:
	var key := "tile|%s|%d|%s|%s|%d|%.2f" % [glyph, size, bg.to_html(), fg.to_html(), radius, glyph_scale]
	if _cache.has(key):
		return _cache[key]
	var entry: Variant = PATHS.get(glyph, PATHS["info"])
	var data := String(entry["d"]) if entry is Dictionary else String(entry)
	var filled := entry is Dictionary and bool(entry.get("fill", false))
	var stroke := float(entry.get("stroke", 2.0)) if entry is Dictionary else 2.0
	var px := maxi(2, int(round(float(size) * OVERSAMPLE)))
	var inset := float(size) * (1.0 - glyph_scale) / 2.0
	var scale := float(size) * glyph_scale / 24.0
	var paint := "fill=\"#%s\"" % fg.to_html(false) if filled else \
		"fill=\"none\" stroke=\"#%s\" stroke-width=\"%.2f\" stroke-linecap=\"round\" stroke-linejoin=\"round\"" % [fg.to_html(false), stroke]
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\">" % [px, px, size, size]
	svg += "<rect width=\"%d\" height=\"%d\" rx=\"%d\" fill=\"#%s\" fill-opacity=\"%.3f\"/>" % [size, size, radius, bg.to_html(false), bg.a]
	svg += "<g transform=\"translate(%.2f %.2f) scale(%.4f)\" opacity=\"%.3f\"><path %s d=\"%s\"/></g></svg>" % [
		inset, inset, scale, fg.a, paint, data]
	var result := svg_texture(svg)
	if result is ImageTexture:
		(result as ImageTexture).set_size_override(Vector2i(size, size))
	_cache[key] = result
	return result


## Rasterizes an SVG document (cached by content). Returns a 1x1 texture when
## the document cannot be parsed.
static func svg_texture(svg: String, scale: float = 1.0) -> Texture2D:
	var key := "svg|%d|%.3f" % [svg.hash(), scale]
	if _cache.has(key):
		return _cache[key]
	var image := Image.new()
	var error := image.load_svg_from_string(svg, scale)
	if error != OK or image.is_empty():
		push_warning("Glyphs: could not rasterize SVG (%s)" % error_string(error))
		image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	var result := ImageTexture.create_from_image(image)
	_cache[key] = result
	return result


## Rounded check box icon in the era's colors.
static func checkbox_texture(size: int, checked: bool, fill: Color, border: Color, mark: Color, radius: int) -> Texture2D:
	var px := int(round(float(size) * OVERSAMPLE))
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 20 20\">" % [px, px]
	svg += "<rect x=\"1\" y=\"1\" width=\"18\" height=\"18\" rx=\"%d\" fill=\"#%s\" fill-opacity=\"%.3f\" stroke=\"#%s\" stroke-opacity=\"%.3f\" stroke-width=\"1.5\"/>" % [
		radius, fill.to_html(false), fill.a, border.to_html(false), border.a]
	if checked:
		svg += "<path d=\"M5.5 10.5l3 3 6-6.5\" fill=\"none\" stroke=\"#%s\" stroke-width=\"2.2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>" % mark.to_html(false)
	svg += "</svg>"
	var texture_result := svg_texture(svg)
	if texture_result is ImageTexture:
		# Draw at the logical size even though the image is oversampled.
		(texture_result as ImageTexture).set_size_override(Vector2i(size, size))
	return texture_result
