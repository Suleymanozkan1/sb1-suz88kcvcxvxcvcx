class_name FrameMonitor
extends RefCounted
## Smoothed frame-time tracker that detects *sustained* slowness.
##
## Frame times are smoothed with a time-constant exponential moving average
## (so the smoothing is frame-rate independent) and kept in a ring buffer. The
## device counts as struggling only when the average has stayed above
## target * [member slow_ratio] for at least [member window_s] seconds; single
## hitches (loading, GC, app resume) never trigger it.

const DEFAULT_WINDOW_S: float = 3.0
const DEFAULT_SLOW_RATIO: float = 1.25
const DEFAULT_EMA_TAU_S: float = 0.5
const DEFAULT_MAX_SAMPLE_S: float = 0.25
const MIN_WINDOW_S: float = 0.1
const MIN_SLOW_RATIO: float = 1.0
const MIN_EMA_TAU_S: float = 0.01
const MIN_SAMPLE_S: float = 0.001
const HISTORY_SIZE: int = 1024
const MS_PER_S: float = 1000.0

var window_s: float = DEFAULT_WINDOW_S
var slow_ratio: float = DEFAULT_SLOW_RATIO
var ema_tau_s: float = DEFAULT_EMA_TAU_S
var max_sample_s: float = DEFAULT_MAX_SAMPLE_S
var _ema_ms: float = 0.0
var _samples: int = 0
var _ema_hist: PackedFloat32Array = PackedFloat32Array()
var _dt_hist: PackedFloat32Array = PackedFloat32Array()
var _head: int = 0
var _count: int = 0


## [param window] seconds of sustained slowness, [param ratio] over the target,
## [param tau] smoothing time constant, [param max_sample] clamp for one frame.
func _init(
	window: float = DEFAULT_WINDOW_S,
	ratio: float = DEFAULT_SLOW_RATIO,
	tau: float = DEFAULT_EMA_TAU_S,
	max_sample: float = DEFAULT_MAX_SAMPLE_S,
) -> void:
	window_s = maxf(MIN_WINDOW_S, window)
	slow_ratio = maxf(MIN_SLOW_RATIO, ratio)
	ema_tau_s = maxf(MIN_EMA_TAU_S, tau)
	max_sample_s = maxf(MIN_SAMPLE_S, max_sample)
	_ema_hist.resize(HISTORY_SIZE)
	_dt_hist.resize(HISTORY_SIZE)


## Records one frame of [param delta] seconds. Non-positive or NaN deltas are ignored.
func push(delta: float) -> void:
	if is_nan(delta) or delta <= 0.0:
		return
	var dt: float = minf(delta, max_sample_s)
	var ms: float = dt * MS_PER_S
	if _samples == 0:
		_ema_ms = ms
	else:
		var alpha: float = 1.0 - exp(-dt / ema_tau_s)
		_ema_ms += (ms - _ema_ms) * alpha
	_samples += 1
	_ema_hist[_head] = _ema_ms
	_dt_hist[_head] = dt
	_head = (_head + 1) % HISTORY_SIZE
	_count = mini(_count + 1, HISTORY_SIZE)


## Current smoothed frame time in milliseconds (0 before the first sample).
func average_ms() -> float:
	return _ema_ms


## Smoothed frames per second (0 before the first sample).
func average_fps() -> float:
	return MS_PER_S / _ema_ms if _ema_ms > 0.0 else 0.0


## True when the smoothed frame time stayed above [param target_ms] *
## [member slow_ratio] for the last [member window_s] seconds without a break.
func is_struggling(target_ms: float) -> bool:
	if target_ms <= 0.0 or _count == 0:
		return false
	var threshold: float = target_ms * slow_ratio
	var covered: float = 0.0
	for i: int in _count:
		var idx: int = (_head - 1 - i + HISTORY_SIZE) % HISTORY_SIZE
		if _ema_hist[idx] <= threshold:
			return false
		covered += _dt_hist[idx]
		if covered >= window_s:
			return true
	return false


## Forgets all history (after a quality change the old timings are meaningless).
func reset() -> void:
	_ema_ms = 0.0
	_samples = 0
	_head = 0
	_count = 0
