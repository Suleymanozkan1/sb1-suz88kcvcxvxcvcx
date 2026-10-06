extends TestCase
## PlayerProfile.from_dict must survive any JSON a corrupted or edited save can
## hold: wrong types become safe defaults, never script errors.


func test_wrong_types_fall_back_to_safe_defaults() -> void:
	var p: PlayerProfile = (
		PlayerProfile
		. from_dict(
			{
				"coins": "lots",
				"gems": null,
				"xp": [1],
				"player_level": {"a": 1},
				"levels":
				{
					"w01_l01": {"stars": "3", "perfect": "yes", "best_time": null, "best_score": [5], "clears": {}},
					"w01_l02": {"stars": 7, "perfect": 1, "best_time": 12.5, "clears": 2},
					"w01_l03": "not a record",
				},
				"stats": {"runs_played": "x", "max_combo": null, "taps": 40},
				"settings": {"sound": "loud", "sfx_volume": 2},
				"cosmetics_owned": [1, null, "core_plasma", "core_plasma"],
				"flags": [],
				"ledger": "no",
			}
		)
	)
	assert_eq(p.coins, 0)
	assert_eq(p.gems, 0)
	assert_eq(p.player_level, 1)
	assert_eq(p.stars_for("w01_l01"), 0, "string stars rejected")
	assert_false(bool(p.level_result("w01_l01")["perfect"]), '"yes" is not a boolean')
	assert_eq(p.stars_for("w01_l02"), 3, "stars clamped to 3")
	assert_true(bool(p.level_result("w01_l02")["perfect"]))
	assert_true(p.is_cleared("w01_l02"))
	assert_false(p.levels.has("w01_l03"), "non-object records dropped")
	assert_eq(p.stat("runs_played"), 0)
	assert_eq(p.stat("taps"), 40)
	assert_eq(p.total_stars(), 3)
	assert_eq(bool(p.setting("sound")), true, "invalid setting keeps the default")
	assert_true(p.cosmetics_owned.has("core_plasma"))
	assert_eq(p.ledger.size(), 0)


func test_non_finite_times_are_zeroed() -> void:
	var p: PlayerProfile = PlayerProfile.from_dict({"levels": {"w01_l01": {"best_time": INF, "clears": 1}}})
	assert_eq(float(p.level_result("w01_l01")["best_time"]), 0.0)


func test_known_flags_of_the_wrong_type_are_dropped() -> void:
	var data: Dictionary = PlayerProfile.new().to_dict()
	data["flags"] = {
		"mode_best": {"endless": "lots", "classic": 50.0, "zen": INF},
		"economy_starting_granted": "yes",
		"tutorial_done": 1,
		"last_level": 7,
		"notifications.daily_day": 20000.0,
		"custom": "kept",
	}
	var p: PlayerProfile = PlayerProfile.from_dict(data)
	assert_eq(p.flags["mode_best"], {"classic": 50}, "only whole-number bests survive")
	assert_false(p.flags.has("economy_starting_granted"))
	assert_false(p.flags.has("tutorial_done"))
	assert_false(p.flags.has("last_level"))
	assert_eq(p.flags["notifications.daily_day"], 20000)
	assert_eq(p.flags["custom"], "kept", "unknown flags untouched")
	data["flags"] = {"mode_best": [1, 2, 3]}
	assert_false(PlayerProfile.from_dict(data).flags.has("mode_best"), "a list is not a table of bests")
