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
## Control characters: C0 below CONTROL_C0_END, DEL and C1 from CONTROL_DEL
## up to (excluding) CONTROL_C1_END.
const CONTROL_C0_END: int = 0x20
const CONTROL_DEL: int = 0x7F
const CONTROL_C1_END: int = 0xA0
const SPACE: int = 0x20
## Raw names longer than max_length times this are cut before sanitising.
const RAW_NAME_FACTOR: int = 4
## Invisible direction / zero-width marks that could disguise a name.
const INVISIBLE_MARKS: PackedInt32Array = [
	0x200B,
	0x200C,
	0x200D,
	0x200E,
	0x200F,
	0x202A,
	0x202B,
	0x202C,
	0x202D,
	0x202E,
	0x2066,
	0x2067,
	0x2068,
	0x2069,
	0xFEFF,
]
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
## HTTP contract above; [param p_app_version] defaults to AppInfo.version();
## [param config] is the "leaderboard" section of data/daily/daily.json.
func _init(
	p_base_url: String, p_transport: Callable, p_install_id: String, p_app_version: String = "", config: Dictionary = {}
) -> void:
	var url: String = p_base_url.strip_edges()
	while url.ends_with("/"):
		url = url.substr(0, url.length() - 1)
	base_url = url
	transport = p_transport
	install_id = p_install_id
	app_version = p_app_version if not p_app_version.is_empty() else AppInfo.version()
	var max_len: Variant = config.get("name_max_length", DEFAULT_NAME_MAX_LENGTH)
	name_max_length = maxi(1, int(max_len)) if _is_number(max_len) else DEFAULT_NAME_MAX_LENGTH


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
	var score: Variant = entry.get("score", 0)
	var sim_version: Variant = entry.get("sim_version", replay_dict.get("sim_version", RunReplay.SIM_VERSION))
	return {
		"board": board_id,
		"score": int(score) if _is_number(score) else 0,
		"replay": replay_dict,
		"level_id": str(entry.get("level_id", "")),
		"mode": str(entry.get("mode", "")),
		"app_version": app_version,
		"install_id": install_id,
		"sim_version": int(sim_version) if _is_number(sim_version) else RunReplay.SIM_VERSION,
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
		# Untrusted body: only a JSON true counts (bool(null) would abort).
		var accepted: bool = HttpLeaderboardBackend._is_true(payload.get("accepted", true))
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
	var ok: bool = HttpLeaderboardBackend._is_true(r.get("ok", false))
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
	var name_v: Variant = raw.get("name", "")
	var name: String = sanitize_name(name_v as String if typeof(name_v) == TYPE_STRING else "", name_max_length)
	return {
		"rank": maxi(rank, 0),
		"name": name,
		"score": maxi(0, int(score_v)),
		"is_player": HttpLeaderboardBackend._is_true(raw.get("is_player", false)),
	}


## Display-safe version of an untrusted player name: control characters
## become spaces, invisible direction / zero-width marks are removed, runs of
## spaces collapse, and the result is trimmed to [param max_length].
static func sanitize_name(raw: String, max_length: int) -> String:
	var text: String = raw.substr(0, maxi(1, max_length) * RAW_NAME_FACTOR)
	var out: String = ""
	var last_space: bool = true
	for i: int in text.length():
		var code: int = text.unicode_at(i)
		if INVISIBLE_MARKS.has(code):
			continue
		var is_control: bool = code < CONTROL_C0_END or (code >= CONTROL_DEL and code < CONTROL_C1_END)
		var is_space: bool = is_control or code == SPACE
		if is_space:
			if not last_space:
				out += " "
			last_space = true
			continue
		out += text[i]
		last_space = false
	out = out.strip_edges()
	if out.length() > max_length:
		out = out.substr(0, max_length).strip_edges()
	return out


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


## True only for a real boolean true (untrusted data: comparing a string or
## number with == true is a script error in Godot 4).
static func _is_true(v: Variant) -> bool:
	return typeof(v) == TYPE_BOOL and bool(v)
