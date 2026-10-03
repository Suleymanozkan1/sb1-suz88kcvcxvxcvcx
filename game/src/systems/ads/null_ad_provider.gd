class_name NullAdProvider
extends AdProvider
## Provider used when no ad SDK is present: never has an ad available, so
## optional reward offers are hidden instead of failing after a tap.


## Always false.
func is_available(_kind: StringName) -> bool:
	return false


## Never shows anything.
func show(_kind: StringName, _placement: StringName) -> Dictionary:
	return {"shown": false, "completed": false}
