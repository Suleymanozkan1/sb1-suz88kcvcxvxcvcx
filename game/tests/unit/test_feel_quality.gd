extends TestCase
## Quality presets, battery saver, auto-detect, FrameMonitor and the automatic
## downgrade policy (sustained slowness only, once per cooldown, manual opt-out).

const SLOW_DT: float = 0.05
const FAST_DT: float = 1.0 / 60.0

var _settings: SettingsService
var _bus: EventBus
var _events: Array = []
var _saved_max_fps: int = 0


func before_each() -> void:
	_settings = SettingsService.new(PlayerProfile.new(), EventBus.new())
	_bus = EventBus.new()
	_events = []
	_bus.quality_changed.connect(_on_quality_changed)
	_saved_max_fps = Engine.max_fps


func after_each() -> void:
	Engine.max_fps = _saved_max_fps


func _on_quality_changed(preset: StringName, automatic: bool) -> void:
	_events.append([preset, automatic])


## Presets document whose auto-detection always starts at "high" (deterministic).
func _doc_starting_high() -> Dictionary:
	var doc: Dictionary = JsonIO.read_dict(QualityService.DEFAULT_PRESETS_PATH).duplicate(true)
	var rule: Array = [{"min_cores": 0, "preset": "high"}]
	doc["auto_detect"] = {"compatibility_preset": "high", "mobile": rule, "desktop": rule}
	return doc


func _feed(q: QualityService, dt: float, seconds: float) -> int:
	var steps: int = 0
	var t: float = 0.0
	while t < seconds:
		if q.feed_frame(dt):
			steps += 1
		t += dt
	return steps


func test_shipped_presets_are_complete() -> void:
	var doc: Dictionary = JsonIO.read_dict(QualityService.DEFAULT_PRESETS_PATH)
	assert_empty(QualityService.validate_document(doc))
	var presets: Dictionary = doc["presets"] as Dictionary
	for name: StringName in QualityService.PRESET_ORDER:
		var p: Dictionary = presets[String(name)] as Dictionary
		for key: String in QualityService.PARAM_TYPES:
			assert_has(p, key, "%s.%s" % [name, key])
		assert_ge(int(p["msaa_3d"]), 0)
		assert_le(int(p["msaa_3d"]), 3)


func test_presets_scale_up_monotonically() -> void:
	var q: QualityService = QualityService.new(_settings, _bus)
	var prev: Dictionary = {}
	for name: StringName in q.preset_names():
		_settings.set_value("quality", String(name))
		var p: Dictionary = q.params()
		assert_eq(p["preset"], String(name))
		if not prev.is_empty():
			for key: String in ["render_scale", "particle_scale", "trail_points", "msaa_3d", "fps_cap"]:
				assert_ge(float(p[key]), float(prev[key]), "%s %s" % [name, key])
		prev = p


func test_manual_setting_selects_preset() -> void:
	_settings.set_value("quality", "medium")
	var q: QualityService = QualityService.new(_settings, _bus)
	assert_eq(q.current(), &"medium")
	assert_false(q.is_auto())
	_settings.set_value("quality", "ultra")
	assert_eq(q.current(), &"ultra")
	assert_eq(_events.size(), 1)
	assert_eq(_events[0], [&"ultra", false])


func test_battery_saver_caps_fps_and_preset() -> void:
	_settings.set_value("quality", "ultra")
	var q: QualityService = QualityService.new(_settings, _bus)
	assert_eq(int(q.params()["fps_cap"]), 120)
	_settings.set_value("battery_saver", true)
	var p: Dictionary = q.params()
	assert_eq(int(p["fps_cap"]), 30)
	assert_eq(p["preset"], "low")
	assert_true(p["battery_saver"] as bool)
	assert_false(p["post_fx"] as bool)
	assert_eq(q.current(), &"ultra", "the chosen preset is remembered")
	assert_eq(q.effective_preset(), &"low")
	assert_eq(_events.size(), 1, "views are told to re-apply")
	assert_near(q.target_frame_ms(), 1000.0 / 30.0, 0.01)
	_settings.set_value("battery_saver", false)
	assert_eq(int(q.params()["fps_cap"]), 120)


func test_auto_detect_is_conservative() -> void:
	var q: QualityService = QualityService.new(_settings, _bus)
	assert_eq(q.detect_for(true, 8, "mobile"), &"medium")
	assert_eq(q.detect_for(true, 4, "mobile"), &"low")
	assert_eq(q.detect_for(false, 16, "forward_plus"), &"high")
	assert_eq(q.detect_for(false, 4, "forward_plus"), &"medium")
	assert_eq(q.detect_for(false, 2, "mobile"), &"low")
	assert_eq(q.detect_for(false, 32, QualityService.RENDERER_COMPATIBILITY), &"low")
	assert_ne(q.auto_detect(), &"ultra", "auto never picks ultra")
	assert_true(q.preset_names().has(q.auto_detect()))


func test_auto_downgrade_needs_sustained_slow_frames() -> void:
	var q: QualityService = QualityService.new(_settings, _bus, _doc_starting_high())
	assert_true(q.is_auto())
	assert_eq(q.current(), &"high")
	assert_eq(_feed(q, SLOW_DT, 2.0), 0, "2 s of slowness is not enough")
	assert_eq(_feed(q, SLOW_DT, 1.5), 1, "past the 3 s window: one step down")
	assert_eq(q.current(), &"medium")
	assert_eq(_events, [[&"medium", true]])


func test_auto_downgrade_at_most_once_per_cooldown_and_never_below_low() -> void:
	var q: QualityService = QualityService.new(_settings, _bus, _doc_starting_high())
	assert_eq(_feed(q, SLOW_DT, 3.5), 1)
	assert_eq(_feed(q, SLOW_DT, 15.0), 0, "cooldown blocks a second step")
	assert_eq(_feed(q, SLOW_DT, 6.0), 1, "after 20 s another step is allowed")
	assert_eq(q.current(), &"low")
	assert_eq(_feed(q, SLOW_DT, 120.0), 0, "never below low")
	assert_eq(_events.size(), 2)


func test_hitches_and_fast_frames_never_downgrade() -> void:
	var q: QualityService = QualityService.new(_settings, _bus, _doc_starting_high())
	assert_eq(_feed(q, FAST_DT, 60.0), 0)
	for i: int in 10:
		assert_eq(q.feed_frame(2.0), false, "isolated long hitches are clamped and ignored")
		_feed(q, FAST_DT, 4.0)
	for i: int in 8:
		# Slow bursts shorter than the window (including the average's recovery).
		_feed(q, SLOW_DT, 1.5)
		_feed(q, FAST_DT, 2.0)
	assert_eq(q.current(), &"high")
	assert_empty(_events)


func test_manual_preset_disables_auto_downgrade() -> void:
	var q: QualityService = QualityService.new(_settings, _bus, _doc_starting_high())
	assert_true(q.set_preset(&"high"))
	assert_eq(_settings.get_string("quality"), "high", "manual choice persisted in settings")
	assert_false(q.is_auto())
	assert_eq(_feed(q, SLOW_DT, 90.0), 0)
	assert_eq(q.current(), &"high")
	assert_eq(_events, [[&"high", false]])
	assert_false(q.set_preset(&"potato"))
	_settings.set_value("quality", "auto")
	assert_true(q.is_auto())
	assert_eq(_feed(q, SLOW_DT, 3.5), 1, "auto re-enabled")


func test_battery_saver_suspends_auto_downgrade() -> void:
	var q: QualityService = QualityService.new(_settings, _bus, _doc_starting_high())
	_settings.set_value("battery_saver", true)
	_events.clear()
	assert_eq(_feed(q, 0.1, 60.0), 0)
	assert_eq(q.current(), &"high")


func test_apply_to_viewport() -> void:
	_settings.set_value("quality", "medium")
	var q: QualityService = QualityService.new(_settings, _bus)
	var vp: SubViewport = SubViewport.new()
	q.apply_to_viewport(vp)
	var p: Dictionary = q.params()
	assert_near(vp.scaling_3d_scale, float(p["render_scale"]), 0.0001)
	assert_eq(int(vp.msaa_3d), int(p["msaa_3d"]))
	assert_eq(Engine.max_fps, int(p["fps_cap"]))
	_settings.set_value("battery_saver", true)
	q.apply_to_viewport(vp)
	assert_eq(Engine.max_fps, 30)
	q.apply_to_viewport(null)
	vp.free()


func test_broken_presets_fall_back_safely() -> void:
	var doc: Dictionary = {"presets": {"low": {"render_scale": "big", "fps_cap": 9999}}, "battery_saver": {}}
	assert_gt(QualityService.validate_document(doc).size(), 3)
	var q: QualityService = QualityService.new(_settings, _bus, doc)
	assert_eq(q.preset_names().size(), 4)
	_settings.set_value("quality", "low")
	var p: Dictionary = q.params()
	assert_near(float(p["render_scale"]), float(QualityService.FALLBACK_PARAMS["render_scale"]), 0.0001)
	assert_eq(int(p["fps_cap"]), QualityService.MAX_FPS_CAP, "clamped")
	for key: String in QualityService.PARAM_TYPES:
		assert_has(p, key)


func test_malformed_auto_detect_rules_fall_back_to_lowest() -> void:
	var doc: Dictionary = JsonIO.read_dict(QualityService.DEFAULT_PRESETS_PATH)
	doc["auto_detect"] = {"mobile": {"min_cores": 8, "preset": "ultra"}, "desktop": "high"}
	var problems: PackedStringArray = QualityService.validate_document(doc)
	assert_has(problems, "auto_detect.mobile must be a list of rules")
	assert_has(problems, "auto_detect.desktop must be a list of rules")
	var q: QualityService = QualityService.new(_settings, _bus, doc)
	assert_eq(q.current(), &"low", "construction survives and picks the safest preset")
	assert_eq(q.detect_for(true, 8, "mobile"), &"low")
	assert_eq(q.detect_for(false, 16, "forward_plus"), &"low")


func test_battery_overrides_are_range_clamped() -> void:
	var doc: Dictionary = JsonIO.read_dict(QualityService.DEFAULT_PRESETS_PATH)
	(doc["battery_saver"] as Dictionary)["overrides"] = {"render_scale": 50.0, "trail_points": 0, "fps_cap": 5}
	_settings.set_value("quality", "high")
	_settings.set_value("battery_saver", true)
	var q: QualityService = QualityService.new(_settings, _bus, doc)
	var p: Dictionary = q.params()
	assert_near(float(p["render_scale"]), QualityService.MAX_RENDER_SCALE, 0.0001)
	assert_eq(int(p["trail_points"]), QualityService.MIN_TRAIL_POINTS)
	assert_eq(int(p["fps_cap"]), QualityService.MIN_FPS_CAP)
	assert_eq(typeof(p["fps_cap"]), TYPE_INT)
	assert_near(q.target_frame_ms(), 1000.0 / QualityService.MIN_FPS_CAP, 0.01)


func test_target_frame_matches_params_for_every_state() -> void:
	var q: QualityService = QualityService.new(_settings, _bus)
	for saver: bool in [false, true]:
		_settings.set_value("battery_saver", saver)
		for name: StringName in q.preset_names():
			assert_true(q.set_preset(name))
			var fps: int = int(q.params()["fps_cap"])
			assert_near(q.target_frame_ms(), 1000.0 / float(fps), 0.01, "%s saver=%s" % [name, str(saver)])


func test_frame_monitor_average_and_window() -> void:
	var m: FrameMonitor = FrameMonitor.new()
	for i: int in 120:
		m.push(FAST_DT)
	assert_near(m.average_ms(), 1000.0 / 60.0, 0.01)
	assert_near(m.average_fps(), 60.0, 0.1)
	assert_false(m.is_struggling(1000.0 / 60.0))
	var t: float = 0.0
	while t < 2.9:
		m.push(SLOW_DT)
		t += SLOW_DT
	assert_false(m.is_struggling(1000.0 / 60.0), "window not yet covered")
	for i: int in 10:
		m.push(SLOW_DT)
	assert_true(m.is_struggling(1000.0 / 60.0))
	assert_false(m.is_struggling(60.0), "fine against a 60 ms budget")
	m.reset()
	assert_false(m.is_struggling(1000.0 / 60.0))
	assert_near(m.average_ms(), 0.0, 0.0001)


func test_frame_monitor_rejects_bad_samples() -> void:
	var m: FrameMonitor = FrameMonitor.new()
	m.push(NAN)
	m.push(-1.0)
	m.push(0.0)
	assert_near(m.average_ms(), 0.0, 0.0001)
	m.push(5.0)
	assert_near(m.average_ms(), FrameMonitor.DEFAULT_MAX_SAMPLE_S * 1000.0, 0.01, "hitch clamped")
	assert_false(m.is_struggling(0.0))
