class_name RewardEngine
extends RefCounted
## Data-driven reward rules (data/rewards/reward_tables.json) and the single
## place where rewards are applied.
##
## The compute methods are deterministic: the same inputs and profile state
## always give the same bundle, with no hidden randomness and no odds. [method
## grant] applies a bundle through the [EconomyService], the XP callback and
## the cosmetic callback, then returns a new bundle that lists exactly what was
## applied; that returned bundle is the only thing the UI may animate.
##
## Ownership is read from the profile (the single source of truth): a cosmetic
## the player already owns becomes duplicate_cosmetic_coins coins, a badge the
## player already owns is dropped (badges are trophies, not a coin source),
## and an id the cosmetic callback refuses although it is not owned is unknown
## and therefore dropped.

const TABLES_PATH: String = "res://data/rewards/reward_tables.json"
const SCHEMA_VERSION: int = 1

const TABLE_DAILY_STREAK: String = "daily_streak"
const TABLE_BONUS_CHEST: String = "bonus_chest"
const TABLE_LEVEL_UP: String = "level_up"
const TABLE_WORLD_COMPLETE: String = "world_complete"
const TABLE_IDS: Array[String] = [TABLE_DAILY_STREAK, TABLE_BONUS_CHEST, TABLE_LEVEL_UP, TABLE_WORLD_COMPLETE]
const SECTION_LEVEL: String = "level"
const SECTION_AD_DOUBLE: String = "ad_double"
const SECTION_LIMITS: String = "limits"

const KIND_NORMAL: String = "normal"
const KIND_CHALLENGE: String = "challenge"
const KIND_BOSS: String = "boss"
const KINDS: Array[String] = [KIND_NORMAL, KIND_CHALLENGE, KIND_BOSS]

## Reward spec keys accepted by [method bundle_from_spec], in grant order.
const SPEC_COINS: String = "coins"
const SPEC_GEMS: String = "gems"
const SPEC_XP: String = "xp"
const SPEC_COSMETIC: String = "cosmetic"
const SPEC_BADGE: String = "badge"
const SPEC_KEYS: Array[String] = [SPEC_COINS, SPEC_GEMS, SPEC_XP, SPEC_COSMETIC, SPEC_BADGE]

const MAX_STARS: int = 3
## Floor for the coins of a completed run, whatever the data says.
const MIN_COMPLETED_COINS: int = 1
## Key of a [method grant_table] request naming the table to compute.
const REQUEST_TABLE: String = "table"
const DAILY_STREAK_TIERS: int = 7
const FIRST_GEM_STREAK_TIER: int = 3
const FIRST_LEVEL_UP: int = 2
## Amount recorded for a cosmetic or badge item (one unit of an id).
const ITEM_AMOUNT: int = 1
const DUPLICATE_ID_PREFIX: String = "duplicate:"
const DUPLICATE_SOURCE_SUFFIX: String = ":duplicate"
const AD_DOUBLE_SOURCE_SUFFIX: String = ":ad_double"
const LEVEL_SOURCE_PREFIX: String = "level:"
const DEFAULT_SOURCE: String = "reward"
const SPEC_COINS_KEY: String = "coins"
const BADGE_ID_PREFIX: String = "badge_"

## Safe values used when the level table is missing or damaged.
const FALLBACK_LEVEL: Dictionary = {
	"default_tier": "early",
	"first_clear_coins": 20,
	"replay_coins": 2,
	"replay_coins_min": 1,
	"coins_per_new_star": 4,
	"perfect_first_gems": 1,
	"perfect_badge_prefix": "badge_perfect_",
	"xp_base": 10,
	"xp_per_star": 5,
	"fail_xp": 2,
	"fail_xp_min_seconds": 5.0,
}
const FALLBACK_MAX_XP_PER_ITEM: int = 20000
const FALLBACK_WORLD_COUNT: int = 10

## Parsed reward tables (see reward_tables.json). Treat as read-only.
var tables: Dictionary = {}
## Remote economy tuning (remote config economy.coin_multiplier times the
## weekend event bonus, and economy.daily_reward_multiplier). 1.0 pays the
## tables exactly as shipped; set by AppServices, never by the player.
var coin_scale: float = 1.0
var daily_scale: float = 1.0

var _profile: PlayerProfile
var _bus: EventBus
var _economy: EconomyService
var _grant_xp: Callable
var _grant_cosmetic: Callable


## [param grant_xp] is (amount: int) -> void; [param grant_cosmetic] is
## (item_id: String) -> bool, true when the item is newly owned. When
## [param tables_data] is empty the default tables file is loaded.
func _init(
	profile: PlayerProfile,
	bus: EventBus,
	economy: EconomyService,
	grant_xp: Callable,
	grant_cosmetic: Callable,
	tables_data: Dictionary = {}
) -> void:
	if profile == null:
		GameLog.error("reward", "no profile injected; using an empty in-memory profile")
		profile = PlayerProfile.new()
	if economy == null:
		GameLog.error("reward", "no economy injected; using a private wallet over the profile")
		economy = EconomyService.new(profile, bus, GameClock.new())
	_profile = profile
	_bus = bus
	_economy = economy
	_grant_xp = grant_xp
	_grant_cosmetic = grant_cosmetic
	tables = tables_data if not tables_data.is_empty() else load_tables()
	for problem: String in validate_tables(tables, tier_ids()):
		GameLog.warn("reward", "reward tables: %s" % problem)


## Loads reward_tables.json; {} (logged) when missing or unreadable, in which
## case level rewards use built-in safe values and other tables give nothing.
static func load_tables(path: String = TABLES_PATH) -> Dictionary:
	var data: Dictionary = JsonIO.read_dict(path)
	if data.is_empty():
		GameLog.error("reward", "reward tables %s unavailable; using safe fallbacks" % path)
	return data


## Structural and balance checks for a tables dictionary. [param tier_ids] are
## the difficulty tiers that must all be covered. Returns readable errors.
static func validate_tables(data: Dictionary, tier_ids: PackedStringArray) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if EconomyService.int_or(data.get("schema_version"), -1) != SCHEMA_VERSION:
		errors.append("schema_version must be %d" % SCHEMA_VERSION)
	_validate_level_table(_dict(data.get(SECTION_LEVEL)), tier_ids, errors)
	_validate_daily_streak(_dict(data.get(TABLE_DAILY_STREAK)), errors)
	var chest: Dictionary = _dict(_dict(data.get(TABLE_BONUS_CHEST)).get("reward"))
	if chest.is_empty() or not spec_errors(chest).is_empty():
		errors.append("bonus_chest.reward must be a valid, non-empty reward spec")
	_validate_level_up(_dict(data.get(TABLE_LEVEL_UP)), errors)
	_validate_world_complete(_dict(data.get(TABLE_WORLD_COMPLETE)), errors)
	for raw: Variant in _array(_dict(data.get(SECTION_AD_DOUBLE)).get("types")):
		if not EconomyService.is_currency(StringName(str(raw))):
			errors.append("ad_double.types may only list currencies, found '%s'" % str(raw))
	return errors


## Problems with a reward spec ({"coins", "gems", "xp", "cosmetic", "badge"}).
static func spec_errors(spec: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	for key: Variant in spec:
		var key_name: String = str(key)
		if not SPEC_KEYS.has(key_name):
			errors.append("unknown reward key '%s'" % key_name)
		elif key_name == SPEC_COSMETIC or key_name == SPEC_BADGE:
			if typeof(spec[key]) != TYPE_STRING or str(spec[key]).is_empty():
				errors.append("%s must be a non-empty id" % key_name)
		elif EconomyService.int_or(spec[key], -1) < 0:
			errors.append("%s must be a whole number >= 0" % key_name)
	if spec.has(SPEC_BADGE) and not str(spec[SPEC_BADGE]).begins_with(BADGE_ID_PREFIX):
		errors.append("badge ids must start with '%s'" % BADGE_ID_PREFIX)
	return errors


## The difficulty tiers the level table pays for.
func tier_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for key: Variant in _dict(_level_table().get("base_by_tier")):
		out.append(str(key))
	return out


## Reward for one finished run. [param ctx]: {"tier": String, "kind":
## "normal"|"challenge"|"boss", "first_clear": bool, "prev_stars": int,
## "new_stars": int (stars newly earned by this run), "first_perfect": bool}.
## Completed: first-clear coins by tier (+ kind bonus) or the small replay
## amount, + coins per new star, + gems and the tier's perfect badge on the
## first perfect only, + XP for the run's stars. Failed: a small consolation
## XP for a real attempt, never coins.
func compute_level_reward(result: RunResult, ctx: Dictionary) -> RewardBundle:
	if result == null:
		GameLog.warn("reward", "compute_level_reward without a result")
		return RewardBundle.new(SECTION_LEVEL)
	var bundle: RewardBundle = RewardBundle.new(LEVEL_SOURCE_PREFIX + result.level_id)
	if not result.completed:
		if result.time_seconds >= _level_float("fail_xp_min_seconds"):
			bundle.add(RewardBundle.TYPE_XP, _level_int("fail_xp"))
		return bundle
	var tier: String = _resolve_tier(ctx)
	var stars: int = clampi(result.stars, 0, MAX_STARS)
	var prev_stars: int = clampi(EconomyService.int_or(ctx.get("prev_stars"), 0), 0, MAX_STARS)
	var new_stars: int = clampi(EconomyService.int_or(ctx.get("new_stars"), 0), 0, maxi(0, stars - prev_stars))
	var coins: int = 0
	if _flag(ctx, "first_clear"):
		coins = _tier_amount("base_by_tier", tier, "first_clear_coins") + _kind_bonus(ctx)
	else:
		coins = _tier_amount("replay_coins_by_tier", tier, "replay_coins")
	# A completed run always pays something, even with damaged data.
	coins = maxi(coins, maxi(_level_int("replay_coins_min"), MIN_COMPLETED_COINS))
	coins += _level_int("coins_per_new_star") * new_stars
	bundle.add(RewardBundle.TYPE_COINS, RewardEngine.scaled(coins, coin_scale))
	if _flag(ctx, "first_perfect") and result.perfect:
		bundle.add(RewardBundle.TYPE_GEMS, _level_int("perfect_first_gems"))
		var badge: String = _level_string("perfect_badge_prefix") + tier
		if not _profile.cosmetics_owned.has(badge):
			bundle.add(RewardBundle.TYPE_BADGE, ITEM_AMOUNT, badge)
	bundle.add(RewardBundle.TYPE_XP, _level_int("xp_base") + _level_int("xp_per_star") * stars)
	return bundle


## Reward from a named table. [param ctx] per table: daily_streak {"tier":
## 1..7, higher values use tier 7}; bonus_chest (fixed contents, ctx unused);
## level_up {"level": the level just reached, >= 2}; world_complete
## {"world_index": 1..10}. Unknown tables or invalid ctx give an empty bundle.
func compute(table_id: String, ctx: Dictionary = {}) -> RewardBundle:
	match table_id:
		TABLE_DAILY_STREAK:
			return _daily_streak(ctx)
		TABLE_BONUS_CHEST:
			return bundle_from_spec(_dict(_dict(tables.get(TABLE_BONUS_CHEST)).get("reward")), TABLE_BONUS_CHEST)
		TABLE_LEVEL_UP:
			return _level_up(ctx)
		TABLE_WORLD_COMPLETE:
			return _world_complete(ctx)
	GameLog.warn("reward", "unknown reward table '%s'" % table_id)
	return RewardBundle.new(table_id)


## Builds a bundle from {"coins": n, "gems": n, "xp": n, "cosmetic": "id",
## "badge": "id"}. Invalid entries are skipped (and logged).
func bundle_from_spec(spec: Dictionary, source: String = "") -> RewardBundle:
	var bundle: RewardBundle = RewardBundle.new(source)
	for key: Variant in spec:
		if not SPEC_KEYS.has(str(key)):
			GameLog.warn("reward", "ignoring unknown reward key '%s' (%s)" % [str(key), source])
	for key: String in SPEC_KEYS:
		if not spec.has(key):
			continue
		var value: Variant = spec[key]
		if key == SPEC_COSMETIC or key == SPEC_BADGE:
			var id: String = str(value) if typeof(value) == TYPE_STRING else ""
			if id.is_empty():
				GameLog.warn("reward", "ignoring empty %s id (%s)" % [key, source])
				continue
			bundle.add(StringName(key), ITEM_AMOUNT, id)
			continue
		var amount: int = EconomyService.int_or(value, -1)
		if amount < 0:
			GameLog.warn("reward", "ignoring invalid %s amount '%s' (%s)" % [key, str(value), source])
			continue
		bundle.add(StringName(key), amount)
	return bundle


## Applies every item and returns a NEW bundle listing exactly what was
## granted: currencies through the economy (as actually credited), XP through
## the XP callback, cosmetics and badges through the cosmetic callback. Owned
## cosmetics become coins (id "duplicate:<item>"), owned badges, stars and
## invalid items are dropped. Emits [signal EventBus.reward_granted] when
## anything was granted.
func grant(bundle: RewardBundle) -> RewardBundle:
	if bundle == null:
		return RewardBundle.new(DEFAULT_SOURCE)
	var source: String = bundle.source if not bundle.source.is_empty() else DEFAULT_SOURCE
	var granted: RewardBundle = RewardBundle.new(source)
	for item: Dictionary in bundle.items:
		var type: StringName = StringName(str(item.get("type", "")))
		var amount: int = EconomyService.int_or(item.get("amount"), 0)
		var id: String = str(item.get("id", ""))
		match type:
			RewardBundle.TYPE_COINS, RewardBundle.TYPE_GEMS:
				_grant_currency(granted, type, amount, id, source)
			RewardBundle.TYPE_XP:
				_grant_xp_item(granted, amount, source)
			RewardBundle.TYPE_COSMETIC:
				_grant_cosmetic_item(granted, id, source)
			RewardBundle.TYPE_BADGE:
				_grant_badge_item(granted, id, source)
			_:
				GameLog.debug("reward", "dropping non-grantable item %s (%s)" % [type, source])
	if _bus != null and not granted.is_empty():
		_bus.reward_granted.emit(granted)
	return granted


## Convenience for spec-based rewards (achievements, missions):
## grant(bundle_from_spec(spec, source)).
func grant_spec(spec: Dictionary, source: String) -> RewardBundle:
	return grant(bundle_from_spec(spec, source))


## Convenience for table rewards requested as {"table": id, ...ctx}, e.g. the
## daily challenge's {"table": "daily_streak", "tier": n}:
## grant(compute(request.table, request)).
func grant_table(request: Dictionary) -> RewardBundle:
	return grant(compute(str(request.get(REQUEST_TABLE, "")), request))


## The portion of [param bundle] to grant a second time after the player chose
## to watch a rewarded ad: plain currency items only (by default coins and
## gems). XP, cosmetics, badges and duplicate compensation are never doubled.
func double_for_ad(bundle: RewardBundle) -> RewardBundle:
	var source: String = (bundle.source if bundle != null else DEFAULT_SOURCE) + AD_DOUBLE_SOURCE_SUFFIX
	var doubled: RewardBundle = RewardBundle.new(source)
	if bundle == null:
		return doubled
	var types: Array[StringName] = ad_double_types()
	for item: Dictionary in bundle.items:
		var type: StringName = StringName(str(item.get("type", "")))
		var amount: int = EconomyService.int_or(item.get("amount"), 0)
		if types.has(type) and str(item.get("id", "")).is_empty() and amount > 0:
			doubled.add(type, amount)
	return doubled


## Currencies an optional rewarded ad may double (from data; currencies only).
func ad_double_types() -> Array[StringName]:
	var out: Array[StringName] = []
	var section: Dictionary = _dict(tables.get(SECTION_AD_DOUBLE))
	if not section.has("types"):
		out.append_array(EconomyService.CURRENCIES)
		return out
	for raw: Variant in _array(section.get("types")):
		var currency: StringName = StringName(str(raw))
		if EconomyService.is_currency(currency) and not out.has(currency):
			out.append(currency)
		elif not EconomyService.is_currency(currency):
			GameLog.warn("reward", "ad_double ignores non-currency type '%s'" % str(raw))
	return out


func _grant_currency(granted: RewardBundle, type: StringName, amount: int, id: String, source: String) -> void:
	if amount <= 0:
		GameLog.warn("reward", "dropping %s item with amount %d (%s)" % [type, amount, source])
		return
	var before: int = _economy.balance(type)
	if not _economy.grant(type, amount, source):
		return
	var applied: int = _economy.balance(type) - before
	if applied > 0:
		granted.add(type, applied, id)


func _grant_xp_item(granted: RewardBundle, amount: int, source: String) -> void:
	var limit: int = EconomyService.int_or(_dict(tables.get(SECTION_LIMITS)).get("max_xp_per_item"), -1)
	if limit <= 0:
		limit = FALLBACK_MAX_XP_PER_ITEM
	if amount <= 0 or amount > limit:
		GameLog.warn("reward", "dropping xp item with amount %d (%s)" % [amount, source])
		return
	if not _grant_xp.is_valid():
		GameLog.error("reward", "no xp callback; xp not granted (%s)" % source)
		return
	_grant_xp.call(amount)
	granted.add(RewardBundle.TYPE_XP, amount)


func _grant_cosmetic_item(granted: RewardBundle, id: String, source: String) -> void:
	if id.is_empty():
		GameLog.warn("reward", "dropping cosmetic item without id (%s)" % source)
		return
	if _profile.cosmetics_owned.has(id):
		var coins: int = _economy.duplicate_cosmetic_coins()
		if coins > 0:
			var duplicate_source: String = source + DUPLICATE_SOURCE_SUFFIX
			_grant_currency(granted, RewardBundle.TYPE_COINS, coins, DUPLICATE_ID_PREFIX + id, duplicate_source)
		return
	if _call_grant_cosmetic(id, source):
		granted.add(RewardBundle.TYPE_COSMETIC, ITEM_AMOUNT, id)


func _grant_badge_item(granted: RewardBundle, id: String, source: String) -> void:
	if id.is_empty() or _profile.cosmetics_owned.has(id):
		GameLog.debug("reward", "badge '%s' already owned or empty; dropped (%s)" % [id, source])
		return
	if _call_grant_cosmetic(id, source):
		granted.add(RewardBundle.TYPE_BADGE, ITEM_AMOUNT, id)


func _call_grant_cosmetic(id: String, source: String) -> bool:
	if not _grant_cosmetic.is_valid():
		GameLog.error("reward", "no cosmetic callback; '%s' not granted (%s)" % [id, source])
		return false
	var result: Variant = _grant_cosmetic.call(id)
	if typeof(result) == TYPE_BOOL and result as bool:
		return true
	GameLog.warn("reward", "cosmetic '%s' was refused (unknown id?); dropped (%s)" % [id, source])
	return false


func _daily_streak(ctx: Dictionary) -> RewardBundle:
	var tier: int = EconomyService.int_or(ctx.get("tier"), 0)
	if tier < 1:
		GameLog.warn("reward", "daily_streak needs ctx.tier >= 1")
		return RewardBundle.new(TABLE_DAILY_STREAK)
	var best_tier: int = 0
	for raw: Variant in _array(_dict(tables.get(TABLE_DAILY_STREAK)).get("tiers")):
		var entry_tier: int = EconomyService.int_or(_dict(raw).get("tier"), 0)
		if entry_tier <= tier and entry_tier > best_tier:
			best_tier = entry_tier
	var source: String = "%s:%d" % [TABLE_DAILY_STREAK, mini(tier, maxi(best_tier, 1))]
	var spec: Dictionary = daily_tier_reward(tables, tier).duplicate()
	if spec.has(SPEC_COINS_KEY):
		spec[SPEC_COINS_KEY] = RewardEngine.scaled(EconomyService.int_or(spec[SPEC_COINS_KEY], 0), daily_scale)
	return bundle_from_spec(spec, source)


## [param spec] with its coins scaled by the live [member coin_scale]: score
## modes pay through reward specs, and live events must reach them too.
func with_coin_scale(spec: Dictionary) -> Dictionary:
	if not spec.has(SPEC_COINS_KEY):
		return spec
	var out: Dictionary = spec.duplicate()
	out[SPEC_COINS_KEY] = RewardEngine.scaled(EconomyService.int_or(spec[SPEC_COINS_KEY], 0), coin_scale)
	return out


## [param amount] times a tuning [param scale] (rounded; a positive amount
## never drops to zero).
static func scaled(amount: int, scale: float) -> int:
	if amount <= 0 or is_equal_approx(scale, 1.0) or is_nan(scale):
		return amount
	return maxi(1, roundi(float(amount) * clampf(scale, 0.0, 4.0)))


## Most one completed run of a level can pay before the optional ad double:
## every star new and the first perfect included. The server bounds level
## reward claims with it. [param tier] and [param kind] come from the level.
static func level_reward_ceiling(data: Dictionary, tier: String, kind: String, first_clear: bool) -> Dictionary:
	var lvl: Dictionary = _dict(data.get(SECTION_LEVEL))
	var num: Callable = func(key: String) -> int:
		var v: int = EconomyService.int_or(lvl.get(key), -1)
		return v if v >= 0 else int(FALLBACK_LEVEL[key])
	var bases: Dictionary = _dict(lvl.get("base_by_tier"))
	if not bases.has(tier):
		tier = str(lvl.get("default_tier", FALLBACK_LEVEL["default_tier"]))
	var coins: int = 0
	if first_clear:
		coins = EconomyService.int_or(bases.get(tier), num.call("first_clear_coins"))
		coins += maxi(0, EconomyService.int_or(_dict(lvl.get("kind_bonus")).get(kind), 0))
	else:
		coins = EconomyService.int_or(_dict(lvl.get("replay_coins_by_tier")).get(tier), num.call("replay_coins"))
	coins = maxi(coins, maxi(num.call("replay_coins_min"), MIN_COMPLETED_COINS))
	coins += num.call("coins_per_new_star") * MAX_STARS
	return {
		"coins": coins,
		"gems": num.call("perfect_first_gems"),
		"xp": num.call("xp_base") + num.call("xp_per_star") * MAX_STARS,
	}


## Reward spec of the highest streak-table entry at or below [param tier]
## (shared with the server's reward-claim check).
static func daily_tier_reward(data: Dictionary, tier: int) -> Dictionary:
	var best: Dictionary = {}
	var best_tier: int = 0
	for raw: Variant in _array(_dict(data.get(TABLE_DAILY_STREAK)).get("tiers")):
		var entry: Dictionary = _dict(raw)
		var entry_tier: int = EconomyService.int_or(entry.get("tier"), 0)
		if entry_tier <= tier and entry_tier > best_tier:
			best = entry
			best_tier = entry_tier
	return _dict(best.get("reward"))


func _level_up(ctx: Dictionary) -> RewardBundle:
	var level: int = EconomyService.int_or(ctx.get("level"), 0)
	var section: Dictionary = _dict(tables.get(TABLE_LEVEL_UP))
	var bundle: RewardBundle = RewardBundle.new("%s:%d" % [TABLE_LEVEL_UP, level])
	if level < FIRST_LEVEL_UP or section.is_empty():
		GameLog.warn("reward", "level_up needs ctx.level >= %d and a level_up table" % FIRST_LEVEL_UP)
		return bundle
	var coins: int = _int_at(section, "coins_base") + _int_at(section, "coins_per_level") * (level - FIRST_LEVEL_UP)
	var coins_max: int = _int_at(section, "coins_max")
	bundle.add(RewardBundle.TYPE_COINS, mini(coins, coins_max) if coins_max > 0 else coins)
	var every: int = _int_at(section, "gems_every")
	if every > 0 and level % every == 0:
		bundle.add(RewardBundle.TYPE_GEMS, _int_at(section, "gems"))
	for raw: Variant in _array(section.get("milestones")):
		var milestone: Dictionary = _dict(raw)
		if EconomyService.int_or(milestone.get("level"), 0) == level:
			_merge(bundle, bundle_from_spec(_dict(milestone.get("reward")), bundle.source))
	return bundle


func _world_complete(ctx: Dictionary) -> RewardBundle:
	var index: int = EconomyService.int_or(ctx.get("world_index"), 0)
	var section: Dictionary = _dict(tables.get(TABLE_WORLD_COMPLETE))
	var worlds: int = EconomyService.int_or(section.get("worlds"), FALLBACK_WORLD_COUNT)
	var bundle: RewardBundle = RewardBundle.new("%s:%d" % [TABLE_WORLD_COMPLETE, index])
	if index < 1 or index > worlds or section.is_empty():
		GameLog.warn("reward", "world_complete needs ctx.world_index in 1..%d" % worlds)
		return bundle
	var coins: int = _int_at(section, "coins_base") + _int_at(section, "coins_per_world") * (index - 1)
	bundle.add(RewardBundle.TYPE_COINS, coins)
	bundle.add(RewardBundle.TYPE_GEMS, _int_at(section, "gems"))
	bundle.add(RewardBundle.TYPE_XP, _int_at(section, "xp"))
	return bundle


func _level_table() -> Dictionary:
	return _dict(tables.get(SECTION_LEVEL))


func _level_int(key: String) -> int:
	var value: int = EconomyService.int_or(_level_table().get(key), -1)
	return value if value >= 0 else int(FALLBACK_LEVEL[key])


func _level_float(key: String) -> float:
	var raw: Variant = _level_table().get(key)
	if (typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT) and float(raw) >= 0.0:
		return float(raw)
	return float(FALLBACK_LEVEL[key])


func _level_string(key: String) -> String:
	var raw: Variant = _level_table().get(key)
	if typeof(raw) == TYPE_STRING and not (raw as String).is_empty():
		return raw as String
	return str(FALLBACK_LEVEL[key])


func _resolve_tier(ctx: Dictionary) -> String:
	var tier: String = str(ctx.get("tier", ""))
	var known: Dictionary = _dict(_level_table().get("base_by_tier"))
	if known.has(tier):
		return tier
	var fallback: String = _level_string("default_tier")
	if tier != fallback:
		GameLog.warn("reward", "unknown level tier '%s'; using '%s'" % [tier, fallback])
	return fallback


func _kind_bonus(ctx: Dictionary) -> int:
	var kind: String = str(ctx.get("kind", KIND_NORMAL))
	if not KINDS.has(kind):
		GameLog.warn("reward", "unknown level kind '%s'; treated as normal" % kind)
		kind = KIND_NORMAL
	return maxi(0, EconomyService.int_or(_dict(_level_table().get("kind_bonus")).get(kind), 0))


## Per-tier amount; falls back to the table's flat [param fallback_key] value
## (e.g. "replay_coins"), then to the built-in safe value.
func _tier_amount(table_key: String, tier: String, fallback_key: String) -> int:
	var value: int = EconomyService.int_or(_dict(_level_table().get(table_key)).get(tier), -1)
	return value if value >= 0 else _level_int(fallback_key)


static func _merge(into: RewardBundle, from: RewardBundle) -> void:
	for item: Dictionary in from.items:
		into.add(StringName(str(item["type"])), int(item["amount"]), str(item["id"]))


static func _flag(ctx: Dictionary, key: String) -> bool:
	var value: Variant = ctx.get(key, false)
	match typeof(value):
		TYPE_BOOL:
			return value as bool
		TYPE_INT, TYPE_FLOAT:
			return float(value) != 0.0
	return false


static func _int_at(section: Dictionary, key: String) -> int:
	return maxi(0, EconomyService.int_or(section.get(key), 0))


static func _dict(value: Variant) -> Dictionary:
	return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


static func _array(value: Variant) -> Array:
	return value as Array if typeof(value) == TYPE_ARRAY else []


static func _validate_level_table(level: Dictionary, tier_ids: PackedStringArray, errors: PackedStringArray) -> void:
	if level.is_empty():
		errors.append("missing level table")
		return
	var base: Dictionary = _dict(level.get("base_by_tier"))
	var replay: Dictionary = _dict(level.get("replay_coins_by_tier"))
	for tier: String in tier_ids:
		var first: int = EconomyService.int_or(base.get(tier), 0)
		var again: int = EconomyService.int_or(replay.get(tier), 0)
		if first <= 0:
			errors.append("level.base_by_tier.%s must be > 0" % tier)
		if again <= 0 or again >= first:
			errors.append("level.replay_coins_by_tier.%s must be > 0 and below the first-clear amount" % tier)
	if not base.has(str(level.get("default_tier", ""))):
		errors.append("level.default_tier must be one of base_by_tier")
	var bonus: Dictionary = _dict(level.get("kind_bonus"))
	for kind: String in KINDS:
		if EconomyService.int_or(bonus.get(kind), -1) < 0:
			errors.append("level.kind_bonus.%s must be >= 0" % kind)
	for key: String in ["coins_per_new_star", "perfect_first_gems", "xp_per_star", "fail_xp"]:
		if EconomyService.int_or(level.get(key), -1) < 0:
			errors.append("level.%s must be a whole number >= 0" % key)
	for key: String in ["xp_base", "replay_coins_min"]:
		if EconomyService.int_or(level.get(key), 0) <= 0:
			errors.append("level.%s must be > 0" % key)
	if not str(level.get("perfect_badge_prefix", "")).begins_with(BADGE_ID_PREFIX):
		errors.append("level.perfect_badge_prefix must start with '%s'" % BADGE_ID_PREFIX)


static func _validate_daily_streak(section: Dictionary, errors: PackedStringArray) -> void:
	var seen: Dictionary = {}
	for raw: Variant in _array(section.get("tiers")):
		var entry: Dictionary = _dict(raw)
		var tier: int = EconomyService.int_or(entry.get("tier"), 0)
		var reward: Dictionary = _dict(entry.get("reward"))
		if tier < 1 or tier > DAILY_STREAK_TIERS or seen.has(tier):
			errors.append("daily_streak tier %d is invalid or repeated" % tier)
			continue
		seen[tier] = EconomyService.int_or(reward.get(SPEC_COINS), 0)
		if reward.is_empty() or not spec_errors(reward).is_empty():
			errors.append("daily_streak tier %d reward is invalid" % tier)
		if tier < FIRST_GEM_STREAK_TIER and EconomyService.int_or(reward.get(SPEC_GEMS), 0) > 0:
			errors.append("daily_streak tier %d must not give gems" % tier)
	for tier: int in range(1, DAILY_STREAK_TIERS + 1):
		if not seen.has(tier):
			errors.append("daily_streak tier %d missing" % tier)
		elif tier > 1 and seen.has(tier - 1) and int(seen[tier]) < int(seen[tier - 1]):
			errors.append("daily_streak coins must not shrink at tier %d" % tier)


static func _validate_level_up(section: Dictionary, errors: PackedStringArray) -> void:
	if section.is_empty():
		errors.append("missing level_up table")
		return
	for key: String in ["coins_base", "coins_max"]:
		if EconomyService.int_or(section.get(key), 0) <= 0:
			errors.append("level_up.%s must be > 0" % key)
	for key: String in ["coins_per_level", "gems_every", "gems"]:
		if EconomyService.int_or(section.get(key), -1) < 0:
			errors.append("level_up.%s must be >= 0" % key)
	for raw: Variant in _array(section.get("milestones")):
		var milestone: Dictionary = _dict(raw)
		if EconomyService.int_or(milestone.get("level"), 0) < FIRST_LEVEL_UP:
			errors.append("level_up milestone level must be >= %d" % FIRST_LEVEL_UP)
		if not spec_errors(_dict(milestone.get("reward"))).is_empty():
			errors.append("level_up milestone reward is invalid")


static func _validate_world_complete(section: Dictionary, errors: PackedStringArray) -> void:
	if section.is_empty():
		errors.append("missing world_complete table")
		return
	for key: String in ["coins_base", "worlds"]:
		if EconomyService.int_or(section.get(key), 0) <= 0:
			errors.append("world_complete.%s must be > 0" % key)
	for key: String in ["coins_per_world", "gems", "xp"]:
		if EconomyService.int_or(section.get(key), -1) < 0:
			errors.append("world_complete.%s must be >= 0" % key)
