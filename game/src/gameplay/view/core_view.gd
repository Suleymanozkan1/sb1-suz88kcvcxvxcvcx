class_name CoreView
extends Node3D
## The player: a small flux craft carrying the energy core in its canopy —
## the game's signature and visual priority #1.
##
## Each form is its own craft ([CraftShapes]), so the silhouette tells the tap
## meaning (ART_DIRECTION §4): the Glider (hop), the crystal Prism (phase), the
## needle Dart (dash) and the round Hauler in its ring (surge). Seen from behind
## it reads by its wings, glowing engines and their flames. Its energy parts
## (canopy core, crystal, nozzles, wing lights) wear the core shader, so skins
## show there. Motion character (§8): elastic and alive — anticipation squash,
## stretch, one overshoot, settle; it banks into lane changes, hovers, and
## barrel-rolls on a phase change. Only its energy may bloom strongly.

const CORE_SHADER: Shader = preload("res://assets/shaders/core.gdshader")
const FLAME_SHADER: Shader = preload("res://assets/shaders/flame.gdshader")
const HULL_SHADER: Shader = preload("res://assets/shaders/craft_hull.gdshader")
const GLOW_SHADER: Shader = preload("res://assets/shaders/glow_sprite.gdshader")
const INK_SHADER: Shader = preload("res://assets/shaders/ink_shell.gdshader")
## In high-key worlds the core trades raw brightness for hue so it never melts
## into a light floor; the ink shell keeps a value edge around it.
const HIGH_KEY_INTENSITY: float = 1.05
## Outside HOP the body's second colour is the form colour darkened by this.
const FORM_SECOND_SHADE: float = 0.4
const SPRING_K: float = 300.0
const SPRING_D: float = 18.0
const SPRING_STEP: float = 1.0 / 120.0
const MAX_SPRING_DELTA: float = 0.1
const ANTICIPATION: float = 0.04
const HALO_SIZE: float = 1.3
const HALO_INTENSITY: float = 0.2
## Corona: soft rays in the halo, stronger with the combo.
const HALO_RAYS: float = 6.0
const HALO_RAY_STRENGTH: float = 0.15
const HALO_RAY_COMBO: float = 0.35
const LIGHT_RANGE: float = 3.4
## Hull: light ceramic paint with a hint of the skin (or form) colour; dark in
## high-key worlds so it never melts into a light floor. Trim is dark metal.
## The craft is drawn this much larger than the core's collision radius (its
## wings still clear a neighbouring lane's blocks by half a lane).
const CRAFT_SCALE: float = 1.3
const HULL_COLOR: Color = Color("#e6ebf2")
const HULL_DARK: Color = Color("#353e50")
const HULL_TINT: float = 0.12
const TRIM_COLOR: Color = Color("#262d3a")
const TRIM_ROUGHNESS: float = 0.35
const TRIM_METALLIC: float = 0.75
## Engine flames: length (world units) at rest, per unit of run speed, and the
## Dart's afterburner multiplier.
const FLAME_LENGTH: float = 0.2
const FLAME_PER_SPEED: float = 0.014
const FLAME_DASH: float = 2.0
const FLAME_INTENSITY: float = 2.4
## Bank into lane changes: roll (radians) per unit of lateral speed, capped;
## a slight yaw into the turn; eased at BANK_RATE per second.
const BANK_PER_SPEED: float = 0.07
const BANK_MAX: float = 0.6
const YAW_PER_SPEED: float = 0.025
const YAW_MAX: float = 0.22
const BANK_RATE: float = 12.0
## Hover bob: height and rate (radians per second).
const HOVER_HEIGHT: float = 0.022
const HOVER_RATE: float = 3.2
## Phase change: one barrel roll in this many seconds.
const ROLL_TIME: float = 0.32
## Engine sparks (left in the world, so they stream behind the craft).
const ION_AMOUNT: int = 20
const ION_LIFETIME: float = 0.45
const ION_SIZE: float = 0.04
const ION_EMIT_RADIUS: float = 0.05
const ION_SPEED_MIN: float = 0.6
const ION_SPEED_MAX: float = 1.6
const ION_RISE: Vector3 = Vector3(0.0, 0.25, 0.0)
const ION_OFFSET: Vector3 = Vector3(0.0, -0.04, 0.42)
const LIGHT_ENERGY: float = 1.1
## Mass plates ride on top of the core as a stack of thin ballast discs.
const STACK_DISC_RADIUS: float = 0.2
const STACK_DISC_HEIGHT: float = 0.05
const STACK_DISC_GAP: float = 0.065

# --- Motion recipes (§8): scale-velocity kicks fed to the spring ----------------

## Hop: anticipation squash (wide, low), then a stretch along the hop.
const HOP_ANTICIPATION_KICK: Vector3 = Vector3(-2.2, 1.6, -0.8)
const HOP_STRETCH_KICK: Vector3 = Vector3(4.4, -2.4, -0.6)
## Phase: a crisp twist, with a shader pulse of this strength.
const PHASE_TWIST_KICK: Vector3 = Vector3(1.8, -1.2, 1.8)
const PHASE_PULSE: float = 0.6
## Form change: shrink, hold for MORPH_ANTICIPATION seconds, pop into the new
## silhouette; a stronger pulse than a phase.
const MORPH_SHRINK_KICK: Vector3 = Vector3(-6.0, -6.0, -6.0)
const MORPH_POP_KICK: Vector3 = Vector3(7.5, 7.5, 7.5)
const MORPH_ANTICIPATION: float = 0.06
const MORPH_PULSE: float = 0.8
## [method punch] and [method squash] scale their amount into a kick: along the
## squash axis, and (opposite) across it to keep the volume.
const PUNCH_GAIN: float = 8.0
const SQUASH_AXIS_GAIN: float = 11.0
const SQUASH_CROSS_GAIN: float = 4.0
## Spawn-in: grows from nothing at this rate (per second) on an in-out ease.
const SPAWN_RATE: float = 3.5
const SPAWN_EASE: float = -2.4
## The spring's scale never leaves these bounds, however hard the kicks stack.
const SCALE_MIN: Vector3 = Vector3(0.45, 0.45, 0.45)
const SCALE_MAX: Vector3 = Vector3(1.7, 1.7, 1.7)
## Fail: the core implodes to nothing in this many seconds (§9: 60 ms).
const IMPLODE_TIME: float = 0.06

# --- Idle motion ------------------------------------------------------------------

## Spin (radians per second): a base plus a share of the run speed; reduce
## motion keeps this fraction of it.
const SPIN_BASE: float = 1.5
const SPIN_PER_SPEED: float = 0.18
const REDUCED_SPIN: float = 0.3
## Surge ring: wobbles about its upright pose (amplitude in radians, rate as a
## share of the spin) and turns faster than the sphere it carries.
const RING_WOBBLE: float = 0.25
const RING_WOBBLE_RATE: float = 0.7
const RING_SPIN: float = 1.6
## The shader pulse (phase, morph, full stack) fades at this rate per second.
const PULSE_DECAY: float = 3.0
## Combo glow: full at this combo; it adds to the halo and the core light.
const COMBO_GLOW_FULL: float = 40.0
const HALO_COMBO: float = 0.18
const HALO_PULSE: float = 0.2
const LIGHT_COMBO: float = 0.5
## Shield ring turn rate (radians per second).
const SHIELD_SPIN: float = 0.8
## A full plate stack breathes: pulse floor, swing and rate (spin multiples).
const FULL_STACK_PULSE: float = 0.18
const FULL_STACK_PULSE_SWING: float = 0.12
const FULL_STACK_PULSE_RATE: float = 6.0
## Overdrive charge shards orbit the core: speed (radians per second), radius
## and height above the core's centre.
const SHARD_ORBIT_SPEED: float = 2.6
const SHARD_ORBIT_RADIUS: float = 0.56
const SHARD_ORBIT_Y: float = 0.02

var body: MeshInstance3D
var flames: MeshInstance3D
var ions: CPUParticles3D
var ink_shell: MeshInstance3D
var halo: MeshInstance3D
var shield_ring: MeshInstance3D
var chevron: MeshInstance3D
var ring: MeshInstance3D
var light: OmniLight3D
var shards: Array[MeshInstance3D] = []
var stack_discs: Array[MeshInstance3D] = []

var skin_style: int = 0
var skin_color_a: Color = Palette.PRIMARY
var skin_color_b: Color = Palette.PRIMARY.darkened(0.35)
var skin_rim: Color = Color.WHITE
var skin_anim_speed: float = 1.0
var reduce_motion: bool = false
var high_key: bool = false

## Height of the current form's top: the plate discs sit on it.
var _stack_top: float = SimConst.CORE_RADIUS
var _mat: ShaderMaterial = ShaderMaterial.new()
var _accent_mat: ShaderMaterial = ShaderMaterial.new()
var _halo_mat: ShaderMaterial = ShaderMaterial.new()
var _ink_mat: ShaderMaterial = ShaderMaterial.new()
var _shield_mat: StandardMaterial3D = StandardMaterial3D.new()
## Hull paint (craft_hull.gdshader): seams and stripes, off on Low quality.
var _hull_mat: ShaderMaterial = ShaderMaterial.new()
var _trim_mat: StandardMaterial3D = StandardMaterial3D.new()
var _flame_mat: ShaderMaterial = ShaderMaterial.new()
var _ion_mat: StandardMaterial3D = StandardMaterial3D.new()
## Ion sparks follow the particle quality (0 turns them off).
var _ion_scale: float = 1.0
var _form: int = -1
## Craft mesh per form (SimConst.Form).
var _meshes: Dictionary[int, Mesh] = {}
var _tint: Color = Palette.PRIMARY
var _bank: float = 0.0
var _yaw: float = 0.0
var _roll_left: float = 0.0
var _last_x: float = 0.0
var _hover: float = 0.0
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
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(body)
	_hull_mat.shader = HULL_SHADER
	_trim_mat.albedo_color = TRIM_COLOR
	_trim_mat.roughness = TRIM_ROUGHNESS
	_trim_mat.metallic = TRIM_METALLIC
	flames = MeshInstance3D.new()
	_flame_mat.shader = FLAME_SHADER
	_flame_mat.set_shader_parameter("intensity", FLAME_INTENSITY)
	flames.material_override = _flame_mat
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(flames)
	ink_shell = MeshInstance3D.new()
	_ink_mat.shader = INK_SHADER
	_ink_mat.set_shader_parameter("ink", Palette.GRAPHITE)
	ink_shell.material_override = _ink_mat
	ink_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ink_shell.visible = false
	body.add_child(ink_shell)
	ions = _make_ions()
	ions.position = ION_OFFSET
	add_child(ions)
	halo = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	halo.mesh = quad
	_halo_mat.shader = GLOW_SHADER
	_halo_mat.set_shader_parameter("size", HALO_SIZE)
	_halo_mat.set_shader_parameter("intensity", HALO_INTENSITY)
	_halo_mat.set_shader_parameter("rays", HALO_RAYS)
	_halo_mat.set_shader_parameter("ray_strength", HALO_RAY_STRENGTH)
	halo.material_override = _halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)
	shield_ring = MeshInstance3D.new()
	var hex: TorusMesh = TorusMesh.new()
	hex.inner_radius = 0.58
	hex.outer_radius = 0.62
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
	torus.inner_radius = 0.5
	torus.outer_radius = 0.57
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
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = STACK_DISC_RADIUS
	disc.bottom_radius = STACK_DISC_RADIUS
	disc.height = STACK_DISC_HEIGHT
	disc.radial_segments = 24
	var ballast: StandardMaterial3D = StandardMaterial3D.new()
	ballast.albedo_color = Palette.FORM_SURGE_HEAVY.darkened(0.45)
	ballast.roughness = 0.45
	ballast.metallic = 0.6
	for i: int in SimConst.MAX_PLATES:
		var d: MeshInstance3D = MeshInstance3D.new()
		d.mesh = disc
		d.material_override = ballast
		d.position = Vector3(0.0, SimConst.CORE_RADIUS + STACK_DISC_GAP * (float(i) + 0.6), 0.0)
		d.visible = false
		add_child(d)
		stack_discs.append(d)
	light = OmniLight3D.new()
	light.omni_range = LIGHT_RANGE
	light.light_energy = LIGHT_ENERGY
	light.shadow_enabled = false
	add_child(light)
	set_form(SimConst.Form.HOP, 0, false)
	apply_skin_colors()


func _make_ions() -> CPUParticles3D:
	var p: CPUParticles3D = CPUParticles3D.new()
	p.local_coords = false
	p.amount = ION_AMOUNT
	p.lifetime = ION_LIFETIME
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = ION_EMIT_RADIUS
	p.direction = Vector3(0.0, 0.1, 1.0)
	p.spread = 25.0
	p.initial_velocity_min = ION_SPEED_MIN
	p.initial_velocity_max = ION_SPEED_MAX
	p.gravity = ION_RISE
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	var shrink: Curve = Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = shrink
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(ION_SIZE, ION_SIZE)
	_ion_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ion_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_ion_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ion_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ion_mat.vertex_color_use_as_albedo = true
	_ion_mat.albedo_texture = ViewKit.soft_dot_texture()
	quad.material = _ion_mat
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Hull seams, stripes and flake follow the quality's surface detail.
func set_detail(enabled: bool) -> void:
	_ensure_built()
	_hull_mat.set_shader_parameter("detail", 1.0 if enabled else 0.0)


## Ion sparks follow the particle quality: fewer on lower presets, none at 0.
func set_particle_scale(amount_scale: float) -> void:
	_ensure_built()
	_ion_scale = clampf(amount_scale, 0.0, 1.0)
	ions.amount = maxi(1, int(round(float(ION_AMOUNT) * _ion_scale)))


func _build_meshes() -> void:
	for form: int in [SimConst.Form.HOP, SimConst.Form.PHASE, SimConst.Form.DASH, SimConst.Form.SURGE]:
		_meshes[form] = CraftShapes.build(form)


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
	_apply_paint()


## High-key worlds (light floor): ink shell on, core intensity lowered so its
## hue, not its brightness, separates it from the environment.
func set_high_key(enabled: bool) -> void:
	_ensure_built()
	high_key = enabled
	ink_shell.visible = enabled
	apply_skin_colors()
	_apply_paint()


func set_light_enabled(enabled: bool) -> void:
	_ensure_built()
	light.visible = enabled


## Height of a form's craft top as it is drawn (every craft is built upright,
## so [param form] no longer changes the axis).
static func form_top(mesh: Mesh, _form: int) -> float:
	if mesh == null:
		return SimConst.CORE_RADIUS
	return mesh.get_aabb().end.y


func set_form(form: int, phase: int, heavy: bool) -> void:
	if form != _form:
		_form = form
		body.mesh = _meshes.get(form, _meshes[SimConst.Form.HOP]) as Mesh
		body.set_surface_override_material(CraftShapes.SURFACE_HULL, _hull_mat)
		body.set_surface_override_material(CraftShapes.SURFACE_TRIM, _trim_mat)
		body.set_surface_override_material(CraftShapes.SURFACE_ENERGY, _mat)
		ink_shell.mesh = body.mesh
		flames.mesh = CraftShapes.flames(form)
		ring.visible = form == SimConst.Form.SURGE
		_stack_top = form_top(body.mesh, form) * CRAFT_SCALE
	# Form tint only where it carries meaning (phase / dash / surge weight).
	var tint: Color = skin_color_a if form == SimConst.Form.HOP else Palette.form_color(form, phase, heavy)
	_mat.set_shader_parameter("color_a", tint)
	# The skin's second colour would average the form colour towards grey (a
	# teal dash mixed with a magenta skin reads as mud): outside HOP the body
	# is a shade of the form colour instead.
	_mat.set_shader_parameter(
		"color_b", skin_color_b if form == SimConst.Form.HOP else tint.darkened(FORM_SECOND_SHADE)
	)
	_mat.set_shader_parameter("form_lock", 0.0 if form == SimConst.Form.HOP else 1.0)
	_accent_mat.set_shader_parameter("color_a", tint)
	_accent_mat.set_shader_parameter("color_b", tint.darkened(0.25))
	_accent_mat.set_shader_parameter("intensity", 1.3)
	_halo_mat.set_shader_parameter("glow_color", tint)
	light.light_color = tint
	_tint = tint
	_apply_paint()


## Hull paint, flame and spark colours from the current tint (skin colour in
## HOP, the form colour otherwise).
func _apply_paint() -> void:
	var base: Color = HULL_DARK if high_key else HULL_COLOR
	var accent: Color = skin_color_b if _form == SimConst.Form.HOP else _tint
	_hull_mat.set_shader_parameter("paint", base.lerp(accent, HULL_TINT))
	_hull_mat.set_shader_parameter("accent", _tint)
	_flame_mat.set_shader_parameter("flame_color", _tint)
	ions.color = _tint


func set_direction_hint(visible_hint: bool, dir: int) -> void:
	chevron.visible = visible_hint
	chevron.position = Vector3(0.64 * float(dir), 0.0, 0.0)
	chevron.rotation_degrees = Vector3(-90, 0, -90 if dir > 0 else 90)


func spawn_in() -> void:
	_spawn = 0.0
	_implode = -1.0
	visible = true


## Hop: 40 ms anticipation squash, then stretch along the hop direction.
func hop_motion(direction: float) -> void:
	_scale_vel += HOP_ANTICIPATION_KICK
	_anticipation_left = ANTICIPATION
	_pending_stretch = HOP_STRETCH_KICK * absf(direction)


## Phase: a crisp twist, a barrel roll and a pulse (the colour change is the
## information; reduce motion skips the roll).
func phase_motion() -> void:
	_scale_vel += PHASE_TWIST_KICK
	_pulse = maxf(_pulse, PHASE_PULSE)
	if not reduce_motion:
		_roll_left = ROLL_TIME


## Form change: shrink then pop into the new silhouette.
func morph() -> void:
	_scale_vel += MORPH_SHRINK_KICK
	_pending_stretch = MORPH_POP_KICK
	_anticipation_left = MORPH_ANTICIPATION
	_pulse = maxf(_pulse, MORPH_PULSE)


## Fail: brief implosion ([constant IMPLODE_TIME]); the burst follows from the view.
func implode() -> void:
	_implode = 0.0


func punch(amount: float) -> void:
	_scale_vel += Vector3.ONE * amount * PUNCH_GAIN


func squash(axis: Vector3, amount: float) -> void:
	_scale_vel += axis * amount * SQUASH_AXIS_GAIN - (Vector3.ONE - axis) * amount * SQUASH_CROSS_GAIN


func update_visuals(delta: float, sim: FluxSim) -> void:
	if _anticipation_left > 0.0:
		_anticipation_left -= delta
		if _anticipation_left <= 0.0:
			_scale_vel += _pending_stretch
			_pending_stretch = Vector3.ZERO
	_integrate_spring(delta)
	_spawn = minf(1.0, _spawn + delta * SPAWN_RATE)
	var spawn_scale: float = ease(_spawn, SPAWN_EASE) if _spawn < 1.0 else 1.0
	var s: Vector3 = (Vector3.ONE + _scale_off).clamp(SCALE_MIN, SCALE_MAX) * spawn_scale
	if _implode >= 0.0:
		_implode += delta
		s *= maxf(0.0, 1.0 - _implode / IMPLODE_TIME)
		if _implode > IMPLODE_TIME:
			visible = false
	body.scale = s * CRAFT_SCALE
	for i: int in stack_discs.size():
		# On the form's own top, and with its squash and stretch.
		stack_discs[i].position.y = _stack_top * s.y + STACK_DISC_GAP * (float(i) + 0.6)
	var spin_rate: float = (SPIN_BASE + sim.speed * SPIN_PER_SPEED) * (REDUCED_SPIN if reduce_motion else 1.0)
	_spin += delta * spin_rate
	_update_flight(delta, sim)
	ring.rotation = Vector3(PI * 0.5 + sin(_spin * RING_WOBBLE_RATE) * RING_WOBBLE, _spin * RING_SPIN, 0.0)
	_pulse = move_toward(_pulse, 0.0, delta * PULSE_DECAY)
	_mat.set_shader_parameter("pulse", _pulse)
	_mat.set_shader_parameter("overdrive", 1.0 if sim.overdrive_timer > 0.0 else 0.0)
	var combo_glow: float = clampf(float(sim.combo) / COMBO_GLOW_FULL, 0.0, 1.0)
	_halo_mat.set_shader_parameter("intensity", HALO_INTENSITY + combo_glow * HALO_COMBO + _pulse * HALO_PULSE)
	_halo_mat.set_shader_parameter("ray_strength", HALO_RAY_STRENGTH + combo_glow * HALO_RAY_COMBO)
	ions.emitting = visible and _ion_scale > 0.0 and _implode < 0.0
	var flame: float = FLAME_LENGTH + sim.speed * FLAME_PER_SPEED
	if _form == SimConst.Form.DASH or sim.overdrive_timer > 0.0:
		flame *= FLAME_DASH
	_flame_mat.set_shader_parameter("length", flame)
	light.light_energy = LIGHT_ENERGY + combo_glow * LIGHT_COMBO
	shield_ring.visible = sim.shields > 0
	shield_ring.rotation.z += delta * SHIELD_SPIN
	for i: int in stack_discs.size():
		stack_discs[i].visible = i < sim.plates
	if sim.plates >= SimConst.MAX_PLATES:
		# A full stack is a loaded state: the core breathes until it is spent.
		_pulse = maxf(_pulse, FULL_STACK_PULSE + FULL_STACK_PULSE_SWING * sin(_spin * FULL_STACK_PULSE_RATE))
	_update_shards(delta, sim.charges if sim.overdrive_timer <= 0.0 else SimConst.MAX_CHARGES)


## Banking into lane changes (from the craft's own lateral speed), a slight
## yaw into the turn, the phase barrel roll and the hover bob.
func _update_flight(delta: float, sim: FluxSim) -> void:
	var vx: float = (position.x - _last_x) / delta if delta > 0.0 else 0.0
	_last_x = position.x
	var ease_k: float = 1.0 - exp(-BANK_RATE * delta)
	_bank = lerpf(_bank, clampf(-vx * BANK_PER_SPEED, -BANK_MAX, BANK_MAX), ease_k)
	_yaw = lerpf(_yaw, clampf(-vx * YAW_PER_SPEED, -YAW_MAX, YAW_MAX), ease_k)
	var roll: float = 0.0
	if _roll_left > 0.0:
		_roll_left = maxf(0.0, _roll_left - delta)
		if _roll_left > 0.0:
			roll = TAU * ease(1.0 - _roll_left / ROLL_TIME, -1.8)
	if not reduce_motion and sim.is_running():
		_hover += delta * HOVER_RATE
	body.rotation = Vector3(0.0, _yaw, _bank + roll)
	body.position.y = sin(_hover) * HOVER_HEIGHT


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
	_shard_angle += delta * SHARD_ORBIT_SPEED
	for i: int in shards.size():
		var shard: MeshInstance3D = shards[i]
		shard.visible = i < charges
		if not shard.visible:
			continue
		var a: float = _shard_angle + TAU * float(i) / float(SimConst.MAX_CHARGES)
		shard.position = Vector3(cos(a) * SHARD_ORBIT_RADIUS, SHARD_ORBIT_Y, sin(a) * SHARD_ORBIT_RADIUS)
		shard.rotation = Vector3(0.0, -a, 0.0)
