class_name GameFlow
extends Node
## App root (main scene). Owns the persistent gameplay session + view (restarts
## never reload scenes), the UI router and the application state machine, and
## routes every screen intent to the systems. Screens are dumb views; payloads
## come from [Presenters]; run bookkeeping lives in [RunController].

const RESULT_DELAY: float = 0.55
const REVEAL_DELAY_COMPLETE: float = 2.2
const READY_FIRST: float = 0.8
const READY_RESTART: float = 0.35
const ATTRACT_READY: float = 0.2
const WORLD_FADE: float = 0.6

## The service graph; the autoload unless one is injected before _ready (tests).
var s: AppServices
var session: GameplaySession
var view: GameplayView
var runs: RunController
var router: ScreenRouter
var fsm: GameStateMachine = GameStateMachine.new()
var hud: Hud
var toast: ToastView
var attract: bool = true

var _pick_mode: StringName = &""
var _world_id: String = ""
var _reveals: Array = []
var _last_outcome: Dictionary = {}
var _settings_return: StringName = &""
var _restore_status: String = ""
var _ending: bool = false
var _uncommitted: RunResult = null
## A rewarded revive ad is showing (reveals wait; the pending run stays open).
var _reviving: bool = false
var _veil: ColorRect
var _veil_tween: Tween
var _shown_world: String = ""
var _reveal_return: GameStateMachine.State = GameStateMachine.State.MAIN_MENU


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
	s.bus.locale_changed.connect(func(_l: String) -> void: _relocalize_ui.call_deferred())
	# The track breathes with the music: a stronger pulse on each bar's downbeat.
	s.audio.beat.connect(func(i: int) -> void: view.music_beat(1.0 if i % 4 == 0 else 0.45))
	_apply_cosmetics()
	_apply_quality()
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
	# World transition veil: between the 3D view and the UI.
	var veil_layer: CanvasLayer = CanvasLayer.new()
	veil_layer.layer = 5
	add_child(veil_layer)
	_veil = ColorRect.new()
	_veil.color = Palette.INK
	_veil.modulate.a = 0.0
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil_layer.add_child(_veil)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	router = ScreenRouter.new()
	layer.add_child(router)
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
	complete.star_landed.connect(
		func(_i: int) -> void:
			s.audio.play_sfx(&"star")
			s.haptics.play(&"reward", 0.7)
	)
	var reward: RewardOverlay = RewardOverlay.new()
	router.register(&"reward", reward)
	reward.continue_requested.connect(_next_reveal)
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
	_reveals.append_array(s.take_level_up_reveals())
	if not _reveals.is_empty():
		_next_reveal()


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
	var daily_status: Dictionary = s.daily.status()
	s.analytics.track(
		&"daily_started",
		{"date_key": str(daily_status.get("date_key", "")), "streak": int(daily_status.get("streak", 0))}
	)


func _on_tab(tab: StringName) -> void:
	match tab:
		&"progress":
			_go(GameStateMachine.State.PROGRESS)
			router.show_screen(&"progress", Presenters.progress(s, "overview", {}))
			_load_board(Presenters.board_ids(s)[0])
		&"shop":
			_go(GameStateMachine.State.SHOP)
			router.show_screen(&"shop", Presenters.cosmetics(s, &"shop"))
			s.analytics.track(&"shop_opened", {"source": "menu", "tab": "shop"})
		&"collection":
			_go(GameStateMachine.State.COLLECTION)
			router.show_screen(&"collection", Presenters.cosmetics(s, &"collection"))
		&"settings":
			_settings_return = &""
			_go(GameStateMachine.State.SETTINGS)
			router.show_screen(&"settings", Presenters.settings(s, _restore_status))


## The language changed (from Settings): every screen is rebuilt in the new
## language on its next show, and Settings itself is rebuilt in place.
func _relocalize_ui() -> void:
	router.relocalize()
	if router.top_id() != &"settings":
		return
	if _settings_return == &"pause":
		router.push_overlay(&"settings", Presenters.settings(s, _restore_status))
	else:
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
		var req: Dictionary = s.modes.requirement(mode_id)
		toast.show_message(Presenters.t(str(req["key"])).format(req["args"] as Dictionary), &"lock")
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
	_play_level_music(session.level_data)
	(
		s
		. analytics
		. track(
			&"level_started",
			{
				"level_id": str(runs.context.get("level_id", "")),
				"world_id": str(runs.context.get("world_id", "")),
				"mode": String(mode_id),
			}
		)
	)


## The level's world track; bosses and mid-world challenges use the world's
## boss loop (a set piece sounds like one).
func _play_level_music(data: Dictionary) -> void:
	var world: Dictionary = s.catalog.world(str(data.get("world", "")))
	s.audio.set_combo(0)
	s.audio.play_music(str(world.get("id", "menu")), str(data.get("kind", "")) in ["boss", "challenge"])


func _present_level(data: Dictionary) -> void:
	var world_id: String = str(data.get("world", "neon_core"))
	if not attract and not _shown_world.is_empty() and world_id != _shown_world:
		_world_transition()
	_shown_world = world_id
	view.apply_world(WorldTheme.from_world(s.catalog.world(world_id)))
	_apply_cosmetics()
	view.setup_level()


## Entering a different world: the old one is gone behind ink, and the new
## one rises out of it (calm, ART_DIRECTION §8; shorter with reduce motion).
func _world_transition() -> void:
	if _veil_tween != null:
		_veil_tween.kill()
	_veil.modulate.a = 1.0
	_veil_tween = create_tween()
	var seconds: float = WORLD_FADE * (0.4 if router.reduce_motion else 1.0)
	_veil_tween.tween_property(_veil, "modulate:a", 0.0, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)


func _restart() -> void:
	_commit_pending()
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


## Android Back / Escape with no screen handler: pauses a run, leaves the app
## from the main menu (after saving), otherwise goes home.
func _on_back_unhandled() -> void:
	if fsm.current == GameStateMachine.State.PLAYING or fsm.current == GameStateMachine.State.COUNTDOWN:
		_pause()
	elif router.current_id == &"main":
		s.flush_now()
		get_tree().quit()


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
	_commit_pending()
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
	if runs.can_offer_revive(result):
		# Nothing is applied yet: if the player revives, the continued run is
		# applied once when it ends; otherwise it is applied on leaving.
		_last_outcome = runs.preview(result)
		_uncommitted = result
	else:
		_last_outcome = runs.finish(result)
	await get_tree().create_timer(RESULT_DELAY).timeout
	_ending = false
	# The result card owns the screen: the HUD steps away underneath it.
	router.clear_screen()
	_reveals.append_array(_last_outcome.get("reveals", []) as Array)
	if result.completed:
		s.audio.play_stinger(&"perfect_fanfare" if result.perfect else &"level_complete")
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
	# Reveals celebrate on the result of a cleared run (or wait for the menu):
	# nothing ever covers PLAY AGAIN after a fail.
	if not _reveals.is_empty() and result.completed:
		_schedule_reveals(REVEAL_DELAY_COMPLETE)


## Reveals wait until the result sequence (stars, count-up) has played; if the
## player moves on first they stay queued for the next calm moment (menu).
func _schedule_reveals(delay: float) -> void:
	var host: StringName = router.top_id()
	await get_tree().create_timer(delay).timeout
	# Never over a pending revive: the revived run must return to PLAYING.
	if router.top_id() == host and not attract and not _reviving:
		_next_reveal()


## Shows queued reveals (level-up, unlocks, achievements) one at a time on top
## of the result screen; the result screen stays underneath. When the last one
## closes, the state machine returns to the state it came from.
func _next_reveal() -> void:
	router.close_overlay(&"reward")
	if _reveals.is_empty():
		if fsm.current == GameStateMachine.State.REWARD and _reveal_return != GameStateMachine.State.REWARD:
			fsm.transition_to(_reveal_return)
		return
	var r: Dictionary = _reveals.pop_front() as Dictionary
	if fsm.current != GameStateMachine.State.REWARD:
		_reveal_return = fsm.current
	_go(GameStateMachine.State.REWARD)
	router.push_overlay(&"reward", r)


## Applies a failed run that was held back for a possible revive.
func _commit_pending() -> void:
	if _uncommitted == null:
		return
	var result: RunResult = _uncommitted
	_uncommitted = null
	var outcome: Dictionary = runs.finish(result)
	_reveals.append_array(outcome.get("reveals", []) as Array)


func _next_level() -> void:
	var next_id: String = str(_last_outcome.get("next_level_id", ""))
	router.close_overlays()
	if next_id.is_empty():
		_show_main()
		return
	_play_campaign(next_id, runs.context.get("mode", &"classic") as StringName)


func _revive() -> void:
	if _uncommitted == null:
		return
	_reviving = true
	var shown: Dictionary = await s.ads.show_rewarded(&"revive")
	_reviving = false
	if not bool(shown.get("granted", false)):
		return
	if session.revive():
		view.on_revive()
		# The run continues; it is applied once, cumulatively, when it ends.
		_uncommitted = null
		_reveals.clear()
		router.close_overlays()
		router.show_screen(&"hud", {})
		fsm.transition_to(GameStateMachine.State.PLAYING)


func _double_reward() -> void:
	var bundle: RewardBundle = _last_outcome.get("reward") as RewardBundle
	if bundle == null or bool(_last_outcome.get("doubled", false)):
		return
	# One optional double per result: the button goes away before the ad runs.
	_last_outcome["doubled"] = true
	_last_outcome["can_double"] = false
	(router.screen(&"complete") as CompleteOverlay).disable_double()
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
	s.analytics.track(&"mission_claimed", {"mission_id": mission_id})
	_reveals.append_array(s.take_level_up_reveals())
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
		s.achievements.evaluate()
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
	# The intensity stem follows the live combo: it drops on a break, a hit
	# or a miss, not only rises on combo steps.
	s.audio.set_combo(session.sim.combo)
	if kind == &"combo":
		s.bus.combo_reached.emit(pitch_step)


func _apply_cosmetics() -> void:
	view.apply_cosmetics(s.cosmetics.core_skin_params(), s.cosmetics.trail_params())
	# Default items keep the art direction's own palette (no override).
	view.apply_effect_cosmetics(
		Presenters.worn(s, CosmeticCatalog.PARTICLE),
		Presenters.worn(s, CosmeticCatalog.EFFECT),
		Presenters.worn(s, CosmeticCatalog.BACKGROUND)
	)
	if UiTheme.apply_accent(Presenters.worn(s, CosmeticCatalog.THEME)):
		# Buttons keep copies of the theme's boxes: rebuild screens on next show.
		router.relocalize()


func _apply_quality() -> void:
	var p: Dictionary = s.quality.params()
	view.set_quality(
		bool(p.get("post_fx", true)),
		float(p.get("particle_scale", 1.0)),
		int(p.get("trail_points", 18)),
		bool(p.get("dynamic_light", true)),
		bool(p.get("shadows", true)),
		bool(p.get("glow", true)),
		bool(p.get("ambient_particles", true))
	)


func _apply_settings_to_view() -> void:
	var reduce: bool = s.settings.get_bool("reduce_motion")
	router.reduce_motion = reduce
	view.reduce_motion = reduce
	view.core_view.reduce_motion = reduce
	view.set_colorblind(s.settings.get_bool("colorblind"))
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
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_commit_on_leave()


## The app is going to the background or closing while the fail card still
## offers a revive: the run is applied now (the OS may kill the app), and the
## revive offer is withdrawn. Not while the revive ad itself is showing.
func _commit_on_leave() -> void:
	if _uncommitted == null or _reviving or s == null:
		return
	_commit_pending()
	var fail: FailOverlay = router.screen(&"fail") as FailOverlay if router != null else null
	if fail != null:
		fail.disable_revive()
	s.flush_now()
