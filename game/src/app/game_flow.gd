class_name GameFlow
extends Node
## App root (main scene). Owns the persistent gameplay session + view (restarts
## never reload scenes), the UI router and the application state machine, and
## routes every screen intent to the systems. Screens are dumb views; payloads
## come from [Presenters]; run bookkeeping lives in [RunController].

const RESULT_DELAY: float = 0.55
const READY_FIRST: float = 0.8
const READY_RESTART: float = 0.35
const ATTRACT_READY: float = 0.2

## The service graph; the autoload unless one is injected before _ready (tests).
var s: AppServices
var session: GameplaySession
var view: GameplayView
var runs: RunController
var router: ScreenRouter
var fsm: GameStateMachine = GameStateMachine.new()
var hud: Hud
var attract: bool = true

var _pick_mode: StringName = &""
var _world_id: String = ""
var _reveals: Array = []
var _last_outcome: Dictionary = {}
var _settings_return: StringName = &""
var _restore_status: String = ""
var _ending: bool = false


func _ready() -> void:
	if s == null:
		s = get_node("/root/Services") as AppServices
	if not s.is_booted:
		s.boot()
	view = GameplayView.new()
	add_child(view)
	session = GameplaySession.new()
	add_child(session)
	view.bind(session)
	runs = RunController.new(s, session)
	session.run_ended.connect(_on_run_ended)
	session.run_started.connect(
		func(level_id: String) -> void:
			if not attract:
				s.bus.run_started.emit(level_id, session.mode_id)
	)
	view.feedback.connect(_on_feedback)
	_build_ui()
	_apply_settings_to_view()
	s.bus.cosmetic_equipped.connect(func(_c: StringName, _id: String) -> void: _apply_cosmetics())
	s.bus.settings_changed.connect(func(_k: StringName, _v: Variant) -> void: _apply_settings_to_view())
	s.bus.quality_changed.connect(func(_p: StringName, _a: bool) -> void: _apply_quality())
	_apply_cosmetics()
	_apply_quality()
	fsm.state_changed.connect(
		func(_from: GameStateMachine.State, to: GameStateMachine.State, _p: Dictionary) -> void:
			s.errors.context_provider = func() -> Dictionary:
				var ctx: Dictionary = AppInfo.context()
				ctx["state"] = GameStateMachine.state_name(to)
				ctx["level"] = str(runs.context.get("level_id", ""))
				return ctx
	)
	fsm.transition_to(GameStateMachine.State.MAIN_MENU)
	_start_attract()
	_show_main()


# --- UI construction -------------------------------------------------------------


func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	router = ScreenRouter.new()
	layer.add_child(router)
	hud = Hud.new()
	hud.bind(session)
	router.register(&"hud", hud)
	hud.pause_requested.connect(_pause)
	var main: MainMenu = MainMenu.new()
	router.register(&"main", main)
	main.play_requested.connect(func() -> void: _play_campaign(s.progression.next_level_to_play(), &"classic"))
	main.daily_requested.connect(_show_daily)
	main.modes_requested.connect(_show_modes)
	main.worlds_requested.connect(
		func() -> void:
			_pick_mode = &""
			_show_worlds()
	)
	main.tab_requested.connect(_on_tab)
	var worlds: WorldSelect = WorldSelect.new()
	router.register(&"worlds", worlds)
	worlds.world_selected.connect(_show_levels)
	worlds.back_requested.connect(_show_main)
	var levels: LevelSelect = LevelSelect.new()
	router.register(&"levels", levels)
	levels.level_selected.connect(
		func(id: String) -> void: _play_campaign(id, _pick_mode if _pick_mode != &"" else &"classic")
	)
	levels.back_requested.connect(_show_worlds)
	var modes: ModesScreen = ModesScreen.new()
	router.register(&"modes", modes)
	modes.mode_selected.connect(_on_mode_selected)
	modes.back_requested.connect(_show_main)
	var daily: DailyScreen = DailyScreen.new()
	router.register(&"daily", daily)
	daily.play_requested.connect(func() -> void: _start_run(&"daily"))
	daily.claim_requested.connect(_claim_mission)
	daily.back_requested.connect(_show_main)
	var progress: ProgressScreen = ProgressScreen.new()
	router.register(&"progress", progress)
	progress.board_requested.connect(_load_board)
	progress.back_requested.connect(_show_main)
	for mode: StringName in [&"shop", &"collection"]:
		var cos: CosmeticsScreen = CosmeticsScreen.new()
		cos.mode = mode
		router.register(mode, cos)
		cos.buy_requested.connect(_buy)
		cos.equip_requested.connect(_equip)
		cos.pack_requested.connect(_buy_pack)
		cos.back_requested.connect(_show_main)
	var settings: SettingsScreen = SettingsScreen.new()
	router.register(&"settings", settings)
	settings.setting_changed.connect(func(key: String, value: Variant) -> void: s.settings.set_value(key, value))
	settings.restore_requested.connect(_restore_purchases)
	settings.back_requested.connect(_close_settings)
	var pause: PauseOverlay = PauseOverlay.new()
	router.register(&"pause", pause)
	pause.resume_requested.connect(_resume)
	pause.restart_requested.connect(_restart)
	pause.settings_requested.connect(
		func() -> void:
			_settings_return = &"pause"
			router.push_overlay(&"settings", Presenters.settings(s, _restore_status))
	)
	pause.home_requested.connect(_quit_run)
	var fail: FailOverlay = FailOverlay.new()
	router.register(&"fail", fail)
	fail.retry_requested.connect(_restart)
	fail.revive_requested.connect(_revive)
	fail.home_requested.connect(_quit_run)
	var complete: CompleteOverlay = CompleteOverlay.new()
	router.register(&"complete", complete)
	complete.next_requested.connect(_next_level)
	complete.replay_requested.connect(_restart)
	complete.home_requested.connect(_quit_run)
	complete.double_requested.connect(_double_reward)
	complete.star_landed.connect(func(_i: int) -> void: s.audio.play_sfx(&"star"))
	var reward: RewardOverlay = RewardOverlay.new()
	router.register(&"reward", reward)
	reward.continue_requested.connect(_next_reveal)
	reward.item_landed.connect(func(_i: int) -> void: s.audio.play_sfx(&"coin"))
	router.back_unhandled.connect(
		func() -> void:
			if router.current_id == &"main":
				s.flush_now()
	)


# --- Navigation ------------------------------------------------------------------


func _go(state: GameStateMachine.State) -> void:
	if fsm.current != state:
		fsm.transition_to(state)


func _show_main() -> void:
	_go(GameStateMachine.State.MAIN_MENU)
	router.show_screen(&"main", Presenters.main_menu(s))
	if not attract:
		_start_attract()


func _show_worlds() -> void:
	_go(GameStateMachine.State.WORLD_SELECT)
	router.show_screen(&"worlds", Presenters.worlds(s))


func _show_levels(world_id: String) -> void:
	_world_id = world_id
	_go(GameStateMachine.State.LEVEL_SELECT)
	router.show_screen(&"levels", Presenters.level_grid(s, world_id))


func _show_modes() -> void:
	_go(GameStateMachine.State.MODES)
	router.show_screen(&"modes", Presenters.modes(s))


func _show_daily() -> void:
	s.missions.refresh()
	_go(GameStateMachine.State.DAILY)
	router.show_screen(&"daily", Presenters.daily(s))
	s.analytics.track(&"daily_started", {})


func _on_tab(tab: StringName) -> void:
	match tab:
		&"progress":
			_go(GameStateMachine.State.PROGRESS)
			router.show_screen(&"progress", Presenters.progress(s, "overview", {}))
			_load_board(Presenters.board_ids(s)[0])
		&"shop":
			_go(GameStateMachine.State.SHOP)
			router.show_screen(&"shop", Presenters.cosmetics(s, &"shop"))
			s.analytics.track(&"shop_opened", {})
		&"collection":
			_go(GameStateMachine.State.COLLECTION)
			router.show_screen(&"collection", Presenters.cosmetics(s, &"collection"))
		&"settings":
			_settings_return = &""
			_go(GameStateMachine.State.SETTINGS)
			router.show_screen(&"settings", Presenters.settings(s, _restore_status))


func _close_settings() -> void:
	if _settings_return == &"pause":
		_settings_return = &""
		router.close_overlay(&"settings")
		return
	_show_main()


func _on_mode_selected(mode_id: StringName) -> void:
	match s.modes.source(mode_id):
		"campaign_pick":
			_pick_mode = mode_id
			_show_worlds()
		"daily":
			_show_daily()
		"campaign":
			_play_campaign(s.progression.next_level_to_play(), mode_id)
		_:
			_start_run(mode_id)


# --- Runs --------------------------------------------------------------------------


func _start_attract() -> void:
	attract = true
	var id: String = s.progression.next_level_to_play()
	var data: Dictionary = s.levels.load_level(id)
	if data.is_empty() or not session.load_level(data):
		return
	var taps: PackedInt32Array = PackedInt32Array()
	for t: Variant in (data.get("solution", {}) as Dictionary).get("taps", []) as Array:
		taps.append(int(t))
	session.autopilot = taps
	_present_level(data)
	session.begin(ATTRACT_READY)
	s.audio.play_music("menu")


func _play_campaign(level_id: String, mode_id: StringName) -> void:
	if level_id.is_empty() or not s.progression.is_level_unlocked(level_id):
		return
	_start_run(mode_id, level_id)


func _start_run(mode_id: StringName, level_id: String = "") -> void:
	if not s.modes.is_unlocked(mode_id, s.mode_progress()):
		return
	attract = false
	session.autopilot = PackedInt32Array()
	if not runs.prepare(mode_id, level_id):
		s.bus.toast_requested.emit(Presenters.t("toast.run_unavailable"), &"info")
		_show_main()
		return
	_go(GameStateMachine.State.COUNTDOWN)
	_present_level(session.level_data)
	router.clear_screen()
	router.show_screen(
		&"hud",
		{
			"tutorial": bool(session.level_data.get("tutorial", false)),
			"solution_taps": (session.level_data.get("solution", {}) as Dictionary).get("taps", [])
		}
	)
	session.begin(READY_FIRST)
	_go(GameStateMachine.State.PLAYING)
	var world: Dictionary = s.catalog.world(str(session.level_data.get("world", "")))
	s.audio.play_music(str(world.get("id", "menu")), str(session.level_data.get("kind", "")) == "boss")
	s.analytics.track(&"level_started", {"level": str(runs.context.get("level_id", "")), "mode": String(mode_id)})


func _present_level(data: Dictionary) -> void:
	view.apply_world(WorldTheme.from_world(s.catalog.world(str(data.get("world", "neon_core")))))
	_apply_cosmetics()
	view.setup_level()


func _restart() -> void:
	router.close_overlays()
	_ending = false
	if runs.streamer != null:
		# Endless courses are rebuilt from the same weekly seed.
		_start_run(runs.context.get("mode", &"endless") as StringName)
		return
	if str(runs.context.get("source", "")) == "boss_rush":
		_start_run(&"boss_rush")
		return
	session.restart(READY_RESTART)
	view.reset_for_run(false)
	router.show_screen(&"hud", {})
	_go(GameStateMachine.State.COUNTDOWN)
	_go(GameStateMachine.State.PLAYING)
	s.bus.run_restarted.emit(str(runs.context.get("level_id", "")))


func _pause() -> void:
	if attract or not session.is_running():
		return
	session.set_paused(true)
	_go(GameStateMachine.State.PAUSED)
	router.push_overlay(&"pause")
	s.bus.run_paused.emit(true)


func _resume() -> void:
	router.close_overlays()
	session.set_paused(false)
	_go(GameStateMachine.State.PLAYING)
	s.bus.run_paused.emit(false)


func _quit_run() -> void:
	session.set_paused(false)
	_ending = false
	router.close_overlays()
	_show_main()


func _on_run_ended(result: RunResult) -> void:
	if attract:
		_start_attract()
		return
	if _ending:
		return
	_ending = true
	if result.completed and runs.advance_rush(result):
		# Boss rush continues straight into the next boss.
		_ending = false
		_present_level(session.level_data)
		session.begin(READY_FIRST)
		return
	if result.completed:
		s.bus.run_completed.emit(result)
	else:
		s.bus.run_failed.emit(result)
	_last_outcome = runs.finish(result)
	await get_tree().create_timer(RESULT_DELAY).timeout
	_ending = false
	_reveals = (_last_outcome.get("reveals", []) as Array).duplicate()
	if result.completed:
		s.audio.play_stinger(&"perfect" if result.perfect else &"complete")
		_go(GameStateMachine.State.COMPLETE)
		router.push_overlay(
			&"complete",
			{
				"result": result,
				"best": int(_last_outcome.get("best", 0)),
				"new_best": bool(_last_outcome.get("new_best", false)),
				"reward": _last_outcome.get("reward"),
				"can_double": bool(_last_outcome.get("can_double", false)),
				"has_next": bool(_last_outcome.get("has_next", false))
			}
		)
		if s.ads.can_show_interstitial(&"level_end"):
			await s.ads.show_interstitial(&"level_end")
	else:
		_go(GameStateMachine.State.FAILED)
		router.push_overlay(
			&"fail",
			{
				"result": result,
				"best": int(_last_outcome.get("best", 0)),
				"progress": float(_last_outcome.get("progress", 0.0)),
				"can_revive": bool(_last_outcome.get("can_revive", false))
			}
		)
	if not _reveals.is_empty():
		_next_reveal()


## Shows queued reveals (level-up, unlocks, achievements) one at a time on top
## of the result screen; the result screen stays underneath.
func _next_reveal() -> void:
	router.close_overlay(&"reward")
	if _reveals.is_empty():
		return
	var r: Dictionary = _reveals.pop_front() as Dictionary
	_go(GameStateMachine.State.REWARD)
	router.push_overlay(&"reward", r)


func _next_level() -> void:
	var next_id: String = str(_last_outcome.get("next_level_id", ""))
	router.close_overlays()
	if next_id.is_empty():
		_show_main()
		return
	_play_campaign(next_id, runs.context.get("mode", &"classic") as StringName)


func _revive() -> void:
	var shown: Dictionary = await s.ads.show_rewarded(&"revive")
	if not bool(shown.get("granted", false)):
		return
	if session.revive():
		router.close_overlays()
		router.show_screen(&"hud", {})
		_go(GameStateMachine.State.PLAYING)


func _double_reward() -> void:
	var bundle: RewardBundle = _last_outcome.get("reward") as RewardBundle
	if bundle == null:
		return
	var shown: Dictionary = await s.ads.show_rewarded(&"double_reward")
	if not bool(shown.get("granted", false)):
		return
	var extra: RewardBundle = runs.grant_double(bundle)
	_reveals.append(
		{
			"eyebrow": Presenters.t("reveal.bonus"),
			"title": Presenters.t("reveal.doubled"),
			"subtitle": "",
			"bundle": extra
		}
	)
	_next_reveal()


# --- Meta actions -------------------------------------------------------------------


func _claim_mission(mission_id: String) -> void:
	var bundle: RewardBundle = s.missions.claim(mission_id)
	if bundle == null or bundle.is_empty():
		return
	s.analytics.track(&"mission_claimed", {"id": mission_id})
	router.show_screen(&"daily", Presenters.daily(s))
	_reveals.append(
		{
			"eyebrow": Presenters.t("reveal.mission"),
			"title": Presenters.t("reveal.mission_done"),
			"subtitle": "",
			"bundle": bundle
		}
	)
	_next_reveal()


func _load_board(board_id: String) -> void:
	var fetched: Dictionary = await s.leaderboard.fetch(board_id)
	var screen: ProgressScreen = router.screen(&"progress") as ProgressScreen
	if screen != null and router.current_id == &"progress":
		screen.show_board(Presenters.board_view(s, fetched))


func _buy(item_id: String) -> void:
	if s.cosmetics.purchase(item_id):
		s.cosmetics.equip(item_id)
	router.show_screen(router.current_id, Presenters.cosmetics(s, router.current_id))


func _equip(item_id: String) -> void:
	s.cosmetics.equip(item_id)
	router.show_screen(router.current_id, Presenters.cosmetics(s, router.current_id))


func _buy_pack(product_id: String) -> void:
	var result: Dictionary = await s.store.purchase(product_id)
	if not bool(result.get("ok", false)):
		s.bus.toast_requested.emit(Presenters.t(StoreService.message_key(str(result.get("error", "")))), &"info")
	router.show_screen(router.current_id, Presenters.cosmetics(s, router.current_id))


func _restore_purchases() -> void:
	_restore_status = Presenters.t("settings.restoring")
	var screen: SettingsScreen = router.screen(&"settings") as SettingsScreen
	screen.set_restore_status(_restore_status)
	var result: Dictionary = await s.store.restore_purchases()
	if bool(result.get("ok", false)):
		_restore_status = Presenters.t("settings.restored").format(
			{"n": (result.get("product_ids", []) as Array).size()}
		)
	else:
		_restore_status = Presenters.t(StoreService.message_key(str(result.get("error", ""))))
	screen.set_restore_status(_restore_status)


# --- Presentation glue --------------------------------------------------------------


func _on_feedback(kind: StringName, strength: float, pitch_step: int) -> void:
	if attract:
		return
	s.audio.on_feedback(kind, strength, pitch_step)
	s.haptics.on_feedback(kind, strength, pitch_step)
	if kind == &"combo":
		s.bus.combo_reached.emit(pitch_step)
		s.audio.set_combo(pitch_step)


func _apply_cosmetics() -> void:
	view.apply_cosmetics(s.cosmetics.core_skin_params(), s.cosmetics.trail_params())


func _apply_quality() -> void:
	var p: Dictionary = s.quality.params()
	view.set_quality(
		bool(p.get("post_fx", true)),
		float(p.get("particle_scale", 1.0)),
		int(p.get("trail_points", 18)),
		bool(p.get("dynamic_light", true)),
		bool(p.get("shadows", true))
	)


func _apply_settings_to_view() -> void:
	var reduce: bool = s.settings.get_bool("reduce_motion")
	router.reduce_motion = reduce
	view.reduce_motion = reduce
	view.core_view.reduce_motion = reduce
	(router.screen(&"reward") as RewardOverlay).reduce_motion = reduce


func _process(delta: float) -> void:
	if not attract and session.is_running():
		if runs.pump():
			view.on_stream_appended()
		if s.quality.feed_frame(delta):
			_apply_quality()


func _unhandled_input(event: InputEvent) -> void:
	# Desktop clicks arrive as touches too (emulate_touch_from_mouse), so only
	# touch and the space key count: one physical tap is never counted twice.
	var pressed: bool = (
		(event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
		or (
			event is InputEventKey
			and (event as InputEventKey).pressed
			and not (event as InputEventKey).echo
			and (event as InputEventKey).keycode == KEY_SPACE
		)
	)
	if not pressed or attract:
		return
	if fsm.current == GameStateMachine.State.PLAYING or fsm.current == GameStateMachine.State.COUNTDOWN:
		session.request_tap()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# Never let a run continue in the background.
		_pause()
