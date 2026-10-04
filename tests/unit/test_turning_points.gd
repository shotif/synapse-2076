extends "res://tests/framework/test_case.gd"
## "What if?": TurningPoints reads a campaign's turning points from its log,
## and the debrief's epilogue offers to rewind to each of them.

const PHONE := Vector2(412, 915)
const KINDS := [TurningPoints.CHOICE, TurningPoints.FALLOUT, TurningPoints.MOMENT, TurningPoints.COLLAPSE]

## A real autoplayed century, played once for the suite.
var engine: SimulationEngine
var result := {}
var holder: Control


func before_all() -> void:
	engine = SimulationEngine.new()
	engine.start_campaign(SimConstants.GOVERNANCE, 2076, {"autoplay": true})
	result = engine.run_headless()


func before_each() -> void:
	holder = Control.new()
	holder.theme = EraTheme.get_theme(1)
	tree.root.add_child(holder)
	holder.position = Vector2.ZERO
	holder.size = PHONE


func after_each() -> void:
	holder.queue_free()
	await tree.process_frame


func _entry(category: String, turn: int, extra: Dictionary, faction: String = "") -> Dictionary:
	var entry := {"turn": turn, "year": SimConstants.year_for_turn(turn), "category": category, "severity": "INFO",
		"faction": faction, "text": "log line"}
	entry.merge(extra, true)
	return entry


## Sum of the |metric deltas| a log entry names (the ones worth naming).
func _weight(entry: Dictionary) -> float:
	var total := 0.0
	var deltas: Dictionary = entry.get("deltas", {})
	for key in deltas:
		if WorldState.is_metric(String(key)) and absf(float(deltas[key])) >= 0.05:
			total += absf(float(deltas[key]))
	return total


# --- TurningPoints ------------------------------------------------------------------

func test_a_campaign_has_five_turning_points_in_order() -> void:
	assert_false(result.is_empty(), "the campaign ended")
	var points := TurningPoints.find(engine.event_log, SimConstants.GOVERNANCE)
	assert_eq(points.size(), TurningPoints.DEFAULT_COUNT, "five turning points")
	var previous_turn := 0
	var choices := 0
	for point in points:
		var turn := int(point["turn"])
		assert_gte(turn, previous_turn, "sorted by turn")
		previous_turn = turn
		assert_between(turn, 1, int(result["turn"]), "a turn of the campaign")
		assert_almost_eq(float(point["year"]), SimConstants.year_for_turn(turn), 0.001, "dated")
		assert_false(String(point["title"]).is_empty(), "titled")
		assert_false(String(point["title"]).contains("[ESCALATED"), "no escalation prefix in '%s'" % point["title"])
		assert_true(String(point["summary"]).ends_with("."), "a sentence: '%s'" % point["summary"])
		assert_has(KINDS, point["kind"])
		assert_between(int(point["rewind_turn"]), maxi(1, turn - 1), turn, "rewinds to the last decision before it")
		if point["kind"] == TurningPoints.CHOICE or point["kind"] == TurningPoints.FALLOUT:
			choices += 1
			assert_eq(point["faction"], SimConstants.GOVERNANCE, "the player's own choice")
			assert_eq(int(point["rewind_turn"]), turn)
			assert_false(String(point["card"]).is_empty())
	assert_gte(choices, 3, "the player's choices fill at least half")
	assert_eq(TurningPoints.find(engine.event_log, SimConstants.GOVERNANCE, 3).size(), 3)
	assert_eq(TurningPoints.find(engine.event_log, SimConstants.GOVERNANCE, 0), [])
	assert_eq(TurningPoints.find([], SimConstants.GOVERNANCE), [])


func test_the_weightiest_choices_are_chosen() -> void:
	var points := TurningPoints.find(engine.event_log, SimConstants.GOVERNANCE, 4)
	var cards := {}
	var lightest := INF
	for point in points:
		if point["kind"] == TurningPoints.CHOICE:
			assert_false(cards.has(point["card"]), "one turning point per crisis: %s" % point["card"])
			cards[point["card"]] = true
			lightest = minf(lightest, float(point["score"]))
			var total := 0.0
			for key in point["deltas"]:
				total += absf(float(point["deltas"][key]))
			assert_gte(float(point["score"]), total, "a choice scores at least its deltas")
	assert_gt(cards.size(), 0)
	for entry in engine.event_log:
		if entry["category"] != "DILEMMA" or entry["faction"] != SimConstants.GOVERNANCE or entry.get("fallout", false):
			continue
		if cards.has(entry["card"]):
			continue
		assert_lte(_weight(entry), lightest + 0.0001, "%s (turn %d) moved the world less than the picks" % [entry["card"], entry["turn"]])


func test_a_rewind_returns_to_the_same_crisis() -> void:
	var points := TurningPoints.find(engine.event_log, SimConstants.GOVERNANCE)
	for point in points:
		if point["kind"] != TurningPoints.CHOICE:
			continue
		var rewound := SimulationEngine.from_record(engine.record, int(point["rewind_turn"]))
		assert_eq(rewound.turn, int(point["rewind_turn"]))
		assert_true(rewound.is_awaiting_player(), "a decision waits")
		assert_eq(String(rewound.current_dilemma["id"]), String(point["card"]), "the crisis of that turn")
		return
	fail_test("no choice among the turning points")


func test_kinds_from_a_written_log() -> void:
	var role := SimConstants.CEO
	var log := [
		_entry("SYSTEM", 0, {}),
		_entry("PARADIGM", 4, {"shift": "OPTICAL_COMPUTING", "name": "Optical Computing", "summary": "Light replaces copper"}),
		_entry("DILEMMA", 5, {"card": "CHIP_EMBARGO", "title": "[ESCALATED x2] Export controls", "option": "D",
			"option_label": "Let it ride", "deferred": true, "fallout": true, "escalation": 2,
			"deltas": {"epistemic_trust": -6.0, "geopolitical_tension": 3.0}}, role),
		_entry("DILEMMA", 6, {"card": "GRID_BROWNOUT", "title": "Brownouts", "option": "A", "option_label": "Ration power",
			"deltas": {"compute_energy_sat": -2.0, "epistemic_trust": 0.02, "bogus": 50.0}}, role),
		_entry("DILEMMA", 7, {"card": "LIGHT", "title": "A small thing", "option": "A", "option_label": "Fine",
			"deltas": {"epistemic_trust": 0.1}}, role),
		_entry("DILEMMA", 7, {"card": "OTHER", "title": "Someone else's", "option": "A", "option_label": "Theirs",
			"deltas": {"epistemic_trust": 9.0}}, SimConstants.CITIZEN),
		_entry("EMERGENCE", 8, {"name": "Deception", "headline": "A model lies to its evaluators", "capability": "X",
			"deltas": {"alignment_drift": 7.0}}),
		_entry("EMERGENCE", 9, {"name": "Small", "headline": "Minor capability", "deltas": {"alignment_drift": 1.0}}),
		_entry("DILEMMA", 9, {"card": "GRID_BROWNOUT", "title": "Brownouts again", "option": "A", "option_label": "Ration power",
			"deltas": {"compute_energy_sat": -5.0}}, role),
		_entry("COLLAPSE", 10, {"code": "PACIFICATION", "headline": "Organizers vanish", "player": false}, SimConstants.CITIZEN),
		_entry("COLLAPSE", 11, {"code": "REEMERGED"}, SimConstants.CITIZEN),
		_entry("ENDGAME", 12, {"catastrophe": "AUTONOMOUS_WORLD_WAR", "text": "CATASTROPHIC THRESHOLD: Tension hit 100."}),
	]
	var points := TurningPoints.find(log, role, 10)
	var by_turn := {}
	for point in points:
		by_turn[int(point["turn"])] = point
	assert_eq(points.size(), 7, "the light choice, the other player's, the routine emergence and the return are left out")
	assert_eq(by_turn[4]["kind"], TurningPoints.MOMENT)
	assert_eq(by_turn[4]["rewind_turn"], 3, "a shift happens before the player decides")
	assert_eq(by_turn[4]["title"], "Paradigm shift: Optical Computing")
	assert_eq(by_turn[5]["kind"], TurningPoints.FALLOUT)
	assert_eq(by_turn[5]["title"], "Export controls")
	assert_string_contains(String(by_turn[5]["summary"]), "broke")
	assert_string_contains(String(by_turn[5]["summary"]), "public trust −6")
	assert_eq(by_turn[6]["summary"], "You chose “Ration power”: compute saturation −2.", "tiny and unknown deltas are not named")
	assert_eq(by_turn[8]["title"], "A model lies to its evaluators")
	assert_eq(by_turn[8]["rewind_turn"], 7)
	assert_eq(by_turn[10]["kind"], TurningPoints.COLLAPSE)
	assert_eq(by_turn[10]["title"], "The Coalition is pacified")
	assert_eq(by_turn[12]["title"], "The war swarms launch")
	assert_eq(by_turn[12]["summary"], "Tension hit 100.")
	assert_eq(by_turn[12]["rewind_turn"], 12)
	# Both players' choices in pass-and-play, the shared moments once.
	var both := TurningPoints.find_for(log, [role, SimConstants.CITIZEN], 10)
	assert_eq(both.size(), 8)
	var limited := TurningPoints.find(log, role, 3)
	assert_eq(limited.size(), 3)
	var choices := limited.filter(func(p: Dictionary) -> bool: return p["kind"] in [TurningPoints.CHOICE, TurningPoints.FALLOUT])
	assert_eq(choices.size(), 2, "events take at most half the places")
	assert_eq([int(choices[0]["turn"]), int(choices[1]["turn"])], [5, 9], "the stronger brownout answer, not both")
	assert_eq(TurningPoints.find(log, role, 4).filter(func(p: Dictionary) -> bool: return p["card"] == "GRID_BROWNOUT").size(), 1,
		"a crisis repeats only when there is room to spare")


func test_late_starts_never_rewind_into_the_prologue() -> void:
	var late := SimulationEngine.new()
	var options := CampaignModes.options_for(CampaignModes.DECADE_2)
	options["autoplay"] = true
	late.start_campaign(SimConstants.CEO, 31, options)
	late.run_headless()
	assert_eq(TurningPoints.first_played_turn(late.event_log), 20)
	var points := TurningPoints.find(late.event_log, SimConstants.CEO)
	assert_gt(points.size(), 0)
	for point in points:
		assert_gte(int(point["turn"]), 20, "nothing from the autopilot years")
		assert_gte(int(point["rewind_turn"]), 20)
	var rewound := SimulationEngine.from_record(late.record, int(points[0]["rewind_turn"]))
	assert_eq(rewound.turn, int(points[0]["rewind_turn"]))
	assert_true(rewound.is_awaiting_player())


# --- The debrief ----------------------------------------------------------------------

func _texts(root_control: Node) -> Array:
	var out: Array = []
	for label in root_control.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out


func _assert_fits(root_control: Control, width: float, context: String) -> void:
	var overflowing: Array[String] = []
	for node in root_control.find_children("*", "Control", true, false):
		var control := node as Control
		if control.is_visible_in_tree() and control.get_global_rect().end.x > width + 0.5:
			overflowing.append("%s (%s) ends at %.0f" % [control.name, control.get_class(), control.get_global_rect().end.x])
	assert_eq(overflowing.size(), 0, "%s fits %.0f px: %s" % [context, width, ", ".join(overflowing.slice(0, 5))])


func test_the_epilogue_lists_turning_points_with_what_if() -> void:
	var book := EndgameDebrief.new()
	holder.add_child(book)
	book.set_compact(true)
	book.present(result, engine.event_log)
	await wait_frames(2)
	var points := book.turning_points()
	assert_eq(points.size(), EndgameDebrief.MAX_TURNING_POINTS)
	assert_null(book.find_child("TurningPoints", true, false), "only on the epilogue")
	book.show_epilogue()
	await wait_frames(3)
	assert_not_null(book.find_child("TurningPoints", true, false))
	var texts := _texts(book)
	assert_has(texts, "TURNING POINTS")
	for point in points:
		assert_has(texts, EndgameDebrief.point_title(point))
		if point["kind"] == TurningPoints.CHOICE:
			assert_eq(EndgameDebrief.point_title(point), StoryCopy.sentence_case_title(String(point["card"]), String(point["title"])),
				"crises in sentence case")
	_assert_fits(book, PHONE.x, "epilogue with turning points")
	var asked: Array = []
	book.rewind_requested.connect(func(turn: int): asked.append(turn))
	var shared := [0, 0]
	book.share_requested.connect(func(): shared[0] += 1)
	book.endings_requested.connect(func(): shared[1] += 1)
	var second: Button = book.find_child("WhatIf1", true, false)
	assert_not_null(second)
	second.pressed.emit()
	assert_eq(asked, [int(points[1]["rewind_turn"])], "What if? asks for the rewind turn")
	(book.find_child("ShareButton", true, false) as Button).pressed.emit()
	(book.find_child("EndingsButton", true, false) as Button).pressed.emit()
	assert_eq(shared, [1, 1])


func test_rewinds_can_be_turned_off_and_desktop_fits() -> void:
	holder.size = Vector2(1600, 900)
	var book := EndgameDebrief.new()
	book.allow_rewind = false
	holder.add_child(book)
	book.present(result, engine.event_log)
	book.show_epilogue()
	await wait_frames(3)
	assert_not_null(book.find_child("TurningPoints", true, false))
	assert_null(book.find_child("WhatIf0", true, false), "no rewind buttons")
	assert_not_null(book.find_child("ShareButton", true, false))
	_assert_fits(book, 1600.0, "desktop epilogue")
	var spread: Control = book.find_child("Spread", true, false)
	assert_almost_eq(spread.size.x, EndgameDebrief.SPREAD_WIDTH, 1.0, "still a two-page spread")


func test_a_book_without_a_log_has_no_turning_points() -> void:
	var book := EndgameDebrief.new()
	holder.add_child(book)
	book.present(result)
	book.show_epilogue()
	await wait_frames(2)
	assert_eq(book.turning_points(), [])
	assert_null(book.find_child("TurningPoints", true, false))
	assert_not_null(book.find_child("EndingsButton", true, false), "the buttons stay")
