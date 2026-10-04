extends SceneTree
## Compiles every GDScript and shader in the project and reports failures.
##
##   godot --headless --path . --script res://tools/check_scripts.gd
##
## Exits 1 if any script fails to load. Used by tools/run_tests.sh as a fast
## lint step before the unit tests.

const SKIP_DIRS := [".godot", ".godot-bin", ".git", "build", "exports"]


func _initialize() -> void:
	await process_frame
	var files: Array[String] = []
	_collect("res://", files)
	var failures: Array[String] = []
	for path in files:
		var resource := ResourceLoader.load(path)
		if resource == null:
			failures.append(path)
		elif resource is GDScript and not (resource as GDScript).can_instantiate():
			failures.append(path)
	print("Checked %d scripts/shaders/scenes, %d failure(s)." % [files.size(), failures.size()])
	for path in failures:
		printerr("  FAILED: " + path)
	quit(1 if not failures.is_empty() else 0)


func _collect(directory: String, out: Array[String]) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	for sub in dir.get_directories():
		if not SKIP_DIRS.has(sub):
			_collect(directory.path_join(sub), out)
	for file_name in dir.get_files():
		if file_name.ends_with(".gd") or file_name.ends_with(".gdshader") or file_name.ends_with(".tscn"):
			out.append(directory.path_join(file_name))
