class_name EraUpgrade
extends Control
## The "system upgrade" played when the hardware era changes. The old
## interface glitches out, a boot screen in the new era's colors lists what
## is being rebuilt, then the overlay wipes away over the new theme. The
## dashboard swaps its theme on [signal swap_theme]. Tap to skip.

signal swap_theme(era: int)
signal finished

const MONO := preload("res://ui/fonts/JetBrainsMono-Regular.ttf")
const TRANSITION_SHADER := preload("res://ui/effects/era_transition.gdshader")
## Seconds: glitch out, boot screen in, the five log steps, theme swap, done.
const T_BOOT := 0.42
const T_FIRST_STEP := 0.69
const STEP_INTERVAL := 0.27
const T_SWAP := 2.05
const T_DONE := 2.85

const SCRIPTS := {
	1: {"kicker": "TIMELINE REWIND", "title": "Back to silicon",
		"log": ["Restoring native app chrome", "Regrouping panels into cards", "Charts back to sparklines",
			"Turning on translucent bars", "Ready"]},
	2: {"kicker": "PARADIGM SHIFT", "title": "Optical interconnects & SMR grids",
		"log": ["Loading optical display drivers", "Recalibrating the holographic layer", "Moving vitals to ring telemetry",
			"Re-keying the crisis feed", "System upgraded"]},
	3: {"kicker": "PARADIGM SHIFT", "title": "Neuromorphic & post-biological substrates",
		"log": ["Growing interface tissue", "Letting the ops agent arrange the panels", "Sizing every cell by its value",
			"Dissolving the grid", "The interface is alive"]},
}

var target_era := 1
var _playing := false
var _swapped := false
var _compact := false
var _motion := true
var _tween: Tween
var _glitch: ColorRect
var _glitch_material: ShaderMaterial
var _clip: Control
var _boot: Control
var _boot_bg: ColorRect
var _scan: ColorRect
var _frame: MarginContainer
var _content: VBoxContainer
var _kicker: Label
var _title: Label
var _sub: Label
var _bar_track: ColorRect
var _bar_fill: ColorRect
var _log_rows: Array[HBoxContainer] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_glitch = ColorRect.new()
	_glitch.name = "Glitch"
	_glitch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glitch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glitch_material = ShaderMaterial.new()
	_glitch_material.shader = TRANSITION_SHADER
	_glitch.material = _glitch_material
	add_child(_glitch)

	# The boot screen sits in a clipping frame whose top edge moves down to
	# wipe it away.
	_clip = Control.new()
	_clip.name = "BootClip"
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	_boot = Control.new()
	_boot.name = "Boot"
	_boot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(_boot)
	_boot_bg = ColorRect.new()
	_boot_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_boot_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boot.add_child(_boot_bg)
	_scan = ColorRect.new()
	_scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boot.add_child(_scan)

	# The boot text is a column centered vertically; phones keep it left-aligned.
	_frame = MarginContainer.new()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boot.add_child(_frame)
	_content = VBoxContainer.new()
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("separation", 14)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_content)
	_kicker = _mono_label(12, 3)
	_content.add_child(_kicker)
	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_title)
	_sub = _mono_label(12, 0)
	_content.add_child(_sub)
	_bar_track = ColorRect.new()
	_bar_track.custom_minimum_size = Vector2(0, 3)
	_bar_track.color = Color(0.5, 0.5, 0.5, 0.25)
	_content.add_child(_bar_track)
	_bar_fill = ColorRect.new()
	_bar_fill.anchor_bottom = 1.0
	_bar_track.add_child(_bar_fill)
	var log_box := VBoxContainer.new()
	log_box.add_theme_constant_override("separation", 7)
	_content.add_child(log_box)
	for i in 5:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var mark := _mono_label(12, 0)
		mark.custom_minimum_size = Vector2(14, 0)
		row.add_child(mark)
		var text := _mono_label(12, 0)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		log_box.add_child(row)
		_log_rows.append(row)
	resized.connect(_layout)


## Starts the upgrade to [param era_number]; [param year] labels the boot screen.
func play(era_number: int, year: int = 0) -> void:
	if _tween != null:
		_tween.kill()
	target_era = clampi(era_number, 1, 3)
	_playing = true
	_swapped = false
	visible = true
	_fill_script(year)
	_set_step(0)
	_layout()
	_clip_progress(0.0)
	_boot.modulate.a = 0.0
	_glitch.visible = _motion
	_glitch_material.set_shader_parameter("mode", 0)
	_glitch_material.set_shader_parameter("amount", 0.0)
	_glitch_material.set_shader_parameter("fade_color", EraStyle.for_era(clampi(target_era - 1, 1, 3)).bg)
	_tween = create_tween().set_parallel(true)
	_tween.tween_method(_set_glitch, 0.0, 1.0, T_BOOT + 0.18).set_ease(Tween.EASE_IN)
	_tween.tween_property(_boot, "modulate:a", 1.0, 0.35).set_delay(T_BOOT)
	for i in 5:
		_tween.tween_callback(_set_step.bind(i + 1)).set_delay(T_FIRST_STEP + STEP_INTERVAL * i)
	_tween.tween_callback(_swap).set_delay(T_SWAP)
	_tween.tween_method(_clip_progress, 0.0, 1.0, 0.7).set_delay(T_SWAP).set_ease(Tween.EASE_IN)
	_tween.tween_method(_set_glitch, 1.0, 0.0, 0.8).set_delay(T_SWAP).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_finish).set_delay(T_DONE)


## Jumps to the end: swaps the theme if that has not happened yet and hides.
func finish_now() -> void:
	if not _playing:
		return
	if _tween != null:
		_tween.kill()
	_swap()
	_finish()


## Stops without swapping the theme (a new campaign started mid-upgrade).
func cancel() -> void:
	if _tween != null:
		_tween.kill()
	if _playing:
		_playing = false
		visible = false
		_set_glitch(0.0)


func is_playing() -> bool:
	return _playing


func set_compact(compact: bool) -> void:
	_compact = compact
	_layout()


## Without motion the old interface simply fades; no tearing or blur.
func set_motion(enabled: bool) -> void:
	_motion = enabled


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		accept_event()
		finish_now()


func _process(delta: float) -> void:
	if not _playing or _scan == null:
		return
	_scan.position.y += delta * size.y / 1.1
	if _scan.position.y > size.y:
		_scan.position.y = -20.0


func _swap() -> void:
	if _swapped:
		return
	_swapped = true
	_glitch_material.set_shader_parameter("mode", 1)
	_glitch_material.set_shader_parameter("fade_color", EraStyle.for_era(target_era).bg)
	swap_theme.emit(target_era)


func _finish() -> void:
	_playing = false
	visible = false
	_set_glitch(0.0)
	finished.emit()


func _set_glitch(value: float) -> void:
	_glitch_material.set_shader_parameter("amount", value if _motion else 0.0)
	if not _motion:
		# Plain cross-fade: the boot screen covers the swap.
		_glitch.visible = false


## 0 shows the whole boot screen; 1 has wiped it away from the top.
func _clip_progress(value: float) -> void:
	if _clip == null:
		return
	var top := size.y * value
	_clip.position = Vector2(0, top)
	_clip.size = Vector2(size.x, maxf(size.y - top, 0.0))
	_boot.position = Vector2(0, -top)


func _fill_script(year: int) -> void:
	var s := EraStyle.for_era(target_era)
	var script: Dictionary = SCRIPTS[target_era]
	_boot_bg.color = s.bg
	_scan.color = s.accent
	_kicker.text = String(script["kicker"])
	_kicker.add_theme_color_override("font_color", s.accent)
	_title.text = String(script["title"])
	_title.add_theme_font_override("font", s.font_display)
	_title.add_theme_color_override("font_color", s.text_bright)
	_sub.text = tr("Hardware Era %s · %s") % [EraStyle.ROMAN[target_era], str(year) if year > 0 else String(EraStyle.SPANS[target_era])]
	_sub.add_theme_color_override("font_color", Color(s.text, 0.75))
	_bar_fill.color = s.accent
	for row in _log_rows:
		(row.get_child(0) as Label).add_theme_color_override("font_color", s.accent)
		(row.get_child(1) as Label).add_theme_color_override("font_color", s.text)
	var lines: Array = script["log"]
	for i in _log_rows.size():
		(_log_rows[i].get_child(1) as Label).text = String(lines[i])


## Steps 0-5: the bar fills and each log line is pending, running or done.
func _set_step(step: int) -> void:
	if _bar_fill == null:
		return
	_bar_fill.anchor_right = float(step) / 5.0
	_bar_fill.offset_right = 0.0
	for i in _log_rows.size():
		var row := _log_rows[i]
		var done := step > i
		var running := step == i
		row.modulate.a = 1.0 if done else (0.55 if running else 0.12)
		(row.get_child(0) as Label).text = "✓" if done else ("›" if running else "")


func _layout() -> void:
	if _boot == null:
		return
	_boot.size = size
	_clip_progress(0.0 if not _swapped else 1.0)
	_scan.size = Vector2(size.x, 2)
	_title.add_theme_font_size_override("font_size", 34 if _compact else 46)
	var side := 30.0 if _compact else maxf((size.x - 620.0) / 2.0, 30.0)
	for margin in ["margin_left", "margin_right"]:
		_frame.add_theme_constant_override(margin, int(side))
	for margin in ["margin_top", "margin_bottom"]:
		_frame.add_theme_constant_override(margin, 20)
	_set_step(_current_step())


func _current_step() -> int:
	var step := 0
	for row in _log_rows:
		if (row.get_child(0) as Label).text == "✓":
			step += 1
	return step


func _mono_label(font_size: int, spacing: int) -> Label:
	var label := Label.new()
	var font := FontVariation.new()
	font.base_font = MONO
	font.spacing_glyph = spacing
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
