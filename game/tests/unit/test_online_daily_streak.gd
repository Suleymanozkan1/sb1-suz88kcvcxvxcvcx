extends TestCase
## Daily challenge results: first-completion reward, best score, gentle
## streak / tier decay, status and honest personal rank.

const SECONDS_PER_DAY: int = 86400
const NOON: int = 12 * 3600
const BASE_DATE: String = "2026-10-03"


## Test double for the reward_grant callable: records every spec it receives
## and returns a bundle describing what it granted.
class RecordingRewardGrant:
	extends RefCounted
	var calls: Array[Dictionary] = []

	func grant(spec: Dictionary) -> RewardBundle:
		calls.append(spec.duplicate())
		var bundle: RewardBundle = RewardBundle.new("daily")
		bundle.add(RewardBundle.TYPE_COINS, 40 * int(spec.get("tier", 1)))
		return bundle


var _clock: GameClock
var _profile: PlayerProfile
var _bus: EventBus
var _grant: RecordingRewardGrant
var _catalog: WorldCatalog
var _completed_events: Array[String] = []


func before_each() -> void:
	_clock = GameClock.new()
	_profile = PlayerProfile.new()
	_bus = EventBus.new()
	_grant = RecordingRewardGrant.new()
	_catalog = WorldCatalog.load_default()
	_completed_events.clear()
	_bus.daily_completed.connect(_on_daily_completed)


func _on_daily_completed(date_key: String, _score: int) -> void:
	_completed_events.append(date_key)


func _service() -> DailyChallengeService:
	return DailyChallengeService.new(_profile, _bus, _clock, _catalog, _grant.grant)


func _set_day(day: int) -> void:
	_clock.set_fixed_unix(day * SECONDS_PER_DAY + NOON)


func _base_day() -> int:
	return DailyChallengeService.day_for_date_key(BASE_DATE)


func _daily_result(date_key: String, completed: bool, score: int) -> RunResult:
	var r: RunResult = RunResult.new()
	r.level_id = DailyChallengeService.ID_PREFIX + date_key
	r.mode = DailyChallengeService.MODE
	r.completed = completed
	r.score = score
	return r


## Completes today's daily on each of [param days] (epoch day numbers).
func _complete_days(svc: DailyChallengeService, days: Array) -> Dictionary:
	var last: Dictionary = {}
	for raw: Variant in days:
		var day: int = int(raw)
		_set_day(day)
		last = svc.record_result(_daily_result(GameClock.date_key_for_day(day), true, 1000 + day % 100))
	return last


# --- results, rewards and streak -----------------------------------------------------


func test_first_completion_rewarded_once() -> void:
	var svc: DailyChallengeService = _service()
	_set_day(_base_day())
	var first: Dictionary = svc.record_result(_daily_result(BASE_DATE, true, 1200))
	assert_true(bool(first["first_completion"]))
	assert_true(bool(first["best"]))
	assert_eq(int(first["tier"]), 1)
	assert_eq(int(first["streak"]), 1)
	assert_eq((first["reward"] as RewardBundle).amount_of(RewardBundle.TYPE_COINS), 40)
	assert_eq(_grant.calls.size(), 1)
	assert_eq(str(_grant.calls[0]["table"]), "daily_streak")
	assert_eq(int(_grant.calls[0]["tier"]), 1)
	var second: Dictionary = svc.record_result(_daily_result(BASE_DATE, true, 1500))
	assert_false(bool(second["first_completion"]))
	assert_true((second["reward"] as RewardBundle).is_empty(), "no second reward")
	assert_eq(_grant.calls.size(), 1, "reward_grant called once")
	assert_eq(_completed_events.size(), 1, "daily_completed emitted once")
	assert_eq(_completed_events[0], BASE_DATE)


func test_best_score_kept() -> void:
	var svc: DailyChallengeService = _service()
	_set_day(_base_day())
	svc.record_result(_daily_result(BASE_DATE, true, 1200))
	var better: Dictionary = svc.record_result(_daily_result(BASE_DATE, true, 1800))
	assert_true(bool(better["best"]))
	var worse: Dictionary = svc.record_result(_daily_result(BASE_DATE, true, 900))
	assert_false(bool(worse["best"]))
	var failed: Dictionary = svc.record_result(_daily_result(BASE_DATE, false, 5000))
	assert_false(bool(failed["best"]), "failed runs never set the best")
	var status: Dictionary = svc.status()
	assert_eq(int(status["best_score"]), 1800)
	assert_eq(int(((_profile.daily["results"] as Dictionary)[BASE_DATE] as Dictionary)["attempts"]), 4)


func test_failed_run_counts_as_played_without_reward() -> void:
	var svc: DailyChallengeService = _service()
	_set_day(_base_day())
	var out: Dictionary = svc.record_result(_daily_result(BASE_DATE, false, 300))
	assert_false(bool(out["first_completion"]))
	assert_true((out["reward"] as RewardBundle).is_empty())
	assert_empty(_grant.calls)
	var status: Dictionary = svc.status()
	assert_true(bool(status["played"]))
	assert_false(bool(status["completed"]))
	assert_eq(int(status["streak"]), 0)


func test_streak_increments_on_consecutive_days() -> void:
	var svc: DailyChallengeService = _service()
	var d: int = _base_day()
	for i: int in 3:
		var out: Dictionary = _complete_days(svc, [d + i])
		assert_eq(int(out["streak"]), i + 1, "streak day %d" % i)
		assert_eq(int(out["tier"]), i + 1, "tier day %d" % i)
	assert_eq(_grant.calls.size(), 3)
	assert_eq(int(_grant.calls[2]["tier"]), 3)
	assert_eq(int(_profile.daily["streak_best"]), 3)


func test_tier_capped_at_seven() -> void:
	var svc: DailyChallengeService = _service()
	var d: int = _base_day()
	var days: Array = []
	for i: int in 10:
		days.append(d + i)
	var out: Dictionary = _complete_days(svc, days)
	assert_eq(int(out["tier"]), 7, "capped")
	assert_eq(int(out["streak"]), 10, "streak counter keeps counting")
	assert_eq(int(_grant.calls[_grant.calls.size() - 1]["tier"]), 7)


func test_missed_day_decays_tier_gently() -> void:
	var svc: DailyChallengeService = _service()
	var d: int = _base_day()
	_complete_days(svc, [d, d + 1, d + 2, d + 3, d + 4])
	assert_eq(int(_profile.daily["tier"]), 5)
	# Day d+5 fully missed; the status during the gap shows the decayed tier.
	_set_day(d + 6)
	var gap_status: Dictionary = svc.status()
	assert_eq(int(gap_status["streak"]), 0, "display streak restarts after a miss")
	assert_eq(int(gap_status["tier"]), 4, "held tier decays by one")
	assert_eq(int(gap_status["next_tier"]), 4, "completing today pays tier 4")
	var out: Dictionary = svc.record_result(_daily_result(GameClock.date_key_for_day(d + 6), true, 900))
	assert_eq(int(out["tier"]), 4, "tier 5 -> 4 after one missed day, not reset to 1")
	assert_eq(int(out["streak"]), 1, "display streak restarted")
	assert_eq(int(_grant.calls[_grant.calls.size() - 1]["tier"]), 4)
	var next: Dictionary = _complete_days(svc, [d + 7])
	assert_eq(int(next["tier"]), 5, "climbs again from the decayed tier")


func test_several_missed_days_never_go_below_one() -> void:
	var svc: DailyChallengeService = _service()
	var d: int = _base_day()
	_complete_days(svc, [d, d + 1, d + 2, d + 3, d + 4])
	var after_three: Dictionary = _complete_days(svc, [d + 8])
	assert_eq(int(after_three["tier"]), 2, "5 - 3 missed days")
	var after_long_break: Dictionary = _complete_days(svc, [d + 30])
	assert_eq(int(after_long_break["tier"]), 1, "floored at 1")


func test_tier_after_rule() -> void:
	assert_eq(DailyChallengeService.tier_after(0, -1, 100), 1, "first ever")
	assert_eq(DailyChallengeService.tier_after(3, 99, 100), 4, "consecutive")
	assert_eq(DailyChallengeService.tier_after(7, 99, 100), 7, "cap")
	assert_eq(DailyChallengeService.tier_after(5, 98, 100), 4, "one miss")
	assert_eq(DailyChallengeService.tier_after(5, 95, 100), 1, "four misses")
	assert_eq(DailyChallengeService.tier_after(4, 100, 100), 4, "same day")
	var custom: Dictionary = {"min_tier": 2, "max_tier": 5, "decay_per_missed_day": 2}
	assert_eq(DailyChallengeService.tier_after(5, 97, 100, custom), 2, "custom decay floored at min")


func test_status_next_tier_after_completion_today() -> void:
	var svc: DailyChallengeService = _service()
	var d: int = _base_day()
	_set_day(d)
	var before: Dictionary = svc.status()
	assert_eq(int(before["tier"]), 0, "no tier yet")
	assert_eq(int(before["next_tier"]), 1)
	assert_false(bool(before["played"]))
	assert_eq(str(before["date_key"]), BASE_DATE)
	assert_eq(int(before["seconds_to_reset"]), SECONDS_PER_DAY - NOON)
	_complete_days(svc, [d, d + 1])
	var after: Dictionary = svc.status()
	assert_true(bool(after["completed"]))
	assert_eq(int(after["tier"]), 2)
	assert_eq(int(after["next_tier"]), 3, "tomorrow pays one more")
	assert_eq(int(after["streak"]), 2)
	assert_true(str(after["difficulty_key"]).begins_with("online.daily.difficulty."))


func test_runs_outside_window_or_not_daily_are_ignored() -> void:
	var svc: DailyChallengeService = _service()
	var d: int = _base_day()
	_set_day(d)
	var old: Dictionary = svc.record_result(_daily_result(GameClock.date_key_for_day(d - 3), true, 999))
	assert_false(bool(old["first_completion"]), "old daily ignored")
	var future: Dictionary = svc.record_result(_daily_result(GameClock.date_key_for_day(d + 1), true, 999))
	assert_false(bool(future["first_completion"]), "future daily ignored")
	var campaign: RunResult = _daily_result(BASE_DATE, true, 999)
	campaign.level_id = "w01_l05"
	assert_false(bool(svc.record_result(campaign)["first_completion"]), "campaign run ignored")
	assert_false(bool(svc.record_result(null)["first_completion"]), "null tolerated")
	assert_empty(_grant.calls)


func test_run_crossing_midnight_still_counts_for_its_date() -> void:
	var svc: DailyChallengeService = _service()
	var d: int = _base_day()
	_set_day(d + 1)
	var out: Dictionary = svc.record_result(_daily_result(BASE_DATE, true, 777))
	assert_true(bool(out["first_completion"]), "yesterday's daily within grace window")
	assert_eq(_grant.calls.size(), 1)


func test_corrupted_daily_slice_is_tolerated() -> void:
	_profile.daily = {"results": "garbage", "tier": "x", "last_day": [], "streak": null}
	var svc: DailyChallengeService = _service()
	_set_day(_base_day())
	var out: Dictionary = svc.record_result(_daily_result(BASE_DATE, true, 500))
	assert_true(bool(out["first_completion"]))
	assert_eq(int(out["tier"]), 1)
	assert_eq(typeof(_profile.daily["results"]), TYPE_DICTIONARY)


func test_state_survives_profile_round_trip() -> void:
	var svc: DailyChallengeService = _service()
	var d: int = _base_day()
	_complete_days(svc, [d, d + 1, d + 2])
	var json: String = JsonIO.canonical(_profile.to_dict())
	_profile = PlayerProfile.from_dict(JSON.parse_string(json) as Dictionary)
	var reloaded: DailyChallengeService = _service()
	var out: Dictionary = _complete_days(reloaded, [d + 3])
	assert_eq(int(out["tier"]), 4, "streak continues after save/load")
	assert_eq(int(out["streak"]), 4)


func test_history_is_bounded() -> void:
	var svc: DailyChallengeService = _service()
	var d: int = _base_day()
	var days: Array = []
	for i: int in 70:
		days.append(d + i)
	_complete_days(svc, days)
	var results: Dictionary = _profile.daily["results"] as Dictionary
	assert_eq(results.size(), 60)
	assert_false(results.has(GameClock.date_key_for_day(d)), "oldest pruned")
	assert_true(results.has(GameClock.date_key_for_day(d + 69)), "newest kept")


func test_rank_text_local_is_honest() -> void:
	var svc: DailyChallengeService = _service()
	var d: int = _base_day()
	_set_day(d)
	var first: Dictionary = svc.rank_text_local(500)
	assert_eq(str(first["key"]), "online.rank.first_daily")
	assert_eq(int(first["rank"]), 1)
	assert_eq(int(first["total"]), 1)
	for pair: Vector2i in [Vector2i(d - 3, 3000), Vector2i(d - 2, 6000), Vector2i(d - 1, 4000)]:
		_set_day(pair.x)
		svc.record_result(_daily_result(GameClock.date_key_for_day(pair.x), true, pair.y))
	_set_day(d)
	var mid: Dictionary = svc.rank_text_local(5000)
	assert_eq(int(mid["rank"]), 2, "only 6000 is better")
	assert_eq(int(mid["total"]), 4, "three past dailies plus today")
	assert_eq(str(mid["key"]), "online.rank.personal")
	assert_eq(str(mid["source"]), "local")
	var top: Dictionary = svc.rank_text_local(7000)
	assert_true(bool(top["is_best"]))
	assert_eq(str(top["key"]), "online.rank.personal_best")


func test_missing_reward_callable_is_safe() -> void:
	var svc: DailyChallengeService = DailyChallengeService.new(_profile, _bus, _clock, _catalog, Callable())
	_set_day(_base_day())
	var out: Dictionary = svc.record_result(_daily_result(BASE_DATE, true, 100))
	assert_true(bool(out["first_completion"]))
	assert_true((out["reward"] as RewardBundle).is_empty(), "no invented reward")
