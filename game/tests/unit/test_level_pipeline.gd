extends TestCase
## Level system: 520 data files, generator determinism, validator detection.


func test_catalog_has_ten_worlds_and_520_levels() -> void:
	var c: WorldCatalog = WorldCatalog.load_default()
	assert_eq(c.world_count(), 10)
	assert_eq(c.total_levels(), 520)
	for w: Dictionary in c.worlds:
		var n: int = int(w["levels"])
		assert_true(n >= 40 and n <= 60, "world %s has 40-60 levels" % w["id"])


func test_every_level_file_exists_and_loads() -> void:
	var repo: LevelRepository = LevelRepository.new()
	var missing: Array[String] = []
	for id: String in repo.all_level_ids():
		if repo.load_level(id).is_empty():
			missing.append(id)
	assert_empty(missing, "missing level files")


func test_generator_is_deterministic() -> void:
	var model: DifficultyModel = DifficultyModel.new()
	for n: int in [1, 77, 233, 401]:
		var a: Dictionary = LevelGenerator.new().generate(model.build_spec(n))
		var b: Dictionary = LevelGenerator.new().generate(model.build_spec(n))
		assert_eq(JsonIO.canonical(a), JsonIO.canonical(b), "level %d reproducible" % n)


func test_committed_data_matches_generator() -> void:
	var model: DifficultyModel = DifficultyModel.new()
	var repo: LevelRepository = LevelRepository.new()
	for n: int in [3, 60, 160, 290, 520]:
		var spec: LevelSpec = model.build_spec(n)
		var gen: Dictionary = LevelGenerator.new().generate(spec)
		# JSON stores every number as float; compare after the same round trip.
		var round_trip: Variant = JSON.parse_string(JsonIO.canonical(gen))
		assert_eq(
			JsonIO.canonical(repo.load_level(spec.id)),
			JsonIO.canonical(round_trip),
			"data == generator for %s" % spec.id
		)


func test_seed_changes_level() -> void:
	var model: DifficultyModel = DifficultyModel.new()
	var spec: LevelSpec = model.build_spec(30)
	var a: Dictionary = LevelGenerator.new().generate(spec)
	spec.seed += 1
	var b: Dictionary = LevelGenerator.new().generate(spec)
	assert_ne(JsonIO.canonical(a["entities"]), JsonIO.canonical(b["entities"]))


func test_difficulty_structure_tiers_and_specials() -> void:
	var model: DifficultyModel = DifficultyModel.new()
	assert_eq(model.build_spec(1).tier, "tutorial")
	assert_eq(model.build_spec(20).tier, "early")
	assert_eq(model.build_spec(520).tier, "endgame")
	assert_eq(model.build_spec(26).kind, "challenge")
	assert_eq(model.build_spec(52).kind, "boss")
	assert_eq(model.build_spec(53).chapter_phase, "introduction")
	assert_eq(model.build_spec(53).start_form, "phase", "world 2 starts teaching phase")
	assert_eq(model.build_spec(157).start_form, "dash")
	assert_eq(model.build_spec(209).start_form, "surge")
	assert_true(model.build_spec(1).forgiving)


func test_speed_rises_on_average_but_not_randomly() -> void:
	var model: DifficultyModel = DifficultyModel.new()
	var avg_first: float = 0.0
	var avg_last: float = 0.0
	for n: int in range(6, 26):
		avg_first += model.build_spec(n).speed
	for n: int in range(495, 515):
		avg_last += model.build_spec(n).speed
	assert_gt(avg_last, avg_first * 1.4, "late game noticeably faster")
	# Within a chapter the introduction level is easier than the pressure level.
	assert_lt(model.build_spec(53).speed, model.build_spec(64).speed)


func test_new_main_idea_every_10_to_20_levels() -> void:
	var c: WorldCatalog = WorldCatalog.load_default()
	var intro_numbers: Array[int] = []
	for w: Dictionary in c.worlds:
		for ch: Variant in w["chapters"] as Array:
			intro_numbers.append(c.global_number(int(w["index"]), int((ch as Dictionary)["start"])))
	for i: int in range(1, intro_numbers.size()):
		var gap: int = intro_numbers[i] - intro_numbers[i - 1]
		assert_true(gap >= 10 and gap <= 20, "gap %d between new ideas at %d" % [gap, intro_numbers[i]])


func _base_level() -> Dictionary:
	return LevelRepository.new().load_level("w01_l10").duplicate(true)


func _codes(data: Dictionary) -> PackedStringArray:
	var v: LevelValidator = LevelValidator.new()
	v.check_assets = false
	return v.validate(data).codes()


func test_validator_accepts_shipped_level() -> void:
	assert_empty(_codes(_base_level()), "w01_l10 valid")


func test_validator_detects_missing_objective() -> void:
	var d: Dictionary = _base_level()
	d["objective"] = {"type": ""}
	assert_has(_codes(d), "missing_objective")


func test_validator_detects_invalid_mechanic() -> void:
	var d: Dictionary = _base_level()
	(d["entities"] as Array).append({"t": "teleporter_x", "d": 30.0, "lane": 0})
	assert_has(_codes(d), "invalid_mechanic")


func test_validator_detects_spawn_collision() -> void:
	var d: Dictionary = _base_level()
	var first: Dictionary = (d["entities"] as Array)[0] as Dictionary
	(d["entities"] as Array).append({"t": "spark", "d": float(first["d"]), "lane": int(first.get("lane", 0))})
	var barrier: Dictionary = {}
	for e: Variant in d["entities"] as Array:
		if (e as Dictionary)["t"] == "barrier":
			barrier = e as Dictionary
			break
	(d["entities"] as Array).append({"t": "barrier", "d": float(barrier["d"]) + 0.1, "lanes": barrier["lanes"]})
	assert_has(_codes(d), "spawn_collision")


func test_validator_detects_broken_trigger() -> void:
	var d: Dictionary = _base_level()
	(d["mechanics"] as Array).append("portal")
	(d["entities"] as Array).append({"t": "portal", "d": 30.5, "lane": 0, "to": 0})
	assert_has(_codes(d), "broken_trigger")


func test_validator_detects_impossible_level() -> void:
	var d: Dictionary = _base_level()
	(d["solution"] as Dictionary)["taps"] = []
	assert_has(_codes(d), "impossible_level")


func test_validator_detects_invalid_sequence() -> void:
	var d: Dictionary = _base_level()
	(d["mechanics"] as Array).append("form_gate")
	(d["entities"] as Array).append({"t": "form_gate", "d": 31.0, "form": "hop"})
	assert_has(_codes(d), "invalid_sequence")


func test_validator_detects_missing_asset() -> void:
	var d: Dictionary = _base_level()
	d["environment"] = "atlantis"
	assert_has(_codes(d), "missing_asset")


func test_validator_detects_dead_end_current() -> void:
	var lvl: Dictionary = {
		"id": "x",
		"number": 1,
		"world": "molten_grid",
		"kind": "normal",
		"tier": "early",
		"difficulty": 0.1,
		"seed": 1,
		"lanes": 2,
		"speed": 9.0,
		"length": 60.0,
		"start_form": "hop",
		"start_lane": 0,
		"entities":
		[
			{"t": "current", "d": 20.0, "lanes": [0], "to": 1},
			{"t": "barrier", "d": 21.2, "lanes": [1]},
			{"t": "spark", "d": 30.0, "lane": 0},
		],
		"objective": {"type": "reach_end", "target": 0},
		"mechanics": ["hop", "current", "spark"],
		"score_target": 10,
		"perfect_target": 1,
		"combo_target": 1,
		"environment": "molten_grid",
		"music": "molten_grid",
		"visual_theme": "molten_grid",
		"unlock": {},
		"spawn": {},
		"modifiers": {"hop_time": 0.13, "speed_ramp": 0.0},
		"solution": {"taps": [140]},
	}
	var codes: PackedStringArray = _codes(lvl)
	assert_true(codes.has("dead_end") or codes.has("impossible_level"), "trap detected: %s" % str(codes))


func test_autopilot_solver_solves_independently() -> void:
	var repo: LevelRepository = LevelRepository.new()
	for id: String in ["w01_l03", "w02_l05", "w04_l04", "w05_l03"]:
		var solver: AutopilotSolver = AutopilotSolver.new()
		assert_true(solver.solve(SimLevel.from_dict(repo.load_level(id))), "%s solvable without stored solution" % id)
