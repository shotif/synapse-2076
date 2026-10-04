extends "res://tests/framework/test_case.gd"
## Setting up a campaign: CampaignModes (the century, a quarter century, a
## decade per era, the daily challenge) and the start screen that builds the
## configuration.


# --- CampaignModes --------------------------------------------------------------------

func _era_of_turn(turn: int) -> int:
	return SimConstants.era_for_year(SimConstants.year_for_turn(turn))


func test_modes_match_the_hardware_eras() -> void:
	assert_eq(CampaignModes.ORDER, [CampaignModes.CENTURY, CampaignModes.QUARTER, CampaignModes.DECADE_1, CampaignModes.DECADE_2,
		CampaignModes.DECADE_3])
	var expected := {
		CampaignModes.CENTURY: [1, 100, 100, "2026–2076"], CampaignModes.QUARTER: [1, 50, 50, "2026–2051"],
		CampaignModes.DECADE_1: [1, 19, 19, "2026–2035"], CampaignModes.DECADE_2: [20, 39, 20, "2036–2045"],
		CampaignModes.DECADE_3: [48, 67, 20, "2050–2059"],
	}
	for mode in CampaignModes.ORDER:
		var options := CampaignModes.options_for(mode)
		assert_eq(options, {"start_turn": expected[mode][0], "total_turns": expected[mode][1]}, mode)
		assert_eq(CampaignModes.turns_played(mode), expected[mode][2], mode + " turns")
		assert_eq(CampaignModes.years(mode), expected[mode][3], mode + " years")
		assert_false(CampaignModes.display_name(mode).is_empty())
		assert_false(CampaignModes.short_name(mode).is_empty())
		assert_true(CampaignModes.blurb(mode).ends_with("."), mode + " blurb")
		assert_eq(CampaignModes.mode_for(options), mode, "options identify their mode")
		assert_true(CampaignModes.is_valid(mode))
	# Each decade sits inside one era and ends where the era (or the decade) does.
	assert_eq(_era_of_turn(19), 1)
	assert_eq(_era_of_turn(20), 2, "Era I's decade ends on the era's last turn")
	assert_eq(_era_of_turn(int(CampaignModes.options_for(CampaignModes.DECADE_2)["start_turn"]) - 1), 1)
	assert_eq(_era_of_turn(int(CampaignModes.options_for(CampaignModes.DECADE_2)["start_turn"])), 2, "Era II's decade starts in 2036")
	assert_eq(_era_of_turn(int(CampaignModes.options_for(CampaignModes.DECADE_2)["total_turns"])), 2)
	assert_eq(_era_of_turn(int(CampaignModes.options_for(CampaignModes.DECADE_3)["start_turn"]) - 1), 2)
	assert_eq(_era_of_turn(int(CampaignModes.options_for(CampaignModes.DECADE_3)["start_turn"])), 3, "Era III's decade starts in 2050")
	for mode in [CampaignModes.DECADE_1, CampaignModes.DECADE_2, CampaignModes.DECADE_3]:
		assert_eq(CampaignModes.era_of(mode), _era_of_turn(int(CampaignModes.options_for(mode)["start_turn"])))
	assert_eq(CampaignModes.era_of(CampaignModes.CENTURY), 0)
	assert_eq(CampaignModes.mode_for({}), CampaignModes.CENTURY, "no options: the full century")
	assert_eq(CampaignModes.mode_for({"total_turns": 30}), CampaignModes.CUSTOM)
	assert_eq(CampaignModes.display_name(CampaignModes.CUSTOM), "Custom length")
	assert_eq(CampaignModes.options_for("nonsense"), CampaignModes.options_for(CampaignModes.CENTURY))
	assert_false(CampaignModes.is_valid("nonsense"))


func test_configs_are_cleaned_up() -> void:
	var config := CampaignModes.build_config(SimConstants.ASI, 7, CampaignModes.QUARTER, "chip_war", Difficulty.HARD,
		[SimConstants.CITIZEN, SimConstants.ASI, "NOBODY", SimConstants.CEO, SimConstants.CITIZEN])
	assert_eq(config["role"], SimConstants.ASI)
	assert_eq(config["seed"], 7)
	assert_eq(config["mode"], CampaignModes.QUARTER)
	assert_eq(config["daily"], "")
	assert_false(config["spectate"])
	assert_eq(config["options"], {"start_turn": 1, "total_turns": 50, "scenario": "chip_war", "difficulty": Difficulty.HARD,
		"human_roles": [SimConstants.ASI, SimConstants.CEO, SimConstants.CITIZEN]}, "the chosen role first, then seats in faction order")
	var spectating := CampaignModes.build_config(SimConstants.CEO, 1, "nonsense", "atlantis", "impossible", [SimConstants.ASI], true)
	assert_eq(spectating["mode"], CampaignModes.CENTURY)
	assert_eq(spectating["options"]["scenario"], Scenarios.STANDARD)
	assert_eq(spectating["options"]["difficulty"], Difficulty.STANDARD)
	assert_eq(spectating["options"]["human_roles"], [SimConstants.CEO], "nobody else sits at a spectated table")


func test_every_mode_starts_the_campaign_it_describes() -> void:
	for mode in CampaignModes.ORDER:
		var config := CampaignModes.build_config(SimConstants.GOVERNANCE, 99, mode, "the_pause", Difficulty.STORY, [SimConstants.ASI])
		var engine := SimulationEngine.new()
		engine.start_campaign(config["role"], config["seed"], config["options"])
		var options := CampaignModes.options_for(mode)
		assert_eq(engine.start_turn, int(options["start_turn"]), mode)
		assert_eq(engine.total_turns, int(options["total_turns"]), mode)
		assert_eq(engine.turn, int(options["start_turn"]) - 1, mode + ": the prologue ran on its own")
		assert_eq(engine.scenario_id, "the_pause")
		assert_eq(engine.difficulty, Difficulty.STORY)
		assert_eq(engine.human_roles, [SimConstants.GOVERNANCE, SimConstants.ASI] as Array[String])
		assert_eq(CampaignModes.mode_for(engine.options), mode, mode + ": the engine's options name the mode")


func test_the_daily_challenge_is_the_same_for_everyone_that_day() -> void:
	var day := CampaignModes.daily_config("2026-10-04")
	assert_eq(day, CampaignModes.daily_config("2026-10-04"), "deterministic")
	assert_eq(day["seed"], 20261004)
	assert_eq(day["daily"], "2026-10-04")
	assert_false(day["spectate"])
	assert_eq(day["options"]["difficulty"], Difficulty.STANDARD)
	assert_eq(day["options"]["human_roles"], [day["role"]])
	var n := CampaignModes.day_number("2026-10-04")
	assert_eq(n, 20730)
	assert_eq(day["role"], SimConstants.FACTION_ORDER[n % 4])
	assert_eq(day["options"]["scenario"], Scenarios.ORDER[n % 5])
	assert_eq(day["mode"], CampaignModes.DAILY_MODES[n % 3])
	assert_has(CampaignModes.DAILY_MODES, day["mode"])
	# Every combination comes round within 60 days, and no two days in a row repeat any part.
	var combos := {}
	var previous := {}
	for offset in 60:
		var date := Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string("2026-10-04") + offset * 86400)
		var config := CampaignModes.daily_config(date)
		assert_eq(config["seed"], int(date.replace("-", "")))
		combos["%s|%s|%s" % [config["role"], config["options"]["scenario"], config["mode"]]] = true
		if not previous.is_empty():
			assert_ne(config["role"], previous["role"], date)
			assert_ne(config["options"]["scenario"], previous["options"]["scenario"], date)
			assert_ne(config["mode"], previous["mode"], date)
		previous = config
	assert_eq(combos.size(), 60, "every role x scenario x era")
	# Malformed dates mean today.
	for bad in ["", "2026-13-01", "04/10/2026", "yesterday", "2026-1-4"]:
		assert_eq(CampaignModes.daily_config(bad)["daily"], CampaignModes.today_utc(), "'%s' means today" % bad)
	assert_true(CampaignModes.is_valid_date(CampaignModes.today_utc()))
