class_name OrbitCamera
extends Camera3D
## Orbital camera driven by mouse dragging (PRD milestone 5): left-drag orbits,
## wheel / pinch zooms, and the view slowly auto-rotates when idle. Receives
## input forwarded by the SubViewportContainer. On touch screens one finger
## orbits and two fingers pinch to zoom.

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
var _touches := {}
var _pinch_distance := 0.0
## Touches also arrive as emulated mouse events by default; orbiting from
## both would double the speed, so single-finger drags orbit through one path.
var _mouse_from_touch := bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true))


func _ready() -> void:
	_apply()


func _process(delta: float) -> void:
	_idle_time += delta
	if not _dragging and _idle_time > idle_resume_sec and auto_rotate_speed != 0.0:
		yaw += auto_rotate_speed * delta
		_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pinch_distance = _touch_spread()
		_idle_time = 0.0
		return
	if event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var spread := _touch_spread()
			if _pinch_distance > 0.0 and spread > 0.0:
				zoom(_pinch_distance / spread)
			_pinch_distance = spread
		elif not _mouse_from_touch:
			orbit(event.relative)
		return
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
	elif event is InputEventMouseMotion and _dragging and _touches.size() < 2:
		orbit(event.relative)
	elif event is InputEventMagnifyGesture:
		zoom(1.0 / maxf(event.factor, 0.01))


## Distance between the first two active touches (0 with fewer than two).
func _touch_spread() -> float:
	if _touches.size() < 2:
		return 0.0
	var points: Array = _touches.values()
	return (points[0] as Vector2).distance_to(points[1] as Vector2)


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
