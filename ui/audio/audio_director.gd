class_name AudioDirector
extends Node
## Music and sound effects. Each hardware era has its own loop and the music
## crossfades when the era changes ([method set_era]); short effects play from
## a small pool of players so they can overlap ([method play_sfx]). Volumes
## follow GameSettings ("music_volume" and "sound_volume", 0..1, where 0
## mutes) and change as the player moves a slider.
##
##   var audio := AudioDirector.new()
##   add_child(audio)
##   audio.set_era(1)
##   audio.play_sfx("card_appear")
##   audio.play_event(entry, engine.player_role)   # in the event_logged handler
##
## (A lambda connected to an engine's own signal must not capture that engine
## in a local variable: the pair would keep each other alive.)
##
## Engine log entries map to effects through [method event_sfx]. A turn can
## log a dozen entries at once, so [method play_event] queues their effects
## and plays them a moment apart, the most important first. Effects that
## confirm or warn also vibrate phones (Haptics), even with the sound down.
##
## Headless runs use Godot's dummy audio driver: everything runs, nothing is
## heard. Browsers only allow sound after the first tap, click or key press
## (Godot resumes the page's audio then), so on the web nothing plays before
## that gesture and the music fades in right after it.

## An effect started (tests, debugging).
signal sfx_played(sfx_name: String)

const MUSIC_DIR := "res://assets/audio/music/"
const SFX_DIR := "res://assets/audio/sfx/"
## era -> loop file in MUSIC_DIR.
const MUSIC := {1: "era_1.ogg", 2: "era_2.ogg", 3: "era_3.ogg"}
## Effect names; each is SFX_DIR + name + ".ogg".
const SFX := ["card_appear", "swipe_left", "swipe_right", "option_select", "execute", "headline_ping", "alert",
	"era_upgrade", "goal_met", "goal_missed", "deal", "tap", "page_turn", "fallout"]
## Seconds for one loop to hand over to the next (equal-power crossfade).
const CROSSFADE_TIME := 1.8
## Effects that can sound at once; the oldest is cut when all are busy.
const VOICES := 6
const SILENT_DB := -80.0
## The same effect does not restart within this many seconds.
const REPEAT_GAP := 0.08
## Queued event effects play at least this far apart, at most MAX_QUEUED waiting.
const EVENT_SPACING := 0.35
const MAX_QUEUED := 3
## Which queued event effect goes first (higher first; unlisted 0).
const EVENT_PRIORITY := {
	"alert": 6, "fallout": 5, "era_upgrade": 5, "goal_missed": 4, "goal_met": 4, "deal": 3, "headline_ping": 1,
}
## Effects that also vibrate, and how (Haptics kinds).
const HAPTICS := {
	"execute": "confirm", "alert": "alert", "fallout": "alert", "era_upgrade": "era", "goal_met": "confirm",
	"goal_missed": "select", "deal": "confirm",
}
## Random pitch spread for effects heard many times a turn, so repeats do
## not sound mechanical.
const PITCH_SPREAD := {"tap": 0.04, "swipe_left": 0.05, "swipe_right": 0.05, "option_select": 0.03, "page_turn": 0.06}

## The era whose loop is playing or fading in (0 before the first set_era).
var era := 0
var enabled := true
## True on the web until the first tap, click or key press.
var awaiting_gesture := false

var _settings: GameSettings
## era -> AudioStreamPlayer, created when the era first plays.
var _music := {}
## era -> crossfade weight 0..1.
var _weights := {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _streams := {}
## effect -> Time.get_ticks_msec() when it last started.
var _last_played := {}
var _queue: Array[String] = []
var _queue_wait := 0.0


func _ready() -> void:
	# Fades and queued effects carry on while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	awaiting_gesture = OS.has_feature("web")
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "Effect%d" % i
		add_child(player)
		_voices.append(player)
	if _settings == null:
		bind_settings(GameSettings.instance())


## Follows [param settings] for the volumes instead of the shared instance
## (tests use an in-memory one).
func bind_settings(settings: GameSettings) -> void:
	if _settings != null and _settings.changed.is_connected(_on_setting_changed):
		_settings.changed.disconnect(_on_setting_changed)
	_settings = settings
	if _settings != null:
		_settings.changed.connect(_on_setting_changed)
	_apply_volumes()


## Crossfades to [param era_number]'s loop (1-3) over CROSSFADE_TIME seconds.
## The first call fades the music in.
func set_era(era_number: int) -> void:
	era = clampi(era_number, 1, 3)


## Turns all sound on or off. Off stops the music and every effect at once
## and drops queued ones; on fades the current era's loop back in.
func set_enabled(on: bool) -> void:
	if enabled == on:
		return
	enabled = on
	if on:
		return
	_queue.clear()
	for player in _voices:
		player.stop()
	for key in _music:
		(_music[key] as AudioStreamPlayer).stop()
		_weights[key] = 0.0


## Plays effect [param sfx_name] (one of SFX) at once and returns true when it
## started. Unknown or empty names are ignored, an effect does not restart
## within REPEAT_GAP, and its vibration (HAPTICS) runs even when the sound
## is down.
func play_sfx(sfx_name: String) -> bool:
	if not enabled or not SFX.has(sfx_name) or _voices.is_empty():
		return false
	var now := Time.get_ticks_msec()
	if _last_played.has(sfx_name) and now - int(_last_played[sfx_name]) < int(REPEAT_GAP * 1000.0):
		return false
	_last_played[sfx_name] = now
	Haptics.pulse(String(HAPTICS.get(sfx_name, "")))
	var volume := sound_volume()
	if awaiting_gesture or volume <= 0.0:
		return false
	var stream := _load(SFX_DIR + sfx_name + ".ogg")
	if stream == null:
		return false
	var player := _free_voice()
	player.stream = stream
	player.volume_db = volume_to_db(volume)
	var spread := float(PITCH_SPREAD.get(sfx_name, 0.0))
	player.pitch_scale = 1.0 + randf_range(-spread, spread) if spread > 0.0 else 1.0
	player.play()
	sfx_played.emit(sfx_name)
	return true


## Queues the effect for engine log entry [param entry] ([method event_sfx])
## and returns its name ("" when the entry makes no sound).
## [param player_role] is the human deciding now (retaliation against them pings).
func play_event(entry: Dictionary, player_role: String = "") -> String:
	var sfx_name := event_sfx(entry, player_role)
	if sfx_name != "":
		queue_sfx(sfx_name)
	return sfx_name


## Queues [param sfx_name] to play after the effects already waiting: the
## queue keeps one of each, ordered by EVENT_PRIORITY, at most MAX_QUEUED,
## and plays them EVENT_SPACING seconds apart.
func queue_sfx(sfx_name: String) -> void:
	if not enabled or not SFX.has(sfx_name) or _queue.has(sfx_name):
		return
	var priority := int(EVENT_PRIORITY.get(sfx_name, 0))
	var index := _queue.size()
	for i in _queue.size():
		if int(EVENT_PRIORITY.get(_queue[i], 0)) < priority:
			index = i
			break
	_queue.insert(index, sfx_name)
	if _queue.size() > MAX_QUEUED:
		_queue.resize(MAX_QUEUED)


## Effects waiting in the queue, next first.
func queued() -> Array[String]:
	return _queue.duplicate()


## The effect for an engine log entry, or "" for the many that make no sound
## (rival and player moves, crisis answers, warnings, system notes):
##   GOAL met -> goal_met, missed -> goal_missed
##   THRESHOLD in the critical band (2), imminent containment failure or a
##     near miss -> alert
##   DILEMMA that broke after two deferrals (fallout) -> fallout
##   DEAL -> deal
##   EMERGENCE, PARADIGM, MILESTONE, CRISIS (a crisis forced onto a desk) -> headline_ping
##   COLLAPSE of a human player's faction -> alert; any other COLLAPSE or
##     re-emergence -> headline_ping
##   ENDGAME after a catastrophe -> alert; the final end-state -> headline_ping
##   RETALIATION against [param player_role] -> headline_ping
## ERA entries make no sound here: the dashboard plays "era_upgrade" when the
## system upgrade starts, after the front page.
static func event_sfx(entry: Dictionary, player_role: String = "") -> String:
	match String(entry.get("category", "")):
		"GOAL":
			var status := String(entry.get("status", ""))
			if status == EraGoals.MET:
				return "goal_met"
			if status == EraGoals.FAILED:
				return "goal_missed"
		"THRESHOLD":
			if int(entry.get("band", 0)) >= 2 or bool(entry.get("imminent", false)) or entry.has("near_miss"):
				return "alert"
		"DILEMMA":
			if bool(entry.get("fallout", false)):
				return "fallout"
		"DEAL":
			return "deal"
		"EMERGENCE", "PARADIGM", "MILESTONE", "CRISIS":
			return "headline_ping"
		"COLLAPSE":
			return "alert" if bool(entry.get("player", false)) else "headline_ping"
		"ENDGAME":
			return "alert" if entry.has("catastrophe") else "headline_ping"
		"RETALIATION":
			if player_role != "" and String(entry.get("target", "")) == player_role:
				return "headline_ping"
	return ""


## Linear volume (0..1) in decibels; 0 is silent (SILENT_DB).
static func volume_to_db(linear: float) -> float:
	if linear <= 0.0001:
		return SILENT_DB
	return maxf(linear_to_db(minf(linear, 1.0)), SILENT_DB)


## The player's music volume, 0..1.
func music_volume() -> float:
	return _setting("music_volume", 0.6)


## The player's effects volume, 0..1.
func sound_volume() -> float:
	return _setting("sound_volume", 0.8)


## The loop player for [param era_number], or null before that era first played.
func get_music_player(era_number: int) -> AudioStreamPlayer:
	return _music.get(era_number)


## The crossfade weight (0..1) of [param era_number]'s loop.
func get_music_weight(era_number: int) -> float:
	return float(_weights.get(era_number, 0.0))


func _process(delta: float) -> void:
	_update_music(delta)
	_queue_wait = maxf(_queue_wait - delta, 0.0)
	if _queue_wait <= 0.0 and not _queue.is_empty():
		play_sfx(_queue.pop_front())
		_queue_wait = EVENT_SPACING


func _input(event: InputEvent) -> void:
	if not awaiting_gesture:
		return
	if (event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey) and event.is_pressed():
		awaiting_gesture = false


## Moves every loop's weight toward 1 (the current era) or 0 (the others)
## and sets its volume on an equal-power curve; silent loops stop.
func _update_music(delta: float) -> void:
	var audible := enabled and not awaiting_gesture and music_volume() > 0.0 and era > 0
	var step := delta / CROSSFADE_TIME
	for era_number in MUSIC:
		var target := 1.0 if audible and era_number == era else 0.0
		var weight := move_toward(float(_weights.get(era_number, 0.0)), target, step)
		_weights[era_number] = weight
		var player := _music_player(era_number, weight > 0.0)
		if player == null:
			continue
		if weight <= 0.0:
			if player.playing:
				player.stop()
			continue
		player.volume_db = volume_to_db(music_volume() * sin(weight * PI / 2.0))
		if not player.playing:
			player.play()


func _music_player(era_number: int, create: bool) -> AudioStreamPlayer:
	if _music.has(era_number) or not create:
		return _music.get(era_number)
	var stream := _load(MUSIC_DIR + String(MUSIC[era_number]))
	if stream == null:
		return null
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	var player := AudioStreamPlayer.new()
	player.name = "Music%d" % era_number
	player.stream = stream
	player.volume_db = SILENT_DB
	add_child(player)
	_music[era_number] = player
	return player


## A voice that is not playing, else the one after the last used (the oldest).
func _free_voice() -> AudioStreamPlayer:
	for i in VOICES:
		var index := (_next_voice + i) % VOICES
		if not _voices[index].playing:
			_next_voice = (index + 1) % VOICES
			return _voices[index]
	var oldest := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	return oldest


func _load(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path) as AudioStream if ResourceLoader.exists(path) else null
	return _streams[path]


func _setting(key: String, fallback: float) -> float:
	var value: Variant = _settings.get_value(key) if _settings != null else fallback
	var number := float(value) if (value is float or value is int) else fallback
	return clampf(number, 0.0, 1.0) if is_finite(number) else fallback


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "music_volume" or key == "sound_volume":
		_apply_volumes()


## Applies the volumes at once: playing loops keep their crossfade weight,
## playing effects take the new effects volume.
func _apply_volumes() -> void:
	for era_number in _music:
		var player: AudioStreamPlayer = _music[era_number]
		player.volume_db = volume_to_db(music_volume() * sin(float(_weights.get(era_number, 0.0)) * PI / 2.0))
	var effects_db := volume_to_db(sound_volume())
	for player in _voices:
		if player.playing:
			player.volume_db = effects_db
