class_name CrisisArt
extends RefCounted
## Flat illustrations for the crisis categories: one composition per
## DilemmaDeck category and a radar for anything else (CRISIS). Each is an SVG
## drawn in the era's palette (EraStyle) and rasterized with
## Glyphs.svg_texture at twice the requested size, then cached.
##
## Compositions are designed on a 440x180 canvas and cropped around the center
## to the requested aspect ratio, so subjects stay inside x 30..410, y 16..164.
## Pass [param top_corners] to cut the top corners to a card's shape (rounded,
## or chamfered in Era II) so the art sits flush inside the card.
##
##   var art := CrisisArt.texture_for("ENERGY", 2, Vector2i(420, 190))

const CATEGORIES := ["ALIGNMENT", "ECONOMY", "ENERGY", "EPISTEMIC", "GEOPOLITICS", "LABOR", "RACE", "SECURITY",
	"SOCIETY", "SOVEREIGNTY", "UNREST", "BIOSECURITY", "ROBOTICS", "CULTURE", "PERSONHOOD", "SPACE", "CRISIS"]
const FALLBACK := "CRISIS"
const DESIGN := Vector2(440.0, 180.0)
const OVERSAMPLE := 2.0
## The metric whose color tints each category's sky.
const TINT := {
	"ALIGNMENT": "algorithmic_autonomy", "ECONOMY": "labor_displacement", "ENERGY": "compute_energy_sat",
	"EPISTEMIC": "epistemic_trust", "GEOPOLITICS": "geopolitical_tension", "LABOR": "labor_displacement",
	"RACE": "algorithmic_autonomy", "SECURITY": "geopolitical_tension", "SOCIETY": "epistemic_trust",
	"SOVEREIGNTY": "compute_energy_sat", "UNREST": "labor_displacement", "BIOSECURITY": "alignment_drift",
	"ROBOTICS": "labor_displacement", "CULTURE": "epistemic_trust", "PERSONHOOD": "algorithmic_autonomy",
	"SPACE": "compute_energy_sat", "CRISIS": "alignment_drift",
}

static var _cache := {}


## The illustration for [param category] in [param era] at [param size]
## logical pixels (cached). Unknown categories get the CRISIS radar.
static func texture_for(category: String, era: int, size: Vector2i, top_corners: Vector2 = Vector2.ZERO) -> Texture2D:
	var scene := category_key(category)
	var era_key := clampi(era, 1, 3)
	var pixels := Vector2i(maxi(size.x, 4), maxi(size.y, 4))
	var key := "%s|%d|%dx%d|%.1f|%.1f" % [scene, era_key, pixels.x, pixels.y, top_corners.x, top_corners.y]
	if _cache.has(key):
		return _cache[key]
	var result := Glyphs.svg_texture(svg(scene, era_key, pixels, top_corners))
	if result is ImageTexture:
		(result as ImageTexture).set_size_override(pixels)
	_cache[key] = result
	return result


## The composition used for [param category] (CRISIS when unknown).
static func category_key(category: String) -> String:
	var upper := category.strip_edges().to_upper()
	return upper if CATEGORIES.has(upper) else FALLBACK


## The SVG document for a category, era and output size.
static func svg(category: String, era: int, size: Vector2i, top_corners: Vector2 = Vector2.ZERO) -> String:
	var p := palette(era, category)
	var view := _view_rect(Vector2(size))
	var out := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"%.2f %.2f %.2f %.2f\">" % [
		roundi(size.x * OVERSAMPLE), roundi(size.y * OVERSAMPLE), view.position.x, view.position.y, view.size.x, view.size.y]
	out += _defs(p, view, top_corners * (view.size.x / maxf(1.0, float(size.x))))
	out += "<g clip-path=\"url(#card)\">" if top_corners != Vector2.ZERO else "<g>"
	out += _background(p) + scene_svg(category_key(category), p) + "</g></svg>"
	return out


## Colors for one era, with the sky tinted by the category's metric.
static func palette(era: int, category: String = FALLBACK) -> Dictionary:
	var s := EraStyle.for_era(era)
	var tint: Color = s.metric.get(String(TINT.get(category_key(category), "")), s.accent)
	return {
		"era": s.era,
		"sky_top": s.bg.lerp(s.surface, 0.55).lerp(tint, 0.05),
		"sky_bottom": s.surface.lerp(tint, 0.2),
		"grid": Color(s.text, 0.06) if s.era == 1 else Color(s.accent, 0.11 if s.era == 2 else 0.08),
		"ink": s.raised.lerp(tint, 0.12).lerp(s.bg, 0.15),
		"ink2": s.raised.lerp(s.text, 0.16),
		"deep": s.bg,
		"line": s.text_dim.lerp(s.surface, 0.35),
		"light": s.text_bright,
		"accent": s.accent,
		"good": s.good,
		"warm": s.warn,
		"hot": s.critical,
		"lit": s.globe.get("lights", s.warn),
		"tint": tint,
		"compute": s.metric_color("compute_energy_sat"),
		"labor": s.metric_color("labor_displacement"),
		"tension": s.metric_color("geopolitical_tension"),
		"autonomy": s.metric_color("algorithmic_autonomy"),
		"drift": s.metric_color("alignment_drift"),
		"trust": s.metric_color("epistemic_trust"),
		"glow": s.faction_color("ASI"),
		"round": 1.0 if s.era == 1 else (0.35 if s.era == 2 else 1.8),
		"chamfer": s.corner_detail <= 1,
	}


## The scene's shapes (without background) for a category key.
static func scene_svg(category: String, p: Dictionary) -> String:
	match category:
		"ALIGNMENT":
			return _alignment(p)
		"ECONOMY":
			return _economy(p)
		"ENERGY":
			return _energy(p)
		"EPISTEMIC":
			return _epistemic(p)
		"GEOPOLITICS":
			return _geopolitics(p)
		"LABOR":
			return _labor(p)
		"RACE":
			return _race(p)
		"SECURITY":
			return _security(p)
		"SOCIETY":
			return _society(p)
		"SOVEREIGNTY":
			return _sovereignty(p)
		"UNREST":
			return _unrest(p)
		# Placeholders until these categories get scenes of their own.
		"BIOSECURITY":
			return _security(p)
		"ROBOTICS":
			return _labor(p)
		"CULTURE":
			return _society(p)
		"PERSONHOOD":
			return _alignment(p)
		"SPACE":
			return _energy(p)
	return _crisis(p)


# --- Canvas ------------------------------------------------------------------------

## The part of the design canvas that fills [param size] (centered crop).
static func _view_rect(size: Vector2) -> Rect2:
	var aspect := size.x / maxf(1.0, size.y)
	var design_aspect := DESIGN.x / DESIGN.y
	if aspect >= design_aspect:
		var height := DESIGN.x / aspect
		return Rect2(0.0, (DESIGN.y - height) * 0.5, DESIGN.x, height)
	var width := DESIGN.y * aspect
	return Rect2((DESIGN.x - width) * 0.5, 0.0, width, DESIGN.y)


static func _defs(p: Dictionary, view: Rect2, corners: Vector2) -> String:
	var out := "<defs><linearGradient id=\"sky\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></linearGradient>" % [
		_hex(p["sky_top"]), _hex(p["sky_bottom"])]
	out += _radial("glowA", p["accent"], 0.32) + _radial("glowB", p["glow"], 0.26) + _radial("halo", p["tint"], 0.22)
	out += _radial("fire", p["warm"], 0.3) + _radial("lamp", p["lit"], 0.4)
	if corners != Vector2.ZERO:
		out += "<clipPath id=\"card\"><path d=\"%s\"/></clipPath>" % _top_corner_path(view, corners, bool(p["chamfer"]))
	return out + "</defs>"


static func _radial(id: String, color: Color, opacity: float) -> String:
	return "<radialGradient id=\"%s\" cx=\"0.5\" cy=\"0.5\" r=\"0.5\"><stop offset=\"0\" stop-color=\"%s\" stop-opacity=\"%.2f\"/><stop offset=\"1\" stop-color=\"%s\" stop-opacity=\"0\"/></radialGradient>" % [
		id, _hex(color), opacity, _hex(color)]


## The view rectangle with its top corners rounded (or chamfered).
static func _top_corner_path(view: Rect2, corners: Vector2, chamfer: bool) -> String:
	var x0 := view.position.x
	var y0 := view.position.y
	var x1 := view.end.x
	var y1 := view.end.y
	var left := minf(corners.x, view.size.y)
	var right := minf(corners.y, view.size.y)
	if chamfer:
		return "M%.2f %.2f L%.2f %.2f L%.2f %.2f L%.2f %.2f L%.2f %.2f L%.2f %.2f Z" % [
			x0, y0 + left, x0 + left, y0, x1 - right, y0, x1, y0 + right, x1, y1, x0, y1]
	return "M%.2f %.2f A%.2f %.2f 0 0 1 %.2f %.2f L%.2f %.2f A%.2f %.2f 0 0 1 %.2f %.2f L%.2f %.2f L%.2f %.2f Z" % [
		x0, y0 + left, left, left, x0 + left, y0, x1 - right, y0, right, right, x1, y0 + right, x1, y1, x0, y1]


static func _background(p: Dictionary) -> String:
	var out := "<rect width=\"440\" height=\"180\" fill=\"url(#sky)\"/>"
	match int(p["era"]):
		1:
			var d := ""
			for x in range(44, 440, 44):
				d += "M%d 0V180" % x
			for y in range(36, 180, 36):
				d += "M0 %dH440" % y
			out += _path(d, _stroke(p["grid"], 1.0))
		2:
			var d := ""
			for x in range(22, 440, 22):
				d += "M%d 0V180" % x
			for y in range(18, 180, 18):
				d += "M0 %dH440" % y
			out += _path(d, _stroke(p["grid"], 0.8))
			out += _path("M0 171H440", _stroke(p["accent"], 1.0, 0.25))
		_:
			out += "<circle cx=\"60\" cy=\"10\" r=\"170\" fill=\"url(#glowA)\"/><circle cx=\"410\" cy=\"190\" r=\"180\" fill=\"url(#glowB)\"/>"
			out += _path("M-10 140C80 100 140 170 230 128S360 80 450 110M-10 52C70 24 150 70 240 40S370 8 450 30", _stroke(p["grid"], 1.4))
	return out


# --- Scenes ------------------------------------------------------------------------

## A model rewriting its own training code: a chip inside a dashed orbit,
## diff lines on the left, a climbing reward trace on the right.
static func _alignment(p: Dictionary) -> String:
	var out := "<circle cx=\"262\" cy=\"90\" r=\"96\" fill=\"url(#halo)\"/>"
	out += _circle(262, 90, 66, _stroke(p["drift"], 2.0) + " stroke-dasharray=\"7 7\"")
	out += _path("M306 38l9 -3 -1 9", _stroke(p["drift"], 2.2))
	var chip: Color = p["autonomy"]
	out += _rect(220, 48, 84, 84, 14 * float(p["round"]), _fill(chip.lerp(p["deep"], 0.72)) + " " + _paint(chip, 2.0))
	out += _path("M234 48v-10M252 48v-10M270 48v-10M288 48v-10M234 132v10M252 132v10M270 132v10M288 132v10M220 62h-10M220 80h-10M220 98h-10M220 116h-10M304 62h10M304 80h10M304 98h10M304 116h10",
		_stroke(chip, 2.0))
	out += _path("M280 90a18 18 0 1 1-5.3-12.7M281 70v8h-8", _stroke(p["light"], 3.0))
	# Diff lines: + rows tinted with the accent, the - row with the alarm color.
	var rows := [[44, 104, true], [66, 88, false], [88, 116, true], [110, 74, true], [132, 96, true]]
	for row in rows:
		var y := float(row[0])
		var width := float(row[1])
		var added: bool = row[2]
		var tone: Color = p["accent"] if added else p["hot"]
		out += _rect(36, y, width, 16, 3 * float(p["round"]), _fill(tone, 0.22))
		out += _path("M41 %.1fh6%s" % [y + 8.0, ("M44 %.1fv6" % (y + 5.0)) if added else ""], _stroke(tone.lerp(p["light"], 0.35), 1.6))
		var x := 54.0
		for token in [18.0, 10.0, 24.0, 14.0]:
			if x + token > 36.0 + width - 6.0:
				break
			out += _path("M%.1f %.1fh%.1f" % [x, y + 8.0, token], _stroke(p["light"], 2.2, 0.55))
			x += token + 6.0
	out += _path("M330 150h14v-14h14v-10h14v-22h14v-16h14v-26", _stroke(p["warm"], 2.2))
	out += _circle(400, 36, 3.5, _fill(p["warm"]))
	return out


## A brownout: a city with dark windows, a lightning bolt, a pylon and a
## glowing datacenter drawing the power.
static func _energy(p: Dictionary) -> String:
	var out := _circle(74, 40, 16, _fill(p["light"], 0.85))
	out += _circle(68, 36, 13, _fill(p["sky_top"], 0.55))
	for star in [[128, 22], [176, 46], [36, 70], [232, 16], [380, 22], [410, 60], [150, 64]]:
		out += _circle(float(star[0]), float(star[1]), 1.2, _fill(p["light"], 0.5))
	out += _path("M206 18l-14 30h12l-8 26 26-36h-13l9-20z", _fill(p["warm"]))
	out += _path("M290 30l-16 120M290 30l16 120M280 70h20M276 96h28M271 124h38M282 52h16M290 30v-8", _stroke(p["line"], 2.0))
	out += _path("M298 40c30 6 52 18 120 22M282 40c-34 8-60 22-90 26", _stroke(p["line"], 1.2))
	out += _circle(362, 128, 46, _fill(p["compute"], 0.09))
	out += _rect(332, 100, 60, 64, 3 * float(p["round"]), _fill(p["compute"].lerp(p["deep"], 0.8)) + " " + _paint(p["compute"], 1.5))
	out += _path("M340 112h44M340 124h44M340 136h44M340 148h44", _stroke(p["compute"], 1.5, 0.8))
	var towers := [[20, 96, 34], [58, 78, 40], [102, 110, 30], [136, 88, 44], [184, 118, 34], [222, 104, 28]]
	for tower in towers:
		out += _rect(float(tower[0]), float(tower[1]), float(tower[2]), 180.0 - float(tower[1]), 0, _fill(p["ink"]))
	var lit := [[26, 104], [40, 118], [64, 88], [142, 98], [108, 122], [156, 126], [192, 128], [228, 112]]
	var dark := [[40, 104], [26, 118], [78, 88], [64, 104], [78, 120], [118, 122], [156, 98], [142, 112], [206, 128], [242, 124], [64, 136], [142, 140]]
	for window in lit:
		out += _rect(float(window[0]), float(window[1]), 6, 6, 0, _fill(p["lit"]))
	for window in dark:
		out += _rect(float(window[0]), float(window[1]), 6, 6, 0, _fill(p["ink2"], 0.8))
	return out


## Export controls: a stack of chips, a striped barrier, a fab and a price
## line shooting up.
static func _geopolitics(p: Dictionary) -> String:
	var out := ""
	var chip_box := _fill(p["compute"].lerp(p["deep"], 0.75)) + " " + _paint(p["compute"], 1.5)
	for chip in [[34, 108], [90, 108], [62, 62]]:
		var x := float(chip[0])
		var y := float(chip[1])
		out += _rect(x, y, 50, 40, 3 * float(p["round"]), chip_box)
		out += _rect(x + 16, y + 12, 18, 16, 2, _stroke(p["compute"].lerp(p["light"], 0.4), 1.5))
		out += _path("M%.1f %.1fv-6M%.1f %.1fv-6M%.1f %.1fv-6" % [x + 14, y, x + 25, y, x + 36, y], _stroke(p["compute"], 1.4, 0.7))
	out += "<clipPath id=\"bar\"><rect x=\"180\" y=\"40\" width=\"22\" height=\"124\"/></clipPath>"
	out += _rect(180, 40, 22, 124, 0, _fill(p["light"], 0.92))
	var stripes := ""
	for i in 10:
		var y := 40.0 + i * 16.0
		stripes += "M180 %.1fL202 %.1fV%.1fL180 %.1fZ" % [y + 6.0, y - 4.0, y + 4.0, y + 14.0]
	out += "<g clip-path=\"url(#bar)\">" + _path(stripes, _fill(p["hot"])) + "</g>"
	out += _rect(176, 34, 30, 8, 2, _fill(p["ink2"]))
	out += _path("M248 164V110l22 14V110l22 14V110l22 14V86h20v78z", _fill(p["ink"]) + " " + _paint(p["line"], 1.5))
	out += _path("M318 86V58h10v28", _fill(p["ink"]) + " " + _paint(p["line"], 1.5))
	out += _circle(323, 46, 6, _fill(p["line"], 0.25))
	out += _circle(331, 34, 8, _fill(p["line"], 0.18))
	out += _path("M236 74l26-24 16 12 44-40", _stroke(p["warm"], 2.6))
	out += _path("M308 22h14v14", _stroke(p["warm"], 2.6))
	out += _path("M352 52l8-8 8 8M352 64l8-8 8 8M352 76l8-8 8 8", _stroke(p["warm"], 2.2, 0.85))
	return out


## A market crash: candles climbing then plunging, a falling arrow and a
## toppled stack of coins.
static func _economy(p: Dictionary) -> String:
	var out := _path("M30 156H410", _stroke(p["line"], 1.2, 0.8))
	var closes := [118.0, 110.0, 114.0, 102.0, 96.0, 100.0, 88.0, 80.0, 74.0, 104.0, 128.0, 146.0]
	var previous := 124.0
	var trace := ""
	for i in closes.size():
		var x := 40.0 + i * 22.0
		var close: float = closes[i]
		var rising := close < previous
		var tone: Color = p["good"] if rising else p["hot"]
		var top := minf(close, previous)
		var bottom := maxf(close, previous)
		out += _path("M%.1f %.1fV%.1f" % [x + 6.0, top - 7.0, bottom + 7.0], _stroke(tone, 1.4, 0.8))
		out += _rect(x, top, 12, maxf(3.0, bottom - top), 1.5 * float(p["round"]), _fill(tone, 0.9))
		trace += ("M" if i == 0 else "L") + "%.1f %.1f" % [x + 6.0, close]
		previous = close
	out += _path(trace, _stroke(p["light"], 1.4, 0.45))
	out += _path("M300 52L326 92L338 80L366 128", _stroke(p["hot"], 4.0))
	out += _path("M350 128h16v-16", _stroke(p["hot"], 4.0))
	var coin := _fill(p["warm"].lerp(p["deep"], 0.35)) + " " + _paint(p["warm"], 1.6)
	for j in 4:
		var y := 150.0 - j * 8.0
		out += "<ellipse cx=\"392\" cy=\"%.1f\" rx=\"18\" ry=\"5.5\" %s/>" % [y, coin]
	out += "<ellipse cx=\"394\" cy=\"74\" rx=\"18\" ry=\"5.5\" transform=\"rotate(-28 394 74)\" %s/>" % coin
	out += "<ellipse cx=\"372\" cy=\"52\" rx=\"14\" ry=\"4.5\" transform=\"rotate(24 372 52)\" %s/>" % coin
	return out


## Deepfakes: a video frame whose face splits into color channels, a ballot
## box and a crossed-out eye.
static func _epistemic(p: Dictionary) -> String:
	var out := _rect(150, 22, 150, 136, 10 * float(p["round"]), _fill(p["deep"], 0.6) + " " + _paint(p["line"], 1.5))
	var face := "M200 150C200 128 196 120 190 112C184 104 184 86 190 74C198 58 222 54 236 64C246 71 250 82 248 92L254 102L248 106L250 116C250 124 242 126 236 126L234 150Z"
	out += _path(face, _fill(p["ink2"]))
	out += "<g transform=\"translate(-5 0)\">" + _path(face, _stroke(p["accent"], 2.0, 0.85)) + "</g>"
	out += "<g transform=\"translate(5 0)\">" + _path(face, _stroke(p["hot"], 2.0, 0.85)) + "</g>"
	out += _rect(160, 76, 92, 6, 0, _fill(p["accent"], 0.4))
	out += _rect(206, 98, 86, 4, 0, _fill(p["hot"], 0.45))
	out += _rect(150, 120, 64, 5, 0, _fill(p["light"], 0.22))
	out += _path("M162 140v12l10-6z", _fill(p["light"], 0.75))
	out += _path("M180 146h108", _stroke(p["line"], 2.0))
	out += _path("M180 146h62", _stroke(p["accent"], 2.0))
	out += "<g transform=\"rotate(-7 78 80)\">" + _rect(62, 56, 32, 40, 2, _fill(p["light"], 0.92))
	out += _path("M69 76l6 6 12-14", _stroke(p["accent"], 2.6)) + "</g>"
	out += _rect(38, 94, 80, 62, 4 * float(p["round"]), _fill(p["ink"]) + " " + _paint(p["line"], 1.5))
	out += _rect(58, 92, 40, 5, 2, _fill(p["deep"]))
	out += _path("M50 124h56", _stroke(p["line"], 1.2, 0.6))
	out += "<g transform=\"translate(326 52) scale(3)\">" + _path(String(Glyphs.PATHS["trust"]), _stroke(p["line"], 0.8)) + "</g>"
	out += _path("M334 130L398 54", _stroke(p["hot"], 3.0))
	return out


## Automation: workers fading out on the left, a robot arm loading boxes onto
## a conveyor.
static func _labor(p: Dictionary) -> String:
	var out := _rect(0, 156, 440, 24, 0, _fill(p["ink"], 0.7))
	var people := [[42, 1.0], [76, 0.72], [110, 0.48], [144, 0.26]]
	for person in people:
		var x := float(person[0])
		var alpha := float(person[1])
		out += _circle(x, 112, 8, _fill(p["ink2"], alpha))
		out += _path("M%.1f 156v-20a14 14 0 0 1 28 0v20z" % (x - 14.0), _fill(p["ink2"], alpha))
		out += _path("M%.1f 107a10 10 0 0 1 20 0z" % (x - 10.0), _fill(p["labor"], alpha))
		out += _path("M%.1f 107h24" % (x - 12.0), _stroke(p["labor"], 2.0, alpha))
	out += _rect(168, 136, 250, 14, 7, _fill(p["ink2"]) + " " + _paint(p["line"], 1.5))
	for i in 10:
		out += _circle(178.0 + i * 25.0, 143, 3.5, _fill(p["line"]))
	for box in [[188, 112, 24, 24], [238, 116, 20, 20], [282, 110, 26, 26]]:
		out += _rect(float(box[0]), float(box[1]), float(box[2]), float(box[3]), 2, _fill(p["warm"], 0.85) + " " + _paint(p["warm"].lerp(p["deep"], 0.4), 1.2))
		out += _path("M%.1f %.1fv%.1f" % [float(box[0]) + float(box[2]) * 0.5, float(box[1]), float(box[3])], _stroke(p["deep"], 1.2, 0.35))
	out += _rect(352, 120, 44, 14, 3 * float(p["round"]), _fill(p["ink2"]) + " " + _paint(p["accent"], 1.5))
	out += _path("M374 120L360 70L314 52", _stroke(p["accent"], 7.0))
	out += _path("M374 120L360 70L314 52", _stroke(p["deep"], 2.0, 0.45))
	for joint in [[374, 120, 6], [360, 70, 6], [314, 52, 5]]:
		out += _circle(float(joint[0]), float(joint[1]), float(joint[2]), _fill(p["deep"]) + " " + _paint(p["accent"], 2.0))
	out += _path("M314 52l-10 14M314 52l-16 4M304 66l-4 6M298 56l-6 2", _stroke(p["accent"], 3.0))
	out += _rect(286, 70, 18, 16, 2, _fill(p["warm"], 0.85))
	for lamp in [64.0, 128.0, 192.0]:
		out += _path("M%.1f 0V22" % lamp, _stroke(p["line"], 1.4))
		out += "<circle cx=\"%.1f\" cy=\"42\" r=\"26\" fill=\"url(#lamp)\"/>" % lamp
		out += _path("M%.1f 22h20l-5 9h-10z" % (lamp - 10.0), _fill(p["ink2"]) + " " + _paint(p["line"], 1.2))
		out += _circle(lamp, 32, 2.5, _fill(p["lit"], 0.9))
	return out


## The release race: two trajectories racing to a checkered flag, and a
## stopwatch.
static func _race(p: Dictionary) -> String:
	var out := _circle(74, 62, 28, _fill(p["ink"]) + " " + _paint(p["light"], 2.0))
	out += _rect(67, 26, 14, 7, 2, _fill(p["light"]))
	out += _path("M74 62L90 46", _stroke(p["warm"], 2.6))
	out += _path("M74 38v5M74 81v5M50 62h5M93 62h5", _stroke(p["light"], 1.6, 0.7))
	out += _circle(74, 62, 3, _fill(p["warm"]))
	out += _path("M30 164C120 156 200 128 256 84S324 34 352 26", _stroke(p["accent"], 3.2))
	out += _path("M30 172C130 166 210 144 266 104S330 62 360 52", _stroke(p["hot"], 3.2))
	out += _circle(352, 26, 5.5, _fill(p["accent"]))
	out += _circle(360, 52, 5.5, _fill(p["hot"]))
	out += _path("M322 36h-22M326 46h-30M332 62h-22M336 72h-30", _stroke(p["light"], 1.6, 0.4))
	out += _path("M378 22V158", _stroke(p["line"], 2.4))
	for row in 3:
		for column in 4:
			var light := (row + column) % 2 == 0
			out += _rect(378.0 + column * 8.0, 22.0 + row * 8.0, 8, 8, 0, _fill(p["light"] if light else p["deep"], 0.95))
	out += _rect(378, 22, 32, 24, 0, _stroke(p["light"], 1.0, 0.6))
	return out


## A zero-day cascade: a cracked shield and a network whose nodes flip to the
## alarm color with ripples and a swarm.
static func _security(p: Dictionary) -> String:
	var nodes := [[150, 40], [176, 140], [214, 84], [258, 126], [276, 46], [320, 98], [352, 152], [370, 40], [402, 104], [140, 96]]
	var infected := [false, false, true, true, true, true, true, true, true, false]
	var edges := [[9, 0], [9, 1], [9, 2], [0, 2], [1, 3], [2, 3], [2, 4], [3, 5], [4, 5], [4, 7], [5, 6], [5, 8], [7, 8], [6, 8]]
	var out := ""
	for edge in edges:
		var a: Array = nodes[edge[0]]
		var b: Array = nodes[edge[1]]
		var hot: bool = infected[edge[0]] or infected[edge[1]]
		out += _path("M%d %dL%d %d" % [a[0], a[1], b[0], b[1]], _stroke(p["hot"] if hot else p["line"], 1.6, 0.55 if hot else 0.7))
	for i in nodes.size():
		var node: Array = nodes[i]
		if infected[i]:
			out += _circle(float(node[0]), float(node[1]), 13, _stroke(p["hot"], 1.2, 0.35))
			out += _circle(float(node[0]), float(node[1]), 6, _fill(p["hot"]))
		else:
			out += _circle(float(node[0]), float(node[1]), 6, _fill(p["deep"]) + " " + _paint(p["accent"], 2.0))
	out += _circle(370, 40, 22, _stroke(p["hot"], 1.0, 0.2))
	for dot in [[384, 58], [392, 50], [396, 66], [404, 58], [380, 70], [410, 74], [388, 80], [400, 86]]:
		out += _circle(float(dot[0]), float(dot[1]), 1.8, _fill(p["hot"], 0.8))
	out += "<g transform=\"translate(26 34) scale(4)\">"
	out += _path(String(Glyphs.PATHS["enforcement"]), _fill(p["ink2"]) + " " + _paint(p["accent"], 0.5))
	out += _path("M12.5 4.5l-2 4.5 3 2.5-2.5 3.5 1.5 3", _stroke(p["hot"], 0.6))
	out += "</g>"
	return out


## A referendum: a crowd with a few highlighted voices and speech bubbles.
static func _society(p: Dictionary) -> String:
	var out := ""
	out += _bubble(64, 18, 72, 38, p, "M88 37l8 8 16-17", p["accent"])
	out += _bubble(180, 30, 84, 32, p, "M194 41h48M194 51h30", p["line"])
	out += _bubble(304, 16, 76, 38, p, "M318 30h44M318 40h28", p["line"])
	var rows := [[110.0, 0.8, 30.0, 0.0, p["ink"]], [134.0, 0.95, 36.0, 18.0, p["ink2"]], [162.0, 1.1, 44.0, 6.0, p["ink2"]]]
	var highlight := {"1:4": true, "2:7": true, "0:9": true, "2:2": true}
	for r in rows.size():
		var row: Array = rows[r]
		var base := float(row[0])
		var scale := float(row[1])
		var step := float(row[2])
		var x := float(row[3]) + 20.0
		var i := 0
		while x < 430.0:
			var tone: Color = row[4]
			if highlight.has("%d:%d" % [r, i]):
				tone = p["accent"]
			out += _person(x, base, scale, tone)
			x += step
			i += 1
	return out


## Nationalization: a capitol with a flag, a server rack chained and padlocked.
static func _sovereignty(p: Dictionary) -> String:
	var out := _path("M150 26V4", _stroke(p["light"], 1.5))
	out += _rect(150, 4, 24, 14, 0, _fill(p["hot"]))
	out += _path("M58 60L150 26L242 60Z", _fill(p["ink2"]) + " " + _paint(p["light"], 1.5))
	out += _rect(62, 60, 176, 10, 0, _fill(p["ink2"]) + " " + _paint(p["light"], 1.5))
	for x in [74, 106, 138, 170, 202]:
		out += _rect(float(x), 72, 16, 64, 0, _fill(p["ink"]) + " " + _paint(p["light"], 1.2, 0.7))
	out += _rect(54, 136, 192, 8, 0, _fill(p["ink2"]) + " " + _paint(p["light"], 1.2))
	out += _rect(46, 144, 208, 8, 0, _fill(p["ink2"]) + " " + _paint(p["light"], 1.2))
	out += _rect(290, 48, 84, 110, 4 * float(p["round"]), _fill(p["ink"]) + " " + _paint(p["compute"], 1.5))
	for i in 6:
		var y := 64.0 + i * 16.0
		out += _path("M298 %.1fH366" % y, _stroke(p["compute"], 1.0, 0.5))
		out += _circle(304, y - 7.0, 2, _fill(p["accent"] if i % 2 == 0 else p["lit"]))
		out += _circle(312, y - 7.0, 2, _fill(p["accent"], 0.5))
	for k in 7:
		var cx := 272.0 + k * 19.0
		var cy := 152.0 - k * 17.0
		out += "<ellipse cx=\"%.1f\" cy=\"%.1f\" rx=\"10\" ry=\"5\" transform=\"rotate(-42 %.1f %.1f)\" %s/>" % [cx, cy, cx, cy, _stroke(p["warm"], 2.6)]
	out += _path("M322 92v-8a10 10 0 0 1 20 0v8", _stroke(p["warm"], 3.2))
	out += _rect(316, 92, 32, 26, 4, _fill(p["warm"]))
	out += _circle(332, 103, 3.2, _fill(p["deep"]))
	out += _path("M332 105v6", _stroke(p["deep"], 2.2))
	return out


## Sabotage: a substation with a snapped line throwing sparks, flames, smoke
## and a crowd with raised fists.
static func _unrest(p: Dictionary) -> String:
	var out := "<circle cx=\"120\" cy=\"170\" r=\"110\" fill=\"url(#fire)\"/><circle cx=\"376\" cy=\"150\" r=\"70\" fill=\"url(#fire)\"/>"
	for cloud in [[372, 56, 14, 0.24], [390, 40, 19, 0.2], [414, 22, 24, 0.16], [352, 74, 10, 0.26]]:
		out += _circle(float(cloud[0]), float(cloud[1]), float(cloud[2]), _fill(p["line"], float(cloud[3])))
	out += _path("M250 160V48M330 160V48M246 48H334M250 80H330M250 80L290 48L330 80", _stroke(p["line"], 2.4))
	for x in [262, 290, 318]:
		for k in 3:
			out += _rect(float(x) - 4.0, 50.0 + k * 5.0, 8, 3.5, 1, _fill(p["light"], 0.75))
	out += _path("M262 50C226 38 196 44 150 36M290 50C250 30 220 30 180 22", _stroke(p["line"], 1.3))
	out += _path("M318 50C330 70 338 84 344 100", _stroke(p["line"], 1.5))
	out += _path("M344 100l12-8M344 100l14 2M344 100l7 11M344 100l-3 13M344 100l-10-6", _stroke(p["warm"], 2.2))
	out += _circle(344, 100, 4, _fill(p["light"]))
	out += _rect(348, 116, 58, 44, 4 * float(p["round"]), _fill(p["ink"]) + " " + _paint(p["line"], 1.5))
	out += _path("M358 124v28M368 124v28M378 124v28M388 124v28M398 124v28", _stroke(p["line"], 1.2, 0.7))
	out += _path("M356 162c-6-12 4-18 2-30 10 8 14 18 9 30z", _fill(p["hot"]))
	out += _path("M362 162c-3-6 2-10 1-16 5 4 7 10 4 16z", _fill(p["warm"]))
	out += _path("M392 162c-5-10 3-14 2-24 8 6 11 15 7 24z", _fill(p["hot"], 0.9))
	for figure in [[50.0, 0.0], [92.0, 1.0], [134.0, 0.0], [176.0, 1.0]]:
		var x := float(figure[0])
		out += _person(x, 164.0, 1.25, p["ink2"])
		if float(figure[1]) > 0.5:
			out += _path("M%.1f 132l10-30" % (x + 9.0), _stroke(p["ink2"], 5.0))
			out += _circle(x + 19.0, 100, 5, _fill(p["ink2"]))
	return out


## Fallback: a radar sweep with blips around a warning sign.
static func _crisis(p: Dictionary) -> String:
	var out := ""
	for r in [26, 52, 78]:
		out += _circle(220, 96, float(r), _stroke(p["accent"], 1.4, 0.35))
	out += _path("M220 96L298 70A82 82 0 0 0 270 30Z", _fill(p["accent"], 0.12))
	out += _path("M220 96L298 70", _stroke(p["accent"], 2.0))
	for blip in [[150, 58], [300, 132], [262, 154], [130, 140]]:
		out += _circle(float(blip[0]), float(blip[1]), 9, _stroke(p["hot"], 1.2, 0.4))
		out += _circle(float(blip[0]), float(blip[1]), 3.5, _fill(p["hot"]))
	out += _path("M220 62L252 118H188Z", _fill(p["warm"]) + " " + _paint(p["warm"], 3.0))
	out += _path("M220 80v18M220 106v2", _stroke(p["deep"], 4.0))
	return out


# --- Drawing helpers -----------------------------------------------------------------

static func _person(x: float, base: float, scale: float, tone: Color) -> String:
	var head := "<circle cx=\"%.1f\" cy=\"%.1f\" r=\"%.1f\" %s/>" % [x, base - 30.0 * scale, 7.0 * scale, _fill(tone)]
	var body := "M%.1f %.1fv%.1fa%.1f %.1f 0 0 1 %.1f 0v%.1fz" % [x - 12.0 * scale, base, -12.0 * scale, 12.0 * scale, 12.0 * scale, 24.0 * scale, 12.0 * scale]
	return head + _path(body, _fill(tone))


static func _bubble(x: float, y: float, width: float, height: float, p: Dictionary, marks: String, mark_color: Color) -> String:
	var out := _rect(x, y, width, height, 10 * float(p["round"]), _fill(p["light"], 0.92))
	out += _path("M%.1f %.1fl-4 12 14-12z" % [x + 18.0, y + height - 1.0], _fill(p["light"], 0.92))
	return out + _path(marks, _stroke(mark_color, 2.6))


static func _rect(x: float, y: float, width: float, height: float, radius: float, paint: String) -> String:
	return "<rect x=\"%.1f\" y=\"%.1f\" width=\"%.1f\" height=\"%.1f\" rx=\"%.1f\" %s/>" % [x, y, width, height, radius, paint]


static func _circle(x: float, y: float, radius: float, paint: String) -> String:
	return "<circle cx=\"%.1f\" cy=\"%.1f\" r=\"%.1f\" %s/>" % [x, y, radius, paint]


static func _path(data: String, paint: String) -> String:
	return "<path d=\"%s\" %s/>" % [data, paint]


static func _hex(color: Color) -> String:
	return "#" + color.to_html(false)


static func _fill(color: Color, opacity: float = 1.0) -> String:
	var alpha := clampf(color.a * opacity, 0.0, 1.0)
	if alpha >= 0.999:
		return "fill=\"%s\"" % _hex(color)
	return "fill=\"%s\" fill-opacity=\"%.3f\"" % [_hex(color), alpha]


## Stroke attributes without a fill, to combine with [method _fill].
static func _paint(color: Color, width: float, opacity: float = 1.0) -> String:
	var out := "stroke=\"%s\" stroke-width=\"%.2f\" stroke-linecap=\"round\" stroke-linejoin=\"round\"" % [_hex(color), width]
	var alpha := clampf(color.a * opacity, 0.0, 1.0)
	if alpha < 0.999:
		out += " stroke-opacity=\"%.3f\"" % alpha
	return out


static func _stroke(color: Color, width: float, opacity: float = 1.0) -> String:
	return "fill=\"none\" " + _paint(color, width, opacity)
