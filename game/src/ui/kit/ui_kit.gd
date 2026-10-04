class_name UiKit
extends RefCounted
## Factories for typography and components so every screen is assembled from the
## same parts (one design system, ART_DIRECTION §10).

enum ButtonRole { PRIMARY, SECONDARY, TERTIARY, DESTRUCTIVE, ICON, CHOICE }

const ROLE_VARIATION: Dictionary[ButtonRole, StringName] = {
	ButtonRole.PRIMARY: &"PrimaryButton",
	ButtonRole.SECONDARY: &"SecondaryButton",
	ButtonRole.TERTIARY: &"TertiaryButton",
	ButtonRole.DESTRUCTIVE: &"DestructiveButton",
	ButtonRole.ICON: &"IconButton",
	ButtonRole.CHOICE: &"ChoiceButton",
}

## Optional UI feedback hook (sound + haptic) installed by the app layer:
## (kind: StringName) -> void, kinds: ui_click, ui_back.
static var feedback_hook: Callable = Callable()


## Label in one of the typography styles: h1 h2 h3 body caption score button reward.
static func text(content: String, style: StringName = &"body", color: Color = UiTokens.TEXT) -> Label:
	var l: Label = Label.new()
	l.text = content
	apply_style(l, style)
	if color != UiTokens.TEXT or style != &"reward":
		l.add_theme_color_override("font_color", color if style != &"reward" else Palette.ACCENT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func apply_style(l: Label, style: StringName) -> void:
	var spec: Array[int] = UiTokens.BODY
	var tracking: int = 0
	match style:
		&"h1":
			spec = UiTokens.H1
			tracking = UiTokens.TRACK_H1
		&"h2":
			spec = UiTokens.H2
		&"h3":
			spec = UiTokens.H3
		&"caption":
			spec = UiTokens.CAPTION
			tracking = UiTokens.TRACK_CAPTION
			l.uppercase = true
		&"score":
			spec = UiTokens.SCORE
		&"button":
			spec = UiTokens.BUTTON
			tracking = UiTokens.TRACK_BUTTON
			l.uppercase = true
		&"reward":
			spec = UiTokens.REWARD
	var font: Font = UiFonts.tracked(spec[1], tracking) if tracking != 0 else UiFonts.get_font(spec[1])
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", spec[0])


static func button(label: String, role: ButtonRole = ButtonRole.PRIMARY, icon_name: StringName = &"") -> UiButton:
	var b: UiButton = UiButton.new()
	b.setup(label, role, icon_name)
	return b


static func icon_button(icon_name: StringName, accessible_name: String) -> UiButton:
	var b: UiButton = UiButton.new()
	b.setup("", ButtonRole.ICON, icon_name)
	b.tooltip_text = accessible_name
	b.custom_minimum_size = Vector2(UiTokens.ICON_BUTTON, UiTokens.ICON_BUTTON)
	return b


static func icon(icon_name: StringName, size_px: int = UiTokens.ICON_SIZE, color: Color = UiTokens.TEXT) -> IconGlyph:
	var g: IconGlyph = IconGlyph.new()
	g.icon = icon_name
	g.color = color
	g.custom_minimum_size = Vector2(size_px, size_px)
	return g


static func card(variation: StringName = &"") -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	if variation != &"":
		p.theme_type_variation = variation
	return p


static func vbox(separation: int = UiTokens.GUTTER) -> VBoxContainer:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation: int = UiTokens.GUTTER) -> HBoxContainer:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func spacer(vertical: bool = true, px: int = UiTokens.UNIT) -> Control:
	var c: Control = Control.new()
	c.custom_minimum_size = Vector2(0, px) if vertical else Vector2(px, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func expand() -> Control:
	var c: Control = Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Icon + value pair (coins, gems, stars) with tabular-feeling weight.
static func stat_chip(icon_name: StringName, value: String, color: Color) -> HBoxContainer:
	var h: HBoxContainer = hbox(UiTokens.UNIT)
	h.add_child(icon(icon_name, 24, color))
	var l: Label = text(value, &"h3")
	l.name = "Value"
	h.add_child(l)
	return h


static func play_feedback(kind: StringName) -> void:
	if feedback_hook.is_valid():
		feedback_hook.call(kind)


## Formats integers with thin grouping (1 250 000) for readability.
static func format_int(value: int) -> String:
	var s: String = str(absi(value))
	var out: String = ""
	var count: int = 0
	for i: int in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	return ("-" if value < 0 else "") + out
