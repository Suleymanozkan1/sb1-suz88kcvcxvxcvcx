extends TestCase
## A streamed run (time attack) played like the client plays it — course
## appended chunk by chunk while running — must verify against the course the
## server rebuilds from the seed alone.

const SERVER_UNIX: int = 1790000000
const VERIFY_CLI: GDScript = preload("res://server/verify_replay.gd")


func _server_clock() -> GameClock:
	var clock: GameClock = GameClock.new()
	clock.set_fixed_unix(SERVER_UNIX)
	return clock


func _client_run(mode_id: StringName, seed_override: int = -1) -> Dictionary:
	var modes: ModeCatalog = ModeCatalog.shared()
	var catalog: WorldCatalog = WorldCatalog.load_default()
	var seed_value: int = ModeCatalog.endless_seed(mode_id, _server_clock().week_key())
	if seed_override >= 0:
		seed_value = seed_override
	var streamer: EndlessStreamer = modes.make_streamer(mode_id, seed_value, catalog, DifficultyModel.new(catalog))
	var data: Dictionary = streamer.begin()
	var session: GameplaySession = GameplaySession.new()
	tree.root.add_child(session)
	session.load_level(data, modes.sim_modifiers(mode_id))
	session.begin(0.0)
	var guard: int = 0
	while session.sim.is_running() and guard < 60 * 120:
		session.step_ticks(1, streamer.planned_taps())
		streamer.pump(session.sim)
		guard += 1
	var result: RunResult = RunResult.from_sim(session.sim, session.level_data, mode_id)
	var replay: RunReplay = session.replay
	replay.end_tick = session.sim.tick
	session.queue_free()
	return {"result": result, "replay": replay, "level_id": str(data["id"])}


func test_time_attack_replay_verifies_on_rebuilt_course() -> void:
	var run: Dictionary = _client_run(&"time_attack")
	var result: RunResult = run["result"] as RunResult
	assert_true(result.completed, "the planned path survives until the time limit")
	assert_near(result.time_seconds, 60.0, 0.1)
	var replay: RunReplay = run["replay"] as RunReplay
	var week: String = _server_clock().week_key()
	var submission: Dictionary = {
		"score": result.score,
		"board": "weekly:%s:time_attack" % week,
		"mode": "time_attack",
		"level_id": run["level_id"],
		"sim_version": replay.sim_version,
		"replay": replay.to_dict(),
	}
	var cli: Object = VERIFY_CLI.new()
	var config: Dictionary = DailyChallengeService.load_config()
	var level: Dictionary = cli.call("load_level", str(run["level_id"]), config, replay.end_tick) as Dictionary
	assert_false(level.is_empty(), "server rebuilds the streamed course from its id")
	var verdict: Dictionary = ReplayVerifier.new(_server_clock(), config).verify(submission, level)
	assert_true(bool(verdict["valid"]), "genuine streamed run verifies: %s" % str(verdict["details"]))
	assert_eq(int(verdict["score"]), result.score, "authoritative score matches")
	submission["score"] = result.score + 500
	assert_false(
		bool(ReplayVerifier.new(_server_clock(), config).verify(submission, level)["valid"]), "tampered score rejected"
	)
	(cli as Object).free()


func test_off_week_seed_is_rejected_on_the_weekly_board() -> void:
	var run: Dictionary = _client_run(&"time_attack", 1)
	var result: RunResult = run["result"] as RunResult
	var replay: RunReplay = run["replay"] as RunReplay
	var config: Dictionary = DailyChallengeService.load_config()
	var submission: Dictionary = {
		"score": result.score,
		"board": "weekly:%s:time_attack" % _server_clock().week_key(),
		"mode": "time_attack",
		"level_id": run["level_id"],
		"sim_version": replay.sim_version,
		"replay": replay.to_dict(),
	}
	var cli: Object = VERIFY_CLI.new()
	var level: Dictionary = cli.call("load_level", str(run["level_id"]), config, replay.end_tick) as Dictionary
	var verdict: Dictionary = ReplayVerifier.new(_server_clock(), config).verify(submission, level)
	assert_false(bool(verdict["valid"]), "a self-chosen course cannot enter the weekly board")
	assert_has(verdict["reasons"], ReplayVerifier.REASON_SEED_MISMATCH)
	(cli as Object).free()


func test_cli_refuses_bad_streams_before_rebuilding_them() -> void:
	var cli: Object = VERIFY_CLI.new()
	var config: Dictionary = DailyChallengeService.load_config()
	var verifier: ReplayVerifier = ReplayVerifier.new(_server_clock(), config)
	var week: String = _server_clock().week_key()
	var official_ta: String = ModeCatalog.stream_id(&"time_attack", ModeCatalog.endless_seed(&"time_attack", week))
	var official_endless: String = ModeCatalog.stream_id(&"endless", ModeCatalog.endless_seed(&"endless", week))
	var cases: Dictionary = {
		"zen_12345": ReplayVerifier.REASON_UNRANKED_MODE,
		"endless_777": ReplayVerifier.REASON_SEED_MISMATCH,
		official_ta: ReplayVerifier.REASON_END_TICK,
	}
	for id: String in cases:
		var t0: int = Time.get_ticks_msec()
		var verdict: Dictionary = cli.call("precheck", verifier, id, 108000) as Dictionary
		assert_false(bool(verdict.get("valid", true)), id)
		assert_has(verdict["reasons"], cases[id], id)
		assert_lt(float(Time.get_ticks_msec() - t0), 50.0, "%s refused without a rebuild" % id)
	assert_true((cli.call("precheck", verifier, official_endless, 6000) as Dictionary).is_empty(), "official seed")
	assert_true((cli.call("precheck", verifier, "w03_l10", 3000) as Dictionary).is_empty(), "campaign untouched")
