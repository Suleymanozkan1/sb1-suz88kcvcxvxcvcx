extends TestCase
## The player character (player feedback: "change the character completely",
## then "make the character more advanced"): a flux craft per form, lofted
## hulls with airfoil wings, a glass canopy over the core, detailed engines,
## skins on its energy parts, banking into lane changes, a barrel roll on a
## phase change, engine flames, sparks and wingtip vapour trails. And each
## world's sky scenery.

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
		assert_eq(mesh.get_surface_count(), 4, "hull, trim, energy and glass surfaces")
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
	var skin_hull: Color = core._hull_mat.get_shader_parameter("paint") as Color
	var skin_stripe: Color = core._hull_mat.get_shader_parameter("accent") as Color
	assert_true(skin_stripe.is_equal_approx(core.skin_color_a), "the stripe wears the skin")
	core.set_form(SimConst.Form.DASH, 0, false)
	assert_false((core._hull_mat.get_shader_parameter("paint") as Color).is_equal_approx(skin_hull), "dash tint")
	var stripe: Color = core._hull_mat.get_shader_parameter("accent") as Color
	assert_true(stripe.is_equal_approx(Palette.FORM_DASH), "and its stripe is the form colour")
	var flame: Color = core._flame_mat.get_shader_parameter("flame_color") as Color
	assert_true(flame.is_equal_approx(Palette.FORM_DASH), "flames burn in the form colour")
	core.set_form(SimConst.Form.HOP, 0, false)
	core.set_high_key(true)
	var dark: Color = core._hull_mat.get_shader_parameter("paint") as Color
	assert_lt(dark.get_luminance(), 0.4, "a dark hull on a light floor")


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


func test_the_hull_is_smooth_and_detailed() -> void:
	var mesh: ArrayMesh = CraftShapes.build(SimConst.Form.HOP)
	var arrays: Array = mesh.surface_get_arrays(CraftShapes.SURFACE_HULL)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var smooth: int = 0
	for t: int in range(0, normals.size() - 2, 3):
		if not normals[t].is_equal_approx(normals[t + 1]) or not normals[t].is_equal_approx(normals[t + 2]):
			smooth += 1
	assert_gt(float(smooth), 200.0, "the curved hull is smooth shaded, not faceted")
	var view: GameplayView = _view_for("w01_l20")
	var hull: ShaderMaterial = view.core_view._hull_mat
	assert_eq(hull.shader, CoreView.HULL_SHADER, "panel seams and stripes")
	view.set_quality(false, 0.4, 12, false, false, false, false, false, false)
	assert_eq(float(hull.get_shader_parameter("detail")), 0.0, "flat paint on Low")
	view.set_quality(true, 1.0, 28, true, true)
	assert_eq(float(hull.get_shader_parameter("detail")), 1.0)


func test_the_top_preset_adds_bloom_sun_scatter_and_crisp_shadows() -> void:
	var view: GameplayView = _view_for("w01_l20")
	view.set_quality_extras(true, 2)
	assert_gt(view.environment.get_glow_level(1), 0.0, "a wider bloom")
	assert_gt(view.environment.fog_sun_scatter, 0.0, "the fog catches the key light")
	assert_eq(view.key_light.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	view.set_quality_extras(false, 0)
	assert_eq(view.environment.get_glow_level(1), 0.0)
	assert_eq(view.environment.fog_sun_scatter, 0.0)
	assert_eq(view.key_light.directional_shadow_mode, DirectionalLight3D.SHADOW_ORTHOGONAL)


func test_the_core_glows_under_a_glass_canopy() -> void:
	var view: GameplayView = _view_for("w01_l20")
	var core: CoreView = view.core_view
	for form: int in FORMS:
		core.set_form(form, 0, false)
		var glass: Material = core.body.get_surface_override_material(CraftShapes.SURFACE_GLASS)
		assert_true(glass is ShaderMaterial, "form %d has its glass" % form)
		assert_eq((glass as ShaderMaterial).shader, CoreView.GLASS_SHADER)
		var mesh: ArrayMesh = core.body.mesh as ArrayMesh
		var glass_box: AABB = _surface_box(mesh, CraftShapes.SURFACE_GLASS)
		var energy_box: AABB = _surface_box(mesh, CraftShapes.SURFACE_ENERGY)
		assert_true(glass_box.intersects(energy_box), "form %d: the core sits under the glass" % form)
	view.set_quality(false, 0.4, 12, false, false, false, false, false, false)
	assert_eq(float(core._glass_mat.get_shader_parameter("detail")), 0.0, "plain glass on Low")


func test_engines_have_petals_turbines_and_a_glow() -> void:
	var per_nozzle: int = CraftShapes.NOZZLE_PETALS * 4 + CraftShapes.TURBINE_BLADES * 2
	for form: int in FORMS:
		var mesh: ArrayMesh = CraftShapes.build(form)
		var trim_tris: int = mesh.surface_get_array_len(CraftShapes.SURFACE_TRIM) / 3
		var nozzles: int = CraftShapes.engines(form).size()
		assert_ge(float(trim_tris), float(per_nozzle * nozzles), "form %d: petals and blades on every nozzle" % form)
		var tris: int = 0
		for s: int in mesh.get_surface_count():
			tris += mesh.surface_get_array_len(s) / 3
		assert_ge(float(tris), 1000.0, "form %d is detailed" % form)
		assert_le(float(tris), 6000.0, "form %d stays in a phone's budget" % form)


func test_wings_carry_an_airfoil() -> void:
	assert_eq(CraftShapes._naca(0.0), 0.0, "sharp at the leading edge")
	assert_near(CraftShapes._naca(0.3), 0.5, 0.01, "thickest near 30 % of the chord")
	assert_lt(CraftShapes._naca(1.0), 0.02, "thin at the trailing edge")
	for form: int in FORMS:
		var layout: Vector2 = CraftShapes.paint_layout(form)
		var tip: Vector3 = CraftShapes.wingtips(form)[1]
		assert_lt(layout.x, layout.y, "form %d: fuselage inside the span" % form)
		assert_le(tip.x * CoreView.CRAFT_SCALE, MAX_HALF_SPAN, "form %d: wingtip inside the lane" % form)


func test_vapour_trails_follow_the_wingtips_on_high() -> void:
	var view: GameplayView = _view_for("w01_l20")
	view.set_quality(true, 1.0, 28, true, true)
	assert_true(view.wing_trails.allowed, "High draws them")
	for _i: int in 3:
		view._update_frame(1.0 / 60.0)
	assert_true(view.wing_trails.visible)
	view.set_quality(true, 0.7, 20, true, false)
	assert_false(view.wing_trails.allowed, "Medium keeps the particle budget")
	view.set_quality(true, 1.0, 28, true, true)
	view.reduce_motion = true
	view._update_frame(1.0 / 60.0)
	assert_false(view.wing_trails.allowed, "reduce motion turns them off")


func _surface_box(mesh: ArrayMesh, surface: int) -> AABB:
	var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var box: AABB = AABB(verts[0], Vector3.ZERO)
	for v: Vector3 in verts:
		box = box.expand(v)
	return box
