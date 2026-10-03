class_name HapticsService
extends RefCounted
## Short, rate-limited vibration feedback driven by data/haptics/patterns.json.
##
## Each pattern kind (tap, collect, perfect, hit, ...) has a duration, an
## amplitude and its own minimum interval; on top of that a global floor stops
## overlapping kinds from buzzing continuously. Gameplay feedback kinds without
## a pattern of their own are mapped through the document's "aliases". The
## player's "haptics" setting is respected on every call and battery saver
## scales the amplitude down. Vibration and time are injected so tests run
## without a device.

const LOG_CHANNEL: String = "haptics"
const DEFAULT_PATTERNS_PATH: String = "res://data/haptics/patterns.json"
const REQUIRED_KINDS: Array[StringName] = [
	&"tap", &"collect", &"perfect", &"hit", &"combo", &"complete",
	&"reward", &"near_miss", &"shatter", &"ui", &"fail",
]
const GLOBAL_MIN_INTERVAL_MS: int = 40
const BATTERY_SAVER_AMPLITUDE_SCALE: float = 0.5
const FEEDBACK_STRENGTH_FLOOR: float = 0.5
const MIN_DURATION_MS: int = 1
const MAX_DURATION_MS: int = 1000
const MAX_INTERVAL_MS: int = 10000
## Fallback values for a kind whose pattern data is missing or malformed.
const SAFE_DURATION_MS: int = 10
const SAFE_AMPLITUDE: float = 0.3
const SAFE_INTERVAL_MS: int = 100
const NEVER: int = -1

var _settings: SettingsService
var _vibrate: Callable
var _clock_ms: Callable
var _patterns: Dictionary = {}
var _aliases: Dictionary = {}
var _global_min_interval_ms: int = GLOBAL_MIN_INTERVAL_MS
var _battery_scale: float = BATTERY_SAVER_AMPLITUDE_SCALE
var _feedback_floor: float = FEEDBACK_STRENGTH_FLOOR
var _last_by_kind: Dictionary = {}
var _last_any_ms: int = NEVER
var _played: int = 0


## [param vibrate] is called as (duration_ms: int, amplitude: float); when not
## given it is [method Input.vibrate_handheld] on mobile and a no-op elsewhere.
## [param patterns] is either the whole patterns document or a plain kind->pattern
## map; empty loads [constant DEFAULT_PATTERNS_PATH]. [param clock_ms] returns the
## current time in milliseconds (defaults to [method Time.get_ticks_msec]).
func _init(
	settings: SettingsService,
	vibrate: Callable = Callable(),
	patterns: Dictionary = {},
	clock_ms: Callable = Callable(),
) -> void:
	_settings = settings
	_vibrate = vibrate
	if not _vibrate.is_valid() and AppInfo.is_mobile():
		_vibrate = Callable(Input, &"vibrate_handheld")
	_clock_ms = clock_ms if clock_ms.is_valid() else Callable(Time, &"get_ticks_msec")
	var doc: Dictionary = patterns if not patterns.is_empty() else JsonIO.read_dict(DEFAULT_PATTERNS_PATH)
	_load(doc)


## Problems found in a patterns document (empty when it is complete and valid).
static func validate_document(doc: Dictionary) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var map: Dictionary = _pattern_map(doc)
	for kind: StringName in REQUIRED_KINDS:
		if not map.has(String(kind)):
			problems.append("missing pattern '%s'" % kind)
	for key: Variant in map:
		var raw: Variant = map[key]
		if typeof(raw) != TYPE_DICTIONARY:
			problems.append("pattern '%s' is not an object" % str(key))
			continue
		var p: Dictionary = raw as Dictionary
		var d: float = _num(p, "duration_ms", -1.0)
		var a: float = _num(p, "amplitude", -1.0)
		var i: float = _num(p, "min_interval_ms", -1.0)
		if d < MIN_DURATION_MS or d > MAX_DURATION_MS:
			problems.append("pattern '%s' duration_ms out of range" % str(key))
		if a < 0.0 or a > 1.0:
			problems.append("pattern '%s' amplitude outside 0..1" % str(key))
		if i < 0.0 or i > MAX_INTERVAL_MS:
			problems.append("pattern '%s' min_interval_ms out of range" % str(key))
	var aliases: Variant = doc.get("aliases", {})
	if typeof(aliases) == TYPE_DICTIONARY:
		for alias: Variant in aliases as Dictionary:
			var target: String = str((aliases as Dictionary)[alias])
			if not map.has(target):
				problems.append("alias '%s' points to unknown pattern '%s'" % [str(alias), target])
	return problems


## Plays the pattern for [param kind] (or its alias) scaled by [param strength]
## (0..1). Returns true when a vibration was actually requested.
func play(kind: StringName, strength: float = 1.0) -> bool:
	if _settings == null or not _settings.get_bool("haptics") or is_nan(strength) or strength <= 0.0:
		return false
	var resolved: StringName = resolve(kind)
	if resolved == &"":
		return false
	var p: Dictionary = _patterns[resolved] as Dictionary
	var now: int = int(_clock_ms.call())
	if not _interval_elapsed(resolved, int(p["min_interval_ms"]), now):
		return false
	var amplitude: float = float(p["amplitude"]) * clampf(strength, 0.0, 1.0)
	if _settings.get_bool("battery_saver"):
		amplitude *= _battery_scale
	amplitude = clampf(amplitude, 0.0, 1.0)
	if amplitude <= 0.0:
		return false
	_last_by_kind[resolved] = now
	_last_any_ms = now
	_played += 1
	if _vibrate.is_valid():
		_vibrate.call(int(p["duration_ms"]), amplitude)
	return true


## Signal-compatible with [signal GameplayView.feedback]. Gameplay strengths are
## lifted above [member _feedback_floor] so light events are still perceptible.
func on_feedback(kind: StringName, strength: float, _pitch_step: int) -> void:
	play(kind, lerpf(_feedback_floor, 1.0, clampf(strength, 0.0, 1.0)))


## The pattern kind that [param kind] plays (itself, its alias, or &"" if none).
func resolve(kind: StringName) -> StringName:
	if _patterns.has(kind):
		return kind
	var alias: StringName = _aliases.get(kind, &"") as StringName
	return alias if _patterns.has(alias) else &""


## True when [param kind] (directly or via an alias) has a pattern.
func has_pattern(kind: StringName) -> bool:
	return resolve(kind) != &""


## A copy of the sanitised pattern for [param kind] (empty if none).
func pattern(kind: StringName) -> Dictionary:
	var resolved: StringName = resolve(kind)
	return (_patterns[resolved] as Dictionary).duplicate() if resolved != &"" else {}


## Number of vibrations requested so far.
func played_count() -> int:
	return _played


## Forgets rate-limit history (e.g. after returning from background).
func reset_rate_limits() -> void:
	_last_by_kind.clear()
	_last_any_ms = NEVER


## Per-kind interval and the global floor both have to have passed.
func _interval_elapsed(kind: StringName, min_interval_ms: int, now: int) -> bool:
	var last_kind: int = int(_last_by_kind.get(kind, NEVER))
	if last_kind != NEVER and now - last_kind < min_interval_ms:
		return false
	return _last_any_ms == NEVER or now - _last_any_ms >= _global_min_interval_ms


func _load(doc: Dictionary) -> void:
	var problems: PackedStringArray = validate_document(doc)
	for p: String in problems:
		GameLog.warn(LOG_CHANNEL, p)
	var map: Dictionary = _pattern_map(doc)
	for kind: StringName in REQUIRED_KINDS:
		if not map.has(String(kind)):
			_patterns[kind] = _sanitize({})
	for key: Variant in map:
		var raw: Variant = map[key]
		_patterns[StringName(str(key))] = _sanitize(raw as Dictionary if typeof(raw) == TYPE_DICTIONARY else {})
	var aliases: Variant = doc.get("aliases", {})
	if typeof(aliases) == TYPE_DICTIONARY:
		for alias: Variant in aliases as Dictionary:
			_aliases[StringName(str(alias))] = StringName(str((aliases as Dictionary)[alias]))
	_global_min_interval_ms = maxi(GLOBAL_MIN_INTERVAL_MS, int(_num(doc, "global_min_interval_ms",
		GLOBAL_MIN_INTERVAL_MS)))
	_battery_scale = clampf(_num(doc, "battery_saver_amplitude_scale", BATTERY_SAVER_AMPLITUDE_SCALE), 0.0, 1.0)
	_feedback_floor = clampf(_num(doc, "feedback_strength_floor", FEEDBACK_STRENGTH_FLOOR), 0.0, 1.0)


static func _sanitize(p: Dictionary) -> Dictionary:
	return {
		"duration_ms": clampi(int(_num(p, "duration_ms", SAFE_DURATION_MS)), MIN_DURATION_MS, MAX_DURATION_MS),
		"amplitude": clampf(_num(p, "amplitude", SAFE_AMPLITUDE), 0.0, 1.0),
		"min_interval_ms": clampi(int(_num(p, "min_interval_ms", SAFE_INTERVAL_MS)), 0, MAX_INTERVAL_MS),
	}


static func _pattern_map(doc: Dictionary) -> Dictionary:
	var nested: Variant = doc.get("patterns", null)
	if typeof(nested) == TYPE_DICTIONARY:
		return nested as Dictionary
	var out: Dictionary = {}
	for key: Variant in doc:
		if typeof(doc[key]) == TYPE_DICTIONARY and key != "aliases":
			out[key] = doc[key]
	return out


static func _num(d: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = d.get(key, fallback)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		var f: float = float(v)
		return fallback if is_nan(f) else f
	return fallback
