class_name AnalyticsSchema
extends RefCounted
## Parsed analytics schema (data/analytics/events.json) with privacy guards.
##
## Only declared events can be recorded and only their declared, typed
## parameters survive [method sanitize_params]. Parameter names that match a
## forbidden pattern (email, name, ip, ...) are refused twice: when the schema
## is loaded (so a bad data edit cannot open a PII channel) and when an event
## is tracked. String values that look like an e-mail or IP address are dropped.

const DEFAULT_PATH: String = "res://data/analytics/events.json"
const PARAM_STRING: String = "string"
const PARAM_INT: String = "int"
const PARAM_FLOAT: String = "float"
const PARAM_BOOL: String = "bool"
const PARAM_TYPES: PackedStringArray = ["string", "int", "float", "bool"]
const DEFAULT_MAX_PARAMS: int = 16
const DEFAULT_MAX_STRING_LENGTH: int = 80
const MAX_EVENT_NAME_LENGTH: int = 40
## Patterns shorter than this only match whole name tokens, so "ip" blocks
## "user_ip" but not "multiplier"; longer ones match anywhere in the name.
const SHORT_PATTERN_LENGTH: int = 4
## Floats beyond this magnitude are not converted to int (precision loss).
const MAX_SAFE_INT_FLOAT: float = 9.0e15
const DEFAULT_FORBIDDEN: PackedStringArray = [
	"email",
	"name",
	"phone",
	"device_id",
	"imei",
	"advertising_id",
	"ip",
	"lat",
	"lon",
	"address",
]
const TRUE_WORDS: PackedStringArray = ["true", "yes", "1"]
const FALSE_WORDS: PackedStringArray = ["false", "no", "0"]
const EMAIL_REGEX: String = "[^@\\s]+@[^@\\s]+\\.[^@\\s]+"
const IPV4_REGEX: String = "\\b\\d{1,3}(\\.\\d{1,3}){3}\\b"
const IPV6_REGEX: String = "\\b[0-9a-fA-F]{1,4}(:[0-9a-fA-F]{0,4}){4,7}\\b"

## event name -> {param name -> type name}
var events: Dictionary = {}
var forbidden_patterns: PackedStringArray = DEFAULT_FORBIDDEN.duplicate()
var max_params: int = DEFAULT_MAX_PARAMS
var max_string_length: int = DEFAULT_MAX_STRING_LENGTH
## Raw "limits" block (sink sizes etc.), read through [method limit].
var limits: Dictionary = {}
## Problems found while loading (forbidden or badly typed declarations).
var load_issues: PackedStringArray = PackedStringArray()
var _pii_patterns: Array[RegEx] = []


func _init() -> void:
	for source: String in [EMAIL_REGEX, IPV4_REGEX, IPV6_REGEX]:
		var re: RegEx = RegEx.new()
		if re.compile(source) == OK:
			_pii_patterns.append(re)


## Loads the bundled schema; an unreadable file yields an empty schema
## (every event is then rejected, which is the safe failure mode).
static func load_default(path: String = DEFAULT_PATH) -> AnalyticsSchema:
	var data: Dictionary = JsonIO.read_dict(path)
	if data.is_empty():
		GameLog.error("analytics", "schema %s missing or invalid; analytics disabled" % path)
	return AnalyticsSchema.from_dict(data)


## Builds a schema from parsed JSON, skipping anything malformed or unsafe.
static func from_dict(data: Dictionary) -> AnalyticsSchema:
	var schema: AnalyticsSchema = AnalyticsSchema.new()
	var patterns: Variant = data.get("forbidden_param_patterns", null)
	if typeof(patterns) == TYPE_ARRAY:
		# Data may add patterns but never remove the built-in ones.
		for raw: Variant in patterns as Array:
			var p: String = str(raw).strip_edges().to_lower()
			if not p.is_empty() and not schema.forbidden_patterns.has(p):
				schema.forbidden_patterns.append(p)
	var raw_limits: Variant = data.get("limits", {})
	if typeof(raw_limits) == TYPE_DICTIONARY:
		schema.limits = (raw_limits as Dictionary).duplicate()
	schema.max_params = maxi(1, schema.limit("max_params", DEFAULT_MAX_PARAMS))
	schema.max_string_length = maxi(1, schema.limit("max_string_length", DEFAULT_MAX_STRING_LENGTH))
	var raw_events: Variant = data.get("events", {})
	if typeof(raw_events) != TYPE_DICTIONARY:
		schema.load_issues.append("events block missing")
		return schema
	for raw_name: Variant in raw_events as Dictionary:
		schema._add_event(str(raw_name), (raw_events as Dictionary)[raw_name])
	for issue: String in schema.load_issues:
		GameLog.error("analytics", "schema: %s" % issue)
	return schema


## True when [param event] is declared.
func has_event(event: String) -> bool:
	return events.has(event)


## Declared parameters of [param event] as {name: type}; empty when unknown.
func param_types(event: String) -> Dictionary:
	return (events.get(event, {}) as Dictionary).duplicate()


## Integer limit from the "limits" block with a fallback for missing/bad data.
func limit(key: String, fallback: int) -> int:
	var v: Variant = limits.get(key, fallback)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return int(v)
	return fallback


## True when a parameter name could carry personal data.
func is_forbidden_param(param: String) -> bool:
	var tokens: PackedStringArray = AnalyticsSchema.name_tokens(param)
	var joined: String = "".join(tokens)
	for pattern: String in forbidden_patterns:
		var needle: String = "".join(AnalyticsSchema.name_tokens(pattern))
		if needle.is_empty():
			continue
		if needle.length() < SHORT_PATTERN_LENGTH:
			if tokens.has(needle):
				return true
		elif joined.contains(needle):
			return true
	return false


## True when a string value looks like an e-mail or IP address.
func looks_like_pii(value: String) -> bool:
	for re: RegEx in _pii_patterns:
		if re.search(value) != null:
			return true
	return false


## Returns only declared, non-forbidden params of [param event], each coerced
## to its declared type. Anything else is dropped (and logged).
func sanitize_params(event: String, params: Dictionary) -> Dictionary:
	var types: Dictionary = events.get(event, {}) as Dictionary
	var out: Dictionary = {}
	for raw_key: Variant in params:
		var key: String = str(raw_key)
		if is_forbidden_param(key):
			GameLog.warn("analytics", "%s: forbidden param '%s' dropped" % [event, key])
			continue
		if not types.has(key):
			GameLog.debug("analytics", "%s: undeclared param '%s' dropped" % [event, key])
			continue
		if out.size() >= max_params:
			GameLog.warn("analytics", "%s: more than %d params, '%s' dropped" % [event, max_params, key])
			continue
		var value: Variant = AnalyticsSchema.coerce(params[raw_key], str(types[key]), max_string_length)
		if typeof(value) == TYPE_NIL:
			GameLog.warn("analytics", "%s: param '%s' has an unusable value, dropped" % [event, key])
			continue
		if typeof(value) == TYPE_STRING and looks_like_pii(value as String):
			GameLog.warn("analytics", "%s: param '%s' looks like personal data, dropped" % [event, key])
			continue
		out[key] = value
	return out


## Converts [param value] to the declared [param type_name]. Returns null when
## the value cannot be represented faithfully (objects, NaN, "abc" as int...).
static func coerce(value: Variant, type_name: String, max_length: int = DEFAULT_MAX_STRING_LENGTH) -> Variant:
	var out: Variant = null
	match type_name:
		PARAM_STRING:
			out = AnalyticsSchema._coerce_string(value, max_length)
		PARAM_INT:
			out = AnalyticsSchema._coerce_int(value)
		PARAM_FLOAT:
			out = AnalyticsSchema._coerce_float(value)
		PARAM_BOOL:
			out = AnalyticsSchema._coerce_bool(value)
	return out


## Lower-case name tokens split on separators and camelCase boundaries
## ("userIP_address" -> ["user", "ip", "address"]).
static func name_tokens(text: String) -> PackedStringArray:
	var tokens: PackedStringArray = PackedStringArray()
	var current: String = ""
	var prev_lower: bool = false
	for i: int in text.length():
		var ch: String = text[i]
		var is_alnum: bool = ch.is_valid_identifier() or ch.is_valid_int()
		if not is_alnum or ch == "_":
			if not current.is_empty():
				tokens.append(current.to_lower())
			current = ""
			prev_lower = false
			continue
		var is_upper: bool = ch != ch.to_lower()
		if is_upper and prev_lower and not current.is_empty():
			tokens.append(current.to_lower())
			current = ""
		current += ch
		prev_lower = not is_upper
	if not current.is_empty():
		tokens.append(current.to_lower())
	return tokens


func _add_event(event: String, raw_spec: Variant) -> void:
	if event.is_empty() or event.length() > MAX_EVENT_NAME_LENGTH or not event.is_valid_identifier():
		load_issues.append("invalid event name '%s'" % event)
		return
	var declared: Dictionary = {}
	if typeof(raw_spec) == TYPE_DICTIONARY:
		var raw_params: Variant = (raw_spec as Dictionary).get("params", {})
		if typeof(raw_params) == TYPE_DICTIONARY:
			declared = raw_params as Dictionary
		else:
			load_issues.append("%s: params must be an object" % event)
	else:
		load_issues.append("%s: definition must be an object" % event)
	var params: Dictionary = {}
	for raw_param: Variant in declared:
		var param: String = str(raw_param)
		var type_name: String = str(declared[raw_param])
		if is_forbidden_param(param):
			load_issues.append("%s.%s matches a forbidden pattern; removed" % [event, param])
		elif not PARAM_TYPES.has(type_name):
			load_issues.append("%s.%s has unknown type '%s'; removed" % [event, param, type_name])
		else:
			params[param] = type_name
	events[event] = params


static func _coerce_string(value: Variant, max_length: int) -> Variant:
	var out: Variant = null
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME, TYPE_INT, TYPE_BOOL:
			out = str(value)
		TYPE_FLOAT:
			if is_finite(value as float):
				out = str(value)
	if typeof(out) == TYPE_STRING:
		out = (out as String).left(maxi(1, max_length))
	return out


static func _coerce_int(value: Variant) -> Variant:
	var out: Variant = null
	match typeof(value):
		TYPE_INT:
			out = value
		TYPE_BOOL:
			out = 1 if value else 0
		TYPE_FLOAT:
			out = AnalyticsSchema._float_to_int(value as float)
		TYPE_STRING, TYPE_STRING_NAME:
			var s: String = str(value).strip_edges()
			if s.is_valid_int():
				out = s.to_int()
			elif s.is_valid_float():
				out = AnalyticsSchema._float_to_int(s.to_float())
	return out


static func _float_to_int(f: float) -> Variant:
	if not is_finite(f) or absf(f) > MAX_SAFE_INT_FLOAT:
		return null
	return roundi(f)


static func _coerce_float(value: Variant) -> Variant:
	var out: Variant = null
	match typeof(value):
		TYPE_FLOAT:
			out = value
		TYPE_INT:
			out = float(value)
		TYPE_BOOL:
			out = 1.0 if value else 0.0
		TYPE_STRING, TYPE_STRING_NAME:
			var s: String = str(value).strip_edges()
			if s.is_valid_float():
				out = s.to_float()
	if typeof(out) == TYPE_FLOAT and not is_finite(out as float):
		out = null
	return out


static func _coerce_bool(value: Variant) -> Variant:
	var out: Variant = null
	match typeof(value):
		TYPE_BOOL:
			out = value
		TYPE_INT:
			out = int(value) != 0
		TYPE_FLOAT:
			if is_finite(value as float):
				out = float(value) != 0.0
		TYPE_STRING, TYPE_STRING_NAME:
			var s: String = str(value).strip_edges().to_lower()
			if TRUE_WORDS.has(s):
				out = true
			elif FALSE_WORDS.has(s):
				out = false
	return out
