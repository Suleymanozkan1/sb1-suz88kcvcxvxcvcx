class_name TestCase
extends RefCounted
## Minimal dependency-free test base class.
##
## Subclasses define methods named `test_*`. Methods may be coroutines (use
## `await`) when they need frames; [member tree] gives access to the SceneTree.

var tree: SceneTree
var failures: PackedStringArray = PackedStringArray()
var assertions: int = 0
var current_test: String = ""


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func fail(message: String) -> void:
	failures.append("%s: %s" % [current_test, message])


func assert_true(condition: bool, message: String = "expected true") -> void:
	assertions += 1
	if not condition:
		fail(message)


func assert_false(condition: bool, message: String = "expected false") -> void:
	assertions += 1
	if condition:
		fail(message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	assertions += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		var numeric: bool = (
			(typeof(actual) == TYPE_INT or typeof(actual) == TYPE_FLOAT)
			and (typeof(expected) == TYPE_INT or typeof(expected) == TYPE_FLOAT)
		)
		if numeric and float(actual) == float(expected):
			return
		fail("%s expected <%s> got <%s>" % [message, str(expected), str(actual)])


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	assertions += 1
	if actual == unexpected:
		fail("%s value should differ from <%s>" % [message, str(unexpected)])


func assert_near(actual: float, expected: float, tolerance: float, message: String = "") -> void:
	assertions += 1
	if absf(actual - expected) > tolerance:
		fail("%s expected %f±%f got %f" % [message, expected, tolerance, actual])


func assert_gt(actual: float, bound: float, message: String = "") -> void:
	assertions += 1
	if not actual > bound:
		fail("%s expected > %s got %s" % [message, str(bound), str(actual)])


func assert_ge(actual: float, bound: float, message: String = "") -> void:
	assertions += 1
	if not actual >= bound:
		fail("%s expected >= %s got %s" % [message, str(bound), str(actual)])


func assert_lt(actual: float, bound: float, message: String = "") -> void:
	assertions += 1
	if not actual < bound:
		fail("%s expected < %s got %s" % [message, str(bound), str(actual)])


func assert_le(actual: float, bound: float, message: String = "") -> void:
	assertions += 1
	if not actual <= bound:
		fail("%s expected <= %s got %s" % [message, str(bound), str(actual)])


func assert_has(container: Variant, item: Variant, message: String = "") -> void:
	assertions += 1
	var found: bool = false
	match typeof(container):
		TYPE_DICTIONARY:
			found = (container as Dictionary).has(item)
		TYPE_ARRAY:
			found = (container as Array).has(item)
		TYPE_PACKED_STRING_ARRAY:
			found = (container as PackedStringArray).has(str(item))
		TYPE_STRING:
			found = (container as String).contains(str(item))
	if not found:
		fail("%s <%s> not found" % [message, str(item)])


func assert_empty(container: Variant, message: String = "") -> void:
	assertions += 1
	var size: int = -1
	match typeof(container):
		TYPE_DICTIONARY:
			size = (container as Dictionary).size()
		TYPE_ARRAY:
			size = (container as Array).size()
		TYPE_PACKED_STRING_ARRAY:
			size = (container as PackedStringArray).size()
	if size != 0:
		fail("%s expected empty, got %s" % [message, str(container)])


## Waits [param frames] process frames (for scene/gameplay tests).
func wait_frames(frames: int) -> void:
	for _i: int in frames:
		await tree.process_frame
