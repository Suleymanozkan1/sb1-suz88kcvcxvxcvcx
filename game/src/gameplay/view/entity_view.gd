class_name EntityView
extends Node3D
## Pooled visual for one level entity, composed of up to [constant MAX_PARTS]
## mesh parts (body, shadow, track, posts, lamps, membrane …).
##
## Motion follows ART_DIRECTION §8: obstacles are heavy and mechanical (linear
## or ease-in-out, no overshoot); pickups bob lightly; membranes ripple on use.

const MAX_PARTS: int = 7
const SHUTTER_RAMP: float = 0.12
const LAMP_WARN_TIME: float = 0.35
const PICKUP_BOB: float = 0.05
## Mass plates float at collect height like the other pickups.
const PLATE_Y: float = 0.4
## chevron.gdshader's default `tiles` (restored when a pooled view is reused).
const CHEVRON_TILES: float = 4.0
## A passed gate arch sinks between these distances behind the core (m), by
## its full height plus the beam (it ends below the floor).
const ARCH_SINK_FROM: float = 0.2
const ARCH_SINK_TO: float = 1.6
const ARCH_SINK_DEPTH: float = ViewKit.ARCH_HEIGHT + ViewKit.ARCH_POST

var entity_index: int = -1
var entity_type: int = -1
var appear: float = 1.0
var _parts: Array[MeshInstance3D] = []
var _body: MeshInstance3D
var _shadow: MeshInstance3D
var _membrane: MeshInstance3D
var _lamps: Array[MeshInstance3D] = []
## Last lamp state applied (-1 unknown): materials change only on a switch.
var _lamp_warn: int = -1
var _kit: ViewKit
var _ripple: float = 0.0
var _bob_phase: float = 0.0


func _init() -> void:
	for _i: int in MAX_PARTS:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.visible = false
		mi.layers = ViewKit.GAMEPLAY_LAYER
		add_child(mi)
		_parts.append(mi)


## Called by [NodePool] on release.
func pool_reset() -> void:
	entity_index = -1
	entity_type = -1
	_ripple = 0.0
	_body = null
	_shadow = null
	_membrane = null
	_lamps.clear()
	_lamp_warn = -1
	for mi: MeshInstance3D in _parts:
		mi.visible = false
		mi.mesh = null
		mi.material_override = null
		mi.position = Vector3.ZERO
		mi.rotation = Vector3.ZERO
		mi.scale = Vector3.ONE
		# Per-instance shader values outlive the material swap: back to the
		# shaders' defaults so a reused view never inherits them.
		mi.set_instance_shader_parameter("tiles", CHEVRON_TILES)
		mi.set_instance_shader_parameter("ripple", 0.0)
		mi.set_instance_shader_parameter("visibility", 1.0)
	scale = Vector3.ONE


func _part(i: int, mesh: Mesh, material: Material, pos: Vector3, shadows: bool) -> MeshInstance3D:
	var mi: MeshInstance3D = _parts[i]
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = Vector3.ZERO
	mi.scale = Vector3.ONE
	mi.visible = true
	mi.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	return mi


func configure(index: int, type: int, lvl: SimLevel, kit: ViewKit) -> void:
	pool_reset()
	entity_index = index
	entity_type = type
	_kit = kit
	appear = 0.0
	_bob_phase = float(index) * 0.7
	var lanes: int = lvl.lane_count
	var lane_x: float = SimConst.lane_x(lvl.e_lane[index], lanes)
	position = Vector3(0.0, 0.0, -lvl.e_d[index])
	var h: float = ViewKit.BLOCK_HEIGHT
	match type:
		SimConst.EntityType.BARRIER:
			var n: int = 0
			for l: int in lanes:
				if (lvl.e_mask[index] & (1 << l)) != 0:
					var x: float = SimConst.lane_x(l, lanes)
					var body: MeshInstance3D = _part(
						n * 2, kit.block_mesh, kit.hazard_material, Vector3(x, h * 0.5, 0.0), true
					)
					if n == 0:
						_body = body
					_part(n * 2 + 1, kit.blob_mesh, kit.blob_material, Vector3(x, 0.006, 0.0), false)
					n += 1
		SimConst.EntityType.SLIDER:
			var from_lane: int = int(lvl.e_p0[index])
			var to_lane: int = int(lvl.e_p1[index])
			_part(0, kit.track_mesh(lanes, from_lane, to_lane), kit.track_material, Vector3.ZERO, false)
			_body = _part(
				1, kit.slider_mesh, kit.hazard_material, Vector3(lvl.slider_x(index, 0.0), h * 0.41, 0.0), true
			)
			_shadow = _part(2, kit.blob_mesh, kit.blob_material, Vector3(lvl.slider_x(index, 0.0), 0.006, 0.0), false)
		SimConst.EntityType.PULSE_GATE:
			var k: int = 0
			for l2: int in lanes:
				if (lvl.e_mask[index] & (1 << l2)) == 0 or k > 0:
					continue
				var x2: float = SimConst.lane_x(l2, lanes)
				var half: float = SimConst.BLOCK_HALF_WIDTH + ViewKit.POST_WIDTH * 0.6
				_body = _part(0, kit.shutter_mesh, kit.hazard_material, Vector3(x2, h * 0.5, 0.0), true)
				_part(1, kit.post_mesh, kit.structure_material, Vector3(x2 - half, h * 0.62, 0.0), true)
				_part(2, kit.post_mesh, kit.structure_material, Vector3(x2 + half, h * 0.62, 0.0), true)
				_lamps.append(_part(3, kit.lamp_mesh, kit.lamp_off_material, Vector3(x2 - half, h * 1.29, 0.0), false))
				_lamps.append(_part(4, kit.lamp_mesh, kit.lamp_off_material, Vector3(x2 + half, h * 1.29, 0.0), false))
				_part(5, kit.track_mesh(lanes, l2, l2), kit.track_material, Vector3.ZERO, false)
				k += 1
		SimConst.EntityType.BREAKABLE:
			_body = _part(0, kit.glass_mesh, kit.glass_material, Vector3(lane_x, h * 0.48, 0.0), true)
			_part(1, kit.blob_mesh, kit.blob_material, Vector3(lane_x, 0.006, 0.0), false)
		SimConst.EntityType.PHASE_GATE:
			_part(0, kit.arch_mesh(lanes), kit.structure_material, Vector3.ZERO, true)
			_membrane = _part(
				1,
				kit.membrane_mesh(lanes),
				kit.phase_material(lvl.e_color[index]),
				Vector3(0.0, ViewKit.ARCH_HEIGHT * 0.48, 0.0),
				false
			)
			if kit.colorblind:
				var c: int = lvl.e_color[index]
				var marker: MeshInstance3D = _part(
					2,
					kit.phase_marker_mesh(c),
					kit.phase_marker_material(c),
					Vector3(0.0, ViewKit.ARCH_HEIGHT + 0.42, 0.0),
					false
				)
				if c == 0:
					marker.rotation_degrees = Vector3(90, 0, 0)
		SimConst.EntityType.FORM_GATE:
			var form: int = int(lvl.e_p0[index])
			_part(0, kit.arch_mesh(lanes), kit.structure_material, Vector3.ZERO, true)
			_membrane = _part(
				1,
				kit.membrane_mesh(lanes),
				kit.form_material(form),
				Vector3(0.0, ViewKit.ARCH_HEIGHT * 0.48, 0.0),
				false
			)
			_body = _part(
				2,
				kit.form_icon_mesh(form),
				kit.form_icon_material(form),
				Vector3(0.0, ViewKit.ARCH_HEIGHT + 0.42, 0.0),
				false
			)
		SimConst.EntityType.PORTAL:
			_part(0, kit.portal_ring_mesh, kit.structure_material, Vector3(lane_x, 0.62, 0.0), true).rotation_degrees = Vector3(
				90, 0, 0
			)
			_membrane = _part(1, kit.disc_mesh, kit.portal_material, Vector3(lane_x, 0.62, 0.0), false)
			_membrane.scale = Vector3.ONE * 1.05
			_part(
				2,
				kit.floor_disc_mesh,
				kit.exit_material,
				Vector3(SimConst.lane_x(int(lvl.e_p0[index]), lanes), 0.02, -0.4),
				false
			)
		SimConst.EntityType.CURRENT:
			var from_l: int = 0
			for l3: int in lanes:
				if (lvl.e_mask[index] & (1 << l3)) != 0:
					from_l = l3
			var to_l: int = int(lvl.e_p0[index])
			var mi: MeshInstance3D = _part(
				0, kit.chevron_mesh(lanes, from_l, to_l), kit.chevron_material, Vector3.ZERO, false
			)
			mi.set_instance_shader_parameter("ripple", 0.0)
			# The arrows point along +x; a leftward current is mirrored. The
			# mirror also flips the strip's baked centre, so it is shifted back
			# over its own lanes (matters off-centre, i.e. in 3-lane levels).
			var mirrored: bool = to_l < from_l
			mi.scale = Vector3(-1.0 if mirrored else 1.0, 1.0, 1.0)
			mi.position.x = (SimConst.lane_x(from_l, lanes) + SimConst.lane_x(to_l, lanes)) if mirrored else 0.0
		SimConst.EntityType.SHIELD:
			_body = _part(0, kit.shield_mesh, kit.shield_material, Vector3(lane_x, 0.42, 0.0), false)
			_body.rotation_degrees = Vector3(90, 0, 0)
		SimConst.EntityType.MAGNET:
			_body = _part(0, kit.magnet_mesh, kit.magnet_material, Vector3(lane_x, 0.42, 0.0), false)
			_body.rotation_degrees = Vector3(0, 0, 90)
		SimConst.EntityType.LAUNCH_PAD:
			# Matte slab (matter) with an energy insert pointing down the track.
			_body = _part(0, kit.pad_mesh, kit.structure_material, Vector3(lane_x, ViewKit.PAD_SIZE.y * 0.5, 0.0), true)
			_membrane = _part(
				1, kit.pad_insert_mesh, kit.pad_material, Vector3(lane_x, ViewKit.PAD_SIZE.y + 0.006, 0.0), false
			)
			_membrane.rotation_degrees = Vector3(0, 90, 0)
			_membrane.set_instance_shader_parameter("tiles", 2.0)
		SimConst.EntityType.PLATE:
			_body = _part(0, kit.plate_mesh, kit.ballast_material, Vector3(lane_x, PLATE_Y, 0.0), true)
			_membrane = _part(1, kit.plate_ring_mesh, kit.plate_ring_material, Vector3(lane_x, PLATE_Y, 0.0), false)
			_part(2, kit.blob_mesh, kit.blob_material, Vector3(lane_x, 0.006, 0.0), false).scale = Vector3.ONE * 0.5
		SimConst.EntityType.GRAVITY:
			var span: float = lvl.e_p0[index]
			var strip: MeshInstance3D = _part(
				0,
				kit.gravity_strip_mesh(lanes, span),
				kit.gravity_material(lvl.e_p1[index] > 1.0),
				Vector3(0.0, 0.016, -span * 0.5),
				false
			)
			strip.rotation_degrees = Vector3(0, 90, 0)
			strip.set_instance_shader_parameter("tiles", maxf(2.0, roundf(span / ViewKit.GRAVITY_ARROW_LENGTH)))
			# Matte rails mark where the well begins and ends.
			_part(1, kit.rail_mesh(lanes), kit.structure_material, Vector3(0.0, 0.025, 0.0), true)
			_part(2, kit.rail_mesh(lanes), kit.structure_material, Vector3(0.0, 0.025, -span), true)


func flash(amount: float) -> void:
	_ripple = maxf(_ripple, amount)


## Per-frame animation for time-based hazards, membranes and pickups.
func animate(delta: float, lvl: SimLevel, sim_time: float, core_d: float = 0.0) -> void:
	appear = minf(1.0, appear + delta * 5.0)
	_ripple = move_toward(_ripple, 0.0, delta * 4.0)
	match entity_type:
		SimConst.EntityType.SLIDER:
			var x: float = lvl.slider_x(entity_index, sim_time)
			_body.position.x = x
			_shadow.position.x = x
		SimConst.EntityType.PULSE_GATE:
			_animate_shutter(lvl, sim_time)
		SimConst.EntityType.PHASE_GATE, SimConst.EntityType.FORM_GATE, SimConst.EntityType.PORTAL:
			if _membrane != null:
				_membrane.set_instance_shader_parameter("ripple", _ripple)
				# Once the core is through, the membrane dissolves (it has done its job).
				var behind: float = clampf((core_d - lvl.e_d[entity_index]) / 1.5, 0.0, 1.0)
				_membrane.set_instance_shader_parameter("visibility", 1.0 - behind)
			if entity_type == SimConst.EntityType.FORM_GATE and _body != null:
				_body.rotation.y += delta * 1.2
		SimConst.EntityType.SHIELD, SimConst.EntityType.MAGNET:
			_bob_phase += delta * 2.4
			_body.position.y = 0.42 + sin(_bob_phase) * PICKUP_BOB
			_body.rotation.y += delta * 1.4
		SimConst.EntityType.PLATE:
			# Heavy ballast: a slow bob and turn (lighter pickups move quicker).
			_bob_phase += delta * 1.6
			var y: float = PLATE_Y + sin(_bob_phase) * PICKUP_BOB
			_body.position.y = y
			_membrane.position.y = y
			_body.rotation.y += delta * 0.7
		SimConst.EntityType.LAUNCH_PAD:
			_membrane.set_instance_shader_parameter("ripple", _ripple * 2.0)
	# Appear: matter rises out of the floor (mechanical ease-out, no overshoot).
	var a: float = ease(appear, 0.4)
	position.y = (a - 1.0) * 0.6
	if (
		entity_type == SimConst.EntityType.PHASE_GATE
		or entity_type == SimConst.EntityType.FORM_GATE
		or entity_type == SimConst.EntityType.PULSE_GATE
	):
		# Gates (arches, shutters and their posts) go back into the floor once passed.
		position.y -= arch_sink(core_d - lvl.e_d[entity_index]) * ARCH_SINK_DEPTH


## How far a passed gate arch has sunk (0..1) [param through] metres after the
## core went through it: its top beam would otherwise cross the camera's line to
## the core (the player is never hidden, ART_DIRECTION §2), so it goes back into
## the floor as quickly as it rose.
static func arch_sink(through: float) -> float:
	return smoothstep(ARCH_SINK_FROM, ARCH_SINK_TO, through)


## Shutter panel physically drops into its floor slot while the gate is open.
## The visual is conservative: it is fully raised whenever the sim blocks.
func _animate_shutter(lvl: SimLevel, sim_time: float) -> void:
	var period: float = lvl.e_p0[entity_index]
	var open_frac: float = lvl.e_p1[entity_index]
	var t: float = lvl.pulse_cycle(entity_index, sim_time) * period
	var open_end: float = open_frac * period
	var lowered: float = 0.0
	if t < open_end:
		var opening: float = clampf(t / SHUTTER_RAMP, 0.0, 1.0)
		var closing: float = clampf((open_end - t) / SHUTTER_RAMP, 0.0, 1.0)
		lowered = smoothstep(0.0, 1.0, minf(opening, closing))
	var h: float = ViewKit.BLOCK_HEIGHT
	_body.position.y = h * 0.5 - lowered * (h - 0.04)
	var until_close: float = open_end - t
	var warn: bool = t >= open_end or (until_close < LAMP_WARN_TIME and fmod(until_close, 0.12) < 0.06)
	if int(warn) == _lamp_warn:
		return
	_lamp_warn = int(warn)
	for lamp: MeshInstance3D in _lamps:
		lamp.material_override = _kit.lamp_on_material if warn else _kit.lamp_off_material
