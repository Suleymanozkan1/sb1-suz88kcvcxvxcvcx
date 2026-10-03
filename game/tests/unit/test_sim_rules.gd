extends TestCase
## Core simulation rules: movement, collisions, forms, scoring, combo, determinism.


func _level(entities: Array, extra: Dictionary = {}) -> SimLevel:
	var data: Dictionary = {"id": "t", "lanes": 2, "speed": 8.0, "length": 60.0, "entities": entities}
	data.merge(extra, true)
	return SimLevel.from_dict(data)


func _run(sim: FluxSim, taps: Array = []) -> FluxSim:
	var guard: int = 0
	while sim.is_running() and guard < 20000:
		sim.step(taps.has(sim.tick))
		guard += 1
	return sim


func test_hop_moves_between_lanes_smoothly() -> void:
	var sim: FluxSim = FluxSim.new(_level([]))
	var start_x: float = sim.x
	sim.step(true)
	assert_true(sim.is_hopping(), "hop in progress after tap")
	assert_true(sim.x != start_x or sim.hop_t > 0.0)
	for _i: int in 20:
		sim.step(false)
	assert_near(sim.x, SimConst.lane_x(1, 2), 0.0001, "arrives at lane 1")
	assert_false(sim.is_hopping())


func test_three_lane_ping_pong_direction() -> void:
	var sim: FluxSim = FluxSim.new(_level([], {"lanes": 3, "start_lane": 0}))
	var lanes_seen: Array[int] = []
	for _k: int in 4:
		sim.step(true)
		for _i: int in 15:
			sim.step(false)
		lanes_seen.append(sim.lane)
	assert_eq(lanes_seen, [1, 2, 1, 0] as Array[int], "ping-pong 0->1->2->1->0")


func test_phase_gate_requires_matching_phase() -> void:
	var gate: Array = [{"t": "phase_gate", "d": 20.0, "color": 1}]
	var fail: FluxSim = _run(FluxSim.new(_level(gate, {"start_form": "phase"})))
	assert_eq(fail.status, SimConst.Status.FAILED)
	assert_eq(fail.fail_reason, SimConst.FailReason.WRONG_PHASE)
	var ok: FluxSim = _run(FluxSim.new(_level(gate, {"start_form": "phase"})), [5])
	assert_eq(ok.status, SimConst.Status.COMPLETED)
	assert_eq(ok.gates, 1)


func test_dash_shatters_breakable_and_chains() -> void:
	var ents: Array = [
		{"t": "breakable", "d": 20.0, "lane": 0},
		{"t": "breakable", "d": 20.0, "lane": 1},
	]
	var no_dash: FluxSim = _run(FluxSim.new(_level(ents, {"start_form": "dash"})))
	assert_eq(no_dash.status, SimConst.Status.FAILED, "breakable blocks without dash")
	var sim: FluxSim = FluxSim.new(_level(ents, {"start_form": "dash"}))
	sim.advance_to_distance(18.6)
	sim.step(true)
	_run(sim)
	assert_eq(sim.status, SimConst.Status.COMPLETED, "dash breaks through")
	assert_eq(sim.shatters, 2, "neighbour shattered by chain reaction")
	assert_eq(sim.chain_links, 1)


func test_dash_cooldown_denies_spam() -> void:
	var sim: FluxSim = FluxSim.new(_level([], {"start_form": "dash"}))
	sim.step(true)
	var cooldown: float = sim.dash_cooldown
	sim.step(true)
	assert_gt(cooldown, 0.0)
	assert_lt(sim.dash_timer, SimConst.DASH_TIME, "second tap did not restart the dash")


func test_surge_changes_speed_with_momentum() -> void:
	var sim: FluxSim = FluxSim.new(_level([], {"start_form": "surge"}))
	for _i: int in 120:
		sim.step(false)
	var light_speed: float = sim.speed
	sim.step(true)
	sim.step(false)
	assert_lt(sim.speed, light_speed + 1.0, "speed does not jump instantly (momentum)")
	for _i: int in 180:
		sim.step(false)
	assert_gt(sim.speed, light_speed * 1.5, "heavy is much faster than light")


func test_spark_collection_combo_and_multiplier() -> void:
	var ents: Array = []
	for i: int in 7:
		ents.append({"t": "spark", "d": 10.0 + float(i) * 2.0, "lane": 0})
	var sim: FluxSim = _run(FluxSim.new(_level(ents)))
	assert_eq(sim.sparks, 7)
	assert_eq(sim.max_combo, 7)
	# Combo 1-4 at x1, combo 5-7 at x1.5 (no overdrive below MAX_CHARGES) + clear bonus.
	assert_eq(sim.score, 4 * 10 + 3 * 15 + SimConst.SCORE_CLEAR_BONUS)
	assert_true(sim.is_perfect())


func test_missed_spark_breaks_combo() -> void:
	var ents: Array = [
		{"t": "spark", "d": 10.0, "lane": 0},
		{"t": "spark", "d": 12.0, "lane": 1},
		{"t": "spark", "d": 14.0, "lane": 0},
	]
	var sim: FluxSim = _run(FluxSim.new(_level(ents)))
	assert_eq(sim.sparks, 2)
	assert_eq(sim.max_combo, 1, "combo broken by the missed spark")
	assert_false(sim.is_perfect())


func test_shield_absorbs_one_hit() -> void:
	var ents: Array = [{"t": "barrier", "d": 20.0, "lanes": [0]}, {"t": "barrier", "d": 40.0, "lanes": [0]}]
	var sim: FluxSim = _run(FluxSim.new(_level(ents, {"forgiving": true})))
	assert_eq(sim.status, SimConst.Status.FAILED, "second hit fails")
	assert_eq(sim.damage, 1)
	assert_gt(sim.d, 39.0)


func test_zen_never_fails() -> void:
	var sim: FluxSim = FluxSim.new(_level([{"t": "barrier", "d": 20.0, "lanes": [0]}]))
	sim.zen = true
	_run(sim)
	assert_eq(sim.status, SimConst.Status.COMPLETED)
	assert_eq(sim.damage, 1)


func test_slider_position_is_deterministic_polynomial() -> void:
	var lvl: SimLevel = _level([{"t": "slider", "d": 30.0, "from": 0, "to": 1, "period": 2.0, "offset": 0.0}])
	assert_near(lvl.slider_x(0, 0.0), SimConst.lane_x(0, 2), 0.0001)
	assert_near(lvl.slider_x(0, 1.0), SimConst.lane_x(1, 2), 0.0001)
	assert_near(lvl.slider_x(0, 2.0), SimConst.lane_x(0, 2), 0.0001)


func test_pulse_gate_open_closed_cycle() -> void:
	var lvl: SimLevel = _level(
		[{"t": "pulse_gate", "d": 30.0, "lanes": [0], "period": 1.0, "open": 0.5, "offset": 0.0}]
	)
	assert_false(lvl.pulse_closed(0, 0.1))
	assert_true(lvl.pulse_closed(0, 0.6))


func test_portal_teleports_and_current_pushes() -> void:
	var portal: FluxSim = _run(FluxSim.new(_level([{"t": "portal", "d": 20.0, "lane": 0, "to": 1}])))
	assert_eq(portal.portals_used, 1)
	assert_eq(portal.lane, 1)
	var current: FluxSim = _run(FluxSim.new(_level([{"t": "current", "d": 20.0, "lanes": [0], "to": 1}])))
	assert_eq(current.currents_ridden, 1)
	assert_eq(current.lane, 1)


func test_form_gate_switches_tap_meaning() -> void:
	var sim: FluxSim = FluxSim.new(_level([{"t": "form_gate", "d": 15.0, "form": "phase"}]))
	sim.advance_to_distance(16.0)
	assert_eq(sim.form, SimConst.Form.PHASE)
	var lane_before: int = sim.lane
	sim.step(true)
	assert_eq(sim.lane, lane_before, "tap no longer hops")
	assert_eq(sim.phase, 1, "tap toggles phase")


func test_overdrive_after_charges() -> void:
	var ents: Array = []
	for i: int in SimConst.MAX_CHARGES + 1:
		ents.append({"t": "spark", "d": 10.0 + float(i) * 1.5, "lane": 0})
	var sim: FluxSim = FluxSim.new(_level(ents))
	sim.advance_to_distance(10.0 + float(SimConst.MAX_CHARGES - 1) * 1.5 + 0.7)
	assert_eq(sim.overdrives, 1)
	assert_gt(sim.overdrive_timer, 0.0)


func test_determinism_identical_inputs_identical_state() -> void:
	var repo: LevelRepository = LevelRepository.new()
	var data: Dictionary = repo.load_level("w04_l30")
	var taps: PackedInt32Array = PackedInt32Array()
	for t: Variant in (data["solution"] as Dictionary)["taps"] as Array:
		taps.append(int(t))
	var a: FluxSim = FluxSim.new(SimLevel.from_dict(data))
	var b: FluxSim = FluxSim.new(SimLevel.from_dict(data))
	a.record_events = false
	b.record_events = false
	_run(a, Array(taps))
	_run(b, Array(taps))
	assert_eq(a.tick, b.tick)
	assert_eq(a.score, b.score)
	assert_eq(a.d, b.d)
	assert_eq(a.x, b.x)


func test_clone_is_independent() -> void:
	var sim: FluxSim = FluxSim.new(_level([{"t": "spark", "d": 10.0, "lane": 0}]))
	sim.advance_to_distance(5.0)
	var c: FluxSim = sim.clone()
	c.advance_to_distance(20.0)
	assert_eq(c.sparks, 1)
	assert_eq(sim.sparks, 0, "original untouched")
	assert_lt(sim.d, 6.0)


func test_run_result_stars_and_grades() -> void:
	assert_eq(RunResult.compute_stars(false, 999, 10, true), 0)
	assert_eq(RunResult.compute_stars(true, 5, 10, false), 1)
	assert_eq(RunResult.compute_stars(true, 10, 10, false), 2)
	assert_eq(RunResult.compute_stars(true, 50, 10, true), 3)
	assert_eq(RunResult.compute_grade(true, 3, true, true), RunResult.Grade.PERFECT)
	assert_eq(RunResult.compute_grade(true, 2, false, true), RunResult.Grade.GREAT)
	assert_eq(RunResult.compute_grade(true, 2, false, false), RunResult.Grade.GOOD)
	assert_eq(RunResult.compute_grade(true, 1, false, false), RunResult.Grade.NORMAL)
