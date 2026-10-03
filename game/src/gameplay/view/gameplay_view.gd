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
const VIEW_BEHIND: float = 6.0
const RIB_SPACING: float = 7.0
const RIB_COUNT: int = 16
const RIB_HEIGHT_PATTERN: Array[float] = [1.0, 0.88, 1.06, 0.94]
const FLOOR_LENGTH: float = 160.0
const FLOOR_WIDTH: float = 9.0
const CORE_Y: float = 0.38
const SILHOUETTE_DISTANCE: float = 150.0
const SILHOUETTE_PARALLAX: float = 0.03
const FOG_BEGIN: float = 28.0
const FOG_END: float = 115.0
## Juice budgets (ART_DIRECTION §9).
const SHAKE_FAIL: float = 0.6
const SHAKE_SHIELD: float = 0.35
const SHAKE_SHATTER: float = 0.12
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

## Quality / accessibility toggles.
var post_fx_enabled: bool = true
var reduce_motion: bool = false

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
	_apply_environment()
	key_light.light_color = theme.key_color
	key_light.light_energy = theme.key_energy
	key_light.rotation_degrees = Vector3(theme.key_pitch, theme.key_yaw, 0.0)
	_floor_mat.set_shader_parameter("floor_color", theme.floor_color)
	_floor_mat.set_shader_parameter("lane_color", theme.lane_color)
	_floor_mat.set_shader_parameter("fog_color", theme.fog)
	_floor_mat.set_shader_parameter("caustics", 0.12 if theme.caustics else 0.0)
	_floor_mat.set_shader_parameter("caustic_color", theme.key_color)
	_ribs.multimesh.mesh = MeshFactory.rib(theme.rib_profile)
	_ribs.multimesh.instance_count = RIB_COUNT
	_ribs.material_override = kit.structure_material
	_silhouette.mesh = MeshFactory.silhouette(theme.silhouette)
	_silhouette_mat.albedo_color = theme.sky_bottom.lerp(theme.story_accent, 0.2)
	_finish_arch.mesh = kit.arch_mesh(3)
	_finish_arch.material_override = kit.structure_material
	_finish_arch.scale = Vector3(1.0, 1.4, 1.0)
	_finish_membrane.mesh = kit.membrane_mesh(3)
	_finish_membrane.position = Vector3(0.0, ViewKit.ARCH_HEIGHT * 0.68, 0.0)
	_finish_membrane.scale = Vector3(1.0, 1.4, 1.0)
	_setup_atmosphere()
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
	environment.glow_enabled = true
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
	core_view.apply_skin(0, Palette.PRIMARY, Palette.PRIMARY.darkened(0.35), Color.WHITE)
	trail.set_colors(Palette.PRIMARY, Palette.with_alpha(Palette.PRIMARY.darkened(0.5), 0.0))


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
	bursts.stop_all()
	_update_frame(0.0)


## Endless streaming: new course entities were appended to the running level.
## Hazards spawn through the normal cursor; the spark field is re-windowed.
func on_stream_appended() -> void:
	sparks.rebuild_append(session.sim_level, session.sim.cursor)


func clear_entities() -> void:
	for idx: Variant in _active.keys():
		_pool.release(_active[idx] as Node)
	_active.clear()


## Quality hooks (see QualityService presets).
func set_quality(post_fx: bool, particle_scale: float, trail_points: int, dynamic_light: bool, shadows: bool) -> void:
	_ensure_built()
	post_fx_enabled = post_fx
	bursts.set_amount_scale(particle_scale)
	trail.set_length(trail_points)
	core_view.set_light_enabled(dynamic_light)
	key_light.shadow_enabled = shadows
	if theme != null:
		_atmosphere.amount = maxi(1, int(float(theme.atmosphere_count) * clampf(particle_scale, 0.0, 1.0)))
		_atmosphere.emitting = theme.atmosphere_count > 0 and particle_scale > 0.2


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
	var core_pos: Vector3 = Vector3(x, CORE_Y, -d)
	core_view.position = core_pos
	core_view.set_form(sim.form, sim.phase, sim.heavy)
	core_view.set_direction_hint(sim.form == SimConst.Form.HOP and lvl.lane_count > 2, sim.hop_dir)
	core_view.update_visuals(delta, sim)
	var form_color: Color = Palette.form_color(sim.form, sim.phase, sim.heavy)
	trail.set_colors(form_color, Palette.with_alpha(form_color.darkened(0.5), 0.0))
	trail.width = 0.12 + clampf(float(sim.combo) / 40.0, 0.0, 1.0) * 0.06 + (0.05 if sim.overdrive_timer > 0.0 else 0.0)
	if core_view.visible:
		trail.push_point(core_pos + Vector3(0.0, -0.02, 0.16))
	camera_rig.follow(core_pos, delta)
	trail.rebuild(camera_rig.camera)
	_floor.position = Vector3(0.0, 0.0, -d - FLOOR_LENGTH * 0.5 + 12.0)
	_floor_mat.set_shader_parameter("scroll", d + FLOOR_LENGTH * 0.5 - 12.0)
	_place_ribs(d)
	_silhouette.position = Vector3(0.0, -8.0, -d - SILHOUETTE_DISTANCE + d * SILHOUETTE_PARALLAX)
	if theme != null and theme.silhouette == "turbine":
		# The rotor turns slowly around its own hub (story: World 1's boss machine).
		_silhouette.rotation.z = 0.0
		_turbine_angle += delta * 0.06
		_silhouette.transform.basis = Basis(Vector3.BACK, _turbine_angle)
		_silhouette.position += Vector3(0.0, 30.0, 0.0) - _silhouette.transform.basis * Vector3(0.0, 30.0, 0.0)
	_atmosphere.position = Vector3(0.0, 1.6, -d - 14.0)
	_spawn_entities(lvl, d)
	for idx: Variant in _active.keys():
		var i: int = int(idx)
		var view: EntityView = _active[idx] as EntityView
		var consumed_pickup: bool = (sim.ent_flags[i] & FluxSim.FLAG_CONSUMED) != 0 and _is_pickup(view.entity_type)
		if lvl.e_d[i] < d - VIEW_BEHIND or consumed_pickup:
			_pool.release(view)
			_active.erase(idx)
			continue
		view.animate(delta, lvl, t, d)
	sparks.apply_magnet(core_pos, lvl, sim.cursor, sim.magnet_timer > 0.0 or sim.overdrive_timer > 0.0)
	_music_pulse = move_toward(_music_pulse, 0.0, delta * 3.0)


func _is_pickup(type: int) -> bool:
	return type == SimConst.EntityType.SHIELD or type == SimConst.EntityType.MAGNET


func _spawn_entities(lvl: SimLevel, d: float) -> void:
	var n: int = lvl.entity_count()
	while _spawn_cursor < n and lvl.e_d[_spawn_cursor] < d + VIEW_AHEAD:
		var i: int = _spawn_cursor
		_spawn_cursor += 1
		var type: int = lvl.e_type[i]
		if type == SimConst.EntityType.SPARK or type == SimConst.EntityType.PRISM:
			continue
		if lvl.e_d[i] < d - VIEW_BEHIND:
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


func _setup_atmosphere() -> void:
	var p: CPUParticles3D = _atmosphere
	p.amount = maxi(1, theme.atmosphere_count)
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
	var alpha: float = 0.22
	match theme.atmosphere:
		"embers":
			color = Color("#ffb37a")
			p.gravity = Vector3(0, 0.35, 0)
			alpha = 0.5
		"bubbles":
			color = theme.key_color
			p.gravity = Vector3(0, 0.3, 0)
			quad.size = Vector2(0.07, 0.07)
		"snow":
			color = Color.WHITE
			p.gravity = Vector3(0, -0.35, 0)
			alpha = 0.4
		"sand":
			color = theme.key_color
			p.gravity = Vector3(0.6, -0.05, 0)
		"stars":
			color = Color("#c8c6e8")
			p.direction = Vector3(0, 0, 1)
			p.initial_velocity_min = 2.0
			p.initial_velocity_max = 3.0
			alpha = 0.35
		"puffs":
			color = Color.WHITE
			quad.size = Vector2(0.4, 0.4)
			alpha = 0.12
		"sprinkles":
			color = theme.story_accent.lightened(0.4)
			p.gravity = Vector3(0, -0.25, 0)
			alpha = 0.45
	p.color = Palette.with_alpha(color, alpha)
	p.emitting = theme.atmosphere_count > 0


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
	_shock = maxf(_shock, strength * (0.5 if reduce_motion else 1.0))
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
		SimConst.EventType.TAP_DASH_DENIED:
			core_view.punch(-0.12)
			feedback.emit(&"denied", 0.2, 0)
		SimConst.EventType.TAP_SURGE:
			core_view.squash(Vector3(0, 1, 0), -0.3 if value == 1 else 0.25)
			camera_rig.fov_punch(3.0 if value == 1 else 0.0)
			feedback.emit(&"surge", 0.5, value)
		SimConst.EventType.SPARK, SimConst.EventType.PRISM:
			var pos: Vector3 = sparks.position_of(ent)
			sparks.hide_entity(ent)
			var col: Color = sparks.color_of(ent, session.sim_level)
			bursts.emit("collect" if type == SimConst.EventType.SPARK else "prism", pos, col)
			core_view.punch(0.08 if type == SimConst.EventType.SPARK else 0.2)
			feedback.emit(&"collect" if type == SimConst.EventType.SPARK else &"prism", 0.3, sim.combo)
		SimConst.EventType.SPARK_MISSED:
			feedback.emit(&"miss", 0.2, 0)
		SimConst.EventType.NEAR_MISS:
			bursts.emit("streak", _entity_pos(ent), Palette.BONE)
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
			edge_tint(Palette.FAILURE, 0.55)
			core_view.implode()
			bursts.emit_delayed("fail", core, Palette.form_color(sim.form, sim.phase, sim.heavy), 0.06)
			feedback.emit(&"fail", 1.0, 0)
		SimConst.EventType.COMPLETE:
			_end_slow = true
			session.time_scale = 0.4
			var perfect: bool = sim.damage == 0 and sim.sparks >= session.sim_level.spark_total
			if perfect:
				bursts.emit("perfect", core + Vector3(0, 0.2, -0.6), Palette.ACCENT)
				shockwave(0.6)
				edge_tint(Palette.ACCENT, 0.25)
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


func _flash_entity(index: int, amount: float) -> void:
	if _active.has(index):
		(_active[index] as EntityView).flash(amount)


func _release_entity(index: int) -> void:
	if _active.has(index):
		_pool.release(_active[index] as Node)
		_active.erase(index)


func active_entity_count() -> int:
	return _active.size()
