class_name ProfileMerge
extends RefCounted
## Deterministic, pure merge of two player profiles for cloud saves (REQ-182).
##
## Both inputs are dictionaries in [method PlayerProfile.to_dict] shape
## (callers pass sanitised data: [method PlayerProfile.from_dict] output);
## neither is modified. The rules keep every bit of progress made on either
## device without ever creating currency:
## [br]- [b]levels[/b]: union by level id; for a level on both sides stars,
##   best_score, clears, attempts and best_combo take the maximum, perfect is
##   true when either side is perfect, best_time is the smaller positive time
##   (0 means "no time").
## [br]- [b]unlocked_worlds, cosmetics_owned, purchases[/b]: union (local
##   order first, then remote-only entries in remote order).
## [br]- [b]xp, player_level, bonus_stars[/b]: maximum. [b]stats[/b]: maximum
##   per key (lifetime counters and bests only ever grow).
## [br]- [b]achievements[/b]: union, keeping the earliest unlock time.
## [br]- [b]missions[/b]: per kind (daily / weekly) the slice of the later
##   period key wins; for the same period a mission claimed on either side
##   stays claimed and best_combo takes the maximum. The claimed-id history
##   is a union (bounded like [MissionService]), so no mission pays twice.
## [br]- [b]daily[/b]: results per date key keep the better result (best
##   score, attempts, completions and tier by maximum, completed when either
##   completed, the earliest first completion time); streak, tier and
##   last_day come from the side with the later last_day; streak_best takes
##   the maximum.
## [br]- [b]coins, gems, ledger[/b]: taken together from the side whose save
##   is newer (ties keep local), never summed or mixed, so spending on one
##   device cannot be undone and nothing is duplicated; the ledger always
##   matches the wallet it describes.
## [br]- [b]flags[/b]: local wins; remote-only flags are adopted except the
##   device-local cloud.* bookkeeping. Exceptions: mode_best takes the maximum
##   per mode, bonus_chest_day the later day (one chest a day across devices).
## [br]- [b]install_id, settings, cosmetics_equipped, pending_submissions[/b]
##   and any other key: local (device-specific state); keys only the remote
##   has are adopted.
## [br]- [b]created_at[/b]: the earliest positive time.
## [br]The merge is idempotent (merge(a, a) == a) and, for the union and
## maximum rules, independent of the argument order.

const CLOUD_FLAG_PREFIX: String = "cloud."
const FLAG_MODE_BEST: String = "mode_best"
const FLAG_BONUS_CHEST_DAY: String = "bonus_chest_day"
const KEY_COINS: String = "coins"
const KEY_GEMS: String = "gems"
const KEY_LEDGER: String = "ledger"
const KEY_FLAGS: String = "flags"
const KEY_LEVELS: String = "levels"
const KEY_STATS: String = "stats"
const KEY_ACHIEVEMENTS: String = "achievements"
const KEY_MISSIONS: String = "missions"
const KEY_DAILY: String = "daily"
const KEY_CREATED_AT: String = "created_at"
const KEY_PENDING: String = "pending_submissions"
const MAX_KEYS: PackedStringArray = ["xp", "player_level", "bonus_stars"]
const UNION_KEYS: PackedStringArray = ["unlocked_worlds", "cosmetics_owned", "purchases"]
const LEVEL_MAX_FIELDS: PackedStringArray = ["stars", "best_score", "clears", "attempts", "best_combo"]
const LEVEL_PERFECT: String = "perfect"
const LEVEL_BEST_TIME: String = "best_time"
const PERIOD_KEY: String = "key"
const PERIOD_MISSIONS: String = "missions"
const PERIOD_BEST_COMBO: String = "best_combo"
const MISSION_ID: String = "id"
const MISSION_CLAIMED: String = "claimed"
const DAILY_RESULTS: String = "results"
const DAILY_LAST_DAY: String = "last_day"
const DAILY_STREAK_BEST: String = "streak_best"
const DAILY_STREAK_FIELDS: PackedStringArray = ["streak", "tier", "last_day"]
const RESULT_MAX_FIELDS: PackedStringArray = ["best", "attempts", "completions", "tier"]
const RESULT_COMPLETED: String = "completed"
const RESULT_FIRST_COMPLETED_AT: String = "first_completed_at"
## Day value of a daily slice that never completed a challenge.
const NO_DAY: int = -1


## Merges [param local] (this device) with [param remote] (the cloud copy).
## [param local_saved_at] / [param remote_saved_at] (unix seconds) date each
## side's state and decide which wallet is newer. Returns a new dictionary.
static func merge(local: Dictionary, remote: Dictionary, local_saved_at: int, remote_saved_at: int) -> Dictionary:
	var out: Dictionary = ProfileMerge._local_first(local, remote)
	for key: String in MAX_KEYS:
		if local.has(key) or remote.has(key):
			out[key] = maxi(ProfileMerge._int(local.get(key)), ProfileMerge._int(remote.get(key)))
	for key: String in UNION_KEYS:
		if local.has(key) or remote.has(key):
			out[key] = ProfileMerge._union(local.get(key), remote.get(key))
	out[KEY_CREATED_AT] = ProfileMerge._earliest(local.get(KEY_CREATED_AT), remote.get(KEY_CREATED_AT))
	out[KEY_LEVELS] = ProfileMerge._merge_records(local.get(KEY_LEVELS), remote.get(KEY_LEVELS))
	out[KEY_STATS] = ProfileMerge._max_per_key(local.get(KEY_STATS), remote.get(KEY_STATS))
	out[KEY_ACHIEVEMENTS] = ProfileMerge._earliest_per_key(
		local.get(KEY_ACHIEVEMENTS), remote.get(KEY_ACHIEVEMENTS)
	)
	out[KEY_MISSIONS] = ProfileMerge.merge_missions(
		ProfileMerge._dict(local.get(KEY_MISSIONS)), ProfileMerge._dict(remote.get(KEY_MISSIONS))
	)
	out[KEY_DAILY] = ProfileMerge.merge_daily(
		ProfileMerge._dict(local.get(KEY_DAILY)), ProfileMerge._dict(remote.get(KEY_DAILY))
	)
	out[KEY_FLAGS] = ProfileMerge.merge_flags(
		ProfileMerge._dict(local.get(KEY_FLAGS)), ProfileMerge._dict(remote.get(KEY_FLAGS))
	)
	if local.has(KEY_PENDING) or remote.has(KEY_PENDING):
		# Queued submissions belong to this device; a remote queue would be sent twice.
		out[KEY_PENDING] = ProfileMerge._array(local.get(KEY_PENDING)).duplicate(true)
	var wallet: Dictionary = remote if remote_saved_at > local_saved_at else local
	out[KEY_COINS] = maxi(0, ProfileMerge._int(wallet.get(KEY_COINS)))
	out[KEY_GEMS] = maxi(0, ProfileMerge._int(wallet.get(KEY_GEMS)))
	out[KEY_LEDGER] = ProfileMerge._array(wallet.get(KEY_LEDGER)).duplicate(true)
	return out


## Mission slices: see the class description.
static func merge_missions(local: Dictionary, remote: Dictionary) -> Dictionary:
	var out: Dictionary = ProfileMerge._local_first(local, remote)
	for kind: String in MissionService.KINDS:
		if local.has(kind) or remote.has(kind):
			out[kind] = ProfileMerge._merge_period(local.get(kind), remote.get(kind))
	var history_key: String = MissionService.HISTORY_KEY
	if local.has(history_key) or remote.has(history_key):
		var history: Array = ProfileMerge._union(local.get(history_key), remote.get(history_key))
		while history.size() > MissionService.CLAIM_HISTORY_LIMIT:
			history.remove_at(0)
		out[history_key] = history
	return out


## Daily challenge slice: see the class description.
static func merge_daily(local: Dictionary, remote: Dictionary) -> Dictionary:
	var out: Dictionary = ProfileMerge._local_first(local, remote)
	if local.has(DAILY_RESULTS) or remote.has(DAILY_RESULTS):
		var results: Dictionary = ProfileMerge._dict(local.get(DAILY_RESULTS)).duplicate(true)
		var theirs: Dictionary = ProfileMerge._dict(remote.get(DAILY_RESULTS))
		for date_key: Variant in theirs:
			var mine: Variant = results.get(date_key)
			if typeof(mine) == TYPE_DICTIONARY and typeof(theirs[date_key]) == TYPE_DICTIONARY:
				results[date_key] = ProfileMerge._merge_daily_result(mine as Dictionary, theirs[date_key] as Dictionary)
			elif typeof(mine) != TYPE_DICTIONARY:
				results[date_key] = ProfileMerge._copy(theirs[date_key])
		out[DAILY_RESULTS] = results
	var local_day: int = ProfileMerge._int_or(local.get(DAILY_LAST_DAY), NO_DAY)
	var remote_day: int = ProfileMerge._int_or(remote.get(DAILY_LAST_DAY), NO_DAY)
	var later: Dictionary = remote if remote_day > local_day else local
	for key: String in DAILY_STREAK_FIELDS:
		if later.has(key):
			out[key] = ProfileMerge._copy(later[key])
	if local.has(DAILY_STREAK_BEST) or remote.has(DAILY_STREAK_BEST):
		out[DAILY_STREAK_BEST] = maxi(
			ProfileMerge._int(local.get(DAILY_STREAK_BEST)), ProfileMerge._int(remote.get(DAILY_STREAK_BEST))
		)
	return out


## Flags: see the class description.
static func merge_flags(local: Dictionary, remote: Dictionary) -> Dictionary:
	var out: Dictionary = local.duplicate(true)
	for key: Variant in remote:
		if not out.has(key) and not str(key).begins_with(CLOUD_FLAG_PREFIX):
			out[key] = ProfileMerge._copy(remote[key])
	if local.has(FLAG_MODE_BEST) or remote.has(FLAG_MODE_BEST):
		out[FLAG_MODE_BEST] = ProfileMerge._max_per_key(local.get(FLAG_MODE_BEST), remote.get(FLAG_MODE_BEST))
	var local_day: Variant = local.get(FLAG_BONUS_CHEST_DAY)
	var remote_day: Variant = remote.get(FLAG_BONUS_CHEST_DAY)
	if ProfileMerge._is_number(local_day) and ProfileMerge._is_number(remote_day):
		out[FLAG_BONUS_CHEST_DAY] = maxi(int(local_day), int(remote_day))
	return out


## True when [param profile] (to_dict shape) holds any play history: a level
## record, XP, an achievement or a purchase. A fresh install has none.
static func has_progress(profile: Dictionary) -> bool:
	return (
		not ProfileMerge._dict(profile.get(KEY_LEVELS)).is_empty()
		or ProfileMerge._int(profile.get("xp")) > 0
		or not ProfileMerge._dict(profile.get(KEY_ACHIEVEMENTS)).is_empty()
		or not ProfileMerge._array(profile.get("purchases")).is_empty()
	)


## A deep copy of [param local] plus deep copies of the keys only
## [param remote] has.
static func _local_first(local: Dictionary, remote: Dictionary) -> Dictionary:
	var out: Dictionary = local.duplicate(true)
	for key: Variant in remote:
		if not out.has(key):
			out[key] = ProfileMerge._copy(remote[key])
	return out


static func _merge_records(local_raw: Variant, remote_raw: Variant) -> Dictionary:
	var out: Dictionary = ProfileMerge._dict(local_raw).duplicate(true)
	var theirs: Dictionary = ProfileMerge._dict(remote_raw)
	for id: Variant in theirs:
		var mine: Variant = out.get(id)
		if typeof(mine) == TYPE_DICTIONARY and typeof(theirs[id]) == TYPE_DICTIONARY:
			out[id] = ProfileMerge._merge_level(mine as Dictionary, theirs[id] as Dictionary)
		elif typeof(mine) != TYPE_DICTIONARY:
			out[id] = ProfileMerge._copy(theirs[id])
	return out


static func _merge_level(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = ProfileMerge._local_first(a, b)
	for key: String in LEVEL_MAX_FIELDS:
		out[key] = maxi(ProfileMerge._int(a.get(key)), ProfileMerge._int(b.get(key)))
	out[LEVEL_PERFECT] = ProfileMerge._is_true(a.get(LEVEL_PERFECT)) or ProfileMerge._is_true(b.get(LEVEL_PERFECT))
	var time_a: float = ProfileMerge._float(a.get(LEVEL_BEST_TIME))
	var time_b: float = ProfileMerge._float(b.get(LEVEL_BEST_TIME))
	if time_a <= 0.0:
		out[LEVEL_BEST_TIME] = maxf(time_b, 0.0)
	elif time_b <= 0.0:
		out[LEVEL_BEST_TIME] = time_a
	else:
		out[LEVEL_BEST_TIME] = minf(time_a, time_b)
	return out


static func _merge_period(local_raw: Variant, remote_raw: Variant) -> Variant:
	if typeof(remote_raw) != TYPE_DICTIONARY:
		return ProfileMerge._copy(local_raw)
	if typeof(local_raw) != TYPE_DICTIONARY:
		return ProfileMerge._copy(remote_raw)
	var mine: Dictionary = local_raw as Dictionary
	var theirs: Dictionary = remote_raw as Dictionary
	var my_key: String = str(mine.get(PERIOD_KEY, ""))
	var their_key: String = str(theirs.get(PERIOD_KEY, ""))
	if my_key != their_key:
		# Period keys ("YYYY-MM-DD" / "YYYY-Www") sort chronologically.
		return theirs.duplicate(true) if their_key > my_key else mine.duplicate(true)
	var out: Dictionary = mine.duplicate(true)
	out[PERIOD_BEST_COMBO] = maxi(
		ProfileMerge._int(mine.get(PERIOD_BEST_COMBO)), ProfileMerge._int(theirs.get(PERIOD_BEST_COMBO))
	)
	var claimed: Dictionary = {}
	for raw: Variant in ProfileMerge._array(theirs.get(PERIOD_MISSIONS)):
		if typeof(raw) == TYPE_DICTIONARY and ProfileMerge._is_true((raw as Dictionary).get(MISSION_CLAIMED)):
			claimed[str((raw as Dictionary).get(MISSION_ID, ""))] = true
	for raw: Variant in ProfileMerge._array(out.get(PERIOD_MISSIONS)):
		if typeof(raw) == TYPE_DICTIONARY and claimed.has(str((raw as Dictionary).get(MISSION_ID, ""))):
			(raw as Dictionary)[MISSION_CLAIMED] = true
	return out


static func _merge_daily_result(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = ProfileMerge._local_first(a, b)
	for key: String in RESULT_MAX_FIELDS:
		if a.has(key) or b.has(key):
			out[key] = maxi(ProfileMerge._int(a.get(key)), ProfileMerge._int(b.get(key)))
	if a.has(RESULT_COMPLETED) or b.has(RESULT_COMPLETED):
		out[RESULT_COMPLETED] = (
			ProfileMerge._is_true(a.get(RESULT_COMPLETED)) or ProfileMerge._is_true(b.get(RESULT_COMPLETED))
		)
	if a.has(RESULT_FIRST_COMPLETED_AT) or b.has(RESULT_FIRST_COMPLETED_AT):
		out[RESULT_FIRST_COMPLETED_AT] = ProfileMerge._earliest(
			a.get(RESULT_FIRST_COMPLETED_AT), b.get(RESULT_FIRST_COMPLETED_AT)
		)
	return out


static func _max_per_key(local_raw: Variant, remote_raw: Variant) -> Dictionary:
	var out: Dictionary = ProfileMerge._dict(local_raw).duplicate(true)
	var theirs: Dictionary = ProfileMerge._dict(remote_raw)
	for key: Variant in theirs:
		if out.has(key):
			out[key] = maxi(ProfileMerge._int(out[key]), ProfileMerge._int(theirs[key]))
		else:
			out[key] = ProfileMerge._copy(theirs[key])
	return out


static func _earliest_per_key(local_raw: Variant, remote_raw: Variant) -> Dictionary:
	var out: Dictionary = ProfileMerge._dict(local_raw).duplicate(true)
	var theirs: Dictionary = ProfileMerge._dict(remote_raw)
	for key: Variant in theirs:
		if out.has(key):
			out[key] = ProfileMerge._earliest(out[key], theirs[key])
		else:
			out[key] = ProfileMerge._copy(theirs[key])
	return out


## The smaller positive time of the two (0 when neither is positive).
static func _earliest(a: Variant, b: Variant) -> int:
	var x: int = ProfileMerge._int(a)
	var y: int = ProfileMerge._int(b)
	if x <= 0:
		return maxi(y, 0)
	if y <= 0:
		return x
	return mini(x, y)


## Union of two lists: [param a] in order, then the items only [param b] has.
static func _union(a: Variant, b: Variant) -> Array:
	var out: Array = ProfileMerge._array(a).duplicate(true)
	for item: Variant in ProfileMerge._array(b):
		if not out.has(item):
			out.append(ProfileMerge._copy(item))
	return out


static func _copy(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		return (value as Dictionary).duplicate(true)
	if typeof(value) == TYPE_ARRAY:
		return (value as Array).duplicate(true)
	return value


static func _dict(value: Variant) -> Dictionary:
	return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


static func _array(value: Variant) -> Array:
	return value as Array if typeof(value) == TYPE_ARRAY else []


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value as float))


static func _int(value: Variant) -> int:
	return ProfileMerge._int_or(value, 0)


static func _int_or(value: Variant, fallback: int) -> int:
	return int(value) if ProfileMerge._is_number(value) else fallback


static func _float(value: Variant) -> float:
	return float(value) if ProfileMerge._is_number(value) else 0.0


## True only for a real boolean true (untrusted data).
static func _is_true(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL and bool(value)
