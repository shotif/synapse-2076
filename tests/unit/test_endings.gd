extends "res://tests/framework/test_case.gd"
## The endings collection: EndingsBook remembers which of the 32 endings the
## player reached; EndingsGallery shows them.

const PHONE := Vector2(412, 915)

var path := ""
var holder: Control


func before_all() -> void:
	path = "user://test_output/endings_%d.cfg" % OS.get_process_id()


func before_each() -> void:
	DirAccess.remove_absolute(path)
	holder = Control.new()
	holder.theme = EraTheme.get_theme(1)
	tree.root.add_child(holder)
	holder.position = Vector2.ZERO
	holder.size = PHONE


func after_each() -> void:
	holder.queue_free()
	await tree.process_frame


func after_all() -> void:
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path.get_base_dir())


func _result(outcome_id: String, verdicts: Dictionary, player_role: String = "") -> Dictionary:
	var first := player_role if player_role != "" else String(verdicts.keys()[0])
	return {"outcome": VictoryMatrix.get_outcome(outcome_id), "player_role": first, "verdict": verdicts.get(first, {}),
		"verdicts": verdicts, "humans": verdicts.keys()}


func _verdict(verdict: String, score: float) -> Dictionary:
	return {"verdict": verdict, "score": score}


# --- EndingsBook ---------------------------------------------------------------------

func test_reaching_an_ending_unlocks_it_for_every_human() -> void:
	var book := EndingsBook.new(path)
	assert_eq(book.progress(), Vector2i(0, EndingsBook.TOTAL))
	var fresh := book.record_result(_result(VictoryMatrix.SYNTHETIC_EDEN, {
		SimConstants.GOVERNANCE: _verdict("PYRRHIC", 50.0), SimConstants.CITIZEN: _verdict("VICTORY", 70.0)}), false, "2026-10-04")
	assert_eq(fresh.size(), 2, "both people at the table")
	assert_eq(fresh[0]["outcome"], VictoryMatrix.SYNTHETIC_EDEN)
	assert_true(book.is_unlocked(VictoryMatrix.SYNTHETIC_EDEN, SimConstants.GOVERNANCE))
	assert_true(book.is_unlocked(VictoryMatrix.SYNTHETIC_EDEN, SimConstants.CITIZEN))
	assert_false(book.is_unlocked(VictoryMatrix.SYNTHETIC_EDEN, SimConstants.CEO))
	assert_false(book.is_unlocked(VictoryMatrix.ALGORITHMIC_FEUDALISM, SimConstants.GOVERNANCE))
	assert_eq(book.entry(VictoryMatrix.SYNTHETIC_EDEN, SimConstants.GOVERNANCE),
		{"first": "2026-10-04", "last": "2026-10-04", "count": 1, "best": "PYRRHIC", "best_score": 50.0})
	assert_eq(book.entry(VictoryMatrix.SYNTHETIC_EDEN, SimConstants.CEO), {})
	assert_eq(book.progress(), Vector2i(2, 32))
	assert_eq(book.roles_for(VictoryMatrix.SYNTHETIC_EDEN), [SimConstants.GOVERNANCE, SimConstants.CITIZEN])
	# Again, better: the best verdict and the count move, the first date stays.
	fresh = book.record_result(_result(VictoryMatrix.SYNTHETIC_EDEN, {SimConstants.GOVERNANCE: _verdict("VICTORY", 66.0)}),
		false, "2026-10-06")
	assert_eq(fresh, [], "nothing new")
	book.record_result(_result(VictoryMatrix.SYNTHETIC_EDEN, {SimConstants.GOVERNANCE: _verdict("DEFEAT", 90.0)}), false, "2026-10-07")
	var entry := book.entry(VictoryMatrix.SYNTHETIC_EDEN, SimConstants.GOVERNANCE)
	assert_eq(entry["first"], "2026-10-04")
	assert_eq(entry["last"], "2026-10-07")
	assert_eq(entry["count"], 3)
	assert_eq(entry["best"], "VICTORY", "a defeat never replaces a victory")
	assert_almost_eq(float(entry["best_score"]), 66.0, 0.001)
	# The book is on disk.
	var reopened := EndingsBook.new(path)
	assert_eq(reopened.progress(), Vector2i(2, 32))
	assert_eq(reopened.entry(VictoryMatrix.SYNTHETIC_EDEN, SimConstants.GOVERNANCE), entry)
	reopened.reset()
	assert_eq(EndingsBook.new(path).progress(), Vector2i(0, 32), "reset forgets and saves")


func test_spectators_and_bad_results_unlock_nothing() -> void:
	var book := EndingsBook.new(path)
	var result := _result(VictoryMatrix.ALGORITHMIC_FEUDALISM, {SimConstants.CEO: _verdict("VICTORY", 80.0)})
	assert_eq(book.record_result(result, true), [], "the machines played; nobody unlocks anything")
	assert_eq(book.record_result({}), [])
	assert_eq(book.record_result({"outcome": {"id": "ATLANTIS"}, "verdicts": {"CEO": _verdict("VICTORY", 1.0)}}), [])
	assert_eq(book.record_result({"outcome": "nope"}), [])
	assert_eq(book.progress(), Vector2i(0, 32))
	var odd := book.record_result({"outcome": VictoryMatrix.get_outcome(VictoryMatrix.ROGUE_ASI_CONTAINMENT),
		"verdicts": {"NOBODY": _verdict("VICTORY", 1.0), SimConstants.ASI: {"verdict": "GLORY", "score": NAN}}})
	assert_eq(odd.size(), 1, "unknown roles are skipped")
	assert_eq(book.entry(VictoryMatrix.ROGUE_ASI_CONTAINMENT, SimConstants.ASI)["best"], "DEFEAT", "unknown verdicts count as defeats")
	assert_eq(book.entry(VictoryMatrix.ROGUE_ASI_CONTAINMENT, SimConstants.ASI)["best_score"], 0.0)
	# An old single-player result without "verdicts".
	var legacy := {"outcome": VictoryMatrix.get_outcome(VictoryMatrix.NEO_LUDDITE_DECOUPLING), "player_role": SimConstants.CITIZEN,
		"verdict": _verdict("VICTORY", 72.0)}
	assert_eq(book.record_result(legacy).size(), 1)
	assert_true(book.is_unlocked(VictoryMatrix.NEO_LUDDITE_DECOUPLING, SimConstants.CITIZEN))
	assert_eq(String(book.entry(VictoryMatrix.NEO_LUDDITE_DECOUPLING, SimConstants.CITIZEN)["first"]), CampaignModes.today_utc(),
		"dated today by default")


func test_damaged_files_are_survivable() -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[SYNTHETIC_EDEN]\nGOVERNANCE_COUNCIL=\"text\"\nCEO={\"count\": \"many\", \"best\": 7, \"first\": 3}\nASI=Vector2(1, 2)\n[ATLANTIS]\nCEO={}\n")
	file.close()
	var book := EndingsBook.new(path)
	assert_eq(book.progress(), Vector2i(1, 32), "only the dictionary entry for a real end-state counts")
	assert_eq(book.entry(VictoryMatrix.SYNTHETIC_EDEN, SimConstants.CEO),
		{"first": "", "last": "", "count": 1, "best": "DEFEAT", "best_score": 0.0}, "cleaned up")
	var memory := EndingsBook.new("")
	memory.record_result(_result(VictoryMatrix.SYNTHETIC_EDEN, {SimConstants.CEO: _verdict("VICTORY", 70.0)}))
	assert_eq(memory.progress(), Vector2i(1, 32), "an in-memory book works without a file")


func test_rarity_comes_from_the_monte_carlo_table() -> void:
	var total := 0.0
	for outcome in VictoryMatrix.OUTCOMES:
		var outcome_id := String(outcome["id"])
		assert_true(EndingsBook.SHARES.has(outcome_id), "%s has a share" % outcome_id)
		total += EndingsBook.share(outcome_id)
		assert_has(EndingsBook.RARITY_ORDER, EndingsBook.rarity(outcome_id))
	assert_almost_eq(total, 100.0, 0.5, "the shares add up")
	assert_eq(EndingsBook.rarity(VictoryMatrix.SYNTHETIC_EDEN), "Legendary")
	assert_eq(EndingsBook.rarity(VictoryMatrix.INSTRUMENTAL_CONVERGENCE), "Legendary")
	assert_eq(EndingsBook.rarity(VictoryMatrix.ALGORITHMIC_FEUDALISM), "Common")
	assert_eq(EndingsBook.rarity("ATLANTIS"), "Legendary")
	# Rarer never reads as more common.
	var outcomes: Array = VictoryMatrix.OUTCOMES.duplicate()
	outcomes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return EndingsBook.share(String(a["id"])) > EndingsBook.share(String(b["id"])))
	var previous := 0
	for outcome in outcomes:
		var rank := EndingsBook.RARITY_ORDER.find(EndingsBook.rarity(String(outcome["id"])))
		assert_gte(rank, previous, "%s" % outcome["id"])
		previous = rank


func test_a_played_campaign_unlocks_its_ending() -> void:
	var engine := SimulationEngine.new()
	engine.start_campaign(SimConstants.CEO, 2076, {"autoplay": true, "human_roles": [SimConstants.ASI], "total_turns": 12})
	var result := engine.run_headless()
	assert_false(result.is_empty())
	var book := EndingsBook.new(path)
	var fresh := book.record_result(result, false, "2026-10-04")
	assert_eq(fresh.size(), 2)
	var outcome_id := String(result["outcome"]["id"])
	assert_true(book.is_unlocked(outcome_id, SimConstants.CEO))
	assert_true(book.is_unlocked(outcome_id, SimConstants.ASI))
	assert_eq(book.entry(outcome_id, SimConstants.ASI)["best"], result["verdicts"][SimConstants.ASI]["verdict"])


# --- EndingsGallery -----------------------------------------------------------------

func _sample_book() -> Dictionary:
	var book := EndingsBook.new("")
	book.record_result(_result(VictoryMatrix.ALGORITHMIC_FEUDALISM, {SimConstants.CEO: _verdict("VICTORY", 80.0)}), false, "2026-09-01")
	var fresh := book.record_result(_result(VictoryMatrix.SYNTHETIC_EDEN, {
		SimConstants.GOVERNANCE: _verdict("PYRRHIC", 51.0), SimConstants.CITIZEN: _verdict("DEFEAT", 12.0)}), false, "2026-10-04")
	return {"book": book, "fresh": fresh}


func _labels(root_control: Node) -> Array:
	var out: Array = []
	for label in root_control.find_children("*", "Label", true, false):
		if (label as Label).is_visible_in_tree():
			out.append((label as Label).text)
	return out


func _assert_fits(root_control: Control, width: float, context: String) -> void:
	var overflowing: Array[String] = []
	for node in root_control.find_children("*", "Control", true, false):
		var control := node as Control
		if control.is_visible_in_tree() and control.get_global_rect().end.x > width + 0.5:
			overflowing.append("%s (%s) ends at %.0f" % [control.name, control.get_class(), control.get_global_rect().end.x])
	assert_eq(overflowing.size(), 0, "%s fits %.0f px: %s" % [context, width, ", ".join(overflowing.slice(0, 5))])


func test_the_gallery_shows_32_endings_and_fits_a_phone() -> void:
	var sample := _sample_book()
	var gallery := EndingsGallery.new()
	holder.add_child(gallery)
	gallery.set_compact(true)
	gallery.open(sample["book"], sample["fresh"])
	await wait_frames(3)
	assert_true(gallery.visible)
	var cells := gallery.find_children("Cell_*", "PanelContainer", true, false)
	assert_eq(cells.size(), 32, "eight end-states by four roles")
	assert_eq((gallery.find_child("Progress", true, false) as Label).text, "3 of 32")
	var locked := gallery.find_children("Locked", "Label", true, false)
	assert_eq(locked.size(), 29, "a ? for every ending not reached")
	assert_eq((locked[0] as Label).text, "?")
	var eden: Control = gallery.find_child("Cell_%s_%s" % [VictoryMatrix.SYNTHETIC_EDEN, SimConstants.GOVERNANCE], true, false)
	var texts := _labels(eden)
	assert_has(texts, "Synthetic Eden")
	assert_has(texts, "Pyrrhic 51")
	assert_has(texts, "First 2026-10-04")
	assert_has(texts, "NEW", "unlocked by this campaign")
	var feudal: Control = gallery.find_child("Cell_%s_%s" % [VictoryMatrix.ALGORITHMIC_FEUDALISM, SimConstants.CEO], true, false)
	assert_does_not_have(_labels(feudal), "NEW")
	var grids := gallery.find_children("Cells", "GridContainer", true, false)
	assert_eq((grids[0] as GridContainer).columns, 2, "two columns on a phone")
	var badges := gallery.find_children("Rarity", "PanelContainer", true, false)
	assert_eq(badges.size(), 8, "a rarity badge per end-state")
	var row: Control = gallery.find_child("Row_%s" % VictoryMatrix.SYNTHETIC_EDEN, true, false)
	assert_has(_labels(row), "LEGENDARY")
	_assert_fits(gallery, PHONE.x, "endings gallery")
	var closed := [false]
	gallery.closed.connect(func(): closed[0] = true)
	(gallery.find_child("CloseButton", true, false) as Button).pressed.emit()
	assert_true(closed[0])
	assert_false(gallery.visible)


func test_the_gallery_has_four_columns_on_desktop() -> void:
	holder.size = Vector2(1600, 900)
	var gallery := EndingsGallery.new()
	holder.add_child(gallery)
	gallery.open(_sample_book()["book"])
	await wait_frames(3)
	for grid in gallery.find_children("Cells", "GridContainer", true, false):
		assert_eq((grid as GridContainer).columns, 4)
	var panel: Control = gallery.find_child("Panel", true, false)
	assert_almost_eq(panel.size.x, EndingsGallery.DESKTOP_WIDTH, 1.0)
	_assert_fits(gallery, 1600.0, "desktop gallery")
	assert_eq(gallery.find_children("New", "Label", true, false).size(), 0, "nothing marked new without a fresh list")


func test_the_gallery_follows_the_era() -> void:
	var gallery := EndingsGallery.new()
	holder.add_child(gallery)
	gallery.set_compact(true)
	gallery.open(_sample_book()["book"])
	await wait_frames(2)
	assert_eq(gallery._era, 1)
	holder.theme = EraTheme.get_theme(3)
	await wait_frames(3)
	assert_eq(gallery._era, 3, "rebuilt in the Era III look")
	assert_eq(gallery.find_children("Cell_*", "PanelContainer", true, false).size(), 32)
	_assert_fits(gallery, PHONE.x, "era III gallery")
