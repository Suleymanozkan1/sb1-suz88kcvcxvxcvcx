extends TestCase
## Analytics: schema enforcement, PII guards, coercion, consent and sinks.

const FIXED_NOW: int = 1790000000
const INSTALL: String = "0123456789abcdef0123456789abcdef"
const REQUIRED_EVENTS: PackedStringArray = [
	"session_started",
	"level_started",
	"level_completed",
	"level_failed",
	"perfect_completed",
	"combo_reached",
	"reward_claimed",
	"shop_opened",
	"purchase_started",
	"purchase_completed",
	"ad_started",
	"ad_completed",
	"daily_started",
	"daily_completed",
	"achievement_unlocked",
	"mission_claimed",
	"quality_auto_reduced",
	"save_recovered",
	"error_reported",
	"tutorial_step",
	"settings_changed",
	"world_unlocked",
]

var _dirs: PackedStringArray = PackedStringArray()


## Transport double: offline until [member online] is set; records requests.
class ScriptedTransport:
	extends RefCounted
	var online: bool = false
	var status: int = 200
	var calls: Array[Dictionary] = []
	## When set, responses resolve one frame later (coroutine path).
	var tree: SceneTree = null

	func respond(method: String, url: String, body: Dictionary) -> Dictionary:
		calls.append({"method": method, "url": url, "body": body.duplicate(true)})
		if tree != null:
			await tree.process_frame
		if not online:
			return {"ok": false, "status": 0, "body": null, "error": "cant_connect"}
		return {"ok": status >= 200 and status < 300, "status": status, "body": {}, "error": ""}


func after_each() -> void:
	for dir_path: String in _dirs:
		_remove_dir(dir_path)
	_dirs.clear()


func _service(schema: Dictionary = {}) -> AnalyticsService:
	var clock: GameClock = GameClock.new()
	clock.set_fixed_unix(FIXED_NOW)
	return AnalyticsService.new(INSTALL, clock, schema)


func _unique_dir() -> String:
	var dir_path: String = "user://test_platform_analytics_%d_%d" % [Time.get_ticks_usec(), randi()]
	_dirs.append(dir_path)
	return dir_path


func _remove_dir(dir_path: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for f: String in dir.get_files():
		DirAccess.remove_absolute(dir_path.path_join(f))
	DirAccess.remove_absolute(dir_path)


func test_bundled_schema_declares_required_events_without_pii() -> void:
	var schema: AnalyticsSchema = AnalyticsSchema.load_default()
	assert_empty(schema.load_issues, "bundled schema loads cleanly")
	for event: String in REQUIRED_EVENTS:
		assert_true(schema.has_event(event), "event %s declared" % event)
	for event: String in schema.events:
		for param: String in schema.param_types(event):
			assert_false(schema.is_forbidden_param(param), "%s.%s must not look like PII" % [event, param])
	for pattern: String in ["email", "name", "phone", "device_id", "imei", "advertising_id", "ip", "lat", "lon"]:
		assert_has(schema.forbidden_patterns, pattern)


func test_unknown_event_rejected() -> void:
	var svc: AnalyticsService = _service()
	var sink: MemoryAnalyticsSink = MemoryAnalyticsSink.new()
	svc.add_sink(sink)
	assert_false(svc.track(&"totally_unknown_event", {"level_id": "w01_l01"}))
	assert_eq(sink.events.size(), 0, "nothing recorded")
	assert_eq(svc.rejected_count, 1)
	assert_true(svc.track(&"level_started", {"level_id": "w01_l01"}))
	assert_eq(sink.events.size(), 1)


func test_forbidden_params_dropped() -> void:
	var svc: AnalyticsService = _service()
	var sink: MemoryAnalyticsSink = MemoryAnalyticsSink.new()
	svc.add_sink(sink)
	var params: Dictionary = {
		"level_id": "w01_l02",
		"email": "player@example.com",
		"player_name": "Ayse",
		"user_ip": "10.1.2.3",
		"deviceId": "abc",
		"advertising_id": "zzz",
		"lat": 41.0,
		"lon": 29.0,
		"phone": "555",
		"home_address": "street",
		"imei": "123",
	}
	assert_true(svc.track(&"level_started", params))
	var recorded: Dictionary = sink.last()["params"] as Dictionary
	assert_eq(recorded.keys(), ["level_id"], "only the declared, safe param survives")


func test_forbidden_name_in_schema_is_removed_at_load() -> void:
	var data: Dictionary = {
		"events": {"custom": {"params": {"email": "string", "nickname": "string", "score": "int", "bad": "vector"}}},
	}
	var schema: AnalyticsSchema = AnalyticsSchema.from_dict(data)
	assert_true(schema.has_event("custom"))
	assert_eq(schema.param_types("custom").keys(), ["score"])
	assert_eq(schema.load_issues.size(), 3, "email, nickname and unknown type reported")


func test_pattern_matching_uses_tokens_for_short_patterns() -> void:
	var schema: AnalyticsSchema = AnalyticsSchema.from_dict({"events": {}})
	assert_true(schema.is_forbidden_param("user_ip"))
	assert_true(schema.is_forbidden_param("userIP"))
	assert_true(schema.is_forbidden_param("lat"))
	assert_true(schema.is_forbidden_param("username"))
	assert_true(schema.is_forbidden_param("advertisingId"))
	assert_false(schema.is_forbidden_param("multiplier"), "'ip' inside a word is fine")
	assert_false(schema.is_forbidden_param("platform"), "'lat' inside a word is fine")
	assert_false(schema.is_forbidden_param("long_combo"), "'lon' inside a word is fine")
	assert_false(schema.is_forbidden_param("skipped"))


func test_type_coercion() -> void:
	var svc: AnalyticsService = _service()
	var sink: MemoryAnalyticsSink = MemoryAnalyticsSink.new()
	svc.add_sink(sink)
	var params: Dictionary = {
		"level_id": &"w01_l05",
		"score": "1200",
		"stars": 2.6,
		"time_seconds": 12,
		"revived": "true",
		"grade": 4,
		"max_combo": "lots",
		"taps": [1, 2],
		"attempt": NAN,
	}
	assert_true(svc.track(&"level_completed", params))
	var p: Dictionary = sink.last()["params"] as Dictionary
	assert_eq(typeof(p["level_id"]), TYPE_STRING)
	assert_eq(p["level_id"], "w01_l05")
	assert_eq(typeof(p["score"]), TYPE_INT)
	assert_eq(p["score"], 1200)
	assert_eq(p["stars"], 3, "floats round to the nearest int")
	assert_eq(typeof(p["time_seconds"]), TYPE_FLOAT)
	assert_eq(p["revived"], true)
	assert_eq(p["grade"], "4")
	assert_false(p.has("max_combo"), "non-numeric string dropped")
	assert_false(p.has("taps"), "arrays dropped")
	assert_false(p.has("attempt"), "NaN dropped")


func test_coerce_edge_cases() -> void:
	assert_eq(AnalyticsSchema.coerce(true, "int"), 1)
	assert_eq(AnalyticsSchema.coerce("0", "bool"), false)
	assert_eq(AnalyticsSchema.coerce("maybe", "bool"), null)
	assert_eq(AnalyticsSchema.coerce(INF, "float"), null)
	assert_eq(AnalyticsSchema.coerce(1.0e300, "int"), null)
	assert_eq(AnalyticsSchema.coerce("x".repeat(500), "string", 10), "xxxxxxxxxx")
	assert_eq(AnalyticsSchema.coerce({"a": 1}, "string"), null)


func test_personal_data_values_dropped() -> void:
	var svc: AnalyticsService = _service()
	var sink: MemoryAnalyticsSink = MemoryAnalyticsSink.new()
	svc.add_sink(sink)
	svc.track(&"settings_changed", {"key": "language", "value": "someone@example.com"})
	assert_false((sink.last()["params"] as Dictionary).has("value"), "e-mail value dropped")
	svc.track(&"settings_changed", {"key": "language", "value": "192.168.1.20"})
	assert_false((sink.last()["params"] as Dictionary).has("value"), "IP value dropped")
	svc.track(&"settings_changed", {"key": "language", "value": "tr"})
	assert_eq((sink.last()["params"] as Dictionary)["value"], "tr")


func test_events_are_enriched_without_device_identifiers() -> void:
	var svc: AnalyticsService = _service()
	var sink: MemoryAnalyticsSink = MemoryAnalyticsSink.new()
	svc.add_sink(sink)
	svc.track(&"session_started", {"locale": "tr", "quality": "high"})
	svc.track(&"level_started", {"level_id": "w01_l01"})
	var first: Dictionary = sink.events[0]
	var second: Dictionary = sink.events[1]
	assert_eq(first["event"], "session_started")
	assert_eq(first["ts"], FIXED_NOW)
	assert_eq(first["seq"], 0)
	assert_eq(second["seq"], 1)
	assert_eq(first["session"], svc.session_id)
	assert_eq(str(first["session"]).length(), AnalyticsService.SESSION_ID_BYTES * 2)
	assert_eq(first["app_version"], AppInfo.version())
	assert_eq(first["platform"], AppInfo.platform())
	assert_eq(first["install"], INSTALL)
	var allowed: Array = ["event", "params", "ts", "session", "app_version", "platform", "seq", "install"]
	for key: Variant in first:
		assert_has(allowed, key, "unexpected top-level field")
	assert_ne(svc.session_id, _service().session_id, "session id is random per launch")


func test_non_opaque_install_id_is_not_sent() -> void:
	var clock: GameClock = GameClock.new()
	var svc: AnalyticsService = AnalyticsService.new("someone@example.com", clock)
	var sink: MemoryAnalyticsSink = MemoryAnalyticsSink.new()
	svc.add_sink(sink)
	svc.track(&"level_started", {})
	assert_false(sink.last().has("install"))


func test_consent_off_records_and_sends_nothing() -> void:
	var svc: AnalyticsService = _service()
	var memory: MemoryAnalyticsSink = MemoryAnalyticsSink.new()
	var transport: ScriptedTransport = ScriptedTransport.new()
	transport.online = true
	var http: HttpAnalyticsSink = HttpAnalyticsSink.new("https://analytics.example.invalid/v1/events", transport.respond)
	var file_sink: FileAnalyticsSink = FileAnalyticsSink.new(_unique_dir().path_join("events.jsonl"), 50)
	svc.add_sink(memory)
	svc.add_sink(http)
	svc.add_sink(file_sink)
	svc.enabled = false
	assert_false(svc.track(&"level_started", {"level_id": "w01_l01"}))
	assert_false(svc.track(&"session_started", {}))
	var flushed: bool = await svc.flush()
	assert_false(flushed, "flush refused without consent")
	assert_eq(memory.events.size(), 0)
	assert_eq(http.queued_count(), 0)
	assert_eq(file_sink.line_count(), 0)
	assert_eq(transport.calls.size(), 0, "no network traffic")


func test_withdrawing_consent_clears_stored_events() -> void:
	var svc: AnalyticsService = _service()
	var memory: MemoryAnalyticsSink = MemoryAnalyticsSink.new()
	var transport: ScriptedTransport = ScriptedTransport.new()
	var http: HttpAnalyticsSink = HttpAnalyticsSink.new("https://analytics.example.invalid/v1/events", transport.respond)
	var file_sink: FileAnalyticsSink = FileAnalyticsSink.new(_unique_dir().path_join("events.jsonl"), 50)
	svc.add_sink(memory)
	svc.add_sink(http)
	svc.add_sink(file_sink)
	svc.track(&"level_started", {"level_id": "w01_l01"})
	assert_eq(memory.events.size(), 1)
	assert_eq(http.queued_count(), 1)
	assert_eq(file_sink.line_count(), 1)
	svc.enabled = false
	assert_eq(memory.events.size(), 0)
	assert_eq(http.queued_count(), 0)
	assert_false(FileAccess.file_exists(file_sink.path))
	svc.enabled = true
	assert_true(svc.track(&"level_started", {"level_id": "w01_l02"}), "re-enabling resumes tracking")


func test_context_is_merged_into_error_reports_only() -> void:
	var svc: AnalyticsService = _service()
	var sink: MemoryAnalyticsSink = MemoryAnalyticsSink.new()
	svc.add_sink(sink)
	svc.context = {"level_id": "w02_l07", "state": "gameplay"}
	svc.track(&"level_failed", {"score": 10})
	assert_false((sink.last()["params"] as Dictionary).has("level_id"), "context not merged into other events")
	svc.track(&"error_reported", {"kind": "script", "state": "menu"})
	var p: Dictionary = sink.last()["params"] as Dictionary
	assert_eq(p["level_id"], "w02_l07")
	assert_eq(p["state"], "menu", "explicit params win over context")


func test_error_reports_are_aggregated_and_stripped() -> void:
	var svc: AnalyticsService = _service()
	var sink: MemoryAnalyticsSink = MemoryAnalyticsSink.new()
	svc.add_sink(sink)
	var err: Dictionary = {
		"file": "/home/someone/project/src/gameplay/sim/flux_sim.gd",
		"line": 42,
		"message": "secret user path",
		"error_type": 2,
	}
	var reports: Array[Dictionary] = [
		{"error": err, "context": {"level_id": "w01_l03", "user_email": "x@y.z"}},
		{"error": err},
		{"error": {"file": "res://src/ui/hud.gd", "line": 7, "error_type": 0}},
		{"error": "garbage"},
	]
	assert_eq(svc.track_error_reports(reports), 3)
	var first: Dictionary = sink.events[0]["params"] as Dictionary
	assert_eq(first["where"], "flux_sim.gd:42", "only the file name is kept")
	assert_eq(first["kind"], "script")
	assert_eq(first["count"], 2)
	assert_eq(first["level_id"], "w01_l03")
	assert_false(first.has("message"))
	assert_false(first.has("user_email"))
	assert_eq((sink.events[2]["params"] as Dictionary)["kind"], "unknown")


func test_service_flush_with_coroutine_transport() -> void:
	var transport: ScriptedTransport = ScriptedTransport.new()
	transport.tree = tree
	transport.online = true
	var svc: AnalyticsService = _service()
	var sink: HttpAnalyticsSink = HttpAnalyticsSink.new("https://analytics.example.invalid/v1/events", transport.respond)
	svc.add_sink(sink)
	svc.track(&"level_started", {"level_id": "w01_l01"})
	svc.track(&"level_failed", {"level_id": "w01_l01", "score": 3})
	var delivered: bool = await svc.flush()
	assert_true(delivered)
	assert_eq(sink.queued_count(), 0)
	assert_eq(transport.calls.size(), 1)
