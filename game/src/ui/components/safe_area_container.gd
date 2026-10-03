class_name SafeAreaContainer
extends MarginContainer
## Keeps content inside the device safe area (notch, Dynamic Island, punch-hole,
## rounded corners, home indicator) plus the design system's outer margin.
##
## Converts DisplayServer.get_display_safe_area() (physical pixels) into this
## control's canvas units, so it works with the canvas_items/expand stretch on
## every aspect ratio. Tests can inject a simulated device.

var base_margin: int = UiTokens.MARGIN
## Simulated device for tests: screen size + safe rect in physical pixels.
var debug_screen_size: Vector2i = Vector2i.ZERO
var debug_safe_rect: Rect2i = Rect2i()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(apply_safe_area)
	apply_safe_area()


func current_insets() -> Dictionary:
	var screen: Vector2i = debug_screen_size
	var safe: Rect2i = debug_safe_rect
	if screen == Vector2i.ZERO:
		screen = DisplayServer.screen_get_size() if not AppInfo.is_headless() else Vector2i.ZERO
		safe = DisplayServer.get_display_safe_area() if AppInfo.is_mobile() else Rect2i(Vector2i.ZERO, screen)
	if screen.x <= 0 or screen.y <= 0 or safe.size == Vector2i.ZERO:
		return {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	var view: Vector2 = get_viewport_rect().size
	var sx: float = view.x / float(screen.x)
	var sy: float = view.y / float(screen.y)
	return {
		"left": float(safe.position.x) * sx,
		"top": float(safe.position.y) * sy,
		"right": float(screen.x - safe.end.x) * sx,
		"bottom": float(screen.y - safe.end.y) * sy,
	}


func apply_safe_area() -> void:
	var insets: Dictionary = current_insets()
	add_theme_constant_override("margin_left", base_margin + int(ceil(float(insets["left"]))))
	add_theme_constant_override("margin_top", base_margin + int(ceil(float(insets["top"]))))
	add_theme_constant_override("margin_right", base_margin + int(ceil(float(insets["right"]))))
	add_theme_constant_override("margin_bottom", base_margin + int(ceil(float(insets["bottom"]))))
