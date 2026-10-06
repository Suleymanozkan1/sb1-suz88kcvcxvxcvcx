class_name GameplaySession
extends Node
## Drives one run: fixed-step simulation, input queue, replay recording,
## presentation time scaling (hit-stop / slow-motion never change outcomes,
## because the sim always advances in whole ticks) and instant restart.

signal run_started(level_id: String)
signal run_ended(result: RunResult)
## [param events] holds [param count] values: (type, entity, value) triples. The
## buffer is reused next frame, so listeners read it during the call only.
signal frame_events(events: PackedInt32Array, count: int)

enum Phase { IDLE, READY, RUNNING, ENDED }

const MAX_STEPS_PER_FRAME: int = 5
const MIN_CLOCK_SCALE: float = 0.5
const MAX_CLOCK_SCALE: float = 2.0
const MAX_PENDING_TAPS: int = 2
const REVIVE_INVULN: float = 1.5

var sim: FluxSim
var sim_level: SimLevel
var level_data: Dictionary = {}
var replay: RunReplay
var phase: Phase = Phase.IDLE
var paused: bool = false
var mode_id: StringName = &"classic"
var revived: bool = false
## Presentation scaling, set by the juice layer.
var time_scale: float = 1.0
## The mode's game clock (Hard 1.12, Zen 0.85, from the mode's "speed_scale"):
## the whole run (movement, sliders, pulse gates, hops, music) plays that much
## faster or slower in real time. The simulation itself is the Classic one, so
## every level stays exactly as solvable as in Classic and replays are
## tick-identical; only the time a player has to react shrinks or grows.
var clock_scale: float = 1.0
var hit_stop: float = 0.0
## 0..1 fraction between the previous and current tick for smooth rendering.
var alpha: float = 0.0
var ready_left: float = 0.0
var total_taps_received: int = 0
## Scripted taps (attract mode / demo / capture). When set, player input is ignored.
var autopilot: PackedInt32Array = PackedInt32Array()
## Lockstep: treat every frame as exactly one tick (deterministic captures).
var lockstep: bool = false
var _autopilot_index: int = 0

var _accum: float = 0.0
var _pending_taps: int = 0
## Tick of the last applied player tap (queued taps keep the replay's minimum
## spacing, so honest runs always pass server validation).
var _last_tap_tick: int = -RunReplay.MIN_TAP_GAP_TICKS
## Ticks of the most recent applied taps (window check, same rule as the server).
var _recent_taps: PackedInt32Array = PackedInt32Array()


## Loads level data; [param modifiers] may contain zen, speed_scale,
## shields_allowed, strict, time_limit, mode (see [ModeCatalog]). Returns false on invalid data.
func load_level(data: Dictionary, modifiers: Dictionary = {}) -> bool:
	if data.is_empty():
		GameLog.error("session", "empty level data")
		return false
	level_data = data
	sim_level = SimLevel.from_dict(data)
	if not sim_level.errors.is_empty():
		GameLog.warn("session", "level %s: %s" % [sim_level.level_id, ", ".join(sim_level.errors)])
	sim = FluxSim.new()
	sim.zen = bool(modifiers.get("zen", false))
	clock_scale = GameplaySession.clock_scale_for(modifiers)
	sim.shields_allowed = bool(modifiers.get("shields_allowed", true))
	sim.strict = bool(modifiers.get("strict", false))
	if modifiers.has("time_limit"):
		sim_level.time_limit = float(modifiers["time_limit"])
	sim.setup(sim_level)
	mode_id = StringName(str(modifiers.get("mode", "classic")))
	_reset_run_state()
	phase = Phase.IDLE
	return true


## Starts after [param ready_seconds] of anticipation (core spawn / reveal).
func begin(ready_seconds: float = 0.6) -> void:
	if sim == null:
		return
	ready_left = ready_seconds
	phase = Phase.READY if ready_seconds > 0.0 else Phase.RUNNING
	paused = false
	if phase == Phase.RUNNING:
		run_started.emit(sim_level.level_id)


## Instant restart: resets the simulation in place (no scene reload).
func restart(ready_seconds: float = 0.35) -> void:
	if sim == null:
		return
	sim.reset()
	_reset_run_state()
	begin(ready_seconds)


func _reset_run_state() -> void:
	replay = RunReplay.new()
	replay.level_id = sim_level.level_id
	replay.level_seed = int(level_data.get("seed", 0))
	replay.mode = mode_id
	revived = false
	_accum = 0.0
	_pending_taps = 0
	_last_tap_tick = -RunReplay.MIN_TAP_GAP_TICKS
	_recent_taps.clear()
	if sim != null:
		sim.clear_events()
	_autopilot_index = 0
	time_scale = 1.0
	hit_stop = 0.0
	alpha = 0.0
	total_taps_received = 0


## The game-clock scale a mode's modifiers ask for (bounded, 1.0 when absent).
static func clock_scale_for(modifiers: Dictionary) -> float:
	var value: float = float(modifiers.get("speed_scale", 1.0))
	return clampf(value, MIN_CLOCK_SCALE, MAX_CLOCK_SCALE) if is_finite(value) else 1.0


func request_tap() -> void:
	if phase == Phase.READY:
		# Tapping during the anticipation beat starts the run immediately.
		ready_left = 0.0
		return
	if phase != Phase.RUNNING or paused or not autopilot.is_empty():
		return
	total_taps_received += 1
	_pending_taps = mini(_pending_taps + 1, MAX_PENDING_TAPS)


func set_paused(value: bool) -> void:
	paused = value


func is_running() -> bool:
	return phase == Phase.RUNNING and not paused


## Continues a failed run once (optional rewarded revive). A revived run can
## never be perfect or submitted to leaderboards.
func revive() -> bool:
	if phase != Phase.ENDED or sim.status != SimConst.Status.FAILED or revived:
		return false
	if not can_revive_reason(sim.fail_reason):
		return false
	revived = true
	if sim.fail_entity >= 0:
		sim.ent_flags[sim.fail_entity] |= FluxSim.FLAG_CONSUMED
	sim.status = SimConst.Status.RUNNING
	sim.fail_reason = SimConst.FailReason.NONE
	sim.invuln = REVIVE_INVULN
	sim.damage += 1
	# Input from before the failure must not fire into the continued run.
	_pending_taps = 0
	_accum = 0.0
	hit_stop = 0.0
	_last_tap_tick = sim.tick
	begin(0.5)
	return true


## Only a collision can be continued: an objective, time-limit or missed-spark
## failure would fail again on the next tick, so no revive is offered for them.
static func can_revive_reason(reason: int) -> bool:
	return reason == SimConst.FailReason.COLLISION or reason == SimConst.FailReason.WRONG_PHASE


func _process(delta: float) -> void:
	if phase == Phase.READY and not paused:
		ready_left -= delta
		if ready_left <= 0.0:
			phase = Phase.RUNNING
			run_started.emit(sim_level.level_id)
		return
	if phase != Phase.RUNNING or paused:
		return
	if hit_stop > 0.0:
		hit_stop -= delta
		return
	_accum += (SimConst.DT if lockstep else delta * clock_scale) * time_scale
	var steps: int = 0
	while _accum >= SimConst.DT and steps < MAX_STEPS_PER_FRAME:
		var tap: bool = _next_tap()
		if tap:
			replay.record_tap(sim.tick)
		# Events gather in the sim's reusable buffer and go out once per frame.
		sim.step(tap)
		_accum -= SimConst.DT
		steps += 1
		if not sim.is_running():
			break
	if steps == MAX_STEPS_PER_FRAME:
		_accum = minf(_accum, SimConst.DT)
	alpha = clampf(_accum / SimConst.DT, 0.0, 1.0)
	if sim.event_len > 0:
		frame_events.emit(sim.events, sim.event_len)
		sim.clear_events()
	if not sim.is_running():
		_end()


func _next_tap() -> bool:
	if not autopilot.is_empty():
		while _autopilot_index < autopilot.size() and autopilot[_autopilot_index] < sim.tick:
			_autopilot_index += 1
		if _autopilot_index < autopilot.size() and autopilot[_autopilot_index] == sim.tick:
			_autopilot_index += 1
			return true
		return false
	if _pending_taps > 0 and sim.tick - _last_tap_tick >= RunReplay.MIN_TAP_GAP_TICKS:
		while not _recent_taps.is_empty() and sim.tick - _recent_taps[0] >= RunReplay.TAP_WINDOW_TICKS:
			_recent_taps.remove_at(0)
		if _recent_taps.size() >= RunReplay.MAX_TAPS_PER_WINDOW:
			# Beyond a human rate: drop the tap rather than record a replay the
			# server would refuse (mashing never helps; no form needs > 12/s).
			_pending_taps -= 1
			return false
		_pending_taps -= 1
		_last_tap_tick = sim.tick
		_recent_taps.append(sim.tick)
		return true
	return false


## Advances the run deterministically without frame timing (tests, autopilot).
func step_ticks(count: int, taps_at: PackedInt32Array = PackedInt32Array()) -> void:
	for _i: int in count:
		if not sim.is_running():
			break
		var tap: bool = taps_at.has(sim.tick)
		if tap:
			replay.record_tap(sim.tick)
		sim.step(tap)
		sim.clear_events()
	if not sim.is_running() and phase != Phase.ENDED:
		_end()


func _end() -> void:
	phase = Phase.ENDED
	replay.end_tick = sim.tick
	var result: RunResult = RunResult.from_sim(sim, level_data, mode_id)
	result.replay = replay
	result.revived = revived
	if revived:
		result.perfect = false
		result.stars = RunResult.compute_stars(result.completed, result.score, result.score_target, false)
		result.grade = RunResult.compute_grade(result.completed, result.stars, false, result.combo_target_met)
	run_ended.emit(result)


func interpolated_d() -> float:
	return lerpf(sim.prev_d, sim.d, alpha)


func interpolated_x() -> float:
	return lerpf(sim.prev_x, sim.x, alpha)


## Height of a launched core above its resting line.
func interpolated_y() -> float:
	return lerpf(sim.prev_y, sim.y, alpha)


func interpolated_time() -> float:
	return (float(sim.tick) + alpha) * SimConst.DT
