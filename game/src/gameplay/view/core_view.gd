class_name CoreView
extends Node3D
## The energy core — the game's signature visual.
##
## Its *form* is readable at a glance: ORB (sphere, hop), PRISM (diamond,
## phase colour), COMET (stretched, dash), SURGE (ringed, weight). Squash /
## stretch, scale punch and spin are spring-driven; charges orbit as shards
## (stacking); a halo sprite and an optional light provide the glow.

const CORE_SHADER: Shader = preload("res://assets/shaders/core.gdshader")
const GLOW_SHADER: Shader = preload("res://assets/shaders/glow_sprite.gdshader")
const PHASE_COLORS: Array[Color] = [Color("#3df5ff"), Color("#ff3dcb")]
const DASH_COLOR: Color = Color("#ffb03d")
const HEAVY_COLOR: Color = Color("#7a5cff")
const LIGHT_COLOR: Color = Color("#c8fff4")
const SPRING_K: float = 260.0
const SPRING_D: float = 16.0

var body: MeshInstance3D
var halo: MeshInstance3D
var shield_bubble: MeshInstance3D
var chevron: MeshInstance3D
var ring: MeshInstance3D
var light: OmniLight3D
var shards: Array[MeshInstance3D] = []

var skin_style: int = 0
var skin_color_a: Color = Color("#3df5ff")
var skin_color_b: Color = Color("#ff3dcb")
var skin_rim: Color = Color.WHITE
var reduce_motion: bool = false

var _mat: ShaderMaterial = ShaderMaterial.new()
var _halo_mat: ShaderMaterial = ShaderMaterial.new()
var _shield_mat: ShaderMaterial = ShaderMaterial.new()
var _form: int = -1
var _meshes: Dictionary = {}
var _scale_off: Vector3 = Vector3.ZERO
var _scale_vel: Vector3 = Vector3.ZERO
var _spin: float = 0.0
var _pulse: float = 0.0
var _charges_shown: int = 0
var _shard_angle: float = 0.0
var _spawn: float = 1.0


func _ready() -> void:
	_build_meshes()
	body = MeshInstance3D.new()
	_mat.shader = CORE_SHADER
	body.material_override = _mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(body)
	halo = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	halo.mesh = quad
	_halo_mat.shader = GLOW_SHADER
	_halo_mat.set_shader_parameter("size", 2.4)
	_halo_mat.set_shader_parameter("intensity", 0.55)
	halo.material_override = _halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)
	shield_bubble = MeshInstance3D.new()
	_shield_mat.shader = GLOW_SHADER
	_shield_mat.set_shader_parameter("size", 1.6)
	_shield_mat.set_shader_parameter("ring", 0.82)
	_shield_mat.set_shader_parameter("glow_color", Color("#9fffe0"))
	shield_bubble.mesh = quad
	shield_bubble.material_override = _shield_mat
	shield_bubble.visible = false
	add_child(shield_bubble)
	ring = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	ring.mesh = torus
	ring.material_override = _mat
	ring.visible = false
	add_child(ring)
	chevron = MeshInstance3D.new()
	var prism: PrismMesh = PrismMesh.new()
	prism.size = Vector3(0.22, 0.16, 0.06)
	chevron.mesh = prism
	chevron.material_override = _mat
	chevron.rotation_degrees = Vector3(-90, 0, -90)
	chevron.visible = false
	add_child(chevron)
	for i: int in SimConst.MAX_CHARGES:
		var s: MeshInstance3D = MeshInstance3D.new()
		var d: SphereMesh = SphereMesh.new()
		d.radius = 0.06
		d.height = 0.16
		d.radial_segments = 4
		d.rings = 2
		s.mesh = d
		s.material_override = _mat
		s.visible = false
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
		shards.append(s)
	light = OmniLight3D.new()
	light.omni_range = 4.5
	light.light_energy = 1.4
	light.shadow_enabled = false
	add_child(light)
	set_form(SimConst.Form.HOP, 0, false)
	apply_skin_colors()


func _build_meshes() -> void:
	var orb: SphereMesh = SphereMesh.new()
	orb.radius = SimConst.CORE_RADIUS
	orb.height = SimConst.CORE_RADIUS * 2.0
	orb.radial_segments = 32
	orb.rings = 16
	_meshes[SimConst.Form.HOP] = orb
	var prism: SphereMesh = SphereMesh.new()
	prism.radius = SimConst.CORE_RADIUS * 1.15
	prism.height = SimConst.CORE_RADIUS * 2.6
	prism.radial_segments = 4
	prism.rings = 2
	_meshes[SimConst.Form.PHASE] = prism
	var comet: CapsuleMesh = CapsuleMesh.new()
	comet.radius = SimConst.CORE_RADIUS * 0.85
	comet.height = SimConst.CORE_RADIUS * 3.2
	_meshes[SimConst.Form.DASH] = comet
	var surge: SphereMesh = SphereMesh.new()
	surge.radius = SimConst.CORE_RADIUS * 0.8
	surge.height = SimConst.CORE_RADIUS * 1.6
	_meshes[SimConst.Form.SURGE] = surge


## Applies cosmetic skin parameters (cosmetics never touch gameplay state).
func apply_skin(style: int, color_a: Color, color_b: Color, rim: Color) -> void:
	skin_style = style
	skin_color_a = color_a
	skin_color_b = color_b
	skin_rim = rim
	apply_skin_colors()


func apply_skin_colors() -> void:
	_mat.set_shader_parameter("style", skin_style)
	_mat.set_shader_parameter("color_a", skin_color_a)
	_mat.set_shader_parameter("color_b", skin_color_b)
	_mat.set_shader_parameter("rim_color", skin_rim)
	_halo_mat.set_shader_parameter("glow_color", skin_color_a)
	light.light_color = skin_color_a


func set_light_enabled(enabled: bool) -> void:
	light.visible = enabled


func set_form(form: int, phase: int, heavy: bool) -> void:
	if form != _form:
		_form = form
		body.mesh = _meshes.get(form, _meshes[SimConst.Form.HOP]) as Mesh
		body.rotation = Vector3.ZERO
		if form == SimConst.Form.DASH:
			body.rotation_degrees = Vector3(90, 0, 0)
		ring.visible = form == SimConst.Form.SURGE
		punch(0.5)
	var tint: Color = skin_color_a
	match form:
		SimConst.Form.PHASE:
			tint = PHASE_COLORS[clampi(phase, 0, 1)]
		SimConst.Form.DASH:
			tint = DASH_COLOR
		SimConst.Form.SURGE:
			tint = HEAVY_COLOR if heavy else LIGHT_COLOR
	if form == SimConst.Form.HOP:
		_mat.set_shader_parameter("color_a", skin_color_a)
		_halo_mat.set_shader_parameter("glow_color", skin_color_a)
		light.light_color = skin_color_a
	else:
		_mat.set_shader_parameter("color_a", tint)
		_halo_mat.set_shader_parameter("glow_color", tint)
		light.light_color = tint


func set_direction_hint(visible_hint: bool, dir: int) -> void:
	chevron.visible = visible_hint
	chevron.position = Vector3(0.48 * float(dir), 0.0, 0.0)
	chevron.rotation_degrees = Vector3(-90, 0, -90 if dir > 0 else 90)


func set_shield(active: bool) -> void:
	shield_bubble.visible = active


func spawn_in() -> void:
	_spawn = 0.0


## Scale punch (elastic). [param amount] ~0.2–0.8.
func punch(amount: float) -> void:
	_scale_vel += Vector3.ONE * amount * 9.0


## Squash/stretch along a direction (x for hops, z for dashes).
func squash(axis: Vector3, amount: float) -> void:
	_scale_vel += axis * amount * 12.0 - (Vector3.ONE - axis) * amount * 5.0


func flash_pulse(amount: float) -> void:
	_pulse = maxf(_pulse, amount)


func update_visuals(delta: float, sim: FluxSim) -> void:
	_scale_vel += (-_scale_off * SPRING_K - _scale_vel * SPRING_D) * delta
	_scale_off += _scale_vel * delta
	_spawn = minf(1.0, _spawn + delta * 3.0)
	var spawn_scale: float = ease(_spawn, -2.6) if _spawn < 1.0 else 1.0
	var s: Vector3 = (Vector3.ONE + _scale_off).clamp(Vector3(0.4, 0.4, 0.4), Vector3(1.9, 1.9, 1.9)) * spawn_scale
	body.scale = s
	_spin += delta * (2.0 + sim.speed * 0.25) * (0.3 if reduce_motion else 1.0)
	if _form == SimConst.Form.HOP or _form == SimConst.Form.SURGE:
		body.rotation = Vector3(-_spin, _spin * 0.3, 0.0)
	elif _form == SimConst.Form.PHASE:
		body.rotation = Vector3(0.0, _spin * 1.6, 0.0)
	ring.rotation = Vector3(PI * 0.5 + sin(_spin) * 0.3, _spin * 2.0, 0.0)
	_pulse = move_toward(_pulse, 0.0, delta * 4.0)
	_mat.set_shader_parameter("pulse", _pulse)
	_mat.set_shader_parameter("overdrive", 1.0 if sim.overdrive_timer > 0.0 else 0.0)
	var combo_glow: float = clampf(float(sim.combo) / 30.0, 0.0, 1.0)
	_halo_mat.set_shader_parameter("intensity", 0.45 + combo_glow * 0.5 + _pulse * 0.6)
	light.light_energy = 1.2 + combo_glow * 1.2 + _pulse
	set_shield(sim.shields > 0)
	_update_shards(delta, sim.charges if sim.overdrive_timer <= 0.0 else SimConst.MAX_CHARGES)


func _update_shards(delta: float, charges: int) -> void:
	_shard_angle += delta * 3.2
	_charges_shown = charges
	for i: int in shards.size():
		var shard: MeshInstance3D = shards[i]
		shard.visible = i < charges
		if not shard.visible:
			continue
		var a: float = _shard_angle + TAU * float(i) / float(SimConst.MAX_CHARGES)
		shard.position = Vector3(cos(a) * 0.52, sin(a * 2.0) * 0.08 + 0.05, sin(a) * 0.52)
		shard.rotation = Vector3(a, a * 1.3, 0.0)
