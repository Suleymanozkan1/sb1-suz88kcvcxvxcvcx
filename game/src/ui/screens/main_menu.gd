class_name MainMenu
extends UiScreen
## Main screen: the live game (attract mode) is the background; the UI is a thin
## layer on top with one primary action. Everything else is one tap away and
## organised by intent: play, daily, modes, then the tab bar.

signal play_requested
signal daily_requested
signal modes_requested
signal worlds_requested
signal tab_requested(tab: StringName)

const TABS: Array[StringName] = [&"progress", &"shop", &"collection", &"settings"]
const TAB_ICONS: Array[StringName] = [&"progress", &"shop", &"collection", &"settings"]

var _level_label: Label
var _coins: Label
var _gems: Label
var _player_level: Label
var _emblem: ProfileEmblem
var _xp: ProgressBar
var _unlock_title: Label
var _unlock_meter: ProgressBar
var _unlock_value: Label
var _daily_badge: Label


func build() -> void:
	var shade: ColorRect = ColorRect.new()
	shade.color = Palette.with_alpha(Palette.INK, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	# Ink falls off behind the top bar and the bottom controls so the live run
	# behind the menu never competes with text (visual priority: UI > decor).
	# The title sits on ink: overhead structure passing in the attract run
	# must never cross the wordmark.
	add_child(_edge_fade(true, 0.34, 0.6))
	add_child(_edge_fade(false, 0.46))
	var root: SafeAreaContainer = make_safe_root()
	var col: VBoxContainer = UiKit.vbox(UiTokens.GUTTER)
	root.add_child(col)
	col.add_child(_top_bar())
	col.add_child(UiKit.spacer(true, UiTokens.u(6)))
	var wordmark: Label = UiKit.text("FLUX DROP", &"h1")
	wordmark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(wordmark)
	var tagline: Label = UiKit.text(tr("menu.tagline"), &"caption", UiTokens.TEXT_MUTED)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tagline)
	col.add_child(UiKit.expand())
	col.add_child(_unlock_card())
	var play: UiButton = UiKit.button(tr("menu.play"), UiKit.ButtonRole.PRIMARY, &"play")
	play.pressed.connect(func() -> void: play_requested.emit())
	col.add_child(play)
	_level_label = UiKit.text("", &"caption", UiTokens.TEXT_MUTED)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_level_label)
	var row: HBoxContainer = UiKit.hbox()
	var daily: UiButton = UiKit.button(tr("menu.daily"), UiKit.ButtonRole.SECONDARY, &"daily")
	daily.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	daily.pressed.connect(func() -> void: daily_requested.emit())
	_daily_badge = UiKit.text("", &"caption", Palette.ACCENT)
	_daily_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_daily_badge.position = Vector2(-UiTokens.u(4), UiTokens.u(0.5))
	daily.add_child(_daily_badge)
	row.add_child(daily)
	var worlds: UiButton = UiKit.button(tr("menu.worlds"), UiKit.ButtonRole.SECONDARY, &"collection")
	worlds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	worlds.pressed.connect(func() -> void: worlds_requested.emit())
	row.add_child(worlds)
	var modes: UiButton = UiKit.button(tr("menu.modes"), UiKit.ButtonRole.SECONDARY, &"endless")
	modes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modes.pressed.connect(func() -> void: modes_requested.emit())
	row.add_child(modes)
	col.add_child(row)
	col.add_child(UiKit.spacer(true, UiTokens.UNIT))
	col.add_child(_tab_bar())


## [param hold]: share of the fade that stays (almost) opaque before it eases out.
func _edge_fade(top: bool, fraction: float, hold: float = 0.0) -> TextureRect:
	var g: Gradient = Gradient.new()
	g.set_color(0, Palette.with_alpha(Palette.INK, 0.92))
	g.set_color(1, Palette.with_alpha(Palette.INK, 0.0))
	if hold > 0.0:
		g.add_point(hold, Palette.with_alpha(Palette.INK, 0.86))
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.5, 0.0 if top else 1.0)
	tex.fill_to = Vector2(0.5, 1.0 if top else 0.0)
	tex.width = 4
	tex.height = 256
	var rect: TextureRect = TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.anchor_left = 0.0
	rect.anchor_right = 1.0
	rect.anchor_top = 0.0 if top else 1.0 - fraction
	rect.anchor_bottom = fraction if top else 1.0
	return rect


func _top_bar() -> HBoxContainer:
	var bar: HBoxContainer = UiKit.hbox()
	var level_box: HBoxContainer = UiKit.hbox(UiTokens.UNIT)
	_emblem = ProfileEmblem.new()
	_emblem.custom_minimum_size = Vector2(56, 56)
	level_box.add_child(_emblem)
	var badge: PanelContainer = UiKit.card(&"RaisedCard")
	badge.custom_minimum_size = Vector2(56, 56)
	_player_level = UiKit.text("1", &"h3")
	_player_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(_player_level)
	level_box.add_child(badge)
	var xp_col: VBoxContainer = UiKit.vbox(UiTokens.UNIT / 2)
	xp_col.alignment = BoxContainer.ALIGNMENT_CENTER
	xp_col.add_child(UiKit.text(tr("menu.level"), &"caption", UiTokens.TEXT_MUTED))
	_xp = ProgressBar.new()
	_xp.show_percentage = false
	_xp.custom_minimum_size = Vector2(UiTokens.u(12), 4)
	_xp.max_value = 1.0
	xp_col.add_child(_xp)
	level_box.add_child(xp_col)
	bar.add_child(level_box)
	bar.add_child(UiKit.expand())
	var coins: HBoxContainer = UiKit.stat_chip(&"coin", "0", Palette.ACCENT)
	_coins = coins.get_node("Value") as Label
	bar.add_child(coins)
	var gems: HBoxContainer = UiKit.stat_chip(&"gem", "0", Palette.SECONDARY)
	_gems = gems.get_node("Value") as Label
	bar.add_child(gems)
	return bar


func _unlock_card() -> PanelContainer:
	var card: PanelContainer = UiKit.card()
	var col: VBoxContainer = UiKit.vbox(UiTokens.UNIT)
	card.add_child(col)
	var head: HBoxContainer = UiKit.hbox(UiTokens.UNIT)
	head.add_child(UiKit.icon(&"lock", 20, UiTokens.TEXT_MUTED))
	_unlock_title = UiKit.text("", &"caption", UiTokens.TEXT_MUTED)
	_unlock_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_unlock_title)
	_unlock_value = UiKit.text("", &"caption")
	head.add_child(_unlock_value)
	col.add_child(head)
	_unlock_meter = ProgressBar.new()
	_unlock_meter.show_percentage = false
	_unlock_meter.custom_minimum_size = Vector2(0, 4)
	_unlock_meter.max_value = 1.0
	col.add_child(_unlock_meter)
	return card


func _tab_bar() -> HBoxContainer:
	var bar: HBoxContainer = UiKit.hbox(0)
	for i: int in TABS.size():
		var tab: StringName = TABS[i]
		var cell: VBoxContainer = UiKit.vbox(UiTokens.UNIT / 2)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		var b: UiButton = UiKit.icon_button(TAB_ICONS[i], tr("menu." + String(tab)))
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func() -> void: tab_requested.emit(tab))
		cell.add_child(b)
		var label: Label = UiKit.text(tr("menu." + String(tab)), &"caption", UiTokens.TEXT_MUTED)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(label)
		bar.add_child(cell)
	return bar


## payload: {"coins", "gems", "player_level", "xp_progress" (0..1), "next_level_label",
##           "unlock": {"title", "progress", "target"}, "daily_badge": String}
func enter(payload: Dictionary) -> void:
	_coins.text = UiKit.format_int(int(payload.get("coins", 0)))
	_gems.text = UiKit.format_int(int(payload.get("gems", 0)))
	_player_level.text = str(int(payload.get("player_level", 1)))
	_emblem.setup(payload.get("emblem", {}) as Dictionary)
	_xp.value = clampf(float(payload.get("xp_progress", 0.0)), 0.0, 1.0)
	_level_label.text = str(payload.get("next_level_label", ""))
	var unlock: Dictionary = payload.get("unlock", {}) as Dictionary
	var target: int = maxi(1, int(unlock.get("target", 1)))
	var progress: int = clampi(int(unlock.get("progress", 0)), 0, target)
	_unlock_title.text = str(unlock.get("title", ""))
	_unlock_value.text = "%d / %d" % [progress, target]
	_unlock_meter.value = float(progress) / float(target)
	_unlock_title.get_parent().get_parent().get_parent().visible = not str(unlock.get("title", "")).is_empty()
	_daily_badge.text = str(payload.get("daily_badge", ""))
