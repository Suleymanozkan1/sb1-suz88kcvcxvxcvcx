class_name AsyncLoader
extends RefCounted
## Thin wrapper over ResourceLoader threaded loading with a result cache.
##
## Used to stream world music and heavy resources in the background so the
## next world/level never blocks the main thread.

var _requested: Dictionary = {}
var _cache: Dictionary = {}


func request(path: String) -> void:
	if _cache.has(path) or _requested.has(path):
		return
	if not ResourceLoader.exists(path):
		GameLog.warn("loader", "missing resource %s" % path)
		return
	var err: Error = ResourceLoader.load_threaded_request(path)
	if err == OK:
		_requested[path] = true
	else:
		GameLog.warn("loader", "threaded request failed for %s: %s" % [path, error_string(err)])


func is_ready(path: String) -> bool:
	if _cache.has(path):
		return true
	if not _requested.has(path):
		return false
	return ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED


## Returns the resource, blocking only if it is still loading.
func get_resource(path: String) -> Resource:
	if _cache.has(path):
		return _cache[path] as Resource
	var res: Resource = null
	if _requested.has(path):
		res = ResourceLoader.load_threaded_get(path)
		_requested.erase(path)
	elif ResourceLoader.exists(path):
		res = load(path)
	if res != null:
		_cache[path] = res
	return res


func evict(path: String) -> void:
	_cache.erase(path)


func cached_count() -> int:
	return _cache.size()
