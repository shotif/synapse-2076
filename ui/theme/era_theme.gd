class_name EraTheme
extends RefCounted
## Builds a Theme from an EraStyle. Besides the stock controls it defines:
##
##   Labels:  HeaderTitle, DisplayTitle, PanelTitle, DimLabel, ValueLabel,
##            Caption, Kicker
##   Buttons: AccentButton, GhostButton, ChipButton (toggle chips and
##            segmented controls), TabButton (bottom tab bars)
##   Panels:  OverlayPanel, CardPanel, CardPanelSelected, InsetPanel, ChipPanel
##
## and the "Era" type: colors (bg, surface, raised, overlay, border,
## border_strong, shade, text, text_dim, text_bright, accent, accent_hover,
## on_accent, good, bad, warn, critical, metric_<key>, faction_<id>), fonts
## (ui, ui_bold, display, mono, mono_bold) and constants (era, radius,
## control_radius), so custom-drawn widgets follow the active era.

const COLOR_NAMES := ["bg", "surface", "raised", "overlay", "border", "border_strong", "shade", "text", "text_dim",
	"text_bright", "accent", "accent_hover", "on_accent", "good", "bad", "warn", "critical"]

static var _cache := {}


static func get_theme(era: int) -> Theme:
	var key := clampi(era, 1, 3)
	if not _cache.has(key):
		_cache[key] = build(EraStyle.for_era(key))
	return _cache[key]


## The EraStyle behind [param control]'s inherited theme (Era I when none).
static func style_of(control: Control) -> EraStyle:
	if control != null and control.has_theme_constant("era", "Era"):
		return EraStyle.for_era(control.get_theme_constant("era", "Era"))
	return EraStyle.for_era(1)


static func build(s: EraStyle) -> Theme:
	var t := Theme.new()
	t.default_font = s.font_ui
	t.default_font_size = 14

	# Era data for custom-drawn widgets.
	t.set_constant("era", "Era", s.era)
	t.set_constant("radius", "Era", s.radius)
	t.set_constant("control_radius", "Era", s.control_radius)
	for color_name in COLOR_NAMES:
		t.set_color(color_name, "Era", s.get(color_name))
	for key in s.metric:
		t.set_color("metric_" + key, "Era", s.metric[key])
	for faction_id in s.faction:
		t.set_color("faction_" + faction_id, "Era", s.faction[faction_id])
	t.set_font("ui", "Era", s.font_ui)
	t.set_font("ui_bold", "Era", s.font_ui_bold)
	t.set_font("display", "Era", s.font_display)
	t.set_font("mono", "Era", s.font_mono)
	t.set_font("mono_bold", "Era", s.font_mono_bold)

	# Panels.
	t.set_stylebox("panel", "PanelContainer", panel(s, s.surface, s.border, s.radius, 10))
	t.set_stylebox("panel", "Panel", panel(s, s.surface, s.border, s.radius, 0))
	t.set_type_variation("OverlayPanel", "PanelContainer")
	var overlay_box := panel(s, s.overlay, s.border_strong if s.border_width > 0 else s.border, s.radius + 4, 22)
	overlay_box.shadow_color = Color(0, 0, 0, 0.55)
	overlay_box.shadow_size = 24
	t.set_stylebox("panel", "OverlayPanel", overlay_box)
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", panel(s, s.raised, s.border, s.control_radius + 4, 12))
	t.set_type_variation("CardPanelSelected", "PanelContainer")
	var selected := panel(s, s.raised.lerp(s.accent, 0.12), s.accent, s.control_radius + 4, 12)
	selected.set_border_width_all(2)
	t.set_stylebox("panel", "CardPanelSelected", selected)
	t.set_type_variation("InsetPanel", "PanelContainer")
	t.set_stylebox("panel", "InsetPanel", panel(s, s.bg.lerp(s.surface, 0.5), s.border, s.control_radius, 10))
	t.set_type_variation("ChipPanel", "PanelContainer")
	var chip := box(s.raised, s.border, s.border_width, 999, 10, 4, s.corner_detail)
	t.set_stylebox("panel", "ChipPanel", chip)

	# Buttons.
	var r := s.control_radius
	var border_w := maxi(s.border_width, 0)
	_button_styles(t, "Button", s,
		box(s.raised, s.border, border_w, r, 12, 8, s.corner_detail),
		box(s.raised.lerp(s.text, 0.07), s.border_strong, border_w, r, 12, 8, s.corner_detail),
		box(s.raised.lerp(s.accent, 0.22), s.accent, border_w, r, 12, 8, s.corner_detail),
		box(Color(s.raised, 0.5), Color(s.border, s.border.a * 0.5), border_w, r, 12, 8, s.corner_detail))
	t.set_color("font_color", "Button", s.text)
	t.set_color("font_hover_color", "Button", s.accent if s.era == 2 else s.text_bright)
	t.set_color("font_pressed_color", "Button", s.text_bright)
	t.set_color("font_hover_pressed_color", "Button", s.text_bright)
	t.set_color("font_focus_color", "Button", s.text)
	t.set_color("font_disabled_color", "Button", Color(s.text_dim, 0.55))
	t.set_color("icon_normal_color", "Button", s.text)
	t.set_color("icon_hover_color", "Button", s.text_bright)
	t.set_color("icon_pressed_color", "Button", s.text_bright)
	t.set_color("icon_disabled_color", "Button", Color(s.text_dim, 0.5))
	t.set_font("font", "Button", s.font_ui_bold if s.era != 1 else s.font_ui)
	t.set_constant("h_separation", "Button", 8)

	t.set_type_variation("AccentButton", "Button")
	_button_styles(t, "AccentButton", s,
		box(s.accent, s.accent, 0, r, 16, 9, s.corner_detail, s.glow),
		box(s.accent_hover, s.accent_hover, 0, r, 16, 9, s.corner_detail, s.glow),
		box(s.accent.darkened(0.18), s.accent, 0, r, 16, 9, s.corner_detail, s.glow),
		box(Color(s.raised, 0.6), s.border, border_w, r, 16, 9, s.corner_detail))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(state, "AccentButton", s.on_accent)
	t.set_color("font_disabled_color", "AccentButton", Color(s.text_dim, 0.6))
	t.set_color("icon_normal_color", "AccentButton", s.on_accent)
	t.set_font("font", "AccentButton", s.font_ui_bold)

	t.set_type_variation("GhostButton", "Button")
	var clear := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, r, 10, 8, s.corner_detail)
	_button_styles(t, "GhostButton", s, clear,
		box(Color(s.text, 0.07), Color(0, 0, 0, 0), 0, r, 10, 8, s.corner_detail),
		box(Color(s.accent, 0.16), Color(0, 0, 0, 0), 0, r, 10, 8, s.corner_detail), clear)
	t.set_color("font_color", "GhostButton", s.accent if s.era != 3 else s.text)
	t.set_color("font_hover_color", "GhostButton", s.accent_hover)
	t.set_color("font_pressed_color", "GhostButton", s.accent_hover)
	t.set_color("font_disabled_color", "GhostButton", Color(s.text_dim, 0.5))

	t.set_type_variation("ChipButton", "Button")
	_button_styles(t, "ChipButton", s,
		box(Color(s.raised, 0.7), s.border, maxi(border_w, 1), r, 12, 6, s.corner_detail),
		box(s.raised.lerp(s.text, 0.06), s.border_strong, maxi(border_w, 1), r, 12, 6, s.corner_detail),
		box(s.raised.lerp(s.accent, 0.2), s.accent, maxi(border_w, 1) + (1 if s.era == 1 else 0), r, 12, 6, s.corner_detail),
		box(Color(s.raised, 0.35), Color(s.border, 0.4), maxi(border_w, 1), r, 12, 6, s.corner_detail))
	t.set_color("font_color", "ChipButton", s.text)
	t.set_color("font_pressed_color", "ChipButton", s.text_bright)
	t.set_color("font_hover_pressed_color", "ChipButton", s.text_bright)
	t.set_color("font_hover_color", "ChipButton", s.text_bright)
	t.set_font_size("font_size", "ChipButton", 13)

	t.set_type_variation("TabButton", "Button")
	var tab_clear := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, r, 6, 6, s.corner_detail)
	var tab_on := box(Color(s.accent, 0.12) if s.era != 1 else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, r, 6, 6, s.corner_detail)
	_button_styles(t, "TabButton", s, tab_clear, box(Color(s.text, 0.05), Color(0, 0, 0, 0), 0, r, 6, 6, s.corner_detail), tab_on, tab_clear)
	t.set_color("font_color", "TabButton", s.text_dim)
	t.set_color("font_hover_color", "TabButton", s.text)
	t.set_color("font_pressed_color", "TabButton", s.accent)
	t.set_color("font_hover_pressed_color", "TabButton", s.accent)
	t.set_color("icon_normal_color", "TabButton", s.text_dim)
	t.set_color("icon_hover_color", "TabButton", s.text)
	t.set_color("icon_pressed_color", "TabButton", s.accent)
	t.set_color("icon_hover_pressed_color", "TabButton", s.accent)
	t.set_font("font", "TabButton", s.font_ui_bold)
	t.set_font_size("font_size", "TabButton", 11)

	# Labels.
	t.set_color("font_color", "Label", s.text)
	_label(t, "HeaderTitle", s.font_display, 20, s.accent if s.era == 2 else s.text_bright)
	_label(t, "DisplayTitle", s.font_display, 30, s.text_bright)
	_label(t, "PanelTitle", s.font_ui_bold, 13 if s.labels_upper else 15, s.accent if s.era == 2 else s.text_bright)
	_label(t, "DimLabel", s.font_ui, 12, s.text_dim)
	_label(t, "ValueLabel", s.font_mono_bold, 14, s.text_bright)
	_label(t, "Caption", s.font_ui, 11, s.text_dim)
	_label(t, "Kicker", s.font_mono, 11, s.accent)

	# Progress bars and sliders.
	t.set_stylebox("background", "ProgressBar", box(Color(s.text, 0.1), Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("fill", "ProgressBar", box(s.accent, s.accent, 0, 3))
	t.set_color("font_color", "ProgressBar", s.text_bright)
	var rail := box(Color(s.text, 0.16), Color(0, 0, 0, 0), 0, 3)
	rail.content_margin_top = 2
	rail.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", rail)
	var filled := box(s.accent, s.accent, 0, 3)
	filled.content_margin_top = 2
	filled.content_margin_bottom = 2
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)
	t.set_icon("grabber", "HSlider", CyberTheme.disc_texture(16, s.text_bright))
	t.set_icon("grabber_highlight", "HSlider", CyberTheme.disc_texture(18, s.text_bright))
	t.set_icon("grabber_disabled", "HSlider", CyberTheme.disc_texture(14, s.text_dim))

	# Text input.
	for type_name in ["LineEdit", "SpinBox"]:
		t.set_stylebox("normal", type_name, box(s.bg.lerp(s.surface, 0.4), s.border_strong, 1, r, 10, 7, s.corner_detail))
		t.set_stylebox("focus", type_name, box(Color(0, 0, 0, 0), s.accent, 2, r, 10, 7, s.corner_detail))
		t.set_stylebox("read_only", type_name, box(s.surface, s.border, 1, r, 10, 7, s.corner_detail))
	t.set_color("font_color", "LineEdit", s.text_bright)
	t.set_color("caret_color", "LineEdit", s.accent)
	t.set_color("selection_color", "LineEdit", Color(s.accent, 0.3))
	t.set_color("font_placeholder_color", "LineEdit", s.text_dim)

	# Check boxes.
	var check_r := 5 if s.era != 3 else 9
	t.set_icon("unchecked", "CheckBox", Glyphs.checkbox_texture(18, false, s.raised, s.border_strong, s.on_accent, check_r))
	t.set_icon("checked", "CheckBox", Glyphs.checkbox_texture(18, true, s.accent, s.accent, s.on_accent, check_r))
	t.set_icon("unchecked_disabled", "CheckBox", Glyphs.checkbox_texture(18, false, Color(s.raised, 0.5), Color(s.border, 0.5), s.on_accent, check_r))
	t.set_icon("checked_disabled", "CheckBox", Glyphs.checkbox_texture(18, true, Color(s.text_dim, 0.6), Color(s.text_dim, 0.6), s.bg, check_r))
	t.set_color("font_color", "CheckBox", s.text)
	t.set_color("font_hover_color", "CheckBox", s.text_bright)
	t.set_color("font_pressed_color", "CheckBox", s.text_bright)
	t.set_color("font_hover_pressed_color", "CheckBox", s.text_bright)
	t.set_color("font_disabled_color", "CheckBox", Color(s.text_dim, 0.6))
	t.set_constant("h_separation", "CheckBox", 8)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(state, "CheckBox", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 4, 3))

	# Rich text.
	t.set_font("normal_font", "RichTextLabel", s.font_ui)
	t.set_font("bold_font", "RichTextLabel", s.font_ui_bold)
	t.set_font("mono_font", "RichTextLabel", s.font_mono)
	t.set_font_size("normal_font_size", "RichTextLabel", 13)
	t.set_font_size("bold_font_size", "RichTextLabel", 13)
	t.set_color("default_color", "RichTextLabel", s.text)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())

	# Scroll bars: thin rails.
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 3, 2, 2))
		t.set_stylebox("grabber", bar, box(Color(s.text, 0.22), Color(0, 0, 0, 0), 0, 3, 3, 3))
		t.set_stylebox("grabber_highlight", bar, box(Color(s.text, 0.35), Color(0, 0, 0, 0), 0, 3, 3, 3))
		t.set_stylebox("grabber_pressed", bar, box(s.accent, s.accent, 0, 3, 3, 3))

	# Tooltips.
	t.set_stylebox("panel", "TooltipPanel", box(s.overlay, s.border_strong, 1, r, 10, 7, s.corner_detail))
	t.set_color("font_color", "TooltipLabel", s.text_bright)
	t.set_font_size("font_size", "TooltipLabel", 12)

	t.set_constant("separation", "HSeparator", 10)
	t.set_stylebox("separator", "HSeparator", CyberTheme.line_box(s.border))
	t.set_stylebox("separator", "VSeparator", CyberTheme.line_box(s.border, true))
	return t


## A panel StyleBox in the era's shape language (Era III cells get uneven corners).
static func panel(s: EraStyle, bg: Color, border: Color, radius: int, margin: float) -> StyleBoxFlat:
	var style := box(bg, border, s.border_width, radius, margin, -1.0, s.corner_detail)
	if s.organic:
		style.corner_radius_top_left = int(radius * 1.15)
		style.corner_radius_top_right = int(radius * 0.7)
		style.corner_radius_bottom_right = int(radius * 1.25)
		style.corner_radius_bottom_left = int(radius * 0.8)
	return style


static func box(bg: Color, border: Color, border_width: int = 1, radius: int = 4, margin_h: float = 0.0,
		margin_v: float = -1.0, corner_detail: int = 8, glow: float = 0.0) -> StyleBoxFlat:
	var style := CyberTheme.box(bg, border, border_width, radius, margin_h, margin_v)
	style.corner_detail = corner_detail
	if glow > 0.0:
		style.shadow_color = Color(border, glow)
		style.shadow_size = 8
	return style


static func _button_styles(t: Theme, type_name: String, s: EraStyle, normal: StyleBoxFlat, hover: StyleBoxFlat,
		pressed: StyleBoxFlat, disabled: StyleBoxFlat) -> void:
	t.set_stylebox("normal", type_name, normal)
	t.set_stylebox("hover", type_name, hover)
	t.set_stylebox("pressed", type_name, pressed)
	t.set_stylebox("hover_pressed", type_name, pressed)
	t.set_stylebox("disabled", type_name, disabled)
	var focus := box(Color(0, 0, 0, 0), s.accent, 2, s.control_radius, 12, 8, s.corner_detail)
	t.set_stylebox("focus", type_name, focus)


static func _label(t: Theme, type_name: String, label_font: Font, font_size: int, color: Color) -> void:
	t.set_type_variation(type_name, "Label")
	t.set_font("font", type_name, label_font)
	t.set_font_size("font_size", type_name, font_size)
	t.set_color("font_color", type_name, color)
