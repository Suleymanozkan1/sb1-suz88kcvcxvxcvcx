class_name DailyScreen
extends UiScreen
## Daily hub: today's seeded challenge, the gentle streak, and missions.
## Every number is real state: the countdown is the true UTC reset, the streak
## tiers are explained up front (a missed day lowers the tier by one, never to
## zero), and missions show exact progress. No timers that invent urgency.

signal play_requested
signal claim_requested(mission_id: String)
signal back_requested

const MAX_TIER: int = 7
const TIER_DOT: int = 20
const MISSION_KINDS: PackedStringArray = ["daily", "weekly"]

var _date: Label
var _world: Label
var _best: Label
var _rank: Label
var _play: UiButton
var _reset: Label
var _streak_value: Label
var _tier_dots: Array[ColorRect] = []
var _tier_note: Label
var _missions_tabs: UiSegmented
var _missions_list: VBoxContainer
var _missions_reset: Label
var _missions: Dictionary = {}
var _reset_seconds: Dictionary = {"challenge": 0, "daily": 0, "weekly": 0}
var _tick: float = 0.0


func build() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.color = Palette.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root: SafeAreaContainer = make_safe_root()
	var col: VBoxContainer = UiKit.vbox()
	root.add_child(col)
	var header: ScreenHeader = ScreenHeader.new()
	header.setup(tr("daily.title"))
	header.back_pressed.connect(func() -> void: back_requested.emit())
	col.add_child(header)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var body: VBoxContainer = UiKit.vbox(UiTokens.u(3))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	body.add_child(_challenge_card())
	body.add_child(_streak_card())
	body.add_child(_missions_section())


func _challenge_card() -> PanelContainer:
	var card: PanelContainer = UiKit.card(&"RaisedCard")
	var v: VBoxContainer = UiKit.vbox(UiTokens.UNIT)
	card.add_child(v)
	var head: HBoxContainer = UiKit.hbox(UiTokens.UNIT)
	head.add_child(UiKit.icon(&"daily", 24, Palette.PRIMARY))
	_date = UiKit.text("", &"caption", Palette.PRIMARY)
	_date.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_date)
	_reset = UiKit.text("", &"caption", UiTokens.TEXT_MUTED)
	head.add_child(_reset)
	v.add_child(head)
	_world = UiKit.text("", &"h2")
	_world.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_world)
	var note: Label = UiKit.text(tr("daily.same_for_everyone"), &"body", UiTokens.TEXT_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	var stats: HBoxContainer = UiKit.hbox(UiTokens.u(3))
	_best = UiKit.text("", &"h3")
	stats.add_child(_labelled_value(tr("daily.best"), _best))
	_rank = UiKit.text("", &"h3")
	stats.add_child(_labelled_value(tr("daily.personal_rank"), _rank))
	v.add_child(stats)
	v.add_child(UiKit.spacer(true, UiTokens.UNIT))
	_play = UiKit.button(tr("daily.play"), UiKit.ButtonRole.PRIMARY, &"play")
	_play.pressed.connect(func() -> void: play_requested.emit())
	v.add_child(_play)
	return card


func _labelled_value(caption: String, value: Label) -> VBoxContainer:
	var v: VBoxContainer = UiKit.vbox(UiTokens.UNIT / 2)
	v.add_child(UiKit.text(caption, &"caption", UiTokens.TEXT_MUTED))
	v.add_child(value)
	return v


func _streak_card() -> VBoxContainer:
	var section: VBoxContainer = UiKit.vbox(UiTokens.UNIT)
	section.add_child(UiKit.text(tr("daily.streak"), &"caption", UiTokens.TEXT_MUTED))
	var card: PanelContainer = UiKit.card()
	var v: VBoxContainer = UiKit.vbox(UiTokens.GUTTER)
	card.add_child(v)
	var head: HBoxContainer = UiKit.hbox(UiTokens.UNIT)
	head.add_child(UiKit.icon(&"combo", 24, Palette.ACCENT))
	_streak_value = UiKit.text("", &"h3")
	_streak_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_streak_value)
	v.add_child(head)
	var dots: HBoxContainer = UiKit.hbox(UiTokens.UNIT)
	for i: int in MAX_TIER:
		var cell: VBoxContainer = UiKit.vbox(UiTokens.UNIT / 2)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var dot: ColorRect = ColorRect.new()
		dot.custom_minimum_size = Vector2(0, UiTokens.UNIT)
		dot.color = Palette.SLATE
		cell.add_child(dot)
		var n: Label = UiKit.text(str(i + 1), &"caption", UiTokens.TEXT_MUTED)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(n)
		dots.add_child(cell)
		_tier_dots.append(dot)
	v.add_child(dots)
	_tier_note = UiKit.text("", &"body", UiTokens.TEXT_MUTED)
	_tier_note.add_theme_font_size_override("font_size", UiTokens.CAPTION[0] + 2)
	_tier_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_tier_note)
	section.add_child(card)
	return section


func _missions_section() -> VBoxContainer:
	var section: VBoxContainer = UiKit.vbox(UiTokens.UNIT)
	var head: HBoxContainer = UiKit.hbox(UiTokens.UNIT)
	var title: Label = UiKit.text(tr("missions.title"), &"caption", UiTokens.TEXT_MUTED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_missions_reset = UiKit.text("", &"caption", UiTokens.TEXT_MUTED)
	head.add_child(_missions_reset)
	section.add_child(head)
	_missions_tabs = UiSegmented.new()
	_missions_tabs.setup(MISSION_KINDS, PackedStringArray([tr("missions.daily"), tr("missions.weekly")]), "daily")
	_missions_tabs.selected.connect(func(_id: String) -> void: _render_missions())
	section.add_child(_missions_tabs)
	_missions_list = UiKit.vbox(UiTokens.UNIT)
	section.add_child(_missions_list)
	return section


## payload: {"date_label", "world_name", "status": DailyChallengeService.status(),
##           "rank": {"rank", "of"}, "missions": {"daily": [...], "weekly": [...]},
##           "reset": {"daily": secs, "weekly": secs}}
func enter(payload: Dictionary) -> void:
	var status: Dictionary = payload.get("status", {}) as Dictionary
	_date.text = str(payload.get("date_label", ""))
	_world.text = str(payload.get("world_name", ""))
	var best: int = int(status.get("best_score", 0))
	_best.text = UiKit.format_int(best) if bool(status.get("played", false)) else "—"
	var rank: Dictionary = payload.get("rank", {}) as Dictionary
	_rank.text = (
		tr("daily.rank_of").format({"rank": int(rank.get("rank", 0)), "of": int(rank.get("of", 0))})
		if int(rank.get("of", 0)) > 0 else "—"
	)
	_play.text = tr("daily.play_again") if bool(status.get("completed", false)) else tr("daily.play")
	var streak: int = int(status.get("streak", 0))
	var tier: int = clampi(int(status.get("tier", 1)), 1, MAX_TIER)
	_streak_value.text = tr("daily.streak_days").format({"n": streak})
	for i: int in _tier_dots.size():
		_tier_dots[i].color = Palette.ACCENT if i < tier else Palette.SLATE
	_tier_note.text = tr("daily.tier_note").format({"tier": tier})
	var reset: Dictionary = payload.get("reset", {}) as Dictionary
	_reset_seconds["challenge"] = int(status.get("seconds_to_reset", reset.get("daily", 0)))
	_reset_seconds["daily"] = int(reset.get("daily", _reset_seconds["challenge"]))
	_reset_seconds["weekly"] = int(reset.get("weekly", 0))
	_missions = payload.get("missions", {}) as Dictionary
	_render_missions()
	_update_countdowns()


func _render_missions() -> void:
	for c: Node in _missions_list.get_children():
		c.queue_free()
	var kind: String = _missions_tabs.current
	var list: Array = _missions.get(kind, []) as Array
	if list.is_empty():
		var empty: Label = UiKit.text(tr("missions.empty"), &"body", UiTokens.TEXT_MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_missions_list.add_child(empty)
	for raw: Variant in list:
		_missions_list.add_child(_mission_row(raw as Dictionary))
	_update_countdowns()


func _mission_row(m: Dictionary) -> PanelContainer:
	var card: PanelContainer = UiKit.card()
	var h: HBoxContainer = UiKit.hbox(UiTokens.GUTTER)
	card.add_child(h)
	var info: VBoxContainer = UiKit.vbox(UiTokens.UNIT)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var target: int = maxi(1, int(m.get("target", 1)))
	var progress: int = clampi(int(m.get("progress", 0)), 0, target)
	var desc: Label = UiKit.text(tr(str(m.get("desc_key", ""))).format({"n": target}), &"body")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc)
	var meter_row: HBoxContainer = UiKit.hbox(UiTokens.UNIT)
	var meter: ProgressBar = ProgressBar.new()
	meter.show_percentage = false
	meter.custom_minimum_size = Vector2(0, 4)
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter.max_value = float(target)
	meter.value = float(progress)
	meter_row.add_child(meter)
	meter_row.add_child(UiKit.text("%d / %d" % [progress, target], &"caption", UiTokens.TEXT_MUTED))
	info.add_child(meter_row)
	info.add_child(_reward_row(m.get("reward", {}) as Dictionary))
	h.add_child(info)
	var id: String = str(m.get("id", ""))
	if bool(m.get("claimed", false)):
		var done: IconGlyph = UiKit.icon(&"check", 28, Palette.SUCCESS)
		done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(done)
	elif bool(m.get("complete", false)):
		var claim: UiButton = UiKit.button(tr("missions.claim"), UiKit.ButtonRole.PRIMARY)
		claim.custom_minimum_size = Vector2(UiTokens.u(16), UiTokens.BUTTON_HEIGHT)
		claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		claim.pressed.connect(func() -> void: claim_requested.emit(id))
		h.add_child(claim)
	return card


## Reward preview: the exact contents of the mission reward spec.
static func _reward_row(spec: Dictionary) -> HBoxContainer:
	var row: HBoxContainer = UiKit.hbox(UiTokens.GUTTER)
	if int(spec.get("coins", 0)) > 0:
		row.add_child(_small_chip(&"coin", "+" + UiKit.format_int(int(spec["coins"])), Palette.ACCENT))
	if int(spec.get("gems", 0)) > 0:
		row.add_child(_small_chip(&"gem", "+" + UiKit.format_int(int(spec["gems"])), Palette.SECONDARY))
	if int(spec.get("xp", 0)) > 0:
		row.add_child(_small_chip(&"progress", "+%d XP" % int(spec["xp"]), UiTokens.TEXT_MUTED))
	return row


static func _small_chip(icon_name: StringName, value: String, color: Color) -> HBoxContainer:
	var h: HBoxContainer = UiKit.hbox(UiTokens.UNIT / 2)
	h.add_child(UiKit.icon(icon_name, 18, color))
	h.add_child(UiKit.text(value, &"caption", color))
	return h


func _process(delta: float) -> void:
	if not visible:
		return
	_tick += delta
	if _tick < 1.0:
		return
	_tick -= 1.0
	for k: String in _reset_seconds:
		_reset_seconds[k] = maxi(0, int(_reset_seconds[k]) - 1)
	_update_countdowns()


func _update_countdowns() -> void:
	if _reset == null:
		return
	_reset.text = tr("daily.resets_in").format({"t": format_duration(int(_reset_seconds["challenge"]))})
	var kind: String = _missions_tabs.current if _missions_tabs != null else "daily"
	_missions_reset.text = tr("daily.resets_in").format({"t": format_duration(int(_reset_seconds.get(kind, 0)))})


## "5h 04m" / "12m 09s" / "2d 03h": compact, unambiguous, no seconds above an hour.
static func format_duration(seconds: int) -> String:
	var s: int = maxi(0, seconds)
	var d: int = s / 86400
	var h: int = (s % 86400) / 3600
	var m: int = (s % 3600) / 60
	if d > 0:
		return "%dd %02dh" % [d, h]
	if h > 0:
		return "%dh %02dm" % [h, m]
	return "%dm %02ds" % [m, s % 60]


func handle_back() -> bool:
	back_requested.emit()
	return true
