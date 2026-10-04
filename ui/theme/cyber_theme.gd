class_name CyberTheme
extends RefCounted
## Builds the Cyber-Telemetry Theme at runtime (PRD section 8.1): obsidian
## panels with charcoal vector outlines, cyan accents, amber warnings and
## crimson alerts. Monospaced data (JetBrains Mono) with Inter headers.
##
## Type variations: HeaderTitle, PanelTitle, DimLabel, ValueLabel, AccentButton,
## OverlayPanel, CardPanel, CardPanelSelected.

const P := preload("res://ui/theme/cyber_palette.gd")

static var _cached: Theme


## The dashboard's starting theme (Era I). See EraTheme for the per-era themes.
static func get_theme() -> Theme:
	return EraTheme.get_theme(1)


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = P.MONO_FONT
	theme.default_font_size = 14

	theme.set_stylebox("panel", "PanelContainer", box(P.PANEL, P.BORDER, 1, 4, 10))
	theme.set_stylebox("panel", "Panel", box(P.PANEL, P.BORDER, 1, 4))

	# Buttons.
	theme.set_stylebox("normal", "Button", box(P.PANEL_RAISED, P.BORDER_BRIGHT, 1, 3, 10, 6))
	theme.set_stylebox("hover", "Button", box(P.PANEL_RAISED.lerp(P.CYAN, 0.08), P.CYAN, 1, 3, 10, 6))
	theme.set_stylebox("pressed", "Button", box(P.PANEL_RAISED.lerp(P.CYAN, 0.2), P.CYAN, 1, 3, 10, 6))
	theme.set_stylebox("disabled", "Button", box(P.PANEL, P.BORDER, 1, 3, 10, 6))
	theme.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), P.CYAN.darkened(0.3), 1, 3, 10, 6))
	theme.set_color("font_color", "Button", P.TEXT)
	theme.set_color("font_hover_color", "Button", P.CYAN)
	theme.set_color("font_pressed_color", "Button", P.TEXT_BRIGHT)
	theme.set_color("font_hover_pressed_color", "Button", P.TEXT_BRIGHT)
	theme.set_color("font_focus_color", "Button", P.TEXT)
	theme.set_color("font_disabled_color", "Button", P.TEXT_DIM.darkened(0.35))

	theme.set_type_variation("AccentButton", "Button")
	theme.set_stylebox("normal", "AccentButton", box(P.CYAN.darkened(0.55), P.CYAN, 1, 3, 14, 8))
	theme.set_stylebox("hover", "AccentButton", box(P.CYAN.darkened(0.4), P.CYAN, 1, 3, 14, 8))
	theme.set_stylebox("pressed", "AccentButton", box(P.CYAN.darkened(0.25), P.CYAN, 1, 3, 14, 8))
	theme.set_stylebox("disabled", "AccentButton", box(P.PANEL, P.BORDER, 1, 3, 14, 8))
	theme.set_color("font_color", "AccentButton", P.TEXT_BRIGHT)
	theme.set_color("font_hover_color", "AccentButton", Color.WHITE)
	theme.set_font("font", "AccentButton", P.MONO_BOLD)

	# Labels.
	theme.set_color("font_color", "Label", P.TEXT)
	theme.set_type_variation("HeaderTitle", "Label")
	theme.set_font("font", "HeaderTitle", P.SANS_BOLD)
	theme.set_font_size("font_size", "HeaderTitle", 20)
	theme.set_color("font_color", "HeaderTitle", P.CYAN)
	theme.set_type_variation("PanelTitle", "Label")
	theme.set_font("font", "PanelTitle", P.SANS_BOLD)
	theme.set_font_size("font_size", "PanelTitle", 13)
	theme.set_color("font_color", "PanelTitle", P.CYAN)
	theme.set_type_variation("DimLabel", "Label")
	theme.set_font_size("font_size", "DimLabel", 12)
	theme.set_color("font_color", "DimLabel", P.TEXT_DIM)
	theme.set_type_variation("ValueLabel", "Label")
	theme.set_font("font", "ValueLabel", P.MONO_BOLD)
	theme.set_color("font_color", "ValueLabel", P.TEXT_BRIGHT)

	# Panels used by overlays and cards.
	theme.set_type_variation("OverlayPanel", "PanelContainer")
	var overlay := box(P.BG, P.CYAN.darkened(0.2), 1, 6, 22)
	overlay.shadow_color = Color(0, 0, 0, 0.6)
	overlay.shadow_size = 18
	theme.set_stylebox("panel", "OverlayPanel", overlay)
	theme.set_type_variation("CardPanel", "PanelContainer")
	theme.set_stylebox("panel", "CardPanel", box(P.PANEL_RAISED, P.BORDER_BRIGHT, 1, 4, 12))
	theme.set_type_variation("CardPanelSelected", "PanelContainer")
	theme.set_stylebox("panel", "CardPanelSelected", box(P.PANEL_RAISED.lerp(P.CYAN, 0.1), P.CYAN, 2, 4, 12))

	# Progress bars and sliders.
	theme.set_stylebox("background", "ProgressBar", box(P.PANEL_RAISED, P.BORDER, 1, 2))
	theme.set_stylebox("fill", "ProgressBar", box(P.CYAN.darkened(0.15), P.CYAN, 0, 2))
	theme.set_color("font_color", "ProgressBar", P.TEXT_BRIGHT)
	var slider := box(P.BORDER_BRIGHT, P.BORDER_BRIGHT, 0, 2)
	slider.content_margin_top = 2
	slider.content_margin_bottom = 2
	theme.set_stylebox("slider", "HSlider", slider)
	var grabber_area := box(P.CYAN.darkened(0.35), P.CYAN.darkened(0.35), 0, 2)
	grabber_area.content_margin_top = 2
	grabber_area.content_margin_bottom = 2
	theme.set_stylebox("grabber_area", "HSlider", grabber_area)
	theme.set_stylebox("grabber_area_highlight", "HSlider", grabber_area)
	theme.set_icon("grabber", "HSlider", disc_texture(12, P.CYAN))
	theme.set_icon("grabber_highlight", "HSlider", disc_texture(14, Color.WHITE))
	theme.set_icon("grabber_disabled", "HSlider", disc_texture(12, P.TEXT_DIM))

	# Text input.
	for type_name in ["LineEdit", "SpinBox"]:
		theme.set_stylebox("normal", type_name, box(P.BG, P.BORDER_BRIGHT, 1, 3, 8, 5))
		theme.set_stylebox("focus", type_name, box(P.BG, P.CYAN, 1, 3, 8, 5))
		theme.set_stylebox("read_only", type_name, box(P.PANEL, P.BORDER, 1, 3, 8, 5))
	theme.set_color("font_color", "LineEdit", P.TEXT_BRIGHT)
	theme.set_color("caret_color", "LineEdit", P.CYAN)
	theme.set_color("selection_color", "LineEdit", Color(P.CYAN, 0.3))
	theme.set_color("font_placeholder_color", "LineEdit", P.TEXT_DIM)

	# Check boxes and toggles.
	theme.set_icon("unchecked", "CheckBox", square_texture(16, P.BG, P.BORDER_BRIGHT))
	theme.set_icon("checked", "CheckBox", square_texture(16, P.CYAN.darkened(0.2), P.CYAN))
	theme.set_icon("unchecked_disabled", "CheckBox", square_texture(16, P.PANEL, P.BORDER))
	theme.set_icon("checked_disabled", "CheckBox", square_texture(16, P.TEXT_DIM, P.BORDER))
	theme.set_color("font_color", "CheckBox", P.TEXT)
	theme.set_color("font_hover_color", "CheckBox", P.CYAN)
	theme.set_color("font_pressed_color", "CheckBox", P.TEXT_BRIGHT)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		theme.set_stylebox(state, "CheckBox", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 4, 2))

	# Rich text (event feed, crisis bodies).
	theme.set_font("normal_font", "RichTextLabel", P.MONO_FONT)
	theme.set_font("bold_font", "RichTextLabel", P.MONO_BOLD)
	theme.set_font_size("normal_font_size", "RichTextLabel", 13)
	theme.set_font_size("bold_font_size", "RichTextLabel", 13)
	theme.set_color("default_color", "RichTextLabel", P.TEXT)
	theme.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())

	# Scroll bars: thin vector rails.
	for bar in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", bar, box(P.PANEL, P.PANEL, 0, 2, 3, 3))
		theme.set_stylebox("grabber", bar, box(P.BORDER_BRIGHT, P.BORDER_BRIGHT, 0, 2, 3, 3))
		theme.set_stylebox("grabber_highlight", bar, box(P.CYAN.darkened(0.3), P.CYAN.darkened(0.3), 0, 2, 3, 3))
		theme.set_stylebox("grabber_pressed", bar, box(P.CYAN, P.CYAN, 0, 2, 3, 3))

	# Tooltips.
	theme.set_stylebox("panel", "TooltipPanel", box(P.BG, P.CYAN.darkened(0.3), 1, 3, 8, 6))
	theme.set_color("font_color", "TooltipLabel", P.TEXT_BRIGHT)
	theme.set_font_size("font_size", "TooltipLabel", 12)

	theme.set_constant("separation", "HSeparator", 8)
	theme.set_stylebox("separator", "HSeparator", line_box(P.BORDER))
	theme.set_stylebox("separator", "VSeparator", line_box(P.BORDER, true))
	return theme


static func box(bg: Color, border: Color, border_width: int = 1, radius: int = 4,
		margin_h: float = 0.0, margin_v: float = -1.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	style.content_margin_left = margin_h
	style.content_margin_right = margin_h
	var vertical := margin_h if margin_v < 0.0 else margin_v
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	return style


static func line_box(color: Color, vertical: bool = false) -> StyleBoxLine:
	var style := StyleBoxLine.new()
	style.color = color
	style.thickness = 1
	style.vertical = vertical
	return style


static func disc_texture(diameter: int, color: Color) -> ImageTexture:
	var image := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var radius := diameter * 0.5
	for y in diameter:
		for x in diameter:
			var distance := Vector2(x + 0.5 - radius, y + 0.5 - radius).length()
			var alpha := clampf(radius - distance, 0.0, 1.0)
			image.set_pixel(x, y, Color(color, alpha))
	return ImageTexture.create_from_image(image)


static func square_texture(size: int, fill: Color, border: Color) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var edge := x == 0 or y == 0 or x == size - 1 or y == size - 1
			var inner := x >= 4 and y >= 4 and x < size - 4 and y < size - 4
			if edge:
				image.set_pixel(x, y, border)
			elif inner:
				image.set_pixel(x, y, fill)
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)
