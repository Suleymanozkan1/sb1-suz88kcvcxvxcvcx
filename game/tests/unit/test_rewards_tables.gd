extends TestCase
## reward_tables.json content: coverage of every difficulty tier, named tables,
## balance targets, grantability and the economy string files.

const CURVE_PATH: String = "res://data/difficulty/curve.json"
const EN_PATH: String = "res://data/i18n/parts/economy.en.json"
const TR_PATH: String = "res://data/i18n/parts/economy.tr.json"
const EXPECTED_TIERS: Array[String] = [
	"tutorial",
	"early",
	"core_learning",
	"mechanic_expansion",
	"combination",
	"advanced_timing",
	"expert",
	"master",
	"challenge",
	"endgame",
]
## A typical shop cosmetic costs 300-1500 coins.
const CHEAP_COSMETIC: int = 300
const EXPENSIVE_COSMETIC: int = 1500

var profile: PlayerProfile
var economy: EconomyService
var engine: RewardEngine


func before_each() -> void:
	profile = PlayerProfile.new()
	var bus: EventBus = EventBus.new()
	economy = EconomyService.new(profile, bus, GameClock.new())
	engine = RewardEngine.new(profile, bus, economy, _grant_xp, _grant_cosmetic)


func _grant_xp(_amount: int) -> void:
	pass


func _grant_cosmetic(item_id: String) -> bool:
	if profile.cosmetics_owned.has(item_id):
		return false
	profile.cosmetics_owned.append(item_id)
	return true


func _curve_tiers() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for raw: Variant in JsonIO.read_dict(CURVE_PATH).get("tiers", []) as Array:
		out.append(str((raw as Dictionary)["id"]))
	return out


func _clear(tier: String, kind: String, stars: int, perfect: bool) -> RewardBundle:
	var r: RunResult = RunResult.new()
	r.level_id = "w01_l01"
	r.completed = true
	r.stars = stars
	r.perfect = perfect
	r.time_seconds = 30.0
	var ctx: Dictionary = {
		"tier": tier,
		"kind": kind,
		"first_clear": true,
		"prev_stars": 0,
		"new_stars": stars,
		"first_perfect": perfect,
	}
	return engine.compute_level_reward(r, ctx)


func test_tables_validate_clean() -> void:
	var errors: PackedStringArray = RewardEngine.validate_tables(engine.tables, _curve_tiers())
	assert_empty(errors, "validation errors: %s" % ", ".join(errors))


func test_tables_cover_every_difficulty_tier() -> void:
	var curve: PackedStringArray = _curve_tiers()
	assert_eq(curve.size(), EXPECTED_TIERS.size(), "curve has the 10 tiers")
	var level: Dictionary = engine.tables["level"] as Dictionary
	for tier: String in EXPECTED_TIERS:
		assert_has(curve, tier, "curve tier")
		assert_has(level["base_by_tier"] as Dictionary, tier, "base_by_tier")
		assert_has(level["replay_coins_by_tier"] as Dictionary, tier, "replay_coins_by_tier")
	assert_eq(engine.tier_ids().size(), EXPECTED_TIERS.size())


func test_validator_reports_broken_tables() -> void:
	var broken: Dictionary = engine.tables.duplicate(true)
	var level: Dictionary = broken["level"] as Dictionary
	(level["base_by_tier"] as Dictionary).erase("master")
	(level["replay_coins_by_tier"] as Dictionary)["early"] = 500
	var tiers: Array = (broken["daily_streak"] as Dictionary)["tiers"] as Array
	((tiers[0] as Dictionary)["reward"] as Dictionary)["gems"] = 5
	tiers.remove_at(6)
	broken["bonus_chest"] = {"reward": {"coins": 10, "boosters": 1}}
	broken["ad_double"] = {"types": ["coins", "cosmetic"]}
	var errors: String = "\n".join(RewardEngine.validate_tables(broken, _curve_tiers()))
	assert_has(errors, "base_by_tier.master")
	assert_has(errors, "replay_coins_by_tier.early")
	assert_has(errors, "tier 1 must not give gems")
	assert_has(errors, "tier 7 missing")
	assert_has(errors, "bonus_chest")
	assert_has(errors, "ad_double")
	assert_has("\n".join(RewardEngine.validate_tables({}, _curve_tiers())), "missing level table")


func test_daily_streak_grows_gently_with_gems_from_tier_three() -> void:
	var previous_coins: int = 0
	var first_coins: int = 0
	for tier: int in range(1, RewardEngine.DAILY_STREAK_TIERS + 1):
		var bundle: RewardBundle = engine.compute(RewardEngine.TABLE_DAILY_STREAK, {"tier": tier})
		var coins: int = bundle.amount_of(RewardBundle.TYPE_COINS)
		var gems: int = bundle.amount_of(RewardBundle.TYPE_GEMS)
		assert_gt(coins, 0, "tier %d pays coins" % tier)
		assert_ge(coins, previous_coins, "tier %d never shrinks" % tier)
		if tier < RewardEngine.FIRST_GEM_STREAK_TIER:
			assert_eq(gems, 0, "no gems on tier %d" % tier)
		else:
			assert_gt(gems, 0, "gems on tier %d" % tier)
		if tier == 1:
			first_coins = coins
		previous_coins = coins
		assert_eq(bundle.source, "daily_streak:%d" % tier)
	assert_le(previous_coins, first_coins * 3, "day 7 is at most 3x day 1 (gentle)")


func test_daily_streak_beyond_seven_stays_at_top_tier() -> void:
	var top: RewardBundle = engine.compute(RewardEngine.TABLE_DAILY_STREAK, {"tier": 7})
	var later: RewardBundle = engine.compute(RewardEngine.TABLE_DAILY_STREAK, {"tier": 30})
	assert_eq(later.to_dict()["items"], top.to_dict()["items"])
	assert_true(engine.compute(RewardEngine.TABLE_DAILY_STREAK, {"tier": 0}).is_empty())
	assert_true(engine.compute(RewardEngine.TABLE_DAILY_STREAK, {}).is_empty())


func test_bonus_chest_contents_are_fixed() -> void:
	var a: RewardBundle = engine.compute(RewardEngine.TABLE_BONUS_CHEST)
	var b: RewardBundle = engine.compute(RewardEngine.TABLE_BONUS_CHEST, {"seed": 12345})
	assert_false(a.is_empty())
	assert_eq(a.to_dict(), b.to_dict(), "same contents every time, nothing random")
	var spec: Dictionary = (engine.tables["bonus_chest"] as Dictionary)["reward"] as Dictionary
	assert_eq(a.amount_of(RewardBundle.TYPE_COINS), int(spec.get("coins", 0)), "contents match the data shown")
	assert_eq(a.amount_of(RewardBundle.TYPE_XP), int(spec.get("xp", 0)))


func test_level_up_rewards() -> void:
	var table: Dictionary = engine.tables["level_up"] as Dictionary
	var two: RewardBundle = engine.compute(RewardEngine.TABLE_LEVEL_UP, {"level": 2})
	assert_eq(two.amount_of(RewardBundle.TYPE_COINS), int(table["coins_base"]))
	assert_eq(two.amount_of(RewardBundle.TYPE_GEMS), 0)
	var three: RewardBundle = engine.compute(RewardEngine.TABLE_LEVEL_UP, {"level": 3})
	assert_gt(three.amount_of(RewardBundle.TYPE_COINS), two.amount_of(RewardBundle.TYPE_COINS), "grows")
	var every: int = int(table["gems_every"])
	var gem_level: RewardBundle = engine.compute(RewardEngine.TABLE_LEVEL_UP, {"level": every})
	assert_eq(gem_level.amount_of(RewardBundle.TYPE_GEMS), int(table["gems"]))
	var ten: RewardBundle = engine.compute(RewardEngine.TABLE_LEVEL_UP, {"level": 10})
	assert_gt(ten.amount_of(RewardBundle.TYPE_GEMS), int(table["gems"]), "milestone adds gems")
	var high: RewardBundle = engine.compute(RewardEngine.TABLE_LEVEL_UP, {"level": 400})
	assert_eq(high.amount_of(RewardBundle.TYPE_COINS), int(table["coins_max"]), "capped")
	assert_true(engine.compute(RewardEngine.TABLE_LEVEL_UP, {"level": 1}).is_empty())
	assert_true(engine.compute(RewardEngine.TABLE_LEVEL_UP, {}).is_empty())


func test_world_complete_rewards() -> void:
	var table: Dictionary = engine.tables["world_complete"] as Dictionary
	var first: RewardBundle = engine.compute(RewardEngine.TABLE_WORLD_COMPLETE, {"world_index": 1})
	var last: RewardBundle = engine.compute(RewardEngine.TABLE_WORLD_COMPLETE, {"world_index": 10})
	assert_eq(first.amount_of(RewardBundle.TYPE_COINS), int(table["coins_base"]))
	var expected_last: int = int(table["coins_base"]) + 9 * int(table["coins_per_world"])
	assert_eq(last.amount_of(RewardBundle.TYPE_COINS), expected_last)
	assert_eq(first.amount_of(RewardBundle.TYPE_GEMS), int(table["gems"]))
	assert_eq(last.source, "world_complete:10")
	assert_true(engine.compute(RewardEngine.TABLE_WORLD_COMPLETE, {"world_index": 0}).is_empty())
	assert_true(engine.compute(RewardEngine.TABLE_WORLD_COMPLETE, {"world_index": 11}).is_empty())


func test_unknown_table_is_empty() -> void:
	assert_true(engine.compute("loot_box", {}).is_empty())


func test_typical_cosmetic_takes_a_fair_number_of_levels() -> void:
	# Typical play: first clear of a normal level with two stars.
	for tier: String in EXPECTED_TIERS:
		var coins: int = _clear(tier, "normal", 2, false).amount_of(RewardBundle.TYPE_COINS)
		var cheap_levels: int = ceili(float(CHEAP_COSMETIC) / float(coins))
		var expensive_levels: int = ceili(float(EXPENSIVE_COSMETIC) / float(coins))
		assert_ge(coins, 30, "%s pays enough" % tier)
		assert_le(coins, 38, "%s does not inflate" % tier)
		assert_ge(cheap_levels, 8, "%s: a cheap cosmetic still takes a few levels" % tier)
		assert_le(cheap_levels, 10, tier)
		assert_ge(expensive_levels, 40, tier)
		assert_le(expensive_levels, 50, "%s: an expensive cosmetic stays reachable by skill" % tier)


func test_replays_never_out_earn_progress() -> void:
	var level: Dictionary = engine.tables["level"] as Dictionary
	for tier: String in EXPECTED_TIERS:
		var replay: int = int((level["replay_coins_by_tier"] as Dictionary)[tier])
		var first: int = _clear(tier, "normal", 1, false).amount_of(RewardBundle.TYPE_COINS)
		assert_gt(replay, 0, tier)
		assert_le(replay * 5, first, "%s replay <= 20%% of a first clear" % tier)


func test_every_table_reward_is_grantable_even_when_doubled() -> void:
	var bundles: Array[RewardBundle] = []
	for tier: String in EXPECTED_TIERS:
		for kind: String in RewardEngine.KINDS:
			bundles.append(_clear(tier, kind, 3, true))
	for tier: int in range(1, 11):
		bundles.append(engine.compute(RewardEngine.TABLE_DAILY_STREAK, {"tier": tier}))
		bundles.append(engine.compute(RewardEngine.TABLE_WORLD_COMPLETE, {"world_index": tier}))
	for level: int in range(2, 201):
		bundles.append(engine.compute(RewardEngine.TABLE_LEVEL_UP, {"level": level}))
	bundles.append(engine.compute(RewardEngine.TABLE_BONUS_CHEST))
	for bundle: RewardBundle in bundles:
		for currency: StringName in EconomyService.CURRENCIES:
			var amount: int = bundle.amount_of(currency)
			assert_le(amount, economy.max_single_grant(currency), "%s %s" % [bundle.source, currency])
			assert_le(engine.double_for_ad(bundle).amount_of(currency), economy.max_single_grant(currency))
	assert_le(economy.duplicate_cosmetic_coins(), CHEAP_COSMETIC / 2, "duplicates never beat a purchase")


func test_perfect_badges_follow_badge_naming() -> void:
	for tier: String in EXPECTED_TIERS:
		var bundle: RewardBundle = _clear(tier, "normal", 3, true)
		var found: bool = false
		for item: Dictionary in bundle.items:
			if item["type"] == RewardBundle.TYPE_BADGE:
				found = true
				assert_eq(str(item["id"]), "badge_perfect_" + tier)
		assert_true(found, "first perfect in %s offers its badge" % tier)


func test_compute_is_deterministic() -> void:
	for table_id: String in RewardEngine.TABLE_IDS:
		var ctx: Dictionary = {"tier": 5, "level": 10, "world_index": 4}
		var a: String = JSON.stringify(engine.compute(table_id, ctx).to_dict(), "", true)
		var b: String = JSON.stringify(engine.compute(table_id, ctx).to_dict(), "", true)
		assert_eq(a, b, table_id)
		assert_false(engine.compute(table_id, ctx).is_empty(), "%s gives a reward" % table_id)


func test_economy_strings_exist_in_english_and_turkish() -> void:
	var en: Dictionary = JsonIO.read_dict(EN_PATH)
	var tr: Dictionary = JsonIO.read_dict(TR_PATH)
	assert_false(en.is_empty(), "english strings load")
	assert_eq(en.keys(), tr.keys(), "same keys in the same order")
	var key_format: RegEx = RegEx.create_from_string("^economy(\\.[a-z0-9]+(_[a-z0-9]+)*)+$")
	var translated: int = 0
	for key: Variant in en:
		assert_true(key_format.search(str(key)) != null, "key format %s" % str(key))
		assert_false(str(tr.get(key, "")).strip_edges().is_empty(), "turkish text for %s" % str(key))
		if str(en[key]) != str(tr.get(key, "")):
			translated += 1
	assert_ge(translated, en.size() - 2, "almost every string is really translated")
