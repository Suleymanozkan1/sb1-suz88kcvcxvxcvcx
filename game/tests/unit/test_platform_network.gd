extends TestCase
## Network: monitor transitions, wrapped transports, real HttpTransport.

const FIRST_TEST_PORT: int = 47310
const PORT_ATTEMPTS: int = 200
const MAX_WAIT_FRAMES: int = 1200

var _nodes: Array[Node] = []


## Transport double answering every request with a fixed response.
class ScriptedTransport:
	extends RefCounted
	var response: Variant = {"ok": false, "status": 0, "body": null, "error": "cant_connect"}

	func respond(_method: String, _url: String, _body: Dictionary) -> Variant:
		return response


func after_each() -> void:
	for node: Node in _nodes:
		if is_instance_valid(node):
			node.queue_free()
	_nodes.clear()


func _transport_in_tree() -> HttpTransport:
	var transport: HttpTransport = HttpTransport.new()
	tree.root.add_child(transport)
	_nodes.append(transport)
	return transport


func _listen(server: TCPServer) -> int:
	for i: int in PORT_ATTEMPTS:
		var port: int = FIRST_TEST_PORT + i
		if server.listen(port, "127.0.0.1") == OK:
			return port
	return -1


func test_monitor_transitions_emit_signal() -> void:
	var bus: EventBus = EventBus.new()
	var seen: Array[bool] = []
	bus.network_state_changed.connect(func(online: bool) -> void: seen.append(online))
	var monitor: NetworkMonitor = NetworkMonitor.new(bus)
	assert_true(monitor.online, "optimistic until proven otherwise")
	monitor.report(true)
	assert_empty(seen, "no signal without a change")
	monitor.report(false)
	monitor.report(false)
	assert_false(monitor.online)
	assert_eq(monitor.failures_in_row, 2)
	monitor.report(true)
	assert_true(monitor.online)
	assert_eq(monitor.failures_in_row, 0)
	assert_eq(seen, [false, true] as Array[bool])
	assert_eq(monitor.transitions, 2)


func test_wrapped_transport_reports_real_outcomes() -> void:
	var bus: EventBus = EventBus.new()
	var monitor: NetworkMonitor = NetworkMonitor.new(bus)
	var inner: ScriptedTransport = ScriptedTransport.new()
	var wrapped: Callable = monitor.wrap(inner.respond)
	var offline: Dictionary = await wrapped.call("GET", "https://x.example.invalid", {})
	assert_false(bool(offline["ok"]))
	assert_false(monitor.online, "status 0 means unreachable")
	inner.response = {"ok": false, "status": 503, "body": null, "error": "http_status_503"}
	await wrapped.call("GET", "https://x.example.invalid", {})
	assert_true(monitor.online, "any HTTP status means the server was reached")
	inner.response = "not a dictionary"
	var invalid: Dictionary = await wrapped.call("POST", "https://x.example.invalid", {"a": 1})
	assert_eq(invalid["error"], "invalid_response")
	assert_false(monitor.online)
	inner.response = {"ok": true, "status": 200, "body": {}, "error": ""}
	var ok: Dictionary = await wrapped.call("GET", "https://x.example.invalid", {})
	assert_true(bool(ok["ok"]))
	assert_true(monitor.online)
	assert_false(NetworkMonitor.server_reached({"ok": "true", "status": "500"}), "odd types are not evidence")
	assert_false(NetworkMonitor.server_reached({"ok": null, "status": null}))
	assert_true(NetworkMonitor.server_reached({"status": 404.0}))


func test_http_transport_refuses_insecure_or_invalid_requests() -> void:
	var transport: HttpTransport = _transport_in_tree()
	var plain: Dictionary = await transport.request("GET", "http://example.invalid/config")
	assert_false(bool(plain["ok"]))
	assert_eq(plain["status"], 0)
	assert_eq(plain["error"], HttpTransport.ERR_INSECURE_URL)
	var ftp: Dictionary = await transport.request("GET", "ftp://example.invalid/x")
	assert_eq(ftp["error"], HttpTransport.ERR_INSECURE_URL)
	var spaced: Dictionary = await transport.request("GET", "https://exa mple.invalid")
	assert_eq(spaced["error"], HttpTransport.ERR_INSECURE_URL)
	var verb: Dictionary = await transport.request("TRACE", "https://example.invalid")
	assert_eq(verb["error"], HttpTransport.ERR_UNSUPPORTED_METHOD)
	transport.allow_local_http = false
	assert_false(transport.is_url_allowed("http://127.0.0.1:8080/"))
	assert_true(transport.is_url_allowed("https://api.example.invalid/v1"))
	var detached: HttpTransport = HttpTransport.new()
	var not_in_tree: Dictionary = await detached.request("GET", "https://example.invalid")
	assert_eq(not_in_tree["error"], HttpTransport.ERR_NOT_IN_TREE)
	detached.free()


func test_parse_completion() -> void:
	var ok: Dictionary = HttpTransport.parse_completion(HTTPRequest.RESULT_SUCCESS, 200, "{\"a\": 1}".to_utf8_buffer())
	assert_true(bool(ok["ok"]))
	assert_eq(ok["status"], 200)
	assert_eq((ok["body"] as Dictionary)["a"], 1.0)
	assert_eq(ok["error"], "")
	var missing: Dictionary = HttpTransport.parse_completion(HTTPRequest.RESULT_SUCCESS, 404, PackedByteArray())
	assert_false(bool(missing["ok"]))
	assert_eq(missing["status"], 404)
	assert_eq(missing["error"], "http_status_404")
	assert_eq(missing["body"], null)
	var text: Dictionary = HttpTransport.parse_completion(HTTPRequest.RESULT_SUCCESS, 200, "plain".to_utf8_buffer())
	assert_eq(text["body"], "plain")
	var timeout: Dictionary = HttpTransport.parse_completion(HTTPRequest.RESULT_TIMEOUT, 0, PackedByteArray())
	assert_eq(timeout["status"], 0)
	assert_eq(timeout["error"], "timeout")
	var odd: Dictionary = HttpTransport.parse_completion(999, 0, PackedByteArray())
	assert_eq(odd["error"], "network_error")


func test_http_transport_round_trip_with_local_server() -> void:
	var server: TCPServer = TCPServer.new()
	var port: int = _listen(server)
	assert_gt(port, 0, "a local port is available")
	if port < 0:
		return
	# Earlier suites may block the main loop for seconds; let that huge frame
	# delta pass so HTTPRequest's internal timeout timer starts fresh.
	await wait_frames(2)
	var transport: HttpTransport = _transport_in_tree()
	var send: Callable = transport.as_callable()
	var holder: Dictionary = {}
	var url: String = "http://127.0.0.1:%d/v1/scores" % port
	var runner: Callable = func() -> void: holder["result"] = await send.call("POST", url, {"hello": "world"})
	runner.call()
	var peer: StreamPeerTCP = null
	var request_text: String = ""
	var responded: bool = false
	var frames: int = 0
	while not holder.has("result") and frames < MAX_WAIT_FRAMES:
		await tree.process_frame
		frames += 1
		if peer == null and server.is_connection_available():
			peer = server.take_connection()
		if peer == null:
			continue
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		var available: int = peer.get_available_bytes()
		if available > 0:
			request_text += peer.get_utf8_string(available)
		if not responded and request_text.contains("\r\n\r\n") and request_text.ends_with("}"):
			var reply: String = "{\"accepted\": true, \"rank\": 3}"
			var head: String = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n"
			var response: String = (head % reply.to_utf8_buffer().size()) + "Connection: close\r\n\r\n" + reply
			peer.put_data(response.to_utf8_buffer())
			responded = true
	server.stop()
	assert_true(holder.has("result"), "request completed")
	if not holder.has("result"):
		return
	var result: Dictionary = holder["result"] as Dictionary
	var detail: String = "%s after %d frames; server saw: %s" % [str(result), frames, request_text.c_escape()]
	assert_true(bool(result["ok"]), detail)
	assert_eq(result["status"], 200, detail)
	if typeof(result["body"]) != TYPE_DICTIONARY:
		return
	assert_eq((result["body"] as Dictionary)["accepted"], true)
	assert_eq(transport.in_flight, 0)
	assert_true(request_text.begins_with("POST /v1/scores HTTP/1.1"))
	assert_has(request_text, "Content-Type: application/json")
	assert_has(request_text, "{\"hello\":\"world\"}")
	assert_has(request_text, "User-Agent: FluxDrop/")


func test_http_transport_unreachable_host_is_offline_not_crash() -> void:
	var server: TCPServer = TCPServer.new()
	var port: int = _listen(server)
	server.stop()
	if port < 0:
		assert_true(true, "no local port to probe")
		return
	await wait_frames(2)
	var transport: HttpTransport = _transport_in_tree()
	var holder: Dictionary = {}
	var url: String = "http://127.0.0.1:%d/" % port
	var runner: Callable = func() -> void: holder["result"] = await transport.request("GET", url, {}, 2.0)
	runner.call()
	var frames: int = 0
	while not holder.has("result") and frames < MAX_WAIT_FRAMES:
		await tree.process_frame
		frames += 1
	assert_true(holder.has("result"), "request resolved")
	if holder.has("result"):
		var result: Dictionary = holder["result"] as Dictionary
		assert_false(bool(result["ok"]))
		assert_eq(result["status"], 0)
		assert_false(str(result["error"]).is_empty())
