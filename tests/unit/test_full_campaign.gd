extends "res://tests/framework/test_case.gd"
## End-to-end: full 100-turn campaigns in automated and player-interactive modes
## (PRD milestone 6).

const SEEDS := [1, 7, 2076, 31337]


func _validate(engine: SimulationEngine, label: String) -> void:
	assert_true(engine.is_ended(), label + " ended")
	assert_eq(engine.world.validate().size(), 0, label + " world valid: " + str(engine.world.validate()))
	assert_eq(engine.world.history.size(), engine.turn + 1, label + " history per turn")
	for entry in engine.world.history:
		for key in WorldState.METRIC_KEYS:
			var value := float(entry[key])
			if not (is_finite(value) and value >= 0.0 and value <= 100.0):
				fail_test("%s turn %d %s=%s" % [label, entry["turn"], key, value])
				return
	for faction_id in engine.factions:
		for key in engine.factions[faction_id].resources:
			assert_finite(float(engine.factions[faction_id].resources[key]), "%s %s.%s" % [label, faction_id, key])
	var result := engine.result
	assert_false(VictoryMatrix.get_outcome(result["outcome"]["id"]).is_empty(), label + " valid outcome")
	assert_has(["VICTORY", "PYRRHIC", "DEFEAT"], result["verdict"]["verdict"], label + " verdict")
	assert_has(["TURN_LIMIT", "PLAYER_LOSS", "CATASTROPHE"], result["reason"], label + " reason")
	if result["reason"] == "TURN_LIMIT":
		assert_eq(engine.turn, SimConstants.TOTAL_TURNS, label + " reached turn 100")


func test_automated_campaigns_for_every_role_and_seed() -> void:
	for role in SimConstants.FACTION_ORDER:
		for seed_value in SEEDS:
			var engine := SimulationEngine.new()
			engine.start_campaign(role, seed_value, {"autoplay": true})
			engine.run_headless()
			_validate(engine, "%s/%d" % [role, seed_value])


func test_interactive_campaign_with_scripted_player() -> void:
	for role in SimConstants.FACTION_ORDER:
		var engine := SimulationEngine.new()
		engine.start_campaign(role, 99)
		var chooser := RandomNumberGenerator.new()
		chooser.seed = 4
		var rejected := 0
		for _guard in 400:
			if engine.is_ended():
				break
			engine.advance()
			if not engine.is_awaiting_player():
				continue
			var submission := _scripted_choice(engine, chooser)
			var response := engine.submit_player_turn(submission["directives"], submission["option"])
			if not response["ok"]:
				rejected += 1
				engine.submit_player_turn([], DilemmaDeck.DEFER_ID)
		assert_eq(rejected, 0, role + " scripted submissions all valid")
		_validate(engine, role + "/interactive")


func test_headless_campaigns_are_fast() -> void:
	var started := Time.get_ticks_msec()
	for role in SimConstants.FACTION_ORDER:
		var engine := SimulationEngine.new()
		engine.start_campaign(role, 5, {"autoplay": true})
		engine.run_headless()
	assert_lt(float(Time.get_ticks_msec() - started), 10000.0, "four 100-turn campaigns in under 10 s")


## A player who picks a random affordable crisis option and up to two random
## affordable directives, as the UI would allow.
func _scripted_choice(engine: SimulationEngine, chooser: RandomNumberGenerator) -> Dictionary:
	var player := engine.get_player()
	var card := engine.current_dilemma
	var budget := player.resources.duplicate()
	var options := []
	for option in card["options"]:
		if player.can_afford(option["cost"]):
			options.append(option)
	var option_id := DilemmaDeck.DEFER_ID
	if not options.is_empty() and chooser.randf() < 0.85:
		var option: Dictionary = options[chooser.randi_range(0, options.size() - 1)]
		option_id = option["id"]
		for key in option["cost"]:
			budget[key] = float(budget[key]) - float(option["cost"][key])
	var directives := []
	var candidates := player.get_available_actions()
	for i in range(candidates.size() - 1, 0, -1):
		var j := chooser.randi_range(0, i)
		var swap := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = swap
	for action_id in candidates:
		if directives.size() >= engine.max_player_directives:
			break
		var intensity: float = [1.0, 1.0, 1.5, 2.0][chooser.randi_range(0, 3)]
		var cost := player.get_action_cost(action_id, intensity)
		var affordable := true
		for key in cost:
			if float(budget.get(key, 0.0)) + 0.0001 < float(cost[key]):
				affordable = false
		if not affordable:
			continue
		for key in cost:
			budget[key] = float(budget[key]) - float(cost[key])
		directives.append({"action": action_id, "intensity": intensity})
	return {"directives": directives, "option": option_id}
