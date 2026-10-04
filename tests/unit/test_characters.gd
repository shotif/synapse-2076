extends "res://tests/framework/test_case.gd"
## The recurring cast: roster data, ages and stances.


func test_roster_is_complete() -> void:
	assert_eq(Characters.ids().size(), 7)
	for character_id in Characters.ids():
		var person := Characters.get_character(character_id)
		for key in ["name", "short", "pronoun", "kind", "born", "faction", "roles", "bio", "look"]:
			assert_true(person.has(key), "%s has %s" % [character_id, key])
		assert_has(SimConstants.FACTION_ORDER, String(person["faction"]))
		assert_true(person["pronoun"] in ["she", "he", "they", "it"])
		for era in [1, 2, 3]:
			assert_false(Characters.role_in(character_id, era).is_empty(), "%s has a role in era %d" % [character_id, era])
		var look: Dictionary = person["look"]
		for key in ["skin", "hair", "eyes", "accent"]:
			assert_true(Color.html_is_valid(String(look[key])), "%s %s" % [character_id, key])
		assert_true(look["hair_style"] in ["short", "long", "braids", "bob", "curly", "slick", "bald"])
		assert_true(look["accessory"] in ["", "glasses", "headset", "earrings", "beard"])


func test_people_age_with_the_campaign() -> void:
	assert_eq(Characters.age_in("sam", 2026.5), 11, "a kid in 2026")
	assert_eq(Characters.age_in("sam", 2076.0), 61)
	assert_eq(Characters.age_in("jonas", 2076.0), 96)
	assert_true(Characters.is_machine("aria"))
	assert_eq(Characters.version_in("aria", 2029.0), 1)
	assert_eq(Characters.version_in("aria", 2076.0), 7)
	assert_false(Characters.exists("nobody"))
	assert_eq(Characters.display_name("nobody"), "nobody")


func test_stances() -> void:
	assert_eq(Characters.stance(4.0), "Loyal")
	assert_eq(Characters.stance(1.0), "Warm")
	assert_eq(Characters.stance(0.0), "Neutral")
	assert_eq(Characters.stance(-2.0), "Wary")
	assert_eq(Characters.stance(-3.5), "Hostile")


## The text of the memory entry for [param character_id] whose [param key] is [param value].
func _memory(character_id: String, key: String, value: Variant) -> String:
	for entry in CardLibrary.memories():
		if entry["character"] == character_id and entry.has(key) and entry[key] == value:
			return String(entry["text"])
	return "<missing>"


func test_memories_are_well_formed() -> void:
	var flags_set := {}
	for template in DilemmaDeck.all_cards():
		for option in template["options"] + [template["defer"]]:
			for flag in ((option.get("effects", {}) as Dictionary).get("flags", {}) as Dictionary).get("set", []):
				flags_set[String(flag)] = true
	var remembered := {}
	for entry in CardLibrary.memories():
		var character_id := String(entry.get("character", ""))
		assert_true(Characters.exists(character_id), "a real character: " + character_id)
		assert_false(String(entry.get("text", "")).is_empty(), character_id + " remembers something")
		assert_true(entry.has("flag") or entry.has("min") or entry.has("max"), "%s: '%s' says when it applies" % [character_id, entry.get("text", "")])
		if entry.has("flag"):
			assert_true(flags_set.has(String(entry["flag"])), "a card sets %s" % entry["flag"])
		remembered[character_id] = true
	for character_id in Characters.ids():
		assert_true(remembered.has(character_id), character_id + " has memories")


func test_memory_line_prefers_what_the_players_did() -> void:
	var deck := DilemmaDeck.new()
	assert_eq(Characters.memory_line("lin", deck), "", "nothing to remember yet")
	assert_eq(Characters.memory_line("lin", null), "")
	deck.adjust_character("lin", -2.0)
	assert_eq(Characters.memory_line("lin", deck), _memory("lin", "max", -2.0), "a hostile score")
	deck.set_flag("hushed_whistleblower")
	assert_eq(Characters.memory_line("lin", deck), _memory("lin", "flag", "hushed_whistleblower"), "a flag beats a score")
	deck.set_flag("nda_denied")
	assert_eq(Characters.memory_line("lin", deck), _memory("lin", "flag", "nda_denied"), "the later chapter wins")
	deck.adjust_character("jonas", 2.5)
	assert_eq(Characters.memory_line("jonas", deck), _memory("jonas", "min", 2.0))
	assert_eq(Characters.memory_line("maya", deck), "", "flags and scores are per character")
	assert_eq(Characters.memory_line("nobody", deck), "")


func test_met_lists_the_cast_in_order_of_appearance() -> void:
	var deck := DilemmaDeck.new()
	assert_eq(Characters.met(deck), [])
	assert_eq(Characters.met(null), [])
	var ctx := {"turn": 4, "year": 2028.0, "role": SimConstants.CITIZEN}
	deck._instantiate(DilemmaDeck.get_template("LABELERS_STRIKE"), ctx, null, "DECK", 0)
	deck._instantiate(DilemmaDeck.get_template("KID_COMPANION"), ctx, null, "DECK", 0)
	ctx["turn"] = 2
	deck._instantiate(DilemmaDeck.get_template("POWER_BILL"), ctx, null, "DECK", 0)
	ctx["turn"] = 9
	deck._instantiate(DilemmaDeck.get_template("LABELERS_UNION"), ctx, null, "FOLLOW_UP", 0)
	assert_eq(Characters.met(deck), ["jonas", "maya", "sam"], "first seen first; ties in roster order")
	assert_eq(deck.characters_met["maya"], {"first_turn": 4, "last_turn": 9, "count": 2})
