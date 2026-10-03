class_name EntityView
extends Node3D
## Pooled visual for one level entity (hazards, gates, markers, pickups).
##
## A single class configured per entity type keeps the pool simple; materials
## are shared per (type, world) and per-object state uses instance uniforms.

const HAZARD_HEIGHT: float = 0.9
const BREAKABLE_COLOR: Color = Color("#ffb03d")
const PHASE_COLORS: Array[Color] = [Color("#3df5ff"), Color("#ff3dcb")]

var entity_index: int = -1
var entity_type: int = -1
var mesh_instance: MeshInstance3D
var extra: MeshInstance3D
var appear: float = 1.0
var _flash: float = 0.0


func _init() -> void:
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	extra = MeshInstance3D.new()
	extra.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(extra)


## Called by [NodePool] on release.
func pool_reset() -> void:
	entity_index = -1
	entity_type = -1
	_flash = 0.0
	mesh_instance.mesh = null
	extra.mesh = null
	extra.visible = false
	scale = Vector3.ONE
	rotation = Vector3.ZERO


func configure(index: int, type: int, lvl: SimLevel, kit: ViewKit) -> void:
	entity_index = index
	entity_type = type
	appear = 0.0
	var lanes: int = lvl.lane_count
	var lane_x: float = SimConst.lane_x(lvl.e_lane[index], lanes)
	position = Vector3(lane_x, 0.0, -lvl.e_d[index])
	mesh_instance.position = Vector3.ZERO
	mesh_instance.rotation = Vector3.ZERO
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	extra.visible = false
	extra.position = Vector3.ZERO
	extra.rotation = Vector3.ZERO
	match type:
		SimConst.EntityType.BARRIER:
			_setup_mask_blocks(lvl, index, kit.block_mesh, kit.hazard_material)
		SimConst.EntityType.PULSE_GATE:
			_setup_mask_blocks(lvl, index, kit.pulse_mesh, kit.pulse_material)
		SimConst.EntityType.BREAKABLE:
			mesh_instance.mesh = kit.breakable_mesh
			mesh_instance.material_override = kit.breakable_material
			mesh_instance.position = Vector3(0.0, HAZARD_HEIGHT * 0.45, 0.0)
		SimConst.EntityType.SLIDER:
			position.x = lvl.slider_x(index, 0.0)
			mesh_instance.mesh = kit.slider_mesh
			mesh_instance.material_override = kit.slider_material
			mesh_instance.position = Vector3(0.0, HAZARD_HEIGHT * 0.4, 0.0)
		SimConst.EntityType.PHASE_GATE:
			position.x = 0.0
			mesh_instance.mesh = kit.phase_gate_mesh(lanes)
			mesh_instance.material_override = kit.phase_material(lvl.e_color[index])
			mesh_instance.position = Vector3(0.0, 0.6, 0.0)
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		SimConst.EntityType.PORTAL:
			mesh_instance.mesh = kit.portal_mesh
			mesh_instance.material_override = kit.portal_material
			mesh_instance.position = Vector3(0.0, 0.55, 0.0)
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			extra.mesh = kit.portal_exit_mesh
			extra.material_override = kit.portal_material
			extra.visible = true
			extra.position = Vector3(SimConst.lane_x(int(lvl.e_p0[index]), lanes) - lane_x, 0.05, -0.2)
			extra.rotation_degrees = Vector3(-90, 0, 0)
		SimConst.EntityType.CURRENT:
			position.x = 0.0
			mesh_instance.mesh = kit.current_mesh(lvl, index)
			mesh_instance.material_override = kit.current_material
			mesh_instance.position = Vector3(0.0, 0.03, 0.0)
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		SimConst.EntityType.FORM_GATE:
			position.x = 0.0
			mesh_instance.mesh = kit.form_gate_mesh(lanes)
			mesh_instance.material_override = kit.form_gate_material(int(lvl.e_p0[index]))
			mesh_instance.position = Vector3(0.0, 0.8, 0.0)
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			extra.mesh = kit.form_icon_mesh(int(lvl.e_p0[index]))
			extra.material_override = kit.form_icon_material(int(lvl.e_p0[index]))
			extra.visible = true
			extra.position = Vector3(0.0, 1.7, 0.0)
		SimConst.EntityType.SHIELD:
			mesh_instance.mesh = kit.pickup_mesh
			mesh_instance.material_override = kit.shield_material
			mesh_instance.position = Vector3(0.0, 0.4, 0.0)
		SimConst.EntityType.MAGNET:
			mesh_instance.mesh = kit.magnet_mesh
			mesh_instance.material_override = kit.magnet_material
			mesh_instance.position = Vector3(0.0, 0.4, 0.0)


func _setup_mask_blocks(lvl: SimLevel, index: int, mesh: Mesh, material: Material) -> void:
	# Multi-lane blocks: one mesh for the first lane, the extra mesh for a second.
	var lanes: Array[int] = []
	for l: int in lvl.lane_count:
		if (lvl.e_mask[index] & (1 << l)) != 0:
			lanes.append(l)
	position.x = 0.0
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.position = Vector3(SimConst.lane_x(lanes[0], lvl.lane_count), HAZARD_HEIGHT * 0.5, 0.0)
	if lanes.size() > 1:
		extra.mesh = mesh
		extra.material_override = material
		extra.visible = true
		extra.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		extra.position = Vector3(SimConst.lane_x(lanes[1], lvl.lane_count), HAZARD_HEIGHT * 0.5, 0.0)


func flash(amount: float) -> void:
	_flash = maxf(_flash, amount)


## Per-frame animation for time-based hazards and appear-in.
func animate(delta: float, lvl: SimLevel, sim_time: float) -> void:
	appear = minf(1.0, appear + delta * 4.0)
	var s: float = ease(appear, -2.0)
	_flash = move_toward(_flash, 0.0, delta * 5.0)
	match entity_type:
		SimConst.EntityType.SLIDER:
			position.x = lvl.slider_x(entity_index, sim_time)
			mesh_instance.set_instance_shader_parameter("flash", _flash)
		SimConst.EntityType.PULSE_GATE:
			var cycle: float = lvl.pulse_cycle(entity_index, sim_time)
			var open_frac: float = lvl.e_p1[entity_index]
			var closed: bool = cycle >= open_frac
			# Open: mostly dissolved; warn glow just before closing.
			var fade: float = 0.0 if closed else 0.82
			var to_close: float = (open_frac - cycle) / maxf(open_frac, 0.01)
			var warn: float = 1.0 if (not closed and to_close < 0.25) else 0.0
			mesh_instance.set_instance_shader_parameter("fade", fade)
			mesh_instance.set_instance_shader_parameter("warn", warn)
			if extra.visible:
				extra.set_instance_shader_parameter("fade", fade)
				extra.set_instance_shader_parameter("warn", warn)
		SimConst.EntityType.PORTAL, SimConst.EntityType.FORM_GATE:
			extra.rotation.y += delta * 2.0
		SimConst.EntityType.SHIELD, SimConst.EntityType.MAGNET:
			mesh_instance.rotation.y += delta * 3.0
		_:
			mesh_instance.set_instance_shader_parameter("flash", _flash)
	scale = Vector3(1.0, s, 1.0)
