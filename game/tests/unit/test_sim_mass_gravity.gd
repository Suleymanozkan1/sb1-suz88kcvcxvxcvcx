extends TestCase
## Mass & gravity family: gravity wells, launch pads and mass plates.

## A barrier this far after a pad (at 8 m/s) sits inside the measured air
## stretch of an unweighted launch in normal gravity.
const WALL_AFTER_PAD: float = 2.5


func _level(entities: Array, extra: Dictionary = {}) -> SimLevel:
	var data: Dictionary = {"id": "t", "lanes": 2, "speed": 8.0, "length": 40.0, "entities": entities}
	data.merge(extra, true)
	return SimLevel.from_dict(data)


func _run(sim: FluxSim, taps: Array = []) -> FluxSim:
	var guard: int = 0
	while sim.is_running() and guard < 20000:
		sim.step(taps.has(sim.tick))
		guard += 1
	return sim


func _has_event(sim: FluxSim, type: int) -> bool:
	for k: int in range(0, sim.event_len, 3):
		if sim.events[k] == type:
			return true
	return false


func _plates_then_pad(pad_d: float, wall: bool, extra_ents: Array = []) -> Array:
	var ents: Array = [
		{"t": "plate", "d": 4.0, "lane": 0},
		{"t": "plate", "d": 5.0, "lane": 0},
		{"t": "plate", "d": 6.0, "lane": 0},
		{"t": "launch_pad", "d": pad_d, "lane": 0},
	]
	if wall:
		ents.append({"t": "barrier", "d": pad_d + WALL_AFTER_PAD, "lanes": [0, 1]})
	ents.append_array(extra_ents)
	return ents


func test_gravity_well_scales_speed_and_restores_on_exit() -> void:
	var sim: FluxSim = FluxSim.new(_level([{"t": "gravity", "d": 10.0, "span": 10.0, "g": 1.4}]))
	sim.advance_to_distance(14.0)
	assert_near(sim.grav, 1.4, 0.0001, "inside the well")
	assert_near(sim.speed, 8.0 * SimConst.gravity_speed_factor(1.4), 0.01, "heavier gravity, faster fall")
	assert_true(_has_event(sim, SimConst.EventType.GRAVITY_ENTER), "entering is announced")
	sim.advance_to_distance(22.0)
	assert_near(sim.grav, 1.0, 0.0001, "normal gravity after the well")
	assert_near(sim.speed, 8.0, 0.01, "speed restored")
	assert_true(_has_event(sim, SimConst.EventType.GRAVITY_EXIT), "leaving is announced")


func test_newest_well_wins_and_sets_the_end() -> void:
	var ents: Array = [
		{"t": "gravity", "d": 5.0, "span": 20.0, "g": 1.4},
		{"t": "gravity", "d": 10.0, "span": 4.0, "g": 0.7},
	]
	var sim: FluxSim = FluxSim.new(_level(ents))
	sim.advance_to_distance(12.0)
	assert_near(sim.grav, 0.7, 0.0001, "the later well replaces the earlier one")
	sim.advance_to_distance(15.0)
	assert_near(sim.grav, 1.0, 0.0001, "and its end restores normal gravity")


func test_hop_time_is_fixed_when_the_hop_starts() -> void:
	var sim: FluxSim = FluxSim.new(_level([{"t": "gravity", "d": 5.0, "span": 3.0, "g": 1.4}]))
	sim.advance_to_distance(7.9)
	sim.step(true)
	var expected: float = sim.level.hop_time * SimConst.gravity_hop_factor(1.4)
	assert_near(sim.hop_duration, expected, 0.0001, "heavy gravity snaps the hop")
	sim.advance_to_distance(9.0)
	assert_near(sim.hop_duration, expected, 0.0001, "leaving the well mid-hop keeps the hop's time")
	assert_lt(SimConst.gravity_hop_factor(1.4), 1.0)
	assert_gt(SimConst.gravity_hop_factor(0.7), 1.0)


func test_pad_launches_only_a_grounded_core_in_its_lane() -> void:
	var on_lane: FluxSim = FluxSim.new(_level([{"t": "launch_pad", "d": 10.0, "lane": 0}]))
	on_lane.advance_to_distance(10.5)
	assert_true(on_lane.airborne, "in-lane core is launched")
	assert_eq(on_lane.launches, 1)
	var off_lane: FluxSim = FluxSim.new(_level([{"t": "launch_pad", "d": 10.0, "lane": 1}]))
	off_lane.advance_to_distance(10.5)
	assert_false(off_lane.airborne, "a pad in another lane does nothing")
	var double: FluxSim = FluxSim.new(
		_level([{"t": "launch_pad", "d": 10.0, "lane": 0}, {"t": "launch_pad", "d": 11.0, "lane": 0}])
	)
	double.advance_to_distance(11.5)
	assert_eq(double.launches, 1, "a pad under an airborne core does nothing")
	_run(on_lane)
	assert_false(on_lane.airborne, "the core lands")
	assert_near(on_lane.y, 0.0, 0.0001)
	assert_true(_has_event(on_lane, SimConst.EventType.LAND))


func test_launch_vaults_a_wall_and_scores() -> void:
	var ents: Array = [
		{"t": "launch_pad", "d": 10.0, "lane": 0},
		{"t": "barrier", "d": 10.0 + WALL_AFTER_PAD, "lanes": [0, 1]},
	]
	var sim: FluxSim = _run(FluxSim.new(_level(ents)))
	assert_eq(sim.status, SimConst.Status.COMPLETED, "the wall is cleared in the air")
	assert_eq(sim.vaults, 1)
	assert_true(_has_event(sim, SimConst.EventType.VAULT))
	var grounded: FluxSim = _run(FluxSim.new(_level([{"t": "barrier", "d": 12.5, "lanes": [0, 1]}])))
	assert_eq(grounded.status, SimConst.Status.FAILED, "the same wall without a pad blocks")


func test_every_ground_hazard_can_be_vaulted() -> void:
	var walls: Array = [
		{"t": "slider", "d": 12.5, "from": 0, "to": 1, "period": 2.0},
		{"t": "pulse_gate", "d": 12.5, "lanes": [0, 1], "period": 1.0, "open": 0.05},
		{"t": "breakable", "d": 12.5, "lane": 0},
	]
	for wall: Dictionary in walls:
		var sim: FluxSim = _run(FluxSim.new(_level([{"t": "launch_pad", "d": 10.0, "lane": 0}, wall])))
		assert_eq(sim.status, SimConst.Status.COMPLETED, "%s vaulted" % str(wall["t"]))


func test_phase_gates_still_apply_in_the_air() -> void:
	var ents: Array = [
		{"t": "launch_pad", "d": 10.0, "lane": 0},
		{"t": "phase_gate", "d": 12.5, "color": 1},
	]
	var sim: FluxSim = _run(FluxSim.new(_level(ents, {"start_form": "phase"})))
	assert_eq(sim.status, SimConst.Status.FAILED, "a gate spans the shaft")
	assert_eq(sim.fail_reason, SimConst.FailReason.WRONG_PHASE)


func test_landing_on_a_block_is_a_collision() -> void:
	var land_d: float = 10.0 + 8.0 * 2.0 * SimConst.LAUNCH_VY / SimConst.G0
	var ents: Array = [
		{"t": "launch_pad", "d": 10.0, "lane": 0},
		{"t": "barrier", "d": land_d, "lane": 0},
	]
	var sim: FluxSim = _run(FluxSim.new(_level(ents)))
	assert_eq(sim.status, SimConst.Status.FAILED, "coming down onto a block hits it")
	assert_eq(sim.fail_reason, SimConst.FailReason.COLLISION)


func test_a_tap_steers_the_core_in_the_air() -> void:
	var sim: FluxSim = FluxSim.new(_level([{"t": "launch_pad", "d": 10.0, "lane": 0}]))
	sim.advance_to_distance(11.0)
	assert_true(sim.airborne)
	sim.step(true)
	for _i: int in 20:
		sim.step(false)
	assert_eq(sim.lane, 1, "hop form steers while flying")


func test_currents_and_portals_pass_under_a_flying_core() -> void:
	var current: FluxSim = _run(
		FluxSim.new(
			_level([{"t": "launch_pad", "d": 10.0, "lane": 0}, {"t": "current", "d": 12.5, "lanes": [0], "to": 1}])
		)
	)
	assert_eq(current.currents_ridden, 0, "a floor current misses a flying core")
	assert_eq(current.lane, 0)
	var portal: FluxSim = _run(
		FluxSim.new(_level([{"t": "launch_pad", "d": 10.0, "lane": 0}, {"t": "portal", "d": 12.5, "lane": 0, "to": 1}]))
	)
	assert_eq(portal.portals_used, 0, "a portal mouth on the floor misses a flying core")
	var form: FluxSim = _run(
		FluxSim.new(_level([{"t": "launch_pad", "d": 10.0, "lane": 0}, {"t": "form_gate", "d": 12.5, "form": "phase"}]))
	)
	assert_eq(form.form, SimConst.Form.PHASE, "form gates span the shaft and still apply")


func test_pickups_need_a_low_core() -> void:
	var ents: Array = [
		{"t": "launch_pad", "d": 10.0, "lane": 0},
		{"t": "spark", "d": 12.5, "lane": 0},
		{"t": "shield", "d": 13.0, "lane": 0},
		{"t": "plate", "d": 13.5, "lane": 0},
	]
	var sim: FluxSim = _run(FluxSim.new(_level(ents)))
	assert_eq(sim.sparks, 0, "a spark under the arc is missed")
	assert_eq(sim.shields, 0, "a shield under the arc stays")
	assert_eq(sim.plates, 0, "a plate under the arc stays")
	var low: FluxSim = _run(FluxSim.new(_level([{"t": "spark", "d": 12.5, "lane": 0}])))
	assert_eq(low.sparks, 1, "the same spark on the floor is collected")


func test_plates_stack_to_three() -> void:
	var ents: Array = []
	for k: int in 5:
		ents.append({"t": "plate", "d": 4.0 + float(k), "lane": 0})
	var sim: FluxSim = _run(FluxSim.new(_level(ents)))
	assert_eq(sim.plates, SimConst.MAX_PLATES, "the stack is capped")
	assert_true(_has_event(sim, SimConst.EventType.PLATE_UP))


func test_a_full_stack_flies_only_in_low_gravity() -> void:
	var heavy: FluxSim = _run(FluxSim.new(_level(_plates_then_pad(10.0, true))))
	assert_eq(heavy.status, SimConst.Status.FAILED, "three plates are too heavy to clear a wall")
	var low_g: Array = _plates_then_pad(10.0, true, [{"t": "gravity", "d": 2.0, "span": 30.0, "g": 0.7}])
	var floaty: FluxSim = _run(FluxSim.new(_level(low_g)))
	assert_eq(floaty.status, SimConst.Status.COMPLETED, "low gravity carries a full stack over")
	assert_lt(SimConst.launch_speed(3), SimConst.launch_speed(0), "mass lowers the launch")


func test_a_full_stack_smashes_glass_and_chains() -> void:
	var ents: Array = [
		{"t": "plate", "d": 4.0, "lane": 0},
		{"t": "plate", "d": 5.0, "lane": 0},
		{"t": "plate", "d": 6.0, "lane": 0},
		{"t": "breakable", "d": 12.0, "lane": 0},
		{"t": "breakable", "d": 12.0, "lane": 1},
	]
	var sim: FluxSim = _run(FluxSim.new(_level(ents)))
	assert_eq(sim.status, SimConst.Status.COMPLETED, "stack crash")
	assert_eq(sim.stack_crashes, 1)
	assert_eq(sim.shatters, 2, "the crash sets off the chain")
	assert_eq(sim.plates, 0, "the stack is spent")
	assert_true(_has_event(sim, SimConst.EventType.STACK_CRASH))
	var short: Array = ents.duplicate()
	short.remove_at(0)
	var two: FluxSim = _run(FluxSim.new(_level(short)))
	assert_eq(two.status, SimConst.Status.FAILED, "two plates are not enough")


func test_a_shield_hit_drops_the_stack() -> void:
	var ents: Array = [
		{"t": "plate", "d": 4.0, "lane": 0},
		{"t": "plate", "d": 5.0, "lane": 0},
		{"t": "barrier", "d": 12.0, "lane": 0},
	]
	var sim: FluxSim = _run(FluxSim.new(_level(ents, {"forgiving": true})))
	assert_eq(sim.status, SimConst.Status.COMPLETED)
	assert_eq(sim.plates, 0, "the hit knocks the plates off")


func test_clone_and_reset_cover_the_new_state() -> void:
	var low_g: Array = [{"t": "gravity", "d": 2.0, "span": 30.0, "g": 0.7}]
	var sim: FluxSim = FluxSim.new(_level(_plates_then_pad(10.0, false, low_g)))
	sim.advance_to_distance(11.0)
	assert_true(sim.airborne)
	var c: FluxSim = sim.clone()
	for field: String in ["y", "prev_y", "vy", "airborne", "grav", "grav_end", "plates", "launches"]:
		assert_eq(c.get(field), sim.get(field), "clone keeps %s" % field)
	c.step(false)
	sim.step(false)
	assert_eq(c.y, sim.y, "clone flies identically")
	sim.reset()
	assert_false(sim.airborne)
	assert_eq(sim.plates, 0)
	assert_near(sim.grav, 1.0, 0.0001)
	assert_near(sim.y, 0.0, 0.0001)


func test_state_key_only_changes_with_the_new_state() -> void:
	var a: FluxSim = FluxSim.new(_level([]))
	var b: FluxSim = FluxSim.new(_level([]))
	b.y = 2.0
	b.vy = 3.0
	assert_eq(a.state_key(), b.state_key(), "grounded legacy states keep their key")
	b.plates = 1
	assert_ne(a.state_key(), b.state_key(), "a plate is a different state")
	var c: FluxSim = FluxSim.new(_level([]))
	c.grav = 0.7
	c.grav_end = 10.0
	assert_ne(a.state_key(), c.state_key(), "a gravity well is a different state")


func test_mass_and_gravity_runs_are_deterministic() -> void:
	var ents: Array = _plates_then_pad(10.0, false, [{"t": "gravity", "d": 2.0, "span": 30.0, "g": 0.7}])
	ents.append({"t": "breakable", "d": 20.0, "lane": 1})
	var first: FluxSim = _run(FluxSim.new(_level(ents)), [700, 900])
	var second: FluxSim = _run(FluxSim.new(_level(ents)), [700, 900])
	assert_eq(first.tick, second.tick)
	assert_eq(first.score, second.score)
	assert_eq(first.d, second.d)
	assert_eq(first.recorded_events(), second.recorded_events(), "same events tick for tick")
