class_name CompleteOverlay
extends UiScreen
## Level complete + reward sequence (ART_DIRECTION §8 reward motion):
## stars land one by one (120 ms apart, overshoot, one chime each), score and
## rewards count up, then actions appear. Values shown are exactly the granted
## reward bundle — nothing is invented for the animation.

signal next_requested
signal replay_requested
signal home_requested
signal double_requested
signal star_landed(index: int)

const GRADE_KEYS: Array[String] = ["", "grade.normal", "grade.good", "grade.great", "grade.perfect"]
const STAR_SIZE: int = 72

var _grade: Label
var _score: Label
var _best: Label
var _stars: Array[IconGlyph] = []
var _rewards: HBoxContainer
var _actions: VBoxContainer
var _double: UiButton
var _next: UiButton
var _seq_tween: Tween

func build() -> void:
	is_overlay = true
	add_scrim(0.6)
	var root: SafeAreaContainer = make_safe_root()
	var col: VBoxContainer = UiKit.vbox(UiTokens.GUTTER)
	root.add_child(col)
	col.add_child(UiKit.spacer(true, UiTokens.u(10)))
	_grade = UiKit.text("", &"caption", Palette.ACCENT)
	_grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_grade)
	var star_row: HBoxContainer = UiKit.hbox(UiTokens.u(3))
	star_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i: int in 3:
		var star: IconGlyph = UiKit.icon(&"star", STAR_SIZE, Palette.SLATE)
		star.stroke_units = 1.6
		star_row.add_child(star)
		_stars.append(star)
	col.add_child(star_row)
	_score = UiKit.text("0", &"score")
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_score)
	_best = UiKit.text("", &"caption", UiTokens.TEXT_MUTED)
	_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_best)
	col.add_child(UiKit.spacer(true, UiTokens.u(2)))
	_rewards = UiKit.hbox(UiTokens.u(4))
	_rewards.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_rewards)
	col.add_child(UiKit.expand())
	_actions = UiKit.vbox(UiTokens.GUTTER)
	col.add_child(_actions)
	_next = UiKit.button(tr("complete.next"), UiKit.ButtonRole.PRIMARY, &"chevron_right")
	_next.pressed.connect(func() -> void: next_requested.emit())
	_actions.add_child(_next)
	_double = UiKit.button(tr("complete.double_optional"), UiKit.ButtonRole.SECONDARY, &"coin")
	_double.pressed.connect(func() -> void: double_requested.emit())
	_actions.add_child(_double)
	var row: HBoxContainer = UiKit.hbox()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var replay: UiButton = UiKit.button(tr("complete.replay"), UiKit.ButtonRole.TERTIARY, &"retry")
	replay.pressed.connect(func() -> void: replay_requested.emit())
	row.add_child(replay)
	var home: UiButton = UiKit.button(tr("fail.home"), UiKit.ButtonRole.TERTIARY, &"home")
	home.pressed.connect(func() -> void: home_requested.emit())
	row.add_child(home)
	_actions.add_child(row)

## payload: {"result": RunResult, "best": int, "new_best": bool,
##           "reward": RewardBundle, "can_double": bool, "has_next": bool}
func enter(payload: Dictionary) -> void:
	var result: RunResult = payload.get("result") as RunResult
	if result == null:
		return
	_grade.text = tr(GRADE_KEYS[clampi(result.grade, 0, 4)])
	_score.text = "0"
	var best: int = int(payload.get("best", 0))
	_best.text = tr("result.new_best") if bool(payload.get("new_best", false)) else (tr("result.best") + "  " + UiKit.format_int(best))
	for star: IconGlyph in _stars:
		star.icon = &"star"
		star.color = Palette.SLATE
		star.scale = Vector2.ONE
	for c: Node in _rewards.get_children():
		c.queue_free()
	var reward: RewardBundle = payload.get("reward") as RewardBundle
	var reward_labels: Array[Label] = []
	var reward_values: Array[int] = []
	if reward != null:
		for item: Dictionary in reward.items:
			var t: StringName = item["type"] as StringName
			var icon_name: StringName = {&"coins": &"coin", &"gems": &"gem", &"xp": &"progress"}.get(t, &"star") as StringName
			var color: Color = Palette.ACCENT if t == &"coins" else (Palette.SECONDARY if t == &"gems" else UiTokens.TEXT)
			if t in [&"coins", &"gems", &"xp"]:
				var chip: HBoxContainer = UiKit.stat_chip(icon_name, "0", color)
				_rewards.add_child(chip)
				reward_labels.append(chip.get_node("Value") as Label)
				reward_values.append(int(item["amount"]))
	_double.visible = bool(payload.get("can_double", false))
	_next.visible = bool(payload.get("has_next", true))
	_actions.modulate.a = 0.0
	_play_sequence(result, reward_labels, reward_values)

func _play_sequence(result: RunResult, labels: Array[Label], values: Array[int]) -> void:
	if _seq_tween != null:
		_seq_tween.kill()
	_seq_tween = create_tween()
	_seq_tween.tween_interval(0.25)
	for i: int in 3:
		var star: IconGlyph = _stars[i]
		var earned: bool = i < result.stars
		_seq_tween.tween_callback(_land_star.bind(i, earned))
		if earned:
			star.pivot_offset = Vector2(STAR_SIZE, STAR_SIZE) * 0.5
			_seq_tween.tween_property(star, "scale", Vector2(1.25, 1.25), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_seq_tween.tween_property(star, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			_seq_tween.tween_interval(UiTokens.STAR_INTERVAL)
	_seq_tween.tween_method(func(v: float) -> void: _score.text = UiKit.format_int(int(v)), 0.0, float(result.score), UiTokens.COUNT_UP_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for k: int in labels.size():
		var label: Label = labels[k]
		var target: float = float(values[k])
		_seq_tween.parallel().tween_method(func(v: float) -> void: label.text = UiKit.format_int(int(v)), 0.0, target, UiTokens.COUNT_UP_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_seq_tween.tween_property(_actions, "modulate:a", 1.0, 0.2)
	_seq_tween.tween_callback(func() -> void: _next.grab_focus())

func _land_star(index: int, earned: bool) -> void:
	var star: IconGlyph = _stars[index]
	if earned:
		star.icon = &"star_filled"
		star.color = Palette.ACCENT
		star_landed.emit(index)

## Skip the sequence on tap (respect the player's time).
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed and _seq_tween != null and _seq_tween.is_running():
		_seq_tween.custom_step(10.0)

func handle_back() -> bool:
	home_requested.emit()
	return true
