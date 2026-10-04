extends SceneTree
## Renders any scene and saves a PNG (needs a real renderer, e.g. under Xvfb):
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/capture_scene.gd \
##       -- --scene=res://viewports_3d/globe_viewport.tscn --out=/tmp/globe.png --frames=30
##
## Optional --snapshot=metric:value,... feeds a fake telemetry snapshot to scenes
## exposing update_from_snapshot().

func _initialize() -> void:
	await process_frame
	var scene_path := ""
	var out_path := "user://capture.png"
	var frames := 30
	var metrics := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			scene_path = arg.get_slice("=", 1)
		elif arg.begins_with("--out="):
			out_path = arg.get_slice("=", 1)
		elif arg.begins_with("--frames="):
			frames = int(arg.get_slice("=", 1))
		elif arg.begins_with("--snapshot="):
			for pair in arg.get_slice("=", 1).split(","):
				metrics[pair.get_slice(":", 0)] = float(pair.get_slice(":", 1))
	var packed: PackedScene = load(scene_path)
	if packed == null:
		printerr("Cannot load " + scene_path)
		quit(1)
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	if not metrics.is_empty() and instance.has_method("update_from_snapshot"):
		instance.update_from_snapshot({"metrics": metrics, "tech": {"capability_index": metrics.get("capability_index", 50.0),
			"emerged_capabilities": ["A", "B", "C"]}})
	for _i in frames:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("saved %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	quit(0)
