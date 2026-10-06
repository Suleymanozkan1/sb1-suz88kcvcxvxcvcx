extends TestCase
## Obstacle variety (player feedback: "every obstacle is an orange box"). Each
## world builds its lane blockers in its own shape family and body material,
## rows mix shapes, and one cue stays the same everywhere: a warm warning light,
## kept in the danger band and away from every gameplay role colour.

const DANGER_HUE_MAX: float = 20.0 / 360.0
const BODY_SAFE_SATURATION: float = 0.35
const MAX_WIDTH: float = SimConst.BLOCK_HALF_WIDTH * 2.0 + 0.005
const MAX_DEPTH: float = 0.62
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


func _roles() -> Array[Color]:
	return [Palette.PRIMARY, Palette.SECONDARY, Palette.ACCENT, Palette.SUCCESS, Palette.FORM_SURGE_HEAVY]


func test_worlds_build_their_obstacles_differently() -> void:
	var styles: Dictionary[String, bool] = {}
	for w: Dictionary in _app.catalog.worlds:
		var t: WorldTheme = WorldTheme.from_world(w)
		assert_has(HazardShapes.STYLES, t.hazard_style, "%s names a known style" % w["id"])
		styles[t.hazard_style] = true
	assert_ge(float(styles.size()), 8.0, "at least eight different obstacle families across the ten worlds")


func test_the_warning_light_is_always_a_danger_colour() -> void:
	for w: Dictionary in _app.catalog.worlds:
		var t: WorldTheme = WorldTheme.from_world(w)
		var warn: Color = t.hazard_warn
		var hue_ok: bool = warn.h <= DANGER_HUE_MAX or warn.h >= 1.0 - 0.01
		assert_true(hue_ok and warn.s > 0.6, "%s warning light is red to orange-red" % w["id"])
		for role: Color in _roles():
			assert_ge(WorldTheme.hue_distance(warn.h, role.h), WorldTheme.ROLE_HUE_GAP, "%s warn vs role" % w["id"])
		var body: Color = t.hazard_body
		for role2: Color in _roles():
			var close: bool = WorldTheme.hue_distance(body.h, role2.h) < WorldTheme.ROLE_HUE_GAP
			assert_true(not close or body.s <= BODY_SAFE_SATURATION, "%s body never looks like a role" % w["id"])


func test_every_shape_fits_its_lane() -> void:
	for style: String in HazardShapes.STYLES:
		for mesh: ArrayMesh in HazardShapes.barriers(style):
			var box: AABB = mesh.get_aabb()
			assert_le(box.size.x, MAX_WIDTH, "%s is no wider than a lane block" % style)
			assert_le(box.size.z, MAX_DEPTH, "%s is not much deeper than the hazard" % style)
			assert_near(box.position.y, -HazardShapes.HALF_H, 0.02, "%s stands on the floor" % style)
			assert_gt(box.size.y, 0.75, "%s is tall enough to read as blocking" % style)
			var lit: bool = HazardShapes.LIT_STYLES.has(style)
			assert_eq(mesh.get_surface_count(), 2 if lit else 1, "%s: warning light surface" % style)


func test_a_world_dresses_its_shapes_and_mixes_them() -> void:
	var kit: ViewKit = ViewKit.new(WorldTheme.from_world(_app.catalog.world("molten_grid")))
	assert_eq(kit.barrier_meshes.size(), HazardShapes.VARIANTS_PER_STYLE)
	var body: ShaderMaterial = kit.barrier_meshes[0].surface_get_material(0) as ShaderMaterial
	assert_eq(body.shader, ViewKit.HAZARD_SHADER)
	assert_eq(int(body.get_shader_parameter("pattern")), HazardShapes.PATTERNS["basalt"], "lava rock pattern")
	var used: Dictionary[ArrayMesh, bool] = {}
	for index: int in 12:
		for lane: int in 2:
			used[kit.barrier_mesh(index, lane)] = true
	assert_eq(used.size(), HazardShapes.VARIANTS_PER_STYLE, "rows use every shape of the world")
	var lit_kit: ViewKit = ViewKit.new(WorldTheme.from_world(_app.catalog.world("deep_ocean")))
	var light: StandardMaterial3D = lit_kit.barrier_meshes[0].surface_get_material(1) as StandardMaterial3D
	assert_true(light.emission_enabled, "the warning light glows")
	assert_true(light.emission.is_equal_approx(lit_kit.theme.hazard_warn))


func test_a_barrier_view_wears_its_world_shape() -> void:
	var view: GameplayView = GameplayView.new()
	_nodes.append(view)
	tree.root.add_child(view)
	assert_true(_runs.prepare(&"classic", "w03_l20"))
	view.bind(_session)
	view.apply_world(WorldTheme.from_world(_app.catalog.world("molten_grid")))
	view.setup_level()
	var lvl: SimLevel = _session.sim_level
	var barrier: int = -1
	for i: int in lvl.entity_count():
		if lvl.e_type[i] == SimConst.EntityType.BARRIER:
			barrier = i
			break
	assert_gt(float(barrier), -1.0, "w03_l20 has a barrier")
	var ent: EntityView = EntityView.new()
	ent.configure(barrier, SimConst.EntityType.BARRIER, lvl, view.kit)
	var part: MeshInstance3D = ent.get_child(0) as MeshInstance3D
	assert_true(view.kit.barrier_meshes.has(part.mesh), "the part is one of the world's shapes")
	assert_true(part.material_override == null, "materials come from the shape's surfaces")
	ent.free()
