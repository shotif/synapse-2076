class_name SaveManager
extends RefCounted
## Saves and resumes campaigns. A save is the engine's [member SimulationEngine.record]
## (every input that shaped the campaign; SimulationEngine.from_record replays
## it) plus a little metadata for the Continue card, as JSON in
## user://saves/<slot>.json:
##   {version, saved_at (unix seconds), role, humans, turn, year, era, scenario,
##    difficulty, mode, seed, daily ("YYYY-MM-DD" or ""), spectate, record}
##
##   var saves := SaveManager.new()
##   saves.save(engine, {"daily": "", "spectate": false})   # after each decision
##   role_select.set_continue(saves.summary())              # {} hides the card
##   var resumed := saves.resume()                          # null when unusable
##
## Ended campaigns are never saved: [method save] refuses them, and the
## dashboard deletes the autosave when the engine emits campaign_ended.
## Missing, corrupted, foreign or old-version files read as "no save":
## [method load_record] returns {}, [method resume] null and [method summary]
## {}. Nothing here pushes errors, so a bad file never breaks the start screen.
## Writes go to a temporary file first and replace the save in one rename.

const VERSION := 1
const DEFAULT_DIR := "user://saves"
const AUTOSAVE := "autosave"
const EXTENSION := ".json"

## Where the saves live (tests point it at a scratch directory).
var dir := DEFAULT_DIR


func _init(save_dir: String = DEFAULT_DIR) -> void:
	dir = save_dir


func path_for(slot: String = AUTOSAVE) -> String:
	return dir.path_join(clean_slot(slot) + EXTENSION)


## Slot names become file names: letters, digits, "-" and "_" only.
static func clean_slot(slot: String) -> String:
	var out := ""
	for i in slot.length():
		var c := slot[i]
		out += c if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "-" or c == "_" else "_"
	return out if not out.is_empty() else AUTOSAVE


## Writes [param engine]'s record and metadata to [param slot]. [param meta]
## adds or overrides metadata (the dashboard passes "daily" and "spectate";
## "mode" defaults to CampaignModes.mode_for(engine.options)). Returns false
## for an engine that has not started or has ended, or when the file cannot be
## written.
func save(engine: SimulationEngine, meta: Dictionary = {}, slot: String = AUTOSAVE) -> bool:
	if engine == null or engine.world == null or engine.record.is_empty() or engine.is_ended():
		return false
	var data := describe(engine, meta)
	data["record"] = engine.record
	var text := JSON.stringify(data, "", false)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := path_for(slot)
	var temp := path + ".tmp"
	if not _write(temp, text):
		return false
	if DirAccess.rename_absolute(temp, path) == OK:
		return true
	# Some platforms will not rename over an existing file.
	DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(temp, path) == OK:
		return true
	DirAccess.remove_absolute(temp)
	return _write(path, text)


## The metadata [method save] writes for [param engine], with [param meta]
## merged over it ("record" and "version" cannot be overridden).
static func describe(engine: SimulationEngine, meta: Dictionary = {}) -> Dictionary:
	var humans: Array = []
	for role in engine.human_roles:
		humans.append(String(role))
	var data := {
		"version": VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"role": String(engine.record.get("role", engine.player_role)),
		"humans": humans,
		"turn": engine.turn,
		"year": engine.get_year(),
		"era": SimConstants.era_for_year(engine.get_year()),
		"scenario": engine.scenario_id,
		"difficulty": engine.difficulty,
		"mode": CampaignModes.mode_for(engine.options),
		"seed": engine.campaign_seed,
		"daily": "",
		"spectate": engine.autoplay_player,
	}
	for key in meta:
		if String(key) != "record" and String(key) != "version":
			data[String(key)] = meta[key]
	return data


## True when [param slot] holds a save this build can resume.
func has_save(slot: String = AUTOSAVE) -> bool:
	return not load_file(slot).is_empty()


## The saved record ({} when missing or unusable).
func load_record(slot: String = AUTOSAVE) -> Dictionary:
	var data := load_file(slot)
	return (data["record"] as Dictionary).duplicate(true) if not data.is_empty() else {}


## The whole save file, validated ({} when missing, corrupted or from another
## version of the save format or the engine's record).
func load_file(slot: String = AUTOSAVE) -> Dictionary:
	var path := path_for(slot)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	return parse(text)


## Parses and validates the text of a save file ({} when unusable).
static func parse(text: String) -> Dictionary:
	var json := JSON.new()
	if text.is_empty() or json.parse(text) != OK or not (json.data is Dictionary):
		return {}
	var data: Dictionary = json.data
	if _number(data.get("version"), -1.0) != float(VERSION):
		return {}
	var record: Variant = data.get("record")
	if not (record is Dictionary):
		return {}
	if _number(record.get("version"), -1.0) != float(SimulationEngine.RECORD_VERSION):
		return {}
	if not SimConstants.is_valid_faction(_text(record.get("role"))):
		return {}
	if not (record.get("seed") is float or record.get("seed") is int):
		return {}
	if not (record.get("turns") is Dictionary) or not (record.get("options", {}) is Dictionary):
		return {}
	return data


## What the Continue card shows ({} when there is no usable save):
## {slot, saved_at, saved_at_text ("just now", "5 min ago", "yesterday",
## "2026-09-21"), role, role_title, humans, players, turn, year (int), era,
## mode, mode_name, years ("2026–2051"), scenario, scenario_name, difficulty,
## difficulty_name, seed, daily, spectate}. [param now_unix] fixes the clock
## for the relative time (tests).
func summary(slot: String = AUTOSAVE, now_unix: float = -1.0) -> Dictionary:
	var data := load_file(slot)
	if data.is_empty():
		return {}
	var record: Dictionary = data["record"]
	var options: Dictionary = record.get("options", {})
	var role := _text(data.get("role"))
	if not SimConstants.is_valid_faction(role):
		role = _text(record.get("role"))
	var humans: Array = []
	var saved_humans: Variant = data.get("humans", options.get("human_roles", []))
	if saved_humans is Array:
		for other in saved_humans:
			if other is String and SimConstants.is_valid_faction(other) and not humans.has(other):
				humans.append(other)
	if humans.is_empty():
		humans = [role]
	var turn := int(_number(data.get("turn"), 0.0))
	var year := _number(data.get("year"), SimConstants.year_for_turn(turn))
	var mode := _text(data.get("mode"))
	if not CampaignModes.is_valid(mode) and mode != CampaignModes.CUSTOM:
		mode = CampaignModes.mode_for(options)
	var scenario := _text(data.get("scenario"), _text(options.get("scenario"), Scenarios.STANDARD))
	var difficulty := _text(data.get("difficulty"), _text(options.get("difficulty"), Difficulty.STANDARD))
	var saved_at := int(_number(data.get("saved_at"), 0.0))
	var now := now_unix if now_unix >= 0.0 else Time.get_unix_time_from_system()
	return {
		"slot": clean_slot(slot),
		"saved_at": saved_at,
		"saved_at_text": relative_time(saved_at, int(now)),
		"role": role,
		"role_title": SimConstants.role_title(role),
		"humans": humans,
		"players": humans.size(),
		"turn": turn,
		"year": int(floor(year)),
		"era": int(_number(data.get("era"), float(SimConstants.era_for_year(year)))),
		"mode": mode,
		"mode_name": CampaignModes.display_name(mode),
		"years": CampaignModes.years_for(int(_number(options.get("start_turn"), 1.0)),
			int(_number(options.get("total_turns"), float(SimConstants.TOTAL_TURNS)))),
		"scenario": scenario,
		"scenario_name": Scenarios.display_name(scenario),
		"difficulty": difficulty,
		"difficulty_name": Difficulty.display_name(difficulty),
		"seed": int(_number(record.get("seed"), 0.0)),
		"daily": _text(data.get("daily")),
		"spectate": bool(data.get("spectate", false)) if data.get("spectate", false) is bool else false,
	}


## Rebuilds the saved campaign at the decision it was saved on. Returns null
## when there is no usable save, or when the replay does not reach the saved
## turn (a save from a build whose rules have changed since).
func resume(slot: String = AUTOSAVE) -> SimulationEngine:
	var data := load_file(slot)
	if data.is_empty():
		return null
	var engine := SimulationEngine.from_record(data["record"])
	if engine.world == null or engine.is_ended() or engine.turn < int(_number(data.get("turn"), 0.0)):
		return null
	return engine


## Removes [param slot]. Returns true when a save was there.
func delete(slot: String = AUTOSAVE) -> bool:
	var path := path_for(slot)
	if FileAccess.file_exists(path + ".tmp"):
		DirAccess.remove_absolute(path + ".tmp")
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK


## "just now", "5 min ago", "3 h ago", "yesterday", "4 days ago", then the
## date ("2026-09-21", UTC).
static func relative_time(saved_at: int, now: int) -> String:
	var seconds := now - saved_at
	if saved_at <= 0:
		return ""
	if seconds < 60:
		return "just now"
	if seconds < 3600:
		return "%d min ago" % floori(seconds / 60.0)
	if seconds < 86400:
		return "%d h ago" % floori(seconds / 3600.0)
	if seconds < 2 * 86400:
		return "yesterday"
	if seconds < 7 * 86400:
		return "%d days ago" % floori(seconds / 86400.0)
	return Time.get_date_string_from_unix_time(saved_at)


static func _write(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	var ok := file.get_error() == OK
	file.close()
	return ok


static func _number(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		var number := float(value)
		return number if is_finite(number) else fallback
	return fallback


static func _text(value: Variant, fallback: String = "") -> String:
	return String(value) if value is String and not (value as String).is_empty() else fallback
