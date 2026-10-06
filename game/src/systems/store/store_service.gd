class_name StoreService
extends RefCounted
## Cosmetic-only in-app purchases.
##
## Products come from data/store/products.json (owned by the cosmetics
## module). Only non-consumable packs whose items are cosmetic ids are
## accepted: anything granting currency, boosters, revives or other gameplay
## power is rejected at load time. Purchases are recorded in
## profile.purchases (restorable) and the items are granted through the
## injected grant callable. Without a billing provider every call returns a
## clear "store_unavailable" error — never a simulated success.

const DEFAULT_PRODUCTS_PATH: String = "res://data/store/products.json"
const TYPE_NON_CONSUMABLE: String = "non_consumable"
const ERR_UNAVAILABLE: String = "store_unavailable"
const ERR_UNKNOWN_PRODUCT: String = "unknown_product"
const ERR_ALREADY_OWNED: String = "already_owned"
const ERR_IN_PROGRESS: String = "purchase_in_progress"
const ERR_INVALID_RESPONSE: String = "invalid_response"
const ERR_FAILED: String = "purchase_failed"
const ERR_CANCELLED: String = "cancelled"
const KNOWN_ERRORS: PackedStringArray = [
	"store_unavailable",
	"unknown_product",
	"already_owned",
	"purchase_in_progress",
	"invalid_response",
	"purchase_failed",
	"cancelled",
]
const CANCEL_ALIASES: PackedStringArray = ["cancelled", "canceled", "user_cancelled", "user_canceled"]
const MESSAGE_KEY_PREFIX: String = "platform.store.error."
const MESSAGE_KEY_GENERIC: String = "platform.store.error.generic"
const PRODUCT_ID_CHARS: String = "abcdefghijklmnopqrstuvwxyz0123456789_."
const MAX_PRODUCT_ID_LENGTH: int = 64
## Provider error strings are untrusted free text: only short lower_snake
## codes are passed on (to the UI and analytics), anything else is generic.
const ERROR_CODE_CHARS: String = "abcdefghijklmnopqrstuvwxyz0123456789_"
const MAX_ERROR_CODE_LENGTH: int = 40
## An item id whose first segment is one of these would grant currency or
## gameplay power; such products are rejected.
const FORBIDDEN_ITEM_PREFIXES: PackedStringArray = [
	"coin",
	"coins",
	"gem",
	"gems",
	"xp",
	"currency",
	"cash",
	"booster",
	"boosters",
	"boost",
	"powerup",
	"revive",
	"revives",
	"life",
	"lives",
	"energy",
	"skip",
	"stars",
]
## Product fields that would grant currency or consumables directly.
const FORBIDDEN_PRODUCT_KEYS: PackedStringArray = ["coins", "gems", "xp", "currency", "boosters", "consumables"]
const EVENT_STARTED: StringName = &"purchase_started"
const EVENT_COMPLETED: StringName = &"purchase_completed"
const EVENT_FAILED: StringName = &"purchase_failed"

## Product ids that failed validation (diagnostics).
var rejected_products: PackedStringArray = PackedStringArray()
var _profile: PlayerProfile = null
var _bus: EventBus = null
var _provider: StoreProvider = null
var _grant: Callable = Callable()
var _track: Callable = Callable()
## product id -> validated product dictionary
var _catalog: Dictionary[String, Dictionary] = {}
var _order: PackedStringArray = PackedStringArray()
var _busy: bool = false


## [param products] is the "products" array of products.json.
## [param grant_product] is (product_id: String) -> Variant (e.g.
## CosmeticService.grant_from_product); [param analytics_track] is
## (event: StringName, params: Dictionary) -> bool.
func _init(
	profile: PlayerProfile,
	bus: EventBus,
	provider: StoreProvider,
	products: Array,
	grant_product: Callable,
	analytics_track: Callable = Callable()
) -> void:
	_profile = profile if profile != null else PlayerProfile.new()
	_bus = bus
	_provider = provider if provider != null else NullStoreProvider.new()
	_grant = grant_product
	_track = analytics_track
	for raw: Variant in products:
		_add_product(raw)


## Reads the "products" array of products.json ([] when missing/invalid).
static func load_products(path: String = DEFAULT_PRODUCTS_PATH) -> Array:
	var raw: Variant = JsonIO.read_dict(path).get("products", [])
	if typeof(raw) != TYPE_ARRAY:
		GameLog.error("store", "%s: products must be an array" % path)
		return []
	return raw as Array


## Validation errors for one product definition (empty when valid).
static func validate_product(product: Variant) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if typeof(product) != TYPE_DICTIONARY:
		errors.append("product must be an object")
		return errors
	var p: Dictionary = product as Dictionary
	var id: String = str(p.get("id", ""))
	if not StoreService._is_valid_product_id(id):
		errors.append("invalid product id '%s'" % id)
	if str(p.get("type", "")) != TYPE_NON_CONSUMABLE:
		errors.append("%s: type must be non_consumable" % id)
	if typeof(p.get("name_key")) != TYPE_STRING or str(p["name_key"]).is_empty():
		errors.append("%s: name_key missing" % id)
	for key: String in FORBIDDEN_PRODUCT_KEYS:
		if p.has(key):
			errors.append("%s: field '%s' would grant currency or consumables" % [id, key])
	var items: Variant = p.get("items")
	if typeof(items) != TYPE_ARRAY or (items as Array).is_empty():
		errors.append("%s: items must be a non-empty array of cosmetic ids" % id)
		return errors
	var seen: PackedStringArray = PackedStringArray()
	for item: Variant in items as Array:
		errors.append_array(StoreService._item_errors(id, item, seen))
	return errors


## True when the platform store can take purchases now.
func is_available() -> bool:
	return _provider.is_available()


## Valid product ids in catalog order.
func product_ids() -> PackedStringArray:
	return _order.duplicate()


## The validated product definition ({} when unknown).
func product(product_id: String) -> Dictionary:
	return (_catalog.get(product_id, {}) as Dictionary).duplicate(true)


## True when the player owns [param product_id].
func owns(product_id: String) -> bool:
	return _profile.purchases.has(product_id)


## Shop rows: {"id", "name_key", "items", "owned", "price", "purchasable"}.
## "price" is the platform's localized text ("" when the store is
## unavailable); "purchasable" is false when unavailable or already owned.
func listings() -> Array[Dictionary]:
	var prices: Dictionary[String, String] = {}
	var available: bool = _provider.is_available()
	if available:
		for raw: Variant in _provider.products():
			if typeof(raw) == TYPE_DICTIONARY:
				prices[str((raw as Dictionary).get("id", ""))] = str((raw as Dictionary).get("price", ""))
	var out: Array[Dictionary] = []
	for id: String in _order:
		var p: Dictionary = _catalog[id]
		var owned: bool = owns(id)
		(
			out
			. append(
				{
					"id": id,
					"name_key": p["name_key"],
					"items": (p["items"] as Array).duplicate(),
					"owned": owned,
					"price": str(prices.get(id, "")),
					"purchasable": available and not owned,
				}
			)
		)
	return out


## Buys [param product_id]. Returns {"ok", "error", "product_id", "granted"}.
## Coroutine: always await it.
func purchase(product_id: String) -> Dictionary:
	var error: String = _precheck(product_id)
	if not error.is_empty():
		return _result(false, error, product_id, [])
	_busy = true
	_track_event(EVENT_STARTED, {"product_id": product_id})
	var raw: Variant = await _provider.purchase(product_id)
	_busy = false
	error = StoreService._purchase_error(raw)
	if not error.is_empty():
		_track_event(EVENT_FAILED, {"product_id": product_id, "error": error})
		return _result(false, error, product_id, [])
	var granted: Array = _record_ownership(product_id)
	_track_event(EVENT_COMPLETED, {"product_id": product_id, "restored": false})
	return _result(true, "", product_id, granted)


## Restores previously bought packs. Returns {"ok", "error", "restored"
## (newly restored ids), "product_ids" (all known owned ids reported)}.
## Coroutine: always await it.
func restore_purchases() -> Dictionary:
	if not _provider.is_available():
		return {"ok": false, "error": ERR_UNAVAILABLE, "restored": [], "product_ids": []}
	if _busy:
		# A purchase or restore is already talking to the store.
		return {"ok": false, "error": ERR_IN_PROGRESS, "restored": [], "product_ids": []}
	_busy = true
	var raw: Variant = await _provider.restore()
	_busy = false
	if typeof(raw) != TYPE_DICTIONARY:
		return {"ok": false, "error": ERR_INVALID_RESPONSE, "restored": [], "product_ids": []}
	var r: Dictionary = raw as Dictionary
	if not (typeof(r.get("ok")) == TYPE_BOOL and bool(r["ok"])):
		var err: String = StoreService._error_code(r.get("error"))
		return {"ok": false, "error": err, "restored": [], "product_ids": []}
	var restored: Array[String] = []
	var reported: Array[String] = []
	var raw_ids: Variant = r.get("product_ids", [])
	var ids: Array = raw_ids as Array if typeof(raw_ids) == TYPE_ARRAY else []
	for raw_id: Variant in ids:
		var id: String = str(raw_id)
		if not _catalog.has(id):
			GameLog.warn("store", "restore reported unknown product '%s'; ignored" % id)
			continue
		if reported.has(id):
			continue
		reported.append(id)
		var was_owned: bool = owns(id)
		_record_ownership(id)
		if not was_owned:
			restored.append(id)
			_track_event(EVENT_COMPLETED, {"product_id": id, "restored": true})
	return {"ok": true, "error": "", "restored": restored, "product_ids": reported}


## Re-grants the items of every owned product (repairs cosmetics lost from a
## damaged save while the purchase list survived). Returns products processed.
func reconcile_owned() -> int:
	var count: int = 0
	for id: String in _profile.purchases:
		if _catalog.has(id):
			_call_grant(id)
			count += 1
	return count


## Translation key for a purchase/restore error code.
static func message_key(error: String) -> String:
	return MESSAGE_KEY_PREFIX + error if KNOWN_ERRORS.has(error) else MESSAGE_KEY_GENERIC


func _add_product(raw: Variant) -> void:
	var errors: PackedStringArray = StoreService.validate_product(raw)
	var id: String = str((raw as Dictionary).get("id", "")) if typeof(raw) == TYPE_DICTIONARY else ""
	if errors.is_empty() and _catalog.has(id):
		errors.append("duplicate product id '%s'" % id)
	if not errors.is_empty():
		rejected_products.append(id)
		for e: String in errors:
			GameLog.error("store", "product rejected: %s" % e)
		return
	_catalog[id] = (raw as Dictionary).duplicate(true)
	_order.append(id)


func _precheck(product_id: String) -> String:
	var error: String = ""
	if not _catalog.has(product_id):
		error = ERR_UNKNOWN_PRODUCT
	elif owns(product_id):
		error = ERR_ALREADY_OWNED
	elif _busy:
		error = ERR_IN_PROGRESS
	elif not _provider.is_available():
		error = ERR_UNAVAILABLE
	return error


## Records ownership (idempotent), grants the items and announces it.
func _record_ownership(product_id: String) -> Array:
	var is_new: bool = not _profile.purchases.has(product_id)
	if is_new:
		_profile.purchases.append(product_id)
	var granted: Array = _call_grant(product_id)
	if is_new and _bus != null:
		_bus.purchase_completed.emit(product_id)
	return granted


func _call_grant(product_id: String) -> Array:
	if not _grant.is_valid():
		GameLog.error("store", "no grant callable; %s recorded and will be granted on restore" % product_id)
		return []
	var granted: Variant = _grant.call(product_id)
	return (granted as Array).duplicate() if typeof(granted) == TYPE_ARRAY else []


func _track_event(event: StringName, params: Dictionary) -> void:
	if _track.is_valid():
		_track.call(event, params)


func _result(ok: bool, error: String, product_id: String, granted: Array) -> Dictionary:
	return {"ok": ok, "error": error, "product_id": product_id, "granted": granted}


## "" when the provider response is a genuine success, else an error code.
static func _purchase_error(raw: Variant) -> String:
	if typeof(raw) != TYPE_DICTIONARY:
		return ERR_INVALID_RESPONSE
	var r: Dictionary = raw as Dictionary
	var ok: bool = typeof(r.get("ok")) == TYPE_BOOL and bool(r["ok"])
	if not ok:
		return StoreService._error_code(r.get("error"))
	var receipt: Variant = r.get("receipt", "")
	if typeof(receipt) != TYPE_STRING or (receipt as String).strip_edges().is_empty():
		return ERR_INVALID_RESPONSE
	return ""


## Normalises a provider error: cancel spellings -> "cancelled"; short
## lower_snake codes kept; empty, long or free-text values -> "purchase_failed".
static func _error_code(raw: Variant) -> String:
	if typeof(raw) != TYPE_STRING and typeof(raw) != TYPE_STRING_NAME:
		return ERR_FAILED
	var code: String = str(raw).strip_edges().to_lower().replace("-", "_").replace(" ", "_")
	if CANCEL_ALIASES.has(code):
		return ERR_CANCELLED
	if code.is_empty() or code.length() > MAX_ERROR_CODE_LENGTH:
		return ERR_FAILED
	for i: int in code.length():
		if not ERROR_CODE_CHARS.contains(code[i]):
			return ERR_FAILED
	return code


static func _is_valid_product_id(id: String) -> bool:
	if id.is_empty() or id.length() > MAX_PRODUCT_ID_LENGTH:
		return false
	for i: int in id.length():
		if not PRODUCT_ID_CHARS.contains(id[i]):
			return false
	return true


static func _item_errors(product_id: String, item: Variant, seen: PackedStringArray) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if typeof(item) != TYPE_STRING or (item as String).strip_edges().is_empty():
		errors.append("%s: item %s is not a cosmetic id" % [product_id, str(item)])
		return errors
	var item_id: String = item as String
	var first: String = item_id.to_lower().replace(".", "_").replace(":", "_").replace("-", "_").get_slice("_", 0)
	if FORBIDDEN_ITEM_PREFIXES.has(first):
		errors.append("%s: item '%s' grants currency or gameplay power" % [product_id, item_id])
	if seen.has(item_id):
		errors.append("%s: duplicate item '%s'" % [product_id, item_id])
	seen.append(item_id)
	return errors
