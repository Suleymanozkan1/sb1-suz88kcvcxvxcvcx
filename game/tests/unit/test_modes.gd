extends TestCase
## Game modes: data, modifiers, unlocks, score rewards, strict perfect rule and
## the deterministic endless stream.

const REQUIRED: PackedStringArray = [
	"classic", "endless", "time_attack", "daily", "perfect_run", "zen", "hard", "boss_rush"
]


func _catalog() -> ModeCatalog:
	return ModeCatalog.load_default()


func test_catalog_has_all_modes_and_validates() -> void:
	var c: ModeCatalog = _catalog()
	for id: String in REQUIRED:
		assert_true(c.has(StringName(id)), "mode %s present" % id)
	assert_empty(c.validate(), "modes.json validates")


func test_modifiers_carry_mode_and_rules() -> void:
	var c: ModeCatalog = _catalog()
	var zen: Dictionary = c.sim_modifiers(&"zen")
	assert_eq(zen["mode"], "zen")
	assert_true(bool(zen["zen"]), "zen never fails")
	var perfect: Dictionary = c.sim_modifiers(&"perfect_run")
	assert_true(bool(perfect["strict"]), "perfect run is strict")
	assert_false(bool(perfect["shields_allowed"]), "no shields in perfect run")
	assert_eq(c.sim_modifiers(&"classic"), {"mode": "classic"})


func test_unlock_rules_are_honest_thresholds() -> void:
	var c: ModeCatalog = _catalog()
	var fresh: Dictionary = {"levels_cleared": 0, "perfects": 0, "bosses_cleared": 0, "worlds_cleared": 0}
	assert_true(c.is_unlocked(&"classic", fresh))
	assert_true(c.is_unlocked(&"zen", fresh))
	assert_false(c.is_unlocked(&"endless", fresh))
	assert_true(c.is_unlocked(&"endless", {"levels_cleared": 10}))
	assert_false(c.is_unlocked(&"boss_rush", {"bosses_cleared": 1}))
	var req: Dictionary = c.requirement(&"endless")
	assert_eq(req["key"], "mode.unlock.levels_cleared")
	assert_eq(int((req["args"] as Dictionary)["n"]), 10)


func test_score_rewards_are_proportional_and_capped() -> void:
	var c: ModeCatalog = _catalog()
	var small: Dictionary = c.score_reward(&"endless", 5000)
	var large: Dictionary = c.score_reward(&"endless", 50000000)
	assert_gt(float(small.get("coins", 0)), 0.0, "some coins for a real score")
	assert_eq(int(large["coins"]), int(c.score_rewards["max_coins"]), "capped")
	assert_eq(c.score_reward(&"zen", 99999), {}, "zen grants nothing")
	assert_eq(c.score_reward(&"endless", -10), {}, "negative scores grant nothing")


func test_endless_seed_is_weekly_and_deterministic() -> void:
	var a: int = ModeCatalog.endless_seed(&"endless", "2026-W40")
	assert_eq(a, ModeCatalog.endless_seed(&"endless", "2026-W40"))
	assert_ne(a, ModeCatalog.endless_seed(&"endless", "2026-W41"))
	assert_ne(a, ModeCatalog.endless_seed(&"time_attack", "2026-W40"))


func test_strict_rule_fails_on_missed_spark() -> void:
	var data: Dictionary = {
		"id": "t", "lanes": 2, "speed": 8.0, "length": 40.0, "entities": [{"t": "spark", "d": 20.0, "lane": 1}]
	}
	var relaxed: FluxSim = FluxSim.new(SimLevel.from_dict(data))
	var strict: FluxSim = FluxSim.new(SimLevel.from_dict(data))
	strict.strict = true
	for _i: int in 2000:
		relaxed.step(false)
		strict.step(false)
	assert_eq(relaxed.status, SimConst.Status.COMPLETED, "missing a spark is fine normally")
	assert_eq(strict.status, SimConst.Status.FAILED, "perfect run fails on a miss")
	assert_eq(strict.fail_reason, SimConst.FailReason.MISSED_SPARK)


func test_time_limit_completes_the_run() -> void:
	var data: Dictionary = {"id": "t", "lanes": 2, "speed": 8.0, "endless": true, "entities": []}
	var session_mods: Dictionary = _catalog().sim_modifiers(&"time_attack")
	var lvl: SimLevel = SimLevel.from_dict(data)
	lvl.time_limit = float(session_mods["time_limit"])
	var sim: FluxSim = FluxSim.new(lvl)
	var guard: int = 0
	while sim.is_running() and guard < 10000:
		sim.step(false)
		guard += 1
	assert_eq(sim.status, SimConst.Status.COMPLETED)
	assert_near(sim.time(), 60.0, 0.05, "ends at the time limit")


func _stream(seed_value: int) -> EndlessStreamer:
	var c: ModeCatalog = _catalog()
	var catalog: WorldCatalog = WorldCatalog.load_default()
	var spec: LevelSpec = c.stream_spec(&"endless", seed_value, catalog.world_at(1), DifficultyModel.new(catalog))
	return EndlessStreamer.new(spec)


func test_endless_stream_is_deterministic_and_ordered() -> void:
	var a: EndlessStreamer = _stream(1234)
	var b: EndlessStreamer = _stream(1234)
	var da: Dictionary = a.begin()
	var db: Dictionary = b.begin()
	assert_eq(JsonIO.canonical(da), JsonIO.canonical(db), "same seed -> same opening")
	assert_true(bool(da["endless"]))
	var ents: Array = da["entities"] as Array
	assert_gt(float(ents.size()), 10.0, "opening has content")
	var last: float = -INF
	for e: Variant in ents:
		var d: float = float((e as Dictionary)["d"])
		assert_ge(d, last, "entities sorted by distance")
		last = d


func test_endless_stream_is_solvable_by_its_plan() -> void:
	var streamer: EndlessStreamer = _stream(77)
	var data: Dictionary = streamer.begin()
	var sim: FluxSim = FluxSim.new(SimLevel.from_dict(data))
	var guard: int = 0
	var appended: int = 0
	while sim.is_running() and sim.d < 420.0 and guard < 30000:
		var taps: PackedInt32Array = streamer.planned_taps()
		sim.step(taps.has(sim.tick))
		if guard % 10 == 0:
			appended += streamer.pump(sim).size()
		guard += 1
	assert_false(streamer.failed, "stream kept generating")
	assert_eq(sim.status, SimConst.Status.RUNNING, "planned path survives the stream")
	assert_gt(sim.d, 400.0, "travelled far")
	assert_gt(float(appended), 0.0, "course was extended while running")


func test_stream_compaction_never_changes_the_course() -> void:
	var a: EndlessStreamer = _stream(4242)
	var b: EndlessStreamer = _stream(4242)
	b.compaction = false
	var ca: Dictionary = a.course_until(600.0)
	var cb: Dictionary = b.course_until(600.0)
	assert_eq(JsonIO.canonical(ca), JsonIO.canonical(cb), "same course with and without compaction")
	assert_lt(float(a.generator_entity_count()), float(b.generator_entity_count()), "compaction forgets old entities")


func test_stream_generator_memory_stays_bounded() -> void:
	var s: EndlessStreamer = _stream(99)
	s.course_until(2500.0)
	assert_lt(float(s.generator_entity_count()), 400.0, "only the recent course is kept for planning")


func test_stream_uses_the_mode_ramp_distance() -> void:
	var data: Dictionary = _stream(7).begin()
	var mods: Dictionary = data["modifiers"] as Dictionary
	assert_near(float(mods["ramp_distance"]), 900.0, 0.01, "endless ramps over its configured distance")


func test_star_total_unlocks_the_time_attack_challenge() -> void:
	var c: ModeCatalog = _catalog()
	assert_eq(str(c.mode(&"time_attack")["unlock"]["type"]), "stars")
	assert_false(c.is_unlocked(&"time_attack", {"stars": 59, "levels_cleared": 520}), "stars, not clears")
	assert_true(c.is_unlocked(&"time_attack", {"stars": 60}))
	assert_eq(c.requirement(&"time_attack")["key"], "mode.unlock.stars")
