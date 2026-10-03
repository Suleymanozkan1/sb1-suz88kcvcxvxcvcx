extends SceneTree
## Server-side replay verification CLI (authoritative anti-cheat check).
##
## Usage:
##   godot --headless --path game -s res://server/verify_replay.gd -- \
##       --submission=<path.json> [--now=<unix seconds>]
##
## The submission is the JSON body a client POSTs to /v1/scores (see
## server/README.md). The authoritative level is never taken from the client:
## campaign ids ("wNN_lMM") are loaded with [LevelRepository]; daily ids
## ("daily_YYYY-MM-DD") are regenerated from the date with
## [DailyChallengeService] (deterministic, independent of any player state).
## --now fixes the server clock (daily date window); default: system UTC time.
##
## Prints one JSON object on stdout: the [ReplayVerifier] verdict plus
## "level_id" and "server_date" (or {"valid": false, "error": "..."}).
## Exit code: 0 valid, 2 invalid, 1 error (bad arguments, unreadable
## submission, unknown level, missing configuration).

const EXIT_VALID: int = 0
const EXIT_ERROR: int = 1
const EXIT_INVALID: int = 2
const ARG_SUBMISSION: String = "--submission="
const ARG_NOW: String = "--now="
const USAGE: String = (
	"usage: godot --headless --path game -s res://server/verify_replay.gd -- "
	+ "--submission=<path.json> [--now=<unix>]"
)


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	# Keep stdout machine-readable: only warnings/errors are logged (stderr).
	GameLog.min_level = GameLog.Level.WARN
	quit(run(OS.get_cmdline_user_args()))


## Runs the verification for the given user arguments; returns the exit code.
func run(args: PackedStringArray) -> int:
	var opts: Dictionary = parse_args(args)
	if opts.has("error"):
		return _fail(str(opts["error"]))
	var submission_path: String = str(opts["submission"])
	var parsed: Variant = JsonIO.read(submission_path)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("submission %s is not a readable JSON object" % submission_path)
	var submission: Dictionary = parsed as Dictionary
	var config: Dictionary = DailyChallengeService.load_config()
	if config.is_empty():
		return _fail("configuration %s missing" % DailyChallengeService.CONFIG_PATH)
	var clock: GameClock = GameClock.new()
	if int(opts["now"]) >= 0:
		clock.set_fixed_unix(int(opts["now"]))
	var level_id: String = str(submission.get("level_id", ""))
	if level_id.is_empty() and typeof(submission.get("replay", null)) == TYPE_DICTIONARY:
		level_id = str((submission["replay"] as Dictionary).get("level_id", ""))
	var level: Dictionary = load_level(level_id, config)
	if level.is_empty():
		return _fail("unknown or unloadable level '%s'" % level_id)
	var verdict: Dictionary = ReplayVerifier.new(clock, config).verify(submission, level)
	verdict["level_id"] = level_id
	verdict["server_date"] = clock.date_key()
	verdict["reasons"] = Array(verdict["reasons"] as PackedStringArray)
	verdict["details"] = Array(verdict["details"] as PackedStringArray)
	print(JsonIO.canonical(verdict))
	return EXIT_VALID if bool(verdict["valid"]) else EXIT_INVALID


## Parses the user arguments into {"submission": path, "now": unix or -1},
## or {"error": message}.
func parse_args(args: PackedStringArray) -> Dictionary:
	var opts: Dictionary = {"submission": "", "now": -1}
	for arg: String in args:
		if arg.begins_with(ARG_SUBMISSION):
			opts["submission"] = arg.substr(ARG_SUBMISSION.length())
		elif arg.begins_with(ARG_NOW):
			var raw: String = arg.substr(ARG_NOW.length())
			if not raw.is_valid_int() or raw.to_int() < 0:
				return {"error": "invalid --now value '%s'" % raw}
			opts["now"] = raw.to_int()
		else:
			return {"error": "unknown argument '%s'\n%s" % [arg, USAGE]}
	if str(opts["submission"]).is_empty():
		return {"error": "missing --submission\n%s" % USAGE}
	return opts


## Authoritative level data for [param level_id] ({} when unknown).
func load_level(level_id: String, config: Dictionary) -> Dictionary:
	var catalog: WorldCatalog = WorldCatalog.load_default()
	var date_key: String = DailyChallengeService.date_key_from_level_id(level_id)
	if not date_key.is_empty():
		var fixed: GameClock = GameClock.new()
		fixed.set_fixed_unix(DailyChallengeService.day_for_date_key(date_key) * DailyChallengeService.SECONDS_PER_DAY)
		var daily: DailyChallengeService = DailyChallengeService.new(
			PlayerProfile.new(), EventBus.new(), fixed, catalog, Callable(), config
		)
		return daily.level_for(date_key)
	if WorldCatalog.parse_level_id(level_id).is_empty():
		return {}
	return LevelRepository.new(catalog).load_level(level_id)


func _fail(message: String) -> int:
	printerr("verify_replay: " + message)
	print(JsonIO.canonical({"valid": false, "error": message}))
	return EXIT_ERROR
