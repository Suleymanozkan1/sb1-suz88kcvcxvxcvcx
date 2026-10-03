class_name ViewKit
extends RefCounted
## Shared meshes and materials for one world theme (built once per world, so
## every entity of a kind shares the same resources — draw-call friendly).

const HAZARD_SHADER: Shader = preload("res://assets/shaders/hazard.gdshader")
const PORTAL_SHADER: Shader = preload("res://assets/shaders/portal.gdshader")
const GLOW_SHADER: Shader = preload("res://assets/shaders/glow_sprite.gdshader")
const CORE_SHADER: Shader = preload("res://assets/shaders/core.gdshader")
const FORM_COLORS: Array[Color] = [Color("#3df5ff"), Color("#ff3dcb"), Color("#ffb03d"), Color("#b8a6ff")]

var theme: WorldTheme
var block_mesh: BoxMesh
var pulse_mesh: BoxMesh
var breakable_mesh: BoxMesh
var slider_mesh: BoxMesh
var portal_mesh: QuadMesh
var portal_exit_mesh: QuadMesh
var pickup_mesh: QuadMesh
var magnet_mesh: TorusMesh
var hazard_material: ShaderMaterial
var pulse_material: ShaderMaterial
var breakable_material: ShaderMaterial
var slider_material: ShaderMaterial
var portal_material: ShaderMaterial
var current_material: ShaderMaterial
var shield_material: ShaderMaterial
var magnet_material: ShaderMaterial
var _phase_materials: Array[ShaderMaterial] = []
var _phase_meshes: Dictionary = {}
var _form_gate_meshes: Dictionary = {}
var _form_gate_materials: Dictionary = {}
var _form_icon_meshes: Dictionary = {}
var _form_icon_materials: Dictionary = {}
var _current_meshes: Dictionary = {}


func _init(world_theme: WorldTheme) -> void:
	theme = world_theme
	var half: Vector3 = Vector3(SimConst.BLOCK_HALF_WIDTH, EntityView.HAZARD_HEIGHT * 0.5, SimConst.HAZARD_HALF_DEPTH)
	block_mesh = BoxMesh.new()
	block_mesh.size = half * 2.0
	pulse_mesh = BoxMesh.new()
	pulse_mesh.size = Vector3(half.x * 2.0, EntityView.HAZARD_HEIGHT, 0.14)
	breakable_mesh = BoxMesh.new()
	breakable_mesh.size = Vector3(half.x * 1.9, EntityView.HAZARD_HEIGHT * 0.9, half.z * 1.8)
	slider_mesh = BoxMesh.new()
	slider_mesh.size = Vector3(half.x * 2.0, EntityView.HAZARD_HEIGHT * 0.8, half.z * 2.0)
	var body: Color = theme.floor_color.darkened(0.35) if not theme.bright else Color("#2a2f55")
	hazard_material = _hazard(body, theme.hazard, half, theme.hazard_style)
	pulse_material = _hazard(body.darkened(0.2), theme.accent, Vector3(half.x, EntityView.HAZARD_HEIGHT * 0.5, 0.07), 5)
	breakable_material = _hazard(Color("#3a2410"), EntityView.BREAKABLE_COLOR, half * Vector3(0.95, 0.9, 0.9), 1)
	slider_material = _hazard(body, theme.secondary, half * Vector3(1.0, 0.8, 1.0), 9 if theme.hazard_style == 9 else theme.hazard_style)
	portal_mesh = QuadMesh.new()
	portal_mesh.size = Vector2(1.3, 1.3)
	portal_exit_mesh = QuadMesh.new()
	portal_exit_mesh.size = Vector2(1.2, 1.2)
	portal_material = ShaderMaterial.new()
	portal_material.shader = PORTAL_SHADER
	portal_material.set_shader_parameter("color_a", theme.primary)
	portal_material.set_shader_parameter("color_b", theme.secondary)
	current_material = ShaderMaterial.new()
	current_material.shader = PORTAL_SHADER
	current_material.set_shader_parameter("color_a", theme.accent)
	current_material.set_shader_parameter("color_b", theme.primary)
	current_material.set_shader_parameter("swirl", 3.0)
	pickup_mesh = QuadMesh.new()
	pickup_mesh.size = Vector2(0.9, 0.9)
	shield_material = ShaderMaterial.new()
	shield_material.shader = GLOW_SHADER
	shield_material.set_shader_parameter("glow_color", Color("#9fffe0"))
	shield_material.set_shader_parameter("ring", 0.7)
	shield_material.set_shader_parameter("intensity", 1.6)
	magnet_mesh = TorusMesh.new()
	magnet_mesh.inner_radius = 0.16
	magnet_mesh.outer_radius = 0.26
	magnet_material = ShaderMaterial.new()
	magnet_material.shader = CORE_SHADER
	magnet_material.set_shader_parameter("color_a", Color("#ff5c8a"))
	magnet_material.set_shader_parameter("color_b", Color("#5cc8ff"))
	magnet_material.set_shader_parameter("style", 8)
	for c: int in 2:
		var m: ShaderMaterial = _hazard(EntityView.PHASE_COLORS[c].darkened(0.75), EntityView.PHASE_COLORS[c], Vector3(1.0, 0.6, 0.05), 5)
		_phase_materials.append(m)


func _hazard(body: Color, edge: Color, half: Vector3, style: int) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = HAZARD_SHADER
	m.set_shader_parameter("base_color", body)
	m.set_shader_parameter("edge_color", edge)
	m.set_shader_parameter("half_extents", half)
	m.set_shader_parameter("style", style)
	return m


func phase_material(color: int) -> ShaderMaterial:
	return _phase_materials[clampi(color, 0, 1)]


func phase_gate_mesh(lanes: int) -> BoxMesh:
	if not _phase_meshes.has(lanes):
		var b: BoxMesh = BoxMesh.new()
		b.size = Vector3(float(lanes) * SimConst.LANE_WIDTH + 0.3, 1.2, 0.1)
		_phase_meshes[lanes] = b
		var half: Vector3 = b.size * 0.5
		for m: ShaderMaterial in _phase_materials:
			m.set_shader_parameter("half_extents", half)
	return _phase_meshes[lanes] as BoxMesh


func form_gate_mesh(lanes: int) -> QuadMesh:
	if not _form_gate_meshes.has(lanes):
		var q: QuadMesh = QuadMesh.new()
		q.size = Vector2(float(lanes) * SimConst.LANE_WIDTH + 1.2, 1.8)
		_form_gate_meshes[lanes] = q
	return _form_gate_meshes[lanes] as QuadMesh


func form_gate_material(form: int) -> ShaderMaterial:
	if not _form_gate_materials.has(form):
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = PORTAL_SHADER
		m.set_shader_parameter("color_a", FORM_COLORS[clampi(form, 0, 3)])
		m.set_shader_parameter("color_b", Color.WHITE)
		m.set_shader_parameter("opacity", 0.8)
		_form_gate_materials[form] = m
	return _form_gate_materials[form] as ShaderMaterial


func form_icon_mesh(form: int) -> Mesh:
	if _form_icon_meshes.has(form):
		return _form_icon_meshes[form] as Mesh
	var mesh: Mesh
	match form:
		SimConst.Form.PHASE:
			var d: SphereMesh = SphereMesh.new()
			d.radius = 0.28
			d.height = 0.64
			d.radial_segments = 4
			d.rings = 2
			mesh = d
		SimConst.Form.DASH:
			var c: CapsuleMesh = CapsuleMesh.new()
			c.radius = 0.18
			c.height = 0.8
			mesh = c
		SimConst.Form.SURGE:
			var t: TorusMesh = TorusMesh.new()
			t.inner_radius = 0.2
			t.outer_radius = 0.3
			mesh = t
		_:
			var s: SphereMesh = SphereMesh.new()
			s.radius = 0.26
			s.height = 0.52
			mesh = s
	_form_icon_meshes[form] = mesh
	return mesh


func form_icon_material(form: int) -> ShaderMaterial:
	if not _form_icon_materials.has(form):
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = CORE_SHADER
		m.set_shader_parameter("color_a", FORM_COLORS[clampi(form, 0, 3)])
		m.set_shader_parameter("color_b", Color.WHITE)
		_form_icon_materials[form] = m
	return _form_icon_materials[form] as ShaderMaterial


## Chevron strip on the floor pointing from the current's lane to its target.
func current_mesh(lvl: SimLevel, index: int) -> Mesh:
	var lanes: int = lvl.lane_count
	var key: String = "%d:%d:%d" % [lanes, lvl.e_mask[index], int(lvl.e_p0[index])]
	if _current_meshes.has(key):
		return _current_meshes[key] as Mesh
	var from_lane: int = 0
	for l: int in lanes:
		if (lvl.e_mask[index] & (1 << l)) != 0:
			from_lane = l
	var x0: float = SimConst.lane_x(from_lane, lanes)
	var x1: float = SimConst.lane_x(int(lvl.e_p0[index]), lanes)
	var q: QuadMesh = QuadMesh.new()
	q.size = Vector2(absf(x1 - x0) + 1.2, 1.4)
	q.orientation = PlaneMesh.FACE_Y
	q.center_offset = Vector3((x0 + x1) * 0.5, 0.0, 0.0)
	_current_meshes[key] = q
	return q
