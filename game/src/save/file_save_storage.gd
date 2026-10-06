class_name FileSaveStorage
extends SaveStorage
## [SaveStorage] backed by one directory on disk (default [code]user://save[/code]).
##
## Writes go to "<name>.tmp" first and are renamed over the target only after
## the full text was stored, so a crash or a full disk mid-write can never
## leave a half-written entry. Temp files are deleted on every failure path,
## and stale ones from an interrupted previous session are purged on startup.

const DEFAULT_DIR: String = "user://save"
## Entries larger than this read as unreadable instead of being loaded into
## memory, so a runaway or hostile file cannot crash every launch; the caller
## then sets it aside like any other damaged entry.
const MAX_ENTRY_BYTES: int = 32 * 1024 * 1024

var _base_dir: String = DEFAULT_DIR


## Creates the storage directory (recursively) when it does not exist yet.
func _init(base_dir: String = DEFAULT_DIR) -> void:
	var cleaned: String = base_dir.strip_edges()
	while cleaned.length() > 1 and cleaned.ends_with("/") and not cleaned.ends_with("://"):
		cleaned = cleaned.substr(0, cleaned.length() - 1)
	_base_dir = cleaned if not cleaned.is_empty() else DEFAULT_DIR
	if _ensure_dir():
		_purge_stale_temp_files()


## Returns the entry's text, or "" when it is missing, unreadable or larger
## than [constant MAX_ENTRY_BYTES].
func read_text(entry_name: String) -> String:
	if not _is_valid_name(entry_name):
		return ""
	var path: String = _path(entry_name)
	if not _is_file(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		GameLog.warn("save", "cannot open %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return ""
	var length: int = file.get_length()
	if length > MAX_ENTRY_BYTES:
		file.close()
		GameLog.warn("save", "%s is too large to read (%d bytes)" % [path, length])
		return ""
	var text: String = file.get_buffer(length).get_string_from_utf8()
	file.close()
	return text


## Writes "<name>.tmp", then renames it over the entry (atomic replace).
func write_text(entry_name: String, text: String) -> Error:
	if not _is_valid_name(entry_name):
		return _reject_name(entry_name)
	if not _ensure_dir():
		return ERR_CANT_CREATE
	var path: String = _path(entry_name)
	var tmp_path: String = path + TEMP_SUFFIX
	var err: Error = _write_file(tmp_path, text)
	if err == OK:
		err = _replace(tmp_path, path)
	if err != OK:
		_discard_temp(tmp_path)
		GameLog.warn("save", "write %s failed: %s" % [path, error_string(err)])
	return err


## True when the entry exists.
func exists(entry_name: String) -> bool:
	return _is_valid_name(entry_name) and _is_file(_path(entry_name))


## Deletes the entry; [constant ERR_FILE_NOT_FOUND] when it is missing.
func remove(entry_name: String) -> Error:
	if not _is_valid_name(entry_name):
		return _reject_name(entry_name)
	var path: String = _path(entry_name)
	if not _is_file(path):
		return ERR_FILE_NOT_FOUND
	return DirAccess.remove_absolute(path)


## Renames an entry, replacing any existing entry with the target name.
func rename(from_name: String, to_name: String) -> Error:
	if not _is_valid_name(from_name):
		return _reject_name(from_name)
	if not _is_valid_name(to_name):
		return _reject_name(to_name)
	var from_path: String = _path(from_name)
	if not _is_file(from_path):
		return ERR_FILE_NOT_FOUND
	if from_name == to_name:
		return OK
	return _replace(from_path, _path(to_name))


## Sorted names of the stored entries.
func list_names() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if not DirAccess.dir_exists_absolute(_base_dir):
		return out
	for file_name: String in DirAccess.get_files_at(_base_dir):
		if not file_name.ends_with(TEMP_SUFFIX):
			out.append(file_name)
	out.sort()
	return out


func _path(entry_name: String) -> String:
	return _base_dir.path_join(entry_name)


func _is_file(path: String) -> bool:
	return FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path)


func _ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(_base_dir):
		return true
	var err: Error = DirAccess.make_dir_recursive_absolute(_base_dir)
	if err != OK:
		GameLog.error("save", "cannot create save directory %s: %s" % [_base_dir, error_string(err)])
		return false
	return true


func _write_file(path: String, text: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var open_err: Error = FileAccess.get_open_error()
		return open_err if open_err != OK else ERR_CANT_OPEN
	var stored: bool = file.store_string(text)
	file.flush()
	var err: Error = file.get_error()
	file.close()
	if not stored and err == OK:
		err = ERR_FILE_CANT_WRITE
	return err


## Moves [param from_path] over [param to_path]. POSIX rename replaces the
## target atomically; platforms that refuse to overwrite get remove + rename.
func _replace(from_path: String, to_path: String) -> Error:
	var err: Error = DirAccess.rename_absolute(from_path, to_path)
	if err != OK and _is_file(to_path):
		var rm: Error = DirAccess.remove_absolute(to_path)
		if rm != OK:
			return rm
		err = DirAccess.rename_absolute(from_path, to_path)
	return err


func _discard_temp(tmp_path: String) -> void:
	if _is_file(tmp_path):
		var err: Error = DirAccess.remove_absolute(tmp_path)
		if err != OK:
			GameLog.warn("save", "could not delete temp file %s: %s" % [tmp_path, error_string(err)])


func _purge_stale_temp_files() -> void:
	for file_name: String in DirAccess.get_files_at(_base_dir):
		if file_name.ends_with(TEMP_SUFFIX):
			GameLog.info("save", "removing interrupted write %s" % file_name)
			_discard_temp(_base_dir.path_join(file_name))
