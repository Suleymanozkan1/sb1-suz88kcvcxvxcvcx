extends TestCase
## SaveService recovery: damaged main saves, backups, quarantine and
## newer-version files.

const NOW: int = 1790000000

var _clock: GameClock
var _storage: MemorySaveStorage
var _recovered: PackedStringArray = PackedStringArray()


func before_each() -> void:
	_clock = GameClock.new()
	_clock.set_fixed_unix(NOW)
	_storage = MemorySaveStorage.new()


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


## Leaves MAIN = coins 200 and BACKUP = coins 100.
func _save_two_generations() -> void:
	var writer: SaveService = SaveService.new(_storage, _clock)
	assert_eq(writer.save_profile(_profile(100)), OK)
	assert_eq(writer.save_profile(_profile(200)), OK)


func _main_envelope() -> Dictionary:
	return JSON.parse_string(_storage.read_text(SaveService.MAIN)) as Dictionary


func _assert_backup_used(label: String) -> void:
	var service: SaveService = _service()
	var p: PlayerProfile = service.load_profile()
	assert_eq(p.coins, 100, "%s: backup profile loaded" % label)
	assert_eq(service.last_load_source, SaveService.SOURCE_BACKUP, label)
	assert_eq(_recovered, PackedStringArray([SaveService.SOURCE_BACKUP]), "%s: recovered(backup)" % label)
	assert_true(service.last_errors.size() > 0, "%s: problem reported" % label)
	assert_true(service.dirty, "%s: repaired save pending" % label)


func test_garbage_main_falls_back_to_backup() -> void:
	_save_two_generations()
	_storage.corrupt(SaveService.MAIN, "%$#@! ÿþ binary-ish garbage ~~~")
	_assert_backup_used("garbage")


func test_truncated_main_falls_back_to_backup() -> void:
	_save_two_generations()
	var text: String = _storage.read_text(SaveService.MAIN)
	_storage.corrupt(SaveService.MAIN, text.substr(0, text.length() / 2))
	_assert_backup_used("truncated")


func test_wrong_checksum_falls_back_to_backup() -> void:
	_save_two_generations()
	var env: Dictionary = _main_envelope()
	env["checksum"] = "f".repeat(64)
	_storage.corrupt(SaveService.MAIN, JSON.stringify(env))
	_assert_backup_used("wrong checksum")


func test_wrong_format_falls_back_to_backup() -> void:
	_save_two_generations()
	var env: Dictionary = _main_envelope()
	env["format"] = "some-other-game"
	_storage.corrupt(SaveService.MAIN, JSON.stringify(env))
	_assert_backup_used("wrong format")


func test_tampered_coins_fall_back_to_backup() -> void:
	_save_two_generations()
	var env: Dictionary = _main_envelope()
	(env["payload"] as Dictionary)["coins"] = 999999
	_storage.corrupt(SaveService.MAIN, JSON.stringify(env))
	_assert_backup_used("coins edited")


func test_empty_main_file_falls_back_to_backup() -> void:
	_save_two_generations()
	_storage.corrupt(SaveService.MAIN, "")
	_assert_backup_used("zero-byte main")


func test_missing_main_uses_backup() -> void:
	_save_two_generations()
	_storage.remove(SaveService.MAIN)
	_assert_backup_used("missing main")


func test_both_corrupted_start_new_and_emit_recovered() -> void:
	_save_two_generations()
	_storage.corrupt(SaveService.MAIN, "{\"format\": \"fluxdrop-save\", \"payl")
	_storage.corrupt(SaveService.BACKUP, "not json")
	var service: SaveService = _service()
	var p: PlayerProfile = service.load_profile()
	assert_eq(p.coins, 0, "fresh profile")
	assert_eq(p.created_at, NOW)
	assert_eq(service.last_load_source, SaveService.SOURCE_NEW)
	assert_eq(_recovered, PackedStringArray([SaveService.SOURCE_NEW]))
	assert_eq(service.last_errors.size(), 2, "both slots reported")
	assert_true(service.dirty)


func test_damaged_main_is_quarantined_and_never_becomes_backup() -> void:
	_save_two_generations()
	var good_backup: String = _storage.read_text(SaveService.BACKUP)
	_storage.corrupt(SaveService.MAIN, "garbage")
	var service: SaveService = _service()
	var p: PlayerProfile = service.load_profile()
	assert_eq(_storage.read_text(SaveService.QUARANTINE), "garbage", "damaged file kept for diagnosis")
	assert_false(_storage.exists(SaveService.MAIN))
	p.coins = 150
	assert_eq(service.flush_if_dirty(p), OK)
	assert_eq(_storage.read_text(SaveService.BACKUP), good_backup, "good backup not replaced by damage")
	var reloaded: SaveService = _service()
	assert_eq(reloaded.load_profile().coins, 150)
	assert_eq(reloaded.last_load_source, SaveService.SOURCE_MAIN)


func test_main_damaged_after_load_is_not_copied_to_backup() -> void:
	_save_two_generations()
	var service: SaveService = _service()
	var p: PlayerProfile = service.load_profile()
	_storage.corrupt(SaveService.MAIN, "{truncated")
	var backup_before: String = _storage.read_text(SaveService.BACKUP)
	assert_eq(service.save_profile(p), OK)
	assert_eq(_storage.read_text(SaveService.BACKUP), backup_before)
	assert_eq(_storage.read_text(SaveService.QUARANTINE), "{truncated")


func test_main_damaged_between_saves_is_not_copied_to_backup() -> void:
	var service: SaveService = _service()
	assert_eq(service.save_profile(_profile(100)), OK)
	assert_eq(service.save_profile(_profile(200)), OK)
	var good_backup: String = _storage.read_text(SaveService.BACKUP)
	_storage.corrupt(SaveService.MAIN, "{\"format\": \"fluxdrop-save\", \"version\": 1, \"payload\": {}}")
	assert_eq(service.save_profile(_profile(300)), OK)
	assert_eq(_storage.read_text(SaveService.BACKUP), good_backup, "service re-verifies a changed main")
	assert_eq(_service().load_profile().coins, 300)


func test_future_main_is_preserved_and_backup_used() -> void:
	_save_two_generations()
	var future_text: String = SaveService.encode_payload(
		{"coins": 5000, "brand_new_system": {"x": 1}}, SaveService.CURRENT_VERSION + 1, NOW)
	_storage.corrupt(SaveService.MAIN, future_text)
	var service: SaveService = _service()
	var p: PlayerProfile = service.load_profile()
	assert_eq(p.coins, 100, "backup used")
	assert_eq(service.last_load_source, SaveService.SOURCE_BACKUP)
	assert_eq(_recovered, PackedStringArray([SaveService.SOURCE_BACKUP]))
	assert_eq(service.preserved_future, SaveService.FUTURE)
	assert_eq(_storage.read_text(SaveService.FUTURE), future_text, "newer save kept byte for byte")
	assert_false(_storage.exists(SaveService.QUARANTINE), "a newer save is not treated as damage")
	p.coins = 120
	assert_eq(service.save_profile(p), OK)
	assert_eq(service.save_profile(p), OK)
	assert_eq(_storage.read_text(SaveService.FUTURE), future_text, "still untouched after saving")
	assert_ne(_storage.read_text(SaveService.MAIN), future_text)
	assert_ne(_storage.read_text(SaveService.BACKUP), future_text)


func test_future_only_starts_new_and_keeps_file() -> void:
	var future_text: String = SaveService.encode_payload({"coins": 1}, SaveService.CURRENT_VERSION + 4, NOW)
	_storage.corrupt(SaveService.MAIN, future_text)
	var service: SaveService = _service()
	service.load_profile()
	assert_eq(service.last_load_source, SaveService.SOURCE_NEW)
	assert_eq(_recovered, PackedStringArray([SaveService.SOURCE_NEW]))
	assert_eq(_storage.read_text(SaveService.FUTURE), future_text)


func test_future_backup_is_preserved_too() -> void:
	var future_text: String = SaveService.encode_payload({"coins": 1}, SaveService.CURRENT_VERSION + 1, NOW)
	_storage.corrupt(SaveService.BACKUP, future_text)
	var service: SaveService = _service()
	service.load_profile()
	assert_eq(_storage.read_text(SaveService.FUTURE), future_text)
	assert_false(_storage.exists(SaveService.BACKUP))


func test_save_without_load_never_overwrites_future_main() -> void:
	var future_text: String = SaveService.encode_payload({"coins": 9}, SaveService.CURRENT_VERSION + 2, NOW)
	_storage.corrupt(SaveService.MAIN, future_text)
	var service: SaveService = _service()
	_storage.fail_writes = true
	assert_ne(service.save_profile(_profile(3)), OK, "cannot move it aside, so refuse to save")
	assert_eq(_storage.read_text(SaveService.MAIN), future_text)
	_storage.fail_writes = false
	assert_eq(service.save_profile(_profile(3)), OK)
	assert_eq(_storage.read_text(SaveService.FUTURE), future_text)
	assert_eq(service.load_profile().coins, 3)


func test_future_slots_do_not_overwrite_each_other() -> void:
	var older: String = SaveService.encode_payload({"coins": 1}, SaveService.CURRENT_VERSION + 1, NOW)
	var newer: String = SaveService.encode_payload({"coins": 2}, SaveService.CURRENT_VERSION + 2, NOW)
	_storage.corrupt(SaveService.FUTURE, older)
	_storage.corrupt(SaveService.MAIN, newer)
	var service: SaveService = _service()
	service.load_profile()
	var second_slot: String = SaveService.FUTURE_SLOT_PATTERN % 1
	assert_eq(service.preserved_future, second_slot)
	assert_eq(_storage.read_text(SaveService.FUTURE), older)
	assert_eq(_storage.read_text(second_slot), newer)
