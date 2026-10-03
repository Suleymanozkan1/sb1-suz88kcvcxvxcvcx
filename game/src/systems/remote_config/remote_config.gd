class_name RemoteConfig
extends RefCounted
## Typed, range-checked remote tunables with an offline cache.
##
## Every key is declared in data/config/remote_defaults.json with a type,
## optional range and a default. Overrides (from the network or the cache)
## are validated key by key: a value of the wrong type or out of range is
## rejected on its own while valid ones are kept. [method get_value] always
## returns a correctly typed, clamped value — the default when nothing valid
## was supplied — so gameplay never depends on being online.

signal applied(changed_keys: PackedStringArray)

const DEFAULT_PATH: String = "res://data/config/remote_defaults.json"
const CACHE_FORMAT: String = "flux_drop.remote_config"
const CACHE_VERSION: int = 1
const KIND_INT: String = "int"
const KIND_FLOAT: String = "float"
const KIND_BOOL: String = "bool"
const KIND_STRING: String = "string"
const KINDS: PackedStringArray = ["int", "float", "bool", "string"]
const FORMAT_URL: String = "url"
const SECURE_URL_PREFIX: String = "https://"
const DEFAULT_MAX_LENGTH: int = 256
const VALUES_KEY: String = "values"
const HTTP_GET: String = "GET"
## Largest float magnitude that still represents every integer exactly.
const MAX_EXACT_INT_FLOAT: float = 9007199254740992.0

## True when the last [method fetch] succeeded.
var last_fetch_ok: bool = false
## Keys rejected by the last [method apply_overrides] / fetch / cache load.
var last_rejected: PackedStringArray = PackedStringArray()
## key -> sanitised spec {"type", "default", optional "min", "max", "format", "max_length"}
var _schema: Dictionary = {}
var _overrides: Dictionary = {}
var _read: Callable = Callable()
var _write: Callable = Callable()


## [param defaults] is the parsed remote_defaults.json ({"schema": {...}}) or
## the schema dictionary itself. [param storage_read] is () -> String and
## [param storage_write] is (text: String) -> void; both may be invalid
## Callables, which simply disables caching.
func _init(defaults: Dictionary, storage_read: Callable = Callable(), storage_write: Callable = Callable()) -> void:
	_read = storage_read
	_write = storage_write
	var raw_schema: Variant = defaults.get("schema", defaults)
	if typeof(raw_schema) != TYPE_DICTIONARY:
		GameLog.error("remote_config", "schema block is not an object; no remote keys available")
		return
	for raw_key: Variant in raw_schema as Dictionary:
		var spec: Dictionary = RemoteConfig._sanitize_spec(str(raw_key), (raw_schema as Dictionary)[raw_key])
		if not spec.is_empty():
			_schema[str(raw_key)] = spec


## Reads the bundled defaults file (empty dictionary when unreadable).
static func load_defaults(path: String = DEFAULT_PATH) -> Dictionary:
	return JsonIO.read_dict(path)


## Cache reader for a file path, usable as the storage_read Callable.
static func file_reader(path: String) -> Callable:
	return func() -> String: return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


## Atomic cache writer for a file path, usable as the storage_write Callable.
static func file_writer(path: String) -> Callable:
	return func(text: String) -> void:
		var err: Error = JsonIO.write_atomic(path, text)
		if err != OK:
			GameLog.warn("remote_config", "cache write failed: %s" % error_string(err))


## Declared keys (sorted).
func keys() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray(_schema.keys())
	out.sort()
	return out


## True when [param key] is declared.
func has_key(key: String) -> bool:
	return _schema.has(key)


## True when a validated override (remote or cached) is active for [param key].
func has_override(key: String) -> bool:
	return _overrides.has(key)


## Declared type name of [param key] ("" when unknown).
func type_of(key: String) -> String:
	return str((_schema.get(key, {}) as Dictionary).get("type", ""))


## Typed, clamped value of [param key]; the default when no valid override
## exists; null (with a warning) for undeclared keys.
func get_value(key: String) -> Variant:
	if not _schema.has(key):
		GameLog.warn("remote_config", "unknown key '%s'" % key)
		return null
	var spec: Dictionary = _schema[key] as Dictionary
	var raw: Variant = _overrides.get(key, spec["default"])
	return RemoteConfig._clamped(spec, raw)


## Integer convenience accessor ([param fallback] for unknown or non-int keys).
func get_int(key: String, fallback: int = 0) -> int:
	var v: Variant = get_value(key)
	return int(v) if typeof(v) == TYPE_INT else fallback


## Float convenience accessor (ints are widened).
func get_float(key: String, fallback: float = 0.0) -> float:
	var v: Variant = get_value(key)
	return float(v) if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT else fallback


## Bool convenience accessor.
func get_bool(key: String, fallback: bool = false) -> bool:
	var v: Variant = get_value(key)
	return bool(v) if typeof(v) == TYPE_BOOL else fallback


## String convenience accessor.
func get_string(key: String, fallback: String = "") -> String:
	var v: Variant = get_value(key)
	return str(v) if typeof(v) == TYPE_STRING else fallback


## Copy of the active validated overrides.
func overrides() -> Dictionary:
	return _overrides.duplicate()


## Validates and merges [param values] into the active overrides. Each
## unknown, wrongly typed or out-of-range key is rejected individually; valid
## keys are kept. Returns the rejected keys.
func apply_overrides(values: Dictionary) -> PackedStringArray:
	return _apply(values, false)


## Drops every override (all keys back to defaults).
func reset_overrides() -> void:
	var changed: PackedStringArray = PackedStringArray(_overrides.keys())
	_overrides.clear()
	if not changed.is_empty():
		applied.emit(changed)


## Downloads a config snapshot with [param transport] (contract:
## (method, url, body) -> {"ok", "status", "body", "error"}). On success the
## snapshot replaces the previous overrides and is cached. Offline or invalid
## responses keep the current (cached or default) values. Returns success.
func fetch(transport: Callable, url: String) -> bool:
	last_fetch_ok = false
	if url.strip_edges().is_empty() or not transport.is_valid():
		return false
	var response: Variant = await transport.call(HTTP_GET, url, {})
	if typeof(response) != TYPE_DICTIONARY:
		GameLog.warn("remote_config", "transport returned no response object")
		return false
	var r: Dictionary = response as Dictionary
	if not (typeof(r.get("ok")) == TYPE_BOOL and bool(r["ok"])):
		GameLog.info("remote_config", "fetch failed (%s); keeping cached/default values" % str(r.get("error", "")))
		return false
	var values: Variant = RemoteConfig._extract_values(r.get("body"))
	if typeof(values) != TYPE_DICTIONARY:
		# Only a {"values": {...}} snapshot replaces the overrides: an error or
		# maintenance body must not silently reset every remote setting.
		GameLog.warn("remote_config", "fetch body is not a {\"values\": {...}} snapshot; ignored")
		return false
	var snapshot: Dictionary = values as Dictionary
	var usable: bool = snapshot.is_empty()
	for key: Variant in snapshot:
		usable = usable or typeof(validate(str(key), snapshot[key])) != TYPE_NIL
	if not usable:
		GameLog.warn("remote_config", "no usable value in the fetched snapshot; keeping the current values")
		return false
	_apply(snapshot, true)
	save_cache()
	last_fetch_ok = true
	return true


## Restores overrides from the cache. Corrupt or foreign data is ignored
## (defaults stay active). Returns true when a cache was applied.
func load_cache() -> bool:
	if not _read.is_valid():
		return false
	var text: Variant = _read.call()
	if typeof(text) != TYPE_STRING or (text as String).strip_edges().is_empty():
		return false
	var parsed: Variant = RemoteConfig._parse_json(text as String)
	if typeof(parsed) != TYPE_DICTIONARY:
		GameLog.warn("remote_config", "cache is corrupt; using defaults")
		return false
	var data: Dictionary = parsed as Dictionary
	if str(data.get("format", "")) != CACHE_FORMAT or typeof(data.get(VALUES_KEY)) != TYPE_DICTIONARY:
		GameLog.warn("remote_config", "cache has an unknown format; using defaults")
		return false
	_apply(data[VALUES_KEY] as Dictionary, true)
	return true


## Writes the active overrides to the cache. Returns false without a writer.
func save_cache() -> bool:
	if not _write.is_valid():
		return false
	var payload: Dictionary = {"format": CACHE_FORMAT, "version": CACHE_VERSION, VALUES_KEY: _overrides.duplicate()}
	_write.call(JsonIO.canonical(payload))
	return true


## Validated value for [param key], or null when it must be rejected.
func validate(key: String, value: Variant) -> Variant:
	if not _schema.has(key):
		return null
	return RemoteConfig._validated(_schema[key] as Dictionary, value)


func _apply(values: Dictionary, replace: bool) -> PackedStringArray:
	var rejected: PackedStringArray = PackedStringArray()
	var next: Dictionary = {} if replace else _overrides.duplicate()
	for raw_key: Variant in values:
		var key: String = str(raw_key)
		var clean: Variant = validate(key, values[raw_key])
		if typeof(clean) == TYPE_NIL:
			rejected.append(key)
		else:
			next[key] = clean
	var changed: PackedStringArray = PackedStringArray()
	for key: String in _schema:
		var before: Variant = _overrides.get(key)
		var after: Variant = next.get(key)
		if typeof(before) != typeof(after) or before != after:
			changed.append(key)
	_overrides = next
	last_rejected = rejected
	if not rejected.is_empty():
		GameLog.warn("remote_config", "rejected keys: %s" % ", ".join(rejected))
	if not changed.is_empty():
		applied.emit(changed)
	return rejected


## Parses JSON quietly (no engine error spam for corrupt input); null on failure.
static func _parse_json(text: String) -> Variant:
	var json: JSON = JSON.new()
	return json.data if json.parse(text) == OK else null


## The "values" object of a fetched {"values": {...}} body; null otherwise.
static func _extract_values(body: Variant) -> Variant:
	var data: Variant = body
	if typeof(data) == TYPE_STRING:
		data = RemoteConfig._parse_json(data as String)
	if typeof(data) == TYPE_DICTIONARY and typeof((data as Dictionary).get(VALUES_KEY)) == TYPE_DICTIONARY:
		return (data as Dictionary)[VALUES_KEY]
	return null


## Normalises one schema entry; returns {} (and logs) when unusable.
static func _sanitize_spec(key: String, raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		GameLog.error("remote_config", "%s: spec must be an object" % key)
		return {}
	var src: Dictionary = raw as Dictionary
	var kind: String = str(src.get("type", ""))
	if not KINDS.has(kind):
		GameLog.error("remote_config", "%s: unknown type '%s'" % [key, kind])
		return {}
	var spec: Dictionary = {"type": kind}
	if kind == KIND_INT or kind == KIND_FLOAT:
		for bound: String in ["min", "max"]:
			var b: Variant = src.get(bound)
			if typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT:
				spec[bound] = int(b) if kind == KIND_INT else float(b)
		if spec.has("min") and spec.has("max") and float(spec["min"]) > float(spec["max"]):
			GameLog.error("remote_config", "%s: min > max; range ignored" % key)
			spec.erase("min")
			spec.erase("max")
	elif kind == KIND_STRING:
		var raw_max: Variant = src.get("max_length", DEFAULT_MAX_LENGTH)
		var numeric_max: bool = typeof(raw_max) == TYPE_INT or typeof(raw_max) == TYPE_FLOAT
		spec["max_length"] = maxi(0, int(raw_max)) if numeric_max else DEFAULT_MAX_LENGTH
		spec["format"] = str(src.get("format", ""))
	var default_value: Variant = RemoteConfig._validated(spec, src.get("default"))
	if typeof(default_value) == TYPE_NIL:
		default_value = RemoteConfig._clamped(spec, RemoteConfig._zero(kind))
		GameLog.error("remote_config", "%s: invalid default; using %s" % [key, str(default_value)])
	spec["default"] = default_value
	return spec


## Strict validation: wrong type or out of range -> null.
static func _validated(spec: Dictionary, value: Variant) -> Variant:
	var out: Variant = null
	match str(spec["type"]):
		KIND_INT:
			if typeof(value) == TYPE_INT:
				out = value
			elif typeof(value) == TYPE_FLOAT:
				# JSON numbers arrive as floats; accept only exact integers.
				var f: float = value as float
				if is_finite(f) and f == floorf(f) and absf(f) <= MAX_EXACT_INT_FLOAT:
					out = int(f)
		KIND_FLOAT:
			if typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value as float)):
				out = float(value)
		KIND_BOOL:
			if typeof(value) == TYPE_BOOL:
				out = value
		KIND_STRING:
			out = RemoteConfig._validated_string(spec, value)
	if (typeof(out) == TYPE_INT or typeof(out) == TYPE_FLOAT) and not RemoteConfig._in_range(spec, float(out)):
		out = null
	return out


static func _validated_string(spec: Dictionary, value: Variant) -> Variant:
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		return null
	var s: String = str(value)
	if s.length() > int(spec.get("max_length", DEFAULT_MAX_LENGTH)):
		return null
	if str(spec.get("format", "")) == FORMAT_URL and not RemoteConfig.is_secure_url_or_empty(s):
		return null
	return s


## URLs from remote data must be empty (feature off) or HTTPS without spaces,
## naming one plain host (no credentials or "?"/"#" tricks before the path).
static func is_secure_url_or_empty(url: String) -> bool:
	if url.is_empty():
		return true
	var has_space: bool = url.contains(" ") or url.contains("\t") or url.contains("\n")
	return (
		url.begins_with(SECURE_URL_PREFIX)
		and url.length() > SECURE_URL_PREFIX.length()
		and not has_space
		and HttpTransport.has_plain_authority(url)
	)


static func _in_range(spec: Dictionary, v: float) -> bool:
	if spec.has("min") and v < float(spec["min"]):
		return false
	if spec.has("max") and v > float(spec["max"]):
		return false
	return true


## Defensive typed clamp used on read (values are validated on write already).
static func _clamped(spec: Dictionary, value: Variant) -> Variant:
	var out: Variant = value
	match str(spec["type"]):
		KIND_INT:
			var i: int = int(value) if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT else 0
			if spec.has("min"):
				i = maxi(i, int(spec["min"]))
			if spec.has("max"):
				i = mini(i, int(spec["max"]))
			out = i
		KIND_FLOAT:
			var f: float = float(value) if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT else 0.0
			if spec.has("min"):
				f = maxf(f, float(spec["min"]))
			if spec.has("max"):
				f = minf(f, float(spec["max"]))
			out = f
		KIND_BOOL:
			out = bool(value) if typeof(value) == TYPE_BOOL else false
		KIND_STRING:
			out = str(value) if typeof(value) == TYPE_STRING else ""
	return out


static func _zero(kind: String) -> Variant:
	var zeros: Dictionary = {KIND_INT: 0, KIND_FLOAT: 0.0, KIND_BOOL: false, KIND_STRING: ""}
	return zeros.get(kind)
