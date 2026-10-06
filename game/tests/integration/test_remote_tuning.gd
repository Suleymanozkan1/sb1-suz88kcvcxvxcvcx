extends TestCase
## Remote config keys that tune a live game: coin and daily multipliers, the
## weekend event bonus and the daily-challenge switch, applied by AppServices
## and mirrored by the server's reward-claim bounds.

const SATURDAY_UNIX: int = 1790380800  # 2026-09-26 (UTC), a Saturday
const MONDAY_UNIX: int = 1790553600  # 2026-09-28 (UTC)

var _app: AppServices


func _boot(unix: int) -> void:
	_app = AppServices.new()
	_app.auto_boot = false
	tree.root.add_child(_app)
	var clock: GameClock = GameClock.new()
	clock.set_fixed_unix(unix)
	_app.boot(MemorySaveStorage.new(), clock)


func after_each() -> void:
	if _app != null:
		_app.queue_free()
	await wait_frames(2)


func test_coin_and_daily_multipliers_reach_the_reward_engine() -> void:
	_boot(MONDAY_UNIX)
	assert_near(_app.rewards.coin_scale, 1.0, 0.0001, "shipped tables by default")
	_app.remote_config.apply_overrides({"economy.coin_multiplier": 1.5, "economy.daily_reward_multiplier": 2.0})
	assert_near(_app.rewards.coin_scale, 1.5, 0.0001)
	assert_near(_app.rewards.daily_scale, 2.0, 0.0001)
	var tier1: Dictionary = RewardEngine.daily_tier_reward(_app.rewards.tables, 1)
	var bundle: RewardBundle = _app.rewards.compute(RewardEngine.TABLE_DAILY_STREAK, {"tier": 1})
	assert_eq(bundle.amount_of(&"coins"), int(tier1["coins"]) * 2, "daily coins doubled remotely")


func test_weekend_bonus_applies_on_saturday_only() -> void:
	_boot(SATURDAY_UNIX)
	_app.remote_config.apply_overrides({"events.weekend_coin_bonus": 0.5})
	assert_near(_app.rewards.coin_scale, 1.5, 0.0001, "weekend event bonus")
	_app.queue_free()
	await wait_frames(2)
	_boot(MONDAY_UNIX)
	_app.remote_config.apply_overrides({"events.weekend_coin_bonus": 0.5})
	assert_near(_app.rewards.coin_scale, 1.0, 0.0001, "no bonus on a Monday")


func test_server_claim_bounds_follow_the_same_scale() -> void:
	_boot(MONDAY_UNIX)
	var verifier: ReplayVerifier = ReplayVerifier.new(_app.clock, DailyChallengeService.load_config())
	var today: String = _app.clock.date_key()
	var tier1: Dictionary = RewardEngine.daily_tier_reward(RewardEngine.load_tables(), 1)
	var claim: Dictionary = {
		"type": "daily", "date_key": today, "tier": 1, "deltas": {"coins": int(tier1["coins"]) * 3}
	}
	var history: Dictionary = {"verified_completions": ["daily_" + today], "daily_claims": {}}
	assert_false(bool(verifier.verify_reward_claim(claim, history)["valid"]), "above the shipped reward")
	verifier.daily_scale = 1.5
	assert_true(bool(verifier.verify_reward_claim(claim, history)["valid"]), "within 1.5x, ad-doubled")


func test_server_tuning_allows_the_weekend_bonus_on_any_day() -> void:
	_boot(MONDAY_UNIX)
	var verifier: ReplayVerifier = ReplayVerifier.new(_app.clock, DailyChallengeService.load_config())
	var level_id: String = "w01_l10"
	var data: Dictionary = LevelRepository.new().load_level(level_id)
	var ceiling: Dictionary = RewardEngine.level_reward_ceiling(
		RewardEngine.load_tables(), str(data["tier"]), str(data.get("kind", "normal")), true
	)
	# A run started on Saturday with a 50 % weekend bonus, ad-doubled, claimed on Monday.
	var claim: Dictionary = {
		"type": "level",
		"level_id": level_id,
		"first_clear": true,
		"deltas": {"coins": RewardEngine.scaled(int(ceiling["coins"]), 1.5) * 2},
	}
	var history: Dictionary = {"verified_completions": [level_id], "level_claims": []}
	assert_false(bool(verifier.verify_reward_claim(claim, history)["valid"]), "untuned server: above the tables")
	verifier.apply_remote_tuning({"events.weekend_coin_bonus": 0.5})
	assert_near(verifier.coin_scale, 1.5, 0.0001, "bonus allowed although the server's day is Monday")
	assert_true(bool(verifier.verify_reward_claim(claim, history)["valid"]), "weekend claim accepted on Monday")
	verifier.apply_remote_tuning({"economy.coin_multiplier": "x", "economy.daily_reward_multiplier": NAN})
	assert_near(verifier.coin_scale, 1.0, 0.0001, "junk values fall back to the tables")
	assert_near(verifier.daily_scale, 1.0, 0.0001, "junk values fall back to the tables")
	verifier.apply_remote_tuning({"economy.coin_multiplier": 50.0})
	assert_near(verifier.coin_scale, ReplayVerifier.MAX_TUNING_SCALE, 0.0001, "clamped like the client")


func test_score_mode_coins_follow_the_live_multiplier() -> void:
	_boot(SATURDAY_UNIX)
	_app.remote_config.apply_overrides({"economy.coin_multiplier": 2.0, "events.weekend_coin_bonus": 0.5})
	var spec: Dictionary = _app.modes.score_reward(&"endless", 20000)
	assert_true(spec.has("coins"), "endless pays coins for this score")
	var runs: RunController = RunController.new(_app, null)
	runs.context = {"source": "endless"}
	var result: RunResult = RunResult.new()
	result.score = 20000
	var coins: int = _app.economy.balance(EconomyService.COINS)
	var bundle: RewardBundle = runs._finish_scored(&"endless", result, {})
	var expected: int = RewardEngine.scaled(int(spec["coins"]), 3.0)
	assert_eq(bundle.amount_of(&"coins"), expected, "weekend event and multiplier reach score modes")
	# (The run's XP can level the player up, which pays its own reward.)
	assert_ge(float(_app.economy.balance(EconomyService.COINS)), float(coins + expected), "and the wallet")
	assert_eq(int(_app.modes.score_reward(&"endless", 20000)["coins"]), int(spec["coins"]), "spec untouched")


func test_daily_challenge_can_be_paused_remotely() -> void:
	_boot(MONDAY_UNIX)
	_app.stats.set_value("levels_cleared", 999)
	_app.remote_config.apply_overrides({"daily.enabled": false})
	var view: Dictionary = Presenters.daily(_app)
	assert_false(bool(view["unlocked"]), "challenge locked while paused")
	assert_eq(str(view["requirement"]), Presenters.t("daily.paused"), "and says why")
	assert_true(view.has("missions"), "missions stay available")
