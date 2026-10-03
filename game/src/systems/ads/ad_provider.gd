class_name AdProvider
extends RefCounted
## Adapter around an ad network SDK.
##
## No ad SDK is linked into this build, so the composition root uses
## [NullAdProvider]. A platform plugin would subclass this; [method show] may
## then be a coroutine (callers always [code]await[/code] it). The base class
## never has inventory and never pretends an ad was shown.

const KIND_INTERSTITIAL: StringName = &"interstitial"
const KIND_REWARDED: StringName = &"rewarded"


## True when an ad of [param kind] is loaded and can be shown right now.
func is_available(_kind: StringName) -> bool:
	return false


## Shows an ad. Returns {"shown": bool, "completed": bool}: "completed" is
## true only when a rewarded ad was watched to the end.
func show(_kind: StringName, _placement: StringName) -> Dictionary:
	return {"shown": false, "completed": false}
