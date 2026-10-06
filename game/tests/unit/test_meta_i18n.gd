extends TestCase
## Translation parts of the meta module (achievements + missions): every key
## referenced by data exists in English and Turkish, with matching format tokens.

const EN_PATH: String = "res://data/i18n/parts/meta.en.json"
const TR_PATH: String = "res://data/i18n/parts/meta.tr.json"
const KEY_PATTERN: String = "^(ach|mis)(\\.[a-z0-9_]+)+$"
const TOKEN_PATTERN: String = "\\{[a-z_]+\\}"
## Letters that only appear in real Turkish text.
const TURKISH_LETTERS: String = "çğıöşüÇĞİÖŞÜ"


func _en() -> Dictionary:
	return JsonIO.read_dict(EN_PATH)


func _tr() -> Dictionary:
	return JsonIO.read_dict(TR_PATH)


func _referenced_keys() -> PackedStringArray:
	var keys: PackedStringArray = PackedStringArray()
	for raw: Variant in AchievementService.load_definitions():
		var d: Dictionary = raw as Dictionary
		keys.append(str(d["name_key"]))
		keys.append(str(d["desc_key"]))
	var config: Dictionary = MissionService.load_config()
	for kind: String in MissionService.KINDS:
		for raw: Variant in config.get(kind + "_templates", []) as Array:
			keys.append(str((raw as Dictionary)["desc_key"]))
	for category: String in AchievementService.CATEGORIES:
		keys.append("ach.category.%s" % category)
	return keys


func _format_tokens(text: String) -> PackedStringArray:
	var regex: RegEx = RegEx.create_from_string(TOKEN_PATTERN)
	var out: PackedStringArray = PackedStringArray()
	for m: RegExMatch in regex.search_all(text):
		out.append(m.get_string())
	out.sort()
	return out


func test_parts_parse_and_share_keys() -> void:
	var en: Dictionary = _en()
	var tr_text: Dictionary = _tr()
	assert_gt(en.size(), 0, "english part")
	assert_eq(en.size(), tr_text.size(), "same number of keys")
	for key: Variant in en:
		assert_true(tr_text.has(key), "turkish missing %s" % key)
		assert_eq(typeof(en[key]), TYPE_STRING, "%s is text" % key)
		assert_false(str(en[key]).strip_edges().is_empty(), "%s english empty" % key)
		assert_false(str(tr_text.get(key, "")).strip_edges().is_empty(), "%s turkish empty" % key)


func test_keys_are_namespaced_lower_snake() -> void:
	var regex: RegEx = RegEx.create_from_string(KEY_PATTERN)
	for key: Variant in _en():
		assert_true(regex.search(str(key)) != null, "bad key %s" % key)


func test_every_data_key_is_translated() -> void:
	var en: Dictionary = _en()
	var tr_text: Dictionary = _tr()
	for key: String in _referenced_keys():
		assert_true(en.has(key), "english missing %s" % key)
		assert_true(tr_text.has(key), "turkish missing %s" % key)


func test_format_tokens_match_between_languages() -> void:
	var en: Dictionary = _en()
	var tr_text: Dictionary = _tr()
	for key: Variant in en:
		assert_eq(_format_tokens(str(tr_text.get(key, ""))), _format_tokens(str(en[key])), "format tokens of %s" % key)


func test_turkish_is_a_real_translation() -> void:
	var en: Dictionary = _en()
	var tr_text: Dictionary = _tr()
	var differing: int = 0
	var with_turkish_letters: int = 0
	for key: Variant in en:
		var text: String = str(tr_text.get(key, ""))
		if text != str(en[key]):
			differing += 1
		for letter: String in TURKISH_LETTERS:
			if text.contains(letter):
				with_turkish_letters += 1
				break
	assert_gt(float(differing), en.size() * 0.9, "most strings translated")
	assert_gt(float(with_turkish_letters), en.size() * 0.5, "turkish orthography used")
