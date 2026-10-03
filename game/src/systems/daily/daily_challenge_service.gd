class_name DailyChallengeService
extends RefCounted
## Daily challenge: one deterministic level per UTC day, identical for every
## player, plus a gentle streak / reward-tier system.
##
## LEVEL. The date key seeds a [DetRng] that picks the world (all ten worlds),
## and — from the weekday table in data/daily/daily.json (Monday easiest …
## Sunday hardest) — a mid-campaign *mechanics* level inside that world and a
## mid-campaign *pacing* level number. [DifficultyModel] builds a spec for
## both; the daily spec takes its mechanics and theme from the first and its
## speed, spacing, density and fairness tier from the second. Player progress
## is never read, so everyone gets exactly the same level, and the server can
## regenerate it from the date alone (see server/verify_replay.gd).
##
## STREAK (gentle by design — missing a day is never punished harshly):
## - completing the daily on consecutive UTC days raises the streak counter
##   and the reward tier by one (tier capped at max_tier, 7 by default);
## - every fully missed day lowers the reward tier by one (never below
##   min_tier) instead of resetting it: tier 5, one missed day, next
##   completion pays tier 4. Only the displayed streak counter restarts at 1;
## - the reward is granted once per date, on its first completion, through
##   the injected [member reward_grant] callable with
##   {"table": "daily_streak", "tier": n}.
##
## Profile slice (profile.daily, owned by this module):
## {"results": {date_key: {"best", "completed", "attempts", "completions",
## "first_completed_at", "tier"}}, "streak", "streak_best", "tier", "last_day",
## "boards" (personal leaderboard store, see [LocalLeaderboardBackend])}.

const CONFIG_PATH: String = "res://data/daily/daily.json"
const SEED_SALT: String = "fluxdrop-daily-v1"
const ID_PREFIX: String = "daily_"
const KIND: String = "daily"
const MODE: StringName = &"daily"
const SECONDS_PER_DAY: int = 86400
const DAYS_PER_WEEK: int = 7
## 1970-01-01 (day 0) was a Thursday; with Monday = 0 that is weekday 3.
const EPOCH_WEEKDAY: int = 3
const DATE_KEY_LENGTH: int = 10
const DIGITS: String = "0123456789"
const MONTHS_PER_YEAR: int = 12
const MONTH_DAYS: PackedInt32Array = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const DEFAULT_MIN_TIER: int = 1
const DEFAULT_MAX_TIER: int = 7
const DEFAULT_DECAY: int = 1
const DEFAULT_REWARD_TABLE: String = "daily_streak"
const DEFAULT_DURATION: Vector2 = Vector2(30.0, 45.0)
const DEFAULT_GRACE_DAYS: int = 1
const DEFAULT_HISTORY_LIMIT: int = 60
const DEFAULT_CACHE_SIZE: int = 3
const DEFAULT_FALLBACK_ATTEMPTS: int = 4
const DEFAULT_PACING_STEP: int = 40
const DEFAULT_MECHANICS_STEP: int = 6
## Lowest campaign number used for pacing (end of the onboarding tiers).
const MIN_PACING_NUMBER: int = 27
## Lowest local index used for mechanics (chapter B: past every tutorial).
const MIN_MECHANICS_LOCAL: int = 14
## Fallback weekday row (mid-week difficulty) when daily.json is unusable.
const DEFAULT_PACING_RANGE: Vector2i = Vector2i(155, 195)
const DEFAULT_MECHANICS_RANGE: Vector2i = Vector2i(27, 39)
const DEFAULT_WEEKDAY_ROW: Dictionary = {
	"day": "wednesday",
	"label_key": "online.daily.difficulty.medium",
	"pacing": [155, 195],
	"mechanics_local": [27, 39],
	"duration": 35,
}

var profile: PlayerProfile
var bus: EventBus
var clock: GameClock
var catalog: WorldCatalog
## (spec: Dictionary) -> RewardBundle — grants the reward described by spec
## ({"table": "daily_streak", "tier": n}) and returns what was really granted.
var reward_grant: Callable
var config: Dictionary = {}

var _daily_cfg: Dictionary = {}
var _streak_cfg: Dictionary = {}
var _model: DifficultyModel
var _validator: LevelValidator = null
var _cache: Dictionary = {}
var _cache_order: PackedStringArray = PackedStringArray()


## [param p_reward_grant]: see [member reward_grant]; [param p_config] is
## data/daily/daily.json (loaded when empty).
func _init(
	p_profile: PlayerProfile,
	p_bus: EventBus,
	p_clock: GameClock,
	p_catalog: WorldCatalog,
	p_reward_grant: Callable,
	p_config: Dictionary = {}
) -> void:
	profile = p_profile if p_profile != null else PlayerProfile.new()
	bus = p_bus
	clock = p_clock if p_clock != null else GameClock.new()
	catalog = p_catalog if p_catalog != null else WorldCatalog.load_default()
	reward_grant = p_reward_grant
	config = p_config if not p_config.is_empty() else DailyChallengeService.load_config()
	_daily_cfg = _section(config, "daily")
	_streak_cfg = _section(config, "streak")
	_model = DifficultyModel.new(catalog)


## Loads data/daily/daily.json (empty dictionary + warning when unreadable;
## every consumer then falls back to built-in defaults).
static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	var data: Dictionary = JsonIO.read_dict(path)
	if data.is_empty():
		GameLog.warn("daily", "config %s missing or invalid, using defaults" % path)
	return data


# --- dates ----------------------------------------------------------------------


## Today's UTC date key "YYYY-MM-DD".
func date_key() -> String:
	return clock.date_key()


## Deterministic level seed of a date (same on every device and the server).
func seed_for(p_date_key: String) -> int:
	var salt: String = str(_daily_cfg.get("seed_salt", SEED_SALT))
	return DetRng.hash_string(salt + ":" + p_date_key)


## Level id of the daily level of [param p_date_key] ("daily_YYYY-MM-DD").
## Always [constant ID_PREFIX]: [method date_key_from_level_id], the
## leaderboards and the server verifier recognise daily levels by it.
func level_id_for(p_date_key: String) -> String:
	return ID_PREFIX + p_date_key


## Extracts the date key from a daily level id ("" when it is not one).
static func date_key_from_level_id(level_id: String) -> String:
	if not level_id.begins_with(ID_PREFIX):
		return ""
	var key: String = level_id.substr(ID_PREFIX.length())
	return key if DailyChallengeService.day_for_date_key(key) >= 0 else ""


## Days since the Unix epoch for a strict "YYYY-MM-DD" key, or -1 if invalid
## (pure integer arithmetic: identical on every platform, never logs errors).
## Only the canonical spelling is accepted (ASCII digits, zero-padded): a
## key such as "2026-11-+5" would otherwise name the same day but seed a
## different level and open a second board for it.
static func day_for_date_key(key: String) -> int:
	if key.length() != DATE_KEY_LENGTH or key[4] != "-" or key[7] != "-":
		return -1
	for i: int in DATE_KEY_LENGTH:
		if i != 4 and i != 7 and not DIGITS.contains(key[i]):
			return -1
	var ys: String = key.substr(0, 4)
	var ms: String = key.substr(5, 2)
	var ds: String = key.substr(8, 2)
	var y: int = ys.to_int()
	var m: int = ms.to_int()
	var d: int = ds.to_int()
	if y < 1970 or m < 1 or m > MONTHS_PER_YEAR or d < 1 or d > DailyChallengeService.days_in_month(y, m):
		return -1
	# Howard Hinnant's days_from_civil, specialised for years >= 1970.
	var yy: int = y - (1 if m <= 2 else 0)
	var era: int = yy / 400
	var yoe: int = yy - era * 400
	var mp: int = m - 3 if m > 2 else m + 9
	var doy: int = (153 * mp + 2) / 5 + d - 1
	var doe: int = yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468


## Number of days in [param month] (1-12) of [param year] (Gregorian).
static func days_in_month(year: int, month: int) -> int:
	if month < 1 or month > MONTHS_PER_YEAR:
		return 0
	if month == 2 and ((year % 4 == 0 and year % 100 != 0) or year % 400 == 0):
		return 29
	return MONTH_DAYS[month - 1]


## Weekday of an epoch day number with Monday = 0 … Sunday = 6.
static func weekday_for_day(day: int) -> int:
	return posmod(day + EPOCH_WEEKDAY, DAYS_PER_WEEK)


## Reward tier after completing the daily on [param day], given the tier of
## the last completion on [param last_day] (-1 / tier 0: never completed).
## Consecutive day: +1 (capped). Each fully missed day: -decay (floored).
## Shared with [ReplayVerifier] for reward-claim plausibility checks.
static func tier_after(prev_tier: int, last_day: int, day: int, rules: Dictionary = {}) -> int:
	var min_tier: int = int(rules.get("min_tier", DEFAULT_MIN_TIER))
	var max_tier: int = maxi(min_tier, int(rules.get("max_tier", DEFAULT_MAX_TIER)))
	var decay: int = maxi(0, int(rules.get("decay_per_missed_day", DEFAULT_DECAY)))
	if last_day < 0 or prev_tier < min_tier:
		return min_tier
	if day <= last_day:
		return clampi(prev_tier, min_tier, max_tier)
	if day == last_day + 1:
		return mini(max_tier, prev_tier + 1)
	var missed: int = day - last_day - 1
	return clampi(prev_tier - decay * missed, min_tier, max_tier)


# --- level ----------------------------------------------------------------------


## Generator spec of the daily level of [param p_date_key] (null if the key
## is not a valid date). Deterministic; independent of player progress.
func spec_for(p_date_key: String) -> LevelSpec:
	return _build_spec(p_date_key, 0)


## The generated daily level for [param p_date_key] ({} on invalid date or
## generation failure). Each deterministic attempt must stay inside the
## daily duration bounds and pass [LevelValidator] (fairness, solvability,
## objectives); otherwise the next, gentler fallback attempt is used. The
## client and the server must therefore share data/daily/daily.json.
## Cost: roughly 0.2-3 s on desktop, so call it once per day off the hot
## path (it is cached in memory per date, failures included, so a broken
## date is not regenerated on every call; returns a copy).
func level_for(p_date_key: String) -> Dictionary:
	if _cache.has(p_date_key):
		return (_cache[p_date_key] as Dictionary).duplicate(true)
	var fallback: Dictionary = _section(_daily_cfg, "fallback")
	var attempts: int = maxi(1, int(fallback.get("attempts", DEFAULT_FALLBACK_ATTEMPTS)))
	var validate: bool = bool(_daily_cfg.get("validate", true))
	for attempt: int in attempts:
		var spec: LevelSpec = _build_spec(p_date_key, attempt)
		if spec == null:
			return {}
		var generator: LevelGenerator = LevelGenerator.new()
		var data: Dictionary = generator.generate(spec)
		if data.is_empty():
			GameLog.warn(
				"daily", "generation attempt %d for %s failed: %s" % [attempt, p_date_key, ", ".join(generator.errors)]
			)
			continue
		var duration: float = float(data.get("duration", 0.0))
		if duration < spec.duration_bounds.x or duration > spec.duration_bounds.y:
			GameLog.info("daily", "attempt %d for %s rejected: duration %.1f s" % [attempt, p_date_key, duration])
			continue
		if validate:
			var report: LevelValidator.Report = _get_validator().validate(data)
			if not report.ok():
				GameLog.info(
					"daily", "attempt %d for %s rejected by validator: %s" % [attempt, p_date_key, report.codes()]
				)
				continue
		data["kind"] = KIND
		var day: int = DailyChallengeService.day_for_date_key(p_date_key)
		data["daily"] = {
			"date": p_date_key,
			"weekday": DailyChallengeService.weekday_for_day(day),
			"difficulty_key": str(_weekday_row(DailyChallengeService.weekday_for_day(day)).get("label_key", "")),
			"fallback": attempt,
		}
		_remember(p_date_key, data)
		return data.duplicate(true)
	GameLog.error("daily", "could not generate the daily level for %s" % p_date_key)
	_remember(p_date_key, {})
	return {}


## Today's daily level (see [method level_for]).
func today_level() -> Dictionary:
	return level_for(date_key())


func _get_validator() -> LevelValidator:
	if _validator == null:
		_validator = LevelValidator.new(catalog)
		# Fairness/solvability only: audio assets are a presentation concern
		# and must not change which level the server regenerates.
		_validator.check_assets = false
	return _validator


func _build_spec(p_date_key: String, attempt: int) -> LevelSpec:
	var day: int = DailyChallengeService.day_for_date_key(p_date_key)
	if day < 0:
		GameLog.warn("daily", "invalid date key '%s'" % p_date_key)
		return null
	var world_count: int = catalog.world_count()
	if world_count <= 0:
		GameLog.error("daily", "no worlds loaded")
		return null
	var level_seed: int = seed_for(p_date_key)
	var rng: DetRng = DetRng.new(level_seed)
	# Every draw happens in a fixed order so fallbacks never change the world.
	var world_index: int = rng.range_int(1, world_count)
	var row: Dictionary = _weekday_row(DailyChallengeService.weekday_for_day(day))
	var pacing_range: Vector2i = _int_range(row.get("pacing", []), DEFAULT_PACING_RANGE)
	var mech_range: Vector2i = _int_range(row.get("mechanics_local", []), DEFAULT_MECHANICS_RANGE)
	var pacing_number: int = rng.range_int(pacing_range.x, pacing_range.y)
	var mech_local: int = rng.range_int(mech_range.x, mech_range.y)
	var objective: String = _pick_objective(rng)
	var fallback: Dictionary = _section(_daily_cfg, "fallback")
	pacing_number -= attempt * int(fallback.get("pacing_step", DEFAULT_PACING_STEP))
	mech_local -= attempt * int(fallback.get("mechanics_step", DEFAULT_MECHANICS_STEP))
	var pace: LevelSpec = _normal_spec(clampi(pacing_number, MIN_PACING_NUMBER, catalog.total_levels()))
	var local_max: int = catalog.levels_in(world_index)
	var mech_number: int = catalog.global_number(world_index, clampi(mech_local, MIN_MECHANICS_LOCAL, local_max))
	var spec: LevelSpec = _normal_spec(mech_number)
	if pace == null or spec == null:
		GameLog.error("daily", "difficulty model could not build specs for %s" % p_date_key)
		return null
	_apply_pacing(spec, pace)
	spec.id = level_id_for(p_date_key)
	spec.number = 0
	spec.seed = level_seed
	spec.kind = KIND
	spec.tutorial = false
	spec.forgiving = false
	spec.intro_mechanic = ""
	spec.pattern = ""
	spec.boss_name = ""
	spec.unlock_requires = ""
	spec.unlock_stars = 0
	_apply_objective(spec, objective)
	_apply_duration(spec, float(row.get("duration", DEFAULT_DURATION.x)))
	return spec


## Builds the spec for [param number], stepping down past challenge, boss and
## tutorial levels so the daily always derives from a regular level.
func _normal_spec(number: int) -> LevelSpec:
	var n: int = number
	while n >= 1:
		var spec: LevelSpec = _model.build_spec(n)
		if spec == null:
			return null
		if spec.kind == "normal" and not spec.tutorial:
			return spec
		n -= 1
	return null


static func _apply_pacing(spec: LevelSpec, pace: LevelSpec) -> void:
	spec.tier = pace.tier
	spec.min_window = pace.min_window
	spec.intensity = pace.intensity
	spec.speed = pace.speed
	spec.spacing = pace.spacing
	spec.spacing_jitter = pace.spacing_jitter
	spec.change_prob = pace.change_prob
	spec.density = pace.density
	spec.score_ratio = pace.score_ratio
	spec.combo_ratio = pace.combo_ratio


func _pick_objective(rng: DetRng) -> String:
	var weights: Dictionary = _section(_daily_cfg, "objective_weights")
	if weights.is_empty():
		weights = {"reach_end": 1.0}
	var picked: Variant = rng.pick_weighted(weights)
	return str(picked) if picked != null else "reach_end"


func _apply_objective(spec: LevelSpec, objective: String) -> void:
	var fractions: Dictionary = _section(_daily_cfg, "objective_fraction")
	var chosen: String = objective
	if chosen == "shatter" and not spec.forms.has("dash"):
		chosen = "collect"
	if not chosen in ["reach_end", "collect", "shatter"]:
		chosen = "reach_end"
	spec.objective_type = chosen
	spec.objective_fraction = float(fractions.get(chosen, 0.0))


func _apply_duration(spec: LevelSpec, wanted: float) -> void:
	var bounds: Vector2 = DEFAULT_DURATION
	var raw: Variant = _daily_cfg.get("duration_bounds", [])
	if typeof(raw) == TYPE_ARRAY and (raw as Array).size() == 2:
		bounds = Vector2(float((raw as Array)[0]), float((raw as Array)[1]))
	if bounds.y < bounds.x:
		bounds = DEFAULT_DURATION
	spec.duration_bounds = bounds
	spec.target_duration = clampf(wanted, bounds.x, bounds.y)
	var avg_speed: float = spec.speed * (1.0 + spec.speed_ramp * 0.5)
	var usable: float = spec.target_duration * avg_speed - LevelGenerator.LEAD_IN - LevelGenerator.TAIL
	spec.slot_count = maxi(4, int(usable / maxf(spec.spacing, 0.1)))


func _weekday_row(weekday: int) -> Dictionary:
	var rows: Variant = _daily_cfg.get("weekday_difficulty", [])
	if typeof(rows) == TYPE_ARRAY and (rows as Array).size() == DAYS_PER_WEEK:
		var row: Variant = (rows as Array)[weekday]
		if typeof(row) == TYPE_DICTIONARY:
			return row as Dictionary
	GameLog.warn("daily", "weekday difficulty table missing or malformed, using defaults")
	return DEFAULT_WEEKDAY_ROW


static func _int_range(raw: Variant, fallback: Vector2i) -> Vector2i:
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() != 2:
		return fallback
	var a: int = int((raw as Array)[0])
	var b: int = int((raw as Array)[1])
	return Vector2i(mini(a, b), maxi(a, b))


func _remember(p_date_key: String, data: Dictionary) -> void:
	_cache[p_date_key] = data
	_cache_order.append(p_date_key)
	var limit: int = maxi(1, int(_daily_cfg.get("level_cache_size", DEFAULT_CACHE_SIZE)))
	while _cache_order.size() > limit:
		_cache.erase(_cache_order[0])
		_cache_order.remove_at(0)


# --- results, streak and rewards ---------------------------------------------------


## Records a finished daily run. Returns {"best": bool (new best score for the
## date), "first_completion": bool, "streak": int, "tier": int, "reward":
## RewardBundle (empty unless this was the first completion of the date)}.
## Runs for dates other than today (or yesterday within the grace window, for
## runs that crossed midnight) are ignored, as are dates older than the last
## completion minus the grace window (device clock turned back).
func record_result(result: RunResult) -> Dictionary:
	var out: Dictionary = {
		"best": false,
		"first_completion": false,
		"streak": 0,
		"tier": 0,
		"reward": RewardBundle.new("daily"),
	}
	if result == null:
		GameLog.warn("daily", "record_result called without a result")
		return _finish_out(out)
	var key: String = DailyChallengeService.date_key_from_level_id(result.level_id)
	if key.is_empty():
		GameLog.warn("daily", "run %s is not a daily run" % result.level_id)
		return _finish_out(out)
	var day: int = DailyChallengeService.day_for_date_key(key)
	var today: int = clock.day_number()
	var grace: int = maxi(0, int(_daily_cfg.get("late_grace_days", DEFAULT_GRACE_DAYS)))
	if day > today or day < today - grace:
		GameLog.warn("daily", "daily %s is outside the playable window (today %s)" % [key, clock.date_key()])
		return _finish_out(out)
	# A date well before the latest completion is only reachable by turning
	# the device clock back; it must not pay out old dailies again and again.
	var last_day: int = _state_int("last_day", -1)
	if last_day >= 0 and day < last_day - grace:
		GameLog.warn("daily", "daily %s predates the last completion; device clock moved back?" % key)
		return _finish_out(out)
	var entry: Dictionary = _result_entry(key)
	entry["attempts"] = DailyChallengeService._as_int(entry.get("attempts", 0), 0) + 1
	if result.completed:
		entry["completions"] = DailyChallengeService._as_int(entry.get("completions", 0), 0) + 1
		var had_completion: bool = DailyChallengeService._is_true(entry.get("completed", false))
		if not had_completion or result.score > DailyChallengeService._as_int(entry.get("best", 0), 0):
			entry["best"] = maxi(0, result.score)
			out["best"] = true
		if not had_completion:
			entry["completed"] = true
			entry["first_completed_at"] = clock.now_unix()
			out["first_completion"] = true
			var tier: int = _advance_streak(day)
			entry["tier"] = tier
			out["tier"] = tier
			out["reward"] = _grant_reward(tier)
			if bus != null:
				bus.daily_completed.emit(key, result.score)
	_prune_history()
	return _finish_out(out)


func _finish_out(out: Dictionary) -> Dictionary:
	out["streak"] = _display_streak(clock.day_number())
	if int(out["tier"]) <= 0:
		out["tier"] = _current_tier(clock.day_number())
	return out


func _results() -> Dictionary:
	var raw: Variant = profile.daily.get("results", null)
	if typeof(raw) != TYPE_DICTIONARY:
		var fresh: Dictionary = {}
		profile.daily["results"] = fresh
		return fresh
	return raw as Dictionary


func _result_entry(key: String) -> Dictionary:
	var results: Dictionary = _results()
	var raw: Variant = results.get(key, {})
	if typeof(raw) != TYPE_DICTIONARY:
		raw = {}
	var entry: Dictionary = raw as Dictionary
	results[key] = entry
	return entry


func _state_int(key: String, fallback: int) -> int:
	return DailyChallengeService._as_int(profile.daily.get(key, fallback), fallback)


## int() of a persisted value; [param fallback] for anything non-numeric
## (int(null) would abort the caller with a script error).
static func _as_int(v: Variant, fallback: int) -> int:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return int(v)
	return fallback


## Applies a first completion on [param day] to the streak state; returns the
## reward tier earned for that completion.
func _advance_streak(day: int) -> int:
	var last_day: int = _state_int("last_day", -1)
	var tier: int = _state_int("tier", 0)
	var streak: int = _state_int("streak", 0)
	if day <= last_day and tier > 0:
		# Late completion of an older date (run crossed midnight): pay the
		# current tier, leave the streak untouched.
		return tier
	var new_tier: int = DailyChallengeService.tier_after(tier, last_day, day, _streak_cfg)
	streak = streak + 1 if (last_day >= 0 and day == last_day + 1) else 1
	profile.daily["tier"] = new_tier
	profile.daily["streak"] = streak
	profile.daily["last_day"] = day
	profile.daily["streak_best"] = maxi(_state_int("streak_best", 0), streak)
	return new_tier


func _grant_reward(tier: int) -> RewardBundle:
	var table: String = str(_streak_cfg.get("reward_table", DEFAULT_REWARD_TABLE))
	if not reward_grant.is_valid():
		GameLog.warn("daily", "no reward_grant callable; tier %d reward skipped" % tier)
		return RewardBundle.new("daily")
	var granted: Variant = reward_grant.call({"table": table, "tier": tier})
	if granted is RewardBundle:
		return granted as RewardBundle
	GameLog.warn("daily", "reward_grant returned no RewardBundle for tier %d" % tier)
	return RewardBundle.new("daily")


## Streak counter for display: 0 once a full day has been missed.
func _display_streak(today: int) -> int:
	var last_day: int = _state_int("last_day", -1)
	if last_day < 0 or last_day < today - 1:
		return 0
	return maxi(0, _state_int("streak", 0))


## Tier currently held, after gentle decay for fully missed days (0 = none yet).
func _current_tier(today: int) -> int:
	var last_day: int = _state_int("last_day", -1)
	var tier: int = _state_int("tier", 0)
	if last_day < 0 or tier <= 0:
		return 0
	var missed: int = maxi(0, today - last_day - 1)
	var min_tier: int = int(_streak_cfg.get("min_tier", DEFAULT_MIN_TIER))
	var decay: int = maxi(0, int(_streak_cfg.get("decay_per_missed_day", DEFAULT_DECAY)))
	return maxi(min_tier, tier - decay * missed)


## Highest reward tier (same clamp as [method tier_after]).
func _max_tier() -> int:
	var min_tier: int = int(_streak_cfg.get("min_tier", DEFAULT_MIN_TIER))
	return maxi(min_tier, int(_streak_cfg.get("max_tier", DEFAULT_MAX_TIER)))


## Keeps the newest history_limit dates; malformed keys/entries go first
## (they would otherwise sort after real dates and never be pruned).
func _prune_history() -> void:
	var results: Dictionary = _results()
	var limit: int = maxi(1, int(_daily_cfg.get("history_limit", DEFAULT_HISTORY_LIMIT)))
	if results.size() <= limit:
		return
	var keys: Array = []
	for k: Variant in results.keys():
		var valid: bool = typeof(k) == TYPE_STRING and DailyChallengeService.day_for_date_key(str(k)) >= 0
		if valid and typeof(results[k]) == TYPE_DICTIONARY:
			keys.append(k)
		else:
			results.erase(k)
	keys.sort()
	for i: int in keys.size() - limit:
		results.erase(keys[i])


## Snapshot for the Daily screen: {"date_key", "level_id", "played",
## "completed", "best_score", "streak", "tier", "next_tier", "max_tier",
## "seconds_to_reset", "difficulty_key", "streak_best"}. "tier" is the tier
## held now (after gentle decay); "next_tier" is what the next completion
## pays; "max_tier" is the cap (fills {max} in online.daily.tier).
func status() -> Dictionary:
	var today: int = clock.day_number()
	var key: String = clock.date_key()
	var entry: Dictionary = {}
	var raw: Variant = _results().get(key, {})
	if typeof(raw) == TYPE_DICTIONARY:
		entry = raw as Dictionary
	var completed: bool = DailyChallengeService._is_true(entry.get("completed", false))
	var last_day: int = _state_int("last_day", -1)
	var held: int = _state_int("tier", 0)
	var next_tier: int
	if completed and last_day >= today:
		next_tier = DailyChallengeService.tier_after(held, last_day, today + 1, _streak_cfg)
	else:
		next_tier = DailyChallengeService.tier_after(held, last_day, today, _streak_cfg)
	return {
		"date_key": key,
		"level_id": level_id_for(key),
		"played": DailyChallengeService._as_int(entry.get("attempts", 0), 0) > 0,
		"completed": completed,
		"best_score": DailyChallengeService._as_int(entry.get("best", 0), 0),
		"streak": _display_streak(today),
		"streak_best": _state_int("streak_best", 0),
		"tier": _current_tier(today),
		"next_tier": next_tier,
		"max_tier": _max_tier(),
		"seconds_to_reset": SECONDS_PER_DAY - posmod(clock.now_unix(), SECONDS_PER_DAY),
		"difficulty_key": str(_weekday_row(DailyChallengeService.weekday_for_day(today)).get("label_key", "")),
	}


## Honest personal rank of [param score] among the player's own best scores
## of previous dailies (no invented players; works offline). Returns
## {"rank", "total", "is_best", "key", "params", "source": "local"} where key
## is an i18n key (online.rank.*) and params fill its {name} slots.
func rank_text_local(score: int) -> Dictionary:
	var today_key: String = clock.date_key()
	var others: Array[int] = []
	var results: Dictionary = _results()
	for k: Variant in results:
		if str(k) == today_key or typeof(results[k]) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = results[k] as Dictionary
		if DailyChallengeService._is_true(e.get("completed", false)):
			others.append(DailyChallengeService._as_int(e.get("best", 0), 0))
	var rank: int = 1
	var top: int = -1
	for s: int in others:
		if s > score:
			rank += 1
		top = maxi(top, s)
	var total: int = others.size() + 1
	var is_best: bool = others.is_empty() or score > top
	var key: String = "online.rank.personal"
	if others.is_empty():
		key = "online.rank.first_daily"
	elif is_best:
		key = "online.rank.personal_best"
	return {
		"rank": rank,
		"total": total,
		"is_best": is_best,
		"key": key,
		"params": {"rank": rank, "total": total, "score": score},
		"source": "local",
	}


static func _section(data: Dictionary, key: String) -> Dictionary:
	var v: Variant = data.get(key, {})
	return v as Dictionary if typeof(v) == TYPE_DICTIONARY else {}


## True only for a real boolean true (untrusted data: comparing a string or
## number with == true is a script error in Godot 4).
static func _is_true(v: Variant) -> bool:
	return typeof(v) == TYPE_BOOL and bool(v)
