class_name AchievementService
extends RefCounted
## Data-driven achievements evaluated against the lifetime counters in
## [member PlayerProfile.stats].
##
## Definitions live in data/achievements/achievements.json. Each one names a
## stat and a target; [method evaluate] unlocks every achievement whose stat has
## reached its target, records the unlock time in
## [member PlayerProfile.achievements], grants its reward exactly once through
## the injected [code]reward_grant[/code] callable and publishes
## [signal EventBus.achievement_unlocked]. The service owns only the
## [code]achievements[/code] slice of the profile plus the
## [code]achievements_unlocked[/code] counter.
##
## Hidden ("secret") achievements are left out of [method list] until they are
## unlocked, so a player can never see their goal in advance but always sees
## what they earned.

const DEFAULT_PATH: String = "res://data/achievements/achievements.json"
const LOG_CHANNEL: String = "achievements"
const REWARD_SOURCE_PREFIX: String = "achievement:"
const STAT_ACHIEVEMENTS_UNLOCKED: String = "achievements_unlocked"
const BADGE_PREFIX: String = "badge_"

const CATEGORIES: PackedStringArray = [
	"progress",
	"skill",
	"collection",
	"combo",
	"daily",
	"boss",
	"mastery",
	"secret",
]

## Lifetime stats an achievement may reference (maintained by StatsService;
## "cosmetics_owned" and "achievements_unlocked" are set by their owners).
const KNOWN_STATS: PackedStringArray = [
	"runs_played",
	"runs_failed",
	"levels_cleared",
	"unique_levels_cleared",
	"perfects",
	"unique_perfects",
	"sparks_collected",
	"prisms_collected",
	"near_misses",
	"shatters",
	"chain_links",
	"gates_passed",
	"portals_used",
	"currents_ridden",
	"overdrives",
	"max_combo",
	"total_score",
	"damage_free_clears",
	"bosses_cleared",
	"challenges_cleared",
	"fast_clears",
	"daily_completed",
	"daily_streak_max",
	"coins_earned",
	"cosmetics_owned",
	"achievements_unlocked",
	"worlds_completed",
	"worlds_perfected",
	"taps",
	"zen_runs",
	"endless_best_distance",
	"time_played_seconds",
]

## Reward spec keys understood by RewardEngine.bundle_from_spec.
const REWARD_AMOUNT_KEYS: PackedStringArray = ["coins", "gems", "xp"]
const REWARD_ID_KEYS: PackedStringArray = ["badge", "cosmetic"]

var _profile: PlayerProfile
var _bus: EventBus
var _clock: GameClock
var _reward_grant: Callable
## Definitions exactly as provided (used by [method validate_definitions]).
var _raw_definitions: Array = []
## Sanitised definitions in data order; each has typed fields.
var _defs: Array[Dictionary] = []
## id -> index into [member _defs].
var _index: Dictionary = {}


## [param reward_grant] has the signature
## [code](spec: Dictionary, source: String) -> RewardBundle[/code].
## When [param definitions] is empty the shipped data file is loaded.
func _init(
	profile: PlayerProfile, bus: EventBus, clock: GameClock, reward_grant: Callable, definitions: Array = []
) -> void:
	_profile = profile
	_bus = bus
	_clock = clock
	_reward_grant = reward_grant
	_raw_definitions = definitions if not definitions.is_empty() else AchievementService.load_definitions()
	_build_index()


## Loads the definition list from [param path]. Accepts either
## [code]{"achievements": [...]}[/code] or a bare array. Never fails: returns an
## empty array (and logs) when the file is missing or malformed.
static func load_definitions(path: String = DEFAULT_PATH) -> Array:
	var data: Variant = JsonIO.read(path)
	if typeof(data) == TYPE_ARRAY:
		return data as Array
	if typeof(data) == TYPE_DICTIONARY:
		var list_value: Variant = (data as Dictionary).get("achievements", [])
		if typeof(list_value) == TYPE_ARRAY:
			return list_value as Array
	GameLog.error(LOG_CHANNEL, "no achievement definitions in %s" % path)
	return []


## Unlocks every achievement whose stat reached its target and returns the ids
## unlocked by this call (in data order). Repeats until stable so achievements
## that count other achievements unlock in the same call. Already unlocked
## achievements are never unlocked, rewarded or announced again.
func evaluate() -> Array[String]:
	var newly: Array[String] = []
	var passes: int = 0
	var changed: bool = true
	# Each pass unlocks at least one achievement or ends the loop, so the
	# definition count bounds it; the guard only protects against bad state.
	while changed and passes <= _defs.size():
		changed = false
		passes += 1
		for def: Dictionary in _defs:
			var id: String = def["id"]
			if _profile.achievements.has(id):
				continue
			var stat_name: String = def["stat"]
			if _profile.stat(stat_name) >= int(def["target"]):
				_unlock(def)
				newly.append(id)
				changed = true
	return newly


## Progress of one achievement:
## [code]{"value": int, "target": int, "unlocked": bool, "unlocked_at": int}[/code].
## [code]value[/code] is clamped to [code]target[/code] (and equals it once
## unlocked). Unknown ids return zeros.
func progress(id: String) -> Dictionary:
	if not _index.has(id):
		GameLog.warn(LOG_CHANNEL, "progress for unknown achievement %s" % id)
		return {"value": 0, "target": 0, "unlocked": false, "unlocked_at": 0}
	var def: Dictionary = _defs[int(_index[id])]
	var target: int = def["target"]
	var stat_name: String = def["stat"]
	var unlocked: bool = _profile.achievements.has(id)
	var value: int = target if unlocked else clampi(_profile.stat(stat_name), 0, target)
	return {
		"value": value,
		"target": target,
		"unlocked": unlocked,
		"unlocked_at": int(_profile.achievements.get(id, 0)),
	}


## Achievements for the UI in data order. Each entry:
## [code]{"id", "name_key", "desc_key", "desc_args", "category", "stat", "target",
## "value", "unlocked", "unlocked_at", "hidden", "reward"}[/code].
## With [param include_hidden] false, hidden achievements are omitted until
## the player has unlocked them.
func list(include_hidden: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def: Dictionary in _defs:
		var id: String = def["id"]
		var unlocked: bool = _profile.achievements.has(id)
		if bool(def["hidden"]) and not include_hidden and not unlocked:
			continue
		var p: Dictionary = progress(id)
		(
			out
			. append(
				{
					"id": id,
					"name_key": def["name_key"],
					"desc_key": def["desc_key"],
					"desc_args": {"target": def["target"]},
					"category": def["category"],
					"stat": def["stat"],
					"target": def["target"],
					"value": p["value"],
					"unlocked": unlocked,
					"unlocked_at": p["unlocked_at"],
					"hidden": def["hidden"],
					"reward": (def["reward"] as Dictionary).duplicate(),
				}
			)
		)
	return out


## Number of defined achievements the player has unlocked.
func unlocked_count() -> int:
	var count: int = 0
	for def: Dictionary in _defs:
		if _profile.achievements.has(def["id"]):
			count += 1
	return count


## Number of valid achievement definitions.
func total_count() -> int:
	return _defs.size()


## Hidden achievements that are still locked (for an honest "N secrets left").
func hidden_locked_count() -> int:
	var count: int = 0
	for def: Dictionary in _defs:
		if bool(def["hidden"]) and not _profile.achievements.has(def["id"]):
			count += 1
	return count


## Checks the definitions as provided and returns one message per problem
## (empty when everything is valid). [param known_stats] is the list of stat
## names the game maintains, usually [constant KNOWN_STATS].
func validate_definitions(known_stats: PackedStringArray) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	for i: int in _raw_definitions.size():
		var raw: Variant = _raw_definitions[i]
		if typeof(raw) != TYPE_DICTIONARY:
			errors.append("entry %d is not an object" % i)
			continue
		var def: Dictionary = raw as Dictionary
		var id: String = str(def.get("id", ""))
		var label: String = id if not id.is_empty() else "entry %d" % i
		if id.is_empty():
			errors.append("%s: missing id" % label)
		elif seen.has(id):
			errors.append("%s: duplicate id" % label)
		seen[id] = true
		for key: String in ["name_key", "desc_key"]:
			if str(def.get(key, "")).is_empty():
				errors.append("%s: missing %s" % [label, key])
		if not CATEGORIES.has(str(def.get("category", ""))):
			errors.append("%s: unknown category '%s'" % [label, str(def.get("category", ""))])
		var stat_name: String = str(def.get("stat", ""))
		if not known_stats.has(stat_name):
			errors.append("%s: unknown stat '%s'" % [label, stat_name])
		if _positive_int(def.get("target", null)) <= 0:
			errors.append("%s: target must be a positive integer" % label)
		if def.has("hidden") and typeof(def["hidden"]) != TYPE_BOOL:
			errors.append("%s: hidden must be a boolean" % label)
		if not def.has("reward"):
			errors.append("%s: missing reward" % label)
		for problem: String in AchievementService.validate_reward(def.get("reward", {})):
			errors.append("%s: %s" % [label, problem])
	return errors


## Validates a reward spec ([code]{"coins", "gems", "xp", "badge", "cosmetic"}[/code]).
## Returns the problems found (empty when valid).
static func validate_reward(reward: Variant) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if typeof(reward) != TYPE_DICTIONARY:
		errors.append("reward must be an object")
		return errors
	var spec: Dictionary = reward as Dictionary
	for key: Variant in spec:
		var k: String = str(key)
		var v: Variant = spec[key]
		if REWARD_AMOUNT_KEYS.has(k):
			if not _is_integral(v) or int(v) < 0:
				errors.append("reward %s must be a non-negative integer" % k)
		elif REWARD_ID_KEYS.has(k):
			if typeof(v) != TYPE_STRING or str(v).is_empty():
				errors.append("reward %s must be a non-empty id" % k)
			elif k == "badge" and not str(v).begins_with(BADGE_PREFIX):
				errors.append("reward badge '%s' must start with %s" % [str(v), BADGE_PREFIX])
		else:
			errors.append("unknown reward key '%s'" % k)
	return errors


func _unlock(def: Dictionary) -> void:
	var id: String = def["id"]
	# Record first: even if granting fails the reward can never be paid twice.
	_profile.achievements[id] = _clock.now_unix()
	var count: int = maxi(_profile.stat(STAT_ACHIEVEMENTS_UNLOCKED) + 1, unlocked_count())
	_profile.stats[STAT_ACHIEVEMENTS_UNLOCKED] = count
	_bus.stat_changed.emit(StringName(STAT_ACHIEVEMENTS_UNLOCKED), count)
	var reward: Dictionary = def["reward"]
	if not _reward_is_empty(reward):
		if _reward_grant.is_valid():
			_reward_grant.call(reward.duplicate(), REWARD_SOURCE_PREFIX + id)
		else:
			GameLog.error(LOG_CHANNEL, "no reward handler; reward for %s not granted" % id)
	GameLog.info(LOG_CHANNEL, "unlocked %s" % id)
	_bus.achievement_unlocked.emit(id)


func _build_index() -> void:
	_defs.clear()
	_index.clear()
	for raw: Variant in _raw_definitions:
		var def: Dictionary = _sanitize(raw)
		if def.is_empty():
			continue
		var id: String = def["id"]
		if _index.has(id):
			GameLog.warn(LOG_CHANNEL, "duplicate achievement id %s ignored" % id)
			continue
		_index[id] = _defs.size()
		_defs.append(def)
	if _defs.is_empty():
		GameLog.error(LOG_CHANNEL, "no valid achievement definitions")


## Returns a typed copy of a definition, or {} when it cannot be used.
func _sanitize(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		GameLog.warn(LOG_CHANNEL, "skipping non-object achievement entry")
		return {}
	var def: Dictionary = raw as Dictionary
	var id: String = str(def.get("id", ""))
	var stat_name: String = str(def.get("stat", ""))
	var target: int = _positive_int(def.get("target", null))
	if id.is_empty() or stat_name.is_empty() or target <= 0:
		GameLog.warn(LOG_CHANNEL, "skipping invalid achievement '%s'" % id)
		return {}
	if not KNOWN_STATS.has(stat_name):
		# It could never unlock; keep it out of the list instead of showing a dead goal.
		GameLog.warn(LOG_CHANNEL, "skipping achievement %s on unknown stat '%s'" % [id, stat_name])
		return {}
	var category: String = str(def.get("category", ""))
	if not CATEGORIES.has(category):
		GameLog.warn(LOG_CHANNEL, "achievement %s has unknown category '%s'" % [id, category])
	var reward: Dictionary = {}
	if AchievementService.validate_reward(def.get("reward", {})).is_empty():
		reward = (def.get("reward", {}) as Dictionary).duplicate()
		for key: String in REWARD_AMOUNT_KEYS:
			if reward.has(key):
				reward[key] = int(reward[key])
	else:
		GameLog.warn(LOG_CHANNEL, "achievement %s has an invalid reward; it unlocks without one" % id)
	return {
		"id": id,
		"name_key": str(def.get("name_key", "ach.%s.name" % id)),
		"desc_key": str(def.get("desc_key", "ach.%s.desc" % id)),
		"category": category,
		"stat": stat_name,
		"target": target,
		"reward": reward,
		"hidden": typeof(def.get("hidden", false)) == TYPE_BOOL and bool(def.get("hidden", false)),
	}


static func _reward_is_empty(reward: Dictionary) -> bool:
	for key: String in REWARD_AMOUNT_KEYS:
		if int(reward.get(key, 0)) > 0:
			return false
	for key: String in REWARD_ID_KEYS:
		if not str(reward.get(key, "")).is_empty():
			return false
	return true


## Integer value of a JSON number, or 0 when not a positive whole number.
static func _positive_int(v: Variant) -> int:
	if not _is_integral(v):
		return 0
	return maxi(0, int(v))


static func _is_integral(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		return is_finite(f) and f == floorf(f)
	return false
