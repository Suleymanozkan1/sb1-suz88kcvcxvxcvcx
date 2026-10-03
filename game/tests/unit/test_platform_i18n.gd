extends TestCase
## Platform strings: complete EN/TR pairs, key format, neutral reminder copy.

const EN_PATH: String = "res://data/i18n/parts/platform.en.json"
const TR_PATH: String = "res://data/i18n/parts/platform.tr.json"
const KEY_PREFIXES: PackedStringArray = ["platform.", "notif."]
const URGENCY_WORDS_EN: PackedStringArray = [
	"hurry",
	"last chance",
	"don't miss",
	"expire",
	"lose",
	"too late",
	"now!",
	"streak",
]
const URGENCY_WORDS_TR: PackedStringArray = ["acele et", "son şans", "kaçırma", "kaybet", "süre doluyor", "seri"]


func test_locales_have_identical_keys_and_real_translations() -> void:
	var en: Dictionary = JsonIO.read_dict(EN_PATH)
	var tr_strings: Dictionary = JsonIO.read_dict(TR_PATH)
	assert_gt(en.size(), 0)
	assert_eq(en.size(), tr_strings.size(), "same number of keys")
	var key_format: RegEx = RegEx.create_from_string("^[a-z0-9_]+(\\.[a-z0-9_]+)+$")
	for key: String in en:
		assert_true(tr_strings.has(key), "tr has %s" % key)
		assert_true(key_format.search(key) != null, "key format %s" % key)
		var prefixed: bool = false
		for prefix: String in KEY_PREFIXES:
			prefixed = prefixed or key.begins_with(prefix)
		assert_true(prefixed, "module prefix on %s" % key)
		assert_false(str(en[key]).strip_edges().is_empty(), "en text for %s" % key)
		assert_false(str(tr_strings.get(key, "")).strip_edges().is_empty(), "tr text for %s" % key)
		assert_ne(str(tr_strings.get(key, "")), str(en[key]), "%s is actually translated" % key)


func test_required_keys_present() -> void:
	var en: Dictionary = JsonIO.read_dict(EN_PATH)
	assert_has(en, NotificationService.TITLE_KEY)
	assert_has(en, NotificationService.BODY_KEY)
	assert_has(en, StoreService.MESSAGE_KEY_GENERIC)
	for error: String in StoreService.KNOWN_ERRORS:
		assert_has(en, StoreService.message_key(error))


func test_consent_copy_does_not_overclaim_anonymity() -> void:
	# Events carry the random install id (pseudonymous), so the copy must not
	# promise anonymity or "no personal data".
	var key: String = "platform.analytics.consent.body"
	var en_text: String = str(JsonIO.read_dict(EN_PATH).get(key, "")).to_lower()
	var tr_text: String = str(JsonIO.read_dict(TR_PATH).get(key, "")).to_lower()
	for word: String in ["anonymous", "no personal data"]:
		assert_false(en_text.contains(word), "en consent copy must not claim '%s'" % word)
	for word: String in ["anonim", "kişisel veri toplanmaz"]:
		assert_false(tr_text.contains(word), "tr consent copy must not claim '%s'" % word)
	assert_has(en_text, "random id")


func test_reminder_copy_is_neutral() -> void:
	var en: Dictionary = JsonIO.read_dict(EN_PATH)
	var tr_strings: Dictionary = JsonIO.read_dict(TR_PATH)
	for key: String in [NotificationService.TITLE_KEY, NotificationService.BODY_KEY]:
		var en_text: String = str(en.get(key, "")).to_lower()
		var tr_text: String = str(tr_strings.get(key, "")).to_lower()
		for word: String in URGENCY_WORDS_EN:
			assert_false(en_text.contains(word), "no urgency ('%s') in %s" % [word, key])
		for word: String in URGENCY_WORDS_TR:
			assert_false(tr_text.contains(word), "no urgency ('%s') in tr %s" % [word, key])
