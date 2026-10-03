extends TestCase
## StatsService: counters, max stats, signals, record_run rules and wiring.

## Stat names other modules (achievements/missions) rely on.
const REQUIRED_STATS: PackedStringArray = [
	"runs_played", "runs_failed", "levels_cleared", "unique_levels_cleared", "perfects", "unique_perfects",
	"sparks_collected", "prisms_collected", "near_misses", "shatters", "chain_links", "gates_passed",
	"portals_used", "currents_ridden", "overdrives", "max_combo", "total_score", "damage_free_clears",
	"bosses_cleared", "challenges_cleared", "fast_clears", "daily_completed", "daily_streak_max",
	"coins_earned", "cosmetics_owned", "achievements_unlocked", "worlds_completed", "worlds_perfected",
	"taps", "revives_used", "zen_runs", "endless_best_distance", "time_played_seconds",
]

var profile: PlayerProfile
var bus: EventBus
var stats: StatsService
var events: Array[String] = []


func before_each() -> void:
	profile = PlayerProfile.new()
	bus = EventBus.new()
	stats = StatsService.new(profile, bus)
	# The lambda captures a local array (shared by reference), never `self`, so
	# the bus does not keep this test case alive.
	var sink: Array[String] = []
	events = sink
	bus.stat_changed.connect(func(stat: StringName, v: int) -> void: sink.append("%s=%d" % [stat, v]))


func _result(completed: bool) -> RunResult:
	var r: RunResult = RunResult.new()
	r.level_id = "w01_l01"
	r.mode = &"classic"
	r.completed = completed
	r.stars = 1 if completed else 0
	r.score = 1200
	r.sparks = 30
	r.spark_total = 32
	r.prisms = 2
	r.max_combo = 18
	r.near_misses = 3
	r.shatters = 4
	r.chain_links = 5
	r.gates = 6
	r.damage = 1
	r.portals_used = 1
	r.currents_ridden = 2
	r.overdrives = 1
	r.taps = 40
	r.time_seconds = 58.4
	r.distance = 400.0
	return r


func _ctx(kind: String, duration: float, first_clear: bool = false, first_perfect: bool = false) -> Dictionary:
	return {
		"kind": kind, "first_clear": first_clear, "first_perfect": first_perfect,
		"design_duration": duration, "mode": &"classic",
	}


func test_known_stats_cover_the_shared_list() -> void:
	var known: PackedStringArray = StatsService.known_stats()
	for stat: String in REQUIRED_STATS:
		assert_true(StatsService.is_known(stat), "%s is a known stat" % stat)
	assert_eq(known.size(), REQUIRED_STATS.size(), "no extra or missing stats")
	var seen: Dictionary = {}
	for stat2: String in known:
		assert_false(seen.has(stat2), "duplicate stat %s" % stat2)
		seen[stat2] = true
	assert_eq(stats.snapshot().size(), known.size(), "snapshot lists every stat")


func test_add_set_max_set_value_and_signals() -> void:
	assert_eq(stats.add("runs_played"), 1)
	assert_eq(stats.add("runs_played", 4), 5)
	assert_eq(stats.value("runs_played"), 5)
	assert_eq(profile.stat("runs_played"), 5, "stored in the profile slice")
	assert_eq(stats.set_max("max_combo", 10), 10)
	assert_eq(stats.set_max("max_combo", 5), 10, "set_max keeps the larger value")
	assert_eq(stats.set_value("cosmetics_owned", 7), 7)
	assert_eq(stats.set_value("cosmetics_owned", 3), 3, "set_value overwrites (external totals)")
	assert_eq(events.size(), 5, "one signal per change, none for no-ops")
	assert_eq(events[0], "runs_played=1")
	assert_eq(events[1], "runs_played=5")
	assert_eq(events[2], "max_combo=10")
	assert_eq(events[4], "cosmetics_owned=3")
	assert_eq(stats.add("runs_played", 0), 5)
	assert_eq(stats.set_value("cosmetics_owned", 3), 3)
	assert_eq(events.size(), 5, "unchanged values do not emit")
	assert_eq(stats.value("never_recorded"), 0)


func test_rejects_negative_and_invalid_input() -> void:
	stats.add("runs_played", 3)
	assert_eq(stats.add("runs_played", -2), 3, "counters never decrease")
	assert_eq(stats.add("Bad Name!"), 0, "invalid names rejected")
	assert_false(profile.stats.has("Bad Name!"))
	assert_eq(stats.add(""), 0)
	assert_eq(stats.set_value("cosmetics_owned", -4), 0, "negative values clamp to 0")
	assert_eq(stats.add("combo_runs_10"), 1, "well-formed custom stats are allowed")


func test_values_are_bounded() -> void:
	stats.add("total_score", StatsService.MAX_VALUE)
	assert_eq(stats.add("total_score", StatsService.MAX_VALUE), StatsService.MAX_VALUE)
	assert_eq(stats.add("taps", 9_000_000_000_000_000_000), StatsService.MAX_VALUE, "no overflow")


func test_record_run_counts_completed_perfect_boss_fast_clear() -> void:
	var r: RunResult = _result(true)
	r.perfect = true
	r.damage = 0
	r.sparks = 32
	r.time_seconds = 50.0
	stats.record_run(r, _ctx("boss", 60.0, true, true))
	assert_eq(stats.value("runs_played"), 1)
	assert_eq(stats.value("runs_failed"), 0)
	assert_eq(stats.value("levels_cleared"), 1)
	assert_eq(stats.value("unique_levels_cleared"), 1)
	assert_eq(stats.value("perfects"), 1)
	assert_eq(stats.value("unique_perfects"), 1)
	assert_eq(stats.value("damage_free_clears"), 1)
	assert_eq(stats.value("bosses_cleared"), 1)
	assert_eq(stats.value("challenges_cleared"), 0)
	assert_eq(stats.value("fast_clears"), 1, "50s <= 0.9 * 60s")
	assert_eq(stats.value("sparks_collected"), 32)
	assert_eq(stats.value("prisms_collected"), 2)
	assert_eq(stats.value("near_misses"), 3)
	assert_eq(stats.value("shatters"), 4)
	assert_eq(stats.value("chain_links"), 5)
	assert_eq(stats.value("gates_passed"), 6)
	assert_eq(stats.value("portals_used"), 1)
	assert_eq(stats.value("currents_ridden"), 2)
	assert_eq(stats.value("overdrives"), 1)
	assert_eq(stats.value("total_score"), 1200)
	assert_eq(stats.value("taps"), 40)
	assert_eq(stats.value("time_played_seconds"), 50)
	assert_eq(stats.value("max_combo"), 18)


func test_replay_counts_clear_but_not_unique() -> void:
	stats.record_run(_result(true), _ctx("normal", 60.0, true))
	stats.record_run(_result(true), _ctx("normal", 60.0, false))
	assert_eq(stats.value("levels_cleared"), 2, "every completed run")
	assert_eq(stats.value("unique_levels_cleared"), 1, "first clears only")


func test_damage_and_slow_clears_not_counted() -> void:
	var r: RunResult = _result(true)
	r.time_seconds = 58.0
	stats.record_run(r, _ctx("challenge", 60.0))
	assert_eq(stats.value("damage_free_clears"), 0, "took damage")
	assert_eq(stats.value("fast_clears"), 0, "58s > 54s")
	assert_eq(stats.value("challenges_cleared"), 1)
	assert_eq(stats.value("bosses_cleared"), 0)
	assert_eq(stats.value("perfects"), 0)
	var no_duration: RunResult = _result(true)
	no_duration.time_seconds = 1.0
	stats.record_run(no_duration, _ctx("normal", 0.0))
	assert_eq(stats.value("fast_clears"), 0, "no design duration -> never fast")


func test_fast_clear_accepts_duration_key_and_boundary() -> void:
	var r: RunResult = _result(true)
	r.time_seconds = 45.0
	stats.record_run(r, {"kind": "normal", "duration": 50.0})
	assert_eq(stats.value("fast_clears"), 1, "exactly 0.9x counts, ctx.duration accepted")
	assert_false(stats.is_fast_clear(_result(false), 100.0), "failed runs are never fast clears")


func test_max_combo_is_a_max() -> void:
	var a: RunResult = _result(true)
	a.max_combo = 30
	stats.record_run(a, _ctx("normal", 60.0))
	var b: RunResult = _result(false)
	b.max_combo = 12
	stats.record_run(b, _ctx("normal", 60.0))
	assert_eq(stats.value("max_combo"), 30, "lower combo does not overwrite")
	var c: RunResult = _result(true)
	c.max_combo = 55
	stats.record_run(c, _ctx("normal", 60.0))
	assert_eq(stats.value("max_combo"), 55)


func test_failed_run_counts_failure_and_collectibles() -> void:
	stats.record_run(_result(false), _ctx("normal", 60.0))
	assert_eq(stats.value("runs_played"), 1)
	assert_eq(stats.value("runs_failed"), 1)
	assert_eq(stats.value("levels_cleared"), 0)
	assert_eq(stats.value("damage_free_clears"), 0)
	assert_eq(stats.value("sparks_collected"), 30, "collected energy still counts")


func test_zen_and_endless_modes() -> void:
	var zen: RunResult = _result(true)
	zen.mode = &"zen"
	zen.damage = 0
	stats.record_run(zen, {"kind": "normal", "first_clear": true, "mode": &"zen"})
	assert_eq(stats.value("zen_runs"), 1)
	assert_eq(stats.value("runs_played"), 1)
	assert_eq(stats.value("levels_cleared"), 0, "zen completions are not clears")
	assert_eq(stats.value("unique_levels_cleared"), 0)
	assert_eq(stats.value("damage_free_clears"), 0)
	assert_eq(stats.value("sparks_collected"), 30)
	var endless: RunResult = _result(false)
	endless.mode = &"endless"
	endless.distance = 812.7
	stats.record_run(endless, {"mode": &"endless"})
	assert_eq(stats.value("endless_best_distance"), 812)
	assert_eq(stats.value("runs_failed"), 0, "endless runs end by design")
	var shorter: RunResult = _result(false)
	shorter.mode = &"endless"
	shorter.distance = 500.0
	stats.record_run(shorter)
	assert_eq(stats.value("endless_best_distance"), 812, "best distance is a max (mode from result)")


func test_revives_counted() -> void:
	var r: RunResult = _result(true)
	r.revived = true
	stats.record_run(r, _ctx("normal", 60.0))
	assert_eq(stats.value("revives_used"), 1)


func test_record_daily() -> void:
	stats.record_daily(true, 3)
	assert_eq(stats.value("daily_completed"), 1)
	assert_eq(stats.value("daily_streak_max"), 3)
	stats.record_daily(false, 2)
	assert_eq(stats.value("daily_completed"), 1, "repeat plays of the same day do not count")
	assert_eq(stats.value("daily_streak_max"), 3, "longest streak kept")


func test_connect_bus_counts_earned_coins_once() -> void:
	stats.connect_bus()
	stats.connect_bus()
	bus.currency_changed.emit(&"coins", 150, 50)
	assert_eq(stats.value("coins_earned"), 50, "idempotent connection")
	bus.currency_changed.emit(&"coins", 100, -50)
	bus.currency_changed.emit(&"gems", 5, 5)
	assert_eq(stats.value("coins_earned"), 50, "spending and gems are not coins earned")
	stats.disconnect_bus()
	bus.currency_changed.emit(&"coins", 200, 100)
	assert_eq(stats.value("coins_earned"), 50, "disconnected")


func test_fast_clear_ratio_config() -> void:
	var tuned: StatsService = StatsService.new(profile, bus, {"stats": {"fast_clear_ratio": 0.5}})
	assert_near(tuned.fast_clear_ratio, 0.5, 0.0001)
	var bad: StatsService = StatsService.new(profile, bus, {"stats": {"fast_clear_ratio": 5.0}})
	assert_near(bad.fast_clear_ratio, StatsService.DEFAULT_FAST_CLEAR_RATIO, 0.0001)
	var wrong_type: StatsService = StatsService.new(profile, bus, {"stats": "x"})
	assert_near(wrong_type.fast_clear_ratio, StatsService.DEFAULT_FAST_CLEAR_RATIO, 0.0001)
	var from_file: StatsService = StatsService.new(profile, bus, ProgressionService.load_config())
	assert_near(from_file.fast_clear_ratio, 0.9, 0.0001)


func test_null_inputs_are_safe() -> void:
	stats.record_run(null)
	assert_eq(stats.value("runs_played"), 0)
	var detached: StatsService = StatsService.new(null, null)
	assert_eq(detached.add("runs_played"), 1, "works without profile or bus")
	detached.connect_bus()


func test_build_context_and_end_to_end_with_progression() -> void:
	var catalog: WorldCatalog = WorldCatalog.load_default()
	var progression: ProgressionService = ProgressionService.new(profile, bus, catalog)
	var meta: Dictionary = {"id": "w01_l01", "kind": "normal", "duration": 60.0}
	var r: RunResult = _result(true)
	r.perfect = true
	r.damage = 0
	r.stars = 3
	var outcome: Dictionary = progression.record_level_result(r, meta)
	var ctx: Dictionary = StatsService.build_context(r, meta, outcome)
	assert_eq(ctx["kind"], "normal")
	assert_true(bool(ctx["first_clear"]))
	assert_true(bool(ctx["first_perfect"]))
	assert_near(float(ctx["design_duration"]), 60.0, 0.001)
	assert_eq(ctx["mode"], &"classic")
	stats.record_run(r, ctx)
	var outcome2: Dictionary = progression.record_level_result(r, meta)
	stats.record_run(r, StatsService.build_context(r, meta, outcome2))
	assert_eq(stats.value("levels_cleared"), 2)
	assert_eq(stats.value("unique_levels_cleared"), 1)
	assert_eq(stats.value("perfects"), 2)
	assert_eq(stats.value("unique_perfects"), 1)
	var empty_ctx: Dictionary = StatsService.build_context(null, {}, {})
	assert_eq(empty_ctx["kind"], "normal")
	assert_false(bool(empty_ctx["first_clear"]))
