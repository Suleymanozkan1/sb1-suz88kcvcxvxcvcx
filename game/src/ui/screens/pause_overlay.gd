class_name PauseOverlay
extends UiScreen
## Pause: one decision, one primary action (Resume). Restart / Settings / Home
## are secondary. No timers, no pressure.

signal resume_requested
signal restart_requested
signal settings_requested
signal home_requested

var _title: Label


func build() -> void:
	is_overlay = true
	add_scrim(0.7)
	var root: SafeAreaContainer = make_safe_root()
	var center: CenterContainer = CenterContainer.new()
	root.add_child(center)
	var col: VBoxContainer = UiKit.vbox(UiTokens.GUTTER)
	col.custom_minimum_size = Vector2(UiTokens.u(52), 0)
	center.add_child(col)
	_title = UiKit.text(tr("pause.title"), &"h2")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	col.add_child(UiKit.spacer(true, UiTokens.u(2)))
	var resume: UiButton = UiKit.button(tr("pause.resume"), UiKit.ButtonRole.PRIMARY, &"play")
	resume.pressed.connect(func() -> void: resume_requested.emit())
	col.add_child(resume)
	var restart: UiButton = UiKit.button(tr("pause.restart"), UiKit.ButtonRole.SECONDARY, &"retry")
	restart.pressed.connect(func() -> void: restart_requested.emit())
	col.add_child(restart)
	var row: HBoxContainer = UiKit.hbox()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var settings: UiButton = UiKit.button(tr("menu.settings"), UiKit.ButtonRole.TERTIARY, &"settings")
	settings.pressed.connect(func() -> void: settings_requested.emit())
	row.add_child(settings)
	var home: UiButton = UiKit.button(tr("pause.home"), UiKit.ButtonRole.TERTIARY, &"home")
	home.pressed.connect(func() -> void: home_requested.emit())
	row.add_child(home)
	col.add_child(row)


func handle_back() -> bool:
	resume_requested.emit()
	return true
