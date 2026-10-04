class_name GameplayView
extends Node3D
## 3D presentation of a [GameplaySession] following docs/ART_DIRECTION.md:
## calm physical environment, one key light, only energy glows, and every
## effect has one job (information, impact, reward, progression, atmosphere).
##
## Emits [signal feedback] so audio/haptics systems react without the view
## depending on them.

signal feedback(kind: StringName, strength: float, pitch_step: int)

const SKY_SHADER: Shader = preload("res://assets/shaders/sky.gdshader")
const FLOOR_SHADER: Shader = preload("res://assets/shaders/floor.gdshader")
const POST_SHADER: Shader = preload("res://assets/shaders/post_fx.gdshader")
const MEMBRANE_SHADER: Shader = preload("res://assets/shaders/membrane.gdshader")
const VIEW_AHEAD: float = 75.0
## Camera shake, lean and FOV kicks with "reduce motion" on (fraction of full).
const REDUCED_CAMERA_MOTION: float = 0.2
const VIEW_BEHIND: float = 6.0
const RIB_SPACING: float = 7.0
const RIB_COUNT: int = 16
const RIB_HEIGHT_PATTERN: Array[float] = [1.0, 0.88, 1.06, 0.94]
const FLOOR_LENGTH: float = 160.0
const FLOOR_WIDTH: float = 9.0
const CORE_Y: float = 0.38
const SILHOUETTE_DISTANCE: float = 150.0
const SILHOUETTE_PARALLAX: float = 0.03
const SILHOUETTE_MAX_APPROACH: float = 40.0
const ATMOSPHERE_MAX_ALPHA: float = 0.08
## Bursts whose colour and size follow the equipped particle style.
const SKINNED_BURSTS: PackedStringArray = ["collect", "prism", "streak"]
const FOG_BEGIN: float = 28.0
const FOG_END: float = 115.0
## Juice budgets (ART_DIRECTION §9).
const SHAKE_FAIL: float = 0.6
const SHAKE_SHIELD: float = 0.35
const SHAKE_SHATTER: float = 0.12
const SHAKE_LAND: float = 0.08
const SHAFT_SHADER: Shader = preload("res://assets/shaders/light_shaft.gdshader")
## Light shafts: a few tall beams spread across the shaft far ahead of the
## core, at most 8 % opacity (ART_DIRECTION §7).
const SHAFT_COUNT: int = 4
const SHAFT_SIZE: Vector2 = Vector2(2.2, 16.0)
const SHAFT_OPACITY: float = 0.06
const PROBE_SIZE: Vector3 = Vector3(14.0, 10.0, 70.0)
const PROBE_STEP: float = 21.0
const PROBE_HEIGHT: float = 2.0
## Ground shadow under the core: shrinks and fades as a launch carries it up.
const CORE_SHADOW_SIZE: float = 0.9
const CORE_SHADOW_ALPHA: float = 0.32
const CORE_SHADOW_FALLOFF: float = 0.5
const HOP_LEAN: float = 0.15
const NEAR_MISS_SLOWMO_COMBO: int = 10

var session: GameplaySession
var theme: WorldTheme
var kit: ViewKit
var camera_rig: CameraRig
var core_view: CoreView
var trail: TrailRibbon
var sparks: SparkField
var bursts: BurstPool
var environment: Environment
var world_env: WorldEnvironment
var key_light: DirectionalLight3D
var post_rect: ColorRect
var post_layer: CanvasLayer
var core_shadow: MeshInstance3D
var ripples: TapRipple

## Quality / accessibility toggles.
var post_fx_enabled: bool = true
## Accessibility: halves hit-stop and shockwaves, drops slow-motion, and cuts
## camera shake, lean and FOV kicks to a fraction.
var reduce_motion: bool = false:
	set(value):
		reduce_motion = value
		if camera_rig != null:
			camera_rig.shake_scale = REDUCED_CAMERA_MOTION if value else 1.0
var _core_skin: Dictionary = {}
## Equipped particle / effect / background cosmetics ({} = the art direction's
## own palette, i.e. the default item).
var _particle_skin: Dictionary = {}
var _effect_skin: Dictionary = {}
var _sky_skin: Dictionary = {}
var _trail_skin: Dictionary = {}
var _trail_head: Color = Palette.PRIMARY
var _trail_tail: Color = Palette.PRIMARY.darkened(0.5)

var _floor: MeshInstance3D
var _floor_mat: ShaderMaterial
var _sky_mat: ShaderMaterial
var _post_mat: ShaderMaterial
var _ribs: MultiMeshInstance3D
var _silhouette: MeshInstance3D
var _silhouette_mat: StandardMaterial3D
var _atmosphere: CPUParticles3D
var _finish: Node3D
var _finish_membrane: MeshInstance3D
var _finish_arch: MeshInstance3D
var _pool: NodePool
var _active: Dictionary = {}
var _spawn_cursor: int = 0
var _chroma: float = 0.0
var _shock: float = 0.0
var _shock_radius: float = 0.0
var _tint: float = 0.0
var _tint_color: Color = Palette.FAILURE
var _slowmo_left: float = 0.0
var _slowmo_scale: float = 1.0
var _end_slow: bool = false
var _music_pulse: float = 0.0
var _built: bool = false
var _turbine_angle: float = 0.0
var _particle_scale: float = 1.0
var _colorblind: bool = false
var _finish_open: float = 0.0
var _to_release: PackedInt32Array = PackedInt32Array()
var _glow: bool = true
var _ambient: bool = true
var _surface_detail: bool = true
## Reflection probe (High/Ultra): it follows the core in steps of a few rib
## lengths, so it re-captures the (periodic) shaft rarely and cheaply.
var _probe: ReflectionProbe
var _probe_cell: int = -1
var _shafts: Node3D
## Side details between the ribs (one per rib gap, same MultiMesh rhythm).
var _details: MultiMeshInstance3D
var _shaft_mat: ShaderMaterial


func _ready() -> void:
	_ensure_built()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	world_env = WorldEnvironment.new()
	environment = Environment.new()
	world_env.environment = environment
	add_child(world_env)
	key_light = DirectionalLight3D.new()
	key_light.shadow_enabled = true
	key_light.directional_shadow_max_distance = 36.0
	key_light.shadow_bias = 0.12
	key_light.shadow_normal_bias = 2.4
	key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(key_light)
	camera_rig = CameraRig.new()
	camera_rig.shake_scale = REDUCED_CAMERA_MOTION if reduce_motion else 1.0
	add_child(camera_rig)
	_floor = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(FLOOR_WIDTH, FLOOR_LENGTH)
	_floor.mesh = plane
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = FLOOR_SHADER
	_floor.material_override = _floor_mat
	_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_floor)
	_ribs = MultiMeshInstance3D.new()
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 0
	_ribs.multimesh = mm
	# Thin ribs make noisy, wavering shadow lines on the floor: they read as
	# render artefacts, so the ribs do not cast (they still receive light).
	_ribs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ribs)
	_silhouette = MeshInstance3D.new()
	_silhouette_mat = StandardMaterial3D.new()
	_silhouette_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_silhouette_mat.disable_fog = true
	_silhouette.material_override = _silhouette_mat
	_silhouette.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_silhouette)
	sparks = SparkField.new()
	add_child(sparks)
	core_view = CoreView.new()
	add_child(core_view)
	core_shadow = _make_core_shadow()
	add_child(core_shadow)
	ripples = TapRipple.new()
	add_child(ripples)
	_probe = ReflectionProbe.new()
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_probe.size = PROBE_SIZE
	_probe.interior = true
	_probe.max_distance = PROBE_SIZE.z
	_probe.visible = false
	add_child(_probe)
	_shafts = _make_shafts()
	add_child(_shafts)
	_details = MultiMeshInstance3D.new()
	var dmm: MultiMesh = MultiMesh.new()
	dmm.transform_format = MultiMesh.TRANSFORM_3D
	_details.multimesh = dmm
	# Like the ribs: thin wall pieces would draw noisy lines across the floor.
	_details.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_details)
	trail = TrailRibbon.new()
	add_child(trail)
	bursts = BurstPool.new()
	add_child(bursts)
	_atmosphere = CPUParticles3D.new()
	add_child(_atmosphere)
	_finish = Node3D.new()
	_finish_arch = MeshInstance3D.new()
	_finish.add_child(_finish_arch)
	_finish_membrane = MeshInstance3D.new()
	var mem_mat: ShaderMaterial = ShaderMaterial.new()
	mem_mat.shader = MEMBRANE_SHADER
	mem_mat.set_shader_parameter("energy", Palette.PRIMARY)
	mem_mat.set_shader_parameter("density", 0.32)
	_finish_membrane.material_override = mem_mat
	_finish.add_child(_finish_membrane)
	add_child(_finish)
	_pool = NodePool.new(func() -> Node: return EntityView.new(), self, 24)
	post_layer = CanvasLayer.new()
	post_layer.layer = 0
	add_child(post_layer)
	post_rect = ColorRect.new()
	post_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = POST_SHADER
	post_rect.material = _post_mat
	post_rect.visible = false
	post_layer.add_child(post_rect)


func bind(gameplay_session: GameplaySession) -> void:
	_ensure_built()
	session = gameplay_session
	if not session.frame_events.is_connected(_on_frame_events):
		session.frame_events.connect(_on_frame_events)


## Applies a world's environment identity (light, sky, materials, ribs, story).
func apply_world(world_theme: WorldTheme) -> void:
	_ensure_built()
	theme = world_theme
	kit = ViewKit.new(theme)
	kit.colorblind = _colorblind
	kit.set_detail(_surface_detail)
	_apply_environment()
	key_light.light_color = theme.key_color
	key_light.light_energy = theme.key_energy
	key_light.rotation_degrees = Vector3(theme.key_pitch, theme.key_yaw, 0.0)
	_floor_mat.set_shader_parameter("floor_color", theme.floor_color)
	_floor_mat.set_shader_parameter("lane_color", theme.lane_color)
	_floor_mat.set_shader_parameter("fog_color", theme.fog)
	_floor_mat.set_shader_parameter("caustics", 0.12 if theme.caustics else 0.0)
	_floor_mat.set_shader_parameter("gloss", theme.floor_gloss)
	_floor_mat.set_shader_parameter("caustic_color", theme.key_color)
	_ribs.multimesh.mesh = MeshFactory.rib(theme.rib_profile)
	_ribs.multimesh.instance_count = RIB_COUNT
	_ribs.material_override = kit.structure_material
	_details.visible = not theme.detail.is_empty()
	if _details.visible:
		_details.multimesh.instance_count = 0
		_details.multimesh.mesh = MeshFactory.detail(theme.detail)
		_details.multimesh.instance_count = RIB_COUNT
		_details.material_override = kit.structure_material
	_silhouette.mesh = MeshFactory.silhouette(theme.silhouette)
	# Only the turbine turns; no other world inherits its accumulated roll.
	_silhouette.transform.basis = Basis.IDENTITY
	_turbine_angle = 0.0
	_silhouette_mat.albedo_color = theme.sky_bottom.lerp(theme.story_accent, 0.2)
	_finish_arch.mesh = kit.arch_mesh(3)
	_finish_arch.material_override = kit.structure_material
	_finish_arch.scale = Vector3(1.0, 1.4, 1.0)
	_finish_membrane.mesh = kit.membrane_mesh(3)
	_finish_membrane.position = Vector3(0.0, ViewKit.ARCH_HEIGHT * 0.68, 0.0)
	_finish_membrane.scale = Vector3(1.0, 1.4, 1.0)
	_setup_atmosphere()
	_apply_sky_skin()
	core_view.set_high_key(theme.bright)
	_apply_core_skin_defaults()


func _apply_environment() -> void:
	environment.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SKY_SHADER
	_sky_mat.set_shader_parameter("sky_top", theme.sky_top)
	_sky_mat.set_shader_parameter("sky_bottom", theme.sky_bottom)
	_sky_mat.set_shader_parameter("sink_color", theme.sink)
	_sky_mat.set_shader_parameter("sink_strength", 0.75 if theme.bright else 1.0)
	_sky_mat.set_shader_parameter("star_density", 1.0 if theme.atmosphere == "stars" else 0.0)
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = theme.ambient
	environment.ambient_light_energy = theme.ambient_energy
	# Metals need something to reflect, or they read black (physically wrong).
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 1.0
	# Only HDR energy (> 1.0) blooms; matter never does.
	environment.glow_enabled = _glow
	environment.glow_hdr_threshold = 1.0
	environment.glow_intensity = 0.55
	environment.glow_bloom = 0.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = theme.fog
	environment.fog_depth_begin = FOG_BEGIN
	environment.fog_depth_end = FOG_END
	environment.fog_depth_curve = 1.4
	environment.fog_sky_affect = 0.0
	environment.adjustment_enabled = false


func _apply_core_skin_defaults() -> void:
	apply_cosmetics(_core_skin, _trail_skin)


## Equipped cosmetics (never gameplay): core skin {"style","color_a","color_b",
## "rim","anim_speed"} and trail {"style","head","tail"}. In the HOP form the
## trail wears the cosmetic colours; other forms tint it with their gameplay
## colour because there the colour carries information (ART_DIRECTION §3).
func apply_cosmetics(core_skin: Dictionary, trail_skin: Dictionary) -> void:
	_ensure_built()
	_core_skin = core_skin
	_trail_skin = trail_skin
	core_view.apply_skin(
		int(core_skin.get("style", 0)),
		core_skin.get("color_a", Palette.PRIMARY) as Color,
		core_skin.get("color_b", Palette.PRIMARY.darkened(0.35)) as Color,
		core_skin.get("rim", Color.WHITE) as Color,
		float(core_skin.get("anim_speed", 1.0))
	)
	trail.set_style(int(trail_skin.get("style", 0)))
	_trail_head = trail_skin.get("head", Palette.PRIMARY) as Color
	_trail_tail = trail_skin.get("tail", Palette.PRIMARY.darkened(0.5)) as Color


## Particle, effect and background cosmetics. Gameplay meaning stays with the
## palette roles: phase-coloured sparks keep their phase colour, hazards and
## the core are untouched; only celebration colours, sizes and the sky change.
func apply_effect_cosmetics(particle: Dictionary, effect: Dictionary, background: Dictionary) -> void:
	_ensure_built()
	_particle_skin = particle
	_effect_skin = effect
	_sky_skin = background
	bursts.set_size_scale(SKINNED_BURSTS, float(particle.get("size_mult", 1.0)))
	if theme != null:
		_apply_sky_skin()


## Colour [param slot] of the equipped particle style, or [param fallback].
func _particle_color(slot: int, fallback: Color) -> Color:
	var colors: Array = _particle_skin.get("colors", []) as Array
	if colors.is_empty():
		return fallback
	var c: Variant = colors[slot % colors.size()]
	return c as Color if typeof(c) == TYPE_COLOR else fallback


func _effect_color(key: String, fallback: Color) -> Color:
	var c: Variant = _effect_skin.get(key, null)
	return c as Color if typeof(c) == TYPE_COLOR else fallback


## A non-world background replaces the sky gradient and its star density.
func _apply_sky_skin() -> void:
	if _sky_skin.is_empty() or bool(_sky_skin.get("use_world_palette", true)):
		return
	_sky_mat.set_shader_parameter("sky_top", _sky_skin.get("sky_top", theme.sky_top))
	_sky_mat.set_shader_parameter("sky_bottom", _sky_skin.get("sky_bottom", theme.sky_bottom))
	_sky_mat.set_shader_parameter("star_density", clampf(float(_sky_skin.get("star_density", 0.0)), 0.0, 1.0))


## Builds visuals for the session's current level.
func setup_level() -> void:
	_ensure_built()
	var lvl: SimLevel = session.sim_level
	_floor_mat.set_shader_parameter("lane_count", lvl.lane_count)
	_floor_mat.set_shader_parameter("lane_width", SimConst.LANE_WIDTH)
	_finish.visible = not lvl.endless
	_finish.position = Vector3(0.0, 0.0, -lvl.length)
	reset_for_run(true)


func reset_for_run(full_reveal: bool) -> void:
	clear_entities()
	sparks.build(session.sim_level, theme)
	_spawn_cursor = 0
	trail.clear_points()
	camera_rig.reset_state()
	camera_rig.start_reveal(1.0 if full_reveal else 0.25)
	core_view.spawn_in()
	core_view.set_form(session.sim.form, session.sim.phase, session.sim.heavy)
	core_view.visible = true
	_chroma = 0.0
	_shock = 0.0
	_tint = 0.0
	_slowmo_left = 0.0
	_end_slow = false
	_finish_open = 0.0
	bursts.stop_all()
	_update_frame(0.0)


## Colour-blind aid (Settings): phase gates get shape markers and phase-B
## sparks lie on their side. Applies to the visible course right away.
func set_colorblind(on: bool) -> void:
	if on == _colorblind:
		return
	_colorblind = on
	sparks.colorblind = on
	if kit == null:
		return
	kit.colorblind = on
	var lvl: SimLevel = session.sim_level if session != null else null
	if lvl == null:
		return
	for idx: Variant in _active.keys():
		var view: EntityView = _active[idx] as EntityView
		if view.entity_type == SimConst.EntityType.PHASE_GATE:
			view.configure(int(idx), view.entity_type, lvl, kit)
			view.appear = 1.0
	var hidden: Dictionary = sparks.hidden_entities()
	sparks.build(lvl, theme, session.sim.cursor)
	for idx2: Variant in hidden:
		sparks.hide_entity(int(idx2), false)


## Rewarded revive: the run continues from the failure point. The core comes
## back (it imploded on the fail), the trail restarts from it, and the
## barrier it hit is removed (the sim marked it consumed).
func on_revive() -> void:
	_release_entity(session.sim.fail_entity)
	trail.clear_points()
	core_view.spawn_in()
	core_view.set_form(session.sim.form, session.sim.phase, session.sim.heavy)
	_chroma = 0.0
	_shock = 0.0
	_tint = 0.0
	_slowmo_left = 0.0
	_end_slow = false


## Endless streaming: new course entities were appended to the running level.
## Hazards spawn through the normal cursor; the spark field is re-windowed.
func on_stream_appended() -> void:
	# Keep everything the camera can still see behind the core (the sim cursor
	# is already past it), so missed sparks don't pop out on each append.
	var lvl: SimLevel = session.sim_level
	var behind: float = session.sim.d - VIEW_BEHIND
	var from_index: int = mini(session.sim.cursor, lvl.entity_count())
	while from_index > 0 and lvl.e_d[from_index - 1] >= behind:
		from_index -= 1
	sparks.rebuild_append(lvl, from_index)


func clear_entities() -> void:
	for idx: Variant in _active.keys():
		_pool.release(_active[idx] as Node)
	_active.clear()


## Quality hooks (see QualityService presets).
func set_quality(
	post_fx: bool,
	particle_scale: float,
	trail_points: int,
	dynamic_light: bool,
	shadows: bool,
	glow: bool = true,
	ambient_particles: bool = true,
	reflections: bool = false
) -> void:
	_ensure_built()
	post_fx_enabled = post_fx
	_particle_scale = clampf(particle_scale, 0.0, 1.0)
	_glow = glow
	_ambient = ambient_particles
	bursts.set_amount_scale(particle_scale)
	trail.set_length(trail_points)
	core_view.set_light_enabled(dynamic_light)
	# Surface relief follows dynamic lighting: both are off on Low and in
	# battery saver, where a flat lit surface is the budget.
	_surface_detail = dynamic_light
	if kit != null:
		kit.set_detail(_surface_detail)
	key_light.shadow_enabled = shadows
	environment.glow_enabled = _glow
	_probe.visible = reflections
	_probe_cell = -1
	if theme != null:
		_apply_atmosphere_quality()


## Ambient motes follow the quality preset (and battery saver): fewer on
## lower presets, none when ambient particles are off.
func _apply_atmosphere_quality() -> void:
	_atmosphere.amount = maxi(1, int(float(theme.atmosphere_count) * _particle_scale))
	_atmosphere.emitting = _ambient and theme.atmosphere_count > 0 and _particle_scale > 0.2
	_shafts.visible = _ambient and theme.shafts
	_shaft_mat.set_shader_parameter("shaft_color", theme.key_color)


func _process(delta: float) -> void:
	if session == null or session.sim == null:
		return
	_update_juice(delta)
	_update_frame(delta)


func _update_frame(delta: float) -> void:
	var sim: FluxSim = session.sim
	var lvl: SimLevel = session.sim_level
	var d: float = session.interpolated_d()
	var x: float = session.interpolated_x()
	var t: float = session.interpolated_time()
	var lift: float = session.interpolated_y()
	var core_pos: Vector3 = Vector3(x, CORE_Y + lift, -d)
	core_view.position = core_pos
	core_shadow.position = Vector3(x, 0.008, -d)
	core_shadow.scale = Vector3.ONE / (1.0 + lift * CORE_SHADOW_FALLOFF)
	core_shadow.visible = core_view.visible
	core_view.set_form(sim.form, sim.phase, sim.heavy)
	core_view.set_direction_hint(sim.form == SimConst.Form.HOP and lvl.lane_count > 2, sim.hop_dir)
	core_view.update_visuals(delta, sim)
	if sim.form == SimConst.Form.HOP:
		trail.set_colors(_trail_head, Palette.with_alpha(_trail_tail, 0.0))
	else:
		var form_color: Color = Palette.form_color(sim.form, sim.phase, sim.heavy)
		trail.set_colors(form_color, Palette.with_alpha(form_color.darkened(0.5), 0.0))
	trail.width = 0.12 + clampf(float(sim.combo) / 40.0, 0.0, 1.0) * 0.06 + (0.05 if sim.overdrive_timer > 0.0 else 0.0)
	if core_view.visible:
		trail.push_point(core_pos + Vector3(0.0, -0.02, 0.16))
	camera_rig.follow(core_pos, delta, lift)
	trail.rebuild(camera_rig.camera)
	_floor.position = Vector3(0.0, 0.0, -d - FLOOR_LENGTH * 0.5 + 12.0)
	_floor_mat.set_shader_parameter("scroll", d + FLOOR_LENGTH * 0.5 - 12.0)
	_place_ribs(d)
	if _probe.visible:
		var cell: int = int(floorf(d / PROBE_STEP))
		if cell != _probe_cell:
			_probe_cell = cell
			_probe.position = Vector3(0.0, PROBE_HEIGHT, -float(cell) * PROBE_STEP - PROBE_SIZE.z * 0.35)
	# Slow parallax approach, capped so long Endless/Zen runs never bring the
	# silhouette into the camera.
	var approach: float = minf(d * SILHOUETTE_PARALLAX, SILHOUETTE_MAX_APPROACH)
	_silhouette.position = Vector3(0.0, -8.0, -d - SILHOUETTE_DISTANCE + approach)
	if theme != null and theme.silhouette == "turbine":
		# The rotor turns slowly around its own hub (story: World 1's boss machine).
		_silhouette.rotation.z = 0.0
		_turbine_angle += delta * 0.06
		_silhouette.transform.basis = Basis(Vector3.BACK, _turbine_angle)
		_silhouette.position += Vector3(0.0, 30.0, 0.0) - _silhouette.transform.basis * Vector3(0.0, 30.0, 0.0)
	_atmosphere.position = Vector3(0.0, 1.6, -d - 14.0)
	_shafts.position = Vector3(0.0, 0.0, -d)
	if _finish.visible:
		# The finish membrane opens as the core reaches it and is gone once the
		# run is complete (like every gate), so it never fills the backdrop of
		# the result screen.
		if sim.status == SimConst.Status.COMPLETED:
			_finish_open = move_toward(_finish_open, 1.0, delta * 3.0)
		var through: float = maxf(_finish_open, clampf((d - lvl.length + 0.3) / 1.2, 0.0, 1.0))
		_finish_membrane.set_instance_shader_parameter("visibility", 1.0 - through)
	_spawn_entities(lvl, d)
	# Iterate the dictionary itself (no per-frame keys() copy); releases are
	# collected in a reused array and applied after the loop.
	_to_release.clear()
	for idx: Variant in _active:
		var i: int = int(idx)
		var view: EntityView = _active[idx] as EntityView
		var consumed_pickup: bool = (sim.ent_flags[i] & FluxSim.FLAG_CONSUMED) != 0 and _is_pickup(view.entity_type)
		if _entity_end(lvl, i) < d - VIEW_BEHIND or consumed_pickup:
			_to_release.append(i)
			continue
		view.animate(delta, lvl, t, d)
	for i: int in _to_release:
		_release_entity(i)
	sparks.apply_magnet(core_pos, lvl, sim.cursor, sim.magnet_timer > 0.0 or sim.overdrive_timer > 0.0, sim.phase)
	_music_pulse = move_toward(_music_pulse, 0.0, delta * 3.0)
	_floor_mat.set_shader_parameter("beat", 0.0 if reduce_motion else _music_pulse)


func _is_pickup(type: int) -> bool:
	return (
		type == SimConst.EntityType.SHIELD or type == SimConst.EntityType.MAGNET or type == SimConst.EntityType.PLATE
	)


## Where an entity ends along the track: gravity wells span a stretch, every
## other entity sits at one distance.
static func _entity_end(lvl: SimLevel, index: int) -> float:
	if lvl.e_type[index] == SimConst.EntityType.GRAVITY:
		return lvl.e_d[index] + lvl.e_p0[index]
	return lvl.e_d[index]


func _make_shafts() -> Node3D:
	var root: Node3D = Node3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = SHAFT_SIZE
	_shaft_mat = ShaderMaterial.new()
	_shaft_mat.shader = SHAFT_SHADER
	_shaft_mat.set_shader_parameter("opacity", SHAFT_OPACITY)
	for i: int in SHAFT_COUNT:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = _shaft_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Fixed, spread composition: beams lean the same way, like one light.
		var x: float = -4.5 + 3.0 * float(i)
		mi.position = Vector3(x, SHAFT_SIZE.y * 0.42, -32.0 - 11.0 * float(i % 2) - 6.0 * float(i))
		mi.rotation_degrees = Vector3(0.0, 0.0, -14.0)
		mi.set_instance_shader_parameter("seed", float(i) * 0.37)
		root.add_child(mi)
	root.visible = false
	return root


func _make_core_shadow() -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(CORE_SHADOW_SIZE, CORE_SHADOW_SIZE)
	quad.orientation = PlaneMesh.FACE_Y
	mi.mesh = quad
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = ViewKit.soft_dot_texture()
	m.albedo_color = Color(0, 0, 0, CORE_SHADOW_ALPHA)
	m.render_priority = -1
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _spawn_entities(lvl: SimLevel, d: float) -> void:
	var n: int = lvl.entity_count()
	while _spawn_cursor < n and lvl.e_d[_spawn_cursor] < d + VIEW_AHEAD:
		var i: int = _spawn_cursor
		_spawn_cursor += 1
		var type: int = lvl.e_type[i]
		if type == SimConst.EntityType.SPARK or type == SimConst.EntityType.PRISM:
			continue
		if type == SimConst.EntityType.SHIELD and not session.sim.shields_allowed:
			continue
		if _entity_end(lvl, i) < d - VIEW_BEHIND:
			continue
		var view: EntityView = _pool.acquire() as EntityView
		view.configure(i, type, lvl, kit)
		_active[i] = view


## Ribs on a fixed 7 u rhythm; monolith worlds vary height by a fixed pattern
## (controlled variation, never random).
func _place_ribs(d: float) -> void:
	var base_index: int = int(floorf(d / RIB_SPACING))
	var mm: MultiMesh = _ribs.multimesh
	var vary: bool = theme != null and theme.rib_profile == "monolith"
	var floating: bool = theme != null and theme.atmosphere == "stars"
	for i: int in mm.instance_count:
		var rib_index: int = base_index + i - 1
		var z: float = -float(rib_index) * RIB_SPACING
		var sy: float = RIB_HEIGHT_PATTERN[posmod(rib_index, RIB_HEIGHT_PATTERN.size())] if vary else 1.0
		var y: float = (sy - 1.0) * 1.5 if floating else 0.0
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, sy, 1.0)), Vector3(0.0, y, z)))
		if _details.visible and i < _details.multimesh.instance_count:
			_details.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, z - RIB_SPACING * 0.5)))


func _setup_atmosphere() -> void:
	var p: CPUParticles3D = _atmosphere
	p.lifetime = 5.0
	p.preprocess = 5.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(5.5, 2.2, 18.0)
	p.direction = Vector3(0, 1, 0)
	p.spread = 25.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.08
	p.initial_velocity_max = 0.25
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	# Soft round mote (never a hard square sprite).
	mat.albedo_texture = ViewKit.soft_dot_texture()
	quad.material = mat
	p.mesh = quad
	var color: Color = theme.key_color
	var alpha: float = 0.06
	match theme.atmosphere:
		"embers":
			color = Color("#ffb37a")
			p.gravity = Vector3(0, 0.35, 0)
			alpha = 0.08
		"bubbles":
			color = theme.key_color
			p.gravity = Vector3(0, 0.3, 0)
			quad.size = Vector2(0.07, 0.07)
		"snow":
			color = Color.WHITE
			p.gravity = Vector3(0, -0.35, 0)
			alpha = 0.08
		"sand":
			color = theme.key_color
			p.gravity = Vector3(0.6, -0.05, 0)
		"stars":
			color = Color("#c8c6e8")
			p.direction = Vector3(0, 0, 1)
			p.initial_velocity_min = 2.0
			p.initial_velocity_max = 3.0
			alpha = 0.08
		"puffs":
			color = Color.WHITE
			quad.size = Vector2(0.4, 0.4)
			alpha = 0.05
		"sprinkles":
			color = theme.story_accent.lightened(0.4)
			p.gravity = Vector3(0, -0.25, 0)
			alpha = 0.08
	# ART_DIRECTION §7: decoration stays at or under 8 % opacity.
	p.color = Palette.with_alpha(color, minf(alpha, ATMOSPHERE_MAX_ALPHA))
	_apply_atmosphere_quality()


# --- Juice (ART_DIRECTION §9) ----------------------------------------------------


func _update_juice(delta: float) -> void:
	_chroma = move_toward(_chroma, 0.0, delta * 3.0)
	_shock = move_toward(_shock, 0.0, delta * 2.2)
	_shock_radius += delta * 1.5
	_tint = move_toward(_tint, 0.0, delta * 1.6)
	if _slowmo_left > 0.0:
		_slowmo_left -= delta
		session.time_scale = _slowmo_scale
		if _slowmo_left <= 0.0 and not _end_slow:
			session.time_scale = 1.0
	var active: bool = post_fx_enabled and (_chroma > 0.01 or _shock > 0.01 or _tint > 0.01)
	post_rect.visible = active
	if active:
		_post_mat.set_shader_parameter("chroma", _chroma)
		_post_mat.set_shader_parameter("shock", _shock)
		_post_mat.set_shader_parameter("shock_radius", _shock_radius)
		_post_mat.set_shader_parameter("tint", _tint)
		_post_mat.set_shader_parameter("tint_color", _tint_color)


func hit_stop(seconds: float) -> void:
	session.hit_stop = maxf(session.hit_stop, seconds * (0.5 if reduce_motion else 1.0))


func slow_motion(scale_value: float, seconds: float) -> void:
	if reduce_motion:
		return
	_slowmo_scale = scale_value
	_slowmo_left = maxf(_slowmo_left, seconds)


func shockwave(strength: float) -> void:
	var style: float = clampf(float(_effect_skin.get("shockwave", 1.0)), 0.0, 2.0)
	_shock = maxf(_shock, strength * style * (0.5 if reduce_motion else 1.0))
	_shock_radius = 0.0


func edge_tint(color: Color, amount: float) -> void:
	_tint_color = color
	_tint = maxf(_tint, amount)


func music_beat(strength: float) -> void:
	_music_pulse = maxf(_music_pulse, strength)


func _entity_pos(index: int) -> Vector3:
	var lvl: SimLevel = session.sim_level
	return Vector3(SimConst.lane_x(lvl.e_lane[index], lvl.lane_count), CORE_Y, -lvl.e_d[index])


func _on_frame_events(events: PackedInt32Array) -> void:
	var i: int = 0
	while i + 2 < events.size():
		_handle_event(events[i], events[i + 1], events[i + 2])
		i += 3


func _handle_event(type: int, ent: int, value: int) -> void:
	var sim: FluxSim = session.sim
	var core: Vector3 = core_view.position
	match type:
		SimConst.EventType.TAP_HOP, SimConst.EventType.TAP_PHASE, SimConst.EventType.TAP_DASH, SimConst.EventType.TAP_SURGE:
			ripples.emit(core, Palette.form_color(sim.form, sim.phase, sim.heavy))
			_handle_tap(type, value)
		SimConst.EventType.TAP_DASH_DENIED:
			ripples.emit(core, Palette.FOG)
			core_view.punch(-0.12)
			feedback.emit(&"denied", 0.2, 0)
		SimConst.EventType.SPARK, SimConst.EventType.PRISM:
			var pos: Vector3 = sparks.position_of(ent)
			sparks.hide_entity(ent)
			var col: Color = sparks.color_of(ent, session.sim_level)
			if session.sim_level.e_color[ent] < 0:
				# Neutral sparks and prisms take the equipped particle colours;
				# phase-coloured sparks keep their phase (it is information).
				col = _particle_color(0 if type == SimConst.EventType.SPARK else 1, col)
			bursts.emit("collect" if type == SimConst.EventType.SPARK else "prism", pos, col)
			core_view.punch(0.08 if type == SimConst.EventType.SPARK else 0.2)
			feedback.emit(&"collect" if type == SimConst.EventType.SPARK else &"prism", 0.3, sim.combo)
		SimConst.EventType.SPARK_MISSED:
			feedback.emit(&"miss", 0.2, 0)
		SimConst.EventType.NEAR_MISS:
			bursts.emit("streak", _entity_pos(ent), _particle_color(2, Palette.BONE))
			if sim.combo >= NEAR_MISS_SLOWMO_COMBO:
				slow_motion(0.75, 0.08)
			feedback.emit(&"near_miss", 0.5, sim.combo)
		SimConst.EventType.SHATTER, SimConst.EventType.CHAIN:
			bursts.emit("shatter", _entity_pos(ent) + Vector3(0, 0.1, 0), Palette.GLASS_TINT)
			_release_entity(ent)
			hit_stop(0.03 if type == SimConst.EventType.SHATTER else 0.015)
			camera_rig.add_trauma(SHAKE_SHATTER)
			feedback.emit(&"shatter" if type == SimConst.EventType.SHATTER else &"chain", 0.6, value)
		SimConst.EventType.GATE_PASS:
			_flash_entity(ent, 1.0)
			feedback.emit(&"gate", 0.4, sim.combo)
		SimConst.EventType.HIT_SHIELDED:
			hit_stop(0.06)
			camera_rig.add_trauma(SHAKE_SHIELD)
			bursts.emit("shield", core, Palette.SUCCESS)
			_release_entity(ent)
			feedback.emit(&"shield_break", 0.8, 0)
		SimConst.EventType.ZEN_BUMP:
			camera_rig.add_trauma(0.15)
			core_view.punch(-0.2)
			feedback.emit(&"bump", 0.3, 0)
		SimConst.EventType.FAIL:
			hit_stop(0.09)
			camera_rig.add_trauma(SHAKE_FAIL)
			_chroma = 0.8
			edge_tint(_effect_color("fail_color", Palette.FAILURE), 0.55)
			core_view.implode()
			bursts.emit_delayed("fail", core, Palette.form_color(sim.form, sim.phase, sim.heavy), 0.06)
			feedback.emit(&"fail", 1.0, 0)
		SimConst.EventType.COMPLETE:
			_end_slow = true
			session.time_scale = 0.4
			var perfect: bool = sim.damage == 0 and sim.sparks >= session.sim_level.spark_total
			if perfect:
				var perfect_col: Color = _effect_color("perfect_color", Palette.ACCENT)
				bursts.emit("perfect", core + Vector3(0, 0.2, -0.6), perfect_col)
				shockwave(0.6)
				edge_tint(perfect_col, 0.25)
			feedback.emit(&"perfect" if perfect else &"complete", 1.0, 0)
		SimConst.EventType.FORM_CHANGE:
			core_view.morph()
			_flash_entity(ent, 1.0)
			shockwave(0.35)
			feedback.emit(&"form", 0.7, value)
		SimConst.EventType.PORTAL:
			_flash_entity(ent, 1.0)
			trail.clear_points()
			feedback.emit(&"portal", 0.6, 0)
		SimConst.EventType.CURRENT:
			camera_rig.impulse(Vector3(HOP_LEAN, 0.0, 0.0))
			feedback.emit(&"current", 0.4, 0)
		SimConst.EventType.SHIELD_UP, SimConst.EventType.MAGNET_UP:
			core_view.punch(0.25)
			feedback.emit(&"pickup", 0.5, 0 if type == SimConst.EventType.SHIELD_UP else 1)
		SimConst.EventType.OVERDRIVE_START:
			shockwave(0.45)
			_chroma = maxf(_chroma, 0.35)
			feedback.emit(&"overdrive", 0.9, 0)
		SimConst.EventType.OVERDRIVE_END:
			feedback.emit(&"overdrive_end", 0.3, 0)
		SimConst.EventType.COMBO_STEP:
			bursts.emit("ring", core, Palette.form_color(sim.form, sim.phase, sim.heavy))
			feedback.emit(&"combo", clampf(float(value) / 30.0, 0.3, 1.0), value)
		_:
			_handle_mass_event(type, ent, value)


## Accepted taps: the form's own motion, camera cue and sound/haptic.
func _handle_tap(type: int, value: int) -> void:
	var core: Vector3 = core_view.position
	match type:
		SimConst.EventType.TAP_HOP:
			var target_x: float = SimConst.lane_x(value, session.sim_level.lane_count)
			core_view.hop_motion(signf(target_x - core.x))
			camera_rig.impulse(Vector3(HOP_LEAN * signf(target_x - core.x), 0.0, 0.0))
			feedback.emit(&"tap", 0.4, value)
		SimConst.EventType.TAP_PHASE:
			core_view.phase_motion()
			feedback.emit(&"phase", 0.5, value)
		SimConst.EventType.TAP_DASH:
			core_view.squash(Vector3(0, 0, 1), 0.45)
			camera_rig.fov_punch(4.0)
			feedback.emit(&"dash", 0.6, 0)
		SimConst.EventType.TAP_SURGE:
			core_view.squash(Vector3(0, 1, 0), -0.3 if value == 1 else 0.25)
			camera_rig.fov_punch(3.0 if value == 1 else 0.0)
			feedback.emit(&"surge", 0.5, value)


## Launch pads, gravity wells and mass plates.
func _handle_mass_event(type: int, ent: int, value: int) -> void:
	var core: Vector3 = core_view.position
	match type:
		SimConst.EventType.LAUNCH:
			core_view.squash(Vector3(0, 1, 0), 0.4)
			_flash_entity(ent, 1.0)
			bursts.emit("ring", core, Palette.PRIMARY)
			feedback.emit(&"launch", 0.6, value)
		SimConst.EventType.LAND:
			core_view.squash(Vector3(0, 1, 0), -0.35)
			camera_rig.add_trauma(SHAKE_LAND)
			feedback.emit(&"land", 0.4, 0)
		SimConst.EventType.VAULT:
			bursts.emit("streak", _entity_pos(ent), _particle_color(2, Palette.BONE))
			feedback.emit(&"near_miss", 0.5, session.sim.combo)
		SimConst.EventType.STACK_CRASH:
			hit_stop(0.05)
			core_view.punch(0.3)
			feedback.emit(&"stack_crash", 0.8, 0)
		SimConst.EventType.GRAVITY_ENTER:
			var heavy: bool = value > 100
			edge_tint(Palette.FORM_SURGE_HEAVY if heavy else Palette.FORM_SURGE_LIGHT, 0.18)
			feedback.emit(&"gravity", 0.4, 1 if heavy else 0)
		SimConst.EventType.PLATE_UP:
			core_view.punch(0.15)
			feedback.emit(&"plate", 0.4, value)


func _flash_entity(index: int, amount: float) -> void:
	if _active.has(index):
		(_active[index] as EntityView).flash(amount)


func _release_entity(index: int) -> void:
	if _active.has(index):
		_pool.release(_active[index] as Node)
		_active.erase(index)
