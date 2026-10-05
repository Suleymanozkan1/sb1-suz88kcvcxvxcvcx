extends TestCase
## Gaps the detail audit (ART_DIRECTION §13) found, closed: the prism's orbit
## ring, the glitter and spores airs, the form colour winning over colour-
## overriding skins and trails, and the chromatic split reserved for the fail.

const FIXED_UNIX: int = 1790000000

var _app: AppServices
var _session: GameplaySession
var _runs: RunController
var _nodes: Array[Node] = []


func before_each() -> void:
	_app = AppServices.new()
	_app.auto_boot = false
	tree.root.add_child(_app)
	var clock: GameClock = GameClock.new()
	clock.set_fixed_unix(FIXED_UNIX)
	_app.boot(MemorySaveStorage.new(), clock)
	_session = GameplaySession.new()
	tree.root.add_child(_session)
	_runs = RunController.new(_app, _session)
	_nodes.clear()


func after_each() -> void:
	for n: Node in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_session.queue_free()
	_app.queue_free()
	await wait_frames(2)


func _view_for(level_id: String) -> GameplayView:
	var view: GameplayView = GameplayView.new()
	_nodes.append(view)
	tree.root.add_child(view)
	assert_true(_runs.prepare(&"classic", level_id), "prepared %s" % level_id)
	view.bind(_session)
	var world_id: String = str(_session.level_data.get("world", ""))
	view.apply_world(WorldTheme.from_world(_app.catalog.world(world_id)))
	view.setup_level()
	return view


func test_prisms_carry_their_orbit_ring() -> void:
	var view: GameplayView = _view_for("w01_l17")
	var lvl: SimLevel = _session.sim_level
	var prisms: Array[int] = []
	for i: int in lvl.entity_count():
		if lvl.e_type[i] == SimConst.EntityType.PRISM:
			prisms.append(i)
	assert_false(prisms.is_empty(), "w01_l17 has prisms")
	assert_eq(view.sparks.ring_count(), prisms.size(), "one ring per prism")
	var ring: ArrayMesh = MeshFactory.tilted_ring(SparkField.RING_RADIUS, SparkField.RING_TUBE, SparkField.RING_TILT)
	var aabb: AABB = ring.get_aabb()
	assert_gt(aabb.size.y, SparkField.RING_RADIUS, "tilted off the floor plane, so its spin sweeps round the shard")


func test_glitter_and_spores_have_their_own_air() -> void:
	var dust: GameplayView = _view_for("w01_l20")
	var glitter: GameplayView = _view_for("w02_l20")
	var spores: GameplayView = _view_for("w06_l20")
	assert_eq(glitter.theme.atmosphere, "glitter")
	assert_eq(spores.theme.atmosphere, "spores")
	assert_true(glitter._atmosphere.color_ramp != null, "glitter motes twinkle")
	assert_true(dust._atmosphere.color_ramp == null, "plain dust does not")
	var glitter_size: Vector2 = (glitter._atmosphere.mesh as QuadMesh).size
	var spore_size: Vector2 = (spores._atmosphere.mesh as QuadMesh).size
	var dust_size: Vector2 = (dust._atmosphere.mesh as QuadMesh).size
	assert_lt(glitter_size.x, dust_size.x, "glitter is finer than dust")
	assert_gt(spore_size.x, dust_size.x, "spores are larger than dust")
	assert_gt(spores._atmosphere.gravity.y, 0.0, "spores rise")
	for view: GameplayView in [glitter, spores]:
		assert_le(view._atmosphere.color.a, AmbientMotes.MAX_ALPHA + 0.0001, "within the opacity cap")


func test_form_colour_wins_over_colour_overriding_skins() -> void:
	var view: GameplayView = _view_for("w04_l20")
	var core_mat: ShaderMaterial = view.core_view._mat
	view.core_view.set_form(SimConst.Form.HOP, 0, false)
	assert_eq(float(core_mat.get_shader_parameter("form_lock")), 0.0, "HOP shows the skin as bought")
	var skin_b: Color = core_mat.get_shader_parameter("color_b") as Color
	view.core_view.set_form(SimConst.Form.DASH, 0, false)
	assert_eq(float(core_mat.get_shader_parameter("form_lock")), 1.0, "DASH: the form colour wins")
	var dash_b: Color = core_mat.get_shader_parameter("color_b") as Color
	assert_true(
		dash_b.is_equal_approx(Palette.FORM_DASH.darkened(CoreView.FORM_SECOND_SHADE)), "no skin colour mixed in"
	)
	view.core_view.set_form(SimConst.Form.HOP, 0, false)
	assert_true((core_mat.get_shader_parameter("color_b") as Color).is_equal_approx(skin_b), "HOP gets the skin back")
	view.core_view.set_form(SimConst.Form.DASH, 0, false)
	_session.sim.form = SimConst.Form.DASH
	view._update_frame(0.016)
	assert_eq(float(view.trail._mat.get_shader_parameter("form_lock")), 1.0, "and the trail follows")
	_session.sim.form = SimConst.Form.HOP
	view._update_frame(0.016)
	assert_eq(float(view.trail._mat.get_shader_parameter("form_lock")), 0.0)


func test_only_the_fail_splits_colour() -> void:
	var view: GameplayView = _view_for("w01_l20")
	view._handle_event(SimConst.EventType.OVERDRIVE_START, -1, 0)
	assert_eq(view._chroma, 0.0, "overdrive starts with a shockwave, not a chromatic split")
	view._handle_event(SimConst.EventType.FAIL, -1, 0)
	assert_gt(view._chroma, 0.0, "the fail keeps its split")


func test_the_sky_turns_with_the_camera() -> void:
	var view: GameplayView = _view_for("w01_l20")
	view._update_frame(0.016)
	var mat: ShaderMaterial = view._sky_mat
	var tan_half: Vector2 = mat.get_shader_parameter("tan_half") as Vector2
	assert_gt(tan_half.y, 0.0, "the sky is laid out from the eye direction, not the screen")
	assert_near(tan_half.y, tan(deg_to_rad(view.camera_rig.camera.fov) * 0.5), 0.0001)
	var rest: Basis = mat.get_shader_parameter("rest_view") as Basis
	var forward: Vector3 = CameraRig.rest_basis() * Vector3.FORWARD
	assert_true((rest * forward).is_equal_approx(Vector3.FORWARD), "the rest view looks straight at the sink")


func test_a_passed_gate_arch_never_hides_the_core() -> void:
	assert_eq(EntityView.arch_sink(0.0), 0.0, "the arch stands while the core goes through")
	assert_eq(EntityView.arch_sink(EntityView.ARCH_SINK_TO), 1.0, "then it is gone into the floor")
	var sinking: float = _sightline_crossing(true)
	var standing: float = _sightline_crossing(false)
	assert_gt(standing, 1.0, "a standing arch's beam would sweep over the core for over a metre of travel")
	assert_lt(sinking, standing * 0.5, "sinking cuts that to a brief graze right behind the core")


## Metres of travel during which the arch's top beam overlaps the camera's line
## to the core (camera at rest, beam and core with their real sizes).
func _sightline_crossing(sinks: bool) -> float:
	var cam: Vector3 = CameraRig.BASE_OFFSET
	var core_y: float = SimConst.CORE_RADIUS
	var metres: float = 0.0
	for step: int in 81:
		var through: float = float(step) * 0.1
		var sink: float = EntityView.arch_sink(through) * EntityView.ARCH_SINK_DEPTH if sinks else 0.0
		var top: float = ViewKit.ARCH_HEIGHT + ViewKit.ARCH_POST * 0.5 - sink
		var sightline: float = core_y + (cam.y - core_y) * (through / cam.z)
		if top - ViewKit.ARCH_POST < sightline + SimConst.CORE_RADIUS and top > sightline - SimConst.CORE_RADIUS:
			metres += 0.1
	return metres


func test_quality_survives_a_world_change() -> void:
	# R-6: each world builds a new ViewKit; Low/Medium kept getting Voronoi glass.
	var view: GameplayView = _view_for("w01_l20")
	view.set_quality(false, 0.4, 12, false, false, false, false, false, false)
	view.apply_world(WorldTheme.from_world(_app.catalog.world("cloud_factory")))
	assert_eq(view.kit.glass_material.shader, ViewKit.GLASS_LITE_SHADER, "the new world keeps the analytic glass")
	assert_eq(float(view.kit.structure_material.get_shader_parameter("detail_strength")), 0.0, "and no relief")


func test_the_probe_mirrors_only_the_environment() -> void:
	# R-6: on High the probe painted hazard orange onto ice and crystal ribs.
	var view: GameplayView = _view_for("w07_l20")
	assert_eq(view._probe.cull_mask, ViewKit.ENVIRONMENT_LAYER)
	assert_eq(view.core_view.body.layers, ViewKit.GAMEPLAY_LAYER, "the core is not mirrored")
	assert_eq(view.trail.layers, ViewKit.GAMEPLAY_LAYER)
	var ent: EntityView = EntityView.new()
	assert_eq((ent.get_child(0) as MeshInstance3D).layers, ViewKit.GAMEPLAY_LAYER, "nor any hazard part")
	ent.free()


func test_reused_views_and_motes_start_clean() -> void:
	var view: GameplayView = _view_for("w09_l45")
	var lvl: SimLevel = _session.sim_level
	var well: int = -1
	for i: int in lvl.entity_count():
		if lvl.e_type[i] == SimConst.EntityType.GRAVITY:
			well = i
			break
	assert_gt(float(well), -1.0, "w09_l45 has a gravity well")
	var ent: EntityView = EntityView.new()
	ent.configure(well, SimConst.EntityType.GRAVITY, lvl, view.kit)
	ent.pool_reset()
	for part: Node in ent.get_children():
		var mi: MeshInstance3D = part as MeshInstance3D
		if mi != null:
			assert_eq(float(mi.get_instance_shader_parameter("tiles")), EntityView.CHEVRON_TILES, "no arrow count kept")
	ent.free()
	view.apply_world(WorldTheme.from_world(_app.catalog.world("crystal_valley")))
	assert_true(view._atmosphere.color_ramp != null)
	view.apply_world(WorldTheme.from_world(_app.catalog.world("desert_reactor")))
	assert_true(view._atmosphere.color_ramp == null, "sand does not twinkle after glitter")
	var orb: float = CoreView.form_top(view.core_view._meshes[SimConst.Form.HOP], SimConst.Form.HOP)
	var shard: float = CoreView.form_top(view.core_view._meshes[SimConst.Form.PHASE], SimConst.Form.PHASE)
	assert_gt(shard, orb, "plate discs sit higher on the tall phase shard")
