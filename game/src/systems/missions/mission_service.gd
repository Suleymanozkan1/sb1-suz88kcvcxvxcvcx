class_name MissionService
extends RefCounted
## Daily and weekly missions chosen deterministically from data templates.
##
## Every UTC day (and every ISO week) [method refresh] assigns a new set of
## missions: a [DetRng] seeded with [code]"missions:<kind>:<period key>"[/code]
## shuffles the eligible templates, picks [code]<kind>_count[/code] distinct
## ones (preferring different stats) and one target per template. Each mission
## stores the stat value at assignment as its baseline, so progress is
## [code]current - baseline[/code]: only play after the assignment counts.
##
## Combo missions use the virtual stats [constant STAT_BEST_COMBO_TODAY] and
## [constant STAT_BEST_COMBO_WEEK], which this service maintains from
## [signal EventBus.combo_reached] (best combo of the current period).
##
## Fair by design: unfinished missions simply expire at the reset (no penalty,
## nothing is taken away), [method time_left_seconds] reports the real reset
## time, and templates with a [code]requires[/code] gate are only offered once
## the player has reached the content they need. The service owns only
## [member PlayerProfile.missions].

const DEFAULT_PATH: String = "res://data/missions/missions.json"
const LOG_CHANNEL: String = "missions"
const KIND_DAILY: String = "daily"
const KIND_WEEKLY: String = "weekly"
const KINDS: PackedStringArray = [KIND_DAILY, KIND_WEEKLY]
const SEED_PREFIX: String = "missions:"
const REWARD_SOURCE_PREFIX: String = "mission:"
const STAT_BEST_COMBO_TODAY: String = "best_combo_today"
const STAT_BEST_COMBO_WEEK: String = "best_combo_week"
## Stats that hold a maximum rather than a running total; "current - baseline"
## is meaningless for them, so templates may not use them.
const MAX_STATS: PackedStringArray = ["max_combo", "daily_streak_max", "endless_best_distance"]
const SECONDS_PER_DAY: int = 86400
const DAYS_PER_WEEK: int = 7
## 1970-01-01 (day 0) was a Thursday; adding 3 gives a Monday-based weekday.
const EPOCH_WEEKDAY_OFFSET: int = 3
const DEFAULT_COUNT: int = 3
const MAX_COUNT: int = 6
const DEFAULT_REWARD_STEP: float = 0.25
const DEFAULT_SCALED_KEYS: PackedStringArray = ["coins", "xp"]
## Claimed mission ids remembered so a re-assigned period (e.g. after a device
## clock change) can never pay the same mission twice.
const CLAIM_HISTORY_LIMIT: int = 32
const HISTORY_KEY: String = "claimed_ids"

var _profile: PlayerProfile
var _bus: EventBus
var _clock: GameClock
var _reward_grant: Callable
var _config: Dictionary = {}
## kind -> int missions per period.
var _counts: Dictionary = {}
## kind -> Array[Dictionary] sanitised templates.
var _templates: Dictionary = {}
var _reward_step: float = DEFAULT_REWARD_STEP
var _scaled_keys: PackedStringArray = DEFAULT_SCALED_KEYS


## [param reward_grant] has the signature
## [code](spec: Dictionary, source: String) -> RewardBundle[/code].
## When [param config] is empty the shipped data file is loaded. Connects to
## the bus (combo, stat and run-start signals) and assigns the current missions.
func _init(
	profile: PlayerProfile, bus: EventBus, clock: GameClock, reward_grant: Callable, config: Dictionary = {}
) -> void:
	_profile = profile
	_bus = bus
	_clock = clock
	_reward_grant = reward_grant
	_config = config if not config.is_empty() else MissionService.load_config()
	_apply_config()
	_bus.combo_reached.connect(on_combo)
	_bus.stat_changed.connect(_on_stat_changed)
	_bus.run_started.connect(_on_run_started)
	refresh()


## Loads the mission configuration (returns {} and logs when unavailable).
static func load_config(path: String = DEFAULT_PATH) -> Dictionary:
	var data: Dictionary = JsonIO.read_dict(path)
	if data.is_empty():
		GameLog.error(LOG_CHANNEL, "no mission config in %s" % path)
	return data


## Assigns new missions when the UTC date (daily) or ISO week (weekly) changed
## since the last assignment, or when the stored state is unusable. Returns
## true when anything was (re)assigned. Old unclaimed missions just expire.
func refresh() -> bool:
	var changed: bool = false
	for kind: String in KINDS:
		var key: String = period_key(kind)
		var stored: Variant = _profile.missions.get(kind, null)
		var same_period: bool = typeof(stored) == TYPE_DICTIONARY and str((stored as Dictionary).get("key", "")) == key
		if same_period and _slice_valid(stored as Dictionary):
			continue
		if same_period:
			GameLog.warn(LOG_CHANNEL, "stored %s missions were unreadable; reassigned" % kind)
		_profile.missions[kind] = _assign(kind, key)
		changed = true
	return changed


## Current missions of [param kind] ("daily" or "weekly"). Each entry:
## [code]{"id", "kind", "template", "desc_key", "desc_args", "stat", "target",
## "progress", "complete", "claimed", "reward"}[/code].
func active(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not KINDS.has(kind):
		GameLog.warn(LOG_CHANNEL, "unknown mission kind '%s'" % kind)
		return out
	refresh()
	for record: Dictionary in _records(kind):
		out.append(_view(kind, record))
	return out


## Claims the reward of a completed mission. Works only once per mission and
## only when it is complete; otherwise returns an empty bundle. On success the
## reward is granted through [code]reward_grant[/code], the mission is marked
## claimed and [signal EventBus.mission_completed] is emitted.
func claim(mission_id: String) -> RewardBundle:
	var empty: RewardBundle = RewardBundle.new(REWARD_SOURCE_PREFIX + mission_id)
	refresh()
	var record: Dictionary = _locate(mission_id)
	if record.is_empty():
		GameLog.warn(LOG_CHANNEL, "claim for unknown or expired mission %s" % mission_id)
		return empty
	if bool(record["claimed"]) or _progress(record) < int(record["target"]):
		return empty
	# Mark first so a failing grant can never be retried into a double payout.
	record["claimed"] = true
	_remember_claim(mission_id)
	var granted: Variant = null
	if _reward_grant.is_valid():
		granted = _reward_grant.call((record["reward"] as Dictionary).duplicate(), REWARD_SOURCE_PREFIX + mission_id)
	else:
		GameLog.error(LOG_CHANNEL, "no reward handler; reward for %s not granted" % mission_id)
	_bus.mission_completed.emit(mission_id)
	if granted is RewardBundle:
		return granted as RewardBundle
	return empty


## Records a combo reached during a run (connected to
## [signal EventBus.combo_reached]); keeps the best combo of the current day
## and week for the combo missions.
func on_combo(combo: int) -> void:
	if combo <= 0:
		return
	refresh()
	for kind: String in KINDS:
		var slice: Dictionary = _profile.missions[kind]
		if combo > int(slice.get("best_combo", 0)):
			slice["best_combo"] = combo
			_announce(_combo_stat(kind))


## Seconds until the missions of [param kind] reset (next UTC midnight, or
## next Monday 00:00 UTC for weekly). Matches [method refresh] exactly.
func time_left_seconds(kind: String) -> int:
	var now: int = _clock.now_unix()
	if kind == KIND_DAILY:
		return SECONDS_PER_DAY - posmod(now, SECONDS_PER_DAY)
	if kind == KIND_WEEKLY:
		var day: int = _clock.day_number()
		var weekday: int = posmod(day + EPOCH_WEEKDAY_OFFSET, DAYS_PER_WEEK)
		var next_monday: int = day - weekday + DAYS_PER_WEEK
		return next_monday * SECONDS_PER_DAY - now
	GameLog.warn(LOG_CHANNEL, "unknown mission kind '%s'" % kind)
	return 0


## The period identifier missions of [param kind] are assigned for:
## "YYYY-MM-DD" for daily, "YYYY-Www" for weekly ("" for unknown kinds).
func period_key(kind: String) -> String:
	if kind == KIND_DAILY:
		return _clock.date_key()
	if kind == KIND_WEEKLY:
		return _clock.week_key()
	return ""


## Number of missions assigned per period of [param kind].
func mission_count(kind: String) -> int:
	return int(_counts.get(kind, 0))


## Sanitised templates of [param kind] (copies).
func templates(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: Dictionary in _templates.get(kind, []) as Array:
		out.append(t.duplicate(true))
	return out


## Completed but unclaimed missions across both kinds (for a menu badge).
func claimable_count() -> int:
	var count: int = 0
	refresh()
	for kind: String in KINDS:
		for record: Dictionary in _records(kind):
			if not bool(record["claimed"]) and _progress(record) >= int(record["target"]):
				count += 1
	return count


## Checks the configuration as provided and returns one message per problem
## (empty when valid). [param known_stats] lists the lifetime stat names;
## the virtual combo stats are always accepted for their own kind.
func validate_config(known_stats: PackedStringArray) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	for kind: String in KINDS:
		var count: Variant = _config.get(kind + "_count", null)
		if not _is_integral(count) or int(count) < 1 or int(count) > MAX_COUNT:
			errors.append("%s_count must be an integer in 1..%d" % [kind, MAX_COUNT])
		var list_value: Variant = _config.get(kind + "_templates", null)
		if typeof(list_value) != TYPE_ARRAY:
			errors.append("%s_templates must be an array" % kind)
			continue
		var list: Array = list_value as Array
		if _is_integral(count) and list.size() < int(count):
			errors.append("%s_templates has fewer entries than %s_count" % [kind, kind])
		var seen: Dictionary = {}
		for i: int in list.size():
			for problem: String in _template_problems(list[i], kind, known_stats):
				errors.append("%s template %d: %s" % [kind, i, problem])
			if typeof(list[i]) == TYPE_DICTIONARY:
				var id: String = str((list[i] as Dictionary).get("id", ""))
				if seen.has(id):
					errors.append("%s template %d: duplicate id '%s'" % [kind, i, id])
				seen[id] = true
	return errors


func _apply_config() -> void:
	for kind: String in KINDS:
		var count: Variant = _config.get(kind + "_count", DEFAULT_COUNT)
		_counts[kind] = clampi(int(count), 1, MAX_COUNT) if _is_integral(count) else DEFAULT_COUNT
		var list: Array[Dictionary] = []
		var ids: Dictionary = {}
		var raw_list: Variant = _config.get(kind + "_templates", [])
		if typeof(raw_list) != TYPE_ARRAY:
			raw_list = []
		for raw: Variant in raw_list as Array:
			var t: Dictionary = _sanitize_template(raw, kind)
			if t.is_empty() or ids.has(t["id"]):
				continue
			ids[t["id"]] = true
			list.append(t)
		if list.is_empty():
			GameLog.error(LOG_CHANNEL, "no usable %s mission templates" % kind)
		_templates[kind] = list
	var scaling: Variant = _config.get("reward_scaling", {})
	if typeof(scaling) == TYPE_DICTIONARY:
		var step: Variant = (scaling as Dictionary).get("step_per_target_index", DEFAULT_REWARD_STEP)
		if typeof(step) == TYPE_FLOAT or typeof(step) == TYPE_INT:
			_reward_step = maxf(0.0, float(step))
		var keys: Variant = (scaling as Dictionary).get("keys", null)
		if typeof(keys) == TYPE_ARRAY:
			_scaled_keys = PackedStringArray()
			for k: Variant in keys as Array:
				_scaled_keys.append(str(k))


func _sanitize_template(raw: Variant, kind: String) -> Dictionary:
	# A template on an unknown stat could never progress, so it is dropped too.
	var problems: PackedStringArray = _template_problems(raw, kind, AchievementService.KNOWN_STATS)
	if not problems.is_empty():
		GameLog.warn(LOG_CHANNEL, "skipping %s template: %s" % [kind, "; ".join(problems)])
		return {}
	var t: Dictionary = raw as Dictionary
	var targets: Array[int] = []
	for v: Variant in t["targets"] as Array:
		targets.append(int(v))
	var reward: Dictionary = (t["reward"] as Dictionary).duplicate()
	for key: String in AchievementService.REWARD_AMOUNT_KEYS:
		if reward.has(key):
			reward[key] = int(reward[key])
	var requires: Dictionary = {}
	if t.has("requires"):
		var req: Dictionary = t["requires"]
		requires = {"stat": str(req["stat"]), "min": int(req["min"])}
	var id: String = t["id"]
	return {
		"id": id,
		"desc_key": str(t.get("desc_key", "mis.%s.desc" % id)),
		"stat": str(t["stat"]),
		"targets": targets,
		"reward": reward,
		"requires": requires,
	}


## Problems of one raw template. An empty [param known_stats] skips the
## stat-name check (runtime sanitising).
func _template_problems(raw: Variant, kind: String, known_stats: PackedStringArray) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		problems.append("not an object")
		return problems
	var t: Dictionary = raw as Dictionary
	if typeof(t.get("id", null)) != TYPE_STRING or str(t["id"]).is_empty():
		problems.append("missing id")
	if str(t.get("desc_key", "")).is_empty():
		problems.append("missing desc_key")
	var stat_name: String = str(t.get("stat", ""))
	if stat_name.is_empty():
		problems.append("missing stat")
	elif MAX_STATS.has(stat_name):
		problems.append("stat '%s' is a maximum, not a counter" % stat_name)
	elif _is_virtual(stat_name):
		if stat_name != _combo_stat(kind):
			problems.append("stat '%s' does not belong to %s missions" % [stat_name, kind])
	elif not known_stats.is_empty() and not known_stats.has(stat_name):
		problems.append("unknown stat '%s'" % stat_name)
	var targets: Variant = t.get("targets", null)
	if typeof(targets) != TYPE_ARRAY or (targets as Array).is_empty():
		problems.append("targets must be a non-empty array")
	else:
		for v: Variant in targets as Array:
			if not _is_integral(v) or int(v) <= 0:
				problems.append("targets must be positive integers")
				break
	if not t.has("reward"):
		problems.append("missing reward")
	problems.append_array(AchievementService.validate_reward(t.get("reward", {})))
	if t.has("requires"):
		var req: Variant = t["requires"]
		if (
			typeof(req) != TYPE_DICTIONARY
			or str((req as Dictionary).get("stat", "")).is_empty()
			or not _is_integral((req as Dictionary).get("min", null))
		):
			problems.append("requires must be {\"stat\": String, \"min\": int}")
		elif not known_stats.is_empty() and not known_stats.has(str((req as Dictionary)["stat"])):
			problems.append("unknown stat '%s' in requires" % str((req as Dictionary)["stat"]))
	return problems


func _assign(kind: String, key: String) -> Dictionary:
	var eligible: Array[Dictionary] = _eligible(kind)
	var count: int = mini(int(_counts[kind]), eligible.size())
	var rng: DetRng = DetRng.new(DetRng.hash_string(SEED_PREFIX + kind + ":" + key))
	var order: Array[int] = []
	for i: int in eligible.size():
		order.append(i)
	rng.shuffle(order)
	var picked: Array[int] = []
	var used_stats: Dictionary = {}
	for i: int in order:
		if picked.size() < count and not used_stats.has(eligible[i]["stat"]):
			used_stats[eligible[i]["stat"]] = true
			picked.append(i)
	# Fill up with repeated stats only when distinct ones ran out.
	for i: int in order:
		if picked.size() < count and not picked.has(i):
			picked.append(i)
	var claimed_before: Array = _claim_history()
	var records: Array = []
	for i: int in picked:
		var t: Dictionary = eligible[i]
		var targets: Array[int] = t["targets"]
		var target_index: int = rng.range_int(0, targets.size() - 1)
		var stat_name: String = t["stat"]
		var id: String = "%s:%s:%s" % [kind, key, t["id"]]
		records.append(
			{
				"id": id,
				"template": t["id"],
				"desc_key": t["desc_key"],
				"stat": stat_name,
				"target": targets[target_index],
				"baseline": 0 if _is_virtual(stat_name) else _profile.stat(stat_name),
				"claimed": claimed_before.has(id),
				"reward": _scaled_reward(t["reward"], target_index),
			}
		)
	GameLog.info(LOG_CHANNEL, "assigned %d %s missions for %s" % [records.size(), kind, key])
	return {"key": key, "assigned_at": _clock.now_unix(), "best_combo": 0, "missions": records}


func _eligible(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: Dictionary in _templates.get(kind, []) as Array:
		var req: Dictionary = t["requires"]
		if req.is_empty() or _profile.stat(str(req["stat"])) >= int(req["min"]):
			out.append(t)
	return out


func _scaled_reward(reward: Dictionary, target_index: int) -> Dictionary:
	var out: Dictionary = reward.duplicate()
	var factor: float = 1.0 + _reward_step * float(target_index)
	for key: String in _scaled_keys:
		if out.has(key) and AchievementService.REWARD_AMOUNT_KEYS.has(key):
			out[key] = roundi(float(out[key]) * factor)
	return out


## Progress of a stored mission, clamped to 0..target.
func _progress(record: Dictionary) -> int:
	var stat_name: String = str(record["stat"])
	var value: int = 0
	if _is_virtual(stat_name):
		var combo_kind: String = KIND_DAILY if stat_name == STAT_BEST_COMBO_TODAY else KIND_WEEKLY
		value = int((_profile.missions[combo_kind] as Dictionary).get("best_combo", 0))
	else:
		value = _profile.stat(stat_name) - int(record["baseline"])
	return clampi(value, 0, int(record["target"]))


func _view(kind: String, record: Dictionary) -> Dictionary:
	var target: int = int(record["target"])
	var progress: int = _progress(record)
	return {
		"id": str(record["id"]),
		"kind": kind,
		"template": str(record.get("template", "")),
		"desc_key": str(record.get("desc_key", "")),
		"desc_args": {"target": target},
		"stat": str(record["stat"]),
		"target": target,
		"progress": progress,
		"complete": progress >= target,
		"claimed": bool(record["claimed"]),
		"reward": (record["reward"] as Dictionary).duplicate(),
	}


func _records(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Variant in (_profile.missions[kind] as Dictionary)["missions"] as Array:
		out.append(raw as Dictionary)
	return out


## The stored record of a current mission (shared, so edits persist), or {}.
func _locate(mission_id: String) -> Dictionary:
	for kind: String in KINDS:
		for record: Dictionary in _records(kind):
			if str(record["id"]) == mission_id:
				return record
	return {}


## Emits mission_progressed for every unclaimed current mission on [param stat_name].
func _announce(stat_name: String) -> void:
	for kind: String in KINDS:
		for record: Dictionary in _records(kind):
			if str(record["stat"]) == stat_name and not bool(record["claimed"]):
				_bus.mission_progressed.emit(str(record["id"]), _progress(record), int(record["target"]))


func _claim_history() -> Array:
	var history: Variant = _profile.missions.get(HISTORY_KEY, [])
	return history as Array if typeof(history) == TYPE_ARRAY else []


func _remember_claim(mission_id: String) -> void:
	var history: Array = _claim_history().duplicate()
	history.append(mission_id)
	while history.size() > CLAIM_HISTORY_LIMIT:
		history.remove_at(0)
	_profile.missions[HISTORY_KEY] = history


func _slice_valid(slice: Dictionary) -> bool:
	if not _is_integral(slice.get("best_combo", 0)):
		return false
	var missions: Variant = slice.get("missions", null)
	if typeof(missions) != TYPE_ARRAY:
		return false
	for raw: Variant in missions as Array:
		if typeof(raw) != TYPE_DICTIONARY:
			return false
		var r: Dictionary = raw as Dictionary
		var shaped: bool = (
			typeof(r.get("id", null)) == TYPE_STRING
			and typeof(r.get("stat", null)) == TYPE_STRING
			and typeof(r.get("claimed", null)) == TYPE_BOOL
			and typeof(r.get("reward", null)) == TYPE_DICTIONARY
			and _is_integral(r.get("target", null))
			and int(r.get("target", 0)) > 0
			and _is_integral(r.get("baseline", null))
		)
		if not shaped:
			return false
	return true


func _on_stat_changed(stat: StringName, _value: int) -> void:
	refresh()
	_announce(String(stat))


func _on_run_started(_level_id: String, _mode: StringName) -> void:
	# A new period that began while the player sat in a menu is assigned before
	# the run's stats are recorded, so this run counts toward the new missions.
	refresh()


static func _combo_stat(kind: String) -> String:
	return STAT_BEST_COMBO_TODAY if kind == KIND_DAILY else STAT_BEST_COMBO_WEEK


static func _is_virtual(stat_name: String) -> bool:
	return stat_name == STAT_BEST_COMBO_TODAY or stat_name == STAT_BEST_COMBO_WEEK


static func _is_integral(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		return is_finite(f) and f == floorf(f)
	return false
