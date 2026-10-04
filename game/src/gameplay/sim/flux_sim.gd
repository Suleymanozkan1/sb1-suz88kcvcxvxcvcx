class_name FluxSim
extends RefCounted
## Deterministic fixed-step simulation of one FLUX DROP run.
##
## Pure logic (no nodes, no engine time, no transcendental math in rules) so the
## exact same code drives gameplay, level generation, validation, the autopilot,
## replay verification on a server, and tests. Advance it with [method step],
## one call per tick, passing whether a tap happened on that tick.

const FLAG_CONSUMED: int = 1
const FLAG_RESOLVED: int = 2
## Set while passing a hazard whenever the core came within the near-miss
## margin of it (judged over the whole pass, not only its centre line).
const FLAG_CLOSE: int = 4
## Set when a launched core passed over a hazard it would have hit on the floor.
const FLAG_VAULT: int = 8
## Initial event buffer: room for 32 events (one busy frame), doubled on demand.
const EVENT_BUFFER_START: int = 96

var level: SimLevel
## Presentation events are recorded only when needed (off for solver searches).
var record_events: bool = true
## Mode tweaks.
var zen: bool = false
var speed_scale: float = 1.0
var shields_allowed: bool = true
## Perfect Run mode: a missed spark ends the run.
var strict: bool = false

var tick: int = 0
var status: int = SimConst.Status.RUNNING
var fail_reason: int = SimConst.FailReason.NONE
var fail_entity: int = -1
var d: float = 0.0
var prev_d: float = 0.0
var x: float = 0.0
var prev_x: float = 0.0
var lane: int = 0
var hop_from: float = 0.0
var hop_to: float = 0.0
var hop_t: float = 1.0
var hop_duration: float = SimConst.HOP_TIME
var hop_dir: int = 1
var phase: int = 0
var form: int = SimConst.Form.HOP
var heavy: bool = false
var speed: float = 0.0
var dash_timer: float = 0.0
var dash_cooldown: float = 0.0
var invuln: float = 0.0
var magnet_timer: float = 0.0
var overdrive_timer: float = 0.0
var charges: int = 0
var shields: int = 0
var combo: int = 0
var max_combo: int = 0
var score: int = 0
var sparks: int = 0
var prisms: int = 0
var near_misses: int = 0
var shatters: int = 0
var chain_links: int = 0
var gates: int = 0
var damage: int = 0
var taps: int = 0
var portals_used: int = 0
var currents_ridden: int = 0
var overdrives: int = 0
## Height above the resting line after a launch pad, and vertical speed.
var y: float = 0.0
var prev_y: float = 0.0
var vy: float = 0.0
var airborne: bool = false
## Gravity factor of the gravity well the core is in (1.0 outside) and where
## that well ends.
var grav: float = 1.0
var grav_end: float = 0.0
## Mass plates stacked on the core (0..MAX_PLATES).
var plates: int = 0
var launches: int = 0
var vaults: int = 0
var stack_crashes: int = 0
var cursor: int = 0
var ent_flags: PackedByteArray = PackedByteArray()
## Flat triples [event_type, entity_index, value, ...] in events[0, event_len).
## The buffer keeps its capacity: clear_events() only resets the length, so a
## running game does not allocate per tick (Godot frees a packed array on clear).
var events: PackedInt32Array = PackedInt32Array()
var event_len: int = 0


func _init(sim_level: SimLevel = null) -> void:
	if sim_level != null:
		setup(sim_level)


func setup(sim_level: SimLevel) -> void:
	level = sim_level
	reset()


## Restores the initial state for the current level (used for instant restart).
func reset() -> void:
	tick = 0
	status = SimConst.Status.RUNNING
	fail_reason = SimConst.FailReason.NONE
	fail_entity = -1
	d = 0.0
	prev_d = 0.0
	lane = level.start_lane
	x = SimConst.lane_x(lane, level.lane_count)
	prev_x = x
	hop_from = x
	hop_to = x
	hop_t = 1.0
	hop_duration = level.hop_time
	hop_dir = 1 if lane < level.lane_count - 1 else -1
	phase = level.start_phase
	form = level.start_form
	heavy = false
	y = 0.0
	prev_y = 0.0
	vy = 0.0
	airborne = false
	grav = 1.0
	grav_end = 0.0
	plates = 0
	launches = 0
	vaults = 0
	stack_crashes = 0
	speed = _target_speed()
	dash_timer = 0.0
	dash_cooldown = 0.0
	invuln = 0.0
	magnet_timer = 0.0
	overdrive_timer = 0.0
	charges = 0
	shields = level.start_shields if shields_allowed else 0
	combo = 0
	max_combo = 0
	score = 0
	sparks = 0
	prisms = 0
	near_misses = 0
	shatters = 0
	chain_links = 0
	gates = 0
	damage = 0
	taps = 0
	portals_used = 0
	currents_ridden = 0
	overdrives = 0
	cursor = 0
	ent_flags = PackedByteArray()
	ent_flags.resize(level.entity_count())
	event_len = 0


## Call after [method SimLevel.append_entities] (endless streaming).
func sync_entity_capacity() -> void:
	var n: int = level.entity_count()
	if ent_flags.size() < n:
		ent_flags.resize(n)


func clone() -> FluxSim:
	var c: FluxSim = FluxSim.new()
	c.level = level
	c.record_events = record_events
	c.zen = zen
	c.speed_scale = speed_scale
	c.strict = strict
	c.shields_allowed = shields_allowed
	c.tick = tick
	c.status = status
	c.fail_reason = fail_reason
	c.fail_entity = fail_entity
	c.d = d
	c.prev_d = prev_d
	c.x = x
	c.prev_x = prev_x
	c.lane = lane
	c.hop_from = hop_from
	c.hop_to = hop_to
	c.hop_t = hop_t
	c.hop_duration = hop_duration
	c.hop_dir = hop_dir
	c.phase = phase
	c.form = form
	c.heavy = heavy
	c.speed = speed
	c.dash_timer = dash_timer
	c.dash_cooldown = dash_cooldown
	c.invuln = invuln
	c.magnet_timer = magnet_timer
	c.overdrive_timer = overdrive_timer
	c.charges = charges
	c.shields = shields
	c.combo = combo
	c.max_combo = max_combo
	c.score = score
	c.sparks = sparks
	c.prisms = prisms
	c.near_misses = near_misses
	c.shatters = shatters
	c.chain_links = chain_links
	c.gates = gates
	c.damage = damage
	c.taps = taps
	c.portals_used = portals_used
	c.currents_ridden = currents_ridden
	c.overdrives = overdrives
	c.y = y
	c.prev_y = prev_y
	c.vy = vy
	c.airborne = airborne
	c.grav = grav
	c.grav_end = grav_end
	c.plates = plates
	c.launches = launches
	c.vaults = vaults
	c.stack_crashes = stack_crashes
	c.cursor = cursor
	c.ent_flags = ent_flags.duplicate()
	return c


func time() -> float:
	return float(tick) * SimConst.DT


func is_running() -> bool:
	return status == SimConst.Status.RUNNING


func is_hopping() -> bool:
	return hop_t < 1.0


## Advances the simulation by one fixed tick.
func step(tap: bool) -> void:
	if status != SimConst.Status.RUNNING:
		return
	if tap:
		_apply_tap()
	tick += 1
	_update_timers()
	var accel: float = SimConst.SURGE_ACCEL if form == SimConst.Form.SURGE else SimConst.DEFAULT_ACCEL
	speed = move_toward(speed, _target_speed(), accel * SimConst.DT)
	prev_d = d
	prev_x = x
	prev_y = y
	d += speed * SimConst.DT
	if hop_t < 1.0:
		hop_t = minf(1.0, hop_t + SimConst.DT / hop_duration)
		x = hop_from + (hop_to - hop_from) * SimConst.smoothstep01(hop_t)
	if airborne:
		_update_air()
	if grav != 1.0 and d >= grav_end:
		grav = 1.0
		_emit(SimConst.EventType.GRAVITY_EXIT, -1, 100)
	_process_entities(time())
	if status != SimConst.Status.RUNNING:
		return
	if level.time_limit > 0.0 and time() >= level.time_limit:
		_complete()
	elif d >= level.length:
		_complete()


## Runs ticks with no input until the core reaches [param target_d] or the run ends.
func advance_to_distance(target_d: float, max_ticks: int = 100000) -> void:
	var guard: int = 0
	while status == SimConst.Status.RUNNING and d < target_d and guard < max_ticks:
		step(false)
		guard += 1


## Whether the run is a perfect run (only meaningful after completion).
func is_perfect() -> bool:
	return status == SimConst.Status.COMPLETED and damage == 0 and sparks >= level.spark_total


func objective_progress() -> int:
	match level.objective_type:
		SimLevel.Objective.COLLECT:
			return sparks
		SimLevel.Objective.SHATTER:
			return shatters
	return 0


func objective_met() -> bool:
	match level.objective_type:
		SimLevel.Objective.COLLECT:
			return sparks >= level.objective_target
		SimLevel.Objective.SHATTER:
			return shatters >= level.objective_target
	return true


## Compact integer key of everything that affects future survival; used by the
## solver to merge equivalent search states.
func state_key() -> int:
	var k: int = form
	k = k * 4 + lane
	k = k * 2 + phase
	k = k * 2 + (1 if heavy else 0)
	k = k * 3 + (hop_dir + 1)
	k = k * 32 + int(hop_t * 31.0)
	k = (k * 1031 + int(roundf(x * 64.0)) + 512) & 0xFFFFFFFFFFFF
	k = (k * 257 + int(dash_timer * 60.0)) & 0xFFFFFFFFFFFF
	k = (k * 257 + int(dash_cooldown * 60.0)) & 0xFFFFFFFFFFFF
	k = (k * 1031 + int(roundf(speed * 16.0))) & 0xFFFFFFFFFFFF
	k = (k * 4099 + int(roundf(d * 8.0)) % 4096) & 0xFFFFFFFFFFFF
	k = (k * 4 + shields) & 0xFFFFFFFFFFFF
	k = (k * 64 + int(invuln * 60.0)) & 0xFFFFFFFFFFFF
	k = (k * 2 + (1 if magnet_timer > 0.0 else 0)) & 0xFFFFFFFFFFFF
	k = (k * 97 + _broken_ahead()) & 0xFFFFFFFFFFFF
	if airborne or plates > 0 or grav != 1.0:
		# Mass/gravity state; legacy states keep exactly their old keys.
		k = (k * 4 + plates) & 0xFFFFFFFFFFFF
		k = (k * 64 + clampi(roundi(y * 24.0), 0, 63)) & 0xFFFFFFFFFFFF
		k = (k * 131 + clampi(roundi(vy * 4.0) + 65, 0, 130)) & 0xFFFFFFFFFFFF
		k = (k * 23 + clampi(roundi(grav * 10.0), 0, 22)) & 0xFFFFFFFFFFFF
		k = (k * 67 + clampi(int((grav_end - d) * 2.0), 0, 66)) & 0xFFFFFFFFFFFF
	return k


func _broken_ahead() -> int:
	var count: int = 0
	var n: int = level.entity_count()
	var i: int = cursor
	while i < n and level.e_d[i] < d + 12.0:
		if level.e_type[i] == SimConst.EntityType.BREAKABLE and (ent_flags[i] & FLAG_CONSUMED) != 0:
			count += 1
		i += 1
	return count


func _emit(type: int, entity: int, value: int) -> void:
	if record_events:
		if event_len + 3 > events.size():
			events.resize(maxi(EVENT_BUFFER_START, events.size() * 2))
		events[event_len] = type
		events[event_len + 1] = entity
		events[event_len + 2] = value
		event_len += 3


## Forgets the recorded events, keeping the buffer for reuse.
func clear_events() -> void:
	event_len = 0


## A copy of the recorded events (tools and tests; the game reads the buffer).
func recorded_events() -> PackedInt32Array:
	return events.slice(0, event_len)


func _target_speed() -> float:
	var base: float = level.base_speed * speed_scale
	if level.speed_ramp != 0.0:
		base *= 1.0 + level.speed_ramp * clampf(d / level.ramp_distance, 0.0, 1.0)
	if form == SimConst.Form.SURGE:
		base *= SimConst.SURGE_HEAVY_FACTOR if heavy else SimConst.SURGE_LIGHT_FACTOR
	if dash_timer > 0.0:
		base *= SimConst.DASH_SPEED_FACTOR
	if grav != 1.0:
		base *= SimConst.gravity_speed_factor(grav)
	return base


## Ballistic flight after a launch pad (semi-implicit Euler, pure arithmetic).
func _update_air() -> void:
	vy -= SimConst.G0 * grav * SimConst.DT
	y += vy * SimConst.DT
	if y <= 0.0:
		y = 0.0
		vy = 0.0
		airborne = false
		_emit(SimConst.EventType.LAND, -1, 0)


func _update_timers() -> void:
	var dt: float = SimConst.DT
	if dash_timer > 0.0:
		dash_timer = maxf(0.0, dash_timer - dt)
	if dash_cooldown > 0.0:
		dash_cooldown = maxf(0.0, dash_cooldown - dt)
	if invuln > 0.0:
		invuln = maxf(0.0, invuln - dt)
	if magnet_timer > 0.0:
		magnet_timer = maxf(0.0, magnet_timer - dt)
	if overdrive_timer > 0.0:
		overdrive_timer = maxf(0.0, overdrive_timer - dt)
		if overdrive_timer == 0.0:
			_emit(SimConst.EventType.OVERDRIVE_END, -1, 0)


func _apply_tap() -> void:
	taps += 1
	match form:
		SimConst.Form.HOP:
			_tap_hop()
		SimConst.Form.PHASE:
			phase = 1 - phase
			_emit(SimConst.EventType.TAP_PHASE, -1, phase)
		SimConst.Form.DASH:
			if dash_cooldown <= 0.0:
				dash_timer = SimConst.DASH_TIME
				dash_cooldown = SimConst.DASH_COOLDOWN
				_emit(SimConst.EventType.TAP_DASH, -1, 0)
			else:
				_emit(SimConst.EventType.TAP_DASH_DENIED, -1, 0)
		SimConst.Form.SURGE:
			heavy = not heavy
			_emit(SimConst.EventType.TAP_SURGE, -1, 1 if heavy else 0)


func _tap_hop() -> void:
	var target: int
	if level.lane_count == 2:
		target = 1 - lane
	else:
		target = lane + hop_dir
		if target < 0 or target >= level.lane_count:
			hop_dir = -hop_dir
			target = lane + hop_dir
	_begin_hop(target)
	_emit(SimConst.EventType.TAP_HOP, -1, target)


func _begin_hop(target: int) -> void:
	var lane_count: int = level.lane_count
	target = clampi(target, 0, lane_count - 1)
	lane = target
	if target == 0:
		hop_dir = 1
	elif target == lane_count - 1:
		hop_dir = -1
	hop_from = x
	hop_to = SimConst.lane_x(target, lane_count)
	var dist: float = absf(hop_to - hop_from) / SimConst.LANE_WIDTH
	if dist <= 0.0001:
		hop_t = 1.0
		x = hop_to
		return
	hop_duration = level.hop_time * maxf(SimConst.HOP_MIN_TIME_FRACTION, minf(dist, 1.0))
	if grav != 1.0:
		# Fixed for the whole hop, even if it ends outside the well.
		hop_duration *= SimConst.gravity_hop_factor(grav)
	hop_t = 0.0


func _complete() -> void:
	if not objective_met():
		_fail(SimConst.FailReason.OBJECTIVE, -1)
		return
	status = SimConst.Status.COMPLETED
	score += SimConst.SCORE_CLEAR_BONUS
	_emit(SimConst.EventType.COMPLETE, -1, score)


func _fail(reason: int, entity: int) -> void:
	status = SimConst.Status.FAILED
	fail_reason = reason
	fail_entity = entity
	_emit(SimConst.EventType.FAIL, entity, reason)


func _multiplier() -> float:
	var m: float = SimConst.combo_multiplier(combo)
	if overdrive_timer > 0.0:
		m *= SimConst.OVERDRIVE_MULT
	return m


func _add_score(base: int) -> int:
	var gained: int = int(roundf(float(base) * _multiplier()))
	score += gained
	return gained


func _combo_up() -> void:
	combo += 1
	if combo > max_combo:
		max_combo = combo
	if combo % SimConst.COMBO_STEP == 0:
		_emit(SimConst.EventType.COMBO_STEP, -1, combo)


func _combo_break() -> void:
	combo = 0


func _process_entities(t: float) -> void:
	var n: int = level.entity_count()
	var core_back: float = d - SimConst.CORE_RADIUS
	while cursor < n and level.e_d[cursor] + SimConst.ENTITY_REACH < core_back:
		_on_left_behind(cursor)
		cursor += 1
		if status != SimConst.Status.RUNNING:
			return
	var core_front: float = d + SimConst.CORE_RADIUS
	var i: int = cursor
	while i < n:
		var ed: float = level.e_d[i]
		if ed - SimConst.ENTITY_REACH > core_front:
			break
		if (ent_flags[i] & FLAG_CONSUMED) == 0:
			_process_entity(i, ed, t)
			if status != SimConst.Status.RUNNING:
				return
		i += 1


func _crossed(ed: float) -> bool:
	return prev_d < ed and ed <= d


func _process_entity(i: int, ed: float, t: float) -> void:
	var type: int = level.e_type[i]
	match type:
		SimConst.EntityType.SPARK, SimConst.EntityType.PRISM:
			_check_collect(i, ed)
		SimConst.EntityType.SHIELD, SimConst.EntityType.MAGNET:
			_check_pickup(i, ed)
		SimConst.EntityType.PLATE:
			_check_plate(i, ed)
		SimConst.EntityType.GRAVITY:
			if _crossed(ed):
				ent_flags[i] |= FLAG_CONSUMED
				# The newest well wins; leaving it restores normal gravity.
				grav = clampf(level.e_p1[i], SimConst.GRAVITY_MIN, SimConst.GRAVITY_MAX)
				grav_end = ed + level.e_p0[i]
				_emit(SimConst.EventType.GRAVITY_ENTER, i, roundi(grav * 100.0))
		SimConst.EntityType.LAUNCH_PAD:
			if _crossed(ed):
				ent_flags[i] |= FLAG_CONSUMED
				var pad_x: float = SimConst.lane_x(level.e_lane[i], level.lane_count)
				if not airborne and absf(x - pad_x) <= SimConst.PAD_CAPTURE_HALF_WIDTH:
					airborne = true
					vy = SimConst.launch_speed(plates)
					launches += 1
					_emit(SimConst.EventType.LAUNCH, i, plates)
		SimConst.EntityType.CURRENT:
			if _crossed(ed):
				ent_flags[i] |= FLAG_CONSUMED
				var nearest: int = _nearest_lane()
				# A current pushes along the floor: a core in the air flies over it.
				if not airborne and (level.e_mask[i] & (1 << nearest)) != 0:
					currents_ridden += 1
					_begin_hop(int(level.e_p0[i]))
					_emit(SimConst.EventType.CURRENT, i, lane)
		SimConst.EntityType.PORTAL:
			if _crossed(ed):
				ent_flags[i] |= FLAG_CONSUMED
				var px: float = SimConst.lane_x(level.e_lane[i], level.lane_count)
				if absf(x - px) <= SimConst.PORTAL_CAPTURE_HALF_WIDTH and y < SimConst.AIR_CLEARANCE:
					_teleport(int(level.e_p0[i]))
					portals_used += 1
					_emit(SimConst.EventType.PORTAL, i, lane)
		SimConst.EntityType.FORM_GATE:
			if _crossed(ed):
				ent_flags[i] |= FLAG_CONSUMED
				_change_form(int(level.e_p0[i]))
				_emit(SimConst.EventType.FORM_CHANGE, i, form)
		_:
			_check_hazard(i, type, ed, t)


func _nearest_lane() -> int:
	var best: int = 0
	var best_dist: float = INF
	for l: int in level.lane_count:
		var dist: float = absf(x - SimConst.lane_x(l, level.lane_count))
		if dist < best_dist:
			best_dist = dist
			best = l
	return best


func _teleport(target: int) -> void:
	lane = clampi(target, 0, level.lane_count - 1)
	x = SimConst.lane_x(lane, level.lane_count)
	prev_x = x
	hop_from = x
	hop_to = x
	hop_t = 1.0
	if lane == 0:
		hop_dir = 1
	elif lane == level.lane_count - 1:
		hop_dir = -1


func _change_form(new_form: int) -> void:
	if new_form < 0 or new_form == form:
		return
	form = new_form
	heavy = false
	dash_timer = 0.0
	dash_cooldown = 0.0
	# Momentum never carries a dash boost into a new form.
	speed = minf(speed, _target_speed())


func _check_collect(i: int, ed: float) -> void:
	var magnet: bool = magnet_timer > 0.0 or overdrive_timer > 0.0
	var depth: float = SimConst.SPARK_COLLECT_DEPTH * (2.0 if magnet else 1.0)
	if d - ed > depth:
		# Passed without collecting: a missed spark breaks the combo right away.
		ent_flags[i] |= FLAG_CONSUMED
		if level.e_type[i] == SimConst.EntityType.SPARK:
			if combo > 0:
				_combo_break()
			_emit(SimConst.EventType.SPARK_MISSED, i, 0)
			if strict:
				_fail(SimConst.FailReason.MISSED_SPARK, i)
		return
	if absf(ed - d) > depth or y > SimConst.PICKUP_HEIGHT:
		return
	var radius: float = SimConst.MAGNET_COLLECT_RADIUS if magnet else SimConst.SPARK_COLLECT_RADIUS
	var lx: float = SimConst.lane_x(level.e_lane[i], level.lane_count)
	if absf(x - lx) > radius:
		return
	var color: int = level.e_color[i]
	if color >= 0 and color != phase:
		return
	ent_flags[i] |= FLAG_CONSUMED
	_combo_up()
	if level.e_type[i] == SimConst.EntityType.SPARK:
		sparks += 1
		var gained: int = _add_score(SimConst.SCORE_SPARK)
		_emit(SimConst.EventType.SPARK, i, gained)
		if overdrive_timer <= 0.0:
			charges += 1
			if charges >= SimConst.MAX_CHARGES:
				charges = 0
				overdrive_timer = SimConst.OVERDRIVE_TIME
				overdrives += 1
				_emit(SimConst.EventType.OVERDRIVE_START, -1, 0)
	else:
		prisms += 1
		var gained_prism: int = _add_score(SimConst.SCORE_PRISM)
		_emit(SimConst.EventType.PRISM, i, gained_prism)


func _check_pickup(i: int, ed: float) -> void:
	# Modes without shields leave shield pickups untouched (and the view does
	# not draw them), so nothing ever pretends to protect the player.
	if not shields_allowed and level.e_type[i] == SimConst.EntityType.SHIELD:
		return
	if absf(ed - d) > SimConst.SPARK_COLLECT_DEPTH or y > SimConst.PICKUP_HEIGHT:
		return
	var lx: float = SimConst.lane_x(level.e_lane[i], level.lane_count)
	if absf(x - lx) > SimConst.PICKUP_RADIUS:
		return
	ent_flags[i] |= FLAG_CONSUMED
	if level.e_type[i] == SimConst.EntityType.SHIELD:
		if shields_allowed:
			shields = mini(shields + 1, SimConst.MAX_SHIELDS)
		_emit(SimConst.EventType.SHIELD_UP, i, shields)
	else:
		magnet_timer = SimConst.MAGNET_TIME
		_emit(SimConst.EventType.MAGNET_UP, i, 0)


## Mass plates stack on the core (up to MAX_PLATES); a full stack makes the
## core heavy enough to smash glass on contact.
func _check_plate(i: int, ed: float) -> void:
	if absf(ed - d) > SimConst.SPARK_COLLECT_DEPTH or y > SimConst.PICKUP_HEIGHT:
		return
	var lx: float = SimConst.lane_x(level.e_lane[i], level.lane_count)
	if absf(x - lx) > SimConst.PICKUP_RADIUS:
		return
	ent_flags[i] |= FLAG_CONSUMED
	plates = mini(plates + 1, SimConst.MAX_PLATES)
	_combo_up()
	_add_score(SimConst.SCORE_PLATE)
	_emit(SimConst.EventType.PLATE_UP, i, plates)


## Returns the lateral clearance between the core and the entity's blocking
## geometry at time [param t]; negative means overlap, INF means not blocking.
func _hazard_clearance(i: int, type: int, t: float) -> float:
	var r: float = SimConst.CORE_RADIUS + SimConst.BLOCK_HALF_WIDTH
	match type:
		SimConst.EntityType.SLIDER:
			return absf(x - level.slider_x(i, t)) - r
		SimConst.EntityType.PULSE_GATE:
			if not level.pulse_closed(i, t):
				return INF
		SimConst.EntityType.PHASE_GATE:
			return -1.0 if phase != level.e_color[i] else INF
	var mask: int = level.e_mask[i]
	var best: float = INF
	for l: int in level.lane_count:
		if (mask & (1 << l)) != 0:
			var c: float = absf(x - SimConst.lane_x(l, level.lane_count)) - r
			if c < best:
				best = c
	return best


func _check_hazard(i: int, type: int, ed: float, t: float) -> void:
	var half_depth: float = (
		SimConst.GATE_HALF_DEPTH if type == SimConst.EntityType.PHASE_GATE else SimConst.HAZARD_HALF_DEPTH
	)
	if absf(ed - d) > half_depth + SimConst.CORE_RADIUS:
		return
	var clearance: float = _hazard_clearance(i, type, t)
	# A launched core high enough clears ground hazards (phase gates still apply).
	var over: bool = airborne and y >= SimConst.AIR_CLEARANCE and SimConst.is_vaultable(type)
	if over:
		if clearance < 0.0:
			ent_flags[i] |= FLAG_VAULT
	elif clearance < 0.0:
		if type == SimConst.EntityType.BREAKABLE and dash_timer > 0.0:
			_shatter(i, 0)
			return
		if type == SimConst.EntityType.BREAKABLE and plates >= SimConst.MAX_PLATES:
			# Stack crash: a full stack of plates smashes the glass and is spent.
			plates = 0
			stack_crashes += 1
			_emit(SimConst.EventType.STACK_CRASH, i, 0)
			_shatter(i, 0)
			return
		if invuln > 0.0:
			return
		_collide(
			i,
			SimConst.FailReason.WRONG_PHASE if type == SimConst.EntityType.PHASE_GATE else SimConst.FailReason.COLLISION
		)
		return
	elif clearance < SimConst.NEAR_MISS_MARGIN:
		# A late dodge is close at the front of the hazard and clear by its
		# centre line: the closest approach over the pass decides.
		ent_flags[i] |= FLAG_CLOSE
	if (ent_flags[i] & FLAG_RESOLVED) == 0 and _crossed(ed):
		ent_flags[i] |= FLAG_RESOLVED
		if type == SimConst.EntityType.PHASE_GATE:
			gates += 1
			_combo_up()
			var gained: int = _add_score(SimConst.SCORE_GATE_PASS)
			_emit(SimConst.EventType.GATE_PASS, i, gained)
		elif (ent_flags[i] & FLAG_VAULT) != 0:
			vaults += 1
			_combo_up()
			var vault_gain: int = _add_score(SimConst.SCORE_VAULT)
			_emit(SimConst.EventType.VAULT, i, vault_gain)
		elif (ent_flags[i] & FLAG_CLOSE) != 0:
			near_misses += 1
			_combo_up()
			var nm_gain: int = _add_score(SimConst.SCORE_NEAR_MISS)
			_emit(SimConst.EventType.NEAR_MISS, i, nm_gain)


func _collide(i: int, reason: int) -> void:
	if zen:
		ent_flags[i] |= FLAG_CONSUMED
		damage += 1
		invuln = SimConst.HIT_INVULN_TIME
		_combo_break()
		_emit(SimConst.EventType.ZEN_BUMP, i, 0)
		return
	if shields > 0:
		shields -= 1
		damage += 1
		invuln = SimConst.HIT_INVULN_TIME
		charges = 0
		plates = 0
		ent_flags[i] |= FLAG_CONSUMED
		_combo_break()
		_emit(SimConst.EventType.HIT_SHIELDED, i, shields)
		return
	_fail(reason, i)


func _shatter(i: int, depth_level: int) -> void:
	ent_flags[i] |= FLAG_CONSUMED
	shatters += 1
	_combo_up()
	var gained: int = _add_score(SimConst.SCORE_SHATTER + SimConst.SCORE_CHAIN_LINK * depth_level)
	if depth_level == 0:
		_emit(SimConst.EventType.SHATTER, i, gained)
	else:
		chain_links += 1
		_emit(SimConst.EventType.CHAIN, i, depth_level)
	_chain_from(i, depth_level + 1)


## Breakables within CHAIN_DISTANCE of a shattered block shatter too (cascade).
func _chain_from(i: int, depth_level: int) -> void:
	var n: int = level.entity_count()
	var origin_d: float = level.e_d[i]
	var origin_x: float = SimConst.lane_x(level.e_lane[i], level.lane_count)
	var j: int = cursor
	while j < n:
		var jd: float = level.e_d[j]
		if jd > origin_d + SimConst.CHAIN_DISTANCE:
			break
		if (
			j != i
			and level.e_type[j] == SimConst.EntityType.BREAKABLE
			and (ent_flags[j] & FLAG_CONSUMED) == 0
			and absf(jd - origin_d) <= SimConst.CHAIN_DISTANCE
		):
			var jx: float = SimConst.lane_x(level.e_lane[j], level.lane_count)
			if absf(jx - origin_x) <= SimConst.LANE_WIDTH * 1.01:
				_shatter(j, depth_level)
		j += 1


func _on_left_behind(i: int) -> void:
	if (ent_flags[i] & FLAG_CONSUMED) != 0:
		return
	if level.e_type[i] == SimConst.EntityType.SPARK:
		ent_flags[i] |= FLAG_CONSUMED
		if combo > 0:
			_combo_break()
		_emit(SimConst.EventType.SPARK_MISSED, i, 0)
		if strict:
			_fail(SimConst.FailReason.MISSED_SPARK, i)
