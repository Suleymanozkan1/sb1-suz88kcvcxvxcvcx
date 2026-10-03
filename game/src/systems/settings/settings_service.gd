class_name SettingsService
extends RefCounted
## Validated read/write access to the settings slice of [PlayerProfile].
##
## Keys and value types come from [constant PlayerProfile.DEFAULT_SETTINGS]; volumes
## must lie in 0..1 and enumerated settings (quality, language) must use a known
## value. Rejected writes are logged and never stored. Accepted changes are
## published on [signal changed] (for directly wired services such as
## [AudioService]) and on [signal EventBus.settings_changed].

## Emitted after a setting actually changed value.
signal changed(key: StringName, value: Variant)

const LOG_CHANNEL: String = "settings"
const QUALITY_VALUES: PackedStringArray = ["auto", "low", "medium", "high", "ultra"]
const LANGUAGE_VALUES: PackedStringArray = ["auto", "en", "tr"]
const VOLUME_KEYS: PackedStringArray = ["sfx_volume", "music_volume"]
const VOLUME_MIN: float = 0.0
const VOLUME_MAX: float = 1.0

var _profile: PlayerProfile
var _bus: EventBus


## Reads/writes [member PlayerProfile.settings] of [param profile]; changes are
## also published on [param bus] (may be null in tools and tests).
func _init(profile: PlayerProfile, bus: EventBus) -> void:
	if profile == null:
		GameLog.error(LOG_CHANNEL, "no profile injected; using an unsaved default profile")
		profile = PlayerProfile.new()
	_profile = profile
	_bus = bus
	_repair()


## Every known setting key, in [constant PlayerProfile.DEFAULT_SETTINGS] order.
static func keys() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for key: String in PlayerProfile.DEFAULT_SETTINGS:
		out.append(key)
	return out


## Returns true when [param value] is acceptable for [param key] (after int->float
## coercion for float settings and StringName->String for string settings).
static func is_valid(key: String, value: Variant) -> bool:
	return _validation_error(key, value).is_empty()


## The stored value for [param key], or null (with a warning) for unknown keys.
func get_value(key: String) -> Variant:
	if not PlayerProfile.DEFAULT_SETTINGS.has(key):
		GameLog.warn(LOG_CHANNEL, "unknown setting '%s'" % key)
		return null
	return _profile.settings.get(key, PlayerProfile.DEFAULT_SETTINGS[key])


## Typed convenience getter for boolean settings (false for unknown/mistyped keys).
func get_bool(key: String) -> bool:
	var v: Variant = get_value(key)
	return v as bool if typeof(v) == TYPE_BOOL else false


## Typed convenience getter for float settings (0.0 for unknown/mistyped keys).
func get_float(key: String) -> float:
	var v: Variant = get_value(key)
	return float(v) if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT else 0.0


## Typed convenience getter for string settings ("" for unknown/mistyped keys).
func get_string(key: String) -> String:
	var v: Variant = get_value(key)
	return v as String if typeof(v) == TYPE_STRING else ""


## Validates and stores a setting. Returns true when the value was accepted (also
## when it equals the current value, in which case nothing is emitted).
func set_value(key: String, value: Variant) -> bool:
	var problem: String = _validation_error(key, value)
	if not problem.is_empty():
		GameLog.warn(LOG_CHANNEL, "rejected %s=%s: %s" % [key, str(value), problem])
		return false
	var coerced: Variant = _coerce(key, value)
	var current: Variant = _profile.settings.get(key, PlayerProfile.DEFAULT_SETTINGS[key])
	if typeof(current) == typeof(coerced) and current == coerced:
		return true
	_profile.settings[key] = coerced
	_emit(key, coerced)
	return true


## Restores every setting to its default, emitting a change for each key that differed.
func reset_to_defaults() -> void:
	for key: String in PlayerProfile.DEFAULT_SETTINGS:
		var def: Variant = PlayerProfile.DEFAULT_SETTINGS[key]
		var current: Variant = _profile.settings.get(key, def)
		_profile.settings[key] = def
		if typeof(current) != typeof(def) or current != def:
			_emit(key, def)


## A copy of all settings (defaults filled in).
func snapshot() -> Dictionary:
	var out: Dictionary = {}
	for key: String in PlayerProfile.DEFAULT_SETTINGS:
		out[key] = get_value(key)
	return out


static func _validation_error(key: String, value: Variant) -> String:
	if not PlayerProfile.DEFAULT_SETTINGS.has(key):
		return "unknown key"
	var expected: int = typeof(PlayerProfile.DEFAULT_SETTINGS[key])
	var actual: int = typeof(value)
	var numeric_ok: bool = expected == TYPE_FLOAT and actual == TYPE_INT
	var string_ok: bool = expected == TYPE_STRING and actual == TYPE_STRING_NAME
	if actual != expected and not numeric_ok and not string_ok:
		return "expected %s, got %s" % [type_string(expected), type_string(actual)]
	if VOLUME_KEYS.has(key):
		var f: float = float(value)
		if is_nan(f) or f < VOLUME_MIN or f > VOLUME_MAX:
			return "volume outside %.1f..%.1f" % [VOLUME_MIN, VOLUME_MAX]
	if key == "quality" and not QUALITY_VALUES.has(str(value)):
		return "unknown quality preset"
	if key == "language" and not LANGUAGE_VALUES.has(str(value)):
		return "unsupported language"
	return ""


## Stores floats as float (ints accepted) and strings as String (StringName accepted).
static func _coerce(key: String, value: Variant) -> Variant:
	match typeof(PlayerProfile.DEFAULT_SETTINGS[key]):
		TYPE_FLOAT:
			return float(value)
		TYPE_STRING:
			return str(value)
	return value


## Replaces stored values that are present but invalid (e.g. out-of-range volumes
## from an old or tampered save) with defaults. Runs silently at construction.
func _repair() -> void:
	for key: String in PlayerProfile.DEFAULT_SETTINGS:
		if not _profile.settings.has(key):
			_profile.settings[key] = PlayerProfile.DEFAULT_SETTINGS[key]
			continue
		var stored: Variant = _profile.settings[key]
		if not is_valid(key, stored):
			GameLog.warn(LOG_CHANNEL, "repaired invalid stored %s=%s" % [key, str(stored)])
			_profile.settings[key] = PlayerProfile.DEFAULT_SETTINGS[key]
		else:
			_profile.settings[key] = _coerce(key, stored)


func _emit(key: String, value: Variant) -> void:
	var name: StringName = StringName(key)
	changed.emit(name, value)
	if _bus != null:
		_bus.settings_changed.emit(name, value)
