extends TestCase
## Reward types of REQ-148 beyond currencies: grantable bonus stars that count
## toward star unlocks (never toward a level's three stars), and typed skin /
## trail rewards checked against the cosmetic catalog; their data, saving and
## sanitising.

const NOW: int = 1790000000

var _profile: PlayerProfile
var _bus: EventBus
var _clock: GameClock
var _economy: EconomyService
var _catalog: CosmeticCatalog
var _cosmetics: CosmeticService
var _engine: RewardEngine
var _xp: Array[int] = []


func before_each() -> void:
	_profile = PlayerProfile.new()
	_bus = EventBus.new()
	_clock = GameClock.new()
	_clock.set_fixed_unix(NOW)
	_economy = EconomyService.new(_profile, _bus, _clock)
	_catalog = CosmeticCatalog.load_default()
	_cosmetics = CosmeticService.new(_profile, _bus, _catalog, _economy, Callable())
	_xp = []
	_engine = RewardEngine.new(_profile, _bus, _economy, _grant_xp, _cosmetics.grant, {}, _catalog.category_of)


func _grant_xp(amount: int) -> void:
	_xp.append(amount)


func _types(bundle: RewardBundle) -> Array:
	var out: Array = []
	for item: Dictionary in bundle.items:
		out.append([String(item["type"]), str(item["id"])])
	return out


func test_engine_grants_every_type() -> void:
	var spec: Dictionary = {
		"coins": 10,
		"gems": 1,
		"xp": 20,
		"stars": 2,
		"cosmetic": "fx_prism",
		"skin": "core_shadow",
		"trail": "trail_ghost",
		"badge": "badge_boss_master",
	}
	assert_empty(RewardEngine.spec_errors(spec))
	assert_empty(AchievementService.validate_reward(spec), "achievements and missions accept it too")
	var granted: RewardBundle = _engine.grant_spec(spec, "achievement:test")
	assert_eq(
		_types(granted),
		[
			["coins", ""],
			["gems", ""],
			["xp", ""],
			["stars", ""],
			["cosmetic", "fx_prism"],
			["skin", "core_shadow"],
			["trail", "trail_ghost"],
			["badge", "badge_boss_master"],
		]
	)
	assert_eq(_profile.bonus_stars, 2)
	assert_eq(granted.amount_of(RewardBundle.TYPE_STARS), 2)
	for id: String in ["fx_prism", "core_shadow", "trail_ghost", "badge_boss_master"]:
		assert_true(_cosmetics.owns(id), "%s owned" % id)
	assert_eq(_xp, [20])
	var doubled: RewardBundle = _engine.double_for_ad(granted)
	assert_eq(doubled.amount_of(RewardBundle.TYPE_STARS), 0, "stars are never doubled")
	assert_eq(doubled.amount_of(RewardBundle.TYPE_SKIN), 0)


func test_typed_cosmetics_must_match_their_category() -> void:
	for spec: Dictionary in [
		{"skin": "trail_flame"},
		{"skin": "core_nope"},
		{"trail": "core_fire"},
		{"trail": "badge_boss_master"},
		{"skin": ""},
	]:
		var granted: RewardBundle = _engine.grant_spec(spec, "test")
		assert_true(granted.is_empty(), "refused: %s" % str(spec))
	assert_false(_cosmetics.owns("trail_flame") or _cosmetics.owns("core_fire"), "nothing granted")
	assert_eq(_economy.balance(EconomyService.COINS), 0, "and nothing paid instead")
	var blind: RewardEngine = RewardEngine.new(_profile, _bus, _economy, Callable(), _cosmetics.grant)
	assert_true(blind.grant_spec({"skin": "core_fire"}, "test").is_empty(), "no category lookup: refused")
	_cosmetics.grant("core_fire")
	var duplicate: RewardBundle = _engine.grant_spec({"skin": "core_fire"}, "test")
	assert_eq(duplicate.amount_of(RewardBundle.TYPE_COINS), _economy.duplicate_cosmetic_coins(), "owned: coins")
	assert_eq(duplicate.amount_of(RewardBundle.TYPE_SKIN), 0)
	assert_has(RewardEngine.spec_errors({"skin": 5}), "skin must be a non-empty id")
	assert_has(RewardEngine.spec_errors({"stars": -1}), "stars must be a whole number >= 0")
	assert_false(AchievementService.validate_reward({"stars": 1.5}).is_empty())


func test_stars_are_bounded() -> void:
	assert_true(_engine.grant_spec({"stars": 4}, "test").is_empty(), "above the per-item limit")
	assert_true(_engine.grant_spec({"stars": 0}, "test").is_empty())
	_profile.bonus_stars = PlayerProfile.MAX_BONUS_STARS - 1
	var capped: RewardBundle = _engine.grant_spec({"stars": 3}, "test")
	assert_eq(capped.amount_of(RewardBundle.TYPE_STARS), 1, "only what fits under the cap is granted and shown")
	assert_eq(_profile.bonus_stars, PlayerProfile.MAX_BONUS_STARS)
	assert_true(_engine.grant_spec({"stars": 1}, "test").is_empty(), "full")


func test_bonus_stars_count_toward_unlocks_not_campaign_totals() -> void:
	var worlds: WorldCatalog = WorldCatalog.load_default()
	var count: int = worlds.levels_in(1)
	var needed: int = int(worlds.world_at(2).get("unlock_stars", 0))
	var stars_left: int = needed - 2
	for local: int in range(1, count + 1):
		var stars: int = clampi(stars_left, 0, 3)
		stars_left -= stars
		_profile.levels[WorldCatalog.level_id(1, local)] = {"stars": stars, "clears": 1}
	var progression: ProgressionService = ProgressionService.new(_profile, _bus, worlds)
	assert_eq(progression.campaign_stars(), needed - 2)
	var second: String = str(worlds.world_at(2)["id"])
	assert_false(progression.is_world_unlocked(second), "two stars short")
	assert_eq(progression.stars_needed_for(second), 2)
	_engine.grant_spec({"stars": 2}, "achievement:secret_time")
	assert_eq(progression.total_stars(), needed, "bonus stars count")
	assert_eq(progression.campaign_stars(), needed - 2, "but not as campaign stars")
	assert_eq(_profile.total_stars(), needed - 2, "PlayerProfile.total_stars stays campaign-only")
	assert_eq(progression.refresh_world_unlocks(), [second] as Array[String], "the world unlocks")
	var summary: Dictionary = progression.progress_summary()
	assert_eq(int(summary["total_stars"]), needed - 2, "x / max shows campaign stars")
	assert_le(float(summary["total_stars"]), float(summary["max_stars"]))
	assert_eq(int(summary["bonus_stars"]), 2)
	assert_eq(int(summary["unlock_stars"]), needed)
	var modes: ModeCatalog = ModeCatalog.load_default()
	var time_attack: int = int((modes.mode(&"time_attack").get("unlock", {}) as Dictionary).get("value", 0))
	_profile.levels.clear()
	_profile.bonus_stars = 0
	assert_false(modes.is_unlocked(&"time_attack", {"stars": progression.total_stars()}))
	_profile.bonus_stars = time_attack
	assert_true(modes.is_unlocked(&"time_attack", {"stars": progression.total_stars()}), "stars mode unlock")


func test_bonus_stars_survive_a_save_round_trip() -> void:
	var storage: MemorySaveStorage = MemorySaveStorage.new()
	var save: SaveService = SaveService.new(storage, _clock)
	_profile.bonus_stars = 5
	_profile.flags[CloudSaveService.FLAG_REVISION] = "r3"
	_profile.flags[CloudSaveService.FLAG_DIRTY] = true
	_profile.flags[CloudSaveService.FLAG_SYNCED_AT] = NOW
	assert_eq(save.save_profile(_profile), OK)
	var loaded: PlayerProfile = SaveService.new(storage, _clock).load_profile()
	assert_eq(loaded.bonus_stars, 5)
	assert_eq(str(loaded.flags[CloudSaveService.FLAG_REVISION]), "r3")
	assert_true(bool(loaded.flags[CloudSaveService.FLAG_DIRTY]))
	assert_eq(int(loaded.flags[CloudSaveService.FLAG_SYNCED_AT]), NOW)


func test_hostile_values_are_sanitized() -> void:
	var cases: Dictionary = {-5: 0, 1e15: PlayerProfile.MAX_BONUS_STARS, "lots": 0, 2.9: 2, null: 0}
	for raw: Variant in cases:
		var p: PlayerProfile = PlayerProfile.from_dict({"bonus_stars": raw})
		assert_eq(p.bonus_stars, int(cases[raw]), "bonus_stars %s" % str(raw))
	var flags: Dictionary = {"cloud.dirty": "yes", "cloud.revision": 7, "cloud.synced_at": "today", "other": 1}
	var cleaned: PlayerProfile = PlayerProfile.from_dict({"flags": flags})
	assert_eq(cleaned.flags, {"other": 1}, "cloud flags of the wrong type are dropped")
	var copy: PlayerProfile = PlayerProfile.new()
	var levels_ref: Dictionary = copy.levels
	copy.copy_from(PlayerProfile.from_dict({"bonus_stars": 3, "levels": {"w01_l01": {"stars": 9}}}))
	assert_eq(copy.bonus_stars, 3)
	assert_true(is_same(levels_ref, copy.levels), "containers keep their identity")
	assert_eq(copy.stars_for("w01_l01"), 3, "already sanitised")


func test_achievement_data_pays_the_new_types() -> void:
	var stars_paid: int = 0
	var kinds: Dictionary = {}
	for raw: Variant in AchievementService.load_definitions():
		var def: Dictionary = raw as Dictionary
		var reward: Dictionary = def.get("reward", {}) as Dictionary
		if reward.has("stars"):
			stars_paid += 1
			assert_has(["secret", "mastery"], str(def["category"]), "%s: stars for secret / mastery goals" % def["id"])
			assert_true(int(reward["stars"]) >= 1 and int(reward["stars"]) <= 3, "%s pays 1-3 stars" % def["id"])
		for kind: String in ["skin", "trail"]:
			if not reward.has(kind):
				continue
			kinds[kind] = true
			var id: String = str(reward[kind])
			var category: String = CosmeticCatalog.CORE_SKIN if kind == "skin" else CosmeticCatalog.TRAIL
			assert_eq(_catalog.category_of(id), category, "%s rewards a real %s" % [def["id"], kind])
			assert_ne(str(_catalog.unlock_of(id)["type"]), CosmeticCatalog.UNLOCK_PREMIUM, "never a premium item")
			assert_empty(_catalog.products_containing(id), "never part of a store pack")
	assert_ge(float(stars_paid), 2.0, "a few achievements pay stars")
	assert_eq(kinds.keys().size(), 2, "one skin and one trail reward")
