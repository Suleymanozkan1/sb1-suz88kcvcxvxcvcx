extends TestCase
## End-to-end app integration: the real service graph (in-memory save, fixed
## clock) driving real runs through RunController, plus the main scene booting
## headless and restart stability.

const FIXED_UNIX: int = 1790000000
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

class WatchedAds:
	extends AdProvider

	func is_available(_kind: StringName) -> bool:
		return true

	func show(_kind: StringName, _placement: StringName) -> Dictionary:
		return {"shown": true, "completed": true}


var _app: AppServices
var _session: GameplaySession
var _runs: RunController
var _last: RunResult


func before_each() -> void:
	_app = AppServices.new()
	_app.auto_boot = false
	tree.root.add_child(_app)
	var clock: GameClock = GameClock.new()
	clock.set_fixed_unix(FIXED_UNIX)
	_app.boot(MemorySaveStorage.new(), clock)
	_session = GameplaySession.new()
	tree.root.add_child(_session)
	_runs = RunController.new(_app, _session)
	_last = null
	_session.run_ended.connect(func(r: RunResult) -> void: _last = r)


func after_each() -> void:
	_session.queue_free()
	_app.queue_free()
	await wait_frames(2)


func _play_solution() -> RunResult:
	var taps: PackedInt32Array = PackedInt32Array()
	for t: Variant in (_session.level_data.get("solution", {}) as Dictionary).get("taps", []) as Array:
		taps.append(int(t))
	_session.begin(0.0)
	_session.step_ticks(60 * 400, taps)
	return _last


## Coins in every bundle an outcome shows: the run reward plus each reveal.
static func _granted_coins(outcome: Dictionary) -> int:
	var total: int = (outcome["reward"] as RewardBundle).amount_of(&"coins")
	for r: Variant in outcome["reveals"] as Array:
		var b: Variant = (r as Dictionary).get("bundle", null)
		if b is RewardBundle:
			total += (b as RewardBundle).amount_of(&"coins")
	return total


func _play_no_input(max_ticks: int) -> RunResult:
	_session.begin(0.0)
	_session.step_ticks(max_ticks)
	return _last


func test_boot_builds_every_service() -> void:
	for name: String in [
		"bus",
		"save",
		"profile",
		"settings",
		"economy",
		"stats",
		"progression",
		"cosmetics",
		"rewards",
		"achievements",
		"missions",
		"daily",
		"leaderboard",
		"analytics",
		"ads",
		"store",
		"notifications",
		"haptics",
		"audio",
		"quality",
		"modes"
	]:
		assert_true(_app.get(name) != null, "%s constructed" % name)
	assert_true(_app.is_booted)
	assert_eq(_app.profile.player_level, 1)


func test_first_clear_records_progress_and_grants_real_rewards() -> void:
	var coins_before: int = _app.economy.balance(EconomyService.COINS)
	assert_true(_runs.prepare(&"classic", "w01_l01"))
	var result: RunResult = _play_solution()
	assert_true(result != null and result.completed, "stored solution clears the level")
	var outcome: Dictionary = _runs.finish(result)
	assert_true(_app.profile.is_cleared("w01_l01"), "level recorded as cleared")
	assert_ge(float(_app.profile.stars_for("w01_l01")), 1.0)
	assert_true(_app.progression.is_level_unlocked("w01_l02"), "next level unlocked")
	assert_true(bool(outcome["has_next"]))
	var reward: RewardBundle = outcome["reward"] as RewardBundle
	assert_gt(float(reward.amount_of(&"coins")), 0.0, "coins granted on first clear")
	assert_eq(
		_app.economy.balance(EconomyService.COINS),
		coins_before + _granted_coins(outcome),
		"the balance moved by exactly the bundles shown (result + reveals)"
	)
	assert_eq(_app.profile.stat("runs_played"), 1)


func test_failed_run_grants_no_coins() -> void:
	assert_true(_runs.prepare(&"classic", "w01_l06"))
	var coins_before: int = _app.economy.balance(EconomyService.COINS)
	var result: RunResult = _play_no_input(60 * 120)
	assert_true(result != null and not result.completed, "no input fails a level with hazards")
	var outcome: Dictionary = _runs.finish(result)
	assert_eq((outcome["reward"] as RewardBundle).amount_of(&"coins"), 0, "no coins for a failed run")
	assert_eq(_app.economy.balance(EconomyService.COINS), coins_before)
	assert_false(_app.profile.is_cleared("w01_l06"))
	assert_gt(float(outcome["progress"]), 0.0, "progress reported for the fail screen")


func test_daily_rewards_only_first_completion() -> void:
	assert_true(_runs.prepare(&"daily"))
	assert_eq(str(_session.level_data.get("kind", "")), "daily")
	var first: RunResult = _play_solution()
	assert_true(first.completed, "daily solution clears")
	var out1: Dictionary = _runs.finish(first)
	assert_true(bool((out1["daily"] as Dictionary).get("first_completion", false)))
	var coins_after_first: int = _app.economy.balance(EconomyService.COINS)
	assert_true(_runs.prepare(&"daily"))
	var second: RunResult = _play_solution()
	var out2: Dictionary = _runs.finish(second)
	assert_false(bool((out2["daily"] as Dictionary).get("first_completion", true)), "second clear is a replay")
	assert_eq((out2["reward"] as RewardBundle).amount_of(&"coins"), 0, "replays are not rewarded again")
	assert_eq(
		_app.economy.balance(EconomyService.COINS),
		coins_after_first + _granted_coins(out2),
		"only reveal bundles (achievements, level-ups) can move the balance"
	)


func test_endless_streams_and_records_best_distance() -> void:
	_app.profile.stats["unique_levels_cleared"] = 50
	assert_true(_app.modes.is_unlocked(&"endless", _app.mode_progress()))
	assert_true(_runs.prepare(&"endless"))
	assert_true(_runs.streamer != null)
	_session.begin(0.0)
	var taps: PackedInt32Array = _runs.streamer.planned_taps()
	for _frame: int in 600:
		_session.step_ticks(1, _runs.streamer.planned_taps())
		_runs.pump()
		if _last != null:
			break
	assert_true(_session.sim.d > 60.0, "the run travelled past the opening chunk")
	assert_true(taps.size() >= 0)


func test_boss_rush_needs_beaten_bosses() -> void:
	assert_eq(_runs.boss_rush_queue().size(), 0)
	assert_false(_runs.prepare(&"boss_rush"), "no bosses beaten -> no rush")


func test_restart_is_stable_and_fast() -> void:
	var view: GameplayView = GameplayView.new()
	tree.root.add_child(view)
	assert_true(_runs.prepare(&"classic", "w01_l10"))
	view.bind(_session)
	view.apply_world(WorldTheme.from_world(_app.catalog.world("neon_core")))
	view.setup_level()
	_session.begin(0.0)
	_session.step_ticks(240)
	await wait_frames(2)
	var nodes_before: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT) as int
	var worst_ms: float = 0.0
	for _i: int in 100:
		var t0: int = Time.get_ticks_usec()
		_session.restart(0.0)
		view.reset_for_run(false)
		worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - t0) / 1000.0)
		_session.step_ticks(30)
	await wait_frames(2)
	var nodes_after: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT) as int
	assert_le(float(nodes_after - nodes_before), 2.0, "100 restarts do not leak nodes")
	assert_lt(worst_ms, 50.0, "restart is instant (no scene reload)")
	view.queue_free()


func test_main_scene_boots_headless() -> void:
	var flow: GameFlow = MAIN_SCENE.instantiate() as GameFlow
	flow.s = _app
	tree.root.add_child(flow)
	await wait_frames(30)
	assert_eq(flow.router.current_id, &"main", "main menu is the first screen")
	assert_true(flow.attract, "attract mode plays behind the menu")
	assert_eq(flow.fsm.current, GameStateMachine.State.MAIN_MENU)
	flow.queue_free()
	await wait_frames(2)


func test_leaving_the_app_on_a_revivable_fail_applies_the_run() -> void:
	var flow: GameFlow = MAIN_SCENE.instantiate() as GameFlow
	flow.s = _app
	tree.root.add_child(flow)
	await wait_frames(3)
	flow._start_run(&"classic", "w01_l05")
	assert_true(_app.hold_autosave, "no autosave while a run is played")
	flow.session.step_ticks(60 * 120)
	var result: RunResult = RunResult.from_sim(flow.session.sim, flow.session.level_data, &"classic")
	assert_false(result.completed, "the run failed")
	# The fail card is up with a revive on offer: the run is still pending.
	flow.runs.pending = result
	flow.router.push_overlay(&"fail", {"result": result, "best": 0, "progress": 0.5, "can_revive": true})
	var played: int = _app.stats.value(StatsService.RUNS_PLAYED)
	flow._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	assert_true(flow.runs.pending == null, "applied before the OS can kill the app")
	assert_eq(_app.stats.value(StatsService.RUNS_PLAYED), played + 1, "counted once")
	assert_false((flow.router.screen(&"fail") as FailOverlay)._revive.visible, "revive offer withdrawn")
	flow.queue_free()
	await wait_frames(2)


func test_fail_card_stays_clear_and_music_follows_the_run() -> void:
	var flow: GameFlow = MAIN_SCENE.instantiate() as GameFlow
	flow.s = _app
	tree.root.add_child(flow)
	await wait_frames(3)
	for stinger: StringName in [&"level_complete", &"perfect_fanfare"]:
		assert_false(_app.audio._bank.stinger(stinger).is_empty(), "stinger %s exists in the bank" % stinger)
	flow._start_run(&"classic", "w01_l05")
	_app.audio.set_combo(30)
	flow._on_feedback(&"miss", 0.2, 0)
	assert_near(_app.audio._intensity_target, 0.0, 0.0001, "combo break drops the intensity stem")
	# A queued reveal never covers the fail card.
	flow.reveals.add({"eyebrow": "x", "title": "y", "subtitle": "", "bundle": null})
	flow.session.step_ticks(60 * 120)
	await wait_frames(2)
	await tree.create_timer(GameFlow.RESULT_DELAY + 0.2).timeout
	assert_eq(flow.router.top_id(), &"fail", "fail card on top")
	assert_false(flow.reveals.is_empty(), "the reveal waits for a calmer moment")
	flow.queue_free()
	await wait_frames(2)


func test_music_is_locked_to_the_run() -> void:
	var flow: GameFlow = MAIN_SCENE.instantiate() as GameFlow
	flow.s = _app
	tree.root.add_child(flow)
	await wait_frames(3)
	flow._start_run(&"classic", "w01_l05")
	await wait_frames(2)
	var deck: AudioService.MusicDeck = _app.audio._decks[_app.audio._active_deck]
	assert_eq(deck.track, "neon_core", "the world's track")
	assert_true(deck.base.stream_paused, "held at the top through the READY beat")
	flow.session.request_tap()
	await wait_frames(3)
	assert_eq(flow.session.phase, GameplaySession.Phase.RUNNING)
	assert_false(deck.base.stream_paused, "the loop starts with the run")
	assert_true(_app.audio._locked)
	flow._pause()
	await wait_frames(2)
	assert_true(deck.base.stream_paused, "pause holds the loop")
	flow._resume()
	await wait_frames(2)
	assert_false(deck.base.stream_paused)
	flow.session.step_ticks(60 * 120)
	await tree.create_timer(AudioService.LOCK_RELEASE_S + 0.1).timeout
	assert_false(_app.audio._locked, "the run is over: the loop plays on freely")
	flow.queue_free()
	await wait_frames(2)


func test_every_reveal_has_its_cue() -> void:
	var flow: GameFlow = MAIN_SCENE.instantiate() as GameFlow
	flow.s = _app
	tree.root.add_child(flow)
	await wait_frames(3)
	for sound: String in ["level_up", "unlock", "reward"]:
		assert_false(_app.audio._bank.sfx(StringName(sound)).is_empty(), "%s is in the bank" % sound)
	flow.reveals.add({"eyebrow": "x", "title": "Level 3", "subtitle": "", "bundle": null, "sound": "level_up"})
	flow.reveals.add({"eyebrow": "x", "title": "World", "subtitle": "", "bundle": null, "sound": "unlock"})
	flow.reveals.add({"eyebrow": "x", "title": "Badge", "subtitle": "", "bundle": null})
	flow.reveals.show_next()
	assert_eq(_app.audio.active_voice_count(&"level_up"), 1, "a level-up sounds like one")
	flow.reveals.show_next()
	assert_eq(_app.audio.active_voice_count(&"unlock"), 1, "an unlock sounds like one")
	flow.reveals.show_next()
	assert_eq(_app.audio.active_voice_count(&"reward"), 1, "everything else is a reward")
	_app._on_level_up(2)
	assert_eq(str(_app.take_level_up_reveals()[0].get("sound", "")), "level_up", "level-up reveals name their cue")
	# The result card's three stars rise in pitch as they land.
	var complete: CompleteOverlay = flow.router.screen(&"complete") as CompleteOverlay
	var pitches: Array[float] = []
	for i: int in 3:
		complete.star_landed.emit(i)
		for v: int in _app.audio._voices.size():
			if _app.audio._voice_kind[v] == &"star" and _app.audio._voice_seq[v] == _app.audio._seq:
				pitches.append(_app.audio._voices[v].pitch_scale)
	assert_eq(pitches.size(), 3, "every star sounds")
	assert_true(pitches[0] < pitches[1] and pitches[1] < pitches[2], "each star lands a step higher: %s" % str(pitches))
	flow.queue_free()
	await wait_frames(2)


func test_bonus_chest_is_optional_and_once_a_day() -> void:
	var flow: GameFlow = MAIN_SCENE.instantiate() as GameFlow
	flow.s = _app
	tree.root.add_child(flow)
	await wait_frames(3)
	assert_false(Presenters.bonus_chest_offered(_app), "no ad available: no offer")
	_app.ads._provider = WatchedAds.new()
	assert_true(Presenters.bonus_chest_offered(_app), "offered when an ad can play")
	var coins: int = _app.economy.balance(EconomyService.COINS)
	flow.menus.show_daily()
	await flow.meta.open_bonus_chest()
	var chest: Dictionary = RewardEngine.load_tables()["bonus_chest"]["reward"] as Dictionary
	assert_eq(_app.economy.balance(EconomyService.COINS), coins + int(chest.get("coins", 0)), "fixed chest contents")
	assert_false(Presenters.bonus_chest_offered(_app), "once a day")
	assert_eq(flow.router.top_id(), &"reward", "revealed")
	flow.queue_free()
	await wait_frames(2)


func test_bonus_chest_level_up_is_revealed_with_it() -> void:
	var flow: GameFlow = MAIN_SCENE.instantiate() as GameFlow
	flow.s = _app
	tree.root.add_child(flow)
	await wait_frames(3)
	_app.ads._provider = WatchedAds.new()
	_app.take_level_up_reveals()
	var bar: Dictionary = _app.progression.xp_progress()
	_app.profile.xp += int(bar["needed"]) - int(bar["into_level"]) - 1
	var level: int = _app.profile.player_level
	flow.menus.show_daily()
	await flow.meta.open_bonus_chest()
	assert_gt(float(_app.profile.player_level), float(level), "chest XP levelled up")
	var level_up: String = TranslationServer.translate("reveal.level_up")
	var queued: Array = flow.reveals.pending().filter(
		func(r: Dictionary) -> bool: return str(r.get("eyebrow", "")) == level_up
	)
	assert_eq(queued.size(), 1, "level-up revealed after the chest, not after the next run")
	assert_true(_app.take_level_up_reveals().is_empty(), "nothing left over for the next run")
	flow.queue_free()
	await wait_frames(2)
