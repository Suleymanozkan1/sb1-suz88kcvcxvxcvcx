extends TestCase
## ProfileMerge: every cloud-save merge rule on its own, idempotence and
## independence from the argument order for the union / maximum rules.

const LOCAL_ID: String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const REMOTE_ID: String = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const OLDER: int = 1790000000
const NEWER: int = 1790000500


func _local() -> PlayerProfile:
	var p: PlayerProfile = PlayerProfile.new()
	p.install_id = LOCAL_ID
	p.created_at = 1000
	p.coins = 300
	p.gems = 4
	p.ledger.append({"t": 1500, "c": "coins", "d": 300, "s": "level:w01_l01", "b": 300})
	p.xp = 500
	p.player_level = 4
	p.bonus_stars = 1
	p.levels = {
		"w01_l01": _record(2, 1000, false, 2, 5, 9, 20.5),
		"w01_l02": _record(1, 400, false, 1, 1, 3, 0.0),
	}
	p.stats = {"runs_played": 10, "max_combo": 9}
	p.cosmetics_owned.assign(["core_plasma", "core_fire"])
	p.cosmetics_equipped = {"core_skin": "core_fire"}
	p.achievements = {"first_clear": 1200, "combo_10": 1300}
	p.missions = {
		"daily": _period("2026-10-04", 4, [_mission("daily:2026-10-04:a", false), _mission("daily:2026-10-04:b")]),
		"weekly": _period("2026-W40", 6, [_mission("weekly:2026-W40:a", false)]),
		"claimed_ids": ["daily:2026-10-04:b"],
	}
	p.daily = {
		"results": {"2026-10-03": _daily_result(500, true, 2, 1, 1400, 2)},
		"streak": 2,
		"streak_best": 3,
		"tier": 2,
		"last_day": 20364,
		"boards": {"alltime:classic": {"entries": [], "updated": 0}},
	}
	p.settings["sound"] = false
	p.purchases.assign(["pack_inferno"])
	p.flags = {
		"tutorial_done": true,
		"mode_best": {"endless": 100, "zen": 5},
		"bonus_chest_day": 20360,
		"last_level": "w01_l02",
		"cloud.revision": "r1",
	}
	p.pending_submissions.append({"kind": "leaderboard", "id": "local-run"})
	return p


func _remote() -> PlayerProfile:
	var p: PlayerProfile = PlayerProfile.new()
	p.install_id = REMOTE_ID
	p.created_at = 900
	p.coins = 5000
	p.gems = 40
	p.ledger.append({"t": 1600, "c": "coins", "d": 5000, "s": "daily_streak:3", "b": 5000})
	p.xp = 450
	p.player_level = 5
	p.bonus_stars = 3
	p.levels = {
		"w01_l01": _record(3, 900, true, 1, 2, 12, 18.0),
		"w02_l01": _record(2, 700, false, 1, 4, 6, 30.0),
	}
	p.unlocked_worlds.assign(["neon_core", "cloud_factory"])
	p.stats = {"runs_played": 7, "zen_runs": 3}
	p.cosmetics_owned.assign(["core_plasma", "trail_flame"])
	p.cosmetics_equipped = {"core_skin": "core_plasma"}
	p.achievements = {"first_clear": 1100, "zen_first": 1700}
	p.missions = {
		"daily": _period("2026-10-04", 7, [_mission("daily:2026-10-04:a"), _mission("daily:2026-10-04:b", false)]),
		"weekly": _period("2026-W41", 0, [_mission("weekly:2026-W41:c", false)]),
		"claimed_ids": ["daily:2026-10-04:a"],
	}
	p.daily = {
		"results": {
			"2026-10-03": _daily_result(650, true, 1, 1, 1350, 2),
			"2026-10-04": _daily_result(300, true, 1, 1, 1800, 3),
		},
		"streak": 3,
		"streak_best": 3,
		"tier": 3,
		"last_day": 20365,
	}
	p.settings["sound"] = true
	p.purchases.assign(["theme_pack_midnight"])
	p.flags = {
		"tutorial_done": false,
		"mode_best": {"endless": 80, "time_attack": 40},
		"bonus_chest_day": 20365,
		"notifications.daily_day": 20365,
		"cloud.revision": "r9",
		"cloud.dirty": true,
	}
	p.pending_submissions.append({"kind": "leaderboard", "id": "remote-run"})
	return p


static func _record(
	stars: int, score: int, perfect: bool, clears: int, attempts: int, combo: int, time: float
) -> Dictionary:
	return {
		"stars": stars,
		"best_score": score,
		"perfect": perfect,
		"clears": clears,
		"attempts": attempts,
		"best_combo": combo,
		"best_time": time,
	}


static func _mission(id: String, claimed: bool = true) -> Dictionary:
	var reward: Dictionary = {"coins": 20}
	return {"id": id, "stat": "runs_played", "target": 3, "baseline": 0, "claimed": claimed, "reward": reward}


static func _period(key: String, best_combo: int, missions: Array) -> Dictionary:
	return {"key": key, "assigned_at": 1000, "best_combo": best_combo, "missions": missions}


static func _daily_result(
	best: int, completed: bool, attempts: int, completions: int, at: int, tier: int
) -> Dictionary:
	return {
		"best": best,
		"completed": completed,
		"attempts": attempts,
		"completions": completions,
		"first_completed_at": at,
		"tier": tier,
	}


## Sanitised dictionaries after a save round trip, exactly what the cloud
## service merges.
static func _clean(p: PlayerProfile) -> Dictionary:
	var decoded: Dictionary = SaveService.decode(SaveService.encode(p, OLDER))
	return PlayerProfile.from_dict(decoded["payload"] as Dictionary).to_dict()


func _merged(local_time: int = NEWER, remote_time: int = OLDER) -> Dictionary:
	return ProfileMerge.merge(_clean(_local()), _clean(_remote()), local_time, remote_time)


static func _sorted(list: Variant) -> Array:
	var out: Array = (list as Array).duplicate()
	out.sort()
	return out


func test_levels_keep_the_best_of_both() -> void:
	var levels: Dictionary = _merged()["levels"] as Dictionary
	assert_eq(_sorted(levels.keys()), ["w01_l01", "w01_l02", "w02_l01"], "union of level records")
	var both: Dictionary = levels["w01_l01"] as Dictionary
	assert_eq(int(both["stars"]), 3, "max stars")
	assert_eq(int(both["best_score"]), 1000, "max score")
	assert_true(bool(both["perfect"]), "perfect on either side")
	assert_eq(int(both["clears"]), 2)
	assert_eq(int(both["attempts"]), 5)
	assert_eq(int(both["best_combo"]), 12)
	assert_near(float(both["best_time"]), 18.0, 0.0001, "smaller positive time")
	var untimed: Dictionary = {"levels": {"x": _record(1, 1, false, 1, 1, 1, 0.0)}}
	var timed: Dictionary = {"levels": {"x": _record(1, 1, false, 1, 1, 1, 9.5)}}
	var no_time: Dictionary = ProfileMerge.merge(untimed, timed, 0, 0)
	assert_near(float(((no_time["levels"] as Dictionary)["x"] as Dictionary)["best_time"]), 9.5, 0.0001, "0 = no time")


func test_unions_and_maximums() -> void:
	var m: Dictionary = _merged()
	assert_eq(m["unlocked_worlds"], ["neon_core", "cloud_factory"], "local order, then remote-only worlds")
	assert_eq(m["cosmetics_owned"], ["core_plasma", "core_fire", "trail_flame"])
	assert_eq(m["purchases"], ["pack_inferno", "theme_pack_midnight"])
	assert_eq(int(m["xp"]), 500, "max xp")
	assert_eq(int(m["player_level"]), 5, "max level")
	assert_eq(int(m["bonus_stars"]), 3, "max bonus stars")
	assert_eq(m["stats"], {"runs_played": 10, "max_combo": 9, "zen_runs": 3}, "max per stat")
	assert_eq(int(m["created_at"]), 900, "earliest creation time")


func test_achievements_keep_the_earliest_unlock() -> void:
	var achievements: Dictionary = _merged()["achievements"] as Dictionary
	assert_eq(achievements, {"first_clear": 1100, "combo_10": 1300, "zen_first": 1700})
	var unknown_time: Dictionary = ProfileMerge.merge({"achievements": {"a": 0}}, {"achievements": {"a": 50}}, 0, 0)
	assert_eq(int((unknown_time["achievements"] as Dictionary)["a"]), 50, "a missing time never wins")


func test_wallet_comes_whole_from_the_newer_save() -> void:
	var local_newer: Dictionary = _merged(NEWER, OLDER)
	assert_eq(int(local_newer["coins"]), 300)
	assert_eq(int(local_newer["gems"]), 4)
	assert_eq(str(((local_newer["ledger"] as Array)[0] as Dictionary)["s"]), "level:w01_l01", "ledger with its wallet")
	var remote_newer: Dictionary = _merged(OLDER, NEWER)
	assert_eq(int(remote_newer["coins"]), 5000, "never summed")
	assert_eq(int(remote_newer["gems"]), 40)
	assert_eq(str(((remote_newer["ledger"] as Array)[0] as Dictionary)["s"]), "daily_streak:3")
	var tie: Dictionary = _merged(OLDER, OLDER)
	assert_eq(int(tie["coins"]), 300, "a tie keeps the local wallet")
	var restored: PlayerProfile = PlayerProfile.from_dict(remote_newer)
	assert_empty(IntegrityMonitor.new(restored).check(), "the wallet still matches its ledger")


func test_device_local_fields_stay_local() -> void:
	var m: Dictionary = _merged(OLDER, NEWER)
	assert_eq(str(m["install_id"]), LOCAL_ID)
	assert_eq(m["cosmetics_equipped"], {"core_skin": "core_fire"})
	assert_false(bool((m["settings"] as Dictionary)["sound"]), "settings stay local")
	assert_eq((m["pending_submissions"] as Array).size(), 1)
	assert_eq(str(((m["pending_submissions"] as Array)[0] as Dictionary)["id"]), "local-run", "no remote queue")
	var boards: Dictionary = (m["daily"] as Dictionary)["boards"] as Dictionary
	assert_true(boards.has("alltime:classic"), "personal boards kept")


func test_flags_local_wins_except_bests() -> void:
	var flags: Dictionary = _merged()["flags"] as Dictionary
	assert_true(bool(flags["tutorial_done"]), "local wins")
	assert_eq(str(flags["last_level"]), "w01_l02")
	assert_eq(int(flags["notifications.daily_day"]), 20365, "remote-only flags adopted")
	assert_eq(flags["mode_best"], {"endless": 100, "zen": 5, "time_attack": 40}, "best per mode")
	assert_eq(int(flags["bonus_chest_day"]), 20365, "one chest a day across devices")
	assert_eq(str(flags["cloud.revision"]), "r1", "this device's cloud bookkeeping")
	assert_false(flags.has("cloud.dirty"), "the other device's cloud flags are never adopted")


func test_daily_keeps_better_results_and_the_later_streak() -> void:
	var daily: Dictionary = _merged()["daily"] as Dictionary
	var results: Dictionary = daily["results"] as Dictionary
	assert_eq(_sorted(results.keys()), ["2026-10-03", "2026-10-04"])
	var both: Dictionary = results["2026-10-03"] as Dictionary
	assert_eq(int(both["best"]), 650, "better score")
	assert_eq(int(both["attempts"]), 2)
	assert_eq(int(both["first_completed_at"]), 1350, "earliest completion")
	assert_true(bool(both["completed"]))
	assert_eq(int(daily["last_day"]), 20365, "streak fields from the later side")
	assert_eq(int(daily["streak"]), 3)
	assert_eq(int(daily["tier"]), 3)
	assert_eq(int(daily["streak_best"]), 3)
	var older_remote: Dictionary = ProfileMerge.merge_daily(
		{"last_day": 50, "streak": 4, "tier": 4, "streak_best": 4}, {"last_day": 40, "streak": 9, "streak_best": 9}
	)
	assert_eq(int(older_remote["streak"]), 4, "the earlier side's streak is not taken")
	assert_eq(int(older_remote["streak_best"]), 9, "but the longest streak is kept")


func test_missions_never_pay_twice() -> void:
	var missions: Dictionary = _merged()["missions"] as Dictionary
	var daily: Dictionary = missions["daily"] as Dictionary
	assert_eq(int(daily["best_combo"]), 7)
	for raw: Variant in daily["missions"] as Array:
		assert_true(bool((raw as Dictionary)["claimed"]), "%s claimed on either side" % str((raw as Dictionary)["id"]))
	assert_eq(str((missions["weekly"] as Dictionary)["key"]), "2026-W41", "the later week's slice")
	assert_eq(_sorted(missions["claimed_ids"]), ["daily:2026-10-04:a", "daily:2026-10-04:b"])
	var long_history: Array = []
	for i: int in MissionService.CLAIM_HISTORY_LIMIT:
		long_history.append("old:%d" % i)
	var bounded: Dictionary = ProfileMerge.merge_missions({"claimed_ids": long_history}, {"claimed_ids": ["new"]})
	assert_eq((bounded["claimed_ids"] as Array).size(), MissionService.CLAIM_HISTORY_LIMIT, "history stays bounded")
	assert_eq(str((bounded["claimed_ids"] as Array).back()), "new")


func test_merge_is_idempotent() -> void:
	for p: PlayerProfile in [_local(), _remote(), PlayerProfile.new()]:
		var a: Dictionary = _clean(p)
		var once: Dictionary = ProfileMerge.merge(a, a, OLDER, OLDER)
		assert_eq(JsonIO.canonical(once), JsonIO.canonical(a), "merge(a, a) == a")
		var applied: Dictionary = PlayerProfile.from_dict(once).to_dict()
		assert_eq(JsonIO.canonical(applied), JsonIO.canonical(a), "and survives sanitising")
	var m: Dictionary = _merged()
	var again: Dictionary = ProfileMerge.merge(m, _clean(_remote()), NEWER, OLDER)
	assert_eq(JsonIO.canonical(again), JsonIO.canonical(m), "merging the same remote twice changes nothing")


func test_union_and_max_rules_ignore_argument_order() -> void:
	var a: Dictionary = _clean(_local())
	var b: Dictionary = _clean(_remote())
	var ab: Dictionary = ProfileMerge.merge(a, b, OLDER, OLDER)
	var ba: Dictionary = ProfileMerge.merge(b, a, OLDER, OLDER)
	for key: String in ["levels", "stats", "achievements", "xp", "player_level", "bonus_stars", "created_at"]:
		assert_eq(JsonIO.canonical(ab[key]), JsonIO.canonical(ba[key]), "%s is order-independent" % key)
	for key2: String in ["unlocked_worlds", "cosmetics_owned", "purchases"]:
		assert_eq(_sorted(ab[key2]), _sorted(ba[key2]), "%s is the same set" % key2)
	var mode_ab: Dictionary = (ab["flags"] as Dictionary)["mode_best"] as Dictionary
	var mode_ba: Dictionary = (ba["flags"] as Dictionary)["mode_best"] as Dictionary
	assert_eq(JsonIO.canonical(mode_ab), JsonIO.canonical(mode_ba), "mode bests")
	var results_ab: Variant = (ab["daily"] as Dictionary)["results"]
	var results_ba: Variant = (ba["daily"] as Dictionary)["results"]
	assert_eq(JsonIO.canonical(results_ab), JsonIO.canonical(results_ba), "daily results")
	assert_false(ProfileMerge.has_progress(_clean(PlayerProfile.new())), "a fresh profile has no history")
	assert_true(ProfileMerge.has_progress(a))
