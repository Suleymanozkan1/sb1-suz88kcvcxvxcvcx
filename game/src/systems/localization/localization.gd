class_name Localization
extends RefCounted
## String tables and locale selection.
##
## Tables are flat {"key": "text"} JSON files: data/i18n/<locale>.json holds the
## common UI strings and every module adds data/i18n/parts/<module>.<locale>.json.
## [method install] registers one [Translation] per supported locale with the
## [TranslationServer] (so Controls translate their text keys automatically) and
## selects the locale from the "language" setting ("auto" follows the device
## when it is supported, English otherwise).

const LOG_CHANNEL: String = "i18n"
const DEFAULT_DIR: String = "res://data/i18n"
const PARTS_DIR: String = "parts"
const JSON_EXT: String = "json"
const SUPPORTED_LOCALES: PackedStringArray = ["en", "tr"]
const FALLBACK_LOCALE: String = "en"
const AUTO: String = "auto"
const LANGUAGE_CODE_LENGTH: int = 2

var _base_dir: String = DEFAULT_DIR
var _bus: EventBus
var _tables: Dictionary = {}
var _installed: Array[Translation] = []
var _locale: String = FALLBACK_LOCALE


## Loads all tables from [param base_dir]. [param bus] (optional) receives
## [signal EventBus.locale_changed].
func _init(base_dir: String = DEFAULT_DIR, bus: EventBus = null) -> void:
	_base_dir = base_dir
	_bus = bus
	_tables = load_all(base_dir)


## Reads <locale>.json plus parts/*.<locale>.json under [param base_dir] and
## returns {locale: {key: text}}. Non-string values are skipped with a warning.
static func load_all(base_dir: String = DEFAULT_DIR) -> Dictionary:
	var out: Dictionary = {}
	if not DirAccess.dir_exists_absolute(base_dir):
		GameLog.error(LOG_CHANNEL, "translation directory %s missing" % base_dir)
		return out
	var base_files: PackedStringArray = DirAccess.get_files_at(base_dir)
	base_files.sort()
	for file: String in base_files:
		if file.get_extension() == JSON_EXT and _is_locale_code(file.get_basename()):
			_merge_file(out, file.get_basename(), base_dir.path_join(file))
	var parts_dir: String = base_dir.path_join(PARTS_DIR)
	if DirAccess.dir_exists_absolute(parts_dir):
		var part_files: PackedStringArray = DirAccess.get_files_at(parts_dir)
		part_files.sort()
		for file: String in part_files:
			if file.get_extension() != JSON_EXT:
				continue
			var locale: String = file.get_basename().get_extension()
			if not _is_locale_code(locale):
				GameLog.warn(LOG_CHANNEL, "ignoring %s (expected <module>.<locale>.json)" % file)
				continue
			_merge_file(out, locale, parts_dir.path_join(file))
	return out


## Maps a language preference to a supported locale: "auto"/"" uses
## [param os_language]; region suffixes ("tr_TR") are dropped; anything
## unsupported falls back to English.
static func resolve_locale(preference: String, os_language: String) -> String:
	var pref: String = preference.strip_edges().to_lower()
	if pref.is_empty() or pref == AUTO:
		pref = os_language.strip_edges().to_lower()
	pref = pref.substr(0, LANGUAGE_CODE_LENGTH)
	return pref if SUPPORTED_LOCALES.has(pref) else FALLBACK_LOCALE


## Registers translations for every supported locale and activates the one
## chosen by [param locale_pref]. Returns the active locale.
func install(locale_pref: String) -> String:
	uninstall()
	for locale: String in SUPPORTED_LOCALES:
		var table: Dictionary = _tables.get(locale, {}) as Dictionary
		if table.is_empty():
			GameLog.warn(LOG_CHANNEL, "no strings for locale %s" % locale)
			continue
		var t: Translation = Translation.new()
		t.locale = locale
		for key: String in table:
			t.add_message(StringName(key), StringName(str(table[key])))
		TranslationServer.add_translation(t)
		_installed.append(t)
	var resolved: String = resolve_locale(locale_pref, OS.get_locale_language())
	var previous: String = _locale
	TranslationServer.set_locale(resolved)
	_locale = resolved
	if _bus != null and previous != resolved:
		_bus.locale_changed.emit(resolved)
	return resolved


## Removes the translations this instance registered.
func uninstall() -> void:
	for t: Translation in _installed:
		TranslationServer.remove_translation(t)
	_installed.clear()


## Re-installs whenever the "language" setting changes.
func bind_settings(settings: SettingsService) -> void:
	if settings != null and not settings.changed.is_connected(_on_settings_changed):
		settings.changed.connect(_on_settings_changed)


## The active locale code.
func current_locale() -> String:
	return _locale


## Locales that have a table, sorted.
func locales() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for locale: String in _tables:
		out.append(locale)
	out.sort()
	return out


## All keys of [param locale], sorted.
func keys(locale: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for key: String in _tables.get(locale, {}) as Dictionary:
		out.append(key)
	out.sort()
	return out


## Keys present (and non-empty) in [param from_locale] but missing or empty in
## [param to_locale], sorted.
func missing_keys(from_locale: String, to_locale: String) -> PackedStringArray:
	var source: Dictionary = _tables.get(from_locale, {}) as Dictionary
	var target: Dictionary = _tables.get(to_locale, {}) as Dictionary
	var out: PackedStringArray = PackedStringArray()
	for key: String in source:
		if str(source[key]).is_empty():
			continue
		if not target.has(key) or str(target[key]).strip_edges().is_empty():
			out.append(key)
	out.sort()
	return out


## True when [param key] exists in [param locale] (active locale when empty).
func has_key(key: String, locale: String = "") -> bool:
	return (_tables.get(_locale if locale.is_empty() else locale, {}) as Dictionary).has(key)


## Text for [param key] in [param locale] (active when empty), falling back to
## English and finally to the key itself. Usable without the TranslationServer.
func text(key: String, locale: String = "") -> String:
	var loc: String = _locale if locale.is_empty() else locale
	var table: Dictionary = _tables.get(loc, {}) as Dictionary
	if table.has(key):
		return str(table[key])
	var fallback: Dictionary = _tables.get(FALLBACK_LOCALE, {}) as Dictionary
	return str(fallback.get(key, key))


## [method text] with {name} fields substituted from [param args].
func format(key: String, args: Dictionary, locale: String = "") -> String:
	return text(key, locale).format(args)


func _on_settings_changed(key: StringName, value: Variant) -> void:
	if key == &"language":
		install(str(value))


static func _merge_file(out: Dictionary, locale: String, path: String) -> void:
	var data: Dictionary = JsonIO.read_dict(path)
	if data.is_empty():
		GameLog.warn(LOG_CHANNEL, "empty or invalid string table %s" % path)
		return
	var table: Dictionary = out.get(locale, {}) as Dictionary
	for key: Variant in data:
		var value: Variant = data[key]
		if typeof(value) != TYPE_STRING:
			GameLog.warn(LOG_CHANNEL, "%s: value of '%s' is not a string" % [path, str(key)])
			continue
		var k: String = str(key)
		if table.has(k) and str(table[k]) != str(value):
			GameLog.warn(LOG_CHANNEL, "%s: key '%s' redefined" % [path, k])
		table[k] = value
	out[locale] = table


static func _is_locale_code(code: String) -> bool:
	if code.length() != LANGUAGE_CODE_LENGTH:
		return false
	for c: String in code:
		if c < "a" or c > "z":
			return false
	return true
