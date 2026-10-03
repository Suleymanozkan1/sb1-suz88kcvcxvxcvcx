class_name IntegrityMonitor
extends RefCounted
## Read-only consistency checks over the wallet and its ledger.
##
## The result tags analytics events and online submissions for review. This
## is detection only: it never changes the profile, never blocks play and
## never takes anything away from the player, so a false positive (for
## example a device whose clock was corrected) costs the player nothing.

const LEDGER_MISMATCH: String = "ledger_mismatch"
const NEGATIVE_BALANCE: String = "negative_balance"
const IMPLAUSIBLE_BALANCE: String = "implausible_balance"
const TIME_TRAVEL: String = "time_travel"
## Order in which [method check] lists codes.
const CODE_ORDER: Array[String] = [LEDGER_MISMATCH, NEGATIVE_BALANCE, IMPLAUSIBLE_BALANCE, TIME_TRAVEL]

## Sentinel for a ledger field that is missing or not a whole number.
const INVALID: int = -1

## Evidence for the anomalies found by the last [method check]; one entry per
## finding, e.g. {"code": "ledger_mismatch", "currency": "coins",
## "expected": 120, "actual": 9999}.
var last_details: Array[Dictionary] = []

var _profile: PlayerProfile
var _config: Dictionary
var _clock: GameClock


## [param config_data] is the economy config (default file when empty). With a
## [param clock], a newest ledger entry dated more than the tolerance in the
## future (device clock moved back) is also reported as time travel.
func _init(profile: PlayerProfile, config_data: Dictionary = {}, clock: GameClock = null) -> void:
	_profile = profile
	_clock = clock
	if config_data.is_empty():
		_config = EconomyService.load_config()
	else:
		_config = EconomyService.sanitize_config(config_data)


## Returns the anomaly codes found now (each code at most once, in a stable
## order): ledger_mismatch, negative_balance, implausible_balance, time_travel.
## An empty array means nothing suspicious.
func check() -> Array[String]:
	last_details = []
	var codes: Array[String] = []
	if _profile == null:
		return codes
	var last_logged: Dictionary = _last_logged_balances()
	var caps: Dictionary = _config[EconomyService.KEY_BALANCE_CAP] as Dictionary
	for currency: StringName in EconomyService.CURRENCIES:
		var key: String = String(currency)
		var current: int = _balance(currency)
		if last_logged.has(key) and int(last_logged[key]) != current:
			_report(codes, LEDGER_MISMATCH, {"currency": key, "expected": last_logged[key], "actual": current})
		if current < 0:
			_report(codes, NEGATIVE_BALANCE, {"currency": key, "actual": current})
		if current > int(caps.get(key, 0)):
			_report(codes, IMPLAUSIBLE_BALANCE, {"currency": key, "actual": current, "cap": caps.get(key, 0)})
	_check_time_travel(codes)
	var ordered: Array[String] = []
	for code: String in CODE_ORDER:
		if codes.has(code):
			ordered.append(code)
	return ordered


## True when [method check] finds nothing.
func is_clean() -> bool:
	return check().is_empty()


func _balance(currency: StringName) -> int:
	return _profile.coins if currency == EconomyService.COINS else _profile.gems


## Balance recorded by the newest well-formed ledger entry of each currency.
func _last_logged_balances() -> Dictionary:
	var out: Dictionary = {}
	for i: int in range(_profile.ledger.size() - 1, -1, -1):
		var entry: Dictionary = _profile.ledger[i]
		var key: String = str(entry.get(EconomyService.LEDGER_CURRENCY, ""))
		if out.has(key) or not EconomyService.is_currency(StringName(key)):
			continue
		if not entry.has(EconomyService.LEDGER_BALANCE):
			continue
		var logged: Variant = entry[EconomyService.LEDGER_BALANCE]
		var value: int = EconomyService.int_or(logged, INVALID)
		# Two different fallbacks agree only when the value really parsed.
		if value != EconomyService.int_or(logged, 0):
			continue
		out[key] = value
	return out


func _check_time_travel(codes: Array[String]) -> void:
	var tolerance: int = int((_config[EconomyService.KEY_INTEGRITY] as Dictionary)[EconomyService.KEY_TIME_TRAVEL])
	var previous: int = INVALID
	for entry: Dictionary in _profile.ledger:
		var stamp: int = EconomyService.int_or(entry.get(EconomyService.LEDGER_TIME), INVALID)
		if stamp < 0:
			continue
		if previous >= 0 and stamp < previous - tolerance:
			_report(codes, TIME_TRAVEL, {"from": previous, "to": stamp})
		previous = stamp
	if _clock != null and previous >= 0 and previous > _clock.now_unix() + tolerance:
		_report(codes, TIME_TRAVEL, {"from": previous, "to": _clock.now_unix()})


func _report(codes: Array[String], code: String, detail: Dictionary) -> void:
	if not codes.has(code):
		codes.append(code)
	var entry: Dictionary = detail.duplicate()
	entry["code"] = code
	last_details.append(entry)
