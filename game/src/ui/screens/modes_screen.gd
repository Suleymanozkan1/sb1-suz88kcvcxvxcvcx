class_name ModesScreen
extends UiScreen
## Game modes as one list of equal cards: glyph, name, one honest sentence on
## the rule, the personal best, and (when locked) the exact requirement.

signal mode_selected(mode_id: StringName)
signal back_requested

const MODE_ICONS: Dictionary = {
	&"classic": &"play",
	&"endless": &"endless",
	&"time_attack": &"timer",
	&"daily": &"daily",
	&"perfect_run": &"target",
	&"zen": &"zen",
	&"hard": &"shield",
	&"boss_rush": &"trophy",
}

var _list: VBoxContainer


func build() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = Palette.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root: SafeAreaContainer = make_safe_root()
	var col: VBoxContainer = UiKit.vbox()
	root.add_child(col)
	var header: ScreenHeader = ScreenHeader.new()
	header.setup(tr("menu.modes"))
	header.back_pressed.connect(func() -> void: back_requested.emit())
	col.add_child(header)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = UiKit.vbox(UiTokens.GUTTER)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


## payload: {"modes": [{"id", "name", "desc", "best" (String, "" if none),
##           "unlocked": bool, "requirement": String}]}
func enter(payload: Dictionary) -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	for raw: Variant in payload.get("modes", []) as Array:
		_list.add_child(_mode_card(raw as Dictionary))


func _mode_card(m: Dictionary) -> Control:
	var unlocked: bool = bool(m.get("unlocked", false))
	var id: StringName = StringName(str(m.get("id", "classic")))
	var button: Button = Button.new()
	button.theme_type_variation = &"ChoiceButton"
	button.custom_minimum_size = Vector2(0, UiTokens.u(13))
	button.disabled = not unlocked
	button.pressed.connect(
		func() -> void:
			UiKit.play_feedback(&"ui_click")
			mode_selected.emit(id)
	)
	var row: HBoxContainer = UiKit.hbox(UiTokens.GUTTER)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)
	row.add_child(UiKit.spacer(false, UiTokens.UNIT))
	var glyph: IconGlyph = UiKit.icon(
		MODE_ICONS.get(id, &"play") as StringName, 32, Palette.PRIMARY if unlocked else UiTokens.TEXT_MUTED
	)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(glyph)
	var info: VBoxContainer = UiKit.vbox(UiTokens.UNIT / 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(UiKit.text(str(m.get("name", "")), &"h3", UiTokens.TEXT if unlocked else UiTokens.TEXT_MUTED))
	var desc: Label = UiKit.text(
		str(m.get("desc", "")) if unlocked else str(m.get("requirement", "")), &"body", UiTokens.TEXT_MUTED
	)
	desc.add_theme_font_size_override("font_size", UiTokens.CAPTION[0] + 2)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc)
	row.add_child(info)
	var right: VBoxContainer = UiKit.vbox(UiTokens.UNIT / 2)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.custom_minimum_size = Vector2(UiTokens.u(12), 0)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if unlocked:
		var best: String = str(m.get("best", ""))
		if not best.is_empty():
			var cap: Label = UiKit.text(tr("result.best"), &"caption", UiTokens.TEXT_MUTED)
			cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			right.add_child(cap)
			var value: Label = UiKit.text(best, &"h3")
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			right.add_child(value)
	else:
		var lock: IconGlyph = UiKit.icon(&"lock", 28, UiTokens.TEXT_MUTED)
		lock.size_flags_horizontal = Control.SIZE_SHRINK_END
		right.add_child(lock)
	row.add_child(right)
	row.add_child(UiKit.spacer(false, UiTokens.UNIT))
	return button


func handle_back() -> bool:
	back_requested.emit()
	return true
