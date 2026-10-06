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


func test_event_buffer_is_reused_between_frames() -> void:
	var sparks: Array = []
	for k: int in 30:
		sparks.append({"t": "spark", "d": 6.0 + float(k), "lane": 0})
	var sim: FluxSim = FluxSim.new(_level(sparks))
	var capacity: int = 0
	var seen: int = 0
	var guard: int = 0
	while sim.is_running() and guard < 10000:
		sim.step(false)
		if capacity == 0 and sim.event_len > 0:
			capacity = sim.events.size()
		for i: int in range(0, sim.event_len, 3):
			if sim.events[i] == SimConst.EventType.SPARK:
				seen += 1
		sim.clear_events()
		guard += 1
	assert_gt(float(capacity), 0.0, "the buffer is allocated at the first event")
	assert_eq(sim.events.size(), capacity, "clearing keeps the capacity: no allocation per tick")
	assert_eq(seen, 30, "every collect was delivered through the reused buffer")
	assert_eq(sim.recorded_events().size(), 0, "nothing left after the last clear")
