class_name UiButton
extends Button
## Button with a role (primary/secondary/…), optional stroke icon and the
## tactile motion of ART_DIRECTION §8: press 0.96 in 60 ms, release with a 1.02
## overshoot settling in 140 ms. Large touch targets (≥ 64 px).

var role: UiKit.ButtonRole = UiKit.ButtonRole.PRIMARY
var glyph: IconGlyph
var _tween: Tween


func setup(label: String, button_role: UiKit.ButtonRole, icon_name: StringName = &"") -> void:
	role = button_role
	text = label
	theme_type_variation = UiKit.ROLE_VARIATION[role]
	focus_mode = Control.FOCUS_ALL
	var min_h: int = UiTokens.BUTTON_HEIGHT_PRIMARY if role == UiKit.ButtonRole.PRIMARY else UiTokens.BUTTON_HEIGHT
	if role == UiKit.ButtonRole.ICON:
		min_h = UiTokens.ICON_BUTTON
	custom_minimum_size = Vector2(maxf(custom_minimum_size.x, float(UiTokens.MIN_TOUCH)), float(min_h))
	if icon_name != &"":
		glyph = UiKit.icon(icon_name, UiTokens.ICON_SIZE, _icon_color())
		add_child(glyph)
		if label.is_empty():
			# Centred by anchors + symmetric offsets so it stays centred when the
			# container resizes the button.
			var half: Vector2 = glyph.custom_minimum_size * 0.5
			glyph.set_anchors_preset(Control.PRESET_CENTER)
			glyph.offset_left = -half.x
			glyph.offset_top = -half.y
			glyph.offset_right = half.x
			glyph.offset_bottom = half.y
		else:
			# Reserve real padding for the glyph so it never overlaps the label.
			var pad: int = UiTokens.ICON_SIZE + UiTokens.UNIT
			for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
				var base: StyleBox = UiTheme.get_theme().get_stylebox(state, theme_type_variation)
				if base != null:
					var sb: StyleBox = base.duplicate() as StyleBox
					sb.content_margin_left = base.content_margin_left + float(pad)
					add_theme_stylebox_override(state, sb)
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	pressed.connect(_on_pressed)
	resized.connect(_layout_glyph)


func _icon_color() -> Color:
	match role:
		UiKit.ButtonRole.PRIMARY:
			return UiTokens.TEXT_ON_PRIMARY
		UiKit.ButtonRole.TERTIARY:
			return UiTokens.TEXT_MUTED
		UiKit.ButtonRole.DESTRUCTIVE:
			return Palette.FAILURE
	return UiTokens.TEXT


func set_glyph_color(c: Color) -> void:
	if glyph != null:
		glyph.color = c


func _layout_glyph() -> void:
	pivot_offset = size * 0.5
	if glyph == null:
		return
	var gs: Vector2 = glyph.custom_minimum_size
	# Icon-only glyphs are centred by their anchors/offsets (see setup); setting
	# position on a centre-anchored control would add the anchor point again.
	if not text.is_empty():
		glyph.position = Vector2(float(UiTokens.u(3)), (size.y - gs.y) * 0.5)


func _on_down() -> void:
	_animate(0.96, UiTokens.PRESS_TIME, Tween.TRANS_QUAD, Tween.EASE_OUT)


func _on_up() -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	(
		_tween
		. tween_property(self, "scale", Vector2(1.02, 1.02), UiTokens.RELEASE_TIME * 0.45)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_tween
		. tween_property(self, "scale", Vector2.ONE, UiTokens.RELEASE_TIME * 0.55)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)


func _on_pressed() -> void:
	UiKit.play_feedback(&"ui_back" if role == UiKit.ButtonRole.TERTIARY else &"ui_click")


func _animate(target: float, duration: float, trans: Tween.TransitionType, ease_type: Tween.EaseType) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2(target, target), duration).set_trans(trans).set_ease(ease_type)
