class_name NavBar
extends PanelContainer
## Tab bar of the compact layouts in the active era's idiom: Era I a
## translucent bar with icons over labels, Era II an outlined bar with capital
## labels and a lit underline, Era III a row of round icon buttons. A dot
## flags a tab that needs attention (a decision waiting on ACT).

signal tab_selected(tab: String)

const ROUND_SIZE := 52.0

var active := ""
var _tabs: Array = []
var _buttons := {}
var _dots := {}
var _badges := {}
var _row: HBoxContainer
var _restyling := false


func _ready() -> void:
	_row = HBoxContainer.new()
	_row.name = "Tabs"
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_row)
	if not _tabs.is_empty():
		_rebuild()


## [param tabs]: Array of {id, label, glyph}.
func setup(tabs: Array) -> void:
	_tabs = tabs.duplicate(true)
	if _row != null:
		_rebuild()


func set_active(tab: String) -> void:
	active = tab
	_restyle()


## Shows or hides the attention dot on [param tab].
func set_badge(tab: String, on: bool) -> void:
	_badges[tab] = on
	if _dots.has(tab):
		(_dots[tab] as Control).visible = on and tab != active


## Renames [param tab] and changes its glyph (the LENS tab takes the lens's name).
func set_tab(tab: String, label: String, glyph: String) -> void:
	for entry in _tabs:
		if String(entry["id"]) == tab:
			entry["label"] = label
			entry["glyph"] = glyph
	_restyle()


func set_tab_visible(tab: String, shown: bool) -> void:
	if _buttons.has(tab):
		(_buttons[tab] as Button).visible = shown


func get_button(tab: String) -> Button:
	return _buttons.get(tab)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _row != null:
		_restyle()


func _rebuild() -> void:
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	_buttons.clear()
	_dots.clear()
	for tab in _tabs:
		var tab_id := String(tab["id"])
		var button := Button.new()
		button.name = tab_id.capitalize() + "Tab"
		button.focus_mode = Control.FOCUS_NONE
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.tooltip_text = String(tab["label"]).capitalize()
		button.pressed.connect(func(): tab_selected.emit(tab_id))
		var dot := Panel.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.visible = false
		button.add_child(dot)
		_dots[tab_id] = dot
		_buttons[tab_id] = button
		_row.add_child(button)
	_restyle()


func _restyle() -> void:
	# Overriding our own panel style re-sends NOTIFICATION_THEME_CHANGED.
	if _row == null or _restyling:
		return
	_restyling = true
	_apply_styles()
	_restyling = false


func _apply_styles() -> void:
	var s := EraTheme.style_of(self)
	var round_tabs := s.era == 3
	_row.add_theme_constant_override("separation", 18 if round_tabs else 0)
	add_theme_stylebox_override("panel", _bar_style(s))
	for tab in _tabs:
		var tab_id := String(tab["id"])
		var button: Button = _buttons.get(tab_id)
		if button == null:
			continue
		var on := tab_id == active
		var glyph := String(tab["glyph"])
		button.icon = Glyphs.texture(glyph, 22 if round_tabs else 24, 1.8)
		button.text = "" if round_tabs else s.label(String(tab["label"]).capitalize())
		button.custom_minimum_size = Vector2(ROUND_SIZE, ROUND_SIZE) if round_tabs else Vector2(0, 54 if s.era == 1 else 56)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if round_tabs else Control.SIZE_EXPAND_FILL
		button.add_theme_font_override("font", s.font_ui_bold)
		button.add_theme_font_size_override("font_size", 10 if s.era == 1 else 11)
		button.add_theme_constant_override("h_separation", 3)
		var fg := _tab_color(s, on)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, fg)
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
			button.add_theme_color_override(state, fg)
		var style := _tab_style(s, on)
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(state, style)
		var dot: Panel = _dots[tab_id]
		dot.add_theme_stylebox_override("panel", EraTheme.box(s.warn, s.warn, 0, 5))
		dot.size = Vector2(9, 9)
		if round_tabs:
			dot.position = Vector2(ROUND_SIZE - 14, 6)
		else:
			dot.anchor_left = 0.5
			dot.anchor_right = 0.5
			dot.offset_left = 8
			dot.offset_right = 17
			dot.offset_top = 6
			dot.offset_bottom = 15
		dot.visible = bool(_badges.get(tab_id, false)) and not on


func _tab_color(s: EraStyle, on: bool) -> Color:
	if s.era == 3:
		return s.bg if on else s.text
	if on:
		return s.accent
	return Color("#8E8E93") if s.era == 1 else s.text_dim


func _bar_style(s: EraStyle) -> StyleBoxFlat:
	match s.era:
		1:
			var bar := EraTheme.box(Color("#161618", 0.94), Color(1, 1, 1, 0.14), 0, 0, 4, 2)
			bar.border_width_top = 1
			return bar
		2:
			var holo := EraTheme.box(Color(s.bg, 0.88), Color(s.accent, 0.22), 0, 0, 4, 0)
			holo.border_width_top = 1
			return holo
	return EraTheme.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 8, 8)


func _tab_style(s: EraStyle, on: bool) -> StyleBoxFlat:
	match s.era:
		1:
			return EraTheme.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 2, 5)
		2:
			var tab := EraTheme.box(Color(s.accent, 0.06) if on else Color(0, 0, 0, 0), s.accent, 0, 0, 2, 6)
			tab.border_width_bottom = 2 if on else 0
			return tab
	var round := EraTheme.box(s.text if on else Color(0, 0, 0, 0), Color(s.text, 0.28), 0 if on else 1, int(ROUND_SIZE / 2.0), 0, 0)
	round.corner_detail = 12
	return round
