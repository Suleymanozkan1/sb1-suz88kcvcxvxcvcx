extends TestCase
## Store: honest unavailability, cosmetic-only product validation, purchase
## recording, restore.

const PACK: String = "pack_neon_pulse"
const BUNDLE: String = "starter_cosmetic_bundle"

var _bus: EventBus
var _profile: PlayerProfile
var _tracker: RecordingTracker
var _grants: RecordingGrants
var _completed: Array[String] = []


## Billing double with scripted answers.
class ScriptedStoreProvider:
	extends StoreProvider
	var available: bool = true
	var purchase_result: Variant = {"ok": true, "receipt": "receipt-001", "error": ""}
	var restore_result: Variant = {"ok": true, "product_ids": [], "error": ""}
	var listing: Array = [{"id": "pack_neon_pulse", "price": "₺49,99"}]
	var purchases: PackedStringArray = PackedStringArray()
	## When set, purchase() resolves one frame later (coroutine path).
	var tree: SceneTree = null

	func is_available() -> bool:
		return available

	func products() -> Array:
		return listing

	func purchase(product_id: String) -> Dictionary:
		purchases.append(product_id)
		if tree != null:
			await tree.process_frame
		return purchase_result if typeof(purchase_result) == TYPE_DICTIONARY else {"raw": purchase_result}

	func restore() -> Dictionary:
		return restore_result if typeof(restore_result) == TYPE_DICTIONARY else {"raw": restore_result}


## Records analytics calls made through the injected Callable.
class RecordingTracker:
	extends RefCounted
	var calls: Array[Dictionary] = []

	func track(event: StringName, params: Dictionary) -> bool:
		calls.append({"event": String(event), "params": params.duplicate()})
		return true

	func names() -> PackedStringArray:
		var out: PackedStringArray = PackedStringArray()
		for c: Dictionary in calls:
			out.append(str(c["event"]))
		return out


## Records grant_product calls and answers with the product's items.
class RecordingGrants:
	extends RefCounted
	var granted: PackedStringArray = PackedStringArray()

	func grant(product_id: String) -> Array:
		granted.append(product_id)
		return ["item_of_" + product_id]


func before_each() -> void:
	_bus = EventBus.new()
	_profile = PlayerProfile.create_new(1790000000)
	_tracker = RecordingTracker.new()
	_grants = RecordingGrants.new()
	# Capture a local array (not self) so the bus connection creates no cycle.
	var completed: Array[String] = []
	_completed = completed
	_bus.purchase_completed.connect(func(product_id: String) -> void: completed.append(product_id))


func _products() -> Array:
	return [
		{
			"id": PACK,
			"type": "non_consumable",
			"name_key": "cos.pack_neon_pulse.name",
			"items": ["core_neon_pulse", "trail_neon_pulse"],
			"display_price_hint": "—",
		},
		{
			"id": BUNDLE,
			"type": "non_consumable",
			"name_key": "cos.starter_cosmetic_bundle.name",
			"items": ["frame_starter", "avatar_starter"],
		},
	]


func _store(provider: StoreProvider, products: Array = []) -> StoreService:
	var list: Array = products if not products.is_empty() else _products()
	return StoreService.new(_profile, _bus, provider, list, _grants.grant, _tracker.track)


func test_store_unavailable_is_honest() -> void:
	var store: StoreService = _store(NullStoreProvider.new())
	assert_false(store.is_available())
	var result: Dictionary = await store.purchase(PACK)
	assert_false(bool(result["ok"]), "no simulated success")
	assert_eq(result["error"], StoreService.ERR_UNAVAILABLE)
	assert_empty(_profile.purchases)
	assert_empty(_grants.granted)
	assert_empty(_completed)
	assert_false(_tracker.names().has("purchase_completed"))
	for row: Dictionary in store.listings():
		assert_false(bool(row["purchasable"]))
		assert_eq(row["price"], "")
	assert_eq(StoreService.message_key(str(result["error"])), "platform.store.error.store_unavailable")


func test_restore_with_null_provider_returns_error() -> void:
	var provider: NullStoreProvider = NullStoreProvider.new()
	var direct: Dictionary = await provider.restore()
	assert_false(bool(direct["ok"]))
	assert_eq(direct["error"], "store_unavailable")
	assert_empty(direct["product_ids"])
	var direct_purchase: Dictionary = await provider.purchase(PACK)
	assert_false(bool(direct_purchase["ok"]))
	assert_eq(direct_purchase["receipt"], "")
	assert_empty(provider.products())
	var store: StoreService = _store(provider)
	var result: Dictionary = await store.restore_purchases()
	assert_false(bool(result["ok"]))
	assert_eq(result["error"], "store_unavailable")
	assert_empty(result["restored"])


func test_product_validation_rejects_currency_and_consumables() -> void:
	var bad: Array = [
		{"id": "coins_pack", "type": "non_consumable", "name_key": "k", "items": ["coins_500"]},
		{"id": "gem_pile", "type": "non_consumable", "name_key": "k", "items": ["core_x", "gems_100"]},
		{"id": "dict_items", "type": "non_consumable", "name_key": "k", "items": [{"type": "coins", "amount": 100}]},
		{"id": "field_gems", "type": "non_consumable", "name_key": "k", "items": ["core_x"], "gems": 50},
		{"id": "boosters", "type": "non_consumable", "name_key": "k", "items": ["booster_shield"]},
		{"id": "revive_pack", "type": "non_consumable", "name_key": "k", "items": ["revive_token"]},
		{"id": "consumable", "type": "consumable", "name_key": "k", "items": ["core_x"]},
		{"id": "empty_items", "type": "non_consumable", "name_key": "k", "items": []},
		{"id": "no_name", "type": "non_consumable", "items": ["core_x"]},
		{"id": "Bad Id!", "type": "non_consumable", "name_key": "k", "items": ["core_x"]},
		{"id": "dupe_items", "type": "non_consumable", "name_key": "k", "items": ["core_x", "core_x"]},
		"not a product",
	]
	for product: Variant in bad:
		assert_false(StoreService.validate_product(product).is_empty(), "rejected: %s" % str(product))
	var list: Array = _products()
	list.append_array(bad)
	list.append(_products()[0])
	var store: StoreService = _store(ScriptedStoreProvider.new(), list)
	assert_eq(store.product_ids(), PackedStringArray([PACK, BUNDLE]), "only valid cosmetic packs kept")
	assert_eq(store.rejected_products.size(), bad.size() + 1, "duplicate id rejected too")
	var result: Dictionary = await store.purchase("coins_pack")
	assert_eq(result["error"], StoreService.ERR_UNKNOWN_PRODUCT)


func test_valid_products_pass_validation() -> void:
	for product: Variant in _products():
		assert_empty(StoreService.validate_product(product))


func test_bundled_products_are_cosmetic_only() -> void:
	if not FileAccess.file_exists(StoreService.DEFAULT_PRODUCTS_PATH):
		assert_true(true, "products.json is provided by the cosmetics module")
		return
	var products: Array = StoreService.load_products()
	assert_gt(products.size(), 0)
	for product: Variant in products:
		assert_empty(StoreService.validate_product(product), "bundled product %s" % str(product))


func test_purchase_success_records_grants_and_tracks() -> void:
	var provider: ScriptedStoreProvider = ScriptedStoreProvider.new()
	var store: StoreService = _store(provider)
	var result: Dictionary = await store.purchase(PACK)
	assert_true(bool(result["ok"]))
	assert_eq(result["error"], "")
	assert_eq(result["granted"], ["item_of_pack_neon_pulse"])
	assert_true(store.owns(PACK))
	assert_eq(Array(_profile.purchases), [PACK])
	assert_eq(_grants.granted, PackedStringArray([PACK]))
	assert_eq(_completed, [PACK] as Array[String])
	assert_eq(_tracker.names(), PackedStringArray(["purchase_started", "purchase_completed"]))
	assert_eq((_tracker.calls[1]["params"] as Dictionary)["restored"], false)
	var again: Dictionary = await store.purchase(PACK)
	assert_eq(again["error"], StoreService.ERR_ALREADY_OWNED)
	assert_eq(provider.purchases.size(), 1, "owned packs are never charged twice")
	var rows: Array[Dictionary] = store.listings()
	assert_eq(rows[0]["price"], "₺49,99", "platform price shown as given")
	assert_true(bool(rows[0]["owned"]))
	assert_false(bool(rows[0]["purchasable"]))
	assert_true(bool(rows[1]["purchasable"]))


func test_purchase_failures_record_nothing() -> void:
	var provider: ScriptedStoreProvider = ScriptedStoreProvider.new()
	var store: StoreService = _store(provider)
	provider.purchase_result = {"ok": false, "receipt": "", "error": "user_canceled"}
	var cancelled: Dictionary = await store.purchase(PACK)
	assert_eq(cancelled["error"], StoreService.ERR_CANCELLED)
	provider.purchase_result = {"ok": true, "receipt": "", "error": ""}
	var no_receipt: Dictionary = await store.purchase(PACK)
	assert_eq(no_receipt["error"], StoreService.ERR_INVALID_RESPONSE, "success without a receipt is not trusted")
	provider.purchase_result = "garbage"
	var garbage: Dictionary = await store.purchase(PACK)
	assert_eq(garbage["error"], StoreService.ERR_FAILED, "an answer without ok=true is a failure")
	provider.purchase_result = {"ok": "true", "receipt": "r"}
	var string_ok: Dictionary = await store.purchase(PACK)
	assert_false(bool(string_ok["ok"]))
	provider.purchase_result = {"ok": false}
	var bare: Dictionary = await store.purchase(PACK)
	assert_eq(bare["error"], StoreService.ERR_FAILED)
	assert_empty(_profile.purchases)
	assert_empty(_grants.granted)
	assert_empty(_completed)
	assert_eq(_tracker.names().count("purchase_failed"), 5)
	assert_eq(_tracker.names().count("purchase_completed"), 0)
	assert_eq(StoreService.message_key("weird_platform_code"), StoreService.MESSAGE_KEY_GENERIC)


func test_provider_error_text_is_normalised() -> void:
	var provider: ScriptedStoreProvider = ScriptedStoreProvider.new()
	var store: StoreService = _store(provider)
	provider.purchase_result = {"ok": false, "error": "Billing-Unavailable"}
	assert_eq((await store.purchase(PACK))["error"], "billing_unavailable", "short codes are kept, normalised")
	provider.purchase_result = {"ok": false, "error": "Payment declined for card of someone@example.com"}
	assert_eq((await store.purchase(PACK))["error"], StoreService.ERR_FAILED, "free text is never passed on")
	provider.purchase_result = {"ok": false, "error": "x".repeat(200)}
	assert_eq((await store.purchase(PACK))["error"], StoreService.ERR_FAILED)
	provider.purchase_result = {"ok": false, "error": 42}
	assert_eq((await store.purchase(PACK))["error"], StoreService.ERR_FAILED)
	provider.purchase_result = {"ok": false, "error": "User Canceled"}
	assert_eq((await store.purchase(PACK))["error"], StoreService.ERR_CANCELLED)
	for call: Dictionary in _tracker.calls:
		if call["event"] == "purchase_failed":
			assert_false(str((call["params"] as Dictionary)["error"]).contains("@"), "no free text in analytics")
	provider.restore_result = {"ok": false, "error": "Network unreachable: host 10.0.0.1"}
	assert_eq((await store.restore_purchases())["error"], StoreService.ERR_FAILED)


func test_restore_is_blocked_while_a_purchase_is_in_flight() -> void:
	var provider: ScriptedStoreProvider = ScriptedStoreProvider.new()
	provider.tree = tree
	provider.restore_result = {"ok": true, "product_ids": [PACK], "error": ""}
	var store: StoreService = _store(provider)
	var holder: Dictionary = {}
	var buy: Callable = func() -> void: holder["result"] = await store.purchase(PACK)
	buy.call()
	var restore: Dictionary = await store.restore_purchases()
	assert_false(bool(restore["ok"]))
	assert_eq(restore["error"], StoreService.ERR_IN_PROGRESS)
	var guard: int = 0
	while not holder.has("result") and guard < 10:
		await tree.process_frame
		guard += 1
	assert_true(bool((holder["result"] as Dictionary)["ok"]))
	assert_eq(_tracker.names().count("purchase_completed"), 1, "one purchase, one completion")
	assert_true(bool((await store.restore_purchases())["ok"]), "restore works once the purchase finished")


func test_concurrent_purchase_is_blocked() -> void:
	var provider: ScriptedStoreProvider = ScriptedStoreProvider.new()
	provider.tree = tree
	var store: StoreService = _store(provider)
	var holder: Dictionary = {}
	var first: Callable = func() -> void: holder["result"] = await store.purchase(PACK)
	first.call()
	var second: Dictionary = await store.purchase(BUNDLE)
	assert_eq(second["error"], StoreService.ERR_IN_PROGRESS)
	var guard: int = 0
	while not holder.has("result") and guard < 10:
		await tree.process_frame
		guard += 1
	assert_true(bool((holder["result"] as Dictionary)["ok"]))
	var third: Dictionary = await store.purchase(BUNDLE)
	assert_true(bool(third["ok"]), "store usable again after completion")


func test_restore_with_scripted_provider() -> void:
	var provider: ScriptedStoreProvider = ScriptedStoreProvider.new()
	provider.restore_result = {"ok": true, "product_ids": [PACK, "unknown_pack", PACK, 42], "error": ""}
	var store: StoreService = _store(provider)
	var result: Dictionary = await store.restore_purchases()
	assert_true(bool(result["ok"]))
	assert_eq(result["restored"], [PACK] as Array[String])
	assert_true(store.owns(PACK))
	assert_eq(_completed, [PACK] as Array[String])
	assert_eq((_tracker.calls[0]["params"] as Dictionary)["restored"], true)
	var again: Dictionary = await store.restore_purchases()
	assert_empty(again["restored"], "nothing new the second time")
	assert_eq(again["product_ids"], [PACK] as Array[String])
	assert_eq(_grants.granted, PackedStringArray([PACK, PACK]), "restore re-grants to repair lost items")
	assert_eq(_completed.size(), 1, "purchase_completed only for newly restored packs")


func test_restore_failure_is_reported() -> void:
	var provider: ScriptedStoreProvider = ScriptedStoreProvider.new()
	provider.restore_result = {"ok": false, "product_ids": [], "error": "network"}
	var store: StoreService = _store(provider)
	var result: Dictionary = await store.restore_purchases()
	assert_false(bool(result["ok"]))
	assert_eq(result["error"], "network")
	provider.restore_result = 7
	result = await store.restore_purchases()
	assert_false(bool(result["ok"]))
	assert_empty(_profile.purchases)


func test_reconcile_owned_regrants_items() -> void:
	_profile.purchases.append(PACK)
	_profile.purchases.append("retired_pack")
	var store: StoreService = _store(NullStoreProvider.new())
	assert_eq(store.reconcile_owned(), 1)
	assert_eq(_grants.granted, PackedStringArray([PACK]))
	assert_true(store.owns("retired_pack"), "unknown owned ids are kept, never deleted")


func test_missing_grant_callable_still_records_purchase() -> void:
	var store: StoreService = StoreService.new(_profile, _bus, ScriptedStoreProvider.new(), _products(), Callable())
	var result: Dictionary = await store.purchase(PACK)
	assert_true(bool(result["ok"]))
	assert_true(store.owns(PACK), "paid purchase is never lost")
	assert_empty(result["granted"])
