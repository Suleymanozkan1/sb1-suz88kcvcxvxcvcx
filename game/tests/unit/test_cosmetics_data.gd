extends TestCase
## Shipped cosmetics data: store products are cosmetic-only and every
## player-visible string exists in English and Turkish.

const PRODUCTS_PATH: String = "res://data/store/products.json"
const EN_PATH: String = "res://data/i18n/parts/cosmetics.en.json"
const TR_PATH: String = "res://data/i18n/parts/cosmetics.tr.json"
## Anything that would make a product grant currency or gameplay power.
const FORBIDDEN_WORDS: PackedStringArray = [
	"coin",
	"gem",
	"xp",
	"currency",
	"booster",
	"boost",
	"powerup",
	"revive",
	"life",
	"lives",
	"energy",
	"skip",
	"shield",
	"slowmo",
]
const REQUIRED_PRODUCTS: PackedStringArray = ["pack_neon_pulse", "starter_cosmetic_bundle"]
const PRODUCT_ID_CHARS: String = "abcdefghijklmnopqrstuvwxyz0123456789_."
## Achievement definitions owned by the meta module (checked once merged).
const ACHIEVEMENTS_PATH: String = "res://data/achievements/achievements.json"
## 520 campaign levels x 3 stars.
const MAX_STARS: int = 1560
## With the shared XP curve (120 * level^1.25) and run XP (10 + 5 per star) a
## full three-star campaign lands around player level 12; 15 needs more play.
const MAX_PLAYER_LEVEL_TARGET: int = 15
const MAX_PERFECTS_TARGET: int = 520
## Typical cosmetic price band from the economy balance (coins).
const COIN_PRICE_RANGE: Vector2i = Vector2i(300, 1500)

var _catalog: CosmeticCatalog = null
var _en: Dictionary = {}
var _tr: Dictionary = {}


func before_each() -> void:
	_catalog = CosmeticCatalog.load_default()
	_en = JsonIO.read_dict(EN_PATH)
	_tr = JsonIO.read_dict(TR_PATH)


func test_products_contain_only_cosmetic_ids() -> void:
	var raw: Dictionary = JsonIO.read_dict(PRODUCTS_PATH)
	var products: Array = raw.get("products", []) as Array
	assert_ge(products.size(), 4, "several cosmetic packs")
	for entry: Variant in products:
		var p: Dictionary = entry as Dictionary
		var pid: String = str(p["id"])
		assert_eq(str(p["type"]), "non_consumable", "%s type" % pid)
		for key: Variant in p.keys():
			assert_has(CosmeticCatalog.PRODUCT_FIELDS, str(key), "%s field" % pid)
		var items: Array = p["items"] as Array
		assert_gt(items.size(), 0, "%s has items" % pid)
		for raw_id: Variant in items:
			var id: String = str(raw_id)
			assert_true(_catalog.has_item(id), "%s: %s is a cosmetic id" % [pid, id])
			var category: String = str(_catalog.item(id).get("category", ""))
			assert_has(CosmeticCatalog.REQUIRED_CATEGORIES, category, "%s: %s category" % [pid, id])
			assert_ne(category, CosmeticCatalog.BADGE, "%s sells a badge" % pid)
			assert_eq(str(_catalog.unlock_of(id)["type"]), "premium", "%s: %s premium" % [pid, id])
			assert_false(_looks_like_gameplay(id), "%s: %s looks like currency/gameplay" % [pid, id])


func test_required_products_present() -> void:
	var ids: PackedStringArray = PackedStringArray()
	for p: Dictionary in _catalog.products:
		ids.append(str(p["id"]))
	for required: String in REQUIRED_PRODUCTS:
		assert_has(ids, required)
	var theme_packs: int = 0
	for id: String in ids:
		if id.begins_with("theme_pack_"):
			theme_packs += 1
	assert_ge(theme_packs, 1, "at least one theme pack")


func test_product_ids_are_store_safe() -> void:
	for p: Dictionary in _catalog.products:
		var pid: String = str(p["id"])
		assert_le(pid.length(), 64, "%s length" % pid)
		for ch: String in pid:
			assert_true(PRODUCT_ID_CHARS.contains(ch), "%s char '%s'" % [pid, ch])
		assert_false(str(p.get("display_price_hint", "")).is_valid_float(), "%s hard-codes no price" % pid)


func test_every_item_and_product_name_translated() -> void:
	assert_false(_en.is_empty(), "english strings load")
	assert_false(_tr.is_empty(), "turkish strings load")
	var keys: PackedStringArray = PackedStringArray()
	for it: Dictionary in _catalog.items:
		keys.append(str(it["name_key"]))
		if it.has("desc_key"):
			keys.append(str(it["desc_key"]))
	for p: Dictionary in _catalog.products:
		keys.append(str(p["name_key"]))
		if p.has("desc_key"):
			keys.append(str(p["desc_key"]))
	for category: String in _catalog.categories():
		keys.append("cos.category.%s" % category)
	for rarity: String in _catalog.options("rarities"):
		keys.append("cos.rarity.%s" % rarity)
	for type: String in CosmeticCatalog.UNLOCK_TYPES:
		keys.append("cos.unlock.%s" % type)
	keys.append("cos.unlock.perfects_tier")
	for tier: String in _catalog.options("perfect_tiers"):
		keys.append("cos.tier.%s" % tier)
	for key: String in keys:
		assert_true(_en.has(key) and not str(_en[key]).is_empty(), "en missing %s" % key)
		assert_true(_tr.has(key) and not str(_tr[key]).is_empty(), "tr missing %s" % key)


func test_translation_files_match_and_are_really_translated() -> void:
	assert_eq(_en.size(), _tr.size(), "same number of keys")
	var differing: int = 0
	for key: Variant in _en:
		var k: String = str(key)
		assert_true(_tr.has(k), "tr has %s" % k)
		assert_true(k.begins_with("cos."), "%s uses the module prefix" % k)
		assert_true(_is_key_format(k), "%s key format" % k)
		if str(_en[k]) != str(_tr.get(k, "")):
			differing += 1
		for token: String in ["{value}", "{name}", "{price}", "{owned}", "{total}"]:
			if str(_en[k]).contains(token):
				assert_true(str(_tr.get(k, "")).contains(token), "%s keeps %s in Turkish" % [k, token])
	assert_gt(float(differing) / float(maxi(_en.size(), 1)), 0.9, "Turkish text is translated")


func test_turkish_uses_turkish_characters() -> void:
	var joined: String = " ".join(PackedStringArray(_tr.values()))
	for ch: String in ["ç", "ş", "ğ", "ı", "ö", "ü", "İ"]:
		assert_true(joined.contains(ch), "Turkish text contains %s" % ch)


func test_unlock_targets_are_reachable_and_prices_in_band() -> void:
	var limits: Dictionary = {
		"stars": MAX_STARS,
		"player_level": MAX_PLAYER_LEVEL_TARGET,
		"perfects": MAX_PERFECTS_TARGET,
	}
	for it: Dictionary in _catalog.items:
		var id: String = str(it["id"])
		var unlock: Dictionary = _catalog.unlock_of(id)
		var type: String = str(unlock["type"])
		if limits.has(type) and typeof(unlock["value"]) == TYPE_INT:
			assert_le(int(unlock["value"]), int(limits[type]), "%s %s target reachable" % [id, type])
		if type == "coins":
			var price: int = int(unlock["value"])
			assert_true(price >= COIN_PRICE_RANGE.x and price <= COIN_PRICE_RANGE.y, "%s price %d" % [id, price])


func test_achievement_ids_and_badges_match_meta_data() -> void:
	if not FileAccess.file_exists(ACHIEVEMENTS_PATH):
		assert_true(true, "meta achievements not merged into this tree yet")
		return
	var raw: Dictionary = JsonIO.read_dict(ACHIEVEMENTS_PATH)
	var achievement_ids: PackedStringArray = PackedStringArray()
	for entry: Variant in raw.get("achievements", []) as Array:
		var a: Dictionary = entry as Dictionary
		achievement_ids.append(str(a.get("id", "")))
		var reward: Dictionary = a.get("reward", {}) as Dictionary
		if reward.has("badge"):
			var badge: String = str(reward["badge"])
			assert_eq(
				_catalog.category_of(badge), "badge", "achievement %s rewards defined badge %s" % [a["id"], badge]
			)
	for it: Dictionary in _catalog.items:
		var unlock: Dictionary = _catalog.unlock_of(str(it["id"]))
		if str(unlock["type"]) == "achievement":
			assert_has(achievement_ids, str(unlock["value"]), "%s unlock achievement exists" % it["id"])


func _looks_like_gameplay(id: String) -> bool:
	for segment: String in id.to_lower().split("_"):
		for word: String in FORBIDDEN_WORDS:
			if segment == word or segment == word + "s":
				return true
	return false


func _is_key_format(key: String) -> bool:
	var regex: RegEx = RegEx.create_from_string("^[a-z0-9]+(_[a-z0-9]+)*(\\.[a-z0-9]+(_[a-z0-9]+)*)+$")
	return regex.search(key) != null
