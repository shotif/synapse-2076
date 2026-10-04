class_name I18n
extends RefCounted
## The interface languages. English is the source: every translatable string
## is its own English text (the message id), and res://locale/<code>.gd holds
## one `const STRINGS := {english: translation}` per language. apply() builds
## a Translation from it at runtime and hands it to the TranslationServer, so
## there is no import step: it works headless, in tests and on the web.
##
##   I18n.apply("de")       # register German (once) and switch to it
##   I18n.apply("")         # the system's language when it is translated, else English
##   I18n.t("Settings")     # translate from static or RefCounted code
##   tr("Settings")         # the same from any Object
##   I18n.current()         # "de"
##
## Controls translate their own text and tooltip when the whole text is a
## message id (auto_translate_mode inherit), and again whenever the language
## changes. Composed text (formats, BBCode, EraStyle.label() case) is
## translated before it is put together: s.label(tr("Intel")),
## tr("Turn %d of %d") % [turn, total]; widgets set such text again on
## NOTIFICATION_TRANSLATION_CHANGED. Labels that show English prose, an LLM's
## words or the player's own text turn auto translation off.
##
## What stays English: the generated news prose (HeadlineWriter, EraChronicle
## and StoryCopy write the newswire, the front pages and the history book),
## the simulation's own records (the log, causes as filed, saves) and anything
## an LLM or a player writes. Crisis cards keep their English fields and get
## translated copies ("title_local", ...) when they are dealt (DilemmaDeck).
##
## tools/i18n_catalog.gd lists every message id (from the game's data and the
## tr()/I18n.t()/I18n.mark() calls and text assignments in the code);
## tests/unit/test_i18n.gd checks that each locale file covers exactly those,
## with every {placeholder}, %-format and BBCode tag intact.

## The languages the settings offer, in menu order (names in their own language).
const LANGUAGES := [
	{"code": "en", "name": "English"},
	{"code": "de", "name": "Deutsch"},
	{"code": "es", "name": "Español"},
	{"code": "fr", "name": "Français"},
]
## The language the message ids are written in.
const SOURCE := "en"
const LOCALE_DIR := "res://locale/"
## Overrides the system language that "" follows (the test runner sets "en").
const SYSTEM_LANGUAGE_SETTING := "synapse/i18n/system_language"
## A GDScript format placeholder (%%, %s, %d, %5.1f, %-10s, %.2f ...). A "%"
## followed by anything else is plain text ("15 % der Kampagnen").
const SPEC_PATTERN := "%%|%[-+0]*(?:[0-9]+|\\*)?(?:\\.(?:[0-9]+|\\*))?[scdoxXfv]"

## Language code -> the Translation registered for it.
static var _loaded := {}


## Every supported language code, English first.
static func codes() -> Array[String]:
	var out: Array[String] = []
	for entry in LANGUAGES:
		out.append(String(entry["code"]))
	return out


static func is_supported(code: String) -> bool:
	return codes().has(code)


## The language "" stands for: the system's when it is translated, else English.
static func system_language() -> String:
	var forced := String(ProjectSettings.get_setting(SYSTEM_LANGUAGE_SETTING, ""))
	var language := forced if forced != "" else OS.get_locale_language()
	return language if is_supported(language) else SOURCE


## The language [param code] selects: itself when supported, the system
## language for "", English otherwise.
static func resolve(code: String) -> String:
	if code == "":
		return system_language()
	return code if is_supported(code) else SOURCE


## Switches the interface to [param code] (GameSettings "language"; "" follows
## the system) and returns the language now in use. The translation is built
## on first use; switching notifies every node (NOTIFICATION_TRANSLATION_CHANGED).
static func apply(code: String) -> String:
	var language := resolve(code)
	if language != SOURCE:
		_register(language)
	if TranslationServer.get_locale() != language:
		TranslationServer.set_locale(language)
	return language


## The language the interface is showing ("en" until another one is applied).
static func current() -> String:
	var language := TranslationServer.get_locale().get_slice("_", 0)
	return language if _loaded.has(language) else SOURCE


## [param text] in the current language ([param text] itself when it has no
## translation). Translate the English template before filling it in.
static func t(text: String) -> String:
	if text == "":
		return text
	return String(TranslationServer.translate(text))


## [param text], a filled-in [param format] (an English message id with
## %d, %s or %.1f specs, as an engine record keeps it), in the interface
## language: the format is translated and filled with the same values. ""
## when [param text] does not fit [param format].
static func t_format(text: String, format: String) -> String:
	var found := RegEx.create_from_string(_format_pattern(format)).search(text)
	if found == null:
		return ""
	var translated := t(format)
	var out := ""
	var last := 0
	var index := 1
	for spec in _spec_regex().search_all(translated):
		out += translated.substr(last, spec.get_start() - last)
		if spec.get_string() == "%%":
			out += "%"
		else:
			out += found.get_string(index) if index <= found.get_group_count() else ""
			index += 1
		last = spec.get_end()
	return out + translated.substr(last)


## Marks [param text] as an interface string without translating it, for a
## literal handed to a helper that puts it in a Control's text or tooltip
## (which translate themselves, and follow a language change). The catalog
## (tools/i18n_catalog.gd) collects marked literals.
static func mark(text: String) -> String:
	return text


## Lower case for a name set in running text. German keeps its capitals,
## since its nouns are written with one.
static func lowercase(text: String) -> String:
	return text if current() == "de" else text.to_lower()


## The message table of [param code] (English source -> translation) from
## res://locale/<code>.gd; {} for English or an unknown language.
static func strings(code: String) -> Dictionary:
	if code == SOURCE or not is_supported(code):
		return {}
	var path := LOCALE_DIR + code + ".gd"
	if not ResourceLoader.exists(path):
		return {}
	var script := load(path) as GDScript
	if script == null:
		return {}
	var table: Variant = script.get_script_constant_map().get("STRINGS", {})
	return table if table is Dictionary else {}


static var _specs: RegEx


## The format placeholders in [param text], in order: ["%d", "%s"]. A
## translation keeps the same list as its message id.
static func specs(text: String) -> Array[String]:
	var out: Array[String] = []
	for found in _spec_regex().search_all(text):
		out.append(found.get_string())
	return out


static func _spec_regex() -> RegEx:
	if _specs == null:
		_specs = RegEx.create_from_string(SPEC_PATTERN)
	return _specs


## A regex matching [param format] filled in (each spec captures its text).
static func _format_pattern(format: String) -> String:
	var pattern := "^"
	var last := 0
	for spec in _spec_regex().search_all(format):
		pattern += _escape(format.substr(last, spec.get_start() - last))
		pattern += "%" if spec.get_string() == "%%" else "(.+?)"
		last = spec.get_end()
	return pattern + _escape(format.substr(last)) + "$"


static func _escape(text: String) -> String:
	var out := ""
	for character in text:
		out += ("\\" + character) if "\\^$.|?*+()[]{}".contains(character) else character
	return out


static func _register(language: String) -> void:
	if _loaded.has(language):
		return
	var translation := Translation.new()
	translation.locale = language
	var table := strings(language)
	for source in table:
		translation.add_message(String(source), String(table[source]))
	TranslationServer.add_translation(translation)
	_loaded[language] = translation
