extends "res://tests/unit/test_meta_fixture.gd"
## AchievementService behaviour: unlock and reward rules, hidden achievements,
## progress reporting and robustness against invalid definitions.


func test_fresh_profile_unlocks_nothing() -> void:
	var service: AchievementService = _achievements()
	assert_empty(service.evaluate(), "fresh profile")
	assert_eq(service.unlocked_count(), 0)
	assert_empty(_rewards.calls)


func test_evaluate_unlocks_once_and_grants_once() -> void:
	var service: AchievementService = _achievements()
	_profile.stats["perfects"] = 1
	var first: Array[String] = service.evaluate()
	assert_has(first, "first_perfect")
	assert_eq(_rewards.count_for("achievement:first_perfect"), 1, "granted once")
	assert_eq(int(_profile.achievements["first_perfect"]), NOW, "unlock time recorded")
	assert_eq(_unlocked_events.count("first_perfect"), 1, "signal once")
	assert_eq(_profile.stat("achievements_unlocked"), first.size(), "achievements_unlocked counter")
	_profile.stats["perfects"] = 5
	var second: Array[String] = service.evaluate()
	assert_false(second.has("first_perfect"), "not unlocked again")
	assert_eq(_rewards.count_for("achievement:first_perfect"), 1, "still granted once")
	assert_eq(_unlocked_events.count("first_perfect"), 1, "still one signal")
	assert_empty(service.evaluate(), "stable without stat changes")


func test_reward_spec_is_passed_through() -> void:
	var service: AchievementService = _achievements()
	_profile.stats["perfects"] = 1
	service.evaluate()
	var spec: Dictionary = {}
	for call: Dictionary in _rewards.calls:
		if call["source"] == "achievement:first_perfect":
			spec = call["spec"]
	assert_eq(str(spec.get("badge", "")), "badge_first_perfect")
	assert_gt(float(spec.get("coins", 0)), 0.0, "coins in reward")


func test_meta_achievements_unlock_in_same_evaluate() -> void:
	var defs: Array = [
		_def("a", "runs_played", 1),
		_def("b", "runs_played", 2),
		_def("meta", "achievements_unlocked", 2),
		_def("meta_far", "achievements_unlocked", 10),
	]
	var service: AchievementService = _achievements(defs)
	_profile.stats["runs_played"] = 2
	var unlocked: Array[String] = service.evaluate()
	assert_eq(unlocked, ["a", "b", "meta"] as Array[String])
	assert_eq(_profile.stat("achievements_unlocked"), 3)
	assert_eq(service.unlocked_count(), 3)


func test_stat_changed_emitted_for_unlock_counter() -> void:
	var values: Array[int] = []
	_bus.stat_changed.connect(
		func(stat: StringName, value: int) -> void:
			if stat == &"achievements_unlocked":
				values.append(value)
	)
	var service: AchievementService = _achievements([_def("a", "taps", 1), _def("b", "taps", 1)])
	_profile.stats["taps"] = 3
	service.evaluate()
	assert_eq(values, [1, 2] as Array[int])


func test_hidden_excluded_from_list_until_unlocked() -> void:
	var service: AchievementService = _achievements()
	var hidden_total: int = 0
	for d: Dictionary in _shipped_achievements():
		if bool(d["hidden"]):
			hidden_total += 1
	assert_gt(hidden_total, 0, "data has secrets")
	var visible: Array[Dictionary] = service.list(false)
	assert_eq(visible.size(), service.total_count() - hidden_total)
	for entry: Dictionary in visible:
		assert_false(bool(entry["hidden"]), "%s hidden but listed" % entry["id"])
	assert_eq(service.list(true).size(), service.total_count(), "include_hidden lists all")
	assert_eq(service.hidden_locked_count(), hidden_total)
	_profile.stats["zen_runs"] = 1
	service.evaluate()
	var ids: Array[String] = []
	for entry: Dictionary in service.list(false):
		ids.append(str(entry["id"]))
	assert_has(ids, "secret_zen", "unlocked secret is revealed")
	assert_eq(service.hidden_locked_count(), hidden_total - 1)


func test_list_entries_carry_display_fields() -> void:
	var service: AchievementService = _achievements()
	_profile.stats["runs_played"] = 30
	var entry: Dictionary = {}
	for e: Dictionary in service.list(false):
		if e["id"] == "runs_100":
			entry = e
	for key: String in ["name_key", "desc_key", "desc_args", "category", "target", "value", "unlocked", "reward"]:
		assert_has(entry, key, "list field")
	assert_eq(int(entry["value"]), 30)
	assert_eq(int((entry["desc_args"] as Dictionary)["target"]), 100)
	assert_false(bool(entry["unlocked"]))


func test_progress_reports_clamped_values() -> void:
	var service: AchievementService = _achievements()
	_profile.stats["runs_played"] = 50
	var p: Dictionary = service.progress("runs_100")
	assert_eq(int(p["value"]), 50)
	assert_eq(int(p["target"]), 100)
	assert_false(bool(p["unlocked"]))
	assert_eq(int(p["unlocked_at"]), 0)
	_profile.stats["runs_played"] = 150
	assert_eq(int(service.progress("runs_100")["value"]), 100, "clamped to target")
	_clock.set_fixed_unix(NOW + 60)
	service.evaluate()
	p = service.progress("runs_100")
	assert_true(bool(p["unlocked"]))
	assert_eq(int(p["unlocked_at"]), NOW + 60)


func test_progress_for_unknown_id_is_zero() -> void:
	var p: Dictionary = _achievements().progress("does_not_exist")
	assert_eq(int(p["target"]), 0)
	assert_false(bool(p["unlocked"]))


func test_invalid_definitions_reported_and_skipped() -> void:
	var defs: Array = [
		_def("good", "runs_played", 1),
		_def("good", "runs_played", 3),
		_def("bad_stat", "flux_capacity", 1),
		_def("zero_target", "runs_played", 0),
		_def("bad_category", "runs_played", 2, {"category": "weird"}),
		_def("bad_badge", "runs_played", 2, {"reward": {"coins": 5, "badge": "shiny"}}),
		_def("bad_amount", "runs_played", 2, {"reward": {"coins": -5}}),
		_def("fraction", "runs_played", 2.5),
		"not an object",
	]
	var service: AchievementService = _achievements(defs)
	var errors: PackedStringArray = service.validate_definitions(AchievementService.KNOWN_STATS)
	var joined: String = " | ".join(errors)
	for fragment: String in [
		"duplicate id",
		"unknown stat 'flux_capacity'",
		"zero_target: target",
		"unknown category 'weird'",
		"must start with badge_",
		"non-negative",
		"fraction: target",
		"not an object",
	]:
		assert_has(joined, fragment, "validation message")
	# good, bad_category, bad_badge and bad_amount stay usable; the rest are dropped.
	assert_eq(service.total_count(), 4)
	_profile.stats["runs_played"] = 5
	assert_eq(service.evaluate().size(), 4)
	assert_eq(_rewards.count_for("achievement:bad_badge"), 0, "invalid reward is not granted")
	assert_eq(_rewards.count_for("achievement:good"), 1)


func test_float_targets_from_json_are_accepted() -> void:
	var service: AchievementService = _achievements([_def("f", "taps", 5.0)])
	assert_empty(service.validate_definitions(AchievementService.KNOWN_STATS))
	_profile.stats["taps"] = 5
	assert_eq(service.evaluate(), ["f"] as Array[String])


func test_missing_reward_handler_does_not_crash() -> void:
	var service: AchievementService = AchievementService.new(_profile, _bus, _clock, Callable(), [_def("a", "taps", 1)])
	_profile.stats["taps"] = 1
	assert_eq(service.evaluate(), ["a"] as Array[String])
	assert_true(_profile.achievements.has("a"))
	assert_eq(_unlocked_events, ["a"] as Array[String])


func test_preexisting_unlocks_are_not_regranted() -> void:
	_profile.achievements["first_perfect"] = 123
	_profile.stats["perfects"] = 3
	var service: AchievementService = _achievements()
	assert_false(service.evaluate().has("first_perfect"))
	assert_eq(_rewards.count_for("achievement:first_perfect"), 0)
	assert_eq(int(service.progress("first_perfect")["unlocked_at"]), 123)


func test_unlocks_survive_profile_round_trip() -> void:
	var service: AchievementService = _achievements()
	_profile.stats["sparks_collected"] = 150
	service.evaluate()
	var text: String = JSON.stringify(_profile.to_dict())
	var restored: PlayerProfile = PlayerProfile.from_dict(JSON.parse_string(text) as Dictionary)
	var calls_before: int = _rewards.calls.size()
	var again: AchievementService = AchievementService.new(restored, _bus, _clock, _rewards.grant)
	assert_empty(again.evaluate(), "nothing new after reload")
	assert_eq(_rewards.calls.size(), calls_before, "no duplicate rewards after reload")
	assert_true(bool(again.progress("sparks_100")["unlocked"]))
