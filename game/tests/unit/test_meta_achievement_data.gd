extends "res://tests/unit/test_meta_fixture.gd"
## Quality of the shipped achievement definitions (data/achievements).

const LEVEL_TIERS: Array[int] = [1, 10, 50, 100, 250, 520]
## RewardEngine/EconomyService single-grant caps (data/economy/economy.json).
const MAX_SINGLE_COINS: float = 5000.0
const MAX_SINGLE_GEMS: float = 50.0


func _find(stat: String, target: int) -> Dictionary:
	for d: Dictionary in _shipped_achievements():
		if d["stat"] == stat and int(d["target"]) == target:
			return d
	return {}


func test_shipped_definitions_have_at_least_55_entries() -> void:
	var service: AchievementService = _achievements()
	assert_ge(service.total_count(), 55, "achievement count")
	assert_eq(service.total_count(), _shipped_achievements().size(), "every shipped definition is usable")


func test_shipped_definitions_validate_clean() -> void:
	var errors: PackedStringArray = _achievements().validate_definitions(AchievementService.KNOWN_STATS)
	assert_empty(errors, "validation errors: %s" % "; ".join(errors))


func test_ids_unique_targets_positive_stats_known() -> void:
	var seen: Dictionary = {}
	for d: Dictionary in _shipped_achievements():
		var id: String = d["id"]
		assert_false(seen.has(id), "duplicate id %s" % id)
		seen[id] = true
		assert_gt(float(d["target"]), 0.0, "%s target" % id)
		assert_true(AchievementService.KNOWN_STATS.has(str(d["stat"])), "%s stat %s" % [id, d["stat"]])
		assert_true(AchievementService.CATEGORIES.has(str(d["category"])), "%s category" % id)
		assert_eq(typeof(d["hidden"]), TYPE_BOOL, "%s hidden flag" % id)


func test_every_category_is_used_and_secrets_are_hidden() -> void:
	var used: Dictionary = {}
	for d: Dictionary in _shipped_achievements():
		used[d["category"]] = true
		if d["category"] == "secret":
			assert_true(bool(d["hidden"]), "%s secret must be hidden" % d["id"])
	for category: String in AchievementService.CATEGORIES:
		assert_true(used.has(category), "category %s unused" % category)


func test_required_examples_present() -> void:
	assert_false(_find("perfects", 1).is_empty(), "First Perfect")
	assert_false(_find("sparks_collected", 100).is_empty(), "100 collectibles")
	assert_false(_find("max_combo", 10).is_empty(), "10 combo")
	assert_false(_find("damage_free_clears", 1).is_empty(), "No Miss")
	assert_false(_find("worlds_perfected", 1).is_empty(), "Perfect World")
	assert_false(_find("fast_clears", 1).is_empty(), "Fast Clear")
	for tier: int in LEVEL_TIERS:
		assert_false(_find("unique_levels_cleared", tier).is_empty(), "%d levels tier" % tier)
	var high_combo: bool = false
	for d: Dictionary in _shipped_achievements():
		if d["stat"] == "max_combo" and int(d["target"]) >= 50:
			high_combo = true
	assert_true(high_combo, "High Combo (50+)")
	assert_eq(str((_find("daily_completed", 30)["reward"] as Dictionary).get("badge", "")), "badge_daily_master")
	assert_eq(str((_find("bosses_cleared", 10)["reward"] as Dictionary).get("badge", "")), "badge_boss_master")


func test_rewards_use_badge_prefix_and_respect_grant_caps() -> void:
	var badges: int = 0
	for d: Dictionary in _shipped_achievements():
		var reward: Dictionary = d["reward"]
		if reward.has("badge"):
			badges += 1
			assert_true(str(reward["badge"]).begins_with("badge_"), "%s badge id" % d["id"])
		assert_le(float(reward.get("coins", 0)), MAX_SINGLE_COINS, "%s coins within single-grant cap" % d["id"])
		assert_le(float(reward.get("gems", 0)), MAX_SINGLE_GEMS, "%s gems within single-grant cap" % d["id"])
	assert_gt(badges, 0, "some achievements award badges")


func test_tiers_of_a_stat_have_growing_rewards() -> void:
	# Within one stat a higher target never pays less coins (no dead tiers).
	var by_stat: Dictionary = {}
	for d: Dictionary in _shipped_achievements():
		var list: Array = by_stat.get(d["stat"], [])
		list.append(d)
		by_stat[d["stat"]] = list
	for stat: Variant in by_stat:
		var list: Array = by_stat[stat]
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["target"]) < int(b["target"]))
		for i: int in range(1, list.size()):
			var lower: Dictionary = list[i - 1]
			var higher: Dictionary = list[i]
			assert_ge(
				float((higher["reward"] as Dictionary).get("coins", 0)),
				float((lower["reward"] as Dictionary).get("coins", 0)),
				"%s pays at least %s" % [higher["id"], lower["id"]]
			)


func test_missing_definition_file_yields_empty_list() -> void:
	assert_empty(AchievementService.load_definitions("res://data/achievements/missing.json"))
