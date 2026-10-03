class_name ProfileEmblem
extends Control
## The player's identity in the UI: the equipped avatar inside the equipped
## frame, with the equipped badge on the lower-right corner. Drawn with the
## same swatch grammar as the collection, so what was bought is what is shown.

const AVATAR_SCALE: float = 0.8
const BADGE_SCALE: float = 0.42

var _frame: CosmeticSwatch
var _avatar: CosmeticSwatch
var _badge: CosmeticSwatch


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = _layer()
	_avatar = _layer()
	_badge = _layer()
	resized.connect(_layout)


func _layer() -> CosmeticSwatch:
	var s: CosmeticSwatch = CosmeticSwatch.new()
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(s)
	return s


## [param emblem]: {"avatar": params, "frame": params, "badge": params}.
func setup(emblem: Dictionary) -> void:
	_avatar.setup("avatar", emblem.get("avatar", {}) as Dictionary, true)
	_frame.setup("frame", emblem.get("frame", {}) as Dictionary, true)
	var badge: Dictionary = emblem.get("badge", {}) as Dictionary
	_badge.visible = not badge.is_empty()
	_badge.setup("badge", badge, true)


func _layout() -> void:
	_frame.position = Vector2.ZERO
	_frame.size = size
	_avatar.size = size * AVATAR_SCALE
	_avatar.position = (size - _avatar.size) * 0.5
	_badge.size = size * BADGE_SCALE
	_badge.position = size - _badge.size
