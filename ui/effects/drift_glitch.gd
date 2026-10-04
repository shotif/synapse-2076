class_name DriftGlitch
extends ColorRect
## Full-screen interface glitch driven by alignment drift: chromatic
## aberration, intermittent horizontal tear bands in bursts and a slight
## jitter. Nothing below drift 40; full strength at drift 100. Players can
## turn it off with [method set_enabled]. The node hides itself whenever its
## intensity is 0, so it costs nothing at rest.
##
## It samples the screen drawn before it (hint_screen_texture): add it as the
## last child of the area it should distort, e.g. the dashboard root (full
## rect). Mouse input passes through.

const GlitchShader := preload("res://ui/effects/drift_glitch.gdshader")
## Drift where the effect starts and where it reaches full strength.
const START_DRIFT := 40.0
const FULL_DRIFT := 100.0

var drift := 0.0
var enabled := true
var _material: ShaderMaterial


func _init() -> void:
	name = "DriftGlitch"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	_material = ShaderMaterial.new()
	_material.shader = GlitchShader
	material = _material
	visible = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_apply()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _material != null:
		_material.set_shader_parameter("rect_size", size)


## Alignment drift, 0-100.
func set_drift(value: float) -> void:
	drift = clampf(value, 0.0, 100.0) if is_finite(value) else 0.0
	_apply()


## Turns the effect on or off (an accessibility setting).
func set_enabled(value: bool) -> void:
	enabled = value
	_apply()


## Effective strength 0-1 (0 while disabled).
func get_intensity() -> float:
	return intensity_for(drift) if enabled else 0.0


## 0 at drift 40 or below, rising linearly to 1 at drift 100.
static func intensity_for(drift_value: float) -> float:
	if not is_finite(drift_value):
		return 0.0
	return clampf((drift_value - START_DRIFT) / (FULL_DRIFT - START_DRIFT), 0.0, 1.0)


func _apply() -> void:
	var intensity := get_intensity()
	_material.set_shader_parameter("intensity", intensity)
	_material.set_shader_parameter("rect_size", size)
	visible = intensity > 0.0
