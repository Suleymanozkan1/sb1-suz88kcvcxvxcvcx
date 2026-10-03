extends TestCase
## EconomyService: configuration, fallbacks, starting balance, prices, labels.

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


func test_default_config_matches_contract() -> void:
	assert_eq(economy.max_single_grant(COINS), 5000, "coin grant limit")
	assert_eq(economy.max_single_grant(GEMS), 50, "gem grant limit")
	assert_eq(economy.duplicate_cosmetic_coins(), 150, "duplicate compensation")
	assert_gt(economy.balance_cap(COINS), economy.max_single_grant(COINS), "coin cap above grant limit")
	assert_gt(economy.balance_cap(GEMS), economy.max_single_grant(GEMS), "gem cap above grant limit")
	var starting: Dictionary = economy.config[EconomyService.KEY_STARTING] as Dictionary
	assert_eq(int(starting["coins"]), 100)
	assert_eq(int(starting["gems"]), 0)


func test_starting_balance_applied_once() -> void:
	assert_true(economy.apply_starting_balance())
	assert_eq(economy.balance(COINS), 100)
	assert_eq(economy.balance(GEMS), 0)
	assert_eq(profile.ledger.size(), 1, "gems are 0 so only the coin entry")
	assert_eq(profile.ledger[0]["s"], EconomyService.STARTING_SOURCE)
	assert_false(economy.apply_starting_balance(), "second call does nothing")
	assert_eq(economy.balance(COINS), 100)
	var reloaded: PlayerProfile = PlayerProfile.from_dict(profile.to_dict())
	var again: EconomyService = EconomyService.new(reloaded, bus, clock)
	assert_false(again.apply_starting_balance(), "flag survives a save round trip")
	assert_eq(again.balance(COINS), 100)


func test_price_of_normalises_formats() -> void:
	assert_eq(economy.price_of({"coins": 500}), {"coins": 500})
	assert_eq(economy.price_of({"gems": 20.0}), {"gems": 20}, "JSON floats become ints")
	assert_eq(economy.price_of({"currency": "gems", "amount": 15}), {"gems": 15})
	assert_eq(economy.price_of({"type": "coins", "value": 800}), {"coins": 800}, "cosmetic unlock form")
	assert_eq(economy.price_of({"coins": 300, "gems": 5}), {"coins": 300}, "coins win when both listed")
	assert_eq(economy.price_of({"coins": 0, "gems": 5}), {"gems": 5}, "a zero coin entry never makes it free")
	assert_eq(economy.price_of({"coins": "x", "gems": 5}), {"gems": 5}, "an invalid coin entry is ignored")
	assert_eq(economy.price_of({"gems": 0, "coins": 40}), {"coins": 40})
	assert_eq(economy.price_of({"coins": 0, "gems": 0}), {}, "both zero is free")
	assert_eq(economy.price_of({}), {}, "free")
	assert_eq(economy.price_of({"coins": 0}), {}, "zero is free")
	assert_eq(economy.price_of({"coins": -5}), {}, "negative rejected")
	assert_eq(economy.price_of({"coins": "lots"}), {}, "non-numeric rejected")
	assert_eq(economy.price_of({"type": "stars", "value": 30}), {}, "not a currency")
	assert_eq(economy.price_of({"type": "coins", "value": 12.5}), {}, "fractional rejected")


func test_sanitize_config_uses_fallbacks_for_bad_values() -> void:
	var config: Dictionary = (
		EconomyService
		. sanitize_config(
			{
				"max_single_grant": {"coins": -5, "gems": "many"},
				"balance_cap": "broken",
				"duplicate_cosmetic_coins": "abc",
				"starting": {"coins": 999999, "gems": -1},
				"integrity": [],
			}
		)
	)
	var max_grant: Dictionary = config[EconomyService.KEY_MAX_SINGLE_GRANT] as Dictionary
	assert_eq(int(max_grant["coins"]), int(EconomyService.FALLBACK_MAX_SINGLE_GRANT["coins"]))
	assert_eq(int(max_grant["gems"]), int(EconomyService.FALLBACK_MAX_SINGLE_GRANT["gems"]))
	var cap: Dictionary = config[EconomyService.KEY_BALANCE_CAP] as Dictionary
	assert_eq(int(cap["coins"]), int(EconomyService.FALLBACK_BALANCE_CAP["coins"]))
	assert_eq(int(config[EconomyService.KEY_DUPLICATE_COINS]), EconomyService.FALLBACK_DUPLICATE_COSMETIC_COINS)
	var starting: Dictionary = config[EconomyService.KEY_STARTING] as Dictionary
	assert_eq(int(starting["coins"]), int(max_grant["coins"]), "starting clamped to the grant limit")
	assert_eq(int(starting["gems"]), int(EconomyService.FALLBACK_STARTING["gems"]))
	var integrity: Dictionary = config[EconomyService.KEY_INTEGRITY] as Dictionary
	assert_eq(int(integrity[EconomyService.KEY_TIME_TRAVEL]), EconomyService.FALLBACK_TIME_TRAVEL_TOLERANCE)


func test_missing_config_file_falls_back_to_defaults() -> void:
	var config: Dictionary = EconomyService.load_config("res://data/economy/does_not_exist.json")
	var max_grant: Dictionary = config[EconomyService.KEY_MAX_SINGLE_GRANT] as Dictionary
	assert_eq(int(max_grant["coins"]), int(EconomyService.FALLBACK_MAX_SINGLE_GRANT["coins"]))
	var service: EconomyService = EconomyService.new(PlayerProfile.new(), null, null, config)
	assert_true(service.grant(COINS, 10, "test"), "works without bus or clock")
	assert_eq(service.balance(COINS), 10)


func test_null_profile_does_not_crash() -> void:
	var service: EconomyService = EconomyService.new(null, bus, clock)
	assert_true(service.grant(COINS, 10, "test"))
	assert_eq(service.balance(COINS), 10)


func test_ledger_label_keys_resolve_to_strings() -> void:
	var strings: Dictionary = JsonIO.read_dict("res://data/i18n/parts/economy.en.json")
	var cases: Dictionary = {
		"level:w01_l03": "economy.ledger.source.level",
		"daily_streak:4": "economy.ledger.source.daily_streak",
		"level:w02_l10:duplicate": "economy.ledger.source.duplicate",
		"level:w02_l10:ad_double": "economy.ledger.source.ad_double",
		"starting_balance": "economy.ledger.source.starting_balance",
		"purchase:core_fire": "economy.ledger.source.purchase",
		"cosmetic:core_fire": "economy.ledger.source.purchase",
		"achievement:first_clear": "economy.ledger.source.achievement",
		"mission:daily_play_3:ad_double": "economy.ledger.source.ad_double",
		"": "economy.ledger.source.other",
		"something_new:42": "economy.ledger.source.other",
	}
	for source: String in cases:
		var key: String = EconomyService.ledger_label_key(source)
		assert_eq(key, str(cases[source]), source)
		assert_has(strings, key, "label exists")
	for kind: String in EconomyService.LEDGER_LABEL_KINDS + EconomyService.LEDGER_LABEL_SUFFIXES:
		assert_has(strings, EconomyService.LEDGER_LABEL_KEY_PREFIX + kind)


func test_int_or_parses_json_numbers() -> void:
	assert_eq(EconomyService.int_or(12, -1), 12)
	assert_eq(EconomyService.int_or(12.0, -1), 12)
	assert_eq(EconomyService.int_or("34", -1), 34)
	assert_eq(EconomyService.int_or(1.5, -1), -1)
	assert_eq(EconomyService.int_or(INF, -1), -1)
	assert_eq(EconomyService.int_or(null, -1), -1)
	assert_eq(EconomyService.int_or([], -1), -1)
	assert_eq(EconomyService.int_or("-12", -1), -12)
	assert_eq(EconomyService.int_or("999999999999999999", -1), 999999999999999999, "18 digits fit")
	assert_eq(EconomyService.int_or("99999999999999999999999", -1), -1, "too large for 64 bits")
	assert_eq(EconomyService.int_or(true, -1), -1, "booleans are not numbers")
