class_name GameSettings
extends RefCounted
## Player preferences shared by the whole interface (accessibility, sound,
## language, onboarding), saved in user://synapse_ui.cfg next to the display
## options. One instance per run: [method instance]. Components read values
## with [method value] and listen to [signal changed] to restyle.

signal changed(key: String, value: Variant)

const PATH := "user://synapse_ui.cfg"
const SECTION := "display"
const TEXT_SCALES := [1.0, 1.15, 1.3]
const DEFAULTS := {
	## Backdrop shaders, glitches and era transitions.
	"effects": true,
	## Interface text size: one of TEXT_SCALES.
	"text_scale": 1.0,
	## Blue and orange instead of green and red for better and worse.
	"colorblind": false,
	## Everyday words instead of the model's jargon.
	"plain_language": false,
	## 0..1
	"sound_volume": 0.8,
	"music_volume": 0.6,
	## Short vibrations on swipes and alerts (phones).
	"vibration": true,
	## Interface language ("" = follow the system when translated).
	"language": "",
	## The guided first campaign has been played or skipped.
	"coach_done": false,
}

static var _instance: GameSettings

## Where this instance saves ("" keeps it in memory, as in tests).
var path := PATH
var _values := {}


static func instance() -> GameSettings:
	if _instance == null:
		_instance = GameSettings.new()
		_instance.load_settings()
	return _instance


## Shortcut for instance().get_value(key).
static func value(key: String) -> Variant:
	return instance().get_value(key)


## Replaces the shared instance (tests use an in-memory one: path "").
static func use(settings: GameSettings) -> void:
	_instance = settings


func _init() -> void:
	_values = DEFAULTS.duplicate(true)


func load_settings() -> void:
	_values = DEFAULTS.duplicate(true)
	if path == "":
		return
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	for key in DEFAULTS:
		if config.has_section_key(SECTION, key):
			_values[key] = _coerce(key, config.get_value(SECTION, key))


func save_settings() -> void:
	if path == "":
		return
	var config := ConfigFile.new()
	config.load(path)
	for key in _values:
		config.set_value(SECTION, key, _values[key])
	config.save(path)


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


## Sets [param key] (unknown keys are ignored), saves and emits [signal changed]
## when the value actually changes.
func set_value(key: String, new_value: Variant, persist: bool = true) -> void:
	if not DEFAULTS.has(key):
		push_warning("GameSettings: unknown key '%s'" % key)
		return
	var clean: Variant = _coerce(key, new_value)
	if _values.get(key) == clean:
		return
	_values[key] = clean
	if persist:
		save_settings()
	changed.emit(key, clean)


## The stored value converted to the default's type (and range).
func _coerce(key: String, raw: Variant) -> Variant:
	var default_value: Variant = DEFAULTS[key]
	match typeof(default_value):
		TYPE_BOOL:
			return bool(raw)
		TYPE_FLOAT:
			var number := float(raw) if (raw is float or raw is int) else float(default_value)
			if not is_finite(number):
				number = float(default_value)
			if key == "text_scale":
				var best: float = TEXT_SCALES[0]
				for option in TEXT_SCALES:
					if absf(float(option) - number) < absf(best - number):
						best = float(option)
				return best
			return clampf(number, 0.0, 1.0)
		_:
			return String(raw)
