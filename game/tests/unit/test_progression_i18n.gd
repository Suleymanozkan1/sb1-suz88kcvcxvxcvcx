extends TestCase
## Progression/stats strings: the en and tr parts stay in sync, are really
## translated and cover every stat label and hint key the services return.

const EN_PATH: String = "res://data/i18n/parts/progression.en.json"
const TR_PATH: String = "res://data/i18n/parts/progression.tr.json"
const KEY_PATTERN: String = "^progression(\\.[a-z0-9]+(_[a-z0-9]+)*)+$"
const FORMAT_TOKEN_PATTERN: String = "\\{[a-z_]+\\}"
## Words that read the same in both languages (units such as XP).
const SHARED_WORDS: PackedStringArray = ["XP"]

var en: Dictionary = {}
var tr_text: Dictionary = {}


func before_each() -> void:
	en = JsonIO.read_dict(EN_PATH)
	tr_text = JsonIO.read_dict(TR_PATH)


func _format_tokens(text: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var regex: RegEx = RegEx.create_from_string(FORMAT_TOKEN_PATTERN)
	for m: RegExMatch in regex.search_all(text):
		out.append(m.get_string())
	out.sort()
	return out


## The text left once format tokens, shared words and punctuation are removed.
func _words(text: String) -> String:
	var stripped: String = RegEx.create_from_string(FORMAT_TOKEN_PATTERN).sub(text, "", true)
	for word: String in SHARED_WORDS:
		stripped = stripped.replace(word, "")
	return RegEx.create_from_string("[^\\p{L}]").sub(stripped, "", true)


func test_both_locales_load() -> void:
	assert_false(en.is_empty(), "progression.en.json loads")
	assert_false(tr_text.is_empty(), "progression.tr.json loads")


func test_same_keys_in_both_locales() -> void:
	for key: Variant in en:
		assert_has(tr_text, key, "tr has %s" % key)
	for key2: Variant in tr_text:
		assert_has(en, key2, "en has %s" % key2)
	assert_eq(en.size(), tr_text.size())


func test_keys_are_prefixed_and_texts_non_empty() -> void:
	var pattern: RegEx = RegEx.create_from_string(KEY_PATTERN)
	for table: Dictionary in [en, tr_text]:
		for key: Variant in table:
			assert_true(pattern.search(str(key)) != null, "key %s is progression.lower_snake" % key)
			assert_eq(typeof(table[key]), TYPE_STRING, "%s is text" % key)
			assert_false(str(table[key]).strip_edges().is_empty(), "%s is not empty" % key)


func test_format_tokens_match_between_locales() -> void:
	for key: Variant in en:
		if not tr_text.has(key):
			continue
		var en_tokens: PackedStringArray = _format_tokens(str(en[key]))
		var tr_tokens: PackedStringArray = _format_tokens(str(tr_text[key]))
		assert_eq(tr_tokens, en_tokens, "format tokens of %s" % key)


func test_turkish_texts_are_translated() -> void:
	for key: Variant in en:
		var words: String = _words(str(en[key]))
		if words.is_empty() or not tr_text.has(key):
			continue
		assert_ne(str(tr_text[key]), str(en[key]), "%s has a Turkish translation" % key)


func test_every_stat_and_hint_has_a_label() -> void:
	for stat: String in StatsService.known_stats():
		assert_has(en, "progression.stat." + stat, "en label for %s" % stat)
		assert_has(tr_text, "progression.stat." + stat, "tr label for %s" % stat)
	var hint_keys: PackedStringArray = [
		ProgressionService.HINT_KEY_LEVEL,
		ProgressionService.HINT_KEY_WORLD,
		ProgressionService.HINT_KEY_STARS,
		ProgressionService.HINT_KEY_PLAYER_LEVEL,
		ProgressionService.HINT_KEY_COMPLETE,
	]
	for key: String in hint_keys:
		assert_has(en, key, "en hint text %s" % key)
		assert_has(tr_text, key, "tr hint text %s" % key)
