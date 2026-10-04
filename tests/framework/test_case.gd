extends RefCounted
## Minimal GUT-style test case for headless CLI runs (no addon required).
##
## Assertion names mirror GUT (assert_eq, assert_true, assert_almost_eq,
## assert_between, assert_has, ...) so a suite can be ported to GUT by changing
## its `extends` line. Suites live in res://tests/unit/test_*.gd; every method
## whose name starts with "test_" runs in declaration order, wrapped by
## before_each()/after_each(). Tests may be coroutines (use `await`).

## The running SceneTree, for tests that need frames, timers or nodes.
var tree: SceneTree

var _failures: Array[String] = []
var _assertions := 0
var _current_test := ""


func before_all() -> void:
	pass


func after_all() -> void:
	pass


func before_each() -> void:
	pass


func after_each() -> void:
	pass


# --- Runner protocol -------------------------------------------------------------

func _begin_test(test_name: String) -> void:
	_current_test = test_name
	_failures.clear()
	_assertions = 0


func _end_test() -> Dictionary:
	return {
		"name": _current_test,
		"passed": _failures.is_empty() and _assertions > 0,
		"failures": _failures.duplicate(),
		"assertions": _assertions,
	}


func _record(condition: bool, description: String, message: String) -> bool:
	_assertions += 1
	if not condition:
		var text := description
		if message != "":
			text = "%s :: %s" % [message, description]
		_failures.append(text)
	return condition


# --- Assertions --------------------------------------------------------------------

func assert_true(condition: bool, message: String = "") -> bool:
	return _record(condition, "expected true", message)


func assert_false(condition: bool, message: String = "") -> bool:
	return _record(not condition, "expected false", message)


func assert_eq(got: Variant, expected: Variant, message: String = "") -> bool:
	return _record(_equals(got, expected), "expected [%s] got [%s]" % [str(expected), str(got)], message)


func assert_ne(got: Variant, not_expected: Variant, message: String = "") -> bool:
	return _record(not _equals(got, not_expected), "expected anything but [%s]" % str(not_expected), message)


func assert_almost_eq(got: float, expected: float, tolerance: float, message: String = "") -> bool:
	return _record(absf(got - expected) <= tolerance,
		"expected %s +/- %s got %s" % [expected, tolerance, got], message)


func assert_gt(got: float, threshold: float, message: String = "") -> bool:
	return _record(got > threshold, "expected %s > %s" % [got, threshold], message)


func assert_gte(got: float, threshold: float, message: String = "") -> bool:
	return _record(got >= threshold, "expected %s >= %s" % [got, threshold], message)


func assert_lt(got: float, threshold: float, message: String = "") -> bool:
	return _record(got < threshold, "expected %s < %s" % [got, threshold], message)


func assert_lte(got: float, threshold: float, message: String = "") -> bool:
	return _record(got <= threshold, "expected %s <= %s" % [got, threshold], message)


func assert_between(got: float, low: float, high: float, message: String = "") -> bool:
	return _record(got >= low and got <= high, "expected %s in [%s, %s]" % [got, low, high], message)


func assert_finite(got: float, message: String = "") -> bool:
	return _record(is_finite(got), "expected a finite number, got %s" % got, message)


func assert_has(container: Variant, value: Variant, message: String = "") -> bool:
	var found := false
	if container is Dictionary or container is Array or container is PackedStringArray:
		found = container.has(value)
	elif container is String:
		found = (container as String).contains(str(value))
	return _record(found, "expected container to have [%s]" % str(value), message)


func assert_does_not_have(container: Variant, value: Variant, message: String = "") -> bool:
	var found := false
	if container is Dictionary or container is Array or container is PackedStringArray:
		found = container.has(value)
	elif container is String:
		found = (container as String).contains(str(value))
	return _record(not found, "expected container not to have [%s]" % str(value), message)


func assert_null(got: Variant, message: String = "") -> bool:
	return _record(got == null, "expected null got [%s]" % str(got), message)


func assert_not_null(got: Variant, message: String = "") -> bool:
	return _record(got != null, "expected non-null", message)


func assert_string_contains(text: String, search: String, message: String = "") -> bool:
	return _record(text.contains(search), "expected '%s' to contain '%s'" % [text.left(120), search], message)


func fail_test(message: String) -> void:
	_record(false, "explicit failure", message)


func pass_test(message: String = "") -> void:
	_record(true, "explicit pass", message)


## Awaits [param frames] process frames (requires [member tree]).
func wait_frames(frames: int) -> void:
	for _i in frames:
		await tree.process_frame


func wait_seconds(seconds: float) -> void:
	await tree.create_timer(seconds).timeout


func _equals(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	if typeof(a) != typeof(b):
		if (a is String or a is StringName) and (b is String or b is StringName):
			return String(a) == String(b)
		return false
	return a == b
