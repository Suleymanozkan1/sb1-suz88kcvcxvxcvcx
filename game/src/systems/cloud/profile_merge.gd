class_name ProfileMerge
extends RefCounted
## Deterministic, pure merge of two player profiles for cloud saves (REQ-182).
##
## Both inputs are dictionaries in [method PlayerProfile.to_dict] shape
## (callers pass sanitised data: [method PlayerProfile.from_dict] output);
## neither is modified. [param local] is this device, [param remote] the cloud
## copy. The rules keep every bit of progress made on either device, apply
## every spend and earning exactly once and never create currency:
## [br]- [b]levels[/b]: union by level id; for a level on both sides stars,
##   best_score, clears, attempts and best_combo take the maximum, perfect is
##   true when either side is perfect, best_time is the smaller positive time
##   (0 means "no time").
## [br]- [b]unlocked_worlds, cosmetics_owned, purchases[/b]: union (local
##   order first, then remote-only entries in remote order), so an item bought
##   on both devices is owned once.
## [br]- [b]xp, player_level[/b]: maximum. [b]stats[/b]: maximum per key
##   (lifetime counters and bests only ever grow; coins_earned included, so
##   coins that arrive with a merge never count as earned here).
## [br]- [b]achievements[/b]: union, keeping the earliest unlock time.
## [br]- [b]missions[/b]: per kind (daily / weekly) the slice of the later
##   period key wins; for the same period a mission claimed on either side
##   stays claimed and best_combo takes the maximum. The claimed-id history
##   is a union (bounded like [MissionService]), so no mission pays twice.
## [br]- [b]daily[/b]: results per date key keep the better result (best
##   score, attempts, completions and tier by maximum, completed when either
##   completed, the earliest first completion time); streak, tier and
##   last_day come from the side with the later last_day, but a remote
##   last_day beyond today plus the daily grace (a device clock running ahead)
##   is never adopted, as it would block every daily; streak_best takes the
##   maximum.
## [br]- [b]coins, gems, bonus_stars, ledger[/b]: three-way merge against the
##   base, the wallet this device and the cloud last shared ([WalletMerge]
##   has the exact rule): remote + (local - base) per currency, clamped at 0,
##   so both devices' spends and earnings apply once whatever their clocks
##   say; a purchase or once-per-account reward made on both devices counts
##   once. A device that never synced adds only what it holds beyond the
##   starting wallet; a pristine wallet never replaces or reduces the cloud's.
## [br]- [b]flags[/b]: local wins; remote-only flags are adopted except the
##   device-local cloud.* bookkeeping. Exceptions: mode_best takes the maximum
##   per mode, sync.pushes the maximum per device, bonus_chest_day the later
##   day (one chest a day across devices) but never a remote day after today.
## [br]- [b]install_id, settings, cosmetics_equipped, pending_submissions[/b]
##   and any other key: local (device-specific state); keys only the remote
##   has are adopted.
## [br]- [b]created_at[/b]: the earliest positive time.
## [br]A cloud copy with exactly this device's content
## ([method travelling]) is this device's own state: nothing changes but the
## base. The merge is idempotent (merging the same cloud copy again changes
## nothing; merge(a, a) == a for a profile whose base is its own wallet) and,
## for the union and maximum rules, independent of the argument order.
## [br][br]
## [b]Base bookkeeping[/b] (cloud.* flags, never travel): cloud.base
## {coins, gems, bonus_stars} and cloud.base_ledger {ledger id: count} are the
## base. Every merge records the cloud copy it merged as the new base (this
## device now contains it); [CloudSaveService] records the pushed copy after
## every accepted push. Before a push the device stores the copy it sends as
## cloud.pending / cloud.pending_ledger with a sequence number seq, and counts
## that push in the travelling flag sync.pushes {cloud.device id: last seq}.
## When a cloud copy shows sync.pushes[this device] >= the pending seq, that
## push reached the cloud even though its answer was lost, so the pending copy
## is the base: this device's changes are never counted twice. A save that
## synced before bases existed (a cloud.revision without a base) rebuilds it
## from the ledger entries dated up to cloud.synced_at.

const CLOUD_FLAG_PREFIX: String = "cloud."
const FLAG_REVISION: String = "cloud.revision"
const FLAG_SYNCED_AT: String = "cloud.synced_at"
const FLAG_DEVICE: String = "cloud.device"
const FLAG_BASE: String = "cloud.base"
const FLAG_BASE_LEDGER: String = "cloud.base_ledger"
const FLAG_PENDING: String = "cloud.pending"
const FLAG_PENDING_LEDGER: String = "cloud.pending_ledger"
const FLAG_PUSHES: String = "sync.pushes"
const PENDING_SEQ: String = "seq"
const FLAG_MODE_BEST: String = "mode_best"
const FLAG_BONUS_CHEST_DAY: String = "bonus_chest_day"
## Profile fields that never travel to another device.
const DEVICE_LOCAL_KEYS: PackedStringArray = ["settings", "cosmetics_equipped", "pending_submissions"]
const KEY_LEDGER: String = "ledger"
const KEY_FLAGS: String = "flags"
const KEY_LEVELS: String = "levels"
const KEY_STATS: String = "stats"
const KEY_ACHIEVEMENTS: String = "achievements"
const KEY_MISSIONS: String = "missions"
const KEY_DAILY: String = "daily"
const KEY_CREATED_AT: String = "created_at"
const KEY_PENDING: String = "pending_submissions"
const MAX_KEYS: PackedStringArray = ["xp", "player_level"]
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
const SECONDS_PER_DAY: int = 86400
## Day value of a daily slice that never completed a challenge.
const NO_DAY: int = -1
## Latest day of [method merge_daily] / [method merge_flags] when no limit applies.
const NO_DAY_LIMIT: int = 1 << 62


## Merges [param local] (this device) with [param remote] (the cloud copy).
## [param now_unix] is this device's clock (today's day and "cloud_sync"
## ledger entries); [param starting] is the economy's starting wallet
## {"coins", "gems"} (what a device that never synced holds without earning
## it); [param grace_days] is the daily challenge's late grace. Returns a new
## dictionary whose cloud flags record [param remote] as the new base.
static func merge(
	local: Dictionary,
	remote: Dictionary,
	now_unix: int,
	starting: Dictionary = {},
	grace_days: int = DailyChallengeService.DEFAULT_GRACE_DAYS
) -> Dictionary:
	var landed: bool = ProfileMerge.pending_landed(local, remote)
	var out: Dictionary = local.duplicate(true)
	if not ProfileMerge._same_content(local, remote):
		out = ProfileMerge._merge_content(local, remote, floori(now_unix / float(SECONDS_PER_DAY)), grace_days)
		var base: Dictionary = ProfileMerge._base_of(local, remote, landed)
		out.merge(WalletMerge.merge(local, remote, base, starting, now_unix), true)
	var flags: Dictionary = ProfileMerge._dict(out.get(KEY_FLAGS))
	flags[FLAG_BASE] = WalletMerge.wallet_of(remote)
	flags[FLAG_BASE_LEDGER] = WalletMerge.ledger_ids(remote.get(KEY_LEDGER))
	if landed:
		flags.erase(FLAG_PENDING)
		flags.erase(FLAG_PENDING_LEDGER)
	out[KEY_FLAGS] = flags
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
		out[history_key] = history.slice(maxi(0, history.size() - MissionService.CLAIM_HISTORY_LIMIT))
	return out


## Daily challenge slice: see the class description. A remote last_day after
## [param latest_day] is never adopted.
static func merge_daily(local: Dictionary, remote: Dictionary, latest_day: int = NO_DAY_LIMIT) -> Dictionary:
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
	var later: Dictionary = remote if remote_day > local_day and remote_day <= latest_day else local
	for key: String in DAILY_STREAK_FIELDS:
		if later.has(key):
			out[key] = ProfileMerge._copy(later[key])
		elif not local.has(key):
			# Never keep a field of a remote slice that was not adopted.
			out.erase(key)
	if local.has(DAILY_STREAK_BEST) or remote.has(DAILY_STREAK_BEST):
		out[DAILY_STREAK_BEST] = maxi(
			ProfileMerge._int(local.get(DAILY_STREAK_BEST)), ProfileMerge._int(remote.get(DAILY_STREAK_BEST))
		)
	return out


## Flags: see the class description. A remote bonus_chest_day after
## [param latest_day] is never adopted.
static func merge_flags(local: Dictionary, remote: Dictionary, latest_day: int = NO_DAY_LIMIT) -> Dictionary:
	var out: Dictionary = local.duplicate(true)
	for key: Variant in remote:
		if not out.has(key) and not str(key).begins_with(CLOUD_FLAG_PREFIX):
			out[key] = ProfileMerge._copy(remote[key])
	for key2: String in [FLAG_MODE_BEST, FLAG_PUSHES]:
		if local.has(key2) or remote.has(key2):
			out[key2] = ProfileMerge._max_per_key(local.get(key2), remote.get(key2))
	var local_day: Variant = local.get(FLAG_BONUS_CHEST_DAY)
	var remote_day: Variant = remote.get(FLAG_BONUS_CHEST_DAY)
	if ProfileMerge._is_number(remote_day) and int(remote_day) > latest_day:
		if ProfileMerge._is_number(local_day):
			out[FLAG_BONUS_CHEST_DAY] = int(local_day)
		else:
			out.erase(FLAG_BONUS_CHEST_DAY)
	elif ProfileMerge._is_number(local_day) and ProfileMerge._is_number(remote_day):
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


## True when [param remote] shows that the push [param local] recorded as
## cloud.pending reached the cloud (see the class description).
static func pending_landed(local: Dictionary, remote: Dictionary) -> bool:
	var flags: Dictionary = ProfileMerge._dict(local.get(KEY_FLAGS))
	var device: Variant = flags.get(FLAG_DEVICE, "")
	var seq: int = ProfileMerge._int(ProfileMerge._dict(flags.get(FLAG_PENDING)).get(PENDING_SEQ))
	if typeof(device) != TYPE_STRING or (device as String).is_empty() or seq <= 0:
		return false
	var pushes: Dictionary = ProfileMerge._dict(ProfileMerge._dict(remote.get(KEY_FLAGS)).get(FLAG_PUSHES))
	return ProfileMerge._int(pushes.get(device)) >= seq


## The part of [param profile] (to_dict shape) that travels to the cloud: a
## deep copy without the device-local fields and the cloud.* bookkeeping.
static func travelling(profile: Dictionary) -> Dictionary:
	var data: Dictionary = profile.duplicate(true)
	for key: String in DEVICE_LOCAL_KEYS:
		data.erase(key)
	var flags: Dictionary = ProfileMerge._dict(data.get(KEY_FLAGS))
	for key2: Variant in flags.keys():
		if str(key2).begins_with(CLOUD_FLAG_PREFIX):
			flags.erase(key2)
	return data


## Everything but the wallet, with the daily days capped at today (+ grace).
static func _merge_content(local: Dictionary, remote: Dictionary, today: int, grace_days: int) -> Dictionary:
	var out: Dictionary = ProfileMerge._local_first(local, remote)
	for key: String in MAX_KEYS:
		if local.has(key) or remote.has(key):
			out[key] = maxi(ProfileMerge._int(local.get(key)), ProfileMerge._int(remote.get(key)))
	for key2: String in UNION_KEYS:
		if local.has(key2) or remote.has(key2):
			out[key2] = ProfileMerge._union(local.get(key2), remote.get(key2))
	out[KEY_CREATED_AT] = ProfileMerge._earliest(local.get(KEY_CREATED_AT), remote.get(KEY_CREATED_AT))
	out[KEY_LEVELS] = ProfileMerge._merge_records(local.get(KEY_LEVELS), remote.get(KEY_LEVELS))
	out[KEY_STATS] = ProfileMerge._max_per_key(local.get(KEY_STATS), remote.get(KEY_STATS))
	out[KEY_ACHIEVEMENTS] = ProfileMerge._earliest_per_key(local.get(KEY_ACHIEVEMENTS), remote.get(KEY_ACHIEVEMENTS))
	out[KEY_MISSIONS] = ProfileMerge.merge_missions(
		ProfileMerge._dict(local.get(KEY_MISSIONS)), ProfileMerge._dict(remote.get(KEY_MISSIONS))
	)
	out[KEY_DAILY] = ProfileMerge.merge_daily(
		ProfileMerge._dict(local.get(KEY_DAILY)), ProfileMerge._dict(remote.get(KEY_DAILY)), today + maxi(0, grace_days)
	)
	out[KEY_FLAGS] = ProfileMerge.merge_flags(
		ProfileMerge._dict(local.get(KEY_FLAGS)), ProfileMerge._dict(remote.get(KEY_FLAGS)), today
	)
	if local.has(KEY_PENDING) or remote.has(KEY_PENDING):
		# Queued submissions belong to this device; a remote queue would be sent twice.
		out[KEY_PENDING] = ProfileMerge._array(local.get(KEY_PENDING)).duplicate(true)
	return out


## The base of the wallet merge (see [WalletMerge]): the pending push when it
## [param landed], else the recorded base, else one rebuilt for a save that
## synced before bases existed; {} when this device never synced. A field the
## recorded base lacks counts as unchanged (the local value; without its
## ledger ids every local entry counts as known, so none is taken for a repeat).
static func _base_of(local: Dictionary, remote: Dictionary, landed: bool) -> Dictionary:
	var flags: Dictionary = ProfileMerge._dict(local.get(KEY_FLAGS))
	var wallet: Variant = flags.get(FLAG_PENDING) if landed else flags.get(FLAG_BASE)
	var ledger: Variant = flags.get(FLAG_PENDING_LEDGER) if landed else flags.get(FLAG_BASE_LEDGER)
	if typeof(wallet) == TYPE_DICTIONARY:
		var base: Dictionary = WalletMerge.wallet_of(local)
		for key: String in WalletMerge.WALLET_KEYS:
			if ProfileMerge._is_number((wallet as Dictionary).get(key)):
				base[key] = maxi(0, int((wallet as Dictionary)[key]))
		var known: Dictionary = WalletMerge.ledger_ids(local.get(KEY_LEDGER))
		if typeof(ledger) == TYPE_DICTIONARY:
			known = (ledger as Dictionary).duplicate()
		base[WalletMerge.BASE_LEDGER] = known
		return base
	if not CloudSaveProvider.valid_revision(flags.get(FLAG_REVISION, "")).is_empty():
		return WalletMerge.legacy_base(local, remote, ProfileMerge._int(flags.get(FLAG_SYNCED_AT)))
	return {}


## True when both sides carry exactly the same travelling content.
static func _same_content(local: Dictionary, remote: Dictionary) -> bool:
	return JsonIO.canonical(ProfileMerge.travelling(local)) == JsonIO.canonical(ProfileMerge.travelling(remote))


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
	var claimed: Dictionary[String, bool] = {}
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
## Linear: a set tracks the items already taken.
static func _union(a: Variant, b: Variant) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for list: Array in [ProfileMerge._array(a), ProfileMerge._array(b)]:
		for item: Variant in list:
			if not seen.has(item):
				seen[item] = true
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
