class_name ToastView
extends Control
## Small, calm, transient messages (save recovered, store unavailable, offline,
## achievement): one at a time, top of the safe area, 2.4 s, fade in/out. They
## never block input and never use urgency language.

const SHOW_TIME: float = 2.4
const FADE_TIME: float = 0.18
const MAX_QUEUE: int = 4

var _queue: Array[Dictionary] = []
var _card: PanelContainer
var _icon: IconGlyph
var _label: Label
var _busy: bool = false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()


func _ready() -> void:
	var safe: SafeAreaContainer = SafeAreaContainer.new()
	add_child(safe)
	var col: VBoxContainer = UiKit.vbox(0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(col)
	_card = UiKit.card(&"RaisedCard")
	_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.modulate.a = 0.0
	col.add_child(UiKit.spacer(true, UiTokens.u(10)))
	col.add_child(_card)
	var row: HBoxContainer = UiKit.hbox(UiTokens.UNIT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(row)
	_icon = UiKit.icon(&"info", 22, Palette.PRIMARY)
	row.add_child(_icon)
	_label = UiKit.text("", &"body")
	_label.add_theme_font_size_override("font_size", UiTokens.CAPTION[0] + 2)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(UiTokens.u(36), 0)
	row.add_child(_label)


func show_message(text: String, icon_name: StringName = &"info") -> void:
	if text.is_empty():
		return
	if _queue.size() >= MAX_QUEUE:
		_queue.pop_front()
	_queue.append({"text": text, "icon": icon_name})
	if not _busy:
		_next()


func _next() -> void:
	if _queue.is_empty() or _card == null:
		_busy = false
		return
	_busy = true
	var m: Dictionary = _queue.pop_front() as Dictionary
	_label.text = str(m["text"])
	_icon.icon = m["icon"] as StringName
	_icon.queue_redraw()
	var tw: Tween = create_tween()
	tw.tween_property(_card, "modulate:a", 1.0, FADE_TIME)
	tw.tween_interval(SHOW_TIME)
	tw.tween_property(_card, "modulate:a", 0.0, FADE_TIME)
	tw.tween_callback(_next)
