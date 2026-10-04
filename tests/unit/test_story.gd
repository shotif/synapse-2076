extends "res://tests/framework/test_case.gd"
## Headlines instead of logs: HeadlineWriter, the Newswire, EraChronicle, the
## era-closing FrontPage and the history-book debrief.

const MAX_TITLE := 80
const PHONE := Vector2(412, 915)
## Longest values the crisis deck can fill a title with.
const LONGEST_FILLS := {
	"region": "Oregon High Desert", "bloc": "Global South Data Alliance", "sector": "insurance underwriting",
	"city": "Sao Paulo", "lab": "Prometheus Dynamics", "model": "Frontier Model-17", "gw": "18", "pct": "38",
	"n": "12", "year": "2076",
}

## Real campaigns, played once for the suite.
var gov_engine: SimulationEngine
var gov_result := {}
var crash_engine: SimulationEngine
var crash_result := {}
var holder: Control


func before_all() -> void:
	# A Council campaign that plays out the century and wins, and a campaign that
	# ends in catastrophe after reaching Era III: the first seeds from 2076 that
	# produce them, so deck and balance changes keep the stories.
	var gov := _find_campaign(SimConstants.GOVERNANCE, func(result: Dictionary) -> bool:
		return result["reason"] == "TURN_LIMIT" and result["verdict"]["verdict"] == "VICTORY")
	gov_engine = gov[0]
	gov_result = gov[1]
	var crash: Array = []
	for role in [SimConstants.CEO, SimConstants.ASI, SimConstants.CITIZEN, SimConstants.GOVERNANCE]:
		crash = _find_campaign(role, func(result: Dictionary) -> bool:
			return result["reason"] == "CATASTROPHE" and int(result["turn"]) >= EraChronicle.era_turns(3).x)
		if crash[1]["reason"] == "CATASTROPHE":
			break
	crash_engine = crash[0]
	crash_result = crash[1]


## [engine, result] for the first seed from 2076 whose autoplayed [param role]
## campaign satisfies [param wanted] and has a footnoted drift jump.
func _find_campaign(role: String, wanted: Callable) -> Array:
	var found: Array = []
	for seed_value in range(2076, 2136):
		var engine := SimulationEngine.new()
		engine.start_campaign(role, seed_value, {"autoplay": true})
		var result := engine.run_headless()
		found = [engine, result]
		if wanted.call(result) and _largest_spike(engine.event_log).get("spike", 0.0) >= 4.0:
			break
	return found


## The emergence with the campaign's largest drift jump: {name, turn, spike}.
func _largest_spike(event_log: Array) -> Dictionary:
	var best := {}
	for entry in event_log:
		if entry["category"] != "EMERGENCE":
			continue
		var spike := float((entry.get("deltas", {}) as Dictionary).get(WorldState.ALIGNMENT_DRIFT, 0.0))
		if best.is_empty() or spike > float(best["spike"]) + 0.000001:
			best = {"name": String(entry.get("name", "")), "turn": int(entry["turn"]), "spike": spike}
	return best


func before_each() -> void:
	holder = Control.new()
	holder.theme = EraTheme.get_theme(1)
	tree.root.add_child(holder)
	holder.position = Vector2.ZERO
	holder.size = PHONE


func after_each() -> void:
	holder.queue_free()
	await tree.process_frame


# --- HeadlineWriter ------------------------------------------------------------------

func _check_title(h: Dictionary, context: String) -> void:
	var title := String(h["title"])
	assert_true(title.length() > 0, "%s: title" % context)
	assert_lte(title.length(), MAX_TITLE, "%s: '%s' is short" % [context, title])
	assert_false(title.contains("{") or title.contains("}"), "%s: no placeholders in '%s'" % [context, title])
	assert_true(title.left(1) == title.left(1).to_upper(), "%s: sentence case '%s'" % [context, title])
	assert_true(Glyphs.has_glyph(String(h["glyph"])), "%s: glyph '%s'" % [context, h["glyph"]])
	assert_true(String(h["kicker"]) != "", "%s: kicker" % context)


func _entry(category: String, extra: Dictionary, faction: String = "", severity: String = "INFO") -> Dictionary:
	var entry := {"turn": 12, "year": 2032.0, "category": category, "severity": severity, "faction": faction, "text": "log line"}
	entry.merge(extra, true)
	return entry


func test_every_directive_has_a_headline() -> void:
	for faction_id in SimConstants.FACTION_ORDER:
		var catalog: Dictionary = FactionRegistry.catalog_for(faction_id)
		for action_id in catalog:
			var definition: Dictionary = catalog[action_id]
			var h := HeadlineWriter.headline(_entry("ACTION", {"action": action_id, "action_name": definition["name"],
				"statement": definition["statement"], "intensity": 1.0, "deltas": {"alignment_drift": 2.0}}, faction_id))
			if action_id == SimulationEngine.CONSERVE:
				assert_false(h["newsworthy"], "%s conserving is not news" % faction_id)
				continue
			assert_true(h["newsworthy"], "%s/%s is news" % [faction_id, action_id])
			assert_false(StoryCopy.action(faction_id, action_id).is_empty(), "%s/%s has copy" % [faction_id, action_id])
			_check_title(h, "%s/%s" % [faction_id, action_id])
			assert_eq(h["deltas"], {"alignment_drift": 2.0}, "deltas carried")


func test_every_crisis_choice_has_a_short_headline() -> void:
	for template in DilemmaDeck.all_cards():
		var card_id := String(template["id"])
		var title := StoryCopy.fill(String(template["title"]), LONGEST_FILLS)
		for role in SimConstants.FACTION_ORDER:
			var option_ids: Array = []
			for option in template["options"]:
				var roles: Array = option.get("roles", [])
				if roles.is_empty() or roles.has(role):
					option_ids.append(String(option["id"]))
			option_ids.append(DilemmaDeck.DEFER_ID)
			for option_id in option_ids:
				assert_false(StoryCopy.card_option(card_id, option_id, role).is_empty(), "%s %s copy for %s" % [card_id, option_id, role])
				for escalation in [0, 2]:
					var h := HeadlineWriter.headline(_entry("DILEMMA", {"card": card_id, "title": title, "option": option_id,
						"option_label": "label", "escalation": escalation, "deferred": option_id == DilemmaDeck.DEFER_ID,
						"card_category": template["category"]}, role), role)
					_check_title(h, "%s %s %s" % [card_id, option_id, role])
					assert_true(h["mine"], "the player's own choice")
					assert_eq(h["unattributed"], role == SimConstants.ASI, "only the machines go unsigned")
					assert_string_contains(String(h["dek"]), StoryCopy.sentence_case_title(card_id, title), "dek names the crisis")


func test_crisis_titles_keep_their_proper_nouns() -> void:
	var title := "Pacific Accord Imposes Export Controls on Sub-2nm Accelerators"
	assert_eq(StoryCopy.title_fills("CHIP_EMBARGO", title), {"bloc": "Pacific Accord"})
	assert_eq(StoryCopy.sentence_case_title("CHIP_EMBARGO", "[ESCALATED x2] " + title),
		"Pacific Accord imposes export controls on sub-2nm accelerators")
	assert_eq(StoryCopy.sentence_case_title("AGENTIC_FINANCE_FLASH", "Autonomous Trading Agents Erase $7T in Minutes"),
		"Autonomous trading agents erase $7T in minutes")
	var h := HeadlineWriter.headline(_entry("DILEMMA", {"card": "FRONTIER_RELEASE_RACE", "option": "B",
		"title": "Atlantic Compact Announces Frontier Model-4 Release Ahead of Safety Evals"}, SimConstants.GOVERNANCE))
	assert_eq(h["title"], "Council calls for a pause as the Atlantic Compact ships early")
	var deferred := HeadlineWriter.headline(_entry("DILEMMA", {"card": "ORBITAL_SOLAR_PROPOSAL", "option": "DEFER", "deferred": true,
		"escalation": 2, "title": "Consortium Proposes Orbital Solar Collectors for Compute"}, SimConstants.GOVERNANCE))
	assert_eq(deferred["title"], "Council tables the orbital solar plan again", "deferrals are news too")
	assert_string_contains(String(deferred["kicker"]), "ESCALATED ×2")


func test_world_events_have_headlines() -> void:
	for shift_id in TechTreeManager.PARADIGM_SHIFTS:
		var shift: Dictionary = TechTreeManager.PARADIGM_SHIFTS[shift_id]
		var h := HeadlineWriter.headline(_entry("PARADIGM", {"shift": shift_id, "name": shift["name"], "summary": shift["summary"]}))
		_check_title(h, shift_id)
		assert_false((h["deltas"] as Dictionary).is_empty(), "%s shows its effects" % shift_id)
	for capability in TechTreeManager.EMERGENT_CAPABILITIES:
		var info: Dictionary = TechTreeManager.EMERGENT_CAPABILITIES[capability]
		var model := "Frontier Model-17"
		var h := HeadlineWriter.headline(_entry("EMERGENCE", {"capability": capability, "name": info["name"], "model": model,
			"headline": String(info["headline"]).replace("{model}", model), "deltas": {"alignment_drift": 4.0}}, "", "CRITICAL"))
		_check_title(h, capability)
		assert_string_contains(String(h["title"]), model.trim_prefix("Frontier "), "%s names the model" % capability)
		assert_eq(h["desk"], SimConstants.ASI, "emergences file under Machines")
	for era in [2, 3]:
		_check_title(HeadlineWriter.headline(_entry("ERA", {"era": era})), "era %d" % era)
	for mover in [SimConstants.CEO, "STATE"]:
		_check_title(HeadlineWriter.headline(_entry("MILESTONE", {"milestone": "AGI", "first_mover": mover,
			"text": "AGI MILESTONE: x (10^30.5 FLOPs)."})), "milestone " + mover)
	for key in WorldState.METRIC_KEYS:
		for band in [0, 1, 2]:
			for value in [5.0, 95.0]:
				_check_title(HeadlineWriter.headline(_entry("THRESHOLD", {"metric": key, "band": band, "value": value})),
					"%s band %d at %d" % [key, band, value])
	for code in StoryCopy.COLLAPSES:
		_check_title(HeadlineWriter.headline(_entry("COLLAPSE", {"code": code}, SimConstants.CEO, "CRITICAL")), code)
	for faction_id in SimConstants.FACTION_ORDER:
		_check_title(HeadlineWriter.headline(_entry("COLLAPSE", {"code": "REEMERGED"}, faction_id)), "reemerged " + faction_id)
		for target in SimConstants.FACTION_ORDER:
			if target != faction_id:
				_check_title(HeadlineWriter.headline(_entry("RETALIATION", {"target": target}, faction_id)), "feud")
	for outcome in VictoryMatrix.OUTCOMES:
		for verdict in ["VICTORY", "PYRRHIC", "DEFEAT"]:
			_check_title(HeadlineWriter.headline(_entry("ENDGAME", {"outcome": outcome["id"], "outcome_name": outcome["name"],
				"outcome_number": outcome["number"], "verdict": verdict, "score": 50.0})), String(outcome["id"]))
	for code in StoryCopy.CATASTROPHES:
		_check_title(HeadlineWriter.headline(_entry("ENDGAME", {"catastrophe": code})), code)
	for card_id in StoryCopy.INJECTIONS:
		var h := HeadlineWriter.headline(_entry("CRISIS", {"injected": card_id}, SimConstants.ASI))
		_check_title(h, card_id)
		assert_true(h["attach"], "incoming crises fold into the story that caused them")


func test_unattributed_machines() -> void:
	var swarm := HeadlineWriter.headline(_entry("ACTION", {"action": "DEPLOY_SUB_AGENT_SWARMS",
		"statement": "[unattributed] Autonomous procurement agents are renegotiating supply contracts worldwide."}, SimConstants.ASI))
	assert_true(swarm["unattributed"])
	assert_eq(swarm["byline"], "No human author")
	assert_eq(swarm["faction"], SimConstants.ASI, "still filed under Machines")
	assert_false(String(swarm["dek"]).contains("[unattributed]"), "tag stripped from the dek")
	var camouflage := HeadlineWriter.headline(_entry("ACTION", {"action": "COGNITIVE_CAMOUFLAGE",
		"statement": "Evaluation suite v12 complete: no anomalous capabilities detected."}, SimConstants.ASI))
	assert_false(camouflage["unattributed"])
	assert_eq(camouflage["byline"], "Emergent ASI")
	var lab := HeadlineWriter.headline(_entry("ACTION", {"action": "SCALE_FRONTIER_CLUSTERS", "statement": "We build."}, SimConstants.CEO))
	assert_false(lab["unattributed"])
	assert_eq(lab["byline"], "Frontier Lab")
	assert_eq(lab["dek"], "“We build.”")


func test_counters_only_where_defined() -> void:
	var drift := HeadlineWriter.headline(_entry("THRESHOLD", {"metric": "alignment_drift", "band": 2, "value": 77.0}))
	assert_eq(drift["counter"], "Lab says its models have never been more aligned")
	var labor := HeadlineWriter.headline(_entry("THRESHOLD", {"metric": "labor_displacement", "band": 2, "value": 81.0}))
	assert_eq(labor["counter"], "Frontier Lab reports record employment")
	var tension := HeadlineWriter.headline(_entry("THRESHOLD", {"metric": "geopolitical_tension", "band": 2, "value": 82.0}))
	assert_eq(tension["counter"], "Ministry calls war-swarm reports a foreign fabrication")
	var swarms := HeadlineWriter.headline(_entry("EMERGENCE", {"capability": "MASS_COORDINATION_SWARMS", "model": "Frontier Model-15",
		"headline": "Frontier Model-15 coordinates ten million sub-agents across global supply chains"}))
	assert_eq(swarms["counter"], "Network reports no unusual agent activity")
	assert_eq(swarms["title"], "Frontier Model-15 coordinates ten million sub-agents", "long engine headline shortened")
	assert_eq(HeadlineWriter.headline(_entry("THRESHOLD", {"metric": "alignment_drift", "band": 1, "value": 55.0}))["counter"], "",
		"warnings are reported straight")
	assert_eq(HeadlineWriter.headline(_entry("ACTION", {"action": "SCALE_FRONTIER_CLUSTERS"}, SimConstants.CEO))["counter"], "")
	assert_eq(HeadlineWriter.headline(_entry("PARADIGM", {"shift": "OPTICAL_COMPUTING"}))["counter"], "")


func test_system_entries_are_not_news() -> void:
	assert_false(HeadlineWriter.headline(_entry("SYSTEM", {"text": "Campaign initialized"}))["newsworthy"])
	assert_false(HeadlineWriter.headline(_entry("SOMETHING_NEW", {}))["newsworthy"])


func test_statements_stay_plain_text() -> void:
	var markup := "[color=red]injected[/color] [url=x]link[/url]"
	var h := HeadlineWriter.headline(_entry("ACTION", {"action": "SCALE_FRONTIER_CLUSTERS", "statement": markup, "source": "LLM"},
		SimConstants.CEO))
	assert_string_contains(String(h["dek"]), markup, "untrusted statement kept verbatim for a Label")
	var bare := HeadlineWriter.headline(_entry("ACTION", {"text": markup}, SimConstants.ASI))
	assert_eq(bare["title"], markup, "a bare log line becomes the headline as is")


func test_real_campaign_headlines_are_short() -> void:
	for engine in [gov_engine, crash_engine]:
		var news := 0
		for entry in (engine as SimulationEngine).event_log:
			var h := HeadlineWriter.headline(entry, (engine as SimulationEngine).player_role)
			if not h["newsworthy"]:
				assert_true(entry["category"] in ["SYSTEM", "ACTION"], "only system lines and conserving drop out")
				continue
			news += 1
			assert_lte(String(h["title"]).length(), MAX_TITLE, "'%s'" % h["title"])
			assert_false(String(h["title"]).contains("{"), "'%s'" % h["title"])
		assert_gt(news, 100, "a campaign makes plenty of news")


# --- Newswire ------------------------------------------------------------------------

func _wire(horizontal: bool, compact: bool) -> Newswire:
	var wire := Newswire.new()
	holder.add_child(wire)
	wire.size = PHONE if not horizontal else Vector2(1580, 170)
	wire.set_compact(compact)
	wire.set_horizontal(horizontal)
	return wire


func _story(turn: int, faction: String, title: String) -> Dictionary:
	return {"turn": turn, "year": SimConstants.year_for_turn(turn), "category": "ACTION", "severity": "INFO",
		"faction": faction, "text": title}


func test_newswire_newest_first_and_capped() -> void:
	var wire := _wire(true, false)
	for i in Newswire.MAX_CARDS + 30:
		wire.add_entry(_story(i, SimConstants.CEO, "Story %d" % i))
	assert_eq(wire.entry_count(), Newswire.MAX_CARDS, "capped")
	var titles := wire.get_headline_titles()
	assert_eq(titles[0], "Story %d" % (Newswire.MAX_CARDS + 29), "newest first")
	assert_eq(titles[-1], "Story 30", "oldest dropped")
	wire.add_entry({"turn": 1, "year": 2026.5, "category": "SYSTEM", "severity": "INFO", "faction": "", "text": "noise"})
	assert_eq(wire.entry_count(), Newswire.MAX_CARDS, "system lines skipped")
	wire.clear()
	assert_eq(wire.entry_count(), 0)


func test_newswire_filters_by_desk() -> void:
	var wire := _wire(false, true)
	var desks := [SimConstants.CEO, SimConstants.GOVERNANCE, SimConstants.CITIZEN, SimConstants.ASI]
	for i in 8:
		wire.add_entry(_story(i, desks[i % 4], "Story %d" % i))
	wire.set_filter(SimConstants.ASI)
	await wait_frames(1)
	var visible := 0
	for card in wire.find_children("*", "PanelContainer", true, false):
		if card.has_meta("headline") and (card as Control).visible:
			visible += 1
			assert_eq((card.get_meta("headline") as Dictionary)["desk"], SimConstants.ASI, "only the Machines desk")
	assert_eq(visible, 2)
	wire.set_filter("")
	visible = 0
	for card in wire.find_children("*", "PanelContainer", true, false):
		if card.has_meta("headline") and (card as Control).visible:
			visible += 1
	assert_eq(visible, 8, "All shows every desk")


func test_newswire_shows_markup_literally() -> void:
	var wire := _wire(false, true)
	var markup := "[color=red]injected[/color] [url=x]link[/url]"
	wire.add_entry(_story(1, SimConstants.ASI, markup))
	wire.add_entry(_entry("ACTION", {"action": "DEPLOY_SUB_AGENT_SWARMS", "statement": "[b]bold[/b] claim"}, SimConstants.ASI))
	await wait_frames(1)
	assert_has(wire.get_headline_titles(), markup)
	var texts: Array = []
	for label in wire.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	assert_has(texts, markup, "the headline Label shows the markup as text")
	assert_has(texts, "“[b]bold[/b] claim”", "the lead's dek shows the statement as text")
	assert_eq(wire.find_children("*", "RichTextLabel", true, false).size(), 0, "no BBCode parsing anywhere")


func test_newswire_folds_incoming_crises_and_prints_counters() -> void:
	var wire := _wire(false, true)
	wire.add_entry(_entry("ACTION", {"action": "DEPLOY_SUB_AGENT_SWARMS",
		"statement": "[unattributed] Agents."}, SimConstants.ASI, "WARN"))
	wire.add_entry(_entry("CRISIS", {"injected": "ROGUE_AGENT_SWARM"}, SimConstants.ASI, "WARN"))
	assert_eq(wire.entry_count(), 1, "the incoming crisis folds into its cause")
	assert_string_contains(String((wire.get_headlines()[0] as Dictionary)["kicker"]), "INCOMING")
	wire.set_public_trust(15.0)
	wire.add_entry(_entry("THRESHOLD", {"metric": "alignment_drift", "band": 2, "value": 80.0}, "", "CRITICAL"))
	assert_eq(wire.get_headline_titles()[0], "Lab says its models have never been more aligned",
		"low trust prints the official story")
	wire.set_public_trust(80.0)
	wire.add_entry(_entry("THRESHOLD", {"metric": "alignment_drift", "band": 2, "value": 80.0}, "", "CRITICAL"))
	assert_eq(wire.get_headline_titles()[0], "Drift goes critical: signs of deceptive alignment")


func test_newswire_fits_a_phone_and_fills_the_strip() -> void:
	var wire := _wire(false, true)
	for entry in gov_engine.event_log.slice(0, 120):
		wire.add_entry(entry)
	await wait_frames(3)
	_assert_fits(wire, PHONE.x, "phone wire")
	var strip := _wire(true, false)
	strip.position = Vector2(0, 0)
	for entry in gov_engine.event_log.slice(0, 40):
		strip.add_entry(entry)
	await wait_frames(2)
	assert_gt(strip.entry_count(), 5)
	var rows := {}
	for card in strip.find_children("*", "PanelContainer", true, false):
		if card.has_meta("headline"):
			rows[int((card as Control).position.y)] = true
			assert_almost_eq((card as Control).size.x, Newswire.STRIP_CARD_WIDTH, 0.5, "fixed-width cards")
	assert_eq(rows.size(), 1, "one row of cards scrolling sideways")


func test_components_accept_calls_before_joining_the_tree() -> void:
	var wire := Newswire.new()
	wire.set_horizontal(false)
	wire.set_compact(true)
	wire.add_entry(_story(3, SimConstants.CEO, "Early story"))
	assert_eq(wire.entry_count(), 1)
	holder.add_child(wire)
	await wait_frames(1)
	assert_eq(wire.get_headline_titles(), ["Early story"])
	var page := FrontPage.new()
	page.present(EraChronicle.summarize_era(gov_engine.event_log, gov_engine.world.history, 1, SimConstants.GOVERNANCE))
	holder.add_child(page)
	await wait_frames(2)
	assert_true(page.visible, "the edition prints once the page is ready")


# --- EraChronicle --------------------------------------------------------------------

func test_campaign_scenarios_hold() -> void:
	assert_eq(gov_result["reason"], "TURN_LIMIT", "a Council campaign plays out the century (seed %d)" % gov_engine.campaign_seed)
	assert_eq(gov_result["verdict"]["verdict"], "VICTORY")
	assert_eq(crash_result["reason"], "CATASTROPHE", "a campaign ends in catastrophe (%s, seed %d)" % [crash_engine.player_role, crash_engine.campaign_seed])
	assert_gte(int(crash_result["turn"]), EraChronicle.era_turns(3).x, "after reaching Era III")
	assert_lt(int(crash_result["turn"]), SimConstants.TOTAL_TURNS)


func test_era_summaries_match_history() -> void:
	for pair in [[gov_engine, gov_result], [crash_engine, crash_result]]:
		var engine: SimulationEngine = pair[0]
		var history: Array = engine.world.history
		for era in [1, 2, 3]:
			var summary := EraChronicle.summarize_era(engine.event_log, history, era, engine.player_role)
			var span := EraChronicle.era_turns(era)
			var end_turn := mini(span.y, int(history[-1]["turn"]))
			assert_eq(summary["era_start_turn"], span.x)
			assert_eq(summary["era_end_turn"], end_turn)
			var start_entry := _history_at(history, maxi(0, span.x - 1))
			var end_entry := _history_at(history, end_turn)
			var stats: Array = summary["stats"]
			assert_eq(stats.size(), 3, "trust, compute and drift")
			for stat in stats:
				assert_almost_eq(float(stat["from"]), float(start_entry[stat["key"]]), 0.0001, "%s from (era %d)" % [stat["label"], era])
				assert_almost_eq(float(stat["to"]), float(end_entry[stat["key"]]), 0.0001, "%s to (era %d)" % [stat["label"], era])
			assert_true(String(summary["title"]).begins_with("The "), "title '%s'" % summary["title"])
			assert_between((summary["paragraphs"] as Array).size(), 1, 3)
			assert_lte((summary["also"] as Array).size(), 4)
			for text in summary["paragraphs"] + summary["also"] + [summary["deck"], summary["title"]]:
				assert_false(String(text).contains("{"), "no placeholders: %s" % text)
				assert_true(String(text).length() > 0)
			assert_eq((summary["lines"] as Array).size(), 3, "three lines to chart")
	var era_one := EraChronicle.summarize_era(gov_engine.event_log, gov_engine.world.history, 1, SimConstants.GOVERNANCE)
	assert_has(_era_one_themes(gov_engine.event_log, SimConstants.GOVERNANCE), String(era_one["title"]).trim_prefix("The Decade of "),
		"'%s' is named for something the Council did" % era_one["title"])
	assert_string_contains(String(era_one["paragraphs"][0]), "the Council")
	assert_eq(era_one["edition"], {"volume": "I", "number": 20, "year": 2036})
	assert_eq(era_one["next_line"], "Era II begins: optical interconnects and modular reactors.")
	assert_eq(EraChronicle.summarize_era(gov_engine.event_log, gov_engine.world.history, 1, SimConstants.GOVERNANCE), era_one,
		"deterministic")


## Every theme the chronicle could name Era I after for [param role]: the
## crisis answers and directives it chose before 2036.
func _era_one_themes(event_log: Array, role: String) -> Array:
	var themes := []
	for entry in event_log:
		if int(entry["turn"]) >= EraChronicle.era_turns(2).x or String(entry.get("faction", "")) != role:
			continue
		var theme := ""
		if entry["category"] == "DILEMMA":
			theme = String(StoryCopy.card_option(String(entry.get("card", "")), String(entry.get("option", "")), role).get("theme", ""))
		elif entry["category"] == "ACTION":
			theme = String(StoryCopy.ACTIONS.get("%s/%s" % [role, entry.get("action", "")], {}).get("theme", ""))
		if theme != "" and not themes.has(theme):
			themes.append(theme)
	return themes


func test_one_chapter_per_era_reached() -> void:
	for pair in [[gov_engine, gov_result], [crash_engine, crash_result]]:
		var engine: SimulationEngine = pair[0]
		var result: Dictionary = pair[1]
		var chapters := EraChronicle.chapters(engine.event_log, engine.world.history, result)
		assert_eq(chapters.size(), 3, "both campaigns reach Era III")
		for i in chapters.size():
			var chapter: Dictionary = chapters[i]
			assert_eq(chapter["number"], ["I", "II", "III"][i])
			assert_gt((chapter["paragraphs"] as Array).size(), 0)
			for text in chapter["paragraphs"]:
				assert_false(String(text).contains("{"))
		assert_eq(int(chapters[-1]["era_end_turn"]), int(result["turn"]), "the last chapter ends with the campaign")
		var footnotes := 0
		for chapter in chapters:
			footnotes += (chapter["footnotes"] as Array).size()
		assert_eq(footnotes, 1, "one footnote marks the century's largest drift jump")
	var gov_chapters := EraChronicle.chapters(gov_engine.event_log, gov_engine.world.history, gov_result)
	var spike_era := SimConstants.era_for_year(SimConstants.year_for_turn(int(_largest_spike(gov_engine.event_log)["turn"])))
	assert_string_contains(" ".join(gov_chapters[spike_era - 1]["paragraphs"]), "the century's largest single jump in drift")
	var spike := _largest_spike(gov_engine.event_log)
	var footnoted := false
	for chapter in gov_chapters:
		for note in chapter["footnotes"]:
			assert_eq(note, "%s, turn %d of the campaign." % [spike["name"], spike["turn"]])
			footnoted = true
	assert_true(footnoted)
	var short := EraChronicle.chapters([], gov_engine.world.history.slice(0, 30), {"turn": 29})
	assert_eq(short.size(), 2, "a campaign cut short in Era II has two chapters")


func _history_at(history: Array, turn: int) -> Dictionary:
	var found: Dictionary = history[0]
	for entry in history:
		if int(entry["turn"]) <= turn:
			found = entry
	return found


# --- FrontPage and the history book ---------------------------------------------------

func _assert_fits(root_control: Control, width: float, context: String) -> void:
	var overflowing: Array[String] = []
	for node in root_control.find_children("*", "Control", true, false):
		var control := node as Control
		if control.is_visible_in_tree() and control.get_global_rect().end.x > width + 0.5:
			overflowing.append("%s (%s) ends at %.0f" % [control.name, control.get_class(), control.get_global_rect().end.x])
	assert_eq(overflowing.size(), 0, "%s fits %.0f px: %s" % [context, width, ", ".join(overflowing.slice(0, 5))])


func test_front_page_presents_and_fits_a_phone() -> void:
	var page := FrontPage.new()
	holder.add_child(page)
	page.set_compact(true)
	var summary := EraChronicle.summarize_era(gov_engine.event_log, gov_engine.world.history, 1, SimConstants.GOVERNANCE)
	page.present(summary)
	await wait_frames(3)
	assert_true(page.visible)
	var texts: Array = []
	for label in page.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	assert_has(texts, "The Ledger")
	assert_true(String(summary["title"]).begins_with("The Decade of "), "Era I is named for the Council: " + String(summary["title"]))
	assert_has(texts, String(summary["title"]))
	assert_has(texts, "ALSO IN THIS EDITION")
	_assert_fits(page, PHONE.x, "front page")
	var dismissed := [false]
	page.dismissed.connect(func(): dismissed[0] = true)
	(page.find_child("TurnPage", true, false) as Button).pressed.emit()
	assert_true(dismissed[0], "Turn the page dismisses the edition")
	assert_false(page.visible)


func test_front_page_desktop_has_two_columns() -> void:
	holder.size = Vector2(1600, 900)
	var page := FrontPage.new()
	holder.add_child(page)
	page.present(EraChronicle.summarize_era(crash_engine.event_log, crash_engine.world.history, 2, crash_engine.player_role))
	await wait_frames(3)
	var bodies := page.find_children("*", "RichTextLabel", true, false)
	assert_gt(bodies.size(), 1, "the story runs in columns")
	var page_panel: Control = page.find_child("Page", true, false)
	assert_almost_eq(page_panel.size.x, FrontPage.DESKTOP_WIDTH, 1.0, "broadsheet width")


func test_history_book_presents_and_fits_a_phone() -> void:
	var book := EndgameDebrief.new()
	holder.add_child(book)
	book.set_compact(true)
	book.present(crash_result, crash_engine.event_log)
	await wait_frames(3)
	assert_true(book.visible)
	assert_eq((book._chart.history as Array).size(), crash_engine.world.history.size(), "appendix chart bound to history")
	assert_eq(book._affinity_box.get_child_count(), 8, "eight end-state affinities")
	assert_eq(book.page_count(), 4, "three chapters and an epilogue")
	assert_eq(book.current_page(), 2, "opens on the last chapter")
	_assert_fits(book, PHONE.x, "history book")
	book.show_chapter(0)
	await wait_frames(2)
	var texts: Array = []
	for label in book.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	assert_has(texts, "CHAPTER I")
	assert_has(texts, String(EraChronicle.summarize_era(crash_engine.event_log, crash_engine.world.history, 1, crash_engine.player_role)["title"]))
	_assert_fits(book, PHONE.x, "history book chapter I")
	book.show_chapter(3)
	await wait_frames(2)
	texts.clear()
	for label in book.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	assert_has(texts, "How It Ended")
	assert_has(texts, "HOW IT ENDED · %s" % crash_result["verdict"]["verdict"])
	var asked := [false, false]
	book.new_campaign_requested.connect(func(): asked[0] = true)
	book.closed.connect(func(): asked[1] = true)
	for button in book.find_children("*", "Button", true, false):
		if (button as Button).text == "New campaign":
			(button as Button).pressed.emit()
		elif (button as Button).text == "Inspect final state":
			(button as Button).pressed.emit()
	assert_true(asked[0], "new campaign requested")
	assert_true(asked[1], "closed to inspect the final state")


func test_history_book_without_a_log_still_reads() -> void:
	holder.size = Vector2(1600, 900)
	var book := EndgameDebrief.new()
	holder.add_child(book)
	book.present(gov_result)
	await wait_frames(2)
	assert_eq(book.page_count(), 4)
	assert_eq(book._affinity_box.get_child_count(), 8)
	var spread: Control = book.find_child("Spread", true, false)
	assert_almost_eq(spread.size.x, EndgameDebrief.SPREAD_WIDTH, 1.0, "a two-page spread on desktop")
