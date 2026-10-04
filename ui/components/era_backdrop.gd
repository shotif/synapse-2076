class_name EraBackdrop
extends ColorRect
## Full-screen background in the active era's idiom (see era_backdrop.gdshader).
## Era II also gets [member scanlines], a separate overlay the dashboard puts
## above its panels.

const BACKDROP_SHADER := preload("res://ui/effects/era_backdrop.gdshader")
const SCANLINE_SHADER := preload("res://ui/effects/scanlines.gdshader")

var era := 1
## Overlay of faint horizontal lines for Era II (hidden in other eras).
var scanlines: ColorRect
var _material: ShaderMaterial
var _motion := true


func _init() -> void:
	name = "Backdrop"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = BACKDROP_SHADER
	material = _material
	scanlines = ColorRect.new()
	scanlines.name = "Scanlines"
	scanlines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scanlines.set_anchors_preset(Control.PRESET_FULL_RECT)
	var scan_material := ShaderMaterial.new()
	scan_material.shader = SCANLINE_SHADER
	scanlines.material = scan_material
	scanlines.visible = false
	resized.connect(_on_resized)


## Applies [param era_number]'s colors and pattern.
func set_era(era_number: int) -> void:
	era = clampi(era_number, 1, 3)
	var s := EraStyle.for_era(era)
	color = s.bg
	_material.set_shader_parameter("era", era)
	_material.set_shader_parameter("base_color", s.bg)
	_material.set_shader_parameter("line_color", Color(s.accent, 0.045))
	_material.set_shader_parameter("glow_a", Color(s.metric["compute_energy_sat"], 0.1))
	_material.set_shader_parameter("glow_b", Color(s.metric["alignment_drift"], 0.09))
	scanlines.visible = era == 2 and _motion


## Freezes the Era III glows and hides the scanlines (reduced effects).
func set_motion(enabled: bool) -> void:
	_motion = enabled
	_material.set_shader_parameter("motion", 1.0 if enabled else 0.0)
	scanlines.visible = era == 2 and enabled


func _on_resized() -> void:
	_material.set_shader_parameter("canvas_size", size)
	(scanlines.material as ShaderMaterial).set_shader_parameter("canvas_size", size)
