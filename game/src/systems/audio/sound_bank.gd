class_name SoundBank
extends RefCounted
## Data-driven catalogue of sound effects, music stems and stingers
## (data/audio/sound_bank.json).
##
## Parsing never fails: malformed entries are sanitised to safe values and every
## issue (missing kinds, missing files, bad fields) is collected in
## [member problems]. Streams are loaded lazily and cached.

const LOG_CHANNEL: String = "audio"
const DEFAULT_PATH: String = "res://data/audio/sound_bank.json"
## Every feedback kind the game can request (gameplay feedback + UI/meta).
const REQUIRED_KINDS: Array[StringName] = [
	&"tap", &"phase", &"dash", &"denied", &"surge", &"collect", &"prism", &"miss",
	&"near_miss", &"shatter", &"chain", &"gate", &"shield_break", &"bump", &"fail",
	&"perfect", &"complete", &"form", &"portal", &"current", &"pickup", &"overdrive",
	&"overdrive_end", &"combo", &"ui_click", &"ui_back", &"reward", &"star", &"coin",
	&"level_up", &"unlock",
]
const REQUIRED_STINGERS: Array[StringName] = [&"level_complete", &"perfect_fanfare"]
const MENU_TRACK: String = "menu"
const SFX_BUSES: Array[StringName] = [&"SFX", &"UI"]
const DEFAULT_BUS: StringName = &"SFX"
const MIN_VOLUME_DB: float = -60.0
const MAX_VOLUME_DB: float = 12.0
const MAX_PITCH_STEP: float = 12.0
const MAX_JITTER: float = 2.0
const MIN_VOICES: int = 4
const MAX_VOICES: int = 32
const MIN_BPM: float = 40.0
const MAX_BPM: float = 240.0
const DEFAULT_BARS: int = 8
const BEATS_PER_BAR: int = 4
const SHIMMER_KEY: String = "shimmer"
## Mixer defaults, used for any field missing from the document.
const DEFAULT_MIXER: Dictionary = {
	"voices": 12,
	"max_pitch_semitones": 12.0,
	"strength_floor": 0.5,
	"bus_base_db": {"Music": -4.0, "SFX": 0.0, "UI": -2.0},
	"music_fade_s": 0.8,
	"intensity_response": 4.0,
	"intensity_full_combo": 20,
	"base_volume_db": 0.0,
	"hi_volume_db": -3.0,
	"stinger_duck_db": -10.0,
	"stinger_duck_release_s": 0.6,
	"limiter_ceiling_db": -0.5,
	"shimmer": {"kinds": [], "min_step": 10, "semitones": 12.0, "volume_db": -12.0},
}

## Validation issues found while parsing (empty for a healthy bank).
var problems: PackedStringArray = PackedStringArray()
var source_path: String = ""
var _sfx: Dictionary = {}
var _music: Dictionary = {}
var _stingers: Dictionary = {}
var _mixer: Dictionary = {}
var _streams: Dictionary = {}


## Builds a bank from an already parsed document (see [method from_file]).
func _init(data: Dictionary = {}, source: String = "") -> void:
	source_path = source
	_parse(data)


## Loads and validates a bank file. A missing/corrupt file yields an empty bank
## whose [member problems] explain why.
static func from_file(path: String = DEFAULT_PATH) -> SoundBank:
	var data: Dictionary = JsonIO.read_dict(path)
	var bank: SoundBank = SoundBank.new(data, path)
	if data.is_empty():
		bank.problems.insert(0, "sound bank %s missing or unreadable" % path)
	for p: String in bank.problems:
		GameLog.warn(LOG_CHANNEL, p)
	return bank


## True when no problems were found.
func is_valid() -> bool:
	return problems.is_empty()


## Every resource path referenced by the bank that does not exist.
func missing_files() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for path: String in all_files():
		if not ResourceLoader.exists(path) and not out.has(path):
			out.append(path)
	return out


## Every resource path referenced by the bank (sfx, music stems, stingers).
func all_files() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for kind: StringName in _sfx:
		out.append(str((_sfx[kind] as Dictionary)["file"]))
	for track: String in _music:
		var m: Dictionary = _music[track] as Dictionary
		for stem: String in ["base", "hi", "boss"]:
			if not str(m.get(stem, "")).is_empty():
				out.append(str(m[stem]))
	for s: StringName in _stingers:
		out.append(str((_stingers[s] as Dictionary)["file"]))
	return out


## Sound effect kinds defined in the bank.
func kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	for kind: StringName in _sfx:
		out.append(kind)
	return out


## True when [param kind] has an entry.
func has_kind(kind: StringName) -> bool:
	return _sfx.has(kind)


## Sanitised entry {file, volume_db, pitch_step, bus, max_polyphony, jitter} or {}.
func sfx(kind: StringName) -> Dictionary:
	return _sfx.get(kind, {}) as Dictionary


## Music track ids ("menu" and world ids).
func tracks() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for track: String in _music:
		out.append(track)
	return out


## Sanitised music entry {base, hi, boss, bpm, boss_bpm, bars} or {}.
func music(track: String) -> Dictionary:
	return _music.get(track, {}) as Dictionary


## Stinger entry {file, volume_db} or {}.
func stinger(stinger_name: StringName) -> Dictionary:
	return _stingers.get(stinger_name, {}) as Dictionary


## A mixer tunable (falls back to [constant DEFAULT_MIXER]).
func mixer(key: String) -> Variant:
	return _mixer.get(key, DEFAULT_MIXER.get(key))


## Float mixer tunable.
func mixer_float(key: String) -> float:
	var v: Variant = mixer(key)
	return float(v) if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT else 0.0


## Sanitised combo shimmer layer config: {"kinds": Array[StringName], "min_step": int,
## "semitones": float, "volume_db": float}. Always well-typed, whatever the data said.
func shimmer() -> Dictionary:
	return _mixer[SHIMMER_KEY] as Dictionary


## Number of pooled sfx voices.
func voices() -> int:
	return clampi(int(mixer_float("voices")), MIN_VOICES, MAX_VOICES)


## Loads (and caches) the stream for a sound effect kind; null when unavailable.
func sfx_stream(kind: StringName) -> AudioStream:
	var entry: Dictionary = sfx(kind)
	return null if entry.is_empty() else stream_at(str(entry["file"]))


## Loads (and caches) a stream by resource path; null when missing or not audio.
func stream_at(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if _streams.has(path):
		return _streams[path] as AudioStream
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = ResourceLoader.load(path) as AudioStream
	if stream == null:
		GameLog.warn(LOG_CHANNEL, "cannot load audio stream %s" % path)
	_streams[path] = stream
	return stream


## Loads every sound effect up front so the first play never hitches. Returns
## the number of streams available.
func preload_sfx() -> int:
	var count: int = 0
	for kind: StringName in _sfx:
		if sfx_stream(kind) != null:
			count += 1
	return count


func _parse(data: Dictionary) -> void:
	_mixer = DEFAULT_MIXER.duplicate(true)
	var mixer_raw: Variant = data.get("mixer", {})
	if typeof(mixer_raw) == TYPE_DICTIONARY:
		for key: Variant in mixer_raw as Dictionary:
			var k: String = str(key)
			if _mixer.has(k) and _same_kind(_mixer[k], (mixer_raw as Dictionary)[key]):
				_mixer[k] = (mixer_raw as Dictionary)[key]
			else:
				problems.append("mixer.%s ignored (unknown or wrong type)" % k)
	_parse_sfx(_dict(data.get("sfx", {})))
	_mixer[SHIMMER_KEY] = _parse_shimmer(_mixer[SHIMMER_KEY])
	_parse_music(_dict(data.get("music", {})))
	_parse_stingers(_dict(data.get("stingers", {})))
	for path: String in missing_files():
		problems.append("missing file %s" % path)


## Nested shimmer fields are only type-checked at the top level by the mixer
## merge, so every field is validated here (a string "kinds" or a non-numeric
## "semitones" would otherwise break every play_sfx call).
func _parse_shimmer(raw: Variant) -> Dictionary:
	var defaults: Dictionary = DEFAULT_MIXER[SHIMMER_KEY] as Dictionary
	var src: Dictionary = _dict(raw)
	var kinds: Array[StringName] = []
	var raw_kinds: Variant = src.get("kinds", [])
	if typeof(raw_kinds) == TYPE_ARRAY:
		for item: Variant in raw_kinds as Array:
			var kind: StringName = StringName(str(item))
			if typeof(item) != TYPE_STRING or not _sfx.has(kind):
				problems.append("mixer.shimmer.kinds: '%s' is not a sound effect kind" % str(item))
			elif not kinds.has(kind):
				kinds.append(kind)
	else:
		problems.append("mixer.shimmer.kinds must be a list")
	for key: String in ["min_step", "semitones", "volume_db"]:
		var v: Variant = src.get(key, defaults[key])
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			problems.append("mixer.shimmer.%s must be a number" % key)
	return {
		"kinds": kinds,
		"min_step": maxi(0, int(_num(src, "min_step", float(defaults["min_step"])))),
		"semitones": clampf(_num(src, "semitones", float(defaults["semitones"])), -MAX_PITCH_STEP, MAX_PITCH_STEP),
		"volume_db": clampf(_num(src, "volume_db", float(defaults["volume_db"])), MIN_VOLUME_DB, MAX_VOLUME_DB),
	}


func _parse_sfx(raw: Dictionary) -> void:
	for key: Variant in raw:
		var e: Dictionary = _dict(raw[key])
		var kind: StringName = StringName(str(key))
		var file: String = str(e.get("file", ""))
		if file.is_empty():
			problems.append("sfx.%s has no file" % kind)
			continue
		var bus: StringName = StringName(str(e.get("bus", DEFAULT_BUS)))
		if not SFX_BUSES.has(bus):
			problems.append("sfx.%s bus '%s' unknown" % [kind, bus])
			bus = DEFAULT_BUS
		_sfx[kind] = {
			"file": file,
			"volume_db": clampf(_num(e, "volume_db", 0.0), MIN_VOLUME_DB, MAX_VOLUME_DB),
			"pitch_step": clampf(_num(e, "pitch_step", 0.0), 0.0, MAX_PITCH_STEP),
			"bus": bus,
			"max_polyphony": clampi(int(_num(e, "max_polyphony", 1.0)), 1, MAX_VOICES),
			"jitter": clampf(_num(e, "jitter", 0.0), 0.0, MAX_JITTER),
		}
	for kind: StringName in REQUIRED_KINDS:
		if not _sfx.has(kind):
			problems.append("sfx kind '%s' missing" % kind)


func _parse_music(raw: Dictionary) -> void:
	for key: Variant in raw:
		var e: Dictionary = _dict(raw[key])
		var track: String = str(key)
		var base: String = str(e.get("base", ""))
		if base.is_empty():
			problems.append("music.%s has no base stem" % track)
			continue
		var bpm: float = _num(e, "bpm", 0.0)
		if bpm < MIN_BPM or bpm > MAX_BPM:
			problems.append("music.%s bpm %s out of range" % [track, str(bpm)])
			bpm = clampf(bpm, MIN_BPM, MAX_BPM)
		var boss_bpm: float = _num(e, "boss_bpm", bpm)
		_music[track] = {
			"base": base,
			"hi": str(e.get("hi", "")),
			"boss": str(e.get("boss", "")),
			"bpm": bpm,
			"boss_bpm": clampf(boss_bpm, MIN_BPM, MAX_BPM),
			"bars": maxi(1, int(_num(e, "bars", DEFAULT_BARS))),
		}
	if not _music.has(MENU_TRACK):
		problems.append("music.%s missing" % MENU_TRACK)


func _parse_stingers(raw: Dictionary) -> void:
	for key: Variant in raw:
		var e: Dictionary = _dict(raw[key])
		var file: String = str(e.get("file", ""))
		if file.is_empty():
			problems.append("stinger.%s has no file" % str(key))
			continue
		_stingers[StringName(str(key))] = {
			"file": file,
			"volume_db": clampf(_num(e, "volume_db", 0.0), MIN_VOLUME_DB, MAX_VOLUME_DB),
		}
	for s: StringName in REQUIRED_STINGERS:
		if not _stingers.has(s):
			problems.append("stinger '%s' missing" % s)


static func _dict(v: Variant) -> Dictionary:
	return v as Dictionary if typeof(v) == TYPE_DICTIONARY else {}


static func _num(d: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = d.get(key, fallback)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		var f: float = float(v)
		return fallback if is_nan(f) or is_inf(f) else f
	return fallback


static func _same_kind(a: Variant, b: Variant) -> bool:
	var numeric: Array[int] = [TYPE_INT, TYPE_FLOAT]
	if numeric.has(typeof(a)) and numeric.has(typeof(b)):
		return true
	return typeof(a) == typeof(b)
