extends Control
## SYNAPSE-2076 main dashboard (PRD section 8): the 2D Cyber-Telemetry HUD with
## embedded 3D SubViewports. Owns the SimulationEngine and the LLMService and
## binds them to the widgets purely through signals.
##
## Responsive: large landscape screens get the three-column desktop layout;
## phones, portrait tablets and small windows get the compact layout (see
## UiLayout): a vitals strip with the six metrics, one panel at a time behind
## WORLD / ACT / INTEL / LOG tabs, and phone-sized overlays.
##
## When launched headless as the main scene (`godot --headless --path .`), it
## plays one autoplay campaign, prints the result and quits; pass
## `-- --role=CEO --seed=42` to choose the perspective.

const SPECTATE_INTERVALS := [0.8, 0.4, 0.15]
const NEXT_TURN_DELAY := 0.35
const FEED_LIMIT := 350
const TABS := ["world", "act", "intel", "log"]
const TAB_LABELS := {"world": "WORLD", "act": "ACT", "intel": "INTEL", "log": "LOG"}

var engine: SimulationEngine
var llm: LLMService
var spectate := false
## True while the compact (phone) layout is active.
var compact := false
var active_tab := "act"
var _landscape := true
var _speed_index := 0
var _paused := false
var _pending_option := ""
var _meters := {}
var _vitals := {}
var _feed_entries: Array[Dictionary] = []
var _feed_follow := true
var _spectate_timer: Timer
var _next_turn_timer: Timer
var _vitals_grid: GridContainer
var _tab_bar: HBoxContainer
var _tab_buttons := {}

@onready var _margin: MarginContainer = $Margin
@onready var _layout: VBoxContainer = $Margin/Layout
@onready var _header_row: HBoxContainer = %HeaderRow
@onready var _title_label: Label = %Title
@onready var _year_label: Label = %YearLabel
@onready var _role_label: Label = %RoleLabel
@onready var _phase_label: Label = %PhaseLabel
@onready var _badge: LLMStatusBadge = %LLMStatusBadge
@onready var _spectate_controls: HBoxContainer = %SpectateControls
@onready var _pause_button: Button = %PauseButton
@onready var _speed_button: Button = %SpeedButton
@onready var _menu_button: Button = %MenuButton
@onready var _body: HBoxContainer = %Body
@onready var _telemetry_panel: PanelContainer = %TelemetryPanel
@onready var _center_panel: PanelContainer = %CenterPanel
@onready var _footer: PanelContainer = %Footer
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
@onready var _feed_scroll: ScrollContainer = %FeedScroll
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
	llm.import_page_url_settings()
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

	_build_compact_chrome()
	_bind_feed_scroll()
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
	get_tree().root.size_changed.connect(_on_window_resized)
	_on_window_resized()

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
	_feed_follow = true
	_headline.text = ""
	for meter in _meters.values() + _vitals.values():
		(meter as MeterBar).history = PackedFloat32Array()
	engine.start_campaign(role, seed_value, {
		"autoplay": spectate_mode,
		"max_player_directives": int(ProjectSettings.get_setting("synapse/simulation/max_player_directives", 2)),
		"total_turns": int(ProjectSettings.get_setting("synapse/simulation/total_turns", SimConstants.TOTAL_TURNS)),
	})
	_role_select.visible = false
	_debrief.visible = false
	_dilemma.close()
	_update_role_label()
	_spectate_controls.visible = spectate
	_directive_panel.set_interactive(false)
	show_tab("world" if spectate else "act")
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
		_viewport_caption.text = "[color=%s]GLOBE[/color] // node heat = compute & energy saturation · red rings = regional compute embargo (tension ≥ 60) · cable pulses = epistemic trust · drag to orbit, %s to zoom" % [
			CyberPalette.hex(CyberPalette.CYAN), "pinch" if compact else "wheel"]
	else:
		_viewport_caption.text = "[color=%s]NEURAL LATTICE[/color] // depth = frontier capability · cyan→crimson + jitter = alignment drift · amber = emergent capabilities · surface = tensor loss landscape · drag to orbit" % CyberPalette.hex(CyberPalette.CYAN)


# --- Responsive layout --------------------------------------------------------------

## Picks the layout for the current window. Headless runs (tests, autorun)
## keep the scene's desktop layout unless a test applies one explicitly.
func _on_window_resized() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_tree().root
	apply_layout(UiLayout.compute(Vector2(window.size), DisplayServer.screen_get_scale(),
		DisplayServer.is_touchscreen_available()))


## Applies a layout from [method UiLayout.compute]: the logical canvas size
## (so text keeps a readable physical size) and the compact or desktop mode.
func apply_layout(layout: Dictionary) -> void:
	var content_size: Vector2i = layout.get("content_size", UiLayout.DESKTOP_SIZE)
	var root := get_tree().root
	if root.content_scale_size != content_size:
		root.content_scale_size = content_size
	set_compact(bool(layout.get("compact", false)), bool(layout.get("landscape", true)))


func set_compact(enabled: bool, landscape: bool = false) -> void:
	compact = enabled
	_landscape = landscape
	_title_label.visible = not enabled
	_role_label.visible = not enabled
	_phase_label.visible = not enabled
	_header_row.add_theme_constant_override("separation", 10 if enabled else 24)
	for side in ["left", "right"]:
		_margin.add_theme_constant_override("margin_" + side, 6 if enabled else 10)
	for side in ["top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, 6 if enabled else 8)
	_layout.add_theme_constant_override("separation", 6 if enabled else 8)
	_vitals_grid.visible = enabled
	_vitals_grid.columns = 6 if landscape else 3
	_tab_bar.visible = enabled
	_telemetry_panel.custom_minimum_size = Vector2(0 if enabled else 350, 0)
	_directive_panel.custom_minimum_size = Vector2(0 if enabled else 380, 0)
	for panel in [_telemetry_panel, _directive_panel]:
		(panel as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL if enabled else Control.SIZE_FILL
	_footer.custom_minimum_size = Vector2(0, 0 if enabled else 168)
	_footer.size_flags_vertical = Control.SIZE_EXPAND_FILL if enabled else Control.SIZE_FILL
	# Touch screens scroll the feed by dragging, so text selection gives way.
	_feed.selection_enabled = not enabled
	_badge.set_compact(enabled)
	_directive_panel.set_compact(enabled)
	_dilemma.set_compact(enabled)
	_role_select.set_compact(enabled)
	_debrief.set_compact(enabled)
	_settings.set_compact(enabled)
	_pause_button.text = ("▶" if _paused else "II") if enabled else ("RESUME" if _paused else "PAUSE")
	_speed_button.text = ("x%d" if enabled else "SPEED x%d") % [1, 2, 4][_speed_index]
	_update_header()
	_update_role_label()
	_lattice_button.text = "LATTICE" if enabled else "NEURAL LATTICE"
	show_view("globe" if _globe_container.visible else "lattice")
	show_tab(active_tab)
	_update_llm_hint()


## Compact layout: shows one panel. Desktop: every panel stays visible.
func show_tab(tab: String) -> void:
	if not tab in TABS:
		return
	active_tab = tab
	if not compact:
		_body.visible = true
		_footer.visible = true
		for panel in [_telemetry_panel, _center_panel, _directive_panel]:
			(panel as Control).visible = true
		return
	_body.visible = tab != "log"
	_footer.visible = tab == "log"
	_telemetry_panel.visible = tab == "intel"
	_center_panel.visible = tab == "world"
	_directive_panel.visible = tab == "act"
	_update_tab_buttons()


func _build_compact_chrome() -> void:
	_vitals_grid = GridContainer.new()
	_vitals_grid.name = "VitalsStrip"
	_vitals_grid.columns = 3
	_vitals_grid.add_theme_constant_override("h_separation", 4)
	_vitals_grid.add_theme_constant_override("v_separation", 4)
	_vitals_grid.visible = false
	for key in WorldState.METRIC_KEYS:
		var vital := MeterBar.new()
		vital.metric_key = key
		vital.compact = true
		vital.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vital.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		vital.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				show_tab("intel"))
		_vitals[key] = vital
		_vitals_grid.add_child(vital)
	_layout.add_child(_vitals_grid)
	_layout.move_child(_vitals_grid, 1)

	_tab_bar = HBoxContainer.new()
	_tab_bar.name = "TabBar"
	_tab_bar.add_theme_constant_override("separation", 4)
	_tab_bar.visible = false
	for tab in TABS:
		var button := Button.new()
		button.text = TAB_LABELS[tab]
		button.custom_minimum_size = Vector2(0, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(show_tab.bind(tab))
		_tab_buttons[tab] = button
		_tab_bar.add_child(button)
	_layout.add_child(_tab_bar)


## Highlights the active tab and flags ACT while a decision is waiting.
func _update_tab_buttons() -> void:
	var waiting := engine != null and engine.is_awaiting_player() and not spectate
	for tab in _tab_buttons:
		var button: Button = _tab_buttons[tab]
		var active: bool = tab == active_tab
		button.theme_type_variation = "AccentButton" if active else ""
		button.text = TAB_LABELS[tab] + (" ●" if tab == "act" and waiting and not active else "")
		if tab == "act" and waiting and not active:
			button.add_theme_color_override("font_color", CyberPalette.AMBER)
		else:
			button.remove_theme_color_override("font_color")


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
	if compact:
		_update_tab_buttons()


func _on_actor_decisions_requested(faction_ids: Array) -> void:
	if llm.is_online and not faction_ids.is_empty():
		var waiting := "AWAITING %d AUTONOMOUS ACTORS (LLM)" % faction_ids.size()
		_phase_label.text = "PHASE: " + waiting
		if compact:
			# Phones hide the phase label; say why the turn is paused where the player looks.
			_directive_panel.set_crisis_status("[color=%s]%s...[/color]" % [CyberPalette.hex(CyberPalette.AMBER), waiting])


func _on_player_input_required(context: Dictionary) -> void:
	_refresh_telemetry(engine.get_snapshot(), false)
	if spectate:
		return
	_pending_option = ""
	_directive_panel.setup(context)
	_directive_panel.set_interactive(true)
	show_tab("act")
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
	if compact:
		_pause_button.text = "▶" if _paused else "II"
	else:
		_pause_button.text = "RESUME" if _paused else "PAUSE"


func _cycle_speed() -> void:
	_speed_index = (_speed_index + 1) % SPECTATE_INTERVALS.size()
	_speed_button.text = ("x%d" if compact else "SPEED x%d") % [1, 2, 4][_speed_index]
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


# --- Event feed ------------------------------------------------------------------------------

## Keeps the feed pinned to the newest entry until the player scrolls up, and
## pins it again once they scroll back to the bottom.
func _bind_feed_scroll() -> void:
	var bar := _feed_scroll.get_v_scroll_bar()
	bar.changed.connect(func():
		if _feed_follow:
			_feed_scroll.scroll_vertical = int(bar.max_value))
	bar.value_changed.connect(func(value: float):
		_feed_follow = value + bar.page >= bar.max_value - 8.0)


# --- Telemetry rendering -----------------------------------------------------------------

func _refresh_telemetry(snapshot: Dictionary, record: bool) -> void:
	var metrics: Dictionary = snapshot.get("metrics", {})
	for key in _meters:
		(_meters[key] as MeterBar).set_value(float(metrics.get(key, 0.0)), record)
	for key in _vitals:
		(_vitals[key] as MeterBar).set_value(float(metrics.get(key, 0.0)), record)
	_globe.update_from_snapshot(snapshot)
	_lattice.update_from_snapshot(snapshot)
	_indices_label.text = _format_indices(snapshot)
	if engine != null:
		_directive_panel.update_resources(engine.player_role, engine.get_player().resources)
	_update_header()


func _update_header() -> void:
	if engine == null:
		_year_label.text = "2026 · T0/100" if compact else "YEAR: 2026 (T:0/100)"
		return
	var year := int(floor(engine.get_year()))
	if compact:
		_year_label.text = "%d · T%d/%d" % [year, engine.turn, engine.total_turns]
	else:
		_year_label.text = "YEAR: %d (T:%d/%d)" % [year, engine.turn, engine.total_turns]


func _update_role_label() -> void:
	if engine == null:
		_role_label.text = "ROLE: --"
		return
	_role_label.text = "ROLE: %s%s" % [SimConstants.ROLE_INFO[engine.player_role]["header"], "  [SPECTATE]" if spectate else ""]


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
