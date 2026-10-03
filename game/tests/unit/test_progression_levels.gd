extends TestCase
## ProgressionService: per-level records (attempts, stars, best score/time,
## perfect, combo) and level unlocks in campaign order.

var profile: PlayerProfile
var bus: EventBus
var catalog: WorldCatalog
var svc: ProgressionService
var unlocked_levels: Array[String] = []
var star_totals: Array[int] = []


func before_each() -> void:
	profile = PlayerProfile.new()
	bus = EventBus.new()
	catalog = WorldCatalog.load_default()
	svc = ProgressionService.new(profile, bus, catalog)
	# Lambdas capture local arrays (shared by reference), never `self`: a
	# self-capturing lambda on the bus would keep this test case alive.
	var levels_sink: Array[String] = []
	var stars_sink: Array[int] = []
	unlocked_levels = levels_sink
	star_totals = stars_sink
	bus.level_unlocked.connect(func(id: String) -> void: levels_sink.append(id))
	bus.stars_changed.connect(func(total: int) -> void: stars_sink.append(total))


func _run(level_id: String, completed: bool, stars: int = 1, score: int = 100, time_s: float = 30.0) -> RunResult:
	var r: RunResult = RunResult.new()
	r.level_id = level_id
	r.mode = &"classic"
	r.completed = completed
	r.stars = stars if completed else 0
	r.score = score
	r.time_seconds = time_s
	r.max_combo = 4
	return r


func _clear_direct(world_index: int, from_local: int, to_local: int, stars: int) -> void:
	for local_index: int in range(from_local, to_local + 1):
		profile.levels[WorldCatalog.level_id(world_index, local_index)] = {
			"stars": stars, "best_score": 100, "perfect": stars == 3, "clears": 1,
			"attempts": 1, "best_combo": 3, "best_time": 20.0,
		}


func test_fresh_profile_only_first_level_unlocked() -> void:
	assert_true(svc.is_level_unlocked("w01_l01"), "w01_l01 always unlocked")
	assert_false(svc.is_level_unlocked("w01_l02"), "w01_l02 locked on a fresh profile")
	assert_false(svc.is_level_unlocked("w02_l01"), "next world locked")
	assert_false(svc.is_level_unlocked("bogus"), "invalid ids are never unlocked")
	assert_false(svc.is_level_unlocked("w11_l01"), "ids outside the catalog are never unlocked")
	assert_eq(svc.total_stars(), 0)
	assert_eq(svc.max_stars(), 520 * 3)


func test_first_clear_unlocks_next_level() -> void:
	var out: Dictionary = svc.record_level_result(_run("w01_l01", true, 2, 300))
	assert_true(bool(out["accepted"]))
	assert_true(bool(out["first_clear"]), "first clear flagged")
	assert_eq(out["unlocked_level"], "w01_l02", "next level reported")
	assert_eq(unlocked_levels.size(), 1)
	assert_eq(unlocked_levels[0], "w01_l02", "level_unlocked emitted")
	assert_true(svc.is_level_unlocked("w01_l02"))
	assert_false(svc.is_level_unlocked("w01_l03"))
	var again: Dictionary = svc.record_level_result(_run("w01_l01", true, 2, 200))
	assert_false(bool(again["first_clear"]), "second clear is not a first clear")
	assert_eq(again["unlocked_level"], "", "nothing new unlocked on replay")
	assert_eq(unlocked_levels.size(), 1, "no duplicate unlock signal")
	assert_eq(int(profile.level_result("w01_l01")["clears"]), 2)


func test_failed_run_only_counts_attempts() -> void:
	var out: Dictionary = svc.record_level_result(_run("w01_l01", false, 0, 999))
	var rec: Dictionary = profile.level_result("w01_l01")
	assert_true(bool(out["accepted"]))
	assert_eq(int(rec["attempts"]), 1, "attempt counted")
	assert_eq(int(rec["clears"]), 0, "no clear on fail")
	assert_eq(int(rec["stars"]), 0, "no stars on fail")
	assert_eq(int(rec["best_score"]), 0, "fail score never becomes best")
	assert_false(bool(out["first_clear"]))
	assert_eq(out["unlocked_level"], "")
	assert_false(svc.is_level_unlocked("w01_l02"), "fail does not unlock")
	assert_empty(star_totals, "no stars_changed on fail")
	svc.record_level_result(_run("w01_l01", false))
	svc.record_level_result(_run("w01_l01", true))
	assert_eq(int(profile.level_result("w01_l01")["attempts"]), 3, "every run is an attempt")


func test_stars_keep_max() -> void:
	var first: Dictionary = svc.record_level_result(_run("w01_l01", true, 2))
	assert_eq(int(first["prev_stars"]), 0)
	assert_eq(int(first["new_stars"]), 2, "delta on first clear")
	var worse: Dictionary = svc.record_level_result(_run("w01_l01", true, 1))
	assert_eq(int(worse["prev_stars"]), 2)
	assert_eq(int(worse["new_stars"]), 0, "no delta when worse")
	assert_eq(profile.stars_for("w01_l01"), 2, "stars never decrease")
	var better: Dictionary = svc.record_level_result(_run("w01_l01", true, 3))
	assert_eq(int(better["new_stars"]), 1, "delta is the improvement only")
	assert_eq(int(better["stars"]), 3)
	assert_eq(profile.stars_for("w01_l01"), 3)
	assert_eq(star_totals.size(), 2, "stars_changed only when stars grow")
	assert_eq(star_totals[1], 3, "stars_changed carries the new total")


func test_completed_run_always_earns_at_least_one_star() -> void:
	var r: RunResult = _run("w01_l01", true, 0)
	svc.record_level_result(r)
	assert_eq(profile.stars_for("w01_l01"), 1)
	var r2: RunResult = _run("w01_l02", true, 9)
	svc.record_level_result(r2)
	assert_eq(profile.stars_for("w01_l02"), 3, "stars clamped to 3")


func test_best_score_and_best_time() -> void:
	var a: Dictionary = svc.record_level_result(_run("w01_l01", true, 1, 500, 40.0))
	assert_false(bool(a["new_best"]), "first clear has nothing to beat")
	var rec: Dictionary = profile.level_result("w01_l01")
	assert_eq(int(rec["best_score"]), 500)
	assert_near(float(rec["best_time"]), 40.0, 0.001)
	var b: Dictionary = svc.record_level_result(_run("w01_l01", true, 1, 300, 35.0))
	rec = profile.level_result("w01_l01")
	assert_false(bool(b["new_best"]), "lower score is not a best")
	assert_eq(int(rec["best_score"]), 500, "best score kept")
	assert_near(float(rec["best_time"]), 35.0, 0.001, "faster time recorded")
	var c: Dictionary = svc.record_level_result(_run("w01_l01", true, 1, 900, 50.0))
	rec = profile.level_result("w01_l01")
	assert_true(bool(c["new_best"]), "higher score is a new best")
	assert_eq(int(rec["best_score"]), 900)
	assert_near(float(rec["best_time"]), 35.0, 0.001, "slower time ignored")
	svc.record_level_result(_run("w01_l01", true, 1, 100, 0.0))
	assert_near(float(profile.level_result("w01_l01")["best_time"]), 35.0, 0.001, "zero time ignored")
	svc.record_level_result(_run("w01_l01", false, 0, 100, 5.0))
	assert_near(float(profile.level_result("w01_l01")["best_time"]), 35.0, 0.001, "failed runs never set time")


func test_perfect_flag_and_best_combo() -> void:
	var r: RunResult = _run("w01_l01", true, 3)
	r.perfect = true
	r.max_combo = 40
	var first: Dictionary = svc.record_level_result(r)
	assert_true(bool(first["first_perfect"]), "first perfect flagged")
	var again: Dictionary = svc.record_level_result(r)
	assert_false(bool(again["first_perfect"]), "first perfect only once")
	var plain: RunResult = _run("w01_l01", true, 1)
	plain.max_combo = 12
	svc.record_level_result(plain)
	var rec: Dictionary = profile.level_result("w01_l01")
	assert_true(bool(rec["perfect"]), "perfect is sticky")
	assert_eq(int(rec["best_combo"]), 40, "best combo is a max")


func test_locked_invalid_and_null_results_are_ignored() -> void:
	var locked: Dictionary = svc.record_level_result(_run("w01_l05", true, 3))
	assert_false(bool(locked["accepted"]), "locked level rejected")
	assert_false(profile.levels.has("w01_l05"), "no record for a locked level")
	var unknown: Dictionary = svc.record_level_result(_run("w99_l01", true, 3))
	assert_false(bool(unknown["accepted"]))
	var empty: Dictionary = svc.record_level_result(_run("", true, 3))
	assert_false(bool(empty["accepted"]))
	var none: Dictionary = svc.record_level_result(null)
	assert_false(bool(none["accepted"]))
	assert_true(none.has("unlocked_worlds"), "outcome shape stable on rejection")
	assert_empty(profile.levels, "nothing recorded")


func test_level_id_falls_back_to_meta() -> void:
	var r: RunResult = _run("", true, 2)
	var out: Dictionary = svc.record_level_result(r, {"id": "w01_l01"})
	assert_true(bool(out["accepted"]))
	assert_eq(out["level_id"], "w01_l01")
	assert_eq(profile.stars_for("w01_l01"), 2)


func test_non_campaign_modes_do_not_update_records() -> void:
	var r: RunResult = _run("w01_l01", true, 3)
	r.mode = &"zen"
	var out: Dictionary = svc.record_level_result(r)
	assert_false(bool(out["accepted"]), "zen runs never unlock or award stars")
	assert_false(profile.levels.has("w01_l01"))
	assert_false(svc.is_level_unlocked("w01_l02"))


func test_highest_unlocked_and_next_level_to_play() -> void:
	assert_eq(svc.highest_unlocked_level(), "w01_l01")
	assert_eq(svc.next_level_to_play(), "w01_l01")
	_clear_direct(1, 1, 5, 2)
	assert_eq(svc.highest_unlocked_level(), "w01_l06")
	assert_eq(svc.next_level_to_play(), "w01_l06")
	# A gap (e.g. an imported save) points the player back to the hole.
	profile.levels["w01_l03"]["clears"] = 0
	assert_eq(svc.next_level_to_play(), "w01_l03")
	assert_false(svc.is_level_unlocked("w01_l04"), "level after an uncleared level is locked")


func test_unlock_order_matches_level_repository() -> void:
	var repo: LevelRepository = LevelRepository.new(catalog)
	var current: String = "w01_l01"
	for _i: int in 6:
		var next_id: String = repo.next_level_id(current)
		assert_false(svc.is_level_unlocked(next_id), "%s locked before %s clear" % [next_id, current])
		var out: Dictionary = svc.record_level_result(_run(current, true, 1))
		assert_eq(out["unlocked_level"], next_id, "clearing %s unlocks %s" % [current, next_id])
		current = next_id


func test_partial_records_are_repaired() -> void:
	profile.levels["w01_l01"] = {"stars": 2, "clears": "x"}
	var out: Dictionary = svc.record_level_result(_run("w01_l01", true, 1, 50, 12.0))
	var rec: Dictionary = profile.level_result("w01_l01")
	assert_true(bool(out["first_clear"]), "non-numeric clears treated as 0")
	for key: String in ["stars", "best_score", "perfect", "clears", "attempts", "best_combo", "best_time"]:
		assert_has(rec, key, "record repaired with %s" % key)
	assert_eq(int(rec["stars"]), 2, "existing stars kept")


func test_progress_survives_save_round_trip() -> void:
	svc.record_level_result(_run("w01_l01", true, 3, 700, 22.0))
	svc.record_level_result(_run("w01_l02", true, 2, 400, 25.0))
	var saved: Dictionary = JSON.parse_string(JSON.stringify(profile.to_dict())) as Dictionary
	var restored: PlayerProfile = PlayerProfile.from_dict(saved)
	var svc2: ProgressionService = ProgressionService.new(restored, EventBus.new(), catalog)
	assert_eq(svc2.total_stars(), 5)
	assert_true(svc2.is_level_unlocked("w01_l03"))
	assert_eq(svc2.next_level_to_play(), "w01_l03")
