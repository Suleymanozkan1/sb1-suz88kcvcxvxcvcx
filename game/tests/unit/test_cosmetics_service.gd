extends TestCase
## CosmeticService: defaults, ownership, equipping, purchases and store grants.

var _profile: PlayerProfile = null
var _bus: EventBus = null
var _catalog: CosmeticCatalog = null
var _economy: InMemoryEconomy = null
var _service: CosmeticService = null
var _unlocked: Array[String] = []
var _equipped: Array[String] = []


## Test double: a tiny wallet with the EconomyService spending API.
class InMemoryEconomy:
	extends RefCounted

	var balances: Dictionary = {&"coins": 0, &"gems": 0}
	var reasons: Array[String] = []

	func can_afford(currency: StringName, amount: int) -> bool:
		return balances.has(currency) and amount > 0 and int(balances[currency]) >= amount

	func spend(currency: StringName, amount: int, reason: String) -> bool:
		if not can_afford(currency, amount):
			return false
		balances[currency] = int(balances[currency]) - amount
		reasons.append(reason)
		return true

	func balance(currency: StringName) -> int:
		return int(balances.get(currency, 0))


func before_each() -> void:
	_profile = PlayerProfile.new()
	_bus = EventBus.new()
	_catalog = CosmeticCatalog.load_default()
	_economy = InMemoryEconomy.new()
	_service = CosmeticService.new(_profile, _bus, _catalog, _economy, _no_progress)
	_unlocked = []
	_equipped = []
	_bus.cosmetic_unlocked.connect(_on_unlocked)
	_bus.cosmetic_equipped.connect(_on_equipped)


func test_defaults_owned_and_equipped_on_new_profile() -> void:
	assert_true(_service.ensure_defaults(), "new profile changed")
	for category: String in _catalog.categories():
		var default_id: String = _catalog.default_for(category)
		assert_has(_profile.cosmetics_owned, default_id, "%s default owned" % category)
		assert_eq(str(_profile.cosmetics_equipped[category]), default_id, "%s default equipped" % category)
		assert_eq(_service.equipped(category), default_id)
	assert_false(_service.ensure_defaults(), "second call is a no-op")
	assert_empty(_unlocked, "defaults are not announced as unlocks")


func test_ensure_defaults_repairs_bad_equipped_entries() -> void:
	_profile.cosmetics_equipped = {
		"core_skin": "core_inferno",  # premium, not owned
		"trail": "core_fire",  # wrong category
		"theme": "does_not_exist",
		"hats": "top_hat",  # unknown category
	}
	_profile.cosmetics_owned = ["core_fire", "legacy_item_from_newer_version"]
	assert_true(_service.ensure_defaults())
	assert_eq(_service.equipped("core_skin"), "core_plasma")
	assert_eq(_service.equipped("trail"), "trail_classic")
	assert_eq(_service.equipped("theme"), "theme_neon")
	assert_false(_profile.cosmetics_equipped.has("hats"), "unknown category dropped")
	assert_has(_profile.cosmetics_owned, "legacy_item_from_newer_version", "unknown owned ids kept")
	assert_eq(_service.equipped("hats"), "", "unknown category has nothing equipped")


func test_defaults_count_as_owned_before_ensure() -> void:
	assert_true(_service.owns("core_plasma"), "default owned implicitly")
	assert_eq(_service.equipped("core_skin"), "core_plasma", "default equipped implicitly")
	assert_false(_service.grant("core_plasma"), "granting a default is not new")
	assert_false(_service.owns("core_fire"))
	assert_false(_service.owns("no_such_item"))


func test_purchase_with_coins_deducts_and_grants() -> void:
	_economy.balances[&"coins"] = 1000
	assert_true(_service.purchase("core_fire"), "purchase succeeds")
	assert_eq(_economy.balance(&"coins"), 600, "400 coins spent")
	assert_true(_service.owns("core_fire"))
	assert_eq(_unlocked, ["core_fire"], "unlock announced")
	assert_eq(_economy.reasons, ["cosmetic:core_fire"], "ledger reason")
	assert_false(_service.purchase("core_fire"), "cannot buy twice")
	assert_eq(_economy.balance(&"coins"), 600, "no double charge")


func test_purchase_with_gems() -> void:
	_economy.balances[&"gems"] = 50
	assert_true(_service.purchase("core_nebula"))
	assert_eq(_economy.balance(&"gems"), 10, "40 gems spent")
	assert_true(_service.owns("core_nebula"))


func test_purchase_fails_without_funds() -> void:
	_economy.balances[&"coins"] = 399
	assert_false(_service.purchase("core_fire"))
	assert_eq(_economy.balance(&"coins"), 399, "nothing spent")
	assert_false(_service.owns("core_fire"))
	assert_empty(_unlocked)


func test_cannot_buy_premium_badges_or_earned_items() -> void:
	_economy.balances[&"coins"] = 1000000
	_economy.balances[&"gems"] = 1000000
	for id: String in ["core_inferno", "badge_newcomer", "badge_boss_master", "badge_perfect_early"]:
		assert_false(_service.purchase(id), "%s not purchasable" % id)
	for id2: String in ["core_shadow", "core_void", "core_electric", "core_solar"]:
		assert_false(_service.purchase(id2), "%s earned, not bought" % id2)
	assert_false(_service.purchase("no_such_item"))
	assert_eq(_economy.balance(&"coins"), 1000000, "no coins spent")
	assert_eq(_economy.balance(&"gems"), 1000000, "no gems spent")
	assert_empty(_economy.reasons)


func test_purchase_without_economy_is_safe() -> void:
	var s: CosmeticService = CosmeticService.new(_profile, _bus, _catalog, null, Callable())
	assert_false(s.purchase("core_fire"), "no economy, no purchase")
	var unrelated: CosmeticService = CosmeticService.new(_profile, _bus, _catalog, RefCounted.new(), Callable())
	assert_false(unrelated.purchase("core_fire"), "economy without API")
	assert_false(_profile.cosmetics_owned.has("core_fire"))


func test_cannot_equip_unowned() -> void:
	_service.ensure_defaults()
	assert_false(_service.equip("core_fire"), "not owned")
	assert_false(_service.equip("no_such_item"), "unknown")
	assert_eq(_service.equipped("core_skin"), "core_plasma")
	assert_empty(_equipped, "no equip signal")


func test_equip_owned_item_emits_signal() -> void:
	_service.ensure_defaults()
	assert_true(_service.grant("trail_flame"))
	assert_true(_service.equip("trail_flame"))
	assert_eq(_service.equipped("trail"), "trail_flame")
	assert_eq(str(_profile.cosmetics_equipped["trail"]), "trail_flame", "persisted in profile slice")
	assert_eq(_equipped, ["trail=trail_flame"])
	assert_true(_service.equip("trail_flame"), "re-equipping is fine")
	assert_eq(_equipped.size(), 1, "no duplicate signal")
	assert_true(_service.equip("trail_classic"), "defaults can be re-equipped")
	assert_eq(_service.equipped("trail"), "trail_classic")


func test_grant_duplicate_returns_false() -> void:
	assert_true(_service.grant("badge_combo_master"), "first grant is new")
	assert_false(_service.grant("badge_combo_master"), "duplicate")
	assert_false(_service.grant("no_such_item"), "unknown id")
	assert_eq(_unlocked, ["badge_combo_master"], "one unlock signal")
	var copies: int = 0
	for id: String in _profile.cosmetics_owned:
		if id == "badge_combo_master":
			copies += 1
	assert_eq(copies, 1, "stored once")


func test_grant_changes_only_cosmetic_slice() -> void:
	_profile.coins = 10
	_profile.gems = 2
	_service.grant("core_fire")
	assert_eq(_profile.coins, 10)
	assert_eq(_profile.gems, 2)
	assert_empty(_profile.stats, "stats untouched")
	assert_empty(_profile.purchases, "purchases untouched")


func test_grant_from_product_grants_all_items() -> void:
	var granted: Array[String] = _service.grant_from_product("pack_inferno")
	assert_eq(granted, ["core_inferno", "trail_inferno", "fx_inferno"])
	for id: String in granted:
		assert_true(_service.owns(id), "%s owned" % id)
	assert_empty(_service.grant_from_product("pack_inferno"), "restore grants nothing new")
	assert_empty(_service.grant_from_product("pack_unknown"), "unknown product")
	assert_true(_service.equip("core_inferno"), "premium item equippable once owned")


func test_owned_and_total_counts() -> void:
	_service.ensure_defaults()
	assert_eq(_service.total_count(), _catalog.items.size())
	assert_eq(_service.owned_count(), _catalog.categories().size(), "one default per category")
	_service.grant("core_fire")
	_profile.cosmetics_owned.append("unknown_future_item")
	assert_eq(_service.owned_count(), _catalog.categories().size() + 1, "unknown ids not counted")


func test_missing_dependencies_do_not_crash() -> void:
	var s: CosmeticService = CosmeticService.new(null, null, null, null, Callable())
	assert_true(s.ensure_defaults())
	assert_true(s.grant("core_fire"), "grant without bus")
	assert_true(s.equip("core_fire"), "equip without bus")
	assert_empty(s.check_auto_unlocks(), "no progress query, no auto unlocks")
	assert_gt(s.total_count(), 0, "shipped catalog loaded as fallback")


func _on_unlocked(id: String) -> void:
	_unlocked.append(id)


func _on_equipped(category: StringName, id: String) -> void:
	_equipped.append("%s=%s" % [category, id])


func _no_progress() -> Dictionary:
	return {"total_stars": 0, "player_level": 1, "perfects": 0, "achievements": []}
