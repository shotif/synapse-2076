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
