extends TestCase
## The player character (player feedback: "change the character completely"):
## a flux craft per form instead of a glowing ball, with skins on its energy
## parts, banking into lane changes, a barrel roll on a phase change, engine
## flames and sparks. And each world's sky scenery.

const FIXED_UNIX: int = 1790000000
## A craft's half span may reach at most this far from the lane centre: the
## nearest block in the next lane starts LANE_WIDTH - BLOCK_HALF_WIDTH away.
const MAX_HALF_SPAN: float = 0.6
const FORMS: Array[int] = [SimConst.Form.HOP, SimConst.Form.PHASE, SimConst.Form.DASH, SimConst.Form.SURGE]

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


func test_every_form_is_its_own_craft() -> void:
	var seen: Dictionary[ArrayMesh, bool] = {}
	for form: int in FORMS:
		var mesh: ArrayMesh = CraftShapes.build(form)
		seen[mesh] = true
		assert_eq(mesh.get_surface_count(), 3, "hull, trim and energy surfaces")
		var box: AABB = mesh.get_aabb()
		var half_span: float = maxf(absf(box.position.x), absf(box.end.x)) * CoreView.CRAFT_SCALE
		assert_le(half_span, MAX_HALF_SPAN, "form %d clears the next lane's blocks" % form)
		assert_false(CraftShapes.engines(form).is_empty(), "form %d has engines" % form)
		var flames: ArrayMesh = CraftShapes.flames(form)
		var cones: int = flames.surface_get_array_len(0) / (CraftShapes.FLAME_SIDES * 3)
		assert_eq(cones, CraftShapes.engines(form).size(), "one flame per engine")
	assert_eq(seen.size(), FORMS.size(), "four different crafts")
	var dart: AABB = CraftShapes.build(SimConst.Form.DASH).get_aabb()
	var glider: AABB = CraftShapes.build(SimConst.Form.HOP).get_aabb()
	assert_gt(dart.size.z, glider.size.z, "the dart is the long one")
	assert_lt(dart.size.x, glider.size.x, "and the narrow one")


func test_skins_and_forms_paint_the_craft() -> void:
	var view: GameplayView = _view_for("w01_l20")
	var core: CoreView = view.core_view
	core.set_form(SimConst.Form.HOP, 0, false)
	assert_eq(
		core.body.get_surface_override_material(CraftShapes.SURFACE_ENERGY), core._mat, "skins show on the energy"
	)
	var skin_hull: Color = core._hull_mat.albedo_color
	core.set_form(SimConst.Form.DASH, 0, false)
	assert_false(core._hull_mat.albedo_color.is_equal_approx(skin_hull), "the dash hull takes the form tint")
	var flame: Color = core._flame_mat.get_shader_parameter("flame_color") as Color
	assert_true(flame.is_equal_approx(Palette.FORM_DASH), "flames burn in the form colour")
	core.set_form(SimConst.Form.HOP, 0, false)
	core.set_high_key(true)
	assert_lt(core._hull_mat.albedo_color.get_luminance(), 0.4, "a dark hull on a light floor")


func test_the_craft_banks_and_rolls() -> void:
	var view: GameplayView = _view_for("w01_l20")
	var core: CoreView = view.core_view
	var sim: FluxSim = _session.sim
	core.position.x = 0.0
	core.update_visuals(1.0 / 60.0, sim)
	for _i: int in 6:
		core.position.x += 0.12
		core.update_visuals(1.0 / 60.0, sim)
	assert_lt(core.body.rotation.z, -0.2, "moving right banks the right wing down")
	assert_lt(core.body.rotation.y, 0.0, "and turns the nose right")
	for _j: int in 60:
		core.update_visuals(1.0 / 60.0, sim)
	assert_near(core.body.rotation.z, 0.0, 0.02, "level again once the lane change is over")
	core.phase_motion()
	core.update_visuals(CoreView.ROLL_TIME * 0.5, sim)
	assert_gt(absf(core.body.rotation.z), 0.5, "a phase change rolls the craft")
	core.update_visuals(CoreView.ROLL_TIME, sim)
	assert_near(core.body.rotation.z, 0.0, 0.05, "one full roll")
	core.reduce_motion = true
	core.phase_motion()
	core.update_visuals(CoreView.ROLL_TIME * 0.5, sim)
	assert_near(core.body.rotation.z, 0.0, 0.05, "reduce motion keeps it level")


func test_flames_and_sparks_follow_the_run() -> void:
	var view: GameplayView = _view_for("w01_l20")
	var core: CoreView = view.core_view
	var sim: FluxSim = _session.sim
	core.set_form(SimConst.Form.HOP, 0, false)
	core.update_visuals(1.0 / 60.0, sim)
	var hop_flame: float = float(core._flame_mat.get_shader_parameter("length"))
	core.set_form(SimConst.Form.DASH, 0, false)
	core.update_visuals(1.0 / 60.0, sim)
	assert_gt(float(core._flame_mat.get_shader_parameter("length")), hop_flame * 1.5, "the dash burns longer")
	view.set_quality(false, 0.0, 12, false, false, false, false, false, false)
	core.update_visuals(1.0 / 60.0, sim)
	assert_false(core.ions.emitting, "no sparks without particles")
	view.set_quality(true, 1.0, 18, true, true)
	core.update_visuals(1.0 / 60.0, sim)
	assert_true(core.ions.emitting)
	assert_eq(core.ions.amount, CoreView.ION_AMOUNT)


func test_every_world_has_its_own_sky_scenery() -> void:
	var lines: Dictionary[String, bool] = {}
	for w: Dictionary in _app.catalog.worlds:
		var t: WorldTheme = WorldTheme.from_world(w)
		assert_ne(t.skyline, "none", "%s has a skyline" % w["id"])
		lines[t.skyline] = true
		var extras: float = t.nebula + t.clouds + t.aurora + t.rays + t.stars
		assert_true(extras > 0.0 or t.body_kind != "none", "%s has something in its sky" % w["id"])
		for c: Color in [t.skyline_light, t.aurora_a, t.aurora_b]:
			assert_le(c.s, WorldTheme.SKY_LIGHT_MAX_SATURATION + 0.001, "%s sky lights stay soft" % w["id"])
		assert_le(t.skyline_color.s, WorldTheme.ENV_MAX_SATURATION + 0.001, "%s skyline is environment" % w["id"])
	assert_eq(lines.size(), WorldTheme.SKYLINES.size() - 1, "every world its own skyline")


func test_the_sky_material_carries_the_world_scenery() -> void:
	var view: GameplayView = _view_for("w08_l20")
	var mat: ShaderMaterial = view._sky_mat
	assert_eq(int(mat.get_shader_parameter("skyline")), WorldTheme.SKYLINES.find("dunes"))
	assert_eq(int(mat.get_shader_parameter("body_kind")), WorldTheme.BODY_KINDS.find("sun"))
	assert_gt(float(mat.get_shader_parameter("rays")), 0.0, "the desert sun throws rays")
	view.set_quality(false, 0.4, 12, false, false, false, false, false, false)
	assert_false(bool(mat.get_shader_parameter("detail")), "low quality drops the soft sky layers")
	view.apply_world(WorldTheme.from_world(_app.catalog.world("void_space")))
	assert_false(bool(view._sky_mat.get_shader_parameter("detail")), "and a new world keeps that")
	assert_eq(int(view._sky_mat.get_shader_parameter("body_kind")), WorldTheme.BODY_KINDS.find("ringed"))
