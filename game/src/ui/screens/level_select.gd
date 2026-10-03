class_name LevelSelect
extends UiScreen
## Level grid for one world (4 columns). Tiles: number, three small stars,
## a distinct glyph for the mid-world challenge (combo) and the boss (target).

signal level_selected(level_id: String)
signal back_requested

const COLUMNS: int = 4
const TILE: int = 136

var _header: ScreenHeader
var _grid: GridContainer
var _summary: Label


func build() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = Palette.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root: SafeAreaContainer = make_safe_root()
	var col: VBoxContainer = UiKit.vbox()
	root.add_child(col)
	_header = ScreenHeader.new()
	_header.setup("")
	_header.back_pressed.connect(func() -> void: back_requested.emit())
	col.add_child(_header)
	_summary = UiKit.text("", &"caption", UiTokens.TEXT_MUTED)
	col.add_child(_summary)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var center: CenterContainer = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", UiTokens.GUTTER)
	_grid.add_theme_constant_override("v_separation", UiTokens.GUTTER)
	center.add_child(_grid)


## payload: {"world_name", "summary", "levels": [{"id","local","stars","unlocked",
##           "cleared","kind","perfect"}]}
func enter(payload: Dictionary) -> void:
	_header.title_label.text = str(payload.get("world_name", ""))
	_summary.text = str(payload.get("summary", ""))
	for c: Node in _grid.get_children():
		c.queue_free()
	for raw: Variant in payload.get("levels", []) as Array:
		_grid.add_child(_tile(raw as Dictionary))


func _tile(l: Dictionary) -> Control:
	var unlocked: bool = bool(l.get("unlocked", false))
	var b: Button = Button.new()
	b.theme_type_variation = &"ChoiceButton"
	b.custom_minimum_size = Vector2(TILE, TILE)
	b.disabled = not unlocked
	var id: String = str(l.get("id", ""))
	b.pressed.connect(func() -> void:
		UiKit.play_feedback(&"ui_click")
		level_selected.emit(id))
	var col: VBoxContainer = UiKit.vbox(UiTokens.UNIT)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var kind: String = str(l.get("kind", "normal"))
	if not unlocked:
		var lock: IconGlyph = UiKit.icon(&"lock", 28, UiTokens.TEXT_MUTED)
		lock.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(lock)
		return b
	var top: HBoxContainer = UiKit.hbox(UiTokens.UNIT / 2)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if kind == "boss" or kind == "challenge":
		top.add_child(UiKit.icon(&"target" if kind == "boss" else &"combo", 20, Palette.WARNING))
	var number: Label = UiKit.text(str(int(l.get("local", 0))), &"h3")
	top.add_child(number)
	col.add_child(top)
	var stars: HBoxContainer = UiKit.hbox(2)
	stars.alignment = BoxContainer.ALIGNMENT_CENTER
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var earned: int = int(l.get("stars", 0))
	for i: int in 3:
		var s: IconGlyph = UiKit.icon(&"star_filled" if i < earned else &"star", 18, Palette.ACCENT if i < earned else Palette.SLATE)
		s.stroke_units = 1.6
		stars.add_child(s)
	col.add_child(stars)
	return b


func handle_back() -> bool:
	back_requested.emit()
	return true
