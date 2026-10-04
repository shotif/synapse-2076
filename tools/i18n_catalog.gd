extends SceneTree
## Every interface string the translations in res://locale/ cover (the message
## ids: English source text), and how each locale file stands against them.
##
##   godot --headless --path . --script res://tools/i18n_catalog.gd                  # counts per language
##   godot --headless --path . --script res://tools/i18n_catalog.gd -- --missing=de  # untranslated ids, as dictionary lines
##   godot --headless --path . --script res://tools/i18n_catalog.gd -- --dump=user://msgids.json
##
## Ids come from two places:
##   - the game's data: crisis cards (title, body, responses, defer labels,
##     swipe hints; ENGLISH_ONLY_CARDS can exclude cards), character memories, directives, currencies, metrics,
##     goals, scenarios, difficulties, lengths, end-states, plain-language
##     names, the cast, the tutorial, the negotiator's lines and the interface's
##     own name tables (see [method data_msgids]);
##   - the code under ui/, core/, systems/ and entities/: the literal first
##     argument of tr(), atr(), I18n.t() and I18n.mark(), and a plain literal
##     assigned to text, tooltip_text or placeholder_text (a Control translates
##     those itself), plus tooltip_text in scenes (see [method code_msgids]).
## tests/unit/test_i18n.gd checks that every locale file translates exactly
## these ids. A literal handed to a helper that sets a Control's text takes
## I18n.mark() so it is found here.

const CODE_DIRS := ["res://ui", "res://core", "res://systems", "res://entities"]
## Crisis cards left out of the catalog: their text stays English in every
## language (DilemmaDeck falls back to the English fields).
const ENGLISH_ONLY_CARDS := []
## A call whose first argument is a message id.
const CALL_PATTERN := "(?:(?<![\\w.])tr|(?<![\\w.])atr|\\bI18n\\.t|\\bI18n\\.mark)\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\"\\s*[,)]"
## A text property set from an expression.
const ASSIGN_PATTERN := "(?:\\.|^\\s*)(?:text|tooltip_text|placeholder_text)\\s*=\\s*(.+)$"
const LITERAL_PATTERN := "^\"((?:[^\"\\\\]|\\\\.)*)\"$"
const SCENE_PATTERN := "^tooltip_text = \"((?:[^\"\\\\]|\\\\.)*)\"$"


func _initialize() -> void:
	var ids := msgids()
	var missing_for := ""
	var dump := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--missing="):
			missing_for = arg.get_slice("=", 1)
		elif arg.begins_with("--dump="):
			dump = arg.get_slice("=", 1)
	if dump != "":
		var file := FileAccess.open(dump, FileAccess.WRITE)
		file.store_string(JSON.stringify(ids, "\t", false))
		file.close()
		print("Wrote %d message ids to %s" % [ids.size(), ProjectSettings.globalize_path(dump)])
	if missing_for != "":
		var table := I18n.strings(missing_for)
		for id in ids:
			if not table.has(id):
				print("\t%s: %s," % [JSON.stringify(id), JSON.stringify(id)])
		quit(0)
		return
	print("%d message ids (%d from the game's data, %d from the code)." % [ids.size(), data_msgids().size(),
		code_msgids().size()])
	var status := 0
	for code in I18n.codes():
		if code == I18n.SOURCE:
			continue
		var table := I18n.strings(code)
		var missing := 0
		var stale := 0
		for id in ids:
			if not table.has(id):
				missing += 1
		for id in table:
			if not ids.has(id):
				stale += 1
		print("  %s: %d translated, %d missing, %d not in the game" % [code, table.size(), missing, stale])
		if missing > 0 or stale > 0:
			status = 1
	quit(status)


## Every message id: {id: where it was found}.
static func msgids() -> Dictionary:
	var out := data_msgids()
	var code := code_msgids()
	for id in code:
		if not out.has(id):
			out[id] = code[id]
	return out


# --- The game's data -----------------------------------------------------------------

static func data_msgids() -> Dictionary:
	var out := {}
	for template in CardLibrary.all_cards():
		var card: Dictionary = template
		if ENGLISH_ONLY_CARDS.has(String(card.get("id", ""))):
			continue
		var where := "card " + String(card.get("id", ""))
		_add(out, card.get("title", ""), where)
		_add(out, card.get("body", ""), where)
		for option in card.get("options", []):
			_add(out, (option as Dictionary).get("label", ""), where)
			_add(out, (option as Dictionary).get("detail", ""), where)
		var defer: Dictionary = card.get("defer", {})
		_add(out, defer.get("label", ""), where)
		_add(out, defer.get("detail", ""), where)
		for hint in card.get("swipe_hints", []):
			_add(out, hint, where)
	for card_id in CrisisCard.SWIPE_HINTS:
		for hint in CrisisCard.SWIPE_HINTS[card_id]:
			_add(out, hint, "swipe hints")
	_add_all(out, [DilemmaDeck.DEFER_DETAIL, DilemmaDeck.FALLOUT_LABEL, DilemmaDeck.FALLOUT_DETAIL], "crisis deck")
	_add_all(out, DilemmaDeck.REGIONS + DilemmaDeck.BLOCS + DilemmaDeck.SECTORS, "card places")
	for memory in CardLibrary.memories():
		_add(out, (memory as Dictionary).get("text", ""), "memories")
	for faction_id in SimConstants.FACTION_ORDER:
		var catalog := FactionRegistry.catalog_for(faction_id)
		for action_id in catalog:
			_add(out, catalog[action_id].get("name", ""), "directives")
			_add(out, catalog[action_id].get("description", ""), "directives")
		var currencies := FactionRegistry.resource_info_for(faction_id)
		for key in currencies:
			_add(out, currencies[key].get("label", ""), "currencies")
			_add(out, currencies[key].get("short", ""), "currencies")
		var info: Dictionary = SimConstants.ROLE_INFO[faction_id]
		for key in ["tagline", "objective", "loss"]:
			_add(out, info.get(key, ""), "roles")
	_add_all(out, [CeoFaction.BANKRUPTCY_REASON, CeoFaction.NATIONALIZATION_REASON], "losses")
	for key in WorldState.METRIC_INFO:
		for field in ["label", "short", "low", "mid", "high"]:
			_add(out, WorldState.METRIC_INFO[key].get(field, ""), "metrics")
	for key in WorldState.INDEX_INFO:
		for field in ["label", "short"]:
			_add(out, WorldState.INDEX_INFO[key].get(field, ""), "indices")
	_add_all(out, [WorldState.CAUSE_OTHER, WorldState.CAUSE_WORLD, WorldState.CAUSE_NOISE], "causes")
	for table in [UiFormat.INDEX_SHORT, UiFormat.ROLE_NAMES, UiFormat.ROLE_TITLES, UiFormat.RESOURCE_NAMES, UiFormat.METRIC_NAMES,
			UiFormat.CATEGORY_NAMES, UiFormat.VERDICT_NAMES]:
		_add_all(out, (table as Dictionary).values(), "names")
	for goal in EraGoals.GOALS:
		_add(out, goal.get("text", ""), "goals")
		_add(out, goal.get("reward_text", ""), "goals")
	for scenario_id in Scenarios.LIST:
		_add(out, Scenarios.LIST[scenario_id].get("name", ""), "scenarios")
		_add(out, Scenarios.LIST[scenario_id].get("summary", ""), "scenarios")
	for preset_id in Difficulty.PRESETS:
		_add(out, Difficulty.PRESETS[preset_id].get("name", ""), "difficulty")
		_add(out, Difficulty.PRESETS[preset_id].get("summary", ""), "difficulty")
	for mode in CampaignModes.MODES:
		for field in ["name", "short", "blurb"]:
			_add(out, CampaignModes.MODES[mode].get(field, ""), "campaign lengths")
	for outcome in VictoryMatrix.OUTCOMES:
		for field in ["name", "subtitle", "description"]:
			_add(out, outcome.get(field, ""), "end-states")
	_add_all(out, PlainLanguage.KIND_TITLES.values(), "glossary")
	for table in [PlainLanguage.METRICS, PlainLanguage.INDICES, PlainLanguage.CURRENCIES, PlainLanguage.FACTIONS,
			PlainLanguage.TERMS, PlainLanguage.ERAS, PlainLanguage.END_STATES]:
		for key in table:
			for field in ["technical", "name", "short", "explain"]:
				_add(out, (table[key] as Dictionary).get(field, ""), "plain language")
	_add_all(out, EraStyle.NAMES.values(), "eras")
	for character_id in Characters.ROSTER:
		var person: Dictionary = Characters.ROSTER[character_id]
		_add_all(out, (person.get("roles", {}) as Dictionary).values(), "cast")
		_add(out, person.get("bio", ""), "cast")
	for stance in Characters.STANCES:
		_add(out, stance[1], "cast")
	for step in Coach.STEPS:
		_add(out, step.get("title", ""), "tutorial")
		_add(out, step.get("text", ""), "tutorial")
	for words in Coach.COLOR_WORDS.values():
		_add_all(out, words, "tutorial")
	_add_all(out, Coach.ORDINALS.values(), "tutorial")
	for leader in Negotiator.LINES:
		for key in Negotiator.LINES[leader]:
			_add_all(out, Negotiator.LINES[leader][key], "negotiator")
	for reply in Negotiator.QUICK_REPLIES:
		_add(out, reply.get("text", ""), "negotiator")
	_add_all(out, Negotiator.METRIC_WORDS.values(), "negotiator")
	_add_all(out, Negotiator.NOTE_FORMATS, "negotiator")
	_add(out, Negotiator.DEAL_STRUCK, "negotiator")
	for shift_id in TechTreeManager.PARADIGM_SHIFTS:
		var shift_name := String(TechTreeManager.PARADIGM_SHIFTS[shift_id]["name"])
		_add(out, shift_name, "paradigm shifts")
		_add(out, shift_name.get_slice(" ", 0), "paradigm shifts")
	for capability_id in TechTreeManager.EMERGENT_CAPABILITIES:
		_add(out, TechTreeManager.EMERGENT_CAPABILITIES[capability_id].get("name", ""), "emergent capabilities")
	_add_all(out, EndingsBook.RARITY_ORDER, "endings")
	# The interface's own name tables.
	for tab in preload("res://ui/main_dashboard.gd").TAB_INFO:
		_add(out, tab.get("label", ""), "tabs")
	_add_all(out, GoalsPanel.ACTIVE_LABELS.values(), "goals panel")
	_add_all(out, WhyPopup.GROUP_TITLES.values(), "why popup")
	for entry in WhyPopup.CAUSE_FORMATS:
		_add(out, entry[0], "why popup")
	_add_all(out, SettingsDialog.TEXT_SIZE_NAMES, "settings")
	_add_all(out, [RoleSelect.SUBTITLE, RoleSelect.SUBTITLE_COMPACT], "setup")
	_add_all(out, RoleSelect.OTHERS, "setup")
	_add(out, CastPanel.EMPTY_TEXT, "people")
	_add_all(out, CrisisCard.FACTION_NAMES.values(), "crisis card")
	_add_all(out, EndgameDebrief.REASONS.values(), "debrief")
	for era in EraUpgrade.SCRIPTS:
		var script: Dictionary = EraUpgrade.SCRIPTS[era]
		_add(out, script.get("kicker", ""), "era upgrade")
		_add(out, script.get("title", ""), "era upgrade")
		_add_all(out, script.get("log", []), "era upgrade")
	_add_all(out, WorldOverlay.CAPTIONS.values(), "world")
	_add_all(out, WorldOverlay.SEAL_TEXT.values(), "world")
	_add_all(out, StoryCopy.DESKS.values(), "newswire")
	_add(out, UiFormat.COOLDOWN_REASON, "directives")
	for entry in CeoLens.PRICED:
		_add(out, entry.get("label", ""), "lens: markets")
	for entry in CeoLens.BOOK:
		_add(out, entry[1], "lens: markets")
	_add_all(out, CeoLens.ORDER_NAMES.values(), "lens: markets")
	for entry in GovLens.CURRENCIES:
		_add(out, entry[1], "lens: briefing")
	_add_all(out, GovLens.OWN_TITLES.values(), "lens: briefing")
	_add_all(out, GovLens.ACTION_TITLES.values(), "lens: briefing")
	for entry in AsiLens.VARIABLES:
		_add(out, entry[1], "lens: perception")
	for node in AsiLens.NODES:
		_add(out, node.get("name", ""), "lens: perception")
	_add_all(out, CitizenLens.TABS, "lens: commons")
	for table in [CitizenLens.CHIPS, CitizenLens.TREASURY]:
		for entry in table:
			_add(out, entry[1], "lens: commons")
	_add_all(out, CitizenLens.MOTIONS.values(), "lens: commons")
	_add_all(out, CitizenLens.TOPICS.values(), "lens: commons")
	_add_all(out, CitizenLens.EVENT_KINDS.values(), "lens: commons")
	_add_all(out, LensPanel.KEY_WORDS.values(), "lenses")
	return out


# --- The code -------------------------------------------------------------------------

static func code_msgids() -> Dictionary:
	var out := {}
	var files: Array[String] = []
	for directory in CODE_DIRS:
		_collect_files(directory, files)
	for path in files:
		for id in scan_file(path):
			_add(out, id, path)
	return out


## The message ids in one .gd or .tscn file.
static func scan_file(path: String) -> Array[String]:
	var found: Array[String] = []
	var text := FileAccess.get_file_as_string(path)
	if path.ends_with(".tscn"):
		var scene := RegEx.create_from_string(SCENE_PATTERN)
		for line in text.split("\n"):
			var hit := scene.search(line.strip_edges())
			if hit != null:
				found.append(unescape(hit.get_string(1)))
		return found
	var calls := RegEx.create_from_string(CALL_PATTERN)
	var assignment := RegEx.create_from_string(ASSIGN_PATTERN)
	var literal := RegEx.create_from_string(LITERAL_PATTERN)
	for statement in statements(text):
		for hit in calls.search_all(statement):
			found.append(unescape(hit.get_string(1)))
		var assigned := assignment.search(statement)
		if assigned == null:
			continue
		for piece in _operands(assigned.get_string(1)):
			var plain := literal.search(piece)
			if plain != null:
				var id := unescape(plain.get_string(1))
				if _letters(id) >= 2:
					found.append(id)
	return found


## The source's logical lines: comments removed, lines continued with a
## backslash or inside brackets joined into one.
static func statements(source: String) -> Array[String]:
	var out: Array[String] = []
	var current := ""
	var depth := 0
	for raw in source.split("\n"):
		var line := _strip_comment(raw)
		current += (" " if current != "" else "") + line.strip_edges()
		depth += _bracket_balance(line)
		if current.ends_with("\\"):
			current = current.trim_suffix("\\")
			continue
		if depth > 0:
			continue
		depth = 0
		if current.strip_edges() != "":
			out.append(current)
		current = ""
	if current.strip_edges() != "":
		out.append(current)
	return out


## A GDScript string literal's escapes resolved.
static func unescape(text: String) -> String:
	var out := ""
	var i := 0
	while i < text.length():
		var character := text[i]
		if character == "\\" and i + 1 < text.length():
			var next := text[i + 1]
			match next:
				"n":
					out += "\n"
				"t":
					out += "\t"
				"r":
					out += "\r"
				"u":
					out += String.chr(text.substr(i + 2, 4).hex_to_int())
					i += 4
				_:
					out += next
			i += 2
			continue
		out += character
		i += 1
	return out


static func _strip_comment(line: String) -> String:
	var quote := ""
	var i := 0
	while i < line.length():
		var character := line[i]
		if quote != "":
			if character == "\\":
				i += 2
				continue
			if character == quote:
				quote = ""
		elif character == "\"" or character == "'":
			quote = character
		elif character == "#":
			return line.substr(0, i)
		i += 1
	return line


static func _bracket_balance(line: String) -> int:
	var balance := 0
	var quote := ""
	var i := 0
	while i < line.length():
		var character := line[i]
		if quote != "":
			if character == "\\":
				i += 2
				continue
			if character == quote:
				quote = ""
		elif character == "\"" or character == "'":
			quote = character
		elif "([{".contains(character):
			balance += 1
		elif ")]}".contains(character):
			balance -= 1
		i += 1
	return balance


## The parts of an assignment's right-hand side between top-level "if" and
## "else", without their outer parentheses.
static func _operands(expression: String) -> Array[String]:
	var parts: Array[String] = []
	var current := ""
	var depth := 0
	var quote := ""
	var i := 0
	while i < expression.length():
		var character := expression[i]
		if quote != "":
			current += character
			if character == "\\" and i + 1 < expression.length():
				current += expression[i + 1]
				i += 2
				continue
			if character == quote:
				quote = ""
			i += 1
			continue
		if character == "\"" or character == "'":
			quote = character
		elif "([{".contains(character):
			depth += 1
		elif ")]}".contains(character):
			depth -= 1
		if depth == 0 and character == " ":
			for keyword in [" if ", " else "]:
				if expression.substr(i, keyword.length()) == keyword:
					parts.append(current)
					current = ""
					i += keyword.length() - 1
					character = ""
					break
		current += character
		i += 1
	parts.append(current)
	var out: Array[String] = []
	for part in parts:
		var clean := part.strip_edges()
		while clean.begins_with("(") and clean.ends_with(")"):
			clean = clean.substr(1, clean.length() - 2).strip_edges()
		out.append(clean)
	return out


## Letters left once format specs, {placeholders} and BBCode tags are taken out.
static func _letters(text: String) -> int:
	var bare := RegEx.create_from_string(I18n.SPEC_PATTERN + "|\\{[a-z_]+\\}|\\[/?[a-z_]+(?:=[^\\]]*)?\\]").sub(text, "", true)
	return RegEx.create_from_string("[A-Za-z]").search_all(bare).size()


static func _collect_files(directory: String, out: Array[String]) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect_files(directory.path_join(sub), out)
	for file_name in dir.get_files():
		if file_name.ends_with(".gd") or file_name.ends_with(".tscn"):
			out.append(directory.path_join(file_name))


## Adds [param value] unless it is empty or has no letter to translate ("$", "×").
static func _add(out: Dictionary, value: Variant, where: String) -> void:
	var text := String(value) if value is String or value is StringName else ""
	if text.strip_edges() != "" and not out.has(text) and _letters(text) > 0:
		out[text] = where


static func _add_all(out: Dictionary, values: Array, where: String) -> void:
	for value in values:
		_add(out, value, where)
