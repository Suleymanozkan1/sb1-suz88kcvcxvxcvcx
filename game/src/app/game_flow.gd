class_name GameFlow
extends Node
## App root (main scene) and composition root. Owns the persistent gameplay
## session + view (restarts never reload scenes), the UI router and the
## application state machine, builds every screen and wires its intents, and
## runs the run lifecycle (attract, start, restart, pause, revive, result).
## Screens are dumb views; payloads come from [Presenters]. The collaborators:
## [RunController] (run bookkeeping), [RevealQueue] (reveals on the reward
## overlay), [MetaActions] (the meta screens' actions), [MenuNavigator] (menu
## screens) and [ViewSync] (settings, cosmetics, quality and world veils).

const RESULT_DELAY: float = 0.55
const READY_FIRST: float = 0.8
const READY_RESTART: float = 0.35
const ATTRACT_READY: float = 0.2
## Canvas layer of screens and toasts: above the world veil ([constant ViewSync.VEIL_LAYER]).
const UI_LAYER: int = 10

## The service graph; the autoload unless one is injected before _ready (tests).
var s: AppServices
var session: GameplaySession
var view: GameplayView
var runs: RunController
var router: ScreenRouter
var fsm: GameStateMachine = GameStateMachine.new()
var reveals: RevealQueue
var meta: MetaActions
var menus: MenuNavigator
var view_sync: ViewSync
var hud: Hud
var toast: ToastView
var attract: bool = true

var _last_outcome: Dictionary = {}
var _ending: bool = false
## A rewarded revive ad is showing (reveals wait; the pending run stays open).
var _reviving: bool = false


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
	view_sync = ViewSync.new(s, view, router)
	add_child(view_sync)
	s.bus.locale_changed.connect(func(_l: String) -> void: menus.relocalize.call_deferred())
	fsm.state_changed.connect(
		func(_from: GameStateMachine.State, to: GameStateMachine.State, _p: Dictionary) -> void:
			s.hold_autosave = to == GameStateMachine.State.PLAYING or to == GameStateMachine.State.COUNTDOWN
			s.errors.context_provider = func() -> Dictionary:
				var ctx: Dictionary = AppInfo.context()
				ctx["state"] = GameStateMachine.state_name(to)
				ctx["level"] = str(runs.context.get("level_id", ""))
				return ctx
	)
	fsm.transition_to(GameStateMachine.State.MAIN_MENU)
	_start_attract()
	_show_main()
	_announce_save_state()


## Tells the player, calmly, when their progress came from the backup copy or
## had to start fresh, and when a newer-version save was kept aside.
func _announce_save_state() -> void:
	var source: String = s.save.last_load_source
	if SaveService.RECOVERY_TEXT_KEYS.has(source) and not s.save.last_errors.is_empty():
		toast.show_message(Presenters.t(str(SaveService.RECOVERY_TEXT_KEYS[source])), &"restore")
	if not s.save.preserved_future.is_empty():
		toast.show_message(Presenters.t(SaveService.FUTURE_TEXT_KEY), &"info")


# --- UI construction -------------------------------------------------------------


func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = UI_LAYER
	add_child(layer)
	router = ScreenRouter.new()
	layer.add_child(router)
	reveals = RevealQueue.new(s, router, fsm, func() -> bool: return not attract and not _reviving)
	add_child(reveals)
	meta = MetaActions.new(s, router, runs, reveals)
	add_child(meta)
	menus = MenuNavigator.new(s, router, fsm, meta)
	menus.campaign_requested.connect(_play_campaign)
	menus.run_requested.connect(_start_run)
	menus.home_requested.connect(_show_main)
	toast = ToastView.new()
	layer.add_child(toast)
	s.bus.toast_requested.connect(toast.show_message)
	s.bus.network_state_changed.connect(
		func(online: bool) -> void:
			toast.show_message(Presenters.t("toast.back_online" if online else "toast.offline"), &"info")
	)
	hud = Hud.new()
	hud.bind(session)
	router.register(&"hud", hud)
	hud.pause_requested.connect(_pause)
	var main: MainMenu = MainMenu.new()
	router.register(&"main", main)
	main.play_requested.connect(func() -> void: _play_campaign(s.progression.next_level_to_play(), &"classic"))
	main.daily_requested.connect(menus.show_daily)
	main.modes_requested.connect(menus.show_modes)
	main.worlds_requested.connect(menus.show_campaign)
	main.tab_requested.connect(menus.show_tab)
	var worlds: WorldSelect = WorldSelect.new()
	router.register(&"worlds", worlds)
	worlds.world_selected.connect(menus.show_levels)
	worlds.back_requested.connect(_show_main)
	var levels: LevelSelect = LevelSelect.new()
	router.register(&"levels", levels)
	levels.level_selected.connect(menus.select_level)
	levels.back_requested.connect(menus.show_worlds)
	var modes: ModesScreen = ModesScreen.new()
	router.register(&"modes", modes)
	modes.mode_selected.connect(menus.select_mode)
	modes.back_requested.connect(_show_main)
	var daily: DailyScreen = DailyScreen.new()
	router.register(&"daily", daily)
	daily.play_requested.connect(
		func() -> void:
			if s.remote_config.get_bool("daily.enabled", true):
				_start_run(&"daily")
			else:
				toast.show_message(Presenters.t("toast.daily_paused"), &"info")
	)
	daily.claim_requested.connect(meta.claim_mission)
	daily.chest_requested.connect(meta.open_bonus_chest)
	daily.back_requested.connect(_show_main)
	var progress: ProgressScreen = ProgressScreen.new()
	router.register(&"progress", progress)
	progress.board_requested.connect(meta.load_board)
	progress.back_requested.connect(_show_main)
	for mode: StringName in [&"shop", &"collection"]:
		var cos: CosmeticsScreen = CosmeticsScreen.new()
		cos.mode = mode
		router.register(mode, cos)
		cos.buy_requested.connect(meta.buy)
		cos.equip_requested.connect(meta.equip)
		cos.pack_requested.connect(meta.buy_pack)
		cos.back_requested.connect(_show_main)
	var settings: SettingsScreen = SettingsScreen.new()
	router.register(&"settings", settings)
	settings.setting_changed.connect(func(key: String, value: Variant) -> void: s.settings.set_value(key, value))
	settings.restore_requested.connect(meta.restore_purchases)
	settings.cloud_sync_requested.connect(func() -> void: s.cloud.sync())
	s.cloud.status_changed.connect(
		func(_status: StringName) -> void: settings.set_cloud_status(Presenters.cloud_status(s))
	)
	settings.back_requested.connect(menus.close_settings)
	var pause: PauseOverlay = PauseOverlay.new()
	router.register(&"pause", pause)
	pause.resume_requested.connect(_resume)
	pause.restart_requested.connect(_restart)
	pause.settings_requested.connect(menus.open_settings_over_pause)
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
	complete.double_requested.connect(func() -> void: meta.double_reward(_last_outcome))
	complete.star_landed.connect(
		func(i: int) -> void:
			# Each star lands a step higher (the bank's pitch_step): a rising three-note cue.
			s.audio.play_sfx(&"star", i)
			s.haptics.play(&"reward", 0.7)
	)
	var reward: RewardOverlay = RewardOverlay.new()
	router.register(&"reward", reward)
	reward.continue_requested.connect(reveals.show_next)
	reward.item_landed.connect(
		func(_i: int) -> void:
			s.audio.play_sfx(&"coin")
			s.haptics.play(&"reward", 0.6)
	)
	router.back_unhandled.connect(_on_back_unhandled)


# --- Navigation ------------------------------------------------------------------


func _go(state: GameStateMachine.State) -> void:
	if fsm.current != state:
		fsm.transition_to(state)


func _show_main() -> void:
	_go(GameStateMachine.State.MAIN_MENU)
	router.show_screen(&"main", Presenters.main_menu(s))
	if not attract:
		_start_attract()
	# The next level's world track loads in the background while the menu shows.
	var next: Dictionary = WorldCatalog.parse_level_id(s.progression.next_level_to_play())
	s.audio.prefetch_music(str(s.catalog.world_at(int(next.get("world_index", 1))).get("id", "")))
	reveals.add_level_ups()
	reveals.show_pending()


## Android Back / Escape with no screen handler: pauses a run, leaves the app
## from the main menu (after saving), otherwise goes home.
func _on_back_unhandled() -> void:
	if fsm.current == GameStateMachine.State.PLAYING or fsm.current == GameStateMachine.State.COUNTDOWN:
		_pause()
	elif router.current_id == &"main":
		s.flush_now()
		get_tree().quit()


# --- Runs --------------------------------------------------------------------------


func _start_attract() -> void:
	attract = true
	var id: String = s.progression.next_level_to_play()
	var data: Dictionary = s.levels.load_level(id)
	if data.is_empty() or not session.load_level(data):
		return
	session.autopilot = RunController.solution_taps(data)
	_present_level(data)
	session.begin(ATTRACT_READY)
	s.audio.play_music("menu")


func _play_campaign(level_id: String, mode_id: StringName) -> void:
	if level_id.is_empty() or not s.progression.is_level_unlocked(level_id):
		return
	_start_run(mode_id, level_id)


func _start_run(mode_id: StringName, level_id: String = "") -> void:
	if not s.modes.is_unlocked(mode_id, s.mode_progress()):
		var req: Dictionary = s.modes.requirement(mode_id)
		toast.show_message(Presenters.t(str(req["key"])).format(req["args"] as Dictionary), &"lock")
		return
	attract = false
	session.autopilot = PackedInt32Array()
	if not runs.prepare(mode_id, level_id):
		s.bus.toast_requested.emit(Presenters.t("toast.run_unavailable"), &"info")
		_show_main()
		return
	if runs.streamer != null and fsm.can_transition(GameStateMachine.State.ENDLESS):
		# Streamed courses (endless, time attack) enter through ENDLESS: the
		# weekly course is primed there before the countdown.
		_go(GameStateMachine.State.ENDLESS)
	_go(GameStateMachine.State.COUNTDOWN)
	_present_level(session.level_data)
	router.clear_screen()
	router.show_screen(&"hud", Presenters.hud(session.level_data))
	session.begin(READY_FIRST)
	_go(GameStateMachine.State.PLAYING)
	_play_level_music(session.level_data)
	runs.track_start()


## The level's world track; bosses and mid-world challenges use the world's
## boss loop (a set piece sounds like one).
func _play_level_music(data: Dictionary) -> void:
	var world: Dictionary = s.catalog.world(str(data.get("world", "")))
	s.audio.set_combo(0)
	s.audio.play_music(str(world.get("id", "menu")), str(data.get("kind", "")) in ["boss", "challenge"])


func _present_level(data: Dictionary) -> void:
	# A run entering a different world passes through the veil (the attract run never does).
	view_sync.show_world(str(data.get("world", "neon_core")), not attract)
	view.setup_level()


func _restart() -> void:
	reveals.add_all(runs.commit_pending())
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
	s.audio.set_combo(0)
	view.reset_for_run(false)
	router.show_screen(&"hud", {})
	_go(GameStateMachine.State.COUNTDOWN)
	_go(GameStateMachine.State.PLAYING)
	s.bus.run_restarted.emit(str(runs.context.get("level_id", "")))


func _pause() -> void:
	# The READY beat counts too: a run must never start while nobody watches.
	var live: bool = session.phase == GameplaySession.Phase.RUNNING or session.phase == GameplaySession.Phase.READY
	if attract or session.paused or not live:
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
	reveals.add_all(runs.commit_pending())
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
	s.audio.set_combo(0)
	if result.completed and runs.advance_rush(result):
		# Boss rush continues straight into the next boss (and its music).
		_ending = false
		_present_level(session.level_data)
		_play_level_music(session.level_data)
		session.begin(READY_FIRST)
		return
	if result.completed:
		s.bus.run_completed.emit(result)
	else:
		s.bus.run_failed.emit(result)
	# While a revive is on offer nothing is applied yet: a revived run is applied
	# once when it ends, otherwise this one is applied on leaving.
	_last_outcome = runs.conclude(result)
	await get_tree().create_timer(RESULT_DELAY).timeout
	_ending = false
	# The result card owns the screen: the HUD steps away underneath it.
	router.clear_screen()
	reveals.add_all(_last_outcome.get("reveals", []) as Array)
	var card: Dictionary = Presenters.result_card(s, result, _last_outcome, session.mode_id)
	if result.completed:
		s.audio.play_stinger(&"perfect_fanfare" if result.perfect else &"level_complete")
		_go(GameStateMachine.State.COMPLETE)
		router.push_overlay(&"complete", card)
		if s.ads.can_show_interstitial(&"level_end"):
			await s.ads.show_interstitial(&"level_end")
	else:
		_go(GameStateMachine.State.FAILED)
		router.push_overlay(&"fail", card)
	# Reveals celebrate on the result of a cleared run (or wait for the menu):
	# nothing ever covers PLAY AGAIN after a fail.
	reveals.after_result(result.completed)


func _next_level() -> void:
	var next_id: String = str(_last_outcome.get("next_level_id", ""))
	router.close_overlays()
	if next_id.is_empty():
		_show_main()
		return
	_play_campaign(next_id, runs.context.get("mode", &"classic") as StringName)


func _revive() -> void:
	if runs.pending == null:
		return
	_reviving = true
	var shown: Dictionary = await s.ads.show_rewarded(&"revive")
	_reviving = false
	if not bool(shown.get("granted", false)):
		return
	if session.revive():
		view.on_revive()
		# The run continues; it is applied once, cumulatively, when it ends.
		runs.pending = null
		reveals.clear()
		router.close_overlays()
		router.show_screen(&"hud", {})
		fsm.transition_to(GameStateMachine.State.PLAYING)


## The app is going to the background or closing while the fail card still
## offers a revive: the run is applied now (the OS may kill the app), and the
## revive offer is withdrawn. Not while the revive ad itself is showing.
func _commit_on_leave() -> void:
	if runs == null or runs.pending == null or _reviving:
		return
	reveals.add_all(runs.commit_pending())
	var fail: FailOverlay = router.screen(&"fail") as FailOverlay if router != null else null
	if fail != null:
		fail.disable_revive()
	s.flush_now()


# --- Engine callbacks ----------------------------------------------------------------


func _on_feedback(kind: StringName, strength: float, pitch_step: int) -> void:
	if attract:
		return
	s.audio.on_feedback(kind, strength, pitch_step)
	s.haptics.on_feedback(kind, strength, pitch_step)
	# The intensity stem follows the live combo: it drops on a break, a hit
	# or a miss, not only rises on combo steps.
	s.audio.set_combo(session.sim.combo)
	if kind == &"combo":
		s.bus.combo_reached.emit(pitch_step)


func _process(delta: float) -> void:
	if attract:
		return
	if session.is_running():
		if runs.pump():
			view.on_stream_appended()
		if s.quality.feed_frame(delta):
			view_sync.apply_quality()
	if session.phase == GameplaySession.Phase.READY or session.phase == GameplaySession.Phase.RUNNING:
		# The level's beat grid starts at sim time 0: the loop is held through the
		# READY beat and pause and follows the run while it plays (REQ-224).
		s.audio.sync_run(session.interpolated_time(), session.is_running(), session.clock_scale)


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
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_commit_on_leave()
