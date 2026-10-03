class_name SettingsScreen
extends UiScreen
## Settings grouped by intent: Audio, Feel, Display, Language, Privacy,
## Purchases, About. Every row: icon, label, one control; ≥ 64 px targets.

signal setting_changed(key: String, value: Variant)
signal restore_requested
signal back_requested

const QUALITY_IDS: PackedStringArray = ["auto", "low", "medium", "high", "ultra"]
const LANG_IDS: PackedStringArray = ["auto", "en", "tr"]

var _toggles: Dictionary = {}
var _sliders: Dictionary = {}
var _quality: UiSegmented
var _language: UiSegmented
var _restore_status: Label
var _version: Label
var _licenses: Label
var _licenses_box: VBoxContainer


func build() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = Palette.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root: SafeAreaContainer = make_safe_root()
	var col: VBoxContainer = UiKit.vbox()
	root.add_child(col)
	var header: ScreenHeader = ScreenHeader.new()
	header.setup(tr("menu.settings"))
	header.back_pressed.connect(func() -> void: back_requested.emit())
	col.add_child(header)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var body: VBoxContainer = UiKit.vbox(UiTokens.u(3))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	(
		body
		. add_child(
			_section(
				tr("settings.audio"),
				[
					_toggle_row(&"sound", "sound", tr("settings.sound")),
					_slider_row(&"sound", "sfx_volume", tr("settings.sfx_volume")),
					_toggle_row(&"music", "music", tr("settings.music")),
					_slider_row(&"music", "music_volume", tr("settings.music_volume")),
				]
			)
		)
	)
	(
		body
		. add_child(
			_section(
				tr("settings.feel"),
				[
					_toggle_row(&"haptics", "haptics", tr("settings.haptics")),
					_toggle_row(&"accessibility", "reduce_motion", tr("settings.reduce_motion")),
					_toggle_row(&"accessibility", "colorblind", tr("settings.colorblind")),
				]
			)
		)
	)
	_quality = UiSegmented.new()
	_quality.setup(
		QUALITY_IDS,
		PackedStringArray(
			[
				tr("settings.q.auto"),
				tr("settings.q.low"),
				tr("settings.q.medium"),
				tr("settings.q.high"),
				tr("settings.q.ultra")
			]
		),
		"auto"
	)
	_quality.selected.connect(func(id: String) -> void: setting_changed.emit("quality", id))
	(
		body
		. add_child(
			_section(
				tr("settings.display"),
				[
					_labelled(&"quality", tr("settings.quality"), _quality),
					_toggle_row(&"battery", "battery_saver", tr("settings.battery_saver")),
				]
			)
		)
	)
	_language = UiSegmented.new()
	_language.setup(LANG_IDS, PackedStringArray([tr("settings.lang.auto"), "English", "Türkçe"]), "auto")
	_language.selected.connect(func(id: String) -> void: setting_changed.emit("language", id))
	body.add_child(_section(tr("settings.language"), [_language]))
	(
		body
		. add_child(
			_section(
				tr("settings.privacy"),
				[
					_toggle_row(&"notifications", "notifications", tr("settings.notifications")),
					_toggle_row(&"info", "analytics", tr("settings.analytics")),
				]
			)
		)
	)
	var restore: UiButton = UiKit.button(tr("settings.restore"), UiKit.ButtonRole.SECONDARY, &"restore")
	restore.pressed.connect(func() -> void: restore_requested.emit())
	_restore_status = UiKit.text("", &"caption", UiTokens.TEXT_MUTED)
	_restore_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_section(tr("settings.purchases"), [restore, _restore_status]))
	_version = UiKit.text("", &"caption", UiTokens.TEXT_MUTED)
	var show_licenses: UiButton = UiKit.button(tr("settings.licenses"), UiKit.ButtonRole.TERTIARY, &"info")
	_licenses_box = UiKit.vbox(UiTokens.UNIT)
	_licenses_box.visible = false
	_licenses = UiKit.text("", &"body", UiTokens.TEXT_MUTED)
	_licenses.add_theme_font_size_override("font_size", UiTokens.CAPTION[0])
	_licenses.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_licenses_box.add_child(_licenses)
	show_licenses.pressed.connect(func() -> void: _licenses_box.visible = not _licenses_box.visible)
	body.add_child(_section(tr("settings.about"), [_version, show_licenses, _licenses_box]))


func _section(title: String, rows: Array) -> VBoxContainer:
	var v: VBoxContainer = UiKit.vbox(UiTokens.UNIT)
	v.add_child(UiKit.text(title, &"caption", UiTokens.TEXT_MUTED))
	var card: PanelContainer = UiKit.card()
	var inner: VBoxContainer = UiKit.vbox(UiTokens.UNIT)
	card.add_child(inner)
	for r: Variant in rows:
		inner.add_child(r as Control)
	v.add_child(card)
	return v


func _labelled(icon_name: StringName, label: String, control: Control) -> VBoxContainer:
	var v: VBoxContainer = UiKit.vbox(UiTokens.UNIT)
	var h: HBoxContainer = UiKit.hbox(UiTokens.GUTTER)
	h.add_child(UiKit.icon(icon_name, 24, UiTokens.TEXT_MUTED))
	h.add_child(UiKit.text(label, &"body"))
	v.add_child(h)
	v.add_child(control)
	return v


func _toggle_row(icon_name: StringName, key: String, label: String) -> HBoxContainer:
	var h: HBoxContainer = UiKit.hbox(UiTokens.GUTTER)
	h.custom_minimum_size = Vector2(0, UiTokens.MIN_TOUCH)
	h.add_child(UiKit.icon(icon_name, 24, UiTokens.TEXT_MUTED))
	var l: Label = UiKit.text(label, &"body")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	var t: UiToggle = UiToggle.new()
	t.toggled_on.connect(func(v: bool) -> void: setting_changed.emit(key, v))
	h.add_child(t)
	_toggles[key] = t
	return h


func _slider_row(icon_name: StringName, key: String, label: String) -> HBoxContainer:
	var h: HBoxContainer = UiKit.hbox(UiTokens.GUTTER)
	h.custom_minimum_size = Vector2(0, UiTokens.MIN_TOUCH)
	var spacer_icon: IconGlyph = UiKit.icon(icon_name, 24, Color(0, 0, 0, 0))
	h.add_child(spacer_icon)
	var l: Label = UiKit.text(label, &"caption", UiTokens.TEXT_MUTED)
	l.custom_minimum_size = Vector2(UiTokens.u(18), 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	var s: HSlider = HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(0, UiTokens.MIN_TOUCH)
	s.value_changed.connect(func(v: float) -> void: setting_changed.emit(key, v))
	h.add_child(s)
	_sliders[key] = s
	return h


## payload: {"settings": Dictionary, "version": String, "licenses": String,
##           "restore_status": String}
func enter(payload: Dictionary) -> void:
	var settings: Dictionary = payload.get("settings", {}) as Dictionary
	for key: String in _toggles:
		(_toggles[key] as UiToggle).set_value(bool(settings.get(key, false)))
	for key2: String in _sliders:
		(_sliders[key2] as HSlider).set_value_no_signal(float(settings.get(key2, 1.0)))
	_quality.select(str(settings.get("quality", "auto")), false)
	_language.select(str(settings.get("language", "auto")), false)
	_version.text = tr("settings.version").format({"v": str(payload.get("version", ""))})
	_licenses.text = str(payload.get("licenses", ""))
	_restore_status.text = str(payload.get("restore_status", ""))


func set_restore_status(text: String) -> void:
	_restore_status.text = text


func handle_back() -> bool:
	back_requested.emit()
	return true
