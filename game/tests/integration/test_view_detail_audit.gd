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
		assert_le(view._atmosphere.color.a, GameplayView.ATMOSPHERE_MAX_ALPHA + 0.0001, "≤ 8 % opacity")


func test_form_colour_wins_over_colour_overriding_skins() -> void:
	var view: GameplayView = _view_for("w04_l20")
	var core_mat: ShaderMaterial = view.core_view._mat
	view.core_view.set_form(SimConst.Form.HOP, 0, false)
	assert_eq(float(core_mat.get_shader_parameter("form_lock")), 0.0, "HOP shows the skin as bought")
	view.core_view.set_form(SimConst.Form.DASH, 0, false)
	assert_eq(float(core_mat.get_shader_parameter("form_lock")), 1.0, "DASH: the form colour wins")
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
