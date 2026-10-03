extends TestCase
## server/verify_replay.gd: parses, and as a real headless process returns
## exit 0 (valid) / 2 (invalid) / 1 (error) with a JSON verdict on stdout.

const CLI_PATH: String = "res://server/verify_replay.gd"
const TMP_DIR: String = "user://test_online_cli"
const DATE: String = "2026-10-03"
const NOON: int = 12 * 3600
const SECONDS_PER_DAY: int = 86400

var _written: PackedStringArray = PackedStringArray()


func after_each() -> void:
	for path: String in _written:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_written.clear()
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(TMP_DIR)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_DIR))


func _write(name: String, data: Dictionary) -> String:
	var dir: String = ProjectSettings.globalize_path(TMP_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var path: String = dir.path_join(name)
	JsonIO.write_json(path, data)
	_written.append(path)
	return path


## Runs the CLI in a child Godot process; returns {"code", "verdict"}.
func _run_cli(args: PackedStringArray) -> Dictionary:
	var argv: PackedStringArray = PackedStringArray(
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", CLI_PATH, "--"]
	)
	argv.append_array(args)
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), argv, output, false)
	var verdict: Dictionary = {}
	var text: String = str(output[0]) if not output.is_empty() else ""
	for line: String in text.split("\n"):
		if line.strip_edges().begins_with("{"):
			var parsed: Variant = JSON.parse_string(line.strip_edges())
			if typeof(parsed) == TYPE_DICTIONARY:
				verdict = parsed as Dictionary
	return {"code": code, "verdict": verdict}


func _submission(level: Dictionary, mode: StringName, board: String) -> Dictionary:
	var replay: RunReplay = RunReplay.new()
	replay.level_id = str(level["id"])
	replay.level_seed = int(level["seed"])
	replay.mode = mode
	for t: Variant in (level["solution"] as Dictionary)["taps"] as Array:
		replay.tap_ticks.append(int(t))
	var sim: FluxSim = FluxSim.new()
	sim.setup(SimLevel.from_dict(level))
	replay.play_on(sim)
	replay.end_tick = sim.tick
	return {
		"board": board,
		"score": sim.score,
		"replay": replay.to_dict(),
		"level_id": replay.level_id,
		"mode": String(mode),
		"sim_version": RunReplay.SIM_VERSION,
		"install_id": "0123456789abcdef0123456789abcdef",
		"app_version": "1.0.0",
	}


func test_cli_script_parses() -> void:
	var script: GDScript = load(CLI_PATH) as GDScript
	assert_true(script != null, "script loads")
	if script == null:
		return
	assert_true(script.can_instantiate(), "script compiles")
	var names: PackedStringArray = PackedStringArray()
	for m: Dictionary in script.get_script_method_list():
		names.append(str(m.get("name", "")))
	for wanted: String in ["run", "parse_args", "load_level"]:
		assert_has(names, wanted)


func test_cli_campaign_valid_and_tampered() -> void:
	var level: Dictionary = LevelRepository.new().load_level("w03_l10")
	var good: Dictionary = _submission(level, &"classic", "level:w03_l10")
	var now: String = "--now=%d" % (DailyChallengeService.day_for_date_key(DATE) * SECONDS_PER_DAY + NOON)
	var ok_run: Dictionary = _run_cli(PackedStringArray(["--submission=" + _write("good.json", good), now]))
	assert_eq(int(ok_run["code"]), 0, "exit 0 for a valid run: %s" % str(ok_run["verdict"]))
	var verdict: Dictionary = ok_run["verdict"] as Dictionary
	assert_true(bool(verdict.get("valid", false)))
	assert_eq(int(verdict.get("score", -1)), int(good["score"]))
	assert_eq(str(verdict.get("server_date", "")), DATE)
	var bad: Dictionary = good.duplicate(true)
	bad["score"] = int(good["score"]) * 3
	var bad_run: Dictionary = _run_cli(PackedStringArray(["--submission=" + _write("bad.json", bad), now]))
	assert_eq(int(bad_run["code"]), 2, "exit 2 for an invalid run")
	assert_has((bad_run["verdict"] as Dictionary).get("reasons", []), ReplayVerifier.REASON_SCORE_MISMATCH)


func test_cli_regenerates_daily_level() -> void:
	var cfg: Dictionary = DailyChallengeService.load_config()
	var daily: DailyChallengeService = DailyChallengeService.new(
		PlayerProfile.new(), EventBus.new(), GameClock.new(), WorldCatalog.load_default(), Callable(), cfg
	)
	var level: Dictionary = daily.level_for(DATE)
	var submission: Dictionary = _submission(level, &"daily", "daily:" + DATE)
	var now: String = "--now=%d" % (DailyChallengeService.day_for_date_key(DATE) * SECONDS_PER_DAY + NOON)
	var result: Dictionary = _run_cli(PackedStringArray(["--submission=" + _write("daily.json", submission), now]))
	assert_eq(int(result["code"]), 0, "server regenerates the same daily: %s" % str(result["verdict"]))
	var later: String = "--now=%d" % ((DailyChallengeService.day_for_date_key(DATE) + 3) * SECONDS_PER_DAY)
	var stale: Dictionary = _run_cli(PackedStringArray(["--submission=" + _write("daily.json", submission), later]))
	assert_eq(int(stale["code"]), 2)
	assert_has((stale["verdict"] as Dictionary).get("reasons", []), ReplayVerifier.REASON_STALE_DAILY)


func test_cli_errors_exit_one() -> void:
	var missing: Dictionary = _run_cli(PackedStringArray(["--submission=/nonexistent/dir/none.json"]))
	assert_eq(int(missing["code"]), 1, "unreadable submission")
	assert_false(bool((missing["verdict"] as Dictionary).get("valid", true)))
	assert_eq(int(_run_cli(PackedStringArray([]))["code"]), 1, "no arguments")
	assert_eq(int(_run_cli(PackedStringArray(["--now=yesterday", "--submission=x.json"]))["code"]), 1, "bad --now")
	var unknown_level: Dictionary = {"level_id": "w99_l99", "replay": {"level_id": "w99_l99"}, "score": 1}
	var unknown: Dictionary = _run_cli(PackedStringArray(["--submission=" + _write("unknown.json", unknown_level)]))
	assert_eq(int(unknown["code"]), 1, "unknown level")
