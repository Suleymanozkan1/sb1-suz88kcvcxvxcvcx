extends TestCase
## ProgressionService: world unlock rule (boss cleared AND star threshold),
## world aggregates, world stats and the Progress screen summary.

var profile: PlayerProfile
var bus: EventBus
var catalog: WorldCatalog
var worlds_unlocked: Array[String] = []
var levels_unlocked: Array[String] = []
var stat_events: Array[String] = []


func before_each() -> void:
	profile = PlayerProfile.new()
	bus = EventBus.new()
	catalog = WorldCatalog.load_default()
	# Lambdas capture local arrays (shared by reference), never `self`, so the
	# bus does not keep this test case alive.
	var worlds_sink: Array[String] = []
	var levels_sink: Array[String] = []
	var stats_sink: Array[String] = []
	worlds_unlocked = worlds_sink
	levels_unlocked = levels_sink
	stat_events = stats_sink
	bus.world_unlocked.connect(func(id: String) -> void: worlds_sink.append(id))
	bus.level_unlocked.connect(func(id: String) -> void: levels_sink.append(id))
	bus.stat_changed.connect(func(stat: StringName, v: int) -> void: stats_sink.append("%s=%d" % [stat, v]))


func _service() -> ProgressionService:
	return ProgressionService.new(profile, bus, catalog)


func _run(level_id: String, stars: int) -> RunResult:
	var r: RunResult = RunResult.new()
	r.level_id = level_id
	r.completed = true
	r.stars = stars
	r.score = 1000
	r.time_seconds = 30.0
	return r


func _clear_direct(world_index: int, from_local: int, to_local: int, stars: int) -> void:
	for local_index: int in range(from_local, to_local + 1):
		profile.levels[WorldCatalog.level_id(world_index, local_index)] = {
			"stars": stars, "best_score": 100, "perfect": stars == 3, "clears": 1,
			"attempts": 1, "best_combo": 3, "best_time": 20.0,
		}


func test_world_data_thresholds_are_sane() -> void:
	assert_eq(catalog.world_count(), 10)
	assert_eq(int(catalog.world_at(1)["unlock_stars"]), 0, "first world free")
	var prev: int = 0
	for i: int in range(2, 11):
		var need: int = int(catalog.world_at(i)["unlock_stars"])
		var available: int = (i - 1) * 52 * 3
		assert_gt(need, prev, "thresholds increase")
		assert_le(need, available, "world %d threshold reachable" % i)
		prev = need


func test_world2_needs_boss_even_with_enough_stars() -> void:
	_clear_direct(1, 1, 51, 3)
	var svc: ProgressionService = _service()
	assert_ge(svc.total_stars(), int(catalog.world_at(2)["unlock_stars"]), "stars requirement met")
	assert_false(svc.is_world_unlocked("crystal_valley"), "locked: boss not cleared")
	assert_false(svc.is_level_unlocked("w02_l01"))
	assert_empty(svc.refresh_world_unlocks(), "refresh does not unlock without the boss")
	var out: Dictionary = svc.record_level_result(_run("w01_l52", 2))
	var newly: Array[String] = out["unlocked_worlds"] as Array[String]
	assert_eq(newly.size(), 1)
	assert_eq(newly[0], "crystal_valley", "boss clear unlocks world 2")
	assert_eq(out["unlocked_level"], "w02_l01", "first level of world 2 unlocked")
	assert_eq(worlds_unlocked.size(), 1, "world_unlocked emitted once")
	assert_has(levels_unlocked, "w02_l01")
	assert_true(svc.is_world_unlocked("crystal_valley"))
	assert_true(profile.unlocked_worlds.has("crystal_valley"), "unlock persisted in profile")


func test_world2_needs_stars_even_with_boss_cleared() -> void:
	_clear_direct(1, 1, 51, 1)
	var svc: ProgressionService = _service()
	var boss: Dictionary = svc.record_level_result(_run("w01_l52", 1))
	assert_eq(svc.total_stars(), 52)
	assert_empty(boss["unlocked_worlds"] as Array[String], "stars short: still locked")
	assert_eq(boss["unlocked_level"], "", "w02_l01 not unlocked")
	assert_false(svc.is_world_unlocked("crystal_valley"))
	assert_false(svc.is_level_unlocked("w02_l01"))
	assert_eq(svc.stars_needed_for("crystal_valley"), 90 - 52)
	# Replaying world 1 for better stars eventually opens world 2.
	var opened_on: String = ""
	for local_index: int in range(1, 53):
		var id: String = WorldCatalog.level_id(1, local_index)
		var out: Dictionary = svc.record_level_result(_run(id, 3))
		if not (out["unlocked_worlds"] as Array[String]).is_empty():
			opened_on = id
			assert_eq(out["unlocked_level"], "w02_l01", "world unlock announces its first level")
			break
	assert_eq(opened_on, "w01_l19", "38 more stars needed = 19 levels improved from 1 to 3")
	assert_true(svc.is_world_unlocked("crystal_valley"))
	assert_eq(svc.stars_needed_for("crystal_valley"), 0)
	assert_eq(worlds_unlocked.size(), 1)


func test_world_unlock_is_permanent_and_not_repeated() -> void:
	_clear_direct(1, 1, 51, 3)
	var svc: ProgressionService = _service()
	svc.record_level_result(_run("w01_l52", 3))
	assert_empty(svc.refresh_world_unlocks(), "second refresh unlocks nothing new")
	assert_eq(worlds_unlocked.size(), 1)
	# Even if stars were somehow lost (e.g. a data reset of one level), the world stays open.
	profile.levels.erase("w01_l10")
	assert_true(svc.is_world_unlocked("crystal_valley"), "unlocks are never revoked")


func test_construction_syncs_existing_unlocks_silently() -> void:
	_clear_direct(1, 1, 52, 2)
	_clear_direct(2, 1, 52, 2)
	_clear_direct(3, 1, 52, 3)
	var svc: ProgressionService = _service()
	assert_empty(worlds_unlocked, "no signals for unlocks that already held")
	assert_true(svc.is_world_unlocked("crystal_valley"))
	assert_true(svc.is_world_unlocked("molten_grid"))
	assert_true(svc.is_world_unlocked("cloud_factory"), "%d stars >= 300" % svc.total_stars())
	assert_false(svc.is_world_unlocked("deep_ocean"), "world 4 boss not cleared")
	assert_eq(svc.highest_unlocked_level(), "w04_l01")
	assert_eq(svc.next_level_to_play(), "w04_l01")


func test_world_aggregates() -> void:
	_clear_direct(1, 1, 52, 3)
	_clear_direct(2, 1, 10, 2)
	var svc: ProgressionService = _service()
	assert_eq(svc.world_stars(1), 156)
	assert_eq(svc.world_cleared_count(1), 52)
	assert_true(svc.world_complete(1))
	assert_true(svc.world_perfect(1))
	assert_eq(svc.world_stars(2), 20)
	assert_eq(svc.world_cleared_count(2), 10)
	assert_false(svc.world_complete(2))
	assert_false(svc.world_perfect(2))
	assert_eq(svc.world_stars(11), 0, "unknown world index is empty")
	assert_false(svc.world_perfect(0))
	assert_eq(svc.total_stars(), 176)


func test_world_perfect_requires_every_star() -> void:
	_clear_direct(1, 1, 52, 3)
	profile.levels["w01_l30"]["stars"] = 2
	var svc: ProgressionService = _service()
	assert_true(svc.world_complete(1))
	assert_false(svc.world_perfect(1), "one level short of 3 stars")


func test_total_stars_ignores_unknown_levels() -> void:
	profile.levels["bogus"] = {"stars": 3, "clears": 1}
	profile.levels["w42_l01"] = {"stars": 3, "clears": 1}
	profile.levels["w01_l01"] = {"stars": 7, "clears": 1}
	var svc: ProgressionService = _service()
	assert_eq(svc.total_stars(), 3, "only catalog levels count, clamped to 3")


func test_world_completion_outcome_and_world_stats() -> void:
	_clear_direct(1, 1, 51, 3)
	var svc: ProgressionService = _service()
	var out: Dictionary = svc.record_level_result(_run("w01_l52", 3))
	assert_eq(out["world_completed"], "neon_core", "first completion of the world reported")
	assert_eq(out["world_perfected"], "neon_core", "first perfection reported")
	assert_eq(profile.stat(StatsService.WORLDS_COMPLETED), 1)
	assert_eq(profile.stat(StatsService.WORLDS_PERFECTED), 1)
	assert_has(stat_events, "worlds_completed=1", "stat_changed emitted")
	var replay: Dictionary = svc.record_level_result(_run("w01_l52", 3))
	assert_eq(replay["world_completed"], "", "only reported once")
	assert_eq(profile.stat(StatsService.WORLDS_COMPLETED), 1)


func test_stars_needed_for_edge_cases() -> void:
	var svc: ProgressionService = _service()
	assert_eq(svc.stars_needed_for("neon_core"), 0, "first world needs nothing")
	assert_eq(svc.stars_needed_for("nowhere"), 0, "unknown world")
	assert_eq(svc.stars_needed_for("candy_reactor"), 1030)
	assert_false(svc.is_world_unlocked("nowhere"))
	assert_false(svc.is_world_unlocked(""))


func test_progress_summary_covers_ten_worlds() -> void:
	_clear_direct(1, 1, 52, 2)
	var svc: ProgressionService = _service()
	var summary: Dictionary = svc.progress_summary()
	var worlds: Array[Dictionary] = summary["worlds"] as Array[Dictionary]
	assert_eq(worlds.size(), 10, "one entry per world")
	for i: int in worlds.size():
		var w: Dictionary = worlds[i]
		for key: String in ["index", "id", "name", "stars", "max", "cleared", "unlocked", "perfect"]:
			assert_has(w, key, "world summary has %s" % key)
		assert_eq(int(w["index"]), i + 1)
		assert_eq(int(w["max"]), 156)
		assert_eq(str(w["id"]), str(catalog.world_at(i + 1)["id"]))
	assert_eq(int(worlds[0]["stars"]), 104)
	assert_eq(int(worlds[0]["cleared"]), 52)
	assert_true(bool(worlds[0]["unlocked"]))
	assert_true(bool(worlds[0]["complete"]))
	assert_false(bool(worlds[0]["perfect"]))
	assert_true(bool(worlds[1]["unlocked"]), "104 stars >= 90 and boss cleared")
	assert_false(bool(worlds[2]["unlocked"]))
	assert_eq(int(worlds[2]["stars_required"]), 190)
	assert_eq(int(summary["total_stars"]), 104)
	assert_eq(int(summary["max_stars"]), 1560)
	assert_eq(int(summary["levels_cleared"]), 52)
	assert_eq(int(summary["total_levels"]), 520)
	assert_eq(int(summary["worlds_unlocked"]), 2)
	assert_has(summary, "xp")
