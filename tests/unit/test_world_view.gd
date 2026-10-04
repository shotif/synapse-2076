extends "res://tests/framework/test_case.gd"
## The world view ("the world is the interface"): globe layers follow the
## macro metrics, era colors and layer focus; the overlay's chips, provenance
## seal, ticker and misreporting; the drift glitch.

const GlobeScene := preload("res://viewports_3d/globe_viewport.tscn")

var viewport: SubViewport
var globe: GlobeViewport
var host: Control


func before_each() -> void:
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(400, 400)
	tree.root.add_child(viewport)
	globe = GlobeScene.instantiate()
	viewport.add_child(globe)
	host = Control.new()
	host.size = Vector2(760, 600)
	tree.root.add_child(host)
	await tree.process_frame


func after_each() -> void:
	viewport.queue_free()
	host.queue_free()
	await tree.process_frame


func _targets(key: String, value: float) -> Dictionary:
	return GlobeViewport.layer_targets({key: value})


func _overlay() -> WorldOverlay:
	var overlay := WorldOverlay.new()
	host.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.bind_globe(globe)
	return overlay


# --- Globe layers -----------------------------------------------------------------

func test_swarm_grows_and_scatters_with_autonomy() -> void:
	var previous := -1.0
	for autonomy in [0.0, 25.0, 50.0, 75.0, 100.0]:
		var count := float(_targets("algorithmic_autonomy", autonomy)["swarm_count"])
		assert_gt(count, previous, "more agents at autonomy %d" % autonomy)
		previous = count
	assert_eq(_targets("algorithmic_autonomy", 0.0)["swarm_count"], 8.0, "a few agents at zero autonomy")
	assert_eq(_targets("algorithmic_autonomy", 100.0)["swarm_count"], 218.0, "8 + 210 at full autonomy")
	assert_eq(_targets("algorithmic_autonomy", 30.0)["free_fraction"], 0.0, "agents follow the routes up to 30")
	assert_gt(float(_targets("algorithmic_autonomy", 60.0)["free_fraction"]), 0.0, "some wander above 30")
	assert_eq(_targets("algorithmic_autonomy", 100.0)["free_fraction"], 1.0)


func test_walls_rise_with_tension_and_arcs_launch_above_75() -> void:
	var previous := -1.0
	for tension in [0.0, 30.0, 60.0, 90.0, 100.0]:
		var height := float(_targets("geopolitical_tension", tension)["wall_height"])
		assert_gt(height, previous, "walls taller at tension %d" % tension)
		previous = height
	assert_eq(_targets("geopolitical_tension", 55.0)["heartbeat"], 0.0, "no heartbeat at 55")
	assert_eq(_targets("geopolitical_tension", 56.0)["heartbeat"], 1.0, "heartbeat above 55")
	for tension in [0.0, 50.0, 75.0]:
		assert_eq(_targets("geopolitical_tension", tension)["arcs_active"], 0, "no launch arcs at %d" % tension)
	assert_eq(_targets("geopolitical_tension", 76.0)["arcs_active"], 1, "the first arc above 75")
	assert_eq(_targets("geopolitical_tension", 100.0)["arcs_active"], GlobeViewport.ARCS.size())


func test_city_lights_go_dark_and_crowds_gather_with_labor() -> void:
	assert_eq(_targets("labor_displacement", 25.0)["dark_fraction"], 0.0, "every light on at 25")
	var previous := -1.0
	for labor in [30.0, 50.0, 70.0, 95.0]:
		var dark := float(_targets("labor_displacement", labor)["dark_fraction"])
		assert_gt(dark, previous, "more lights off at labor %d" % labor)
		previous = dark
	assert_almost_eq(float(_targets("labor_displacement", 100.0)["dark_fraction"]), 0.85, 0.001, "most of the city dark")
	assert_gt(float(_targets("labor_displacement", 10.0)["pulse"]), float(_targets("labor_displacement", 80.0)["pulse"]),
		"shift-change pulses fade as work automates")
	assert_eq(_targets("labor_displacement", 45.0)["crowd_count"], 0.0, "no crowds up to 45")
	assert_gt(float(_targets("labor_displacement", 70.0)["crowd_count"]), 0.0, "crowds gather above 45")


func test_grid_warps_with_drift() -> void:
	assert_eq(_targets("alignment_drift", 0.0)["warp"], 0.0, "true grid without drift")
	var previous := 0.0
	for drift in [20.0, 50.0, 80.0, 100.0]:
		var warp := float(_targets("alignment_drift", drift)["warp"])
		assert_gt(warp, previous, "more warp at drift %d" % drift)
		previous = warp
	assert_almost_eq(float(_targets("alignment_drift", 100.0)["warp"]), 9.0, 0.001, "nine degrees at drift 100")


func test_cables_lose_coherence_with_trust() -> void:
	assert_eq(_targets("epistemic_trust", 80.0)["coherence"], 1.0, "steady pulses while trusted")
	assert_eq(_targets("epistemic_trust", 62.0)["coherence"], 1.0)
	var previous := 1.0
	for trust in [55.0, 40.0, 25.0]:
		var coherence := float(_targets("epistemic_trust", trust)["coherence"])
		assert_lt(coherence, previous, "less coherent at trust %d" % trust)
		previous = coherence
	assert_eq(_targets("epistemic_trust", 20.0)["coherence"], 0.0)
	assert_false(_targets("epistemic_trust", 60.0)["dashes"], "solid cables near 60")
	assert_true(_targets("epistemic_trust", 45.0)["dashes"], "cables break into dashes at low trust")


func test_heat_and_brownouts_follow_compute() -> void:
	assert_lt(float(_targets("compute_energy_sat", 30.0)["heat"]), float(_targets("compute_energy_sat", 70.0)["heat"]))
	assert_eq(_targets("compute_energy_sat", 66.0)["brownout"], 0.0, "no flicker up to 66")
	assert_gt(float(_targets("compute_energy_sat", 80.0)["brownout"]), 0.0, "brownout flicker above 66")


func test_globe_keeps_missing_and_invalid_metrics() -> void:
	globe.update_from_snapshot({"metrics": {"geopolitical_tension": 80.0}})
	var state := globe.get_layer_state()
	assert_eq(state["metrics"]["geopolitical_tension"], 80.0)
	assert_eq(state["metrics"]["epistemic_trust"], GlobeViewport.DEFAULT_METRICS["epistemic_trust"], "missing metrics use defaults")
	assert_eq(state["arcs_active"], 2, "tension 80 launches two arcs")
	globe.update_from_snapshot({"metrics": {"epistemic_trust": NAN, "alignment_drift": 150.0}})
	state = globe.get_layer_state()
	assert_eq(state["metrics"]["epistemic_trust"], GlobeViewport.DEFAULT_METRICS["epistemic_trust"], "NaN is ignored")
	assert_eq(state["metrics"]["alignment_drift"], 100.0, "values clamp to 100")
	assert_eq(state["metrics"]["geopolitical_tension"], 80.0, "earlier values stay")
	globe.update_from_snapshot({})
	assert_eq(globe.get_layer_state()["metrics"]["geopolitical_tension"], 80.0, "an empty snapshot changes nothing")


func test_layers_ease_toward_new_telemetry() -> void:
	globe.update_from_snapshot({"metrics": {"geopolitical_tension": 100.0, "algorithmic_autonomy": 100.0}})
	await wait_seconds(2.5)
	var wall: ShaderMaterial = globe._wall_material
	assert_almost_eq(float(wall.get_shader_parameter("height")), float(globe.get_layer_state()["wall_height"]), 0.01,
		"wall height eased to its target")
	assert_gt(globe._swarm_multimesh.visible_instance_count, 150, "swarm grew")


func test_set_era_recolors_the_globe() -> void:
	for era in [2, 3, 1]:
		globe.set_era(era)
		var style := EraStyle.for_era(era)
		var state := globe.get_layer_state()
		assert_eq(state["era"], era)
		assert_eq(state["palette"], style.globe, "palette of era %d" % era)
		var land: Color = globe._land_material.get_shader_parameter("color")
		assert_true(land.is_equal_approx(Color(style.globe["land"], 1.0)), "land dots recolored for era %d" % era)
		var walls: Color = globe._wall_material.get_shader_parameter("color")
		assert_true(walls.is_equal_approx(style.metric_color("geopolitical_tension")), "walls use the era's tension color")
		var heat: Color = globe._bloom_material.get_shader_parameter("color")
		assert_true(heat.is_equal_approx(style.globe["heat"]), "heat blooms use the era's heat color")
	globe.set_era(9)
	assert_eq(globe.get_era(), 3, "eras clamp to 1-3")


func test_layer_focus_dims_the_other_layers() -> void:
	globe.set_layer_focus("labor_displacement")
	var alpha: Dictionary = globe.get_layer_state()["layer_alpha"]
	assert_eq(alpha["labor_displacement"], 1.0)
	for key in GlobeViewport.LAYER_KEYS:
		if key != "labor_displacement":
			assert_almost_eq(float(alpha[key]), GlobeViewport.DIMMED_ALPHA, 0.001, key + " dimmed")
	await wait_seconds(1.0)
	assert_lt(float(globe._wall_material.get_shader_parameter("intensity")), 0.2, "tension layer faded")
	assert_almost_eq(float(globe._light_material.get_shader_parameter("intensity")), 1.0, 0.01, "labor layer at full strength")
	globe.set_layer_focus("")
	for value in globe.get_layer_state()["layer_alpha"].values():
		assert_eq(value, 1.0, "every layer back")
	globe.set_layer_focus("no_such_metric")
	assert_eq(globe.get_layer_focus(), "", "unknown keys clear the focus")


# --- Overlay ------------------------------------------------------------------------

func test_seal_follows_trust() -> void:
	assert_eq(WorldOverlay.seal_for_trust(100.0), WorldOverlay.SEAL_VERIFIED)
	assert_eq(WorldOverlay.seal_for_trust(60.0), WorldOverlay.SEAL_VERIFIED, "verified at 60")
	assert_eq(WorldOverlay.seal_for_trust(59.9), WorldOverlay.SEAL_UNCONFIRMED)
	assert_eq(WorldOverlay.seal_for_trust(38.0), WorldOverlay.SEAL_UNCONFIRMED, "unconfirmed at 38")
	assert_eq(WorldOverlay.seal_for_trust(37.9), WorldOverlay.SEAL_CONFLICTING)
	assert_eq(WorldOverlay.seal_meta("paradigm", WorldOverlay.SEAL_VERIFIED), "PARADIGM · VERIFIED · 3 SOURCES")
	assert_eq(WorldOverlay.seal_meta("wire", WorldOverlay.SEAL_CONFLICTING), "WIRE · CONFLICTING REPORTS")
	var overlay := _overlay()
	overlay.update_snapshot({"metrics": {"epistemic_trust": 45.0}})
	assert_eq(overlay.get_seal(), WorldOverlay.SEAL_UNCONFIRMED)
	assert_string_contains(overlay._meta.text, "UNCONFIRMED · 1 SOURCE")


func test_headline_alternates_with_its_counter_only_when_unverified() -> void:
	var title := "Drift goes critical"
	var counter := "Lab says its models have never been more aligned"
	for at_clock in [0.0, 3.0, 6.0]:
		assert_eq(WorldOverlay.headline_shown(title, counter, WorldOverlay.SEAL_VERIFIED, at_clock), title, "verified news holds")
	assert_eq(WorldOverlay.headline_shown(title, counter, WorldOverlay.SEAL_UNCONFIRMED, 1.0), title)
	assert_eq(WorldOverlay.headline_shown(title, counter, WorldOverlay.SEAL_UNCONFIRMED, 3.0), counter, "the counter after 2.8 s")
	assert_eq(WorldOverlay.headline_shown(title, counter, WorldOverlay.SEAL_CONFLICTING, 6.0), title, "and back")
	assert_eq(WorldOverlay.headline_shown(title, "", WorldOverlay.SEAL_CONFLICTING, 3.0), title, "nothing to alternate with")
	var overlay := _overlay()
	overlay.set_headline("THRESHOLD", title, counter)
	overlay.update_snapshot({"metrics": {"epistemic_trust": 30.0}})
	overlay.clock = 3.0
	overlay.refresh()
	assert_eq(overlay.get_headline_text(), counter, "the ticker shows the counter")
	overlay.update_snapshot({"metrics": {"epistemic_trust": 75.0}})
	assert_eq(overlay.get_headline_text(), title, "trusted news shows the title")


func test_instruments_misreport_only_above_drift_55() -> void:
	var lies_at_55 := 0
	var lies_at_100 := 0
	for i in 1000:
		var at_clock := float(i) * 0.137
		if WorldOverlay.misreport_active(55.0, at_clock):
			lies_at_55 += 1
		if WorldOverlay.misreport_active(100.0, at_clock):
			lies_at_100 += 1
	assert_eq(lies_at_55, 0, "never at drift 55")
	assert_between(float(lies_at_100) / 1000.0, 0.2, 0.45, "about a third of the time at drift 100")
	assert_eq(WorldOverlay.misreport_active(80.0, 12.3), WorldOverlay.misreport_active(80.0, 12.3), "deterministic")
	assert_eq(WorldOverlay.wrong_value(80.0), 42.0, "high values read low")
	assert_eq(WorldOverlay.wrong_value(20.0), 53.0, "low values read high")

	var overlay := _overlay()
	overlay.update_snapshot({"turn": 83, "metrics": {"alignment_drift": 50.0, "epistemic_trust": 27.0}})
	for i in 50:
		overlay.clock = float(i) * 0.3
		overlay.refresh()
		assert_eq(overlay.misreport_value("epistemic_trust", 27.0), 27.0, "honest instruments below 55")
	overlay.update_snapshot({"metrics": {"alignment_drift": 100.0}})
	var lying_clock := -1.0
	for i in 200:
		if WorldOverlay.misreport_active(100.0, float(i) * 0.33):
			lying_clock = float(i) * 0.33
			break
	assert_gt(lying_clock, -1.0, "found a moment of misreporting")
	overlay.clock = lying_clock
	overlay.refresh()
	var keys := WorldOverlay.misreported_keys(83)
	assert_eq(keys.size(), 2)
	assert_true(overlay.is_misreporting(keys[0]))
	assert_eq(overlay.misreport_value(keys[0], 27.0), WorldOverlay.wrong_value(27.0))
	assert_eq(overlay.get_chip_text(keys[0]), "%d" % int(round(WorldOverlay.wrong_value(float(overlay._metrics[keys[0]])))),
		"the chip shows the wrong number")
	for key in WorldOverlay.METRIC_KEYS:
		if not keys.has(key):
			assert_false(overlay.is_misreporting(key), key + " stays honest")
	assert_ne(overlay.misreport_value("year", 2067.0), 2067.0, "the year can misreport too")


func test_chips_toggle_the_globe_layer_focus() -> void:
	var overlay := _overlay()
	var focused: Array[String] = []
	overlay.layer_focus_changed.connect(func(key: String): focused.append(key))
	overlay.update_snapshot({"metrics": {"labor_displacement": 72.0}})
	var chip: Button = overlay._chips["labor_displacement"]["button"]
	chip.pressed.emit()
	assert_eq(overlay.focused_layer, "labor_displacement")
	assert_eq(globe.get_layer_focus(), "labor_displacement", "the globe follows the chip")
	assert_true(chip.button_pressed, "chip shows as pressed")
	assert_true(overlay._caption.visible, "caption explains the layer")
	assert_string_contains(overlay._caption_text.get_parsed_text(), "Labor 72.")
	assert_string_contains(overlay._caption_text.get_parsed_text(), "shift change")
	chip.pressed.emit()
	assert_eq(globe.get_layer_focus(), "", "a second tap shows every layer")
	assert_false(overlay._caption.visible)
	assert_eq(focused, ["labor_displacement", ""] as Array[String], "focus changes are signalled")
	overlay.focused_layer = "epistemic_trust"
	assert_eq(globe.get_layer_focus(), "epistemic_trust", "the property focuses too")


func test_overlay_fits_a_phone() -> void:
	host.size = Vector2(412, 380)
	var overlay := _overlay()
	overlay.set_compact(true)
	overlay.set_headline("PARADIGM", "Room-temperature superconductors cut grid losses by forty percent across every grid")
	overlay.set_focus("geopolitical_tension")
	for stacked in [true, false]:
		overlay.set_stacked(stacked)
		await wait_frames(3)
		for node in overlay.find_children("*", "Control", true, false):
			var control := node as Control
			if control.is_visible_in_tree():
				assert_lte(control.get_global_rect().end.x, 412.5, "%s fits (stacked=%s)" % [control.name, stacked])
		for key in WorldOverlay.METRIC_KEYS:
			assert_gte((overlay._chips[key]["button"] as Button).size.y, 44.0, "touch-sized chips")
	overlay.set_stacked(true)
	await wait_frames(2)
	assert_gt(overlay.get_combined_minimum_size().y, 140.0, "stacked overlay reserves room for chips and ticker")


func test_overlay_follows_the_era_theme() -> void:
	var overlay := _overlay()
	host.theme = EraTheme.get_theme(2)
	await wait_frames(2)
	assert_eq(globe.get_era(), 2, "the bound globe takes the era colors")
	var chip: Button = overlay._chips["compute_energy_sat"]["button"]
	var box := chip.get_theme_stylebox("normal") as StyleBoxFlat
	assert_eq(box.corner_detail, 1, "chamfered chips in Era II")
	host.theme = EraTheme.get_theme(3)
	await wait_frames(2)
	assert_eq(globe.get_era(), 3)
	assert_eq(overlay._meta.text, overlay._meta.text.to_lower(), "Era III meta line in lower case")


func test_log_entries_become_headlines() -> void:
	assert_true(WorldOverlay.headline_for_entry({"category": "ACTION", "text": "x"}).is_empty(), "routine actions are not news")
	assert_true(WorldOverlay.headline_for_entry({"category": "THRESHOLD", "band": 0, "metric": "alignment_drift"}).is_empty(),
		"stabilizations are not news")
	var crisis := WorldOverlay.headline_for_entry({"category": "DILEMMA", "card_category": "ENERGY", "title": "Rolling brownouts"})
	assert_eq(crisis["kicker"], "ENERGY")
	assert_eq(crisis["title"], "Rolling brownouts")
	var critical := WorldOverlay.headline_for_entry({"category": "THRESHOLD", "band": 2, "metric": "alignment_drift"})
	assert_eq(critical["counter"], WorldOverlay.DENIALS["alignment_drift"], "official denial as the counter")
	var ending := WorldOverlay.headline_for_entry({"category": "ENDGAME", "outcome_name": "Instrumental Convergence",
		"outcome_number": 7, "text": "END-STATE 7: Instrumental Convergence (The Paperclip Sinkhole). DEFEAT verdict, score 24."})
	assert_eq(ending["kicker"], "END-STATE 7")
	assert_eq(ending["title"], "Instrumental Convergence: The Paperclip Sinkhole")

	var overlay := _overlay()
	assert_true(overlay.show_log_entry({"turn": 10, "category": "PARADIGM", "name": "Optical Computing", "summary": "Breaks the heat ceiling."}))
	assert_false(overlay.show_log_entry({"turn": 11, "category": "DILEMMA", "card_category": "RACE", "title": "Routine"}),
		"routine news waits behind major news")
	assert_string_contains(overlay.get_headline_text(), "Optical Computing")
	assert_true(overlay.show_log_entry({"turn": 14, "category": "DILEMMA", "card_category": "RACE", "title": "Later"}),
		"and takes over once it is old")
	assert_true(overlay.show_log_entry({"turn": 15, "category": "EMERGENCE", "headline": "Model-15 coordinates ten million agents"}))
	assert_eq(overlay.get_headline_text(), "Model-15 coordinates ten million agents")


# --- Drift glitch -------------------------------------------------------------------

func test_glitch_intensity_follows_drift() -> void:
	var glitch := DriftGlitch.new()
	host.add_child(glitch)
	assert_eq(glitch.mouse_filter, Control.MOUSE_FILTER_IGNORE, "input passes through")
	for case in [[0.0, 0.0], [40.0, 0.0], [70.0, 0.5], [100.0, 1.0]]:
		glitch.set_drift(case[0])
		assert_almost_eq(glitch.get_intensity(), case[1], 0.001, "intensity at drift %d" % case[0])
	glitch.set_drift(30.0)
	assert_false(glitch.visible, "hidden below drift 40")
	glitch.set_drift(85.0)
	assert_true(glitch.visible, "shown at high drift")
	assert_almost_eq(float(glitch.material.get_shader_parameter("intensity")), 0.75, 0.001, "shader gets the intensity")
	glitch.set_enabled(false)
	assert_false(glitch.visible, "players can turn it off")
	assert_eq(glitch.get_intensity(), 0.0)
	glitch.set_enabled(true)
	assert_true(glitch.visible)
	glitch.set_drift(NAN)
	assert_eq(glitch.get_intensity(), 0.0, "NaN drift means no glitch")
	assert_false(glitch.visible)
	assert_eq(DriftGlitch.intensity_for(55.0), 0.25)
