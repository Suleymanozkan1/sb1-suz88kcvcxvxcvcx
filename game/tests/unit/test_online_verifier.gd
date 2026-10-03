extends TestCase
## ReplayVerifier: authoritative re-simulation of score submissions.

const DATE: String = "2026-10-03"
const NOON: int = 12 * 3600
const SECONDS_PER_DAY: int = 86400
const INSTALL_ID: String = "0123456789abcdef0123456789abcdef"

var _clock: GameClock
var _config: Dictionary
var _verifier: ReplayVerifier
var _repo: LevelRepository


func before_each() -> void:
	_clock = GameClock.new()
	_set_day(DailyChallengeService.day_for_date_key(DATE))
	_config = DailyChallengeService.load_config()
	_verifier = ReplayVerifier.new(_clock, _config)
	_repo = LevelRepository.new()


func _set_day(day: int) -> void:
	_clock.set_fixed_unix(day * SECONDS_PER_DAY + NOON)


func _replay(level: Dictionary, mode: StringName, taps: Array) -> RunReplay:
	var rp: RunReplay = RunReplay.new()
	rp.level_id = str(level["id"])
	rp.level_seed = int(level["seed"])
	rp.mode = mode
	for t: Variant in taps:
		rp.tap_ticks.append(int(t))
	return rp


func _solution_taps(level: Dictionary) -> Array:
	return (level["solution"] as Dictionary)["taps"] as Array


## Plays the replay like the game does (independent FluxSim, mode
## modifiers), fills end_tick and builds the client submission.
func _submit(level: Dictionary, replay: RunReplay, board: String) -> Dictionary:
	var rules: Dictionary = LeaderboardService.mode_rules_in(_config, String(replay.mode))
	var sim: FluxSim = FluxSim.new()
	sim.shields_allowed = bool(rules.get("shields", true))
	sim.setup(SimLevel.from_dict(level))
	replay.play_on(sim)
	replay.end_tick = sim.tick
	return {
		"board": board,
		"score": sim.score,
		"replay": replay.to_dict(),
		"level_id": replay.level_id,
		"mode": String(replay.mode),
		"app_version": "1.0.0",
		"install_id": INSTALL_ID,
		"sim_version": RunReplay.SIM_VERSION,
	}


func _campaign_submission(level_id: String) -> Dictionary:
	var level: Dictionary = _repo.load_level(level_id)
	return _submit(level, _replay(level, &"classic", _solution_taps(level)), "level:" + level_id)


func test_accepts_genuine_campaign_solution_replays() -> void:
	for level_id: String in ["w01_l10", "w03_l10", "w05_l20", "w08_l40", "w10_l51"]:
		var level: Dictionary = _repo.load_level(level_id)
		var submission: Dictionary = _campaign_submission(level_id)
		var verdict: Dictionary = _verifier.verify(submission, level)
		assert_true(bool(verdict["valid"]), "%s valid: %s" % [level_id, str(verdict["details"])])
		assert_empty(verdict["reasons"] as PackedStringArray)
		assert_eq(int(verdict["score"]), int(submission["score"]), "%s authoritative score" % level_id)
		assert_eq(
			int(verdict["score"]), int((level["solution"] as Dictionary)["score"]), "%s matches stored plan" % level_id
		)


func test_accepts_every_ranked_board_for_the_run() -> void:
	var level: Dictionary = _repo.load_level("w03_l10")
	var submission: Dictionary = _campaign_submission("w03_l10")
	for board: String in ["weekly:2026-W40:classic", "alltime:classic", "level:w03_l10", "weekly:2026-W39:classic"]:
		submission["board"] = board
		assert_true(bool(_verifier.verify(submission, level)["valid"]), "board %s" % board)
	for bad: String in ["level:w03_l11", "alltime:endless", "daily:2026-10-03", "weekly:2026-W30:classic", "nonsense"]:
		submission["board"] = bad
		assert_has(_verifier.verify(submission, level)["reasons"], ReplayVerifier.REASON_BOARD_MISMATCH, bad)


func test_rejects_tampered_score() -> void:
	var level: Dictionary = _repo.load_level("w03_l10")
	var submission: Dictionary = _campaign_submission("w03_l10")
	var honest: int = int(submission["score"])
	submission["score"] = honest + 10
	var verdict: Dictionary = _verifier.verify(submission, level)
	assert_false(bool(verdict["valid"]))
	assert_eq(verdict["reasons"], PackedStringArray([ReplayVerifier.REASON_SCORE_MISMATCH]))
	assert_eq(int(verdict["score"]), honest, "server reports the real score")


func test_rejects_impossible_tap_rate() -> void:
	var level: Dictionary = _repo.load_level("w02_l20")
	var taps: Array = []
	for t: int in range(30, 90, 2):
		taps.append(t)
	var submission: Dictionary = _submit(level, _replay(level, &"classic", taps), "alltime:classic")
	var verdict: Dictionary = _verifier.verify(submission, level)
	assert_false(bool(verdict["valid"]))
	assert_has(verdict["reasons"], ReplayVerifier.REASON_TAP_RATE)


func test_tap_rate_window_boundaries() -> void:
	var twelve: PackedInt32Array = PackedInt32Array()
	for t: int in range(0, 60, 5):
		twelve.append(t)
	assert_true(_verifier.tap_rate_ok(twelve), "12 taps in one second is human")
	var thirteen: PackedInt32Array = PackedInt32Array()
	for t: int in range(0, 52, 4):
		thirteen.append(t)
	assert_false(_verifier.tap_rate_ok(thirteen), "13 taps in one second is not")
	var spread: PackedInt32Array = PackedInt32Array()
	for t: int in range(0, 65, 5):
		spread.append(t)
	assert_true(_verifier.tap_rate_ok(spread), "13 taps over more than a second is fine")
	assert_true(_verifier.tap_rate_ok(PackedInt32Array()))


func test_rejects_wrong_sim_version() -> void:
	var level: Dictionary = _repo.load_level("w03_l10")
	var submission: Dictionary = _campaign_submission("w03_l10")
	submission["sim_version"] = RunReplay.SIM_VERSION + 1
	(submission["replay"] as Dictionary)["sim_version"] = RunReplay.SIM_VERSION + 1
	var verdict: Dictionary = _verifier.verify(submission, level)
	assert_false(bool(verdict["valid"]))
	assert_has(verdict["reasons"], ReplayVerifier.REASON_SIM_VERSION)
	var old_client: Dictionary = _campaign_submission("w03_l10")
	old_client.erase("sim_version")
	assert_has(_verifier.verify(old_client, level)["reasons"], ReplayVerifier.REASON_SIM_VERSION, "missing version")


func test_rejects_incomplete_run() -> void:
	var level: Dictionary = _repo.load_level("w03_l10")
	var submission: Dictionary = _submit(level, _replay(level, &"classic", []), "alltime:classic")
	var verdict: Dictionary = _verifier.verify(submission, level)
	assert_false(bool(verdict["valid"]))
	assert_eq(verdict["reasons"], PackedStringArray([ReplayVerifier.REASON_NOT_COMPLETED]), "only completion fails")


func test_rejects_end_tick_and_identity_mismatches() -> void:
	var level: Dictionary = _repo.load_level("w03_l10")
	var early: Dictionary = _campaign_submission("w03_l10")
	(early["replay"] as Dictionary)["end_tick"] = int((early["replay"] as Dictionary)["end_tick"]) - 30
	assert_has(_verifier.verify(early, level)["reasons"], ReplayVerifier.REASON_END_TICK)
	var other_level: Dictionary = _repo.load_level("w03_l11")
	var wrong_level: Dictionary = _verifier.verify(_campaign_submission("w03_l10"), other_level)
	assert_has(wrong_level["reasons"], ReplayVerifier.REASON_LEVEL_MISMATCH)
	var reseeded: Dictionary = _campaign_submission("w03_l10")
	(reseeded["replay"] as Dictionary)["seed"] = 12345
	assert_has(_verifier.verify(reseeded, level)["reasons"], ReplayVerifier.REASON_SEED_MISMATCH)
	var relabelled: Dictionary = _campaign_submission("w03_l10")
	relabelled["mode"] = "daily"
	assert_has(_verifier.verify(relabelled, level)["reasons"], ReplayVerifier.REASON_MODE_MISMATCH)


func test_rejects_unranked_and_unknown_modes() -> void:
	var level: Dictionary = _repo.load_level("w03_l10")
	var zen: Dictionary = _submit(level, _replay(level, &"zen", _solution_taps(level)), "alltime:zen")
	assert_has(_verifier.verify(zen, level)["reasons"], ReplayVerifier.REASON_UNRANKED_MODE)
	var odd: Dictionary = _submit(level, _replay(level, &"turbo", _solution_taps(level)), "alltime:turbo")
	assert_has(_verifier.verify(odd, level)["reasons"], ReplayVerifier.REASON_UNKNOWN_MODE)


func test_rejects_malformed_submissions() -> void:
	var level: Dictionary = _repo.load_level("w03_l10")
	assert_has(_verifier.verify({"score": 5}, level)["reasons"], ReplayVerifier.REASON_MISSING_REPLAY)
	assert_has(_verifier.verify(_campaign_submission("w03_l10"), {})["reasons"], ReplayVerifier.REASON_INVALID_LEVEL)
	var negative: Dictionary = _campaign_submission("w03_l10")
	negative["score"] = -1
	assert_has(_verifier.verify(negative, level)["reasons"], ReplayVerifier.REASON_INVALID_SCORE)
	var shuffled: Dictionary = _campaign_submission("w03_l10")
	var taps: Array = (shuffled["replay"] as Dictionary)["taps"] as Array
	taps.reverse()
	assert_has(_verifier.verify(shuffled, level)["reasons"], ReplayVerifier.REASON_STRUCTURE)
	var late_tap: Dictionary = _campaign_submission("w03_l10")
	var rp: Dictionary = late_tap["replay"] as Dictionary
	(rp["taps"] as Array).append(int(rp["end_tick"]))
	assert_has(_verifier.verify(late_tap, level)["reasons"], ReplayVerifier.REASON_STRUCTURE)
	var broken_level: Dictionary = level.duplicate(true)
	broken_level["entities"] = [{"t": "volcano", "d": 20.0}]
	var broken: Dictionary = _verifier.verify(_campaign_submission("w03_l10"), broken_level)
	assert_has(broken["reasons"], ReplayVerifier.REASON_INVALID_LEVEL)


func test_rejects_malformed_replay_fields_without_simulating() -> void:
	var level: Dictionary = _repo.load_level("w03_l10")
	var cases: Array[Array] = [
		["seed", null],
		["seed", "123"],
		["seed", -1],
		["seed", 1.5],
		["taps", [null]],
		["taps", ["30"]],
		["taps", [30.5]],
		["taps", [99999999]],
		["taps", "30,90"],
		["end_tick", "late"],
		["end_tick", 0],
		["mode", 7],
		["level_id", null],
		["sim_version", null],
	]
	for pair: Array in cases:
		var submission: Dictionary = _campaign_submission("w03_l10")
		(submission["replay"] as Dictionary)[pair[0]] = pair[1]
		var verdict: Dictionary = _verifier.verify(submission, level)
		var label: String = "%s=%s" % [str(pair[0]), str(pair[1])]
		assert_false(bool(verdict.get("valid", true)), label)
		var reasons: Variant = verdict.get("reasons", PackedStringArray())
		assert_eq(reasons, PackedStringArray([ReplayVerifier.REASON_STRUCTURE]), label)
		assert_eq(int(verdict.get("score", -1)), 0, "%s never simulated" % label)
	var fractional: Dictionary = _campaign_submission("w03_l10")
	fractional["score"] = float(fractional["score"]) + 0.5
	assert_has(_verifier.verify(fractional, level)["reasons"], ReplayVerifier.REASON_INVALID_SCORE, "fractional score")
	var wire: Dictionary = JSON.parse_string(JSON.stringify(_campaign_submission("w03_l10"))) as Dictionary
	var from_json: Dictionary = _verifier.verify(wire, level)
	assert_true(bool(from_json["valid"]), "JSON numbers (floats) still verify: %s" % str(from_json["details"]))


func test_mode_must_fit_the_level_kind() -> void:
	var level: Dictionary = _repo.load_level("w03_l10")
	var endless: Dictionary = _submit(level, _replay(level, &"endless", _solution_taps(level)), "alltime:endless")
	assert_has(
		_verifier.verify(endless, level)["reasons"], ReplayVerifier.REASON_MODE_MISMATCH, "campaign run on endless"
	)
	var daily_on_campaign: Dictionary = _submit(level, _replay(level, &"daily", _solution_taps(level)), "")
	assert_has(
		_verifier.verify(daily_on_campaign, level)["reasons"],
		ReplayVerifier.REASON_MODE_MISMATCH,
		"daily run, campaign level"
	)
	# Boss rush scores are a sum over several bosses with no single replay to
	# re-simulate, so the mode is unranked rather than half-verified.
	var boss: Dictionary = _repo.load_level("w01_l52")
	assert_eq(str(boss["kind"]), "boss")
	var rush: Dictionary = _submit(boss, _replay(boss, &"boss_rush", _solution_taps(boss)), "alltime:boss_rush")
	assert_has(_verifier.verify(rush, boss)["reasons"], ReplayVerifier.REASON_UNRANKED_MODE, "boss rush is unranked")
	var hard: Dictionary = _submit(boss, _replay(boss, &"classic", _solution_taps(boss)), "alltime:classic")
	var verdict: Dictionary = _verifier.verify(hard, boss)
	assert_true(bool(verdict["valid"]), "boss level in classic: %s" % str(verdict["details"]))


func test_daily_window_reason_uses_server_clock_only() -> void:
	var day: int = DailyChallengeService.day_for_date_key(DATE)
	assert_eq(_verifier.daily_window_reason("w01_l01"), "", "campaign levels have no date window")
	assert_eq(_verifier.daily_window_reason("daily_" + DATE), "")
	assert_eq(_verifier.daily_window_reason("daily_" + GameClock.date_key_for_day(day - 1)), "", "yesterday")
	var old: String = "daily_" + GameClock.date_key_for_day(day - 2)
	assert_eq(_verifier.daily_window_reason(old), ReplayVerifier.REASON_STALE_DAILY)
	var ahead: String = "daily_" + GameClock.date_key_for_day(day + 1)
	assert_eq(_verifier.daily_window_reason(ahead), ReplayVerifier.REASON_FUTURE_DAILY)


func test_daily_window_uses_server_clock() -> void:
	var day: int = DailyChallengeService.day_for_date_key(DATE)
	var daily: DailyChallengeService = DailyChallengeService.new(
		PlayerProfile.new(), EventBus.new(), GameClock.new(), WorldCatalog.load_default(), Callable(), _config
	)
	var level: Dictionary = daily.level_for(DATE)
	assert_false(level.is_empty(), "daily generated")
	var submission: Dictionary = _submit(level, _replay(level, &"daily", _solution_taps(level)), "daily:" + DATE)
	_set_day(day)
	assert_true(bool(_verifier.verify(submission, level)["valid"]), "today")
	_set_day(day + 1)
	assert_true(bool(_verifier.verify(submission, level)["valid"]), "yesterday's daily still accepted")
	_set_day(day + 2)
	assert_has(_verifier.verify(submission, level)["reasons"], ReplayVerifier.REASON_STALE_DAILY)
	_set_day(day - 1)
	assert_has(_verifier.verify(submission, level)["reasons"], ReplayVerifier.REASON_FUTURE_DAILY)
	_set_day(day)
	submission["board"] = "daily:2026-10-02"
	assert_has(_verifier.verify(submission, level)["reasons"], ReplayVerifier.REASON_BOARD_MISMATCH)
	submission["board"] = "weekly:2026-W40:daily"
	assert_true(bool(_verifier.verify(submission, level)["valid"]), "weekly daily board")
	submission["mode"] = "classic"
	assert_has(_verifier.verify(submission, level)["reasons"], ReplayVerifier.REASON_MODE_MISMATCH)


func test_mode_rules_are_data_driven() -> void:
	var cfg: Dictionary = _config.duplicate(true)
	(cfg["modes"] as Dictionary)["practice"] = {
		"ranked": true,
		"requires_completion": false,
		"level_board": false,
		"shields": false,
		"zen": false,
		"speed_scale": 1.0,
		"time_limit": 0.0,
	}
	var verifier: ReplayVerifier = ReplayVerifier.new(_clock, cfg)
	var level: Dictionary = _repo.load_level("w03_l10")
	var replay: RunReplay = _replay(level, &"practice", [])
	var sim: FluxSim = verifier.simulate(level, replay, (cfg["modes"] as Dictionary)["practice"] as Dictionary)
	replay.end_tick = sim.tick
	var submission: Dictionary = {
		"board": "alltime:practice",
		"score": sim.score,
		"replay": replay.to_dict(),
		"level_id": "w03_l10",
		"mode": "practice",
		"sim_version": RunReplay.SIM_VERSION,
	}
	assert_true(bool(verifier.verify(submission, level)["valid"]), "failed run allowed when completion not required")
	var timed: Dictionary = {"shields": true, "time_limit": 2.0}
	var short: FluxSim = verifier.simulate(level, _replay(level, &"practice", _solution_taps(level)), timed)
	assert_eq(short.tick, 2 * SimConst.TICK_RATE, "time limit from mode rules")
