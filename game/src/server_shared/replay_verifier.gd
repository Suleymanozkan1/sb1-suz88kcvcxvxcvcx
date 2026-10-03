class_name ReplayVerifier
extends RefCounted
## Authoritative (server-side) verification of score submissions and reward
## claims. The client is never trusted: the claimed score is ignored except
## for comparison; the verdict comes from re-simulating the submitted input
## replay with the same deterministic [FluxSim] the game uses.
##
## [method verify] checks, in order: replay present and well-typed (every
## field of the untrusted JSON is type- and range-checked before it is
## used; a malformed replay is rejected, never simulated), sim_version,
## replay structure (RunReplay.validate_structure), level/seed identity, mode
## (known, ranked, matches the replay and the level kind — optional per-mode
## "level_kinds" list), daily date window (today or up to
## daily_accept_days_back days ago on the *server* clock), board
## consistency, human tap rate (max_taps_per_second within any
## tap_window_ticks window), then re-simulation with the mode's rules
## (shields, zen, speed_scale, time_limit — data/daily/daily.json "modes"):
## end_tick must match, completion is required for classic/daily-like modes,
## and the claimed (integral) score must equal the recomputed score.
##
## Result: {"valid": bool, "score": int (authoritative recomputed score, 0
## when the run could not be simulated), "reasons": PackedStringArray (stable
## REASON_* codes), "details": PackedStringArray (human-readable)}.
##
## [method verify_reward_claim] rejects duplicate daily claims, claims for
## levels never verified as completed, and impossible currency deltas; daily
## tiers above what the claim history allows are clamped ("allowed_tier").

const REASON_MISSING_REPLAY: String = "missing_replay"
const REASON_INVALID_LEVEL: String = "invalid_level"
const REASON_SIM_VERSION: String = "sim_version_mismatch"
const REASON_STRUCTURE: String = "invalid_structure"
const REASON_LEVEL_MISMATCH: String = "level_mismatch"
const REASON_SEED_MISMATCH: String = "seed_mismatch"
const REASON_MODE_MISMATCH: String = "mode_mismatch"
const REASON_UNKNOWN_MODE: String = "unknown_mode"
const REASON_UNRANKED_MODE: String = "unranked_mode"
const REASON_STALE_DAILY: String = "stale_daily"
const REASON_FUTURE_DAILY: String = "future_daily"
const REASON_BOARD_MISMATCH: String = "board_mismatch"
const REASON_TAP_RATE: String = "tap_rate"
const REASON_INVALID_SCORE: String = "invalid_score"
const REASON_END_TICK: String = "end_tick_mismatch"
const REASON_NOT_COMPLETED: String = "not_completed"
const REASON_NOT_FINISHED: String = "run_not_finished"
const REASON_SCORE_MISMATCH: String = "score_mismatch"

const CLAIM_UNKNOWN_TYPE: String = "unknown_claim_type"
const CLAIM_INVALID: String = "invalid_claim"
const CLAIM_INVALID_DELTA: String = "invalid_delta"
const CLAIM_NEGATIVE_DELTA: String = "negative_delta"
const CLAIM_UNKNOWN_CURRENCY: String = "unknown_currency"
const CLAIM_IMPOSSIBLE_DELTA: String = "impossible_delta"
const CLAIM_DUPLICATE_DAILY: String = "duplicate_daily_claim"
const CLAIM_DUPLICATE_LEVEL: String = "duplicate_level_claim"
const CLAIM_LEVEL_NOT_VERIFIED: String = "level_not_verified"
const CLAIM_STALE: String = "stale_claim"
const CLAIM_FUTURE: String = "future_claim"
const CLAIM_IMPLAUSIBLE_TIER: String = "implausible_tier"

const CLAIM_DAILY: String = "daily"
const CLAIM_LEVEL: String = "level"
const DAILY_MODE: String = "daily"
const DEFAULT_MAX_TAPS_PER_SECOND: int = 12
const DEFAULT_TAP_WINDOW_TICKS: int = 60
const DEFAULT_DAILY_DAYS_BACK: int = 1
const DEFAULT_WEEKS_BACK: int = 1
const DEFAULT_MAX_TICKS: int = 36000
## Streamed courses (endless, time attack) may run up to 30 minutes; the
## client ends endless runs there (modes.json time_limit) so they stay verifiable.
const DEFAULT_MAX_STREAM_TICKS: int = 108000
## Largest valid level seed (seeds are unsigned 32-bit hashes).
const MAX_SEED: int = 0xFFFFFFFF

var clock: GameClock
var config: Dictionary = {}

var _cfg: Dictionary = {}


## Accumulates rejection reasons (stable codes, deduplicated) and details.
class Verdict:
	extends RefCounted
	var reasons: PackedStringArray = PackedStringArray()
	var details: PackedStringArray = PackedStringArray()
	var score: int = 0
	var allowed_tier: int = -1

	## Records a failed check (reason codes are kept unique).
	func reject(reason: String, detail: String) -> void:
		if not reasons.has(reason):
			reasons.append(reason)
		details.append("%s: %s" % [reason, detail])

	## Score-submission verdict dictionary.
	func to_dict() -> Dictionary:
		return {"valid": reasons.is_empty(), "score": score, "reasons": reasons, "details": details}

	## Reward-claim verdict dictionary.
	func to_claim_dict() -> Dictionary:
		var out: Dictionary = {"valid": reasons.is_empty(), "reasons": reasons, "details": details}
		if allowed_tier >= 0:
			out["allowed_tier"] = allowed_tier
		return out


## [param p_clock] is the *server* clock (daily windows); [param p_config]
## is data/daily/daily.json (loaded when empty).
func _init(p_clock: GameClock = null, p_config: Dictionary = {}) -> void:
	clock = p_clock if p_clock != null else GameClock.new()
	config = p_config if not p_config.is_empty() else DailyChallengeService.load_config()
	_cfg = _dict(config.get("verifier", {}))


## Verifies one score submission against the authoritative [param level_data]
## (loaded/regenerated by the server, never sent by the client).
func verify(submission: Dictionary, level_data: Dictionary) -> Dictionary:
	var out: Verdict = Verdict.new()
	var raw_replay: Variant = submission.get("replay", null)
	if typeof(raw_replay) != TYPE_DICTIONARY or (raw_replay as Dictionary).is_empty():
		out.reject(REASON_MISSING_REPLAY, "submission has no replay")
		return out.to_dict()
	if level_data.is_empty() or str(level_data.get("id", "")).is_empty():
		out.reject(REASON_INVALID_LEVEL, "no authoritative level data")
		return out.to_dict()
	# The replay is untrusted JSON: type-check every field before RunReplay
	# converts it (a null or non-numeric field must never reach int()).
	var malformed: PackedStringArray = _replay_type_problems(raw_replay as Dictionary)
	if not malformed.is_empty():
		out.reject(REASON_STRUCTURE, ", ".join(malformed))
		return out.to_dict()
	var replay: RunReplay = RunReplay.from_dict(raw_replay as Dictionary)
	var mode: String = _text_or(submission.get("mode", null), String(replay.mode))
	var level_id: String = _text_or(submission.get("level_id", null), replay.level_id)
	_check_versions(submission, replay, out)
	_check_identity(replay, mode, level_id, level_data, out)
	var rules: Dictionary = LeaderboardService.mode_rules_in(config, mode)
	if rules.is_empty():
		out.reject(REASON_UNKNOWN_MODE, "mode '%s' is unknown" % mode)
	elif not bool(rules.get("ranked", false)):
		out.reject(REASON_UNRANKED_MODE, "mode '%s' is not ranked" % mode)
	elif not _level_kind_ok(rules, level_data):
		out.reject(
			REASON_MODE_MISMATCH, "mode '%s' is not played on %s levels" % [mode, str(level_data.get("kind", ""))]
		)
	_check_daily_window(level_id, out)
	var board: String = _text_or(submission.get("board", ""), "")
	_check_stream_seed(level_id, mode, board, out)
	if not board.is_empty() and not _board_ok(board, mode, level_id, rules):
		out.reject(REASON_BOARD_MISMATCH, "board '%s' does not match %s/%s" % [board, mode, level_id])
	if not tap_rate_ok(replay.tap_ticks):
		out.reject(REASON_TAP_RATE, "more than %d taps within %d ticks" % [_max_taps(), _tap_window()])
	var claimed_v: Variant = submission.get("score", null)
	var claimed_ok: bool = _is_whole(claimed_v) and int(claimed_v) >= 0
	if not claimed_ok:
		out.reject(REASON_INVALID_SCORE, "claimed score missing, negative or not a whole number")
	var sim: FluxSim = simulate(level_data, replay, rules)
	if sim == null:
		out.reject(REASON_INVALID_LEVEL, "level data could not be simulated")
		return out.to_dict()
	out.score = sim.score
	if sim.is_running():
		out.reject(REASON_NOT_FINISHED, "replay still running after %d ticks" % sim.tick)
	if sim.tick != replay.end_tick:
		out.reject(REASON_END_TICK, "run ended at tick %d, replay claims %d" % [sim.tick, replay.end_tick])
	if bool(rules.get("requires_completion", true)) and sim.status != SimConst.Status.COMPLETED:
		out.reject(REASON_NOT_COMPLETED, "run did not complete (fail reason %d)" % sim.fail_reason)
	if claimed_ok and int(claimed_v) != sim.score:
		out.reject(REASON_SCORE_MISMATCH, "claimed %d, simulated %d" % [int(claimed_v), sim.score])
	return out.to_dict()


## Re-simulates [param replay] on [param level_data] with the sim modifiers
## of the mode [param rules]. Returns null when the level data is unusable.
func simulate(level_data: Dictionary, replay: RunReplay, rules: Dictionary) -> FluxSim:
	var lvl: SimLevel = SimLevel.from_dict(level_data)
	if not lvl.errors.is_empty() or lvl.entity_count() == 0:
		GameLog.warn("verifier", "level %s unusable: %s" % [lvl.level_id, ", ".join(lvl.errors)])
		return null
	var time_limit: float = float(rules.get("time_limit", 0.0))
	if time_limit > 0.0:
		lvl.time_limit = time_limit
	var sim: FluxSim = FluxSim.new()
	sim.record_events = false
	sim.zen = bool(rules.get("zen", false))
	sim.speed_scale = float(rules.get("speed_scale", 1.0))
	sim.shields_allowed = bool(rules.get("shields", true))
	sim.strict = bool(rules.get("strict", false))
	sim.setup(lvl)
	replay.play_on(sim, max_ticks_for(replay.level_id))
	return sim


## False when any window of tap_window_ticks ticks holds more taps than a
## human can sustain (max_taps_per_second, scaled to the window).
func tap_rate_ok(tap_ticks: PackedInt32Array) -> bool:
	var window: int = _tap_window()
	var allowed: int = int(ceil(float(_max_taps()) * float(window) / float(SimConst.TICK_RATE)))
	var lo: int = 0
	for hi: int in tap_ticks.size():
		while lo < hi and tap_ticks[hi] - tap_ticks[lo] >= window:
			lo += 1
		if hi - lo + 1 > allowed:
			return false
	return true


## Plausibility of a reward claim. [param claim]: {"type": "daily"|"level",
## "date_key", "level_id", "tier", "first_clear": bool, "deltas": {"coins",
## "gems", "xp"}}. [param history] (server records for this install):
## {"verified_completions": [level ids incl. "daily_<date>"], "daily_claims":
## {date_key: tier} or [date_key], "level_claims": [level ids]}.
## Returns {"valid", "reasons", "allowed_tier" (daily claims only)}.
func verify_reward_claim(claim: Dictionary, history: Dictionary) -> Dictionary:
	var out: Verdict = Verdict.new()
	var type: String = str(claim.get("type", ""))
	var types: Array = _array(_cfg.get("reward_claim_types", [CLAIM_DAILY, CLAIM_LEVEL]))
	if not types.has(type):
		out.reject(CLAIM_UNKNOWN_TYPE, "claim type '%s'" % type)
		return out.to_claim_dict()
	_check_deltas(claim.get("deltas", {}), _dict(_dict(_cfg.get("reward_caps", {})).get(type, {})), out)
	var verified: Dictionary = _key_set(history.get("verified_completions", []))
	if type == CLAIM_DAILY:
		_check_daily_claim(claim, history, verified, out)
	else:
		var level_id: String = str(claim.get("level_id", ""))
		if level_id.is_empty():
			out.reject(CLAIM_INVALID, "level claim without level_id")
		elif not verified.has(level_id):
			out.reject(CLAIM_LEVEL_NOT_VERIFIED, "%s was never verified as completed" % level_id)
		var first_clear: bool = ReplayVerifier._is_true(claim.get("first_clear", false))
		if first_clear and _key_set(history.get("level_claims", [])).has(level_id):
			out.reject(CLAIM_DUPLICATE_LEVEL, "first-clear reward for %s already claimed" % level_id)
	return out.to_claim_dict()


func _check_versions(submission: Dictionary, replay: RunReplay, out: Verdict) -> void:
	var claimed: int = int(submission.get("sim_version", -1)) if _is_number(submission.get("sim_version", null)) else -1
	if claimed != RunReplay.SIM_VERSION or replay.sim_version != RunReplay.SIM_VERSION:
		out.reject(
			REASON_SIM_VERSION, "sim_version %d/%d, server %d" % [claimed, replay.sim_version, RunReplay.SIM_VERSION]
		)
	var problems: PackedStringArray = PackedStringArray()
	for p: String in replay.validate_structure():
		if not p.begins_with("sim_version"):
			problems.append(p)
	if replay.end_tick <= 0:
		problems.append("missing end tick")
	elif not replay.tap_ticks.is_empty() and replay.tap_ticks[replay.tap_ticks.size() - 1] >= replay.end_tick:
		problems.append("tap at or after the final tick")
	if not problems.is_empty():
		out.reject(REASON_STRUCTURE, ", ".join(problems))


func _check_identity(replay: RunReplay, mode: String, level_id: String, level_data: Dictionary, out: Verdict) -> void:
	var data_id: String = str(level_data.get("id", ""))
	if level_id != data_id or replay.level_id != data_id:
		out.reject(REASON_LEVEL_MISMATCH, "submission %s / replay %s / level %s" % [level_id, replay.level_id, data_id])
	var data_seed: int = int(level_data.get("seed", 0)) if _is_number(level_data.get("seed", null)) else 0
	if replay.level_seed != data_seed:
		out.reject(REASON_SEED_MISMATCH, "replay seed %d, level seed %d" % [replay.level_seed, data_seed])
	var is_daily_level: bool = not DailyChallengeService.date_key_from_level_id(data_id).is_empty()
	if String(replay.mode) != mode or (mode == DAILY_MODE) != is_daily_level:
		out.reject(REASON_MODE_MISMATCH, "mode %s / replay %s on level %s" % [mode, String(replay.mode), data_id])


## Daily date-window check on the server clock: "" when [param level_id]
## is not a daily level or its date is accepted, otherwise
## [constant REASON_FUTURE_DAILY] / [constant REASON_STALE_DAILY]. Cheap, so
## a backend can refuse a stale daily before regenerating its level.
func daily_window_reason(level_id: String) -> String:
	var date_key: String = DailyChallengeService.date_key_from_level_id(level_id)
	if date_key.is_empty():
		return ""
	var day: int = DailyChallengeService.day_for_date_key(date_key)
	var today: int = clock.day_number()
	if day > today:
		return REASON_FUTURE_DAILY
	if day < today - _days_back():
		return REASON_STALE_DAILY
	return ""


func _check_daily_window(level_id: String, out: Verdict) -> void:
	var reason: String = daily_window_reason(level_id)
	if not reason.is_empty():
		out.reject(reason, "daily %s is outside the accepted window (server %s)" % [level_id, clock.date_key()])


func _board_ok(board: String, mode: String, level_id: String, rules: Dictionary) -> bool:
	var b: Dictionary = LeaderboardService.parse_board(board)
	var ok: bool = false
	match str(b.get("type", "")):
		LeaderboardService.BOARD_DAILY:
			ok = mode == DAILY_MODE and DailyChallengeService.date_key_from_level_id(level_id) == str(b["date_key"])
		LeaderboardService.BOARD_WEEKLY:
			ok = str(b["mode"]) == mode and _recent_week(str(b["week_key"]))
		LeaderboardService.BOARD_ALLTIME:
			ok = str(b["mode"]) == mode
		LeaderboardService.BOARD_LEVEL:
			ok = bool(rules.get("level_board", false)) and str(b["level_id"]) == level_id
	return ok


## Streamed courses rank only on their weekly board and only on that week's
## official seed: otherwise a player could search offline for an easy seed.
func _check_stream_seed(level_id: String, mode: String, board: String, out: Verdict) -> void:
	var stream: Dictionary = ModeCatalog.shared().parse_stream_id(level_id)
	if stream.is_empty():
		return
	if String(stream["mode"] as StringName) != mode:
		out.reject(
			REASON_MODE_MISMATCH, "course %s belongs to mode %s" % [level_id, String(stream["mode"] as StringName)]
		)
		return
	var b: Dictionary = LeaderboardService.parse_board(board)
	if str(b.get("type", "")) != LeaderboardService.BOARD_WEEKLY:
		out.reject(REASON_BOARD_MISMATCH, "streamed courses rank on their weekly board only")
		return
	var week: String = str(b.get("week_key", ""))
	if int(stream["seed"]) != ModeCatalog.endless_seed(StringName(mode), week):
		out.reject(REASON_SEED_MISMATCH, "course seed is not the official %s seed for %s" % [mode, week])


## True for the server's current ISO week or one of the accepted previous ones.
func _recent_week(week_key: String) -> bool:
	var weeks_back: int = maxi(0, int(_cfg.get("weekly_accept_weeks_back", DEFAULT_WEEKS_BACK)))
	return LeaderboardService.recent_week_keys(clock.day_number(), weeks_back).has(week_key)


## True when [param rules] has no "level_kinds" list or it contains the
## authoritative level's kind (e.g. endless boards only take endless runs).
static func _level_kind_ok(rules: Dictionary, level_data: Dictionary) -> bool:
	var kinds: Variant = rules.get("level_kinds", null)
	if typeof(kinds) != TYPE_ARRAY:
		return true
	return (kinds as Array).has(str(level_data.get("kind", "")))


## Type and range problems of an untrusted replay dictionary (empty = safe
## to hand to RunReplay.from_dict).
func _replay_type_problems(raw: Dictionary) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var max_ticks: int = max_ticks_for(str(raw.get("level_id", "")) if _is_text(raw.get("level_id", null)) else "")
	if not _is_text(raw.get("level_id", null)):
		problems.append("level_id must be a string")
	if not _is_text(raw.get("mode", null)):
		problems.append("mode must be a string")
	if not _whole_in(raw.get("seed", null), 0, MAX_SEED):
		problems.append("seed must be an unsigned 32-bit integer")
	if not _whole_in(raw.get("sim_version", null), 0, MAX_SEED):
		problems.append("sim_version must be a whole number")
	if not _whole_in(raw.get("end_tick", null), 1, max_ticks):
		problems.append("end_tick must be within 1..%d" % max_ticks)
	var taps: Variant = raw.get("taps", null)
	if typeof(taps) != TYPE_ARRAY:
		problems.append("taps must be an array")
	elif (taps as Array).size() > max_ticks:
		problems.append("more taps than ticks")
	else:
		for t: Variant in taps as Array:
			if not _whole_in(t, 0, max_ticks):
				problems.append("tap ticks must be whole numbers within 0..%d" % max_ticks)
				break
	return problems


func _check_daily_claim(claim: Dictionary, history: Dictionary, verified: Dictionary, out: Verdict) -> void:
	var date_key: String = str(claim.get("date_key", ""))
	var day: int = DailyChallengeService.day_for_date_key(date_key)
	if day < 0:
		out.reject(CLAIM_INVALID, "invalid date '%s'" % date_key)
		return
	var today: int = clock.day_number()
	if day > today:
		out.reject(CLAIM_FUTURE, "daily %s is in the future" % date_key)
	elif day < today - _days_back():
		out.reject(CLAIM_STALE, "daily %s is too old" % date_key)
	var claims: Dictionary = _key_set(history.get("daily_claims", {}))
	if claims.has(date_key):
		out.reject(CLAIM_DUPLICATE_DAILY, "daily %s already claimed" % date_key)
	if not verified.has(DailyChallengeService.ID_PREFIX + date_key):
		out.reject(CLAIM_LEVEL_NOT_VERIFIED, "daily %s was never verified as completed" % date_key)
	var streak: Dictionary = _dict(config.get("streak", {}))
	var min_tier: int = int(streak.get("min_tier", DailyChallengeService.DEFAULT_MIN_TIER))
	var max_tier: int = int(streak.get("max_tier", DailyChallengeService.DEFAULT_MAX_TIER))
	var tier_v: Variant = claim.get("tier", null)
	if not _is_number(tier_v) or int(tier_v) < min_tier or int(tier_v) > max_tier:
		out.reject(CLAIM_IMPLAUSIBLE_TIER, "tier %s outside %d..%d" % [str(tier_v), min_tier, max_tier])
		return
	out.allowed_tier = mini(int(tier_v), plausible_tier(claims.keys(), day))


## Highest daily reward tier reachable on [param day] given the dates of the
## previously accepted daily claims (same gentle streak rule as the client).
func plausible_tier(claimed_dates: Array, day: int) -> int:
	var days: Array[int] = []
	for k: Variant in claimed_dates:
		var d: int = DailyChallengeService.day_for_date_key(str(k))
		if d >= 0 and d < day:
			days.append(d)
	days.sort()
	var rules: Dictionary = _dict(config.get("streak", {}))
	var tier: int = 0
	var last: int = -1
	for d: int in days:
		tier = DailyChallengeService.tier_after(tier, last, d, rules)
		last = d
	return DailyChallengeService.tier_after(tier, last, day, rules)


func _check_deltas(raw: Variant, caps: Dictionary, out: Verdict) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		out.reject(CLAIM_INVALID_DELTA, "deltas must be an object")
		return
	var deltas: Dictionary = raw as Dictionary
	for k: Variant in deltas:
		var currency: String = str(k)
		var v: Variant = deltas[k]
		if not caps.has(currency):
			out.reject(CLAIM_UNKNOWN_CURRENCY, "currency '%s'" % currency)
		elif not _is_whole(v):
			out.reject(CLAIM_INVALID_DELTA, "%s delta %s" % [currency, str(v)])
		elif int(v) < 0:
			out.reject(CLAIM_NEGATIVE_DELTA, "%s delta %d" % [currency, int(v)])
		elif int(v) > int(caps[currency]):
			out.reject(CLAIM_IMPOSSIBLE_DELTA, "%s delta %d above cap %d" % [currency, int(v), int(caps[currency])])


func _max_taps() -> int:
	return maxi(1, int(_cfg.get("max_taps_per_second", DEFAULT_MAX_TAPS_PER_SECOND)))


func _tap_window() -> int:
	return maxi(1, int(_cfg.get("tap_window_ticks", DEFAULT_TAP_WINDOW_TICKS)))


func _days_back() -> int:
	return maxi(0, int(_cfg.get("daily_accept_days_back", DEFAULT_DAILY_DAYS_BACK)))


func _max_replay_ticks() -> int:
	return maxi(1, int(_cfg.get("max_replay_ticks", DEFAULT_MAX_TICKS)))


## Longest accepted replay for [param level_id]: streamed courses get the
## stream limit, every authored or daily level the regular one.
func max_ticks_for(level_id: String) -> int:
	if not ModeCatalog.shared().parse_stream_id(level_id).is_empty():
		var stream_cap: Variant = _cfg.get("max_stream_replay_ticks", DEFAULT_MAX_STREAM_TICKS)
		return maxi(1, int(stream_cap) if _is_number(stream_cap) else DEFAULT_MAX_STREAM_TICKS)
	return _max_replay_ticks()


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


## Finite number without a fractional part (JSON numbers arrive as floats).
static func _is_whole(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	return typeof(v) == TYPE_FLOAT and is_finite(float(v)) and float(v) == floorf(float(v))


static func _whole_in(v: Variant, lo: int, hi: int) -> bool:
	return _is_whole(v) and float(v) >= float(lo) and float(v) <= float(hi)


static func _is_text(v: Variant) -> bool:
	return typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME


static func _text_or(v: Variant, fallback: String) -> String:
	return str(v) if _is_text(v) else fallback


static func _dict(v: Variant) -> Dictionary:
	return v as Dictionary if typeof(v) == TYPE_DICTIONARY else {}


static func _array(v: Variant) -> Array:
	return v as Array if typeof(v) == TYPE_ARRAY else []


## Accepts an array of ids or a dictionary keyed by id; returns {id: true}.
static func _key_set(v: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(v) == TYPE_DICTIONARY:
		for k: Variant in v as Dictionary:
			out[str(k)] = true
	elif typeof(v) == TYPE_ARRAY or typeof(v) == TYPE_PACKED_STRING_ARRAY:
		for item: Variant in v:
			out[str(item)] = true
	return out


## True only for a real boolean true (untrusted data: comparing a string or
## number with == true is a script error in Godot 4).
static func _is_true(v: Variant) -> bool:
	return typeof(v) == TYPE_BOOL and bool(v)
