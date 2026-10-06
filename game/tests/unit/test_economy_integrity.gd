extends TestCase
## IntegrityMonitor: detection of edited balances, negatives, implausible
## values and clock jumps, without ever touching the profile.

const NOW: int = 1790000000
const DAY: int = 86400
const COINS: StringName = EconomyService.COINS
const GEMS: StringName = EconomyService.GEMS

var profile: PlayerProfile
var clock: GameClock
var economy: EconomyService
var monitor: IntegrityMonitor


func before_each() -> void:
	profile = PlayerProfile.new()
	clock = GameClock.new()
	clock.set_fixed_unix(NOW)
	economy = EconomyService.new(profile, EventBus.new(), clock)
	monitor = IntegrityMonitor.new(profile)


## Simulates saving to disk: JSON turns every number into a float.
func _through_json(data: Dictionary) -> PlayerProfile:
	return PlayerProfile.from_dict(JSON.parse_string(JSON.stringify(data)) as Dictionary)


func test_clean_profiles_have_no_anomalies() -> void:
	assert_empty(monitor.check(), "fresh profile")
	economy.apply_starting_balance()
	economy.grant(COINS, 250, "level:w01_l01")
	economy.grant(GEMS, 3, "daily_streak:3")
	economy.spend(COINS, 300, "purchase:trail_helix")
	assert_empty(monitor.check(), "normal play")
	assert_true(monitor.is_clean())
	assert_empty(monitor.last_details)


func test_detects_edited_coin_balance() -> void:
	economy.grant(COINS, 120, "level:w01_l01")
	profile.coins = 99999
	var codes: Array[String] = monitor.check()
	assert_eq(codes, [IntegrityMonitor.LEDGER_MISMATCH] as Array[String])
	assert_eq(monitor.last_details.size(), 1)
	var detail: Dictionary = monitor.last_details[0]
	assert_eq(detail["currency"], "coins")
	assert_eq(detail["expected"], 120)
	assert_eq(detail["actual"], 99999)


func test_detects_edited_gem_balance_after_save_round_trip() -> void:
	economy.grant(GEMS, 4, "daily_streak:4")
	economy.grant(COINS, 60, "level:w01_l02")
	var data: Dictionary = profile.to_dict()
	data["gems"] = 500
	var codes: Array[String] = IntegrityMonitor.new(_through_json(data)).check()
	assert_has(codes, IntegrityMonitor.LEDGER_MISMATCH, "JSON floats in the ledger still compare")
	var untouched: PlayerProfile = _through_json(profile.to_dict())
	assert_empty(IntegrityMonitor.new(untouched).check(), "an honest save round trip stays clean")


func test_mismatch_uses_newest_entry_per_currency() -> void:
	economy.grant(COINS, 100, "a")
	economy.spend(COINS, 40, "b")
	economy.grant(GEMS, 2, "c")
	assert_empty(monitor.check(), "older coin entries are not compared")
	profile.coins = 100
	assert_has(monitor.check(), IntegrityMonitor.LEDGER_MISMATCH, "restoring an old balance is detected")


func test_balance_without_ledger_entries_is_not_flagged() -> void:
	profile.gems = 7
	assert_empty(monitor.check(), "older saves without a ledger are not accused")


func test_detects_negative_balance() -> void:
	profile.coins = -50
	var codes: Array[String] = monitor.check()
	assert_has(codes, IntegrityMonitor.NEGATIVE_BALANCE)
	assert_false(codes.has(IntegrityMonitor.LEDGER_MISMATCH), "no ledger entry to compare")


func test_detects_implausible_balance() -> void:
	var cap: int = economy.balance_cap(COINS)
	profile.coins = cap + 1
	assert_eq(monitor.check(), [IntegrityMonitor.IMPLAUSIBLE_BALANCE] as Array[String])
	profile.coins = cap
	assert_empty(monitor.check(), "the cap itself is plausible")
	var strict: IntegrityMonitor = IntegrityMonitor.new(profile, {"balance_cap": {"coins": 1000, "gems": 10}})
	profile.coins = 1001
	assert_has(strict.check(), IntegrityMonitor.IMPLAUSIBLE_BALANCE, "cap comes from config")


func test_detects_time_travel_in_ledger() -> void:
	economy.grant(COINS, 10, "a")
	clock.set_fixed_unix(NOW - DAY - 1)
	economy.grant(COINS, 10, "b")
	assert_eq(monitor.check(), [IntegrityMonitor.TIME_TRAVEL] as Array[String])
	var detail: Dictionary = monitor.last_details[0]
	assert_eq(detail["from"], NOW)
	assert_eq(detail["to"], NOW - DAY - 1)


func test_small_clock_corrections_are_tolerated() -> void:
	economy.grant(COINS, 10, "a")
	clock.set_fixed_unix(NOW - DAY + 60)
	economy.grant(COINS, 10, "b")
	clock.set_fixed_unix(NOW + 5 * DAY)
	economy.grant(COINS, 10, "c")
	assert_empty(monitor.check(), "going back less than a day, or forward, is fine")


func test_future_ledger_entry_detected_with_clock() -> void:
	economy.grant(COINS, 10, "a")
	var with_clock: IntegrityMonitor = IntegrityMonitor.new(profile, {}, clock)
	assert_empty(with_clock.check())
	clock.set_fixed_unix(NOW - 3 * DAY)
	assert_has(with_clock.check(), IntegrityMonitor.TIME_TRAVEL, "device clock moved back")
	assert_empty(monitor.check(), "without a clock only the ledger order is checked")


func test_codes_are_unique_and_ordered() -> void:
	economy.grant(COINS, 10, "a")
	economy.grant(GEMS, 1, "b")
	clock.set_fixed_unix(NOW - 2 * DAY)
	economy.grant(GEMS, 1, "c")
	profile.coins = -1
	profile.gems = 9999999
	var codes: Array[String] = monitor.check()
	var expected: Array[String] = [
		IntegrityMonitor.LEDGER_MISMATCH,
		IntegrityMonitor.NEGATIVE_BALANCE,
		IntegrityMonitor.IMPLAUSIBLE_BALANCE,
		IntegrityMonitor.TIME_TRAVEL,
	]
	assert_eq(codes, expected)
	assert_eq(monitor.last_details.size(), 5, "details keep every finding (2 coin, 2 gem, 1 clock)")


func test_check_never_modifies_profile() -> void:
	economy.grant(COINS, 50, "a")
	profile.coins = 123456
	profile.gems = -3
	var before: String = JSON.stringify(profile.to_dict(), "", true)
	monitor.check()
	monitor.check()
	assert_eq(JSON.stringify(profile.to_dict(), "", true), before)
	assert_eq(profile.coins, 123456, "nothing is taken away")


func test_malformed_ledger_entries_are_ignored() -> void:
	profile.coins = 40
	profile.ledger.append({"c": "coins", "b": "forty", "t": "yesterday"})
	profile.ledger.append({"c": "tokens", "b": 1, "t": NOW})
	profile.ledger.append({"t": NOW})
	assert_empty(monitor.check(), "unparseable entries are skipped, not accused")
	profile.ledger.append({"c": "coins", "b": 40.0, "t": float(NOW)})
	assert_empty(monitor.check(), "float values from JSON are understood")
	profile.ledger.append({"c": "coins", "b": 41, "t": NOW})
	assert_has(monitor.check(), IntegrityMonitor.LEDGER_MISMATCH)


func test_null_profile_is_safe() -> void:
	var empty: IntegrityMonitor = IntegrityMonitor.new(null)
	assert_empty(empty.check())
