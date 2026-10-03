extends TestCase
## Analytics sinks: bounded memory sink, ring-trimmed file sink, batched HTTP
## sink with a bounded offline queue.

const ENDPOINT: String = "https://analytics.example.invalid/v1/events"

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


func _physical_lines(path: String) -> int:
	var count: int = 0
	for line: String in FileAccess.get_file_as_string(path).split("\n", false):
		if not line.strip_edges().is_empty():
			count += 1
	return count


func _events(count: int, first_seq: int = 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in count:
		out.append({"event": "level_started", "params": {}, "seq": first_seq + i})
	return out


func test_memory_sink_is_bounded() -> void:
	var sink: MemoryAnalyticsSink = MemoryAnalyticsSink.new(3)
	sink.send(_events(5))
	assert_eq(sink.events.size(), 3)
	assert_eq(sink.events[0]["seq"], 2, "oldest dropped first")


func test_file_sink_trims_ring() -> void:
	var path: String = _unique_dir().path_join("events.jsonl")
	var sink: FileAnalyticsSink = FileAnalyticsSink.new(path, 5)
	sink.send(_events(3, 0))
	assert_eq(sink.line_count(), 3)
	sink.send(_events(4, 3))
	sink.send(_events(5, 7))
	assert_eq(sink.line_count(), 5)
	var events: Array[Dictionary] = sink.read_events()
	assert_eq(events.size(), 5)
	assert_eq(int(events[0]["seq"]), 7, "newest lines kept")
	assert_eq(int(events[4]["seq"]), 11)
	var reopened: FileAnalyticsSink = FileAnalyticsSink.new(path, 5)
	reopened.send(_events(1, 12))
	assert_eq(reopened.line_count(), 5, "line count recovered from disk")
	assert_eq(int(reopened.read_events()[4]["seq"]), 12)


func test_file_sink_skips_corrupt_lines() -> void:
	var path: String = _unique_dir().path_join("events.jsonl")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_line("{not json")
	f.close()
	var sink: FileAnalyticsSink = FileAnalyticsSink.new(path, 10)
	sink.send(_events(2))
	assert_eq(sink.line_count(), 3)
	assert_eq(sink.read_events().size(), 2, "corrupt line ignored")


func test_file_sink_trims_in_batches_not_per_event() -> void:
	var path: String = _unique_dir().path_join("events.jsonl")
	var sink: FileAnalyticsSink = FileAnalyticsSink.new(path, 10)
	assert_eq(sink.trim_slack, 2)
	for i: int in 12:
		sink.send(_events(1, i))
	assert_eq(_physical_lines(path), 12, "within the slack the file is only appended to")
	assert_eq(sink.line_count(), 10, "readers still see only the newest max_lines")
	assert_eq(sink.read_lines().size(), 10)
	assert_eq(int(sink.read_events()[0]["seq"]), 2)
	sink.send(_events(1, 12))
	assert_eq(_physical_lines(path), 10, "trimmed in one rewrite once the slack is used up")
	assert_eq(int(sink.read_events()[9]["seq"]), 12)
	for i: int in 40:
		sink.send(_events(1, 13 + i))
		assert_le(_physical_lines(path), 12, "the file never grows past max_lines + slack")


func test_file_sink_recovers_a_line_cut_short_by_a_crash() -> void:
	var path: String = _unique_dir().path_join("events.jsonl")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{\"event\": \"level_started\", \"seq\": 0}\n{\"event\": \"level_sta")
	f.close()
	var sink: FileAnalyticsSink = FileAnalyticsSink.new(path, 10)
	sink.send(_events(1, 5))
	var events: Array[Dictionary] = sink.read_events()
	assert_eq(events.size(), 2, "the cut line is skipped, the new event stays intact")
	assert_eq(int(events[1]["seq"]), 5)


func test_file_sink_clear_deletes_the_file() -> void:
	var path: String = _unique_dir().path_join("events.jsonl")
	var sink: FileAnalyticsSink = FileAnalyticsSink.new(path, 10)
	sink.send(_events(3))
	sink.clear()
	assert_false(FileAccess.file_exists(path))
	assert_eq(sink.line_count(), 0)
	sink.send(_events(1))
	assert_eq(sink.line_count(), 1)


func test_http_sink_queues_offline_then_flushes() -> void:
	var transport: ScriptedTransport = ScriptedTransport.new()
	var sink: HttpAnalyticsSink = HttpAnalyticsSink.new(ENDPOINT, transport.respond, 2)
	sink.send(_events(5))
	assert_eq(sink.queued_count(), 5)
	var delivered: bool = await sink.flush()
	assert_false(delivered, "offline flush keeps events")
	assert_eq(sink.queued_count(), 5, "nothing lost while offline")
	assert_eq(transport.calls.size(), 1, "stops at the first failure")
	transport.online = true
	delivered = await sink.flush()
	assert_true(delivered)
	assert_eq(sink.queued_count(), 0)
	assert_eq(sink.sent_count, 5)
	assert_eq(transport.calls.size(), 4, "1 failed + 3 batches (2+2+1)")
	var first_ok: Dictionary = transport.calls[1]
	assert_eq(first_ok["method"], "POST")
	var body: Dictionary = first_ok["body"] as Dictionary
	assert_eq(body["format"], HttpAnalyticsSink.PAYLOAD_FORMAT)
	assert_eq((body["events"] as Array).size(), 2)
	assert_eq(int(((body["events"] as Array)[0] as Dictionary)["seq"]), 0, "oldest first")


func test_http_sink_queue_is_bounded() -> void:
	var transport: ScriptedTransport = ScriptedTransport.new()
	var sink: HttpAnalyticsSink = HttpAnalyticsSink.new(ENDPOINT, transport.respond, 2, 5)
	sink.send(_events(8))
	assert_eq(sink.queued_count(), 5)
	assert_eq(sink.dropped_count, 3)
	await sink.flush()
	assert_eq(sink.queued_count(), 5, "failed batch requeued without exceeding the bound")
	transport.online = true
	await sink.flush()
	var first_body: Dictionary = transport.calls[1]["body"] as Dictionary
	assert_eq(int(((first_body["events"] as Array)[0] as Dictionary)["seq"]), 3, "oldest were dropped")


func test_http_sink_drops_permanently_rejected_batch() -> void:
	var transport: ScriptedTransport = ScriptedTransport.new()
	transport.online = true
	transport.status = 400
	var sink: HttpAnalyticsSink = HttpAnalyticsSink.new(ENDPOINT, transport.respond)
	sink.send(_events(3))
	var delivered: bool = await sink.flush()
	assert_true(delivered, "a malformed batch must not block the queue forever")
	assert_eq(sink.rejected_count, 3)
	transport.status = 429
	sink.send(_events(1))
	delivered = await sink.flush()
	assert_false(delivered, "rate limiting is retried later")
	assert_eq(sink.queued_count(), 1)


func test_http_sink_clear_during_upload_drops_the_batch() -> void:
	var transport: ScriptedTransport = ScriptedTransport.new()
	transport.tree = tree
	var sink: HttpAnalyticsSink = HttpAnalyticsSink.new(ENDPOINT, transport.respond, 2)
	sink.send(_events(3))
	var holder: Dictionary = {}
	var runner: Callable = func() -> void: holder["delivered"] = await sink.flush()
	runner.call()
	sink.clear()
	sink.send(_events(1, 100))
	var guard: int = 0
	while not holder.has("delivered") and guard < 10:
		await tree.process_frame
		guard += 1
	assert_true(holder.has("delivered"))
	assert_eq(sink.queued_count(), 1, "only the event queued after clear() remains")
	transport.online = true
	assert_true(await sink.flush())
	var last_body: Dictionary = transport.calls.back()["body"] as Dictionary
	assert_eq(int(((last_body["events"] as Array)[0] as Dictionary)["seq"]), 100)


func test_http_sink_disabled_without_endpoint() -> void:
	var transport: ScriptedTransport = ScriptedTransport.new()
	var sink: HttpAnalyticsSink = HttpAnalyticsSink.new("", transport.respond)
	assert_false(sink.is_enabled())
	sink.send(_events(3))
	assert_eq(sink.queued_count(), 0)
	var delivered: bool = await sink.flush()
	assert_true(delivered)
	assert_eq(transport.calls.size(), 0)
