extends TestCase
## RewardEngine.grant / grant_spec / bundle_from_spec / double_for_ad: only
## what was really applied is reported, duplicates and invalid items handled.

const NOW: int = 1790000000
const CATALOG: Array[String] = ["core_fire", "core_ice", "trail_helix", "badge_first_perfect", "badge_perfect_early"]

var profile: PlayerProfile
var bus: EventBus
var economy: EconomyService
var engine: RewardEngine
var xp_log: Array[int] = []
var cosmetic_calls: Array[String] = []
var signalled: Array[RewardBundle] = []


func before_each() -> void:
	profile = PlayerProfile.new()
	bus = EventBus.new()
	var clock: GameClock = GameClock.new()
	clock.set_fixed_unix(NOW)
	economy = EconomyService.new(profile, bus, clock)
	engine = RewardEngine.new(profile, bus, economy, _grant_xp, _grant_cosmetic)
	xp_log = []
	cosmetic_calls = []
	signalled = []
	bus.reward_granted.connect(_on_reward_granted)


func _grant_xp(amount: int) -> void:
	xp_log.append(amount)
	profile.xp += amount


## Behaves like CosmeticService.grant: catalog ids only, true when new.
func _grant_cosmetic(item_id: String) -> bool:
	cosmetic_calls.append(item_id)
	if not CATALOG.has(item_id) or profile.cosmetics_owned.has(item_id):
		return false
	profile.cosmetics_owned.append(item_id)
	return true


func _on_reward_granted(bundle: RewardBundle) -> void:
	signalled.append(bundle)


func _items(bundle: RewardBundle) -> Array:
	return bundle.to_dict()["items"] as Array


func test_grant_returns_exactly_applied_items() -> void:
	var bundle: RewardBundle = RewardBundle.new("test_source")
	bundle.add(RewardBundle.TYPE_COINS, 50).add(RewardBundle.TYPE_GEMS, 2).add(RewardBundle.TYPE_XP, 30)
	bundle.add(RewardBundle.TYPE_COSMETIC, 1, "core_fire").add(RewardBundle.TYPE_BADGE, 1, "badge_first_perfect")
	var granted: RewardBundle = engine.grant(bundle)
	assert_ne(granted, bundle, "a new bundle is returned")
	assert_eq(granted.source, "test_source")
	assert_eq(_items(granted), _items(bundle), "everything valid was applied as-is")
	assert_eq(economy.balance(EconomyService.COINS), 50)
	assert_eq(economy.balance(EconomyService.GEMS), 2)
	assert_eq(xp_log, [30] as Array[int])
	assert_true(profile.cosmetics_owned.has("core_fire"))
	assert_true(profile.cosmetics_owned.has("badge_first_perfect"))


func test_grant_drops_invalid_items() -> void:
	var bundle: RewardBundle = RewardBundle.new("mixed")
	bundle.add(RewardBundle.TYPE_COINS, 20)
	bundle.add(RewardBundle.TYPE_GEMS, economy.max_single_grant(EconomyService.GEMS) + 1)
	bundle.add(RewardBundle.TYPE_COSMETIC, 1, "core_unknown")
	bundle.add(RewardBundle.TYPE_STARS, 3)
	bundle.items.append({"type": &"xp", "amount": -5, "id": ""})
	bundle.items.append({"type": &"coins", "amount": "lots", "id": ""})
	bundle.items.append({"type": &"cosmetic", "amount": 1, "id": ""})
	bundle.items.append({"type": &"tokens", "amount": 9, "id": ""})
	var granted: RewardBundle = engine.grant(bundle)
	assert_eq(_items(granted), [{"type": "coins", "amount": 20, "id": ""}])
	assert_eq(economy.balance(EconomyService.GEMS), 0, "over-limit gems rejected")
	assert_false(profile.cosmetics_owned.has("core_unknown"))
	assert_true(xp_log.is_empty())


func test_duplicate_cosmetic_converted_to_coins() -> void:
	profile.cosmetics_owned.append("core_fire")
	var bundle: RewardBundle = RewardBundle.new("chest").add(RewardBundle.TYPE_COSMETIC, 1, "core_fire")
	var granted: RewardBundle = engine.grant(bundle)
	var compensation: int = economy.duplicate_cosmetic_coins()
	assert_eq(_items(granted), [{"type": "coins", "amount": compensation, "id": "duplicate:core_fire"}])
	assert_eq(granted.amount_of(RewardBundle.TYPE_COSMETIC), 0, "no cosmetic shown")
	assert_eq(economy.balance(EconomyService.COINS), compensation)
	assert_true(cosmetic_calls.is_empty(), "owned items are not re-granted")
	assert_eq(profile.ledger[profile.ledger.size() - 1]["s"], "chest:duplicate")


func test_same_cosmetic_twice_in_one_bundle() -> void:
	var bundle: RewardBundle = RewardBundle.new("pack")
	bundle.add(RewardBundle.TYPE_COSMETIC, 1, "core_ice").add(RewardBundle.TYPE_COSMETIC, 1, "core_ice")
	var granted: RewardBundle = engine.grant(bundle)
	assert_eq(granted.amount_of(RewardBundle.TYPE_COSMETIC), 1)
	assert_eq(granted.amount_of(RewardBundle.TYPE_COINS), economy.duplicate_cosmetic_coins())


func test_duplicate_badge_is_dropped_not_converted() -> void:
	profile.cosmetics_owned.append("badge_perfect_early")
	var bundle: RewardBundle = RewardBundle.new("level:w01_l09").add(RewardBundle.TYPE_BADGE, 1, "badge_perfect_early")
	var granted: RewardBundle = engine.grant(bundle)
	assert_true(granted.is_empty(), "badges are trophies, not a coin source")
	assert_eq(economy.balance(EconomyService.COINS), 0)


func test_reward_granted_signal_carries_the_granted_bundle() -> void:
	profile.cosmetics_owned.append("core_fire")
	var bundle: RewardBundle = RewardBundle.new("chest").add(RewardBundle.TYPE_XP, 10)
	bundle.add(RewardBundle.TYPE_COSMETIC, 1, "core_fire").add(RewardBundle.TYPE_COSMETIC, 1, "core_unknown")
	var granted: RewardBundle = engine.grant(bundle)
	assert_eq(signalled.size(), 1)
	assert_eq(signalled[0], granted, "the UI receives what was applied, not what was asked")
	assert_eq(_items(signalled[0]), _items(granted))


func test_empty_or_null_grant_emits_nothing() -> void:
	assert_true(engine.grant(RewardBundle.new("nothing")).is_empty())
	assert_true(engine.grant(null).is_empty())
	var all_invalid: RewardBundle = RewardBundle.new("bad").add(RewardBundle.TYPE_COSMETIC, 1, "core_unknown")
	assert_true(engine.grant(all_invalid).is_empty())
	assert_empty(signalled)


func test_currency_clamped_at_cap_reports_applied_amount() -> void:
	profile.coins = economy.balance_cap(EconomyService.COINS) - 7
	var granted: RewardBundle = engine.grant(RewardBundle.new("x").add(RewardBundle.TYPE_COINS, 100))
	assert_eq(granted.amount_of(RewardBundle.TYPE_COINS), 7, "only the credited part is shown")


func test_double_for_ad_excludes_cosmetics_badges_and_xp() -> void:
	var bundle: RewardBundle = RewardBundle.new("level:w01_l01")
	bundle.add(RewardBundle.TYPE_COINS, 31).add(RewardBundle.TYPE_GEMS, 1).add(RewardBundle.TYPE_XP, 20)
	bundle.add(RewardBundle.TYPE_COSMETIC, 1, "core_fire").add(RewardBundle.TYPE_BADGE, 1, "badge_perfect_early")
	bundle.add(RewardBundle.TYPE_COINS, 150, "duplicate:core_ice")
	var doubled: RewardBundle = engine.double_for_ad(bundle)
	assert_eq(_items(doubled), [{"type": "coins", "amount": 31, "id": ""}, {"type": "gems", "amount": 1, "id": ""}])
	assert_eq(doubled.source, "level:w01_l01:ad_double")
	assert_eq(doubled.amount_of(RewardBundle.TYPE_COSMETIC), 0)
	assert_eq(doubled.amount_of(RewardBundle.TYPE_BADGE), 0)
	assert_eq(bundle.items.size(), 6, "input untouched")
	assert_true(engine.double_for_ad(null).is_empty())


func test_doubled_bundle_grants_the_same_currency_again() -> void:
	var bundle: RewardBundle = RewardBundle.new("level:w01_l02").add(RewardBundle.TYPE_COINS, 25)
	var granted: RewardBundle = engine.grant(bundle)
	var bonus: RewardBundle = engine.grant(engine.double_for_ad(granted))
	assert_eq(bonus.amount_of(RewardBundle.TYPE_COINS), 25)
	assert_eq(economy.balance(EconomyService.COINS), 50)
	assert_eq(EconomyService.ledger_label_key(str(profile.ledger[1]["s"])), "economy.ledger.source.ad_double")


func test_double_for_ad_follows_data() -> void:
	var tables: Dictionary = RewardEngine.load_tables().duplicate(true)
	tables["ad_double"] = {"types": ["coins", "cosmetic", "xp"]}
	var custom: RewardEngine = RewardEngine.new(profile, bus, economy, _grant_xp, _grant_cosmetic, tables)
	assert_eq(custom.ad_double_types(), [EconomyService.COINS] as Array[StringName], "non-currencies ignored")
	var bundle: RewardBundle = RewardBundle.new("x").add(RewardBundle.TYPE_COINS, 10).add(RewardBundle.TYPE_GEMS, 2)
	var doubled: RewardBundle = custom.double_for_ad(bundle)
	assert_eq(doubled.amount_of(RewardBundle.TYPE_COINS), 10)
	assert_eq(doubled.amount_of(RewardBundle.TYPE_GEMS), 0)


func test_bundle_from_spec_builds_every_type() -> void:
	var spec: Dictionary = {"coins": 40, "gems": 2.0, "xp": 15, "cosmetic": "trail_helix", "badge": "badge_first_perfect"}
	var bundle: RewardBundle = engine.bundle_from_spec(spec, "achievement:first_perfect")
	assert_eq(bundle.source, "achievement:first_perfect")
	assert_eq(bundle.amount_of(RewardBundle.TYPE_COINS), 40)
	assert_eq(bundle.amount_of(RewardBundle.TYPE_GEMS), 2)
	assert_eq(bundle.amount_of(RewardBundle.TYPE_XP), 15)
	assert_eq(bundle.items.size(), 5)
	assert_eq(str(bundle.items[3]["id"]), "trail_helix")
	assert_eq(str(bundle.items[4]["id"]), "badge_first_perfect")


func test_bundle_from_spec_skips_invalid_entries() -> void:
	var spec: Dictionary = {"coins": -5, "gems": "two", "xp": 0, "cosmetic": "", "badge": 12, "boosters": 3}
	assert_true(engine.bundle_from_spec(spec).is_empty())
	assert_true(engine.bundle_from_spec({}).is_empty())


func test_grant_spec_matches_achievement_contract() -> void:
	var granted: RewardBundle = engine.grant_spec({"coins": 100, "badge": "badge_first_perfect"}, "achievement:x")
	assert_eq(granted.amount_of(RewardBundle.TYPE_COINS), 100)
	assert_eq(granted.amount_of(RewardBundle.TYPE_BADGE), 1)
	assert_eq(granted.source, "achievement:x")
	var again: RewardBundle = engine.grant_spec({"coins": 100, "badge": "badge_first_perfect"}, "achievement:x")
	assert_eq(_items(again), [{"type": "coins", "amount": 100, "id": ""}], "owned badge dropped on repeat")


func test_missing_callbacks_drop_only_their_items() -> void:
	var bare: RewardEngine = RewardEngine.new(profile, bus, economy, Callable(), Callable())
	var bundle: RewardBundle = RewardBundle.new("x").add(RewardBundle.TYPE_COINS, 5).add(RewardBundle.TYPE_XP, 5)
	bundle.add(RewardBundle.TYPE_COSMETIC, 1, "core_fire")
	var granted: RewardBundle = bare.grant(bundle)
	assert_eq(_items(granted), [{"type": "coins", "amount": 5, "id": ""}])
	assert_false(profile.cosmetics_owned.has("core_fire"))


func test_absurd_xp_is_dropped() -> void:
	var limit: int = int((engine.tables["limits"] as Dictionary)["max_xp_per_item"])
	var granted: RewardBundle = engine.grant(RewardBundle.new("x").add(RewardBundle.TYPE_XP, limit + 1))
	assert_true(granted.is_empty())
	assert_true(xp_log.is_empty())
	assert_eq(engine.grant(RewardBundle.new("x").add(RewardBundle.TYPE_XP, limit)).amount_of(&"xp"), limit)
