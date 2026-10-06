class_name AnalyticsService
extends RefCounted
## Privacy-first event tracking.
##
## - Consent: while [member enabled] is false nothing is recorded or sent, and
##   switching it off clears whatever the sinks still hold.
## - Schema: unknown events are rejected; undeclared or forbidden parameters
##   (email, name, ip, ...) are dropped; values are coerced to declared types.
## - Enrichment: every event gets {"ts", "session", "app_version", "platform",
##   "seq"} plus the opaque random install id. The session id is random per
##   launch. No device identifiers, advertising ids or locations are collected.
## - [member context] (e.g. current level id) is merged into error reports only.

const ERROR_EVENT: StringName = &"error_reported"
const SESSION_ID_BYTES: int = 8
const MAX_INSTALL_ID_LENGTH: int = 64
const INSTALL_ID_CHARSET: String = "0123456789abcdefABCDEF-_"
## Logger error types (Logger.ErrorType order) -> analytics "kind".
const ERROR_KINDS: PackedStringArray = ["error", "warning", "script", "shader"]
const UNKNOWN_ERROR_KIND: String = "unknown"

## Analytics consent. When false nothing is recorded or sent.
var enabled: bool = true:
	set = _set_enabled
## Extra fields (level_id, state, screen) merged into error reports only.
var context: Dictionary = {}
var install_id: String = ""
var session_id: String = ""
var schema: AnalyticsSchema = null
## Number of events rejected (unknown event name) since launch.
var rejected_count: int = 0
var _clock: GameClock = null
var _sinks: Array[AnalyticsSink] = []
var _seq: int = 0
var _app_version: String = ""
var _platform: String = ""


func _init(install: String, clock: GameClock, schema_data: Dictionary = {}) -> void:
	install_id = _sanitize_install_id(install)
	_clock = clock if clock != null else GameClock.new()
	schema = AnalyticsSchema.from_dict(schema_data) if not schema_data.is_empty() else AnalyticsSchema.load_default()
	session_id = Crypto.new().generate_random_bytes(SESSION_ID_BYTES).hex_encode()
	_app_version = AppInfo.version()
	_platform = AppInfo.platform()


## Registers a destination for recorded events (duplicates are ignored).
func add_sink(sink: AnalyticsSink) -> void:
	if sink != null and not _sinks.has(sink):
		_sinks.append(sink)


## Registered sinks.
func sinks() -> Array[AnalyticsSink]:
	return _sinks.duplicate()


## Records [param event] with sanitised [param params]. Returns false when the
## event was not recorded (consent off or unknown event).
func track(event: StringName, params: Dictionary = {}) -> bool:
	var source: Dictionary = params
	if event == ERROR_EVENT and not context.is_empty():
		source = context.duplicate()
		source.merge(params, true)
	return _record(event, source)


## Asks every sink to deliver what it buffered. Returns true when all sinks
## report nothing pending. Does nothing without consent.
func flush() -> bool:
	if not enabled:
		return false
	var all_delivered: bool = true
	for sink: AnalyticsSink in _sinks.duplicate():
		var delivered: bool = await sink.flush()
		all_delivered = all_delivered and delivered
	return all_delivered


## Converts [ErrorReporter] reports into "error_reported" events. Only the
## error kind, script file name (no directories) and line are kept; messages
## are never sent because they may contain paths or user input. Identical
## errors are aggregated with a count. The live [member context] is not added:
## the reports come from an earlier session and carry their own context.
## Returns the number of events tracked.
func track_error_reports(reports: Array[Dictionary]) -> int:
	var grouped: Dictionary[String, Dictionary] = {}
	var order: Array[String] = []
	for report: Dictionary in reports:
		var raw_err: Variant = report.get("error", {})
		var err: Dictionary = raw_err as Dictionary if typeof(raw_err) == TYPE_DICTIONARY else {}
		# Reports are read back from disk: any field may be corrupt or hostile.
		var error_type: int = AnalyticsService._int_or(err.get("error_type"), -1)
		var kind: String = UNKNOWN_ERROR_KIND
		if error_type >= 0 and error_type < ERROR_KINDS.size():
			kind = ERROR_KINDS[error_type]
		var raw_file: Variant = err.get("file", "")
		var file_name: String = (raw_file as String).get_file() if typeof(raw_file) == TYPE_STRING else ""
		var where: String = "%s:%d" % [file_name, AnalyticsService._int_or(err.get("line"), 0)]
		var group_key: String = kind + "|" + where
		if not grouped.has(group_key):
			var params: Dictionary = {"kind": kind, "where": where, "error_type": error_type, "count": 0}
			var extra: Variant = report.get("context", {})
			if typeof(extra) == TYPE_DICTIONARY:
				for k: Variant in extra as Dictionary:
					if not params.has(str(k)):
						params[str(k)] = (extra as Dictionary)[k]
			grouped[group_key] = params
			order.append(group_key)
		var entry: Dictionary = grouped[group_key]
		entry["count"] = int(entry["count"]) + 1
	var tracked: int = 0
	for group_key: String in order:
		if _record(ERROR_EVENT, grouped[group_key]):
			tracked += 1
	return tracked


## Validates, sanitises, enriches and dispatches one event.
func _record(event: StringName, source: Dictionary) -> bool:
	if not enabled:
		return false
	var event_name: String = String(event)
	if not schema.has_event(event_name):
		rejected_count += 1
		GameLog.warn("analytics", "unknown event '%s' rejected" % event_name)
		return false
	var record: Dictionary = {
		"event": event_name,
		"params": schema.sanitize_params(event_name, source),
		"ts": _clock.now_unix(),
		"session": session_id,
		"app_version": _app_version,
		"platform": _platform,
		"seq": _seq,
	}
	if not install_id.is_empty():
		record["install"] = install_id
	_seq += 1
	var batch: Array[Dictionary] = [record]
	for sink: AnalyticsSink in _sinks:
		sink.send(batch)
	return true


func _set_enabled(value: bool) -> void:
	var was_enabled: bool = enabled
	enabled = value
	if was_enabled and not value:
		for sink: AnalyticsSink in _sinks:
			sink.clear()
		GameLog.info("analytics", "consent withdrawn; stored analytics cleared")


## Finite number as int, else [param fallback] (int() on other types is a script error).
static func _int_or(value: Variant, fallback: int) -> int:
	if typeof(value) == TYPE_INT:
		return value as int
	if typeof(value) == TYPE_FLOAT and is_finite(value as float):
		return int(value)
	return fallback


static func _sanitize_install_id(raw: String) -> String:
	var id: String = raw.strip_edges()
	if id.is_empty() or id.length() > MAX_INSTALL_ID_LENGTH:
		return ""
	for i: int in id.length():
		if not INSTALL_ID_CHARSET.contains(id[i]):
			GameLog.warn("analytics", "install id is not an opaque token; omitted from events")
			return ""
	return id
