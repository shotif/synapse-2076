extends "res://tests/framework/test_case.gd"
## Interface translations (I18n, res://locale/<code>.gd): every language
## translates exactly the message ids tools/i18n_catalog.gd finds, keeping each
## {placeholder}, %-format, BBCode tag and glyph of the English text; a dealt
## crisis card carries translated copies beside its English fields; the
## dashboard switches language live and back; and the longer German and French
## texts still fit a 412 px phone on every tab and dialog.

const Catalog := preload("res://tools/i18n_catalog.gd")
const DashboardScene := preload("res://ui/main_dashboard.tscn")
const TRANSLATED := ["de", "es", "fr"]
const PHONE := Vector2(412, 915)
const PHONE_PX := Vector2i(1081, 2202)  # 412 x 839 CSS px at device pixel ratio 2.625
## Glyphs the interface draws with Godot text: a translation keeps each one.
const GLYPHS := "←→↑↓▸▾●○◌▲▼△▽×≥≤✓›‹−⚠★☆"

var settings: GameSettings
var dashboard: Control
var host: Control
var _catalog := {}
var _saved_root_size := Vector2i.ZERO


func before_all() -> void:
	ProjectSettings.set_setting("synapse/llm/probe_on_start", false)


func before_each() -> void:
	settings = GameSettings.new()
	settings.path = ""
	GameSettings.use(settings)
	EraTheme.invalidate()


func after_each() -> void:
	if dashboard != null:
		dashboard.queue_free()
		dashboard = null
	if host != null:
		host.queue_free()
		host = null
	if _saved_root_size != Vector2i.ZERO:
		tree.root.size = _saved_root_size
		tree.root.content_scale_size = UiLayout.DESKTOP_SIZE
		_saved_root_size = Vector2i.ZERO
	await tree.process_frame
	# Every later suite expects English.
	I18n.apply(I18n.SOURCE)
	GameSettings.use(null)
	EraTheme.invalidate()


## The catalog's message ids (scanning the code takes a moment, so once).
func _ids() -> Dictionary:
	if _catalog.is_empty():
		_catalog = Catalog.msgids()
	return _catalog


func _sample(items: Array) -> String:
	return ", ".join(items.slice(0, 6))


func _sorted_matches(regex: RegEx, text: String) -> Array[String]:
	var out: Array[String] = []
	for found in regex.search_all(text):
		out.append(found.get_string())
	out.sort()
	return out


## The text [param control] shows: a control that translates itself shows
## its text through the translation server.
func _shown(control: Control) -> String:
	if control is Label:
		return control.atr((control as Label).text)
	if control is Button:
		return control.atr((control as Button).text)
	return ""


func _assert_fits(root: Control, width: float, context: String) -> void:
	var overflowing: Array[String] = []
	for node in root.find_children("*", "Control", true, false):
		var control := node as Control
		if control.is_visible_in_tree() and control.get_global_rect().end.x > width + 0.5:
			overflowing.append("%s (%s) ends at %.0f" % [control.name, control.get_class(), control.get_global_rect().end.x])
	assert_eq(overflowing.size(), 0, "%s fits %.0f px: %s" % [context, width, ", ".join(overflowing.slice(0, 5))])


# --- The languages and the server --------------------------------------------------------

func test_languages_and_fallbacks() -> void:
	assert_eq(",".join(I18n.codes()), "en,de,es,fr")
	var names := {}
	for entry in I18n.LANGUAGES:
		names[String(entry["code"])] = String(entry["name"])
	assert_eq(names, {"en": "English", "de": "Deutsch", "es": "Español", "fr": "Français"}, "each named in its own language")
	assert_eq(I18n.resolve(""), "en", "the test runner pins the system language to English")
	assert_eq(I18n.resolve("fr"), "fr")
	assert_eq(I18n.resolve("xx"), "en", "an unknown code falls back to English")
	assert_true(I18n.strings("en").is_empty(), "English is the source, with no table")
	assert_eq(I18n.current(), "en")


func test_apply_switches_the_language_and_back() -> void:
	assert_eq(I18n.apply("de"), "de")
	assert_eq(I18n.current(), "de")
	assert_eq(I18n.t("Settings"), "Einstellungen")
	assert_eq(I18n.t("No such message id"), "No such message id", "text without a translation passes through")
	assert_eq(UiFormat.block_reason("Cooldown 2 turn(s)"), "Abklingzeit 2 Runde(n)", "a filled-in format is filled in again")
	assert_eq(UiFormat.role_name(SimConstants.CEO), "Frontier-Labor")
	assert_eq(UiFormat.role_name(SimConstants.CEO, false), "Frontier Lab", "records and news keep the English name")
	assert_eq(I18n.lowercase("Kapital"), "Kapital", "German keeps its capitals in running text")
	I18n.apply("fr")
	assert_eq(I18n.t("Settings"), "Réglages")
	assert_eq(I18n.lowercase("Capital"), "capital")
	I18n.apply("es")
	assert_eq(I18n.t("Settings"), "Ajustes")
	I18n.apply("")
	assert_eq(I18n.current(), "en", "the system language (English here)")
	assert_eq(I18n.t("Settings"), "Settings")


func test_format_specs_follow_gdscript() -> void:
	assert_eq(I18n.specs("%d of %d · %s"), ["%d", "%d", "%s"] as Array[String])
	assert_eq(I18n.specs("%.1f%% of runs"), ["%.1f", "%%"] as Array[String])
	assert_eq(I18n.specs("%-10s|%+d|%05d|%x"), ["%-10s", "%+d", "%05d", "%x"] as Array[String])
	assert_true(I18n.specs("15 % der Kampagnen, 10 % des parties").is_empty(), "a percent sign in prose is not a format")


# --- The locale files --------------------------------------------------------------------

func test_every_language_translates_exactly_the_catalog() -> void:
	var ids := _ids()
	assert_gt(ids.size(), 2000, "the catalog finds the game's text")
	var reference := I18n.strings("de").keys()
	reference.sort()
	for code in TRANSLATED:
		var table := I18n.strings(code)
		var missing: Array[String] = []
		for id in ids:
			if not table.has(id):
				missing.append(String(id))
		var unused: Array[String] = []
		for id in table:
			if not ids.has(id):
				unused.append(String(id))
		assert_eq(missing.size(), 0, "%s translates every message id; missing: %s" % [code, _sample(missing)])
		assert_eq(unused.size(), 0, "%s has no ids the game does not use: %s" % [code, _sample(unused)])
		var keys := table.keys()
		keys.sort()
		assert_eq(keys, reference, "%s has the same keys as de" % code)


func test_translations_keep_formats_placeholders_markup_and_glyphs() -> void:
	var placeholders := RegEx.create_from_string("\\{[a-z_]+\\}")
	var bbcode := RegEx.create_from_string("\\[/?[a-z_]+(?:=[^\\]]*)?\\]")
	var specs := RegEx.create_from_string(I18n.SPEC_PATTERN)
	for code in TRANSLATED:
		var table := I18n.strings(code)
		var problems: Array[String] = []
		for id in table:
			var source := String(id)
			var text := String(table[id])
			if text.strip_edges() == "":
				problems.append("empty: " + source)
				continue
			if I18n.specs(source) != I18n.specs(text):
				problems.append("formats: " + source)
			elif not I18n.specs(source).is_empty() and specs.sub(text, "", true).contains("%"):
				problems.append("a stray %% in a format: " + source)
			if _sorted_matches(placeholders, source) != _sorted_matches(placeholders, text):
				problems.append("placeholders: " + source)
			if _sorted_matches(bbcode, source) != _sorted_matches(bbcode, text):
				problems.append("BBCode: " + source)
			for glyph in GLYPHS:
				if source.count(glyph) != text.count(glyph):
					problems.append("glyph %s: %s" % [glyph, source])
		assert_eq(problems.size(), 0, "%s: %s" % [code, _sample(problems)])


## A translation that is itself another message id would be translated a
## second time by a control that translates its own text.
func test_no_translation_is_another_message_id() -> void:
	for code in TRANSLATED:
		var table := I18n.strings(code)
		var clashes: Array[String] = []
		for id in table:
			var text := String(table[id])
			if text != String(id) and table.has(text) and String(table[text]) != text:
				clashes.append("%s -> %s" % [id, text])
		assert_eq(clashes.size(), 0, "%s: %s" % [code, _sample(clashes)])


## Swipe hints are one or two words. A hint that is also a response's label
## is translated as the label (the hint trims with an ellipsis if it must).
func test_swipe_hints_stay_short() -> void:
	var labels := {}
	for template in CardLibrary.all_cards():
		for option in (template as Dictionary).get("options", []):
			labels[String((option as Dictionary).get("label", ""))] = true
	var hints: Array[String] = []
	for card_id in CrisisCard.SWIPE_HINTS:
		for hint in CrisisCard.SWIPE_HINTS[card_id]:
			if not labels.has(String(hint)):
				hints.append(String(hint))
	for template in CardLibrary.all_cards():
		if Catalog.ENGLISH_ONLY_CARDS.has(String((template as Dictionary).get("id", ""))):
			continue
		for hint in (template as Dictionary).get("swipe_hints", []):
			if not labels.has(String(hint)):
				hints.append(String(hint))
	assert_gt(hints.size(), 100)
	var too_long: Array[String] = []
	for code in TRANSLATED:
		var table := I18n.strings(code)
		for hint in hints:
			if String(table.get(hint, hint)).length() > 12:
				too_long.append("%s %s" % [code, table[hint]])
	assert_eq(too_long.size(), 0, "swipe hints fit the card's corner: %s" % _sample(too_long))


# --- Cards, causes and the settings ----------------------------------------------------

## A campaign whose first crisis card is translated (a few cards stay English).
func _engine_with_translated_card(role: String) -> SimulationEngine:
	var english_only: Array = Catalog.ENGLISH_ONLY_CARDS
	for seed_value in range(2076, 2096):
		var engine := SimulationEngine.new()
		engine.start_campaign(role, seed_value)
		engine.advance()
		if not english_only.has(String(engine.current_dilemma.get("id", ""))):
			return engine
	return null


func test_dealt_cards_carry_translated_copies() -> void:
	I18n.apply("de")
	var engine := _engine_with_translated_card(SimConstants.GOVERNANCE)
	assert_not_null(engine)
	var card: Dictionary = engine.current_dilemma
	var template := DilemmaDeck.get_template(String(card["id"]))
	assert_eq(String(card["title"]), DilemmaDeck._fill(String(template["title"]), card["fills"]), "the English title stays")
	assert_ne(String(card["title_local"]), String(card["title"]), "a German copy beside it")
	assert_eq(DilemmaDeck.local_text(card, "title"), String(card["title_local"]))
	assert_eq(String(card["body_local"]), DilemmaDeck._fill(I18n.t(String(template["body"])), DilemmaDeck._local_fills(card["fills"])))
	for key in ["city", "lab", "model", "n", "pct", "gw"]:
		if String(template["body"]).contains("{%s}" % key):
			assert_string_contains(String(card["body_local"]), String(card["fills"][key]), "names and numbers carry over")
	for option in card["options"]:
		assert_eq(String(option["label_local"]), I18n.t(String(option["label"])))
		assert_ne(String(option["label_local"]), "")
	var defer: Dictionary = card["defer"]
	assert_eq(String(defer["detail_local"]), "Kehrt in 2 Runden verschärft zurück.")
	assert_eq(DilemmaDeck.localize_title(String(card["title"])), String(card["title_local"]), "a filed title finds its card")
	var places := DilemmaDeck._local_fills({"sector": "logistics", "bloc": "Pacific Accord", "city": "Lagos"})
	assert_eq(places, {"sector": "Logistik", "bloc": "Pazifik-Abkommen", "city": "Lagos"}, "words translate, names do not")
	assert_eq(WhyPopup.cause_text("Crisis deferred: " + String(card["title"])),
		"Krise aufgeschoben: " + String(card["title_local"]))
	I18n.apply("en")
	var english := DilemmaDeck.localized(card)
	assert_eq(String(english["title_local"]), String(card["title"]), "back in English")
	assert_eq(String(english["defer"]["detail_local"]), "Returns in 2 turns, escalated.")


func test_settings_offer_every_language_and_note_the_english_news() -> void:
	host = Control.new()
	host.theme = EraTheme.get_theme(1)
	host.size = PHONE
	tree.root.add_child(host)
	var dialog := SettingsDialog.new()
	host.add_child(dialog)
	dialog.set_languages(I18n.LANGUAGES)
	dialog.open()
	await wait_frames(2)
	var language := dialog.find_child("Language", true, false) as OptionButton
	assert_eq(language.item_count, 4)
	assert_eq(language.get_item_text(3), "Français", "names are not translated")
	var note := dialog.find_child("LanguageNote", true, false) as Label
	assert_false(note.visible, "no note in English")
	settings.set_value("language", "de", false)
	I18n.apply("de")
	await wait_frames(3)
	assert_true(note.visible)
	assert_eq(_shown(note), "Nachrichten und Geschichtsseiten bleiben auf Englisch.")
	assert_eq(language.get_item_text(1), "Deutsch")
	assert_eq(language.get_item_text(3), "Français")


# --- The dashboard -------------------------------------------------------------------------

func test_the_dashboard_switches_language_live() -> void:
	dashboard = DashboardScene.instantiate()
	tree.root.add_child(dashboard)
	await tree.process_frame
	dashboard.start_campaign(SimConstants.GOVERNANCE, 2077, false)
	await wait_frames(2)
	var dialog: DilemmaDialog = dashboard.get_node("%DilemmaDialog")
	var card: Dictionary = dashboard.engine.current_dilemma
	var title := dialog.get_card().find_child("Title", true, false) as Label
	var execute: Button = dashboard.get_node("%DirectivePanel").get_execute_button()
	assert_eq(_shown(title), UiFormat.strip_escalation(String(card["title"])))
	assert_eq(_shown(execute).to_lower(), "execute directives")
	settings.set_value("language", "de", false)
	await wait_frames(3)
	assert_eq(I18n.current(), "de", "the setting switches the language")
	var german := DilemmaDeck.localized(card)
	if not Catalog.ENGLISH_ONLY_CARDS.has(String(card["id"])):
		assert_ne(String(german["title_local"]), String(card["title"]))
	assert_eq(_shown(title), UiFormat.strip_escalation(String(german["title_local"])), "the card on screen is retitled")
	assert_eq(_shown(execute).to_lower(), "direktiven ausführen")
	assert_eq(_shown(dashboard._nav.get_button("act")).to_lower(), "handeln")
	assert_eq(_shown(dashboard._nav.get_button("world")).to_lower(), "welt")
	settings.set_value("language", "fr", false)
	await wait_frames(3)
	assert_eq(_shown(execute).to_lower(), "exécuter les directives")
	assert_eq(_shown(dashboard._nav.get_button("act")).to_lower(), "agir")
	settings.set_value("language", "en", false)
	await wait_frames(3)
	assert_eq(I18n.current(), "en")
	assert_eq(_shown(title), UiFormat.strip_escalation(String(card["title"])), "and back to English")
	assert_eq(_shown(execute).to_lower(), "execute directives")
	assert_eq(_shown(dashboard._nav.get_button("act")).to_lower(), "act")


## The dashboard on a phone in [param code], with the role select up.
func _phone_dashboard(code: String) -> float:
	settings.set_value("language", code, false)
	dashboard = DashboardScene.instantiate()
	tree.root.add_child(dashboard)
	await tree.process_frame
	_saved_root_size = tree.root.size
	tree.root.size = PHONE_PX
	dashboard.apply_layout(UiLayout.compute(Vector2(PHONE_PX), 2.625, true))
	await wait_frames(3)
	return dashboard.get_viewport_rect().size.x


func _check_phone(code: String) -> void:
	var width: float = await _phone_dashboard(code)
	assert_eq(I18n.current(), code)
	assert_almost_eq(width, 412.0, 1.0)
	_assert_fits(dashboard, width, code + " setup")
	for role in SimConstants.FACTION_ORDER:
		dashboard.start_campaign(role, 2076, false)
		await wait_frames(3)
		_assert_fits(dashboard, width, "%s %s crisis card" % [code, role])
		dashboard.get_node("%DilemmaDialog").choose(DilemmaDeck.DEFER_ID)
		await wait_frames(2)
		for tab in ["act", "world", "lens", "news"]:
			dashboard.show_tab(tab)
			await wait_frames(2)
			_assert_fits(dashboard, width, "%s %s %s tab" % [code, role, tab])
		dashboard.show_tab("intel")
		await wait_frames(2)
		_assert_fits(dashboard, width, "%s %s intel and goals" % [code, role])
	dashboard._open_menu()
	await wait_frames(2)
	_assert_fits(dashboard, width, code + " menu")
	dashboard._open_settings()
	await wait_frames(3)
	_assert_fits(dashboard, width, code + " settings")
	var settings_dialog: SettingsDialog = dashboard._settings_dialog
	settings_dialog.get_glossary().open()
	await wait_frames(3)
	_assert_fits(dashboard, width, code + " glossary")
	settings_dialog.close()
	dashboard._explain(WorldState.ALIGNMENT_DRIFT)
	await wait_frames(3)
	_assert_fits(dashboard, width, code + " why popup")
	dashboard._why.close()
	dashboard._open_endings()
	await wait_frames(3)
	_assert_fits(dashboard, width, code + " endings gallery")
	dashboard._endings_gallery.close()
	dashboard._open_people()
	await wait_frames(3)
	_assert_fits(dashboard, width, code + " people")
	dashboard._people_layer.visible = false
	dashboard._pass_device.set_compact(true)
	dashboard._pass_device.present(SimConstants.GOVERNANCE, 2041.5, ["A headline from the wire"] as Array[String], 31)
	await wait_frames(3)
	_assert_fits(dashboard, width, code + " pass the device")
	dashboard._pass_device.close()
	await wait_frames(2)
	dashboard._open_call()
	await wait_frames(3)
	var negotiation: NegotiationDialog = dashboard._negotiation
	assert_true(negotiation.visible, "a call can be made")
	_assert_fits(dashboard, width, code + " contact list")
	var contact := negotiation.find_child("Contact_" + SimConstants.GOVERNANCE, true, false) as Button
	if contact != null:
		contact.pressed.emit()
		await wait_frames(3)
		(negotiation.find_child("Quick_calm", true, false) as Button).pressed.emit()
		await wait_frames(3)
		_assert_fits(dashboard, width, code + " call with an offer")
	negotiation.hang_up()
	negotiation.visible = false
	settings.set_value("llm", false, false)
	await wait_frames(2)
	assert_eq(dashboard._badge.get_state(), LLMService.STATE_OFF, code + ": the badge shows the switch")
	_assert_fits(dashboard, width, code + " LLM switched off")
	settings.set_value("llm", true, false)


func test_german_fits_a_phone() -> void:
	await _check_phone("de")


func test_french_fits_a_phone() -> void:
	await _check_phone("fr")
