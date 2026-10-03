extends TestCase
## LeaderboardService: board ids, ranking rules, local recording, offline
## queue (bounded, deduplicated) and flushing through a scripted transport.

const BASE_URL: String = "https://scores.invalid"
const DATE: String = "2026-10-03"
const NOON: int = 12 * 3600
const SECONDS_PER_DAY: int = 86400


## Test double for the HTTP transport contract. Offline -> ok=false/status 0;
## online -> answers with [member status] and [member reply], except HTTP 500
## for submissions to [member fail_board]. With [member tree] set it behaves
## like the real coroutine transport (awaits a frame).
class ScriptedTransport:
	extends RefCounted
	var online: bool = false
	var status: int = 200
	var reply: Dictionary = {"accepted": true, "rank": 7}
	var fail_board: String = ""
	var calls: Array[Dictionary] = []
	var tree: SceneTree = null

	func request(method: String, url: String, body: Dictionary) -> Dictionary:
		if tree != null:
			await tree.process_frame
		calls.append({"method": method, "url": url, "body": body.duplicate(true)})
		if not online:
			return {"ok": false, "status": 0, "body": null, "error": "offline"}
		if not fail_board.is_empty() and str(body.get("board", "")) == fail_board:
			return {"ok": false, "status": 500, "body": {}, "error": ""}
		return {"ok": status >= 200 and status < 300, "status": status, "body": reply.duplicate(true), "error": ""}


var _clock: GameClock
var _profile: PlayerProfile
var _bus: EventBus
var _transport: ScriptedTransport
var _signals: Array[Dictionary] = []


func before_each() -> void:
	_clock = GameClock.new()
	_clock.set_fixed_unix(DailyChallengeService.day_for_date_key(DATE) * SECONDS_PER_DAY + NOON)
	_profile = PlayerProfile.new()
	_bus = EventBus.new()
	_transport = ScriptedTransport.new()
	_signals.clear()
	_bus.leaderboard_submitted.connect(_on_submitted)


func _on_submitted(board: String, accepted: bool) -> void:
	_signals.append({"board": board, "accepted": accepted})


func _local() -> LocalLeaderboardBackend:
	return LocalLeaderboardBackend.new(LocalLeaderboardBackend.profile_store(_profile))


func _service(with_remote: bool) -> LeaderboardService:
	var remote: LeaderboardBackend = null
	if with_remote:
		remote = HttpLeaderboardBackend.new(BASE_URL, _transport.request, _profile.install_id, "1.0.0")
	return LeaderboardService.new(_profile, _bus, _clock, _local(), remote)


func _run(level_id: String, mode: StringName, completed: bool, score: int) -> RunResult:
	var r: RunResult = RunResult.new()
	r.level_id = level_id
	r.mode = mode
	r.completed = completed
	r.score = score
	r.replay = RunReplay.new()
	r.replay.level_id = level_id
	r.replay.mode = mode
	r.replay.tap_ticks = PackedInt32Array([30, 90, 150])
	r.replay.end_tick = 600
	return r


func test_board_ids_for_modes() -> void:
	var svc: LeaderboardService = _service(false)
	assert_eq(GameClock.week_key_for_day(DailyChallengeService.day_for_date_key(DATE)), "2026-W40")
	var classic: PackedStringArray = svc.board_ids_for(_run("w03_l10", &"classic", true, 4000), DATE)
	assert_eq(classic, PackedStringArray(["weekly:2026-W40:classic", "alltime:classic", "level:w03_l10"]))
	var daily: PackedStringArray = svc.board_ids_for(_run("daily_" + DATE, &"daily", true, 900), DATE)
	assert_eq(daily, PackedStringArray(["daily:2026-10-03", "weekly:2026-W40:daily", "alltime:daily"]))
	var endless: PackedStringArray = svc.board_ids_for(_run("endless_run", &"endless", false, 7000), DATE)
	assert_eq(endless, PackedStringArray(["weekly:2026-W40:endless", "alltime:endless"]), "endless ranks failed runs")
	var late: PackedStringArray = svc.board_ids_for(_run("daily_2026-10-02", &"daily", true, 900), DATE)
	assert_eq(late[0], "daily:2026-10-02", "daily board uses the level's date")


func test_revived_zen_incomplete_and_unknown_runs_not_ranked() -> void:
	var svc: LeaderboardService = _service(true)
	_transport.online = true
	var revived: RunResult = _run("w01_l10", &"classic", true, 900)
	revived.revived = true
	var cases: Array[RunResult] = [
		revived,
		_run("w01_l10", &"zen", true, 900),
		_run("w01_l10", &"classic", false, 900),
		_run("w01_l10", &"made_up_mode", true, 900),
		_run("daily_bad-date", &"daily", true, 900),
		_run("daily_" + DATE, &"classic", true, 900),
		_run("w01_l10", &"daily", true, 900),
	]
	for r: RunResult in cases:
		assert_empty(svc.board_ids_for(r, DATE), "%s/%s not ranked" % [r.mode, r.level_id])
		assert_false(svc.is_ranked(r))
		await svc.submit_run(r)
	assert_empty(_transport.calls, "nothing sent")
	assert_empty(_signals, "nothing announced")
	assert_empty(_local().board_ids(), "nothing recorded")
	assert_false(svc.is_ranked(null))


func test_local_only_records_and_emits() -> void:
	var svc: LeaderboardService = _service(false)
	await svc.submit_run(_run("w03_l10", &"classic", true, 4115))
	assert_eq(_signals.size(), 3)
	for s: Dictionary in _signals:
		assert_true(bool(s["accepted"]))
	var board: Dictionary = await svc.fetch("level:w03_l10")
	assert_eq(str(board["source"]), "local")
	assert_eq(str(board["status_key"]), "online.lb.local_only")
	var entries: Array = board["entries"] as Array
	assert_eq(entries.size(), 1, "only the player's own run")
	assert_eq(int((entries[0] as Dictionary)["score"]), 4115)
	assert_true(bool((entries[0] as Dictionary)["is_player"]))
	assert_eq(int((board["player"] as Dictionary)["rank"]), 1)


func test_online_submission_accepted() -> void:
	_transport.online = true
	var svc: LeaderboardService = _service(true)
	await svc.submit_run(_run("w03_l10", &"classic", true, 4115))
	assert_eq(_transport.calls.size(), 3)
	assert_eq(svc.pending_count(), 0)
	assert_eq(_signals.size(), 3)
	assert_true(bool(_signals[0]["accepted"]))
	assert_eq(_local().best_score("alltime:classic"), 4115, "also recorded locally")


func test_offline_queues_then_flushes_when_transport_recovers() -> void:
	var svc: LeaderboardService = _service(true)
	await svc.submit_run(_run("w03_l10", &"classic", true, 4115))
	assert_eq(svc.pending_count(), 3, "all boards queued")
	assert_eq(_transport.calls.size(), 1, "stops calling after the first offline answer")
	assert_empty(_signals, "no outcome yet")
	assert_eq(_local().best_score("level:w03_l10"), 4115, "local record still happens offline")
	var head_id: String = str(_profile.pending_submissions[0]["id"])
	var still_offline: int = await svc.flush_queue()
	assert_eq(still_offline, 0)
	assert_eq(svc.pending_count(), 3, "kept while offline")
	var tail: Dictionary = _profile.pending_submissions[_profile.pending_submissions.size() - 1]
	assert_eq(str(tail["id"]), head_id, "failed item rotated to the back")
	assert_eq(int(tail["attempts"]), 1)
	_transport.online = true
	var delivered: int = await svc.flush_queue()
	assert_eq(delivered, 3)
	assert_eq(svc.pending_count(), 0)
	assert_eq(_signals.size(), 3)
	for s: Dictionary in _signals:
		assert_true(bool(s["accepted"]), "accepted after flush")
	var last: Dictionary = _transport.calls[_transport.calls.size() - 1]
	assert_eq(str(last["method"]), "POST")
	assert_eq(str(last["url"]), BASE_URL + "/v1/scores")


func test_async_transport_coroutine_flush() -> void:
	_transport.tree = tree
	var svc: LeaderboardService = _service(true)
	await svc.submit_run(_run("daily_" + DATE, &"daily", true, 800))
	assert_eq(svc.pending_count(), 3)
	_transport.online = true
	var delivered: int = await svc.flush_queue()
	assert_eq(delivered, 3, "coroutine transport awaited correctly")
	assert_eq(svc.pending_count(), 0)


func test_queue_is_bounded_and_deduplicated() -> void:
	_profile.pending_submissions.append({"kind": "analytics", "events": 3})
	var svc: LeaderboardService = _service(true)
	var run: RunResult = _run("w01_l10", &"classic", true, 500)
	await svc.submit_run(run)
	await svc.submit_run(run)
	assert_eq(svc.pending_count(), 3, "same board+score+level not queued twice")
	for i: int in 40:
		await svc.submit_run(_run("w01_l%02d" % (i % 50 + 1), &"classic", true, 1000 + i))
	assert_eq(svc.pending_count(), 50, "bounded at 50")
	assert_eq(str(_profile.pending_submissions[0]["kind"]), "analytics", "other queues untouched")
	var newest: Dictionary = _profile.pending_submissions[_profile.pending_submissions.size() - 1]
	assert_eq(int((newest["entry"] as Dictionary)["score"]), 1039, "oldest dropped, newest kept")


func test_rejected_submission_not_queued() -> void:
	_transport.online = true
	_transport.status = 422
	_transport.reply = {"accepted": false, "reasons": ["score_mismatch"]}
	var svc: LeaderboardService = _service(true)
	await svc.submit_run(_run("w01_l10", &"classic", true, 999999))
	assert_eq(svc.pending_count(), 0, "verification failures are final")
	assert_eq(_signals.size(), 3)
	assert_false(bool(_signals[0]["accepted"]))


func test_server_errors_are_retried_later() -> void:
	_transport.online = true
	_transport.status = 503
	var svc: LeaderboardService = _service(true)
	await svc.submit_run(_run("w01_l10", &"classic", true, 999))
	assert_eq(svc.pending_count(), 3)
	_transport.status = 200
	assert_eq(await svc.flush_queue(), 3)


func test_stale_queue_entries_are_pruned() -> void:
	var svc: LeaderboardService = _service(true)
	await svc.submit_run(_run("daily_" + DATE, &"daily", true, 800))
	assert_eq(svc.pending_count(), 3)
	# Five days later the daily board is outside the server window; the
	# weekly/all-time entries are still young enough to send.
	_clock.set_fixed_unix(_clock.now_unix() + 5 * SECONDS_PER_DAY)
	_transport.online = true
	var calls_before: int = _transport.calls.size()
	assert_eq(await svc.flush_queue(), 2, "stale daily dropped before sending")
	for i: int in range(calls_before, _transport.calls.size()):
		assert_ne(str((_transport.calls[i]["body"] as Dictionary)["board"]), "daily:" + DATE)
	await svc.submit_run(_run("w01_l10", &"classic", true, 1))
	_transport.online = false
	await svc.submit_run(_run("w01_l11", &"classic", true, 2))
	_clock.set_fixed_unix(_clock.now_unix() + 30 * SECONDS_PER_DAY)
	_transport.online = true
	assert_eq(await svc.flush_queue(), 0, "entries older than the max age dropped")
	assert_eq(svc.pending_count(), 0)


func test_weekly_entries_outside_server_window_are_pruned() -> void:
	var svc: LeaderboardService = _service(true)
	await svc.submit_run(_run("daily_" + DATE, &"daily", true, 800))
	assert_eq(svc.pending_count(), 3)
	# Nine days later is ISO week 42: the daily and the week-40 board are
	# outside the server window; only the all-time entry is still accepted.
	_clock.set_fixed_unix(_clock.now_unix() + 9 * SECONDS_PER_DAY)
	_transport.online = true
	var before: int = _transport.calls.size()
	assert_eq(await svc.flush_queue(), 1)
	assert_eq(_transport.calls.size() - before, 1, "stale boards never sent")
	assert_eq(str((_transport.calls[before]["body"] as Dictionary)["board"]), "alltime:daily")
	assert_eq(svc.pending_count(), 0)


func test_failing_item_does_not_block_the_queue() -> void:
	var svc: LeaderboardService = _service(true)
	await svc.submit_run(_run("w01_l10", &"classic", true, 500))
	assert_eq(str(_profile.pending_submissions[0]["board"]), "weekly:2026-W40:classic", "queue head")
	_transport.online = true
	_transport.fail_board = "weekly:2026-W40:classic"
	assert_eq(await svc.flush_queue(), 0, "head keeps failing and moves to the back")
	assert_eq(await svc.flush_queue(), 2, "the other submissions still go through")
	assert_eq(svc.pending_count(), 1)
	assert_eq(str(_profile.pending_submissions[0]["board"]), "weekly:2026-W40:classic")
	_transport.fail_board = ""
	assert_eq(await svc.flush_queue(), 1)
	assert_eq(svc.pending_count(), 0)


func test_corrupted_queue_items_do_not_break_flushing() -> void:
	var svc: LeaderboardService = _service(true)
	var now: int = _clock.now_unix()
	var entry: Dictionary = {"score": 10, "level_id": "w01_l10", "mode": "classic", "replay": {"level_id": "w01_l10"}}
	var items: Array[Dictionary] = [
		{"id": "a", "board": "alltime:classic", "entry": entry, "queued_at": now, "attempts": null},
		{"id": "b", "board": "alltime:classic", "entry": entry},
		{"id": "c", "board": "nonsense", "queued_at": now},
		{"id": "d", "board": "alltime:classic", "entry": "junk", "queued_at": now},
	]
	for item: Dictionary in items:
		item["kind"] = LeaderboardService.QUEUE_KIND
		_profile.pending_submissions.append(item)
	assert_eq(await svc.flush_queue(), 0, "offline")
	assert_eq(svc.pending_count(), 2, "undated and malformed-board items dropped")
	var a: Dictionary = _profile.pending_submissions[_profile.pending_submissions.size() - 1]
	assert_eq(str(a["id"]), "a")
	assert_eq(int(a["attempts"]), 1, "null attempts counted from zero")
	_transport.online = true
	assert_eq(await svc.flush_queue(), 1, "flushing still works afterwards")
	assert_eq(svc.pending_count(), 0, "junk entry dropped")


func test_remote_without_replay_is_not_reported_as_accepted() -> void:
	_transport.online = true
	var svc: LeaderboardService = _service(true)
	var run: RunResult = _run("w03_l10", &"classic", true, 4115)
	run.replay = null
	await svc.submit_run(run)
	assert_empty(_transport.calls, "nothing the server could verify was sent")
	assert_eq(_signals.size(), 3)
	for s: Dictionary in _signals:
		assert_false(bool(s["accepted"]), "never announced as accepted")
	assert_eq(svc.pending_count(), 0)
	assert_eq(_local().best_score("alltime:classic"), 4115, "still a personal best")


func test_fetch_prefers_remote_and_falls_back_offline() -> void:
	var svc: LeaderboardService = _service(true)
	_transport.online = true
	await svc.submit_run(_run("w03_l10", &"classic", true, 4115))
	_transport.reply = {"entries": [{"rank": 1, "name": "Nova", "score": 9000}], "player": {"rank": 12, "score": 4115}}
	var remote: Dictionary = await svc.fetch("alltime:classic", 10)
	assert_eq(str(remote["source"]), "remote")
	assert_eq(str(((remote["entries"] as Array)[0] as Dictionary)["name"]), "Nova")
	assert_eq(int((remote["player"] as Dictionary)["rank"]), 12)
	_transport.online = false
	var local: Dictionary = await svc.fetch("alltime:classic", 10)
	assert_eq(str(local["source"]), "local")
	assert_eq(str(local["status_key"]), "online.lb.offline")
	assert_eq((local["entries"] as Array).size(), 1, "offline: only the player's own best, nobody invented")


func test_parse_board_round_trips() -> void:
	assert_eq(LeaderboardService.parse_board("daily:2026-10-03")["date_key"], "2026-10-03")
	var weekly: Dictionary = LeaderboardService.parse_board(LeaderboardService.weekly_board("2026-W40", "classic"))
	assert_eq(weekly["week_key"], "2026-W40")
	assert_eq(weekly["mode"], "classic")
	assert_eq(LeaderboardService.parse_board("alltime:endless")["mode"], "endless")
	assert_eq(LeaderboardService.parse_board("level:w01_l01")["level_id"], "w01_l01")
	for bad: String in ["", "daily:2026-13-01", "weekly:2026-W40", "alltime:", "level", "season:1", "daily:a:b"]:
		assert_empty(LeaderboardService.parse_board(bad), "rejects '%s'" % bad)
