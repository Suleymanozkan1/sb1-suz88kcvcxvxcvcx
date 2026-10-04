class_name HttpTransport
extends Node
## Real HTTP transport implementing the project's network contract.
##
## [method request] is a coroutine that performs one JSON request with a
## temporary [HTTPRequest] child and always resolves to
## {"ok": bool, "status": int, "body": Variant, "error": String}; it never
## throws or blocks gameplay. "ok" means a 2xx response. "status" is the HTTP
## status when a response arrived and 0 when none did (offline, timeout, DNS,
## TLS). Only HTTPS URLs are allowed; plain HTTP to localhost only in debug
## builds (development servers and tests). URLs with credentials ("user@host")
## are refused and redirects are not followed, so a server can never bounce a
## request to plain HTTP or to another host.
## [method as_callable] exposes the 3-argument transport Callable that
## services receive by injection.

const DEFAULT_TIMEOUT_S: float = 8.0
const MIN_TIMEOUT_S: float = 0.5
const MAX_TIMEOUT_S: float = 60.0
const MAX_BODY_BYTES: int = 1048576
## API endpoints never need redirects; following one could downgrade to HTTP.
const MAX_REDIRECTS: int = 0
const STATUS_OK_MIN: int = 200
const STATUS_OK_MAX: int = 299
const SCHEME_SEPARATOR: String = "://"
const SECURE_PREFIX: String = "https://"
const LOCAL_PREFIXES: PackedStringArray = [
	"http://127.0.0.1:",
	"http://127.0.0.1/",
	"http://localhost:",
	"http://localhost/",
]
## Characters that end the authority (host[:port]) part of a URL.
const AUTHORITY_END: PackedStringArray = ["/", "?", "#"]
## Never valid in a URL we send (whitespace tricks, Windows-style separators).
const FORBIDDEN_URL_CHARS: PackedStringArray = [" ", "\t", "\n", "\r", "\\"]
const METHODS: Dictionary[String, HTTPClient.Method] = {
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
const RESULT_ERRORS: Dictionary[HTTPRequest.Result, String] = {
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
	HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: "redirect_refused",
	HTTPRequest.RESULT_TIMEOUT: "timeout",
}

## Allows plain HTTP to localhost (development servers and tests). Off in
## release builds.
var allow_local_http: bool = OS.is_debug_build()
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
	var err: Error = http.request(url, headers, METHODS[verb], payload)
	if err != OK:
		http.queue_free()
		return HttpTransport.failure("request_error_%s" % error_string(err).to_snake_case())
	in_flight += 1
	var completed: Array = await http.request_completed
	in_flight -= 1
	http.queue_free()
	return HttpTransport.parse_completion(int(completed[0]), int(completed[1]), completed[3] as PackedByteArray)


## The 3-argument transport Callable (method, url, body) -> Dictionary.
func as_callable() -> Callable:
	return func(method: String, url: String, body: Dictionary) -> Dictionary: return await request(method, url, body)


## True for HTTPS URLs (and localhost HTTP when allowed) with a plain host:
## no embedded credentials and no whitespace or backslashes.
func is_url_allowed(url: String) -> bool:
	for ch: String in FORBIDDEN_URL_CHARS:
		if url.contains(ch):
			return false
	if not HttpTransport.has_plain_authority(url):
		return false
	if url.begins_with(SECURE_PREFIX):
		return true
	var local: bool = false
	if allow_local_http:
		for prefix: String in LOCAL_PREFIXES:
			local = local or url.begins_with(prefix)
	return local


## True when the URL names exactly one plain host: the part between "://" and
## the first "/" (where the engine's URL parser ends the host) holds no
## credentials, query or fragment. Otherwise "https://good.host?@other.host/"
## would pass a check on "good.host" while the engine connects to the other
## host.
static func has_plain_authority(url: String) -> bool:
	var start: int = url.find(SCHEME_SEPARATOR)
	if start < 0:
		return false
	var rest: String = url.substr(start + SCHEME_SEPARATOR.length())
	var slash: int = rest.find("/")
	var host: String = rest if slash < 0 else rest.substr(0, slash)
	for ch: String in ["@", "?", "#"]:
		if host.contains(ch):
			return false
	return not host.is_empty()


## The "host[:port]" part of [param url] (with any "user@" kept so callers
## can refuse it); "" when the URL has no scheme or no host.
static func authority_of(url: String) -> String:
	var start: int = url.find(SCHEME_SEPARATOR)
	if start < 0:
		return ""
	var rest: String = url.substr(start + SCHEME_SEPARATOR.length())
	var end: int = rest.length()
	for sep: String in AUTHORITY_END:
		var at: int = rest.find(sep)
		if at >= 0 and at < end:
			end = at
	return rest.substr(0, end)


## Builds the contract dictionary from an HTTPRequest completion. A failed
## completion keeps the HTTP status when the server did answer (e.g. a
## refused redirect), so connectivity is not misreported as offline.
static func parse_completion(result: int, status: int, raw_body: PackedByteArray) -> Dictionary:
	if result != HTTPRequest.RESULT_SUCCESS:
		var failed: Dictionary = HttpTransport.failure(str(RESULT_ERRORS.get(result, "network_error")))
		failed["status"] = maxi(0, status)
		return failed
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
