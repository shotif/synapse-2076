class_name UiLayout
extends RefCounted
## Responsive layout rules. Phones, portrait tablets and small windows get the
## compact dashboard at about one logical pixel per CSS pixel; larger
## landscape screens keep the 1600x900 desktop layout. Compact screens that
## are wide enough (landscape tablets and phones) split into the world on the
## left and the tabbed panels on the right; the rest show one tab at a time.
##
## Sizes are judged in CSS pixels (physical pixels / device pixel ratio), so a
## 1080x2400 phone at ratio 2.625 counts as 411x914, not as a large screen.

const DESKTOP_SIZE := Vector2i(1600, 900)
## The desktop layout needs at least this much room (CSS px), and a bit more
## on touch screens, where controls must stay finger-sized.
const MIN_DESKTOP_SIZE := Vector2(900.0, 500.0)
const MIN_TOUCH_DESKTOP_WIDTH := 1200.0
## Compact layouts keep the short side between these logical sizes: tiny
## phones zoom out a little, tablets zoom in for larger touch targets.
const COMPACT_SHORT_SIDE_MIN := 360.0
const COMPACT_SHORT_SIDE_MAX := 640.0
## Gap between a compact overlay panel and the screen edge.
const COMPACT_MARGIN := 8.0
## Landscape compact canvases at least this wide (logical px) use the split
## layout.
const SPLIT_MIN_WIDTH := 760.0

const MODE_DESKTOP := "desktop"
const MODE_SPLIT := "split"
const MODE_PHONE := "phone"


## Returns {mode, compact, landscape, content_size (Vector2i), css_size
## (Vector2)} for a window of [param window_px] physical pixels. [code]mode[/code]
## is MODE_DESKTOP, MODE_SPLIT or MODE_PHONE.
static func compute(window_px: Vector2, pixel_ratio: float = 1.0, touch: bool = false) -> Dictionary:
	if window_px.x < 1.0 or window_px.y < 1.0:
		return {"mode": MODE_DESKTOP, "compact": false, "landscape": true, "content_size": DESKTOP_SIZE, "css_size": window_px}
	var ratio := clampf(pixel_ratio if is_finite(pixel_ratio) else 1.0, 0.5, 8.0)
	var css := window_px / ratio
	var landscape := css.x >= css.y
	var compact := not landscape or css.x < MIN_DESKTOP_SIZE.x or css.y < MIN_DESKTOP_SIZE.y \
		or (touch and css.x < MIN_TOUCH_DESKTOP_WIDTH)
	if not compact:
		return {"mode": MODE_DESKTOP, "compact": false, "landscape": true, "content_size": DESKTOP_SIZE, "css_size": css}
	var short_side := minf(css.x, css.y)
	var zoom := short_side / clampf(short_side, COMPACT_SHORT_SIDE_MIN, COMPACT_SHORT_SIDE_MAX)
	var logical := (css / zoom).round()
	var mode := MODE_SPLIT if landscape and logical.x >= SPLIT_MIN_WIDTH else MODE_PHONE
	return {"mode": mode, "compact": true, "landscape": landscape, "content_size": Vector2i(logical), "css_size": css}


## Width for an overlay panel: its desktop width, or the screen minus margins.
static func panel_width(overlay_width: float, desktop_width: float, compact: bool) -> float:
	if not compact:
		return desktop_width
	return maxf(240.0, overlay_width - COMPACT_MARGIN * 2.0)


## Full-screen overlay scaffold shared by the dialogs: a shade, then a scroll
## area whose content stays centered while it fits and scrolls once it does
## not (phones, landscape). Returns the container to put the panel in.
static func build_overlay(overlay: Control, shade: Color) -> MarginContainer:
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = shade
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var scroll := ScrollContainer.new()
	scroll.name = "OverlayScroll"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	overlay.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 0)
	center.add_child(margin)
	return margin


## Switches an overlay built by [method build_overlay] between desktop and
## phone styling: a screen-edge margin, and no scrollbar (phones scroll by
## dragging, and the bar would push a full-width panel past the screen edge).
static func set_overlay_margin(margin: MarginContainer, compact: bool) -> void:
	var value := int(COMPACT_MARGIN) if compact else 0
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, value)
	var scroll := margin.get_parent().get_parent() as ScrollContainer
	if scroll != null:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if compact else ScrollContainer.SCROLL_MODE_AUTO


## Lets touch drags that start anywhere on [param node] or its descendants
## reach the enclosing ScrollContainer. Godot only drag-scrolls when the touch
## propagates to it (MOUSE_FILTER_PASS all the way up), and cancels a pressed
## button once scrolling begins. Panels and buttons stop events by default;
## sliders, scroll bars and text fields keep their own drags.
static func pass_touch_through(node: Node) -> void:
	var controls: Array = node.find_children("*", "Control", true, false)
	if node is Control:
		controls.append(node)
	for item in controls:
		var control := item as Control
		if control.mouse_filter != Control.MOUSE_FILTER_STOP:
			continue
		if control is Slider or control is ScrollBar or control is LineEdit or control is TextEdit \
				or control is SpinBox or control is ScrollContainer:
			continue
		control.mouse_filter = Control.MOUSE_FILTER_PASS
