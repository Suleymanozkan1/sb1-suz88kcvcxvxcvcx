extends TestCase
## StatsService: untrusted context/level data, corrupted stored values and
## non-finite run measurements never crash or inflate a stat.

var profile: PlayerProfile
var bus: EventBus
var stats: StatsService


func before_each() -> void:
	profile = PlayerProfile.new()
	bus = EventBus.new()
	stats = StatsService.new(profile, bus)


func _result(completed: bool) -> RunResult:
	var r: RunResult = RunResult.new()
	r.level_id = "w01_l01"
	r.mode = &"classic"
	r.completed = completed
	r.stars = 1 if completed else 0
	r.score = 1200
	r.sparks = 30
	r.max_combo = 18
	r.damage = 1
	r.taps = 40
	r.time_seconds = 58.4
	r.distance = 400.0
	return r


func _ctx(kind: String, duration: float) -> Dictionary:
	return {"kind": kind, "first_clear": false, "first_perfect": false, "design_duration": duration, "mode": &"classic"}


func test_bad_context_values_do_not_crash() -> void:
	var r: RunResult = _result(true)
	r.time_seconds = 10.0
	r.damage = 0
	# A statement call on purpose: a script error inside record_run must show
	# up as failed counters below instead of silently ending this test.
	stats.record_run(r, {"kind": null, "first_clear": "yes", "first_perfect": null, "design_duration": null, "mode": 4})
	assert_eq(stats.value("levels_cleared"), 1, "clear still counted")
	assert_eq(stats.value("damage_free_clears"), 1, "rest of the run recorded")
	assert_eq(stats.value("unique_levels_cleared"), 0, "non-bool flags are false")
	assert_eq(stats.value("fast_clears"), 0, "no usable design duration")
	assert_eq(stats.value("zen_runs"), 0, "invalid mode falls back to the result mode")
	var meta: Dictionary = {"kind": "boss", "duration": null}
	var built: Variant = StatsService.build_context(r, meta, {"first_clear": "1", "first_perfect": 1})
	assert_eq(typeof(built), TYPE_DICTIONARY, "context built")
	var ctx: Dictionary = built as Dictionary if typeof(built) == TYPE_DICTIONARY else {}
	assert_eq(ctx.get("kind", ""), "boss")
	assert_eq(ctx.get("first_clear"), false, "string flags are not true")
	assert_eq(ctx.get("first_perfect"), true, "numeric flags follow their value")
	assert_eq(ctx.get("design_duration"), 0.0, "null duration -> 0")


func test_corrupted_stored_values_read_as_zero() -> void:
	profile.stats["runs_played"] = null
	profile.stats["taps"] = "many"
	profile.stats["total_score"] = 12.0
	profile.stats["max_combo"] = NAN
	assert_eq(stats.value("runs_played"), 0, "null reads as 0")
	assert_eq(stats.value("taps"), 0, "text reads as 0")
	assert_eq(stats.value("total_score"), 12, "float counters still read")
	assert_eq(stats.value("max_combo"), 0, "NaN reads as 0")
	# Statement calls: a script error must surface as a failed assertion below.
	stats.add("runs_played")
	stats.set_max("max_combo", 9)
	assert_eq(profile.stats.get("runs_played"), 1, "repaired on the next write")
	assert_eq(profile.stats.get("max_combo"), 9)
	assert_eq(stats.snapshot().get("taps"), 0)


func test_non_finite_run_values_are_ignored() -> void:
	var r: RunResult = _result(false)
	r.time_seconds = INF
	stats.record_run(r, _ctx("normal", 60.0))
	assert_eq(stats.value("time_played_seconds"), 0, "infinite time never counted")
	assert_eq(stats.value("runs_played"), 1)
	var e: RunResult = _result(false)
	e.mode = &"endless"
	e.distance = INF
	stats.record_run(e)
	assert_eq(stats.value("endless_best_distance"), 0, "infinite distance ignored")
	e.distance = NAN
	stats.record_run(e)
	assert_eq(stats.value("endless_best_distance"), 0, "NaN distance ignored")
	e.distance = 321.9
	stats.record_run(e)
	assert_eq(stats.value("endless_best_distance"), 321)


func test_fast_clear_needs_finite_durations() -> void:
	var r: RunResult = _result(true)
	r.time_seconds = 10.0
	assert_false(stats.is_fast_clear(r, INF), "an infinite design duration is unknown, not generous")
	assert_false(stats.is_fast_clear(r, NAN))
	assert_true(stats.is_fast_clear(r, 20.0))
	r.time_seconds = NAN
	assert_false(stats.is_fast_clear(r, 20.0), "NaN run time is never fast")
	var tuned: StatsService = StatsService.new(profile, bus, {"stats": {"fast_clear_ratio": NAN}})
	assert_near(tuned.fast_clear_ratio, StatsService.DEFAULT_FAST_CLEAR_RATIO, 0.0001, "NaN ratio rejected")
