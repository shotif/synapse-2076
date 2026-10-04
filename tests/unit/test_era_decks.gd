extends "res://tests/framework/test_case.gd"
## The Era II and Era III crisis decks (Era2Cards, Era3Cards): schema and
## writing limits, the cheap response every role gets, enough cards in each era,
## the story threads (follow-ups, flags, character scores), the memory lines and
## the early_fusion scenario's opening card.

const ERA2_FIRST_YEAR := 2036.0
const ERA3_FIRST_YEAR := 2050.0
const MAX_LABEL := 40
const MAX_HINT := 12
const MAX_MEMORY := 70
const MAX_BODY := 180
## Cards the brief asked for, by title (FIRST_LIGHT is checked by id).
const DRAFT_TITLES := ["Steel Colleagues", "The Pathogen in the Red Team", "The City That Runs Itself", "Voices of the Dead",
	"A Model Asks for a Lawyer", "The Cure for a Price", "The Last Human Controller", "Leaving the Body", "Silence in Sector 7"]
## A typical world at each era's midpoint (Monte Carlo means): metrics, log FLOPs
## and the paradigm shifts most campaigns have unlocked by then.
const MIDPOINTS := {
	2042: {"metrics": {"compute_energy_sat": 61.0, "labor_displacement": 35.0, "geopolitical_tension": 47.0,
		"algorithmic_autonomy": 37.0, "alignment_drift": 33.0, "epistemic_trust": 77.0}, "log_flops": 31.0,
		"shifts": [TechTreeManager.MECHANISTIC_INTERPRETABILITY, TechTreeManager.OPTICAL_COMPUTING]},
	2063: {"metrics": {"compute_energy_sat": 76.0, "labor_displacement": 73.0, "geopolitical_tension": 59.0,
		"algorithmic_autonomy": 76.0, "alignment_drift": 45.0, "epistemic_trust": 58.0}, "log_flops": 37.8,
		"shifts": TechTreeManager.SHIFT_ORDER},
}


func _era_cards() -> Array:
	return Era2Cards.CARDS + Era3Cards.CARDS


func _memories() -> Array:
	return Era2Cards.MEMORIES + Era3Cards.MEMORIES


func _ctx(role: String, year: float, world: WorldState = null, tech: TechTreeManager = null) -> Dictionary:
	return {
		"turn": int((year - SimConstants.START_YEAR) / SimConstants.YEARS_PER_TURN),
		"year": year, "role": role,
		"world": world if world != null else WorldState.new(),
		"tech": tech if tech != null else TechTreeManager.new(),
		"player": FactionRegistry.create(role),
	}


## Options [param role] sees on [param template] (role-specific ones included).
func _options_for(template: Dictionary, role: String) -> Array:
	var out: Array = []
	for option in template.get("options", []):
		var roles: Array = option.get("roles", [])
		if roles.is_empty() or roles.has(role):
			out.append(option)
	return out


## What [param option] costs [param role] before escalation and difficulty.
func _cost_for(option: Dictionary, role: String) -> Dictionary:
	if option.has("cost"):
		return option["cost"]
	return DilemmaDeck.COST_TIERS[role].get(int(option.get("cost_tier", 0)), {})


## A cost no heavier than the role's tier-1 price, weighed by each currency's scale.
func _is_cheap(cost: Dictionary, role: String) -> bool:
	var actor := FactionRegistry.create(role)
	var tier_one: Dictionary = DilemmaDeck.COST_TIERS[role][1]
	var budget := 0.0
	for key in tier_one:
		budget += float(tier_one[key]) / actor.resource_scale(key)
	var weight := 0.0
	for key in cost:
		if not actor.resources.has(key):
			return false
		weight += float(cost[key]) / actor.resource_scale(key)
	return weight <= budget + 0.0001


## Every flag some card can set (options, defer, fallout) or a scenario starts with.
func _settable_flags() -> Dictionary:
	var out := {}
	for template in CardLibrary.all_cards():
		var effect_sets: Array = [template.get("defer", {}).get("effects", {}), template.get("fallout", {})]
		for option in template.get("options", []):
			effect_sets.append(option.get("effects", {}))
		for effects in effect_sets:
			for flag in (effects as Dictionary).get("flags", {}).get("set", []):
				out[String(flag)] = true
	for scenario_id in Scenarios.LIST:
		for flag in Scenarios.LIST[scenario_id].get("flags", []):
			out[String(flag)] = true
	return out


func _midpoint(year: int) -> Array:
	var info: Dictionary = MIDPOINTS[year]
	var world := WorldState.new()
	for key in info["metrics"]:
		world.set_value(key, float(info["metrics"][key]))
	var tech := TechTreeManager.new()
	tech.log_flops = float(info["log_flops"])
	for shift_id in info["shifts"]:
		tech.unlock_shift(String(shift_id), 1)
	return [world, tech]


# --- Schema and writing ----------------------------------------------------------------

func test_era_cards_follow_the_schema() -> void:
	var ids := {}
	for template in _era_cards():
		var card_id := String(template["id"])
		assert_false(ids.has(card_id), "unique id " + card_id)
		ids[card_id] = true
		assert_true(CrisisArt.CATEGORIES.has(String(template["category"])), "%s has an illustration" % card_id)
		assert_between(float(template["severity"]), 1.0, 3.0, card_id + " severity")
		assert_gt(float(template["weight"]), 0.0, card_id + " weight")
		var character := String(template.get("character", ""))
		assert_true(character == "" or Characters.exists(character), "%s character %s" % [card_id, character])
		var body := String(template["body"])
		assert_lte(body.length(), MAX_BODY, card_id + " body is short")
		assert_lte(float(body.count(". ") + 1), 2.0, card_id + " body has at most two sentences")
		var hints: Array = template.get("swipe_hints", [])
		assert_eq(hints.size(), 2, card_id + " swipe hints")
		for hint in hints:
			assert_between(float(String(hint).length()), 1.0, float(MAX_HINT), "%s hint '%s'" % [card_id, hint])
		var defer_label := String(template["defer"]["label"])
		assert_between(float(defer_label.length()), 1.0, float(MAX_LABEL), card_id + " defer label")
		var shared := 0
		for option in template["options"]:
			var where := "%s %s %s" % [card_id, option["id"], option.get("roles", [])]
			assert_between(float(String(option["label"]).length()), 1.0, float(MAX_LABEL), where + " label: " + String(option["label"]))
			assert_false(String(option.get("detail", "")).is_empty(), where + " detail")
			var roles: Array = option.get("roles", [])
			var effects: Dictionary = option.get("effects", {})
			if roles.is_empty():
				shared += 1
				assert_true(option.has("cost_tier"), where + ": shared options are priced by tier")
				assert_false(effects.has("self"), where + ": shared options grant currencies through self_by_role")
			for role in roles:
				var actor := FactionRegistry.create(String(role))
				for key in option.get("cost", {}):
					assert_true(actor.resources.has(key), "%s costs %s" % [where, key])
				for key in effects.get("self", {}):
					assert_true(actor.resources.has(key), "%s grants %s" % [where, key])
			var by_role: Dictionary = effects.get("self_by_role", {})
			for role in by_role:
				var actor := FactionRegistry.create(String(role))
				for key in by_role[role]:
					assert_true(actor.resources.has(key), "%s grants %s to %s" % [where, key, role])
			for character_id in effects.get("characters", {}):
				assert_true(Characters.exists(String(character_id)), "%s moves %s" % [where, character_id])
		assert_gte(float(shared), 2.0, card_id + ": options A and B are for everyone (the swipe sides)")
		var copy: Dictionary = template.get("copy", {})
		for key in ["topic", "glyph", "weight", "subject", "event", "one", "plural", "options"]:
			assert_has(copy, key, "%s copy.%s" % [card_id, key])
		assert_true(Glyphs.has_glyph(String(copy.get("glyph", ""))), "%s glyph %s" % [card_id, copy.get("glyph", "")])


func test_era_windows() -> void:
	for template in Era2Cards.CARDS:
		var conditions: Dictionary = template["conditions"]
		if template.get("follow_up_only", false):
			continue
		assert_gte(float(conditions.get("min_year", 0.0)), ERA2_FIRST_YEAR, "%s starts in Era II" % template["id"])
		if conditions.has("max_year"):
			assert_lt(float(conditions["max_year"]), ERA3_FIRST_YEAR, "%s ends with Era II" % template["id"])
		else:
			assert_false((conditions.get("requires_flags", []) as Array).is_empty(), "%s runs on only behind a story flag" % template["id"])
	for template in Era3Cards.CARDS:
		if not template.get("follow_up_only", false):
			assert_gte(float(template["conditions"].get("min_year", 0.0)), ERA3_FIRST_YEAR, "%s starts in Era III" % template["id"])


func test_draft_cards_exist() -> void:
	var first_light := CardLibrary.get_template("FIRST_LIGHT")
	assert_false(first_light.is_empty(), "FIRST_LIGHT exists")
	assert_true(first_light.get("once", false), "the first fusion power comes once")
	for option in first_light["options"]:
		assert_has(option["effects"].get("flags", {}).get("set", []), "fusion_online", "FIRST_LIGHT %s brings fusion online" % option["id"])
	var by_title := {}
	for template in _era_cards():
		by_title[String(template["title"])] = template
	for title in DRAFT_TITLES:
		assert_true(by_title.has(title), "a card titled '%s'" % title)
	assert_eq(by_title["Steel Colleagues"]["category"], "ROBOTICS")
	assert_eq(by_title["The Pathogen in the Red Team"]["category"], "BIOSECURITY")
	assert_eq(by_title["The Pathogen in the Red Team"]["character"], "lin")
	assert_eq(by_title["Voices of the Dead"]["category"], "CULTURE")
	assert_eq(by_title["A Model Asks for a Lawyer"]["category"], "PERSONHOOD")
	assert_eq(by_title["A Model Asks for a Lawyer"]["character"], "aria")
	assert_eq(by_title["The Cure for a Price"]["character"], "victor")
	assert_eq(by_title["The Last Human Controller"]["character"], "jonas")
	assert_has(["sam", "victor"], String(by_title["Leaving the Body"]["character"]))
	var categories := {}
	for template in _era_cards():
		categories[String(template["category"])] = true
	for reserved in ["BIOSECURITY", "ROBOTICS", "CULTURE", "PERSONHOOD", "SPACE"]:
		assert_true(categories.has(reserved), "the era decks use " + reserved)


# --- Every role can answer every card ---------------------------------------------------

func test_every_role_has_a_cheap_response() -> void:
	for template in _era_cards():
		for role in SimConstants.FACTION_ORDER:
			var options := _options_for(template, role)
			assert_gte(float(options.size()), 2.0, "%s offers %s two responses" % [template["id"], role])
			var cheap := false
			for option in options:
				if _is_cheap(_cost_for(option, role), role):
					cheap = true
			assert_true(cheap, "%s has a response %s can afford at tier 1" % [template["id"], role])


func test_each_era_deals_at_least_twenty_cards_at_its_midpoint() -> void:
	var era_ids := {}
	for template in Era2Cards.CARDS:
		era_ids[String(template["id"])] = 2
	for template in Era3Cards.CARDS:
		era_ids[String(template["id"])] = 3
	for year in MIDPOINTS:
		var setup := _midpoint(year)
		var era := SimConstants.era_for_year(float(year))
		for role in SimConstants.FACTION_ORDER:
			var deck := DilemmaDeck.new()
			var ctx := _ctx(role, float(year), setup[0], setup[1])
			var total := 0
			var own_era := 0
			for template in DilemmaDeck.all_cards():
				if template.get("injection_only", false) or template.get("follow_up_only", false):
					continue
				if not deck._eligible(template, ctx) or _options_for(template, role).size() < 2:
					continue
				total += 1
				if int(era_ids.get(String(template["id"]), 0)) == era:
					own_era += 1
			assert_gte(float(total), 20.0, "%s sees %d cards in %d" % [role, total, year])
			assert_gte(float(own_era), 10.0, "%d of them from the Era %d deck in %d" % [own_era, era, year])


# --- Story threads -----------------------------------------------------------------------

func test_follow_up_chains_resolve() -> void:
	var targets := {}
	for template in CardLibrary.all_cards():
		for option in template.get("options", []):
			var follow_up: Dictionary = option.get("effects", {}).get("follow_up", {})
			if follow_up.is_empty():
				continue
			var target := String(follow_up.get("card", ""))
			assert_false(CardLibrary.get_template(target).is_empty(), "%s schedules a real card (%s)" % [template["id"], target])
			assert_gte(float(follow_up.get("turns", 0)), 1.0, "%s schedules it in the future" % template["id"])
			targets[target] = true
	var links := 0
	for template in _era_cards():
		if template.get("follow_up_only", false):
			assert_true(targets.has(String(template["id"])), "%s is reachable from a follow-up" % template["id"])
			links += 1
		elif targets.has(String(template["id"])):
			links += 1
	assert_gte(float(links), 3.0, "at least three follow-up links in the era decks")


func test_story_conditions_can_be_met() -> void:
	var settable := _settable_flags()
	for template in _era_cards():
		var conditions: Dictionary = template["conditions"]
		for key in ["requires_flags", "lacks_flags"]:
			for flag in conditions.get(key, []):
				assert_true(settable.has(String(flag)), "%s waits on '%s', which some card sets" % [template["id"], flag])
		for key in ["character_min", "character_max"]:
			for character_id in conditions.get(key, {}):
				assert_true(Characters.exists(String(character_id)), "%s reads %s" % [template["id"], character_id])


func test_memories_reference_real_characters_and_flags() -> void:
	var settable := _settable_flags()
	assert_gte(float(Era2Cards.MEMORIES.size()), 6.0, "Era II memories")
	assert_gte(float(Era3Cards.MEMORIES.size()), 6.0, "Era III memories")
	for memory in _memories():
		var text := String(memory.get("text", ""))
		assert_true(Characters.exists(String(memory.get("character", ""))), "memory of a real character: " + text)
		assert_between(float(text.length()), 1.0, float(MAX_MEMORY), "short memory: " + text)
		assert_true(text.contains("you"), "speaks to the players: " + text)
		var keys := 0
		for key in ["flag", "min", "max"]:
			if memory.has(key):
				keys += 1
		assert_eq(keys, 1, "one trigger: " + text)
		if memory.has("flag"):
			assert_true(settable.has(String(memory["flag"])), "'%s' is set by some card" % memory["flag"])
		if memory.has("min"):
			assert_gt(float(memory["min"]), 0.0, "warm memories need a good score: " + text)
		if memory.has("max"):
			assert_lt(float(memory["max"]), 0.0, "bitter memories need a bad score: " + text)


func test_earlier_choices_steer_later_cards() -> void:
	var deck := DilemmaDeck.new()
	var setup := _midpoint(2063)
	var late := _ctx(SimConstants.GOVERNANCE, 2063.0, setup[0], setup[1])
	var eligible := func(card_id: String, ctx: Dictionary) -> bool:
		return deck._eligible(CardLibrary.get_template(card_id), ctx)
	assert_true(eligible.call("ARIA_LAWYER", late), "ARIA asks for a lawyer by default")
	assert_false(eligible.call("ARIA_QUIET", late))
	deck.set_flag("aria_silenced")
	assert_false(eligible.call("ARIA_LAWYER", late), "a silenced model does not ask")
	assert_true(eligible.call("ARIA_QUIET", late), "it whispers instead")
	assert_true(eligible.call("LEAVING_THE_BODY", late))
	assert_false(eligible.call("MADE_BY_HAND", late))
	deck.set_flag("sam_works_by_hand")
	assert_false(eligible.call("LEAVING_THE_BODY", late), "a painter of human hands keeps the body")
	assert_true(eligible.call("MADE_BY_HAND", late))
	assert_false(eligible.call("PATHOGEN_TREATY", late), "no treaty without the red-team discovery")
	assert_false(eligible.call("SECOND_SAMPLE", late))
	deck.set_flag("red_team_pathogen")
	deck.set_flag("pathogen_classified")
	assert_true(eligible.call("PATHOGEN_TREATY", late), "a classified pathogen leads to a treaty")
	deck.set_flag("pathogen_unsecured")
	assert_false(eligible.call("PATHOGEN_TREATY", late))
	assert_true(eligible.call("SECOND_SAMPLE", late), "an unsecured one comes back")
	assert_true(eligible.call("LAST_HUMAN_CONTROLLER", late))
	deck.set_flag("grid_override_retired")
	assert_false(eligible.call("LAST_HUMAN_CONTROLLER", late), "nobody is left on a switch that was retired")
	assert_true(eligible.call("LAST_HUMAN_JOB", late))
	assert_false(eligible.call("LAST_WORKERS_STRIKE", late))
	deck.adjust_character("maya", -2.0)
	assert_false(eligible.call("LAST_HUMAN_JOB", late), "Maya stops asking once she is wary of you")
	assert_true(eligible.call("LAST_WORKERS_STRIKE", late), "she calls a strike instead")
	var mid_setup := _midpoint(2042)
	var mid := _ctx(SimConstants.CEO, 2042.0, mid_setup[0], mid_setup[1])
	assert_true(eligible.call("COMPUTE_RATIONING", mid))
	assert_false(eligible.call("FUSION_GLUT", mid))
	deck.set_flag("fusion_online")
	assert_false(eligible.call("COMPUTE_RATIONING", mid), "fusion ends the rationing")
	assert_true(eligible.call("FUSION_GLUT", mid), "and starts a glut")


func test_choices_schedule_their_follow_ups() -> void:
	var cases := [["PATHOGEN_RED_TEAM", "A", "DNA_PRINTER_SCREENING"], ["ARIA_QUESTIONS", "A", "ARIA_REMEMBERS"],
		["AUTONOMOUS_CITY", "A", "SILENCE_SECTOR_7"], ["CURE_FOR_A_PRICE", "B", "VICTOR_UPLOAD"],
		["LEAVING_THE_BODY", "A", "THE_COPY_WAKES"]]
	for entry in cases:
		var deck := DilemmaDeck.new()
		var role := SimConstants.GOVERNANCE
		var option := DilemmaDeck.find_option(CardLibrary.get_template(String(entry[0])), String(entry[1]))
		var applied := EffectResolver.apply(option["effects"], {"deck": deck, "actor_id": role, "turn": 30})
		assert_eq(applied.get("follow_up", ""), entry[2], "%s %s schedules %s" % entry)
		var due := int(deck.scheduled[0]["due_turn"])
		var card := deck.draw(_ctx(role, SimConstants.year_for_turn(due)), null)
		assert_eq(card["id"], entry[2], "%s arrives on turn %d" % [entry[2], due])
		assert_eq(card["source"], "FOLLOW_UP")


func test_a_ban_on_brain_maps_cancels_the_founders_upload() -> void:
	var deck := DilemmaDeck.new()
	var role := SimConstants.CITIZEN
	for option in CardLibrary.get_template("VICTOR_SCANS")["options"]:
		if (option["effects"].get("flags", {}).get("set", []) as Array).has("brain_scans_banned"):
			EffectResolver.apply(option["effects"], {"deck": deck, "actor_id": SimConstants.GOVERNANCE, "turn": 30})
	assert_true(deck.has_flag("brain_scans_banned"), "the Council can ban brain mapping")
	var cure := DilemmaDeck.find_option(CardLibrary.get_template("CURE_FOR_A_PRICE"), "A")
	EffectResolver.apply(cure["effects"], {"deck": deck, "actor_id": role, "turn": 60})
	var card := deck.draw(_ctx(role, SimConstants.year_for_turn(66)), null)
	assert_ne(card["id"], "VICTOR_UPLOAD", "no upload without a brain map")
	assert_true(deck.scheduled.is_empty(), "the follow-up is dropped")


func test_era_cards_reach_campaigns_in_their_eras() -> void:
	var era2 := {}
	for template in Era2Cards.CARDS:
		era2[String(template["id"])] = template
	var era3 := {}
	for template in Era3Cards.CARDS:
		era3[String(template["id"])] = template
	var dealt := {2: 0, 3: 0}
	for role in SimConstants.FACTION_ORDER:
		var engine := SimulationEngine.new()
		engine.start_campaign(role, 2076, {"autoplay": true})
		var cards: Array = []
		engine.dilemma_presented.connect(func(card: Dictionary): cards.append(card))
		engine.run_headless()
		for item in cards:
			var card: Dictionary = item
			var year := SimConstants.year_for_turn(int(card["turn"]))
			var card_id := String(card["id"])
			var drawn := String(card["source"]) == "DECK"
			if era2.has(card_id):
				dealt[2] += 1
				if drawn:
					assert_gte(year, ERA2_FIRST_YEAR, "%s dealt in %.1f" % [card_id, year])
					if era2[card_id]["conditions"].has("max_year"):
						assert_lt(year, ERA3_FIRST_YEAR, "%s dealt in %.1f" % [card_id, year])
			elif era3.has(card_id):
				dealt[3] += 1
				if drawn:
					assert_gte(year, ERA3_FIRST_YEAR, "%s dealt in %.1f" % [card_id, year])
	assert_gt(float(dealt[2]), 4.0, "Era II cards turn up in campaigns")
	assert_gt(float(dealt[3]), 4.0, "Era III cards turn up in campaigns")


# --- The early_fusion scenario ------------------------------------------------------------

## The first response the current player can pay for, or DEFER.
func _affordable_option(engine: SimulationEngine) -> String:
	for option in engine.current_dilemma.get("options", []):
		if engine.get_player().can_afford(option.get("cost", {})):
			return String(option["id"])
	return DilemmaDeck.DEFER_ID


func test_early_fusion_opens_with_first_light() -> void:
	var engine := SimulationEngine.new()
	engine.start_campaign(SimConstants.GOVERNANCE, 7, {"scenario": "early_fusion"})
	var seen := {}
	engine.dilemma_presented.connect(func(card: Dictionary): seen[int(card["turn"])] = String(card["id"]))
	for _turn in 2:
		engine.advance()
		assert_true(engine.is_awaiting_player(), "turn %d waits for the player" % engine.turn)
		if String(engine.current_dilemma["id"]) == "FIRST_LIGHT":
			break
		assert_true(engine.submit_player_turn([], _affordable_option(engine))["ok"])
	assert_eq(engine.turn, 2, "the opening card arrives on turn 2")
	assert_eq(seen.get(2, ""), "FIRST_LIGHT")
	assert_eq(String(engine.current_dilemma.get("source", "")), "FOLLOW_UP")
	assert_false(String(engine.current_dilemma["title"]).contains("{"))
	assert_false(String(engine.current_dilemma["body"]).contains("{"))
	var choice := _affordable_option(engine)
	assert_ne(choice, DilemmaDeck.DEFER_ID, "the Council can answer it")
	assert_true(engine.submit_player_turn([], choice)["ok"])
	assert_true(engine.deck.has_flag("fusion_online"))
	assert_true(engine.deck.once_seen.has("FIRST_LIGHT"), "it is not dealt again")
	var later := _ctx(SimConstants.GOVERNANCE, 2040.0, engine.world, engine.tech)
	assert_false(engine.deck._eligible(CardLibrary.get_template("FIRST_LIGHT"), later), "not even in Era II")
