extends "res://tests/framework/test_case.gd"
## Sound: the synthesized assets (present, loadable, looping, within budget,
## all renderable by tools/make_audio.sh) and the AudioDirector (era
## crossfades, the effect pool, volumes from GameSettings, the web gesture
## gate, the event queue and the log-entry mapping). Runs on Godot's dummy
## audio driver: everything plays, nothing is heard.

const MUSIC_MAX_BYTES := 250 * 1024
const SFX_MAX_BYTES := 20 * 1024
const TOTAL_MAX_BYTES := 1536 * 1024

var settings: GameSettings
var audio: AudioDirector
var pulses: Array = []


func before_each() -> void:
	settings = GameSettings.new()
	settings.path = ""
	GameSettings.use(settings)
	pulses.clear()
	Haptics.vibrate_func = func(duration_ms: int, amplitude: float) -> void: pulses.append([duration_ms, amplitude])
	Haptics.touch_func = func() -> bool: return true
	audio = AudioDirector.new()
	tree.root.add_child(audio)
	await tree.process_frame


func after_each() -> void:
	# Stop every player so the mixer releases their streams before the next test.
	audio.set_enabled(false)
	audio.queue_free()
	Haptics.vibrate_func = Callable()
	Haptics.touch_func = Callable()
	GameSettings.use(null)
	await wait_seconds(0.05)


func _music_path(era_number: int) -> String:
	return AudioDirector.MUSIC_DIR + String(AudioDirector.MUSIC[era_number])


func _sfx_path(sfx_name: String) -> String:
	return AudioDirector.SFX_DIR + sfx_name + ".ogg"


func _bytes(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	return int(file.get_length()) if file != null else 0


# --- Assets ---------------------------------------------------------------------------

func test_every_sound_exists_and_loads_as_ogg_vorbis() -> void:
	for era_number in [1, 2, 3]:
		var stream := load(_music_path(era_number)) as AudioStreamOggVorbis
		assert_not_null(stream, "era %d loop is Ogg Vorbis" % era_number)
		if stream != null:
			assert_true(stream.loop, "era %d loop is imported looping" % era_number)
			assert_between(stream.get_length(), 20.0, 30.0, "era %d loop length" % era_number)
	var expected := ["card_appear", "swipe_left", "swipe_right", "option_select", "execute", "headline_ping", "alert",
		"era_upgrade", "goal_met", "goal_missed", "deal", "tap", "page_turn", "fallout"]
	for sfx_name in expected:
		assert_has(AudioDirector.SFX, sfx_name)
	for sfx_name in AudioDirector.SFX:
		var stream := load(_sfx_path(sfx_name)) as AudioStreamOggVorbis
		assert_not_null(stream, sfx_name + " is Ogg Vorbis")
		if stream != null:
			assert_false(stream.loop, sfx_name + " plays once")
			var longest := 1.7 if sfx_name == "era_upgrade" else 1.0
			assert_between(stream.get_length(), 0.05, longest, sfx_name + " length")


func test_sounds_fit_the_size_budget() -> void:
	var total := 0
	for era_number in [1, 2, 3]:
		var size := _bytes(_music_path(era_number))
		assert_between(size, 1024, MUSIC_MAX_BYTES, "era %d loop bytes" % era_number)
		total += size
	for sfx_name in AudioDirector.SFX:
		var size := _bytes(_sfx_path(sfx_name))
		assert_between(size, 512, SFX_MAX_BYTES, sfx_name + " bytes")
		total += size
	assert_lt(total, TOTAL_MAX_BYTES, "all audio under 1.5 MB")


func test_the_generator_renders_every_sound() -> void:
	var script := FileAccess.get_file_as_string("res://tools/make_audio.sh")
	assert_string_contains(script, "MUSIC=(era_1 era_2 era_3)")
	for era_number in [1, 2, 3]:
		assert_string_contains(script, "music_era_%d() {" % era_number)
	for sfx_name in AudioDirector.SFX:
		assert_string_contains(script, "sfx_%s() {" % sfx_name)
		assert_string_contains(script.get_slice("SFX=(", 1).get_slice(")", 0), sfx_name, "listed in SFX: " + sfx_name)


# --- Music ----------------------------------------------------------------------------

func test_music_crossfades_between_eras() -> void:
	assert_null(audio.get_music_player(1), "no music before an era is set")
	audio.set_era(1)
	audio._process(AudioDirector.CROSSFADE_TIME)
	var first := audio.get_music_player(1)
	assert_not_null(first)
	assert_true(first.playing, "era I loop plays")
	assert_almost_eq(audio.get_music_weight(1), 1.0, 0.001)
	assert_almost_eq(first.volume_db, linear_to_db(0.6), 0.01, "full weight at the default music volume")
	assert_true((first.stream as AudioStreamOggVorbis).loop)

	audio.set_era(2)
	audio._process(AudioDirector.CROSSFADE_TIME * 0.5)
	var second := audio.get_music_player(2)
	assert_true(first.playing and second.playing, "both loops sound during the crossfade")
	assert_almost_eq(audio.get_music_weight(1), 0.5, 0.01)
	assert_almost_eq(audio.get_music_weight(2), 0.5, 0.01)
	var equal_power := linear_to_db(0.6 * sin(PI / 4.0))
	assert_almost_eq(first.volume_db, equal_power, 0.05, "equal-power midpoint")
	assert_almost_eq(second.volume_db, equal_power, 0.05)

	# A new era mid-fade: the fading loops carry on from where they are.
	audio.set_era(3)
	audio._process(AudioDirector.CROSSFADE_TIME * 0.25)
	assert_almost_eq(audio.get_music_weight(2), 0.25, 0.01, "era II turns back")
	assert_almost_eq(audio.get_music_weight(1), 0.25, 0.01, "era I keeps fading")
	assert_almost_eq(audio.get_music_weight(3), 0.25, 0.01, "era III fades in")
	audio._process(AudioDirector.CROSSFADE_TIME)
	assert_false(first.playing, "silent loops stop")
	assert_false(second.playing)
	assert_true(audio.get_music_player(3).playing)
	assert_almost_eq(audio.get_music_weight(3), 1.0, 0.001)


func test_music_follows_the_music_volume() -> void:
	audio.set_era(2)
	audio._process(AudioDirector.CROSSFADE_TIME)
	var player := audio.get_music_player(2)
	settings.set_value("music_volume", 0.25)
	assert_almost_eq(player.volume_db, linear_to_db(0.25), 0.01, "a slider move applies at once")
	settings.set_value("music_volume", 0.0)
	assert_eq(player.volume_db, AudioDirector.SILENT_DB, "0 mutes")
	audio._process(AudioDirector.CROSSFADE_TIME)
	assert_false(player.playing, "muted music stops")
	settings.set_value("music_volume", 1.0)
	audio._process(AudioDirector.CROSSFADE_TIME)
	assert_true(player.playing, "and comes back")
	assert_almost_eq(player.volume_db, 0.0, 0.01)
	assert_eq(AudioDirector.volume_to_db(0.0), AudioDirector.SILENT_DB)
	assert_almost_eq(AudioDirector.volume_to_db(0.5), -6.02, 0.01)
	assert_almost_eq(AudioDirector.volume_to_db(3.0), 0.0, 0.001, "clamped at full volume")


func test_music_plays_for_real_frames_without_errors() -> void:
	audio.set_era(1)
	await wait_seconds(0.4)
	assert_true(audio.get_music_player(1).playing, "the node's own process starts the music")
	assert_between(audio.get_music_weight(1), 0.05, 0.6, "fading in")
	audio.set_era(3)
	await wait_seconds(0.3)
	assert_true(audio.get_music_player(3).playing)
	assert_gt(audio.get_music_player(1).get_playback_position(), 0.2, "the loop advances on the dummy driver")


# --- Effects --------------------------------------------------------------------------

func test_effects_play_from_a_pool_and_ignore_unknown_names() -> void:
	var played: Array[String] = []
	audio.sfx_played.connect(func(sfx_name: String): played.append(sfx_name))
	assert_true(audio.play_sfx("tap"))
	assert_eq(played, ["tap"] as Array[String])
	assert_false(audio.play_sfx(""), "empty names are ignored")
	assert_false(audio.play_sfx("kazoo"), "unknown names are ignored")
	assert_false(audio.play_sfx("tap"), "no restart within REPEAT_GAP")
	for sfx_name in ["card_appear", "swipe_left", "swipe_right", "option_select", "execute", "alert", "deal"]:
		assert_true(audio.play_sfx(sfx_name), sfx_name)
	var busy := 0
	for child in audio.get_children():
		if child is AudioStreamPlayer and String(child.name).begins_with("Effect") and (child as AudioStreamPlayer).playing:
			busy += 1
	assert_eq(busy, AudioDirector.VOICES, "eight effects share the six voices; the oldest are cut")
	assert_eq(played.size(), 8)


func test_effects_follow_the_sound_volume() -> void:
	settings.set_value("sound_volume", 0.5)
	assert_true(audio.play_sfx("headline_ping"))
	var voice: AudioStreamPlayer = null
	for child in audio.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).playing and (child as AudioStreamPlayer).stream != null \
				and (child as AudioStreamPlayer).stream.resource_path.ends_with("headline_ping.ogg"):
			voice = child
	assert_not_null(voice)
	if voice != null:
		assert_almost_eq(voice.volume_db, -6.02, 0.01)
		settings.set_value("sound_volume", 0.25)
		assert_almost_eq(voice.volume_db, -12.04, 0.01, "playing effects follow the slider")
	settings.set_value("sound_volume", 0.0)
	assert_false(audio.play_sfx("goal_met"), "0 mutes the effects")


func test_effects_that_confirm_or_warn_vibrate_even_when_muted() -> void:
	settings.set_value("sound_volume", 0.0)
	audio.play_sfx("alert")
	audio.play_sfx("era_upgrade")
	audio.play_sfx("tap")
	assert_eq(pulses, [[Haptics.duration_ms("alert"), 1.0], [Haptics.duration_ms("era"), 0.8]], "alert and era pulses; taps stay still")
	settings.set_value("vibration", false)
	audio.play_sfx("execute")
	assert_eq(pulses.size(), 2, "the vibration setting turns them off")


func test_disabling_stops_everything() -> void:
	audio.set_era(1)
	audio._process(AudioDirector.CROSSFADE_TIME)
	audio.play_sfx("alert")
	audio.queue_sfx("deal")
	audio.set_enabled(false)
	assert_false(audio.get_music_player(1).playing)
	assert_eq(audio.queued().size(), 0, "queued effects dropped")
	assert_false(audio.play_sfx("tap"))
	audio._process(AudioDirector.CROSSFADE_TIME)
	assert_false(audio.get_music_player(1).playing, "stays quiet")
	audio.set_enabled(true)
	audio._process(AudioDirector.CROSSFADE_TIME * 0.5)
	assert_true(audio.get_music_player(1).playing, "fades back in")
	assert_almost_eq(audio.get_music_weight(1), 0.5, 0.01)


func test_web_audio_waits_for_the_first_gesture() -> void:
	audio.awaiting_gesture = true
	audio.set_era(1)
	audio._process(AudioDirector.CROSSFADE_TIME)
	assert_null(audio.get_music_player(1), "no music before the gesture")
	assert_false(audio.play_sfx("card_appear"), "no effects before the gesture")
	var motion := InputEventMouseMotion.new()
	audio._input(motion)
	assert_true(audio.awaiting_gesture, "moving the mouse is not a gesture")
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	audio._input(tap)
	assert_false(audio.awaiting_gesture)
	audio._process(AudioDirector.CROSSFADE_TIME * 0.5)
	assert_true(audio.get_music_player(1).playing, "the music fades in after the tap")
	assert_almost_eq(audio.get_music_weight(1), 0.5, 0.01)


# --- Events ---------------------------------------------------------------------------

func _entry(category: String, extra: Dictionary = {}) -> Dictionary:
	var entry := {"turn": 12, "year": 2032.0, "category": category, "severity": "INFO", "faction": "", "text": category}
	entry.merge(extra, true)
	return entry


func test_event_sfx_maps_every_log_category() -> void:
	var cases := [
		[_entry("GOAL", {"status": EraGoals.MET}), "goal_met"],
		[_entry("GOAL", {"status": EraGoals.FAILED}), "goal_missed"],
		[_entry("GOAL", {"status": EraGoals.ACTIVE}), ""],
		[_entry("THRESHOLD", {"metric": "alignment_drift", "band": 2, "value": 81.0}), "alert"],
		[_entry("THRESHOLD", {"metric": "alignment_drift", "band": 2, "imminent": true}), "alert"],
		[_entry("THRESHOLD", {"near_miss": "AUTONOMOUS_WORLD_WAR"}), "alert"],
		[_entry("THRESHOLD", {"metric": "epistemic_trust", "band": 1, "value": 30.0}), ""],
		[_entry("THRESHOLD", {"metric": "epistemic_trust", "band": 0, "value": 50.0}), ""],
		[_entry("DILEMMA", {"option": "A", "deferred": false}), ""],
		[_entry("DILEMMA", {"option": DilemmaDeck.DEFER_ID, "deferred": true, "fallout": false}), ""],
		[_entry("DILEMMA", {"option": DilemmaDeck.DEFER_ID, "deferred": true, "fallout": true}), "fallout"],
		[_entry("DEAL", {"partner": "ASI"}), "deal"],
		[_entry("EMERGENCE", {"capability": "X"}), "headline_ping"],
		[_entry("PARADIGM", {"shift": "OPTICAL_COMPUTING"}), "headline_ping"],
		[_entry("MILESTONE", {"milestone": "AGI"}), "headline_ping"],
		[_entry("CRISIS", {"injected": "CHIP_EMBARGO"}), "headline_ping"],
		[_entry("COLLAPSE", {"code": "BANKRUPTCY"}), "headline_ping"],
		[_entry("COLLAPSE", {"code": "REEMERGED"}), "headline_ping"],
		[_entry("COLLAPSE", {"code": "BANKRUPTCY", "player": true}), "alert"],
		[_entry("ENDGAME", {"catastrophe": "AUTONOMOUS_WORLD_WAR"}), "alert"],
		[_entry("ENDGAME", {"outcome": "X", "verdict": "VICTORY"}), "headline_ping"],
		[_entry("ACTION", {"faction": "ASI", "action": "X"}), ""],
		[_entry("ACTION", {"faction": "CEO", "action": "X"}), ""],
		[_entry("ERA", {"era": 2}), ""],
		[_entry("SYSTEM"), ""],
		[_entry("SOMETHING_NEW", {"severity": "CRITICAL"}), ""],
		[{}, ""],
	]
	for item in cases:
		var entry: Dictionary = item[0]
		assert_eq(AudioDirector.event_sfx(entry, "CEO"), String(item[1]), "%s %s" % [entry.get("category", "?"), entry])
	var retaliation := _entry("RETALIATION", {"faction": "ASI", "target": "CEO"})
	assert_eq(AudioDirector.event_sfx(retaliation, "CEO"), "headline_ping", "a hit on the player pings")
	assert_eq(AudioDirector.event_sfx(retaliation, "GOVERNANCE_COUNCIL"), "", "a feud between others is quiet")
	assert_eq(AudioDirector.event_sfx(retaliation), "")


func test_event_effects_queue_by_priority_and_play_apart() -> void:
	var played: Array[String] = []
	audio.sfx_played.connect(func(sfx_name: String): played.append(sfx_name))
	assert_eq(audio.play_event(_entry("PARADIGM")), "headline_ping")
	audio.play_event(_entry("THRESHOLD", {"band": 2}))
	audio.play_event(_entry("GOAL", {"status": EraGoals.MET}))
	audio.play_event(_entry("DEAL"))
	audio.play_event(_entry("THRESHOLD", {"band": 2}))
	assert_eq(audio.play_event(_entry("ACTION")), "")
	assert_eq(audio.queued(), ["alert", "goal_met", "deal"] as Array[String], "one of each, most important first, three at most")
	audio._process(0.0)
	assert_eq(played, ["alert"] as Array[String])
	audio._process(AudioDirector.EVENT_SPACING * 0.5)
	assert_eq(played.size(), 1, "spaced out")
	audio._process(AudioDirector.EVENT_SPACING * 0.6)
	assert_eq(played, ["alert", "goal_met"] as Array[String])
	audio._process(AudioDirector.EVENT_SPACING)
	assert_eq(played, ["alert", "goal_met", "deal"] as Array[String])
	assert_eq(audio.queued().size(), 0)


func test_a_whole_campaign_of_events_plays_without_errors() -> void:
	var engine := SimulationEngine.new()
	var names := {}
	var role := SimConstants.CITIZEN
	engine.event_logged.connect(func(entry: Dictionary):
		var sfx_name := audio.play_event(entry, role)
		if sfx_name != "":
			names[sfx_name] = true)
	engine.start_campaign(role, 2076, {"autoplay": true})
	engine.run_headless()
	assert_true(engine.is_ended())
	assert_true(names.has("headline_ping"), "a century has news")
	for sfx_name in names:
		assert_has(AudioDirector.SFX, sfx_name)
	assert_between(audio.queued().size(), 1, AudioDirector.MAX_QUEUED, "a burst of entries leaves a short queue")
	await wait_seconds(AudioDirector.EVENT_SPACING * AudioDirector.MAX_QUEUED + 0.2)
	assert_eq(audio.queued().size(), 0, "the queue drains on its own")
