extends TestCase
## ReplayVerifier.verify_reward_claim: plausibility of server-side reward claims.

const DATE: String = "2026-10-03"
const NOON: int = 12 * 3600
const SECONDS_PER_DAY: int = 86400

var _clock: GameClock
var _verifier: ReplayVerifier
var _day: int = 0


func before_each() -> void:
	_day = DailyChallengeService.day_for_date_key(DATE)
	_clock = GameClock.new()
	_clock.set_fixed_unix(_day * SECONDS_PER_DAY + NOON)
	_verifier = ReplayVerifier.new(_clock, DailyChallengeService.load_config())


func _daily_claim(tier: int, coins: int = 100) -> Dictionary:
	return {"type": "daily", "date_key": DATE, "tier": tier, "deltas": {"coins": coins, "xp": 50}}


func _history(verified: Array, daily_claims: Variant = {}, level_claims: Array = []) -> Dictionary:
	return {"verified_completions": verified, "daily_claims": daily_claims, "level_claims": level_claims}


func test_valid_daily_claim() -> void:
	var verdict: Dictionary = _verifier.verify_reward_claim(_daily_claim(1), _history(["daily_" + DATE]))
	assert_true(bool(verdict["valid"]), str(verdict["reasons"]))
	assert_eq(int(verdict["allowed_tier"]), 1)


func test_rejects_duplicate_daily_claim() -> void:
	var as_dict: Dictionary = _verifier.verify_reward_claim(_daily_claim(1), _history(["daily_" + DATE], {DATE: 1}))
	assert_has(as_dict["reasons"], ReplayVerifier.CLAIM_DUPLICATE_DAILY)
	var as_list: Dictionary = _verifier.verify_reward_claim(_daily_claim(1), _history(["daily_" + DATE], [DATE]))
	assert_has(as_list["reasons"], ReplayVerifier.CLAIM_DUPLICATE_DAILY, "list form of history")


func test_rejects_claims_for_unverified_completions() -> void:
	var daily: Dictionary = _verifier.verify_reward_claim(_daily_claim(1), _history([]))
	assert_has(daily["reasons"], ReplayVerifier.CLAIM_LEVEL_NOT_VERIFIED)
	var level_claim: Dictionary = {
		"type": "level", "level_id": "w02_l07", "first_clear": true, "deltas": {"coins": 120}
	}
	var unverified: Dictionary = _verifier.verify_reward_claim(level_claim, _history(["w02_l06"]))
	assert_has(unverified["reasons"], ReplayVerifier.CLAIM_LEVEL_NOT_VERIFIED)
	assert_true(bool(_verifier.verify_reward_claim(level_claim, _history(["w02_l07"]))["valid"]), "verified level ok")
	var again: Dictionary = _verifier.verify_reward_claim(level_claim, _history(["w02_l07"], {}, ["w02_l07"]))
	assert_has(again["reasons"], ReplayVerifier.CLAIM_DUPLICATE_LEVEL)
	var replay_claim: Dictionary = level_claim.duplicate(true)
	replay_claim["first_clear"] = false
	assert_true(bool(_verifier.verify_reward_claim(replay_claim, _history(["w02_l07"], {}, ["w02_l07"]))["valid"]))
	for odd: Variant in [null, "yes", 1]:
		var odd_claim: Dictionary = level_claim.duplicate(true)
		odd_claim["first_clear"] = odd
		var verdict: Dictionary = _verifier.verify_reward_claim(odd_claim, _history(["w02_l07"], {}, ["w02_l07"]))
		assert_true(verdict.has("valid"), "non-boolean first_clear %s handled" % str(odd))
		assert_true(bool(verdict["valid"]), "only a JSON true is a first-clear claim")


func test_rejects_impossible_currency_deltas() -> void:
	var history: Dictionary = _history(["daily_" + DATE])
	var cases: Dictionary = {
		ReplayVerifier.CLAIM_IMPOSSIBLE_DELTA: {"coins": 999999},
		ReplayVerifier.CLAIM_NEGATIVE_DELTA: {"gems": -5},
		ReplayVerifier.CLAIM_UNKNOWN_CURRENCY: {"diamonds": 1},
		ReplayVerifier.CLAIM_INVALID_DELTA: {"coins": 1.5},
	}
	for reason: Variant in cases:
		var claim: Dictionary = _daily_claim(1)
		claim["deltas"] = cases[reason]
		var verdict: Dictionary = _verifier.verify_reward_claim(claim, history)
		assert_false(bool(verdict["valid"]), str(reason))
		assert_has(verdict["reasons"], reason)
	var not_a_dict: Dictionary = _daily_claim(1)
	not_a_dict["deltas"] = [100]
	assert_has(_verifier.verify_reward_claim(not_a_dict, history)["reasons"], ReplayVerifier.CLAIM_INVALID_DELTA)
	var at_cap: Dictionary = _daily_claim(1)
	at_cap["deltas"] = {"coins": 2500, "gems": 25, "xp": 2000}
	assert_true(bool(_verifier.verify_reward_claim(at_cap, history)["valid"]), "caps are inclusive")


func test_rejects_unknown_claim_type_and_bad_dates() -> void:
	var unknown: Dictionary = _verifier.verify_reward_claim({"type": "lottery"}, {})
	assert_eq(unknown["reasons"], PackedStringArray([ReplayVerifier.CLAIM_UNKNOWN_TYPE]))
	var bad_date: Dictionary = _daily_claim(1)
	bad_date["date_key"] = "2026-02-30"
	assert_has(_verifier.verify_reward_claim(bad_date, {})["reasons"], ReplayVerifier.CLAIM_INVALID)
	var old: Dictionary = _daily_claim(1)
	old["date_key"] = GameClock.date_key_for_day(_day - 5)
	var old_history: Dictionary = _history(["daily_" + str(old["date_key"])])
	assert_has(_verifier.verify_reward_claim(old, old_history)["reasons"], ReplayVerifier.CLAIM_STALE)
	var future: Dictionary = _daily_claim(1)
	future["date_key"] = GameClock.date_key_for_day(_day + 1)
	var future_history: Dictionary = _history(["daily_" + str(future["date_key"])])
	assert_has(_verifier.verify_reward_claim(future, future_history)["reasons"], ReplayVerifier.CLAIM_FUTURE)


func test_daily_tier_is_clamped_to_claim_history() -> void:
	var streak: Dictionary = {}
	for k: int in range(1, 5):
		streak[GameClock.date_key_for_day(_day - k)] = 5 - k
	var history: Dictionary = _history(["daily_" + DATE], streak)
	assert_eq(_verifier.plausible_tier(streak.keys(), _day), 5, "four consecutive claims then today")
	var fair: Dictionary = _verifier.verify_reward_claim(_daily_claim(5), history)
	assert_true(bool(fair["valid"]))
	assert_eq(int(fair["allowed_tier"]), 5)
	var greedy: Dictionary = _verifier.verify_reward_claim(_daily_claim(7), history)
	assert_true(bool(greedy["valid"]), "not rejected: offline play is never punished")
	assert_eq(int(greedy["allowed_tier"]), 5, "clamped to what the history supports")
	var absurd: Dictionary = _verifier.verify_reward_claim(_daily_claim(9), history)
	assert_has(absurd["reasons"], ReplayVerifier.CLAIM_IMPLAUSIBLE_TIER)


func test_plausible_tier_applies_gentle_decay() -> void:
	var dates: Array = []
	for k: int in range(2, 7):
		dates.append(GameClock.date_key_for_day(_day - k))
	assert_eq(_verifier.plausible_tier(dates, _day), 4, "five-day streak, one missed day -> 4")
	assert_eq(_verifier.plausible_tier([], _day), 1, "no history -> tier 1")
	assert_eq(_verifier.plausible_tier(["garbage", DATE], _day), 1, "invalid and same-day dates ignored")
