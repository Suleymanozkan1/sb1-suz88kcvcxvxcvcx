class_name UiScreen
extends Control
## Base class for full screens and overlays. Transitions are calm (ART_DIRECTION
## §8): 24 px slide plus fade, ease-out cubic, no bounce.

signal closed

## Overlays draw over gameplay with a scrim; full screens own the canvas.
var is_overlay: bool = false
var safe: SafeAreaContainer
var _tween: Tween


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.get_theme()


## Builds the screen once (called by the router before the first enter()).
func build() -> void:
	pass


## Called with the router payload each time the screen becomes visible.
func enter(_payload: Dictionary) -> void:
	pass


## Tears the built controls down and builds them again. build() bakes
## translated text into the controls, so this runs after a language change.
func rebuild() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	_reset_built_refs()
	build()


## Drops references that build() collected (override where build() appends).
func _reset_built_refs() -> void:
	pass


func exit() -> void:
	pass


## Back navigation (Android back / Escape). Return true if handled.
func handle_back() -> bool:
	return false


func make_safe_root() -> SafeAreaContainer:
	safe = SafeAreaContainer.new()
	add_child(safe)
	return safe


func add_scrim(alpha: float = 0.82) -> ColorRect:
	var scrim: ColorRect = ColorRect.new()
	scrim.color = Palette.with_alpha(UiTokens.SCRIM, alpha)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)
	move_child(scrim, 0)
	return scrim


func transition_in(reduce_motion: bool = false) -> void:
	visible = true
	mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED
	if _tween != null:
		_tween.kill()
	modulate.a = 0.0
	position = Vector2(0.0, 0.0 if reduce_motion else UiTokens.SCREEN_SLIDE)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, UiTokens.SCREEN_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)
	_tween.tween_property(self, "position", Vector2.ZERO, UiTokens.SCREEN_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)


## The screen stops taking input as soon as it starts leaving: an overlay
## fading out over live gameplay must not swallow the next tap.
func transition_out(reduce_motion: bool = false) -> void:
	mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 0.0, UiTokens.SCREEN_TIME * 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_IN
	)
	if not reduce_motion:
		_tween.tween_property(self, "position", Vector2(0.0, -UiTokens.SCREEN_SLIDE * 0.5), UiTokens.SCREEN_TIME * 0.7)
	_tween.chain().tween_callback(func() -> void: visible = false)
