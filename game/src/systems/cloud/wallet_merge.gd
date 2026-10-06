class_name WalletMerge
extends RefCounted
## Three-way merge of the wallet (coins, gems, bonus stars) and its ledger for
## cloud saves (used by [ProfileMerge]; pure and deterministic).
##
## [b]The base.[/b] Both devices' changes are measured against the base: the
## wallet (and the ledger entries) of the last state this device and the cloud
## shared, recorded in the profile's cloud flags at every successful push and
## every merge (see [ProfileMerge]). Its shape is {"coins", "gems",
## "bonus_stars", "ledger": {ledger id: count}}.
## [br][b]With a base[/b], per currency and for bonus stars:
## [code]merged = max(0, remote + (local - base) - repeated)[/code], so every
## spend and every earning made on either device since the base applies
## exactly once, whatever the device clocks say. "repeated" is what this
## device's new ledger entries (those not in the base) did for an event that
## happens once per account and that the cloud copy already holds: the same
## item bought ("cosmetic:<id>"), the same achievement, mission, player-level
## or world reward ("achievement:<id>", "mission:<id>", "level_up:<n>",
## "world_complete:<n>", including their ":duplicate" / ":ad_double" parts),
## or the daily streak reward or bonus chest of the same UTC day. The cloud
## copy holds such an event when its ledger has an entry with the same source
## (and currency; for the daily ones the same day) or, for achievements, items,
## missions and player levels, when its state shows it (unlocked, owned,
## claimed, reached). A purchase made on both devices is therefore charged
## once (the second charge is refunded, the item is owned once) and a reward
## earned on both is paid once. Bonus stars are not in the ledger: stars of
## one achievement unlocked on both devices before either synced count twice
## (a handful at most); stars of different achievements always add up.
## [br][b]Without a base[/b] (this device never synced): only what it holds
## beyond the starting wallet ([param starting] of [method merge], the
## economy's starting balance) counts as earned here:
## [code]merged = remote + max(0, local - starting - repeated)[/code] and
## [code]stars = remote + local[/code]. A pristine or fresh wallet never
## replaces or reduces the cloud's; the starting balance itself is never added.
## [br][b]The ledger[/b]: the cloud copy's entries plus this device's new ones
## that were not repeats, ordered by time (ties: cloud first), each balance
## recomputed along that order, then trimmed to
## [constant PlayerProfile.LEDGER_LIMIT]. When the newest balances still differ
## from the merged wallet (a refunded repeat, a clamp at 0, the starting
## balance, history beyond the ledger limit) one "cloud_sync" entry per
## currency records the difference, so the newest entry always matches the
## wallet ([IntegrityMonitor]). A cloud copy this device's ledger already
## contains (its own entries plus older ones) leaves the ledger as it is.

const KEY_COINS: String = "coins"
const KEY_GEMS: String = "gems"
const KEY_BONUS_STARS: String = "bonus_stars"
const KEY_LEDGER: String = "ledger"
## Key of the ledger-id counts inside a base.
const BASE_LEDGER: String = "ledger"
const CURRENCY_KEYS: PackedStringArray = [KEY_COINS, KEY_GEMS]
const WALLET_KEYS: PackedStringArray = [KEY_COINS, KEY_GEMS, KEY_BONUS_STARS]
const LEDGER_TIME: String = EconomyService.LEDGER_TIME
const LEDGER_CURRENCY: String = EconomyService.LEDGER_CURRENCY
const LEDGER_DELTA: String = EconomyService.LEDGER_DELTA
const LEDGER_SOURCE: String = EconomyService.LEDGER_SOURCE
const LEDGER_BALANCE: String = EconomyService.LEDGER_BALANCE
## Source of the ledger entry that records a merge adjustment.
const SYNC_SOURCE: String = "cloud_sync"
const SOURCE_SEPARATOR: String = ":"
## Hex characters of a ledger id (64 bits of SHA-256).
const LEDGER_ID_LENGTH: int = 16
const SECONDS_PER_DAY: int = 86400
## A time after every ledger entry.
const NO_TIME_LIMIT: int = 1 << 62
const LEVEL_UP_PREFIX: String = RewardEngine.TABLE_LEVEL_UP + SOURCE_SEPARATOR
const WORLD_COMPLETE_PREFIX: String = RewardEngine.TABLE_WORLD_COMPLETE + SOURCE_SEPARATOR
## Ledger sources of events that happen once per account.
const ONCE_PER_ACCOUNT_PREFIXES: PackedStringArray = [
	CosmeticService.SPEND_REASON_PREFIX,
	AchievementService.REWARD_SOURCE_PREFIX,
	MissionService.REWARD_SOURCE_PREFIX,
	LEVEL_UP_PREFIX,
	WORLD_COMPLETE_PREFIX,
]
## Ledger sources of rewards paid once per account and UTC day.
const ONCE_PER_DAY_PREFIXES: PackedStringArray = [RewardEngine.TABLE_DAILY_STREAK, RewardEngine.TABLE_BONUS_CHEST]
## Endings of sources derived from another reward (an owned cosmetic paid as
## coins, a rewarded-ad double).
const DERIVED_SUFFIXES: PackedStringArray = [RewardEngine.DUPLICATE_SOURCE_SUFFIX, RewardEngine.AD_DOUBLE_SOURCE_SUFFIX]
const MISSION_LIST: String = "missions"
const MISSION_ID: String = "id"
const MISSION_CLAIMED: String = "claimed"
const EVIDENCE_ONCE: String = "once"
const EVIDENCE_DAILY: String = "daily"


## Merged {"coins", "gems", "bonus_stars", "ledger"} of [param local] (this
## device) and [param remote] (the cloud copy), both in
## [method PlayerProfile.to_dict] shape. [param base]: see the class
## description ({} when this device never synced); [param starting]: the
## starting wallet {"coins", "gems"}; [param now_unix] stamps "cloud_sync"
## entries.
static func merge(
	local: Dictionary, remote: Dictionary, base: Dictionary, starting: Dictionary, now_unix: int
) -> Dictionary:
	var synced: bool = not base.is_empty()
	var evidence: Dictionary = WalletMerge._evidence(remote)
	var kept: Array = []
	var repeated: Dictionary = {KEY_COINS: 0, KEY_GEMS: 0}
	for entry: Dictionary in WalletMerge._entries_since(local, base):
		var currency: String = str(entry.get(LEDGER_CURRENCY, ""))
		if repeated.has(currency) and WalletMerge._is_repeat(entry, remote, evidence):
			repeated[currency] = int(repeated[currency]) + WalletMerge._int(entry.get(LEDGER_DELTA))
		else:
			kept.append(entry)
	var out: Dictionary = {}
	for key: String in CURRENCY_KEYS:
		var mine: int = WalletMerge._int(local.get(key))
		var theirs: int = WalletMerge._int(remote.get(key))
		if synced:
			out[key] = maxi(0, theirs + mine - WalletMerge._int(base.get(key)) - int(repeated[key]))
		else:
			out[key] = theirs + maxi(0, mine - WalletMerge._int(starting.get(key)) - int(repeated[key]))
	var star_gain: int = WalletMerge._int(local.get(KEY_BONUS_STARS)) - WalletMerge._int(base.get(KEY_BONUS_STARS))
	if not synced:
		star_gain = maxi(0, star_gain)
	var stars: int = WalletMerge._int(remote.get(KEY_BONUS_STARS)) + star_gain
	out[KEY_BONUS_STARS] = clampi(stars, 0, PlayerProfile.MAX_BONUS_STARS)
	out[KEY_LEDGER] = WalletMerge._merge_ledger(local, remote, kept, out, now_unix)
	return out


## {"coins", "gems", "bonus_stars"} of [param profile] (to_dict shape).
static func wallet_of(profile: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in WALLET_KEYS:
		out[key] = maxi(0, WalletMerge._int(profile.get(key)))
	return out


## Ledger id -> number of entries with that id in [param ledger].
static func ledger_ids(ledger: Variant) -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in WalletMerge._array(ledger):
		if typeof(raw) == TYPE_DICTIONARY:
			var id: String = WalletMerge.ledger_id(raw as Dictionary)
			out[id] = int(out.get(id, 0)) + 1
	return out


## Identity of a ledger entry: a hash of its time, currency, delta and source
## (not its balance, which a merge recomputes).
static func ledger_id(entry: Dictionary) -> String:
	var key: Dictionary = {
		LEDGER_TIME: WalletMerge._int(entry.get(LEDGER_TIME)),
		LEDGER_CURRENCY: str(entry.get(LEDGER_CURRENCY, "")),
		LEDGER_DELTA: WalletMerge._int(entry.get(LEDGER_DELTA)),
		LEDGER_SOURCE: str(entry.get(LEDGER_SOURCE, "")),
	}
	return JsonIO.canonical(key).sha256_text().left(LEDGER_ID_LENGTH)


## Base of a save that synced before bases were recorded (it has a cloud
## revision but no base): its wallet minus the ledger entries dated after
## [param synced_at] (the cloud copy it last matched; unknown = none are
## newer, so nothing can be counted twice), and for bonus stars the smaller
## side (the earlier rule kept the larger one).
static func legacy_base(local: Dictionary, remote: Dictionary, synced_at: int) -> Dictionary:
	var base: Dictionary = WalletMerge.wallet_of(local)
	var known: Dictionary = {}
	var since: int = synced_at if synced_at > 0 else NO_TIME_LIMIT
	for raw: Variant in WalletMerge._array(local.get(KEY_LEDGER)):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw as Dictionary
		var currency: String = str(entry.get(LEDGER_CURRENCY, ""))
		if WalletMerge._int(entry.get(LEDGER_TIME)) > since and base.has(currency):
			base[currency] = maxi(0, int(base[currency]) - WalletMerge._int(entry.get(LEDGER_DELTA)))
		else:
			var id: String = WalletMerge.ledger_id(entry)
			known[id] = int(known.get(id, 0)) + 1
	base[KEY_BONUS_STARS] = mini(int(base[KEY_BONUS_STARS]), WalletMerge._int(remote.get(KEY_BONUS_STARS)))
	base[BASE_LEDGER] = known
	return base


## This device's ledger entries that are not in [param base] (all of them,
## minus the starting balance, without a base), in order.
static func _entries_since(local: Dictionary, base: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var known: Dictionary = WalletMerge._dict(base.get(BASE_LEDGER)).duplicate()
	var synced: bool = not base.is_empty()
	for raw: Variant in WalletMerge._array(local.get(KEY_LEDGER)):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw as Dictionary
		var id: String = WalletMerge.ledger_id(entry)
		var left: int = WalletMerge._int(known.get(id))
		if left > 0:
			known[id] = left - 1
		elif synced or str(entry.get(LEDGER_SOURCE, "")) != EconomyService.STARTING_SOURCE:
			out.append(entry)
	return out


## What the cloud copy's ledger shows: once-per-account sources (per currency)
## and once-per-day sources (per currency and UTC day).
static func _evidence(remote: Dictionary) -> Dictionary:
	var once: Dictionary = {}
	var daily: Dictionary = {}
	for raw: Variant in WalletMerge._array(remote.get(KEY_LEDGER)):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw as Dictionary
		once[WalletMerge._once_key(entry)] = true
		var day_key: String = WalletMerge._daily_key(entry)
		if not day_key.is_empty():
			daily[day_key] = true
	return {EVIDENCE_ONCE: once, EVIDENCE_DAILY: daily}


## True when [param entry] (this device, since the base) pays or charges for
## an event the cloud copy already holds (see the class description).
static func _is_repeat(entry: Dictionary, remote: Dictionary, evidence: Dictionary) -> bool:
	var day_key: String = WalletMerge._daily_key(entry)
	if not day_key.is_empty():
		return (evidence[EVIDENCE_DAILY] as Dictionary).has(day_key)
	var source: String = str(entry.get(LEDGER_SOURCE, ""))
	var prefix: String = WalletMerge._prefix_of(source, ONCE_PER_ACCOUNT_PREFIXES)
	if prefix.is_empty():
		return false
	if (evidence[EVIDENCE_ONCE] as Dictionary).has(WalletMerge._once_key(entry)):
		return true
	return WalletMerge._state_shows(prefix, WalletMerge._source_id(source, prefix), remote)


## True when the cloud copy's state shows the once-per-account event
## [param prefix] + [param id] (an unlocked achievement, an owned item, a
## claimed mission, a reached player level).
static func _state_shows(prefix: String, id: String, remote: Dictionary) -> bool:
	if prefix == AchievementService.REWARD_SOURCE_PREFIX:
		return WalletMerge._dict(remote.get("achievements")).has(id)
	if prefix == CosmeticService.SPEND_REASON_PREFIX:
		return WalletMerge._array(remote.get("cosmetics_owned")).has(id)
	if prefix == MissionService.REWARD_SOURCE_PREFIX:
		return WalletMerge._mission_claimed(WalletMerge._dict(remote.get("missions")), id)
	if prefix == LEVEL_UP_PREFIX:
		return id.is_valid_int() and WalletMerge._int(remote.get("player_level")) >= id.to_int()
	return false


static func _mission_claimed(missions: Dictionary, id: String) -> bool:
	if WalletMerge._array(missions.get(MissionService.HISTORY_KEY)).has(id):
		return true
	for kind: String in MissionService.KINDS:
		for raw: Variant in WalletMerge._array(WalletMerge._dict(missions.get(kind)).get(MISSION_LIST)):
			var record: Dictionary = WalletMerge._dict(raw)
			if str(record.get(MISSION_ID, "")) == id and typeof(record.get(MISSION_CLAIMED)) == TYPE_BOOL:
				if bool(record[MISSION_CLAIMED]):
					return true
	return false


static func _once_key(entry: Dictionary) -> String:
	return "%s|%s" % [str(entry.get(LEDGER_CURRENCY, "")), str(entry.get(LEDGER_SOURCE, ""))]


## "currency|kind|day" for a once-per-day source, "" otherwise.
static func _daily_key(entry: Dictionary) -> String:
	var prefix: String = WalletMerge._prefix_of(str(entry.get(LEDGER_SOURCE, "")), ONCE_PER_DAY_PREFIXES)
	if prefix.is_empty():
		return ""
	var day: int = floori(WalletMerge._int(entry.get(LEDGER_TIME)) / float(SECONDS_PER_DAY))
	return "%s|%s|%d" % [str(entry.get(LEDGER_CURRENCY, "")), prefix, day]


static func _prefix_of(source: String, prefixes: PackedStringArray) -> String:
	for prefix: String in prefixes:
		if source.begins_with(prefix):
			return prefix
	return ""


## The id after [param prefix], without a derived-reward ending.
static func _source_id(source: String, prefix: String) -> String:
	var id: String = source.substr(prefix.length())
	for suffix: String in DERIVED_SUFFIXES:
		if id.ends_with(suffix):
			return id.left(id.length() - suffix.length())
	return id


static func _merge_ledger(
	local: Dictionary, remote: Dictionary, kept: Array, wallet: Dictionary, now_unix: int
) -> Array:
	var theirs: Array = WalletMerge._array(remote.get(KEY_LEDGER))
	if WalletMerge._already_merged(local, theirs, wallet):
		return WalletMerge._array(local.get(KEY_LEDGER)).duplicate(true)
	var out: Array = []
	var ends: Dictionary = {}
	for key: String in CURRENCY_KEYS:
		ends[key] = WalletMerge._int(remote.get(key))
	if kept.is_empty():
		out = theirs.duplicate(true)
	else:
		out = WalletMerge._by_time(theirs, kept)
		ends = WalletMerge._rebalance(out, theirs, ends)
	var stamp: int = maxi(now_unix, WalletMerge._last_time(out))
	for key: String in CURRENCY_KEYS:
		var gap: int = int(wallet[key]) - int(ends[key])
		if gap != 0:
			var adjustment: Dictionary = {LEDGER_TIME: stamp, LEDGER_CURRENCY: key, LEDGER_DELTA: gap}
			adjustment[LEDGER_SOURCE] = SYNC_SOURCE
			adjustment[LEDGER_BALANCE] = int(wallet[key])
			out.append(adjustment)
	return out.slice(maxi(0, out.size() - PlayerProfile.LEDGER_LIMIT))


## True when this device's ledger already describes [param wallet] and holds
## every entry of the cloud ledger [param theirs] that is not older than its
## own oldest entry (merging a copy this device already merged).
static func _already_merged(local: Dictionary, theirs: Array, wallet: Dictionary) -> bool:
	var mine: Array = WalletMerge._array(local.get(KEY_LEDGER))
	if mine.is_empty():
		return false
	for key: String in CURRENCY_KEYS:
		if WalletMerge._int(local.get(key)) != int(wallet[key]):
			return false
	var oldest: int = WalletMerge._time(mine[0])
	var known: Dictionary = WalletMerge.ledger_ids(mine)
	for raw: Variant in theirs:
		if typeof(raw) != TYPE_DICTIONARY or WalletMerge._time(raw) < oldest:
			continue
		var id: String = WalletMerge.ledger_id(raw as Dictionary)
		if WalletMerge._int(known.get(id)) <= 0:
			return false
		known[id] = WalletMerge._int(known.get(id)) - 1
	return true


## Deep copies of [param a] and [param b] merged by entry time (ties: [param a] first).
static func _by_time(a: Array, b: Array) -> Array:
	var out: Array = []
	var i: int = 0
	var j: int = 0
	while i < a.size() or j < b.size():
		if j >= b.size() or (i < a.size() and WalletMerge._time(a[i]) <= WalletMerge._time(b[j])):
			out.append(WalletMerge._copy(a[i]))
			i += 1
		else:
			out.append(WalletMerge._copy(b[j]))
			j += 1
	return out


## Recomputes every balance of [param out] in order, starting from the
## balance the cloud ledger [param theirs] started from ([param ends] holds
## the cloud wallet). Returns the balance each currency ends on.
static func _rebalance(out: Array, theirs: Array, ends: Dictionary) -> Dictionary:
	var running: Dictionary = ends.duplicate()
	for raw: Variant in theirs:
		var currency: String = str(WalletMerge._dict(raw).get(LEDGER_CURRENCY, ""))
		if running.has(currency):
			running[currency] = int(running[currency]) - WalletMerge._int(WalletMerge._dict(raw).get(LEDGER_DELTA))
	for raw2: Variant in out:
		if typeof(raw2) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw2 as Dictionary
		var currency2: String = str(entry.get(LEDGER_CURRENCY, ""))
		if running.has(currency2):
			running[currency2] = int(running[currency2]) + WalletMerge._int(entry.get(LEDGER_DELTA))
			entry[LEDGER_BALANCE] = running[currency2]
	return running


static func _last_time(entries: Array) -> int:
	return WalletMerge._time(entries.back()) if not entries.is_empty() else 0


static func _time(entry: Variant) -> int:
	return WalletMerge._int(WalletMerge._dict(entry).get(LEDGER_TIME))


static func _copy(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		return (value as Dictionary).duplicate(true)
	return value


static func _dict(value: Variant) -> Dictionary:
	return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


static func _array(value: Variant) -> Array:
	return value as Array if typeof(value) == TYPE_ARRAY else []


static func _int(value: Variant) -> int:
	if typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value as float)):
		return int(value)
	return 0
