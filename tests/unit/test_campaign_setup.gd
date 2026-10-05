extends "res://tests/framework/test_case.gd"
## Setting up a campaign: CampaignModes (the century, a quarter century, a
## decade per era, the daily challenge) and the start screen that builds the
## configuration.

const PHONE := Vector2(412, 915)
const DESKTOP := Vector2(1600, 900)
const TABLET := Vector2(1180, 820)

var holder: Control


func before_each() -> void:
	holder = Control.new()
	holder.theme = EraTheme.get_theme(1)
	tree.root.add_child(holder)
	holder.position = Vector2.ZERO
	holder.size = DESKTOP


func after_each() -> void:
	holder.queue_free()
	await tree.process_frame


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


# --- The start screen ------------------------------------------------------------------

func _setup(size: Vector2 = DESKTOP, compact: bool = false) -> RoleSelect:
	holder.size = size
	var select := RoleSelect.new()
	holder.add_child(select)
	select.set_compact(compact)
	select.set_today("2026-10-04")
	return select


func _button(select: RoleSelect, node_name: String) -> Button:
	return select.find_child(node_name, true, false) as Button


## Presses [param node_name] the way a tap does (toggle chips toggle).
func _press(select: RoleSelect, node_name: String) -> void:
	var button := _button(select, node_name)
	assert_not_null(button, node_name)
	if button == null:
		return
	if button.toggle_mode:
		button.button_pressed = not button.button_pressed
	else:
		button.pressed.emit()


func _start(select: RoleSelect) -> Dictionary:
	var sent: Array = []
	var listener := func(config: Dictionary): sent.append(config)
	select.campaign_requested.connect(listener)
	_press(select, "StartButton")
	select.campaign_requested.disconnect(listener)
	assert_eq(sent.size(), 1, "one configuration per press")
	return sent[0] if not sent.is_empty() else {}


func _assert_fits(root_control: Control, width: float, context: String) -> void:
	var overflowing: Array[String] = []
	for node in root_control.find_children("*", "Control", true, false):
		var control := node as Control
		if control.is_visible_in_tree() and control.get_global_rect().end.x > width + 0.5:
			overflowing.append("%s (%s) ends at %.0f" % [control.name, control.get_class(), control.get_global_rect().end.x])
	assert_eq(overflowing.size(), 0, "%s fits %.0f px: %s" % [context, width, ", ".join(overflowing.slice(0, 5))])


func test_start_sends_the_whole_setup() -> void:
	var select := _setup()
	await wait_frames(2)
	var config := _start(select)
	assert_eq(config, {"role": SimConstants.GOVERNANCE, "seed": 2076, "spectate": false, "mode": CampaignModes.CENTURY, "daily": "",
		"options": {"human_roles": [SimConstants.GOVERNANCE], "difficulty": Difficulty.STANDARD, "scenario": Scenarios.STANDARD,
			"start_turn": 1, "total_turns": 100}}, "the defaults")
	select.select_role(SimConstants.CEO)
	_press(select, "Mode_quarter")
	_press(select, "Scenario_chip_war")
	_press(select, "Difficulty_hard")
	_press(select, "Seat_ASI")
	select.set_seed(77)
	config = _start(select)
	assert_eq(config, {"role": SimConstants.CEO, "seed": 77, "spectate": false, "mode": CampaignModes.QUARTER, "daily": "",
		"options": {"human_roles": [SimConstants.CEO, SimConstants.ASI], "difficulty": Difficulty.HARD, "scenario": "chip_war",
			"start_turn": 1, "total_turns": 50}})
	assert_true(_button(select, "Mode_quarter").button_pressed)
	assert_false(_button(select, "Mode_century").button_pressed, "one length at a time")
	assert_string_contains((select.find_child("ModeNote", true, false) as Label).text, "2026–2051")
	assert_eq((select.find_child("ScenarioNote", true, false) as Label).text, String(Scenarios.LIST["chip_war"]["summary"]))
	assert_eq((select.find_child("DifficultyNote", true, false) as Label).text, String(Difficulty.PRESETS["hard"]["summary"]))
	assert_eq((select.find_child("SeatNote", true, false) as Label).text, "2 players take turns on this device. The other two act on their own.")
	(select.find_child("SeedEdit", true, false) as LineEdit).text = "the century"
	assert_eq(_start(select)["seed"], hash("the century"), "words make a seed too")


func test_every_length_world_difficulty_and_table() -> void:
	var select := _setup()
	await wait_frames(1)
	var others := [SimConstants.CEO, SimConstants.ASI, SimConstants.CITIZEN]
	var checked := 0
	for mode in CampaignModes.ORDER:
		for scenario_id in Scenarios.ORDER:
			for preset_id in Difficulty.ORDER:
				for mask in 8:
					select.select_mode(mode)
					_button(select, "Scenario_" + scenario_id).button_pressed = true
					_button(select, "Difficulty_" + preset_id).button_pressed = true
					var humans: Array = [SimConstants.GOVERNANCE]
					for i in others.size():
						var seated := (mask >> i) & 1 == 1
						_button(select, "Seat_" + String(others[i])).button_pressed = seated
						if seated:
							humans.append(others[i])
					var config := _start(select)
					var expected := CampaignModes.options_for(mode)
					expected["scenario"] = scenario_id
					expected["difficulty"] = preset_id
					expected["human_roles"] = humans
					if config["options"] != expected or config["mode"] != mode:
						fail_test("%s/%s/%s/%d: %s" % [mode, scenario_id, preset_id, mask, str(config)])
					checked += 1
	assert_eq(checked, 5 * 5 * 3 * 8, "every combination")


func test_spectating_seats_nobody_else() -> void:
	var select := _setup()
	await wait_frames(1)
	_press(select, "Seat_CEO")
	_press(select, "Seat_CITIZEN_COALITION")
	assert_eq(select.seats, [SimConstants.CEO, SimConstants.CITIZEN])
	_press(select, "SpectateCheck")
	assert_true(select.is_spectating())
	assert_eq(select.seats, [], "spectating clears the table")
	assert_true(_button(select, "Seat_CEO").disabled)
	assert_eq((select.find_child("SeatNote", true, false) as Label).text, "Spectating: the AI plays every side.")
	var config := _start(select)
	assert_true(config["spectate"])
	assert_eq(config["options"]["human_roles"], [SimConstants.GOVERNANCE])
	select.set_seat(SimConstants.ASI, true)
	assert_eq(select.seats, [], "no seats while spectating")
	select.set_spectate(false)
	assert_false(_button(select, "Seat_CEO").disabled)
	# Picking a seated faction as your own frees its seat.
	select.set_seat(SimConstants.ASI, true)
	select.select_role(SimConstants.ASI)
	assert_eq(select.seats, [])
	assert_false(_button(select, "Seat_ASI").visible, "your own faction has no extra seat")
	assert_true(_button(select, "Seat_GOVERNANCE_COUNCIL").visible)
	assert_eq(_start(select)["options"]["human_roles"], [SimConstants.ASI])


func test_the_original_signal_waits_for_an_older_dashboard() -> void:
	var select := _setup()
	await wait_frames(1)
	var legacy: Array = []
	select.start_requested.connect(func(role: String, seed_value: int, spectate: bool): legacy.append([role, seed_value, spectate]))
	_press(select, "StartButton")
	assert_eq(legacy, [[SimConstants.GOVERNANCE, 2076, false]], "nobody listens to campaign_requested: start_requested carries it")
	_start(select)
	assert_eq(legacy.size(), 1, "a dashboard that listens to campaign_requested never starts twice")


func test_the_daily_challenge() -> void:
	var select := _setup()
	await wait_frames(1)
	assert_eq((select.find_child("DailyDate", true, false) as Label).text, "2026-10-04", "shows the date")
	var lineup := (select.find_child("DailyLineup", true, false) as Label).text
	var expected := CampaignModes.daily_config("2026-10-04")
	assert_string_contains(lineup, UiFormat.role_name(expected["role"]))
	assert_string_contains(lineup, Scenarios.display_name(expected["options"]["scenario"]))
	var sent: Array = []
	select.campaign_requested.connect(func(config: Dictionary): sent.append(config))
	select.select_mode(CampaignModes.QUARTER)
	select.set_seat(SimConstants.CEO, true)
	_press(select, "DailyButton")
	assert_eq(sent, [expected], "the day's challenge, whatever the setup says")
	assert_eq(sent[0]["seed"], 20261004)
	assert_eq(sent[0]["daily"], "2026-10-04")
	select.set_today("2026-10-05")
	_press(select, "DailyButton")
	assert_eq(sent[1], CampaignModes.daily_config("2026-10-05"))
	assert_ne(sent[1]["role"], sent[0]["role"], "tomorrow is someone else's turn")
	select.set_today("")
	assert_eq((select.find_child("DailyDate", true, false) as Label).text, CampaignModes.today_utc(), "today by default")


func test_continue_shows_only_with_a_save() -> void:
	var select := _setup()
	await wait_frames(1)
	assert_false(select.has_continue())
	assert_false(select.find_child("ContinueCard", true, false).visible)
	var saves := SaveManager.new("user://test_output/setup_saves_%d" % OS.get_process_id())
	var engine := SimulationEngine.new()
	engine.start_campaign(SimConstants.CITIZEN, 3, CampaignModes.options_for(CampaignModes.DECADE_2))
	engine.advance()
	assert_true(saves.save(engine, {"daily": "2026-10-04"}))
	select.set_continue(saves.summary())
	saves.delete()
	DirAccess.remove_absolute(saves.dir)
	DirAccess.remove_absolute(saves.dir.get_base_dir())
	assert_true(select.has_continue())
	assert_eq((select.find_child("ContinueTitle", true, false) as Label).text, "Citizen Coalition · 2036 · Era II")
	var detail := (select.find_child("ContinueDetail", true, false) as Label).text
	assert_eq(detail, "Era II decade · 2026 as we know it · Standard · Daily 2026-10-04")
	var asked := [0]
	select.continue_requested.connect(func(): asked[0] += 1)
	_press(select, "ContinueButton")
	assert_eq(asked[0], 1)
	select.set_continue({})
	assert_false(select.has_continue(), "an empty summary hides the card")
	select.set_continue({"role": "NOBODY"})
	assert_false(select.has_continue(), "so does a broken one")


func test_endings_button() -> void:
	var select := _setup()
	await wait_frames(1)
	assert_eq(_button(select, "EndingsButton").text, "Endings")
	select.set_endings_progress(Vector2i(3, 32))
	assert_eq(_button(select, "EndingsButton").text, "Endings · 3 of 32")
	var asked := [0]
	select.endings_requested.connect(func(): asked[0] += 1)
	_press(select, "EndingsButton")
	assert_eq(asked[0], 1)


func test_the_llm_switch_and_its_status_line() -> void:
	var select := _setup()
	await wait_frames(1)
	var llm_switch := select.find_child("LLMSwitch", true, false) as LLMSwitch
	assert_not_null(llm_switch, "the setup screen offers the LLM On/Off switch")
	for button in select.find_children("*", "Button", true, false):
		assert_ne((button as Button).text, "AI settings", "and no endpoint settings")
	var settings := GameSettings.instance()
	var saved := bool(settings.get_value("llm"))
	settings.set_value("llm", true)
	assert_true(llm_switch.is_on())
	(llm_switch.find_child("LLMOff", true, false) as Button).pressed.emit()
	assert_false(bool(settings.get_value("llm")), "the chips write GameSettings")
	select.set_llm_available(false)
	assert_true((llm_switch.find_child("LLMOn", true, false) as Button).disabled, "no backend: greyed out")
	select.set_llm_available(true)
	assert_false(llm_switch.is_on())
	select.set_llm_status("Online: claude-sonnet-5-5")
	assert_eq((select.find_child("LLMStatus", true, false) as Label).text, "Online: claude-sonnet-5-5")
	settings.set_value("llm", saved)


func _fill(select: RoleSelect) -> void:
	select.set_continue({"role": SimConstants.GOVERNANCE, "year": 2041, "era": 2, "mode_name": "Quarter century",
		"scenario_name": "Open-Weights World", "difficulty_name": "Story", "players": 3, "saved_at_text": "yesterday",
		"daily": "2026-10-03", "spectate": true})
	select.set_endings_progress(Vector2i(31, 32))
	select.set_llm_status("▲ [LLM OFFLINE - RUNNING HEURISTIC FALLBACK ENGINE]")
	select.select_mode(CampaignModes.DECADE_3)
	select.select_scenario("open_weights")
	select.set_seat(SimConstants.CEO, true)
	select.set_seat(SimConstants.CITIZEN, true)


func test_one_scrolling_column_fits_a_phone() -> void:
	var select := _setup(PHONE, true)
	_fill(select)
	await wait_frames(3)
	assert_true(select._body.vertical, "one column")
	assert_eq(select._grid.columns, 1)
	assert_true(select._sticky.visible, "the start button is pinned to the bottom")
	assert_eq(select.find_child("StartButton", true, false).get_parent(), select._sticky)
	var daily: Control = select.find_child("DailyCard", true, false)
	assert_eq(daily.get_parent(), select._box, "the daily challenge sits near the top on phones")
	_assert_fits(select, PHONE.x, "setup on a phone")
	for role in SimConstants.FACTION_ORDER:
		select.select_role(role)
		await wait_frames(1)
		_assert_fits(select, PHONE.x, "setup on a phone, %s selected" % role)
	# The narrowest compact canvas (UiLayout zooms smaller phones out to 360 px),
	# with the badge's phone text.
	select.set_llm_status("▲ LLM OFF")
	holder.size = Vector2(UiLayout.COMPACT_SHORT_SIDE_MIN, 640)
	await wait_frames(3)
	_assert_fits(select, UiLayout.COMPACT_SHORT_SIDE_MIN, "setup on a small phone")


func test_desktop_and_tablet_layouts() -> void:
	var select := _setup(DESKTOP, false)
	_fill(select)
	await wait_frames(3)
	assert_false(select._body.vertical, "roles beside the campaign settings")
	assert_eq(select._grid.columns, 2)
	assert_false(select._sticky.visible)
	assert_eq(select.find_child("DailyCard", true, false).get_parent(), select._roles_column, "under the roles on desktop")
	var panel: Control = select._panel
	assert_lt(panel.size.x, DESKTOP.x - 100.0, "room to spare at 1600 px")
	_assert_fits(select, DESKTOP.x, "setup on desktop")
	select.set_compact(true)
	holder.size = TABLET
	await wait_frames(3)
	assert_true(select._body.vertical)
	assert_eq(select._grid.columns, 2, "two roles abreast on a tablet")
	assert_lte(panel.size.x, RoleSelect.COMPACT_MAX_WIDTH + 0.5, "a readable column")
	_assert_fits(select, TABLET.x, "setup on a tablet")
	select.set_compact(false)
	holder.size = DESKTOP
	await wait_frames(2)
	assert_eq(select.find_child("DailyCard", true, false).get_parent(), select._roles_column, "back under the roles")


func test_the_setup_follows_the_era() -> void:
	var select := _setup()
	await wait_frames(1)
	var length: Label = null
	for label in select._sections:
		if String(label.get_meta("raw", "")) == "Length":
			length = label
	assert_eq(length.text, "Length")
	holder.theme = EraTheme.get_theme(2)
	await wait_frames(2)
	assert_eq(select._era, 2)
	assert_eq(length.text, "LENGTH", "Era II labels in capitals")
