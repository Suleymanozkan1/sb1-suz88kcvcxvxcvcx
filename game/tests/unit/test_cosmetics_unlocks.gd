extends TestCase
## CosmeticService: automatic unlocks, unlock status, shop listing and params.

var _profile: PlayerProfile = null
var _bus: EventBus = null
var _catalog: CosmeticCatalog = null
var _economy: InMemoryWallet = null
var _service: CosmeticService = null
var _progress: Dictionary = {}
var _unlocked: Array[String] = []


## Test double: wallet without a balance() method (only the required API).
class InMemoryWallet:
	extends RefCounted

	var coins: int = 0
	var gems: int = 0

	func can_afford(currency: StringName, amount: int) -> bool:
		return amount > 0 and _amount(currency) >= amount

	func spend(currency: StringName, amount: int, _reason: String) -> bool:
		if not can_afford(currency, amount):
			return false
		if currency == &"coins":
			coins -= amount
		else:
			gems -= amount
		return true

	func _amount(currency: StringName) -> int:
		if currency == &"coins":
			return coins
		if currency == &"gems":
			return gems
		return 0


func before_each() -> void:
	_profile = PlayerProfile.new()
	_bus = EventBus.new()
	_catalog = CosmeticCatalog.load_default()
	_economy = InMemoryWallet.new()
	_progress = {"total_stars": 0, "player_level": 1, "perfects": 0, "achievements": []}
	_service = CosmeticService.new(_profile, _bus, _catalog, _economy, _query)
	_service.ensure_defaults()
	_unlocked = []
	_bus.cosmetic_unlocked.connect(_on_unlocked)


func test_nothing_unlocks_without_progress() -> void:
	assert_empty(_service.check_auto_unlocks())
	assert_empty(_unlocked)


func test_auto_unlock_by_stars() -> void:
	_progress["total_stars"] = 90
	var granted: Array[String] = _service.check_auto_unlocks()
	assert_has(granted, "core_void", "90 stars unlocks Void Core")
	assert_has(granted, "frame_dotted", "60 stars frame")
	assert_has(granted, "avatar_hexagon", "30 stars avatar")
	assert_false(granted.has("theme_jungle"), "120 stars not reached")
	assert_eq(_unlocked, granted, "every unlock announced")
	assert_empty(_service.check_auto_unlocks(), "idempotent")


func test_auto_unlock_by_player_level() -> void:
	_progress["player_level"] = 10
	var granted: Array[String] = _service.check_auto_unlocks()
	assert_has(granted, "core_electric")
	assert_has(granted, "particle_bubbles")
	assert_has(granted, "fx_soft_glow")
	assert_false(granted.has("theme_royal"), "level 12 item still locked")


func test_auto_unlock_by_perfects() -> void:
	_progress["perfects"] = 25
	var granted: Array[String] = _service.check_auto_unlocks()
	assert_has(granted, "fx_void", "10 perfects")
	assert_has(granted, "trail_ghost", "25 perfects")
	assert_false(granted.has("core_solar"), "50 perfects not reached")
	for id: String in granted:
		assert_false(id.begins_with("badge_perfect_"), "tier badges come from the reward engine (%s)" % id)


func test_auto_unlock_by_achievements() -> void:
	_progress["achievements"] = ["boss_master", "high_combo"]
	var granted: Array[String] = _service.check_auto_unlocks()
	assert_has(granted, "core_shadow")
	assert_has(granted, "badge_boss_master")
	assert_has(granted, "badge_high_combo")
	assert_has(granted, "fx_prism")
	assert_false(granted.has("badge_daily_master"))


func test_auto_unlocks_never_grant_shop_or_premium_items() -> void:
	_progress = {"total_stars": 1560, "player_level": 999, "perfects": 520, "achievements": ["boss_master"]}
	_service.check_auto_unlocks()
	assert_false(_service.owns("core_fire"), "coin item not free")
	assert_false(_service.owns("core_nebula"), "gem item not free")
	assert_false(_service.owns("core_inferno"), "premium item not free")
	assert_true(_service.owns("core_prism"), "900 stars item granted")
	assert_true(_service.owns("avatar_crown"), "level 40 item granted")


func test_invalid_progress_query_is_ignored() -> void:
	var s: CosmeticService = CosmeticService.new(_profile, _bus, _catalog, _economy, func() -> Variant: return 42)
	assert_empty(s.check_auto_unlocks(), "non-dictionary progress")
	_progress = {"total_stars": "lots", "achievements": "boss_master"}
	assert_empty(_service.check_auto_unlocks(), "wrongly typed fields count as zero")


func test_unlock_status_for_price_items() -> void:
	_economy.coins = 100
	var s: Dictionary = _service.unlock_status("core_fire")
	assert_eq(str(s["type"]), "coins")
	assert_false(bool(s["owned"]))
	assert_false(bool(s["can_unlock_now"]), "cannot afford")
	assert_eq(s["price"], {"currency": "coins", "amount": 400})
	assert_eq(int(s["target"]), 400)
	_economy.coins = 500
	s = _service.unlock_status("core_fire")
	assert_true(bool(s["can_unlock_now"]), "affordable")
	assert_eq(int(s["progress"]), 400, "progress capped at the price")


func test_unlock_status_for_progress_items() -> void:
	_progress["total_stars"] = 45
	var s: Dictionary = _service.unlock_status("core_void")
	assert_eq(str(s["type"]), "stars")
	assert_eq(int(s["progress"]), 45)
	assert_eq(int(s["target"]), 90)
	assert_false(bool(s["can_unlock_now"]))
	_progress["total_stars"] = 95
	s = _service.unlock_status("core_void")
	assert_true(bool(s["can_unlock_now"]))
	assert_eq(int(s["progress"]), 90, "progress capped")
	var ach: Dictionary = _service.unlock_status("badge_daily_master")
	assert_eq(str(ach["requirement"]), "daily_master")
	assert_eq(int(ach["target"]), 1)
	assert_eq(int(ach["progress"]), 0)
	var tier: Dictionary = _service.unlock_status("badge_perfect_expert")
	assert_eq(str(tier["requirement"]), "expert")
	assert_false(bool(tier["can_unlock_now"]))


func test_unlock_status_for_owned_premium_default_and_unknown() -> void:
	var premium: Dictionary = _service.unlock_status("core_inferno")
	assert_eq(str(premium["type"]), "premium")
	assert_has(premium["products"], "pack_inferno")
	assert_false(bool(premium["can_unlock_now"]), "premium only via store")
	_service.grant_from_product("pack_inferno")
	premium = _service.unlock_status("core_inferno")
	assert_true(bool(premium["owned"]))
	assert_eq(int(premium["progress"]), int(premium["target"]))
	var def: Dictionary = _service.unlock_status("core_plasma")
	assert_true(bool(def["owned"]))
	assert_eq(str(def["type"]), "default")
	var unknown: Dictionary = _service.unlock_status("nope")
	assert_false(bool(unknown["owned"]))
	assert_eq(str(unknown["type"]), "")
	for key: String in ["owned", "can_unlock_now", "type", "progress", "target", "price"]:
		assert_has(unknown, key)


func test_shop_items_purchasable_only_not_owned_first() -> void:
	_service.grant("core_fire")
	_economy.coins = 450
	var rows: Array[Dictionary] = _service.shop_items()
	assert_gt(rows.size(), 0)
	var seen_owned: bool = false
	for row: Dictionary in rows:
		var id: String = str(row["id"])
		assert_has(["coins", "gems"], str(row["currency"]), "%s currency" % id)
		assert_ne(str(row["category"]), "badge", "badges never in the shop")
		assert_gt(int(row["price"]), 0)
		if bool(row["owned"]):
			seen_owned = true
		else:
			assert_false(seen_owned, "%s listed after an owned item" % id)
	assert_true(seen_owned, "owned purchasable item still listed")
	assert_true(bool(rows[rows.size() - 1]["owned"]), "owned rows last")
	var ice: Dictionary = {}
	for row2: Dictionary in rows:
		if row2["id"] == "core_ice":
			ice = row2
	assert_true(bool(ice["affordable"]), "400 <= 450 coins")


func test_params_parse_to_colors() -> void:
	var core: Dictionary = _service.core_skin_params("core_ice")
	assert_eq(typeof(core["color_a"]), TYPE_COLOR)
	assert_eq(typeof(core["color_b"]), TYPE_COLOR)
	assert_eq(typeof(core["rim"]), TYPE_COLOR)
	assert_eq(int(core["style"]), 2, "ice style")
	assert_eq(typeof(core["anim_speed"]), TYPE_FLOAT)
	var trail: Dictionary = _service.trail_params("trail_flame")
	assert_true((trail["head"] as Color).is_equal_approx(Color.html("#ffd23d")))
	assert_eq(int(trail["style"]), 3)
	assert_eq(typeof(_service.particle_params("particle_embers")["colors"]), TYPE_ARRAY)
	assert_eq(typeof(_service.background_params("bg_dusk")["sky_top"]), TYPE_COLOR)
	assert_eq(typeof(_service.theme_params("theme_ember")["panel_tint"]), TYPE_COLOR)
	assert_eq(typeof(_service.effect_params("fx_ember")["shockwave"]), TYPE_FLOAT)
	assert_eq(str(_service.frame_params("frame_laurel")["pattern"]), "laurel")
	assert_eq(str(_service.avatar_params("avatar_bolt")["glyph"]), "bolt")
	assert_eq(typeof(_service.avatar_params("avatar_bolt")["fg"]), TYPE_COLOR)


func test_params_default_to_equipped_and_fall_back_safely() -> void:
	assert_eq(str(_service.core_skin_params()["id"]), "core_plasma", "equipped default")
	_service.grant("core_fire")
	_service.equip("core_fire")
	assert_eq(str(_service.core_skin_params()["id"]), "core_fire", "equipped item")
	assert_eq(str(_service.core_skin_params("trail_flame")["id"]), "core_plasma", "wrong category falls back")
	assert_eq(str(_service.trail_params("no_such")["id"]), "trail_classic", "unknown id falls back")
	assert_eq(typeof(_service.trail_params("no_such")["head"]), TYPE_COLOR)


func _on_unlocked(id: String) -> void:
	_unlocked.append(id)


func _query() -> Dictionary:
	return _progress
