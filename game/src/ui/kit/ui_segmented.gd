class_name UiSegmented
extends HBoxContainer
## Segmented choice (quality presets, language, screen tabs). One selected
## segment carries the PRIMARY outline; the rest stay neutral.

signal selected(option_id: String)

## Compact segments size to their label (for long, scrollable tab rows);
## otherwise segments share the row equally.
var compact: bool = false
var options: PackedStringArray = PackedStringArray()
var current: String = ""
var _buttons: Dictionary = {}


func setup(option_ids: PackedStringArray, labels: PackedStringArray, initial: String) -> void:
	add_theme_constant_override("separation", UiTokens.UNIT)
	options = option_ids
	for i: int in option_ids.size():
		var id: String = option_ids[i]
		var b: UiButton = UiKit.button(labels[i] if i < labels.size() else id, UiKit.ButtonRole.CHOICE)
		if compact:
			b.custom_minimum_size = Vector2(UiTokens.u(14), UiTokens.BUTTON_HEIGHT)
		else:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size = Vector2(0, UiTokens.BUTTON_HEIGHT)
		b.add_theme_font_size_override("font_size", UiTokens.CAPTION[0] + 2)
		b.pressed.connect(func() -> void: select(id, true))
		add_child(b)
		_buttons[id] = b
	select(initial, false)


func select(option_id: String, notify: bool) -> void:
	current = option_id
	for id: String in _buttons:
		var b: UiButton = _buttons[id] as UiButton
		var is_sel: bool = id == option_id
		var color: Color = Palette.PRIMARY if is_sel else UiTokens.TEXT_MUTED
		b.add_theme_color_override("font_color", color)
		b.add_theme_color_override("font_hover_color", color)
		b.add_theme_color_override("font_pressed_color", color)
		if is_sel:
			var sb: StyleBoxFlat = (
				(UiTheme.get_theme().get_stylebox("normal", &"ChoiceButton") as StyleBoxFlat).duplicate()
				as StyleBoxFlat
			)
			sb.border_color = Palette.PRIMARY
			sb.set_border_width_all(UiTokens.STROKE)
			b.add_theme_stylebox_override("normal", sb)
			b.add_theme_stylebox_override("hover", sb)
		else:
			b.remove_theme_stylebox_override("normal")
			b.remove_theme_stylebox_override("hover")
	if notify:
		selected.emit(option_id)
