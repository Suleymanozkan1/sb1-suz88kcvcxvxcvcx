extends TestCase
## Localization: table loading/merging (including every parts file in the repo),
## en<->tr key parity, placeholders, locale resolution and TranslationServer install.

const SCRATCH_DIR: String = "user://test_feel_i18n"
const FORMAT_FIELD_PATTERN: String = "\\{([a-z_]+)\\}"

var _saved_locale: String = ""


func before_each() -> void:
	_saved_locale = TranslationServer.get_locale()


func after_each() -> void:
	TranslationServer.set_locale(_saved_locale)
	_remove_scratch()


func _remove_scratch() -> void:
	var parts: String = SCRATCH_DIR.path_join(Localization.PARTS_DIR)
	for dir_path: String in [parts, SCRATCH_DIR]:
		if DirAccess.dir_exists_absolute(dir_path):
			for f: String in DirAccess.get_files_at(dir_path):
				DirAccess.remove_absolute(dir_path.path_join(f))
			DirAccess.remove_absolute(dir_path)


func _format_fields(text: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var re: RegEx = RegEx.create_from_string(FORMAT_FIELD_PATTERN)
	for m: RegExMatch in re.search_all(text):
		if not out.has(m.get_string(1)):
			out.append(m.get_string(1))
	out.sort()
	return out


func test_tables_load_for_supported_locales() -> void:
	var tables: Dictionary = Localization.load_all()
	for locale: String in Localization.SUPPORTED_LOCALES:
		assert_has(tables, locale)
		assert_gt((tables[locale] as Dictionary).size(), 200, "%s has the common UI strings" % locale)


func test_every_key_exists_in_both_languages() -> void:
	var loc: Localization = Localization.new()
	var en_missing_in_tr: PackedStringArray = loc.missing_keys("en", "tr")
	var tr_missing_in_en: PackedStringArray = loc.missing_keys("tr", "en")
	assert_empty(en_missing_in_tr, "keys missing in tr")
	assert_empty(tr_missing_in_en, "keys missing in en")
	assert_eq(loc.keys("en"), loc.keys("tr"))


func test_every_parts_file_in_repo_is_paired_and_merged() -> void:
	var parts_dir: String = Localization.DEFAULT_DIR.path_join(Localization.PARTS_DIR)
	if not DirAccess.dir_exists_absolute(parts_dir):
		assert_true(true, "no parts present yet")
		return
	var loc: Localization = Localization.new()
	for file: String in DirAccess.get_files_at(parts_dir):
		if file.get_extension() != "json":
			continue
		var module: String = file.get_basename().get_basename()
		for locale: String in Localization.SUPPORTED_LOCALES:
			var sibling: String = parts_dir.path_join("%s.%s.json" % [module, locale])
			assert_true(FileAccess.file_exists(sibling), "%s needs %s" % [file, sibling.get_file()])
		var data: Dictionary = JsonIO.read_dict(parts_dir.path_join(file))
		for key: Variant in data:
			assert_true(loc.has_key(str(key), "en"), "%s merged" % str(key))


func test_values_are_non_empty_and_placeholders_match() -> void:
	var loc: Localization = Localization.new()
	for key: String in loc.keys("en"):
		var en_text: String = loc.text(key, "en")
		var tr_text: String = loc.text(key, "tr")
		assert_false(en_text.strip_edges().is_empty(), key)
		assert_false(tr_text.strip_edges().is_empty(), key)
		assert_eq(_format_fields(tr_text), _format_fields(en_text), "format fields of %s" % key)


func test_turkish_is_actually_translated() -> void:
	var loc: Localization = Localization.new()
	var same: int = 0
	var total: int = 0
	for key: String in loc.keys("en"):
		total += 1
		if loc.text(key, "en") == loc.text(key, "tr"):
			same += 1
	assert_lt(float(same) / float(total), 0.1, "fewer than 10% identical strings (names, XP, ...)")
	assert_eq(loc.text("menu.play", "tr"), "OYNA")
	assert_eq(loc.text("fail.play_again", "tr"), "TEKRAR OYNA")


func test_required_ui_keys_exist() -> void:
	var loc: Localization = Localization.new()
	var required: PackedStringArray = [
		"menu.play", "menu.progress", "menu.shop", "menu.collection", "menu.daily", "menu.settings",
		"pause.title", "pause.resume", "pause.restart", "pause.quit",
		"fail.play_again", "fail.revive", "fail.home",
		"complete.stars", "complete.score", "complete.best", "complete.coins", "complete.continue",
		"complete.next", "store.unavailable", "store.restore", "store.restore_done", "store.restore_failed",
		"credits.title", "licenses.title", "a11y.pause_button", "tutorial.hop", "toast.achievement",
	]
	for key: String in required:
		assert_true(loc.has_key(key, "en"), key)
	for key: String in PlayerProfile.DEFAULT_SETTINGS:
		assert_true(loc.has_key("settings.%s" % key, "en"), "label for setting %s" % key)
	for v: String in SettingsService.QUALITY_VALUES:
		assert_true(loc.has_key("settings.quality.%s" % v, "en"), "quality %s" % v)
	for v: String in SettingsService.LANGUAGE_VALUES:
		assert_true(loc.has_key("settings.language.%s" % v, "en"), "language %s" % v)
	for grade: String in RunResult.Grade.keys():
		if grade != "NONE":
			assert_true(loc.has_key("grade.%s" % grade.to_lower(), "en"), "grade %s" % grade)
	for form: String in SimConst.Form.keys():
		for suffix: String in ["name", "hint", "desc"]:
			assert_true(loc.has_key("form.%s.%s" % [form.to_lower(), suffix], "en"), "form %s %s" % [form, suffix])
	for raw: Variant in JsonIO.read_dict("res://data/worlds/index.json").get("worlds", []) as Array:
		var id: String = str((raw as Dictionary)["id"])
		for suffix: String in ["name", "boss", "challenge"]:
			assert_true(loc.has_key("world.%s.%s" % [id, suffix], "en"), "world %s %s" % [id, suffix])


func test_world_names_match_world_data() -> void:
	var loc: Localization = Localization.new()
	for raw: Variant in JsonIO.read_dict("res://data/worlds/index.json").get("worlds", []) as Array:
		var entry: Dictionary = raw as Dictionary
		var world: Dictionary = JsonIO.read_dict("res://data/worlds/%s" % str(entry["file"]))
		var id: String = str(entry["id"])
		assert_eq(loc.text("world.%s.name" % id, "en"), str(world["name"]))
		assert_eq(loc.text("world.%s.boss" % id, "en"), str((world["boss"] as Dictionary)["name"]))
		assert_eq(loc.text("world.%s.challenge" % id, "en"), str((world["challenge"] as Dictionary)["name"]))


func test_resolve_locale() -> void:
	assert_eq(Localization.resolve_locale("auto", "tr"), "tr")
	assert_eq(Localization.resolve_locale("auto", "de"), "en", "unsupported device language")
	assert_eq(Localization.resolve_locale("", "tr"), "tr")
	assert_eq(Localization.resolve_locale("tr", "en"), "tr", "explicit choice wins")
	assert_eq(Localization.resolve_locale("TR_tr", "en"), "tr", "region dropped, case ignored")
	assert_eq(Localization.resolve_locale("xx", "tr"), "en")
	assert_eq(Localization.resolve_locale("auto", ""), "en")


func test_install_registers_translations_and_switches() -> void:
	var bus: EventBus = EventBus.new()
	var seen: Array[String] = []
	bus.locale_changed.connect(func(locale: String) -> void: seen.append(locale))
	var loc: Localization = Localization.new(Localization.DEFAULT_DIR, bus)
	assert_eq(loc.install("tr"), "tr")
	assert_eq(TranslationServer.get_locale(), "tr")
	assert_eq(String(TranslationServer.translate(&"menu.play")), "OYNA")
	assert_eq(loc.current_locale(), "tr")
	assert_eq(loc.install("en"), "en")
	assert_eq(String(TranslationServer.translate(&"menu.play")), "PLAY")
	assert_eq(seen, ["tr", "en"] as Array[String])
	loc.install("en")
	assert_eq(seen.size(), 2, "no signal when the locale did not change")
	loc.uninstall()
	assert_eq(String(TranslationServer.translate(&"menu.play")), "menu.play", "translations removed")


func test_install_auto_follows_device_or_falls_back() -> void:
	var loc: Localization = Localization.new()
	var expected: String = Localization.resolve_locale("auto", OS.get_locale_language())
	assert_eq(loc.install("auto"), expected)
	assert_true(Localization.SUPPORTED_LOCALES.has(expected))
	loc.uninstall()


func test_language_setting_switches_live() -> void:
	var settings: SettingsService = SettingsService.new(PlayerProfile.new(), EventBus.new())
	var loc: Localization = Localization.new()
	loc.bind_settings(settings)
	loc.install(settings.get_string("language"))
	settings.set_value("language", "tr")
	assert_eq(loc.current_locale(), "tr")
	assert_eq(String(TranslationServer.translate(&"pause.resume")), "Devam et")
	settings.set_value("language", "en")
	assert_eq(loc.current_locale(), "en")
	loc.uninstall()


func test_text_and_format_fallbacks() -> void:
	var loc: Localization = Localization.new()
	assert_eq(loc.text("no.such.key"), "no.such.key")
	assert_eq(loc.format("reward.coins", {"n": 25}, "en"), "+25 coins")
	assert_eq(loc.format("reward.coins", {"n": 25}, "tr"), "+25 altın")
	assert_eq(loc.text("menu.play", "de"), "PLAY", "unknown locale falls back to English")


func test_parts_merge_and_bad_files() -> void:
	_remove_scratch()
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR.path_join(Localization.PARTS_DIR))
	JsonIO.write_json(SCRATCH_DIR.path_join("en.json"), {"a.one": "One", "a.num": 5})
	JsonIO.write_json(SCRATCH_DIR.path_join("tr.json"), {"a.one": "Bir"})
	JsonIO.write_json(SCRATCH_DIR.path_join("parts/mod.en.json"), {"mod.two": "Two"})
	JsonIO.write_json(SCRATCH_DIR.path_join("parts/mod.tr.json"), {"mod.two": "İki"})
	JsonIO.write_json(SCRATCH_DIR.path_join("parts/nolocale.json"), {"x": "y"})
	var f: FileAccess = FileAccess.open(SCRATCH_DIR.path_join("parts/broken.en.json"), FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	var tables: Dictionary = Localization.load_all(SCRATCH_DIR)
	assert_eq((tables["en"] as Dictionary).size(), 2, "non-string value skipped, part merged")
	assert_eq((tables["tr"] as Dictionary)["mod.two"], "İki")
	assert_false((tables["en"] as Dictionary).has("x"))
	var loc: Localization = Localization.new(SCRATCH_DIR)
	assert_empty(loc.missing_keys("en", "tr"))
	assert_empty(Localization.load_all("user://definitely_missing_dir"))
