extends TestCase
## The unlock-all test build: exported with the "unlock_all" feature tag from
## its own Android preset (own package, so it installs beside the real game),
## it opens every level, world, mode and cosmetic without touching the
## player's real progress. Normal builds stay locked.

const FIXED_UNIX: int = 1790000000
const PRESETS_PATH: String = "res://export_presets.cfg"
const UNLOCK_PRESET: String = "Android (Unlock All)"

var _app: AppServices
var _session: GameplaySession


func before_each() -> void:
	_app = AppServices.new()
	_app.auto_boot = false
	tree.root.add_child(_app)
	var clock: GameClock = GameClock.new()
	clock.set_fixed_unix(FIXED_UNIX)
	_app.boot(MemorySaveStorage.new(), clock)
	_session = GameplaySession.new()
	tree.root.add_child(_session)


func after_each() -> void:
	_session.queue_free()
	_app.queue_free()
	await wait_frames(2)


func _first_unowned_cosmetic() -> String:
	for it: Dictionary in _app.cosmetics.catalog.items:
		var id: String = str(it["id"])
		if not _app.cosmetics.owns(id):
			return id
	return ""


func test_normal_builds_stay_locked() -> void:
	assert_false(AppInfo.unlock_all_build(), "the editor and CI run without the feature tag")
	assert_false(_app.progression.is_level_unlocked("w05_l10"))
	assert_false(_app.progression.is_world_unlocked(str(_app.catalog.world_at(2)["id"])))
	assert_false(_app.modes.is_unlocked(&"boss_rush", _app.mode_progress()))
	assert_ne(_first_unowned_cosmetic(), "", "a fresh profile does not own every cosmetic")


func test_unlock_everything_opens_levels_worlds_modes_and_cosmetics() -> void:
	var item: String = _first_unowned_cosmetic()
	var owned_before: int = _app.cosmetics.owned_count()
	var stars_before: int = _app.progression.total_stars()
	var worlds_before: Array = _app.profile.unlocked_worlds.duplicate()
	_app.unlock_everything()
	for id: String in _app.levels.all_level_ids():
		assert_true(_app.progression.is_level_unlocked(id), "%s is open" % id)
	for wi: int in range(1, _app.catalog.world_count() + 1):
		assert_true(_app.progression.is_world_unlocked(str(_app.catalog.world_at(wi)["id"])))
	for m: Dictionary in _app.modes.modes:
		assert_true(_app.modes.is_unlocked(StringName(str(m["id"])), _app.mode_progress()), "mode %s" % m["id"])
	assert_eq(_first_unowned_cosmetic(), "", "every cosmetic can be worn")
	assert_true(_app.cosmetics.equip(item), "and equipped without buying it")
	var runs: RunController = RunController.new(_app, _session)
	assert_eq(runs.boss_rush_queue().size(), _app.catalog.world_count(), "boss rush has every boss")
	# Real progress is untouched: no fake ownership, stars or world records.
	assert_eq(_app.cosmetics.owned_count(), owned_before, "owned count stays real")
	assert_eq(_app.progression.total_stars(), stars_before)
	assert_eq(_app.profile.unlocked_worlds, worlds_before, "no world written into the save")


func test_the_unlock_all_preset_is_a_separate_app() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	assert_eq(cfg.load(PRESETS_PATH), OK)
	var main: String = ""
	var unlock: String = ""
	for section: String in cfg.get_sections():
		if section.ends_with(".options") or not section.begins_with("preset."):
			continue
		match str(cfg.get_value(section, "name", "")):
			"Android":
				main = section
			UNLOCK_PRESET:
				unlock = section
	assert_ne(unlock, "", "the unlock-all preset exists")
	assert_ne(main, "")
	assert_has(str(cfg.get_value(unlock, "custom_features", "")), AppInfo.UNLOCK_ALL_FEATURE)
	assert_eq(str(cfg.get_value(main, "custom_features", "")), "", "the real game has no such tag")
	var main_pkg: String = str(cfg.get_value(main + ".options", "package/unique_name", ""))
	var unlock_pkg: String = str(cfg.get_value(unlock + ".options", "package/unique_name", ""))
	assert_ne(unlock_pkg, main_pkg, "installs beside the real game, with its own save")
