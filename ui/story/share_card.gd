class_name ShareCard
extends Node
## The ending as an image to share: a final edition of The Ledger (FrontPage's
## paper, ink and red, its blackletter masthead and news serif) with the
## end-state as the headline, the verdict and score, the role, the years, the
## scenario, difficulty, length and daily-challenge badges and three final
## numbers. Rendered offscreen at 1080x1350 (a 4:5 portrait that social apps
## show uncropped).
##
##   var card := ShareCard.new()
##   add_child(card)                                   # render() needs the tree
##   var image := await card.render(engine.result, {"daily": "2026-10-04", "mode": "quarter"})
##   var where := ShareCard.deliver(image, ShareCard.file_name(engine.result, extra))
##   DisplayServer.clipboard_set(ShareCard.share_text(engine.result, extra))
##
## [code]extra[/code]: "daily" ("YYYY-MM-DD" or ""), "mode" (CampaignModes id),
## "scenario" and "difficulty" (default to the result's), "seed".
## The headless dummy renderer draws nothing: render() then returns an empty
## Image, and deliver() returns "" for it.

const SIZE := Vector2i(1080, 1350)
const MARGIN := 64.0
const SITE := "https://shotif.github.io/synapse-2076/"
const SITE_SHORT := "shotif.github.io/synapse-2076"
const SHARE_DIR := "user://shares"
const PAPER := FrontPage.PAPER
const INK := FrontPage.INK
const INK_SOFT := FrontPage.INK_SOFT
const RED := FrontPage.RED
const RULE := FrontPage.RULE_LIGHT
## The three numbers the page prints.
const STATS := [["Public trust", WorldState.EPISTEMIC_TRUST], ["Alignment drift", WorldState.ALIGNMENT_DRIFT],
	["Algorithmic autonomy", WorldState.ALGORITHMIC_AUTONOMY]]


## Renders the page for [param result] (SimulationEngine.result) into an
## Image of SIZE. Await it. Returns an empty Image when nothing can be drawn
## (headless runs, or outside the scene tree).
func render(result: Dictionary, extra: Dictionary = {}) -> Image:
	var page := build_page(result, extra)
	if not is_inside_tree():
		page.free()
		return Image.new()
	var viewport := SubViewport.new()
	viewport.name = "ShareViewport"
	viewport.size = SIZE
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.add_child(page)
	add_child(viewport)
	await get_tree().process_frame
	var image := Image.new()
	# The headless dummy renderer never draws a frame and has no texture to read.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var drawn := viewport.get_texture().get_image()
		if drawn != null and not drawn.is_empty():
			image = drawn
	viewport.queue_free()
	return image


## One line to go with the image, e.g. "SYNAPSE-2076 · Daily 2026-10-04 ·
## Frontier Lab · End-state 3: Synthetic Eden · VICTORY 72 — https://...".
static func share_text(result: Dictionary, extra: Dictionary = {}) -> String:
	var outcome: Dictionary = result.get("outcome", {})
	var verdict: Dictionary = result.get("verdict", {})
	var parts: Array[String] = ["SYNAPSE-2076"]
	var daily := String(extra.get("daily", ""))
	if daily != "":
		parts.append("Daily %s" % daily)
	parts.append(UiFormat.role_name(String(result.get("player_role", ""))))
	parts.append("End-state %d: %s" % [int(outcome.get("number", 0)), String(outcome.get("name", "Unknown"))])
	parts.append("%s %d" % [String(verdict.get("verdict", "DEFEAT")), int(round(float(verdict.get("score", 0.0))))])
	return " · ".join(parts) + " — " + SITE


## "synapse-2076-synthetic-eden-daily-2026-10-04.png" or
## "synapse-2076-synthetic-eden-seed-2076.png".
static func file_name(result: Dictionary, extra: Dictionary = {}) -> String:
	var outcome := String((result.get("outcome", {}) as Dictionary).get("id", "ending")).to_lower().replace("_", "-")
	var daily := String(extra.get("daily", ""))
	var tail := ("daily-" + daily) if daily != "" else "seed-%d" % int(extra.get("seed", result.get("seed", 0)))
	return "synapse-2076-%s-%s.png" % [outcome, tail]


## Hands the PNG to the player: a download on the web build, a file in
## [param folder] elsewhere. Returns the file's path (its name on the web), or
## "" when there is nothing to save.
static func deliver(image: Image, name: String, folder: String = SHARE_DIR) -> String:
	if image == null or image.is_empty():
		return ""
	var clean := _clean_file_name(name)
	var png := image.save_png_to_buffer()
	if png.is_empty():
		return ""
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(png, clean, "image/png")
		return clean
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join(clean)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(png)
	file.close()
	return path


static func _clean_file_name(name: String) -> String:
	var out := ""
	for i in name.length():
		var c := name[i]
		out += c if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c in ["-", "_", "."] else "-"
	while out.begins_with("."):
		out = out.substr(1)
	if out.is_empty():
		out = "synapse-2076"
	return out if out.to_lower().ends_with(".png") else out + ".png"


# --- The page --------------------------------------------------------------------------

## The page as a Control of SIZE (also usable on screen as a preview).
static func build_page(result: Dictionary, extra: Dictionary = {}) -> Control:
	var outcome: Dictionary = result.get("outcome", {})
	var outcome_id := String(outcome.get("id", ""))
	var verdict: Dictionary = result.get("verdict", {})
	var verdict_name := String(verdict.get("verdict", "DEFEAT"))
	var role := String(result.get("player_role", ""))
	var end_turn := int(result.get("turn", SimConstants.TOTAL_TURNS))
	var year := int(floor(float(result.get("year", SimConstants.year_for_turn(end_turn)))))
	var era := SimConstants.era_for_year(float(year))
	var early := String(result.get("reason", "TURN_LIMIT")) != "TURN_LIMIT"
	var width := float(SIZE.x) - MARGIN * 2.0

	var page := PanelContainer.new()
	page.name = "SharePage"
	page.custom_minimum_size = Vector2(SIZE)
	page.size = Vector2(SIZE)
	var paper := StyleBoxFlat.new()
	paper.bg_color = PAPER
	paper.content_margin_left = MARGIN
	paper.content_margin_right = MARGIN
	paper.content_margin_top = MARGIN - 8.0
	paper.content_margin_bottom = MARGIN - 16.0
	page.add_theme_stylebox_override("panel", paper)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	page.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.add_child(_label("VOL. %s · NO. %d" % [StoryCopy.ROMAN.get(era, "I"), end_turn], "Newsreader-Medium.ttf", 20, INK,
		HORIZONTAL_ALIGNMENT_LEFT, 1, true))
	top.add_child(_label("EXTRA EDITION" if early else "FINAL EDITION", "Newsreader-SemiBold.ttf", 20, RED, HORIZONTAL_ALIGNMENT_CENTER, 2))
	top.add_child(_label("%d · %s" % [year, FrontPage.PRICES.get(era, "ONE CREDIT")], "Newsreader-Medium.ttf", 20, INK,
		HORIZONTAL_ALIGNMENT_RIGHT, 1, true))
	column.add_child(top)
	column.add_child(_rule(2.0, INK))
	var masthead := _label("The Ledger", "UnifrakturCook-Bold.ttf", 150, INK, HORIZONTAL_ALIGNMENT_CENTER)
	masthead.name = "Masthead"
	column.add_child(masthead)
	column.add_child(_double_rule())

	var kicker := "END-STATE %d OF 8 · %s" % [int(outcome.get("number", 0)), String(outcome.get("subtitle", "")).to_upper()]
	column.add_child(_wrapped(kicker, "Newsreader-SemiBold.ttf", 24, RED, HORIZONTAL_ALIGNMENT_CENTER, 3))
	var head := String(StoryCopy.OUTCOME_HEADS.get(outcome_id, String(outcome.get("name", "The century ends"))))
	var headline := _wrapped(StoryCopy.capitalize_first(head), "Newsreader-SemiBold.ttf", 74, INK, HORIZONTAL_ALIGNMENT_CENTER)
	headline.name = "Headline"
	headline.add_theme_constant_override("line_spacing", -8)
	column.add_child(_balanced(headline, width))
	var deck := _wrapped(String(outcome.get("description", "")), "Newsreader-MediumItalic.ttf", 30, INK_SOFT,
		HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_balanced(deck, width - 60.0))
	column.add_child(_rule(1.0, INK))
	column.add_child(_verdict_band(result, verdict_name, verdict, role))
	var others := _other_players(result)
	if others != "":
		column.add_child(_wrapped(others, "Newsreader-MediumItalic.ttf", 24, INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_rule(1.0, INK))
	column.add_child(_wrapped("THE %s IN THREE NUMBERS" % ("CENTURY" if not early else "STORY"), "Newsreader-SemiBold.ttf", 20, INK,
		HORIZONTAL_ALIGNMENT_CENTER, 3))
	column.add_child(_stats(result))
	column.add_child(_rule(1.0, RULE))
	column.add_child(_badges(result, extra))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	column.add_child(_rule(2.0, INK))
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	foot.add_child(_label("Play it free at %s" % SITE_SHORT, "Newsreader-MediumItalic.ttf", 24, INK, HORIZONTAL_ALIGNMENT_LEFT, 0, true))
	foot.add_child(_label("SEED %d" % int(extra.get("seed", result.get("seed", 0))), "Newsreader-Medium.ttf", 20, INK_SOFT,
		HORIZONTAL_ALIGNMENT_RIGHT, 2))
	column.add_child(foot)
	return page


## [seal] VICTORY / score  |  as the <role> / years
static func _verdict_band(result: Dictionary, verdict_name: String, verdict: Dictionary, role: String) -> Control:
	var band := HBoxContainer.new()
	band.name = "VerdictBand"
	band.add_theme_constant_override("separation", 22)
	var seal := TextureRect.new()
	seal.texture = Glyphs.texture(EndingsGallery.verdict_seal(verdict_name), 104, 1.4)
	seal.custom_minimum_size = Vector2(104, 104)
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	seal.self_modulate = RED
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	band.add_child(seal)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 0)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var word := _label(verdict_name, "Newsreader-SemiBold.ttf", 66, INK, HORIZONTAL_ALIGNMENT_LEFT, 3)
	word.name = "Verdict"
	left.add_child(word)
	left.add_child(_label("Directive score %d of 100" % int(round(float(verdict.get("score", 0.0)))), "Newsreader-Medium.ttf", 26,
		INK_SOFT, HORIZONTAL_ALIGNMENT_LEFT))
	band.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(_label("PLAYED AS", "Newsreader-SemiBold.ttf", 18, RED, HORIZONTAL_ALIGNMENT_RIGHT, 3))
	var who := _wrapped(UiFormat.role_title(role), "Newsreader-SemiBold.ttf", 36, INK, HORIZONTAL_ALIGNMENT_RIGHT)
	who.name = "Role"
	right.add_child(who)
	var start_turn := int(result.get("start_turn", 1))
	right.add_child(_label("%s · %d turns" % [CampaignModes.years_for(start_turn, int(result.get("turn", SimConstants.TOTAL_TURNS))),
		maxi(1, int(result.get("turn", 1)) - start_turn + 1)], "Newsreader-Medium.ttf", 24, INK_SOFT, HORIZONTAL_ALIGNMENT_RIGHT))
	band.add_child(right)
	return band


## "With the Citizen Coalition (Pyrrhic 48)" for pass-and-play tables.
static func _other_players(result: Dictionary) -> String:
	var role := String(result.get("player_role", ""))
	var verdicts: Dictionary = result.get("verdicts", {})
	var parts: Array[String] = []
	for other in result.get("humans", []):
		if String(other) == role or not verdicts.has(other):
			continue
		var v: Dictionary = verdicts[other]
		parts.append("the %s (%s %d)" % [UiFormat.role_name(String(other)), String(v.get("verdict", "DEFEAT")).capitalize(),
			int(round(float(v.get("score", 0.0))))])
	return ("At the same table: " + ", ".join(parts) + ".") if not parts.is_empty() else ""


static func _stats(result: Dictionary) -> Control:
	var values: Dictionary = result.get("final_values", {})
	var row := HBoxContainer.new()
	row.name = "Stats"
	row.add_theme_constant_override("separation", 0)
	for i in STATS.size():
		if i > 0:
			var line := ColorRect.new()
			line.color = RULE
			line.custom_minimum_size = Vector2(1, 0)
			row.add_child(line)
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 0)
		var key := String(STATS[i][1])
		var number := _label(str(int(round(float(values.get(key, 0.0))))), "Newsreader-SemiBold.ttf", 100,
			RED if key == WorldState.ALIGNMENT_DRIFT else INK, HORIZONTAL_ALIGNMENT_CENTER)
		number.name = "Stat_" + key
		cell.add_child(number)
		cell.add_child(_label(String(STATS[i][0]).to_upper(), "Newsreader-SemiBold.ttf", 18, INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER, 1))
		row.add_child(cell)
	return row


## Daily challenge, scenario, difficulty, length and players, boxed in ink.
static func _badges(result: Dictionary, extra: Dictionary) -> Control:
	var texts: Array[String] = []
	var daily := String(extra.get("daily", ""))
	if daily != "":
		texts.append("DAILY %s" % daily)
	texts.append(Scenarios.display_name(String(extra.get("scenario", result.get("scenario", Scenarios.STANDARD)))).to_upper())
	texts.append(Difficulty.display_name(String(extra.get("difficulty", result.get("difficulty", Difficulty.STANDARD)))).to_upper())
	var mode := String(extra.get("mode", ""))
	if CampaignModes.is_valid(mode):
		texts.append(CampaignModes.display_name(mode).to_upper())
	var humans := (result.get("humans", []) as Array).size()
	if humans > 1:
		texts.append("%d PLAYERS" % humans)
	var row := HFlowContainer.new()
	row.name = "Badges"
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 10)
	for text in texts:
		var badge := PanelContainer.new()
		var box := StyleBoxFlat.new()
		box.bg_color = RED if text.begins_with("DAILY") else Color(PAPER, 0.0)
		box.border_color = RED if text.begins_with("DAILY") else INK
		box.set_border_width_all(2)
		box.content_margin_left = 14
		box.content_margin_right = 14
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		badge.add_theme_stylebox_override("panel", box)
		badge.add_child(_label(text, "Newsreader-SemiBold.ttf", 20, PAPER if text.begins_with("DAILY") else INK,
			HORIZONTAL_ALIGNMENT_CENTER, 2))
		row.add_child(badge)
	return row


# --- Type -------------------------------------------------------------------------------

static func _label(text: String, font_file: String, font_size: int, color: Color, align: HorizontalAlignment,
		spacing: int = 0, expand: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_override("font", EraStyle.font(font_file, spacing))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


static func _wrapped(text: String, font_file: String, font_size: int, color: Color, align: HorizontalAlignment,
		spacing: int = 0) -> Label:
	var label := _label(text, font_file, font_size, color, align, spacing)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


static func _rule(thickness: float, color: Color) -> ColorRect:
	var rule := ColorRect.new()
	rule.color = color
	rule.custom_minimum_size = Vector2(0, thickness)
	return rule


static func _double_rule() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(_rule(3.0, INK))
	box.add_child(_rule(1.0, INK))
	return box


## Wraps [param label] at the narrowest width that keeps its line count, so a
## headline's last line is not a lone word, centered within [param max_width].
static func _balanced(label: Label, max_width: float) -> Control:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var full := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var lines := _line_count(font, label.text, font_size, max_width)
	var low := full / float(lines)
	var high := max_width
	while lines > 1 and high - low > 2.0:
		var middle := (low + high) * 0.5
		if _line_count(font, label.text, font_size, middle) <= lines:
			high = middle
		else:
			low = middle
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.custom_minimum_size = Vector2(minf(max_width, (high if lines > 1 else full) + 4.0), 0)
	var holder := CenterContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(label)
	return holder


static func _line_count(font: Font, text: String, font_size: int, width: float) -> int:
	var paragraph := TextParagraph.new()
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE \
		| TextServer.BREAK_TRIM_EDGE_SPACES
	paragraph.add_string(text, font, font_size)
	paragraph.width = width
	return maxi(1, paragraph.get_line_count())
