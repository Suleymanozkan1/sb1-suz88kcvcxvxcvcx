extends TestCase
## The app root's collaborators on the real main scene: the reveal queue, the
## meta screens' actions, menu navigation and the world veil.

const FIXED_UNIX: int = 1790000000
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## A world-1 level a fresh profile has not unlocked (picking it starts nothing).
const LOCKED_LEVEL: String = "w01_l09"


class WatchedAds:
	extends AdProvider

	func is_available(_kind: StringName) -> bool:
		return true

	func show(_kind: StringName, _placement: StringName) -> Dictionary:
		return {"shown": true, "completed": true}


var _app: AppServices
var _flow: GameFlow


func before_each() -> void:
	_app = AppServices.new()
	_app.auto_boot = false
	tree.root.add_child(_app)
	var clock: GameClock = GameClock.new()
	clock.set_fixed_unix(FIXED_UNIX)
	_app.boot(MemorySaveStorage.new(), clock)
	_flow = MAIN_SCENE.instantiate() as GameFlow
	_flow.s = _app
	tree.root.add_child(_flow)
	await wait_frames(3)


func after_each() -> void:
	_flow.queue_free()
	_app.queue_free()
	await wait_frames(2)


static func _reveal(title: String) -> Dictionary:
	return {"eyebrow": "x", "title": title, "subtitle": "", "bundle": null}


func test_reveals_return_to_the_screen_they_covered() -> void:
	_flow.menus.show_modes()
	_flow.reveals.add(_reveal("one"))
	_flow.reveals.add(_reveal("two"))
	_flow.reveals.show_next()
	assert_eq(_flow.fsm.current, GameStateMachine.State.REWARD)
	assert_eq(_flow.router.top_id(), &"reward", "shown over the screen")
	assert_eq(_flow.router.current_id, &"modes", "the screen stays underneath")
	_flow.reveals.show_next()
	assert_eq(_flow.fsm.current, GameStateMachine.State.REWARD, "one reveal after another")
	_flow.reveals.show_next()
	assert_true(_flow.reveals.is_empty())
	assert_false(_flow.router.has_overlay(&"reward"), "the last one closes")
	assert_eq(_flow.fsm.current, GameStateMachine.State.MODES, "back to the state the first one covered")
	_flow.reveals.show_pending()
	assert_false(_flow.router.has_overlay(&"reward"), "nothing waiting: nothing shown")


func test_reveals_after_a_fail_wait_for_the_menu() -> void:
	_flow.reveals.add(_reveal("waits"))
	_flow.reveals.after_result(false)
	await wait_frames(2)
	assert_false(_flow.router.has_overlay(&"reward"), "not after a fail")
	assert_eq(_flow.reveals.pending().size(), 1)
	_flow.menus.show_modes()
	_flow._show_main()
	assert_eq(_flow.router.top_id(), &"reward", "the menu is a calm moment")


func test_double_reward_is_granted_once_per_result() -> void:
	_app.ads._provider = WatchedAds.new()
	var result: RunResult = RunResult.new()
	result.completed = true
	result.score = 900
	var bundle: RewardBundle = RewardBundle.new("run").add(&"coins", 40)
	var outcome: Dictionary = {"result": result, "reward": bundle, "can_double": true}
	_flow.router.push_overlay(&"complete", Presenters.result_card(_app, result, outcome, &"classic"))
	var extra: int = _app.rewards.double_for_ad(bundle).amount_of(&"coins")
	var coins: int = _app.economy.balance(EconomyService.COINS)
	await _flow.meta.double_reward(outcome)
	await _flow.meta.double_reward(outcome)
	assert_gt(float(extra), 0.0, "the double pays coins")
	assert_eq(_app.economy.balance(EconomyService.COINS), coins + extra, "paid exactly once")
	assert_true(bool(outcome["doubled"]) and not bool(outcome["can_double"]), "the result is marked")
	assert_eq(_flow.router.top_id(), &"reward", "the extra is revealed")


func test_settings_closes_back_to_where_it_opened() -> void:
	_flow.menus.show_tab(&"settings")
	assert_eq(_flow.fsm.current, GameStateMachine.State.SETTINGS)
	_flow.menus.close_settings()
	assert_eq(_flow.router.current_id, &"main", "from the menu: home")
	assert_eq(_flow.fsm.current, GameStateMachine.State.MAIN_MENU)
	_flow._start_run(&"classic", "w01_l01")
	_flow._pause()
	_flow.menus.open_settings_over_pause()
	assert_eq(_flow.router.top_id(), &"settings", "over the pause card")
	_flow.menus.close_settings()
	assert_eq(_flow.router.top_id(), &"pause", "back to the paused run")
	assert_eq(_flow.fsm.current, GameStateMachine.State.PAUSED)


func test_mode_picks_choose_the_campaign_rules() -> void:
	var picks: Array = []
	_flow.menus.campaign_requested.connect(
		func(level_id: String, mode_id: StringName) -> void: picks.append([level_id, mode_id])
	)
	_flow.menus.select_mode(&"hard")
	assert_eq(_flow.fsm.current, GameStateMachine.State.WORLD_SELECT, "a picked mode starts on the world map")
	_flow.menus.select_level(LOCKED_LEVEL)
	assert_eq(picks.back(), [LOCKED_LEVEL, &"hard"], "played with the picked mode's rules")
	_flow.menus.show_campaign()
	_flow.menus.select_level(LOCKED_LEVEL)
	assert_eq(picks.back(), [LOCKED_LEVEL, &"classic"], "a plain campaign pick is CLASSIC")
	assert_true(_flow.attract, "a locked level starts no run")


func test_a_run_in_another_world_rises_out_of_the_veil() -> void:
	var veil: ColorRect = _flow.view_sync._veil
	assert_near(veil.modulate.a, 0.0, 0.0001, "the attract run is never veiled")
	var other: String = str(_app.catalog.world_at(2).get("id", ""))
	_flow.view_sync.show_world(other, false)
	assert_near(veil.modulate.a, 0.0, 0.0001, "not veiled when asked not to")
	_flow.view_sync.show_world(str(_app.catalog.world_at(1).get("id", "")), true)
	assert_near(veil.modulate.a, 1.0, 0.0001, "a different world starts behind ink")
	await tree.create_timer(ViewSync.WORLD_FADE + 0.2).timeout
	assert_near(veil.modulate.a, 0.0, 0.0001, "and rises out of it")
