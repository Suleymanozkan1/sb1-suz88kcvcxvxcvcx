class_name WorldSelect
extends UiScreen
## World list: one card per world. A 4 px stripe in the world's sink colour is
## the only identity accent; progress is a star meter. Locked worlds state the
## exact, honest requirement.

signal world_selected(world_id: String)
signal back_requested

const STRIPE: int = 4

var _list: VBoxContainer


func build() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = Palette.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root: SafeAreaContainer = make_safe_root()
	var col: VBoxContainer = UiKit.vbox()
	root.add_child(col)
	var header: ScreenHeader = ScreenHeader.new()
	header.setup(tr("worlds.title"))
	header.back_pressed.connect(func() -> void: back_requested.emit())
	col.add_child(header)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = UiKit.vbox(UiTokens.GUTTER)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


## payload: {"worlds": [{"id","index","name","story","stars","max","unlocked",
##           "requirement" (String), "sink" (Color), "perfect" (bool)}]}
func enter(payload: Dictionary) -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	for raw: Variant in payload.get("worlds", []) as Array:
		_list.add_child(_world_card(raw as Dictionary))


func _world_card(w: Dictionary) -> Control:
	var unlocked: bool = bool(w.get("unlocked", false))
	var button: Button = Button.new()
	button.theme_type_variation = &"ChoiceButton"
	button.custom_minimum_size = Vector2(0, UiTokens.u(15))
	button.disabled = not unlocked
	var id: String = str(w.get("id", ""))
	button.pressed.connect(func() -> void:
		UiKit.play_feedback(&"ui_click")
		world_selected.emit(id))
	var row: HBoxContainer = UiKit.hbox(UiTokens.GUTTER)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)
	var stripe: ColorRect = ColorRect.new()
	stripe.color = (w.get("sink", Palette.PRIMARY) as Color) if unlocked else Palette.SLATE
	stripe.custom_minimum_size = Vector2(STRIPE, 0)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stripe)
	var info: VBoxContainer = UiKit.vbox(UiTokens.UNIT / 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(UiKit.text(tr("worlds.index").format({"n": "%02d" % int(w.get("index", 1))}), &"caption", UiTokens.TEXT_MUTED))
	info.add_child(UiKit.text(str(w.get("name", "")), &"h3", UiTokens.TEXT if unlocked else UiTokens.TEXT_MUTED))
	var sub: Label = UiKit.text(str(w.get("story", "")) if unlocked else str(w.get("requirement", "")), &"body", UiTokens.TEXT_MUTED)
	sub.add_theme_font_size_override("font_size", UiTokens.CAPTION[0] + 2)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(sub)
	row.add_child(info)
	var right: VBoxContainer = UiKit.vbox(UiTokens.UNIT / 2)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.custom_minimum_size = Vector2(UiTokens.u(13), 0)
	if unlocked:
		var stars_row: HBoxContainer = UiKit.stat_chip(&"star_filled", "%d" % int(w.get("stars", 0)), Palette.ACCENT)
		stars_row.alignment = BoxContainer.ALIGNMENT_END
		right.add_child(stars_row)
		var meter: ProgressBar = ProgressBar.new()
		meter.show_percentage = false
		meter.custom_minimum_size = Vector2(0, 4)
		meter.max_value = maxf(1.0, float(w.get("max", 156)))
		meter.value = float(w.get("stars", 0))
		meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		right.add_child(meter)
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
