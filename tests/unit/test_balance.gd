extends "res://tests/framework/test_case.gd"
## Balance guardrails: a small Monte Carlo over autoplay campaigns. These are
## loose bounds meant to catch regressions (one end-state swallowing the matrix,
## runaway catastrophes, campaigns collapsing early), not to pin exact numbers.
## Use tools/monte_carlo.gd for the full report when tuning.

const RUNS_PER_ROLE := 12

var _results: Array[Dictionary] = []


func before_all() -> void:
	for role in SimConstants.FACTION_ORDER:
		for i in RUNS_PER_ROLE:
			var engine := SimulationEngine.new()
			engine.start_campaign(role, 5000 + i, {"autoplay": true})
			var result := engine.run_headless()
			_results.append({"role": role, "result": result, "engine": engine})


func test_outcome_variety() -> void:
	var counts := {}
	for entry in _results:
		var outcome_id := String(entry["result"]["outcome"]["id"])
		counts[outcome_id] = int(counts.get(outcome_id, 0)) + 1
	assert_gte(float(counts.size()), 4.0, "at least four distinct end-states: %s" % str(counts))
	for outcome_id in counts:
		assert_lt(float(counts[outcome_id]) / _results.size(), 0.75, "%s does not dominate" % outcome_id)


func test_most_campaigns_reach_2076() -> void:
	var catastrophes := 0
	var turn_sum := 0
	for entry in _results:
		var result: Dictionary = entry["result"]
		if result["reason"] == "CATASTROPHE":
			catastrophes += 1
		turn_sum += int(result["turn"])
	assert_lt(float(catastrophes) / _results.size(), 0.35, "catastrophe rate")
	assert_gt(float(turn_sum) / _results.size(), 85.0, "mean campaign length")


func test_player_role_changes_the_world() -> void:
	# Identical seeds, different player perspectives: the crisis choices of the
	# player must be able to move the end-state.
	var by_seed := {}
	for entry in _results:
		var seed_value := int(entry["result"]["seed"])
		if not by_seed.has(seed_value):
			by_seed[seed_value] = {}
		by_seed[seed_value][entry["role"]] = String(entry["result"]["outcome"]["id"])
	var divergent := 0
	for seed_value in by_seed:
		var distinct := {}
		for role in by_seed[seed_value]:
			distinct[by_seed[seed_value][role]] = true
		if distinct.size() > 1:
			divergent += 1
	assert_gt(float(divergent) / by_seed.size(), 0.5, "most seeds diverge by player role")


func test_trajectories_stay_gradual_early() -> void:
	# The 2030s should not already sit at the extremes.
	for entry in _results:
		var engine: SimulationEngine = entry["engine"]
		var early: Dictionary = engine.world.history[mini(20, engine.world.history.size() - 1)]
		assert_lt(float(early["labor_displacement"]), 70.0, "labor displacement by 2036")
		assert_lt(float(early["algorithmic_autonomy"]), 75.0, "autonomy by 2036")
