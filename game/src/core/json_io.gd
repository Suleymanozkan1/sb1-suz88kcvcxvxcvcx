class_name JsonIO
extends RefCounted
## JSON file helpers with explicit error reporting (never crash on bad data).


## Reads and parses a JSON file. Returns null (and logs) on any failure.
static func read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		GameLog.warn("json", "missing file %s" % path)
		return null
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		GameLog.warn("json", "empty or unreadable file %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	var json: JSON = JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		GameLog.warn("json", "parse error %s:%d %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


static func read_dict(path: String) -> Dictionary:
	var data: Variant = read(path)
	if typeof(data) == TYPE_DICTIONARY:
		return data as Dictionary
	return {}


## Canonical, key-sorted JSON (stable output for hashing and diffing).
static func canonical(data: Variant, indent: String = "") -> String:
	return JSON.stringify(data, indent, true)


## Writes text atomically: temp file first, then rename over the target.
static func write_atomic(path: String, text: String) -> Error:
	var dir_path: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var mk: Error = DirAccess.make_dir_recursive_absolute(dir_path)
		if mk != OK:
			return mk
	var tmp_path: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var write_err: Error = file.get_error()
	file.close()
	if write_err != OK:
		return write_err
	if FileAccess.file_exists(path):
		var rm: Error = DirAccess.remove_absolute(path)
		if rm != OK:
			return rm
	return DirAccess.rename_absolute(tmp_path, path)


static func write_json(path: String, data: Variant, indent: String = "\t") -> Error:
	return write_atomic(path, canonical(data, indent) + "\n")
