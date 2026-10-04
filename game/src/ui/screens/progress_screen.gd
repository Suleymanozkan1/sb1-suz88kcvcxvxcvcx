class_name ProgressScreen
extends UiScreen
## Progress hub with three tabs: Overview (player level, totals, worlds,
## lifetime stats), Achievements, and Leaderboards. Leaderboards never invent
## players: offline or without a backend, only the player's own entries show,
## with a plain explanation.

signal board_requested(board_id: String)
signal back_requested

const TABS: PackedStringArray = ["overview", "achievements", "leaderboard"]
const STAT_ROWS: PackedStringArray = [
	"levels_cleared",
	"perfects",
	"sparks_collected",
	"max_combo",
	"near_misses",
	"shatters",
	"bosses_cleared",
	"daily_completed",
	"time_played_seconds",
]

var _tabs: UiSegmented
var _pages: Dictionary[String, Control] = {}
var _level: Label
var _xp_meter: ProgressBar
var _xp_label: Label
var _totals: HBoxContainer
var _worlds: VBoxContainer
var _stats: GridContainer
var _ach_summary: Label
var _ach_list: VBoxContainer
var _boards: UiSegmented
var _emblem: ProfileEmblem
var _board_note: Label
var _board_list: VBoxContainer
var _board_ids: PackedStringArray = PackedStringArray()


func build() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = Palette.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root: SafeAreaContainer = make_safe_root()
	var col: VBoxContainer = UiKit.vbox()
	root.add_child(col)
	var header: ScreenHeader = ScreenHeader.new()
	header.setup(tr("menu.progress"))
	header.back_pressed.connect(func() -> void: back_requested.emit())
	col.add_child(header)
	_tabs = UiSegmented.new()
	_tabs.setup(
		TABS,
		PackedStringArray([tr("progress.overview"), tr("progress.achievements"), tr("progress.leaderboard")]),
		"overview"
	)
	_tabs.selected.connect(_show_tab)
	col.add_child(_tabs)
	var stack: Control = Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(stack)
	_pages["overview"] = _page(stack, _build_overview())
	_pages["achievements"] = _page(stack, _build_achievements())
	_pages["leaderboard"] = _page(stack, _build_leaderboard())
	_show_tab("overview")


func _page(stack: Control, content: Control) -> ScrollContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	stack.add_child(scroll)
	return scroll


func _show_tab(id: String) -> void:
	for key: String in _pages:
		_pages[key].visible = key == id


# --- Overview ------------------------------------------------------------------


func _build_overview() -> VBoxContainer:
	var v: VBoxContainer = UiKit.vbox(UiTokens.u(3))
	var card: PanelContainer = UiKit.card(&"RaisedCard")
	var inner: VBoxContainer = UiKit.vbox(UiTokens.UNIT)
	card.add_child(inner)
	var head: HBoxContainer = UiKit.hbox(UiTokens.UNIT)
	head.add_child(UiKit.text(tr("menu.level"), &"caption", UiTokens.TEXT_MUTED))
	head.add_child(UiKit.expand())
	_xp_label = UiKit.text("", &"caption", UiTokens.TEXT_MUTED)
	head.add_child(_xp_label)
	inner.add_child(head)
	var who: HBoxContainer = UiKit.hbox(UiTokens.GUTTER)
	_emblem = ProfileEmblem.new()
	_emblem.custom_minimum_size = Vector2(88, 88)
	who.add_child(_emblem)
	_level = UiKit.text("1", &"h1")
	_level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	who.add_child(_level)
	inner.add_child(who)
	_xp_meter = ProgressBar.new()
	_xp_meter.show_percentage = false
	_xp_meter.custom_minimum_size = Vector2(0, 6)
	_xp_meter.max_value = 1.0
	inner.add_child(_xp_meter)
	v.add_child(card)
	_totals = UiKit.hbox(UiTokens.GUTTER)
	v.add_child(_totals)
	v.add_child(UiKit.text(tr("worlds.title"), &"caption", UiTokens.TEXT_MUTED))
	_worlds = UiKit.vbox(UiTokens.UNIT)
	v.add_child(_worlds)
	v.add_child(UiKit.text(tr("progress.stats"), &"caption", UiTokens.TEXT_MUTED))
	var stats_card: PanelContainer = UiKit.card()
	_stats = GridContainer.new()
	_stats.columns = 2
	_stats.add_theme_constant_override("h_separation", UiTokens.GUTTER)
	_stats.add_theme_constant_override("v_separation", UiTokens.UNIT)
	stats_card.add_child(_stats)
	v.add_child(stats_card)
	return v


func _total_tile(icon_name: StringName, color: Color, value: String, caption: String) -> PanelContainer:
	var card: PanelContainer = UiKit.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v: VBoxContainer = UiKit.vbox(UiTokens.UNIT / 2)
	card.add_child(v)
	v.add_child(UiKit.stat_chip(icon_name, value, color))
	var cap: Label = UiKit.text(caption, &"caption", UiTokens.TEXT_MUTED)
	# Wrapping keeps three tiles inside the column on narrow phones.
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(cap)
	return card


func _world_row(w: Dictionary) -> HBoxContainer:
	var unlocked: bool = bool(w.get("unlocked", false))
	var h: HBoxContainer = UiKit.hbox(UiTokens.GUTTER)
	h.custom_minimum_size = Vector2(0, UiTokens.u(5))
	var index: Label = UiKit.text("%02d" % int(w.get("index", 1)), &"caption", UiTokens.TEXT_MUTED)
	index.custom_minimum_size = Vector2(UiTokens.u(4), 0)
	index.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(index)
	var name_label: Label = UiKit.text(
		str(w.get("name", "")), &"body", UiTokens.TEXT if unlocked else UiTokens.TEXT_MUTED
	)
	name_label.custom_minimum_size = Vector2(UiTokens.u(26), 0)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	h.add_child(name_label)
	var meter: ProgressBar = ProgressBar.new()
	meter.show_percentage = false
	meter.custom_minimum_size = Vector2(0, 4)
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter.max_value = maxf(1.0, float(w.get("max", 156)))
	meter.value = float(w.get("stars", 0))
	h.add_child(meter)
	var value: Label = UiKit.text(
		"%d" % int(w.get("stars", 0)), &"caption", Palette.ACCENT if unlocked else UiTokens.TEXT_MUTED
	)
	value.custom_minimum_size = Vector2(UiTokens.u(6), 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(value)
	if bool(w.get("perfect", false)):
		h.add_child(UiKit.icon(&"check", 20, Palette.SUCCESS))
	h.add_child(UiKit.spacer(false, UiTokens.GUTTER))
	return h


# --- Achievements --------------------------------------------------------------


func _build_achievements() -> VBoxContainer:
	var v: VBoxContainer = UiKit.vbox(UiTokens.UNIT)
	_ach_summary = UiKit.text("", &"caption", UiTokens.TEXT_MUTED)
	v.add_child(_ach_summary)
	_ach_list = UiKit.vbox(UiTokens.UNIT)
	v.add_child(_ach_list)
	return v


func _achievement_row(a: Dictionary) -> PanelContainer:
	var unlocked: bool = bool(a.get("unlocked", false))
	var card: PanelContainer = UiKit.card(&"SelectedCard" if unlocked else &"")
	var h: HBoxContainer = UiKit.hbox(UiTokens.GUTTER)
	card.add_child(h)
	var badge: IconGlyph = UiKit.icon(&"trophy", 32, Palette.ACCENT if unlocked else Palette.SLATE)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(badge)
	var info: VBoxContainer = UiKit.vbox(UiTokens.UNIT / 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(UiKit.text(str(a.get("name", "")), &"h3", UiTokens.TEXT if unlocked else UiTokens.TEXT))
	var desc: Label = UiKit.text(str(a.get("desc", "")), &"body", UiTokens.TEXT_MUTED)
	desc.add_theme_font_size_override("font_size", UiTokens.CAPTION[0] + 2)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc)
	var target: int = maxi(1, int(a.get("target", 1)))
	var value: int = clampi(int(a.get("value", 0)), 0, target)
	if not unlocked:
		var meter_row: HBoxContainer = UiKit.hbox(UiTokens.UNIT)
		var meter: ProgressBar = ProgressBar.new()
		meter.show_percentage = false
		meter.custom_minimum_size = Vector2(0, 4)
		meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		meter.max_value = float(target)
		meter.value = float(value)
		meter_row.add_child(meter)
		meter_row.add_child(
			UiKit.text("%s / %s" % [UiKit.format_int(value), UiKit.format_int(target)], &"caption", UiTokens.TEXT_MUTED)
		)
		info.add_child(meter_row)
	info.add_child(DailyScreen._reward_row(a.get("reward", {}) as Dictionary))
	h.add_child(info)
	if unlocked:
		var check: IconGlyph = UiKit.icon(&"check", 28, Palette.SUCCESS)
		check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(check)
	return card


# --- Leaderboard ---------------------------------------------------------------


func _build_leaderboard() -> VBoxContainer:
	var v: VBoxContainer = UiKit.vbox(UiTokens.UNIT)
	_boards = UiSegmented.new()
	_boards.setup(
		PackedStringArray(["daily", "classic", "endless"]),
		PackedStringArray([tr("lb.daily"), tr("lb.classic"), tr("lb.endless")]),
		"daily"
	)
	_boards.selected.connect(
		func(id: String) -> void:
			var index: int = _boards.options.find(id)
			if index >= 0 and index < _board_ids.size():
				board_requested.emit(_board_ids[index])
	)
	v.add_child(_boards)
	_board_note = UiKit.text("", &"body", UiTokens.TEXT_MUTED)
	_board_note.add_theme_font_size_override("font_size", UiTokens.CAPTION[0] + 2)
	_board_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_board_note)
	var card: PanelContainer = UiKit.card()
	_board_list = UiKit.vbox(0)
	card.add_child(_board_list)
	v.add_child(card)
	return v


## Shows one board: {"entries": [{"rank","name","score","is_player"}], "remote": bool,
## "online": bool}. Called by the flow after a board_requested round trip.
func show_board(board: Dictionary) -> void:
	for c: Node in _board_list.get_children():
		c.queue_free()
	var entries: Array = board.get("entries", []) as Array
	var remote: bool = bool(board.get("remote", false))
	if not remote:
		_board_note.text = tr("lb.local_only")
	elif not bool(board.get("online", true)):
		_board_note.text = tr("lb.offline")
	else:
		_board_note.text = ""
	if entries.is_empty():
		var empty: Label = UiKit.text(tr("lb.empty"), &"body", UiTokens.TEXT_MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_board_list.add_child(empty)
		return
	for raw: Variant in entries:
		_board_list.add_child(_board_row(raw as Dictionary))


func _board_row(e: Dictionary) -> HBoxContainer:
	var mine: bool = bool(e.get("is_player", false))
	var h: HBoxContainer = UiKit.hbox(UiTokens.GUTTER)
	h.custom_minimum_size = Vector2(0, UiTokens.MIN_TOUCH)
	var rank: Label = UiKit.text("%d" % int(e.get("rank", 0)), &"h3", Palette.PRIMARY if mine else UiTokens.TEXT_MUTED)
	rank.custom_minimum_size = Vector2(UiTokens.u(6), 0)
	rank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(rank)
	var name_label: Label = UiKit.text(str(e.get("name", "")), &"body", Palette.PRIMARY if mine else UiTokens.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	h.add_child(name_label)
	var score: Label = UiKit.text(UiKit.format_int(int(e.get("score", 0))), &"h3")
	score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(score)
	return h


## payload: {"player_level", "xp", "xp_next", "stars" (campaign), "max_stars",
##   "bonus_stars" (reward stars, shown apart so "stars" never exceeds the max), "perfects",
##   "cleared", "worlds": [...world rows], "stats": {name: int},
##   "achievements": [{"name","desc","value","target","unlocked","reward"}],
##   "achievements_unlocked", "achievements_total",
##   "board_ids": [daily, classic, endless], "board": {...}, "tab": String}
func enter(payload: Dictionary) -> void:
	_emblem.setup(payload.get("emblem", {}) as Dictionary)
	_level.text = str(int(payload.get("player_level", 1)))
	var xp: int = int(payload.get("xp", 0))
	var xp_next: int = maxi(1, int(payload.get("xp_next", 1)))
	_xp_meter.value = clampf(float(xp) / float(xp_next), 0.0, 1.0)
	_xp_label.text = "%s / %s XP" % [UiKit.format_int(xp), UiKit.format_int(xp_next)]
	for c: Node in _totals.get_children():
		c.queue_free()
	var stars_caption: String = tr("progress.stars_of").format(
		{"max": UiKit.format_int(int(payload.get("max_stars", 0)))}
	)
	var bonus: int = int(payload.get("bonus_stars", 0))
	if bonus > 0:
		stars_caption += "\n" + tr("progress.bonus_stars").format({"n": UiKit.format_int(bonus)})
	_totals.add_child(
		_total_tile(
			&"star_filled", Palette.ACCENT, "%s" % UiKit.format_int(int(payload.get("stars", 0))), stars_caption
		)
	)
	_totals.add_child(
		_total_tile(&"check", Palette.SUCCESS, UiKit.format_int(int(payload.get("cleared", 0))), tr("progress.cleared"))
	)
	_totals.add_child(
		_total_tile(
			&"target", Palette.PRIMARY, UiKit.format_int(int(payload.get("perfects", 0))), tr("progress.perfects")
		)
	)
	for c2: Node in _worlds.get_children():
		c2.queue_free()
	for raw: Variant in payload.get("worlds", []) as Array:
		_worlds.add_child(_world_row(raw as Dictionary))
	for c3: Node in _stats.get_children():
		c3.queue_free()
	var stats: Dictionary = payload.get("stats", {}) as Dictionary
	for key: String in STAT_ROWS:
		var label: Label = UiKit.text(tr("stat." + key), &"body", UiTokens.TEXT_MUTED)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_stats.add_child(label)
		var value: int = int(stats.get(key, 0))
		var shown: String = (
			DailyScreen.format_duration(value) if key == "time_played_seconds" else UiKit.format_int(value)
		)
		var value_label: Label = UiKit.text(shown, &"body")
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_stats.add_child(value_label)
	_ach_summary.text = tr("progress.achievements_count").format(
		{"n": int(payload.get("achievements_unlocked", 0)), "total": int(payload.get("achievements_total", 0))}
	)
	for c4: Node in _ach_list.get_children():
		c4.queue_free()
	for raw2: Variant in payload.get("achievements", []) as Array:
		_ach_list.add_child(_achievement_row(raw2 as Dictionary))
	_board_ids = PackedStringArray(payload.get("board_ids", []) as Array)
	# The flow opens the first board (today's) on entry; the segment matches it.
	_boards.select(_boards.options[0], false)
	show_board(payload.get("board", {}) as Dictionary)
	var tab: String = str(payload.get("tab", ""))
	if TABS.has(tab):
		_tabs.select(tab, false)
		_show_tab(tab)


func handle_back() -> bool:
	back_requested.emit()
	return true
