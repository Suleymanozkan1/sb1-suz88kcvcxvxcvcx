class_name HttpTransport
extends Node
## Real HTTP transport implementing the project's network contract.
##
## [method request] is a coroutine that performs one JSON request with a
## temporary [HTTPRequest] child and always resolves to
## {"ok": bool, "status": int, "body": Variant, "error": String}; it never
## throws or blocks gameplay. "ok" means a 2xx response. "status" is 0 when no
## HTTP response arrived (offline, timeout, DNS, TLS). Only HTTPS URLs are
## allowed (plain HTTP only for localhost during development and tests).
## [method as_callable] exposes the 3-argument transport Callable that
## services receive by injection.

const DEFAULT_TIMEOUT_S: float = 8.0
const MIN_TIMEOUT_S: float = 0.5
const MAX_TIMEOUT_S: float = 60.0
const MAX_BODY_BYTES: int = 1048576
const MAX_REDIRECTS: int = 3
const STATUS_OK_MIN: int = 200
const STATUS_OK_MAX: int = 299
const SECURE_PREFIX: String = "https://"
const LOCAL_PREFIXES: PackedStringArray = [
	"http://127.0.0.1:",
	"http://127.0.0.1/",
	"http://localhost:",
	"http://localhost/",
]
const METHODS: Dictionary = {
	"GET": HTTPClient.METHOD_GET,
	"POST": HTTPClient.METHOD_POST,
	"PUT": HTTPClient.METHOD_PUT,
	"PATCH": HTTPClient.METHOD_PATCH,
	"DELETE": HTTPClient.METHOD_DELETE,
}
const BODYLESS_METHODS: PackedStringArray = ["GET", "DELETE"]
const ERR_UNSUPPORTED_METHOD: String = "unsupported_method"
const ERR_INSECURE_URL: String = "insecure_url"
const ERR_NOT_IN_TREE: String = "not_in_tree"
const ERR_HTTP_STATUS: String = "http_status"
## HTTPRequest.Result -> stable error code.
const RESULT_ERRORS: Dictionary = {
	HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH: "body_size_mismatch",
	HTTPRequest.RESULT_CANT_CONNECT: "cant_connect",
	HTTPRequest.RESULT_CANT_RESOLVE: "cant_resolve",
	HTTPRequest.RESULT_CONNECTION_ERROR: "connection_error",
	HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: "tls_handshake_error",
	HTTPRequest.RESULT_NO_RESPONSE: "no_response",
	HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: "body_too_large",
	HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED: "decompress_failed",
	HTTPRequest.RESULT_REQUEST_FAILED: "request_failed",
	HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN: "download_failed",
	HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR: "download_failed",
	HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: "redirect_limit",
	HTTPRequest.RESULT_TIMEOUT: "timeout",
}

## Allows plain HTTP to localhost (development servers and tests).
var allow_local_http: bool = true
## Requests currently in flight.
var in_flight: int = 0


## Performs one request. [param body] is sent as JSON for POST/PUT/PATCH.
## Coroutine: always await it.
func request(method: String, url: String, body: Dictionary = {}, timeout_s: float = DEFAULT_TIMEOUT_S) -> Dictionary:
	var verb: String = method.to_upper()
	var precheck: String = _precheck(verb, url)
	if not precheck.is_empty():
		return HttpTransport.failure(precheck)
	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = clampf(timeout_s, MIN_TIMEOUT_S, MAX_TIMEOUT_S)
	http.body_size_limit = MAX_BODY_BYTES
	http.max_redirects = MAX_REDIRECTS
	add_child(http)
	var headers: PackedStringArray = ["Accept: application/json", "User-Agent: FluxDrop/%s" % AppInfo.version()]
	var payload: String = ""
	if not BODYLESS_METHODS.has(verb):
		payload = JSON.stringify(body)
		headers.append("Content-Type: application/json")
	var err: Error = http.request(url, headers, METHODS[verb] as HTTPClient.Method, payload)
	if err != OK:
		http.queue_free()
		return HttpTransport.failure("request_error_%s" % error_string(err).to_snake_case())
	in_flight += 1
	var completed: Array = await http.request_completed
	in_flight -= 1
	http.queue_free()
	return HttpTransport.parse_completion(
		int(completed[0]), int(completed[1]), completed[3] as PackedByteArray
	)


## The 3-argument transport Callable (method, url, body) -> Dictionary.
func as_callable() -> Callable:
	return func(method: String, url: String, body: Dictionary) -> Dictionary:
		return await request(method, url, body)


## True for HTTPS URLs (and localhost HTTP when allowed).
func is_url_allowed(url: String) -> bool:
	if url.contains(" ") or url.contains("\n") or url.contains("\t"):
		return false
	if url.begins_with(SECURE_PREFIX) and url.length() > SECURE_PREFIX.length():
		return true
	if allow_local_http:
		for prefix: String in LOCAL_PREFIXES:
			if url.begins_with(prefix):
				return true
	return false


## Builds the contract dictionary from an HTTPRequest completion.
static func parse_completion(result: int, status: int, raw_body: PackedByteArray) -> Dictionary:
	if result != HTTPRequest.RESULT_SUCCESS:
		return HttpTransport.failure(str(RESULT_ERRORS.get(result, "network_error")))
	var text: String = raw_body.get_string_from_utf8()
	var parsed: Variant = null
	if not text.strip_edges().is_empty():
		var json: JSON = JSON.new()
		parsed = json.data if json.parse(text) == OK else text
	var ok: bool = status >= STATUS_OK_MIN and status <= STATUS_OK_MAX
	return {"ok": ok, "status": status, "body": parsed, "error": "" if ok else "%s_%d" % [ERR_HTTP_STATUS, status]}


## A failed response (no HTTP status) with [param error].
static func failure(error: String) -> Dictionary:
	return {"ok": false, "status": 0, "body": null, "error": error}


func _precheck(verb: String, url: String) -> String:
	var error: String = ""
	if not METHODS.has(verb):
		error = ERR_UNSUPPORTED_METHOD
	elif not is_url_allowed(url):
		error = ERR_INSECURE_URL
	elif not is_inside_tree():
		error = ERR_NOT_IN_TREE
	return error
