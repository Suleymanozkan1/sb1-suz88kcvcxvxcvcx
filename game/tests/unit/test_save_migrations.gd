extends TestCase
## SaveMigrations: version support and the legacy v0 -> v1 reshaping.


func _legacy() -> Dictionary:
	return {
		"coins": 321,
		"stars": {"w01_l01": 3, "w01_l02": 1, "w01_l04": 2},
		"best": {"w01_l01": 5000, "w01_l02": 800, "w01_l03": 50},
	}


func test_supported_versions() -> void:
	assert_true(SaveMigrations.is_supported(SaveMigrations.LEGACY_VERSION))
	assert_true(SaveMigrations.is_supported(SaveMigrations.CURRENT_VERSION))
	assert_eq(SaveMigrations.CURRENT_VERSION, PlayerProfile.SCHEMA_VERSION)
	assert_false(SaveMigrations.is_supported(-1))
	assert_false(SaveMigrations.is_supported(SaveMigrations.CURRENT_VERSION + 1))
	assert_false(SaveMigrations.is_supported(99))


func test_v0_to_v1_shape() -> void:
	var out: Dictionary = SaveMigrations.migrate(_legacy(), 0)
	assert_eq(out["schema_version"], PlayerProfile.SCHEMA_VERSION)
	assert_eq(out["coins"], 321)
	var levels: Dictionary = out["levels"] as Dictionary
	assert_eq(levels.size(), 4, "union of stars and best ids")
	var l1: Dictionary = levels["w01_l01"] as Dictionary
	assert_eq(l1["stars"], 3)
	assert_eq(l1["best_score"], 5000)
	assert_eq(l1["clears"], 1)
	assert_true(l1["perfect"] as bool, "three stars include the perfect star")
	var l2: Dictionary = levels["w01_l02"] as Dictionary
	assert_eq(l2["stars"], 1)
	assert_eq(l2["best_score"], 800)
	assert_false(l2["perfect"] as bool)
	var l3: Dictionary = levels["w01_l03"] as Dictionary
	assert_eq(l3["stars"], 0, "best without stars means attempted, not cleared")
	assert_eq(l3["clears"], 0)
	assert_eq(l3["attempts"], 1)
	var l4: Dictionary = levels["w01_l04"] as Dictionary
	assert_eq(l4["best_score"], 0)
	assert_eq(l4["clears"], 1)
	assert_false(out.has("stars"), "legacy keys are not carried over")
	assert_false(out.has("best"))


func test_v0_hostile_values_are_neutralized() -> void:
	var hostile: Dictionary = {
		"coins": -500,
		"stars": {"w01_l01": 9, "w01_l02": -4, "w01_l03": "three", "": 2, "w01_l05": INF},
		"best": ["not", "a", "map"],
	}
	var out: Dictionary = SaveMigrations.migrate(hostile, 0)
	assert_eq(out["coins"], 0)
	var levels: Dictionary = out["levels"] as Dictionary
	assert_eq((levels["w01_l01"] as Dictionary)["stars"], 3, "stars clamped to 3")
	assert_eq((levels["w01_l02"] as Dictionary)["stars"], 0)
	assert_eq((levels["w01_l03"] as Dictionary)["stars"], 0, "non-numeric stars")
	assert_eq((levels["w01_l05"] as Dictionary)["stars"], 0, "non-finite stars")
	assert_false(levels.has(""), "empty level id dropped")
	var weird: Dictionary = SaveMigrations.migrate({"coins": "lots", "stars": 5}, 0)
	assert_eq(weird["coins"], 0)
	assert_empty(weird["levels"])


func test_v0_level_ids_are_trimmed_and_merged() -> void:
	var legacy: Dictionary = {
		"coins": 5,
		"stars": {" w01_l01 ": 2, "w01_l01": 1},
		"best": {"w01_l01 ": 700, "w01_l02": 40},
	}
	var levels: Dictionary = SaveMigrations.migrate(legacy, 0)["levels"] as Dictionary
	assert_eq(levels.size(), 2, "ids that differ only by spaces are one level")
	var l1: Dictionary = levels["w01_l01"] as Dictionary
	assert_eq(l1["stars"], 2, "the highest value wins for a duplicated id")
	assert_eq(l1["best_score"], 700, "a trimmed id still finds its best score")
	assert_eq((levels["w01_l02"] as Dictionary)["stars"], 0)


func test_v0_with_many_levels_keeps_every_level() -> void:
	var stars: Dictionary = {}
	var best: Dictionary = {}
	for i: int in 3000:
		stars["lvl_%05d" % i] = i % 4
		best["lvl_%05d" % (i + 1500)] = i
	var levels: Dictionary = SaveMigrations.migrate({"coins": 1, "stars": stars, "best": best}, 0)["levels"] as Dictionary
	assert_eq(levels.size(), 4500, "union of both maps")
	assert_eq((levels["lvl_00003"] as Dictionary)["stars"], 3)
	assert_eq((levels["lvl_04499"] as Dictionary)["best_score"], 2999)
	assert_eq(levels.keys()[0], "lvl_00000", "levels are emitted in sorted id order")


func test_migrated_payload_builds_a_valid_profile() -> void:
	var profile: PlayerProfile = PlayerProfile.from_dict(SaveMigrations.migrate(_legacy(), 0))
	assert_eq(profile.coins, 321)
	assert_eq(profile.total_stars(), 6)
	assert_true(profile.is_cleared("w01_l01"))
	assert_false(profile.is_cleared("w01_l03"))
	assert_eq(profile.stars_for("w01_l04"), 2)
	assert_has(profile.unlocked_worlds, "neon_core")


func test_current_version_returns_independent_copy() -> void:
	var payload: Dictionary = {"coins": 10, "levels": {"w01_l01": {"stars": 2}}}
	var out: Dictionary = SaveMigrations.migrate(payload, SaveMigrations.CURRENT_VERSION)
	assert_eq(out["coins"], 10)
	((out["levels"] as Dictionary)["w01_l01"] as Dictionary)["stars"] = 0
	assert_eq(((payload["levels"] as Dictionary)["w01_l01"] as Dictionary)["stars"], 2, "input untouched")


func test_migrate_does_not_modify_input() -> void:
	var legacy: Dictionary = _legacy()
	var before: String = JsonIO.canonical(legacy)
	SaveMigrations.migrate(legacy, 0)
	assert_eq(JsonIO.canonical(legacy), before)


func test_unsupported_version_returns_empty() -> void:
	assert_empty(SaveMigrations.migrate({"coins": 1}, SaveMigrations.CURRENT_VERSION + 1))
	assert_empty(SaveMigrations.migrate({"coins": 1}, -3))
