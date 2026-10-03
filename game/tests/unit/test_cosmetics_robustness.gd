extends TestCase
## Hostile or malformed cosmetics data: validation keeps reporting (never
## aborts) and the service never sells or grants anything it should not.

const COSMETICS_PATH: String = "res://data/cosmetics/cosmetics.json"
const PRODUCTS_PATH: String = "res://data/store/products.json"

var _data: Dictionary = {}
var _products: Dictionary = {}


## Test double: records spend calls; always solvent.
class RecordingWallet:
	extends RefCounted

	var spent: Array[String] = []

	func can_afford(_currency: StringName, _amount: int) -> bool:
		return true

	func spend(currency: StringName, amount: int, _reason: String) -> bool:
		spent.append("%s:%d" % [currency, amount])
		return true


func before_each() -> void:
	_data = JsonIO.read_dict(COSMETICS_PATH)
	_products = JsonIO.read_dict(PRODUCTS_PATH)


func test_hex_colour_rejects_signs_spaces_and_garbage() -> void:
	for bad: String in ["#+12345", "#-1234567", "# 12345", "#12345g", "#-fffff", "#ff00ff+"]:
		assert_false(CosmeticCatalog.is_hex_color(bad), "'%s' rejected" % bad)
		assert_eq(CosmeticCatalog.parse_color(bad, Color.RED), Color.RED, "'%s' falls back" % bad)
	assert_true(CosmeticCatalog.is_hex_color("#A1b2C3ff"), "mixed case with alpha")


func test_signed_hex_param_is_a_validation_error() -> void:
	_set_param("core_fire", "rim", "#+12345")
	var c: CosmeticCatalog = CosmeticCatalog.from_data(_data, _products)
	_expect_error(c, "core_fire: param 'rim' must be a #rrggbb colour")
	assert_eq(c.typed_params("core_fire")["rim"], CosmeticCatalog.FALLBACK_COLOR, "parsed to the fallback")


func test_malformed_config_sections_are_reported_not_fatal() -> void:
	_data["schema_version"] = [1]
	_data["ranges"] = "wide"
	_data["min_per_category"] = [14, 10]
	var c: CosmeticCatalog = CosmeticCatalog.from_data(_data, _products)
	var errors: PackedStringArray = c.validate()
	_expect_in(errors, "unsupported cosmetics schema_version")
	_expect_in(errors, "'ranges' must be an object")
	_expect_in(errors, "'min_per_category' must be an object")
	var core: Dictionary = c.typed_params("core_fire")
	assert_eq(typeof(core["anim_speed"]), TYPE_FLOAT, "params still parse without ranges")
	assert_eq(typeof(core["rim"]), TYPE_COLOR)


func test_malformed_range_pairs_are_reported_and_ignored() -> void:
	_data["ranges"] = {"core_skin.anim_speed": ["slow", 3.0], "effect.shockwave": [2.0, 1.0]}
	_set_param("core_fire", "anim_speed", 9.0)
	var c: CosmeticCatalog = CosmeticCatalog.from_data(_data, _products)
	_expect_error(c, "range 'core_skin.anim_speed' must be [min, max]")
	_expect_error(c, "range 'effect.shockwave' must be [min, max]")
	assert_near(float(c.typed_params("core_fire")["anim_speed"]), 9.0, 0.001, "broken range does not clamp")


func test_tier_perfects_unlock_only_on_the_matching_badge() -> void:
	var items: Array = _data["items"] as Array
	items.append(_item("theme_tier", "theme", {"type": "perfects", "value": "expert"}, "theme_mono"))
	items.append(_item("badge_expert_two", "badge", {"type": "perfects", "value": "expert"}, "badge_newcomer"))
	var c: CosmeticCatalog = CosmeticCatalog.from_data(_data, _products)
	_expect_error(c, "theme_tier: a tier perfects unlock is only granted to badge_perfect_expert")
	_expect_error(c, "badge_expert_two: a tier perfects unlock is only granted to badge_perfect_expert")


func test_missing_tier_badge_is_reported() -> void:
	(_data["perfect_tiers"] as Array).append("zen")
	_expect_error(CosmeticCatalog.from_data(_data, _products), "perfect tier 'zen' has no badge badge_perfect_zen")


func test_bad_desc_key_is_reported() -> void:
	_find("core_fire")["desc_key"] = 42
	(((_products["products"] as Array)[0]) as Dictionary)["desc_key"] = "store.pack.desc"
	var c: CosmeticCatalog = CosmeticCatalog.from_data(_data, _products)
	_expect_error(c, "core_fire: desc_key missing or not a cos.* key")
	_expect_error(c, "pack_neon_pulse: desc_key missing or not a cos.* key")


func test_priced_badge_and_text_price_are_never_sold() -> void:
	var items: Array = _data["items"] as Array
	items.append(_item("badge_for_sale", "badge", {"type": "coins", "value": 10}, "badge_newcomer"))
	items.append(_item("theme_text_price", "theme", {"type": "coins", "value": "400"}, "theme_mono"))
	var c: CosmeticCatalog = CosmeticCatalog.from_data(_data, _products)
	var wallet: RecordingWallet = RecordingWallet.new()
	var s: CosmeticService = CosmeticService.new(PlayerProfile.new(), EventBus.new(), c, wallet, Callable())
	for id: String in ["badge_for_sale", "theme_text_price"]:
		assert_false(s.purchase(id), "%s not purchasable" % id)
		assert_false(bool(s.unlock_status(id)["can_unlock_now"]), "%s not unlockable now" % id)
		assert_true((s.unlock_status(id)["price"] as Dictionary).is_empty(), "%s shows no price" % id)
		for row: Dictionary in s.shop_items():
			assert_ne(str(row["id"]), id, "%s not listed in the shop" % id)
	assert_empty(wallet.spent, "nothing charged")


func test_grant_from_product_ignores_non_string_entries() -> void:
	(_data["items"] as Array).append(_item("7", "theme", {"type": "premium"}, "theme_mono"))
	var list: Array = ((_products["products"] as Array)[0] as Dictionary)["items"] as Array
	list.append(7)
	list.append(["core_fire"])
	var c: CosmeticCatalog = CosmeticCatalog.from_data(_data, _products)
	var s: CosmeticService = CosmeticService.new(PlayerProfile.new(), null, c, null, Callable())
	var granted: Array[String] = s.grant_from_product("pack_neon_pulse")
	assert_eq(granted, ["core_neon_pulse", "trail_neon_pulse", "particle_neon_pulse", "frame_neon_pulse"])
	assert_false(s.owns("7"), "numeric entry is not an id")
	assert_false(s.owns("core_fire"), "nested array is not an id")


func _find(id: String) -> Dictionary:
	for raw: Variant in _data["items"] as Array:
		if str((raw as Dictionary).get("id", "")) == id:
			return raw as Dictionary
	return {}


func _set_param(id: String, field: String, value: Variant) -> void:
	(_find(id)["params"] as Dictionary)[field] = value


## A new item with the params of an existing shipped item of the same category.
func _item(id: String, category: String, unlock: Dictionary, params_from: String) -> Dictionary:
	return {
		"id": id,
		"category": category,
		"name_key": "cos.%s.name" % id,
		"rarity": "common",
		"unlock": unlock,
		"params": (_find(params_from)["params"] as Dictionary).duplicate(true),
	}


func _expect_error(c: CosmeticCatalog, fragment: String) -> void:
	_expect_in(c.validate(), fragment)


func _expect_in(errors: PackedStringArray, fragment: String) -> void:
	for e: String in errors:
		if e.contains(fragment):
			assert_true(true)
			return
	fail("expected an error containing '%s' in %s" % [fragment, str(errors)])
