class_name GameplayView
extends Node3D
## 3D presentation of a [GameplaySession]: environment, shaft, entities, core,
## trail, particles and all game-feel ("juice") reactions to sim events.
##
## Emits [signal feedback] so audio/haptics systems can react without the view
## depending on them.

signal feedback(kind: StringName, strength: float, pitch_step: int)

const SKY_SHADER: Shader = preload("res://assets/shaders/sky.gdshader")
const FLOOR_SHADER: Shader = preload("res://assets/shaders/floor.gdshader")
const POST_SHADER: Shader = preload("res://assets/shaders/post_fx.gdshader")
const GLOW_SHADER: Shader = preload("res://assets/shaders/glow_sprite.gdshader")
const VIEW_AHEAD: float = 75.0
const VIEW_BEHIND: float = 6.0
const FRAME_SPACING: float = 7.0
const FRAME_COUNT: int = 14
const FLOOR_LENGTH: float = 160.0
const CORE_Y: float = 0.38

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
var sun: DirectionalLight3D
var post_rect: ColorRect
var post_layer: CanvasLayer

## Quality-driven toggles.
var post_fx_enabled: bool = true
var shake_scale: float = 1.0
var reduce_motion: bool = false

var _floor: MeshInstance3D
var _floor_mat: ShaderMaterial
var _sky_mat: ShaderMaterial
var _post_mat: ShaderMaterial
var _frames: MultiMeshInstance3D
var _ambient: CPUParticles3D
var _finish: Node3D
var _pool: NodePool
var _active: Dictionary = {}
var _spawn_cursor: int = 0
var _chroma: float = 0.0
var _shock: float = 0.0
var _shock_radius: float = 0.0
var _flash: float = 0.0
var _flash_color: Color = Color.WHITE
var _slowmo_left: float = 0.0
var _slowmo_scale: float = 1.0
var _end_slow: bool = false
var _music_pulse: float = 0.0


func _ready() -> void:
	world_env = WorldEnvironment.new()
	environment = Environment.new()
	world_env.environment = environment
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 25.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	camera_rig = CameraRig.new()
	add_child(camera_rig)
	_floor = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(14.0, FLOOR_LENGTH)
	plane.subdivide_depth = 0
	_floor.mesh = plane
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = FLOOR_SHADER
	_floor.material_override = _floor_mat
	_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_floor)
	_frames = _build_frames()
	add_child(_frames)
	sparks = SparkField.new()
	add_child(sparks)
	core_view = CoreView.new()
	add_child(core_view)
	trail = TrailRibbon.new()
	add_child(trail)
	bursts = BurstPool.new()
	add_child(bursts)
	_ambient = CPUParticles3D.new()
	add_child(_ambient)
	_finish = _build_finish_gate()
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
	post_layer.add_child(post_rect)


func bind(gameplay_session: GameplaySession) -> void:
	session = gameplay_session
	if not session.frame_events.is_connected(_on_frame_events):
		session.frame_events.connect(_on_frame_events)


## Applies a world's identity: palette, lighting, fog, glow, particles.
func apply_world(world_theme: WorldTheme) -> void:
	theme = world_theme
	kit = ViewKit.new(theme)
	environment.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SKY_SHADER
	_sky_mat.set_shader_parameter("sky_top", theme.sky_top)
	_sky_mat.set_shader_parameter("sky_bottom", theme.sky_bottom)
	_sky_mat.set_shader_parameter("sink_color", theme.primary)
	_sky_mat.set_shader_parameter("accent_color", theme.secondary)
	_sky_mat.set_shader_parameter("star_density", 0.2 if theme.bright else 0.8)
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = theme.ambient
	environment.ambient_light_energy = theme.ambient_energy
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.0
	environment.glow_enabled = true
	environment.glow_intensity = theme.glow
	environment.glow_bloom = 0.08
	environment.glow_hdr_threshold = 0.9
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.fog_enabled = true
	environment.fog_light_color = theme.fog
	environment.fog_density = theme.fog_density
	environment.fog_sky_affect = 0.0
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.08
	environment.adjustment_contrast = 1.05
	sun.light_color = theme.sun_color
	sun.light_energy = theme.sun_energy
	_floor_mat.set_shader_parameter("floor_color", theme.floor_color)
	_floor_mat.set_shader_parameter("grid_color", theme.grid)
	_floor_mat.set_shader_parameter("rail_color", theme.primary)
	_floor_mat.set_shader_parameter("fog_color", theme.fog)
	var frame_mat: StandardMaterial3D = StandardMaterial3D.new()
	frame_mat.albedo_color = theme.floor_color.darkened(0.2)
	frame_mat.emission_enabled = true
	frame_mat.emission = theme.grid
	frame_mat.emission_energy_multiplier = 0.7
	frame_mat.roughness = 0.3
	frame_mat.metallic = 0.6
	_frames.material_override = frame_mat
	_setup_ambient_particles()
	trail.set_colors(theme.primary, theme.secondary)
	var finish_mat: ShaderMaterial = (_finish.get_child(0) as MeshInstance3D).material_override as ShaderMaterial
	finish_mat.set_shader_parameter("glow_color", theme.primary)


## Builds visuals for the session's current level.
func setup_level() -> void:
	clear_entities()
	var lvl: SimLevel = session.sim_level
	_floor_mat.set_shader_parameter("lane_count", lvl.lane_count)
	_floor_mat.set_shader_parameter("lane_width", SimConst.LANE_WIDTH)
	sparks.build(lvl, theme)
	_finish.visible = not lvl.endless
	_finish.position = Vector3(0.0, 0.8, -lvl.length)
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
	_flash = 0.0
	_slowmo_left = 0.0
	_end_slow = false
	bursts.stop_all()
	_update_frame(0.0)


func clear_entities() -> void:
	for idx: Variant in _active.keys():
		_pool.release(_active[idx] as Node)
	_active.clear()


func set_quality(post_fx: bool, particle_scale: float, trail_points: int, dynamic_light: bool, shadows: bool) -> void:
	post_fx_enabled = post_fx
	bursts.set_amount_scale(particle_scale)
	trail.set_length(trail_points)
	core_view.set_light_enabled(dynamic_light)
	sun.shadow_enabled = shadows
	_ambient.amount = maxi(8, int(60.0 * particle_scale))


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
	if core_view.visible:
		trail.push_point(core_pos + Vector3(0.0, -0.02, 0.18))
	trail.set_intensity(1.2 + clampf(float(sim.combo) / 20.0, 0.0, 1.0) * 1.4)
	camera_rig.follow(core_pos, delta)
	trail.rebuild(camera_rig.camera)
	_floor.position = Vector3(0.0, 0.0, -d - FLOOR_LENGTH * 0.5 + 12.0)
	_floor_mat.set_shader_parameter("scroll", d + FLOOR_LENGTH * 0.5 - 12.0)
	_floor_mat.set_shader_parameter("pulse", _music_pulse)
	_place_frames(d)
	_ambient.position = Vector3(0.0, 1.5, -d - 18.0)
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("drift", d)
		_sky_mat.set_shader_parameter("pulse", _music_pulse * 0.4)
	_spawn_entities(lvl, d)
	for idx: Variant in _active.keys():
		var view: EntityView = _active[idx] as EntityView
		if lvl.e_d[int(idx)] < d - VIEW_BEHIND or (sim.ent_flags[int(idx)] & FluxSim.FLAG_CONSUMED) != 0 and _is_pickup(view.entity_type):
			_pool.release(view)
			_active.erase(idx)
			continue
		view.animate(delta, lvl, t)
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


func _build_frames() -> MultiMeshInstance3D:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var span: float = 3.4
	var height: float = 3.6
	var thick: float = 0.12
	_append_box(st, Vector3(-span, height * 0.5, 0.0), Vector3(thick, height, thick))
	_append_box(st, Vector3(span, height * 0.5, 0.0), Vector3(thick, height, thick))
	_append_box(st, Vector3(0.0, height, 0.0), Vector3(span * 2.0 + thick, thick, thick))
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = FRAME_COUNT
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


func _append_box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	var arrays: Array = box.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	for idx: int in indices:
		st.add_vertex(verts[idx] + center)


func _place_frames(d: float) -> void:
	var base: float = floorf(d / FRAME_SPACING) * FRAME_SPACING
	var mm: MultiMesh = _frames.multimesh
	for i: int in FRAME_COUNT:
		var z: float = -(base + float(i - 1) * FRAME_SPACING)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, z)))


func _build_finish_gate() -> Node3D:
	var root: Node3D = Node3D.new()
	var glow: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	glow.mesh = quad
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = GLOW_SHADER
	mat.set_shader_parameter("size", 7.0)
	mat.set_shader_parameter("ring", 0.7)
	mat.set_shader_parameter("intensity", 1.6)
	glow.material_override = mat
	root.add_child(glow)
	var ring: MeshInstance3D = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 2.4
	torus.outer_radius = 2.6
	ring.mesh = torus
	ring.rotation_degrees = Vector3(90, 0, 0)
	var ring_mat: StandardMaterial3D = StandardMaterial3D.new()
	ring_mat.emission_enabled = true
	ring_mat.emission = Color.WHITE
	ring_mat.emission_energy_multiplier = 2.0
	ring.material_override = ring_mat
	root.add_child(ring)
	return root


func _setup_ambient_particles() -> void:
	var p: CPUParticles3D = _ambient
	p.amount = 60
	p.lifetime = 4.0
	p.preprocess = 4.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(7.0, 4.0, 22.0)
	p.direction = Vector3(0, 1, 0)
	p.spread = 30.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.6
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	p.mesh = quad
	var color: Color = theme.primary
	match theme.ambient_particles:
		"embers":
			color = Color("#ffae5c")
			p.gravity = Vector3(0, 0.8, 0)
		"bubbles":
			color = Color("#bffff0")
			p.gravity = Vector3(0, 0.6, 0)
			quad.size = Vector2(0.12, 0.12)
		"snow":
			color = Color.WHITE
			p.gravity = Vector3(0, -0.8, 0)
		"sand":
			color = Color("#ffd9a0")
			p.gravity = Vector3(1.5, -0.1, 0)
		"stars":
			color = Color("#e6dcff")
			p.direction = Vector3(0, 0, 1)
			p.initial_velocity_min = 6.0
			p.initial_velocity_max = 10.0
		"puffs":
			color = Color(1, 1, 1, 0.5)
			quad.size = Vector2(0.5, 0.5)
		"sprinkles":
			color = Color("#ff9ae0")
			p.gravity = Vector3(0, -0.6, 0)
		"spores":
			color = Color("#b6ff8a")
		"glitter":
			color = Color("#e8d0ff")
	p.color = color
	p.emitting = true


# --- Juice ---------------------------------------------------------------------


func _update_juice(delta: float) -> void:
	_chroma = move_toward(_chroma, 0.0, delta * 4.0)
	_shock = move_toward(_shock, 0.0, delta * 2.5)
	_shock_radius += delta * 1.6
	_flash = move_toward(_flash, 0.0, delta * 3.5)
	if _slowmo_left > 0.0:
		_slowmo_left -= delta
		session.time_scale = _slowmo_scale
		if _slowmo_left <= 0.0 and not _end_slow:
			session.time_scale = 1.0
	var active: bool = post_fx_enabled and (_chroma > 0.01 or _shock > 0.01 or _flash > 0.01)
	post_rect.visible = active
	if active:
		_post_mat.set_shader_parameter("chroma", _chroma)
		_post_mat.set_shader_parameter("shock", _shock)
		_post_mat.set_shader_parameter("shock_radius", _shock_radius)
		_post_mat.set_shader_parameter("flash", _flash)
		_post_mat.set_shader_parameter("flash_color", _flash_color)


func hit_stop(seconds: float) -> void:
	if reduce_motion:
		seconds *= 0.5
	session.hit_stop = maxf(session.hit_stop, seconds)


func slow_motion(scale: float, seconds: float) -> void:
	if reduce_motion:
		return
	_slowmo_scale = scale
	_slowmo_left = maxf(_slowmo_left, seconds)


func shockwave(strength: float, screen_center: Vector2 = Vector2(0.5, 0.72)) -> void:
	_shock = maxf(_shock, strength)
	_shock_radius = 0.0
	_post_mat.set_shader_parameter("shock_center", screen_center)


func screen_flash(color: Color, amount: float) -> void:
	_flash_color = color
	_flash = maxf(_flash, amount * (0.5 if reduce_motion else 1.0))


func music_beat(strength: float) -> void:
	_music_pulse = maxf(_music_pulse, strength)


func _entity_pos(index: int) -> Vector3:
	var lvl: SimLevel = session.sim_level
	return Vector3(SimConst.lane_x(lvl.e_lane[index], lvl.lane_count), CORE_Y, -lvl.e_d[index])


func _on_frame_events(events: PackedInt32Array) -> void:
	var sim: FluxSim = session.sim
	var core: Vector3 = core_view.position
	var i: int = 0
	while i + 2 < events.size():
		var type: int = events[i]
		var ent: int = events[i + 1]
		var value: int = events[i + 2]
		i += 3
		match type:
			SimConst.EventType.TAP_HOP:
				core_view.squash(Vector3(1, 0, 0), 0.35)
				camera_rig.impulse(Vector3(0.6 if core.x < SimConst.lane_x(value, session.sim_level.lane_count) else -0.6, 0.0, 0.0))
				bursts.emit("tap", core, theme.primary)
				feedback.emit(&"tap", 0.4, value)
			SimConst.EventType.TAP_PHASE:
				core_view.punch(0.45)
				core_view.flash_pulse(0.8)
				bursts.emit("tap", core, EntityView.PHASE_COLORS[clampi(value, 0, 1)])
				feedback.emit(&"phase", 0.5, value)
			SimConst.EventType.TAP_DASH:
				core_view.squash(Vector3(0, 0, 1), 0.5)
				camera_rig.fov_punch(7.0)
				_chroma = maxf(_chroma, 0.6)
				feedback.emit(&"dash", 0.6, 0)
			SimConst.EventType.TAP_DASH_DENIED:
				core_view.punch(-0.15)
				feedback.emit(&"denied", 0.2, 0)
			SimConst.EventType.TAP_SURGE:
				core_view.squash(Vector3(0, 1, 0), 0.4 if value == 1 else -0.3)
				camera_rig.fov_punch(5.0 if value == 1 else 0.0)
				feedback.emit(&"surge", 0.5, value)
			SimConst.EventType.SPARK, SimConst.EventType.PRISM:
				var pos: Vector3 = sparks.position_of(ent)
				sparks.hide_entity(ent)
				var col: Color = sparks.color_of(ent, theme, session.sim_level)
				bursts.emit("spark", pos, col)
				core_view.punch(0.12 if type == SimConst.EventType.SPARK else 0.35)
				feedback.emit(&"collect" if type == SimConst.EventType.SPARK else &"prism", 0.3, sim.combo)
			SimConst.EventType.SPARK_MISSED:
				feedback.emit(&"miss", 0.2, 0)
			SimConst.EventType.NEAR_MISS:
				slow_motion(0.55, 0.12)
				_chroma = maxf(_chroma, 0.5)
				_flash_entity(ent, 1.0)
				feedback.emit(&"near_miss", 0.5, sim.combo)
			SimConst.EventType.SHATTER, SimConst.EventType.CHAIN:
				var spos: Vector3 = _entity_pos(ent)
				bursts.emit("shatter", spos + Vector3(0, 0.4, 0), EntityView.BREAKABLE_COLOR)
				_release_entity(ent)
				hit_stop(0.035 if type == SimConst.EventType.SHATTER else 0.02)
				camera_rig.add_trauma(0.25)
				feedback.emit(&"shatter" if type == SimConst.EventType.SHATTER else &"chain", 0.6, value)
			SimConst.EventType.GATE_PASS:
				bursts.emit("gate", _entity_pos(ent) + Vector3(-_entity_pos(ent).x, 0.3, 0), EntityView.PHASE_COLORS[sim.phase])
				_flash_entity(ent, 1.0)
				feedback.emit(&"gate", 0.4, sim.combo)
			SimConst.EventType.HIT_SHIELDED:
				hit_stop(0.06)
				camera_rig.add_trauma(0.5)
				bursts.emit("hit", core, Color("#9fffe0"))
				_release_entity(ent)
				screen_flash(Color("#9fffe0"), 0.35)
				feedback.emit(&"shield_break", 0.8, 0)
			SimConst.EventType.ZEN_BUMP:
				camera_rig.add_trauma(0.2)
				bursts.emit("hit", core, theme.secondary)
				feedback.emit(&"bump", 0.3, 0)
			SimConst.EventType.FAIL:
				hit_stop(0.09)
				camera_rig.add_trauma(0.9)
				_chroma = 1.2
				shockwave(1.0)
				screen_flash(theme.hazard, 0.45)
				bursts.emit("fail", core, theme.primary)
				bursts.emit("hit", core, theme.hazard)
				core_view.visible = false
				feedback.emit(&"fail", 1.0, 0)
			SimConst.EventType.COMPLETE:
				_end_slow = true
				session.time_scale = 0.35
				var perfect: bool = sim.damage == 0 and sim.sparks >= session.sim_level.spark_total
				bursts.emit("perfect" if perfect else "combo", core + Vector3(0, 0.3, -1.0), theme.accent if perfect else theme.primary)
				shockwave(0.9 if perfect else 0.5)
				screen_flash(theme.accent if perfect else Color.WHITE, 0.35 if perfect else 0.2)
				feedback.emit(&"perfect" if perfect else &"complete", 1.0, 0)
			SimConst.EventType.FORM_CHANGE:
				core_view.punch(0.7)
				core_view.flash_pulse(1.2)
				shockwave(0.4)
				_chroma = maxf(_chroma, 0.4)
				feedback.emit(&"form", 0.7, value)
			SimConst.EventType.PORTAL:
				screen_flash(theme.secondary, 0.25)
				shockwave(0.35)
				trail.clear_points()
				feedback.emit(&"portal", 0.6, 0)
			SimConst.EventType.CURRENT:
				camera_rig.impulse(Vector3(0.9, 0.0, 0.0))
				feedback.emit(&"current", 0.4, 0)
			SimConst.EventType.SHIELD_UP:
				core_view.punch(0.4)
				feedback.emit(&"pickup", 0.5, 0)
			SimConst.EventType.MAGNET_UP:
				core_view.punch(0.4)
				feedback.emit(&"pickup", 0.5, 1)
			SimConst.EventType.OVERDRIVE_START:
				shockwave(0.7)
				_chroma = maxf(_chroma, 0.8)
				bursts.emit("combo", core, theme.accent)
				feedback.emit(&"overdrive", 0.9, 0)
			SimConst.EventType.OVERDRIVE_END:
				feedback.emit(&"overdrive_end", 0.3, 0)
			SimConst.EventType.COMBO_STEP:
				bursts.emit("combo", core, theme.secondary if value % 10 == 0 else theme.primary)
				core_view.flash_pulse(0.6)
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
