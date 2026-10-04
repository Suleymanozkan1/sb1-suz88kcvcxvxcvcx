class_name CosmeticCatalog
extends RefCounted
## Cosmetic item definitions (data/cosmetics/cosmetics.json) together with the
## store products that sell premium cosmetic packs (data/store/products.json).
##
## Pure data, parsing and validation: ownership and equipping live in
## [CosmeticService]. Every item is purely visual; nothing in this catalog can
## affect gameplay, and products may only contain premium cosmetic ids.
##
## Item schema:
## [codeblock]
## {"id": "core_fire", "category": "core_skin", "name_key": "cos.core_fire.name",
##  "rarity": "common", "unlock": {"type": "coins", "value": 400}, "params": {...}}
## [/codeblock]
## Unlock types: default, coins, gems (int price), stars, player_level (int
## target), perfects (int total perfect runs, or a String difficulty tier whose
## first perfect is rewarded by the reward engine), achievement (String
## achievement id) and premium (only obtainable through a store product).

enum ParamKind { INT, FLOAT, BOOL, COLOR, COLOR_LIST, STRING }

const DEFAULT_PATH: String = "res://data/cosmetics/cosmetics.json"
const DEFAULT_PRODUCTS_PATH: String = "res://data/store/products.json"
const SUPPORTED_SCHEMA: int = 1

const CORE_SKIN: String = "core_skin"
const TRAIL: String = "trail"
const PARTICLE: String = "particle"
const BACKGROUND: String = "background"
const THEME: String = "theme"
const EFFECT: String = "effect"
const BADGE: String = "badge"
const FRAME: String = "frame"
const AVATAR: String = "avatar"
## The categories every catalog must provide (data may order them).
const REQUIRED_CATEGORIES: PackedStringArray = [
	"core_skin",
	"trail",
	"particle",
	"background",
	"theme",
	"effect",
	"badge",
	"frame",
	"avatar",
]

const UNLOCK_DEFAULT: String = "default"
const UNLOCK_COINS: String = "coins"
const UNLOCK_GEMS: String = "gems"
const UNLOCK_STARS: String = "stars"
const UNLOCK_PLAYER_LEVEL: String = "player_level"
const UNLOCK_ACHIEVEMENT: String = "achievement"
const UNLOCK_PERFECTS: String = "perfects"
const UNLOCK_PREMIUM: String = "premium"
const UNLOCK_TYPES: PackedStringArray = [
	"default",
	"coins",
	"gems",
	"stars",
	"player_level",
	"achievement",
	"perfects",
	"premium",
]
## Unlock types that can be bought with in-game currency.
const PURCHASABLE_UNLOCKS: PackedStringArray = ["coins", "gems"]
## Unlock types granted automatically once the player's progress qualifies.
const AUTO_UNLOCKS: PackedStringArray = ["stars", "player_level", "perfects", "achievement"]
## Badges are earned only (never bought).
const BADGE_UNLOCKS: PackedStringArray = ["default", "achievement", "perfects"]
## Unlock types whose value must be a positive integer.
const INT_UNLOCKS: PackedStringArray = ["coins", "gems", "stars", "player_level"]
const FALLBACK_RARITIES: PackedStringArray = ["common", "rare", "epic", "legendary"]

const PRODUCT_TYPE: String = "non_consumable"
## The only fields a product may carry: anything else (coins, gems, boosters…)
## is rejected so products can never grant currency or gameplay power.
const PRODUCT_FIELDS: PackedStringArray = ["id", "type", "name_key", "desc_key", "items", "display_price_hint"]
const ID_CHARS: String = "abcdefghijklmnopqrstuvwxyz0123456789_"
const HEX_DIGITS: String = "0123456789abcdef"
## The reward engine grants "badge_perfect_<tier>" on a tier's first perfect
## run, so a tier-valued perfects unlock is only obtainable on that badge.
const PERFECT_TIER_BADGE_PREFIX: String = "badge_perfect_"
const KEY_PREFIX: String = "cos."
const CONFIG_RANGES: String = "ranges"
const CONFIG_MINIMUMS: String = "min_per_category"
const CONFIG_TIERS: String = "perfect_tiers"

## Typed parameter schema per category.
const PARAM_SCHEMA: Dictionary[String, Dictionary] = {
	"core_skin":
	{
		"style": ParamKind.INT,
		"color_a": ParamKind.COLOR,
		"color_b": ParamKind.COLOR,
		"rim": ParamKind.COLOR,
		"anim_speed": ParamKind.FLOAT,
	},
	"trail": {"style": ParamKind.INT, "head": ParamKind.COLOR, "tail": ParamKind.COLOR},
	"particle": {"colors": ParamKind.COLOR_LIST, "size_mult": ParamKind.FLOAT, "count_mult": ParamKind.FLOAT},
	"background":
	{
		"use_world_palette": ParamKind.BOOL,
		"sky_top": ParamKind.COLOR,
		"sky_bottom": ParamKind.COLOR,
		"star_density": ParamKind.FLOAT,
	},
	"theme": {"accent": ParamKind.COLOR, "accent_2": ParamKind.COLOR, "panel_tint": ParamKind.COLOR},
	"effect":
	{
		"fail_color": ParamKind.COLOR,
		"perfect_color": ParamKind.COLOR,
		"accent": ParamKind.COLOR,
		"shockwave": ParamKind.FLOAT,
	},
	"badge": {"icon": ParamKind.STRING, "color": ParamKind.COLOR},
	"frame": {"color": ParamKind.COLOR, "accent": ParamKind.COLOR, "pattern": ParamKind.STRING},
	"avatar": {"glyph": ParamKind.STRING, "bg": ParamKind.COLOR, "fg": ParamKind.COLOR},
}
## "category.param" -> name of the option list (in cosmetics.json) the value
## must come from. INT params are indices into the list, STRING params members.
const OPTION_LISTS: Dictionary[String, String] = {
	"core_skin.style": "core_styles",
	"trail.style": "trail_styles",
	"badge.icon": "badge_icons",
	"frame.pattern": "frame_patterns",
	"avatar.glyph": "avatar_glyphs",
}
const FALLBACK_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const FALLBACK_FLOAT: float = 1.0
const MAX_PARTICLE_COLORS: int = 6

## Valid item definitions in data order (unique ids, known categories).
var items: Array[Dictionary] = []
## Product definitions from products.json in data order.
var products: Array[Dictionary] = []
var _config: Dictionary = {}
var _by_id: Dictionary[String, Dictionary] = {}
var _products_by_id: Dictionary[String, Dictionary] = {}
## category -> id of its first default item
var _defaults: Dictionary[String, String] = {}
var _load_errors: PackedStringArray = PackedStringArray()


## Loads the shipped catalog and products.
static func load_default() -> CosmeticCatalog:
	var c: CosmeticCatalog = CosmeticCatalog.new()
	c.load_from(DEFAULT_PATH, DEFAULT_PRODUCTS_PATH)
	return c


## Builds a catalog from already parsed data (used by tests and tools).
static func from_data(cosmetics: Dictionary, products_data: Dictionary) -> CosmeticCatalog:
	var c: CosmeticCatalog = CosmeticCatalog.new()
	c._ingest(cosmetics, products_data)
	return c


## Reads both JSON files; missing or broken files leave an empty (but safe)
## catalog and are reported by [method validate].
func load_from(cosmetics_path: String, products_path: String) -> void:
	var cosmetics: Dictionary = JsonIO.read_dict(cosmetics_path)
	var products_data: Dictionary = JsonIO.read_dict(products_path)
	_ingest(cosmetics, products_data)
	if cosmetics.is_empty():
		_load_errors.append("cosmetics file missing or invalid: %s" % cosmetics_path)
	if products_data.is_empty():
		_load_errors.append("products file missing or invalid: %s" % products_path)
	for e: String in _load_errors:
		GameLog.error("cosmetics", e)


## A copy of the item definition, or {} for unknown ids.
func item(id: String) -> Dictionary:
	var it: Dictionary = _by_id.get(id, {}) as Dictionary
	return it.duplicate(true)


## True when [param id] is a known cosmetic item.
func has_item(id: String) -> bool:
	return _by_id.has(id)


## Copies of every item of [param category], in data order.
func in_category(category: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it: Dictionary in items:
		if str(it.get("category", "")) == category:
			out.append(it.duplicate(true))
	return out


## Category ids in display order.
func categories() -> PackedStringArray:
	var raw: Variant = _config.get("categories")
	var out: PackedStringArray = PackedStringArray()
	if typeof(raw) == TYPE_ARRAY:
		for c: Variant in raw as Array:
			var s: String = str(c)
			if REQUIRED_CATEGORIES.has(s) and not out.has(s):
				out.append(s)
	for required: String in REQUIRED_CATEGORIES:
		if not out.has(required):
			out.append(required)
	return out


## The id of the default (free, pre-owned) item of [param category], or "".
func default_for(category: String) -> String:
	return str(_defaults.get(category, ""))


## The category of item [param id] ("" for unknown ids).
func category_of(id: String) -> String:
	return str((_by_id.get(id, {}) as Dictionary).get("category", ""))


## The product definition, or {} for unknown product ids.
func product(product_id: String) -> Dictionary:
	return (_products_by_id.get(product_id, {}) as Dictionary).duplicate(true)


## Ids of the products that contain [param item_id].
func products_containing(item_id: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for p: Dictionary in products:
		var list: Variant = p.get("items")
		if typeof(list) == TYPE_ARRAY and (list as Array).has(item_id):
			out.append(str(p.get("id", "")))
	return out


## Normalised unlock rule: {"type": String, "value": int|String}. Unknown
## items or malformed rules yield type "" (never unlockable).
func unlock_of(id: String) -> Dictionary:
	var it: Dictionary = _by_id.get(id, {}) as Dictionary
	var raw: Variant = it.get("unlock")
	if typeof(raw) != TYPE_DICTIONARY:
		return {"type": "", "value": 0}
	var u: Dictionary = raw as Dictionary
	var type: String = str(u.get("type", ""))
	var value: Variant = u.get("value", 0)
	if typeof(value) == TYPE_STRING:
		return {"type": type, "value": value as String}
	var as_int: int = CosmeticCatalog._to_int(value, 0)
	return {"type": type, "value": as_int}


## The option list named [param list_name] (e.g. "core_styles").
func options(list_name: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var raw: Variant = _config.get(list_name)
	if typeof(raw) == TYPE_ARRAY:
		for v: Variant in raw as Array:
			out.append(str(v))
	return out


## Typed parameters of item [param id] (see [method parse_params]); {} for
## unknown ids.
func typed_params(id: String) -> Dictionary:
	var it: Dictionary = _by_id.get(id, {}) as Dictionary
	if it.is_empty():
		return {}
	return parse_params(str(it.get("category", "")), it.get("params", {}))


## Parses raw JSON params into typed values for [param category]: Colors from
## "#rrggbb"/"#rrggbbaa", ints, floats clamped to the configured ranges,
## option strings and colour lists. Missing or invalid values fall back to
## safe defaults so callers can always apply the result.
func parse_params(category: String, raw: Variant) -> Dictionary:
	var src: Dictionary = raw as Dictionary if typeof(raw) == TYPE_DICTIONARY else {}
	var schema: Dictionary = PARAM_SCHEMA.get(category, {}) as Dictionary
	var out: Dictionary = {}
	for field: String in schema:
		out[field] = _parse_field(category, field, int(schema[field]), src.get(field))
	return out


## Returns every problem found in the data (empty when the catalog is sound):
## load problems, malformed config sections (option lists, ranges,
## minimums), duplicate ids, missing/duplicate defaults, unknown unlock types
## or values, tier perfects unlocks on anything but "badge_perfect_<tier>"
## (and tiers without that badge), missing/invalid params or translation
## keys, purchasable badges, premium items that no product sells and products
## that reference unknown or non-premium ids or carry anything but cosmetic
## items. Malformed data is reported, never fatal.
func validate() -> PackedStringArray:
	var errors: PackedStringArray = _load_errors.duplicate()
	if CosmeticCatalog._to_int(_config.get("schema_version"), 0) != SUPPORTED_SCHEMA:
		errors.append("unsupported cosmetics schema_version %s" % str(_config.get("schema_version")))
	errors.append_array(_config_errors())
	for it: Dictionary in items:
		errors.append_array(_item_errors(it))
	errors.append_array(_category_errors())
	errors.append_array(_tier_badge_errors())
	errors.append_array(_product_errors())
	return errors


## Converts a "#rrggbb" or "#rrggbbaa" string to a Color ([param fallback]
## when invalid).
static func parse_color(raw: Variant, fallback: Color = FALLBACK_COLOR) -> Color:
	if typeof(raw) != TYPE_STRING or not CosmeticCatalog.is_hex_color(raw as String):
		return fallback
	return Color.html(raw as String)


## True for "#rrggbb" / "#rrggbbaa" strings (hex digits only: no sign, no
## spaces).
static func is_hex_color(text: String) -> bool:
	if not text.begins_with("#"):
		return false
	var hex: String = text.substr(1).to_lower()
	if hex.length() != 6 and hex.length() != 8:
		return false
	for ch: String in hex:
		if not HEX_DIGITS.contains(ch):
			return false
	return true


func _ingest(cosmetics: Dictionary, products_data: Dictionary) -> void:
	items.clear()
	products.clear()
	_by_id.clear()
	_products_by_id.clear()
	_defaults.clear()
	_load_errors.clear()
	_config = cosmetics.duplicate(true)
	_config.erase("items")
	var known: PackedStringArray = categories()
	var raw_items: Variant = cosmetics.get("items", [])
	if typeof(raw_items) != TYPE_ARRAY:
		_load_errors.append("cosmetics 'items' must be an array")
		raw_items = []
	for raw: Variant in raw_items as Array:
		_ingest_item(raw, known)
	var raw_products: Variant = products_data.get("products", [])
	if typeof(raw_products) != TYPE_ARRAY:
		_load_errors.append("products 'products' must be an array")
		raw_products = []
	for raw_p: Variant in raw_products as Array:
		if typeof(raw_p) != TYPE_DICTIONARY:
			_load_errors.append("product entry is not an object: %s" % str(raw_p))
			continue
		var p: Dictionary = (raw_p as Dictionary).duplicate(true)
		var pid: String = str(p.get("id", ""))
		if _products_by_id.has(pid):
			_load_errors.append("duplicate product id '%s'" % pid)
			continue
		products.append(p)
		_products_by_id[pid] = p


func _ingest_item(raw: Variant, known: PackedStringArray) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		_load_errors.append("item entry is not an object: %s" % str(raw))
		return
	var it: Dictionary = (raw as Dictionary).duplicate(true)
	var id: String = str(it.get("id", "")) if typeof(it.get("id")) == TYPE_STRING else ""
	if not _is_valid_id(id):
		_load_errors.append("invalid item id '%s'" % str(it.get("id")))
		return
	if _by_id.has(id):
		_load_errors.append("duplicate item id '%s'" % id)
		return
	var category: String = str(it.get("category", ""))
	if not known.has(category):
		_load_errors.append("%s: unknown category '%s'" % [id, category])
		return
	items.append(it)
	_by_id[id] = it
	if not _defaults.has(category) and unlock_of(id)["type"] == UNLOCK_DEFAULT:
		_defaults[category] = id


## Shape problems of the top-level configuration (option lists, ranges and
## per-category minimums).
func _config_errors() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	for list_name: String in OPTION_LISTS.values():
		if options(list_name).is_empty():
			errors.append("option list '%s' missing" % list_name)
	for section: String in [CONFIG_RANGES, CONFIG_MINIMUMS]:
		if _config.has(section) and typeof(_config[section]) != TYPE_DICTIONARY:
			errors.append("'%s' must be an object" % section)
	var ranges: Dictionary = _config_dict(CONFIG_RANGES)
	for key: Variant in ranges:
		if _range_for(str(key)) == Vector2.ZERO:
			errors.append("range '%s' must be [min, max] numbers with min < max" % str(key))
	return errors


func _item_errors(it: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	var id: String = str(it["id"])
	var category: String = str(it["category"])
	errors.append_array(CosmeticCatalog._key_errors(id, "name_key", it.get("name_key"), true))
	errors.append_array(CosmeticCatalog._key_errors(id, "desc_key", it.get("desc_key"), false))
	var rarities: PackedStringArray = options("rarities")
	if rarities.is_empty():
		rarities = FALLBACK_RARITIES
	if not rarities.has(str(it.get("rarity", ""))):
		errors.append("%s: unknown rarity '%s'" % [id, str(it.get("rarity", ""))])
	errors.append_array(_unlock_errors(id, category, it.get("unlock")))
	errors.append_array(_param_errors(id, category, it.get("params")))
	return errors


func _unlock_errors(id: String, category: String, raw: Variant) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: unlock missing" % id)
		return errors
	var u: Dictionary = raw as Dictionary
	var type: String = str(u.get("type", ""))
	var value: Variant = u.get("value")
	if not UNLOCK_TYPES.has(type):
		errors.append("%s: unknown unlock type '%s'" % [id, type])
		return errors
	if category == BADGE and not BADGE_UNLOCKS.has(type):
		errors.append("%s: badges can only be earned (unlock '%s' not allowed)" % [id, type])
	if INT_UNLOCKS.has(type) and CosmeticCatalog._to_int(value, 0) <= 0:
		errors.append("%s: unlock %s needs a positive integer value" % [id, type])
	elif type == UNLOCK_ACHIEVEMENT and (typeof(value) != TYPE_STRING or (value as String).is_empty()):
		errors.append("%s: achievement unlock needs an achievement id" % id)
	elif type == UNLOCK_PERFECTS and typeof(value) == TYPE_STRING:
		if not options(CONFIG_TIERS).has(value as String):
			errors.append("%s: perfects unlock needs a positive count or a known tier" % id)
		elif id != PERFECT_TIER_BADGE_PREFIX + (value as String):
			errors.append("%s: a tier perfects unlock is only granted to %s%s" % [id, PERFECT_TIER_BADGE_PREFIX, value])
	elif type == UNLOCK_PERFECTS and CosmeticCatalog._to_int(value, 0) <= 0:
		errors.append("%s: perfects unlock needs a positive count or a known tier" % id)
	elif type == UNLOCK_PREMIUM and products_containing(id).is_empty():
		errors.append("%s: premium item is not sold in any product" % id)
	return errors


func _param_errors(id: String, category: String, raw: Variant) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: params missing" % id)
		return errors
	var params: Dictionary = raw as Dictionary
	var schema: Dictionary = PARAM_SCHEMA.get(category, {}) as Dictionary
	for field: String in schema:
		if not params.has(field):
			errors.append("%s: missing param '%s'" % [id, field])
			continue
		var problem: String = _field_problem(category, field, int(schema[field]), params[field])
		if not problem.is_empty():
			errors.append("%s: param '%s' %s" % [id, field, problem])
	return errors


## Describes why a raw param value is invalid ("" when valid).
func _field_problem(category: String, field: String, kind: int, value: Variant) -> String:
	var key: String = "%s.%s" % [category, field]
	var problem: String = ""
	match kind:
		ParamKind.INT:
			problem = _int_problem(key, value)
		ParamKind.FLOAT:
			problem = _float_problem(key, value)
		ParamKind.BOOL:
			problem = "" if typeof(value) == TYPE_BOOL else "must be a boolean"
		ParamKind.COLOR:
			var ok: bool = typeof(value) == TYPE_STRING and CosmeticCatalog.is_hex_color(value as String)
			problem = "" if ok else "must be a #rrggbb colour"
		ParamKind.COLOR_LIST:
			problem = CosmeticCatalog._color_list_problem(value)
		ParamKind.STRING:
			problem = _string_problem(key, value)
	return problem


func _int_problem(key: String, value: Variant) -> String:
	if not CosmeticCatalog._is_integral(value):
		return "must be an integer"
	if not OPTION_LISTS.has(key):
		return ""
	var count: int = options(OPTION_LISTS[key]).size()
	var n: int = CosmeticCatalog._to_int(value, -1)
	return "" if n >= 0 and n < count else "out of range 0..%d" % (count - 1)


func _float_problem(key: String, value: Variant) -> String:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return "must be a number"
	var r: Vector2 = _range_for(key)
	if r != Vector2.ZERO and (float(value) < r.x or float(value) > r.y):
		return "out of range %s..%s" % [str(r.x), str(r.y)]
	return ""


func _string_problem(key: String, value: Variant) -> String:
	if typeof(value) != TYPE_STRING or (value as String).is_empty():
		return "must be a non-empty string"
	if OPTION_LISTS.has(key) and not options(OPTION_LISTS[key]).has(value as String):
		return "'%s' is not a known option" % (value as String)
	return ""


func _category_errors() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	var minimums: Dictionary = _config_dict(CONFIG_MINIMUMS)
	for category: String in categories():
		var defaults: int = 0
		var count: int = 0
		for it: Dictionary in items:
			if str(it["category"]) != category:
				continue
			count += 1
			if unlock_of(str(it["id"]))["type"] == UNLOCK_DEFAULT:
				defaults += 1
		if defaults == 0:
			errors.append("category %s has no default item" % category)
		elif defaults > 1:
			errors.append("category %s has %d default items (exactly one allowed)" % [category, defaults])
		var minimum: int = CosmeticCatalog._to_int(minimums.get(category, 0), 0)
		if count < minimum:
			errors.append("category %s has %d items, needs at least %d" % [category, count, minimum])
	return errors


## Every difficulty tier needs its "badge_perfect_<tier>" badge: the reward
## engine grants exactly that id on the tier's first perfect run.
func _tier_badge_errors() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	for tier: String in options(CONFIG_TIERS):
		var badge_id: String = PERFECT_TIER_BADGE_PREFIX + tier
		if category_of(badge_id) != BADGE:
			errors.append("perfect tier '%s' has no badge %s" % [tier, badge_id])
	return errors


func _product_errors() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	var sold: Dictionary[String, String] = {}
	for p: Dictionary in products:
		var pid: String = str(p.get("id", ""))
		if not _is_valid_id(pid):
			errors.append("invalid product id '%s'" % pid)
		if str(p.get("type", "")) != PRODUCT_TYPE:
			errors.append("%s: product type must be %s" % [pid, PRODUCT_TYPE])
		errors.append_array(CosmeticCatalog._key_errors(pid, "name_key", p.get("name_key"), true))
		errors.append_array(CosmeticCatalog._key_errors(pid, "desc_key", p.get("desc_key"), false))
		for field: Variant in p.keys():
			if not PRODUCT_FIELDS.has(str(field)):
				errors.append("%s: unexpected field '%s' (products hold cosmetic ids only)" % [pid, str(field)])
		var list: Variant = p.get("items")
		if typeof(list) != TYPE_ARRAY or (list as Array).is_empty():
			errors.append("%s: items must be a non-empty array of cosmetic ids" % pid)
			continue
		for raw_id: Variant in list as Array:
			var item_id: String = str(raw_id)
			if sold.has(item_id):
				errors.append("%s: item '%s' is already sold by %s" % [pid, item_id, sold[item_id]])
			sold[item_id] = pid
			errors.append_array(_product_item_errors(pid, raw_id))
	return errors


func _product_item_errors(pid: String, raw_id: Variant) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if typeof(raw_id) != TYPE_STRING or not has_item(raw_id as String):
		errors.append("%s: unknown cosmetic id '%s'" % [pid, str(raw_id)])
		return errors
	var item_id: String = raw_id as String
	if str(_by_id[item_id].get("category", "")) == BADGE:
		errors.append("%s: badge '%s' cannot be sold" % [pid, item_id])
	if unlock_of(item_id)["type"] != UNLOCK_PREMIUM:
		errors.append("%s: item '%s' is not a premium item" % [pid, item_id])
	return errors


func _parse_field(category: String, field: String, kind: int, value: Variant) -> Variant:
	var key: String = "%s.%s" % [category, field]
	var result: Variant = null
	match kind:
		ParamKind.INT:
			var count: int = options(str(OPTION_LISTS.get(key, ""))).size()
			var n: int = CosmeticCatalog._to_int(value, 0)
			result = clampi(n, 0, count - 1) if count > 0 else maxi(n, 0)
		ParamKind.FLOAT:
			var numeric: bool = typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT
			var f: float = float(value) if numeric else FALLBACK_FLOAT
			var r: Vector2 = _range_for(key)
			result = clampf(f, r.x, r.y) if r != Vector2.ZERO else f
		ParamKind.BOOL:
			result = bool(value) if typeof(value) == TYPE_BOOL else false
		ParamKind.COLOR:
			result = CosmeticCatalog.parse_color(value)
		ParamKind.COLOR_LIST:
			result = CosmeticCatalog._parse_color_list(value)
		_:
			result = _parse_option(key, value)
	return result


func _parse_option(key: String, value: Variant) -> String:
	var allowed: PackedStringArray = options(str(OPTION_LISTS.get(key, "")))
	var text: String = value as String if typeof(value) == TYPE_STRING else ""
	if allowed.is_empty() or allowed.has(text):
		return text
	return allowed[0]


## [x, y] range for a float param, or Vector2.ZERO when unconstrained or the
## configured range is malformed (reported by [method validate]).
func _range_for(key: String) -> Vector2:
	var raw: Variant = _config_dict(CONFIG_RANGES).get(key)
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() != 2:
		return Vector2.ZERO
	var pair: Array = raw as Array
	for bound: Variant in pair:
		if typeof(bound) != TYPE_FLOAT and typeof(bound) != TYPE_INT:
			return Vector2.ZERO
	var r: Vector2 = Vector2(float(pair[0]), float(pair[1]))
	return r if r.x < r.y else Vector2.ZERO


## A top-level config object, or {} when it is missing or not an object.
func _config_dict(section: String) -> Dictionary:
	var raw: Variant = _config.get(section)
	return raw as Dictionary if typeof(raw) == TYPE_DICTIONARY else {}


## Problems with a translation key field ([param required] = must exist).
static func _key_errors(owner: String, field: String, value: Variant, required: bool) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if value == null and not required:
		return errors
	if typeof(value) != TYPE_STRING or not (value as String).begins_with(KEY_PREFIX):
		errors.append("%s: %s missing or not a %s* key" % [owner, field, KEY_PREFIX])
	return errors


static func _parse_color_list(value: Variant) -> Array[Color]:
	var out: Array[Color] = []
	if typeof(value) == TYPE_ARRAY:
		for raw: Variant in value as Array:
			if typeof(raw) == TYPE_STRING and CosmeticCatalog.is_hex_color(raw as String):
				out.append(Color.html(raw as String))
			if out.size() >= MAX_PARTICLE_COLORS:
				break
	if out.is_empty():
		out.append(FALLBACK_COLOR)
	return out


static func _color_list_problem(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return "must be a non-empty colour list"
	if (value as Array).size() > MAX_PARTICLE_COLORS:
		return "has more than %d colours" % MAX_PARTICLE_COLORS
	for raw: Variant in value as Array:
		if typeof(raw) != TYPE_STRING or not CosmeticCatalog.is_hex_color(raw as String):
			return "contains an invalid colour %s" % str(raw)
	return ""


static func _is_valid_id(id: String) -> bool:
	if id.is_empty():
		return false
	for ch: String in id:
		if not ID_CHARS.contains(ch):
			return false
	return true


## JSON numbers arrive as floats; accept integral values only.
static func _is_integral(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), roundf(float(value)))


static func _to_int(value: Variant, fallback: int) -> int:
	if CosmeticCatalog._is_integral(value):
		return int(value)
	return fallback
