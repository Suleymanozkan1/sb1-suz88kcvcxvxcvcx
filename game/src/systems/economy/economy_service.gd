class_name EconomyService
extends RefCounted
## Wallet for the two currencies (coins from gameplay, rare gems).
##
## Every balance change goes through [method grant] or [method spend]. Both
## validate the request, append an audit entry to the profile ledger
## ({t, c, d, s, b}, bounded by [constant PlayerProfile.LEDGER_LIMIT]) and
## publish [signal EventBus.currency_changed]. Balances never go negative, a
## single grant is bounded by data/economy/economy.json and balances are
## clamped to a plausibility cap, so a bug elsewhere cannot flood the wallet.
## The service owns only the coins, gems and ledger slice of the profile
## (plus one one-off flag that records the starting balance).

const COINS: StringName = &"coins"
const GEMS: StringName = &"gems"
const CURRENCIES: Array[StringName] = [COINS, GEMS]
const CONFIG_PATH: String = "res://data/economy/economy.json"
const SCHEMA_VERSION: int = 1

const LEDGER_TIME: String = "t"
const LEDGER_CURRENCY: String = "c"
const LEDGER_DELTA: String = "d"
const LEDGER_SOURCE: String = "s"
const LEDGER_BALANCE: String = "b"
const MAX_SOURCE_LENGTH: int = 64
const UNKNOWN_SOURCE: String = "unknown"
const STARTING_FLAG: String = "economy_starting_granted"
const STARTING_SOURCE: String = "starting_balance"
## Ledger source kinds with their own wallet-history label (see i18n part).
const LEDGER_LABEL_KEY_PREFIX: String = "economy.ledger.source."
const LEDGER_LABEL_KINDS: Array[String] = [
	"level",
	"daily_streak",
	"bonus_chest",
	"level_up",
	"world_complete",
	"starting_balance",
	"achievement",
	"mission",
	"purchase",
]
const LEDGER_LABEL_SUFFIXES: Array[String] = ["duplicate", "ad_double"]
## Source kinds written by other modules that share a label (the cosmetics
## shop spends with the reason "cosmetic:<item id>").
const LEDGER_LABEL_ALIASES: Dictionary = {"cosmetic": "purchase"}
const LEDGER_LABEL_OTHER: String = "other"
## Largest whole number a JSON float can hold exactly (2^53).
const MAX_SAFE_FLOAT_INT: float = 9007199254740992.0
## Longest digit run parsed from a numeric string (always fits in 64 bits).
const MAX_INT_STRING_DIGITS: int = 18

const KEY_MAX_SINGLE_GRANT: String = "max_single_grant"
const KEY_BALANCE_CAP: String = "balance_cap"
const KEY_DUPLICATE_COINS: String = "duplicate_cosmetic_coins"
const KEY_STARTING: String = "starting"
const KEY_INTEGRITY: String = "integrity"
const KEY_TIME_TRAVEL: String = "time_travel_tolerance_seconds"

## Safe fallbacks, used only when economy.json is missing or damaged.
const FALLBACK_MAX_SINGLE_GRANT: Dictionary = {"coins": 5000, "gems": 50}
const FALLBACK_BALANCE_CAP: Dictionary = {"coins": 5000000, "gems": 100000}
const FALLBACK_STARTING: Dictionary = {"coins": 100, "gems": 0}
const FALLBACK_DUPLICATE_COSMETIC_COINS: int = 150
const FALLBACK_TIME_TRAVEL_TOLERANCE: int = 86400

## Sanitised configuration (see [method sanitize_config]). Treat as read-only.
var config: Dictionary = {}

var _profile: PlayerProfile
var _bus: EventBus
var _clock: GameClock


## [param config_data] is the parsed economy.json; when empty the default file
## is loaded. Invalid values are replaced by safe fallbacks (and logged).
func _init(profile: PlayerProfile, bus: EventBus, clock: GameClock, config_data: Dictionary = {}) -> void:
	if profile == null:
		GameLog.error("economy", "no profile injected; using an empty in-memory profile")
		profile = PlayerProfile.new()
	if clock == null:
		clock = GameClock.new()
	_profile = profile
	_bus = bus
	_clock = clock
	config = sanitize_config(config_data) if not config_data.is_empty() else load_config()


## Loads and sanitises economy.json. Never fails: falls back to defaults.
static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	var raw: Dictionary = JsonIO.read_dict(path)
	if raw.is_empty():
		GameLog.warn("economy", "economy config %s unavailable; using built-in defaults" % path)
	return sanitize_config(raw)


## Returns a complete, validated config built from [param raw]: every currency
## has a positive single-grant limit and balance cap, starting balances fit
## inside the grant limit, and missing or malformed values use fallbacks.
static func sanitize_config(raw: Dictionary) -> Dictionary:
	var version: int = int_or(raw.get("schema_version", SCHEMA_VERSION), SCHEMA_VERSION)
	if version != SCHEMA_VERSION:
		GameLog.warn("economy", "economy config schema %d (expected %d)" % [version, SCHEMA_VERSION])
	var max_grant: Dictionary = _currency_map(raw.get(KEY_MAX_SINGLE_GRANT), FALLBACK_MAX_SINGLE_GRANT, 1)
	var cap: Dictionary = _currency_map(raw.get(KEY_BALANCE_CAP), FALLBACK_BALANCE_CAP, 1)
	var starting: Dictionary = _currency_map(raw.get(KEY_STARTING), FALLBACK_STARTING, 0)
	for key: String in max_grant:
		if int(max_grant[key]) > int(cap[key]):
			GameLog.warn("economy", "max_single_grant.%s exceeds balance_cap; clamped" % key)
			max_grant[key] = cap[key]
		if int(starting[key]) > int(max_grant[key]):
			GameLog.warn("economy", "starting.%s exceeds max_single_grant; clamped" % key)
			starting[key] = max_grant[key]
	var duplicate_coins: int = int_or(raw.get(KEY_DUPLICATE_COINS), -1)
	if duplicate_coins < 0:
		if raw.has(KEY_DUPLICATE_COINS):
			GameLog.warn("economy", "invalid duplicate_cosmetic_coins; using fallback")
		duplicate_coins = FALLBACK_DUPLICATE_COSMETIC_COINS
	duplicate_coins = mini(duplicate_coins, int(max_grant[String(COINS)]))
	var integrity_raw: Variant = raw.get(KEY_INTEGRITY, {})
	var integrity: Dictionary = integrity_raw as Dictionary if typeof(integrity_raw) == TYPE_DICTIONARY else {}
	var tolerance: int = int_or(integrity.get(KEY_TIME_TRAVEL), -1)
	if tolerance < 0:
		tolerance = FALLBACK_TIME_TRAVEL_TOLERANCE
	return {
		"schema_version": SCHEMA_VERSION,
		KEY_MAX_SINGLE_GRANT: max_grant,
		KEY_BALANCE_CAP: cap,
		KEY_DUPLICATE_COINS: duplicate_coins,
		KEY_STARTING: starting,
		KEY_INTEGRITY: {KEY_TIME_TRAVEL: tolerance},
	}


## True for the currencies this wallet manages ([constant COINS], [constant GEMS]).
static func is_currency(currency: StringName) -> bool:
	return CURRENCIES.has(currency)


## Whole-number view of a parsed JSON value (ints, integral floats, numeric
## strings of at most [constant MAX_INT_STRING_DIGITS] digits);
## [param fallback] for anything else, including values too large to hold.
static func int_or(value: Variant, fallback: int) -> int:
	match typeof(value):
		TYPE_INT:
			return value as int
		TYPE_FLOAT:
			var f: float = value as float
			if is_finite(f) and f == floorf(f) and absf(f) <= MAX_SAFE_FLOAT_INT:
				return int(f)
		TYPE_STRING, TYPE_STRING_NAME:
			var s: String = str(value)
			var digits: String = s.trim_prefix("-").trim_prefix("+")
			if s.is_valid_int() and digits.length() <= MAX_INT_STRING_DIGITS:
				return s.to_int()
	return fallback


## Current balance; 0 for an unknown currency.
func balance(currency: StringName) -> int:
	match currency:
		COINS:
			return _profile.coins
		GEMS:
			return _profile.gems
	return 0


## True when [param amount] (>= 0) of a known currency can be spent now.
func can_afford(currency: StringName, amount: int) -> bool:
	if not is_currency(currency) or amount < 0:
		return false
	return balance(currency) >= amount


## Largest amount accepted by one [method grant] call.
func max_single_grant(currency: StringName) -> int:
	return int((config[KEY_MAX_SINGLE_GRANT] as Dictionary).get(String(currency), 0))


## Plausibility ceiling for a balance (grants are clamped to it).
func balance_cap(currency: StringName) -> int:
	return int((config[KEY_BALANCE_CAP] as Dictionary).get(String(currency), 0))


## Coins given instead of a cosmetic the player already owns.
func duplicate_cosmetic_coins() -> int:
	return int(config[KEY_DUPLICATE_COINS])


## Adds currency. Rejects (returns false, logs) non-positive amounts, unknown
## currencies, amounts above the single-grant limit and grants on a wallet
## that already sits at its cap. A grant that would pass the cap is clamped.
func grant(currency: StringName, amount: int, source: String) -> bool:
	if not is_currency(currency):
		GameLog.warn("economy", "grant rejected: unknown currency '%s' (%s)" % [currency, source])
		return false
	if amount <= 0:
		GameLog.warn("economy", "grant rejected: non-positive amount %d %s (%s)" % [amount, currency, source])
		return false
	if amount > max_single_grant(currency):
		GameLog.warn("economy", "grant rejected: %d %s exceeds single-grant limit (%s)" % [amount, currency, source])
		return false
	var before: int = balance(currency)
	var after: int = mini(before + amount, balance_cap(currency))
	if after <= before:
		GameLog.warn("economy", "grant rejected: %s balance at cap (%s)" % [currency, source])
		return false
	if after - before < amount:
		GameLog.warn("economy", "grant of %d %s clamped to balance cap" % [amount, currency])
	_apply(currency, after, after - before, source)
	return true


## Removes currency. Rejects non-positive amounts, unknown currencies and any
## spend that would make the balance negative.
func spend(currency: StringName, amount: int, reason: String) -> bool:
	if not is_currency(currency):
		GameLog.warn("economy", "spend rejected: unknown currency '%s' (%s)" % [currency, reason])
		return false
	if amount <= 0:
		GameLog.warn("economy", "spend rejected: non-positive amount %d %s (%s)" % [amount, currency, reason])
		return false
	var before: int = balance(currency)
	if amount > before:
		GameLog.info("economy", "spend declined: %d %s > balance %d (%s)" % [amount, currency, before, reason])
		return false
	_apply(currency, before - amount, -amount, reason)
	return true


## Normalises the price formats used in data files into {"coins": n} or
## {"gems": n}. Accepts {"coins": n}, {"gems": n}, {"currency": c, "amount": n}
## and the unlock form {"type": c, "value": n}. Returns {} for a free,
## malformed or unknown-currency price. When both currencies carry a positive
## price the coin price wins (coins are the currency earned by playing); a
## zero or invalid entry for one currency never makes the other price free.
func price_of(item_price: Dictionary) -> Dictionary:
	var currency: StringName = &""
	var amount: int = 0
	if item_price.has(String(COINS)) or item_price.has(String(GEMS)):
		var coins: int = int_or(item_price.get(String(COINS)), 0)
		var gems: int = int_or(item_price.get(String(GEMS)), 0)
		if coins > 0 and gems > 0:
			GameLog.warn("economy", "price lists both currencies; using the coin price")
		currency = GEMS if coins <= 0 and gems > 0 else COINS
		amount = gems if currency == GEMS else coins
	elif item_price.has("currency"):
		currency = StringName(str(item_price["currency"]))
		amount = int_or(item_price.get("amount"), 0)
	elif item_price.has("type"):
		currency = StringName(str(item_price["type"]))
		amount = int_or(item_price.get("value"), 0)
	if not is_currency(currency) or amount <= 0:
		return {}
	return {String(currency): amount}


## Grants the configured starting balance exactly once per profile. Returns
## true when it was applied now, false when it had already been applied.
func apply_starting_balance() -> bool:
	if bool(_profile.flags.get(STARTING_FLAG, false)):
		return false
	var starting: Dictionary = config[KEY_STARTING] as Dictionary
	for currency: StringName in CURRENCIES:
		var amount: int = int(starting.get(String(currency), 0))
		if amount > 0:
			grant(currency, amount, STARTING_SOURCE)
	_profile.flags[STARTING_FLAG] = true
	return true


## Translation key describing a ledger source such as "level:w01_l03",
## "daily_streak:4", "cosmetic:core_fire" or "level:w02_l10:duplicate" for the
## wallet history.
static func ledger_label_key(source: String) -> String:
	var parts: PackedStringArray = source.split(":")
	var kind: String = str(LEDGER_LABEL_ALIASES.get(parts[0], parts[0]))
	if parts.size() > 1 and LEDGER_LABEL_SUFFIXES.has(parts[parts.size() - 1]):
		kind = parts[parts.size() - 1]
	if not LEDGER_LABEL_KINDS.has(kind) and not LEDGER_LABEL_SUFFIXES.has(kind):
		kind = LEDGER_LABEL_OTHER
	return LEDGER_LABEL_KEY_PREFIX + kind


## Most recent ledger entries (newest first), optionally for one currency.
## [param limit] <= 0 returns every matching entry. Each entry is a normalised
## copy {t: int, c: String, d: int, s: String, b: int}, so values stay whole
## numbers after a JSON save round trip; entries of unknown currencies are
## skipped.
func recent_ledger(currency: StringName = &"", limit: int = 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in range(_profile.ledger.size() - 1, -1, -1):
		var entry: Dictionary = _profile.ledger[i]
		var entry_currency: String = str(entry.get(LEDGER_CURRENCY, ""))
		if not is_currency(StringName(entry_currency)):
			continue
		if currency != &"" and entry_currency != String(currency):
			continue
		out.append({
			LEDGER_TIME: int_or(entry.get(LEDGER_TIME), 0),
			LEDGER_CURRENCY: entry_currency,
			LEDGER_DELTA: int_or(entry.get(LEDGER_DELTA), 0),
			LEDGER_SOURCE: str(entry.get(LEDGER_SOURCE, UNKNOWN_SOURCE)),
			LEDGER_BALANCE: int_or(entry.get(LEDGER_BALANCE), 0),
		})
		if limit > 0 and out.size() >= limit:
			break
	return out


func _apply(currency: StringName, new_balance: int, delta: int, source: String) -> void:
	match currency:
		COINS:
			_profile.coins = new_balance
		GEMS:
			_profile.gems = new_balance
	var label: String = source.strip_edges()
	if label.is_empty():
		label = UNKNOWN_SOURCE
	_profile.ledger.append({
		LEDGER_TIME: _clock.now_unix(),
		LEDGER_CURRENCY: String(currency),
		LEDGER_DELTA: delta,
		LEDGER_SOURCE: label.left(MAX_SOURCE_LENGTH),
		LEDGER_BALANCE: new_balance,
	})
	while _profile.ledger.size() > PlayerProfile.LEDGER_LIMIT:
		_profile.ledger.remove_at(0)
	if _bus != null:
		_bus.currency_changed.emit(currency, new_balance, delta)


static func _currency_map(raw: Variant, fallback: Dictionary, minimum: int) -> Dictionary:
	var src: Dictionary = raw as Dictionary if typeof(raw) == TYPE_DICTIONARY else {}
	var out: Dictionary = {}
	for currency: StringName in CURRENCIES:
		var key: String = String(currency)
		var value: int = int_or(src.get(key), minimum - 1)
		if value < minimum:
			if src.has(key):
				GameLog.warn("economy", "invalid economy value for %s; using fallback" % key)
			value = int(fallback[key])
		out[key] = value
	return out

