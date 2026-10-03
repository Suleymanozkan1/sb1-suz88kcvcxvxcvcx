class_name UiToggle
extends Control
## On/off switch from the design system: flat track, round knob, 140 ms slide
## with a settle. Hit area ≥ 64 px even though the visual is compact.

signal toggled_on(value: bool)

const TRACK: Vector2 = Vector2(56, 32)
const KNOB_INSET: float = 4.0

var value: bool = false
var _knob_t: float = 0.0
var _tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(UiTokens.MIN_TOUCH + 8, UiTokens.MIN_TOUCH)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


func set_value(v: bool, animate: bool = false) -> void:
	value = v
	if animate:
		if _tween != null:
			_tween.kill()
		_tween = create_tween()
		(
			_tween
			. tween_method(_set_knob, _knob_t, 1.0 if v else 0.0, UiTokens.RELEASE_TIME)
			. set_trans(Tween.TRANS_BACK)
			. set_ease(Tween.EASE_OUT)
		)
	else:
		_set_knob(1.0 if v else 0.0)


func _set_knob(t: float) -> void:
	_knob_t = t
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var pressed: bool = (
		(
			event is InputEventMouseButton
			and (event as InputEventMouseButton).pressed
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		)
		or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
		or (event.is_action_pressed("ui_accept"))
	)
	if pressed:
		set_value(not value, true)
		UiKit.play_feedback(&"ui_click")
		toggled_on.emit(value)
		accept_event()


func _draw() -> void:
	var origin: Vector2 = (size - TRACK) * 0.5
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Palette.SLATE.lerp(Palette.PRIMARY, _knob_t)
	track.set_corner_radius_all(int(TRACK.y * 0.5))
	track.anti_aliasing = true
	draw_style_box(track, Rect2(origin, TRACK))
	var r: float = TRACK.y * 0.5 - KNOB_INSET
	var x: float = lerpf(origin.x + KNOB_INSET + r, origin.x + TRACK.x - KNOB_INSET - r, clampf(_knob_t, 0.0, 1.1))
	var knob_color: Color = Palette.BONE if _knob_t < 0.5 else Palette.INK
	draw_circle(Vector2(x, origin.y + TRACK.y * 0.5), r, knob_color, true, -1.0, true)
	if has_focus():
		var focus: StyleBoxFlat = StyleBoxFlat.new()
		focus.draw_center = false
		focus.border_color = Palette.with_alpha(Palette.PRIMARY, 0.8)
		focus.set_border_width_all(2)
		focus.set_corner_radius_all(int(TRACK.y * 0.5) + 4)
		draw_style_box(focus, Rect2(origin - Vector2(4, 4), TRACK + Vector2(8, 8)))
