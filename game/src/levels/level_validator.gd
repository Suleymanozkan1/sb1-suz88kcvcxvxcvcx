class_name LevelValidator
extends RefCounted
## Validates level data. Every rule is independent of the generator so broken,
## unfair or impossible data is caught at build/test time (CI fails on errors).
##
## Error codes (stable, used by tests and reports):
##   schema, missing_objective, invalid_mechanic, missing_asset, spawn_collision,
##   broken_trigger, invalid_sequence, impossible_level, unreachable_state,
##   dead_end, unfair_window, duration, solver

const MECHANICS_PATH: String = "res://data/mechanics.json"
const CURVE_PATH: String = "res://data/difficulty/curve.json"
const MUSIC_DIR: String = "res://assets/audio/music"
const VALID_KINDS: PackedStringArray = ["normal", "challenge", "boss", "daily", "endless"]
const VALID_OBJECTIVES: PackedStringArray = ["reach_end", "collect", "shatter", "survive"]
const MIN_FIRST_HAZARD_D: float = 10.0
const REACTION_TIME: float = 0.3
## No tap may be due sooner than this after GO (a tap during READY only starts
## the run, and READY after a restart is short).
const FIRST_DECISION_S: float = 1.0
const WINDOW_SCAN_TICKS: int = 90
const MAX_SPEED: float = 40.0
const PRISM_TAPS_CONSIDERED: int = 3
## A launch pad needs this much room to the nearest blocker in its lane.
const PAD_CLEARANCE: float = 0.8
const MIN_GRAVITY_SPAN: float = 2.0
## Smallest |g − 1| that is worth a gravity well (smaller is unreadable).
const MIN_GRAVITY_CHANGE: float = 0.1

var mechanics_catalog: Dictionary = {}
var tiers: Dictionary = {}
var duration_bounds: Dictionary = {}
var world_ids: PackedStringArray = PackedStringArray()
var check_assets: bool = true
var run_solver: bool = false
var window_tolerance_ticks: int = 1


class Report:
	extends RefCounted
	var level_id: String = ""
	var errors: Array[Dictionary] = []
	var warnings: Array[Dictionary] = []
	var stats: Dictionary = {}

	func error(code: String, message: String) -> void:
		errors.append({"code": code, "message": message})

	func warn(code: String, message: String) -> void:
		warnings.append({"code": code, "message": message})

	func ok() -> bool:
		return errors.is_empty()

	func codes() -> PackedStringArray:
		var out: PackedStringArray = PackedStringArray()
		for e: Dictionary in errors:
			out.append(str(e["code"]))
		return out


func _init(catalog: WorldCatalog = null) -> void:
	mechanics_catalog = JsonIO.read_dict(MECHANICS_PATH)
	var curve: Dictionary = JsonIO.read_dict(CURVE_PATH)
	for t: Variant in curve.get("tiers", []) as Array:
		var tier: Dictionary = t as Dictionary
		tiers[str(tier["id"])] = tier
	duration_bounds = curve.get("duration_bounds", {}) as Dictionary
	var c: WorldCatalog = catalog if catalog != null else WorldCatalog.load_default()
	for w: Dictionary in c.worlds:
		world_ids.append(str(w.get("id", "")))


func validate(data: Dictionary) -> Report:
	var r: Report = Report.new()
	r.level_id = str(data.get("id", "?"))
	_check_schema(data, r)
	if not r.ok():
		return r
	_check_mechanics(data, r)
	_check_assets(data, r)
	_check_objective(data, r)
	_check_entities(data, r)
	_check_sequence(data, r)
	if not r.ok():
		return r
	_check_solution(data, r)
	if r.ok():
		_check_windows(data, r)
		_check_forced_moves(data, r)
		_check_prisms(data, r)
		_check_duration(data, r)
	if r.ok() and run_solver:
		_check_solver(data, r)
	return r


# --- schema -------------------------------------------------------------------


func _check_schema(data: Dictionary, r: Report) -> void:
	var required: Dictionary[String, Variant.Type] = {
		"id": TYPE_STRING,
		"number": TYPE_FLOAT,
		"world": TYPE_STRING,
		"kind": TYPE_STRING,
		"tier": TYPE_STRING,
		"difficulty": TYPE_FLOAT,
		"seed": TYPE_FLOAT,
		"lanes": TYPE_FLOAT,
		"speed": TYPE_FLOAT,
		"length": TYPE_FLOAT,
		"start_form": TYPE_STRING,
		"entities": TYPE_ARRAY,
		"objective": TYPE_DICTIONARY,
		"mechanics": TYPE_ARRAY,
		"score_target": TYPE_FLOAT,
		"perfect_target": TYPE_FLOAT,
		"combo_target": TYPE_FLOAT,
		"environment": TYPE_STRING,
		"music": TYPE_STRING,
		"visual_theme": TYPE_STRING,
		"unlock": TYPE_DICTIONARY,
		"spawn": TYPE_DICTIONARY,
		"modifiers": TYPE_DICTIONARY,
		"solution": TYPE_DICTIONARY,
	}
	for key: String in required:
		if not data.has(key):
			r.error("schema", "missing field '%s'" % key)
			continue
		var want: int = required[key]
		var got: int = typeof(data[key])
		var numeric_ok: bool = want == TYPE_FLOAT and (got == TYPE_INT or got == TYPE_FLOAT)
		if got != want and not numeric_ok:
			r.error("schema", "field '%s' has wrong type" % key)
	if not r.ok():
		return
	if not VALID_KINDS.has(str(data["kind"])):
		r.error("schema", "invalid kind '%s'" % str(data["kind"]))
	if str(data["kind"]) in ["normal", "challenge", "boss"] and not tiers.has(str(data["tier"])):
		r.error("schema", "invalid tier '%s'" % str(data["tier"]))
	var lanes: int = int(data["lanes"])
	if lanes < 2 or lanes > 3:
		r.error("schema", "lanes must be 2 or 3")
	var speed: float = float(data["speed"])
	var ramp: float = float((data["modifiers"] as Dictionary).get("speed_ramp", 0.0))
	var top: float = speed * (1.0 + ramp) * SimConst.DASH_SPEED_FACTOR * _max_gravity_speed_factor(data)
	if speed < 3.0 or top > MAX_SPEED:
		r.error("schema", "speed out of range: %.2f" % speed)
	var hop_time: float = float((data["modifiers"] as Dictionary).get("hop_time", SimConst.HOP_TIME))
	if hop_time < 0.08 or hop_time > 0.3:
		r.error("schema", "hop_time out of range")
	if float(data["length"]) <= MIN_FIRST_HAZARD_D:
		r.error("schema", "length too short")
	if SimConst.form_from_name(str(data["start_form"])) < 0:
		r.error("invalid_mechanic", "unknown start_form '%s'" % str(data["start_form"]))


## Largest forward-speed factor any gravity well of the level applies.
static func _max_gravity_speed_factor(data: Dictionary) -> float:
	var best: float = 1.0
	for raw: Variant in data.get("entities", []) as Array:
		if typeof(raw) == TYPE_DICTIONARY and str((raw as Dictionary).get("t", "")) == "gravity":
			var g: float = clampf(float((raw as Dictionary).get("g", 1.0)), SimConst.GRAVITY_MIN, SimConst.GRAVITY_MAX)
			best = maxf(best, SimConst.gravity_speed_factor(g))
	return best


# --- mechanics / assets / objective -------------------------------------------


func _check_mechanics(data: Dictionary, r: Report) -> void:
	var known: Dictionary = mechanics_catalog.get("mechanics", {}) as Dictionary
	var forms: Array = mechanics_catalog.get("forms", []) as Array
	var declared: Dictionary[String, bool] = {}
	for m: Variant in data["mechanics"] as Array:
		var name: String = str(m)
		declared[name] = true
		if not known.has(name) and not forms.has(name):
			r.error("invalid_mechanic", "unknown mechanic '%s'" % name)
	var needs: Dictionary[String, String] = {
		"slider": "slider",
		"pulse_gate": "pulse",
		"phase_gate": "phase",
		"current": "current",
		"portal": "portal",
		"form_gate": "form_gate",
		"prism": "prism",
		"shield": "shield",
		"magnet": "magnet",
		"gravity": "gravity",
		"launch_pad": "launch",
		"plate": "stack",
	}
	for raw: Variant in data["entities"] as Array:
		var t: String = str((raw as Dictionary).get("t", ""))
		# Glass breaks under a dash or under a full stack of plates.
		if t == "breakable" and not declared.has("dash") and not declared.has("stack"):
			r.error("invalid_mechanic", "entity 'breakable' requires undeclared mechanic 'dash' or 'stack'")
		if needs.has(t) and not declared.has(needs[t]):
			r.error("invalid_mechanic", "entity '%s' requires undeclared mechanic '%s'" % [t, needs[t]])
		if t == "form_gate":
			var f: String = str((raw as Dictionary).get("form", ""))
			if not forms.has(f):
				r.error("invalid_mechanic", "form gate to unknown form '%s'" % f)
			elif not declared.has(f):
				r.error("invalid_mechanic", "form '%s' used but not declared" % f)


func _check_assets(data: Dictionary, r: Report) -> void:
	for key: String in ["environment", "visual_theme"]:
		var v: String = str(data[key])
		if not world_ids.has(v):
			r.error("missing_asset", "%s '%s' is not a known world" % [key, v])
	if check_assets:
		var music: String = str(data["music"])
		if not ResourceLoader.exists(MUSIC_DIR.path_join(music + ".wav")):
			r.error("missing_asset", "music track '%s' not found" % music)


func _check_objective(data: Dictionary, r: Report) -> void:
	var obj: Dictionary = data["objective"] as Dictionary
	var type: String = str(obj.get("type", ""))
	if type.is_empty() or not VALID_OBJECTIVES.has(type):
		r.error("missing_objective", "objective type '%s' invalid" % type)
		return
	var lvl: SimLevel = SimLevel.from_dict(data)
	var target: int = int(obj.get("target", 0))
	if type == "collect" and (target <= 0 or target > lvl.spark_total):
		r.error("missing_objective", "collect target %d not achievable (%d sparks)" % [target, lvl.spark_total])
	if type == "shatter" and (target <= 0 or target > lvl.breakable_total):
		r.error("missing_objective", "shatter target %d not achievable" % target)
	if int(data["score_target"]) <= 0:
		r.error("missing_objective", "score_target must be > 0")
	if int(data["perfect_target"]) != lvl.spark_total:
		r.error("missing_objective", "perfect_target must equal spark count")
	if int(data["combo_target"]) <= 0:
		r.error("missing_objective", "combo_target must be > 0")


# --- entities -----------------------------------------------------------------


func _check_entities(data: Dictionary, r: Report) -> void:
	var lanes: int = int(data["lanes"])
	var length: float = float(data["length"])
	var blocking: Array[Dictionary] = []
	var collectibles: Array[Dictionary] = []
	var pads: Array[Dictionary] = []
	var zones: Array[Dictionary] = []
	var first_hazard: float = INF
	for raw: Variant in data["entities"] as Array:
		if typeof(raw) != TYPE_DICTIONARY:
			r.error("schema", "entity is not an object")
			continue
		var e: Dictionary = raw as Dictionary
		var t: String = str(e.get("t", ""))
		if SimConst.entity_type_from_name(t) < 0:
			r.error("invalid_mechanic", "unknown entity type '%s'" % t)
			continue
		if not e.has("d"):
			r.error("schema", "entity without distance")
			continue
		var d: float = float(e["d"])
		if d < 0.0 or d >= length:
			r.error("spawn_collision", "%s at d=%.2f outside level (length %.2f)" % [t, d, length])
		_check_entity_fields(e, t, lanes, r)
		var tid: int = SimConst.entity_type_from_name(t)
		if SimConst.is_hazard(tid):
			first_hazard = minf(first_hazard, d)
			blocking.append(e)
		elif (
			tid
			in [
				SimConst.EntityType.SPARK,
				SimConst.EntityType.PRISM,
				SimConst.EntityType.SHIELD,
				SimConst.EntityType.MAGNET,
				SimConst.EntityType.PLATE
			]
		):
			collectibles.append(e)
		elif tid == SimConst.EntityType.LAUNCH_PAD:
			first_hazard = minf(first_hazard, d)
			pads.append(e)
		elif tid == SimConst.EntityType.GRAVITY:
			zones.append(e)
	if first_hazard < MIN_FIRST_HAZARD_D:
		r.error("spawn_collision", "first hazard at d=%.2f gives no reaction time" % first_hazard)
	_check_overlaps(blocking, collectibles, lanes, r)
	_check_pads(pads, blocking, lanes, r)
	_check_zones(zones, length, r)


## A launch pad needs clear floor around it in its lane (no take-off from
## inside a block).
func _check_pads(pads: Array[Dictionary], blocking: Array[Dictionary], lanes: int, r: Report) -> void:
	for p: Dictionary in pads:
		var dp: float = float(p["d"])
		var lp: int = int(p.get("lane", 0))
		for h: Dictionary in blocking:
			if absf(float(h["d"]) - dp) < PAD_CLEARANCE and _lanes_of(h, lanes).has(lp):
				r.error("spawn_collision", "launch pad at d=%.2f lane %d too close to %s" % [dp, lp, h["t"]])
				break


## Gravity wells end inside the level and never overlap each other.
func _check_zones(zones: Array[Dictionary], length: float, r: Report) -> void:
	# Hand-made levels may list wells in any order: compare them along the shaft.
	var ordered: Array[Dictionary] = zones.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	var last_end: float = -INF
	for z: Dictionary in ordered:
		var start: float = float(z["d"])
		var end: float = start + float(z.get("span", 0.0))
		if end > length:
			r.error("spawn_collision", "gravity well at d=%.2f ends beyond the level" % start)
		if start < last_end:
			r.error("spawn_collision", "gravity well at d=%.2f overlaps the previous one" % start)
		last_end = maxf(last_end, end)


func _check_entity_fields(e: Dictionary, t: String, lanes: int, r: Report) -> void:
	match t:
		"barrier", "pulse_gate", "current":
			var ls: Variant = e.get("lanes", null)
			if typeof(ls) != TYPE_ARRAY or (ls as Array).is_empty():
				r.error("broken_trigger", "%s without lanes" % t)
			else:
				for l: Variant in ls as Array:
					if int(l) < 0 or int(l) >= lanes:
						r.error("broken_trigger", "%s lane %d out of range" % [t, int(l)])
		"spark", "prism", "shield", "magnet", "breakable", "portal", "launch_pad", "plate":
			var lane: int = int(e.get("lane", -1))
			if lane < 0 or lane >= lanes:
				r.error("broken_trigger", "%s lane %d out of range" % [t, lane])
	match t:
		"gravity":
			var g: float = float(e.get("g", 1.0))
			if float(e.get("span", 0.0)) < MIN_GRAVITY_SPAN:
				r.error("broken_trigger", "gravity well span too short")
			if g < SimConst.GRAVITY_MIN or g > SimConst.GRAVITY_MAX or absf(g - 1.0) < MIN_GRAVITY_CHANGE:
				r.error("broken_trigger", "gravity factor %.2f invalid" % g)
		"slider":
			var a: int = int(e.get("from", -1))
			var b: int = int(e.get("to", -1))
			if a < 0 or a >= lanes or b < 0 or b >= lanes or a == b:
				r.error("broken_trigger", "slider lanes invalid (%d->%d)" % [a, b])
			if float(e.get("period", 0.0)) < 0.3:
				r.error("broken_trigger", "slider period too short")
		"pulse_gate":
			var open: float = float(e.get("open", 0.0))
			if float(e.get("period", 0.0)) < 0.3 or open < 0.2 or open > 0.85:
				r.error("broken_trigger", "pulse gate timing invalid")
		"current":
			var to: int = int(e.get("to", -1))
			if to < 0 or to >= lanes:
				r.error("broken_trigger", "current target lane invalid")
			elif (e.get("lanes", []) as Array).has(to):
				r.error("broken_trigger", "current pushes into its own lane")
		"portal":
			var pto: int = int(e.get("to", -1))
			if pto < 0 or pto >= lanes or pto == int(e.get("lane", -1)):
				r.error("broken_trigger", "portal target invalid")
		"phase_gate", "spark":
			var c: int = int(e.get("color", -1 if t == "spark" else 0))
			if c < -1 or c > 1 or (t == "phase_gate" and c < 0):
				r.error("broken_trigger", "%s color invalid" % t)


func _lanes_of(e: Dictionary, lanes: int) -> Array[int]:
	var out: Array[int] = []
	var t: String = str(e["t"])
	if t == "phase_gate":
		for l: int in lanes:
			out.append(l)
	elif t == "slider":
		var a: int = int(e.get("from", 0))
		var b: int = int(e.get("to", 0))
		for l: int in range(mini(a, b), maxi(a, b) + 1):
			out.append(l)
	elif e.has("lanes"):
		for l: Variant in e["lanes"] as Array:
			out.append(int(l))
	else:
		out.append(int(e.get("lane", 0)))
	return out


func _check_overlaps(blocking: Array[Dictionary], collectibles: Array[Dictionary], lanes: int, r: Report) -> void:
	var min_gap: float = SimConst.HAZARD_HALF_DEPTH * 2.0
	for i: int in blocking.size():
		var a: Dictionary = blocking[i]
		var da: float = float(a["d"])
		var la: Array[int] = _lanes_of(a, lanes)
		for j: int in range(i + 1, blocking.size()):
			var b: Dictionary = blocking[j]
			var db: float = float(b["d"])
			if absf(db - da) >= min_gap:
				continue
			for l: int in _lanes_of(b, lanes):
				if la.has(l):
					r.error("spawn_collision", "%s and %s overlap at d=%.2f lane %d" % [a["t"], b["t"], da, l])
					break
	for c: Dictionary in collectibles:
		var dc: float = float(c["d"])
		var lc: int = int(c.get("lane", 0))
		for h: Dictionary in blocking:
			if str(h["t"]) == "phase_gate":
				continue
			if absf(float(h["d"]) - dc) < SimConst.HAZARD_HALF_DEPTH + 0.35 and _lanes_of(h, lanes).has(lc):
				r.error("spawn_collision", "%s inside %s at d=%.2f" % [c["t"], h["t"], dc])


func _check_sequence(data: Dictionary, r: Report) -> void:
	var lvl: SimLevel = SimLevel.from_dict(data)
	for e: String in lvl.errors:
		r.error("schema", e)
	var form: int = SimConst.form_from_name(str(data["start_form"]))
	for i: int in lvl.entity_count():
		if lvl.e_type[i] == SimConst.EntityType.FORM_GATE:
			var to: int = int(lvl.e_p0[i])
			if to == form:
				r.error("invalid_sequence", "form gate at d=%.2f does not change form" % lvl.e_d[i])
			form = to
	var taps: Array = (data["solution"] as Dictionary).get("taps", []) as Array
	var last: int = -RunReplay.MIN_TAP_GAP_TICKS
	for t: Variant in taps:
		if int(t) - last < RunReplay.MIN_TAP_GAP_TICKS:
			r.error("invalid_sequence", "solution taps not increasing / too close at tick %d" % int(t))
			break
		last = int(t)


# --- simulation-based checks ----------------------------------------------------


func _solution_replay(data: Dictionary) -> RunReplay:
	var rp: RunReplay = RunReplay.new()
	for t: Variant in (data["solution"] as Dictionary).get("taps", []) as Array:
		rp.tap_ticks.append(int(t))
	return rp


func _new_sim(data: Dictionary) -> FluxSim:
	var sim: FluxSim = FluxSim.new()
	sim.record_events = false
	sim.shields_allowed = false
	sim.setup(SimLevel.from_dict(data))
	return sim


func _check_solution(data: Dictionary, r: Report) -> void:
	var sim: FluxSim = _solution_replay(data).play_on(_new_sim(data))
	r.stats["solution_score"] = sim.score
	r.stats["solution_time"] = sim.time()
	r.stats["solution_combo"] = sim.max_combo
	if sim.status != SimConst.Status.COMPLETED:
		r.error(
			"impossible_level",
			"stored solution fails (reason %d at d=%.2f, entity %d)" % [sim.fail_reason, sim.d, sim.fail_entity]
		)
		return
	if not sim.is_perfect():
		r.error(
			"unreachable_state",
			"perfect run not achievable by solution (%d/%d sparks)" % [sim.sparks, sim.level.spark_total]
		)
	if sim.score < int(data["score_target"]):
		r.error("unreachable_state", "score target %d above solution score %d" % [int(data["score_target"]), sim.score])
	if sim.max_combo < int(data["combo_target"]):
		r.error("unreachable_state", "combo target above solution combo")


## Fairness: every required tap must tolerate being early/late by at least
## the tier's minimum window (measured by re-simulation with the tap shifted).
func _check_windows(data: Dictionary, r: Report) -> void:
	var taps: PackedInt32Array = _solution_replay(data).tap_ticks
	if taps.is_empty():
		return
	var min_required: float = _min_window_for(data)
	var base: FluxSim = _new_sim(data)
	# snapshots[i] = state right after tap i-1 was applied (initial state for i=0).
	var snapshots: Array[FluxSim] = []
	# tick -> state signature of the stored solution run
	var states_at: Dictionary[int, int] = {}
	var last_snapshot: FluxSim = base.clone()
	var ti: int = 0
	while base.is_running():
		if ti < taps.size() and base.tick == taps[ti]:
			snapshots.append(last_snapshot)
			ti += 1
			base.step(true)
			last_snapshot = base.clone()
		else:
			base.step(false)
		states_at[base.tick] = _state_sig(base)
	var worst: float = INF
	var settle: int = int(ceil(SimConst.HOP_TIME * 1.6 * float(SimConst.TICK_RATE))) + 2
	for i: int in snapshots.size():
		var has_next: bool = i + 1 < taps.size()
		var next_tap: int = taps[i + 1] if has_next else -1
		var lo_bound: int = snapshots[i].tick
		var hi_bound: int = (next_tap - RunReplay.MIN_TAP_GAP_TICKS) if has_next else taps[i] + WINDOW_SCAN_TICKS
		var check_tick: int = (next_tap + settle) if has_next else taps[i] + WINDOW_SCAN_TICKS
		var earlier: int = 0
		while earlier < WINDOW_SCAN_TICKS and taps[i] - earlier - 1 >= lo_bound:
			if not _shift_ok(snapshots[i], taps[i] - earlier - 1, next_tap, check_tick, states_at):
				break
			earlier += 1
		var later: int = 0
		while later < WINDOW_SCAN_TICKS and taps[i] + later + 1 <= hi_bound:
			if not _shift_ok(snapshots[i], taps[i] + later + 1, next_tap, check_tick, states_at):
				break
			later += 1
		var window: float = float(earlier + later + 1 + window_tolerance_ticks) * SimConst.DT
		worst = minf(worst, window)
		var last_ok_s: float = float(taps[i] + later) * SimConst.DT
		if i == 0 and last_ok_s < FIRST_DECISION_S:
			r.error(
				"unfair_window", "the first tap must land by %.2f s after GO (< %.1f s)" % [last_ok_s, FIRST_DECISION_S]
			)
		if window < min_required:
			r.error(
				"unfair_window",
				(
					"tap %d at tick %d has %.0f ms window (< %.0f ms)"
					% [i, taps[i], window * 1000.0, min_required * 1000.0]
				)
			)
	r.stats["min_window"] = worst


func _state_sig(sim: FluxSim) -> int:
	var sig: int = sim.lane * 1000 + sim.phase * 100 + (10 if sim.heavy else 0) + (1 if sim.hop_t >= 1.0 else 0)
	# Plates and flight are part of where the run is (zero for older levels).
	return sig + sim.plates * 10000 + (100000 if sim.airborne else 0)


## Replays from [param start] with tap i moved to [param tap_tick] (the next
## solution tap unchanged) and checks the run converges back to the baseline.
func _shift_ok(start: FluxSim, tap_tick: int, next_tap: int, check_tick: int, states_at: Dictionary[int, int]) -> bool:
	if tap_tick < start.tick:
		return false
	var s: FluxSim = start.clone()
	while s.is_running() and s.tick < tap_tick:
		s.step(false)
	if not s.is_running():
		return false
	s.step(true)
	while s.is_running() and s.tick < check_tick:
		s.step(s.tick == next_tap)
	if s.status == SimConst.Status.FAILED:
		return false
	if s.status == SimConst.Status.COMPLETED:
		return true
	return int(states_at.get(s.tick, -1)) == _state_sig(s)


func _min_window_for(data: Dictionary) -> float:
	var tier: Dictionary = tiers.get(str(data["tier"]), {}) as Dictionary
	return float(tier.get("min_window", 0.12))


## Currents, portals and launch pads must never push the core into an
## unavoidable hit (a launched core is followed through its whole flight).
func _check_forced_moves(data: Dictionary, r: Report) -> void:
	var lvl: SimLevel = SimLevel.from_dict(data)
	var replay: RunReplay = _solution_replay(data)
	for i: int in lvl.entity_count():
		var type: int = lvl.e_type[i]
		if (
			type != SimConst.EntityType.CURRENT
			and type != SimConst.EntityType.PORTAL
			and type != SimConst.EntityType.LAUNCH_PAD
		):
			continue
		var probe: FluxSim = _new_sim(data)
		var tap_index: int = 0
		while probe.is_running() and probe.d < lvl.e_d[i] - 0.05:
			var tap: bool = tap_index < replay.tap_ticks.size() and replay.tap_ticks[tap_index] == probe.tick
			if tap:
				tap_index += 1
			probe.step(tap)
		if type != SimConst.EntityType.LAUNCH_PAD:
			if _forced_move_fails(probe):
				r.error(
					"dead_end", "%s at d=%.2f leads into an unavoidable hit" % [SimConst.entity_name(type), lvl.e_d[i]]
				)
			continue
		# A player may reach the pad carrying fewer plates than the solution
		# (skipped, or lost to a shield hit): every lighter flight must land safely.
		for carried: int in range(probe.plates, -1, -1):
			var flight: FluxSim = probe.clone()
			flight.plates = carried
			if _pad_flight_fails(flight, lvl.e_d[i]):
				r.error(
					"dead_end",
					"launch pad at d=%.2f with %d plates lands in an unavoidable hit" % [lvl.e_d[i], carried]
				)
				break


## Follows a launch from just before its pad, then the reaction time after landing.
func _pad_flight_fails(probe: FluxSim, d_pad: float) -> bool:
	var launches_before: int = probe.launches
	while probe.is_running() and probe.d < d_pad + 0.05:
		probe.step(false)
	if probe.launches == launches_before:
		return probe.status == SimConst.Status.FAILED
	while probe.is_running() and probe.airborne:
		probe.step(false)
	return _forced_move_fails(probe)


## Plays the reaction time without input: true when the core cannot avoid a hit.
func _forced_move_fails(probe: FluxSim) -> bool:
	var until_tick: int = probe.tick + int(REACTION_TIME * float(SimConst.TICK_RATE)) + 2
	while probe.is_running() and probe.tick < until_tick:
		probe.step(false)
	return probe.status == SimConst.Status.FAILED


## Prisms are optional but must be collectible by some fair timing.
func _check_prisms(data: Dictionary, r: Report) -> void:
	var lvl: SimLevel = SimLevel.from_dict(data)
	var taps: PackedInt32Array = _solution_replay(data).tap_ticks
	for i: int in lvl.entity_count():
		if lvl.e_type[i] != SimConst.EntityType.PRISM:
			continue
		if not _prism_reachable(data, lvl, i, taps):
			r.error("unreachable_state", "prism at d=%.2f lane %d unreachable" % [lvl.e_d[i], lvl.e_lane[i]])


func _prism_reachable(data: Dictionary, lvl: SimLevel, index: int, taps: PackedInt32Array) -> bool:
	# 1) Maybe the stored solution already collects it; remember the state just
	#    before every solution tap so delays can resume from there cheaply.
	var base: FluxSim = _new_sim(data)
	var before_tap: Dictionary[int, FluxSim] = {}
	var ti: int = 0
	while base.is_running() and base.d < lvl.e_d[index] + 2.0:
		var tap: bool = ti < taps.size() and taps[ti] == base.tick
		if tap:
			before_tap[ti] = base.clone()
			ti += 1
		var was_open: bool = (base.ent_flags[index] & FluxSim.FLAG_CONSUMED) == 0
		var prisms_before: int = base.prisms
		base.step(tap)
		if _collected_now(base, index, was_open, prisms_before):
			return true
		if not was_open:
			break
	var tick_at: int = base.tick
	# 2) Delay one of the last solution taps before the prism (others unchanged).
	var first_k: int = maxi(0, ti - PRISM_TAPS_CONSIDERED)
	for k: int in range(first_k, ti):
		var walker: FluxSim = before_tap[k].clone()
		var delay: int = 0
		while walker.is_running() and walker.tick <= tick_at:
			if k + 1 < taps.size() and walker.tick >= taps[k + 1] - RunReplay.MIN_TAP_GAP_TICKS:
				break
			if delay > 0 and _prism_trial(walker, lvl, index, taps, k + 1):
				return true
			walker.step(false)
			delay += 1
	return false


## Taps at [param from] (current tick), then plays the remaining solution taps
## from [param next_tap_index]; true if the prism is collected and the run survives.
func _prism_trial(from: FluxSim, lvl: SimLevel, index: int, taps: PackedInt32Array, next_tap_index: int) -> bool:
	var trial: FluxSim = from.clone()
	var collected: bool = false
	var open: bool = (trial.ent_flags[index] & FluxSim.FLAG_CONSUMED) == 0
	var before: int = trial.prisms
	trial.step(true)
	collected = _collected_now(trial, index, open, before)
	var tj: int = next_tap_index
	while trial.is_running() and trial.d < lvl.e_d[index] + 10.0:
		var t2: bool = tj < taps.size() and taps[tj] == trial.tick
		if t2:
			tj += 1
		open = (trial.ent_flags[index] & FluxSim.FLAG_CONSUMED) == 0
		before = trial.prisms
		trial.step(t2)
		collected = collected or _collected_now(trial, index, open, before)
	return trial.status != SimConst.Status.FAILED and collected


## True when this step resolved prism [param index] by collecting it (the
## consumed flag is also set when a prism is merely passed, so the prism
## counter must have risen on the same step).
static func _collected_now(sim: FluxSim, index: int, was_open: bool, prisms_before: int) -> bool:
	return was_open and (sim.ent_flags[index] & FluxSim.FLAG_CONSUMED) != 0 and sim.prisms > prisms_before


func _check_duration(data: Dictionary, r: Report) -> void:
	var kind: String = str(data["kind"])
	if kind == "endless" or kind == "daily":
		return
	var key: String = str(data["tier"])
	if kind == "boss":
		key = "special_boss"
	elif kind == "challenge":
		key = "special_challenge"
	var b: Array = duration_bounds.get(key, [0, 9999]) as Array
	var t: float = float(r.stats.get("solution_time", 0.0))
	if t < float(b[0]) or t > float(b[1]):
		r.error("duration", "duration %.1fs outside %s bounds [%s, %s]" % [t, key, str(b[0]), str(b[1])])


func _check_solver(data: Dictionary, r: Report) -> void:
	var solver: AutopilotSolver = AutopilotSolver.new()
	var ok: bool = solver.solve(SimLevel.from_dict(data))
	r.stats["solver_states"] = solver.explored
	if not ok:
		r.warn("solver", "independent beam solver found no path (stored solution still valid)")
	else:
		r.stats["solver_sparks"] = solver.best_sparks
