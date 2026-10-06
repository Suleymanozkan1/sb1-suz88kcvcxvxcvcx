extends "res://tests/unit/test_meta_fixture.gd"
## MissionService scheduling: shipped config, deterministic assignment, daily
## and weekly resets, honest countdowns, content gating and reward scaling.


func _signature(missions: Array[Dictionary]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for m: Dictionary in missions:
		parts.append("%s=%d" % [m["template"], int(m["target"])])
	return ",".join(parts)


func _templates_with(kind_templates: Array[Dictionary], stat: String, target: int) -> bool:
	for t: Dictionary in kind_templates:
		if t["stat"] == stat and (t["targets"] as Array).has(target):
			return true
	return false


func test_shipped_config_is_valid() -> void:
	var service: MissionService = _missions()
	var errors: PackedStringArray = service.validate_config(AchievementService.KNOWN_STATS)
	assert_empty(errors, "config errors: %s" % "; ".join(errors))
	assert_eq(service.mission_count("daily"), 3)
	assert_eq(service.mission_count("weekly"), 3)
	assert_ge(service.templates("daily").size(), 10, "daily templates")
	assert_ge(service.templates("weekly").size(), 8, "weekly templates")


func test_required_templates_present() -> void:
	var service: MissionService = _missions()
	var daily: Array[Dictionary] = service.templates("daily")
	var weekly: Array[Dictionary] = service.templates("weekly")
	assert_true(_templates_with(daily, "runs_played", 5), "play 5 levels")
	assert_true(_templates_with(daily, "perfects", 3), "get 3 perfects")
	assert_true(_templates_with(daily, "sparks_collected", 100), "collect 100 energy")
	assert_true(_templates_with(daily, MissionService.STAT_BEST_COMBO_TODAY, 10), "reach x10 combo")
	assert_true(_templates_with(daily, "damage_free_clears", 1), "finish without damage")
	assert_true(_templates_with(weekly, "levels_cleared", 30), "clear 30 levels")
	assert_true(_templates_with(weekly, "perfects", 15), "15 perfects")
	assert_true(_templates_with(weekly, "sparks_collected", 2000), "2000 sparks")
	assert_true(_templates_with(weekly, "daily_completed", 5), "5 dailies")
	assert_true(_templates_with(weekly, "bosses_cleared", 1), "beat a boss")


func test_assigns_distinct_missions_per_kind() -> void:
	var service: MissionService = _missions()
	for kind: String in ["daily", "weekly"]:
		var missions: Array[Dictionary] = service.active(kind)
		assert_eq(missions.size(), 3, "%s count" % kind)
		var templates: Dictionary = {}
		var stats: Dictionary = {}
		for m: Dictionary in missions:
			templates[m["template"]] = true
			stats[m["stat"]] = true
			assert_eq(int(m["progress"]), 0, "fresh progress")
			assert_false(bool(m["complete"]))
			assert_false(bool(m["claimed"]))
			assert_has(str(m["id"]), kind + ":")
		assert_eq(templates.size(), 3, "%s distinct templates" % kind)
		assert_eq(stats.size(), 3, "%s distinct stats" % kind)


func test_same_date_gives_same_missions() -> void:
	var daily: String = _signature(_missions().active("daily"))
	var weekly: String = _signature(_missions().active("weekly"))
	var other: MissionService = _missions_for_new_player()
	assert_eq(_signature(other.active("daily")), daily, "same date, same daily set")
	assert_eq(_signature(other.active("weekly")), weekly, "same week, same weekly set")
	_clock.set_fixed_unix(NOW + 3600)
	assert_eq(_signature(_missions_for_new_player().active("daily")), daily, "time of day does not matter")


func test_different_dates_generally_differ() -> void:
	var signatures: Dictionary = {}
	for i: int in 14:
		_clock.set_fixed_unix(MONDAY + i * DAY)
		signatures[_signature(_missions_for_new_player().active("daily"))] = true
	assert_ge(signatures.size(), 10, "14 days should give mostly different sets")


func test_daily_resets_at_utc_midnight_weekly_keeps() -> void:
	_clock.set_fixed_unix(MONDAY + 3 * DAY - 1)  # Wednesday 23:59:59
	var service: MissionService = _missions()
	var daily_ids: Array[String] = []
	for m: Dictionary in service.active("daily"):
		daily_ids.append(str(m["id"]))
		assert_has(str(m["id"]), "2026-10-07")
	var weekly_before: String = str(service.active("weekly")[0]["id"])
	_clock.set_fixed_unix(MONDAY + 3 * DAY)  # Thursday 00:00:00
	assert_true(service.refresh(), "refresh reports a change")
	for m: Dictionary in service.active("daily"):
		assert_false(daily_ids.has(str(m["id"])), "new daily ids")
		assert_has(str(m["id"]), "2026-10-08")
	assert_eq(str(service.active("weekly")[0]["id"]), weekly_before, "weekly unchanged mid-week")
	assert_false(service.refresh(), "no change within the same day")


func test_weekly_resets_on_monday() -> void:
	_clock.set_fixed_unix(MONDAY + 7 * DAY - 1)  # Sunday 23:59:59
	var service: MissionService = _missions()
	var before: Array[Dictionary] = service.active("weekly")
	assert_has(str(before[0]["id"]), "2026-W41")
	_clock.set_fixed_unix(MONDAY + 7 * DAY)
	var after: Array[Dictionary] = service.active("weekly")
	assert_has(str(after[0]["id"]), "2026-W42")
	assert_ne(str(after[0]["id"]), str(before[0]["id"]))


func test_time_left_matches_daily_reset_boundary() -> void:
	for offset: int in [0, 1, 3600, 43200, DAY - 1]:
		var t: int = MONDAY + offset
		_clock.set_fixed_unix(t)
		var service: MissionService = _missions(_single_config("runs_played", 5))
		var left: int = service.time_left_seconds("daily")
		assert_ge(left, 1, "daily left positive")
		assert_le(left, DAY, "daily left within a day")
		var key: String = service.period_key("daily")
		_clock.set_fixed_unix(t + left - 1)
		assert_eq(service.period_key("daily"), key, "same day one second before reset")
		assert_false(service.refresh(), "nothing resets early")
		_clock.set_fixed_unix(t + left)
		assert_ne(service.period_key("daily"), key, "new day exactly at reset")
		assert_true(service.refresh(), "missions reset at the reported time")


func test_time_left_matches_weekly_reset_boundary() -> void:
	for offset: int in [0, 1, DAY + 5, 3 * DAY + 7200, 7 * DAY - 1]:
		var t: int = MONDAY + offset
		_clock.set_fixed_unix(t)
		var service: MissionService = _missions(_single_config("runs_played", 5))
		var left: int = service.time_left_seconds("weekly")
		assert_ge(left, 1)
		assert_le(left, 7 * DAY)
		var key: String = service.period_key("weekly")
		_clock.set_fixed_unix(t + left - 1)
		assert_eq(service.period_key("weekly"), key, "same week one second before reset")
		_clock.set_fixed_unix(t + left)
		assert_ne(service.period_key("weekly"), key, "new week exactly at reset")
	assert_eq(_missions().time_left_seconds("monthly"), 0, "unknown kind")


func test_run_started_assigns_new_period_before_run_counts() -> void:
	var service: MissionService = _missions(_single_config("runs_played", 1))
	_clock.set_fixed_unix(NOW + DAY)
	_bus.run_started.emit("w01_l01", &"classic")
	_profile.stats["runs_played"] = 1
	assert_true(bool(service.active("daily")[0]["complete"]), "run after the reset counts")


func test_requires_gates_templates() -> void:
	var config: Dictionary = {
		"daily_count": 2,
		"weekly_count": 1,
		"daily_templates":
		[
			_template("basic", "runs_played", [5]),
			_template("portals", "portals_used", [3], {"requires": {"stat": "unique_levels_cleared", "min": 240}}),
		],
		"weekly_templates": [_template("w", "levels_cleared", [30])],
	}
	var fresh: Array[Dictionary] = _missions(config).active("daily")
	assert_eq(fresh.size(), 1, "gated template not offered to new players")
	assert_eq(str(fresh[0]["template"]), "basic")
	var veteran_profile: PlayerProfile = PlayerProfile.create_new(NOW)
	veteran_profile.stats["unique_levels_cleared"] = 300
	var veteran: MissionService = MissionService.new(veteran_profile, EventBus.new(), _clock, _rewards.grant, config)
	assert_eq(veteran.active("daily").size(), 2, "veteran gets both")


func test_shipped_config_never_offers_locked_content_to_new_players() -> void:
	var gated: Dictionary = {}
	var service: MissionService = _missions()
	for kind: String in MissionService.KINDS:
		for t: Dictionary in service.templates(kind):
			if not (t["requires"] as Dictionary).is_empty():
				gated[t["id"]] = true
	assert_gt(gated.size(), 0, "data gates advanced templates")
	for i: int in 30:
		_clock.set_fixed_unix(MONDAY + i * DAY)
		var s: MissionService = _missions_for_new_player()
		for kind: String in MissionService.KINDS:
			for m: Dictionary in s.active(kind):
				assert_false(gated.has(m["template"]), "day %d offered gated %s" % [i, m["template"]])


func test_daily_cap_keeps_weekly_targets_reachable() -> void:
	var config: Dictionary = {
		"daily_count": 1,
		"weekly_count": 2,
		"daily_templates": [_template("d", "runs_played", [5])],
		"weekly_templates":
		[
			_template("dailies", "daily_completed", [3, 5], {"daily_cap": 1}),
			_template("w", "levels_cleared", [30]),
		],
	}
	# Days left in the ISO week, today included: Mon 7 ... Sun 1.
	for week: int in 4:
		for weekday: int in 7:
			var days_left: int = 7 - weekday
			_clock.set_fixed_unix(MONDAY + (week * 7 + weekday) * DAY + (week % 2) * 23 * 3600)
			var dailies: Dictionary = {}
			for m: Dictionary in _missions_for_new_player(config).active("weekly"):
				if m["template"] == "dailies":
					dailies = m
			if days_left < 3:
				assert_true(dailies.is_empty(), "weekday %d: unreachable template not offered" % weekday)
				continue
			assert_false(dailies.is_empty(), "weekday %d: reachable template offered" % weekday)
			assert_le(float(dailies["target"]), float(days_left), "weekday %d target reachable" % weekday)
			if int(dailies["target"]) == 3:
				assert_eq(int((dailies["reward"] as Dictionary)["coins"]), 100, "reward matches the lower target")


func test_shipped_weekly_dailies_are_always_reachable() -> void:
	for i: int in 28:
		_clock.set_fixed_unix(MONDAY + i * DAY)
		var days_left: int = 7 - i % 7
		var veteran_profile: PlayerProfile = PlayerProfile.create_new(NOW)
		veteran_profile.stats["unique_levels_cleared"] = 520
		var service: MissionService = MissionService.new(veteran_profile, EventBus.new(), _clock, _rewards.grant)
		for m: Dictionary in service.active("weekly"):
			if m["stat"] == "daily_completed":
				assert_le(float(m["target"]), float(days_left), "day %d: %s" % [i, m["id"]])


func test_reward_scales_with_target_index() -> void:
	var targets: Array[int] = [5, 10, 20]
	var config: Dictionary = _single_config("runs_played", 5)
	config["daily_templates"] = [_template("d", "runs_played", targets, {"reward": {"coins": 100, "gems": 1}})]
	config["reward_scaling"] = {"step_per_target_index": 0.5, "keys": ["coins"]}
	for i: int in 10:
		_clock.set_fixed_unix(MONDAY + i * DAY)
		var m: Dictionary = _missions_for_new_player(config).active("daily")[0]
		var index: int = targets.find(int(m["target"]))
		assert_ge(index, 0, "target from template")
		var reward: Dictionary = m["reward"]
		assert_eq(int(reward["coins"]), roundi(100.0 * (1.0 + 0.5 * index)))
		assert_eq(int(reward["gems"]), 1, "gems are not scaled")


func test_invalid_config_is_safe_and_reported() -> void:
	var config: Dictionary = {
		"daily_count": "three",
		"weekly_count": 99,
		"daily_templates":
		[
			{"id": ""},
			5,
			_template("max_stat", "max_combo", [10]),
			_template("wrong_combo", MissionService.STAT_BEST_COMBO_WEEK, [10]),
			_template("no_targets", "runs_played", []),
			_template("bad_reward", "runs_played", [5], {"reward": {"coins": "lots"}}),
			_template("unknown", "flux_capacity", [5]),
			_template("bad_cap", "runs_played", [5], {"daily_cap": 0}),
			_template("ok", "runs_played", [5]),
			_template("ok", "taps", [50]),
		],
		"weekly_templates": "nope",
	}
	var service: MissionService = _missions(config)
	var joined: String = " | ".join(service.validate_config(AchievementService.KNOWN_STATS))
	for fragment: String in [
		"daily_count",
		"weekly_count",
		"missing id",
		"not an object",
		"is a maximum",
		"does not belong to daily",
		"targets must be a non-empty array",
		"reward coins",
		"unknown stat 'flux_capacity'",
		"daily_cap must be a positive integer",
		"duplicate id 'ok'",
		"weekly_templates must be an array",
	]:
		assert_has(joined, fragment, "validation message")
	var daily: Array[Dictionary] = service.active("daily")
	assert_eq(daily.size(), 1, "only the valid template is used")
	assert_eq(str(daily[0]["template"]), "ok")
	assert_empty(service.active("weekly"), "no weekly templates, no crash")


func test_missing_config_file_is_safe() -> void:
	assert_empty(MissionService.load_config("res://data/missions/missing.json"))
	var service: MissionService = _missions({"daily_count": 3})
	assert_empty(service.active("daily"), "no templates, no missions")
	assert_eq(service.claimable_count(), 0)
