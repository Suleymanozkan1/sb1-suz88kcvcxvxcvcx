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


## Deltas within the tier-1 streak reward (so every tier accepts them).
func _daily_claim(tier: int, coins: int = 20) -> Dictionary:
	return {"type": "daily", "date_key": DATE, "tier": tier, "deltas": {"coins": coins, "xp": 10}}


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
	var level_claim: Dictionary = {"type": "level", "level_id": "w02_l07", "first_clear": true, "deltas": {"coins": 30}}
	var unverified: Dictionary = _verifier.verify_reward_claim(level_claim, _history(["w02_l06"]))
	assert_has(unverified["reasons"], ReplayVerifier.CLAIM_LEVEL_NOT_VERIFIED)
	assert_true(bool(_verifier.verify_reward_claim(level_claim, _history(["w02_l07"]))["valid"]), "verified level ok")
	var again: Dictionary = _verifier.verify_reward_claim(level_claim, _history(["w02_l07"], {}, ["w02_l07"]))
	assert_has(again["reasons"], ReplayVerifier.CLAIM_DUPLICATE_LEVEL)
	var replay_claim: Dictionary = level_claim.duplicate(true)
	replay_claim["first_clear"] = false
	var two_runs: Dictionary = _history(["w02_l07", "w02_l07"], {}, ["w02_l07"])
	assert_true(bool(_verifier.verify_reward_claim(replay_claim, two_runs)["valid"]), "second run, second claim")
	for odd: Variant in [null, "yes", 1]:
		var odd_claim: Dictionary = level_claim.duplicate(true)
		odd_claim["first_clear"] = odd
		var verdict: Dictionary = _verifier.verify_reward_claim(odd_claim, two_runs)
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
	var at_cap: Dictionary = {
		"type": "level", "level_id": "w02_l07", "first_clear": true, "deltas": {"coins": 5000, "gems": 50, "xp": 5000}
	}
	var capped: Dictionary = _verifier.verify_reward_claim(at_cap, _history(["w02_l07"]))
	assert_has(capped["reasons"], ReplayVerifier.CLAIM_IMPOSSIBLE_DELTA, "global caps are not what a level pays")


## Reward claims bound currencies only: bonus stars, skins and trails are not
## something a client may claim, so such deltas are refused as unknown.
func test_rejects_star_skin_and_trail_deltas() -> void:
	var history: Dictionary = _history(["daily_" + DATE, "w02_l07"])
	for deltas: Dictionary in [{"stars": 1}, {"skin": "core_shadow"}, {"trail": 1}, {"coins": 10, "stars": 3}]:
		var daily: Dictionary = _daily_claim(1)
		daily["deltas"] = deltas
		var verdict: Dictionary = _verifier.verify_reward_claim(daily, history)
		assert_false(bool(verdict["valid"]), "daily %s" % str(deltas))
		assert_has(verdict["reasons"], ReplayVerifier.CLAIM_UNKNOWN_CURRENCY)
		var level: Dictionary = {"type": "level", "level_id": "w02_l07", "first_clear": true, "deltas": deltas}
		var level_verdict: Dictionary = _verifier.verify_reward_claim(level, history)
		assert_has(level_verdict["reasons"], ReplayVerifier.CLAIM_UNKNOWN_CURRENCY, "level %s" % str(deltas))


func test_level_claim_is_bounded_by_what_the_level_pays() -> void:
	var level: Dictionary = LevelRepository.new().load_level("w03_l52")
	var tables: Dictionary = RewardEngine.load_tables()
	var first: Dictionary = RewardEngine.level_reward_ceiling(tables, str(level["tier"]), str(level["kind"]), true)
	var claim: Dictionary = {
		"type": "level",
		"level_id": "w03_l52",
		"first_clear": true,
		"deltas": {"coins": int(first["coins"]) * 2, "gems": int(first["gems"]) * 2, "xp": int(first["xp"])}
	}
	var history: Dictionary = _history(["w03_l52"])
	assert_true(bool(_verifier.verify_reward_claim(claim, history)["valid"]), "boss first clear, ad-doubled")
	claim["deltas"] = {"coins": int(first["coins"]) * 2 + 1}
	assert_has(_verifier.verify_reward_claim(claim, history)["reasons"], ReplayVerifier.CLAIM_IMPOSSIBLE_DELTA)
	var replay: Dictionary = RewardEngine.level_reward_ceiling(tables, str(level["tier"]), str(level["kind"]), false)
	assert_lt(float(replay["coins"]), float(first["coins"]), "a replay pays less than the first clear")
	claim["first_clear"] = false
	claim["deltas"] = {"coins": int(first["coins"]) * 2}
	history["verified_completions"] = ["w03_l52", "w03_l52"]
	history["level_claims"] = ["w03_l52"]
	assert_has(
		_verifier.verify_reward_claim(claim, history)["reasons"],
		ReplayVerifier.CLAIM_IMPOSSIBLE_DELTA,
		"replay claim with first-clear coins"
	)


func test_daily_and_streamed_runs_are_not_level_rewards() -> void:
	for id: String in ["daily_" + DATE, "endless_12345", "w01_l99x"]:
		var claim: Dictionary = {"type": "level", "level_id": id, "first_clear": true, "deltas": {"coins": 10}}
		var verdict: Dictionary = _verifier.verify_reward_claim(claim, _history([id]))
		assert_false(bool(verdict["valid"]), id)
		assert_has(verdict["reasons"], ReplayVerifier.CLAIM_INVALID, id)


func test_daily_claim_is_capped_by_the_allowed_tier_reward() -> void:
	var history: Dictionary = _history(["daily_" + DATE])
	var greedy: Dictionary = _daily_claim(7)
	greedy["deltas"] = {"coins": 2500, "gems": 25, "xp": 2000}
	var verdict: Dictionary = _verifier.verify_reward_claim(greedy, history)
	assert_eq(int(verdict["allowed_tier"]), 1, "first daily ever is tier 1")
	assert_false(bool(verdict["valid"]), "tier-7 sized reward on a tier-1 history")
	assert_has(verdict["reasons"], ReplayVerifier.CLAIM_IMPOSSIBLE_DELTA)
	var tier1: Dictionary = RewardEngine.daily_tier_reward(RewardEngine.load_tables(), 1)
	var doubled: Dictionary = _daily_claim(1)
	doubled["deltas"] = {"coins": int(tier1["coins"]) * 2, "xp": int(tier1["xp"])}
	assert_true(bool(_verifier.verify_reward_claim(doubled, history)["valid"]), "ad-doubled coins accepted")
	doubled["deltas"] = {"coins": int(tier1["coins"]), "xp": int(tier1["xp"]) * 2}
	assert_false(bool(_verifier.verify_reward_claim(doubled, history)["valid"]), "xp is never doubled")


func test_repeat_level_claims_need_their_own_verified_runs() -> void:
	var claim: Dictionary = {"type": "level", "level_id": "w01_l01", "first_clear": false, "deltas": {"coins": 4}}
	var history: Dictionary = _history(["w01_l01"], {}, ["w01_l01"])
	var verdict: Dictionary = _verifier.verify_reward_claim(claim, history)
	assert_false(bool(verdict["valid"]), "one run, already claimed once")
	assert_has(verdict["reasons"], ReplayVerifier.CLAIM_REPEAT_EXCEEDS_RUNS)
	history["verified_completions"] = ["w01_l01", "w01_l01", "w01_l01"]
	history["level_claims"] = ["w01_l01", "w01_l01"]
	assert_true(bool(_verifier.verify_reward_claim(claim, history)["valid"]), "third run, third claim")
	history["level_claims"] = ["w01_l01", "w01_l01", "w01_l01"]
	assert_false(bool(_verifier.verify_reward_claim(claim, history)["valid"]), "no fourth claim on three runs")


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
