class_name StatsService
extends RefCounted
## Lifetime player statistics: the [member PlayerProfile.stats] slice.
##
## Every stat is a non-negative int. Mutators emit [signal EventBus.stat_changed]
## whenever a stored value actually changes; achievements and missions listen
## to that. Counters only grow ([method add], [method set_max]) so bad input can
## never take progress away; [method set_value] exists for totals owned by other
## systems (cosmetics_owned, achievements_unlocked).
##
## The service has no side effects at construction. Call [method connect_bus]
## once from the composition root to count earned coins automatically.

const RUNS_PLAYED: String = "runs_played"
const RUNS_FAILED: String = "runs_failed"
const LEVELS_CLEARED: String = "levels_cleared"
const UNIQUE_LEVELS_CLEARED: String = "unique_levels_cleared"
const PERFECTS: String = "perfects"
const UNIQUE_PERFECTS: String = "unique_perfects"
const SPARKS_COLLECTED: String = "sparks_collected"
const PRISMS_COLLECTED: String = "prisms_collected"
const NEAR_MISSES: String = "near_misses"
const SHATTERS: String = "shatters"
const CHAIN_LINKS: String = "chain_links"
const GATES_PASSED: String = "gates_passed"
const PORTALS_USED: String = "portals_used"
const CURRENTS_RIDDEN: String = "currents_ridden"
const OVERDRIVES: String = "overdrives"
const MAX_COMBO: String = "max_combo"
const TOTAL_SCORE: String = "total_score"
const DAMAGE_FREE_CLEARS: String = "damage_free_clears"
const BOSSES_CLEARED: String = "bosses_cleared"
const CHALLENGES_CLEARED: String = "challenges_cleared"
const FAST_CLEARS: String = "fast_clears"
const DAILY_COMPLETED: String = "daily_completed"
const DAILY_STREAK_MAX: String = "daily_streak_max"
const COINS_EARNED: String = "coins_earned"
const COSMETICS_OWNED: String = "cosmetics_owned"
const ACHIEVEMENTS_UNLOCKED: String = "achievements_unlocked"
const WORLDS_COMPLETED: String = "worlds_completed"
const WORLDS_PERFECTED: String = "worlds_perfected"
const TAPS: String = "taps"
const REVIVES_USED: String = "revives_used"
const ZEN_RUNS: String = "zen_runs"
const ENDLESS_BEST_DISTANCE: String = "endless_best_distance"
const TIME_PLAYED_SECONDS: String = "time_played_seconds"

## Every stat this module defines, in display order.
const ALL_STATS: PackedStringArray = [
	RUNS_PLAYED, RUNS_FAILED, LEVELS_CLEARED, UNIQUE_LEVELS_CLEARED, PERFECTS, UNIQUE_PERFECTS,
	SPARKS_COLLECTED, PRISMS_COLLECTED, NEAR_MISSES, SHATTERS, CHAIN_LINKS, GATES_PASSED,
	PORTALS_USED, CURRENTS_RIDDEN, OVERDRIVES, MAX_COMBO, TOTAL_SCORE, DAMAGE_FREE_CLEARS,
	BOSSES_CLEARED, CHALLENGES_CLEARED, FAST_CLEARS, DAILY_COMPLETED, DAILY_STREAK_MAX,
	COINS_EARNED, COSMETICS_OWNED, ACHIEVEMENTS_UNLOCKED, WORLDS_COMPLETED, WORLDS_PERFECTED,
	TAPS, REVIVES_USED, ZEN_RUNS, ENDLESS_BEST_DISTANCE, TIME_PLAYED_SECONDS,
]
## Stats that keep the best value seen instead of accumulating.
const MAX_STATS: PackedStringArray = [MAX_COMBO, DAILY_STREAK_MAX, ENDLESS_BEST_DISTANCE]
## Stats whose value is owned and written by another system.
const EXTERNAL_STATS: PackedStringArray = [COSMETICS_OWNED, ACHIEVEMENTS_UNLOCKED]
## Upper bound for any stat: stays exact through the JSON float round trip.
const MAX_VALUE: int = 1_000_000_000_000
const DEFAULT_FAST_CLEAR_RATIO: float = 0.9
const FAST_CLEAR_RATIO_MIN: float = 0.1
const FAST_CLEAR_RATIO_MAX: float = 1.0
const MODE_CLASSIC: StringName = &"classic"
const MODE_ZEN: StringName = &"zen"
const MODE_ENDLESS: StringName = &"endless"
const KIND_NORMAL: String = "normal"
const KIND_BOSS: String = "boss"
const KIND_CHALLENGE: String = "challenge"
const CURRENCY_COINS: StringName = &"coins"
## Custom stat names (used by other systems) must be lower_snake_case.
const NAME_PATTERN: String = "^[a-z][a-z0-9]*(_[a-z0-9]+)*$"

## Completed runs at or under this fraction of the design duration are fast clears.
var fast_clear_ratio: float = DEFAULT_FAST_CLEAR_RATIO

var _profile: PlayerProfile
var _bus: EventBus
var _name_regex: RegEx = RegEx.new()


## [param config] is the progression config (data/progression/progression.json);
## only its "stats" section is read. Missing or invalid values use defaults.
func _init(profile: PlayerProfile, bus: EventBus, config: Dictionary = {}) -> void:
	if profile == null:
		GameLog.error("stats", "no profile injected; using a blank in-memory profile")
		profile = PlayerProfile.new()
	_profile = profile
	_bus = bus
	_name_regex.compile(NAME_PATTERN)
	fast_clear_ratio = _read_fast_clear_ratio(config)


## All stat names this module defines.
static func known_stats() -> PackedStringArray:
	return ALL_STATS.duplicate()


## True for a stat name defined by this module.
static func is_known(stat: String) -> bool:
	return ALL_STATS.has(stat)


## Builds the [method record_run] context from a level file and the outcome of
## [method ProgressionService.record_level_result]. Wrongly typed values fall
## back to defaults (normal kind, false flags, no design duration).
static func build_context(result: RunResult, level_meta: Dictionary, outcome: Dictionary) -> Dictionary:
	var mode: StringName = result.mode if result != null else MODE_CLASSIC
	return {
		"kind": _text(level_meta.get("kind", KIND_NORMAL), KIND_NORMAL),
		"first_clear": _flag(outcome.get("first_clear", false)),
		"first_perfect": _flag(outcome.get("first_perfect", false)),
		"design_duration": _duration(level_meta.get("duration", 0.0)),
		"mode": mode,
	}


## Current value of [param stat] (0 when never recorded or not a number).
func value(stat: String) -> int:
	var raw: Variant = _profile.stats.get(stat, 0)
	if typeof(raw) == TYPE_INT:
		return clampi(raw as int, 0, MAX_VALUE)
	if typeof(raw) == TYPE_FLOAT and is_finite(raw as float):
		return int(clampf(raw as float, 0.0, float(MAX_VALUE)))
	return 0


## Adds a non-negative [param amount]; returns the new value. Negative amounts
## are rejected (counters never decrease).
func add(stat: String, amount: int = 1) -> int:
	if not _valid_name(stat):
		return 0
	var current: int = value(stat)
	if amount < 0:
		GameLog.warn("stats", "rejected negative add %d to %s" % [amount, stat])
		return current
	if amount == 0:
		return current
	return _store(stat, mini(current + mini(amount, MAX_VALUE), MAX_VALUE))


## Keeps the larger of the stored value and [param candidate]; returns the result.
func set_max(stat: String, candidate: int) -> int:
	if not _valid_name(stat):
		return 0
	var current: int = value(stat)
	if candidate <= current:
		return current
	return _store(stat, mini(candidate, MAX_VALUE))


## Overwrites [param stat] (clamped to 0..MAX_VALUE); returns the stored value.
## Meant for totals owned by other systems, e.g. cosmetics_owned.
func set_value(stat: String, new_value: int) -> int:
	if not _valid_name(stat):
		return 0
	if new_value < 0:
		GameLog.warn("stats", "clamped negative value %d for %s" % [new_value, stat])
	return _store(stat, clampi(new_value, 0, MAX_VALUE))


## Updates every counter affected by one finished run.
## [param ctx]: {"kind": "normal"|"challenge"|"boss", "first_clear": bool,
## "first_perfect": bool, "design_duration": float, "mode": StringName}.
## Zen runs count as played (plus collectibles and time) but never as clears;
## endless runs end by design, so they are not counted as failures.
func record_run(result: RunResult, ctx: Dictionary = {}) -> void:
	if result == null:
		GameLog.warn("stats", "record_run called without a result")
		return
	var mode: StringName = StringName(_text(ctx.get("mode", result.mode), str(result.mode)))
	add(RUNS_PLAYED)
	_record_run_counters(result)
	if result.revived:
		add(REVIVES_USED)
	if mode == MODE_ZEN:
		add(ZEN_RUNS)
	elif mode == MODE_ENDLESS:
		set_max(ENDLESS_BEST_DISTANCE, floori(_measure(result.distance)))
	if not result.completed:
		if mode != MODE_ENDLESS and mode != MODE_ZEN:
			add(RUNS_FAILED)
		return
	if mode == MODE_ZEN:
		return
	_record_clear(result, ctx)


## Daily challenge bookkeeping: counts a first completion of the day and keeps
## the longest streak (fed by the daily challenge service result).
func record_daily(first_completion: bool, streak: int) -> void:
	if first_completion:
		add(DAILY_COMPLETED)
	set_max(DAILY_STREAK_MAX, streak)


## True when a completed run took at most [member fast_clear_ratio] of the
## level's design duration (both must be positive and finite).
func is_fast_clear(result: RunResult, design_duration: float) -> bool:
	if result == null or not result.completed:
		return false
	if _measure(design_duration) <= 0.0 or _measure(result.time_seconds) <= 0.0:
		return false
	return result.time_seconds <= design_duration * fast_clear_ratio


## Listens to [signal EventBus.currency_changed] so earned coins are counted.
## Idempotent; call once from the composition root.
func connect_bus() -> void:
	if _bus == null:
		return
	if not _bus.currency_changed.is_connected(_on_currency_changed):
		_bus.currency_changed.connect(_on_currency_changed)


## Stops listening to the bus (used when the service is replaced).
func disconnect_bus() -> void:
	if _bus != null and _bus.currency_changed.is_connected(_on_currency_changed):
		_bus.currency_changed.disconnect(_on_currency_changed)


## Every known stat with its current value (for the profile/stats screen).
func snapshot() -> Dictionary:
	var out: Dictionary = {}
	for stat: String in ALL_STATS:
		out[stat] = value(stat)
	return out


func _record_run_counters(result: RunResult) -> void:
	add(TAPS, maxi(result.taps, 0))
	add(TIME_PLAYED_SECONDS, roundi(_measure(result.time_seconds)))
	add(SPARKS_COLLECTED, maxi(result.sparks, 0))
	add(PRISMS_COLLECTED, maxi(result.prisms, 0))
	add(NEAR_MISSES, maxi(result.near_misses, 0))
	add(SHATTERS, maxi(result.shatters, 0))
	add(CHAIN_LINKS, maxi(result.chain_links, 0))
	add(GATES_PASSED, maxi(result.gates, 0))
	add(PORTALS_USED, maxi(result.portals_used, 0))
	add(CURRENTS_RIDDEN, maxi(result.currents_ridden, 0))
	add(OVERDRIVES, maxi(result.overdrives, 0))
	add(TOTAL_SCORE, maxi(result.score, 0))
	set_max(MAX_COMBO, result.max_combo)


func _record_clear(result: RunResult, ctx: Dictionary) -> void:
	add(LEVELS_CLEARED)
	if _flag(ctx.get("first_clear", false)):
		add(UNIQUE_LEVELS_CLEARED)
	if result.perfect:
		add(PERFECTS)
	if _flag(ctx.get("first_perfect", false)):
		add(UNIQUE_PERFECTS)
	if result.damage == 0:
		add(DAMAGE_FREE_CLEARS)
	var kind: String = _text(ctx.get("kind", KIND_NORMAL), KIND_NORMAL)
	if kind == KIND_BOSS:
		add(BOSSES_CLEARED)
	elif kind == KIND_CHALLENGE:
		add(CHALLENGES_CLEARED)
	var duration: float = _duration(ctx.get("design_duration", ctx.get("duration", 0.0)))
	if is_fast_clear(result, duration):
		add(FAST_CLEARS)


func _on_currency_changed(currency: StringName, _balance: int, delta: int) -> void:
	if currency == CURRENCY_COINS and delta > 0:
		add(COINS_EARNED, delta)


func _store(stat: String, new_value: int) -> int:
	var stored: Variant = _profile.stats.get(stat)
	if typeof(stored) == TYPE_INT and (stored as int) == new_value:
		return new_value
	_profile.stats[stat] = new_value
	if _bus != null:
		_bus.stat_changed.emit(StringName(stat), new_value)
	return new_value


func _valid_name(stat: String) -> bool:
	if ALL_STATS.has(stat):
		return true
	if _name_regex.search(stat) == null:
		GameLog.warn("stats", "invalid stat name '%s'" % stat)
		return false
	return true


static func _read_fast_clear_ratio(config: Dictionary) -> float:
	var section: Variant = config.get("stats", {})
	if typeof(section) != TYPE_DICTIONARY:
		return DEFAULT_FAST_CLEAR_RATIO
	var raw: Variant = (section as Dictionary).get("fast_clear_ratio", DEFAULT_FAST_CLEAR_RATIO)
	if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
		GameLog.warn("stats", "fast_clear_ratio is not a number; using %.2f" % DEFAULT_FAST_CLEAR_RATIO)
		return DEFAULT_FAST_CLEAR_RATIO
	var ratio: float = float(raw)
	if is_nan(ratio) or ratio < FAST_CLEAR_RATIO_MIN or ratio > FAST_CLEAR_RATIO_MAX:
		GameLog.warn("stats", "fast_clear_ratio %.3f out of range; using %.2f" % [ratio, DEFAULT_FAST_CLEAR_RATIO])
		return DEFAULT_FAST_CLEAR_RATIO
	return ratio


## A finite, non-negative measurement (time, distance) capped at
## [constant MAX_VALUE]; NaN/INF read as 0 so platform-specific float -> int
## conversions can never inflate a stat.
static func _measure(v: float) -> float:
	if not is_finite(v) or v <= 0.0:
		return 0.0
	return minf(v, float(MAX_VALUE))


## Design duration from untrusted context/level data (0 = unknown).
static func _duration(v: Variant) -> float:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return _measure(float(v))
	return 0.0


## Only real booleans (or non-zero numbers) count as true.
static func _flag(v: Variant) -> bool:
	if typeof(v) == TYPE_BOOL:
		return v as bool
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return float(v) != 0.0
	return false


## Text from a String/StringName, else [param fallback].
static func _text(v: Variant, fallback: String) -> String:
	if typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME:
		return str(v)
	return fallback
