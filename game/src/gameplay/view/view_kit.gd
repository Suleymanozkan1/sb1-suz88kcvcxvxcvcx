class_name ViewKit
extends RefCounted
## Shared meshes and materials for one world (built once, shared by every
## entity of a kind). Implements the material language of ART_DIRECTION §5:
## matter is lit PBR and never emissive; only energy (membranes, pickups,
## functional lamps) uses emission.

const GLASS_SHADER: Shader = preload("res://assets/shaders/glass.gdshader")
const MEMBRANE_SHADER: Shader = preload("res://assets/shaders/membrane.gdshader")
const CHEVRON_SHADER: Shader = preload("res://assets/shaders/chevron.gdshader")
const CORE_SHADER: Shader = preload("res://assets/shaders/core.gdshader")
const BLOCK_HEIGHT: float = 0.9
const SHUTTER_THICKNESS: float = 0.12
const POST_WIDTH: float = 0.12
const ARCH_HEIGHT: float = 1.7
const ARCH_POST: float = 0.18

## Physically motivated presets per structure material: albedo scale,
## roughness, metallic, specular, clearcoat.
const STRUCTURE_PRESETS: Dictionary = {
	"anodised": [1.0, 0.42, 0.85, 0.5, 0.0],
	"steel": [1.0, 0.5, 0.9, 0.5, 0.0],
	"stone": [1.0, 0.88, 0.0, 0.3, 0.0],
	"ceramic": [1.0, 0.3, 0.0, 0.6, 0.0],
	"coated": [1.0, 0.55, 0.6, 0.5, 0.0],
	"ice": [1.0, 0.18, 0.0, 0.6, 0.0],
	"sandstone": [1.0, 0.9, 0.0, 0.3, 0.0],
	"obsidian": [1.0, 0.25, 0.2, 0.6, 0.0],
	"lacquer": [1.0, 0.22, 0.0, 0.55, 1.0],
	"crystal": [1.0, 0.16, 0.0, 0.7, 0.6],
}
## Hazards use a bolder chamfer (same family) so blocks read as machined parts.
const HAZARD_CHAMFER: float = 0.16
## Launch pad slab and mass plate dimensions (world units).
const PAD_SIZE: Vector3 = Vector3(1.0, 0.08, 0.9)
const PLATE_SIZE: Vector3 = Vector3(0.46, 0.07, 0.46)
## Gravity-well arrows are about this long, whatever the well's span.
const GRAVITY_ARROW_LENGTH: float = 1.6
## Floor force fields stay below the gameplay: a gravity well is a large area,
## so its arrows are dimmer than a pad's (the pale low-g colour dimmer still).
const PAD_CHEVRON_INTENSITY: float = 0.45
const GRAVITY_CHEVRON_INTENSITY: float = 0.2

static var _soft_dot: GradientTexture2D

var theme: WorldTheme
var block_mesh: ArrayMesh
var slider_mesh: ArrayMesh
var glass_mesh: ArrayMesh
var shutter_mesh: ArrayMesh
var post_mesh: ArrayMesh
var lamp_mesh: ArrayMesh
var portal_ring_mesh: TorusMesh
var disc_mesh: QuadMesh
var floor_disc_mesh: QuadMesh
var shield_mesh: TorusMesh
var magnet_mesh: CapsuleMesh
var blob_mesh: QuadMesh
var pad_mesh: ArrayMesh
var pad_insert_mesh: QuadMesh
var plate_mesh: ArrayMesh
var plate_ring_mesh: TorusMesh

var hazard_material: StandardMaterial3D
var structure_material: StandardMaterial3D
var track_material: StandardMaterial3D
var lamp_off_material: StandardMaterial3D
var lamp_on_material: StandardMaterial3D
var glass_material: ShaderMaterial
var blob_material: StandardMaterial3D
var portal_material: ShaderMaterial
var exit_material: ShaderMaterial
var chevron_material: ShaderMaterial
var shield_material: StandardMaterial3D
var magnet_material: ShaderMaterial
## Launch pad insert: an energy force pointing down the track.
var pad_material: ShaderMaterial
## Mass plate: matte ballast (matter) with a thin energy ring (collectible).
var ballast_material: StandardMaterial3D
var plate_ring_material: StandardMaterial3D

## Colour-blind aid: phase gates carry a shape marker (A = ring, B = diamond).
var colorblind: bool = false

var _phase_materials: Array[ShaderMaterial] = []
var _phase_marker_meshes: Array[Mesh] = []
var _phase_marker_materials: Array[ShaderMaterial] = []
var _arch_meshes: Dictionary = {}
var _membrane_meshes: Dictionary = {}
var _track_meshes: Dictionary = {}
var _chevron_meshes: Dictionary = {}
var _form_materials: Dictionary = {}
var _form_icon_meshes: Dictionary = {}
var _form_icon_materials: Dictionary = {}
var _gravity_strips: Dictionary = {}
var _gravity_materials: Array[ShaderMaterial] = []
var _rail_meshes: Dictionary = {}


func _init(world_theme: WorldTheme) -> void:
	theme = world_theme
	var bw: float = SimConst.BLOCK_HALF_WIDTH * 2.0
	block_mesh = MeshFactory.chamfered_box(Vector3(bw, BLOCK_HEIGHT, SimConst.HAZARD_HALF_DEPTH * 2.0), HAZARD_CHAMFER)
	slider_mesh = MeshFactory.chamfered_box(
		Vector3(bw, BLOCK_HEIGHT * 0.82, SimConst.HAZARD_HALF_DEPTH * 2.3), HAZARD_CHAMFER
	)
	glass_mesh = MeshFactory.chamfered_box(
		Vector3(bw * 0.97, BLOCK_HEIGHT * 0.95, SimConst.HAZARD_HALF_DEPTH * 1.9), HAZARD_CHAMFER
	)
	shutter_mesh = MeshFactory.chamfered_box(Vector3(bw, BLOCK_HEIGHT, SHUTTER_THICKNESS), HAZARD_CHAMFER)
	post_mesh = MeshFactory.chamfered_box(Vector3(POST_WIDTH, BLOCK_HEIGHT * 1.25, 0.2))
	lamp_mesh = MeshFactory.chamfered_box(Vector3(0.1, 0.08, 0.1), 0.2)
	portal_ring_mesh = TorusMesh.new()
	portal_ring_mesh.inner_radius = 0.5
	portal_ring_mesh.outer_radius = 0.6
	portal_ring_mesh.rings = 32
	portal_ring_mesh.ring_segments = 8
	disc_mesh = QuadMesh.new()
	disc_mesh.size = Vector2(1.0, 1.0)
	floor_disc_mesh = QuadMesh.new()
	floor_disc_mesh.size = Vector2(1.1, 1.1)
	floor_disc_mesh.orientation = PlaneMesh.FACE_Y
	shield_mesh = TorusMesh.new()
	shield_mesh.inner_radius = 0.2
	shield_mesh.outer_radius = 0.27
	shield_mesh.rings = 6
	shield_mesh.ring_segments = 4
	magnet_mesh = CapsuleMesh.new()
	magnet_mesh.radius = 0.1
	magnet_mesh.height = 0.5
	blob_mesh = QuadMesh.new()
	blob_mesh.size = Vector2(bw * 1.25, SimConst.HAZARD_HALF_DEPTH * 4.0)
	blob_mesh.orientation = PlaneMesh.FACE_Y
	pad_mesh = MeshFactory.chamfered_box(PAD_SIZE)
	pad_insert_mesh = QuadMesh.new()
	pad_insert_mesh.size = Vector2(PAD_SIZE.z * 0.8, PAD_SIZE.x * 0.7)
	pad_insert_mesh.orientation = PlaneMesh.FACE_Y
	plate_mesh = MeshFactory.chamfered_box(PLATE_SIZE, HAZARD_CHAMFER)
	plate_ring_mesh = TorusMesh.new()
	plate_ring_mesh.inner_radius = 0.3
	plate_ring_mesh.outer_radius = 0.33
	plate_ring_mesh.rings = 24
	plate_ring_mesh.ring_segments = 4
	_build_materials()


func _build_materials() -> void:
	hazard_material = StandardMaterial3D.new()
	# High-key light lifts and desaturates the warm albedo after tonemapping;
	# a deeper base keeps the same perceived WARNING hue in bright worlds.
	hazard_material.albedo_color = Palette.WARNING.darkened(0.28) if theme.bright else Palette.WARNING
	hazard_material.roughness = 0.55
	hazard_material.metallic = 0.0
	hazard_material.metallic_specular = 0.5
	hazard_material.rim_enabled = true
	hazard_material.rim = 0.22
	hazard_material.rim_tint = 0.4
	# Small matte blocks gain nothing from self-shadowing; avoids shadow acne.
	hazard_material.disable_receive_shadows = true
	structure_material = _structure(theme.structure, theme.rib_material)
	track_material = StandardMaterial3D.new()
	track_material.albedo_color = theme.lane_color.darkened(0.45)
	track_material.roughness = 0.7
	track_material.metallic = 0.3
	lamp_off_material = StandardMaterial3D.new()
	lamp_off_material.albedo_color = Color("#3a2a20")
	lamp_off_material.roughness = 0.4
	lamp_on_material = StandardMaterial3D.new()
	lamp_on_material.albedo_color = Palette.ACCENT
	lamp_on_material.emission_enabled = true
	lamp_on_material.emission = Palette.ACCENT
	lamp_on_material.emission_energy_multiplier = 2.2
	glass_material = ShaderMaterial.new()
	glass_material.shader = GLASS_SHADER
	glass_material.set_shader_parameter("tint", Palette.GLASS_TINT)
	blob_material = StandardMaterial3D.new()
	blob_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blob_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blob_material.albedo_texture = _blob_texture()
	blob_material.albedo_color = Color(0, 0, 0, 0.38)
	blob_material.render_priority = -1
	for c: int in 2:
		_phase_materials.append(_membrane(Palette.PHASE[c], false, 0.24))
	portal_material = _membrane(Palette.PRIMARY, true, 0.18)
	exit_material = _membrane(Palette.PRIMARY, true, 0.1)
	chevron_material = ShaderMaterial.new()
	chevron_material.shader = CHEVRON_SHADER
	chevron_material.set_shader_parameter("energy", Palette.PRIMARY)
	shield_material = StandardMaterial3D.new()
	shield_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shield_material.albedo_color = Palette.SUCCESS * Palette.ENERGY_SPARK
	magnet_material = ShaderMaterial.new()
	magnet_material.shader = CORE_SHADER
	magnet_material.set_shader_parameter("color_a", Palette.PRIMARY)
	magnet_material.set_shader_parameter("color_b", Palette.SECONDARY)
	magnet_material.set_shader_parameter("style", 8)
	magnet_material.set_shader_parameter("intensity", 1.3)
	pad_material = _chevrons(Palette.PRIMARY, 1.0, 3.0, PAD_CHEVRON_INTENSITY)
	ballast_material = StandardMaterial3D.new()
	ballast_material.albedo_color = Palette.FORM_SURGE_HEAVY.darkened(0.45)
	ballast_material.roughness = 0.45
	ballast_material.metallic = 0.6
	plate_ring_material = StandardMaterial3D.new()
	plate_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plate_ring_material.albedo_color = Palette.FORM_SURGE_HEAVY * Palette.ENERGY_SPARK
	# Gravity wells: heavy arrows rush down the track, light ones drift back
	# towards the player (direction is the second cue besides the colour).
	_gravity_materials.append(_chevrons(Palette.FORM_SURGE_LIGHT, -1.0, 1.0, GRAVITY_CHEVRON_INTENSITY * 0.6))
	_gravity_materials.append(_chevrons(Palette.FORM_SURGE_HEAVY, 1.0, 3.5, GRAVITY_CHEVRON_INTENSITY))


func _chevrons(color: Color, direction: float, speed: float, intensity: float) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = CHEVRON_SHADER
	m.set_shader_parameter("energy", color)
	m.set_shader_parameter("direction", direction)
	m.set_shader_parameter("speed", speed)
	m.set_shader_parameter("intensity", intensity)
	return m


func _structure(albedo: Color, kind: String) -> StandardMaterial3D:
	var p: Array = STRUCTURE_PRESETS.get(kind, STRUCTURE_PRESETS["anodised"]) as Array
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = albedo * float(p[0])
	m.roughness = float(p[1])
	m.metallic = float(p[2])
	m.metallic_specular = float(p[3])
	if float(p[4]) > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = float(p[4])
		m.clearcoat_roughness = 0.15
	return m


func _membrane(color: Color, radial: bool, density: float) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = MEMBRANE_SHADER
	m.set_shader_parameter("energy", color)
	m.set_shader_parameter("radial", radial)
	m.set_shader_parameter("density", density)
	m.set_shader_parameter("intensity", Palette.ENERGY_MEMBRANE)
	return m


## Shared soft round mask for motes and particles.
static func soft_dot_texture() -> GradientTexture2D:
	if _soft_dot == null:
		_soft_dot = _blob_texture()
	return _soft_dot


static func _blob_texture() -> GradientTexture2D:
	var tex: GradientTexture2D = GradientTexture2D.new()
	var g: Gradient = Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	return tex


func phase_material(color: int) -> ShaderMaterial:
	return _phase_materials[clampi(color, 0, 1)]


## Shape marker for a phase (colour-blind aid): phase A is a ring, phase B a
## diamond, so the two phases differ by silhouette, not only by hue.
func phase_marker_mesh(color: int) -> Mesh:
	if _phase_marker_meshes.is_empty():
		var ring: TorusMesh = TorusMesh.new()
		ring.inner_radius = 0.15
		ring.outer_radius = 0.23
		ring.rings = 24
		ring.ring_segments = 6
		_phase_marker_meshes.append(ring)
		_phase_marker_meshes.append(MeshFactory.shard(0.22, 0.5))
	return _phase_marker_meshes[clampi(color, 0, 1)]


func phase_marker_material(color: int) -> ShaderMaterial:
	if _phase_marker_materials.is_empty():
		for c: Color in Palette.PHASE:
			var m: ShaderMaterial = ShaderMaterial.new()
			m.shader = CORE_SHADER
			m.set_shader_parameter("color_a", c)
			m.set_shader_parameter("color_b", c.darkened(0.3))
			m.set_shader_parameter("intensity", 1.4)
			_phase_marker_materials.append(m)
	return _phase_marker_materials[clampi(color, 0, 1)]


## Chamfered arch spanning every lane (gates): posts + lintel in the
## structure material.
func arch_mesh(lanes: int) -> ArrayMesh:
	if _arch_meshes.has(lanes):
		return _arch_meshes[lanes] as ArrayMesh
	var half: float = float(lanes) * SimConst.LANE_WIDTH * 0.5 + 0.3
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0, 1.0]:
		st.append_from(
			MeshFactory.chamfered_box(Vector3(ARCH_POST, ARCH_HEIGHT, ARCH_POST)),
			0,
			Transform3D(Basis.IDENTITY, Vector3(side * half, ARCH_HEIGHT * 0.5, 0))
		)
	st.append_from(
		MeshFactory.chamfered_box(Vector3(half * 2.0 + ARCH_POST, ARCH_POST, ARCH_POST)),
		0,
		Transform3D(Basis.IDENTITY, Vector3(0, ARCH_HEIGHT, 0))
	)
	var mesh: ArrayMesh = st.commit()
	_arch_meshes[lanes] = mesh
	return mesh


func membrane_mesh(lanes: int) -> QuadMesh:
	if not _membrane_meshes.has(lanes):
		var q: QuadMesh = QuadMesh.new()
		q.size = Vector2(float(lanes) * SimConst.LANE_WIDTH + 0.6 - ARCH_POST, ARCH_HEIGHT - ARCH_POST * 0.5)
		_membrane_meshes[lanes] = q
	return _membrane_meshes[lanes] as QuadMesh


## Recessed floor track showing a slider's full travel (readability: range).
func track_mesh(lanes: int, from_lane: int, to_lane: int) -> QuadMesh:
	var key: String = "%d:%d:%d" % [lanes, from_lane, to_lane]
	if not _track_meshes.has(key):
		var x0: float = SimConst.lane_x(from_lane, lanes)
		var x1: float = SimConst.lane_x(to_lane, lanes)
		var q: QuadMesh = QuadMesh.new()
		q.size = Vector2(absf(x1 - x0) + SimConst.BLOCK_HALF_WIDTH * 2.0, 0.16)
		q.orientation = PlaneMesh.FACE_Y
		q.center_offset = Vector3((x0 + x1) * 0.5, 0.012, 0.0)
		_track_meshes[key] = q
	return _track_meshes[key] as QuadMesh


func chevron_mesh(lanes: int, from_lane: int, to_lane: int) -> QuadMesh:
	var key: String = "%d:%d:%d" % [lanes, from_lane, to_lane]
	if not _chevron_meshes.has(key):
		var x0: float = SimConst.lane_x(from_lane, lanes)
		var x1: float = SimConst.lane_x(to_lane, lanes)
		var q: QuadMesh = QuadMesh.new()
		q.size = Vector2(absf(x1 - x0) + 1.0, 1.2)
		q.orientation = PlaneMesh.FACE_Y
		q.center_offset = Vector3((x0 + x1) * 0.5, 0.015, 0.0)
		_chevron_meshes[key] = q
	return _chevron_meshes[key] as QuadMesh


## Floor strip of a gravity well: [param span] long, across every lane. Its
## local +x runs along the strip (rotate it 90° about Y to point down the track).
func gravity_strip_mesh(lanes: int, span: float) -> QuadMesh:
	var key: String = "%d:%.2f" % [lanes, span]
	if not _gravity_strips.has(key):
		var q: QuadMesh = QuadMesh.new()
		q.size = Vector2(span, float(lanes) * SimConst.LANE_WIDTH + 0.3)
		q.orientation = PlaneMesh.FACE_Y
		_gravity_strips[key] = q
	return _gravity_strips[key] as QuadMesh


func gravity_material(heavy: bool) -> ShaderMaterial:
	return _gravity_materials[1 if heavy else 0]


## Matte rail across every lane marking where a gravity well begins and ends.
func rail_mesh(lanes: int) -> ArrayMesh:
	if not _rail_meshes.has(lanes):
		_rail_meshes[lanes] = MeshFactory.chamfered_box(Vector3(float(lanes) * SimConst.LANE_WIDTH + 0.4, 0.05, 0.1))
	return _rail_meshes[lanes] as ArrayMesh


func form_material(form: int) -> ShaderMaterial:
	if not _form_materials.has(form):
		_form_materials[form] = _membrane(Palette.form_color(form, 0, false), false, 0.16)
	return _form_materials[form] as ShaderMaterial


func form_icon_mesh(form: int) -> Mesh:
	if _form_icon_meshes.has(form):
		return _form_icon_meshes[form] as Mesh
	var mesh: Mesh
	match form:
		SimConst.Form.PHASE:
			mesh = MeshFactory.shard(0.2, 0.46)
		SimConst.Form.DASH:
			var c: CapsuleMesh = CapsuleMesh.new()
			c.radius = 0.12
			c.height = 0.5
			mesh = c
		SimConst.Form.SURGE:
			var t: TorusMesh = TorusMesh.new()
			t.inner_radius = 0.14
			t.outer_radius = 0.2
			mesh = t
		_:
			var s: SphereMesh = SphereMesh.new()
			s.radius = 0.17
			s.height = 0.34
			mesh = s
	_form_icon_meshes[form] = mesh
	return mesh


func form_icon_material(form: int) -> ShaderMaterial:
	if not _form_icon_materials.has(form):
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = CORE_SHADER
		var c: Color = Palette.form_color(form, 0, false)
		m.set_shader_parameter("color_a", c)
		m.set_shader_parameter("color_b", c.darkened(0.3))
		m.set_shader_parameter("intensity", 1.4)
		_form_icon_materials[form] = m
	return _form_icon_materials[form] as ShaderMaterial
