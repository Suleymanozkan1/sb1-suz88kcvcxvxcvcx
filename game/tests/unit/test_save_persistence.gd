extends TestCase
## SaveService persistence paths: legacy migration through the service and the
## on-disk FileSaveStorage end to end (unique user:// directories, cleaned up).

const NOW: int = 1790000000

var _clock: GameClock
var _storage: MemorySaveStorage
var _recovered: PackedStringArray = PackedStringArray()
var _dirs: PackedStringArray = PackedStringArray()


func before_each() -> void:
	_clock = GameClock.new()
	_clock.set_fixed_unix(NOW)
	_storage = MemorySaveStorage.new()


func after_each() -> void:
	for dir_path: String in _dirs:
		_remove_tree(dir_path)
	_dirs.clear()


func _service(storage: SaveStorage = null) -> SaveService:
	var service: SaveService = SaveService.new(storage if storage != null else _storage, _clock)
	service.recovered.connect(_on_recovered)
	return service


func _on_recovered(source: String) -> void:
	_recovered.append(source)


func _profile(coins: int) -> PlayerProfile:
	var p: PlayerProfile = PlayerProfile.create_new(NOW - 1000)
	p.coins = coins
	p.levels = {"w01_l01": {"stars": 2, "best_score": coins * 10, "clears": 1}}
	return p


func _unique_dir(tag: String) -> String:
	var path: String = "user://test_save_persistence_%s_%d_%d" % [tag, Time.get_ticks_usec(), randi() % 1000000]
	_dirs.append(path)
	return path


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)


func test_migrates_enveloped_v0_save() -> void:
	var legacy: Dictionary = {
		"coins": 321,
		"stars": {"w01_l01": 3, "w01_l02": 1},
		"best": {"w01_l01": 5000, "w01_l02": 800, "w01_l03": 50},
	}
	_storage.corrupt(SaveService.MAIN, SaveService.encode_payload(legacy, 0, NOW - 100))
	var service: SaveService = _service()
	var p: PlayerProfile = service.load_profile()
	assert_eq(service.last_load_source, SaveService.SOURCE_MIGRATED)
	assert_empty(_recovered, "migration is not a recovery")
	assert_true(service.dirty, "migrated data must be rewritten")
	assert_eq(p.coins, 321)
	assert_eq(p.stars_for("w01_l01"), 3)
	assert_eq(p.level_result("w01_l01")["best_score"] as int, 5000)
	assert_eq(p.level_result("w01_l01")["clears"] as int, 1)
	assert_true(p.level_result("w01_l01")["perfect"] as bool)
	assert_eq(p.stars_for("w01_l03"), 0)
	assert_false(p.is_cleared("w01_l03"))
	assert_eq(p.created_at, NOW - 100, "creation time taken from the legacy save")
	assert_eq(p.install_id.length(), 32)


func test_migrates_bare_legacy_file_and_keeps_it_as_backup() -> void:
	var legacy_text: String = JSON.stringify({"coins": 77, "stars": {"w01_l01": 2}, "best": {"w01_l01": 999}})
	_storage.corrupt(SaveService.MAIN, legacy_text)
	var service: SaveService = _service()
	var p: PlayerProfile = service.load_profile()
	assert_eq(service.last_load_source, SaveService.SOURCE_MIGRATED)
	assert_eq(p.coins, 77)
	assert_eq(p.stars_for("w01_l01"), 2)
	assert_eq(p.created_at, NOW, "no timestamp in the legacy file, so now")
	assert_eq(service.flush_if_dirty(p), OK)
	var main: Dictionary = SaveService.decode(_storage.read_text(SaveService.MAIN))
	assert_true(main["ok"] as bool)
	assert_eq(main["version"], SaveService.CURRENT_VERSION, "rewritten in the current format")
	assert_eq(_storage.read_text(SaveService.BACKUP), legacy_text, "legacy file kept as the backup")
	var again: SaveService = _service()
	assert_eq(again.load_profile().coins, 77)
	assert_eq(again.last_load_source, SaveService.SOURCE_MAIN)


func test_file_storage_end_to_end_leaves_no_temp_files() -> void:
	var dir_path: String = _unique_dir("e2e")
	var service: SaveService = _service(FileSaveStorage.new(dir_path))
	var p: PlayerProfile = service.load_profile()
	for coins: int in [10, 20, 30]:
		p.coins = coins
		service.mark_dirty()
		assert_eq(service.flush_if_dirty(p), OK)
	var files: PackedStringArray = DirAccess.get_files_at(dir_path)
	for file_name: String in files:
		assert_false(file_name.ends_with(".tmp"), "leftover temp file %s" % file_name)
	assert_has(files, SaveService.MAIN)
	assert_has(files, SaveService.BACKUP)
	var reader: SaveService = _service(FileSaveStorage.new(dir_path))
	var loaded: PlayerProfile = reader.load_profile()
	assert_eq(loaded.coins, 30)
	assert_eq(loaded.install_id, p.install_id)
	assert_eq(reader.last_load_source, SaveService.SOURCE_MAIN)


func test_file_storage_recovers_from_truncated_main_on_disk() -> void:
	var dir_path: String = _unique_dir("trunc")
	var writer: SaveService = SaveService.new(FileSaveStorage.new(dir_path), _clock)
	writer.save_profile(_profile(100))
	writer.save_profile(_profile(200))
	var main_path: String = dir_path.path_join(SaveService.MAIN)
	var full: String = FileAccess.get_file_as_string(main_path)
	var file: FileAccess = FileAccess.open(main_path, FileAccess.WRITE)
	file.store_string(full.substr(0, full.length() / 3))
	file.close()
	var reader: SaveService = _service(FileSaveStorage.new(dir_path))
	assert_eq(reader.load_profile().coins, 100)
	assert_eq(reader.last_load_source, SaveService.SOURCE_BACKUP)
	assert_eq(_recovered, PackedStringArray([SaveService.SOURCE_BACKUP]))
	assert_true(FileAccess.file_exists(dir_path.path_join(SaveService.QUARANTINE)))
