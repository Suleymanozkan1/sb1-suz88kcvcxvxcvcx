extends TestCase
## HapticsService: data validity, per-kind rate limit, global floor, opt-out,
## battery saver amplitude and robustness, with injected vibrate + clock.

var _now: int = 0
var _calls: Array[Dictionary] = []
var _settings: SettingsService


func before_each() -> void:
	_now = 10_000
	_calls = []
	_settings = SettingsService.new(PlayerProfile.new(), EventBus.new())


func _vibrate(duration_ms: int, amplitude: float) -> void:
	_calls.append({"duration_ms": duration_ms, "amplitude": amplitude})


func _clock() -> int:
	return _now


func _make(patterns: Dictionary = {}) -> HapticsService:
	return HapticsService.new(_settings, _vibrate, patterns, _clock)


func test_shipped_patterns_are_complete_and_valid() -> void:
	var doc: Dictionary = JsonIO.read_dict(HapticsService.DEFAULT_PATTERNS_PATH)
	assert_false(doc.is_empty(), "patterns.json readable")
	assert_empty(HapticsService.validate_document(doc))
	var h: HapticsService = _make()
	for kind: StringName in HapticsService.REQUIRED_KINDS:
		assert_true(h.has_pattern(kind), String(kind))
		var p: Dictionary = h.pattern(kind)
		assert_has(p, "duration_ms")
		assert_has(p, "amplitude")
		assert_has(p, "min_interval_ms")


func test_play_uses_pattern_values() -> void:
	var h: HapticsService = _make()
	var expected: Dictionary = h.pattern(&"tap")
	assert_true(h.play(&"tap"))
	assert_eq(_calls.size(), 1)
	assert_eq(_calls[0]["duration_ms"], expected["duration_ms"])
	assert_near(float(_calls[0]["amplitude"]), float(expected["amplitude"]), 0.0001)
	assert_eq(h.played_count(), 1)


func test_per_kind_rate_limit() -> void:
	var h: HapticsService = _make()
	var interval: int = int(h.pattern(&"tap")["min_interval_ms"])
	assert_gt(interval, HapticsService.GLOBAL_MIN_INTERVAL_MS, "test needs a per-kind interval above the floor")
	assert_true(h.play(&"tap"))
	_now += HapticsService.GLOBAL_MIN_INTERVAL_MS + 1
	assert_false(h.play(&"tap"), "global floor passed but per-kind interval not")
	_now += interval
	assert_true(h.play(&"tap"))
	assert_eq(_calls.size(), 2)


func test_global_floor_across_kinds() -> void:
	var h: HapticsService = _make()
	assert_true(h.play(&"tap"))
	_now += HapticsService.GLOBAL_MIN_INTERVAL_MS - 1
	assert_false(h.play(&"fail"), "another kind is still blocked by the 40 ms floor")
	_now += 1
	assert_true(h.play(&"fail"))
	assert_eq(_calls.size(), 2)


func test_global_floor_cannot_be_lowered_by_data() -> void:
	var doc: Dictionary = JsonIO.read_dict(HapticsService.DEFAULT_PATTERNS_PATH)
	doc["global_min_interval_ms"] = 1
	var h: HapticsService = _make(doc)
	assert_true(h.play(&"tap"))
	_now += 10
	assert_false(h.play(&"fail"))


func test_burst_of_events_is_throttled() -> void:
	var h: HapticsService = _make()
	var kinds: Array[StringName] = [&"collect", &"combo", &"near_miss", &"shatter", &"tap"]
	for i: int in 100:
		h.play(kinds[i % kinds.size()])
		_now += 5
	# 500 ms of spam can produce at most one vibration per 40 ms.
	assert_le(_calls.size(), 500 / HapticsService.GLOBAL_MIN_INTERVAL_MS + 1)
	assert_gt(_calls.size(), 0)


func test_opt_out_setting() -> void:
	var h: HapticsService = _make()
	_settings.set_value("haptics", false)
	assert_false(h.play(&"perfect"))
	assert_empty(_calls)
	_settings.set_value("haptics", true)
	assert_true(h.play(&"perfect"))
	assert_eq(_calls.size(), 1)


func test_battery_saver_halves_amplitude() -> void:
	var h: HapticsService = _make()
	assert_true(h.play(&"hit"))
	var normal: float = float(_calls[0]["amplitude"])
	_settings.set_value("battery_saver", true)
	_now += 10_000
	assert_true(h.play(&"hit"))
	assert_near(float(_calls[1]["amplitude"]), normal * 0.5, 0.0001)
	assert_eq(_calls[1]["duration_ms"], _calls[0]["duration_ms"], "duration unchanged")


func test_strength_scales_amplitude_and_zero_is_ignored() -> void:
	var h: HapticsService = _make()
	var base: float = float(h.pattern(&"fail")["amplitude"])
	assert_true(h.play(&"fail", 0.5))
	assert_near(float(_calls[0]["amplitude"]), base * 0.5, 0.0001)
	_now += 10_000
	assert_false(h.play(&"fail", 0.0))
	assert_false(h.play(&"fail", NAN))
	assert_true(h.play(&"fail", 7.0))
	assert_near(float(_calls[1]["amplitude"]), base, 0.0001, "strength clamps to 1")


func test_aliases_share_the_target_rate_limit() -> void:
	var h: HapticsService = _make()
	assert_eq(h.resolve(&"shield_break"), &"hit")
	assert_eq(h.resolve(&"bump"), &"hit")
	assert_true(h.play(&"shield_break"))
	_now += HapticsService.GLOBAL_MIN_INTERVAL_MS + 1
	assert_false(h.play(&"bump"), "same pattern, per-kind interval applies")
	assert_eq(_calls.size(), 1)


func test_every_gameplay_feedback_kind_resolves_or_is_silent_by_design() -> void:
	var h: HapticsService = _make()
	var silent: Array[StringName] = [&"denied", &"miss", &"current", &"overdrive_end"]
	for kind: StringName in SoundBank.REQUIRED_KINDS:
		if silent.has(kind):
			assert_false(h.has_pattern(kind), "%s intentionally has no vibration" % kind)
		else:
			assert_true(h.has_pattern(kind), "%s should vibrate" % kind)


func test_unknown_kind_is_ignored() -> void:
	var h: HapticsService = _make()
	assert_false(h.play(&"does_not_exist"))
	assert_empty(_calls)


func test_malformed_data_is_sanitised() -> void:
	var doc: Dictionary = {
		"patterns":
		{
			"tap": {"duration_ms": -5, "amplitude": 9.0, "min_interval_ms": "soon"},
			"ui": "not an object",
		},
		"aliases": {"ui_click": "missing_target"},
	}
	assert_gt(HapticsService.validate_document(doc).size(), 3)
	var h: HapticsService = _make(doc)
	var tap: Dictionary = h.pattern(&"tap")
	assert_eq(tap["duration_ms"], HapticsService.MIN_DURATION_MS)
	assert_near(float(tap["amplitude"]), 1.0, 0.0001)
	assert_eq(tap["min_interval_ms"], HapticsService.SAFE_INTERVAL_MS)
	assert_true(h.has_pattern(&"fail"), "missing required kinds fall back to a safe pattern")
	assert_false(h.has_pattern(&"ui_click"), "dangling alias ignored")
	assert_true(h.play(&"tap"))


func test_plain_pattern_map_is_accepted() -> void:
	var h: HapticsService = _make({"tap": {"duration_ms": 20, "amplitude": 0.4, "min_interval_ms": 100}})
	assert_true(h.play(&"tap"))
	assert_eq(_calls[0]["duration_ms"], 20)


func test_on_feedback_lifts_light_events() -> void:
	var h: HapticsService = _make()
	var base: float = float(h.pattern(&"tap")["amplitude"])
	h.on_feedback(&"tap", 0.0, 3)
	assert_eq(_calls.size(), 1)
	assert_near(float(_calls[0]["amplitude"]), base * HapticsService.FEEDBACK_STRENGTH_FLOOR, 0.0001)


func test_reset_rate_limits() -> void:
	var h: HapticsService = _make()
	assert_true(h.play(&"perfect"))
	assert_false(h.play(&"perfect"))
	h.reset_rate_limits()
	assert_true(h.play(&"perfect"))


func test_default_vibrate_is_safe_off_device() -> void:
	var h: HapticsService = HapticsService.new(_settings)
	assert_true(h.play(&"tap"), "request accepted even when the platform has no vibrator")
	h.on_feedback(&"collect", 0.3, 1)
