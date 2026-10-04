extends SceneTree
## Standalone headless smoke test (PRD execution plan, step 5).
##
## Boots the engine, simulates the full 100-turn campaign once per role (all
## four factions driven by the heuristic fallback), prints end-state metrics to
## stdout and exits non-zero on NaN/out-of-range values or incomplete campaigns.
##
##   godot --headless --path . --script res://tests/headless_sim_test.gd
##   godot --headless --path . --script res://tests/headless_sim_test.gd -- --seed=42

const DEFAULT_SEED := 2076


func _initialize() -> void:
	var campaign_seed := DEFAULT_SEED
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			campaign_seed = int(arg.get_slice("=", 1))

	print("SYNAPSE-2076 :: headless simulation test (seed %d)" % campaign_seed)
	print("Heuristic fallback engine drives all four factions; LLM layer not attached.\n")
	var failures: Array[String] = []
	var started := Time.get_ticks_msec()

	for role in SimConstants.FACTION_ORDER:
		var engine := SimulationEngine.new()
		engine.start_campaign(role, campaign_seed, {"autoplay": true})
		var result := engine.run_headless()
		var problems := _validate(engine, result)
		for problem in problems:
			failures.append("%s: %s" % [role, problem])
		_print_result(role, engine, result)

	var elapsed := Time.get_ticks_msec() - started
	print("\nCompleted 4 campaigns in %d ms." % elapsed)
	if failures.is_empty():
		print("RESULT: PASS (zero runtime errors, all metrics finite and within [0, 100])")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		print("RESULT: FAIL (%d problem(s))" % failures.size())
		quit(1)


func _validate(engine: SimulationEngine, result: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	if not engine.is_ended():
		problems.append("campaign did not end (turn %d, phase %s)" % [engine.turn, engine.phase_name()])
	if result.is_empty():
		problems.append("no campaign result")
		return problems
	problems.append_array(engine.world.validate())
	if result["reason"] == "TURN_LIMIT" and engine.turn != SimConstants.TOTAL_TURNS:
		problems.append("turn limit reached at turn %d" % engine.turn)
	for entry in engine.world.history:
		for key in WorldState.METRIC_KEYS:
			var value := float(entry[key])
			if not is_finite(value) or value < 0.0 or value > 100.0:
				problems.append("history turn %d: %s = %s" % [entry["turn"], key, value])
	for faction_id in engine.factions:
		var actor: ActorBase = engine.factions[faction_id]
		for key in actor.resources:
			if not is_finite(float(actor.resources[key])):
				problems.append("%s.%s is not finite" % [faction_id, key])
	return problems


func _print_result(role: String, engine: SimulationEngine, result: Dictionary) -> void:
	print("=== ROLE: %s ===" % SimConstants.role_title(role))
	if result.is_empty():
		print("  (no result)")
		return
	var outcome: Dictionary = result["outcome"]
	var verdict: Dictionary = result["verdict"]
	print("  Ended: turn %d (%d), reason %s" % [result["turn"], int(result["year"]), result["reason"]])
	print("  End-state %d: %s - %s%s" % [outcome["number"], outcome["name"], outcome["subtitle"],
		"" if outcome["strict_match"] else "  [nearest attractor]"])
	print("  Verdict: %s (score %.0f)" % [verdict["verdict"], verdict["score"]])
	for key in WorldState.METRIC_KEYS:
		print("    %-22s %6.1f" % [key, engine.world.get_value(key)])
	print("    %-22s %6.1f" % ["enforcement_level", engine.world.enforcement_level])
	print("    %-22s %6.2f  (capability %.0f, era %d)" % ["log10_training_flops", engine.tech.log_flops,
		engine.tech.get_capability_index(), engine.tech.era])
	print("    paradigm shifts: %s" % ", ".join(engine.tech.unlocked_shifts))
	print("    emergences:      %d  | alignment-tax events: %d" % [engine.tech.emerged_capabilities.size(), engine.tech.alignment_tax_events])
