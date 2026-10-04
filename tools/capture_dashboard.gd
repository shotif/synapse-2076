extends SceneTree
## Drives the real dashboard through a campaign and saves screenshots
## (requires a renderer, e.g. Xvfb + Mesa). The window size and --touch pick
## the layout, as on a real device:
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 \
##       --script res://tools/capture_dashboard.gd -- --out=docs/screenshots
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 412x915 \
##       --script res://tools/capture_dashboard.gd -- --out=docs/screenshots --prefix=mobile_ --touch
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1180x820 \
##       --script res://tools/capture_dashboard.gd -- --out=docs/screenshots --prefix=tablet_ --touch
##
## Options: --role=CEO --seed=2076 --prefix=NAME_ --touch.
## Writes <prefix>role_select, crisis_card, dashboard (Era I), lattice
## (desktop), world, lens and news (tabbed layouts), front_page,
## era_upgrade, era2, era3 and debrief.

var out_dir := "user://screenshots"
var prefix := ""
var role := SimConstants.CEO
var campaign_seed := 2076
var touch := false
var dashboard: Control


func _initialize() -> void:
	await process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--prefix="):
			prefix = arg.get_slice("=", 1)
		elif arg.begins_with("--role="):
			role = arg.get_slice("=", 1)
		elif arg.begins_with("--seed="):
			campaign_seed = int(arg.get_slice("=", 1))
		elif arg == "--touch":
			touch = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	ProjectSettings.set_setting("synapse/llm/probe_on_start", false)

	dashboard = (load("res://ui/main_dashboard.tscn") as PackedScene).instantiate()
	root.add_child(dashboard)
	current_scene = dashboard
	await _frames(5)
	dashboard.apply_layout(UiLayout.compute(Vector2(root.size), 1.0, touch))
	await _frames(20)
	await _shot("role_select")

	dashboard.start_campaign(role, campaign_seed, false)
	await _frames(30)
	await _shot("crisis_card")

	await _play_turns(8)
	await _frames(40)
	if dashboard.compact:
		for tab in ["act", "world", "lens", "news"]:
			dashboard.show_tab(tab)
			await _frames(25)
			await _shot("dashboard" if tab == "act" else tab)
		dashboard.show_tab("world")
	else:
		await _shot("dashboard")
		dashboard.show_view("lattice")
		await _frames(90)
		await _shot("lattice")
		dashboard.show_view("globe")

	await _advance_to_era(2, true)
	await _settle_turn()
	await _shot("era2")
	await _advance_to_era(3, false)
	await _settle_turn()
	if dashboard.compact:
		dashboard.show_tab("world")
		await _frames(30)
	await _shot("era3")

	# Spectate the rest of the campaign to reach the history book.
	var engine: SimulationEngine = dashboard.engine
	dashboard.spectate = true
	engine.autoplay_player = true
	for _i in 400:
		if engine.is_ended():
			break
		engine.advance()
	await _frames(40)
	await _shot("debrief")
	print("Screenshots written to %s" % ProjectSettings.globalize_path(out_dir))
	quit(0)


## Plays [param count] turns through the real widgets and leaves the next
## crisis answered with a directive selected.
func _play_turns(count: int) -> void:
	var engine: SimulationEngine = dashboard.engine
	for _turn in count:
		if engine.is_ended():
			break
		if not engine.is_awaiting_player():
			await _frames(5)
			continue
		_answer_crisis(1.0)
		dashboard.get_node("%DirectivePanel")._on_execute_pressed()
		await _frames(30)
	if engine.is_awaiting_player():
		_answer_crisis(1.4)


func _answer_crisis(intensity: float) -> void:
	var engine: SimulationEngine = dashboard.engine
	var dialog: DilemmaDialog = dashboard.get_node("%DilemmaDialog")
	dialog.choose(DilemmaDeck.choose_auto_option(engine.current_dilemma, role, engine.get_player()))
	var decision := HeuristicFallback.evaluate(role, engine.build_observation(role))
	dashboard.get_node("%DirectivePanel").select_directive(decision["action"], intensity)


## Autoplays until [param era] begins, then shows its front page and the
## system upgrade (captured when [param capture] is true).
func _advance_to_era(era: int, capture: bool) -> void:
	var engine: SimulationEngine = dashboard.engine
	dashboard.spectate = true
	engine.autoplay_player = true
	for _i in 400:
		if engine.is_ended() or int(engine.get_snapshot().get("era", 1)) >= era:
			break
		engine.advance()
	var front_page: FrontPage = dashboard.get_node("FrontPage")
	var upgrade: EraUpgrade = dashboard.get_node("EraUpgrade")
	await _frames(30)
	if front_page.visible:
		if capture:
			await _shot("front_page")
		front_page._turn_page()
	for _i in 900:
		if not upgrade.is_playing() or upgrade._current_step() >= 3:
			break
		await process_frame
	if capture and upgrade.is_playing():
		await _shot("era_upgrade")
	upgrade.finish_now()
	engine.autoplay_player = false
	dashboard.spectate = false


## Brings the campaign to the player's next decision and answers it.
func _settle_turn() -> void:
	var engine: SimulationEngine = dashboard.engine
	for _i in 10:
		if engine.is_awaiting_player() or engine.is_ended():
			break
		engine.advance()
	if engine.is_awaiting_player():
		dashboard._on_player_input_required(engine.get_player_context())
		await _frames(20)
		_answer_crisis(1.2)
	if dashboard.compact:
		dashboard.show_tab("act")
	await _frames(40)


func _frames(count: int) -> void:
	for _i in count:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := out_dir.path_join(prefix + shot_name + ".png")
	image.save_png(path)
	print("saved ", path)
