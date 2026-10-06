extends TestCase
## EconomyService: grant/spend validation, ledger, signals and balance caps.

const NOW: int = 1790000000
const COINS: StringName = EconomyService.COINS
const GEMS: StringName = EconomyService.GEMS

var profile: PlayerProfile
var bus: EventBus
var clock: GameClock
var economy: EconomyService
var events: Array[Array] = []


func before_each() -> void:
	profile = PlayerProfile.new()
	bus = EventBus.new()
	clock = GameClock.new()
	clock.set_fixed_unix(NOW)
	economy = EconomyService.new(profile, bus, clock)
	events = []
	bus.currency_changed.connect(_on_currency_changed)


func _on_currency_changed(currency: StringName, balance: int, delta: int) -> void:
	events.append([currency, balance, delta])


func test_grant_adds_to_balance() -> void:
	assert_true(economy.grant(COINS, 120, "test"))
	assert_true(economy.grant(GEMS, 3, "test"))
	assert_eq(economy.balance(COINS), 120)
	assert_eq(economy.balance(GEMS), 3)
	assert_eq(profile.coins, 120, "profile is the storage")
	assert_eq(profile.gems, 3)


func test_spend_deducts_balance() -> void:
	economy.grant(COINS, 300, "test")
	assert_true(economy.spend(COINS, 120, "shop"))
	assert_eq(economy.balance(COINS), 180)


func test_insufficient_funds_rejected_without_side_effects() -> void:
	economy.grant(GEMS, 5, "test")
	var ledger_size: int = profile.ledger.size()
	events.clear()
	assert_false(economy.spend(GEMS, 6, "shop"), "cannot spend more than owned")
	assert_eq(economy.balance(GEMS), 5, "balance untouched")
	assert_eq(profile.ledger.size(), ledger_size, "no ledger entry")
	assert_empty(events, "no signal")


func test_balance_never_goes_negative() -> void:
	economy.grant(COINS, 40, "test")
	assert_true(economy.spend(COINS, 40, "shop"), "spending the exact balance works")
	assert_eq(economy.balance(COINS), 0)
	assert_false(economy.spend(COINS, 1, "shop"))
	assert_eq(economy.balance(COINS), 0)


func test_zero_and_negative_amounts_rejected() -> void:
	economy.grant(COINS, 50, "test")
	events.clear()
	assert_false(economy.grant(COINS, 0, "test"), "zero grant")
	assert_false(economy.grant(COINS, -10, "test"), "negative grant")
	assert_false(economy.spend(COINS, 0, "shop"), "zero spend")
	assert_false(economy.spend(COINS, -10, "shop"), "negative spend would add money")
	assert_eq(economy.balance(COINS), 50)
	assert_empty(events)


func test_unknown_currency_rejected() -> void:
	assert_false(economy.grant(&"tokens", 10, "test"))
	assert_false(economy.spend(&"tokens", 10, "test"))
	assert_false(economy.can_afford(&"tokens", 0))
	assert_eq(economy.balance(&"tokens"), 0)
	assert_false(EconomyService.is_currency(&"xp"), "xp is not a currency")
	assert_true(EconomyService.is_currency(COINS))
	assert_empty(profile.ledger)


func test_grant_over_single_limit_rejected() -> void:
	assert_false(economy.grant(COINS, 5001, "test"), "above coin limit")
	assert_false(economy.grant(GEMS, 51, "test"), "above gem limit")
	assert_eq(economy.balance(COINS), 0)
	assert_eq(economy.balance(GEMS), 0)
	assert_true(economy.grant(COINS, 5000, "test"), "exactly the limit is fine")
	assert_true(economy.grant(GEMS, 50, "test"))


func test_can_afford() -> void:
	economy.grant(COINS, 100, "test")
	assert_true(economy.can_afford(COINS, 100))
	assert_true(economy.can_afford(COINS, 0), "free is affordable")
	assert_false(economy.can_afford(COINS, 101))
	assert_false(economy.can_afford(COINS, -1), "negative price is invalid")
	assert_false(economy.can_afford(GEMS, 1))


func test_ledger_entry_fields() -> void:
	economy.grant(COINS, 75, "level:w01_l02")
	clock.set_fixed_unix(NOW + 60)
	economy.spend(COINS, 25, "purchase:core_fire")
	assert_eq(profile.ledger.size(), 2)
	var first: Dictionary = profile.ledger[0]
	assert_eq(first["t"], NOW)
	assert_eq(first["c"], "coins")
	assert_eq(first["d"], 75)
	assert_eq(first["s"], "level:w01_l02")
	assert_eq(first["b"], 75)
	var second: Dictionary = profile.ledger[1]
	assert_eq(second["t"], NOW + 60)
	assert_eq(second["d"], -25, "spend is a negative delta")
	assert_eq(second["s"], "purchase:core_fire")
	assert_eq(second["b"], 50, "balance after the spend")


func test_ledger_is_bounded() -> void:
	var total: int = PlayerProfile.LEDGER_LIMIT + 15
	for i: int in total:
		economy.grant(COINS, i + 1, "grant_%d" % i)
	assert_eq(profile.ledger.size(), PlayerProfile.LEDGER_LIMIT)
	assert_eq(profile.ledger[profile.ledger.size() - 1]["s"], "grant_%d" % (total - 1), "newest kept last")
	assert_eq(profile.ledger[0]["s"], "grant_%d" % (total - PlayerProfile.LEDGER_LIMIT), "oldest dropped")
	assert_eq(int(profile.ledger[profile.ledger.size() - 1]["b"]), economy.balance(COINS))


func test_ledger_source_is_sanitised() -> void:
	economy.grant(COINS, 5, "   ")
	economy.grant(COINS, 5, "x".repeat(500))
	assert_eq(profile.ledger[0]["s"], EconomyService.UNKNOWN_SOURCE)
	assert_eq(str(profile.ledger[1]["s"]).length(), EconomyService.MAX_SOURCE_LENGTH)


func test_currency_changed_emitted_with_correct_delta() -> void:
	economy.grant(COINS, 30, "test")
	economy.spend(COINS, 10, "shop")
	economy.grant(GEMS, 2, "test")
	assert_eq(events.size(), 3)
	assert_eq(events[0], [COINS, 30, 30])
	assert_eq(events[1], [COINS, 20, -10])
	assert_eq(events[2], [GEMS, 2, 2])


func test_balance_cap_clamps_and_reports_real_delta() -> void:
	var config: Dictionary = {
		"schema_version": 1,
		"max_single_grant": {"coins": 500, "gems": 10},
		"balance_cap": {"coins": 1000, "gems": 20},
		"duplicate_cosmetic_coins": 50,
		"starting": {"coins": 0, "gems": 0},
	}
	var capped: EconomyService = EconomyService.new(profile, bus, clock, config)
	profile.coins = 900
	assert_true(capped.grant(COINS, 500, "test"))
	assert_eq(capped.balance(COINS), 1000, "clamped to cap")
	assert_eq(events[events.size() - 1], [COINS, 1000, 100], "signal carries the applied delta")
	assert_eq(profile.ledger[profile.ledger.size() - 1]["d"], 100)
	assert_false(capped.grant(COINS, 1, "test"), "no grants beyond the cap")


func test_grant_on_edited_wallet_above_cap_never_reduces_it() -> void:
	var cap: int = economy.balance_cap(COINS)
	profile.coins = cap + 1000
	assert_false(economy.grant(COINS, 10, "test"), "no grant beyond the cap")
	assert_eq(economy.balance(COINS), cap + 1000, "the cap never takes coins away")
	assert_empty(profile.ledger)
	assert_empty(events)
	assert_true(economy.spend(COINS, 500, "shop"), "spending still works")
	assert_eq(economy.balance(COINS), cap + 500)


func test_recent_ledger_normalises_values_after_save_round_trip() -> void:
	economy.grant(COINS, 120, "level:w01_l01")
	economy.spend(COINS, 20, "cosmetic:core_fire")
	var json: Variant = JSON.parse_string(JSON.stringify(profile.to_dict()))
	var reloaded: PlayerProfile = PlayerProfile.from_dict(json as Dictionary)
	reloaded.ledger.append({"c": "tokens", "d": 5, "s": "x", "b": 5, "t": NOW})
	reloaded.ledger.append({"c": "coins"})
	var history: Array[Dictionary] = EconomyService.new(reloaded, bus, clock).recent_ledger()
	assert_eq(history.size(), 3, "unknown currencies skipped, partial entries kept")
	assert_eq(history[0], {"t": 0, "c": "coins", "d": 0, "s": EconomyService.UNKNOWN_SOURCE, "b": 0})
	var spend: Dictionary = history[1]
	assert_eq(typeof(spend["d"]), TYPE_INT, "JSON floats become whole numbers again")
	assert_eq(str(spend["d"]), "-20", "shown without a decimal part")
	assert_eq(spend["b"], 100)
	assert_eq(spend["t"], NOW)
	assert_eq(spend["s"], "cosmetic:core_fire")


func test_recent_ledger_filters_and_orders_newest_first() -> void:
	economy.grant(COINS, 10, "a")
	economy.grant(GEMS, 1, "b")
	economy.grant(COINS, 20, "c")
	var all: Array[Dictionary] = economy.recent_ledger()
	assert_eq(all.size(), 3)
	assert_eq(all[0]["s"], "c")
	var coins_only: Array[Dictionary] = economy.recent_ledger(COINS)
	assert_eq(coins_only.size(), 2)
	assert_eq(coins_only[1]["s"], "a")
	assert_eq(economy.recent_ledger(COINS, 1).size(), 1)
	coins_only[0]["b"] = 999999
	assert_eq(int(profile.ledger[2]["b"]), 30, "returned entries are copies")
