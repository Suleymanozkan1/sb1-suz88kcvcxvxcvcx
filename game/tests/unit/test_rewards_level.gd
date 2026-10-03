extends TestCase
## RewardEngine.compute_level_reward: first clear vs replay, stars, kinds,
## first perfect, failed runs, fallbacks and determinism.

const NOW: int = 1790000000
const LEVEL_ID: String = "w01_l07"

var profile: PlayerProfile
var bus: EventBus
var economy: EconomyService
var engine: RewardEngine
var xp_log: Array[int] = []


func before_each() -> void:
	profile = PlayerProfile.new()
	bus = EventBus.new()
	var clock: GameClock = GameClock.new()
	clock.set_fixed_unix(NOW)
	economy = EconomyService.new(profile, bus, clock)
	engine = RewardEngine.new(profile, bus, economy, _grant_xp, _grant_cosmetic)
	xp_log = []


func _grant_xp(amount: int) -> void:
	xp_log.append(amount)
	profile.xp += amount


## Behaves like CosmeticService.grant for badges: true when newly owned.
func _grant_cosmetic(item_id: String) -> bool:
	if not item_id.begins_with("badge_") or profile.cosmetics_owned.has(item_id):
		return false
	profile.cosmetics_owned.append(item_id)
	return true


func _run(completed: bool, stars: int, perfect: bool = false, seconds: float = 20.0) -> RunResult:
	var r: RunResult = RunResult.new()
	r.level_id = LEVEL_ID
	r.completed = completed
	r.stars = stars if completed else 0
	r.perfect = perfect and completed
	r.time_seconds = seconds
	r.score = 1000 * stars
	return r


func _ctx(tier: String, first_clear: bool, prev_stars: int, new_stars: int, extra: Dictionary = {}) -> Dictionary:
	var ctx: Dictionary = {
		"tier": tier,
		"kind": "normal",
		"first_clear": first_clear,
		"prev_stars": prev_stars,
		"new_stars": new_stars,
		"first_perfect": false,
	}
	ctx.merge(extra, true)
	return ctx


func _level(key: String) -> Variant:
	return (engine.tables["level"] as Dictionary)[key]


func _tier_value(table_key: String, tier: String) -> int:
	return int((_level(table_key) as Dictionary)[tier])


func test_first_clear_pays_tier_base_plus_new_stars() -> void:
	var bundle: RewardBundle = engine.compute_level_reward(_run(true, 2), _ctx("early", true, 0, 2))
	var star_coins: int = int(_level("coins_per_new_star"))
	assert_eq(bundle.amount_of(RewardBundle.TYPE_COINS), _tier_value("base_by_tier", "early") + 2 * star_coins)
	assert_eq(bundle.amount_of(RewardBundle.TYPE_XP), int(_level("xp_base")) + 2 * int(_level("xp_per_star")))
	assert_eq(bundle.amount_of(RewardBundle.TYPE_GEMS), 0, "gems only for a first perfect")
	assert_eq(bundle.amount_of(RewardBundle.TYPE_BADGE), 0)
	assert_eq(bundle.source, "level:" + LEVEL_ID)


func test_replay_pays_small_but_nonzero_coins() -> void:
	var first: RewardBundle = engine.compute_level_reward(_run(true, 2), _ctx("early", true, 0, 2))
	var replay: RewardBundle = engine.compute_level_reward(_run(true, 2), _ctx("early", false, 2, 0))
	var replay_coins: int = replay.amount_of(RewardBundle.TYPE_COINS)
	assert_eq(replay_coins, _tier_value("replay_coins_by_tier", "early"))
	assert_gt(replay_coins, 0, "a completed run always pays something")
	assert_lt(replay_coins * 5, first.amount_of(RewardBundle.TYPE_COINS), "replays are much smaller")
	assert_eq(replay.amount_of(RewardBundle.TYPE_XP), first.amount_of(RewardBundle.TYPE_XP), "XP follows stars")


func test_replay_coins_never_zero_even_if_table_says_zero() -> void:
	var tables: Dictionary = RewardEngine.load_tables().duplicate(true)
	((tables["level"] as Dictionary)["replay_coins_by_tier"] as Dictionary)["early"] = 0
	var custom: RewardEngine = RewardEngine.new(profile, bus, economy, _grant_xp, _grant_cosmetic, tables)
	var replay: RewardBundle = custom.compute_level_reward(_run(true, 1), _ctx("early", false, 1, 0))
	assert_eq(replay.amount_of(RewardBundle.TYPE_COINS), int(_level("replay_coins_min")))
	assert_gt(replay.amount_of(RewardBundle.TYPE_COINS), 0)


func test_completed_run_pays_coins_even_with_broken_tier_data() -> void:
	var tables: Dictionary = RewardEngine.load_tables().duplicate(true)
	var level: Dictionary = tables["level"] as Dictionary
	(level["base_by_tier"] as Dictionary)["early"] = 0
	(level["kind_bonus"] as Dictionary)["normal"] = 0
	level["replay_coins_min"] = 0
	level.erase("replay_coins_by_tier")
	level["replay_coins"] = 3
	var custom: RewardEngine = RewardEngine.new(profile, bus, economy, _grant_xp, _grant_cosmetic, tables)
	var first: RewardBundle = custom.compute_level_reward(_run(true, 1), _ctx("early", true, 1, 0))
	assert_eq(first.amount_of(RewardBundle.TYPE_COINS), RewardEngine.MIN_COMPLETED_COINS, "never zero")
	var replay: RewardBundle = custom.compute_level_reward(_run(true, 1), _ctx("early", false, 1, 0))
	assert_eq(replay.amount_of(RewardBundle.TYPE_COINS), 3, "flat replay_coins from data is the fallback")


func test_new_stars_on_replay_add_star_bonus() -> void:
	var bundle: RewardBundle = engine.compute_level_reward(_run(true, 3, false), _ctx("combination", false, 1, 2))
	var expected: int = _tier_value("replay_coins_by_tier", "combination") + 2 * int(_level("coins_per_new_star"))
	assert_eq(bundle.amount_of(RewardBundle.TYPE_COINS), expected)


func test_new_stars_are_clamped_to_what_the_run_earned() -> void:
	var star_coins: int = int(_level("coins_per_new_star"))
	var base: int = _tier_value("base_by_tier", "early")
	var inflated: RewardBundle = engine.compute_level_reward(_run(true, 2), _ctx("early", true, 0, 5))
	assert_eq(inflated.amount_of(RewardBundle.TYPE_COINS), base + 2 * star_coins, "cannot claim 5 new stars")
	var none_new: RewardBundle = engine.compute_level_reward(_run(true, 2), _ctx("early", false, 2, 3))
	assert_eq(none_new.amount_of(RewardBundle.TYPE_COINS), _tier_value("replay_coins_by_tier", "early"))
	var negative: RewardBundle = engine.compute_level_reward(_run(true, 1), _ctx("early", true, 0, -4))
	assert_eq(negative.amount_of(RewardBundle.TYPE_COINS), base)


func test_kind_bonus_applies_to_first_clear_only() -> void:
	var bonus: Dictionary = _level("kind_bonus") as Dictionary
	var base: int = _tier_value("base_by_tier", "expert")
	var boss: RewardBundle = engine.compute_level_reward(_run(true, 1), _ctx("expert", true, 0, 1, {"kind": "boss"}))
	var star_coins: int = int(_level("coins_per_new_star"))
	assert_eq(boss.amount_of(RewardBundle.TYPE_COINS), base + int(bonus["boss"]) + star_coins)
	var challenge_ctx: Dictionary = _ctx("expert", true, 0, 1, {"kind": "challenge"})
	var challenge: RewardBundle = engine.compute_level_reward(_run(true, 1), challenge_ctx)
	assert_eq(challenge.amount_of(RewardBundle.TYPE_COINS), base + int(bonus["challenge"]) + star_coins)
	assert_gt(int(bonus["boss"]), int(bonus["challenge"]), "bosses pay the most")
	var replay: RewardBundle = engine.compute_level_reward(_run(true, 1), _ctx("expert", false, 1, 0, {"kind": "boss"}))
	assert_eq(replay.amount_of(RewardBundle.TYPE_COINS), _tier_value("replay_coins_by_tier", "expert"))
	var odd: RewardBundle = engine.compute_level_reward(_run(true, 1), _ctx("expert", true, 0, 1, {"kind": "mega"}))
	assert_eq(odd.amount_of(RewardBundle.TYPE_COINS), base + star_coins, "unknown kind counts as normal")


func test_first_perfect_gives_gems_and_badge_only_once() -> void:
	var gems: int = int(_level("perfect_first_gems"))
	var perfect_ctx: Dictionary = _ctx("early", true, 0, 3, {"first_perfect": true})
	var first: RewardBundle = engine.compute_level_reward(_run(true, 3, true), perfect_ctx)
	assert_eq(first.amount_of(RewardBundle.TYPE_GEMS), gems)
	assert_gt(gems, 0)
	assert_eq(_badges(first), ["badge_perfect_early"] as Array[String])
	var granted: RewardBundle = engine.grant(first)
	assert_eq(_badges(granted), ["badge_perfect_early"] as Array[String])
	assert_true(profile.cosmetics_owned.has("badge_perfect_early"))
	assert_eq(economy.balance(EconomyService.GEMS), gems)
	var again: RewardBundle = engine.compute_level_reward(_run(true, 3, true), _ctx("early", false, 3, 0))
	assert_eq(again.amount_of(RewardBundle.TYPE_GEMS), 0, "second perfect of the level: no gems")
	assert_empty(_badges(again), "no badge again")
	var other_level: RewardBundle = engine.compute_level_reward(_run(true, 3, true), perfect_ctx)
	assert_eq(other_level.amount_of(RewardBundle.TYPE_GEMS), gems, "another level's first perfect pays gems")
	assert_empty(_badges(other_level), "badge already owned is not offered again")
	var next_tier_ctx: Dictionary = _ctx("core_learning", true, 0, 3, {"first_perfect": true})
	var next_tier: RewardBundle = engine.compute_level_reward(_run(true, 3, true), next_tier_ctx)
	assert_eq(_badges(next_tier), ["badge_perfect_core_learning"] as Array[String])


func test_first_perfect_flag_needs_a_perfect_run() -> void:
	var ctx: Dictionary = _ctx("early", true, 0, 2, {"first_perfect": true})
	var bundle: RewardBundle = engine.compute_level_reward(_run(true, 2, false), ctx)
	assert_eq(bundle.amount_of(RewardBundle.TYPE_GEMS), 0)
	assert_empty(_badges(bundle))


func test_failed_run_gives_no_coins_only_consolation_xp() -> void:
	var ctx: Dictionary = _ctx("early", true, 0, 2, {"first_perfect": true, "kind": "boss"})
	var bundle: RewardBundle = engine.compute_level_reward(_run(false, 0, false, 30.0), ctx)
	assert_eq(bundle.amount_of(RewardBundle.TYPE_COINS), 0, "no coins for a failed run")
	assert_eq(bundle.amount_of(RewardBundle.TYPE_GEMS), 0)
	assert_eq(bundle.amount_of(RewardBundle.TYPE_XP), int(_level("fail_xp")))
	assert_eq(bundle.items.size(), 1, "xp only")
	assert_lt(int(_level("fail_xp")), int(_level("xp_base")), "consolation is smaller than a clear")


func test_instant_failures_give_nothing() -> void:
	var quick: float = float(_level("fail_xp_min_seconds")) - 0.5
	var bundle: RewardBundle = engine.compute_level_reward(_run(false, 0, false, quick), _ctx("early", false, 0, 0))
	assert_true(bundle.is_empty(), "restart spamming earns nothing")


func test_unknown_tier_falls_back_to_default_tier() -> void:
	var fallback: String = str(_level("default_tier"))
	var ctx: Dictionary = _ctx("not_a_tier", true, 0, 1, {"first_perfect": true})
	var bundle: RewardBundle = engine.compute_level_reward(_run(true, 1, true), ctx)
	var expected: int = _tier_value("base_by_tier", fallback) + int(_level("coins_per_new_star"))
	assert_eq(bundle.amount_of(RewardBundle.TYPE_COINS), expected)
	assert_eq(_badges(bundle), ["badge_perfect_" + fallback] as Array[String])


func test_null_result_and_empty_ctx_are_safe() -> void:
	assert_true(engine.compute_level_reward(null, {}).is_empty())
	var bundle: RewardBundle = engine.compute_level_reward(_run(true, 1), {})
	assert_gt(bundle.amount_of(RewardBundle.TYPE_COINS), 0, "replay of the default tier")
	var odd: Dictionary = {"tier": 7, "first_clear": "yes", "new_stars": "two", "prev_stars": null}
	assert_gt(engine.compute_level_reward(_run(true, 2), odd).amount_of(RewardBundle.TYPE_XP), 0)


func test_level_rewards_are_deterministic() -> void:
	var ctx: Dictionary = _ctx("master", true, 0, 3, {"first_perfect": true, "kind": "boss"})
	var a: Dictionary = engine.compute_level_reward(_run(true, 3, true), ctx).to_dict()
	var b: Dictionary = engine.compute_level_reward(_run(true, 3, true), ctx).to_dict()
	var other: RewardEngine = RewardEngine.new(PlayerProfile.new(), EventBus.new(), economy, _grant_xp, _grant_cosmetic)
	var c: Dictionary = other.compute_level_reward(_run(true, 3, true), ctx).to_dict()
	assert_eq(JSON.stringify(a, "", true), JSON.stringify(b, "", true))
	assert_eq(JSON.stringify(a, "", true), JSON.stringify(c, "", true))
	assert_true(xp_log.is_empty(), "computing never grants")
	assert_eq(economy.balance(EconomyService.COINS), 0)


func test_every_tier_pays_more_for_first_clear_than_replay() -> void:
	for tier: String in engine.tier_ids():
		var first: int = engine.compute_level_reward(_run(true, 1), _ctx(tier, true, 0, 1)).amount_of(&"coins")
		var replay: int = engine.compute_level_reward(_run(true, 1), _ctx(tier, false, 1, 0)).amount_of(&"coins")
		assert_gt(replay, 0, tier)
		assert_gt(first, replay * 4, tier)


func test_granted_level_reward_is_logged_with_level_source() -> void:
	var bundle: RewardBundle = engine.compute_level_reward(_run(true, 1), _ctx("tutorial", true, 0, 1))
	var granted: RewardBundle = engine.grant(bundle)
	assert_eq(granted.amount_of(RewardBundle.TYPE_COINS), bundle.amount_of(RewardBundle.TYPE_COINS))
	assert_eq(profile.ledger[profile.ledger.size() - 1]["s"], "level:" + LEVEL_ID)
	assert_eq(xp_log, [bundle.amount_of(RewardBundle.TYPE_XP)] as Array[int])


func test_missing_tables_use_safe_fallbacks() -> void:
	var bare: RewardEngine = RewardEngine.new(profile, bus, economy, _grant_xp, _grant_cosmetic, {"schema_version": 1})
	var bundle: RewardBundle = bare.compute_level_reward(_run(true, 1), _ctx("early", true, 0, 1))
	var expected: int = int(RewardEngine.FALLBACK_LEVEL["first_clear_coins"])
	expected += int(RewardEngine.FALLBACK_LEVEL["coins_per_new_star"])
	assert_eq(bundle.amount_of(RewardBundle.TYPE_COINS), expected)
	assert_gt(bundle.amount_of(RewardBundle.TYPE_XP), 0)
	assert_true(bare.compute(RewardEngine.TABLE_BONUS_CHEST).is_empty(), "missing tables give nothing")


func _badges(bundle: RewardBundle) -> Array[String]:
	var out: Array[String] = []
	for item: Dictionary in bundle.items:
		if item["type"] == RewardBundle.TYPE_BADGE:
			out.append(str(item["id"]))
	return out
