extends TestCase
## Leaderboard backends: local personal boards (never invent players) and the
## HTTP client contract (URLs, bodies, response mapping, sanitising).

const BASE_URL: String = "https://scores.invalid"


## Test double for the HTTP transport: returns [member next] for every call
## and records the calls.
class ScriptedTransport:
	extends RefCounted
	var next: Variant = {"ok": true, "status": 200, "body": {"accepted": true}, "error": ""}
	var calls: Array[Dictionary] = []

	func request(method: String, url: String, body: Dictionary) -> Dictionary:
		calls.append({"method": method, "url": url, "body": body.duplicate(true)})
		return next as Dictionary if typeof(next) == TYPE_DICTIONARY else {}


var _transport: ScriptedTransport


func before_each() -> void:
	_transport = ScriptedTransport.new()


func _entry(score: int, at: int = 100) -> Dictionary:
	return {"score": score, "level_id": "w01_l05", "mode": "classic", "at": at}


func test_local_keeps_personal_top_entries() -> void:
	var store: Dictionary = {}
	var local: LocalLeaderboardBackend = LocalLeaderboardBackend.new(store, {"local_entries_per_board": 3})
	var r1: Dictionary = await local.submit("alltime:classic", _entry(500))
	assert_true(bool(r1["stored"]) and bool(r1["personal_best"]))
	await local.submit("alltime:classic", _entry(900))
	await local.submit("alltime:classic", _entry(700))
	var low: Dictionary = await local.submit("alltime:classic", _entry(100))
	assert_false(bool(low["stored"]), "outside the personal top 3")
	assert_eq(int(low["rank"]), 0)
	var mid: Dictionary = await local.submit("alltime:classic", _entry(800))
	assert_eq(int(mid["rank"]), 2)
	var board: Dictionary = await local.fetch("alltime:classic", 10)
	var scores: Array = []
	for e: Variant in board["entries"] as Array:
		scores.append(int((e as Dictionary)["score"]))
		assert_true(bool((e as Dictionary)["is_player"]), "every row is the player")
		assert_eq(str((e as Dictionary)["name_key"]), "online.lb.you")
	assert_eq(scores, [900, 800, 700])
	assert_eq(local.best_score("alltime:classic"), 900)
	assert_eq(local.best_score("alltime:endless"), -1)
	var empty: Dictionary = await local.fetch("alltime:endless", 10)
	assert_true(bool(empty["ok"]))
	assert_empty(empty["entries"] as Array, "no invented rows on an empty board")
	assert_empty(empty["player"] as Dictionary)
	assert_true(store.has("alltime:classic"), "writes go to the provided store")


func test_local_rejects_invalid_input() -> void:
	var local: LocalLeaderboardBackend = LocalLeaderboardBackend.new({})
	assert_false(bool((await local.submit("", _entry(5)))["ok"]))
	assert_false(bool((await local.submit("alltime:classic", {"score": -4}))["ok"]))
	assert_false(bool((await local.submit("alltime:classic", {"score": "lots"}))["ok"]))
	assert_false(local.is_remote())


func test_local_board_limit_drops_least_recent_board() -> void:
	var local: LocalLeaderboardBackend = LocalLeaderboardBackend.new({}, {"local_board_limit": 2})
	await local.submit("daily:2026-10-01", _entry(10, 1000))
	await local.submit("daily:2026-10-02", _entry(10, 2000))
	await local.submit("daily:2026-10-03", _entry(10, 3000))
	assert_eq(local.board_ids(), PackedStringArray(["daily:2026-10-02", "daily:2026-10-03"]))


func test_local_store_sanitizes_corruption() -> void:
	var store: Dictionary = {
		"alltime:classic": {"entries": [{"score": 50}, "junk", {"score": "x"}, {"score": 300}], "updated": "never"},
		"level:w01_l01": "not a board",
	}
	var local: LocalLeaderboardBackend = LocalLeaderboardBackend.new(store)
	var board: Dictionary = await local.fetch("alltime:classic", 10)
	var entries: Array = board["entries"] as Array
	assert_eq(entries.size(), 2, "junk rows dropped")
	assert_eq(int((entries[0] as Dictionary)["score"]), 300, "re-sorted")
	var res: Dictionary = await local.submit("level:w01_l01", _entry(42))
	assert_true(bool(res["stored"]), "broken board replaced")


func test_profile_store_lives_in_daily_slice() -> void:
	var profile: PlayerProfile = PlayerProfile.new()
	var store: Dictionary = LocalLeaderboardBackend.profile_store(profile)
	var local: LocalLeaderboardBackend = LocalLeaderboardBackend.new(store)
	await local.submit("alltime:classic", _entry(77))
	var saved: Dictionary = JSON.parse_string(JsonIO.canonical(profile.to_dict())) as Dictionary
	var restored: PlayerProfile = PlayerProfile.from_dict(saved)
	var again: LocalLeaderboardBackend = LocalLeaderboardBackend.new(LocalLeaderboardBackend.profile_store(restored))
	assert_eq(again.best_score("alltime:classic"), 77, "persists with the profile")


func test_http_disabled_without_base_url() -> void:
	var http: HttpLeaderboardBackend = HttpLeaderboardBackend.new("", _transport.request, "abc")
	assert_false(http.is_enabled())
	assert_true(http.is_remote())
	var res: Dictionary = await http.submit("alltime:classic", _entry(5))
	assert_eq(str(res["error"]), "disabled")
	assert_false(bool(res["retry"]), "disabled is not a transient failure")
	var board: Dictionary = await http.fetch("alltime:classic", 10)
	assert_false(bool(board["ok"]))
	assert_empty(_transport.calls, "no network traffic when disabled")
	assert_false(HttpLeaderboardBackend.new(BASE_URL, Callable(), "abc").is_enabled(), "needs a transport")


func test_http_submission_contract() -> void:
	var http: HttpLeaderboardBackend = HttpLeaderboardBackend.new(BASE_URL + "//", _transport.request, "abc123", "1.2.3")
	var replay: RunReplay = RunReplay.new()
	replay.level_id = "w01_l05"
	replay.level_seed = 99
	replay.tap_ticks = PackedInt32Array([10, 40])
	replay.end_tick = 300
	var entry: Dictionary = _entry(640)
	entry["replay"] = replay.to_dict()
	entry["sim_version"] = RunReplay.SIM_VERSION
	_transport.next = {"ok": true, "status": 201, "body": {"accepted": true, "rank": 4, "score": 640}, "error": ""}
	var res: Dictionary = await http.submit("level:w01_l05", entry)
	assert_true(bool(res["ok"]) and bool(res["accepted"]))
	assert_eq(int(res["rank"]), 4)
	assert_eq(int(res["score"]), 640)
	var call: Dictionary = _transport.calls[0]
	assert_eq(str(call["method"]), "POST")
	assert_eq(str(call["url"]), BASE_URL + "/v1/scores", "trailing slashes trimmed")
	var body: Dictionary = call["body"] as Dictionary
	for key: String in ["board", "score", "replay", "level_id", "mode", "app_version", "install_id", "sim_version"]:
		assert_true(body.has(key), "body has %s" % key)
	assert_eq(str(body["board"]), "level:w01_l05")
	assert_eq(str(body["install_id"]), "abc123")
	assert_eq(str(body["app_version"]), "1.2.3")
	assert_eq(JsonIO.canonical(body["replay"]), JsonIO.canonical(replay.to_dict()))


func test_http_result_mapping() -> void:
	var http: HttpLeaderboardBackend = HttpLeaderboardBackend.new(BASE_URL, _transport.request, "abc")
	_transport.next = {"ok": false, "status": 0, "body": null, "error": "timeout"}
	var offline: Dictionary = await http.submit("alltime:classic", _entry(1))
	assert_true(bool(offline["retry"]))
	assert_eq(str(offline["error"]), "timeout")
	_transport.next = {"ok": false, "status": 422, "body": {"reasons": ["tap_rate"]}, "error": ""}
	var rejected: Dictionary = await http.submit("alltime:classic", _entry(1))
	assert_true(bool(rejected["ok"]))
	assert_false(bool(rejected["accepted"]))
	assert_false(bool(rejected["retry"]))
	assert_eq(rejected["reasons"], PackedStringArray(["tap_rate"]))
	_transport.next = {"ok": false, "status": 503, "body": {}, "error": ""}
	assert_true(bool((await http.submit("alltime:classic", _entry(1)))["retry"]), "5xx retried")
	_transport.next = {"ok": false, "status": 429, "body": {}, "error": ""}
	assert_true(bool((await http.submit("alltime:classic", _entry(1)))["retry"]), "429 retried")
	_transport.next = {"ok": true, "status": 200, "body": {"accepted": false}, "error": ""}
	var soft: Dictionary = await http.submit("alltime:classic", _entry(1))
	assert_false(bool(soft["accepted"]))
	assert_false(bool(soft["retry"]))


func test_http_fetch_url_and_sanitizing() -> void:
	var http: HttpLeaderboardBackend = HttpLeaderboardBackend.new(BASE_URL, _transport.request, "abc")
	var long_name: String = "A".repeat(60)
	_transport.next = {
		"ok": true,
		"status": 200,
		"body": JSON.stringify({
			"entries": [
				{"rank": 2, "name": "Bo\nlt", "score": 800},
				{"rank": 1, "name": long_name, "score": 900},
				{"rank": 3, "name": "NoScore"},
				"junk",
			],
			"player": {"rank": 40, "name": "Me", "score": 120},
		}),
		"error": "",
	}
	var board: Dictionary = await http.fetch("daily:2026-10-03", 500)
	var url: String = str(_transport.calls[0]["url"])
	assert_eq(url, BASE_URL + "/v1/boards/daily%3A2026-10-03?limit=100&install_id=abc", "encoded board, clamped limit")
	assert_eq(str(_transport.calls[0]["method"]), "GET")
	assert_true(bool(board["ok"]))
	var entries: Array = board["entries"] as Array
	assert_eq(entries.size(), 2, "entries without a score dropped")
	assert_eq(int((entries[0] as Dictionary)["rank"]), 1, "sorted by rank")
	assert_eq(str((entries[0] as Dictionary)["name"]).length(), 24, "names truncated")
	assert_eq(str((entries[1] as Dictionary)["name"]), "Bo lt", "control characters removed")
	assert_eq(int((board["player"] as Dictionary)["rank"]), 40)
	_transport.next = {"ok": true, "status": 200, "body": {"unexpected": true}, "error": ""}
	assert_false(bool((await http.fetch("daily:2026-10-03", 5))["ok"]), "malformed body is a failure")
	_transport.next = {"ok": false, "status": 0, "body": null, "error": ""}
	var offline: Dictionary = await http.fetch("daily:2026-10-03", 5)
	assert_false(bool(offline["ok"]))
	assert_eq(str(offline["error"]), "offline")


func test_normalize_response_variants() -> void:
	var bad: Dictionary = HttpLeaderboardBackend.normalize_response("nonsense")
	assert_eq(int(bad["status"]), 0)
	assert_false(bool(bad["ok"]))
	var bare_ok: Dictionary = HttpLeaderboardBackend.normalize_response({"ok": true})
	assert_eq(int(bare_ok["status"]), 200, "ok without status treated as 200")
	assert_true(bool(bare_ok["ok"]))
	var raw_text: Dictionary = {"ok": true, "status": 200, "body": "{\"rank\": 3}"}
	var text_body: Dictionary = HttpLeaderboardBackend.normalize_response(raw_text)
	assert_eq(int((text_body["body"] as Dictionary)["rank"]), 3, "JSON text bodies parsed")
	var not_json: Dictionary = HttpLeaderboardBackend.normalize_response({"ok": true, "status": 200, "body": "<html>"})
	assert_empty(not_json["body"] as Dictionary)
