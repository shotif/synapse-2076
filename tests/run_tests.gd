extends SceneTree
## Headless unit-test runner.
##
##   godot --headless --path . --script res://tests/run_tests.gd
##   godot --headless --path . --script res://tests/run_tests.gd -- --suite=world_state --filter=coupling
##
## Discovers res://tests/unit/test_*.gd, runs every test_* method and exits with
## status 0 when all pass, 1 otherwise. Prints one line per test so script
## errors in the log can be attributed (tools/run_tests.sh additionally fails
## the run if any "SCRIPT ERROR" appears).

const UNIT_DIR := "res://tests/unit"


func _initialize() -> void:
	# _initialize() runs before the root window joins the tree; wait one frame so
	# tests that add nodes (HTTPRequest, timers, scenes) get a live SceneTree.
	await process_frame
	var suite_filter := ""
	var test_filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--suite="):
			suite_filter = arg.get_slice("=", 1)
		elif arg.begins_with("--filter="):
			test_filter = arg.get_slice("=", 1)

	var paths := _discover(UNIT_DIR, suite_filter)
	var started := Time.get_ticks_msec()
	var totals := {"passed": 0, "failed": 0, "assertions": 0}
	var failed_names: Array[String] = []
	print("SYNAPSE-2076 unit tests :: %d suite(s)" % paths.size())

	for path in paths:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			printerr("  [LOAD ERROR] %s" % path)
			totals["failed"] += 1
			failed_names.append(path)
			continue
		var suite: Object = script.new()
		suite.set("tree", self)
		print("\n[%s]" % path.get_file())
		await suite.call("before_all")
		for method_name in _test_methods(script):
			if test_filter != "" and not method_name.contains(test_filter):
				continue
			suite.call("_begin_test", method_name)
			await suite.call("before_each")
			await suite.call(method_name)
			await suite.call("after_each")
			var report: Dictionary = suite.call("_end_test")
			totals["assertions"] += int(report["assertions"])
			if report["passed"]:
				totals["passed"] += 1
				print("  PASS  %s (%d)" % [method_name, report["assertions"]])
			else:
				totals["failed"] += 1
				failed_names.append("%s::%s" % [path.get_file(), method_name])
				print("  FAIL  %s" % method_name)
				if int(report["assertions"]) == 0:
					print("        - no assertions ran (did the test abort on a script error?)")
				for failure in report["failures"]:
					print("        - %s" % failure)
		await suite.call("after_all")

	var elapsed := Time.get_ticks_msec() - started
	print("\n%d passed, %d failed, %d assertions in %d ms" % [totals["passed"], totals["failed"], totals["assertions"], elapsed])
	if not failed_names.is_empty():
		print("Failures:")
		for failed in failed_names:
			print("  - %s" % failed)
	quit(0 if totals["failed"] == 0 else 1)


func _discover(directory: String, suite_filter: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		printerr("Cannot open %s" % directory)
		return found
	for file_name in dir.get_files():
		if not file_name.begins_with("test_") or not file_name.ends_with(".gd"):
			continue
		if suite_filter != "" and not file_name.contains(suite_filter):
			continue
		found.append(directory.path_join(file_name))
	found.sort()
	return found


func _test_methods(script: GDScript) -> Array[String]:
	var names: Array[String] = []
	for method in script.get_script_method_list():
		var method_name := String(method["name"])
		if method_name.begins_with("test_") and not names.has(method_name):
			names.append(method_name)
	return names
