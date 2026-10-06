extends TestCase
## SettingsService: validation, coercion, change signals, reset and repair.

var _profile: PlayerProfile
var _bus: EventBus
var _settings: SettingsService
var _bus_events: Array = []
var _own_events: Array = []


func before_each() -> void:
	_profile = PlayerProfile.new()
	_bus = EventBus.new()
	_bus_events = []
	_own_events = []
	_bus.settings_changed.connect(_on_bus_changed)
	_settings = SettingsService.new(_profile, _bus)
	_settings.changed.connect(_on_own_changed)


func _on_bus_changed(key: StringName, value: Variant) -> void:
	_bus_events.append([key, value])


func _on_own_changed(key: StringName, value: Variant) -> void:
	_own_events.append([key, value])


func test_defaults_are_readable() -> void:
	for key: String in PlayerProfile.DEFAULT_SETTINGS:
		assert_eq(_settings.get_value(key), PlayerProfile.DEFAULT_SETTINGS[key], key)
	assert_true(_settings.get_bool("sound"))
	assert_near(_settings.get_float("music_volume"), 0.8, 0.0001)
	assert_eq(_settings.get_string("quality"), "auto")
	assert_eq(_settings.keys().size(), PlayerProfile.DEFAULT_SETTINGS.size())


func test_valid_change_is_stored_and_emitted_once() -> void:
	assert_true(_settings.set_value("haptics", false))
	assert_false(_settings.get_bool("haptics"))
	assert_false(_profile.settings["haptics"] as bool, "profile slice updated")
	assert_eq(_bus_events.size(), 1)
	assert_eq(_bus_events[0][0], &"haptics")
	assert_eq(_bus_events[0][1], false)
	assert_eq(_own_events.size(), 1, "service signal mirrors the bus")


func test_unchanged_value_is_accepted_without_signal() -> void:
	assert_true(_settings.set_value("sound", true))
	assert_empty(_bus_events)


func test_unknown_key_rejected() -> void:
	assert_false(_settings.set_value("volume_master", 1.0))
	assert_eq(_settings.get_value("volume_master"), null)
	assert_false(_profile.settings.has("volume_master"))
	assert_empty(_bus_events)


func test_wrong_types_rejected() -> void:
	assert_false(_settings.set_value("sound", 1))
	assert_false(_settings.set_value("sound", "true"))
	assert_false(_settings.set_value("quality", 2))
	assert_false(_settings.set_value("sfx_volume", "0.5"))
	assert_false(_settings.set_value("language", null))
	assert_empty(_bus_events)
	assert_true(_settings.get_bool("sound"))


func test_volume_ranges() -> void:
	assert_false(_settings.set_value("sfx_volume", -0.01))
	assert_false(_settings.set_value("sfx_volume", 1.01))
	assert_false(_settings.set_value("music_volume", NAN))
	assert_false(_settings.set_value("music_volume", INF))
	assert_true(_settings.set_value("sfx_volume", 0.0))
	assert_true(_settings.set_value("music_volume", 1))
	assert_eq(typeof(_settings.get_value("music_volume")), TYPE_FLOAT, "int is coerced to float")
	assert_near(_settings.get_float("music_volume"), 1.0, 0.0001)
	assert_near(_settings.get_float("sfx_volume"), 0.0, 0.0001)


func test_quality_values() -> void:
	for v: String in SettingsService.QUALITY_VALUES:
		assert_true(_settings.set_value("quality", v), v)
		assert_eq(_settings.get_string("quality"), v)
	assert_false(_settings.set_value("quality", "potato"))
	assert_false(_settings.set_value("quality", "HIGH"))
	assert_eq(_settings.get_string("quality"), "ultra")


func test_language_values() -> void:
	assert_true(_settings.set_value("language", "tr"))
	assert_true(_settings.set_value("language", "en"))
	assert_true(_settings.set_value("language", "auto"))
	assert_false(_settings.set_value("language", "de"))
	assert_eq(_settings.get_string("language"), "auto")


func test_reset_to_defaults_emits_only_changed_keys() -> void:
	_settings.set_value("music", false)
	_settings.set_value("quality", "low")
	_bus_events.clear()
	_settings.reset_to_defaults()
	assert_eq(_bus_events.size(), 2)
	assert_true(_settings.get_bool("music"))
	assert_eq(_settings.get_string("quality"), "auto")
	assert_eq(_settings.snapshot(), PlayerProfile.DEFAULT_SETTINGS)


func test_invalid_stored_values_are_repaired() -> void:
	var p: PlayerProfile = PlayerProfile.new()
	p.settings["sfx_volume"] = 7.5
	p.settings["quality"] = "bogus"
	p.settings["language"] = "klingon"
	p.settings.erase("haptics")
	p.settings["music_volume"] = 0.25
	var s: SettingsService = SettingsService.new(p, null)
	assert_near(s.get_float("sfx_volume"), 1.0, 0.0001)
	assert_eq(s.get_string("quality"), "auto")
	assert_eq(s.get_string("language"), "auto")
	assert_true(s.get_bool("haptics"))
	assert_near(s.get_float("music_volume"), 0.25, 0.0001, "valid values kept")


func test_null_bus_and_null_profile_are_safe() -> void:
	var s: SettingsService = SettingsService.new(null, null)
	assert_true(s.set_value("sound", false))
	assert_false(s.get_bool("sound"))


func test_settings_survive_save_roundtrip() -> void:
	_settings.set_value("language", "tr")
	_settings.set_value("sfx_volume", 0.4)
	var restored: PlayerProfile = PlayerProfile.from_dict(_profile.to_dict())
	var s: SettingsService = SettingsService.new(restored, null)
	assert_eq(s.get_string("language"), "tr")
	assert_near(s.get_float("sfx_volume"), 0.4, 0.0001)


func test_string_name_values_are_accepted_and_stored_as_strings() -> void:
	assert_true(_settings.set_value("quality", &"medium"), "QualityService hands out StringName presets")
	assert_eq(typeof(_profile.settings["quality"]), TYPE_STRING, "saved as a plain String")
	assert_eq(_settings.get_string("quality"), "medium")
	assert_eq(typeof(_bus_events[0][1]), TYPE_STRING, "listeners always receive a String")
	assert_true(_settings.set_value("quality", "medium"), "same value as String")
	assert_eq(_bus_events.size(), 1, "no duplicate change for an equal value")
	assert_false(_settings.set_value("quality", &"potato"))
	assert_false(_settings.set_value("sound", &"true"), "StringName only stands in for String settings")
	assert_true(_settings.set_value("language", &"tr"))
	assert_eq(_settings.get_string("language"), "tr")


func test_is_valid_static_helper() -> void:
	assert_true(SettingsService.is_valid("reduce_motion", true))
	assert_false(SettingsService.is_valid("reduce_motion", 0))
	assert_true(SettingsService.is_valid("sfx_volume", 1))
	assert_false(SettingsService.is_valid("nope", true))
