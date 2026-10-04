class_name OrbitCamera
extends Camera3D
## Orbital camera driven by mouse dragging (PRD milestone 5): left-drag orbits,
## wheel / pinch zooms, and the view slowly auto-rotates when idle. Receives
## input forwarded by the SubViewportContainer.

@export var target := Vector3.ZERO
@export var distance := 3.2
@export var min_distance := 1.6
@export var max_distance := 8.0
@export var yaw := 0.6
@export var pitch := 0.32
@export var drag_sensitivity := 0.008
@export var auto_rotate_speed := 0.06
@export var idle_resume_sec := 2.5

var _dragging := false
var _idle_time := 99.0


func _ready() -> void:
	_apply()


func _process(delta: float) -> void:
	_idle_time += delta
	if not _dragging and _idle_time > idle_resume_sec and auto_rotate_speed != 0.0:
		yaw += auto_rotate_speed * delta
		_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_dragging = event.pressed
				_idle_time = 0.0
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					zoom(0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					zoom(1.1)
	elif event is InputEventMouseMotion and _dragging:
		orbit(event.relative)
	elif event is InputEventScreenDrag:
		orbit(event.relative)
	elif event is InputEventMagnifyGesture:
		zoom(1.0 / maxf(event.factor, 0.01))


func orbit(relative: Vector2) -> void:
	yaw -= relative.x * drag_sensitivity
	pitch = clampf(pitch + relative.y * drag_sensitivity, -1.35, 1.35)
	_idle_time = 0.0
	_apply()


func zoom(factor: float) -> void:
	distance = clampf(distance * factor, min_distance, max_distance)
	_idle_time = 0.0
	_apply()


func _apply() -> void:
	var offset := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)) * distance
	position = target + offset
	look_at(target, Vector3.UP)
