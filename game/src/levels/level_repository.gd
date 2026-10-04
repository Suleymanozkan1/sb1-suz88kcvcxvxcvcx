class_name LevelRepository
extends RefCounted
## Loads campaign level data files (one JSON file per level) with an LRU cache.

const LEVEL_DIR: String = "res://data/levels"
const CACHE_SIZE: int = 8

var catalog: WorldCatalog
var level_dir: String = LEVEL_DIR
var _cache: Dictionary = {}
var _order: PackedStringArray = PackedStringArray()


func _init(world_catalog: WorldCatalog = null, dir: String = LEVEL_DIR) -> void:
	catalog = world_catalog if world_catalog != null else WorldCatalog.load_default()
	level_dir = dir


static func level_path(dir: String, world_index: int, local_index: int) -> String:
	return dir.path_join("w%02d" % world_index).path_join(WorldCatalog.level_id(world_index, local_index) + ".json")


## A designer-authored (or hand-edited) level: validated like every other level
## but never overwritten by the generator, and skipped by its `--check`.
static func is_handmade(level: Dictionary) -> bool:
	return bool(level.get("handmade", false))


func path_for(level_id: String) -> String:
	var parsed: Dictionary = WorldCatalog.parse_level_id(level_id)
	if parsed.is_empty():
		return ""
	return LevelRepository.level_path(level_dir, int(parsed["world_index"]), int(parsed["local_index"]))


func exists(level_id: String) -> bool:
	var p: String = path_for(level_id)
	return not p.is_empty() and FileAccess.file_exists(p)


## Returns the level dictionary, or an empty dictionary if missing/invalid.
func load_level(level_id: String) -> Dictionary:
	if _cache.has(level_id):
		_touch(level_id)
		return _cache[level_id] as Dictionary
	var p: String = path_for(level_id)
	if p.is_empty():
		GameLog.warn("levels", "invalid level id %s" % level_id)
		return {}
	var data: Dictionary = JsonIO.read_dict(p)
	if data.is_empty():
		return {}
	if str(data.get("id", "")) != level_id:
		GameLog.warn("levels", "level id mismatch in %s" % p)
		return {}
	_cache[level_id] = data
	_touch(level_id)
	return data


func level_id_for_number(number: int) -> String:
	var loc: Dictionary = catalog.locate(number)
	if loc.is_empty():
		return ""
	return WorldCatalog.level_id(int(loc["world_index"]), int(loc["local_index"]))


func next_level_id(level_id: String) -> String:
	var parsed: Dictionary = WorldCatalog.parse_level_id(level_id)
	if parsed.is_empty():
		return ""
	var n: int = catalog.global_number(int(parsed["world_index"]), int(parsed["local_index"]))
	if n >= catalog.total_levels():
		return ""
	return level_id_for_number(n + 1)


func all_level_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for n: int in range(1, catalog.total_levels() + 1):
		out.append(level_id_for_number(n))
	return out


func _touch(level_id: String) -> void:
	var idx: int = _order.find(level_id)
	if idx >= 0:
		_order.remove_at(idx)
	_order.append(level_id)
	while _order.size() > CACHE_SIZE:
		_cache.erase(_order[0])
		_order.remove_at(0)
