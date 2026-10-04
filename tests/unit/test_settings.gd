extends "res://tests/framework/test_case.gd"
## GameSettings: the shared player preferences.

const TEST_PATH := "user://test_synapse_settings.cfg"


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	GameSettings.use(null)


func test_defaults_and_coercion() -> void:
	var settings := GameSettings.new()
	settings.path = ""
	assert_eq(settings.get_value("text_scale"), 1.0)
	settings.set_value("text_scale", 1.2)
	assert_eq(settings.get_value("text_scale"), 1.15, "snaps to an offered size")
	settings.set_value("sound_volume", 4.0)
	assert_eq(settings.get_value("sound_volume"), 1.0)
	settings.set_value("colorblind", 1)
	assert_eq(settings.get_value("colorblind"), true)
	settings.set_value("nonsense", 3)
	assert_null(settings.get_value("nonsense"))


func test_changes_are_announced_once_and_saved() -> void:
	var settings := GameSettings.new()
	settings.path = TEST_PATH
	var seen: Array = []
	settings.changed.connect(func(key: String, value: Variant): seen.append([key, value]))
	settings.set_value("plain_language", true)
	settings.set_value("plain_language", true)
	assert_eq(seen, [["plain_language", true]])
	var reloaded := GameSettings.new()
	reloaded.path = TEST_PATH
	reloaded.load_settings()
	assert_eq(reloaded.get_value("plain_language"), true)
	assert_eq(reloaded.get_value("effects"), true, "untouched keys keep their defaults")


func test_shared_instance() -> void:
	var memory := GameSettings.new()
	memory.path = ""
	GameSettings.use(memory)
	memory.set_value("vibration", false)
	assert_eq(GameSettings.value("vibration"), false)
	assert_eq(GameSettings.instance(), memory)
