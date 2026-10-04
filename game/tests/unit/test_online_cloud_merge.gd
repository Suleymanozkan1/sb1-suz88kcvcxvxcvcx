extends TestCase
## ProfileMerge: every cloud-save merge rule on its own, the three-way wallet
## merge (with a base, without one, rebuilt for an older save, from a push
## whose answer was lost; repeats of once-per-account events), idempotence and
## independence from the argument order for the union / maximum rules.

const LOCAL_ID: String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const REMOTE_ID: String = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const OLDER: int = 1790000000
const NEWER: int = 1790000500
const DAY: int = 86400
const STARTING: Dictionary = {"coins": 100, "gems": 0}
const DEVICE: String = "0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f"


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
		"results":
		{
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


func _merged() -> Dictionary:
	return ProfileMerge.merge(_clean(_local()), _clean(_remote()), NEWER)


## [param p] (to_dict shape) recording [param base] (a profile) as the wallet
## and ledger it last shared with the cloud.
static func _with_base(p: Dictionary, base: PlayerProfile) -> Dictionary:
	var out: Dictionary = p.duplicate(true)
	var flags: Dictionary = out["flags"] as Dictionary
	flags[ProfileMerge.FLAG_BASE] = {"coins": base.coins, "gems": base.gems, "bonus_stars": base.bonus_stars}
	flags[ProfileMerge.FLAG_BASE_LEDGER] = WalletMerge.ledger_ids(base.ledger)
	return out


## A copy of [param p] with [param coins] more (or fewer) coins, logged.
static func _coins(p: PlayerProfile, delta: int, source: String, at: int) -> PlayerProfile:
	var out: PlayerProfile = PlayerProfile.from_dict(p.to_dict())
	out.coins += delta
	out.ledger.append({"t": at, "c": "coins", "d": delta, "s": source, "b": out.coins})
	return out


## The wallet both devices last shared: 200 coins, 4 gems, 1 bonus star.
static func _shared() -> PlayerProfile:
	var p: PlayerProfile = PlayerProfile.new()
	p.install_id = LOCAL_ID
	p.created_at = 500
	p.coins = 200
	p.gems = 4
	p.bonus_stars = 1
	p.ledger.append({"t": 1000, "c": "coins", "d": 200, "s": "level:w01_l01", "b": 200})
	p.ledger.append({"t": 1000, "c": "gems", "d": 4, "s": "achievement:first_clear", "b": 4})
	return p


static func _wallet(m: Dictionary) -> Array[int]:
	return [int(m["coins"]), int(m["gems"]), int(m["bonus_stars"])]


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
	var no_time: Dictionary = ProfileMerge.merge(untimed, timed, NEWER)
	assert_near(float(((no_time["levels"] as Dictionary)["x"] as Dictionary)["best_time"]), 9.5, 0.0001, "0 = no time")


func test_unions_and_maximums() -> void:
	var m: Dictionary = _merged()
	assert_eq(m["unlocked_worlds"], ["neon_core", "cloud_factory"], "local order, then remote-only worlds")
	assert_eq(m["cosmetics_owned"], ["core_plasma", "core_fire", "trail_flame"])
	assert_eq(m["purchases"], ["pack_inferno", "theme_pack_midnight"])
	assert_eq(int(m["xp"]), 500, "max xp")
	assert_eq(int(m["player_level"]), 5, "max level")
	assert_eq(m["stats"], {"runs_played": 10, "max_combo": 9, "zen_runs": 3}, "max per stat")
	assert_eq(int(m["created_at"]), 900, "earliest creation time")


func test_achievements_keep_the_earliest_unlock() -> void:
	var achievements: Dictionary = _merged()["achievements"] as Dictionary
	assert_eq(achievements, {"first_clear": 1100, "combo_10": 1300, "zen_first": 1700})
	var unknown_time: Dictionary = ProfileMerge.merge({"achievements": {"a": 0}}, {"achievements": {"a": 50}}, NEWER)
	assert_eq(int((unknown_time["achievements"] as Dictionary)["a"]), 50, "a missing time never wins")


func test_wallet_applies_both_sides_changes_since_the_base() -> void:
	var shared: PlayerProfile = _shared()
	var mine: PlayerProfile = _coins(_coins(shared, -50, "cosmetic:core_fire", 2000), 30, "level:w01_l02", 2100)
	mine.cosmetics_owned.append("core_fire")
	var theirs: PlayerProfile = _coins(shared, 500, "level:w02_l01", 1500)
	theirs.install_id = REMOTE_ID
	theirs.gems += 6
	theirs.ledger.append({"t": 1600, "c": "gems", "d": 6, "s": "achievement:combo_10", "b": theirs.gems})
	theirs.bonus_stars += 2
	var local: Dictionary = _with_base(_clean(mine), shared)
	var remote: Dictionary = _with_base(_clean(theirs), shared)
	var m: Dictionary = ProfileMerge.merge(local, remote, NEWER)
	assert_eq(_wallet(m), [680, 10, 3], "remote + (local - base) for each currency and the bonus stars")
	assert_eq(_wallet(ProfileMerge.merge(remote, local, NEWER)), [680, 10, 3], "the other device gets the same")
	var coin_balances: Array = []
	for raw: Variant in m["ledger"] as Array:
		if str((raw as Dictionary)["c"]) == "coins":
			coin_balances.append(int((raw as Dictionary)["b"]))
	assert_eq(coin_balances, [200, 700, 650, 680], "both histories by time, balances recomputed")
	assert_empty(IntegrityMonitor.new(PlayerProfile.from_dict(m)).check(), "the newest entries match the wallet")
	var flags: Dictionary = m["flags"] as Dictionary
	var new_base: Dictionary = {"coins": 700, "gems": 10, "bonus_stars": 3}
	assert_eq(flags[ProfileMerge.FLAG_BASE], new_base, "the cloud copy is the new base")
	assert_eq(flags[ProfileMerge.FLAG_BASE_LEDGER], WalletMerge.ledger_ids(remote["ledger"]))
	var drained: PlayerProfile = _coins(shared, -200, "cosmetic:core_ice", 2000)
	var overdrawn: PlayerProfile = _coins(shared, -150, "cosmetic:trail_ice", 2000)
	var clamped: Dictionary = ProfileMerge.merge(
		_with_base(_clean(drained), shared), _with_base(_clean(overdrawn), shared), NEWER
	)
	assert_eq(int(clamped["coins"]), 0, "two spends of more than the wallet clamp at 0")
	assert_empty(IntegrityMonitor.new(PlayerProfile.from_dict(clamped)).check(), "a cloud_sync entry records the clamp")


func test_a_device_that_never_synced_adds_only_what_it_earned() -> void:
	var remote: Dictionary = _clean(_remote())
	var fresh: PlayerProfile = PlayerProfile.create_new(OLDER)
	fresh.install_id = LOCAL_ID
	fresh = _coins(fresh, 100, EconomyService.STARTING_SOURCE, OLDER)
	var pristine: Dictionary = ProfileMerge.merge(_clean(fresh), remote, NEWER, STARTING)
	assert_eq(_wallet(pristine), [5000, 40, 3], "a starting balance never replaces or reduces a real wallet")
	assert_eq(pristine["ledger"], remote["ledger"], "nor shows up in its ledger")
	var played: PlayerProfile = _coins(fresh, 60, "level:w01_l01", OLDER + 10)
	played.gems = 1
	played.bonus_stars = 1
	var m: Dictionary = ProfileMerge.merge(_clean(played), remote, NEWER, STARTING)
	assert_eq(_wallet(m), [5060, 41, 4], "what it earned beyond the starting balance is added")
	assert_empty(IntegrityMonitor.new(PlayerProfile.from_dict(m)).check())
	var spent: PlayerProfile = _coins(fresh, -60, "cosmetic:core_fire", OLDER + 10)
	var kept: Dictionary = ProfileMerge.merge(_clean(spent), remote, NEWER, STARTING)
	assert_eq(_wallet(kept), [5000, 40, 3], "spending the starting balance never reduces the account wallet")


func test_a_save_synced_before_bases_rebuilds_its_base_from_the_ledger() -> void:
	var shared: PlayerProfile = _shared()
	var local: Dictionary = _clean(_coins(shared, 50, "level:w01_l02", 2000))
	(local["flags"] as Dictionary)[CloudSaveService.FLAG_REVISION] = "r4"
	(local["flags"] as Dictionary)[CloudSaveService.FLAG_SYNCED_AT] = 1500
	var theirs: PlayerProfile = _coins(shared, 500, "level:w02_l01", 1800)
	theirs.install_id = REMOTE_ID
	var m: Dictionary = ProfileMerge.merge(local, _clean(theirs), NEWER)
	assert_eq(_wallet(m), [750, 4, 1], "entries after its last sync are its changes")


func test_a_push_whose_answer_was_lost_is_never_counted_twice() -> void:
	var shared: PlayerProfile = _shared()
	var pushed: PlayerProfile = _coins(shared, 1000, "level:w02_l01", 2000)
	var local: Dictionary = _with_base(_clean(_coins(pushed, 50, "level:w02_l02", 2100)), shared)
	var flags: Dictionary = local["flags"] as Dictionary
	flags[ProfileMerge.FLAG_DEVICE] = DEVICE
	flags[ProfileMerge.FLAG_PENDING] = {"seq": 3, "coins": 1200, "gems": 4, "bonus_stars": 1}
	flags[ProfileMerge.FLAG_PENDING_LEDGER] = WalletMerge.ledger_ids(pushed.ledger)
	flags[ProfileMerge.FLAG_PUSHES] = {DEVICE: 3}
	var merged_there: PlayerProfile = _coins(pushed, 10, "level:w01_l05", 2050)
	merged_there.install_id = REMOTE_ID
	merged_there.flags[ProfileMerge.FLAG_PUSHES] = {DEVICE: 3, "other": 7}
	var m: Dictionary = ProfileMerge.merge(local, _clean(merged_there), NEWER)
	assert_eq(int(m["coins"]), 1260, "the stored push counts once: its 1000, then 50 here and 10 there")
	var settled: Dictionary = m["flags"] as Dictionary
	assert_false(settled.has(ProfileMerge.FLAG_PENDING), "the push is settled")
	assert_eq(settled[ProfileMerge.FLAG_PUSHES], {DEVICE: 3, "other": 7}, "push counts merge by maximum")
	var without: PlayerProfile = _coins(shared, 10, "level:w01_l05", 2050)
	without.install_id = REMOTE_ID
	without.flags[ProfileMerge.FLAG_PUSHES] = {DEVICE: 2}
	var m2: Dictionary = ProfileMerge.merge(local, _clean(without), NEWER)
	assert_eq(int(m2["coins"]), 1260, "a copy without the push gets all of this device's 1050")
	assert_true((m2["flags"] as Dictionary).has(ProfileMerge.FLAG_PENDING), "the push may still arrive")


func test_once_per_account_and_once_per_day_rewards_count_once() -> void:
	var shared: PlayerProfile = _shared()
	var day: int = 20700 * DAY
	var mine: PlayerProfile = _coins(shared, 30, "bonus_chest", day + 100)
	mine = _coins(mine, 100, "level_up:5", day + 200)
	mine = _coins(mine, 40, "level:w01_l03", day + 300)
	mine = _coins(mine, -300, "cosmetic:core_fire", day + 400)
	mine = _coins(mine, 25, "mission:daily:2026-09-23:a", day + 500)
	mine.cosmetics_owned.append("core_fire")
	var theirs: PlayerProfile = _coins(shared, 30, "bonus_chest", day + 7000)
	theirs.install_id = REMOTE_ID
	theirs.player_level = 5
	theirs.cosmetics_owned.append("core_fire")
	theirs.missions = {MissionService.HISTORY_KEY: ["daily:2026-09-23:a"]}
	var remote: Dictionary = _with_base(_clean(theirs), shared)
	var m: Dictionary = ProfileMerge.merge(_with_base(_clean(mine), shared), remote, NEWER)
	assert_eq(int(m["coins"]), 230 + 40, "only the level earning is new: chest, level-up, item and mission are not")
	assert_empty(IntegrityMonitor.new(PlayerProfile.from_dict(m)).check())
	var tomorrow: PlayerProfile = _coins(shared, 30, "bonus_chest", day + DAY + 5)
	var next_day: Dictionary = ProfileMerge.merge(_with_base(_clean(tomorrow), shared), remote, NEWER)
	assert_eq(int(next_day["coins"]), 260, "a chest of another day counts")


func test_device_local_fields_stay_local() -> void:
	var m: Dictionary = _merged()
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
	var pushes: Dictionary = ProfileMerge.merge_flags(
		{"sync.pushes": {"a": 3, "b": 1}}, {"sync.pushes": {"b": 4, "c": 1}}
	)
	assert_eq(pushes["sync.pushes"], {"a": 3, "b": 4, "c": 1}, "push counts per device by maximum")
	var ahead: Dictionary = ProfileMerge.merge_flags({"bonus_chest_day": 10}, {"bonus_chest_day": 30}, 20)
	assert_eq(int(ahead["bonus_chest_day"]), 10, "never a day after today")
	assert_false(ProfileMerge.merge_flags({}, {"bonus_chest_day": 30}, 20).has("bonus_chest_day"), "not even alone")
	assert_eq(
		int(ProfileMerge.merge_flags({"bonus_chest_day": 10}, {"bonus_chest_day": 20}, 20)["bonus_chest_day"]), 20
	)


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
	var ahead: Dictionary = ProfileMerge.merge_daily(
		{"last_day": 50, "streak": 4, "tier": 4}, {"last_day": 60, "streak": 9, "tier": 7, "streak_best": 9}, 52
	)
	assert_eq(int(ahead["last_day"]), 50, "a day beyond today plus the grace is never adopted")
	assert_eq(int(ahead["streak"]), 4)
	assert_eq(int(ahead["streak_best"]), 9)
	var only_ahead: Dictionary = ProfileMerge.merge_daily({}, {"last_day": 60, "streak": 9}, 52)
	assert_false(only_ahead.has("last_day") or only_ahead.has("streak"), "not even when this device has none")


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
	for p: PlayerProfile in [_local(), _remote(), PlayerProfile.new(), _shared()]:
		var a: Dictionary = _clean(p)
		var once: Dictionary = ProfileMerge.merge(a, a, NEWER, STARTING)
		var content: String = JsonIO.canonical(ProfileMerge.travelling(a))
		assert_eq(JsonIO.canonical(ProfileMerge.travelling(once)), content, "merge(a, a) keeps all of a")
		var twice: Dictionary = ProfileMerge.merge(once, once, NEWER, STARTING)
		assert_eq(JsonIO.canonical(twice), JsonIO.canonical(once), "merge(a, a) == a once a's base is its own")
		var applied: Dictionary = PlayerProfile.from_dict(once).to_dict()
		assert_eq(JsonIO.canonical(applied), JsonIO.canonical(once), "and survives sanitising")
	var m: Dictionary = _merged()
	var again: Dictionary = ProfileMerge.merge(m, _clean(_remote()), NEWER)
	assert_eq(JsonIO.canonical(again), JsonIO.canonical(m), "merging the same remote twice changes nothing")
	var shared: PlayerProfile = _shared()
	var mine: Dictionary = _with_base(_clean(_coins(shared, 70, "level:w01_l02", 2000)), shared)
	var theirs: Dictionary = _with_base(_clean(_coins(shared, -90, "cosmetic:core_ice", 1900)), shared)
	var first: Dictionary = ProfileMerge.merge(mine, theirs, NEWER)
	var second: Dictionary = ProfileMerge.merge(first, theirs, NEWER + 60)
	assert_eq(JsonIO.canonical(second), JsonIO.canonical(first), "with a base too, the wallet and its ledger")
	assert_eq(int(first["coins"]), 180)


## Review R-6 idem.gd: profiles that never synced, merged with themselves,
## twice with the same copy and in both orders.
func test_unsynced_profiles_merge_idempotently_and_in_any_order() -> void:
	var a: Dictionary = _clean(_seeded(1))
	var b: Dictionary = _clean(_seeded(2))
	var aa: Dictionary = ProfileMerge.merge(a, a, NEWER)
	assert_eq(JsonIO.canonical(ProfileMerge.travelling(aa)), JsonIO.canonical(ProfileMerge.travelling(a)))
	var ab: Dictionary = ProfileMerge.merge(a, b, NEWER)
	var ab2: Dictionary = ProfileMerge.merge(ab, b, NEWER)
	assert_eq(JsonIO.canonical(ab2), JsonIO.canonical(ab), "merge(merge(a, b), b) == merge(a, b)")
	var ba: Dictionary = ProfileMerge.merge(b, a, NEWER)
	for key: String in ["levels", "stats", "achievements", "bonus_stars", "xp", "daily"]:
		assert_eq(JsonIO.canonical({"v": ab[key]}), JsonIO.canonical({"v": ba[key]}), "%s is order-independent" % key)
	assert_eq(int(ab["bonus_stars"]), 3, "stars earned on two unsynced devices add up")


static func _seeded(seed: int) -> PlayerProfile:
	var p: PlayerProfile = PlayerProfile.create_new(OLDER - 1000 * seed)
	p.coins = 100 * seed
	p.xp = 7 * seed
	p.bonus_stars = seed
	p.levels["w01_l01"] = _record(seed % 4, 10 * seed, seed % 2 == 0, seed, seed + 1, seed, 10.0 + seed)
	p.levels["w01_l0%d" % (seed + 1)] = _record(1, 5, false, 1, 1, 1, 0.0)
	p.stats["runs_played"] = seed * 3
	p.achievements["a%d" % seed] = OLDER - seed
	p.achievements["shared"] = OLDER - 100 * seed
	p.cosmetics_owned.append("c%d" % seed)
	p.missions = {
		"daily": _period("2026-09-28", seed, [_mission("m1", seed == 1), _mission("m2", seed == 2)]),
		"claimed_ids": ["x%d" % seed],
	}
	p.daily = {
		"results": {"2026-09-27": _daily_result(seed * 10, true, seed, 1, OLDER - seed, seed)},
		"streak": seed,
		"tier": seed,
		"last_day": 20000 + seed,
		"streak_best": seed,
	}
	p.flags["mode_best"] = {"endless": seed * 100}
	p.flags["bonus_chest_day"] = 20000 + seed
	return p


func test_union_and_max_rules_ignore_argument_order() -> void:
	var a: Dictionary = _clean(_local())
	var b: Dictionary = _clean(_remote())
	var ab: Dictionary = ProfileMerge.merge(a, b, NEWER)
	var ba: Dictionary = ProfileMerge.merge(b, a, NEWER)
	for key: String in ["levels", "stats", "achievements", "xp", "player_level", "created_at"]:
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
