class_name LevelGenerator
extends RefCounted
## Deterministic, seed-driven level generator.
##
## Levels are built slot by slot around a *planned* tap sequence. For every slot
## the generator places hazards for the desired core state, then measures the
## real tap window by simulating every candidate tap tick with [FluxSim]. A slot
## is only accepted when its window is at least the tier's fairness minimum, so
## every generated level is solvable by construction. The planned taps are stored
## in the level as `solution`; the validator replays and re-checks them
## independently.

const LEAD_IN: float = 16.0
const TAIL: float = 12.0
const MAX_ATTEMPTS: int = 8
const SLOT_RETRIES: int = 3
const CLEAR_AFTER: float = 0.9
const SPARK_STEP: float = 1.15
const HAZARD_SPARK_GAP: float = 1.1
const MIN_DASH_GAP_FACTOR: float = 1.3
const GENERATOR_VERSION: int = 1

## Codes from [LevelValidator] that make the generator retry with the next
## deterministic attempt (fairness is proven, not assumed).
const RETRY_CODES: PackedStringArray = [
	"impossible_level", "unfair_window", "dead_end", "unreachable_state", "spawn_collision"
]

var spec: LevelSpec
var errors: PackedStringArray = PackedStringArray()
## Run the independent validator on each candidate (off for endless chunks).
var verify_with_validator: bool = true
var _validator: LevelValidator

var _rng: DetRng
var _base: Dictionary = {}
var _entities: Array[Dictionary] = []
var _level: SimLevel
var _checkpoint: FluxSim
var _taps: PackedInt32Array = PackedInt32Array()
var _cursor_d: float = LEAD_IN
var _form: int = SimConst.Form.HOP
var _segment_left: int = 0
var _last_dash_d: float = -INF
var _slot_index: int = 0
var _window_min_seen: float = INF
var _dropped: int = 0


## Generates a complete level dictionary (or an empty dictionary on failure).
func generate(level_spec: LevelSpec) -> Dictionary:
	spec = level_spec
	var slots: int = spec.slot_count
	for attempt: int in MAX_ATTEMPTS:
		errors.clear()
		start(spec, attempt)
		build_slots(slots)
		var level: Dictionary = finish()
		if level.is_empty():
			continue
		var duration: float = float(level["duration"])
		if duration < spec.duration_bounds.x and attempt < MAX_ATTEMPTS - 1:
			slots = int(ceil(float(slots) * spec.duration_bounds.x * 1.08 / maxf(duration, 0.1)))
			continue
		if duration > spec.duration_bounds.y and attempt < MAX_ATTEMPTS - 1:
			slots = maxi(4, int(float(slots) * spec.duration_bounds.y * 0.95 / duration))
			continue
		level["generator"]["attempt"] = attempt
		if verify_with_validator and attempt < MAX_ATTEMPTS - 1 and not _passes_validator(level):
			continue
		return level
	errors.append("generation failed for %s" % spec.id)
	return {}


func _passes_validator(level: Dictionary) -> bool:
	if _validator == null:
		_validator = LevelValidator.new()
		_validator.check_assets = false
	var report: LevelValidator.Report = _validator.validate(level)
	for code: String in report.codes():
		if RETRY_CODES.has(code):
			return false
	return true


## Begins a generation pass (also used directly by endless streaming).
func start(level_spec: LevelSpec, attempt: int = 0) -> void:
	spec = level_spec
	_rng = DetRng.new(spec.seed + attempt * 7919)
	_entities.clear()
	_taps = PackedInt32Array()
	_cursor_d = LEAD_IN
	_form = SimConst.form_from_name(spec.start_form)
	_segment_left = _segment_length()
	_last_dash_d = -INF
	_slot_index = 0
	_window_min_seen = INF
	_base = {
		"id": spec.id,
		"lanes": spec.lanes,
		"speed": snappedf(spec.speed, 0.001),
		"length": SimLevel.ENDLESS_LENGTH,
		"start_form": spec.start_form,
		"start_lane": 0 if spec.lanes == 2 else 1,
		"start_phase": 0,
		"forgiving": spec.forgiving,
		"beat_seconds": snappedf(spec.beat_seconds, 0.0001),
		"modifiers": {"hop_time": spec.hop_time, "speed_ramp": spec.speed_ramp, "ramp_distance": _ramp_distance()},
		"objective": {"type": "reach_end", "target": 0},
	}
	_rebuild_level()
	_checkpoint = _new_sim(_level)


## Fixed ramp distance (independent of final length so planning == playback).
func _ramp_distance() -> float:
	if spec.ramp_distance > 0.0:
		return snappedf(spec.ramp_distance, 0.01)
	return snappedf(LEAD_IN + TAIL + spec.spacing * float(spec.slot_count), 0.01)


func build_slots(count: int) -> void:
	for _i: int in count:
		if _checkpoint == null or not _checkpoint.is_running():
			errors.append("plan died before slot %d" % _slot_index)
			return
		_build_next_slot()
		_slot_index += 1


## Entities committed so far (used by endless streaming).
func committed_entities() -> Array[Dictionary]:
	return _entities


func planned_taps() -> PackedInt32Array:
	return _taps


## Distance up to which slots have been planned (endless streaming frontier).
func frontier() -> float:
	return _cursor_d


## Entities forgotten by [method compact] so far (streaming index offset).
func dropped_count() -> int:
	return _dropped


## Streaming only: forgets up to [param max_drop] of the oldest committed
## entities that lie more than [param behind] metres behind the planning
## checkpoint. They can no longer influence planning (the checkpoint treats
## everything behind the core as resolved), so the course is unchanged while
## the per-slot cost stays bounded however long the run lasts.
func compact(max_drop: int, behind: float) -> int:
	if _checkpoint == null or max_drop <= 0:
		return 0
	var cutoff: float = _checkpoint.d - behind
	var n: int = 0
	while n < max_drop and n < _entities.size() and float(_entities[n].get("d", 0.0)) < cutoff:
		n += 1
	if n == 0:
		return 0
	var kept: Array[Dictionary] = []
	for i: int in range(n, _entities.size()):
		kept.append(_entities[i])
	_entities = kept
	_dropped += n
	_rebuild_level()
	_checkpoint = _retarget(_checkpoint, _level)
	return n


## Level header for an endless stream: the base level fields with no length
## limit and no entities (they are appended chunk by chunk).
func stream_header() -> Dictionary:
	var data: Dictionary = _base.duplicate(true)
	data["endless"] = true
	data["kind"] = "endless"
	data["entities"] = []
	return data


func finish() -> Dictionary:
	if not errors.is_empty():
		return {}
	var length: float = snappedf(_cursor_d + TAIL, 0.01)
	var data: Dictionary = _base.duplicate(true)
	data["length"] = length
	data["entities"] = _entities.duplicate(true)
	# Verify the plan from scratch on the final data; drop sparks the plan misses.
	for _pass: int in 3:
		var check: Dictionary = _replay_plan(data)
		var missed: Array = check["missed_sparks"] as Array
		if not bool(check["completed"]):
			errors.append("plan replay failed: %s" % str(check["reason"]))
			return {}
		if missed.is_empty():
			return _finalize(data, check)
		var kept: Array = []
		var lvl: SimLevel = SimLevel.from_dict(data)
		var miss_d: Dictionary = {}
		for idx: Variant in missed:
			miss_d[snappedf(lvl.e_d[int(idx)], 0.001)] = int(lvl.e_lane[int(idx)])
		for ent: Variant in data["entities"] as Array:
			var e: Dictionary = ent as Dictionary
			var key: float = snappedf(float(e["d"]), 0.001)
			if e["t"] == "spark" and miss_d.has(key) and int(miss_d[key]) == int(e.get("lane", -1)):
				continue
			kept.append(e)
		data["entities"] = kept
	errors.append("could not settle spark placement")
	return {}


func _finalize(data: Dictionary, check: Dictionary) -> Dictionary:
	var lvl: SimLevel = SimLevel.from_dict(data)
	var plan_score: int = int(check["score"])
	var plan_combo: int = int(check["max_combo"])
	var objective: Dictionary = {"type": spec.objective_type, "target": 0}
	match spec.objective_type:
		"collect":
			objective["target"] = maxi(1, int(floor(float(lvl.spark_total) * spec.objective_fraction)))
		"shatter":
			objective["target"] = maxi(1, int(floor(float(int(check["shatters"])) * spec.objective_fraction)))
	if (
		(spec.objective_type == "collect" and lvl.spark_total == 0)
		or (spec.objective_type == "shatter" and int(check["shatters"]) == 0)
	):
		objective = {"type": "reach_end", "target": 0}
	data["objective"] = objective
	data["schema_version"] = 1
	data["number"] = spec.number
	data["world"] = spec.world_id
	data["world_index"] = spec.world_index
	data["local_index"] = spec.local_index
	data["kind"] = spec.kind
	data["tier"] = spec.tier
	data["chapter"] = spec.chapter
	data["chapter_phase"] = spec.chapter_phase
	data["difficulty"] = snappedf(spec.intensity, 0.001)
	data["seed"] = spec.seed
	data["mechanics"] = _mechanics_used(data)
	data["intro_mechanic"] = spec.intro_mechanic
	data["tutorial"] = spec.tutorial
	data["environment"] = spec.environment
	data["visual_theme"] = spec.environment
	data["music"] = spec.music if spec.kind != "boss" else spec.music + "_boss"
	data["spawn"] = {"lead_in": LEAD_IN, "tail": TAIL, "slots": _slot_index, "spacing": snappedf(spec.spacing, 0.001)}
	data["score_target"] = maxi(10, int(floor(float(plan_score) * spec.score_ratio / 10.0)) * 10)
	data["perfect_target"] = lvl.spark_total
	data["combo_target"] = maxi(3, int(floor(float(plan_combo) * spec.combo_ratio)))
	data["unlock"] = {"requires_level": spec.unlock_requires, "requires_stars": spec.unlock_stars}
	data["duration"] = snappedf(float(check["time"]), 0.01)
	data["min_tap_window"] = snappedf(_window_min_seen if _window_min_seen < INF else 9.99, 0.001)
	data["solution"] = {
		"taps": Array(_taps),
		"score": plan_score,
		"max_combo": plan_combo,
		"sparks": int(check["sparks"]),
	}
	if spec.kind != "normal":
		data["special"] = {"name": spec.boss_name, "pattern": spec.pattern}
	data["generator"] = {"version": GENERATOR_VERSION, "attempt": 0}
	return data


func _mechanics_used(data: Dictionary) -> Array:
	var used: Dictionary = {}
	used["spark"] = true
	var forms_seen: Dictionary = {str(data["start_form"]): true}
	for ent: Variant in data["entities"] as Array:
		var e: Dictionary = ent as Dictionary
		match str(e["t"]):
			"barrier":
				used["hop"] = true
			"slider":
				used["slider"] = true
			"pulse_gate":
				used["pulse"] = true
			"phase_gate":
				used["phase"] = true
			"breakable":
				used["dash"] = true
			"current":
				used["current"] = true
			"portal":
				used["portal"] = true
			"form_gate":
				used["form_gate"] = true
				forms_seen[str(e["form"])] = true
			"prism":
				used["prism"] = true
			"shield":
				used["shield"] = true
			"magnet":
				used["magnet"] = true
	for f: String in forms_seen:
		used[f] = true
	if int(data["lanes"]) == 3:
		used["lanes3"] = true
	var mods: Dictionary = data["modifiers"] as Dictionary
	if float(mods["hop_time"]) > SimConst.HOP_TIME + 0.001:
		used["ice"] = true
	if float(mods["speed_ramp"]) > 0.0:
		used["speed_ramp"] = true
	var out: Array = used.keys()
	out.sort()
	return out


# --- Plan replay -------------------------------------------------------------


func _replay_plan(data: Dictionary) -> Dictionary:
	var lvl: SimLevel = SimLevel.from_dict(data)
	var sim: FluxSim = FluxSim.new()
	sim.shields_allowed = false
	sim.record_events = true
	sim.setup(lvl)
	var replay: RunReplay = RunReplay.new()
	replay.tap_ticks = _taps
	replay.play_on(sim)
	var missed: Array = []
	var ev: PackedInt32Array = sim.events
	var i: int = 0
	while i < ev.size():
		if ev[i] == SimConst.EventType.SPARK_MISSED:
			missed.append(ev[i + 1])
		i += 3
	# Sparks still ahead when the run ended count as missed too.
	for j: int in lvl.entity_count():
		if lvl.e_type[j] == SimConst.EntityType.SPARK and (sim.ent_flags[j] & FluxSim.FLAG_CONSUMED) == 0:
			if not missed.has(j):
				missed.append(j)
	return {
		"completed": sim.status == SimConst.Status.COMPLETED,
		"reason": "status=%d fail=%d entity=%d d=%.2f" % [sim.status, sim.fail_reason, sim.fail_entity, sim.d],
		"score": sim.score,
		"max_combo": sim.max_combo,
		"sparks": sim.sparks,
		"shatters": sim.shatters,
		"time": sim.time(),
		"missed_sparks": missed,
	}


# --- Slot construction -------------------------------------------------------


func _segment_length() -> int:
	var base_len: int = maxi(2, spec.form_segment)
	return base_len + _rng.range_int(0, 2) if _rng != null else base_len


func _rebuild_level() -> void:
	var data: Dictionary = _base.duplicate()
	data["entities"] = _entities
	_level = SimLevel.from_dict(data)


func _new_sim(lvl: SimLevel) -> FluxSim:
	var sim: FluxSim = FluxSim.new()
	sim.record_events = false
	sim.shields_allowed = false
	sim.setup(lvl)
	return sim


## Returns a copy of [param source] rebased onto [param lvl]. Inserting sparks
## re-sorts entities, so flags are rebuilt: everything behind the core is done,
## everything ahead is fresh.
func _retarget(source: FluxSim, lvl: SimLevel) -> FluxSim:
	var c: FluxSim = source.clone()
	c.level = lvl
	var n: int = lvl.entity_count()
	var flags: PackedByteArray = PackedByteArray()
	flags.resize(n)
	var cursor: int = n
	var done: int = FluxSim.FLAG_CONSUMED | FluxSim.FLAG_RESOLVED
	for j: int in n:
		var ed: float = lvl.e_d[j]
		if ed < source.d:
			flags[j] = done
		if cursor == n and ed + SimConst.ENTITY_REACH >= source.d - SimConst.CORE_RADIUS:
			cursor = j
	c.ent_flags = flags
	c.cursor = cursor
	return c


func _build_next_slot() -> void:
	var gap: float = spec.spacing * (1.0 + _rng.range_float(-spec.spacing_jitter, spec.spacing_jitter))
	# Keep the *time* between slots, not the distance, when the plan runs fast
	# (speed ramps, heavy surge): decisions never get closer than designed.
	gap *= maxf(1.0, _checkpoint.speed / maxf(spec.speed, 0.1))
	# Form segment boundaries become form gates.
	if spec.forms.size() > 1:
		_segment_left -= 1
		if _segment_left <= 0:
			_place_form_gate(gap)
			_segment_left = _segment_length()
			return
	var specials_roll: float = _rng.next_float()
	if _form == SimConst.Form.HOP and specials_roll < spec.current_chance and _slot_index > 1:
		if _try_current_slot(gap):
			return
	elif _form == SimConst.Form.HOP and specials_roll < spec.current_chance + spec.portal_chance and _slot_index > 1:
		if _try_portal_slot(gap):
			return
	for retry: int in SLOT_RETRIES:
		var change: bool = _rng.chance(spec.change_prob) or (_slot_index == 0 and spec.tutorial)
		if _try_slot(gap * (1.0 + 0.25 * float(retry)), change):
			return
	# Fallback: a calm slot that never needs a tap.
	if not _try_slot(gap * 1.6, false):
		_advance_empty(gap)


func _advance_empty(gap: float) -> void:
	_cursor_d += gap
	_checkpoint.advance_to_distance(_cursor_d)


## Builds one regular slot. Returns false if no fair tap window exists.
func _try_slot(gap: float, change: bool) -> bool:
	var d_slot: float = snappedf(_cursor_d + gap, 0.01)
	if _form == SimConst.Form.DASH and change and d_slot - _last_dash_d < _min_dash_gap():
		change = false
	var target: Dictionary = _desired_state(change)
	var slot_entities: Array[Dictionary] = _slot_hazards(d_slot, target, change)
	if slot_entities.is_empty():
		return false
	var trial: Array[Dictionary] = _entities.duplicate()
	trial.append_array(slot_entities)
	var trial_level: SimLevel = _level_with(trial)
	var tap_tick: int = -1
	if bool(target["needs_tap"]):
		var window: Dictionary = _measure_window(trial_level, d_slot, target)
		if float(window["length"]) < spec.min_window:
			return false
		tap_tick = int(window["center"])
		_window_min_seen = minf(_window_min_seen, float(window["length"]))
	else:
		if not _survives_without_tap(trial_level, d_slot, target):
			return false
	var old_lane: int = _checkpoint.lane
	var prev_d: float = _cursor_d
	_commit(slot_entities, trial_level, tap_tick, d_slot)
	if _form == SimConst.Form.DASH and bool(target["needs_tap"]):
		_last_dash_d = d_slot
	if tap_tick >= 0 and spec.prism_chance > 0.0 and _form == SimConst.Form.HOP:
		_maybe_place_prism(prev_d, d_slot, old_lane)
	return true


func _min_dash_gap() -> float:
	return SimConst.DASH_COOLDOWN * spec.speed * SimConst.DASH_SPEED_FACTOR * MIN_DASH_GAP_FACTOR


func _level_with(entities: Array[Dictionary]) -> SimLevel:
	var data: Dictionary = _base.duplicate()
	data["entities"] = entities
	return SimLevel.from_dict(data)


## Decides what the core should look like when it reaches the next slot.
func _desired_state(change: bool) -> Dictionary:
	var cp: FluxSim = _checkpoint
	var target: Dictionary = {"lane": cp.lane, "phase": cp.phase, "heavy": cp.heavy, "needs_tap": change}
	match _form:
		SimConst.Form.HOP:
			if change:
				var nl: int
				if spec.lanes == 2:
					nl = 1 - cp.lane
				else:
					nl = cp.lane + cp.hop_dir
					if nl < 0 or nl >= spec.lanes:
						nl = cp.lane - cp.hop_dir
				target["lane"] = nl
		SimConst.Form.PHASE:
			if change:
				target["phase"] = 1 - cp.phase
		SimConst.Form.SURGE:
			if change:
				target["heavy"] = not cp.heavy
	return target


func _pick_hazard(allowed: Array[String]) -> String:
	var weights: Dictionary = {}
	for name: String in allowed:
		var w: float = float(spec.hazards.get(name, 0.0))
		if w > 0.0:
			weights[name] = w
	if weights.is_empty():
		return allowed[0]
	return str(_rng.pick_weighted(weights))


func _arrival_time(d_slot: float, target: Dictionary) -> float:
	# Constant-speed forms: the arrival time does not depend on tap timing.
	var probe: FluxSim = _checkpoint.clone()
	if bool(target["needs_tap"]) and _form == SimConst.Form.SURGE:
		probe.step(true)
	probe.advance_to_distance(d_slot)
	return probe.time()


func _slot_hazards(d_slot: float, target: Dictionary, change: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lanes: int = spec.lanes
	var path_lane: int = int(target["lane"])
	match _form:
		SimConst.Form.HOP:
			var blocked: Array[int] = []
			if change:
				blocked.append(_checkpoint.lane)
			for l: int in lanes:
				if l != path_lane and not blocked.has(l):
					if blocked.is_empty() or _rng.chance(spec.density * 0.6):
						blocked.append(l)
			var t_arrive: float = _arrival_time(d_slot, target)
			var slider_used: bool = false
			for l: int in blocked:
				# One slider per slot, only between adjacent lanes, so its sweep
				# never crosses another blocked lane.
				var can_slide: bool = not slider_used and absi(l - path_lane) == 1
				var hazard: Dictionary = _hop_hazard(d_slot, l, path_lane, t_arrive, can_slide)
				if str(hazard["t"]) == "slider":
					slider_used = true
				elif str(hazard["t"]) == "phase_gate":
					# A phase gate spans every lane: it replaces the other blocks.
					return [hazard] as Array[Dictionary]
				out.append(hazard)
		SimConst.Form.PHASE:
			out.append({"t": "phase_gate", "d": d_slot, "color": int(target["phase"])})
		SimConst.Form.DASH:
			if change:
				out.append({"t": "breakable", "d": d_slot, "lane": path_lane})
			for l: int in lanes:
				if l == path_lane:
					continue
				if change and _rng.chance(spec.cluster_chance):
					out.append({"t": "breakable", "d": d_slot, "lane": l})
				else:
					out.append({"t": "barrier", "d": d_slot, "lanes": [l]})
		SimConst.Form.SURGE:
			var t_arr: float = _arrival_time(d_slot, target)
			var kind: String = _pick_hazard(["pulse_gate", "slider"] as Array[String])
			var slider_lane: int = -1
			if kind == "slider" and lanes >= 2:
				var slider: Dictionary = _surge_slider(d_slot, path_lane, t_arr)
				slider_lane = int(slider["from"])
				out.append(slider)
			else:
				out.append(_timed_pulse(d_slot, [path_lane], t_arr, true))
			for l: int in lanes:
				if l != path_lane and l != slider_lane:
					out.append({"t": "barrier", "d": d_slot, "lanes": [l]})
	return out


func _hop_hazard(d_slot: float, lane: int, path_lane: int, t_arrive: float, allow_slider: bool) -> Dictionary:
	var allowed: Array[String] = ["barrier", "pulse_gate"]
	if allow_slider:
		allowed.append("slider")
	if spec.forms.has("phase"):
		allowed.append("phase_gate")
	var kind: String = _pick_hazard(allowed)
	match kind:
		"slider":
			var beats: float = [2.0, 3.0, 4.0][_rng.range_int(0, 2)] as float
			var period: float = beats * spec.beat_seconds
			# Sit on the blocked lane exactly when the core arrives.
			var offset: float = SimConst.wrap01(-t_arrive / period)
			return {
				"t": "slider",
				"d": d_slot,
				"from": lane,
				"to": path_lane,
				"period": snappedf(period, 0.0001),
				"offset": snappedf(offset, 0.0001),
			}
		"pulse_gate":
			return _timed_pulse(d_slot, [lane], t_arrive, false)
		"phase_gate":
			# Spans every lane; passable only in the phase the core already has.
			return {"t": "phase_gate", "d": d_slot, "color": _checkpoint.phase}
	return {"t": "barrier", "d": d_slot, "lanes": [lane]}


## A pulse gate whose open (or closed) window is centred on the arrival time.
func _timed_pulse(d_slot: float, lanes: Array, t_arrive: float, open_at_arrival: bool) -> Dictionary:
	var beats: float = [1.0, 2.0][_rng.range_int(0, 1)] as float
	var period: float = beats * spec.beat_seconds * 2.0
	var open_frac: float = 0.5
	var center_u: float = open_frac * 0.5 if open_at_arrival else open_frac + (1.0 - open_frac) * 0.5
	var offset: float = SimConst.wrap01(center_u - t_arrive / period)
	return {
		"t": "pulse_gate",
		"d": d_slot,
		"lanes": lanes,
		"period": snappedf(period, 0.0001),
		"open": open_frac,
		"offset": snappedf(offset, 0.0001),
	}


func _surge_slider(d_slot: float, path_lane: int, t_arrive: float) -> Dictionary:
	var other: int = 1 if path_lane == 0 else path_lane - 1
	var period: float = 4.0 * spec.beat_seconds
	var offset: float = SimConst.wrap01(-t_arrive / period)
	return {
		"t": "slider",
		"d": d_slot,
		"from": other,
		"to": path_lane,
		"period": snappedf(period, 0.0001),
		"offset": snappedf(offset, 0.0001),
	}


## Simulates every candidate tap tick between the checkpoint and the slot and
## returns the longest contiguous run of ticks that clears the slot.
func _measure_window(lvl: SimLevel, d_slot: float, target: Dictionary) -> Dictionary:
	var walker: FluxSim = _retarget(_checkpoint, lvl)
	var end_d: float = d_slot + CLEAR_AFTER
	var best_start: int = -1
	var best_len: int = 0
	var run_start: int = -1
	var run_len: int = 0
	var guard: int = 0
	while walker.is_running() and walker.d < d_slot and guard < 2000:
		var trial: FluxSim = walker.clone()
		trial.step(true)
		trial.advance_to_distance(end_d)
		var ok: bool = trial.is_running() and _state_matches(trial, target)
		if ok:
			if run_len == 0:
				run_start = walker.tick
			run_len += 1
			if run_len > best_len:
				best_len = run_len
				best_start = run_start
		else:
			run_len = 0
		walker.step(false)
		guard += 1
	return {
		"length": float(best_len) * SimConst.DT,
		"center": best_start + best_len / 2,
		"start": best_start,
	}


func _state_matches(sim: FluxSim, target: Dictionary) -> bool:
	match _form:
		SimConst.Form.HOP:
			return sim.lane == int(target["lane"])
		SimConst.Form.PHASE:
			return sim.phase == int(target["phase"])
		SimConst.Form.SURGE:
			return sim.heavy == bool(target["heavy"])
		SimConst.Form.DASH:
			return sim.shatters > _checkpoint.shatters
	return true


func _survives_without_tap(lvl: SimLevel, d_slot: float, target: Dictionary) -> bool:
	var probe: FluxSim = _retarget(_checkpoint, lvl)
	probe.advance_to_distance(d_slot + CLEAR_AFTER)
	return probe.is_running() and _state_matches_no_tap(probe, target)


func _state_matches_no_tap(sim: FluxSim, target: Dictionary) -> bool:
	if _form == SimConst.Form.DASH:
		return true
	return _state_matches(sim, target)


func _commit(slot_entities: Array[Dictionary], trial_level: SimLevel, tap_tick: int, d_slot: float) -> void:
	var start_tick: int = _checkpoint.tick
	var path: FluxSim = _retarget(_checkpoint, trial_level)
	var samples: Array[Vector3] = []
	var guard: int = 0
	while path.is_running() and path.d < d_slot + CLEAR_AFTER and guard < 4000:
		path.step(path.tick == tap_tick)
		samples.append(Vector3(path.d, path.x, path.hop_t))
		guard += 1
	if not path.is_running():
		errors.append("commit failed at slot %d" % _slot_index)
		return
	if tap_tick >= 0:
		_taps.append(tap_tick)
	var prev_d: float = _cursor_d
	_entities.append_array(slot_entities)
	_add_path_pickups(samples, prev_d, d_slot, path.phase, start_tick)
	_rebuild_level()
	_checkpoint = _retarget(path, _level)
	_cursor_d = d_slot


## Sparks (and occasional pickups) follow the planned path where the core is
## settled in a lane and clear of hazards — they double as path guidance.
func _add_path_pickups(samples: Array[Vector3], from_d: float, to_d: float, phase: int, _start_tick: int) -> void:
	if samples.is_empty():
		return
	var next_d: float = from_d + HAZARD_SPARK_GAP
	var colored: bool = _form == SimConst.Form.PHASE
	var lanes: int = spec.lanes
	for s: Vector3 in samples:
		if s.x < next_d:
			continue
		if s.x > to_d - HAZARD_SPARK_GAP:
			break
		if s.z < 1.0:
			continue
		var lane: int = _lane_of(s.y, lanes)
		if absf(s.y - SimConst.lane_x(lane, lanes)) > 0.05:
			continue
		next_d = s.x + SPARK_STEP
		if not _rng.chance(spec.spark_density):
			continue
		var d: float = snappedf(s.x, 0.01)
		var roll: float = _rng.next_float()
		if roll < spec.shield_chance * 0.25:
			_entities.append({"t": "shield", "d": d, "lane": lane})
		elif roll < (spec.shield_chance + spec.magnet_chance) * 0.25:
			_entities.append({"t": "magnet", "d": d, "lane": lane})
		else:
			var spark: Dictionary = {"t": "spark", "d": d, "lane": lane}
			if colored:
				spark["color"] = phase
			_entities.append(spark)


static func _lane_of(x: float, lanes: int) -> int:
	var best: int = 0
	var best_dist: float = INF
	for l: int in lanes:
		var dist: float = absf(x - SimConst.lane_x(l, lanes))
		if dist < best_dist:
			best_dist = dist
			best = l
	return best


## Risk/reward: a prism on the lane the core is leaving, reachable only by
## delaying the hop towards the late edge of the tap window.
func _maybe_place_prism(prev_d: float, d_slot: float, old_lane: int) -> void:
	if not _rng.chance(spec.prism_chance):
		return
	var probe_d: float = d_slot - SimConst.HAZARD_HALF_DEPTH - SimConst.CORE_RADIUS - 1.0
	if probe_d < prev_d + 1.5:
		return
	_entities.append({"t": "prism", "d": snappedf(probe_d, 0.01), "lane": old_lane})
	_rebuild_level()
	_checkpoint = _retarget(_checkpoint, _level)


func _place_form_gate(gap: float) -> void:
	var options: Dictionary = {}
	for f: String in spec.forms:
		if SimConst.form_from_name(f) != _form and float(spec.forms[f]) > 0.0:
			options[f] = float(spec.forms[f])
	if options.is_empty():
		_advance_empty(gap)
		return
	var next_form: String = str(_rng.pick_weighted(options))
	var d_gate: float = snappedf(_cursor_d + gap * 0.8, 0.01)
	var gate: Dictionary = {"t": "form_gate", "d": d_gate, "form": next_form}
	var trial: Array[Dictionary] = _entities.duplicate()
	trial.append(gate)
	var lvl: SimLevel = _level_with(trial)
	_commit([gate], lvl, -1, d_gate)
	_form = SimConst.form_from_name(next_form)


func _try_current_slot(gap: float) -> bool:
	var d_slot: float = snappedf(_cursor_d + gap, 0.01)
	var lane: int = _checkpoint.lane
	var to: int
	if spec.lanes == 2:
		to = 1 - lane
	else:
		to = lane + (1 if _rng.chance(0.5) else -1)
		if to < 0 or to >= spec.lanes:
			to = lane - (to - lane)
	var ent: Dictionary = {"t": "current", "d": d_slot, "lanes": [lane], "to": to}
	var trial: Array[Dictionary] = _entities.duplicate()
	trial.append(ent)
	var lvl: SimLevel = _level_with(trial)
	var probe: FluxSim = _retarget(_checkpoint, lvl)
	probe.advance_to_distance(d_slot + CLEAR_AFTER)
	if not probe.is_running() or probe.lane != to:
		return false
	_commit([ent], lvl, -1, d_slot)
	_reserve_reaction_room()
	return true


func _try_portal_slot(gap: float) -> bool:
	var d_slot: float = snappedf(_cursor_d + gap, 0.01)
	var lane: int = _checkpoint.lane
	var to: int = 1 - lane if spec.lanes == 2 else (0 if lane != 0 else spec.lanes - 1)
	var portal: Dictionary = {"t": "portal", "d": d_slot, "lane": lane, "to": to}
	var wall: Dictionary = {"t": "barrier", "d": snappedf(d_slot + 1.4, 0.01), "lanes": [lane]}
	var trial: Array[Dictionary] = _entities.duplicate()
	trial.append(portal)
	trial.append(wall)
	var lvl: SimLevel = _level_with(trial)
	var probe: FluxSim = _retarget(_checkpoint, lvl)
	probe.advance_to_distance(d_slot + 1.4 + CLEAR_AFTER)
	if not probe.is_running() or probe.lane != to:
		return false
	_commit([portal, wall], lvl, -1, d_slot + 1.4)
	_reserve_reaction_room()
	return true


## After a forced move the player gets at least the reaction time (plus the
## tier window) before the next slot can demand an input.
func _reserve_reaction_room() -> void:
	var room: float = spec.speed * (1.0 + spec.speed_ramp) * (LevelValidator.REACTION_TIME + spec.min_window)
	_cursor_d += room
	_checkpoint.advance_to_distance(_cursor_d - spec.spacing * 0.5)
