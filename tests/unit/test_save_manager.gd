extends "res://tests/framework/test_case.gd"
## Saves and Continue: SaveManager writes the engine's record and metadata as
## JSON and resumes it by replay; bad files read as "no save".

var saves: SaveManager
var save_dir := ""


func before_all() -> void:
	save_dir = "user://test_output/saves_%d" % OS.get_process_id()


func before_each() -> void:
	_remove_dir(save_dir)
	saves = SaveManager.new(save_dir)


func after_all() -> void:
	_remove_dir(save_dir)
	DirAccess.remove_absolute(save_dir.get_base_dir())


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)


func _engine(role: String = SimConstants.GOVERNANCE, seed_value: int = 404, options: Dictionary = {}) -> SimulationEngine:
	var engine := SimulationEngine.new()
	engine.start_campaign(role, seed_value, options)
	return engine


## Plays until turn [param last_turn] completes, answering every human with an
## affordable option and the heuristic's directive, then brings the engine to
## the next decision.
func _play(engine: SimulationEngine, last_turn: int) -> void:
	for _guard in last_turn * 12 + 20:
		if engine.is_ended() or (engine.turn >= last_turn and engine.phase == SimulationEngine.Phase.IDLE):
			break
		if not engine.is_awaiting_player():
			engine.advance()
			continue
		var option := DilemmaDeck.DEFER_ID
		for candidate in engine.current_dilemma.get("options", []):
			if engine.get_player().can_afford(candidate.get("cost", {})):
				option = String(candidate["id"])
				break
		var decision := HeuristicFallback.evaluate(engine.player_role, engine.build_observation(engine.player_role))
		if not engine.submit_player_turn([{"action": decision["action"], "intensity": 1.2}], option)["ok"]:
			if not engine.submit_player_turn([], option)["ok"]:
				engine.submit_player_turn([], DilemmaDeck.DEFER_ID)
	engine.advance()


func _assert_same_world(a: SimulationEngine, b: SimulationEngine, context: String) -> void:
	assert_eq(b.turn, a.turn, context + ": turn")
	assert_eq(b.phase, a.phase, context + ": phase")
	for key in WorldState.METRIC_KEYS + WorldState.INDEX_KEYS:
		assert_almost_eq(b.world.get_value(key), a.world.get_value(key), 0.000001, "%s: %s" % [context, key])
	for faction_id in SimConstants.FACTION_ORDER:
		var resources_a: Dictionary = (a.factions[faction_id] as ActorBase).resources
		var resources_b: Dictionary = (b.factions[faction_id] as ActorBase).resources
		for key in resources_a:
			assert_almost_eq(float(resources_b[key]), float(resources_a[key]), 0.000001, "%s: %s %s" % [context, faction_id, key])
	assert_almost_eq(b.tech.log_flops, a.tech.log_flops, 0.000001, context + ": compute")


func _write(slot: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(save_dir)
	var file := FileAccess.open(saves.path_for(slot), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _read(slot: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(saves.path_for(slot)))


# --- Round trip ---------------------------------------------------------------------

func test_a_saved_campaign_resumes_at_the_same_decision() -> void:
	var engine := _engine(SimConstants.GOVERNANCE, 404)
	_play(engine, 14)
	assert_true(engine.is_awaiting_player(), "saved while a crisis waits")
	assert_false(saves.has_save(), "nothing saved yet")
	assert_true(saves.save(engine, {"spectate": false}))
	assert_true(saves.has_save())
	assert_true(FileAccess.file_exists(saves.path_for()), "user://.../autosave.json")
	assert_false(FileAccess.file_exists(saves.path_for() + ".tmp"), "the temporary file is renamed away")
	var resumed := saves.resume()
	assert_not_null(resumed)
	if resumed == null:
		return
	assert_true(resumed.is_awaiting_player(), "back at the decision")
	_assert_same_world(engine, resumed, "resumed")
	assert_eq(String(resumed.current_dilemma["id"]), String(engine.current_dilemma["id"]), "the same crisis on the desk")
	assert_eq(resumed.player_role, engine.player_role)
	assert_eq(resumed.event_log.size(), engine.event_log.size(), "the same history")
	# Both play on identically.
	_play(engine, 18)
	_play(resumed, 18)
	_assert_same_world(engine, resumed, "four turns later")


func test_saving_between_turns_resumes_at_the_next_decision() -> void:
	var engine := _engine(SimConstants.CITIZEN, 77, {"scenario": "open_weights", "difficulty": Difficulty.HARD})
	_play(engine, 6)
	engine.submit_player_turn([], DilemmaDeck.DEFER_ID)
	assert_eq(engine.phase, SimulationEngine.Phase.IDLE)
	assert_true(saves.save(engine))
	var resumed := saves.resume()
	assert_not_null(resumed)
	if resumed == null:
		return
	engine.advance()
	_assert_same_world(engine, resumed, "next decision")
	assert_eq(resumed.scenario_id, "open_weights")
	assert_eq(resumed.difficulty, Difficulty.HARD)
	assert_eq(String(resumed.current_dilemma["id"]), String(engine.current_dilemma["id"]))


func test_pass_and_play_and_late_starts_resume() -> void:
	var options := CampaignModes.options_for(CampaignModes.DECADE_2)
	options["human_roles"] = [SimConstants.ASI]
	var engine := _engine(SimConstants.CEO, 12, options)
	_play(engine, 23)
	engine.submit_player_turn([], DilemmaDeck.DEFER_ID)
	assert_eq(engine.player_role, SimConstants.ASI, "saved while the second player decides")
	assert_true(saves.save(engine))
	var resumed := saves.resume()
	assert_not_null(resumed)
	if resumed == null:
		return
	assert_eq(resumed.human_roles, [SimConstants.CEO, SimConstants.ASI] as Array[String])
	assert_eq(resumed.player_role, SimConstants.ASI, "the second player's turn")
	assert_eq(resumed.start_turn, 20)
	assert_eq(resumed.total_turns, 39)
	_assert_same_world(engine, resumed, "pass-and-play")
	assert_eq(saves.summary()["mode"], CampaignModes.DECADE_2)


# --- Metadata and the Continue card ---------------------------------------------------

func test_summary_describes_the_save() -> void:
	var options := CampaignModes.options_for(CampaignModes.QUARTER)
	options["scenario"] = "chip_war"
	options["difficulty"] = Difficulty.HARD
	options["human_roles"] = [SimConstants.CITIZEN]
	var engine := _engine(SimConstants.GOVERNANCE, 20261004, options)
	_play(engine, 3)
	assert_true(saves.save(engine, {"daily": "2026-10-04", "spectate": false}))
	var file := _read(SaveManager.AUTOSAVE)
	var now := float(file["saved_at"])
	assert_almost_eq(now, Time.get_unix_time_from_system(), 5.0, "saved_at is unix seconds")
	for key in ["version", "saved_at", "role", "humans", "turn", "year", "era", "scenario", "difficulty", "mode", "seed", "daily", "record"]:
		assert_has(file, key, "the file keeps " + key)
	assert_eq(int(file["version"]), SaveManager.VERSION)
	assert_eq(int(file["record"]["version"]), SimulationEngine.RECORD_VERSION)
	var summary := saves.summary(SaveManager.AUTOSAVE, now + 300.0)
	assert_eq(summary["role"], SimConstants.GOVERNANCE)
	assert_eq(summary["role_title"], SimConstants.role_title(SimConstants.GOVERNANCE))
	assert_eq(summary["humans"], [SimConstants.GOVERNANCE, SimConstants.CITIZEN])
	assert_eq(summary["players"], 2)
	assert_eq(summary["turn"], engine.turn)
	assert_eq(summary["year"], int(floor(engine.get_year())))
	assert_eq(summary["era"], 1)
	assert_eq(summary["mode"], CampaignModes.QUARTER)
	assert_eq(summary["mode_name"], "Quarter century")
	assert_eq(summary["years"], "2026–2051")
	assert_eq(summary["scenario"], "chip_war")
	assert_eq(summary["scenario_name"], "The Chip War")
	assert_eq(summary["difficulty_name"], "Hard")
	assert_eq(summary["seed"], 20261004)
	assert_eq(summary["daily"], "2026-10-04")
	assert_false(summary["spectate"])
	assert_eq(summary["saved_at_text"], "5 min ago")
	assert_eq(saves.summary(SaveManager.AUTOSAVE, now + 2.0)["saved_at_text"], "just now")


func test_relative_save_times() -> void:
	var saved := 1790000000
	assert_eq(SaveManager.relative_time(saved, saved + 10), "just now")
	assert_eq(SaveManager.relative_time(saved, saved - 100), "just now", "a clock that went back")
	assert_eq(SaveManager.relative_time(saved, saved + 59 * 60), "59 min ago")
	assert_eq(SaveManager.relative_time(saved, saved + 3 * 3600 + 5), "3 h ago")
	assert_eq(SaveManager.relative_time(saved, saved + 30 * 3600), "yesterday")
	assert_eq(SaveManager.relative_time(saved, saved + 4 * 86400), "4 days ago")
	assert_eq(SaveManager.relative_time(saved, saved + 30 * 86400), "2026-09-21")


func test_ended_campaigns_are_not_saved() -> void:
	var engine := _engine(SimConstants.ASI, 5, {"autoplay": true, "total_turns": 6})
	engine.run_headless()
	assert_true(engine.is_ended())
	assert_false(saves.save(engine), "an ended campaign has nothing to continue")
	assert_false(saves.has_save())
	assert_false(saves.save(null))
	assert_false(saves.save(SimulationEngine.new()), "an engine that never started")


# --- Bad files -------------------------------------------------------------------------

func test_missing_and_corrupted_saves_read_as_none() -> void:
	assert_eq(saves.load_record(), {})
	assert_eq(saves.summary(), {})
	assert_null(saves.resume())
	for text in ["", "{not json", "[1, 2, 3]", "\"autosave\"", "{\"version\": 1}", "{\"version\": 1, \"record\": []}",
			"{\"version\": 1, \"record\": {\"version\": 1, \"role\": \"CEO\", \"seed\": \"x\", \"turns\": {}}}",
			"{\"version\": {}, \"record\": {\"version\": 1}}", "null"]:
		_write("broken", text)
		assert_false(saves.has_save("broken"), "unusable: %s" % text)
		assert_eq(saves.load_record("broken"), {})
		assert_eq(saves.summary("broken"), {})
		assert_null(saves.resume("broken"))
	# A file truncated mid-write.
	var engine := _engine()
	_play(engine, 2)
	saves.save(engine, {}, "whole")
	var text := FileAccess.get_file_as_string(saves.path_for("whole"))
	_write("truncated", text.left(floori(text.length() / 2.0)))
	assert_false(saves.has_save("truncated"))
	assert_null(saves.resume("truncated"))


func test_other_versions_are_not_resumed() -> void:
	var engine := _engine(SimConstants.CEO, 9)
	_play(engine, 3)
	saves.save(engine)
	var data := _read(SaveManager.AUTOSAVE)
	data["version"] = SaveManager.VERSION + 1
	_write("newer_file", JSON.stringify(data))
	assert_false(saves.has_save("newer_file"), "a newer save format")
	data["version"] = SaveManager.VERSION
	data["record"]["version"] = SimulationEngine.RECORD_VERSION + 1
	_write("newer_record", JSON.stringify(data))
	assert_false(saves.has_save("newer_record"), "a newer engine record")
	assert_null(saves.resume("newer_record"))
	data["record"]["version"] = SimulationEngine.RECORD_VERSION
	data["record"]["role"] = "NOBODY"
	_write("bad_role", JSON.stringify(data))
	assert_null(saves.resume("bad_role"), "an unknown role")
	assert_true(saves.has_save(), "the real save is untouched")


func test_a_save_whose_replay_diverges_is_refused() -> void:
	var engine := _engine(SimConstants.CEO, 31)
	_play(engine, 8)
	saves.save(engine)
	var data := _read(SaveManager.AUTOSAVE)
	data["record"]["turns"]["3"]["players"][SimConstants.CEO]["option"] = "NO_SUCH_OPTION"
	_write("diverged", JSON.stringify(data))
	assert_true(saves.has_save("diverged"), "the file itself is well formed")
	assert_null(saves.resume("diverged"), "but it no longer replays to the saved turn")


func test_delete_and_slots() -> void:
	var engine := _engine()
	_play(engine, 2)
	assert_true(saves.save(engine, {}, "manual 1"))
	assert_true(saves.has_save("manual 1"))
	assert_eq(SaveManager.clean_slot("../manual 1"), "___manual_1", "slot names cannot leave the save folder")
	assert_eq(saves.path_for("../manual 1").get_base_dir(), save_dir)
	assert_eq(SaveManager.clean_slot(""), SaveManager.AUTOSAVE)
	assert_false(saves.has_save(), "other slots are separate")
	assert_true(saves.delete("manual 1"))
	assert_false(saves.has_save("manual 1"))
	assert_false(saves.delete("manual 1"), "nothing left to delete")
	assert_eq(saves.summary("manual 1"), {})


func test_saving_a_full_campaign_is_fast() -> void:
	var engine := _engine(SimConstants.GOVERNANCE, 2076, {"autoplay": true})
	engine.run_headless(99)
	engine.autoplay_player = false
	engine.advance()
	assert_eq(engine.turn, 100)
	assert_true(engine.is_awaiting_player())
	var best := INF
	for _attempt in 3:
		var started := Time.get_ticks_usec()
		assert_true(saves.save(engine))
		best = minf(best, (Time.get_ticks_usec() - started) / 1000.0)
	assert_lt(best, 30.0, "a 100-turn save takes %.1f ms" % best)
	var resumed := saves.resume()
	assert_not_null(resumed)
	if resumed != null:
		_assert_same_world(engine, resumed, "turn 100")
