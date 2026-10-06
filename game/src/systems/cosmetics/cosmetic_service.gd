class_name CosmeticService
extends RefCounted
## Cosmetic ownership, equipping, coin/gem purchases and automatic unlocks.
##
## Owns the profile slice [member PlayerProfile.cosmetics_owned] and
## [member PlayerProfile.cosmetics_equipped]. Everything here is visual only:
## no item changes gameplay. Premium items come exclusively from store
## products ([method grant_from_product]); badges and achievement items are
## earned, never bought.
##
## Dependencies are injected: [param economy] provides
## [code]can_afford(currency: StringName, amount: int) -> bool[/code] and
## [code]spend(currency: StringName, amount: int, reason: String) -> bool[/code]
## (optionally [code]balance(currency: StringName) -> int[/code]);
## [param progress_query] is [code]() -> Dictionary[/code] returning
## [code]{"total_stars": int, "player_level": int, "perfects": int,
## "achievements": Array[String]}[/code].

const LOG_CHANNEL: String = "cosmetics"
const SPEND_REASON_PREFIX: String = "cosmetic:"
const METHOD_CAN_AFFORD: StringName = &"can_afford"
const METHOD_SPEND: StringName = &"spend"
const METHOD_BALANCE: StringName = &"balance"
const PROGRESS_STARS: String = "total_stars"
const PROGRESS_LEVEL: String = "player_level"
const PROGRESS_PERFECTS: String = "perfects"
const PROGRESS_ACHIEVEMENTS: String = "achievements"

## The catalog this service works on (read-only use; exposed for UI lookups
## such as [method CosmeticCatalog.typed_params] for badges).
var catalog: CosmeticCatalog = null
## Test builds: every item can be worn without buying it. Counts and the
## profile keep real ownership only.
var unlock_all: bool = false
var _profile: PlayerProfile = null
var _bus: EventBus = null
var _economy: Object = null
var _progress_query: Callable = Callable()


## Missing dependencies degrade safely: a blank profile, the shipped catalog,
## no purchases without an economy and no auto unlocks without a query.
func _init(
	profile: PlayerProfile, bus: EventBus, cosmetic_catalog: CosmeticCatalog, economy: Object, progress_query: Callable
) -> void:
	_profile = profile
	if _profile == null:
		GameLog.warn(LOG_CHANNEL, "no profile injected; using a blank one")
		_profile = PlayerProfile.new()
	_bus = bus
	catalog = cosmetic_catalog
	if catalog == null:
		GameLog.warn(LOG_CHANNEL, "no catalog injected; loading the shipped catalog")
		catalog = CosmeticCatalog.load_default()
	_economy = economy
	_progress_query = progress_query


## Owns and equips the default item of every category and repairs equipped
## entries that point at unknown, unowned or wrong-category items. Call after
## loading a profile. Returns true when the profile was changed.
func ensure_defaults() -> bool:
	var changed: bool = false
	var known: PackedStringArray = catalog.categories()
	for category: String in known:
		var default_id: String = catalog.default_for(category)
		if default_id.is_empty():
			GameLog.error(LOG_CHANNEL, "category %s has no default item" % category)
			continue
		if not _profile.cosmetics_owned.has(default_id):
			_profile.cosmetics_owned.append(default_id)
			changed = true
		var current: String = str(_profile.cosmetics_equipped.get(category, ""))
		if not _can_wear(category, current):
			if not current.is_empty():
				GameLog.warn(LOG_CHANNEL, "equipped %s '%s' invalid; reverting to default" % [category, current])
			_profile.cosmetics_equipped[category] = default_id
			changed = true
	for key: Variant in _profile.cosmetics_equipped.keys():
		if not known.has(str(key)):
			_profile.cosmetics_equipped.erase(key)
			changed = true
	return changed


## True when the player owns [param id] (category defaults always count).
func owns(id: String) -> bool:
	if unlock_all and catalog.has_item(id):
		return true
	return _really_owns(id)


func _really_owns(id: String) -> bool:
	if not catalog.has_item(id):
		return false
	if _profile.cosmetics_owned.has(id):
		return true
	return catalog.default_for(catalog.category_of(id)) == id


## The equipped item id of [param category] (the default when nothing valid
## is equipped; "" for unknown categories).
func equipped(category: String) -> String:
	if not catalog.categories().has(category):
		return ""
	var current: String = str(_profile.cosmetics_equipped.get(category, ""))
	if _can_wear(category, current):
		return current
	return catalog.default_for(category)


## Equips an owned item. Returns false for unknown or unowned items. Emits
## [signal EventBus.cosmetic_equipped] when the selection changes.
func equip(id: String) -> bool:
	if not catalog.has_item(id):
		GameLog.warn(LOG_CHANNEL, "cannot equip unknown item '%s'" % id)
		return false
	if not owns(id):
		return false
	var category: String = catalog.category_of(id)
	if str(_profile.cosmetics_equipped.get(category, "")) == id:
		return true
	_profile.cosmetics_equipped[category] = id
	if _bus != null:
		_bus.cosmetic_equipped.emit(StringName(category), id)
	return true


## Adds [param id] to the collection. Returns true only when it was newly
## owned (false for duplicates and unknown ids). Emits
## [signal EventBus.cosmetic_unlocked]; changes nothing else.
func grant(id: String) -> bool:
	if not catalog.has_item(id):
		GameLog.warn(LOG_CHANNEL, "cannot grant unknown item '%s'" % id)
		return false
	if owns(id):
		return false
	_profile.cosmetics_owned.append(id)
	if _bus != null:
		_bus.cosmetic_unlocked.emit(id)
	return true


## Buys a coin/gem item through the economy. Premium, badge, achievement and
## progress items cannot be bought. Returns true when the item was granted.
func purchase(id: String) -> bool:
	if not catalog.has_item(id) or owns(id):
		return false
	var price: int = _sale_price(id)
	var currency_name: String = str(catalog.unlock_of(id)["type"])
	if price <= 0:
		GameLog.info(LOG_CHANNEL, "item '%s' (%s) is not for sale" % [id, currency_name])
		return false
	if not _economy_ready():
		return false
	var currency: StringName = StringName(currency_name)
	if not bool(_economy.call(METHOD_CAN_AFFORD, currency, price)):
		return false
	if not bool(_economy.call(METHOD_SPEND, currency, price, SPEND_REASON_PREFIX + id)):
		return false
	return grant(id)


## Unlock state of an item for the collection UI:
## {"owned", "can_unlock_now", "type", "progress", "target", "price": {"currency", "amount"}}
## plus "requirement" (achievement id / tier for String requirements) and
## "products" (store products selling a premium item).
func unlock_status(id: String) -> Dictionary:
	var status: Dictionary = {
		"owned": false,
		"can_unlock_now": false,
		"type": "",
		"progress": 0,
		"target": 0,
		"price": {},
		"requirement": "",
		"products": PackedStringArray(),
	}
	if not catalog.has_item(id):
		return status
	var unlock: Dictionary = catalog.unlock_of(id)
	var type: String = str(unlock["type"])
	var owned: bool = owns(id)
	status["owned"] = owned
	status["type"] = type
	var price: int = _sale_price(id)
	if price > 0:
		_fill_price_status(status, type, price)
	elif CosmeticCatalog.PURCHASABLE_UNLOCKS.has(type):
		# Malformed sale data (e.g. a priced badge): shown locked, never buyable.
		status["target"] = 1
	elif type == CosmeticCatalog.UNLOCK_PREMIUM:
		status["products"] = catalog.products_containing(id)
		status["target"] = 1
		status["progress"] = 1 if owned else 0
	elif type == CosmeticCatalog.UNLOCK_DEFAULT:
		status["target"] = 1
		status["progress"] = 1
	else:
		_fill_progress_status(status, type, unlock["value"], _progress())
	if owned:
		status["can_unlock_now"] = false
		status["progress"] = status["target"]
	return status


## Grants every not-yet-owned item whose stars / player level / perfects /
## achievement requirement is met. Returns the newly granted ids.
func check_auto_unlocks() -> Array[String]:
	var granted: Array[String] = []
	var progress: Dictionary = _progress()
	for it: Dictionary in catalog.items:
		var id: String = str(it["id"])
		if owns(id):
			continue
		var unlock: Dictionary = catalog.unlock_of(id)
		if not CosmeticCatalog.AUTO_UNLOCKS.has(str(unlock["type"])):
			continue
		if _requirement_met(str(unlock["type"]), unlock["value"], progress) and grant(id):
			granted.append(id)
	return granted


## Coin/gem shop rows, not-owned first (then category order and price):
## {"id", "category", "name_key", "rarity", "currency", "price", "owned",
## "affordable", "equipped"}.
func shop_items() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for it: Dictionary in catalog.items:
		var id: String = str(it["id"])
		var category: String = str(it["category"])
		var price: int = _sale_price(id)
		if price <= 0:
			continue
		var currency_name: String = str(catalog.unlock_of(id)["type"])
		(
			rows
			. append(
				{
					"id": id,
					"category": category,
					"name_key": str(it.get("name_key", "")),
					"rarity": str(it.get("rarity", "")),
					"currency": currency_name,
					"price": price,
					"owned": owns(id),
					"affordable": _can_afford(currency_name, price),
					"equipped": equipped(category) == id,
				}
			)
		)
	var order: PackedStringArray = catalog.categories()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _shop_row_before(a, b, order))
	return rows


## Number of catalog items the player owns (defaults included).
func owned_count() -> int:
	var count: int = 0
	for it: Dictionary in catalog.items:
		if _really_owns(str(it["id"])):
			count += 1
	return count


## Number of items in the catalog.
func total_count() -> int:
	return catalog.items.size()


## Core shader params: {"id", "style": int, "color_a": Color, "color_b": Color,
## "rim": Color, "anim_speed": float}. An empty [param id] means the equipped
## skin; unknown ids fall back to the category default.
func core_skin_params(id: String = "") -> Dictionary:
	return _params(CosmeticCatalog.CORE_SKIN, id)


## Trail shader params: {"id", "style": int, "head": Color, "tail": Color}.
func trail_params(id: String = "") -> Dictionary:
	return _params(CosmeticCatalog.TRAIL, id)


## Collect burst preset: {"id", "colors": Array[Color], "size_mult": float,
## "count_mult": float}.
func particle_params(id: String = "") -> Dictionary:
	return _params(CosmeticCatalog.PARTICLE, id)


## Sky overrides: {"id", "use_world_palette": bool, "sky_top": Color,
## "sky_bottom": Color, "star_density": float}.
func background_params(id: String = "") -> Dictionary:
	return _params(CosmeticCatalog.BACKGROUND, id)


## UI accent palette: {"id", "accent": Color, "accent_2": Color, "panel_tint": Color}.
func theme_params(id: String = "") -> Dictionary:
	return _params(CosmeticCatalog.THEME, id)


## Fail/perfect explosion variant: {"id", "fail_color": Color,
## "perfect_color": Color, "accent": Color, "shockwave": float}.
func effect_params(id: String = "") -> Dictionary:
	return _params(CosmeticCatalog.EFFECT, id)


## Avatar frame: {"id", "color": Color, "accent": Color, "pattern": String}.
func frame_params(id: String = "") -> Dictionary:
	return _params(CosmeticCatalog.FRAME, id)


## Procedural avatar: {"id", "glyph": String, "bg": Color, "fg": Color}.
func avatar_params(id: String = "") -> Dictionary:
	return _params(CosmeticCatalog.AVATAR, id)


## Grants every item of store product [param product_id] (used by the store
## after a verified purchase or restore). Returns the newly owned ids; an
## unknown product grants nothing.
func grant_from_product(product_id: String) -> Array[String]:
	var granted: Array[String] = []
	var p: Dictionary = catalog.product(product_id)
	if p.is_empty():
		GameLog.warn(LOG_CHANNEL, "unknown product '%s'" % product_id)
		return granted
	var list: Variant = p.get("items", [])
	if typeof(list) != TYPE_ARRAY:
		return granted
	for raw: Variant in list as Array:
		if typeof(raw) != TYPE_STRING:
			GameLog.warn(LOG_CHANNEL, "product '%s' lists a non-id entry %s" % [product_id, str(raw)])
			continue
		var id: String = raw as String
		if grant(id):
			granted.append(id)
	return granted


func _can_wear(category: String, id: String) -> bool:
	if id.is_empty() or not catalog.has_item(id):
		return false
	return catalog.category_of(id) == category and owns(id)


func _params(category: String, id: String) -> Dictionary:
	var resolved: String = id if not id.is_empty() else equipped(category)
	if catalog.category_of(resolved) != category:
		GameLog.warn(LOG_CHANNEL, "'%s' is not a %s item; using the default" % [resolved, category])
		resolved = catalog.default_for(category)
	# typed_params() parses in place (no item copy); {} only for an empty catalog.
	var out: Dictionary = catalog.typed_params(resolved)
	if out.is_empty():
		out = catalog.parse_params(category, {})
	out["id"] = resolved
	return out


## The coin/gem price of a purchasable item, or 0 when it is not for sale
## (badges, premium/earned items, unknown ids or malformed prices).
func _sale_price(id: String) -> int:
	if catalog.category_of(id) == CosmeticCatalog.BADGE:
		return 0
	var unlock: Dictionary = catalog.unlock_of(id)
	if not CosmeticCatalog.PURCHASABLE_UNLOCKS.has(str(unlock["type"])):
		return 0
	var value: Variant = unlock["value"]
	return maxi(0, value as int) if typeof(value) == TYPE_INT else 0


func _economy_ready() -> bool:
	if _economy == null:
		GameLog.error(LOG_CHANNEL, "no economy injected; purchases unavailable")
		return false
	if not _economy.has_method(METHOD_CAN_AFFORD) or not _economy.has_method(METHOD_SPEND):
		GameLog.error(LOG_CHANNEL, "economy lacks can_afford/spend; purchases unavailable")
		return false
	return true


func _can_afford(currency_name: String, price: int) -> bool:
	if _economy == null or not _economy.has_method(METHOD_CAN_AFFORD):
		return false
	return bool(_economy.call(METHOD_CAN_AFFORD, StringName(currency_name), price))


func _fill_price_status(status: Dictionary, currency_name: String, price: int) -> void:
	status["price"] = {"currency": currency_name, "amount": price}
	status["target"] = price
	var affordable: bool = _can_afford(currency_name, price)
	var balance: int = price if affordable else 0
	if _economy != null and _economy.has_method(METHOD_BALANCE):
		balance = int(_economy.call(METHOD_BALANCE, StringName(currency_name)))
	status["progress"] = clampi(balance, 0, price)
	status["can_unlock_now"] = affordable


func _fill_progress_status(status: Dictionary, type: String, value: Variant, progress: Dictionary) -> void:
	status["can_unlock_now"] = _requirement_met(type, value, progress)
	if typeof(value) == TYPE_STRING:
		# Achievement ids and perfect tiers are yes/no requirements.
		status["requirement"] = value as String
		status["target"] = 1
		status["progress"] = 1 if status["can_unlock_now"] else 0
		return
	var target: int = int(value)
	status["target"] = target
	status["progress"] = clampi(_progress_value(type, progress), 0, target)


func _requirement_met(type: String, value: Variant, progress: Dictionary) -> bool:
	if type == CosmeticCatalog.UNLOCK_ACHIEVEMENT:
		var achieved: PackedStringArray = progress[PROGRESS_ACHIEVEMENTS] as PackedStringArray
		return typeof(value) == TYPE_STRING and achieved.has(value as String)
	if typeof(value) == TYPE_STRING:
		# Tier perfect badges are granted by the reward engine, not by counts.
		return false
	var target: int = int(value)
	return target > 0 and _progress_value(type, progress) >= target


func _progress_value(type: String, progress: Dictionary) -> int:
	match type:
		CosmeticCatalog.UNLOCK_STARS:
			return int(progress[PROGRESS_STARS])
		CosmeticCatalog.UNLOCK_PLAYER_LEVEL:
			return int(progress[PROGRESS_LEVEL])
		CosmeticCatalog.UNLOCK_PERFECTS:
			return int(progress[PROGRESS_PERFECTS])
	return 0


## Normalised progress snapshot; an invalid query or result means no progress.
func _progress() -> Dictionary:
	var out: Dictionary = {
		PROGRESS_STARS: 0,
		PROGRESS_LEVEL: 1,
		PROGRESS_PERFECTS: 0,
		PROGRESS_ACHIEVEMENTS: PackedStringArray(),
	}
	if not _progress_query.is_valid():
		return out
	var raw: Variant = _progress_query.call()
	if typeof(raw) != TYPE_DICTIONARY:
		GameLog.warn(LOG_CHANNEL, "progress query returned %s; ignoring" % type_string(typeof(raw)))
		return out
	var d: Dictionary = raw as Dictionary
	for key: String in [PROGRESS_STARS, PROGRESS_LEVEL, PROGRESS_PERFECTS]:
		var v: Variant = d.get(key)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			out[key] = maxi(0, int(v))
	var achieved: PackedStringArray = PackedStringArray()
	var list: Variant = d.get(PROGRESS_ACHIEVEMENTS, [])
	if typeof(list) == TYPE_ARRAY or typeof(list) == TYPE_PACKED_STRING_ARRAY:
		for a: Variant in list:
			achieved.append(str(a))
	out[PROGRESS_ACHIEVEMENTS] = achieved
	return out


func _shop_row_before(a: Dictionary, b: Dictionary, order: PackedStringArray) -> bool:
	if bool(a["owned"]) != bool(b["owned"]):
		return not bool(a["owned"])
	var ca: int = order.find(str(a["category"]))
	var cb: int = order.find(str(b["category"]))
	if ca != cb:
		return ca < cb
	if str(a["currency"]) != str(b["currency"]):
		return str(a["currency"]) == CosmeticCatalog.UNLOCK_COINS
	if int(a["price"]) != int(b["price"]):
		return int(a["price"]) < int(b["price"])
	return str(a["id"]) < str(b["id"])
