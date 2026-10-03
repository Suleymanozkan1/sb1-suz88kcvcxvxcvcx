extends TestCase
## SaveStorage implementations: in-memory and on-disk behaviour, atomic writes,
## temp-file hygiene and name safety.

var _dirs: PackedStringArray = PackedStringArray()


func after_each() -> void:
	for dir_path: String in _dirs:
		_remove_tree(dir_path)
	_dirs.clear()


func _unique_dir(tag: String) -> String:
	var path: String = "user://test_save_storage_%s_%d_%d" % [tag, Time.get_ticks_usec(), randi() % 1000000]
	_dirs.append(path)
	return path


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub: String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub))
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)


func _temp_files(path: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for file_name: String in DirAccess.get_files_at(path):
		if file_name.ends_with(SaveStorage.TEMP_SUFFIX):
			out.append(file_name)
	return out


func test_base_storage_reports_unavailable() -> void:
	var base: SaveStorage = SaveStorage.new()
	assert_eq(base.read_text("a.json"), "")
	assert_eq(base.write_text("a.json", "x"), ERR_UNAVAILABLE)
	assert_false(base.exists("a.json"))
	assert_eq(base.remove("a.json"), ERR_UNAVAILABLE)
	assert_eq(base.rename("a.json", "b.json"), ERR_UNAVAILABLE)
	assert_empty(base.list_names())


func test_memory_round_trip_and_listing() -> void:
	var storage: MemorySaveStorage = MemorySaveStorage.new()
	assert_eq(storage.write_text("b.json", "second"), OK)
	assert_eq(storage.write_text("a.json", "first"), OK)
	assert_eq(storage.read_text("a.json"), "first")
	assert_true(storage.exists("b.json"))
	assert_eq(storage.list_names(), PackedStringArray(["a.json", "b.json"]), "names are sorted")
	assert_eq(storage.write_text("a.json", "replaced"), OK)
	assert_eq(storage.read_text("a.json"), "replaced")
	assert_eq(storage.write_count, 3)


func test_memory_missing_entry_reads_empty() -> void:
	var storage: MemorySaveStorage = MemorySaveStorage.new()
	assert_eq(storage.read_text("nothing.json"), "")
	assert_false(storage.exists("nothing.json"))
	assert_eq(storage.remove("nothing.json"), ERR_FILE_NOT_FOUND)
	assert_eq(storage.rename("nothing.json", "other.json"), ERR_FILE_NOT_FOUND)


func test_memory_fail_writes_keeps_entries() -> void:
	var storage: MemorySaveStorage = MemorySaveStorage.new()
	storage.write_text("keep.json", "original")
	storage.fail_writes = true
	assert_ne(storage.write_text("keep.json", "lost"), OK)
	assert_ne(storage.remove("keep.json"), OK)
	assert_ne(storage.rename("keep.json", "moved.json"), OK)
	assert_eq(storage.read_text("keep.json"), "original")
	assert_false(storage.exists("moved.json"))
	assert_eq(storage.write_count, 1, "failed writes are not counted")


func test_memory_rename_replaces_target_and_remove_deletes() -> void:
	var storage: MemorySaveStorage = MemorySaveStorage.new()
	storage.write_text("from.json", "new")
	storage.write_text("to.json", "old")
	assert_eq(storage.rename("from.json", "to.json"), OK)
	assert_false(storage.exists("from.json"))
	assert_eq(storage.read_text("to.json"), "new")
	assert_eq(storage.rename("to.json", "to.json"), OK, "renaming onto itself is a no-op")
	assert_eq(storage.read_text("to.json"), "new")
	assert_eq(storage.remove("to.json"), OK)
	assert_empty(storage.list_names())


func test_memory_corrupt_bypasses_fail_writes() -> void:
	var storage: MemorySaveStorage = MemorySaveStorage.new()
	storage.fail_writes = true
	storage.corrupt("profile.json", "{broken")
	assert_eq(storage.read_text("profile.json"), "{broken")
	assert_eq(storage.write_count, 0)


func test_memory_rejects_unsafe_names() -> void:
	var storage: MemorySaveStorage = MemorySaveStorage.new()
	for bad: String in ["", "../escape.json", "dir/file.json", "c:\\x.json", ".hidden", "profile.json.tmp"]:
		assert_eq(storage.write_text(bad, "x"), ERR_INVALID_PARAMETER, "name '%s'" % bad)
	assert_eq(storage.write_text("a".repeat(SaveStorage.MAX_NAME_LENGTH + 1), "x"), ERR_INVALID_PARAMETER)
	assert_empty(storage.list_names())


func test_names_with_control_characters_are_rejected() -> void:
	var storage: MemorySaveStorage = MemorySaveStorage.new()
	var bad_names: Array[String] = [
		"line\nbreak.json", "tab\there.json", "carriage\r.json",
		"esc%s.json" % String.chr(0x1B), "del%s.json" % String.chr(SaveStorage.DELETE_CODE),
	]
	for bad: String in bad_names:
		assert_eq(storage.write_text(bad, "x"), ERR_INVALID_PARAMETER, "name %s" % bad.c_escape())
	assert_empty(storage.list_names())
	assert_eq(storage.write_text("profile ışık.json", "x"), OK, "printable non-ASCII names stay allowed")


func test_file_creates_nested_directory() -> void:
	var root: String = _unique_dir("nested")
	var dir_path: String = root.path_join("deeper/save")
	var storage: FileSaveStorage = FileSaveStorage.new(dir_path + "/")
	assert_true(DirAccess.dir_exists_absolute(dir_path))
	assert_eq(storage.write_text("profile.json", "{}"), OK)
	assert_true(FileAccess.file_exists(dir_path.path_join("profile.json")))


func test_file_write_read_overwrite_and_list() -> void:
	var dir_path: String = _unique_dir("rw")
	var storage: FileSaveStorage = FileSaveStorage.new(dir_path)
	var text: String = "{\"coins\": 12, \"name\": \"Çekirdek ışığı\"}"
	assert_eq(storage.write_text("profile.json", text), OK)
	assert_eq(storage.read_text("profile.json"), text, "UTF-8 text survives")
	assert_eq(storage.write_text("profile.json", "v2"), OK)
	assert_eq(storage.read_text("profile.json"), "v2")
	assert_eq(storage.write_text("a.json", "a"), OK)
	assert_eq(storage.list_names(), PackedStringArray(["a.json", "profile.json"]))
	assert_eq(storage.read_text("missing.json"), "")
	assert_false(storage.exists("missing.json"))


func test_file_write_leaves_no_temp_files() -> void:
	var dir_path: String = _unique_dir("tmp")
	var storage: FileSaveStorage = FileSaveStorage.new(dir_path)
	for i: int in 5:
		assert_eq(storage.write_text("profile.json", "generation %d" % i), OK)
	assert_empty(_temp_files(dir_path), "no temp files after successful writes")
	assert_eq(storage.read_text("profile.json"), "generation 4")


func test_file_rename_and_remove() -> void:
	var dir_path: String = _unique_dir("mv")
	var storage: FileSaveStorage = FileSaveStorage.new(dir_path)
	storage.write_text("a.json", "alpha")
	storage.write_text("b.json", "beta")
	assert_eq(storage.rename("a.json", "b.json"), OK, "rename replaces an existing target")
	assert_false(storage.exists("a.json"))
	assert_eq(storage.read_text("b.json"), "alpha")
	assert_eq(storage.rename("a.json", "c.json"), ERR_FILE_NOT_FOUND)
	assert_eq(storage.remove("b.json"), OK)
	assert_eq(storage.remove("b.json"), ERR_FILE_NOT_FOUND)
	assert_empty(storage.list_names())


func test_file_failed_write_keeps_previous_text_and_cleans_up() -> void:
	var dir_path: String = _unique_dir("fail")
	var storage: FileSaveStorage = FileSaveStorage.new(dir_path)
	assert_eq(storage.write_text("profile.json", "safe"), OK)
	# A directory squatting on the temp path makes the temp write impossible.
	DirAccess.make_dir_absolute(dir_path.path_join("profile.json.tmp"))
	assert_ne(storage.write_text("profile.json", "never written"), OK)
	assert_eq(storage.read_text("profile.json"), "safe", "previous text intact")
	DirAccess.remove_absolute(dir_path.path_join("profile.json.tmp"))
	# A directory squatting on the target makes the final rename impossible.
	DirAccess.make_dir_absolute(dir_path.path_join("blocked.json"))
	assert_ne(storage.write_text("blocked.json", "data"), OK)
	assert_empty(_temp_files(dir_path), "temp file removed after a failed rename")


func test_file_purges_stale_temp_on_startup() -> void:
	var dir_path: String = _unique_dir("stale")
	var first: FileSaveStorage = FileSaveStorage.new(dir_path)
	first.write_text("profile.json", "good")
	var stale: FileAccess = FileAccess.open(dir_path.path_join("profile.json.tmp"), FileAccess.WRITE)
	stale.store_string("{\"half\": ")
	stale.close()
	assert_eq(first.list_names(), PackedStringArray(["profile.json"]), "temp files are not listed")
	var second: FileSaveStorage = FileSaveStorage.new(dir_path)
	assert_empty(_temp_files(dir_path), "interrupted write purged")
	assert_eq(second.read_text("profile.json"), "good")


func test_file_oversized_entry_reads_as_unreadable() -> void:
	var dir_path: String = _unique_dir("big")
	var storage: FileSaveStorage = FileSaveStorage.new(dir_path)
	# Seeking past the end makes a sparse file, so the test stays fast and small on disk.
	var file: FileAccess = FileAccess.open(dir_path.path_join("profile.json"), FileAccess.WRITE)
	file.seek(FileSaveStorage.MAX_ENTRY_BYTES)
	file.store_8(0)
	file.close()
	assert_true(storage.exists("profile.json"))
	assert_eq(storage.read_text("profile.json"), "", "too large to load into memory")
	assert_eq(storage.write_text("small.json", "ok"), OK)
	assert_eq(storage.read_text("small.json"), "ok", "normal entries still read")


func test_file_rejects_unsafe_names() -> void:
	var dir_path: String = _unique_dir("names")
	var storage: FileSaveStorage = FileSaveStorage.new(dir_path)
	assert_eq(storage.write_text("../escape.json", "x"), ERR_INVALID_PARAMETER)
	assert_eq(storage.write_text("sub/inner.json", "x"), ERR_INVALID_PARAMETER)
	assert_eq(storage.write_text("x.tmp", "x"), ERR_INVALID_PARAMETER)
	assert_false(FileAccess.file_exists(dir_path.get_base_dir().path_join("escape.json")))
	assert_eq(storage.read_text("../escape.json"), "")
	assert_false(storage.exists("../escape.json"))
	assert_empty(storage.list_names())
