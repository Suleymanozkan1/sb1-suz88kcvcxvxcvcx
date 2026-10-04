extends TestCase
## Mass & gravity chapters in the shipped content: each places its mechanic,
## the stored solutions use them fairly, the validator catches broken data and
## set pieces never inherit them.

const CHAPTERS: Dictionary = {
	"launch_pad": ["w09", 14, 25],
	"gravity": ["w09", 40, 51],
	"plate": ["w10", 1, 13],
}


func _count(level: Dictionary, type: String) -> int:
	var n: int = 0
	for e: Variant in level["entities"] as Array:
		if str((e as Dictionary)["t"]) == type:
			n += 1
	return n


func _replay(level: Dictionary) -> FluxSim:
	var sim: FluxSim = FluxSim.new()
	sim.record_events = false
	sim.shields_allowed = false
	sim.setup(SimLevel.from_dict(level))
	var replay: RunReplay = RunReplay.new()
	for t: Variant in (level["solution"] as Dictionary)["taps"] as Array:
		replay.tap_ticks.append(int(t))
	return replay.play_on(sim)


func _validator() -> LevelValidator:
	var v: LevelValidator = LevelValidator.new()
	v.check_assets = false
	return v


func test_each_chapter_places_its_mechanic() -> void:
	var repo: LevelRepository = LevelRepository.new()
	for type: String in CHAPTERS:
		var range_info: Array = CHAPTERS[type] as Array
		var total: int = 0
		for local: int in range(int(range_info[1]), int(range_info[2]) + 1):
			total += _count(repo.load_level("%s_l%02d" % [range_info[0], local]), type)
		assert_gt(float(total), 10.0, "%s chapter of %s places %s" % [range_info[1], range_info[0], type])
	var fused: Dictionary = {}
	for local: int in range(27, 40):
		var level: Dictionary = repo.load_level("w10_l%02d" % local)
		for type: String in CHAPTERS:
			if _count(level, type) > 0:
				fused[type] = true
	assert_eq(fused.size(), 3, "World 10's fused chapter mixes all three")


func test_stored_solutions_fly_over_every_wall() -> void:
	var repo: LevelRepository = LevelRepository.new()
	for local: int in [14, 15, 20, 25]:
		var level: Dictionary = repo.load_level("w09_l%02d" % local)
		var sim: FluxSim = _replay(level)
		assert_eq(sim.status, SimConst.Status.COMPLETED, str(level["id"]))
		assert_eq(sim.launches, _count(level, "launch_pad"), "%s: every pad is used" % str(level["id"]))
		assert_ge(sim.vaults, sim.launches, "%s: every flight clears its wall" % str(level["id"]))


func test_glass_rows_wait_for_a_full_stack() -> void:
	var repo: LevelRepository = LevelRepository.new()
	var crashes: int = 0
	for local: int in range(1, 14):
		var level: Dictionary = repo.load_level("w10_l%02d" % local)
		var sim: FluxSim = _replay(level)
		assert_eq(sim.status, SimConst.Status.COMPLETED, str(level["id"]))
		crashes += sim.stack_crashes
		var glass_rows: Dictionary = {}
		for e: Variant in level["entities"] as Array:
			if str((e as Dictionary)["t"]) == "breakable":
				glass_rows[float((e as Dictionary)["d"])] = true
		# Combination levels bring back the dash form, which breaks glass too.
		if not (level["mechanics"] as Array).has("dash"):
			assert_eq(sim.stack_crashes, glass_rows.size(), "%s: each glass row is a stack crash" % str(level["id"]))
	assert_gt(float(crashes), 5.0, "the plates chapter really crashes glass")


func test_special_bands_fit_in_one_roll() -> void:
	for w: Dictionary in WorldCatalog.load_default().worlds:
		var groups: Array = (w.get("chapters", []) as Array).duplicate()
		groups.append(w.get("challenge", {}))
		groups.append(w.get("boss", {}))
		for g: Variant in groups:
			var c: Dictionary = g as Dictionary
			var sum: float = 0.0
			for key: String in ["current", "portal", "launch", "gravity", "plate"]:
				sum += float(c.get(key, 0.0))
			assert_le(
				sum, 1.0, "%s %s special chances" % [str(w.get("id", "")), str(c.get("intro", c.get("name", "")))]
			)


func test_set_pieces_do_not_inherit_mass_and_gravity() -> void:
	var model: DifficultyModel = DifficultyModel.new()
	var catalog: WorldCatalog = WorldCatalog.load_default()
	for local: int in [26, 52]:
		for wi: int in [9, 10]:
			var spec: LevelSpec = model.build_spec(catalog.global_number(wi, local))
			var label: String = spec.id
			assert_eq(spec.launch_chance, 0.0, "%s launch" % label)
			assert_eq(spec.gravity_chance, 0.0, "%s gravity" % label)
			assert_eq(spec.plate_chance, 0.0, "%s plates" % label)
	var challenge: LevelSpec = model.build_spec(catalog.global_number(9, 26))
	assert_near(challenge.current_chance, 0.3, 0.0001, "w09 challenge keeps its currents")


func test_untouched_set_piece_regenerates_identically() -> void:
	var model: DifficultyModel = DifficultyModel.new()
	var catalog: WorldCatalog = WorldCatalog.load_default()
	var committed: Dictionary = LevelRepository.new().load_level("w09_l26")
	var generated: Dictionary = LevelGenerator.new().generate(model.build_spec(catalog.global_number(9, 26)))
	# JSON stores every number as float; compare after the same round trip.
	var round_trip: Variant = JSON.parse_string(JsonIO.canonical(generated))
	assert_eq(JsonIO.canonical(committed), JsonIO.canonical(round_trip), "w09_l26 unchanged")


func test_validator_catches_broken_mass_and_gravity_data() -> void:
	var base: Dictionary = LevelRepository.new().load_level("w09_l14")
	var v: LevelValidator = _validator()
	assert_true(v.validate(base).ok(), "shipped level validates")
	var bad_g: Dictionary = base.duplicate(true)
	(bad_g["entities"] as Array).append({"t": "gravity", "d": 30.0, "span": 6.0, "g": 1.02})
	assert_has(v.validate(bad_g).codes(), "broken_trigger", "a gravity factor of ~1 is refused")
	var overlap: Dictionary = base.duplicate(true)
	(overlap["entities"] as Array).append({"t": "gravity", "d": 30.0, "span": 8.0, "g": 1.4})
	(overlap["entities"] as Array).append({"t": "gravity", "d": 34.0, "span": 8.0, "g": 0.7})
	overlap["mechanics"] = (overlap["mechanics"] as Array) + ["gravity"]
	assert_has(v.validate(overlap).codes(), "spawn_collision", "overlapping wells")
	var undeclared: Dictionary = base.duplicate(true)
	(undeclared["entities"] as Array).append({"t": "plate", "d": 30.0, "lane": 0})
	assert_has(v.validate(undeclared).codes(), "invalid_mechanic", "plates need the stack mechanic")
	var buried: Dictionary = base.duplicate(true)
	var first_pad: Dictionary = {}
	for e: Variant in buried["entities"] as Array:
		if str((e as Dictionary)["t"]) == "launch_pad":
			first_pad = e as Dictionary
			break
	(buried["entities"] as Array).append(
		{"t": "barrier", "d": float(first_pad["d"]) + 0.3, "lanes": [int(first_pad["lane"])]}
	)
	assert_has(v.validate(buried).codes(), "spawn_collision", "a pad needs clear floor")


func test_validator_catches_a_pad_into_a_landing_block() -> void:
	var pad_d: float = 30.0
	var land_d: float = pad_d + 8.0 * 2.0 * SimConst.LAUNCH_VY / SimConst.G0
	var level: Dictionary = {
		"id": "t_pad",
		"number": 1,
		"world": "void_space",
		"kind": "normal",
		"tier": "master",
		"difficulty": 0.5,
		"seed": 1,
		"lanes": 2,
		"speed": 8.0,
		"length": 60.0,
		"start_form": "hop",
		"entities":
		[
			{"t": "spark", "d": 20.0, "lane": 0},
			{"t": "launch_pad", "d": pad_d, "lane": 0},
			{"t": "barrier", "d": snappedf(land_d + 0.6, 0.01), "lanes": [0]},
		],
		"objective": {"type": "reach_end", "target": 0},
		"mechanics": ["hop", "launch", "spark"],
		"score_target": 10,
		"perfect_target": 1,
		"combo_target": 1,
		"environment": "void_space",
		"music": "void_space",
		"visual_theme": "void_space",
		"unlock": {},
		"spawn": {},
		# The stored solution steers in the air (tick 243 is mid-flight), so it
		# survives; a player who does not steer lands straight on the block.
		"modifiers": {"hop_time": 0.13, "speed_ramp": 0.0},
		"solution": {"taps": [243]},
	}
	var codes: PackedStringArray = _validator().validate(level).codes()
	assert_has(codes, "dead_end", "a flight that lands with no reaction time is a dead end")


func test_solver_solves_new_chapters_without_the_stored_solution() -> void:
	var repo: LevelRepository = LevelRepository.new()
	for id: String in ["w09_l15", "w10_l03"]:
		var solver: AutopilotSolver = AutopilotSolver.new()
		assert_true(solver.solve(SimLevel.from_dict(repo.load_level(id))), "%s solvable independently" % id)


func test_no_extra_dash_keeps_a_stack_the_level_spends() -> void:
	# R-6: for every stack crash the solution makes in dash form, try an extra
	# dash just before it: the stack must still be spent there.
	var repo: LevelRepository = LevelRepository.new()
	var probed: int = 0
	for local: int in range(1, 53):
		var level: Dictionary = repo.load_level("w10_l%02d" % local)
		if not (level["mechanics"] as Array).has("stack"):
			continue
		var taps: PackedInt32Array = PackedInt32Array()
		for t: Variant in (level["solution"] as Dictionary)["taps"] as Array:
			taps.append(int(t))
		for crash_tick: int in _dash_crash_ticks(level, taps):
			for early: int in [3, 6, 9]:
				var extra: int = crash_tick - early
				if _too_close(taps, extra):
					continue
				var probe: FluxSim = _probe_until(level, taps, extra, crash_tick + 30)
				probed += 1
				assert_lt(probe.plates, SimConst.MAX_PLATES, "%s: a dash at %d keeps the stack" % [level["id"], extra])
	assert_gt(float(probed), 0.0, "World 10 has dash-form stack crashes to probe")


func _dash_crash_ticks(level: Dictionary, taps: PackedInt32Array) -> Array[int]:
	var sim: FluxSim = FluxSim.new()
	sim.record_events = false
	sim.shields_allowed = false
	sim.setup(SimLevel.from_dict(level))
	var out: Array[int] = []
	while sim.is_running():
		var dash: bool = sim.form == SimConst.Form.DASH
		var before: int = sim.stack_crashes
		sim.step(taps.has(sim.tick))
		if dash and sim.stack_crashes > before:
			out.append(sim.tick)
	return out


func _too_close(taps: PackedInt32Array, tick: int) -> bool:
	for t: int in taps:
		if absi(t - tick) <= RunReplay.MIN_TAP_GAP_TICKS:
			return true
	return false


func _probe_until(level: Dictionary, taps: PackedInt32Array, extra: int, until: int) -> FluxSim:
	var sim: FluxSim = FluxSim.new()
	sim.record_events = false
	sim.shields_allowed = false
	sim.setup(SimLevel.from_dict(level))
	while sim.is_running() and sim.tick < until:
		sim.step(taps.has(sim.tick) or sim.tick == extra)
	return sim


func test_well_order_in_the_file_does_not_matter() -> void:
	# R-6: hand-made levels may list wells in any order.
	var level: Dictionary = LevelRepository.new().load_level("w09_l41").duplicate(true)
	assert_true(_validator().validate(level).ok(), "shipped order validates")
	(level["entities"] as Array).reverse()
	assert_true(_validator().validate(level).ok(), "reversed order validates too")
