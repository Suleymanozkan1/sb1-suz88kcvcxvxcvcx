extends TestCase
## World art in the gameplay view: environment palette caps, structure colours
## kept out of the gameplay roles, quality-driven reflections, shadows, surface
## relief, light shafts and side details.

const FIXED_UNIX: int = 1790000000

var _app: AppServices
var _session: GameplaySession
var _runs: RunController
var _last: RunResult
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
	_last = null
	_session.run_ended.connect(func(r: RunResult) -> void: _last = r)
	_nodes.clear()


func after_each() -> void:
	TranslationServer.set_locale("en")
	for n: Node in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_session.queue_free()
	_app.queue_free()
	await wait_frames(2)


func _keep(n: Node) -> Node:
	_nodes.append(n)
	tree.root.add_child(n)
	return n


func _view_for(level_id: String, world_id: String) -> GameplayView:
	var view: GameplayView = _keep(GameplayView.new()) as GameplayView
	assert_true(_runs.prepare(&"classic", level_id), "prepared %s" % level_id)
	view.bind(_session)
	view.apply_world(WorldTheme.from_world(_app.catalog.world(world_id)))
	view.setup_level()
	return view


func test_quality_presets_drive_reflections_shadows_and_relief() -> void:
	var presets: Dictionary = JsonIO.read_dict("res://data/quality/presets.json")["presets"] as Dictionary
	assert_true(bool((presets["medium"] as Dictionary)["shadows"]), "phones on auto (Medium) get shadows")
	assert_false(bool((presets["medium"] as Dictionary)["reflections"]), "reflection probes start at High")
	assert_true(bool((presets["high"] as Dictionary)["reflections"]))
	var view: GameplayView = _view_for("w07_l20", "frozen_pulse")
	view.set_quality(true, 1.0, 28, true, true, true, true, true)
	assert_true(view._probe.visible, "High: reflection probe on")
	assert_eq(view.kit.glass_material.shader, ViewKit.GLASS_SHADER, "High: fine Voronoi glass")
	assert_false(bool((presets["medium"] as Dictionary)["fine_glass"]), "Medium uses the analytic glass")
	assert_gt(float(view.kit.structure_material.get_shader_parameter("detail_strength")), 0.0, "surface relief on")
	view._update_frame(0.016)
	var first: Vector3 = view._probe.position
	view._update_frame(0.016)
	assert_eq(view._probe.position, first, "the probe does not move (re-capture) every frame")
	view.set_quality(false, 0.4, 12, false, false, false, false, false, false)
	assert_false(view._probe.visible, "Low: no probe")
	assert_eq(float(view.kit.structure_material.get_shader_parameter("detail_strength")), 0.0, "no relief")
	assert_false(view.key_light.shadow_enabled, "no shadows")
	assert_eq(view.kit.glass_material.shader, ViewKit.GLASS_LITE_SHADER, "Low: no per-fragment cell search")


func test_every_world_has_side_detail_and_shafts_where_light_is_open() -> void:
	var shafts: int = 0
	for w: Dictionary in _app.catalog.worlds:
		var t: WorldTheme = WorldTheme.from_world(w)
		assert_has(MeshFactory.DETAIL_KINDS, t.detail, "%s side detail" % str(w["id"]))
		assert_gt(MeshFactory.detail(t.detail).get_surface_count(), 0, "%s detail mesh builds" % t.detail)
		if t.shafts:
			shafts += 1
	assert_eq(shafts, 4, "four worlds with open light have shafts")
	var view: GameplayView = _view_for("w05_l20", "deep_ocean")
	view.set_quality(true, 1.0, 28, true, true, true, true, false)
	assert_true(view._shafts.visible, "Deep Ocean shows its shafts")
	assert_true(view._details.visible, "and its cables")
	assert_gt(view.theme.floor_gloss, 0.0, "and a polished floor")
	view.set_quality(true, 0.7, 20, true, true, true, false, false)
	assert_false(view._shafts.visible, "atmosphere off: no shafts")


func test_structure_never_wears_a_gameplay_role_colour() -> void:
	var roles: Array[Color] = [Palette.PRIMARY, Palette.SECONDARY, Palette.ACCENT, Palette.WARNING]
	for w: Dictionary in _app.catalog.worlds:
		var c: Color = WorldTheme.from_world(w).structure
		for role: Color in roles:
			var close: bool = WorldTheme.hue_distance(c.h, role.h) < WorldTheme.ROLE_HUE_GAP
			assert_true(not close or c.s <= WorldTheme.ROLE_SAFE_SATURATION + 0.001, "%s structure" % str(w["id"]))
	var orange: Color = WorldTheme.off_roles(Color("#c8702a"))
	assert_le(orange.s, WorldTheme.ROLE_SAFE_SATURATION + 0.001, "a WARNING-like structure is neutralised")


func test_environment_colours_stay_quiet_in_every_world() -> void:
	for w: Dictionary in _app.catalog.worlds:
		var t: WorldTheme = WorldTheme.from_world(w)
		for c: Color in [t.sky_top, t.sky_bottom, t.fog, t.floor_color, t.lane_color]:
			assert_le(c.s, WorldTheme.ENV_MAX_SATURATION + 0.001, "%s saturation" % str(w.get("id", "")))
			if not t.bright:
				assert_le(c.v, WorldTheme.ENV_MAX_VALUE + 0.001, "%s value" % str(w.get("id", "")))
