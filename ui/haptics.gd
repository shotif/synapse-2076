class_name Haptics
extends RefCounted
## Short vibrations that confirm a touch or flag an event on phones and
## tablets, one call per cue:
##
##   Haptics.pulse("swipe")     # a crisis card was swiped
##
## Kinds (KINDS): "swipe" 20 ms, "select" 12 ms, "confirm" 35 ms, "alert"
## 70 ms, "era" 90 ms. A pulse only runs when the player's "vibration"
## setting (GameSettings) is on and the device is a touch device: a phone or
## tablet build, or a browser on a touch screen. Browsers without the
## Vibration API (Safari on iOS) are skipped quietly instead of logging a
## warning per pulse.
##
## Tests capture pulses through [member vibrate_func] and fake the device
## check through [member touch_func].

## kind -> [duration in ms, amplitude 0..1]. Android 8+ uses the amplitude;
## browsers and older phones vibrate at full strength for the duration.
const KINDS := {
	"swipe": [20, 0.35],
	"select": [12, 0.25],
	"confirm": [35, 0.55],
	"alert": [70, 1.0],
	"era": [90, 0.8],
}

## When valid, called as vibrate_func.call(duration_ms: int, amplitude: float)
## instead of Input.vibrate_handheld (tests).
static var vibrate_func := Callable()
## When valid, called with no arguments instead of the platform check and
## returns whether this is a touch device (tests).
static var touch_func := Callable()

## Whether this browser has navigator.vibrate: -1 not asked yet, 0 no, 1 yes.
static var _web_vibrate := -1


## Vibrates for [param kind] when the setting and the device allow it.
## Returns true when a pulse was sent; unknown kinds are ignored.
static func pulse(kind: String) -> bool:
	if not KINDS.has(kind) or not enabled():
		return false
	var spec: Array = KINDS[kind]
	if vibrate_func.is_valid():
		vibrate_func.call(int(spec[0]), float(spec[1]))
	else:
		Input.vibrate_handheld(int(spec[0]), float(spec[1]))
	return true


## Milliseconds a pulse of [param kind] lasts (0 for unknown kinds).
static func duration_ms(kind: String) -> int:
	return int((KINDS.get(kind, [0, 0.0]) as Array)[0])


## True when this device can vibrate and the player wants it to.
static func enabled() -> bool:
	return is_touch_device() and bool(GameSettings.value("vibration")) and _can_vibrate()


## A phone or tablet build, or a browser on a touch screen.
static func is_touch_device() -> bool:
	if touch_func.is_valid():
		return bool(touch_func.call())
	return OS.has_feature("mobile") or (OS.has_feature("web") and DisplayServer.is_touchscreen_available())


static func _can_vibrate() -> bool:
	if vibrate_func.is_valid() or not OS.has_feature("web"):
		return true
	if _web_vibrate < 0:
		var answer: Variant = JavaScriptBridge.eval("typeof navigator.vibrate === 'function'", true)
		_web_vibrate = 1 if answer is bool and answer else 0
	return _web_vibrate == 1
