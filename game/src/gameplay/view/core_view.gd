class_name CoreView
extends Node3D
## The energy core — the game's signature and visual priority #1.
##
## Its form is told by silhouette (ART_DIRECTION §4): ORB sphere (hop), PRISM
## octahedron (phase), COMET capsule (dash), SURGE sphere-in-ring (weight).
## Motion character (§8): elastic and alive — anticipation squash, stretch
## along the motion, one overshoot, settle. Only the core may bloom strongly.

const CORE_SHADER: Shader = preload("res://assets/shaders/core.gdshader")
const GLOW_SHADER: Shader = preload("res://assets/shaders/glow_sprite.gdshader")
const INK_SHADER: Shader = preload("res://assets/shaders/ink_shell.gdshader")
## In high-key worlds the core trades raw brightness for hue so it never melts
## into a light floor; the ink shell keeps a value edge around it.
const HIGH_KEY_INTENSITY: float = 1.05
const SPRING_K: float = 300.0
const SPRING_D: float = 18.0
const SPRING_STEP: float = 1.0 / 120.0
const MAX_SPRING_DELTA: float = 0.1
const ANTICIPATION: float = 0.04
const HALO_SIZE: float = 1.5
const HALO_INTENSITY: float = 0.2
const LIGHT_RANGE: float = 3.4
const LIGHT_ENERGY: float = 1.1

var body: MeshInstance3D
var ink_shell: MeshInstance3D
var halo: MeshInstance3D
var shield_ring: MeshInstance3D
var chevron: MeshInstance3D
var ring: MeshInstance3D
var light: OmniLight3D
var shards: Array[MeshInstance3D] = []

var skin_style: int = 0
var skin_color_a: Color = Palette.PRIMARY
var skin_color_b: Color = Palette.PRIMARY.darkened(0.35)
var skin_rim: Color = Color.WHITE
var skin_anim_speed: float = 1.0
var reduce_motion: bool = false
var high_key: bool = false

var _mat: ShaderMaterial = ShaderMaterial.new()
var _accent_mat: ShaderMaterial = ShaderMaterial.new()
var _halo_mat: ShaderMaterial = ShaderMaterial.new()
var _ink_mat: ShaderMaterial = ShaderMaterial.new()
var _shield_mat: StandardMaterial3D = StandardMaterial3D.new()
var _form: int = -1
var _meshes: Dictionary = {}
var _scale_off: Vector3 = Vector3.ZERO
var _scale_vel: Vector3 = Vector3.ZERO
var _spin: float = 0.0
var _pulse: float = 0.0
var _shard_angle: float = 0.0
var _spawn: float = 1.0
var _anticipation_left: float = 0.0
var _pending_stretch: Vector3 = Vector3.ZERO
var _implode: float = -1.0
var _built: bool = false


func _ready() -> void:
	_ensure_built()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_build_meshes()
	_mat.shader = CORE_SHADER
	_accent_mat.shader = CORE_SHADER
	body = MeshInstance3D.new()
	body.material_override = _mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(body)
	ink_shell = MeshInstance3D.new()
	_ink_mat.shader = INK_SHADER
	_ink_mat.set_shader_parameter("ink", Palette.GRAPHITE)
	ink_shell.material_override = _ink_mat
	ink_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ink_shell.visible = false
	body.add_child(ink_shell)
	halo = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	halo.mesh = quad
	_halo_mat.shader = GLOW_SHADER
	_halo_mat.set_shader_parameter("size", HALO_SIZE)
	_halo_mat.set_shader_parameter("intensity", HALO_INTENSITY)
	halo.material_override = _halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)
	shield_ring = MeshInstance3D.new()
	var hex: TorusMesh = TorusMesh.new()
	hex.inner_radius = 0.5
	hex.outer_radius = 0.54
	hex.rings = 6
	hex.ring_segments = 4
	shield_ring.mesh = hex
	_shield_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shield_mat.albedo_color = Palette.SUCCESS * 1.3
	shield_ring.material_override = _shield_mat
	shield_ring.rotation_degrees = Vector3(90, 0, 0)
	shield_ring.visible = false
	shield_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shield_ring)
	ring = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.4
	torus.outer_radius = 0.46
	ring.mesh = torus
	ring.material_override = _accent_mat
	ring.visible = false
	add_child(ring)
	chevron = MeshInstance3D.new()
	var prism: PrismMesh = PrismMesh.new()
	prism.size = Vector3(0.16, 0.12, 0.04)
	chevron.mesh = prism
	chevron.material_override = _accent_mat
	chevron.visible = false
	add_child(chevron)
	for _i: int in SimConst.MAX_CHARGES:
		var s: MeshInstance3D = MeshInstance3D.new()
		s.mesh = MeshFactory.shard(0.045, 0.12)
		s.material_override = _accent_mat
		s.visible = false
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
		shards.append(s)
	light = OmniLight3D.new()
	light.omni_range = LIGHT_RANGE
	light.light_energy = LIGHT_ENERGY
	light.shadow_enabled = false
	add_child(light)
	set_form(SimConst.Form.HOP, 0, false)
	apply_skin_colors()


func _build_meshes() -> void:
	var r: float = SimConst.CORE_RADIUS
	var orb: SphereMesh = SphereMesh.new()
	orb.radius = r
	orb.height = r * 2.0
	orb.radial_segments = 32
	orb.rings = 16
	_meshes[SimConst.Form.HOP] = orb
	_meshes[SimConst.Form.PHASE] = MeshFactory.shard(r * 1.12, r * 2.7)
	var comet: CapsuleMesh = CapsuleMesh.new()
	comet.radius = r * 0.82
	comet.height = r * 3.1
	_meshes[SimConst.Form.DASH] = comet
	var surge: SphereMesh = SphereMesh.new()
	surge.radius = r * 0.78
	surge.height = r * 1.56
	_meshes[SimConst.Form.SURGE] = surge


## Applies cosmetic skin parameters (cosmetics never touch gameplay state).
func apply_skin(style: int, color_a: Color, color_b: Color, rim: Color, anim_speed: float = 1.0) -> void:
	_ensure_built()
	skin_style = style
	skin_color_a = color_a
	skin_color_b = color_b
	skin_rim = rim
	skin_anim_speed = anim_speed
	apply_skin_colors()


func apply_skin_colors() -> void:
	_mat.set_shader_parameter("style", skin_style)
	_mat.set_shader_parameter("color_a", skin_color_a)
	_mat.set_shader_parameter("color_b", skin_color_b)
	_mat.set_shader_parameter("rim_color", skin_rim)
	_mat.set_shader_parameter("anim_speed", skin_anim_speed)
	_mat.set_shader_parameter("intensity", HIGH_KEY_INTENSITY if high_key else Palette.ENERGY_CORE)
	_mat.set_shader_parameter("rim_strength", 0.35 if high_key else 1.6)
	_halo_mat.set_shader_parameter("glow_color", skin_color_a)
	light.light_color = skin_color_a


## High-key worlds (light floor): ink shell on, core intensity lowered so its
## hue, not its brightness, separates it from the environment.
func set_high_key(enabled: bool) -> void:
	_ensure_built()
	high_key = enabled
	ink_shell.visible = enabled
	apply_skin_colors()


func set_light_enabled(enabled: bool) -> void:
	_ensure_built()
	light.visible = enabled


func set_form(form: int, phase: int, heavy: bool) -> void:
	if form != _form:
		_form = form
		body.mesh = _meshes.get(form, _meshes[SimConst.Form.HOP]) as Mesh
		ink_shell.mesh = body.mesh
		body.rotation = Vector3.ZERO
		ring.visible = form == SimConst.Form.SURGE
	# Form tint only where it carries meaning (phase / dash / surge weight).
	var tint: Color = skin_color_a if form == SimConst.Form.HOP else Palette.form_color(form, phase, heavy)
	_mat.set_shader_parameter("color_a", tint)
	_accent_mat.set_shader_parameter("color_a", tint)
	_accent_mat.set_shader_parameter("color_b", tint.darkened(0.25))
	_accent_mat.set_shader_parameter("intensity", 1.3)
	_halo_mat.set_shader_parameter("glow_color", tint)
	light.light_color = tint


func set_direction_hint(visible_hint: bool, dir: int) -> void:
	chevron.visible = visible_hint
	chevron.position = Vector3(0.46 * float(dir), 0.0, 0.0)
	chevron.rotation_degrees = Vector3(-90, 0, -90 if dir > 0 else 90)


func spawn_in() -> void:
	_spawn = 0.0
	_implode = -1.0
	visible = true


## Hop: 40 ms anticipation squash, then stretch along the hop direction.
func hop_motion(direction: float) -> void:
	_scale_vel += Vector3(-2.2, 1.6, -0.8)
	_anticipation_left = ANTICIPATION
	_pending_stretch = Vector3(4.4, -2.4, -0.6) * absf(direction)


## Phase: a crisp twist and pulse (the colour change is the information).
func phase_motion() -> void:
	_scale_vel += Vector3(1.8, -1.2, 1.8)
	_pulse = maxf(_pulse, 0.6)


## Form change: shrink then pop into the new silhouette.
func morph() -> void:
	_scale_vel += Vector3(-6.0, -6.0, -6.0)
	_pending_stretch = Vector3(7.5, 7.5, 7.5)
	_anticipation_left = 0.06
	_pulse = maxf(_pulse, 0.8)


## Fail: brief implosion; the burst follows from the view.
func implode() -> void:
	_implode = 0.0


func punch(amount: float) -> void:
	_scale_vel += Vector3.ONE * amount * 8.0


func squash(axis: Vector3, amount: float) -> void:
	_scale_vel += axis * amount * 11.0 - (Vector3.ONE - axis) * amount * 4.0


func update_visuals(delta: float, sim: FluxSim) -> void:
	if _anticipation_left > 0.0:
		_anticipation_left -= delta
		if _anticipation_left <= 0.0:
			_scale_vel += _pending_stretch
			_pending_stretch = Vector3.ZERO
	_integrate_spring(delta)
	_spawn = minf(1.0, _spawn + delta * 3.5)
	var spawn_scale: float = ease(_spawn, -2.4) if _spawn < 1.0 else 1.0
	var s: Vector3 = (Vector3.ONE + _scale_off).clamp(Vector3(0.45, 0.45, 0.45), Vector3(1.7, 1.7, 1.7)) * spawn_scale
	if _implode >= 0.0:
		_implode += delta
		s *= maxf(0.0, 1.0 - _implode / 0.06)
		if _implode > 0.06:
			visible = false
	body.scale = s
	var spin_rate: float = (1.5 + sim.speed * 0.18) * (0.3 if reduce_motion else 1.0)
	_spin += delta * spin_rate
	match _form:
		SimConst.Form.HOP, SimConst.Form.SURGE:
			body.rotation = Vector3(-_spin, _spin * 0.25, 0.0)
		SimConst.Form.PHASE:
			body.rotation = Vector3(0.0, _spin * 1.4, 0.0)
		SimConst.Form.DASH:
			body.rotation = Vector3(PI * 0.5, 0.0, _spin)
	ring.rotation = Vector3(PI * 0.5 + sin(_spin * 0.7) * 0.25, _spin * 1.6, 0.0)
	_pulse = move_toward(_pulse, 0.0, delta * 3.0)
	_mat.set_shader_parameter("pulse", _pulse)
	_mat.set_shader_parameter("overdrive", 1.0 if sim.overdrive_timer > 0.0 else 0.0)
	var combo_glow: float = clampf(float(sim.combo) / 40.0, 0.0, 1.0)
	_halo_mat.set_shader_parameter("intensity", HALO_INTENSITY + combo_glow * 0.18 + _pulse * 0.2)
	light.light_energy = LIGHT_ENERGY + combo_glow * 0.5
	shield_ring.visible = sim.shields > 0
	shield_ring.rotation.z += delta * 0.8
	_update_shards(delta, sim.charges if sim.overdrive_timer <= 0.0 else SimConst.MAX_CHARGES)


## Semi-implicit spring integrated in fixed sub-steps: stable even when a frame
## takes 100 ms or more (slow devices), so the scale can never diverge.
func _integrate_spring(delta: float) -> void:
	var remaining: float = minf(delta, MAX_SPRING_DELTA)
	while remaining > 0.0:
		var h: float = minf(remaining, SPRING_STEP)
		_scale_vel += (-_scale_off * SPRING_K - _scale_vel * SPRING_D) * h
		_scale_off += _scale_vel * h
		remaining -= h


func _update_shards(delta: float, charges: int) -> void:
	_shard_angle += delta * 2.6
	for i: int in shards.size():
		var shard: MeshInstance3D = shards[i]
		shard.visible = i < charges
		if not shard.visible:
			continue
		var a: float = _shard_angle + TAU * float(i) / float(SimConst.MAX_CHARGES)
		shard.position = Vector3(cos(a) * 0.48, 0.02, sin(a) * 0.48)
		shard.rotation = Vector3(0.0, -a, 0.0)
