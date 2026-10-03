extends TestCase


func _level(entities: Array, extra: Dictionary = {}) -> SimLevel:
	var data: Dictionary = {"id": "t", "lanes": 2, "speed": 8.0, "length": 40.0, "entities": entities}
	data.merge(extra, true)
	return SimLevel.from_dict(data)


func test_runs_to_completion_without_input() -> void:
	var sim: FluxSim = FluxSim.new(_level([]))
	var guard: int = 0
	while sim.is_running() and guard < 10000:
		sim.step(false)
		guard += 1
	assert_eq(sim.status, SimConst.Status.COMPLETED)
	assert_near(sim.time(), 40.0 / 8.0, 0.05)


func test_barrier_kills_and_hop_avoids() -> void:
	var lvl: SimLevel = _level([{"t": "barrier", "d": 20.0, "lanes": [0]}])
	var sim: FluxSim = FluxSim.new(lvl)
	sim.advance_to_distance(100.0)
	assert_eq(sim.status, SimConst.Status.FAILED, "no tap should crash")
	sim.reset()
	sim.step(true)
	sim.advance_to_distance(100.0)
	assert_eq(sim.status, SimConst.Status.COMPLETED, "hop avoids barrier")
