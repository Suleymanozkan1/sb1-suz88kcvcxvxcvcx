extends TestCase
## Remote config: typed defaults, per-key validation, fetch and cache.

const REQUIRED_KEYS: PackedStringArray = [
	"economy.coin_multiplier",
	"economy.daily_reward_multiplier",
	"difficulty.global_speed_scale",
	"difficulty.min_window_scale",
	"ads.interstitial_every_n_levels",
	"ads.interstitial_min_level",
	"ads.enabled",
	"daily.enabled",
	"events.weekend_coin_bonus",
	"leaderboard.base_url",
	"analytics.endpoint",
	"config.url",
]
const CONFIG_URL: String = "https://config.example.invalid/v1/config"


## In-memory cache storage for the read/write callables.
class InMemoryCache:
	extends RefCounted
	var text: String = ""
	var writes: int = 0

	func read() -> String:
		return text

	func write(value: String) -> void:
		text = value
		writes += 1


## Transport double answering every request with a fixed response.
class ScriptedTransport:
	extends RefCounted
	var response: Variant = {"ok": false, "status": 0, "body": null, "error": "cant_connect"}
	var calls: Array[Dictionary] = []

	func respond(method: String, url: String, body: Dictionary) -> Variant:
		calls.append({"method": method, "url": url, "body": body})
		return response


func _config(cache: InMemoryCache = null) -> RemoteConfig:
	var defaults: Dictionary = RemoteConfig.load_defaults()
	if cache == null:
		return RemoteConfig.new(defaults, Callable(), Callable())
	return RemoteConfig.new(defaults, cache.read, cache.write)


func test_bundled_defaults_declare_required_keys() -> void:
	var rc: RemoteConfig = _config()
	for key: String in REQUIRED_KEYS:
		assert_true(rc.has_key(key), "%s declared" % key)
	assert_eq(rc.get_value("economy.coin_multiplier"), 1.0)
	assert_eq(rc.get_value("difficulty.global_speed_scale"), 1.0)
	assert_eq(typeof(rc.get_value("ads.interstitial_every_n_levels")), TYPE_INT)
	assert_eq(rc.get_value("ads.enabled"), true)
	assert_eq(rc.get_value("leaderboard.base_url"), "")
	assert_eq(rc.get_value("analytics.endpoint"), "")
	assert_eq(rc.get_value("config.url"), "")
	assert_eq(rc.type_of("events.weekend_coin_bonus"), "float")


func test_unknown_key_returns_null() -> void:
	var rc: RemoteConfig = _config()
	assert_eq(rc.get_value("nope.missing"), null)
	assert_eq(rc.get_int("nope.missing", 7), 7)


func test_overrides_reject_bad_values_individually() -> void:
	var rc: RemoteConfig = _config()
	var rejected: PackedStringArray = rc.apply_overrides(
		{
			"economy.coin_multiplier": 1.5,
			"difficulty.global_speed_scale": 5.0,
			"ads.interstitial_every_n_levels": 4.0,
			"ads.interstitial_min_level": 7.5,
			"ads.enabled": "yes",
			"daily.enabled": false,
			"events.weekend_coin_bonus": -0.2,
			"leaderboard.base_url": "http://insecure.example.invalid",
			"analytics.endpoint": "https://analytics.example.invalid/v1/events",
			"unknown.key": 3,
		}
	)
	for key: String in [
		"difficulty.global_speed_scale",
		"ads.interstitial_min_level",
		"ads.enabled",
		"events.weekend_coin_bonus",
		"leaderboard.base_url",
		"unknown.key",
	]:
		assert_has(rejected, key, "rejected")
	assert_eq(rejected.size(), 6)
	assert_eq(rc.get_value("economy.coin_multiplier"), 1.5, "valid value kept")
	assert_eq(rc.get_value("ads.interstitial_every_n_levels"), 4, "integral JSON float accepted as int")
	assert_eq(typeof(rc.get_value("ads.interstitial_every_n_levels")), TYPE_INT)
	assert_eq(rc.get_value("daily.enabled"), false)
	assert_eq(rc.get_value("analytics.endpoint"), "https://analytics.example.invalid/v1/events")
	assert_eq(rc.get_value("difficulty.global_speed_scale"), 1.0, "rejected key keeps its default")
	assert_eq(rc.get_value("ads.enabled"), true)
	assert_eq(rc.get_value("leaderboard.base_url"), "")
	assert_false(rc.has_override("difficulty.global_speed_scale"))
	assert_true(rc.has_override("economy.coin_multiplier"))


func test_values_are_typed_and_clamped_even_with_bad_schema_defaults() -> void:
	var schema: Dictionary = {
		"schema": {
			"a.float": {"type": "float", "min": 0.5, "max": 2.0, "default": 9.0},
			"a.int": {"type": "int", "min": 1, "max": 3, "default": "two"},
			"a.bool": {"type": "bool", "default": 1},
			"a.str": {"type": "string", "default": 5},
			"a.len": {"type": "string", "max_length": [8], "default": "kept"},
			"a.bad": {"type": "vector", "default": 1},
			"a.notdict": 3,
		}
	}
	var rc: RemoteConfig = RemoteConfig.new(schema, Callable(), Callable())
	assert_eq(rc.get_value("a.float"), 0.5, "invalid default replaced by clamped zero")
	assert_eq(rc.get_value("a.int"), 1)
	assert_eq(rc.get_value("a.bool"), false)
	assert_eq(rc.get_value("a.str"), "")
	assert_eq(rc.get_value("a.len"), "kept", "malformed max_length falls back to the default limit")
	assert_false(rc.has_key("a.bad"))
	assert_false(rc.has_key("a.notdict"))
	assert_eq(rc.get_float("a.float"), 0.5)
	assert_eq(rc.get_bool("a.bool", true), false)


func test_applied_signal_reports_changed_keys() -> void:
	var rc: RemoteConfig = _config()
	var seen: Array[PackedStringArray] = []
	rc.applied.connect(func(keys: PackedStringArray) -> void: seen.append(keys))
	rc.apply_overrides({"economy.coin_multiplier": 1.2})
	rc.apply_overrides({"economy.coin_multiplier": 1.2})
	assert_eq(seen.size(), 1, "re-applying the same value changes nothing")
	assert_eq(seen[0], PackedStringArray(["economy.coin_multiplier"]))
	rc.reset_overrides()
	assert_eq(seen.size(), 2)
	assert_eq(rc.get_value("economy.coin_multiplier"), 1.0)


func test_fetch_success_applies_snapshot_and_caches() -> void:
	var cache: InMemoryCache = InMemoryCache.new()
	var rc: RemoteConfig = _config(cache)
	rc.apply_overrides({"daily.enabled": false})
	var transport: ScriptedTransport = ScriptedTransport.new()
	transport.response = {
		"ok": true,
		"status": 200,
		"body": {"values": {"economy.coin_multiplier": 1.25, "difficulty.min_window_scale": 9.0}},
		"error": "",
	}
	var ok: bool = await rc.fetch(transport.respond, CONFIG_URL)
	assert_true(ok)
	assert_true(rc.last_fetch_ok)
	assert_eq(transport.calls[0]["method"], "GET")
	assert_eq(transport.calls[0]["url"], CONFIG_URL)
	assert_eq(rc.get_value("economy.coin_multiplier"), 1.25)
	assert_eq(rc.get_value("difficulty.min_window_scale"), 1.0, "out-of-range remote value rejected")
	assert_eq(rc.get_value("daily.enabled"), true, "a fetched snapshot replaces older overrides")
	assert_has(rc.last_rejected, "difficulty.min_window_scale")
	assert_eq(cache.writes, 1)


func test_fetch_accepts_flat_and_text_bodies() -> void:
	var rc: RemoteConfig = _config()
	var transport: ScriptedTransport = ScriptedTransport.new()
	transport.response = {"ok": true, "status": 200, "body": "{\"economy.coin_multiplier\": 0.75}", "error": ""}
	assert_true(await rc.fetch(transport.respond, CONFIG_URL))
	assert_eq(rc.get_value("economy.coin_multiplier"), 0.75)
	transport.response = {"ok": true, "status": 200, "body": [1, 2], "error": ""}
	assert_false(await rc.fetch(transport.respond, CONFIG_URL), "non-object body refused")
	assert_eq(rc.get_value("economy.coin_multiplier"), 0.75, "previous values kept")


func test_fetch_offline_keeps_cached_values() -> void:
	var cache: InMemoryCache = InMemoryCache.new()
	var first: RemoteConfig = _config(cache)
	first.apply_overrides({"economy.coin_multiplier": 1.5, "ads.interstitial_every_n_levels": 5})
	assert_true(first.save_cache())
	var second: RemoteConfig = _config(cache)
	assert_true(second.load_cache())
	var transport: ScriptedTransport = ScriptedTransport.new()
	var ok: bool = await second.fetch(transport.respond, CONFIG_URL)
	assert_false(ok, "offline fetch fails")
	assert_eq(second.get_value("economy.coin_multiplier"), 1.5, "cached value survives offline")
	assert_eq(second.get_value("ads.interstitial_every_n_levels"), 5)
	transport.response = "garbage"
	assert_false(await second.fetch(transport.respond, CONFIG_URL))
	assert_false(await second.fetch(transport.respond, ""), "empty url disables fetching")


func test_cache_round_trip() -> void:
	var cache: InMemoryCache = InMemoryCache.new()
	var rc: RemoteConfig = _config(cache)
	rc.apply_overrides(
		{
			"economy.daily_reward_multiplier": 1.75,
			"daily.enabled": false,
			"config.url": "https://config.example.invalid/c.json",
			"ads.interstitial_min_level": 10,
		}
	)
	rc.save_cache()
	var restored: RemoteConfig = _config(cache)
	assert_true(restored.load_cache())
	assert_eq(restored.overrides(), rc.overrides())
	assert_eq(restored.get_value("economy.daily_reward_multiplier"), 1.75)
	assert_eq(restored.get_value("daily.enabled"), false)
	assert_eq(restored.get_value("config.url"), "https://config.example.invalid/c.json")
	assert_eq(typeof(restored.get_value("ads.interstitial_min_level")), TYPE_INT, "ints survive JSON round trip")
	assert_eq(restored.get_value("ads.interstitial_min_level"), 10)


func test_corrupt_or_tampered_cache_falls_back_to_defaults() -> void:
	var cache: InMemoryCache = InMemoryCache.new()
	cache.text = "{broken json"
	var rc: RemoteConfig = _config(cache)
	assert_false(rc.load_cache())
	assert_eq(rc.get_value("economy.coin_multiplier"), 1.0)
	cache.text = JSON.stringify({"format": "something_else", "values": {"economy.coin_multiplier": 1.5}})
	assert_false(rc.load_cache(), "foreign format ignored")
	cache.text = JSON.stringify(
		{"format": RemoteConfig.CACHE_FORMAT, "version": 1, "values": {"economy.coin_multiplier": 50.0}}
	)
	assert_true(rc.load_cache())
	assert_eq(rc.get_value("economy.coin_multiplier"), 1.0, "tampered out-of-range cache value rejected")
	var no_storage: RemoteConfig = _config()
	assert_false(no_storage.load_cache())
	assert_false(no_storage.save_cache())


func test_file_storage_helpers_round_trip() -> void:
	var path: String = "user://test_platform_rc_%d/remote_config.json" % Time.get_ticks_usec()
	var rc: RemoteConfig = RemoteConfig.new(
		RemoteConfig.load_defaults(), RemoteConfig.file_reader(path), RemoteConfig.file_writer(path)
	)
	assert_false(rc.load_cache(), "no cache file yet")
	rc.apply_overrides({"events.weekend_coin_bonus": 0.25})
	assert_true(rc.save_cache())
	var restored: RemoteConfig = RemoteConfig.new(
		RemoteConfig.load_defaults(), RemoteConfig.file_reader(path), RemoteConfig.file_writer(path)
	)
	assert_true(restored.load_cache())
	assert_eq(restored.get_value("events.weekend_coin_bonus"), 0.25)
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path.get_base_dir())


func test_url_validation() -> void:
	assert_true(RemoteConfig.is_secure_url_or_empty(""))
	assert_true(RemoteConfig.is_secure_url_or_empty("https://a.example.invalid/x"))
	assert_false(RemoteConfig.is_secure_url_or_empty("http://a.example.invalid/x"))
	assert_false(RemoteConfig.is_secure_url_or_empty("https://"))
	assert_false(RemoteConfig.is_secure_url_or_empty("https://a b"))
	assert_false(RemoteConfig.is_secure_url_or_empty("javascript:alert(1)"))
