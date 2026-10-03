class_name QualityService
extends RefCounted
## Graphics quality presets (data/quality/presets.json), battery saver and the
## automatic, conservative downgrade on sustained slow frames.
##
## The "quality" setting is either a preset name (manual: never changed by the
## game) or "auto": an initial preset is chosen from the device class and the
## [FrameMonitor] steps it down one level when frames stay slow, at most once
## per cooldown and never below the lowest preset. Battery saver caps the
## effective preset and frame rate without touching the chosen preset.

const LOG_CHANNEL: String = "quality"
const DEFAULT_PRESETS_PATH: String = "res://data/quality/presets.json"
const AUTO: String = "auto"
const PRESET_ORDER: Array[StringName] = [&"low", &"medium", &"high", &"ultra"]
## Parameter name -> expected Variant type.
const PARAM_TYPES: Dictionary = {
	"render_scale": TYPE_FLOAT,
	"msaa_3d": TYPE_INT,
	"post_fx": TYPE_BOOL,
	"particle_scale": TYPE_FLOAT,
	"trail_points": TYPE_INT,
	"dynamic_light": TYPE_BOOL,
	"shadows": TYPE_BOOL,
	"glow": TYPE_BOOL,
	"fps_cap": TYPE_INT,
	"ambient_particles": TYPE_BOOL,
}
## Safe values used for any missing or malformed parameter.
const FALLBACK_PARAMS: Dictionary = {
	"render_scale": 0.75,
	"msaa_3d": 0,
	"post_fx": false,
	"particle_scale": 0.5,
	"trail_points": 12,
	"dynamic_light": false,
	"shadows": false,
	"glow": false,
	"fps_cap": 60,
	"ambient_particles": false,
}
const MIN_RENDER_SCALE: float = 0.25
const MAX_RENDER_SCALE: float = 2.0
const MAX_MSAA: int = 3
const MIN_FPS_CAP: int = 15
const MAX_FPS_CAP: int = 240
const MAX_PARTICLE_SCALE: float = 4.0
const MIN_TRAIL_POINTS: int = 2
const MAX_TRAIL_POINTS: int = 256
const DEFAULT_COOLDOWN_S: float = 20.0
const DEFAULT_BATTERY_FPS: int = 30
const MS_PER_S: float = 1000.0
const RENDERER_COMPATIBILITY: String = "gl_compatibility"

var _settings: SettingsService
var _bus: EventBus
var _order: Array[StringName] = []
var _presets: Dictionary = {}
var _battery_max: StringName = &"low"
var _battery_fps: int = DEFAULT_BATTERY_FPS
var _battery_overrides: Dictionary = {}
var _detect: Dictionary = {}
var _monitor: FrameMonitor
var _cooldown_s: float = DEFAULT_COOLDOWN_S
var _since_change_s: float = 0.0
var _current: StringName = &"low"
var _refresh_hz: float = -1.0


## [param presets] is the presets document; empty loads [constant DEFAULT_PRESETS_PATH].
func _init(settings: SettingsService, bus: EventBus, presets: Dictionary = {}) -> void:
	_settings = settings
	_bus = bus
	var doc: Dictionary = presets if not presets.is_empty() else JsonIO.read_dict(DEFAULT_PRESETS_PATH)
	for p: String in validate_document(doc):
		GameLog.warn(LOG_CHANNEL, p)
	_load(doc)
	if not AppInfo.is_headless():
		_refresh_hz = DisplayServer.screen_get_refresh_rate()
	var pref: String = settings.get_string("quality") if settings != null else AUTO
	_current = StringName(pref) if _presets.has(StringName(pref)) else auto_detect()
	_since_change_s = _cooldown_s
	if settings != null:
		settings.changed.connect(_on_settings_changed)


## Problems in a presets document (empty when complete and valid).
static func validate_document(doc: Dictionary) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var presets: Dictionary = _dict(doc.get("presets", {}))
	for name: StringName in PRESET_ORDER:
		if not presets.has(String(name)):
			problems.append("preset '%s' missing" % name)
			continue
		var p: Dictionary = _dict(presets[String(name)])
		for key: String in PARAM_TYPES:
			if not p.has(key):
				problems.append("preset '%s' lacks %s" % [name, key])
			elif not _type_ok(p[key], int(PARAM_TYPES[key])):
				problems.append("preset '%s' %s has wrong type" % [name, key])
	var battery: Dictionary = _dict(doc.get("battery_saver", {}))
	if not presets.has(str(battery.get("max_preset", ""))):
		problems.append("battery_saver.max_preset unknown")
	return problems


## The chosen preset (manual choice or the current automatic level).
func current() -> StringName:
	return _current


## True when the player left quality on "auto".
func is_auto() -> bool:
	return _settings == null or _settings.get_string("quality") == AUTO


## Preset names from lowest to highest.
func preset_names() -> Array[StringName]:
	return _order.duplicate()


## The preset actually applied (battery saver may cap [method current]).
func effective_preset() -> StringName:
	if not _battery_saver():
		return _current
	var cap: int = _order.find(_battery_max)
	var idx: int = _order.find(_current)
	return _order[mini(idx, cap)] if cap >= 0 and idx >= 0 else _current


## Effective render parameters (copy), including battery-saver caps, plus
## "preset" (effective name) and "battery_saver" (bool).
func params() -> Dictionary:
	var preset: StringName = effective_preset()
	var p: Dictionary = (_presets.get(preset, FALLBACK_PARAMS) as Dictionary).duplicate()
	var saver: bool = _battery_saver()
	if saver:
		for key: String in _battery_overrides:
			p[key] = _battery_overrides[key]
		p["fps_cap"] = mini(int(p["fps_cap"]), _battery_fps)
	p["preset"] = String(preset)
	p["battery_saver"] = saver
	return p


## Conservative initial preset for this device.
func auto_detect() -> StringName:
	return detect_for(AppInfo.is_mobile(), OS.get_processor_count(), RenderingServer.get_current_rendering_method())


## Pure detection rule (testable): compatibility renderer -> its preset; otherwise
## the first mobile/desktop rule whose "min_cores" the device meets.
func detect_for(is_mobile: bool, cores: int, rendering_method: String) -> StringName:
	if rendering_method == RENDERER_COMPATIBILITY:
		return _valid_or_lowest(StringName(str(_detect.get("compatibility_preset", ""))))
	var rules: Array = _detect.get("mobile" if is_mobile else "desktop", []) as Array
	for raw: Variant in rules:
		var rule: Dictionary = _dict(raw)
		if cores >= int(_num(rule, "min_cores", 0.0)):
			return _valid_or_lowest(StringName(str(rule.get("preset", ""))))
	return _order[0]


## Manual choice: stores the preset in settings (which disables auto-downgrade)
## and emits [signal EventBus.quality_changed]. Returns false for unknown names.
func set_preset(preset: StringName) -> bool:
	if not _presets.has(preset):
		GameLog.warn(LOG_CHANNEL, "unknown preset '%s'" % preset)
		return false
	_current = preset
	_restart_monitoring(false)
	if _settings != null:
		_settings.set_value("quality", String(preset))
	_emit(false)
	return true


## Feeds one frame time. In "auto" mode, when frames have been slow for the
## monitor's window, steps down one preset (not below the lowest, at most once
## per cooldown) and emits quality_changed(preset, true). Returns true on a step.
func feed_frame(delta: float) -> bool:
	if not is_auto() or _battery_saver() or is_nan(delta) or delta <= 0.0:
		return false
	_monitor.push(delta)
	_since_change_s += delta
	if _since_change_s < _cooldown_s:
		return false
	var idx: int = _order.find(_current)
	if idx <= 0 or not _monitor.is_struggling(target_frame_ms()):
		return false
	_current = _order[idx - 1]
	_restart_monitoring(true)
	GameLog.info(LOG_CHANNEL, "sustained slow frames: auto quality -> %s" % _current)
	_emit(true)
	return true


## Frame budget in ms for the effective fps cap (limited by the display refresh).
func target_frame_ms() -> float:
	var fps: float = float(maxi(int(params()["fps_cap"]), MIN_FPS_CAP))
	if _refresh_hz > 0.0:
		fps = minf(fps, _refresh_hz)
	return MS_PER_S / fps


## The frame monitor (exposed for diagnostics overlays).
func monitor() -> FrameMonitor:
	return _monitor


## Applies render scale, 3D MSAA and the fps cap.
func apply_to_viewport(viewport: Viewport) -> void:
	var p: Dictionary = params()
	if viewport != null:
		viewport.scaling_3d_scale = float(p["render_scale"])
		viewport.msaa_3d = int(p["msaa_3d"]) as Viewport.MSAA
	Engine.max_fps = int(p["fps_cap"])


func _on_settings_changed(key: StringName, value: Variant) -> void:
	match String(key):
		"quality":
			var v: String = str(value)
			if v == AUTO:
				_current = auto_detect()
			elif _presets.has(StringName(v)) and StringName(v) != _current:
				_current = StringName(v)
			else:
				return
			_restart_monitoring(false)
			_emit(false)
		"battery_saver":
			_restart_monitoring(false)
			_emit(false)


## Clears frame history. After an automatic step the cooldown starts; after a
## player-driven change a new downgrade only needs a fresh sustained window.
func _restart_monitoring(start_cooldown: bool) -> void:
	_monitor.reset()
	_since_change_s = 0.0 if start_cooldown else _cooldown_s


func _emit(automatic: bool) -> void:
	if _bus != null:
		_bus.quality_changed.emit(effective_preset(), automatic)


func _battery_saver() -> bool:
	return _settings != null and _settings.get_bool("battery_saver")


func _valid_or_lowest(preset: StringName) -> StringName:
	return preset if _presets.has(preset) else _order[0]


func _load(doc: Dictionary) -> void:
	var raw_presets: Dictionary = _dict(doc.get("presets", {}))
	for name: StringName in PRESET_ORDER:
		_presets[name] = _sanitize(_dict(raw_presets.get(String(name), {})))
	_order = PRESET_ORDER.duplicate()
	var battery: Dictionary = _dict(doc.get("battery_saver", {}))
	_battery_max = _valid_or_lowest(StringName(str(battery.get("max_preset", ""))))
	_battery_fps = clampi(int(_num(battery, "fps_cap", DEFAULT_BATTERY_FPS)), MIN_FPS_CAP, MAX_FPS_CAP)
	var overrides: Dictionary = _dict(battery.get("overrides", {}))
	for key: Variant in overrides:
		var k: String = str(key)
		if PARAM_TYPES.has(k) and _type_ok(overrides[key], int(PARAM_TYPES[k])):
			_battery_overrides[k] = overrides[key]
	_detect = _dict(doc.get("auto_detect", {}))
	var down: Dictionary = _dict(doc.get("auto_downgrade", {}))
	_cooldown_s = maxf(0.0, _num(down, "cooldown_s", DEFAULT_COOLDOWN_S))
	_monitor = FrameMonitor.new(
		_num(down, "window_s", FrameMonitor.DEFAULT_WINDOW_S),
		_num(down, "slow_ratio", FrameMonitor.DEFAULT_SLOW_RATIO),
		_num(down, "ema_tau_s", FrameMonitor.DEFAULT_EMA_TAU_S),
		_num(down, "max_sample_s", FrameMonitor.DEFAULT_MAX_SAMPLE_S),
	)


static func _sanitize(raw: Dictionary) -> Dictionary:
	var p: Dictionary = {}
	for key: String in PARAM_TYPES:
		var expected: int = int(PARAM_TYPES[key])
		var v: Variant = raw.get(key, FALLBACK_PARAMS[key])
		if not _type_ok(v, expected):
			v = FALLBACK_PARAMS[key]
		match expected:
			TYPE_FLOAT:
				p[key] = float(v)
			TYPE_INT:
				p[key] = int(v)
			_:
				p[key] = v
	p["render_scale"] = clampf(float(p["render_scale"]), MIN_RENDER_SCALE, MAX_RENDER_SCALE)
	p["msaa_3d"] = clampi(int(p["msaa_3d"]), 0, MAX_MSAA)
	p["particle_scale"] = clampf(float(p["particle_scale"]), 0.0, MAX_PARTICLE_SCALE)
	p["trail_points"] = clampi(int(p["trail_points"]), MIN_TRAIL_POINTS, MAX_TRAIL_POINTS)
	p["fps_cap"] = clampi(int(p["fps_cap"]), MIN_FPS_CAP, MAX_FPS_CAP)
	return p


static func _type_ok(v: Variant, expected: int) -> bool:
	if expected == TYPE_FLOAT or expected == TYPE_INT:
		return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT
	return typeof(v) == expected


static func _dict(v: Variant) -> Dictionary:
	return v as Dictionary if typeof(v) == TYPE_DICTIONARY else {}


static func _num(d: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = d.get(key, fallback)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		var f: float = float(v)
		return fallback if is_nan(f) or is_inf(f) else f
	return fallback
