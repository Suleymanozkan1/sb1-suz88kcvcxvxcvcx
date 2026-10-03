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
## submission, unknown level, missing configuration, malformed verdict).
## Fail-safe: the process exit code is [member exit_code], which starts as
## 1 and becomes 0 only after a well-formed valid verdict was printed, so an
## unexpected script error can never turn into "valid". A daily outside the
## server's date window is refused before its level is regenerated.

const EXIT_VALID: int = 0
const EXIT_ERROR: int = 1
const EXIT_INVALID: int = 2
const ARG_SUBMISSION: String = "--submission="
const ARG_NOW: String = "--now="
const USAGE: String = (
	"usage: godot --headless --path game -s res://server/verify_replay.gd -- "
	+ "--submission=<path.json> [--now=<unix>]"
)

## Process exit code; see the class description (fail-safe default).
var exit_code: int = EXIT_ERROR


func _initialize() -> void:
	_main.call_deferred()


func _main() -> void:
	# Keep stdout machine-readable: only warnings/errors are logged (stderr).
	GameLog.min_level = GameLog.Level.WARN
	exit_code = EXIT_ERROR
	run(OS.get_cmdline_user_args())
	quit(exit_code)


## Runs the verification for the given user arguments; returns the exit code
## (also stored in [member exit_code]).
func run(args: PackedStringArray) -> int:
	exit_code = EXIT_ERROR
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
	var verifier: ReplayVerifier = ReplayVerifier.new(clock, config)
	var verdict: Dictionary
	var window: String = verifier.daily_window_reason(level_id)
	if not window.is_empty():
		var detail: String = "%s: %s is outside the accepted window (server %s)" % [window, level_id, clock.date_key()]
		verdict = {
			"valid": false,
			"score": 0,
			"reasons": PackedStringArray([window]),
			"details": PackedStringArray([detail]),
		}
	else:
		var level: Dictionary = load_level(level_id, config)
		if level.is_empty():
			return _fail("unknown or unloadable level '%s'" % level_id)
		verdict = verifier.verify(submission, level)
	return _report(verdict, level_id, clock)


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


## Prints a well-formed verdict and sets the exit code; anything malformed
## is reported as an error, never as valid.
func _report(verdict: Dictionary, level_id: String, clock: GameClock) -> int:
	var valid_v: Variant = verdict.get("valid", null)
	var reasons_v: Variant = verdict.get("reasons", null)
	var details_v: Variant = verdict.get("details", null)
	if (
		typeof(valid_v) != TYPE_BOOL
		or typeof(reasons_v) != TYPE_PACKED_STRING_ARRAY
		or typeof(details_v) != TYPE_PACKED_STRING_ARRAY
	):
		return _fail("verifier returned a malformed verdict")
	var valid: bool = valid_v == true and (reasons_v as PackedStringArray).is_empty()
	verdict["valid"] = valid
	verdict["level_id"] = level_id
	verdict["server_date"] = clock.date_key()
	verdict["reasons"] = Array(reasons_v as PackedStringArray)
	verdict["details"] = Array(details_v as PackedStringArray)
	print(JsonIO.canonical(verdict))
	exit_code = EXIT_VALID if valid else EXIT_INVALID
	return exit_code


func _fail(message: String) -> int:
	printerr("verify_replay: " + message)
	print(JsonIO.canonical({"valid": false, "error": message}))
	exit_code = EXIT_ERROR
	return EXIT_ERROR
