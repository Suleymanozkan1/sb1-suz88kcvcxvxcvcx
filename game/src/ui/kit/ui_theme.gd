class_name UiTheme
extends RefCounted
## Builds the single Godot Theme for the whole UI from [UiTokens].
## Flat surfaces, 1 px hairlines, 4 px radius — no gradients, no glow, no blur.

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func _box(bg: Color, border: Color = Color(0, 0, 0, 0), border_width: int = 0, radius: int = UiTokens.RADIUS) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	sb.content_margin_left = UiTokens.u(3)
	sb.content_margin_right = UiTokens.u(3)
	sb.content_margin_top = UiTokens.u(1.5)
	sb.content_margin_bottom = UiTokens.u(1.5)
	return sb


static func _build() -> Theme:
	var t: Theme = Theme.new()
	t.default_font = UiFonts.get_font(400)
	t.default_font_size = UiTokens.BODY[0]
	t.set_color("font_color", "Label", UiTokens.TEXT)
	# Buttons: one role per variation (they are not clones of each other).
	var clear: Color = Color(0, 0, 0, 0)
	var button_font: Font = UiFonts.tracked(UiTokens.BUTTON[1], UiTokens.TRACK_BUTTON)
	_button_variant(
		t, "PrimaryButton", _box(Palette.PRIMARY), _box(Palette.PRIMARY.darkened(0.18)), _box(Palette.SLATE), UiTokens.TEXT_ON_PRIMARY, button_font
	)
	_button_variant(
		t,
		"SecondaryButton",
		_box(clear, Palette.with_alpha(Palette.BONE, 0.4), UiTokens.STROKE),
		_box(UiTokens.SURFACE_PRESSED, Palette.BONE, UiTokens.STROKE),
		_box(clear, Palette.SLATE, UiTokens.STROKE),
		UiTokens.TEXT,
		button_font
	)
	_button_variant(t, "TertiaryButton", _box(clear), _box(clear), _box(clear), UiTokens.TEXT_MUTED, button_font)
	_button_variant(
		t,
		"DestructiveButton",
		_box(clear, Palette.FAILURE, UiTokens.STROKE),
		_box(Palette.with_alpha(Palette.FAILURE, 0.15), Palette.FAILURE, UiTokens.STROKE),
		_box(clear, Palette.SLATE, UiTokens.STROKE),
		Palette.FAILURE,
		button_font
	)
	var round_pressed: StyleBoxFlat = _box(UiTokens.SURFACE_PRESSED, clear, 0, UiTokens.ICON_BUTTON / 2)
	_button_variant(t, "IconButton", _box(clear), round_pressed, _box(clear), UiTokens.TEXT, button_font)
	_button_variant(
		t,
		"ChoiceButton",
		_box(UiTokens.SURFACE, UiTokens.BORDER, UiTokens.HAIRLINE),
		_box(UiTokens.SURFACE_PRESSED, Palette.BONE, UiTokens.HAIRLINE),
		_box(UiTokens.SURFACE, UiTokens.BORDER, UiTokens.HAIRLINE),
		UiTokens.TEXT,
		UiFonts.get_font(600)
	)
	# Surfaces.
	var card: StyleBoxFlat = _box(UiTokens.SURFACE, UiTokens.BORDER, UiTokens.HAIRLINE)
	card.set_content_margin_all(UiTokens.u(2))
	t.set_stylebox("panel", "PanelContainer", card)
	t.set_stylebox("panel", "Panel", card)
	var raised: StyleBoxFlat = _box(UiTokens.SURFACE_RAISED, UiTokens.BORDER, UiTokens.HAIRLINE)
	raised.set_content_margin_all(UiTokens.u(2))
	t.set_type_variation("RaisedCard", "PanelContainer")
	t.set_stylebox("panel", "RaisedCard", raised)
	var selected: StyleBoxFlat = _box(UiTokens.SURFACE_RAISED, Palette.PRIMARY, UiTokens.STROKE)
	selected.set_content_margin_all(UiTokens.u(2))
	t.set_type_variation("SelectedCard", "PanelContainer")
	t.set_stylebox("panel", "SelectedCard", selected)
	# Meters.
	var meter_bg: StyleBoxFlat = _box(Palette.SLATE, clear, 0, 2)
	meter_bg.set_content_margin_all(0)
	var meter_fill: StyleBoxFlat = _box(Palette.PRIMARY, clear, 0, 2)
	meter_fill.set_content_margin_all(0)
	t.set_stylebox("background", "ProgressBar", meter_bg)
	t.set_stylebox("fill", "ProgressBar", meter_fill)
	t.set_constant("separation", "VBoxContainer", UiTokens.GUTTER)
	t.set_constant("separation", "HBoxContainer", UiTokens.GUTTER)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	# Sliders (volume).
	var grabber: GradientTexture2D = GradientTexture2D.new()
	grabber.width = 28
	grabber.height = 28
	grabber.fill = GradientTexture2D.FILL_RADIAL
	grabber.fill_from = Vector2(0.5, 0.5)
	grabber.fill_to = Vector2(0.5, 0.0)
	var gg: Gradient = Gradient.new()
	gg.offsets = PackedFloat32Array([0.0, 0.92, 1.0])
	gg.colors = PackedColorArray([Palette.BONE, Palette.BONE, Color(1, 1, 1, 0)])
	grabber.gradient = gg
	t.set_icon("grabber", "HSlider", grabber)
	t.set_icon("grabber_highlight", "HSlider", grabber)
	var track: StyleBoxFlat = _box(Palette.SLATE, clear, 0, 2)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var track_fill: StyleBoxFlat = _box(Palette.PRIMARY, clear, 0, 2)
	track_fill.content_margin_top = 3
	track_fill.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", track_fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", track_fill)
	return t


static func _button_variant(t: Theme, name: String, normal: StyleBoxFlat, pressed: StyleBoxFlat, disabled: StyleBoxFlat, font_color: Color, font: Font) -> void:
	t.set_type_variation(name, "Button")
	t.set_stylebox("normal", name, normal)
	t.set_stylebox("hover", name, normal)
	t.set_stylebox("pressed", name, pressed)
	t.set_stylebox("hover_pressed", name, pressed)
	t.set_stylebox("disabled", name, disabled)
	var focus: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = Palette.with_alpha(Palette.PRIMARY, 0.8)
	focus.set_border_width_all(UiTokens.STROKE)
	t.set_stylebox("focus", name, focus)
	t.set_color("font_color", name, font_color)
	t.set_color("font_hover_color", name, font_color)
	t.set_color("font_pressed_color", name, font_color)
	t.set_color("font_focus_color", name, font_color)
	t.set_color("font_disabled_color", name, Palette.FOG)
	t.set_font("font", name, font)
	t.set_font_size("font_size", name, UiTokens.BUTTON[0])
