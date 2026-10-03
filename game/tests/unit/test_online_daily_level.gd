extends TestCase
## Daily challenge level: date keys, deterministic generation, validation,
## weekday difficulty, configuration and strings.

const BASE_DATE: String = "2026-10-03"

var _profile: PlayerProfile
var _catalog: WorldCatalog


func before_each() -> void:
	_profile = PlayerProfile.new()
	_catalog = WorldCatalog.load_default()


func _service() -> DailyChallengeService:
	return DailyChallengeService.new(_profile, EventBus.new(), GameClock.new(), _catalog, Callable())


# --- dates ------------------------------------------------------------------------


func test_date_key_parsing_round_trips_and_rejects_garbage() -> void:
	for day: int in [0, 59, 365, 10957, 19723, 20729, 20730, 24000]:
		var key: String = GameClock.date_key_for_day(day)
		assert_eq(DailyChallengeService.day_for_date_key(key), day, "round trip %s" % key)
	for bad: String in ["", "2026-13-01", "2026-02-30", "2025-02-29", "26-10-03", "2026/10/03", "2026-1-03", "abcd-ef-gh",
		"1969-12-31", "2026-10-03x", "+026-10-03", "2026-11-+5", "2026-+1-05", "2026-10- 3", "2026-10-3 "]:
		assert_eq(DailyChallengeService.day_for_date_key(bad), -1, "rejects '%s'" % bad)
	# Non-canonical spellings must not create a second daily (level + board) for a day.
	assert_eq(DailyChallengeService.date_key_from_level_id("daily_2026-11-+5"), "")
	assert_empty(LeaderboardService.parse_board("daily:2026-11-+5"))
	var leap: int = DailyChallengeService.day_for_date_key("2024-02-29")
	assert_eq(leap, DailyChallengeService.day_for_date_key("2024-02-28") + 1, "leap day")


func test_weekday_monday_is_zero() -> void:
	assert_eq(DailyChallengeService.weekday_for_day(DailyChallengeService.day_for_date_key("2026-10-05")), 0, "Monday")
	assert_eq(DailyChallengeService.weekday_for_day(DailyChallengeService.day_for_date_key("2026-10-03")), 5, "Saturday")
	assert_eq(DailyChallengeService.weekday_for_day(DailyChallengeService.day_for_date_key("2026-10-04")), 6, "Sunday")


func test_level_id_helpers() -> void:
	var svc: DailyChallengeService = _service()
	assert_eq(svc.level_id_for(BASE_DATE), "daily_2026-10-03")
	assert_eq(DailyChallengeService.date_key_from_level_id("daily_2026-10-03"), BASE_DATE)
	assert_eq(DailyChallengeService.date_key_from_level_id("w01_l01"), "")
	assert_eq(DailyChallengeService.date_key_from_level_id("daily_2026-02-31"), "")


func test_seed_is_stable_hash_of_date() -> void:
	var svc: DailyChallengeService = _service()
	assert_eq(svc.seed_for(BASE_DATE), DetRng.hash_string("fluxdrop-daily-v1:" + BASE_DATE))
	assert_ne(svc.seed_for("2026-10-03"), svc.seed_for("2026-10-04"))


# --- level ------------------------------------------------------------------------


func test_spec_is_deterministic_and_daily_shaped() -> void:
	var a: LevelSpec = _service().spec_for(BASE_DATE)
	var other: DailyChallengeService = DailyChallengeService.new(
		PlayerProfile.new(), null, GameClock.new(), _catalog, Callable()
	)
	var b: LevelSpec = other.spec_for(BASE_DATE)
	assert_true(a != null and b != null, "specs built")
	assert_eq(a.id, "daily_" + BASE_DATE)
	assert_eq(a.kind, "daily")
	assert_eq(a.seed, _service().seed_for(BASE_DATE))
	assert_eq(a.unlock_requires, "")
	assert_eq(a.unlock_stars, 0)
	assert_false(a.tutorial)
	assert_false(a.forgiving)
	assert_ge(a.target_duration, 30.0)
	assert_le(a.target_duration, 45.0)
	assert_true(not _catalog.world(a.world_id).is_empty(), "world from catalog")
	assert_eq(a.world_id, b.world_id)
	assert_eq(a.speed, b.speed)
	assert_eq(a.slot_count, b.slot_count)
	assert_eq(JsonIO.canonical(a.forms), JsonIO.canonical(b.forms))


func test_spec_ignores_player_progress() -> void:
	var fresh: LevelSpec = _service().spec_for(BASE_DATE)
	_profile.levels["w05_l10"] = {"stars": 3, "best_score": 9999, "clears": 4}
	_profile.unlocked_worlds = ["neon_core", "crystal_valley", "molten_grid"]
	_profile.player_level = 40
	var veteran: LevelSpec = _service().spec_for(BASE_DATE)
	assert_eq(veteran.world_id, fresh.world_id)
	assert_eq(veteran.speed, fresh.speed)
	assert_eq(veteran.slot_count, fresh.slot_count)


func test_invalid_date_gives_no_level() -> void:
	var svc: DailyChallengeService = _service()
	assert_true(svc.spec_for("2026-02-30") == null, "no spec for invalid date")
	assert_empty(svc.level_for("not-a-date"), "no level for invalid date")


func test_weekday_difficulty_monday_easier_than_sunday() -> void:
	var svc: DailyChallengeService = _service()
	var monday_speed: float = 0.0
	var sunday_speed: float = 0.0
	var monday_window: float = 0.0
	var sunday_window: float = 0.0
	# Four Mondays (2026-10-05 + 7k) against the Sundays that follow them.
	var first_monday: int = DailyChallengeService.day_for_date_key("2026-10-05")
	for k: int in 4:
		var mon: LevelSpec = svc.spec_for(GameClock.date_key_for_day(first_monday + 7 * k))
		var sun: LevelSpec = svc.spec_for(GameClock.date_key_for_day(first_monday + 7 * k + 6))
		monday_speed += mon.speed
		sunday_speed += sun.speed
		monday_window += mon.min_window
		sunday_window += sun.min_window
		assert_lt(mon.target_duration, sun.target_duration, "Sunday runs longer")
	assert_lt(monday_speed, sunday_speed, "Monday slower than Sunday")
	assert_gt(monday_window, sunday_window, "Monday more forgiving timing windows")


func test_same_date_gives_identical_level_json() -> void:
	var a: Dictionary = _service().level_for(BASE_DATE)
	var other: DailyChallengeService = DailyChallengeService.new(
		PlayerProfile.new(), EventBus.new(), GameClock.new(), WorldCatalog.load_default(), Callable()
	)
	var b: Dictionary = other.level_for(BASE_DATE)
	assert_false(a.is_empty(), "level generated")
	assert_eq(JsonIO.canonical(a), JsonIO.canonical(b), "identical for everyone")
	assert_eq(str(a["id"]), "daily_" + BASE_DATE)
	assert_eq(str(a["kind"]), "daily")
	assert_eq(int(a["seed"]), _service().seed_for(BASE_DATE))
	var unlock: Dictionary = a["unlock"] as Dictionary
	assert_eq(str(unlock["requires_level"]), "")
	assert_eq(int(unlock["requires_stars"]), 0)


func test_level_cache_returns_copies() -> void:
	var svc: DailyChallengeService = _service()
	var a: Dictionary = svc.level_for(BASE_DATE)
	a["id"] = "tampered"
	(a["entities"] as Array).clear()
	var b: Dictionary = svc.level_for(BASE_DATE)
	assert_eq(str(b["id"]), "daily_" + BASE_DATE, "cache not mutated by callers")
	assert_gt((b["entities"] as Array).size(), 0)


func test_different_dates_give_different_levels() -> void:
	var svc: DailyChallengeService = _service()
	var a: Dictionary = svc.level_for("2026-10-03")
	var b: Dictionary = svc.level_for("2026-10-04")
	assert_false(a.is_empty() or b.is_empty(), "both generated")
	assert_ne(JsonIO.canonical(a["entities"]), JsonIO.canonical(b["entities"]))
	assert_ne(int(a["seed"]), int(b["seed"]))


func test_daily_levels_pass_validator() -> void:
	var svc: DailyChallengeService = _service()
	var validator: LevelValidator = LevelValidator.new()
	validator.check_assets = false
	for key: String in ["2026-10-05", "2026-10-07", "2026-10-09", "2026-10-11"]:
		var level: Dictionary = svc.level_for(key)
		assert_false(level.is_empty(), "%s generated" % key)
		if level.is_empty():
			continue
		var report: LevelValidator.Report = validator.validate(level)
		assert_true(report.ok(), "%s valid: %s" % [key, str(report.errors)])
		var duration: float = float(level["duration"])
		assert_ge(duration, 30.0, "%s at least 30 s" % key)
		assert_le(duration, 45.0, "%s at most 45 s" % key)
		assert_eq(str((level["daily"] as Dictionary)["date"]), key)


# --- data & strings ------------------------------------------------------------------


func test_config_weekday_table_complete() -> void:
	var cfg: Dictionary = DailyChallengeService.load_config()
	var rows: Array = (cfg["daily"] as Dictionary)["weekday_difficulty"] as Array
	assert_eq(rows.size(), 7)
	var last_pacing: int = 0
	for row: Variant in rows:
		var r: Dictionary = row as Dictionary
		var pacing: Array = r["pacing"] as Array
		assert_ge(int(pacing[0]), last_pacing, "pacing never gets easier through the week")
		last_pacing = int(pacing[0])
		var dur: float = float(r["duration"])
		assert_true(dur >= 30.0 and dur <= 45.0, "duration within 30-45 s")


func test_i18n_parts_match_and_cover_code_keys() -> void:
	var en: Dictionary = JsonIO.read_dict("res://data/i18n/parts/online.en.json")
	var tr: Dictionary = JsonIO.read_dict("res://data/i18n/parts/online.tr.json")
	assert_gt(en.size(), 30)
	assert_eq(en.size(), tr.size(), "same number of keys")
	for key: Variant in en:
		assert_true(str(key).begins_with("online."), "%s prefixed" % key)
		assert_true(tr.has(key), "tr has %s" % key)
		assert_false(str(tr.get(key, "")).is_empty(), "tr %s non-empty" % key)
		if str(en[key]).contains("{"):
			for token: String in ["{score}", "{count}", "{tier}", "{max}", "{rank}", "{total}", "{time}"]:
				assert_eq(str(en[key]).contains(token), str(tr[key]).contains(token), "%s keeps %s" % [key, token])
	var used: Array[String] = [
		"online.rank.first_daily", "online.rank.personal", "online.rank.personal_best", "online.lb.you",
		"online.lb.offline", "online.lb.local_only",
	]
	var cfg: Dictionary = DailyChallengeService.load_config()
	for row: Variant in (cfg["daily"] as Dictionary)["weekday_difficulty"] as Array:
		used.append(str((row as Dictionary)["label_key"]))
	for mode: Variant in cfg["modes"] as Dictionary:
		used.append("online.mode." + str(mode))
	for key: String in used:
		assert_true(en.has(key), "en defines %s" % key)
