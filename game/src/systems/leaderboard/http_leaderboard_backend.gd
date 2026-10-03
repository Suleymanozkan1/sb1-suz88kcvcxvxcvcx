class_name HttpLeaderboardBackend
extends LeaderboardBackend
## Remote leaderboard client. The server re-simulates every submitted replay
## (see server/README.md and [ReplayVerifier]); the client is never trusted.
##
## Endpoints (relative to [member base_url]):
## - POST /v1/scores with {"board", "score", "replay": RunReplay.to_dict(),
##   "level_id", "mode", "app_version", "install_id", "sim_version"}
##   -> 2xx {"accepted": bool, "rank": int, "score": int, "reasons": [..]};
##   400/403/404/409/410/422 = rejected by verification (never retried);
##   429 / 5xx / network failure = transient (the caller queues and retries).
## - GET /v1/boards/{board}?limit=n&install_id=<id>
##   -> {"entries": [{"rank", "name", "score"}], "player": {...}}.
## An empty base URL disables the backend. No hosted backend exists today, so
## the shipped configuration (remote config leaderboard.base_url) is empty.
##
## Network calls go through the injected transport Callable
## (method: String, url: String, body: Dictionary) -> Dictionary
## {"ok", "status", "body", "error"}; it is always awaited.

const SCORES_PATH: String = "/v1/scores"
const BOARDS_PATH: String = "/v1/boards/"
const MAX_FETCH_LIMIT: int = 100
const DEFAULT_NAME_MAX_LENGTH: int = 24
const HTTP_OK: int = 200
const HTTP_OK_LAST: int = 299
const HTTP_TOO_MANY_REQUESTS: int = 429
const REJECT_STATUSES: PackedInt32Array = [400, 403, 404, 409, 410, 422]
const ERROR_DISABLED: String = "disabled"
const ERROR_OFFLINE: String = "offline"
const ERROR_REJECTED: String = "rejected"
const ERROR_BAD_RESPONSE: String = "bad_response"

var base_url: String = ""
var transport: Callable
## Opaque random install id (PlayerProfile.install_id) — not PII.
var install_id: String = ""
var app_version: String = ""
var name_max_length: int = DEFAULT_NAME_MAX_LENGTH


## [param p_base_url] "" disables the backend; [param p_transport] follows the
## HTTP contract above; [param p_app_version] defaults to AppInfo.version().
func _init(p_base_url: String, p_transport: Callable, p_install_id: String, p_app_version: String = "") -> void:
	var url: String = p_base_url.strip_edges()
	while url.ends_with("/"):
		url = url.substr(0, url.length() - 1)
	base_url = url
	transport = p_transport
	install_id = p_install_id
	app_version = p_app_version if not p_app_version.is_empty() else AppInfo.version()


## True: this backend talks to a server.
func is_remote() -> bool:
	return true


## False when no base URL or no transport is configured.
func is_enabled() -> bool:
	return not base_url.is_empty() and transport.is_valid()


## Request body for POST /v1/scores (public so the server contract is testable).
func build_submission(board_id: String, entry: Dictionary) -> Dictionary:
	var replay: Variant = entry.get("replay", {})
	var replay_dict: Dictionary = replay as Dictionary if typeof(replay) == TYPE_DICTIONARY else {}
	return {
		"board": board_id,
		"score": int(entry.get("score", 0)),
		"replay": replay_dict,
		"level_id": str(entry.get("level_id", "")),
		"mode": str(entry.get("mode", "")),
		"app_version": app_version,
		"install_id": install_id,
		"sim_version": int(entry.get("sim_version", replay_dict.get("sim_version", RunReplay.SIM_VERSION))),
	}


## POSTs the score; see the class description for the result mapping.
## Adds "score" (authoritative, when the server returns it) and "reasons".
func submit(board_id: String, entry: Dictionary) -> Dictionary:
	if not is_enabled():
		return LeaderboardBackend.submit_result(false, false, false, ERROR_DISABLED)
	var response: Variant = await transport.call("POST", base_url + SCORES_PATH, build_submission(board_id, entry))
	var r: Dictionary = HttpLeaderboardBackend.normalize_response(response)
	var status: int = int(r["status"])
	var payload: Dictionary = r["body"] as Dictionary
	var result: Dictionary
	if status == 0:
		result = LeaderboardBackend.submit_result(false, false, true, str(r["error"]))
	elif status >= HTTP_OK and status <= HTTP_OK_LAST:
		var accepted: bool = bool(payload.get("accepted", true))
		var rank: int = maxi(0, int(payload.get("rank", 0))) if _is_number(payload.get("rank", 0)) else 0
		result = LeaderboardBackend.submit_result(true, accepted, false, "" if accepted else ERROR_REJECTED, rank)
		if _is_number(payload.get("score", null)):
			result["score"] = int(payload["score"])
	elif REJECT_STATUSES.has(status):
		result = LeaderboardBackend.submit_result(true, false, false, ERROR_REJECTED)
	else:
		result = LeaderboardBackend.submit_result(false, false, true, "http_%d" % status)
	result["reasons"] = _string_list(payload.get("reasons", []))
	return result


## GETs a board. On any failure returns ok=false with empty entries (the
## caller falls back to the local personal board).
func fetch(board_id: String, limit: int) -> Dictionary:
	if not is_enabled():
		return LeaderboardBackend.fetch_result(false, [], {}, ERROR_DISABLED)
	var n: int = clampi(limit, 1, MAX_FETCH_LIMIT)
	var url: String = "%s%s%s?limit=%d" % [base_url, BOARDS_PATH, board_id.uri_encode(), n]
	if not install_id.is_empty():
		url += "&install_id=" + install_id.uri_encode()
	var response: Variant = await transport.call("GET", url, {})
	var r: Dictionary = HttpLeaderboardBackend.normalize_response(response)
	var status: int = int(r["status"])
	if status < HTTP_OK or status > HTTP_OK_LAST:
		var err: String = str(r["error"]) if status == 0 else "http_%d" % status
		return LeaderboardBackend.fetch_result(false, [], {}, err)
	var payload: Dictionary = r["body"] as Dictionary
	var raw_entries: Variant = payload.get("entries", null)
	if typeof(raw_entries) != TYPE_ARRAY:
		return LeaderboardBackend.fetch_result(false, [], {}, ERROR_BAD_RESPONSE)
	var entries: Array = []
	for raw: Variant in raw_entries as Array:
		if entries.size() >= n:
			break
		if typeof(raw) == TYPE_DICTIONARY:
			var clean: Dictionary = _clean_entry(raw as Dictionary, entries.size() + 1)
			if not clean.is_empty():
				entries.append(clean)
	entries.sort_custom(_rank_asc)
	var player: Dictionary = {}
	var raw_player: Variant = payload.get("player", {})
	if typeof(raw_player) == TYPE_DICTIONARY and not (raw_player as Dictionary).is_empty():
		player = _clean_entry(raw_player as Dictionary, 0)
	return LeaderboardBackend.fetch_result(true, entries, player)


## Normalises any transport reply to {"ok", "status", "body": Dictionary,
## "error"}. status 0 means the request never got an HTTP answer (offline).
## A transport that reports ok without a status is treated as HTTP 200.
static func normalize_response(response: Variant) -> Dictionary:
	if typeof(response) != TYPE_DICTIONARY:
		return {"ok": false, "status": 0, "body": {}, "error": ERROR_BAD_RESPONSE}
	var r: Dictionary = response as Dictionary
	var ok: bool = bool(r.get("ok", false))
	var raw_status: Variant = r.get("status", 0)
	var status: int = int(raw_status) if _is_number(raw_status) else 0
	if ok and status == 0:
		status = HTTP_OK
	var body: Variant = r.get("body", {})
	if typeof(body) == TYPE_STRING and not (body as String).is_empty():
		var json: JSON = JSON.new()
		body = json.data if json.parse(body as String) == OK else {}
	var error: String = str(r.get("error", ""))
	if status == 0 and error.is_empty():
		error = ERROR_OFFLINE
	return {
		"ok": ok and status >= HTTP_OK and status <= HTTP_OK_LAST,
		"status": status,
		"body": body as Dictionary if typeof(body) == TYPE_DICTIONARY else {},
		"error": error,
	}


func _clean_entry(raw: Dictionary, fallback_rank: int) -> Dictionary:
	var score_v: Variant = raw.get("score", null)
	if not _is_number(score_v):
		return {}
	var rank_v: Variant = raw.get("rank", fallback_rank)
	var rank: int = int(rank_v) if _is_number(rank_v) else fallback_rank
	var name: String = str(raw.get("name", "")).strip_edges().replace("\n", " ").replace("\t", " ")
	if name.length() > name_max_length:
		name = name.substr(0, name_max_length)
	return {
		"rank": maxi(rank, 0),
		"name": name,
		"score": maxi(0, int(score_v)),
		"is_player": bool(raw.get("is_player", false)),
	}


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _string_list(v: Variant) -> PackedStringArray:
	if typeof(v) == TYPE_PACKED_STRING_ARRAY:
		return (v as PackedStringArray).duplicate()
	var out: PackedStringArray = PackedStringArray()
	if typeof(v) == TYPE_ARRAY:
		for item: Variant in v as Array:
			out.append(str(item))
	return out


static func _rank_asc(a: Variant, b: Variant) -> bool:
	return int((a as Dictionary)["rank"]) < int((b as Dictionary)["rank"])
