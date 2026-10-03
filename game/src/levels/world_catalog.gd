class_name WorldCatalog
extends RefCounted
## Loads world definitions (data/worlds/*.json) and maps level numbers.

const INDEX_PATH: String = "res://data/worlds/index.json"

var worlds: Array[Dictionary] = []
var errors: PackedStringArray = PackedStringArray()
var _by_id: Dictionary = {}


static func load_default() -> WorldCatalog:
	var c: WorldCatalog = WorldCatalog.new()
	c.load_from(INDEX_PATH)
	return c


func load_from(index_path: String) -> void:
	worlds.clear()
	_by_id.clear()
	var index: Dictionary = JsonIO.read_dict(index_path)
	var base: String = index_path.get_base_dir()
	for entry: Variant in index.get("worlds", []) as Array:
		var e: Dictionary = entry as Dictionary
		var world: Dictionary = JsonIO.read_dict(base.path_join(str(e.get("file", ""))))
		if world.is_empty():
			errors.append("world file missing: %s" % str(e.get("file", "")))
			continue
		worlds.append(world)
		_by_id[str(world.get("id", ""))] = world
	if worlds.is_empty():
		errors.append("no worlds loaded from %s" % index_path)


func world_count() -> int:
	return worlds.size()


func world(id: String) -> Dictionary:
	return _by_id.get(id, {}) as Dictionary


func world_at(index_1: int) -> Dictionary:
	if index_1 < 1 or index_1 > worlds.size():
		return {}
	return worlds[index_1 - 1]


func levels_in(world_index_1: int) -> int:
	return int(world_at(world_index_1).get("levels", 0))


func total_levels() -> int:
	var total: int = 0
	for w: Dictionary in worlds:
		total += int(w.get("levels", 0))
	return total


## Global level number (1-based) for a world index and local index.
func global_number(world_index_1: int, local_index_1: int) -> int:
	var n: int = 0
	for i: int in range(1, world_index_1):
		n += levels_in(i)
	return n + local_index_1


## Returns {"world_index": int, "local_index": int} for a global number.
func locate(global_number_1: int) -> Dictionary:
	var remaining: int = global_number_1
	for i: int in range(1, worlds.size() + 1):
		var count: int = levels_in(i)
		if remaining <= count:
			return {"world_index": i, "local_index": remaining}
		remaining -= count
	return {}


static func level_id(world_index_1: int, local_index_1: int) -> String:
	return "w%02d_l%02d" % [world_index_1, local_index_1]


static func parse_level_id(id: String) -> Dictionary:
	if id.length() != 7 or not id.begins_with("w") or id.substr(3, 2) != "_l":
		return {}
	var w: String = id.substr(1, 2)
	var l: String = id.substr(5, 2)
	if not w.is_valid_int() or not l.is_valid_int():
		return {}
	return {"world_index": w.to_int(), "local_index": l.to_int()}
