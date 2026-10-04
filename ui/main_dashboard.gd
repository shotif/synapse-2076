extends Control
## SYNAPSE-2076 main dashboard (PRD section 8). Owns the SimulationEngine and
## the LLMService and binds them to the widgets purely through signals.
##
## The look follows the hardware era: the dashboard applies
## EraTheme.get_theme(era) to itself, and when the era changes it plays a
## short "system upgrade" (EraUpgrade) and swaps the theme halfway through.
## The crisis waiting for the player is held back until the upgrade is over.
##
## Three layouts (UiLayout): desktop (a 1600x900 canvas with the header, the
## lens/intel column, the world, the ACT column and the newswire), split
## (landscape tablets and phones: the world beside one tabbed panel) and
## phone (one panel at a time behind WORLD / ACT / LENS / NEWS tabs, with
## the vitals strip on top).
##
## When launched headless as the main scene (`godot --headless --path .`), it
## plays one autoplay campaign, prints the result and quits; pass
## `-- --role=CEO --seed=42` to choose the perspective.

const SPECTATE_INTERVALS := [0.8, 0.4, 0.15]
const NEXT_TURN_DELAY := 0.35
const FEED_LIMIT := 350
const TABS := ["world", "act", "lens", "news"]
const TAB_INFO := [
	{"id": "world", "label": "World", "glyph": "world"},
	{"id": "act", "label": "Act", "glyph": "act"},
	{"id": "lens", "label": "Lens", "glyph": "lens"},
	{"id": "news", "label": "News", "glyph": "news"},
]
## Earlier tab names, still accepted by show_tab().
const TAB_ALIASES := {"intel": "lens", "log": "news"}
const UI_CONFIG_PATH := "user://synapse_ui.cfg"
const DESKTOP_LEFT_WIDTH := 372.0
const DESKTOP_RIGHT_WIDTH := 404.0
const DESKTOP_FOOTER_HEIGHT := 176.0

var engine: SimulationEngine
var llm: LLMService
var spectate := false
## True in the split and phone layouts.
var compact := false
## UiLayout.MODE_DESKTOP, MODE_SPLIT or MODE_PHONE.
var screen_mode := UiLayout.MODE_DESKTOP
## The panel shown on phones (WORLD/ACT/LENS/NEWS) or beside the world in
## the split layout (ACT/LENS/NEWS).
var active_tab := "act"
## What the left column (the LENS tab) shows: "lens" or "intel".
var left_view := "lens"
## The hardware era whose theme is applied (1-3).
var era := 1
## Animated backdrops, glitches and the tearing era transition.
var effects_enabled := true

var _landscape := true
var _split_tab := "act"
var _speed_index := 0
var _paused := false
var _pending_option := ""
var _deferred_context := {}
var _meters := {}
var _vitals := {}
var _feed_entries: Array[Dictionary] = []
var _feed_follow := true
var _lens: Control
var _spectate_timer: Timer
var _next_turn_timer: Timer
var _backdrop: EraBackdrop
var _era_upgrade: EraUpgrade
var _nav: NavBar
var _vitals_grid: GridContainer
var _index_bars := {}
var _index_values := {}
var _index_names := {}
var _menu_layer: Control
var _menu_panel: PanelContainer
var _effects_check: CheckBox

@onready var _margin: MarginContainer = $Margin
@onready var _layout: VBoxContainer = $Margin/Layout
@onready var _header: PanelContainer = %Header
@onready var _header_row: HBoxContainer = %HeaderRow
@onready var _role_mark: TextureRect = %RoleMark
@onready var _title_box: VBoxContainer = %TitleBox
@onready var _kicker: Label = %Kicker
@onready var _title_label: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _header_spacer: Control = %HeaderSpacer
@onready var _clock_box: VBoxContainer = %ClockBox
@onready var _year_label: Label = %YearLabel
@onready var _phase_label: Label = %PhaseLabel
@onready var _badge: LLMStatusBadge = %LLMStatusBadge
@onready var _spectate_controls: HBoxContainer = %SpectateControls
@onready var _pause_button: Button = %PauseButton
@onready var _speed_button: Button = %SpeedButton
@onready var _menu_button: Button = %MenuButton
@onready var _compact_vitals: MarginContainer = %CompactVitals
@onready var _body: HBoxContainer = %Body
@onready var _telemetry_panel: PanelContainer = %TelemetryPanel
@onready var _left_switch: HBoxContainer = %LeftSwitch
@onready var _lens_button: Button = %LensButton
@onready var _intel_button: Button = %IntelButton
@onready var _lens_host: MarginContainer = %LensHost
@onready var _intel_scroll: ScrollContainer = %IntelScroll
@onready var _meter_grid: GridContainer = %MeterGrid
@onready var _indices_label: RichTextLabel = %IndicesLabel
@onready var _center_panel: PanelContainer = %CenterPanel
@onready var _world_stack: Control = %WorldStack
@onready var _globe_button: Button = %GlobeButton
@onready var _lattice_button: Button = %LatticeButton
@onready var _globe_container: SubViewportContainer = %GlobeContainer
@onready var _lattice_container: SubViewportContainer = %LatticeContainer
@onready var _globe: GlobeViewport = %Globe
@onready var _lattice: NeuralLattice = %Lattice
@onready var _viewport_caption: RichTextLabel = %ViewportCaption
@onready var _directive_panel: DirectivePanel = %DirectivePanel
@onready var _footer: PanelContainer = %Footer
@onready var _headline: RichTextLabel = %FeedHeadline
@onready var _feed_scroll: ScrollContainer = %FeedScroll
@onready var _feed: RichTextLabel = %EventFeed
@onready var _dilemma: DilemmaDialog = %DilemmaDialog
@onready var _debrief: EndgameDebrief = %EndgameDebrief
@onready var _settings: LLMSettingsDialog = %LLMSettingsDialog
@onready var _role_select: RoleSelect = %RoleSelect


func _ready() -> void:
	_load_ui_settings()
	for node in find_children("*Meter", "", true, false):
		if node is MeterBar:
			_meters[(node as MeterBar).metric_key] = node
	_build_chrome()

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
	_lens_button.pressed.connect(func(): show_left_view("lens"))
	_intel_button.pressed.connect(func(): show_left_view("intel"))
	_pause_button.pressed.connect(_toggle_pause)
	_speed_button.pressed.connect(_cycle_speed)
	_menu_button.pressed.connect(_open_menu)
	_apply_era(1)
	_apply_effects()
	show_view("globe")
	show_left_view("lens")
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
	_era_upgrade.cancel()
	if engine != null:
		engine.set_decision_provider(null)
	spectate = spectate_mode
	_paused = false
	_pending_option = ""
	_deferred_context = {}
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
	_apply_era(int(engine.get_snapshot().get("era", 1)))
	_role_select.visible = false
	_debrief.visible = false
	_dilemma.close()
	_spectate_controls.visible = spectate
	_update_spectate_buttons()
	_directive_panel.set_interactive(false)
	_rebuild_lens()
	show_tab("world" if spectate else "act")
	_refresh_telemetry(engine.get_snapshot(), true)
	engine.advance()
	if spectate:
		_spectate_timer.start(SPECTATE_INTERVALS[_speed_index])


func show_view(view: String) -> void:
	var globe := view == "globe"
	_globe_container.visible = globe
	_lattice_container.visible = not globe
	_globe_button.button_pressed = globe
	_lattice_button.button_pressed = not globe
	var s := EraStyle.for_era(era)
	var hint := "pinch" if compact else "scroll"
	if globe:
		_viewport_caption.text = "[color=%s]%s[/color]  Datacenter heat = compute & energy · red rings = compute embargo · cable pulses = trust · drag to orbit, %s to zoom" % [
			CyberPalette.hex(s.accent), s.label("Globe"), hint]
	else:
		_viewport_caption.text = "[color=%s]%s[/color]  Depth = frontier capability · color and jitter = alignment drift · amber = emergent capabilities · drag to orbit" % [
			CyberPalette.hex(s.accent), s.label("Neural lattice")]


## Switches the left column (the LENS tab) between the faction lens and the
## detailed telemetry.
func show_left_view(view: String) -> void:
	left_view = "intel" if view == "intel" or _lens == null else "lens"
	_lens_host.visible = left_view == "lens"
	_intel_scroll.visible = left_view == "intel"
	_lens_button.button_pressed = left_view == "lens"
	_intel_button.button_pressed = left_view == "intel"
	_left_switch.visible = _lens != null


# --- Eras ---------------------------------------------------------------------------

## Applies [param era_number]'s theme to the whole dashboard.
func _apply_era(era_number: int) -> void:
	era = clampi(era_number, 1, 3)
	theme = EraTheme.get_theme(era)
	_backdrop.set_era(era)
	if _globe.has_method("set_era"):
		_globe.call("set_era", era)
	_restyle_chrome()
	_update_header()
	show_view("globe" if _globe_container.visible else "lattice")
	if engine != null:
		_update_indices(engine.get_snapshot())


func _begin_era_change(new_era: int) -> void:
	if new_era == era and not _era_upgrade.is_playing():
		return
	_era_upgrade.set_compact(compact)
	_era_upgrade.play(new_era, int(floor(engine.get_year())) if engine != null else 0)


## True while an era change holds the next crisis back.
func _story_busy() -> bool:
	return _era_upgrade.is_playing()


func _on_story_finished() -> void:
	if _story_busy():
		return
	if not _deferred_context.is_empty() and engine != null and engine.is_awaiting_player() and not spectate:
		_present_crisis(_deferred_context)


func _restyle_chrome() -> void:
	var s := EraStyle.for_era(era)
	_header.add_theme_stylebox_override("panel", _header_style(s))
	_meter_grid.columns = 2 if era == 1 else 3
	_role_mark.texture = _role_mark_texture(s)
	_menu_button.icon = Glyphs.texture("menu", 18)
	_speed_button.icon = Glyphs.texture("speed", 14)
	_lens_button.icon = Glyphs.texture("lens", 16)
	_intel_button.icon = Glyphs.texture("intel", 16)
	_globe_button.icon = Glyphs.texture("world", 16)
	_lattice_button.icon = Glyphs.texture("lattice", 16)
	_lens_button.text = s.label("Lens")
	_intel_button.text = s.label("Intel")
	_globe_button.text = s.label("Globe")
	_lattice_button.text = s.label("Lattice")
	_update_spectate_buttons()
	_restyle_header_type(s)
	_viewport_caption.add_theme_font_size_override("normal_font_size", 11)
	_viewport_caption.add_theme_color_override("default_color", s.text_dim)
	_indices_label.add_theme_font_size_override("normal_font_size", 12)
	_indices_label.add_theme_font_size_override("mono_font_size", 12)
	_headline.add_theme_font_size_override("normal_font_size", 14)
	_feed.add_theme_font_size_override("normal_font_size", 12)
	_feed.add_theme_font_size_override("mono_font_size", 12)
	if _menu_panel != null:
		_restyle_menu(s)


## Era I: a bare toolbar. Era II: a lit glass strip. Era III: nothing at all.
func _header_style(s: EraStyle) -> StyleBoxFlat:
	if s.era == 2:
		return EraTheme.box(Color(s.accent, 0.035), Color(s.accent, 0.22), 1, 8, 14 if not compact else 8, 6, 1)
	return EraTheme.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 2 if not compact else 0, 2)


## Header type per era: Era I leads with the role, Eras II and III with the year.
func _restyle_header_type(s: EraStyle) -> void:
	var title_size := 20
	match s.era:
		2:
			title_size = 22 if compact else 30
		3:
			title_size = 26 if compact else 40
		_:
			title_size = 17 if compact else 20
	_title_label.add_theme_font_size_override("font_size", title_size)
	_title_label.add_theme_font_override("font", s.font_display)
	if s.era == 2:
		_title_label.add_theme_color_override("font_shadow_color", Color(s.accent, 0.35))
		_title_label.add_theme_constant_override("shadow_outline_size", 6)
		_title_label.add_theme_constant_override("shadow_offset_x", 0)
		_title_label.add_theme_constant_override("shadow_offset_y", 0)
	else:
		_title_label.remove_theme_color_override("font_shadow_color")
		_title_label.remove_theme_constant_override("shadow_outline_size")
	_title_label.add_theme_color_override("font_color", s.text_bright)
	_subtitle.add_theme_font_override("font", s.font_mono if s.era != 1 else s.font_ui)
	_subtitle.add_theme_font_size_override("font_size", 11 if s.era != 1 else 13)
	_kicker.add_theme_font_override("font", EraStyle.font("ChakraPetch-SemiBold.ttf", 2))
	_kicker.add_theme_font_size_override("font_size", 11 if compact else 12)
	_year_label.add_theme_font_override("font", s.font_ui_bold if s.era == 1 else s.font_mono)
	_year_label.add_theme_font_size_override("font_size", 13)
	_year_label.add_theme_color_override("font_color", s.text_dim if s.era == 1 else s.text)
	# Phones trim the lines to fit beside the buttons; the desktop shows them whole.
	for label in [_kicker, _title_label, _subtitle]:
		(label as Label).clip_text = compact
		(label as Label).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if compact else TextServer.OVERRUN_NO_TRIMMING


func _role_mark_texture(s: EraStyle) -> Texture2D:
	var size := 28 if compact else 36
	var radius := 4 if s.era == 2 else (size / 2 if s.era == 3 else 9)
	if engine == null:
		return Glyphs.tile("spark", size, s.accent, s.on_accent, radius, 0.58)
	return Glyphs.tile(Glyphs.for_faction(engine.player_role), size, s.faction_color(engine.player_role), s.bg, radius, 0.58)


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
## (so text keeps a readable physical size) and the screen mode.
func apply_layout(layout: Dictionary) -> void:
	var content_size: Vector2i = layout.get("content_size", UiLayout.DESKTOP_SIZE)
	var root := get_tree().root
	if root.content_scale_size != content_size:
		root.content_scale_size = content_size
	var fallback := UiLayout.MODE_PHONE if bool(layout.get("compact", false)) else UiLayout.MODE_DESKTOP
	set_screen_mode(String(layout.get("mode", fallback)), bool(layout.get("landscape", true)))


## Desktop (false) or phone (true) layout; kept for older callers.
func set_compact(enabled: bool, landscape: bool = false) -> void:
	set_screen_mode(UiLayout.MODE_PHONE if enabled else UiLayout.MODE_DESKTOP, landscape)


func set_screen_mode(mode: String, landscape: bool = true) -> void:
	screen_mode = mode if mode in [UiLayout.MODE_DESKTOP, UiLayout.MODE_SPLIT, UiLayout.MODE_PHONE] else UiLayout.MODE_DESKTOP
	compact = screen_mode != UiLayout.MODE_DESKTOP
	_landscape = landscape
	var phone := screen_mode == UiLayout.MODE_PHONE
	_margin.add_theme_constant_override("margin_left", 8 if compact else 14)
	_margin.add_theme_constant_override("margin_right", 8 if compact else 14)
	_margin.add_theme_constant_override("margin_top", 6 if compact else 10)
	_margin.add_theme_constant_override("margin_bottom", 0 if compact else 12)
	_layout.add_theme_constant_override("separation", 6 if compact else 10)
	_body.add_theme_constant_override("separation", 8 if compact else 10)
	_header_row.add_theme_constant_override("separation", 8 if compact else 14)
	# Phones give the title lines all the room the buttons leave.
	_title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL if compact else Control.SIZE_FILL
	_header_spacer.visible = not compact
	_clock_box.visible = not compact
	_place_footer()
	_nav.visible = compact
	_nav.set_tab_visible("world", phone)
	_telemetry_panel.custom_minimum_size = Vector2(0 if compact else DESKTOP_LEFT_WIDTH, 0)
	_directive_panel.custom_minimum_size = Vector2(0 if compact else DESKTOP_RIGHT_WIDTH, 0)
	for panel in [_telemetry_panel, _directive_panel, _footer]:
		(panel as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL if compact else Control.SIZE_FILL
		(panel as Control).size_flags_stretch_ratio = 1.0
	_center_panel.size_flags_stretch_ratio = 1.15 if screen_mode == UiLayout.MODE_SPLIT else 1.0
	_vitals_grid.columns = 6 if landscape else 3
	# Touch screens scroll the feed by dragging, so text selection gives way.
	_feed.selection_enabled = not compact
	for button in [_menu_button, _pause_button, _speed_button]:
		(button as Control).custom_minimum_size = Vector2(44, 44) if compact else Vector2(40, 36)
	_badge.set_compact(compact)
	_directive_panel.set_compact(compact)
	_dilemma.set_compact(compact)
	_role_select.set_compact(compact)
	_debrief.set_compact(compact)
	_settings.set_compact(compact)
	_era_upgrade.set_compact(compact)
	if _lens != null and _lens.has_method("set_compact"):
		_lens.call("set_compact", compact)
	_restyle_chrome()
	_update_header()
	show_view("globe" if _globe_container.visible else "lattice")
	show_tab(active_tab)
	_update_llm_hint()


## Phones show one panel; the split layout shows the world beside one panel;
## the desktop shows every panel.
func show_tab(tab: String) -> void:
	if tab == "intel":
		show_left_view("intel")
	tab = String(TAB_ALIASES.get(tab, tab))
	if not tab in TABS:
		return
	active_tab = tab
	var panels := {"world": _center_panel, "act": _directive_panel, "lens": _telemetry_panel, "news": _footer}
	match screen_mode:
		UiLayout.MODE_DESKTOP:
			for key in panels:
				(panels[key] as Control).visible = true
		UiLayout.MODE_SPLIT:
			if tab != "world":
				_split_tab = tab
			for key in panels:
				(panels[key] as Control).visible = key == "world" or key == _split_tab
			_nav.set_active(_split_tab)
		_:
			for key in panels:
				(panels[key] as Control).visible = key == tab
			_nav.set_active(tab)
	_compact_vitals.visible = screen_mode == UiLayout.MODE_PHONE and tab != "world"
	_update_tab_buttons()


## Compact layouts keep the newswire as a panel beside the others; the
## desktop puts it in a strip under them. The split layout keeps the world
## on the left whichever panel sits beside it.
func _place_footer() -> void:
	var target: Node = _body if compact else _layout
	if _footer.get_parent() != target:
		_footer.reparent(target, false)
	if not compact:
		_layout.move_child(_footer, _body.get_index() + 1)
	if screen_mode == UiLayout.MODE_SPLIT:
		_body.move_child(_center_panel, 0)
	else:
		_body.move_child(_telemetry_panel, 0)
		_body.move_child(_center_panel, 1)
	_footer.custom_minimum_size = Vector2(0, 0 if compact else DESKTOP_FOOTER_HEIGHT)
	_footer.size_flags_vertical = Control.SIZE_EXPAND_FILL if compact else Control.SIZE_FILL


func _build_chrome() -> void:
	_backdrop = EraBackdrop.new()
	add_child(_backdrop)
	move_child(_backdrop, 0)
	add_child(_backdrop.scanlines)
	move_child(_backdrop.scanlines, _margin.get_index() + 1)

	_vitals_grid = GridContainer.new()
	_vitals_grid.name = "VitalsStrip"
	_vitals_grid.columns = 3
	_vitals_grid.add_theme_constant_override("h_separation", 4)
	_vitals_grid.add_theme_constant_override("v_separation", 4)
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
	_compact_vitals.add_child(_vitals_grid)
	_build_index_grid()

	_nav = NavBar.new()
	_nav.name = "NavBar"
	_nav.visible = false
	_nav.setup(TAB_INFO)
	_nav.tab_selected.connect(show_tab)
	_layout.add_child(_nav)

	_era_upgrade = EraUpgrade.new()
	_era_upgrade.name = "EraUpgrade"
	_era_upgrade.swap_theme.connect(_apply_era)
	_era_upgrade.finished.connect(_on_story_finished)
	add_child(_era_upgrade)
	_build_menu()


# --- Menu ---------------------------------------------------------------------------

func _build_menu() -> void:
	_menu_layer = Control.new()
	_menu_layer.name = "MenuLayer"
	_menu_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_layer.visible = false
	_menu_layer.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_menu_layer.visible = false)
	add_child(_menu_layer)
	_menu_panel = PanelContainer.new()
	_menu_panel.theme_type_variation = "OverlayPanel"
	_menu_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_menu_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_menu_layer.add_child(_menu_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_menu_panel.add_child(box)
	box.add_child(_menu_item("New campaign", "home", func(): _show_role_select()))
	box.add_child(_menu_item("AI settings", "settings", func(): _open_llm_settings()))
	if OS.has_feature("web"):
		box.add_child(_menu_item("Full screen", "layers", func(): _toggle_fullscreen()))
	box.add_child(HSeparator.new())
	_effects_check = CheckBox.new()
	_effects_check.text = "Visual effects"
	_effects_check.tooltip_text = "Glitches, animated backgrounds and the tearing era transition"
	_effects_check.custom_minimum_size = Vector2(0, 40)
	_effects_check.toggled.connect(func(pressed: bool):
		effects_enabled = pressed
		_apply_effects()
		_save_ui_settings())
	box.add_child(_effects_check)


func _menu_item(text: String, glyph: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = Glyphs.texture(glyph, 16)
	button.theme_type_variation = "GhostButton"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(220, 40)
	button.pressed.connect(func():
		_menu_layer.visible = false
		action.call())
	return button


func _restyle_menu(s: EraStyle) -> void:
	for button in _menu_panel.find_children("*", "Button", true, false):
		if not (button is CheckBox):
			(button as Button).add_theme_color_override("font_color", s.text)
			(button as Button).add_theme_color_override("icon_normal_color", s.text_dim)


func _open_menu() -> void:
	_effects_check.set_pressed_no_signal(effects_enabled)
	var button_rect := _menu_button.get_global_rect()
	_menu_panel.reset_size()
	var width := _menu_panel.get_combined_minimum_size().x
	_menu_panel.position = Vector2(clampf(button_rect.end.x - width, 8.0, maxf(size.x - width - 8.0, 8.0)), button_rect.end.y + 6.0)
	_menu_layer.visible = true


func _toggle_fullscreen() -> void:
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _apply_effects() -> void:
	_backdrop.set_motion(effects_enabled)
	_era_upgrade.set_motion(effects_enabled)


func _load_ui_settings() -> void:
	var config := ConfigFile.new()
	if config.load(UI_CONFIG_PATH) == OK:
		effects_enabled = bool(config.get_value("display", "effects", true))


func _save_ui_settings() -> void:
	var config := ConfigFile.new()
	config.load(UI_CONFIG_PATH)
	config.set_value("display", "effects", effects_enabled)
	config.save(UI_CONFIG_PATH)


## Flags ACT while a decision is waiting and another tab is showing.
func _update_tab_buttons() -> void:
	var waiting := engine != null and engine.is_awaiting_player() and not spectate
	var showing_act := active_tab == "act" if screen_mode == UiLayout.MODE_PHONE else _split_tab == "act"
	_nav.set_badge("act", waiting and not showing_act)


# --- Lens ---------------------------------------------------------------------------

## Builds the faction lens for the player's role into the left column.
func _rebuild_lens() -> void:
	for child in _lens_host.get_children():
		_lens_host.remove_child(child)
		child.queue_free()
	_lens = null
	show_left_view(left_view)


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
		var s := EraStyle.for_era(era)
		_headline.text = "[color=%s]%s[/color]  [color=%s]%s[/color]" % [
			CyberPalette.hex(s.accent), s.label("Latest"), CyberPalette.hex(_severity_color(s, severity)),
			CyberPalette.escape_bbcode(String(entry.get("text", ""))).left(220)]
	if String(entry.get("category", "")) == "ERA":
		_begin_era_change(int(entry.get("era", era)))


func _on_phase_changed(phase: int, _turn: int) -> void:
	var names := {
		SimulationEngine.Phase.IDLE: "Standby",
		SimulationEngine.Phase.WORLD_TICK: "World tick",
		SimulationEngine.Phase.ACTOR_RESOLUTION: "Factions moving",
		SimulationEngine.Phase.PLAYER_ACTION: "Your move" if not spectate else "Autoplay move",
		SimulationEngine.Phase.TELEMETRY: "Reconciling telemetry",
		SimulationEngine.Phase.ENDED: "Campaign complete",
	}
	_set_phase_text(String(names.get(phase, "?")))
	_update_header()
	if compact:
		_update_tab_buttons()


func _on_actor_decisions_requested(faction_ids: Array) -> void:
	if llm.is_online and not faction_ids.is_empty():
		var waiting := "Waiting on %d factions (LLM)" % faction_ids.size()
		_set_phase_text(waiting)
		if compact:
			# Phones hide the phase label; say why the turn is paused where the player looks.
			_directive_panel.set_crisis_status("[color=%s]%s…[/color]" % [CyberPalette.hex(EraStyle.for_era(era).warn), waiting])


func _on_player_input_required(context: Dictionary) -> void:
	_refresh_telemetry(engine.get_snapshot(), false)
	if spectate:
		return
	_pending_option = ""
	_directive_panel.setup(context)
	_directive_panel.set_interactive(true)
	if _story_busy():
		_deferred_context = context
		_update_tab_buttons()
		return
	_present_crisis(context)


func _present_crisis(context: Dictionary) -> void:
	_deferred_context = {}
	if screen_mode != UiLayout.MODE_DESKTOP:
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
	_era_upgrade.finish_now()
	_deferred_context = {}
	_directive_panel.set_interactive(false)
	_dilemma.close()
	_debrief.present(result)


# --- Player interaction -------------------------------------------------------------

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
	var s := EraStyle.for_era(era)
	_directive_panel.set_crisis_status("[color=%s]%s[/color] Resolving the turn…" % [CyberPalette.hex(s.accent), s.label("Directives executed.")])


func _begin_next_turn() -> void:
	if engine != null and not engine.is_ended() and engine.phase == SimulationEngine.Phase.IDLE:
		engine.advance()


func _on_spectate_tick() -> void:
	if engine == null or _paused or engine.is_ended() or engine.is_awaiting_actors() or _story_busy():
		return
	engine.advance()


func _toggle_pause() -> void:
	_paused = not _paused
	_update_spectate_buttons()


func _cycle_speed() -> void:
	_speed_index = (_speed_index + 1) % SPECTATE_INTERVALS.size()
	_update_spectate_buttons()
	if spectate:
		_spectate_timer.start(SPECTATE_INTERVALS[_speed_index])


func _update_spectate_buttons() -> void:
	_pause_button.icon = Glyphs.texture("play" if _paused else "pause", 14)
	_pause_button.tooltip_text = "Resume autoplay" if _paused else "Pause autoplay"
	_speed_button.text = "×%d" % [1, 2, 4][_speed_index]


func _show_role_select() -> void:
	_spectate_timer.stop()
	_next_turn_timer.stop()
	_era_upgrade.cancel()
	_debrief.visible = false
	_dilemma.close()
	_update_llm_hint()
	if era != 1:
		_apply_era(1)
	_role_select.visible = true


func _open_llm_settings() -> void:
	_settings.open(llm)


func _update_llm_hint() -> void:
	_role_select.set_llm_status(_badge.get_text())


# --- Event feed ---------------------------------------------------------------------

## Keeps the feed pinned to the newest entry until the player scrolls up, and
## pins it again once they scroll back to the bottom.
func _bind_feed_scroll() -> void:
	var bar := _feed_scroll.get_v_scroll_bar()
	bar.changed.connect(func():
		if _feed_follow:
			_feed_scroll.scroll_vertical = int(bar.max_value))
	bar.value_changed.connect(func(value: float):
		_feed_follow = value + bar.page >= bar.max_value - 8.0)


func _format_entry(entry: Dictionary) -> String:
	var s := EraStyle.for_era(era)
	var faction := String(entry.get("faction", ""))
	var tag := ""
	if faction != "":
		tag = "[color=%s]%s[/color] " % [CyberPalette.hex(s.faction_color(faction)), UiFormat.role_name(faction)]
	var category := String(entry.get("category", "")).capitalize()
	return "[color=%s][code]T%02d %d[/code][/color]  [color=%s]%s[/color]  %s[color=%s]%s[/color]" % [
		CyberPalette.hex(s.text_dim), int(entry.get("turn", 0)), int(float(entry.get("year", 2026.0))),
		CyberPalette.hex(s.accent), s.label(category), tag, CyberPalette.hex(_severity_color(s, String(entry.get("severity", "INFO")))),
		CyberPalette.escape_bbcode(String(entry.get("text", "")))]


func _severity_color(s: EraStyle, severity: String) -> Color:
	match severity:
		"WARN":
			return s.warn
		"CRITICAL":
			return s.critical
	return s.text


# --- Telemetry rendering ------------------------------------------------------------

func _refresh_telemetry(snapshot: Dictionary, record: bool) -> void:
	var metrics: Dictionary = snapshot.get("metrics", {})
	for key in _meters:
		(_meters[key] as MeterBar).set_value(float(metrics.get(key, 0.0)), record)
	for key in _vitals:
		(_vitals[key] as MeterBar).set_value(float(metrics.get(key, 0.0)), record)
	_globe.update_from_snapshot(snapshot)
	_lattice.update_from_snapshot(snapshot)
	_update_indices(snapshot)
	if engine != null:
		_directive_panel.update_resources(engine.player_role, engine.get_player().resources)
	_update_header()


func _set_phase_text(text: String) -> void:
	var s := EraStyle.for_era(era)
	_phase_label.text = text.to_lower() if s.era == 3 else s.label(text)


## The header's lines in the active era's voice.
func _update_header() -> void:
	if _year_label == null:
		return
	var role := engine.player_role if engine != null else ""
	var year_value := engine.get_year() if engine != null else float(SimConstants.START_YEAR)
	var year := int(floor(year_value))
	var half := "H1" if year_value - floor(year_value) < 0.25 else "H2"
	var turn := engine.turn if engine != null else 0
	var total := engine.total_turns if engine != null else SimConstants.TOTAL_TURNS
	var role_name := UiFormat.role_name(role) if role != "" else "SYNAPSE-2076"
	var turn_line := "%s %d · Turn %d of %d" % [half, year, turn, total]
	match era:
		2:
			_kicker.visible = true
			_kicker.text = "%s // OPS" % role_name.to_upper()
			_title_label.text = "%.1f" % year_value
			_subtitle.text = ("T%d · ERA II" % turn) if compact else ("T%d · ERA II · %s" % [turn, String(EraStyle.NAMES[2]).to_upper()])
			_year_label.text = "TURN %d / %d" % [turn, total]
		3:
			_kicker.visible = false
			_title_label.text = str(year)
			_subtitle.text = ("era iii · turn %d" % turn) if compact else ("era iii · %s · turn %d" % [String(EraStyle.NAMES[3]).to_lower(), turn])
			_year_label.text = "turn %d of %d" % [turn, total]
		_:
			_kicker.visible = false
			_title_label.text = role_name
			_subtitle.text = turn_line if compact else "Era I · %s" % EraStyle.NAMES[1]
			_year_label.text = turn_line
	_role_mark.texture = _role_mark_texture(EraStyle.for_era(era))


## Secondary indices as labelled bars, built once under the meters.
func _build_index_grid() -> void:
	var grid := GridContainer.new()
	grid.name = "IndexGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	var title := Label.new()
	title.name = "IndexTitle"
	title.theme_type_variation = "PanelTitle"
	var box := _indices_label.get_parent()
	box.add_child(title)
	box.move_child(title, _indices_label.get_index())
	box.add_child(grid)
	box.move_child(grid, _indices_label.get_index())
	for key in WorldState.INDEX_KEYS:
		var name_label := Label.new()
		name_label.theme_type_variation = "DimLabel"
		name_label.custom_minimum_size = Vector2(96, 0)
		grid.add_child(name_label)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 100.0
		bar.custom_minimum_size = Vector2(0, 6)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(bar)
		var value_label := Label.new()
		value_label.theme_type_variation = "ValueLabel"
		value_label.custom_minimum_size = Vector2(30, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value_label)
		_index_names[key] = name_label
		_index_bars[key] = bar
		_index_values[key] = value_label


func _update_indices(snapshot: Dictionary) -> void:
	var s := EraStyle.for_era(era)
	var title := _indices_label.get_parent().get_node("IndexTitle") as Label
	title.text = s.label("Secondary indices")
	var indices: Dictionary = snapshot.get("indices", {})
	for key in _index_bars:
		var value := float(indices.get(key, 0.0))
		(_index_names[key] as Label).text = s.label(UiFormat.metric_short(key))
		(_index_bars[key] as ProgressBar).value = value
		(_index_values[key] as Label).text = str(int(round(value)))
	_indices_label.text = _format_compute(snapshot)


## The frontier-compute block under the indices.
func _format_compute(snapshot: Dictionary) -> String:
	var s := EraStyle.for_era(era)
	var dim := CyberPalette.hex(s.text_dim)
	var bright := CyberPalette.hex(s.text_bright)
	var tech: Dictionary = snapshot.get("tech", {})
	var grid: Dictionary = snapshot.get("compute", {})
	var era_number := int(snapshot.get("era", era))
	var lines: Array[String] = []
	lines.append("[color=%s]%s[/color] [color=%s]· Era %s, %s[/color]" % [bright, s.label("Frontier compute"), dim,
		EraStyle.ROMAN.get(era_number, "I"), EraStyle.NAMES.get(era_number, "")])
	lines.append("[color=%s]Training FLOPs[/color] [code]10^%.2f[/code]   [color=%s]Capability[/color] [code]%.0f[/code]" % [
		dim, float(tech.get("log_flops", 26.0)), dim, float(tech.get("capability_index", 0.0))])
	lines.append("[color=%s]Grid load[/color] [code]%.0f/%.0f GW[/code]   [color=%s]Throttle[/color] [code]%.2f[/code]" % [
		dim, float(grid.get("power_demand_gw", 0.0)), float(grid.get("grid_capacity_gw", 0.0)), dim, float(grid.get("throttle", 1.0))])
	var agi_turn := int(tech.get("agi_turn", -1))
	lines.append("[color=%s]AGI milestone[/color] %s   [color=%s]Alignment tax[/color] [code]×%.2f[/code]" % [
		dim, ("crossed %d" % int(SimConstants.year_for_turn(agi_turn))) if agi_turn >= 0 else "pending",
		dim, float(tech.get("alignment_tax_multiplier", 1.0))])
	var shifts: Array = tech.get("unlocked_shifts", [])
	var shift_tags: Array[String] = []
	for shift_id in shifts:
		shift_tags.append(String(TechTreeManager.PARADIGM_SHIFTS[shift_id]["name"]).get_slice(" ", 0))
	lines.append("[color=%s]Paradigms[/color] %s" % [dim, ", ".join(shift_tags) if not shift_tags.is_empty() else "none yet"])
	return "\n".join(lines)


# --- Headless autorun ---------------------------------------------------------------

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
