extends "res://tests/unit/test_meta_fixture.gd"
## MissionService progress and claiming: baselines, claim-once rules, combo
## tracking, progress signals, expiry without penalty and state robustness.


func test_progress_counts_from_baseline() -> void:
	_profile.stats["runs_played"] = 40
	var service: MissionService = _missions(_single_config("runs_played", 5))
	var m: Dictionary = service.active("daily")[0]
	assert_eq(int(m["progress"]), 0, "earlier runs do not count")
	_profile.stats["runs_played"] = 43
	m = service.active("daily")[0]
	assert_eq(int(m["progress"]), 3)
	assert_false(bool(m["complete"]))
	_profile.stats["runs_played"] = 60
	m = service.active("daily")[0]
	assert_eq(int(m["progress"]), 5, "clamped to target")
	assert_true(bool(m["complete"]))


func test_claim_once_only_when_complete() -> void:
	var service: MissionService = _missions(_single_config("runs_played", 5))
	var id: String = str(service.active("daily")[0]["id"])
	_profile.stats["runs_played"] = 4
	assert_true(service.claim(id).is_empty(), "incomplete mission cannot be claimed")
	assert_empty(_rewards.calls)
	assert_empty(_completed_events)
	assert_false(bool(service.active("daily")[0]["claimed"]))
	_profile.stats["runs_played"] = 5
	var bundle: RewardBundle = service.claim(id)
	assert_eq(bundle.amount_of(RewardBundle.TYPE_COINS), 100)
	assert_eq(str(_rewards.calls[0]["source"]), "mission:" + id)
	assert_eq(_completed_events, [id] as Array[String], "mission_completed emitted")
	assert_true(bool(service.active("daily")[0]["claimed"]))
	assert_true(service.claim(id).is_empty(), "second claim is empty")
	assert_eq(_rewards.calls.size(), 1, "granted once")
	assert_eq(_completed_events.size(), 1)


func test_claim_unknown_or_expired_id() -> void:
	var service: MissionService = _missions(_single_config("runs_played", 1))
	var old_id: String = str(service.active("daily")[0]["id"])
	assert_true(service.claim("daily:1999-01-01:nothing").is_empty())
	_profile.stats["runs_played"] = 10
	_clock.set_fixed_unix(NOW + DAY)
	assert_true(service.claim(old_id).is_empty(), "expired mission cannot be claimed")
	assert_empty(_rewards.calls)


func test_expired_missions_carry_no_penalty() -> void:
	_profile.coins = 250
	_profile.stats["runs_played"] = 3
	var service: MissionService = _missions(_single_config("runs_played", 5))
	_profile.stats["runs_played"] = 6
	_clock.set_fixed_unix(NOW + DAY)
	var fresh: Dictionary = service.active("daily")[0]
	assert_eq(_profile.coins, 250, "coins untouched")
	assert_eq(_profile.stat("runs_played"), 6, "stats untouched")
	assert_eq(int(fresh["progress"]), 0, "new mission starts from the current value")
	assert_false(bool(fresh["claimed"]))


func test_combo_mission_via_on_combo_and_bus() -> void:
	var service: MissionService = _missions(_single_config(MissionService.STAT_BEST_COMBO_TODAY, 10))
	service.on_combo(7)
	assert_eq(int(service.active("daily")[0]["progress"]), 7)
	service.on_combo(4)
	assert_eq(int(service.active("daily")[0]["progress"]), 7, "keeps the best combo")
	_bus.combo_reached.emit(12)
	var m: Dictionary = service.active("daily")[0]
	assert_eq(int(m["progress"]), 10)
	assert_true(bool(m["complete"]))
	assert_false(service.claim(str(m["id"])).is_empty(), "combo mission claimable")
	_clock.set_fixed_unix(NOW + DAY)
	assert_eq(int(service.active("daily")[0]["progress"]), 0, "combo best resets with the day")


func test_weekly_combo_keeps_week_best_across_days() -> void:
	var config: Dictionary = {
		"daily_count": 1,
		"weekly_count": 1,
		"daily_templates": [_template("d", MissionService.STAT_BEST_COMBO_TODAY, [10])],
		"weekly_templates": [_template("w", MissionService.STAT_BEST_COMBO_WEEK, [25])],
	}
	var service: MissionService = _missions(config)
	service.on_combo(20)
	_clock.set_fixed_unix(NOW + DAY)
	assert_eq(int(service.active("daily")[0]["progress"]), 0, "new day")
	assert_eq(int(service.active("weekly")[0]["progress"]), 20, "week best kept")
	service.on_combo(26)
	assert_true(bool(service.active("weekly")[0]["complete"]))


func test_mission_progressed_emitted_on_stat_change() -> void:
	var events: Array[Dictionary] = []
	_bus.mission_progressed.connect(
		func(id: String, progress: int, target: int) -> void:
			events.append({"id": id, "progress": progress, "target": target})
	)
	var service: MissionService = _missions(_single_config("runs_played", 5))
	var id: String = str(service.active("daily")[0]["id"])
	_profile.stats["runs_played"] = 2
	_bus.stat_changed.emit(&"runs_played", 2)
	assert_eq(events.size(), 1)
	assert_eq(str(events[0]["id"]), id)
	assert_eq(int(events[0]["progress"]), 2)
	assert_eq(int(events[0]["target"]), 5)
	_bus.stat_changed.emit(&"taps", 9)
	assert_eq(events.size(), 1, "unrelated stats do not announce")
	_bus.stat_changed.emit(&"runs_played", 2)
	assert_eq(events.size(), 1, "unchanged progress is not announced again")


func test_combo_progress_announced_only_when_it_changes() -> void:
	var events: Array[int] = []
	_bus.mission_progressed.connect(func(_id: String, progress: int, _target: int) -> void: events.append(progress))
	var service: MissionService = _missions(_single_config(MissionService.STAT_BEST_COMBO_TODAY, 10))
	service.on_combo(5)
	service.on_combo(4)
	service.on_combo(5)
	assert_eq(events, [5] as Array[int], "no event without a new best")
	for combo: int in range(6, 30):
		service.on_combo(combo)
	assert_eq(events.size(), 6, "6..10 announced, nothing after the mission is complete")
	assert_eq(events[events.size() - 1], 10)


func test_corrupted_state_recovers() -> void:
	_profile.missions["daily"] = "garbage"
	_profile.missions["weekly"] = {"key": _clock.week_key(), "missions": [{"id": 5}]}
	var service: MissionService = _missions(_single_config("runs_played", 5))
	assert_eq(service.active("daily").size(), 1)
	assert_eq(service.active("weekly").size(), 1)
	assert_eq(int(service.active("weekly")[0]["target"]), 30)
	assert_empty(service.active("monthly"), "unknown kind")
	# A slice replaced after construction is checked again, not trusted.
	_profile.missions["daily"] = {"key": _clock.date_key(), "missions": [{"id": 5}]}
	var daily: Array[Dictionary] = service.active("daily")
	assert_eq(daily.size(), 1, "replaced garbage slice reassigned")
	assert_eq(int(daily[0]["target"]), 5)


func test_tampered_stored_reward_is_never_paid() -> void:
	var service: MissionService = _missions(_single_config("runs_played", 1))
	var slice: Dictionary = (_profile.missions["daily"] as Dictionary).duplicate(true)
	var record: Dictionary = (slice["missions"] as Array)[0]
	record["reward"] = {"coins": "lots", "gems": -50}
	_profile.missions["daily"] = slice
	var m: Dictionary = service.active("daily")[0]
	assert_eq(int((m["reward"] as Dictionary)["coins"]), 100, "reward restored from the template")
	assert_false((m["reward"] as Dictionary).has("gems"))
	_profile.stats["runs_played"] = 1
	assert_false(service.claim(str(m["id"])).is_empty())
	assert_eq(int((_rewards.calls[0]["spec"] as Dictionary)["coins"]), 100)


func test_claim_history_prevents_double_payout_after_clock_rollback() -> void:
	var service: MissionService = _missions(_single_config("runs_played", 1))
	var id: String = str(service.active("daily")[0]["id"])
	_profile.stats["runs_played"] = 1
	assert_false(service.claim(id).is_empty())
	_clock.set_fixed_unix(NOW + DAY)
	service.refresh()
	_clock.set_fixed_unix(NOW)
	var m: Dictionary = service.active("daily")[0]
	assert_eq(str(m["id"]), id, "same period, same id")
	assert_true(bool(m["claimed"]), "remembered as claimed")
	_profile.stats["runs_played"] = 5
	assert_true(service.claim(id).is_empty(), "no second payout")
	assert_eq(_rewards.calls.size(), 1)


func test_claimable_count() -> void:
	var service: MissionService = _missions(_single_config("runs_played", 2, "runs_played"))
	assert_eq(service.claimable_count(), 0)
	_profile.stats["runs_played"] = 2
	assert_eq(service.claimable_count(), 1, "daily complete, weekly needs 30")
	service.claim(str(service.active("daily")[0]["id"]))
	assert_eq(service.claimable_count(), 0)


func test_missing_reward_handler_still_marks_claimed() -> void:
	var service: MissionService = MissionService.new(_profile, _bus, _clock, Callable(), _single_config("taps", 1))
	var id: String = str(service.active("daily")[0]["id"])
	_profile.stats["taps"] = 1
	assert_true(service.claim(id).is_empty(), "nothing granted without a handler")
	assert_true(bool(service.active("daily")[0]["claimed"]))
	assert_eq(_completed_events, [id] as Array[String])


func test_state_survives_profile_round_trip() -> void:
	var service: MissionService = _missions(_single_config("runs_played", 5))
	_profile.stats["runs_played"] = 3
	service.on_combo(9)
	var before: Dictionary = service.active("daily")[0]
	var text: String = JSON.stringify(_profile.to_dict())
	var restored: PlayerProfile = PlayerProfile.from_dict(JSON.parse_string(text) as Dictionary)
	var again: MissionService = MissionService.new(
		restored, EventBus.new(), _clock, _rewards.grant, _single_config("runs_played", 5)
	)
	var after: Dictionary = again.active("daily")[0]
	assert_eq(str(after["id"]), str(before["id"]))
	assert_eq(int(after["progress"]), 3, "baseline preserved, no reassignment")
	assert_eq(int((restored.missions["daily"] as Dictionary)["best_combo"]), 9)
	var reward: Dictionary = after["reward"]
	assert_eq(typeof(reward["coins"]), TYPE_INT, "amounts stay whole numbers after a JSON round trip")
	restored.stats["runs_played"] = 8
	assert_false(again.claim(str(after["id"])).is_empty())
	var spec: Dictionary = _rewards.calls[_rewards.calls.size() - 1]["spec"]
	assert_eq(typeof(spec["coins"]), TYPE_INT, "granted spec uses int amounts")
	assert_eq(int(spec["coins"]), 100)
