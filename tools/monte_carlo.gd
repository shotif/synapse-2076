extends SceneTree
## Monte Carlo balance report: runs autoplay campaigns across seeds and roles
## and prints end-state distribution, termination reasons, verdicts and mean
## metric trajectories. Use it after touching any coupling constant.
##
##   godot --headless --path . --script res://tools/monte_carlo.gd -- --runs=50
##   godot --headless --path . --script res://tools/monte_carlo.gd -- --runs=200 --role=ASI

const CHECKPOINT_TURNS := [20, 48, 75, 100]


func _initialize() -> void:
	var runs := 40
	var roles: Array = SimConstants.FACTION_ORDER.duplicate()
	var seed_offset := 1000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--runs="):
			runs = int(arg.get_slice("=", 1))
		elif arg.begins_with("--role="):
			roles = [arg.get_slice("=", 1)]
		elif arg.begins_with("--seed-offset="):
			seed_offset = int(arg.get_slice("=", 1))

	var started := Time.get_ticks_msec()
	var outcomes := {}
	var strict := 0
	var reasons := {}
	var verdicts := {}
	var collapses := {}
	var checkpoints := {}
	var agi_years: Array[float] = []
	var shift_years := {}
	var emergences := 0.0
	var total := 0
	var end_turns: Array[int] = []
	var finals := {}
	var strict_outcomes := {}
	var role_outcomes := {}
	var role_scores := {}
	for role in roles:
		verdicts[role] = {"VICTORY": 0, "PYRRHIC": 0, "DEFEAT": 0}
		for i in runs:
			var engine := SimulationEngine.new()
			engine.start_campaign(role, seed_offset + i, {"autoplay": true})
			var result := engine.run_headless()
			total += 1
			var outcome_id := String(result["outcome"]["id"])
			outcomes[outcome_id] = int(outcomes.get(outcome_id, 0)) + 1
			if not role_outcomes.has(role):
				role_outcomes[role] = {}
				role_scores[role] = []
			role_outcomes[role][outcome_id] = int(role_outcomes[role].get(outcome_id, 0)) + 1
			role_scores[role].append(float(result["verdict"]["objective_score"]))
			if result["outcome"]["strict_match"]:
				strict += 1
				strict_outcomes[outcome_id] = int(strict_outcomes.get(outcome_id, 0)) + 1
			for key in result["final_values"]:
				if not finals.has(key):
					finals[key] = []
				finals[key].append(float(result["final_values"][key]))
			var reason := String(result["reason"])
			if reason == "PLAYER_LOSS":
				reason += ":" + String(result["player_loss"]["code"])
			elif reason == "CATASTROPHE":
				reason += ":" + String(result["catastrophe"]["code"])
			reasons[reason] = int(reasons.get(reason, 0)) + 1
			verdicts[role][result["verdict"]["verdict"]] += 1
			end_turns.append(int(result["turn"]))
			for faction_id in engine.factions:
				var count := (engine.factions[faction_id] as ActorBase).collapse_count
				if count > 0:
					collapses[faction_id] = int(collapses.get(faction_id, 0)) + count
			for entry in engine.world.history:
				var t := int(entry["turn"])
				if CHECKPOINT_TURNS.has(t):
					if not checkpoints.has(t):
						checkpoints[t] = {"n": 0}
					checkpoints[t]["n"] += 1
					for key in WorldState.METRIC_KEYS + ["capability_index", "log_flops"]:
						checkpoints[t][key] = float(checkpoints[t].get(key, 0.0)) + float(entry[key])
			if engine.tech.agi_turn >= 0:
				agi_years.append(SimConstants.year_for_turn(engine.tech.agi_turn))
			for shift_id in engine.tech.shift_unlock_turns:
				if not shift_years.has(shift_id):
					shift_years[shift_id] = []
				shift_years[shift_id].append(SimConstants.year_for_turn(int(engine.tech.shift_unlock_turns[shift_id])))
			emergences += engine.tech.emerged_capabilities.size()

	print("SYNAPSE-2076 Monte Carlo :: %d campaigns (%d per role) in %d ms" % [total, runs, Time.get_ticks_msec() - started])
	print("\nEND-STATES (strict signature matches: %d%%)" % int(100.0 * strict / maxf(1.0, total)))
	for outcome in VictoryMatrix.OUTCOMES:
		var count := int(outcomes.get(outcome["id"], 0))
		print("  %d. %-28s %5.1f%%  %s" % [outcome["number"], outcome["name"], 100.0 * count / total, "#".repeat(int(60.0 * count / total))])
	print("  strict-only: %s" % str(strict_outcomes))
	print("\nFINAL VALUES p10 / p50 / p90")
	for key in finals:
		var sorted_values: Array = finals[key]
		sorted_values.sort()
		var n := sorted_values.size()
		print("  %-22s %5.1f / %5.1f / %5.1f" % [key, sorted_values[int(n * 0.1)], sorted_values[int(n * 0.5)], sorted_values[mini(n - 1, int(n * 0.9))]])
	print("\nTERMINATION")
	for reason in reasons:
		print("  %-40s %5.1f%%" % [reason, 100.0 * reasons[reason] / total])
	var turn_sum := 0
	for t in end_turns:
		turn_sum += t
	print("  mean end turn: %.1f" % (float(turn_sum) / maxf(1.0, end_turns.size())))
	print("\nVERDICTS")
	for role in verdicts:
		var v: Dictionary = verdicts[role]
		print("  %-20s VICTORY %3d  PYRRHIC %3d  DEFEAT %3d" % [role, v["VICTORY"], v["PYRRHIC"], v["DEFEAT"]])
	print("\nEND-STATES BY PLAYER ROLE (mean objective score)")
	for role in role_outcomes:
		var parts: Array[String] = []
		for outcome in VictoryMatrix.OUTCOMES:
			parts.append("%d:%d" % [outcome["number"], int(role_outcomes[role].get(outcome["id"], 0))])
		print("  %-20s %s   obj %.1f" % [role, "  ".join(parts), _mean(role_scores[role])])
	print("\nAUTONOMOUS FACTION COLLAPSES (total)")
	for faction_id in collapses:
		print("  %-20s %d" % [faction_id, collapses[faction_id]])
	print("\nMEAN METRICS AT CHECKPOINTS")
	var header := "  turn  year "
	for key in WorldState.METRIC_KEYS:
		header += "%8s" % UiFormat.metric_short(key).left(7)
	print(header + "   capab  logF")
	for t in CHECKPOINT_TURNS:
		if not checkpoints.has(t):
			continue
		var c: Dictionary = checkpoints[t]
		var n := float(c["n"])
		var line := "  %4d  %4d " % [t, int(SimConstants.year_for_turn(t))]
		for key in WorldState.METRIC_KEYS:
			line += "%8.1f" % (float(c[key]) / n)
		print(line + "  %6.1f %5.2f   (n=%d)" % [float(c["capability_index"]) / n, float(c["log_flops"]) / n, int(n)])
	print("\nTECH")
	if not agi_years.is_empty():
		print("  AGI milestone: %d%% of runs, mean year %.1f" % [int(100.0 * agi_years.size() / total), _mean(agi_years)])
	for shift_id in TechTreeManager.SHIFT_ORDER:
		var years: Array = shift_years.get(shift_id, [])
		if years.is_empty():
			print("  %-30s never" % shift_id)
		else:
			print("  %-30s %3d%% of runs, mean year %.1f" % [shift_id, int(100.0 * years.size() / total), _mean(years)])
	print("  emergences per run: %.1f" % (emergences / total))
	quit(0)


func _mean(values: Array) -> float:
	var sum := 0.0
	for v in values:
		sum += float(v)
	return sum / maxf(1.0, values.size())
