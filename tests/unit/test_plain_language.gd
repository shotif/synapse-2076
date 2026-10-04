extends "res://tests/framework/test_case.gd"
## Plain language: every metric, index, currency, faction and key idea has
## plain words; UiFormat's names switch with the setting and back; the
## widgets that cache names follow; the glossary filters and fits a phone.

const PHONE := Vector2(412, 915)

var settings: GameSettings
var host: Control


func before_each() -> void:
	settings = GameSettings.new()
	settings.path = ""
	GameSettings.use(settings)
	host = Control.new()
	host.theme = EraTheme.get_theme(1)
	host.size = PHONE
	tree.root.add_child(host)


func after_each() -> void:
	host.queue_free()
	await tree.process_frame
	GameSettings.use(null)
	EraTheme.invalidate()


func _assert_words(key: String, context: String) -> void:
	assert_true(PlainLanguage.has_entry(key), "%s %s has plain words" % [context, key])
	assert_ne(PlainLanguage.plain_name(key), key, "%s %s: plain name" % [context, key])
	assert_gt(PlainLanguage.explain(key).length(), 20.0, "%s %s: explanation" % [context, key])
	assert_false(PlainLanguage.short_name(key).is_empty(), "%s %s: short label" % [context, key])
	assert_ne(PlainLanguage.technical_name(key), "", "%s %s: technical name" % [context, key])


func test_every_metric_and_index_has_plain_words() -> void:
	for key in WorldState.METRIC_KEYS:
		_assert_words(key, "metric")
		assert_eq(PlainLanguage.technical_name(key), String(WorldState.METRIC_INFO[key]["label"]))
		assert_lte(PlainLanguage.short_name(key).length(), 14.0, "%s: short enough for chips and tiles" % key)
	for key in WorldState.INDEX_KEYS:
		_assert_words(key, "index")
		assert_eq(PlainLanguage.technical_name(key), String(WorldState.INDEX_INFO[key]["label"]))
		assert_lte(PlainLanguage.short_name(key).length(), 14.0, "%s: short enough for chips and tiles" % key)
	assert_eq(PlainLanguage.plain_name("alignment_drift"), "AI going off-script")
	assert_eq(PlainLanguage.plain_name("epistemic_trust"), "Trust in what's true")


func test_every_currency_and_faction_has_plain_words() -> void:
	for role in SimConstants.FACTION_ORDER:
		_assert_words(role, "faction")
		assert_eq(PlainLanguage.technical_name(role), UiFormat.role_name(role))
		var info: Dictionary = FactionRegistry.resource_info_for(role)
		for key in info:
			_assert_words(String(key), "currency")
			assert_eq(PlainLanguage.technical_name(String(key)), String(info[key]["label"]))
	for key in UiFormat.RESOURCE_NAMES:
		assert_true(PlainLanguage.CURRENCIES.has(key), "%s is covered" % key)


func test_key_ideas_eras_and_endings_have_plain_words() -> void:
	for term in ["flops", "compute", "agi", "alignment", "alignment_tax", "interpretability", "paradigm_shift",
			"emergent_capability", "directive", "cooldown", "defer", "era_goal"]:
		_assert_words(term, "term")
	for era in [1, 2, 3]:
		_assert_words("era_%d" % era, "era")
		assert_string_contains(PlainLanguage.technical_name("era_%d" % era), String(EraStyle.NAMES[era]))
	for outcome in VictoryMatrix.OUTCOMES:
		_assert_words(String(outcome["id"]), "end-state")
		assert_string_contains(PlainLanguage.technical_name(String(outcome["id"])), String(outcome["name"]))
	var seen := {}
	for item in PlainLanguage.glossary():
		assert_false(seen.has(item["id"]), "%s appears once in the glossary" % item["id"])
		seen[item["id"]] = true
		assert_has(PlainLanguage.KINDS, String(item["kind"]))
	assert_eq(PlainLanguage.entry("nonsense"), {})
	assert_eq(PlainLanguage.plain_name("nonsense"), "nonsense", "unknown keys pass through")


func test_ui_format_switches_with_the_setting_and_back() -> void:
	var technical := {}
	for key in WorldState.METRIC_KEYS:
		technical[key] = UiFormat.metric_name(key)
	assert_eq(UiFormat.metric_name("alignment_drift"), "Drift")
	assert_eq(UiFormat.resource_name("covert_flops"), "Covert FLOPs")
	assert_eq(UiFormat.metric_short("discovery_index"), "ASI Discovery")
	settings.set_value("plain_language", true)
	for key in WorldState.METRIC_KEYS:
		assert_eq(UiFormat.metric_name(key), PlainLanguage.short_name(key), "%s reads plainly" % key)
		assert_ne(UiFormat.metric_name(key), technical[key], "%s changes" % key)
	assert_eq(UiFormat.metric_name("alignment_drift"), "Off-script AI")
	assert_eq(UiFormat.resource_name("covert_flops"), "Hidden compute")
	assert_eq(UiFormat.metric_short("discovery_index"), "AI exposure")
	assert_eq(UiFormat.metric_name("discovery_index"), "AI exposure", "indices too")
	assert_eq(PlainLanguage.display_name("alignment_drift"), "AI going off-script")
	settings.set_value("plain_language", false)
	for key in WorldState.METRIC_KEYS:
		assert_eq(UiFormat.metric_name(key), technical[key], "%s back to the model's name" % key)
	assert_eq(UiFormat.resource_name("covert_flops"), "Covert FLOPs")
	assert_eq(PlainLanguage.display_name("alignment_drift"), "Alignment Drift Index")


func test_search_matches_names_and_explanations() -> void:
	var ids := func(items: Array) -> Array: return items.map(func(item: Dictionary) -> String: return String(item["id"]))
	assert_has(ids.call(PlainLanguage.search("drift")), "alignment_drift")
	assert_has(ids.call(PlainLanguage.search("OFF script")), "alignment_drift", "every word, any case")
	assert_has(ids.call(PlainLanguage.search("flops")), "flops")
	assert_has(ids.call(PlainLanguage.search("flops")), "covert_flops")
	assert_eq(PlainLanguage.search("zzzz-nothing").size(), 0)
	assert_eq(PlainLanguage.search("  ").size(), PlainLanguage.glossary().size())


func test_meters_and_vitals_follow_the_setting() -> void:
	var meter := MeterBar.new()
	meter.metric_key = "alignment_drift"
	host.add_child(meter)
	assert_eq(meter.label_text, "Drift")
	var strip := VitalsStrip.new()
	strip.size = Vector2(800, 54)
	host.add_child(strip)
	settings.set_value("plain_language", true)
	assert_eq(meter.label_text, "Off-script AI", "meters rename at once")
	assert_string_contains(meter.tooltip_text, "AI going off-script")
	assert_string_contains(strip._get_tooltip(Vector2(700, 20)), "Trust in what's true", "vitals name metrics plainly")
	settings.set_value("plain_language", false)
	assert_eq(meter.label_text, "Drift")


func test_lenses_refresh_names_when_the_setting_changes() -> void:
	var engine := SimulationEngine.new()
	engine.start_campaign(SimConstants.GOVERNANCE, 7, {"autoplay": true})
	engine.run_headless(2)
	engine.advance()
	var lens := LensPanel.create(SimConstants.GOVERNANCE)
	lens.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(lens)
	lens.update_state(engine.get_snapshot(), engine.get_player().resources)
	assert_string_contains(_labels_text(lens), "DRIFT")
	settings.set_value("plain_language", true)
	await wait_frames(2)
	assert_string_contains(_labels_text(lens), "OFF-SCRIPT AI", "the threat board speaks plainly")


func test_glossary_lists_filters_and_fits_a_phone() -> void:
	var glossary := GlossaryDialog.new()
	host.add_child(glossary)
	glossary.set_compact(true)
	glossary.open()
	await wait_frames(3)
	assert_true(glossary.visible)
	assert_eq(glossary.visible_terms().size(), PlainLanguage.glossary().size(), "every term listed")
	_assert_fits(glossary, PHONE.x, "glossary")
	glossary.set_query("trust")
	assert_has(glossary.visible_terms(), "epistemic_trust")
	assert_lt(float(glossary.visible_terms().size()), float(PlainLanguage.glossary().size()), "the search filters")
	var card := glossary.find_child("Term_epistemic_trust", true, false)
	assert_not_null(card, "a card per term")
	if card != null:
		assert_eq((card.find_child("Plain", true, false) as Label).text, "Trust in what's true")
		assert_eq((card.find_child("Technical", true, false) as Label).text, "Public Trust & Cohesion")
	glossary.set_query("no-such-term")
	assert_eq(glossary.visible_terms().size(), 0)
	await wait_frames(2)
	_assert_fits(glossary, PHONE.x, "empty glossary")
	var closed := [false]
	glossary.closed.connect(func() -> void: closed[0] = true)
	glossary.close()
	assert_false(glossary.visible)
	assert_true(closed[0], "closed emitted")


func _labels_text(node: Node) -> String:
	var parts: Array[String] = []
	for label in node.find_children("*", "Label", true, false):
		parts.append((label as Label).text)
	return "\n".join(parts)


func _assert_fits(root: Control, width: float, context: String) -> void:
	var overflowing: Array[String] = []
	for node in root.find_children("*", "Control", true, false):
		var control := node as Control
		if control.is_visible_in_tree() and control.get_global_rect().end.x > width + 0.5:
			overflowing.append("%s (%s) ends at %.0f" % [control.name, control.get_class(), control.get_global_rect().end.x])
	assert_eq(overflowing.size(), 0, "%s fits %.0f px: %s" % [context, width, ", ".join(overflowing.slice(0, 5))])
