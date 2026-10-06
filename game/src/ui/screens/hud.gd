class_name Hud
extends UiScreen
## In-run HUD (visual priority 3 and 5): score, combo multiplier, objective,
## level progress and pause. Quiet by default — elements react only when their
## value changes (one punch, then settle).

signal pause_requested

const FORM_HINT_TIME: float = 1.6
const FORM_KEYS: Array[String] = ["form.hop.hint", "form.phase.hint", "form.dash.hint", "form.surge.hint"]
const FORM_ICONS: Array[StringName] = [&"form_orb", &"form_prism", &"form_comet", &"form_surge"]
const TUTORIAL_HINT_LEAD: int = 40
## A chapter's new mechanic is named for this long when its introduction
## levels start (teaching through play, one short line).
const INTRO_HINT_TIME: float = 2.8
const INTRO_HINT_FADE: float = 0.4
## Score nudge on every accepted tap (the score punch on points is 1.06).
const TAP_NUDGE_SCALE: float = 1.03
const STACK_PIP_SIZE: Vector2 = Vector2(12, 12)
const STACK_PIP_GAP: int = 4
const STACK_PIP_EMPTY_ALPHA: float = 0.25

var session: GameplaySession
var _score: Label
var _combo: Label
var _combo_box: Control
var _objective: HBoxContainer
var _objective_label: Label
var _progress: ProgressBar
var _form_hint: HBoxContainer
var _form_icon: IconGlyph
var _form_label: Label
var _tap_hint: Control
var _tap_ring: IconGlyph
var _shield: IconGlyph
## Mass plates stacked on the core (one pip per plate, full = smashes glass).
var _stack: HBoxContainer
var _stack_pips: Array[ColorRect] = []
var _last_plates: int = -1
var _last_taps: int = 0
var _intro_hint: Label
var _intro_left: float = 0.0
var _last_score: int = -1
var _last_combo_mult: float = 1.0
var _last_form: int = -1
var _form_hint_left: float = 0.0
var _tutorial_taps: PackedInt32Array = PackedInt32Array()
var _score_tween: Tween
var _combo_tween: Tween


func build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var root: SafeAreaContainer = make_safe_root()
	var col: VBoxContainer = UiKit.vbox(UiTokens.UNIT)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	var top: HBoxContainer = UiKit.hbox()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	_objective = UiKit.hbox(UiTokens.UNIT)
	_objective.add_child(UiKit.icon(&"target", 22, UiTokens.TEXT_MUTED))
	_objective_label = UiKit.text("", &"caption", UiTokens.TEXT_MUTED)
	_objective.add_child(_objective_label)
	# The slot keeps its width when the objective is hidden (reach-the-end
	# levels) so the score stays at top centre, balanced by the right slot.
	var left: HBoxContainer = UiKit.hbox(0)
	left.custom_minimum_size = Vector2(160, 0)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_objective)
	top.add_child(left)
	var center: VBoxContainer = UiKit.vbox(0)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.alignment = BoxContainer.ALIGNMENT_BEGIN
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(center)
	_score = UiKit.text("0", &"score")
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.pivot_offset = Vector2(0, 0)
	center.add_child(_score)
	_combo_box = Control.new()
	_combo_box.custom_minimum_size = Vector2(0, 36)
	_combo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_combo_box)
	_combo = UiKit.text("", &"h3", Palette.PRIMARY)
	_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_combo_box.add_child(_combo)
	var right: HBoxContainer = UiKit.hbox(UiTokens.UNIT)
	right.custom_minimum_size = Vector2(160, 0)
	right.alignment = BoxContainer.ALIGNMENT_END
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(right)
	_shield = UiKit.icon(&"shield", 24, Palette.SUCCESS)
	_shield.visible = false
	right.add_child(_shield)
	_stack = UiKit.hbox(STACK_PIP_GAP)
	_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for _i: int in SimConst.MAX_PLATES:
		var pip: ColorRect = ColorRect.new()
		pip.custom_minimum_size = STACK_PIP_SIZE
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.color = Palette.FORM_SURGE_HEAVY
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stack.add_child(pip)
		_stack_pips.append(pip)
	_stack.visible = false
	right.add_child(_stack)
	var pause: UiButton = UiKit.icon_button(&"pause", tr("hud.pause"))
	pause.pressed.connect(func() -> void: pause_requested.emit())
	right.add_child(pause)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 3)
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.max_value = 1.0
	col.add_child(_progress)
	_intro_hint = UiKit.text("", &"button", Palette.BONE)
	_intro_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_hint.modulate.a = 0.0
	col.add_child(_intro_hint)
	col.add_child(UiKit.expand())
	_tap_hint = CenterContainer.new()
	_tap_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tap_ring = UiKit.icon(&"target", 72, Palette.with_alpha(Palette.BONE, 0.9))
	var hint_col: VBoxContainer = UiKit.vbox(UiTokens.UNIT)
	hint_col.alignment = BoxContainer.ALIGNMENT_CENTER
	hint_col.add_child(_tap_ring)
	var tap_label: Label = UiKit.text(tr("hud.tap"), &"button")
	tap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_col.add_child(tap_label)
	_tap_hint.add_child(hint_col)
	_tap_hint.visible = false
	col.add_child(_tap_hint)
	_form_hint = UiKit.hbox(UiTokens.UNIT)
	_form_hint.alignment = BoxContainer.ALIGNMENT_CENTER
	_form_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_form_icon = UiKit.icon(&"form_orb", 28)
	_form_hint.add_child(_form_icon)
	_form_label = UiKit.text("", &"button")
	_form_hint.add_child(_form_label)
	_form_hint.modulate.a = 0.0
	col.add_child(_form_hint)
	col.add_child(UiKit.spacer(true, UiTokens.u(6)))


func bind(gameplay_session: GameplaySession) -> void:
	session = gameplay_session


func enter(payload: Dictionary) -> void:
	_last_score = -1
	_last_combo_mult = 1.0
	_last_form = -1
	_form_hint_left = 0.0
	_combo.text = ""
	_tutorial_taps = PackedInt32Array()
	if bool(payload.get("tutorial", false)):
		for t: Variant in payload.get("solution_taps", []) as Array:
			_tutorial_taps.append(int(t))
	var level: Dictionary = session.level_data if session != null else {}
	var obj: Dictionary = level.get("objective", {}) as Dictionary
	_objective.visible = str(obj.get("type", "reach_end")) in ["collect", "shatter"]
	_stack.visible = (level.get("mechanics", []) as Array).has("stack")
	_last_plates = -1
	_last_taps = 0
	_show_intro_hint(str(level.get("intro_mechanic", "")))


func _process(delta: float) -> void:
	if session == null or session.sim == null or not visible:
		return
	var sim: FluxSim = session.sim
	if sim.score != _last_score:
		if _last_score >= 0 and sim.score > _last_score:
			_punch_score()
		_last_score = sim.score
		_score.text = UiKit.format_int(sim.score)
	if sim.taps != _last_taps:
		# Feedback chain: every accepted tap gives the score a small nudge
		# (score events punch harder).
		if sim.taps > _last_taps:
			_nudge_score()
		_last_taps = sim.taps
	var mult: float = SimConst.combo_multiplier(sim.combo)
	if mult != _last_combo_mult:
		_combo.text = "" if mult <= 1.0 else "×%s  ·  %d" % [_mult_text(mult), sim.combo]
		if mult > _last_combo_mult:
			_punch_combo()
		_last_combo_mult = mult
	_combo.add_theme_color_override("font_color", Palette.ACCENT if sim.overdrive_timer > 0.0 else Palette.PRIMARY)
	_progress.value = clampf(sim.d / maxf(sim.level.length, 1.0), 0.0, 1.0) if not sim.level.endless else 0.0
	_progress.visible = not sim.level.endless
	_shield.visible = sim.shields > 0
	if _stack.visible and sim.plates != _last_plates:
		_last_plates = sim.plates
		for i: int in _stack_pips.size():
			_stack_pips[i].modulate.a = 1.0 if i < sim.plates else STACK_PIP_EMPTY_ALPHA
	if _objective.visible:
		_objective_label.text = "%d / %d" % [sim.objective_progress(), sim.level.objective_target]
	if sim.form != _last_form:
		if _last_form >= 0 or sim.form != SimConst.Form.HOP:
			_show_form_hint(sim.form)
		_last_form = sim.form
	if _form_hint_left > 0.0:
		_form_hint_left -= delta
		_form_hint.modulate.a = (
			clampf(_form_hint_left / 0.3, 0.0, 1.0)
			if _form_hint_left < 0.3
			else minf(1.0, _form_hint.modulate.a + delta * 6.0)
		)
	if _intro_left > 0.0:
		_intro_left -= delta
		_intro_hint.modulate.a = clampf(_intro_left / INTRO_HINT_FADE, 0.0, 1.0)
	_update_tap_hint()


## Names the chapter's new mechanic on its introduction levels.
func _show_intro_hint(mechanic: String) -> void:
	var key: String = intro_hint_key(mechanic)
	var text: String = tr(key) if not mechanic.is_empty() else ""
	_intro_left = INTRO_HINT_TIME if not text.is_empty() and text != key else 0.0
	_intro_hint.text = text if _intro_left > 0.0 else ""
	_intro_hint.modulate.a = 1.0 if _intro_left > 0.0 else 0.0


static func intro_hint_key(mechanic: String) -> String:
	return "hint.mechanic." + mechanic


func _mult_text(mult: float) -> String:
	return str(int(mult)) if is_equal_approx(mult, roundf(mult)) else "%.1f" % mult


func _show_form_hint(form: int) -> void:
	_form_icon.icon = FORM_ICONS[clampi(form, 0, 3)]
	_form_icon.color = Palette.form_color(form, session.sim.phase, session.sim.heavy)
	_form_label.text = tr(FORM_KEYS[clampi(form, 0, 3)])
	_form_hint_left = FORM_HINT_TIME


## Tutorial: show "TAP" while the next planned tap's window is near.
func _update_tap_hint() -> void:
	if _tutorial_taps.is_empty() or not session.is_running():
		_tap_hint.visible = false
		return
	var tick: int = session.sim.tick
	var show: bool = false
	for t: int in _tutorial_taps:
		if tick >= t - TUTORIAL_HINT_LEAD and tick <= t + 6:
			show = true
			break
	_tap_hint.visible = show
	if show:
		var pulse: float = 0.85 + 0.15 * sin(float(Time.get_ticks_msec()) * 0.012)
		_tap_ring.scale = Vector2(pulse, pulse)
		_tap_ring.pivot_offset = _tap_ring.size * 0.5


func _punch_score() -> void:
	if _score_tween != null:
		_score_tween.kill()
	_score.pivot_offset = _score.size * 0.5
	_score_tween = create_tween()
	_score_tween.tween_property(_score, "scale", Vector2(1.06, 1.06), 0.05)
	_score_tween.tween_property(_score, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE)


func _nudge_score() -> void:
	if _score_tween != null and _score_tween.is_running():
		return
	_score.pivot_offset = _score.size * 0.5
	_score_tween = create_tween()
	_score_tween.tween_property(_score, "scale", Vector2(TAP_NUDGE_SCALE, TAP_NUDGE_SCALE), 0.04)
	_score_tween.tween_property(_score, "scale", Vector2.ONE, 0.08).set_trans(Tween.TRANS_SINE)


func _punch_combo() -> void:
	if _combo_tween != null:
		_combo_tween.kill()
	_combo.pivot_offset = _combo.size * 0.5
	_combo_tween = create_tween()
	_combo_tween.tween_property(_combo, "scale", Vector2(1.18, 1.18), 0.06)
	_combo_tween.tween_property(_combo, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
