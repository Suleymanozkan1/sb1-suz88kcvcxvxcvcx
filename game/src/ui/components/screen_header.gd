class_name ScreenHeader
extends HBoxContainer
## Standard screen header: back button (64 px target), H2 title, optional
## trailing content (e.g. currency). Every non-root screen uses it.

signal back_pressed

var title_label: Label
var trailing: HBoxContainer


func setup(title: String) -> void:
	add_theme_constant_override("separation", UiTokens.UNIT)
	var back: UiButton = UiKit.icon_button(&"back", tr("ui.back"))
	back.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back)
	title_label = UiKit.text(title, &"h2")
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.clip_text = true
	add_child(title_label)
	trailing = UiKit.hbox(UiTokens.GUTTER)
	add_child(trailing)
