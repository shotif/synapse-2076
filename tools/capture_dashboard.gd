extends SceneTree
## Drives the real dashboard through a campaign and saves screenshots
## (requires a renderer, e.g. Xvfb + Mesa):
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 \
##       --script res://tools/capture_dashboard.gd -- --out=docs/screenshots --role=CEO --seed=2076
##
## Produces role_select.png, crisis_card.png, dashboard_globe.png,
## dashboard_lattice.png and endgame_debrief.png.

var out_dir := "user://screenshots"
var role := SimConstants.CEO
var campaign_seed := 2076


func _initialize() -> void:
	await process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--role="):
			role = arg.get_slice("=", 1)
		elif arg.begins_with("--seed="):
			campaign_seed = int(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(out_dir)

	var dashboard: Control = (load("res://ui/main_dashboard.tscn") as PackedScene).instantiate()
	root.add_child(dashboard)
	current_scene = dashboard
	await _frames(20)
	await _shot("role_select")

	dashboard.start_campaign(role, campaign_seed, false)
	await _frames(30)
	await _shot("crisis_card")

	# Play a dozen interactive turns through the real widgets.
	for _turn in 12:
		var engine: SimulationEngine = dashboard.engine
		if engine.is_ended():
			break
		if not engine.is_awaiting_player():
			await _frames(5)
			continue
		var player := engine.get_player()
		var choice := DilemmaDeck.choose_auto_option(engine.current_dilemma, role, player)
		dashboard.get_node("%DilemmaDialog").choose(choice)
		var decision := HeuristicFallback.evaluate(role, engine.build_observation(role))
		dashboard.get_node("%DirectivePanel").select_directive(decision["action"], 1.0)
		dashboard.get_node("%DirectivePanel")._on_execute_pressed()
		await _frames(30)
	# Leave the next crisis resolved and a directive selected for the screenshot.
	var engine: SimulationEngine = dashboard.engine
	if engine.is_awaiting_player():
		dashboard.get_node("%DilemmaDialog").choose(DilemmaDeck.choose_auto_option(engine.current_dilemma, role, engine.get_player()))
		var decision := HeuristicFallback.evaluate(role, engine.build_observation(role))
		dashboard.get_node("%DirectivePanel").select_directive(decision["action"], 1.4)
	await _frames(40)
	await _shot("dashboard_globe")
	dashboard.show_view("lattice")
	await _frames(90)
	await _shot("dashboard_lattice")
	dashboard.show_view("globe")

	# Spectate the rest of the campaign to reach the debrief.
	dashboard.spectate = true
	engine.autoplay_player = true
	for _i in 400:
		if engine.is_ended():
			break
		engine.advance()
	await _frames(30)
	await _shot("endgame_debrief")
	print("Screenshots written to %s" % ProjectSettings.globalize_path(out_dir))
	quit(0)


func _frames(count: int) -> void:
	for _i in count:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	image.save_png(path)
	print("saved ", path)
