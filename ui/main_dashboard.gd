extends Control
## SYNAPSE-2076 main dashboard (PRD section 8): the 2D Cyber-Telemetry HUD with
## embedded 3D SubViewports. Owns the SimulationEngine and the LLMService and
## binds them to the widgets purely through signals.
##
## When launched headless as the main scene (`godot --headless --path .`), it
## plays one autoplay campaign, prints the result and quits; pass
## `-- --role=CEO --seed=42` to choose the perspective.

const SPECTATE_INTERVALS := [0.8, 0.4, 0.15]
const NEXT_TURN_DELAY := 0.35
const FEED_LIMIT := 350

var engine: SimulationEngine
var llm: LLMService
var spectate := false
var _speed_index := 0
var _paused := false
var _pending_option := ""
var _meters := {}
var _feed_entries: Array[Dictionary] = []
var _spectate_timer: Timer
var _next_turn_timer: Timer

@onready var _year_label: Label = %YearLabel
@onready var _role_label: Label = %RoleLabel
@onready var _phase_label: Label = %PhaseLabel
@onready var _badge: LLMStatusBadge = %LLMStatusBadge
@onready var _spectate_controls: HBoxContainer = %SpectateControls
@onready var _pause_button: Button = %PauseButton
@onready var _speed_button: Button = %SpeedButton
@onready var _menu_button: Button = %MenuButton
@onready var _indices_label: RichTextLabel = %IndicesLabel
@onready var _globe_button: Button = %GlobeButton
@onready var _lattice_button: Button = %LatticeButton
@onready var _globe_container: SubViewportContainer = %GlobeContainer
@onready var _lattice_container: SubViewportContainer = %LatticeContainer
@onready var _globe: GlobeViewport = %Globe
@onready var _lattice: NeuralLattice = %Lattice
@onready var _viewport_caption: RichTextLabel = %ViewportCaption
@onready var _directive_panel: DirectivePanel = %DirectivePanel
@onready var _headline: RichTextLabel = %FeedHeadline
@onready var _feed: RichTextLabel = %EventFeed
@onready var _dilemma: DilemmaDialog = %DilemmaDialog
@onready var _debrief: EndgameDebrief = %EndgameDebrief
@onready var _settings: LLMSettingsDialog = %LLMSettingsDialog
@onready var _role_select: RoleSelect = %RoleSelect


func _ready() -> void:
	theme = CyberTheme.get_theme()
	for node in find_children("*Meter", "", true, false):
		if node is MeterBar:
			_meters[(node as MeterBar).metric_key] = node

	llm = LLMService.new()
	llm.name = "LLMService"
	add_child(llm)
	llm.load_configuration()
	_badge.bind(llm)
	_badge.settings_requested.connect(_open_llm_settings)
	llm.llm_status_changed.connect(func(_online: bool, _provider: String): _update_llm_hint())

	_spectate_timer = Timer.new()
	_spectate_timer.timeout.connect(_on_spectate_tick)
	add_child(_spectate_timer)
	_next_turn_timer = Timer.new()
	_next_turn_timer.one_shot = true
	_next_turn_timer.timeout.connect(_begin_next_turn)
	add_child(_next_turn_timer)

	_dilemma.option_chosen.connect(_on_dilemma_option_chosen)
	_directive_panel.execute_requested.connect(_on_execute_requested)
	_directive_panel.review_crisis_requested.connect(_reopen_crisis)
	_debrief.new_campaign_requested.connect(_show_role_select)
	_settings.closed.connect(func(): _badge.refresh())
	_role_select.start_requested.connect(start_campaign)
	_role_select.llm_settings_requested.connect(_open_llm_settings)
	_globe_button.pressed.connect(func(): show_view("globe"))
	_lattice_button.pressed.connect(func(): show_view("lattice"))
	_pause_button.pressed.connect(_toggle_pause)
	_speed_button.pressed.connect(_cycle_speed)
	_menu_button.pressed.connect(_show_role_select)
	show_view("globe")
	_spectate_controls.visible = false

	if _should_autorun_headless():
		_run_headless_autoplay.call_deferred()
		return
	if bool(ProjectSettings.get_setting("synapse/llm/probe_on_start", true)) and llm.should_auto_probe():
		llm.probe_connection()
	_show_role_select()


## Starts a campaign from the perspective of [param role].
func start_campaign(role: String, seed_value: int, spectate_mode: bool = false) -> void:
	_spectate_timer.stop()
	_next_turn_timer.stop()
	if engine != null:
		engine.set_decision_provider(null)
	spectate = spectate_mode
	_paused = false
	_pending_option = ""
	engine = SimulationEngine.new()
	engine.event_logged.connect(_on_event_logged)
	engine.phase_changed.connect(_on_phase_changed)
	engine.actor_decisions_requested.connect(_on_actor_decisions_requested)
	engine.player_input_required.connect(_on_player_input_required)
	engine.telemetry_updated.connect(_on_telemetry_updated)
	engine.turn_completed.connect(_on_turn_completed)
	engine.campaign_ended.connect(_on_campaign_ended)
	engine.set_decision_provider(llm)
	_feed_entries.clear()
	_feed.clear()
	_headline.text = ""
	for key in _meters:
		(_meters[key] as MeterBar).history = PackedFloat32Array()
	engine.start_campaign(role, seed_value, {
		"autoplay": spectate_mode,
		"max_player_directives": int(ProjectSettings.get_setting("synapse/simulation/max_player_directives", 2)),
		"total_turns": int(ProjectSettings.get_setting("synapse/simulation/total_turns", SimConstants.TOTAL_TURNS)),
	})
	_role_select.visible = false
	_debrief.visible = false
	_dilemma.close()
	_role_label.text = "ROLE: %s%s" % [SimConstants.ROLE_INFO[role]["header"], "  [SPECTATE]" if spectate else ""]
	_spectate_controls.visible = spectate
	_directive_panel.set_interactive(false)
	_refresh_telemetry(engine.get_snapshot(), true)
	engine.advance()
	if spectate:
		_spectate_timer.start(SPECTATE_INTERVALS[_speed_index])


func show_view(view: String) -> void:
	var globe := view == "globe"
	_globe_container.visible = globe
	_lattice_container.visible = not globe
	_globe_button.disabled = globe
	_lattice_button.disabled = not globe
	if globe:
		_viewport_caption.text = "[color=%s]GLOBE[/color] // node heat = compute & energy saturation · red rings = regional compute embargo (tension ≥ 60) · cable pulses = epistemic trust · drag to orbit, wheel to zoom" % CyberPalette.hex(CyberPalette.CYAN)
	else:
		_viewport_caption.text = "[color=%s]NEURAL LATTICE[/color] // depth = frontier capability · cyan→crimson + jitter = alignment drift · amber = emergent capabilities · surface = tensor loss landscape · drag to orbit" % CyberPalette.hex(CyberPalette.CYAN)


# --- Engine signal handlers ---------------------------------------------------------

func _on_event_logged(entry: Dictionary) -> void:
	_feed_entries.append(entry)
	if _feed_entries.size() > FEED_LIMIT:
		_feed_entries = _feed_entries.slice(_feed_entries.size() - FEED_LIMIT)
		_feed.clear()
		for old in _feed_entries:
			_feed.append_text(_format_entry(old) + "\n")
	else:
		_feed.append_text(_format_entry(entry) + "\n")
	var severity := String(entry.get("severity", "INFO"))
	if severity != "INFO" or _headline.text == "":
		_headline.text = "[color=%s]EVENT FEED & CRISIS LOG:[/color] [color=%s]\"%s\"[/color]" % [
			CyberPalette.hex(CyberPalette.TEXT_DIM), CyberPalette.hex(CyberPalette.severity_color(severity)),
			CyberPalette.escape_bbcode(String(entry.get("text", ""))).left(220)]


func _on_phase_changed(phase: int, _turn: int) -> void:
	var names := {
		SimulationEngine.Phase.IDLE: "STANDBY",
		SimulationEngine.Phase.WORLD_TICK: "PHYSICAL WORLD TICK",
		SimulationEngine.Phase.ACTOR_RESOLUTION: "AUTONOMOUS ACTOR RESOLUTION",
		SimulationEngine.Phase.PLAYER_ACTION: "PLAYER DILEMMA & ACTION" if not spectate else "AUTOPLAY ACTION",
		SimulationEngine.Phase.TELEMETRY: "TELEMETRY RECONCILIATION",
		SimulationEngine.Phase.ENDED: "CAMPAIGN COMPLETE",
	}
	_phase_label.text = "PHASE: " + String(names.get(phase, "?"))
	_update_header()


func _on_actor_decisions_requested(faction_ids: Array) -> void:
	if llm.is_online and not faction_ids.is_empty():
		_phase_label.text = "PHASE: AWAITING %d AUTONOMOUS ACTORS (LLM)" % faction_ids.size()


func _on_player_input_required(context: Dictionary) -> void:
	_refresh_telemetry(engine.get_snapshot(), false)
	if spectate:
		return
	_pending_option = ""
	_directive_panel.setup(context)
	_directive_panel.set_interactive(true)
	_dilemma.present(context["dilemma"], context["resources"], engine.player_role)


func _on_telemetry_updated(snapshot: Dictionary) -> void:
	_refresh_telemetry(snapshot, true)


func _on_turn_completed(_turn: int, _snapshot: Dictionary) -> void:
	if not spectate:
		_next_turn_timer.start(NEXT_TURN_DELAY)


func _on_campaign_ended(result: Dictionary) -> void:
	_spectate_timer.stop()
	_next_turn_timer.stop()
	_directive_panel.set_interactive(false)
	_dilemma.close()
	_debrief.present(result)


# --- Player interaction ----------------------------------------------------------------

func _on_dilemma_option_chosen(option_id: String) -> void:
	_pending_option = option_id
	_directive_panel.set_crisis_choice(DilemmaDeck.find_option(engine.current_dilemma, option_id))
	_directive_panel.show_message("")


func _reopen_crisis() -> void:
	if engine != null and engine.is_awaiting_player():
		_dilemma.present(engine.current_dilemma, engine.get_player().resources, engine.player_role)


func _on_execute_requested(directives: Array) -> void:
	if engine == null or not engine.is_awaiting_player() or _pending_option == "":
		return
	var response := engine.submit_player_turn(directives, _pending_option)
	if not response["ok"]:
		_directive_panel.show_message("\n".join(response["errors"]))
		return
	_directive_panel.set_interactive(false)
	_directive_panel.set_crisis_status("[color=%s]DIRECTIVES EXECUTED[/color] - resolving turn..." % CyberPalette.hex(CyberPalette.CYAN))


func _begin_next_turn() -> void:
	if engine != null and not engine.is_ended() and engine.phase == SimulationEngine.Phase.IDLE:
		engine.advance()


func _on_spectate_tick() -> void:
	if engine == null or _paused or engine.is_ended() or engine.is_awaiting_actors():
		return
	engine.advance()


func _toggle_pause() -> void:
	_paused = not _paused
	_pause_button.text = "RESUME" if _paused else "PAUSE"


func _cycle_speed() -> void:
	_speed_index = (_speed_index + 1) % SPECTATE_INTERVALS.size()
	_speed_button.text = "SPEED x%d" % [1, 2, 4][_speed_index]
	if spectate:
		_spectate_timer.start(SPECTATE_INTERVALS[_speed_index])


func _show_role_select() -> void:
	_spectate_timer.stop()
	_next_turn_timer.stop()
	_debrief.visible = false
	_dilemma.close()
	_update_llm_hint()
	_role_select.visible = true


func _open_llm_settings() -> void:
	_settings.open(llm)


func _update_llm_hint() -> void:
	_role_select.set_llm_status(_badge.get_text())


# --- Telemetry rendering -----------------------------------------------------------------

func _refresh_telemetry(snapshot: Dictionary, record: bool) -> void:
	var metrics: Dictionary = snapshot.get("metrics", {})
	for key in _meters:
		(_meters[key] as MeterBar).set_value(float(metrics.get(key, 0.0)), record)
	_globe.update_from_snapshot(snapshot)
	_lattice.update_from_snapshot(snapshot)
	_indices_label.text = _format_indices(snapshot)
	if engine != null:
		_directive_panel.update_resources(engine.player_role, engine.get_player().resources)
	_update_header()


func _update_header() -> void:
	if engine == null:
		_year_label.text = "YEAR: 2026 (T:0/100)"
		return
	_year_label.text = "YEAR: %d (T:%d/%d)" % [int(floor(engine.get_year())), engine.turn, engine.total_turns]


func _format_indices(snapshot: Dictionary) -> String:
	var dim := CyberPalette.hex(CyberPalette.TEXT_DIM)
	var cyan := CyberPalette.hex(CyberPalette.CYAN)
	var indices: Dictionary = snapshot.get("indices", {})
	var tech: Dictionary = snapshot.get("tech", {})
	var grid: Dictionary = snapshot.get("compute", {})
	var lines: Array[String] = ["[color=%s]SECONDARY INDICES[/color]" % cyan]
	for key in WorldState.INDEX_KEYS:
		var value := float(indices.get(key, 0.0))
		var filled := int(round(value / 10.0))
		lines.append("[color=%s]%-14s[/color] %3d [color=%s]%s[/color][color=%s]%s[/color]" % [
			dim, UiFormat.metric_short(key), int(round(value)), cyan, "█".repeat(filled), dim, "░".repeat(10 - filled)])
	var era_names := {1: "SILICON & NUCLEAR", 2: "OPTICAL & SMR GRIDS", 3: "NEUROMORPHIC"}
	lines.append("")
	lines.append("[color=%s]FRONTIER COMPUTE[/color]  ERA %d: %s" % [cyan, int(snapshot.get("era", 1)), era_names.get(int(snapshot.get("era", 1)), "")])
	lines.append("[color=%s]Training FLOPs[/color] 10^%.2f  [color=%s]Capability[/color] %.0f" % [
		dim, float(tech.get("log_flops", 26.0)), dim, float(tech.get("capability_index", 0.0))])
	lines.append("[color=%s]Grid load[/color] %.0f/%.0f GW  [color=%s]throttle[/color] %.2f" % [
		dim, float(grid.get("power_demand_gw", 0.0)), float(grid.get("grid_capacity_gw", 0.0)), dim, float(grid.get("throttle", 1.0))])
	var agi_turn := int(tech.get("agi_turn", -1))
	lines.append("[color=%s]AGI milestone[/color] %s  [color=%s]Align. tax[/color] x%.2f" % [
		dim, ("CROSSED %d" % int(SimConstants.year_for_turn(agi_turn))) if agi_turn >= 0 else "PENDING",
		dim, float(tech.get("alignment_tax_multiplier", 1.0))])
	var shifts: Array = tech.get("unlocked_shifts", [])
	var shift_tags: Array[String] = []
	for shift_id in shifts:
		shift_tags.append(String(TechTreeManager.PARADIGM_SHIFTS[shift_id]["name"]).get_slice(" ", 0).to_upper())
	lines.append("[color=%s]Paradigms[/color] %s" % [dim, ", ".join(shift_tags) if not shift_tags.is_empty() else "none"])
	return "\n".join(lines)


func _format_entry(entry: Dictionary) -> String:
	var faction := String(entry.get("faction", ""))
	var tag := ""
	if faction != "":
		tag = "[color=%s][%s][/color] " % [CyberPalette.hex(CyberPalette.faction_color(faction)), faction.get_slice("_", 0)]
	var category := String(entry.get("category", ""))
	var severity_color := CyberPalette.severity_color(String(entry.get("severity", "INFO")))
	return "[color=%s]T%02d %d[/color] [color=%s]%-10s[/color] %s[color=%s]%s[/color]" % [
		CyberPalette.hex(CyberPalette.TEXT_DIM), int(entry.get("turn", 0)), int(float(entry.get("year", 2026.0))),
		CyberPalette.hex(CyberPalette.CYAN.darkened(0.25)), category, tag, CyberPalette.hex(severity_color),
		CyberPalette.escape_bbcode(String(entry.get("text", "")))]


# --- Headless autorun ------------------------------------------------------------------------

func _should_autorun_headless() -> bool:
	return DisplayServer.get_name() == "headless" and get_tree().current_scene == self \
		and bool(ProjectSettings.get_setting("synapse/headless/autorun_campaign", true))


func _run_headless_autoplay() -> void:
	var role := String(ProjectSettings.get_setting("synapse/headless/autorun_role", SimConstants.GOVERNANCE))
	var seed_value := int(ProjectSettings.get_setting("synapse/simulation/default_seed", 2076))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			role = arg.get_slice("=", 1)
		elif arg.begins_with("--seed="):
			seed_value = int(arg.get_slice("=", 1))
	var headless_engine := SimulationEngine.new()
	headless_engine.start_campaign(role, seed_value, {"autoplay": true})
	var result := headless_engine.run_headless()
	if result.is_empty():
		printerr("Headless campaign did not complete.")
		get_tree().quit(1)
		return
	print("SYNAPSE-2076 headless campaign :: %s, seed %d" % [SimConstants.role_title(role), seed_value])
	print("End-state %d: %s (%s) at T%d / %d" % [result["outcome"]["number"], result["outcome"]["name"],
		result["outcome"]["subtitle"], result["turn"], int(result["year"])])
	print("Verdict: %s (score %.0f)" % [result["verdict"]["verdict"], result["verdict"]["score"]])
	for key in WorldState.METRIC_KEYS:
		print("  %-22s %6.1f" % [key, float(result["final_values"][key])])
	get_tree().quit(0)
