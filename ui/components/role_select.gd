class_name RoleSelect
extends Control
## The new-campaign setup. Choose one of the four asymmetric perspectives (PRD
## section 1), the campaign's length (CampaignModes), its starting world
## (Scenarios), the difficulty, who else plays on this device (pass-and-play
## seats), a seed, and whether to spectate (the AI plays your role). Above it
## sit a Continue card when an autosave exists ([method set_continue]), the
## daily challenge and the endings collection. Campaigns open in Era I, so this
## screen wears the Era I look. On phones everything stacks in one scrolling
## column, only the selected role shows its details and the start button stays
## pinned to the bottom; tablets get the same column at a readable width.
##
## Signals:
##   campaign_requested(config)   Start or the daily challenge. config is
##       CampaignModes.build_config: {"role", "seed", "spectate", "mode",
##       "daily" ("YYYY-MM-DD" or ""), "options": {"human_roles",
##       "difficulty", "scenario", "start_turn", "total_turns"}}; the options
##       go straight to SimulationEngine.start_campaign.
##   start_requested(role, seed, spectate)   the original signal. It is only
##       emitted while nothing is connected to campaign_requested, so an older
##       dashboard keeps working and a newer one never starts twice.
##   continue_requested   the Continue card.
##   endings_requested    the Endings button.
##   llm_settings_requested

signal campaign_requested(config: Dictionary)
signal start_requested(role: String, seed_value: int, spectate: bool)
signal continue_requested
signal endings_requested
signal llm_settings_requested

const CARD_WIDTH := 430.0
const SETTINGS_WIDTH := 430.0
## Compact layouts on wide screens (tablets) keep a readable column.
const COMPACT_MAX_WIDTH := 760.0
## Compact columns at least this wide show the roles two abreast.
const TWO_COLUMN_MIN := 640.0
## A press that moves further than this (px) is a scroll, not a role pick.
const TAP_SLOP := 12.0
## Height of the bar that pins the start button to the bottom on phones.
const STICKY_HEIGHT := 62.0
const SUBTITLE := "A hard-systems simulation of AI, energy, labor and alignment from 2026 to 2076, in half-year turns.\nPick a perspective and a campaign. The other factions act on their own (an LLM when one is online, heuristics otherwise)."
const SUBTITLE_COMPACT := "AI, energy, labor and alignment, 2026–2076. Pick a perspective and a campaign; the other factions act on their own."
const OTHERS := ["", "one", "two", "three"]

var selected_role := SimConstants.GOVERNANCE
var selected_mode := CampaignModes.DEFAULT
var selected_scenario := Scenarios.STANDARD
var selected_difficulty := Difficulty.STANDARD
## Other factions played by people on this device (pass-and-play).
var seats: Array = []
## The daily challenge's date, "YYYY-MM-DD" ("" = today in UTC).
var today := ""
var _compact := false
var _continue_summary := {}
var _endings_progress := Vector2i(-1, -1)
var _cards := {}
var _details := {}
var _taglines: Array[Label] = []
var _sections: Array[Label] = []
var _frame: MarginContainer
var _scroll: ScrollContainer
var _panel: PanelContainer
var _box: VBoxContainer
var _start: Button
var _sticky: PanelContainer
var _grid: GridContainer
var _body: BoxContainer
var _roles_column: VBoxContainer
var _settings: VBoxContainer
var _options: HFlowContainer
var _title: Label
var _subtitle: Label
var _seed_edit: LineEdit
var _spectate_check: CheckBox
var _llm_label: Label
var _fullscreen_button: Button
var _endings_button: Button
var _continue_card: PanelContainer
var _continue_box: BoxContainer
var _continue_mark: TextureRect
var _continue_kicker: Label
var _continue_title: Label
var _continue_detail: Label
var _continue_button: Button
var _daily_card: PanelContainer
var _daily_mark: TextureRect
var _daily_date: Label
var _daily_lineup: Label
var _daily_button: Button
var _mode_chips := {}
var _scenario_chips := {}
var _difficulty_chips := {}
var _seat_chips := {}
var _mode_note: Label
var _scenario_note: Label
var _difficulty_note: Label
var _seat_note: Label
var _press_position := Vector2.INF
var _marks := {}
var _names := {}
var _era := 0


func _ready() -> void:
	# Fill the parent however we were created (scene or code).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame = UiLayout.build_overlay(self, Color(0, 0, 0, 0.96))
	_scroll = get_node("OverlayScroll")
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "OverlayPanel"
	_frame.add_child(_panel)
	var box := VBoxContainer.new()
	_box = box
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)

	_continue_card = _build_continue_card()
	box.add_child(_continue_card)

	# The Endings button wraps under the title when a phone has no room beside it.
	var title_row := HFlowContainer.new()
	title_row.name = "TitleRow"
	title_row.add_theme_constant_override("h_separation", 12)
	title_row.add_theme_constant_override("v_separation", 4)
	_title = Label.new()
	_title.theme_type_variation = "HeaderTitle"
	_title.add_theme_font_size_override("font_size", 34)
	_title.text = "SYNAPSE-2076"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title)
	_endings_button = Button.new()
	_endings_button.name = "EndingsButton"
	_endings_button.theme_type_variation = "GhostButton"
	_endings_button.icon = Glyphs.texture("book", 18)
	_endings_button.text = "Endings"
	_endings_button.tooltip_text = "Every ending you have reached"
	_endings_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_endings_button.pressed.connect(func(): endings_requested.emit())
	title_row.add_child(_endings_button)
	box.add_child(title_row)
	_subtitle = Label.new()
	_subtitle.theme_type_variation = "DimLabel"
	_subtitle.add_theme_font_size_override("font_size", 13)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.text = SUBTITLE
	box.add_child(_subtitle)

	_body = BoxContainer.new()
	_body.add_theme_constant_override("separation", 22)
	box.add_child(_body)
	_roles_column = VBoxContainer.new()
	_roles_column.add_theme_constant_override("separation", 8)
	_roles_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roles_column.add_child(_section("Perspective"))
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_roles_column.add_child(_grid)
	for role in SimConstants.FACTION_ORDER:
		var card := _role_card(role)
		_cards[role] = card
		_grid.add_child(card)
	_body.add_child(_roles_column)
	_settings = _build_settings()
	_body.add_child(_settings)
	# Desktop: under the roles; phones: near the top (see _place_daily_card).
	_daily_card = _build_daily_card()
	_roles_column.add_child(_daily_card)

	var options := HFlowContainer.new()
	_options = options
	options.add_theme_constant_override("h_separation", 14)
	options.add_theme_constant_override("v_separation", 10)
	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_label.theme_type_variation = "DimLabel"
	options.add_child(seed_label)
	_seed_edit = LineEdit.new()
	_seed_edit.name = "SeedEdit"
	_seed_edit.text = str(int(ProjectSettings.get_setting("synapse/simulation/default_seed", 2076)))
	_seed_edit.custom_minimum_size = Vector2(120, 0)
	options.add_child(_seed_edit)
	var randomize_button := Button.new()
	randomize_button.text = "Random"
	randomize_button.pressed.connect(func(): _seed_edit.text = str(randi() % 1000000))
	options.add_child(randomize_button)
	_spectate_check = CheckBox.new()
	_spectate_check.name = "SpectateCheck"
	_spectate_check.text = "Spectate (the AI plays your role)"
	_spectate_check.toggled.connect(_on_spectate_toggled)
	options.add_child(_spectate_check)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_child(spacer)
	_llm_label = Label.new()
	_llm_label.theme_type_variation = "DimLabel"
	options.add_child(_llm_label)
	var llm_button := Button.new()
	llm_button.text = "AI settings"
	llm_button.pressed.connect(func(): llm_settings_requested.emit())
	options.add_child(llm_button)
	# Browsers on phones lose a sixth of the screen to their own toolbars.
	_fullscreen_button = Button.new()
	_fullscreen_button.text = "Full screen"
	_fullscreen_button.visible = OS.has_feature("web")
	_fullscreen_button.pressed.connect(_toggle_fullscreen)
	options.add_child(_fullscreen_button)
	box.add_child(options)

	_start = Button.new()
	_start.name = "StartButton"
	_start.theme_type_variation = "AccentButton"
	_start.text = "Start campaign"
	_start.custom_minimum_size = Vector2(0, 46)
	_start.pressed.connect(_on_start_pressed)
	box.add_child(_start)
	# Phones: the start button stays on screen below the scrolling setup.
	_sticky = PanelContainer.new()
	_sticky.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_sticky.offset_top = -STICKY_HEIGHT
	_sticky.visible = false
	add_child(_sticky)
	_scroll.scroll_started.connect(func(): _press_position = Vector2.INF)
	UiLayout.pass_touch_through(_panel)
	resized.connect(_apply_layout)
	_restyle()
	select_role(selected_role)
	select_mode(selected_mode)
	select_scenario(selected_scenario)
	select_difficulty(selected_difficulty)
	_refresh_daily()
	_refresh_continue()
	_refresh_endings()
	_apply_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _sticky != null and EraTheme.style_of(self).era != _era:
		_restyle()


func _restyle() -> void:
	var s := EraTheme.style_of(self)
	_era = s.era
	(get_child(0) as ColorRect).color = Color(s.bg, 0.96)
	var bar := EraTheme.box(s.bg, s.border_strong, 0, 0, 8, 8)
	bar.border_width_top = 1
	_sticky.add_theme_stylebox_override("panel", bar)
	for role in _marks:
		(_marks[role] as TextureRect).texture = _role_mark(s, role)
		(_names[role] as Label).add_theme_font_override("font", s.font_ui_bold)
		(_names[role] as Label).add_theme_color_override("font_color", s.text_bright)
	for label in _sections:
		label.text = s.label(String(label.get_meta("raw", label.text)))
	for role in _seat_chips:
		(_seat_chips[role] as Button).add_theme_color_override("icon_normal_color", s.faction_color(role))
		(_seat_chips[role] as Button).add_theme_color_override("icon_pressed_color", s.faction_color(role))
	_daily_mark.self_modulate = s.accent
	_refresh_continue()


func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	_apply_layout()


func select_role(role: String) -> void:
	if not SimConstants.is_valid_faction(role):
		return
	selected_role = role
	seats.erase(role)
	for other in _cards:
		(_cards[other] as PanelContainer).theme_type_variation = "CardPanelSelected" if other == role else "CardPanel"
		# Phones show the objective and loss conditions of the selected role only.
		for label in _details.get(other, []):
			(label as Control).visible = not _compact or other == role
	_refresh_seats()


func select_mode(mode: String) -> void:
	if not CampaignModes.is_valid(mode):
		return
	selected_mode = mode
	_press_only(_mode_chips, mode)
	if _mode_note != null:
		_mode_note.text = "%s · %s · %d turns. %s" % [CampaignModes.display_name(mode), CampaignModes.years(mode),
			CampaignModes.turns_played(mode), CampaignModes.blurb(mode)]


func select_scenario(scenario_id: String) -> void:
	if not Scenarios.is_valid(scenario_id):
		return
	selected_scenario = scenario_id
	_press_only(_scenario_chips, scenario_id)
	if _scenario_note != null:
		_scenario_note.text = String(Scenarios.LIST[scenario_id]["summary"])


func select_difficulty(preset_id: String) -> void:
	if not Difficulty.is_valid(preset_id):
		return
	selected_difficulty = preset_id
	_press_only(_difficulty_chips, preset_id)
	if _difficulty_note != null:
		_difficulty_note.text = String(Difficulty.PRESETS[preset_id]["summary"])


## Seats [param role] at the table (another person plays it on this device).
func set_seat(role: String, seated: bool) -> void:
	if not SimConstants.is_valid_faction(role) or role == selected_role:
		return
	if seated and not seats.has(role) and not is_spectating():
		seats.append(role)
	elif not seated:
		seats.erase(role)
	_refresh_seats()


func set_spectate(spectating: bool) -> void:
	_spectate_check.button_pressed = spectating


func is_spectating() -> bool:
	return _spectate_check != null and _spectate_check.button_pressed


func set_llm_status(text: String) -> void:
	if _llm_label != null:
		_llm_label.text = text
		_fit_options_row()


func set_seed(seed_value: int) -> void:
	_seed_edit.text = str(seed_value)


## The Continue card: SaveManager.summary() ({} hides it).
func set_continue(summary: Dictionary) -> void:
	_continue_summary = summary.duplicate(true)
	_refresh_continue()


func has_continue() -> bool:
	return _continue_card != null and _continue_card.visible


## Shows "Endings · n of 32" on the Endings button (EndingsBook.progress()).
func set_endings_progress(progress: Vector2i) -> void:
	_endings_progress = progress
	_refresh_endings()


## Uses [param date] ("YYYY-MM-DD") as today for the daily challenge ("" =
## the real UTC date).
func set_today(date: String) -> void:
	today = date
	_refresh_daily()


## The configuration Start would emit now.
func build_config() -> Dictionary:
	var text := _seed_edit.text.strip_edges()
	var seed_value := int(text) if text.is_valid_int() else hash(text)
	return CampaignModes.build_config(selected_role, seed_value, selected_mode, selected_scenario, selected_difficulty, seats,
		is_spectating())


## Today's daily challenge (CampaignModes.daily_config).
func daily_config() -> Dictionary:
	return CampaignModes.daily_config(today)


func _apply_layout() -> void:
	if _panel == null:
		return
	var width := UiLayout.panel_width(size.x, 0.0, _compact)
	if _compact:
		width = minf(width, COMPACT_MAX_WIDTH)
	_panel.custom_minimum_size = Vector2(width if _compact else 0.0, 0)
	_body.vertical = _compact
	_body.add_theme_constant_override("separation", 16 if _compact else 22)
	_grid.columns = (2 if width - 44.0 >= TWO_COLUMN_MIN else 1) if _compact else 2
	for role in _cards:
		(_cards[role] as Control).custom_minimum_size = Vector2(0.0 if _compact else CARD_WIDTH, 0)
	for tagline in _taglines:
		tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if _compact else TextServer.AUTOWRAP_OFF
	_settings.custom_minimum_size = Vector2(0.0 if _compact else SETTINGS_WIDTH, 0)
	_settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _compact else Control.SIZE_FILL
	_title.add_theme_font_size_override("font_size", 26 if _compact else 34)
	_subtitle.add_theme_font_size_override("font_size", 12 if _compact else 13)
	_subtitle.text = SUBTITLE_COMPACT if _compact else SUBTITLE
	# Desktop keeps the original two-line subtitle; phones wrap it to the panel.
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if _compact else TextServer.AUTOWRAP_OFF
	_continue_box.vertical = _compact
	_continue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _compact else Control.SIZE_SHRINK_END
	_daily_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _compact else Control.SIZE_SHRINK_END
	for chips in [_mode_chips, _scenario_chips, _difficulty_chips, _seat_chips]:
		for key in chips:
			(chips[key] as Control).custom_minimum_size = Vector2(0, 44 if _compact else 34)
	for button in [_continue_button, _daily_button, _endings_button]:
		(button as Control).custom_minimum_size = Vector2(0, 44 if _compact else 36)
	_place_daily_card()
	var start_parent: Node = _sticky if _compact else _box
	if _start.get_parent() != start_parent:
		_start.reparent(start_parent, false)
	_sticky.visible = _compact
	_scroll.offset_bottom = -STICKY_HEIGHT if _compact else 0.0
	UiLayout.set_overlay_margin(_frame, _compact)
	_fit_options_row()
	select_role(selected_role)


## The daily challenge sits under the roles on desktop (balancing the two
## columns) and right below the title on phones, before the long setup.
func _place_daily_card() -> void:
	var parent: Node = _box if _compact else _roles_column
	if _daily_card.get_parent() != parent:
		_daily_card.reparent(parent, false)
	parent.move_child(_daily_card, _subtitle.get_index() + 1 if _compact else -1)


## Desktop keeps the options on one line; phones let them wrap.
func _fit_options_row() -> void:
	if _options == null:
		return
	var width := 0.0
	if not _compact:
		var count := 0
		for child in _options.get_children():
			if (child as Control).visible:
				width += (child as Control).get_combined_minimum_size().x
				count += 1
		width += _options.get_theme_constant("h_separation") * maxi(count - 1, 0)
	_options.custom_minimum_size = Vector2(width, 0)


func _toggle_fullscreen() -> void:
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)


# --- Campaign settings ----------------------------------------------------------------

func _build_settings() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "Settings"
	column.add_theme_constant_override("separation", 8)
	column.add_child(_section("Length"))
	var modes := _chip_row("Modes")
	var mode_group := ButtonGroup.new()
	for mode in CampaignModes.ORDER:
		var chip := _chip("Mode_" + mode, CampaignModes.short_name(mode), mode_group)
		chip.tooltip_text = "%s, %s" % [CampaignModes.display_name(mode), CampaignModes.years(mode)]
		chip.toggled.connect(_on_chip_toggled.bind(select_mode, mode))
		_mode_chips[mode] = chip
		modes.add_child(chip)
	column.add_child(modes)
	_mode_note = _note("ModeNote")
	column.add_child(_mode_note)

	column.add_child(_section("World"))
	var scenarios := _chip_row("Scenarios")
	var scenario_group := ButtonGroup.new()
	for scenario_id in Scenarios.ORDER:
		var info: Dictionary = Scenarios.LIST[scenario_id]
		var chip := _chip("Scenario_" + scenario_id, String(info["name"]), scenario_group, String(info.get("glyph", "world")))
		chip.toggled.connect(_on_chip_toggled.bind(select_scenario, scenario_id))
		_scenario_chips[scenario_id] = chip
		scenarios.add_child(chip)
	column.add_child(scenarios)
	_scenario_note = _note("ScenarioNote")
	column.add_child(_scenario_note)

	column.add_child(_section("Difficulty"))
	var presets := _chip_row("Difficulties")
	var difficulty_group := ButtonGroup.new()
	for preset_id in Difficulty.ORDER:
		var chip := _chip("Difficulty_" + preset_id, Difficulty.display_name(preset_id), difficulty_group)
		chip.toggled.connect(_on_chip_toggled.bind(select_difficulty, preset_id))
		_difficulty_chips[preset_id] = chip
		presets.add_child(chip)
	column.add_child(presets)
	_difficulty_note = _note("DifficultyNote")
	column.add_child(_difficulty_note)

	column.add_child(_section("Players"))
	var seat_row := _chip_row("Seats")
	for role in SimConstants.FACTION_ORDER:
		var chip := _chip("Seat_" + role, "+ " + UiFormat.role_name(role), null, Glyphs.for_faction(role))
		chip.tooltip_text = "Another person plays the %s on this device" % UiFormat.role_name(role)
		chip.toggled.connect(_on_seat_toggled.bind(role))
		_seat_chips[role] = chip
		seat_row.add_child(chip)
	column.add_child(seat_row)
	_seat_note = _note("SeatNote")
	column.add_child(_seat_note)
	return column


func _section(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = "PanelTitle"
	label.set_meta("raw", text)
	label.text = text
	_sections.append(label)
	return label


func _chip_row(node_name: String) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.name = node_name
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	return row


func _chip(node_name: String, text: String, group: ButtonGroup, glyph: String = "") -> Button:
	var chip := Button.new()
	chip.name = node_name
	chip.theme_type_variation = "ChipButton"
	chip.toggle_mode = true
	chip.button_group = group
	chip.text = text
	if glyph != "":
		chip.icon = Glyphs.texture(glyph, 16)
	return chip


func _note(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.theme_type_variation = "DimLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## A chip of an exclusive group was pressed: [param select] the [param id].
func _on_chip_toggled(pressed: bool, select: Callable, id: String) -> void:
	if pressed:
		select.call(id)


func _on_seat_toggled(pressed: bool, role: String) -> void:
	set_seat(role, pressed)


## Presses the chip for [param selected] and releases the rest (without signals).
static func _press_only(chips: Dictionary, selected: String) -> void:
	for key in chips:
		(chips[key] as Button).set_pressed_no_signal(String(key) == selected)


func _refresh_seats() -> void:
	if _seat_note == null:
		return
	var spectating := is_spectating()
	for role in _seat_chips:
		var chip: Button = _seat_chips[role]
		chip.visible = role != selected_role
		chip.disabled = spectating
		chip.set_pressed_no_signal(seats.has(role))
	if spectating:
		_seat_note.text = "Spectating: the AI plays every side."
	elif seats.is_empty():
		_seat_note.text = "Just you. The other three factions act on their own."
	else:
		var others := SimConstants.FACTION_ORDER.size() - 1 - seats.size()
		_seat_note.text = "%d players take turns on this device.%s" % [seats.size() + 1,
			(" The other %s %s on their own." % [OTHERS[others], "acts" if others == 1 else "act"]) if others > 0 else ""]


func _on_spectate_toggled(spectating: bool) -> void:
	if spectating:
		seats.clear()
	_refresh_seats()


# --- Continue, daily challenge, endings --------------------------------------------------

func _build_continue_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "ContinueCard"
	card.theme_type_variation = "CardPanelSelected"
	card.visible = false
	_continue_box = BoxContainer.new()
	_continue_box.add_theme_constant_override("separation", 12)
	card.add_child(_continue_box)
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 12)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_continue_mark = TextureRect.new()
	_continue_mark.custom_minimum_size = Vector2(44, 44)
	_continue_mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_continue_mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_continue_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_child(_continue_mark)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_continue_kicker = Label.new()
	_continue_kicker.theme_type_variation = "Kicker"
	_continue_kicker.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_continue_kicker)
	_continue_title = Label.new()
	_continue_title.name = "ContinueTitle"
	_continue_title.theme_type_variation = "PanelTitle"
	_continue_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_continue_title)
	_continue_detail = Label.new()
	_continue_detail.name = "ContinueDetail"
	_continue_detail.theme_type_variation = "DimLabel"
	_continue_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_continue_detail)
	info.add_child(text)
	_continue_box.add_child(info)
	_continue_button = Button.new()
	_continue_button.name = "ContinueButton"
	_continue_button.theme_type_variation = "AccentButton"
	_continue_button.text = "Continue"
	_continue_button.icon = Glyphs.texture("play", 14)
	_continue_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_continue_button.pressed.connect(func(): continue_requested.emit())
	_continue_box.add_child(_continue_button)
	return card


func _refresh_continue() -> void:
	if _continue_card == null:
		return
	var summary := _continue_summary
	var role := String(summary.get("role", ""))
	_continue_card.visible = not summary.is_empty() and SimConstants.is_valid_faction(role)
	if not _continue_card.visible:
		return
	var s := EraTheme.style_of(self)
	_continue_mark.texture = _role_mark(s, role, 44)
	var saved := String(summary.get("saved_at_text", ""))
	_continue_kicker.text = s.label("Continue") + (" · saved %s" % saved if saved != "" else "")
	var era := int(summary.get("era", 1))
	_continue_title.text = "%s · %d · Era %s" % [UiFormat.role_name(role), int(summary.get("year", 2026)),
		EraStyle.ROMAN.get(clampi(era, 1, 3), "I")]
	var parts: Array[String] = []
	for key in ["mode_name", "scenario_name", "difficulty_name"]:
		if String(summary.get(key, "")) != "":
			parts.append(String(summary[key]))
	var players := int(summary.get("players", (summary.get("humans", []) as Array).size()))
	if players > 1:
		parts.append("%d players" % players)
	if String(summary.get("daily", "")) != "":
		parts.append("Daily %s" % summary["daily"])
	if bool(summary.get("spectate", false)):
		parts.append("Spectating")
	_continue_detail.text = " · ".join(parts)
	UiLayout.pass_touch_through(_continue_card)


func _build_daily_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "DailyCard"
	card.theme_type_variation = "InsetPanel"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_daily_mark = Glyphs.icon("clock", 20)
	_daily_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_daily_mark)
	var title := Label.new()
	title.theme_type_variation = "PanelTitle"
	title.text = "Daily challenge"
	title.set_meta("raw", "Daily challenge")
	_sections.append(title)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_daily_date = Label.new()
	_daily_date.name = "DailyDate"
	_daily_date.theme_type_variation = "ValueLabel"
	head.add_child(_daily_date)
	column.add_child(head)
	_daily_lineup = _note("DailyLineup")
	column.add_child(_daily_lineup)
	_daily_button = Button.new()
	_daily_button.name = "DailyButton"
	_daily_button.text = "Play today's challenge"
	_daily_button.pressed.connect(func(): _emit(daily_config()))
	column.add_child(_daily_button)
	return card


func _refresh_daily() -> void:
	if _daily_lineup == null:
		return
	var config := daily_config()
	var mode := String(config["mode"])
	_daily_date.text = String(config["daily"])
	_daily_lineup.text = "%s · %s · %s, %s. The same world for everyone today, on Standard." % [
		UiFormat.role_name(String(config["role"])), Scenarios.display_name(String(config["options"]["scenario"])),
		CampaignModes.display_name(mode), CampaignModes.years(mode)]


func _refresh_endings() -> void:
	if _endings_button == null:
		return
	_endings_button.text = "Endings" if _endings_progress.y <= 0 else "Endings · %d of %d" % [_endings_progress.x, _endings_progress.y]


# --- Roles ----------------------------------------------------------------------------

func _role_card(role: String) -> PanelContainer:
	var info: Dictionary = SimConstants.ROLE_INFO[role]
	var card := PanelContainer.new()
	card.name = "Role_" + role
	card.theme_type_variation = "CardPanel"
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Pick on release, and only when the finger did not drag (a drag scrolls the list).
	card.gui_input.connect(func(event: InputEvent):
		if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
			return
		if event.pressed:
			_press_position = event.global_position
		elif _press_position != Vector2.INF and event.global_position.distance_to(_press_position) <= TAP_SLOP:
			_press_position = Vector2.INF
			select_role(role))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var mark := TextureRect.new()
	mark.custom_minimum_size = Vector2(40, 40)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(mark)
	_marks[role] = mark
	var name_label := Label.new()
	name_label.text = UiFormat.role_title(role)
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(name_label)
	_names[role] = name_label
	box.add_child(head)
	var tagline := Label.new()
	tagline.text = String(info["tagline"])
	tagline.add_theme_font_size_override("font_size", 13)
	box.add_child(tagline)
	_taglines.append(tagline)
	var currencies: Array[String] = []
	for key in FactionRegistry.resource_info_for(role):
		currencies.append(UiFormat.resource_label(role, key))
	var details: Array = []
	for line in ["Currencies · " + ", ".join(currencies), "Objective · " + String(info["objective"]), "Loss · " + String(info["loss"])]:
		var label := Label.new()
		label.text = line
		label.theme_type_variation = "DimLabel"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 11)
		box.add_child(label)
		details.append(label)
	_details[role] = details
	for child in box.find_children("*", "Control", true, false):
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card


## The faction's glyph on a tile in its color.
func _role_mark(s: EraStyle, role: String, size_px: int = 40) -> Texture2D:
	return Glyphs.tile(Glyphs.for_faction(role), size_px, s.faction_color(role), s.bg, 10 if s.era != 3 else 18, 0.6)


func _on_start_pressed() -> void:
	_emit(build_config())


## Sends [param config] on campaign_requested, and on the original
## start_requested while nothing listens to the new signal.
func _emit(config: Dictionary) -> void:
	campaign_requested.emit(config)
	if campaign_requested.get_connections().is_empty():
		start_requested.emit(String(config["role"]), int(config["seed"]), bool(config["spectate"]))
