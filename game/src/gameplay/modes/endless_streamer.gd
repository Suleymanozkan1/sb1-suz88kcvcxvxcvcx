class_name EndlessStreamer
extends RefCounted
## Streams an endless run from the deterministic [LevelGenerator].
##
## The stream depends only on the spec seed, never on the player's inputs, so a
## server can regenerate exactly the same course to verify a replay. Slots are
## built a few at a time (frame budget) and released to the running [SimLevel]
## once they are safely behind the planning frontier, which keeps entity order
## monotonic for the simulation's cursor.

const INITIAL_SLOTS: int = 14
const SLOTS_PER_STEP: int = 1
## Keep at least this much course ahead of the core.
const AHEAD_DISTANCE: float = 70.0
## Entities closer than this to the frontier are held back (the next slot may
## still place pickups around them).
const HOLD_BACK_SPACINGS: float = 2.5

var spec: LevelSpec
var failed: bool = false
var _gen: LevelGenerator = LevelGenerator.new()
var _released_flags: PackedByteArray = PackedByteArray()
var _scan_from: int = 0
var _last_d: float = -INF


func _init(stream_spec: LevelSpec) -> void:
	spec = stream_spec
	_gen.verify_with_validator = false


## Tap ticks of the generator's planned path (proves the stream is solvable).
func planned_taps() -> PackedInt32Array:
	return _gen.planned_taps()


## Builds the opening stretch and returns the level dictionary to load.
func begin() -> Dictionary:
	_gen.start(spec)
	_gen.build_slots(INITIAL_SLOTS)
	if not _gen.errors.is_empty():
		failed = true
		GameLog.warn("endless", "opening failed: %s" % ", ".join(_gen.errors))
	var data: Dictionary = _gen.stream_header()
	data["id"] = spec.id
	data["seed"] = spec.seed
	data["world"] = spec.world_id
	data["entities"] = _take_releasable()
	return data


## Extends the course when the core gets within [constant AHEAD_DISTANCE] of the
## planned frontier. Returns the newly appended entities (for the view).
func pump(sim: FluxSim) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if failed or sim == null:
		return added
	if _gen.frontier() - sim.d > AHEAD_DISTANCE:
		return added
	_gen.build_slots(SLOTS_PER_STEP)
	if not _gen.errors.is_empty():
		failed = true
		GameLog.warn("endless", "stream stopped: %s" % ", ".join(_gen.errors))
	added = _take_releasable()
	if not added.is_empty():
		sim.level.append_entities(added)
		sim.sync_entity_capacity()
	return added


## Generates the course up to [param distance] with no presentation (used by
## replay verification).
func extend_to(sim: FluxSim, distance: float) -> void:
	var guard: int = 0
	while not failed and _gen.frontier() < distance + AHEAD_DISTANCE and guard < 10000:
		pump_headless(sim)
		guard += 1


## The whole course up to [param distance] as one level dictionary, built with
## exactly the client's release sequence (begin, then one slot per pump), so a
## server re-simulation meets the same entities the player met.
func course_until(distance: float) -> Dictionary:
	var data: Dictionary = begin()
	var entities: Array = data["entities"] as Array
	var guard: int = 0
	while not failed and _gen.frontier() < distance + AHEAD_DISTANCE and guard < 100000:
		_gen.build_slots(SLOTS_PER_STEP)
		if not _gen.errors.is_empty():
			failed = true
		entities.append_array(_take_releasable())
		guard += 1
	return data


func pump_headless(sim: FluxSim) -> void:
	_gen.build_slots(SLOTS_PER_STEP)
	if not _gen.errors.is_empty():
		failed = true
	var added: Array[Dictionary] = _take_releasable()
	if not added.is_empty() and sim != null:
		sim.level.append_entities(added)
		sim.sync_entity_capacity()


func _take_releasable() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var all: Array[Dictionary] = _gen.committed_entities()
	var limit: float = INF if failed else _gen.frontier() - spec.spacing * HOLD_BACK_SPACINGS
	if _released_flags.size() < all.size():
		_released_flags.resize(all.size())
	var picked: Array[Dictionary] = []
	var first_open: int = -1
	for i: int in range(_scan_from, all.size()):
		if _released_flags[i] != 0:
			continue
		if float(all[i].get("d", 0.0)) < limit:
			_released_flags[i] = 1
			picked.append(all[i])
		elif first_open < 0:
			first_open = i
	_scan_from = all.size() if first_open < 0 else first_open
	picked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	for e: Dictionary in picked:
		var ed: float = float(e.get("d", 0.0))
		if ed < _last_d:
			# A pickup planned beside an already released slot: skipping it keeps
			# the simulation cursor monotonic (only sparks can land here).
			continue
		_last_d = ed
		out.append(e.duplicate(true))
	return out
