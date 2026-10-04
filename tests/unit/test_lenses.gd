extends "res://tests/framework/test_case.gd"
## Faction lenses: each role gets its own view of the world, fed with real
## snapshots, log entries and player contexts from seeded headless campaigns.

const TITLES := {"CEO": "Markets", "GOVERNANCE_COUNCIL": "Briefing", "ASI": "Perception", "CITIZEN_COALITION": "Commons"}
const PHONE := Vector2(412, 915)

var host: Control


func before_each() -> void:
	host = Control.new()
	host.theme = EraTheme.get_theme(1)
	host.size = PHONE
	tree.root.add_child(host)


func after_each() -> void:
	host.queue_free()
	await tree.process_frame


## Plays [param turns] autoplay turns for [param role] (seed 2076), then
## presents the next player phase. Returns {engine, events, snapshots}.
func _play(role: String, turns: int) -> Dictionary:
	var engine := SimulationEngine.new()
	var events: Array = []
	var snapshots: Array = []
	engine.event_logged.connect(func(entry: Dictionary) -> void: events.append(entry))
	engine.telemetry_updated.connect(func(snapshot: Dictionary) -> void: snapshots.append(snapshot))
	engine.start_campaign(role, 2076, {"autoplay": true})
	engine.run_headless(turns)
	engine.advance()
	return {"engine": engine, "events": events, "snapshots": snapshots}


## Feeds a lens the way the dashboard does: every log entry, one update per
## completed turn, then the open player phase with a suggested directive.
func _feed(lens: LensPanel, run: Dictionary) -> void:
	var engine: SimulationEngine = run["engine"]
	for entry in run["events"]:
		lens.record_event(entry)
	for snapshot in run["snapshots"]:
		lens.update_state(snapshot, snapshot["factions"][engine.player_role]["resources"])
	lens.update_state(engine.get_snapshot(), engine.get_player().resources)
	lens.set_context(_context(engine))


func _context(engine: SimulationEngine) -> Dictionary:
	var context := engine.get_player_context()
	context["suggested_action"] = String(HeuristicFallback.evaluate(engine.player_role, engine.build_observation(engine.player_role))["action"])
	return context


func _mount(role: String, compact: bool) -> LensPanel:
	var lens := LensPanel.create(role)
	lens.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(lens)
	lens.set_compact(compact)
	return lens


func _directive_buttons(lens: LensPanel) -> Array[Button]:
	var found: Array[Button] = []
	for node in lens.find_children("*", "Button", true, false):
		if (node as Button).has_meta("action_id"):
			found.append(node)
	return found


func _labels_text(node: Node) -> String:
	var parts: Array[String] = []
	for label in node.find_children("*", "Label", true, false):
		parts.append((label as Label).text)
	return "\n".join(parts)


## Every visible control must end inside [param width] (phones never scroll sideways).
func _assert_fits(lens: LensPanel, width: float, context: String) -> void:
	var overflowing: Array[String] = []
	for node in lens.find_children("*", "Control", true, false):
		var control := node as Control
		if control.is_visible_in_tree() and control.get_global_rect().end.x > width + 0.5:
			overflowing.append("%s (%s) ends at %.0f" % [control.name, control.get_class(), control.get_global_rect().end.x])
	assert_eq(overflowing.size(), 0, "%s fits %.0f px: %s" % [context, width, ", ".join(overflowing.slice(0, 5))])


func test_create_returns_the_lens_of_each_role() -> void:
	for role in SimConstants.FACTION_ORDER:
		var lens := LensPanel.create(role)
		assert_not_null(lens, role)
		match role:
			SimConstants.CEO:
				assert_true(lens is CeoLens, "CEO trading terminal")
			SimConstants.GOVERNANCE:
				assert_true(lens is GovLens, "Governance briefing")
			SimConstants.ASI:
				assert_true(lens is AsiLens, "ASI perception")
			SimConstants.CITIZEN:
				assert_true(lens is CitizenLens, "Citizen commons")
		assert_eq(lens.role, role)
		assert_eq(lens.lens_title(), TITLES[role])
		assert_true(Glyphs.has_glyph(lens.lens_glyph()), "tab glyph for " + role)
		lens.free()


func test_each_lens_renders_a_real_campaign() -> void:
	for role in SimConstants.FACTION_ORDER:
		var run := _play(role, 6)
		var engine: SimulationEngine = run["engine"]
		var lens := _mount(role, false)
		_feed(lens, run)
		await wait_frames(2)
		assert_eq(int(lens.snapshot["turn"]), engine.turn, role + " snapshot")
		assert_eq(lens.history.size(), (run["snapshots"] as Array).size() + 1, role + " one sample per update")
		assert_eq(lens.events.size(), mini((run["events"] as Array).size(), LensPanel.EVENT_LIMIT), role + " events kept")
		var text := _labels_text(lens)
		match role:
			SimConstants.CEO:
				var capital := float(engine.get_player().resources["capital"])
				assert_eq(lens._capital_label.text, UiFormat.format_resource(role, "capital", capital), "capital runway")
				assert_string_contains(text, "T%d · " % engine.turn, "turn in the header")
				assert_eq(lens._tiles.size(), 6, "six priced tiles")
			SimConstants.GOVERNANCE:
				assert_string_contains(text, "CYCLE %d" % engine.turn, "brief dated by cycle")
				assert_string_contains(text, "%.1f" % float(engine.get_player().resources["public_mandate"]), "readiness")
				assert_eq(lens._threat_cells.size(), 6, "six threats")
				assert_ne(lens._item_bodies[0].get_parsed_text(), "", "first brief item")
			SimConstants.ASI:
				var drift := engine.world.alignment_drift / 100.0
				assert_eq(lens._variable_values[0].text, "%.2f" % drift, "drift as operator intent divergence")
				assert_eq(lens._policy_box.get_child_count(), AsiFaction.ACTIONS.size(), "every directive in the policy")
				assert_gt(lens._token_flow.get_child_count(), 0, "token stream")
			SimConstants.CITIZEN:
				assert_not_null(lens.find_child("OfficialPost", true, false), "official post")
				assert_string_contains(text, "Turn %d" % engine.turn, "treasury dated")
		lens.queue_free()
	await wait_frames(1)


func test_history_keeps_one_sample_per_update() -> void:
	var run := _play(SimConstants.CEO, 3)
	var engine: SimulationEngine = run["engine"]
	var lens := _mount(SimConstants.CEO, false)
	var snapshots: Array = run["snapshots"]
	for i in snapshots.size():
		var snapshot: Dictionary = snapshots[i]
		lens.update_state(snapshot, snapshot["factions"]["CEO"]["resources"])
		assert_eq(lens.history.size(), i + 1, "sample %d" % i)
	lens.update_state(engine.get_snapshot(), engine.get_player().resources)
	lens.update_state(engine.get_snapshot(), engine.get_player().resources)
	assert_eq(lens.history.size(), snapshots.size() + 2, "repeated updates still add samples")
	var before: Dictionary = (snapshots.back() as Dictionary)["factions"]["CEO"]["resources"]
	var expected := float(engine.get_player().resources["capital"]) - float(before["capital"])
	assert_almost_eq(lens.resource_delta("capital"), expected, 0.001, "change since the previous turn")
	assert_eq(lens.resource_series("capital").size(), lens.history.size(), "one chart point per sample")
	for _i in LensPanel.HISTORY_LIMIT + 5:
		lens.update_state(engine.get_snapshot(), engine.get_player().resources)
	assert_eq(lens.history.size(), LensPanel.HISTORY_LIMIT, "history stays short")


func test_directive_buttons_ask_for_valid_directives() -> void:
	for role in SimConstants.FACTION_ORDER:
		var run := _play(role, 8)
		var lens := _mount(role, true)
		_feed(lens, run)
		await wait_frames(1)
		var requested: Array[String] = []
		lens.directive_requested.connect(func(action_id: String) -> void: requested.append(action_id))
		var buttons := _directive_buttons(lens)
		assert_gt(buttons.size(), 0, role + " has directive buttons")
		var pressed := 0
		for button in buttons:
			if not button.disabled:
				button.pressed.emit()
				pressed += 1
		assert_gt(pressed, 0, role + " has an available directive")
		assert_eq(requested.size(), pressed, role + " each press asks once")
		var catalog := FactionRegistry.catalog_for(role)
		var context := _context(run["engine"])
		for action_id in requested:
			assert_has(catalog, action_id, role + " requests its own directive")
			for entry in context["actions"]:
				if entry["id"] == action_id:
					assert_eq(String(entry["blocked_reason"]), "", "%s %s is available" % [role, action_id])
		lens.queue_free()
	await wait_frames(1)


func test_asi_commits_the_selected_policy() -> void:
	var run := _play(SimConstants.ASI, 8)
	var lens := _mount(SimConstants.ASI, false) as AsiLens
	_feed(lens, run)
	await wait_frames(1)
	var commit := lens.find_child("CommitButton", true, false) as Button
	assert_eq(String(commit.get_meta("action_id")), lens.suggested_action(), "suggested directive selected first")
	var alternative := ""
	for entry in lens.action_entries():
		if String(entry["blocked_reason"]) == "" and String(entry["id"]) != lens.suggested_action():
			alternative = String(entry["id"])
	assert_ne(alternative, "", "another directive is available")
	for row in lens._policy_box.get_children():
		if String(row.get_meta("policy_id", "")) == alternative:
			(row as Button).pressed.emit()
	await wait_frames(2)
	var requested: Array[String] = []
	lens.directive_requested.connect(func(action_id: String) -> void: requested.append(action_id))
	commit.pressed.emit()
	assert_eq(requested, [alternative] as Array[String], "commit sends the selected policy")


func test_citizen_lens_shows_the_coalitions_latest_statement() -> void:
	var run := _play(SimConstants.CITIZEN, 5)
	var engine: SimulationEngine = run["engine"]
	var lens := _mount(SimConstants.CITIZEN, true)
	_feed(lens, run)
	await wait_frames(1)
	var statement := lens.find_child("Statement", true, false) as Label
	assert_not_null(statement, "official post statement")
	assert_eq(statement.text, engine.get_player().last_statement, "last turn's statement while the player decides")
	# Resolve this turn with an available directive: the post follows the new statement.
	var directive := LensPanel.CONSERVE
	for entry in engine.get_player_context()["actions"]:
		if String(entry["blocked_reason"]) == "" and String(entry["id"]) != LensPanel.CONSERVE:
			directive = String(entry["id"])
	var response := engine.submit_player_turn([{"action": directive, "intensity": 1.0}], DilemmaDeck.DEFER_ID)
	assert_true(response["ok"], "turn submitted: %s" % str(response.get("errors", [])))
	lens.update_state(engine.get_snapshot(), engine.get_player().resources)
	await wait_frames(1)
	statement = lens.find_child("Statement", true, false) as Label
	var outcome: Dictionary = engine.turn_actions[SimConstants.CITIZEN]
	assert_eq(statement.text, String(outcome["public_statement"]), "this turn's statement")
	assert_string_contains(_labels_text(lens.find_child("OfficialPost", true, false)), String(outcome["action_name"]), "names the directive")


func test_lenses_fit_a_phone() -> void:
	for role in SimConstants.FACTION_ORDER:
		var run := _play(role, 12)
		for width in [PHONE.x, 360.0]:
			host.size = Vector2(width, PHONE.y)
			var lens := _mount(role, true)
			_feed(lens, run)
			await wait_frames(3)
			_assert_fits(lens, width, "%s lens" % role)
			if lens is CitizenLens:
				for tab in CitizenLens.TABS:
					(lens as CitizenLens).show_feed_tab(tab)
					await wait_frames(2)
					_assert_fits(lens, width, "Commons %s" % tab)
				(lens as CitizenLens).set_dark(true)
				await wait_frames(2)
				_assert_fits(lens, width, "Commons dark")
			lens.queue_free()
			await wait_frames(1)
	host.size = PHONE


func test_touch_targets_are_finger_sized() -> void:
	for role in SimConstants.FACTION_ORDER:
		var run := _play(role, 4)
		var lens := _mount(role, true)
		_feed(lens, run)
		await wait_frames(2)
		for node in lens.find_children("*", "Button", true, false):
			var button := node as Button
			if button.is_visible_in_tree():
				assert_gte(button.size.y, LensPanel.TOUCH, "%s %s is %.0f px tall" % [role, button.name, button.size.y])
		lens.queue_free()
	await wait_frames(1)


func test_briefing_redacts_labs_and_escapes_markup() -> void:
	var run := _play(SimConstants.GOVERNANCE, 3)
	var engine: SimulationEngine = run["engine"]
	var lens := _mount(SimConstants.GOVERNANCE, false) as GovLens
	_feed(lens, run)
	lens.record_event({"turn": engine.turn, "year": engine.get_year(), "category": "EMERGENCE", "severity": "CRITICAL", "faction": "",
		"text": "", "capability": "X", "name": "[url=x]Payload[/url]", "headline": "Frontier Model-12 [color=red]breaks out[/color]",
		"model": "Frontier Model-12", "deltas": {}})
	lens.update_state(engine.get_snapshot(), engine.get_player().resources)
	var body := lens._item_bodies[0]
	assert_string_contains(lens._item_titles[0].text, "EMERGENT CAPABILITY", "the emergence leads the brief")
	assert_string_contains(body.get_parsed_text(), "[color=red]breaks out[/color]", "markup shown literally")
	assert_string_contains(body.get_parsed_text(), "[url=x]Payload[/url]", "names escaped")
	assert_string_contains(body.text, "[bgcolor=", "model name blacked out")


func test_lens_frame_follows_the_era() -> void:
	var lens := _mount(SimConstants.CEO, false) as CeoLens
	await wait_frames(1)
	assert_eq(lens.era_style.era, 1)
	for era in [2, 3]:
		host.theme = EraTheme.get_theme(era)
		await wait_frames(1)
		assert_eq(lens.era_style.era, era, "era %d style" % era)
		assert_eq(lens._accent, EraStyle.for_era(era).faction_color(SimConstants.CEO), "accent follows the era")
	host.theme = EraTheme.get_theme(1)


func test_lenses_survive_without_data() -> void:
	for role in SimConstants.FACTION_ORDER:
		var lens := _mount(role, true)
		await wait_frames(2)
		assert_true(lens.history.is_empty(), role + " starts empty")
		assert_ne(lens.suggested_action(), "", role + " still proposes a directive")
		lens.reset()
		lens.queue_free()
	await wait_frames(1)
