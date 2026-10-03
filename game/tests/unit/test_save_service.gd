extends TestCase
## SaveService: envelope encoding, round trips, debounced flushing, signals,
## sanitising of hostile payloads and the save module's translations.

const NOW: int = 1790000000
const I18N_DIR: String = "res://data/i18n/parts"

var _clock: GameClock
var _storage: MemorySaveStorage
var _service: SaveService
var _recovered: PackedStringArray = PackedStringArray()
var _saved_bytes: Array[int] = []


func before_each() -> void:
	_clock = GameClock.new()
	_clock.set_fixed_unix(NOW)
	_storage = MemorySaveStorage.new()
	_service = _make_service(_storage)


func _make_service(storage: SaveStorage) -> SaveService:
	var service: SaveService = SaveService.new(storage, _clock)
	service.recovered.connect(_on_recovered)
	service.saved.connect(_on_saved)
	return service


func _on_recovered(source: String) -> void:
	_recovered.append(source)


func _on_saved(bytes: int) -> void:
	_saved_bytes.append(bytes)


## Canonical text of a value in its parsed-JSON form (numbers compared by value).
func _norm(value: Variant) -> String:
	return JsonIO.canonical(JSON.parse_string(JsonIO.canonical(value)))


func _rich_profile() -> PlayerProfile:
	var p: PlayerProfile = PlayerProfile.create_new(NOW - 5000)
	p.coins = 1234
	p.gems = 56
	p.xp = 7890
	p.player_level = 12
	p.levels = {
		"w01_l01": {
			"stars": 3, "best_score": 4200, "perfect": true, "clears": 5,
			"attempts": 9, "best_combo": 31, "best_time": 41.25,
		},
		"w02_l07": {
			"stars": 1, "best_score": 120, "perfect": false, "clears": 1,
			"attempts": 4, "best_combo": 3, "best_time": 63.0,
		},
	}
	p.unlocked_worlds = ["neon_core", "crystal_valley"]
	p.stats = {"runs": 77, "taps": 9001}
	p.cosmetics_owned = ["trail_comet", "core_prism"]
	p.cosmetics_equipped = {"trail": "trail_comet", "core": "core_prism"}
	p.achievements = {"first_clear": NOW - 4000}
	p.missions = {
		"daily": {"date": "2026-09-21", "slots": [{"id": "m_taps", "progress": 3, "target": 50, "claimed": false}]},
		"weekly": {"week": "2026-W39", "slots": []},
	}
	p.daily = {"last_key": "2026-09-21", "best": 880, "streak": 2}
	p.settings["sfx_volume"] = 0.35
	p.settings["music_volume"] = 0.6
	p.settings["language"] = "tr"
	p.settings["haptics"] = false
	p.settings["quality"] = "low"
	p.purchases = ["supporter_pack"]
	p.pending_submissions = [{"board": "w01_l01", "score": 4200, "at": NOW - 100}]
	p.flags = {"tutorial_done": true, "rated": false}
	p.ledger = [{"currency": "coins", "delta": 50, "reason": "level_clear", "at": NOW - 10}]
	return p


func test_round_trip_preserves_every_profile_field() -> void:
	var original: PlayerProfile = _rich_profile()
	assert_eq(_service.save_profile(original), OK)
	var loaded: PlayerProfile = _make_service(_storage).load_profile()
	var want: Dictionary = original.to_dict()
	var got: Dictionary = loaded.to_dict()
	assert_eq(got.keys().size(), want.keys().size())
	for key: String in want:
		assert_eq(_norm(got.get(key)), _norm(want[key]), "field %s" % key)
	assert_eq(loaded.install_id, original.install_id)
	assert_eq(loaded.created_at, NOW - 5000)
	assert_eq(loaded.total_stars(), 4)
	assert_empty(_recovered)


func test_round_trip_keeps_value_types() -> void:
	_service.save_profile(_rich_profile())
	var loaded: PlayerProfile = _make_service(_storage).load_profile()
	var slot: Dictionary = (((loaded.missions["daily"] as Dictionary)["slots"] as Array)[0]) as Dictionary
	assert_eq(typeof(slot["progress"]), TYPE_INT, "whole numbers come back as ints")
	assert_eq(typeof(slot["claimed"]), TYPE_BOOL)
	assert_eq(typeof(loaded.settings["sfx_volume"]), TYPE_FLOAT)
	assert_near(loaded.settings["sfx_volume"] as float, 0.35, 0.000001)
	assert_eq(typeof(loaded.settings["music"]), TYPE_BOOL)
	var level: Dictionary = loaded.level_result("w02_l07")
	assert_eq(typeof(level["best_time"]), TYPE_FLOAT, "integral float stays float in the profile")
	assert_eq(typeof(loaded.pending_submissions[0]["score"]), TYPE_INT)


func test_encode_produces_checksummed_envelope() -> void:
	var text: String = SaveService.encode(_rich_profile(), NOW)
	var env: Dictionary = JSON.parse_string(text) as Dictionary
	assert_eq(env["format"], SaveService.FORMAT)
	assert_eq(env["version"], PlayerProfile.SCHEMA_VERSION)
	assert_eq(env["saved_at"], NOW)
	var checksum: String = str(env["checksum"])
	assert_eq(checksum.length(), 64)
	assert_true(checksum.is_valid_hex_number(), "hex digest")
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((JsonIO.canonical(env["payload"]) + SaveService.CHECKSUM_SALT).to_utf8_buffer())
	assert_eq(checksum, ctx.finish().hex_encode(), "sha256(canonical(payload) + salt)")
	assert_eq(SaveService.encode(null, NOW), "")


func test_decode_accepts_valid_envelope() -> void:
	var result: Dictionary = SaveService.decode(SaveService.encode(_rich_profile(), NOW))
	assert_true(result["ok"] as bool, str(result["error"]))
	assert_eq(result["version"], PlayerProfile.SCHEMA_VERSION)
	assert_eq(result["error"], "")
	assert_eq((result["payload"] as Dictionary)["coins"], 1234)


func test_decode_rejects_damaged_inputs() -> void:
	var good: Dictionary = JSON.parse_string(SaveService.encode(_rich_profile(), NOW)) as Dictionary
	var cases: Dictionary = {
		"empty": "",
		"blank": "   \n",
		"garbage": "%$#@! not a save ~~~",
		"truncated": JSON.stringify(good).substr(0, 40),
		"array root": "[1, 2, 3]",
		"bare object": "{\"hello\": \"world\"}",
	}
	var variants: Dictionary = {
		"wrong format": {"format": "another-game"},
		"missing format": {"format": null},
		"bad version": {"version": "one"},
		"negative version": {"version": -2},
		"fractional version": {"version": 0.5},
		"missing payload": {"payload": "nope"},
		"wrong checksum": {"checksum": "0".repeat(64)},
	}
	for label: String in variants:
		var env: Dictionary = good.duplicate(true)
		env.merge(variants[label] as Dictionary, true)
		cases[label] = JSON.stringify(env)
	for label: String in cases:
		var result: Dictionary = SaveService.decode(str(cases[label]))
		assert_false(result["ok"] as bool, "%s must be rejected" % label)
		assert_ne(str(result["error"]), "", "%s has an error message" % label)
		assert_empty(result["payload"], "%s exposes no payload" % label)


func test_decode_reports_future_version_separately() -> void:
	var text: String = SaveService.encode_payload({"coins": 1}, SaveService.CURRENT_VERSION + 3, NOW)
	var result: Dictionary = SaveService.decode(text)
	assert_false(result["ok"] as bool)
	assert_eq(result["version"], SaveService.CURRENT_VERSION + 3)
	assert_has(str(result["error"]), "newer")


func test_empty_storage_starts_new_without_recovered() -> void:
	var profile: PlayerProfile = _service.load_profile()
	assert_true(profile != null)
	assert_eq(_service.last_load_source, SaveService.SOURCE_NEW)
	assert_empty(_recovered, "nothing was lost, so no recovery notice")
	assert_empty(_service.last_errors)
	assert_eq(profile.created_at, NOW)
	assert_eq(profile.coins, 0)
	assert_eq(profile.install_id.length(), 32)
	assert_true(_service.dirty, "a brand-new profile still has to be written")


func test_clean_load_reports_main_and_is_not_dirty() -> void:
	_service.save_profile(_rich_profile())
	var service: SaveService = _make_service(_storage)
	service.load_profile()
	assert_eq(service.last_load_source, SaveService.SOURCE_MAIN)
	assert_false(service.dirty)
	assert_empty(service.last_errors)
	assert_eq(service.preserved_future, "")


func test_saved_signal_reports_written_bytes() -> void:
	assert_eq(_service.save_profile(_rich_profile()), OK)
	assert_eq(_saved_bytes.size(), 1)
	assert_eq(_saved_bytes[0], _storage.read_text(SaveService.MAIN).to_utf8_buffer().size())
	assert_gt(_saved_bytes[0], 0)


func test_second_save_keeps_previous_main_as_backup() -> void:
	var p: PlayerProfile = _rich_profile()
	_service.save_profile(p)
	var first: String = _storage.read_text(SaveService.MAIN)
	assert_false(_storage.exists(SaveService.BACKUP), "first save has nothing to back up")
	p.coins = 99
	_service.save_profile(p)
	assert_eq(_storage.read_text(SaveService.BACKUP), first)
	var main: Dictionary = SaveService.decode(_storage.read_text(SaveService.MAIN))
	assert_eq((main["payload"] as Dictionary)["coins"], 99)


func test_failing_writes_return_error_and_keep_previous_file() -> void:
	var p: PlayerProfile = _rich_profile()
	assert_eq(_service.save_profile(p), OK)
	var before: String = _storage.read_text(SaveService.MAIN)
	_storage.fail_writes = true
	p.coins = 5
	var err: Error = _service.save_profile(p)
	assert_ne(err, OK)
	assert_true(_service.dirty, "unsaved changes stay pending")
	assert_eq(_storage.read_text(SaveService.MAIN), before, "previous valid file untouched")
	assert_eq(_saved_bytes.size(), 1, "no saved signal for the failed write")
	assert_true(_service.last_errors.size() > 0)
	_storage.fail_writes = false
	var loaded: PlayerProfile = _make_service(_storage).load_profile()
	assert_eq(loaded.coins, 1234, "the last good save loads")


func test_flush_if_dirty_writes_only_when_dirty() -> void:
	var p: PlayerProfile = _rich_profile()
	assert_false(_service.dirty)
	assert_eq(_service.flush_if_dirty(p), OK)
	assert_eq(_storage.write_count, 0, "clean profile is not written")
	for i: int in 10:
		_service.mark_dirty()
	assert_eq(_service.flush_if_dirty(p), OK)
	assert_eq(_storage.write_count, 1, "many changes coalesce into one write")
	assert_false(_service.dirty)
	assert_eq(_service.flush_if_dirty(p), OK)
	assert_eq(_storage.write_count, 1)


func test_flush_retries_after_failure() -> void:
	var p: PlayerProfile = _rich_profile()
	_service.mark_dirty()
	_storage.fail_writes = true
	assert_ne(_service.flush_if_dirty(p), OK)
	assert_true(_service.dirty)
	_storage.fail_writes = false
	assert_eq(_service.flush_if_dirty(p), OK)
	assert_false(_service.dirty)
	assert_true(_storage.exists(SaveService.MAIN))


func test_hostile_payload_values_are_sanitized() -> void:
	var payload: Dictionary = {
		"install_id": "../../etc",
		"coins": -5,
		"gems": "lots",
		"xp": -100,
		"player_level": -3,
		"levels": {"w01_l01": {"stars": 9, "best_score": -10, "clears": -1}, "w01_l02": "broken"},
		"unlocked_worlds": ["crystal_valley"],
		"stats": {"runs": -4, "taps": "many"},
		"settings": {"sfx_volume": "loud", "music": 0, "language": 42},
		"pending_submissions": [1, "x", {"board": "ok"}],
		"ledger": "nope",
	}
	_storage.corrupt(SaveService.MAIN, SaveService.encode_payload(payload, SaveService.CURRENT_VERSION, NOW))
	var p: PlayerProfile = _service.load_profile()
	assert_eq(_service.last_load_source, SaveService.SOURCE_MAIN, "checksum valid, so the values get sanitised")
	assert_eq(p.coins, 0, "coins -5 -> 0")
	assert_eq(p.gems, 0)
	assert_eq(p.xp, 0)
	assert_eq(p.player_level, 1)
	assert_eq(p.stars_for("w01_l01"), 3, "stars clamped")
	assert_eq(p.level_result("w01_l01")["best_score"] as int, 0)
	assert_false(p.levels.has("w01_l02"))
	assert_eq(p.unlocked_worlds[0], "neon_core", "first world always unlocked")
	assert_eq(p.stat("runs"), 0)
	assert_false(p.stats.has("taps"))
	assert_eq(p.settings["sfx_volume"], PlayerProfile.DEFAULT_SETTINGS["sfx_volume"])
	assert_eq(p.settings["music"], true)
	assert_eq(p.settings["language"], "auto")
	assert_eq(p.pending_submissions.size(), 1)
	assert_empty(p.ledger)
	assert_eq(p.install_id.length(), 32)
	assert_true(p.install_id.is_valid_hex_number())


func test_non_finite_numbers_are_saved_safely() -> void:
	var p: PlayerProfile = _rich_profile()
	p.settings["sfx_volume"] = NAN
	(p.levels["w01_l01"] as Dictionary)["best_time"] = INF
	p.flags["weird"] = Vector2(1, 2)
	var text: String = SaveService.encode(p, NOW)
	assert_false(text.contains("nan"), "no NaN literal in JSON")
	assert_false(text.contains("e99999"), "no infinity literal in JSON")
	assert_eq(_service.save_profile(p), OK)
	var reader: SaveService = _make_service(_storage)
	var loaded: PlayerProfile = reader.load_profile()
	assert_eq(reader.last_load_source, SaveService.SOURCE_MAIN)
	assert_empty(reader.last_errors)
	assert_near(loaded.settings["sfx_volume"] as float, 0.0, 0.0001)
	assert_near(loaded.level_result("w01_l01")["best_time"] as float, 0.0, 0.0001)
	assert_eq(loaded.flags["weird"], "(1.0, 2.0)")


func test_missing_dependencies_fall_back_to_memory() -> void:
	var service: SaveService = SaveService.new(null, null)
	var p: PlayerProfile = service.load_profile()
	assert_eq(service.last_load_source, SaveService.SOURCE_NEW)
	assert_eq(service.save_profile(p), OK)
	assert_eq(service.save_profile(null), ERR_INVALID_PARAMETER)
	assert_eq(service.load_profile().install_id, p.install_id, "memory storage still round-trips")


func test_recovery_text_keys_exist_in_both_languages() -> void:
	var en: Dictionary = JsonIO.read_dict(I18N_DIR.path_join("save.en.json"))
	var tr_text: Dictionary = JsonIO.read_dict(I18N_DIR.path_join("save.tr.json"))
	assert_false(en.is_empty(), "English strings load")
	var en_keys: Array = en.keys()
	var tr_keys: Array = tr_text.keys()
	en_keys.sort()
	tr_keys.sort()
	assert_eq(en_keys, tr_keys, "same keys in both languages")
	var needed: Array = SaveService.RECOVERY_TEXT_KEYS.values()
	needed.append(SaveService.FUTURE_TEXT_KEY)
	needed.append(SaveService.WRITE_FAILED_TEXT_KEY)
	for key: Variant in needed:
		assert_has(en, key)
		assert_has(tr_text, key)
	for key: String in en:
		assert_true(key.begins_with("save."), "%s is prefixed" % key)
		assert_ne(str(en[key]).strip_edges(), "", "%s has English text" % key)
		assert_ne(str(tr_text.get(key, "")).strip_edges(), "", "%s has Turkish text" % key)
		assert_ne(str(tr_text.get(key, "")), str(en[key]), "%s is translated" % key)
