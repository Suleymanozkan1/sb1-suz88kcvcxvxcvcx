class_name HttpCloudSaveProvider
extends CloudSaveProvider
## Remote cloud save slot over the project's HTTP transport contract. The
## server keeps the newest save envelope with an opaque revision and never
## trusts its contents (see server/README.md, "Cloud save").
##
## Endpoints (relative to [member base_url]; {id} = the URI-encoded install id):
## - GET /v1/saves/{id} -> 2xx {"blob": String, "revision": String};
##   404 = no cloud copy yet (ok, found = false).
## - PUT /v1/saves/{id} with {"blob", "base_revision", "app_version"}
##   -> 2xx {"revision": String} (stored); 409 {"blob", "revision"} = the cloud
##   moved on since base_revision: the caller merges that copy and pushes again.
## For both: no answer, 429 or 5xx = transient (retry later); any other 4xx =
## final. A 2xx (or 409) whose body is not the documented shape (an HTML error
## page, an empty 204, wrong field types, a blob over
## [constant SaveService.MAX_SAVE_CHARS], a revision that is not a
## [method CloudSaveProvider.valid_revision] token) is never applied and
## counts as a transient "bad_response".
## An empty base URL or a missing transport or install id disables the
## provider. Network calls go through the injected transport Callable
## (method: String, url: String, body: Dictionary) -> {"ok", "status", "body",
## "error"}; it is always awaited, and its replies are normalised with the
## shared [method HttpLeaderboardBackend.normalize_response].

const SAVES_PATH: String = "/v1/saves/"
const METHOD_GET: String = "GET"
const METHOD_PUT: String = "PUT"
const HTTP_OK: int = 200
const HTTP_OK_LAST: int = 299
const HTTP_CLIENT_ERROR: int = 400
const HTTP_CLIENT_ERROR_LAST: int = 499
const HTTP_NOT_FOUND: int = 404
const HTTP_CONFLICT: int = 409
const HTTP_TOO_MANY_REQUESTS: int = 429
const ERROR_DISABLED: String = "disabled"
const ERROR_BAD_RESPONSE: String = "bad_response"
const ERROR_EMPTY_BLOB: String = "empty_blob"
const ERROR_TOO_LARGE: String = "too_large"
const ERROR_CONFLICT: String = "conflict"
const ERROR_HTTP: String = "http_%d"

var base_url: String = ""
var transport: Callable
## Opaque random install id (PlayerProfile.install_id) naming the save slot.
var install_id: String = ""
var app_version: String = ""


## [param p_base_url] "" disables the provider; [param p_transport] follows
## the HTTP contract above; [param p_app_version] defaults to AppInfo.version().
func _init(p_base_url: String, p_transport: Callable, p_install_id: String, p_app_version: String = "") -> void:
	var url: String = p_base_url.strip_edges()
	while url.ends_with("/"):
		url = url.substr(0, url.length() - 1)
	base_url = url
	transport = p_transport
	install_id = p_install_id
	app_version = p_app_version if not p_app_version.is_empty() else AppInfo.version()


## False without a base URL, a transport or an install id.
func is_enabled() -> bool:
	return not base_url.is_empty() and transport.is_valid() and not install_id.is_empty()


## The save slot of this install.
func slot_url() -> String:
	return base_url + SAVES_PATH + install_id.uri_encode()


## Request body of the PUT (public so the server contract is testable).
func build_push_body(blob: String, base_revision: String) -> Dictionary:
	return {"blob": blob, "base_revision": base_revision, "app_version": app_version}


## GETs the cloud copy; see the class description for the result mapping.
func fetch() -> Dictionary:
	if not is_enabled():
		return CloudSaveProvider.fetch_result(false, false, "", "", false, ERROR_DISABLED)
	var response: Variant = await transport.call(METHOD_GET, slot_url(), {})
	var r: Dictionary = HttpLeaderboardBackend.normalize_response(response)
	var status: int = int(r["status"])
	var body: Dictionary = r["body"] as Dictionary
	if status == HTTP_NOT_FOUND:
		return CloudSaveProvider.fetch_result(true, false, "", "", false)
	if not HttpCloudSaveProvider._is_success(status):
		var transient: bool = HttpCloudSaveProvider.is_transient(status)
		return CloudSaveProvider.fetch_result(false, false, "", "", transient, HttpCloudSaveProvider._error_of(r))
	var blob: String = HttpCloudSaveProvider.valid_blob(body.get("blob", null))
	var revision: String = CloudSaveProvider.valid_revision(body.get("revision", null))
	if blob.is_empty() or revision.is_empty():
		return CloudSaveProvider.fetch_result(false, false, "", "", true, ERROR_BAD_RESPONSE)
	return CloudSaveProvider.fetch_result(true, true, blob, revision, false)


## PUTs [param blob] as the successor of [param base_revision]; see the class
## description for the result mapping. An empty or oversized blob is refused
## before anything is sent.
func push(blob: String, base_revision: String) -> Dictionary:
	if not is_enabled():
		return CloudSaveProvider.push_result(false, "", false, false, ERROR_DISABLED)
	if blob.is_empty() or blob.length() > SaveService.MAX_SAVE_CHARS:
		return CloudSaveProvider.push_result(
			false, "", false, false, ERROR_EMPTY_BLOB if blob.is_empty() else ERROR_TOO_LARGE
		)
	var response: Variant = await transport.call(METHOD_PUT, slot_url(), build_push_body(blob, base_revision))
	var r: Dictionary = HttpLeaderboardBackend.normalize_response(response)
	var status: int = int(r["status"])
	var body: Dictionary = r["body"] as Dictionary
	if HttpCloudSaveProvider._is_success(status):
		var revision: String = CloudSaveProvider.valid_revision(body.get("revision", null))
		if revision.is_empty():
			return CloudSaveProvider.push_result(false, "", false, true, ERROR_BAD_RESPONSE)
		return CloudSaveProvider.push_result(true, revision, false, false)
	if status == HTTP_CONFLICT:
		return HttpCloudSaveProvider._conflict_result(body)
	return CloudSaveProvider.push_result(
		false, "", false, HttpCloudSaveProvider.is_transient(status), HttpCloudSaveProvider._error_of(r)
	)


## True for statuses worth retrying later: no answer (0), 429, 5xx and anything
## that is neither a success nor a client error.
static func is_transient(status: int) -> bool:
	if status == HTTP_TOO_MANY_REQUESTS:
		return true
	return status < HTTP_CLIENT_ERROR or status > HTTP_CLIENT_ERROR_LAST


## [param raw] when it is a non-empty String within the save size cap, else "".
static func valid_blob(raw: Variant) -> String:
	if typeof(raw) != TYPE_STRING:
		return ""
	var text: String = raw as String
	return text if text.length() <= SaveService.MAX_SAVE_CHARS else ""


## A 409 carries the server's current copy; without a usable one the push
## is simply retried later.
static func _conflict_result(body: Dictionary) -> Dictionary:
	var blob: String = HttpCloudSaveProvider.valid_blob(body.get("blob", null))
	var revision: String = CloudSaveProvider.valid_revision(body.get("revision", null))
	if blob.is_empty() or revision.is_empty():
		return CloudSaveProvider.push_result(false, "", false, true, ERROR_BAD_RESPONSE)
	return CloudSaveProvider.push_result(false, "", true, false, ERROR_CONFLICT, blob, revision)


static func _is_success(status: int) -> bool:
	return status >= HTTP_OK and status <= HTTP_OK_LAST


## The transport's error for unanswered requests, "http_<status>" otherwise.
static func _error_of(normalized: Dictionary) -> String:
	var status: int = int(normalized["status"])
	return str(normalized["error"]) if status == 0 else ERROR_HTTP % status
