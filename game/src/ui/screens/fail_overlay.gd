class_name FailOverlay
extends UiScreen
## Fail screen: PLAY AGAIN is the dominant, thumb-reachable action and appears
## fast (one-more-try). The optional rewarded revive is clearly labelled as
## optional and only shown when an ad is actually available; no countdown.

signal retry_requested
signal revive_requested
signal home_requested

const TIP_KEYS: Dictionary = {
	SimConst.FailReason.WRONG_PHASE: "fail.tip.phase",
	SimConst.FailReason.OBJECTIVE: "fail.tip.objective",
	SimConst.FailReason.MISSED_SPARK: "fail.tip.missed",
	SimConst.FailReason.TIME_UP: "fail.tip.time",
}

var _score: Label
var _best: Label
var _progress: ProgressBar
var _progress_label: Label
var _tip: Label
var _revive: UiButton
var _retry: UiButton


func build() -> void:
	is_overlay = true
	add_scrim(0.55)
	var root: SafeAreaContainer = make_safe_root()
	var col: VBoxContainer = UiKit.vbox(UiTokens.GUTTER)
	root.add_child(col)
	col.add_child(UiKit.expand())
	var card: PanelContainer = UiKit.card()
	col.add_child(card)
	var inner: VBoxContainer = UiKit.vbox(UiTokens.UNIT)
	card.add_child(inner)
	var head: HBoxContainer = UiKit.hbox()
	var titles: VBoxContainer = UiKit.vbox(0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(UiKit.text(tr("fail.title"), &"caption", Palette.FAILURE))
	_score = UiKit.text("0", &"h2")
	titles.add_child(_score)
	head.add_child(titles)
	_best = UiKit.text("", &"caption", UiTokens.TEXT_MUTED)
	_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_best.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_best)
	inner.add_child(head)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 6)
	_progress.max_value = 1.0
	inner.add_child(_progress)
	_progress_label = UiKit.text("", &"caption", UiTokens.TEXT_MUTED)
	inner.add_child(_progress_label)
	_tip = UiKit.text("", &"body", UiTokens.TEXT_MUTED)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(_tip)
	col.add_child(UiKit.spacer(true, UiTokens.UNIT))
	_retry = UiKit.button(tr("fail.play_again"), UiKit.ButtonRole.PRIMARY, &"retry")
	_retry.pressed.connect(func() -> void: retry_requested.emit())
	col.add_child(_retry)
	_revive = UiKit.button(tr("fail.revive_optional"), UiKit.ButtonRole.SECONDARY, &"play")
	_revive.pressed.connect(func() -> void: revive_requested.emit())
	col.add_child(_revive)
	var home: UiButton = UiKit.button(tr("fail.home"), UiKit.ButtonRole.TERTIARY, &"home")
	home.pressed.connect(func() -> void: home_requested.emit())
	col.add_child(home)


## payload: {"result": RunResult, "best": int, "progress": float, "can_revive": bool}
func enter(payload: Dictionary) -> void:
	var result: RunResult = payload.get("result") as RunResult
	if result == null:
		return
	_score.text = UiKit.format_int(result.score)
	var best: int = int(payload.get("best", 0))
	_best.text = tr("result.best") + "  " + UiKit.format_int(best) if best > 0 else ""
	var raw_progress: float = float(payload.get("progress", 0.0))
	# Streamed courses (Endless, Time Attack, Zen) have no finish line: the
	# distance is the measure, a "0% of the way" bar would be false.
	_progress.visible = raw_progress >= 0.0
	if raw_progress < 0.0:
		_progress_label.text = tr("fail.distance").format({"m": UiKit.format_int(int(result.distance))})
	else:
		var progress: float = clampf(raw_progress, 0.0, 1.0)
		_progress.value = progress
		_progress_label.text = tr("fail.progress").format({"percent": int(round(progress * 100.0))})
	_tip.text = tr(str(TIP_KEYS.get(result.fail_reason, "fail.tip.general")))
	_revive.visible = bool(payload.get("can_revive", false))
	_retry.grab_focus.call_deferred()


## Withdraws the revive offer (the run was applied, e.g. the app was left).
func disable_revive() -> void:
	if _revive != null:
		_revive.visible = false


func handle_back() -> bool:
	home_requested.emit()
	return true
