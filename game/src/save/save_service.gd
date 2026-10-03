class_name SaveService
extends RefCounted
## Versioned, corruption-safe persistence of the [PlayerProfile].
##
## Every save is an envelope
## [code]{"format", "version", "saved_at", "checksum", "payload"}[/code] where
## checksum = SHA-256 hex of [code]JsonIO.canonical(payload) + CHECKSUM_SALT[/code],
## computed over the payload exactly as JSON parsing returns it.
## [br][br]
## Two slots are kept: [constant MAIN] and [constant BACKUP]. Before MAIN is
## replaced, its current text is copied to BACKUP, but only when it is itself a
## valid save, so a damaged MAIN can never overwrite a good backup. Loading
## tries MAIN, then BACKUP, then starts a new profile. Nothing a newer game
## version wrote is overwritten: such a file is renamed to
## [constant FUTURE] (or a numbered slot) and kept. A damaged MAIN is kept as [constant QUARANTINE]
## for support instead of being silently discarded.
## [br][br]
## The checksum detects storage damage and casual edits; it is not a security
## boundary (the salt ships with the game), and [method PlayerProfile.from_dict]
## still sanitises every loaded value.

## Emitted after a successful save with the size of the written envelope in bytes.
signal saved(bytes: int)
## Emitted when the main save could not be used: "backup" when the backup was
## loaded, "new" when save files existed but none was usable.
signal recovered(source: String)

enum Probe { MISSING, VALID, FUTURE, CORRUPT }

const MAIN: String = "profile.json"
const BACKUP: String = "profile.bak.json"
## Where a save written by a newer game version is kept untouched.
const FUTURE: String = "profile.future.json"
## Additional slots used when [constant FUTURE] already holds a different file.
const FUTURE_SLOT_PATTERN: String = "profile.future.%d.json"
const FUTURE_SLOTS: int = 8
## Where an unreadable main save is kept for diagnosis.
const QUARANTINE: String = "profile.corrupt.json"
const FORMAT: String = "fluxdrop-save"
const CHECKSUM_SALT: String = "fluxdrop/save-envelope/v1/7f3c19d2a8e54b60"
const CURRENT_VERSION: int = SaveMigrations.CURRENT_VERSION
const SLOTS: PackedStringArray = [MAIN, BACKUP]

const SOURCE_MAIN: String = "main"
const SOURCE_BACKUP: String = "backup"
const SOURCE_NEW: String = "new"
const SOURCE_MIGRATED: String = "migrated"

## Saves larger than this are refused both ways (a runaway list, not a profile).
const MAX_SAVE_CHARS: int = 16 * 1024 * 1024
## Deepest JSON nesting walked when normalising values (guards the call stack).
const MAX_NESTING: int = 64
## Integral JSON numbers up to 2^53 are restored as exact ints.
const MAX_EXACT_INT: float = 9007199254740992.0
## How JSON.stringify spells +/-infinity; seeing it triggers the slow sanitiser.
const INFINITY_LITERAL: String = "e99999"

## Translation keys the UI shows for each [signal recovered] source.
const RECOVERY_TEXT_KEYS: Dictionary = {
	SOURCE_BACKUP: "save.recovered.backup",
	SOURCE_NEW: "save.recovered.new",
}
## Translation key shown when [member preserved_future] is set.
const FUTURE_TEXT_KEY: String = "save.future.kept"
## Translation key shown when [method save_profile] fails.
const WRITE_FAILED_TEXT_KEY: String = "save.write_failed"

## Where the last [method load_profile] got its data: "main", "backup", "new" or "migrated".
var last_load_source: String = ""
## Problems found by the last load or save (empty when everything was clean).
var last_errors: PackedStringArray = PackedStringArray()
## True when the in-memory profile has changes that are not on disk yet.
var dirty: bool = false
## Entry name a newer-version save was moved to by the last load or save ("" if none).
var preserved_future: String = ""

var _storage: SaveStorage
var _clock: GameClock
## Text currently in MAIN that this service wrote or verified ("" if unknown);
## lets a save skip re-verifying its own previous output.
var _known_main: String = ""


## [param storage] holds the save entries; [param clock] stamps saves and new
## profiles. Missing dependencies fall back to memory-only storage and the
## system clock so the game still runs (without persistence).
func _init(storage: SaveStorage, clock: GameClock) -> void:
	_storage = storage
	_clock = clock
	if _storage == null:
		GameLog.error("save", "no save storage injected; progress will not persist")
		_storage = MemorySaveStorage.new()
	if _clock == null:
		_clock = GameClock.new()


## Loads the best available profile. Never fails: falls back to the backup,
## then to a brand-new profile. See [member last_load_source].
func load_profile() -> PlayerProfile:
	last_errors = PackedStringArray()
	last_load_source = ""
	preserved_future = ""
	_known_main = ""
	var damaged: bool = false
	for slot: String in SLOTS:
		var probe: Dictionary = _probe(slot)
		match probe["state"] as int:
			Probe.VALID:
				if slot == MAIN:
					_known_main = str(probe["text"])
				return _adopt(slot, probe["decoded"] as Dictionary)
			Probe.FUTURE:
				damaged = true
				_preserve_future(slot, str(probe["text"]))
			Probe.CORRUPT:
				damaged = true
				if slot == MAIN:
					_quarantine(slot)
	return _start_new(damaged)


## Writes [param profile] atomically. The previous main save becomes the
## backup first (only if it is valid). On failure the previous files stay
## intact, [member dirty] stays set and the error is returned.
func save_profile(profile: PlayerProfile) -> Error:
	last_errors = PackedStringArray()
	if profile == null:
		_note("save_profile called without a profile")
		return ERR_INVALID_PARAMETER
	var text: String = encode(profile, _clock.now_unix())
	var err: Error = OK
	if text.is_empty() or text.length() > MAX_SAVE_CHARS:
		_note("profile could not be encoded (%d chars)" % text.length())
		err = ERR_INVALID_DATA
	if err == OK:
		err = _protect_previous()
	if err == OK:
		err = _storage.write_text(MAIN, text)
	if err == OK and _storage.read_text(MAIN) != text:
		err = ERR_FILE_CORRUPT
	if err != OK:
		dirty = true
		_known_main = ""
		_note("saving %s failed: %s" % [MAIN, error_string(err)])
		return err
	dirty = false
	_known_main = text
	saved.emit(text.to_utf8_buffer().size())
	return OK


## Flags the profile as changed; the next [method flush_if_dirty] writes it.
func mark_dirty() -> void:
	dirty = true


## Debounced save: writes only when something changed since the last
## successful save. Many [method mark_dirty] calls coalesce into one write.
func flush_if_dirty(profile: PlayerProfile) -> Error:
	if not dirty:
		return OK
	return save_profile(profile)


## Serialises [param profile] into a current-version save envelope.
static func encode(profile: PlayerProfile, now_unix: int) -> String:
	if profile == null:
		return ""
	return encode_payload(profile.to_dict(), CURRENT_VERSION, now_unix)


## Wraps an arbitrary payload dictionary in a checksummed envelope of the
## given version (used by [method encode]; tools and tests use it to produce
## older or newer save versions). Returns "" if the payload cannot be
## represented as JSON.
static func encode_payload(payload: Dictionary, version: int, now_unix: int) -> String:
	# Fast path stays in native code; only payloads holding infinities (or
	# anything JSON cannot round-trip) go through the GDScript sanitiser.
	var payload_text: String = JsonIO.canonical(payload)
	var parsed: Variant = null
	if not payload_text.contains(INFINITY_LITERAL):
		parsed = JSON.parse_string(payload_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		payload_text = JsonIO.canonical(_json_safe(payload, 0))
		parsed = JSON.parse_string(payload_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		GameLog.error("save", "payload cannot be encoded as JSON")
		return ""
	# Same text JsonIO.canonical(envelope) yields, without re-serialising the payload.
	return "{\"checksum\":%s,\"format\":%s,\"payload\":%s,\"saved_at\":%d,\"version\":%d}" % [
		JSON.stringify(_checksum(parsed as Dictionary)),
		JSON.stringify(FORMAT),
		payload_text,
		maxi(0, now_unix),
		version,
	]


## Parses and verifies a save. Returns
## [code]{"ok", "payload", "version", "saved_at", "error"}[/code]. A file from a
## newer version reports ok=false with its [code]version[/code] set so callers
## can tell it apart from damage. A bare legacy v0 object (no envelope) is
## accepted as version 0.
static func decode(text: String) -> Dictionary:
	return _decode(text, true)


## [method decode] with optional int restoring ([param restore_numbers] false
## when only validity matters, which skips a full walk of the payload).
static func _decode(text: String, restore_numbers: bool) -> Dictionary:
	var out: Dictionary = {"ok": false, "payload": {}, "version": -1, "saved_at": 0, "error": ""}
	var problem: String = ""
	var json: JSON = JSON.new()
	if text.strip_edges().is_empty():
		problem = "empty save"
	elif text.length() > MAX_SAVE_CHARS:
		problem = "save is too large (%d chars)" % text.length()
	elif json.parse(text) != OK:
		problem = "unparseable JSON (line %d: %s)" % [json.get_error_line(), json.get_error_message()]
	elif typeof(json.data) != TYPE_DICTIONARY:
		problem = "save root is not an object"
	elif _is_legacy_shape(json.data as Dictionary):
		out["version"] = SaveMigrations.LEGACY_VERSION
		out["payload"] = json.data
	else:
		problem = _read_envelope(json.data as Dictionary, out)
	out["error"] = problem
	out["ok"] = problem.is_empty()
	if not problem.is_empty():
		out["payload"] = {}
	elif restore_numbers:
		_restore_numbers(out["payload"], 0)
	return out


func _probe(slot: String) -> Dictionary:
	var text: String = _storage.read_text(slot)
	var probe: Dictionary = {"state": Probe.MISSING, "text": text, "decoded": {}}
	if text.is_empty():
		if _storage.exists(slot):
			_note("%s: empty or unreadable" % slot)
			probe["state"] = Probe.CORRUPT
		return probe
	var decoded: Dictionary = decode(text)
	probe["decoded"] = decoded
	if decoded["ok"] as bool:
		probe["state"] = Probe.VALID
		return probe
	_note("%s: %s" % [slot, str(decoded["error"])])
	probe["state"] = Probe.FUTURE if (decoded["version"] as int) > CURRENT_VERSION else Probe.CORRUPT
	return probe


func _adopt(slot: String, decoded: Dictionary) -> PlayerProfile:
	var version: int = decoded["version"] as int
	var payload: Dictionary = decoded["payload"] as Dictionary
	if version < CURRENT_VERSION:
		payload = SaveMigrations.migrate(payload, version)
		if not payload.has("created_at"):
			var saved_at: int = decoded["saved_at"] as int
			payload["created_at"] = saved_at if saved_at > 0 else _clock.now_unix()
	var profile: PlayerProfile = PlayerProfile.from_dict(payload)
	if slot == BACKUP:
		last_load_source = SOURCE_BACKUP
	elif version < CURRENT_VERSION:
		last_load_source = SOURCE_MIGRATED
	else:
		last_load_source = SOURCE_MAIN
	# Anything but a clean main load should be rewritten in the current format.
	dirty = last_load_source != SOURCE_MAIN
	if last_load_source == SOURCE_MIGRATED:
		GameLog.info("save", "migrated save from v%d to v%d" % [version, CURRENT_VERSION])
	if slot == BACKUP:
		_note("%s unusable; restored from %s" % [MAIN, BACKUP])
		recovered.emit(SOURCE_BACKUP)
	return profile


func _start_new(damaged: bool) -> PlayerProfile:
	var profile: PlayerProfile = PlayerProfile.create_new(_clock.now_unix())
	last_load_source = SOURCE_NEW
	dirty = true
	if damaged:
		GameLog.error("save", "no usable save found; starting a new profile")
		recovered.emit(SOURCE_NEW)
	return profile


## Prepares the slots before MAIN is replaced: a valid MAIN is copied to the
## backup, a newer-version MAIN is moved aside, a damaged MAIN is quarantined.
func _protect_previous() -> Error:
	var current: String = _storage.read_text(MAIN)
	if current.is_empty():
		return OK
	var decoded: Dictionary = {"ok": true, "version": CURRENT_VERSION}
	if current != _known_main:
		decoded = _decode(current, false)
	if decoded["ok"] as bool:
		var backup_err: Error = _storage.write_text(BACKUP, current)
		if backup_err != OK:
			# MAIN is still written atomically, so the save itself can proceed.
			_note("backup copy failed: %s" % error_string(backup_err))
		return OK
	if (decoded["version"] as int) > CURRENT_VERSION:
		return OK if _preserve_future(MAIN, current) else ERR_ALREADY_EXISTS
	_quarantine(MAIN)
	return OK


func _preserve_future(slot: String, text: String) -> bool:
	var target: String = _future_slot_for(text)
	var err: Error = _storage.rename(slot, target)
	if err != OK:
		_note("could not keep newer-version save %s: %s" % [slot, error_string(err)])
		return false
	preserved_future = target
	GameLog.warn("save", "%s was written by a newer game version; kept as %s" % [slot, target])
	return true


## First future slot that is free or already holds this exact text; when all
## are taken the last slot is reused so the newest file is still kept.
func _future_slot_for(text: String) -> String:
	var candidate: String = FUTURE
	for i: int in FUTURE_SLOTS:
		candidate = FUTURE if i == 0 else FUTURE_SLOT_PATTERN % i
		if not _storage.exists(candidate) or _storage.read_text(candidate) == text:
			return candidate
	return candidate


func _quarantine(slot: String) -> void:
	var err: Error = _storage.rename(slot, QUARANTINE)
	if err != OK:
		_note("could not quarantine damaged %s: %s" % [slot, error_string(err)])
	else:
		GameLog.warn("save", "kept damaged %s as %s" % [slot, QUARANTINE])


func _note(message: String) -> void:
	last_errors.append(message)
	GameLog.warn("save", message)


static func _read_envelope(root: Dictionary, out: Dictionary) -> String:
	if typeof(root.get("format")) != TYPE_STRING or str(root["format"]) != FORMAT:
		return "wrong format '%s'" % str(root.get("format", ""))
	var version: int = _whole_number(root.get("version"))
	if version < 0:
		return "invalid version '%s'" % str(root.get("version", ""))
	out["version"] = version
	out["saved_at"] = maxi(0, _whole_number(root.get("saved_at")))
	if version > CURRENT_VERSION:
		return "save version %d is newer than supported version %d" % [version, CURRENT_VERSION]
	var payload: Variant = root.get("payload")
	if typeof(payload) != TYPE_DICTIONARY:
		return "missing payload"
	if str(root.get("checksum", "")).to_lower() != _checksum(payload as Dictionary):
		return "checksum mismatch"
	out["payload"] = payload
	return ""


## A pre-envelope v0 save: a bare object with numeric coins and a stars map.
static func _is_legacy_shape(root: Dictionary) -> bool:
	if root.has("format") or root.has("payload"):
		return false
	var coins_type: int = typeof(root.get("coins"))
	return (coins_type == TYPE_INT or coins_type == TYPE_FLOAT) and typeof(root.get("stars")) == TYPE_DICTIONARY


## SHA-256 hex of [code]JsonIO.canonical(payload) + CHECKSUM_SALT[/code]. The
## payload must be in parsed-JSON form (numbers as floats) on both the writing
## and the reading side, because ints and integral floats serialise differently.
static func _checksum(payload: Dictionary) -> String:
	var canonical: String = JsonIO.canonical(payload)
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((canonical + CHECKSUM_SALT).to_utf8_buffer())
	return ctx.finish().hex_encode()


## Non-negative whole number from a parsed JSON value, or -1.
static func _whole_number(value: Variant) -> int:
	var result: int = -1
	if typeof(value) == TYPE_INT:
		result = value as int
	elif typeof(value) == TYPE_FLOAT:
		var f: float = value as float
		if is_finite(f) and f == floorf(f) and absf(f) <= MAX_EXACT_INT:
			result = int(f)
	return result if result >= 0 else -1


## Makes a value JSON-representable: non-finite floats become 0, keys become
## strings, packed arrays become arrays, engine objects are dropped.
static func _json_safe(value: Variant, depth: int) -> Variant:
	if depth > MAX_NESTING:
		return null
	var t: int = typeof(value)
	var out: Variant = null
	if t == TYPE_FLOAT:
		out = value if is_finite(value as float) else 0.0
	elif t == TYPE_DICTIONARY:
		var dict: Dictionary = {}
		for key: Variant in value as Dictionary:
			dict[str(key)] = _json_safe((value as Dictionary)[key], depth + 1)
		out = dict
	elif t >= TYPE_ARRAY and t < TYPE_MAX:
		var list: Array = []
		for item: Variant in value:
			list.append(_json_safe(item, depth + 1))
		out = list
	elif t == TYPE_NIL or t == TYPE_BOOL or t == TYPE_INT or t == TYPE_STRING:
		out = value
	elif t != TYPE_OBJECT and t != TYPE_CALLABLE and t != TYPE_SIGNAL and t != TYPE_RID:
		out = str(value)
	return out


## Turns parsed JSON numbers back into ints where they are whole (JSON parsing
## yields floats only) and replaces non-finite numbers with 0. Works in place on
## freshly parsed containers; scalars are handled inline to keep it fast.
static func _restore_numbers(container: Variant, depth: int) -> void:
	if depth > MAX_NESTING:
		return
	if typeof(container) == TYPE_DICTIONARY:
		var dict: Dictionary = container as Dictionary
		for key: Variant in dict:
			var item: Variant = dict[key]
			var t: int = typeof(item)
			if t == TYPE_FLOAT:
				dict[key] = _number_from_json(item as float)
			elif t == TYPE_DICTIONARY or t == TYPE_ARRAY:
				_restore_numbers(item, depth + 1)
	elif typeof(container) == TYPE_ARRAY:
		var list: Array = container as Array
		for i: int in list.size():
			var t: int = typeof(list[i])
			if t == TYPE_FLOAT:
				list[i] = _number_from_json(list[i] as float)
			elif t == TYPE_DICTIONARY or t == TYPE_ARRAY:
				_restore_numbers(list[i], depth + 1)


static func _number_from_json(f: float) -> Variant:
	if f == floorf(f) and absf(f) <= MAX_EXACT_INT:
		return int(f)
	return f if is_finite(f) else 0.0
