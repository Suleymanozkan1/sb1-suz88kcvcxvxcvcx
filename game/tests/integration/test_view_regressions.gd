extends TestCase
## Regression tests for the integrated review (R-INT) findings in the gameplay
## view: revive visuals, currents, magnet, colour-blind markers, quality and
## reduced-motion wiring, budgets.

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


# --- Gameplay view ---------------------------------------------------------------


func test_revive_brings_the_core_back_and_removes_the_barrier() -> void:
	var view: GameplayView = _view_for("w01_l05", "neon_core")
	_session.begin(0.0)
	_session.step_ticks(60 * 120)
	assert_true(_last != null and _last.fail_reason == SimConst.FailReason.COLLISION, "failed on a barrier")
	await wait_frames(2)
	var killer: int = _session.sim.fail_entity
	view.core_view.implode()
	assert_true(view._active.has(killer), "the barrier is drawn")
	assert_true(_session.revive())
	view.on_revive()
	assert_true(view.core_view.visible, "core visible again")
	assert_lt(view.core_view._implode, 0.0, "implosion cancelled")
	assert_false(view._active.has(killer), "the barrier that was hit is gone")


func test_leftward_current_is_drawn_over_its_own_lanes() -> void:
	_view_for("w03_l14", "molten_grid")
	var lvl: SimLevel = _session.sim_level
	var kit: ViewKit = ViewKit.new(WorldTheme.from_world(_app.catalog.world("molten_grid")))
	var checked: int = 0
	for i: int in lvl.entity_count():
		if lvl.e_type[i] != SimConst.EntityType.CURRENT:
			continue
		var from_l: int = 0
		for l: int in lvl.lane_count:
			if (lvl.e_mask[i] & (1 << l)) != 0:
				from_l = l
		var to_l: int = int(lvl.e_p0[i])
		var ev: EntityView = _keep(EntityView.new()) as EntityView
		ev.configure(i, lvl.e_type[i], lvl, kit)
		var part: MeshInstance3D = ev._parts[0]
		var centre: Vector3 = part.transform * (part.mesh as QuadMesh).center_offset
		var expected: float = (SimConst.lane_x(from_l, lvl.lane_count) + SimConst.lane_x(to_l, lvl.lane_count)) * 0.5
		assert_near(centre.x, expected, 0.001, "current %d (%d->%d)" % [i, from_l, to_l])
		checked += 1
	assert_gt(float(checked), 2.0, "level has currents both ways")


func test_magnet_pulls_only_sparks_it_will_collect() -> void:
	_view_for("w01_l10", "neon_core")
	var lvl: SimLevel = _session.sim_level
	var field: SparkField = _keep(SparkField.new()) as SparkField
	field.build(lvl)
	var spark: int = -1
	for i: int in lvl.entity_count():
		if lvl.e_type[i] == SimConst.EntityType.SPARK and lvl.e_color[i] < 0:
			spark = i
			break
	assert_ge(float(spark), 0.0, "level has a neutral spark")
	# (MultiMesh transforms cannot be read back headless; the field's record of
	# displaced sparks is checked instead.)
	var base: Vector3 = field.position_of(spark)
	var far: Vector3 = Vector3(base.x + SimConst.MAGNET_COLLECT_RADIUS + 0.5, base.y, base.z + 1.0)
	field.apply_magnet(far, lvl, 0, true, 0)
	assert_false(field._pulled.has(spark), "out of reach: not pulled")
	var near: Vector3 = Vector3(base.x, base.y, base.z + 1.0)
	field.apply_magnet(near, lvl, 0, true, 0)
	assert_true(field._pulled.has(spark), "in reach: pulled")
	field.apply_magnet(near, lvl, 0, false, 0)
	assert_true(field._pulled.is_empty(), "back in lane after the pull")
	var coloured: int = -1
	for i: int in lvl.entity_count():
		if lvl.e_type[i] == SimConst.EntityType.SPARK and lvl.e_color[i] >= 0:
			coloured = i
			break
	if coloured >= 0:
		var cbase: Vector3 = field.position_of(coloured)
		field.apply_magnet(Vector3(cbase.x, cbase.y, cbase.z + 1.0), lvl, 0, true, 1 - lvl.e_color[coloured])
		assert_false(field._pulled.has(coloured), "wrong phase: not pulled")


func test_collected_sparks_pop_then_vanish() -> void:
	_view_for("w01_l10", "neon_core")
	var lvl: SimLevel = _session.sim_level
	var field: SparkField = _keep(SparkField.new()) as SparkField
	field.build(lvl)
	field.set_process(false)
	var spark: int = -1
	for i: int in lvl.entity_count():
		if lvl.e_type[i] == SimConst.EntityType.SPARK:
			spark = i
			break
	assert_ge(float(spark), 0.0, "level has a spark")
	assert_near(SparkField.pop_scale(0.0), 1.0, 0.001, "pop starts at full size")
	var peak: float = SparkField.pop_scale(SparkField.POP_TIME * SparkField.POP_PEAK_AT)
	assert_near(peak, SparkField.POP_PEAK_SCALE, 0.001, "pop peaks at 1.25")
	assert_near(SparkField.pop_scale(SparkField.POP_TIME), 0.0, 0.001, "pop ends at zero")
	field.hide_entity(spark)
	assert_eq(field.popping_count(), 1, "collect starts a pop")
	assert_true(field.hidden_entities().has(spark), "collected at once for the run")
	field.advance_pops(SparkField.POP_TIME * 0.5)
	assert_eq(field.popping_count(), 1, "pop still playing mid-way")
	field.advance_pops(SparkField.POP_TIME)
	assert_eq(field.popping_count(), 0, "pop over after 120 ms")
	field.hide_entity(spark)
	assert_eq(field.popping_count(), 0, "a hidden spark does not pop twice")
	var other: int = -1
	for i: int in range(spark + 1, lvl.entity_count()):
		if lvl.e_type[i] == SimConst.EntityType.SPARK:
			other = i
			break
	field.hide_entity(other, false)
	assert_eq(field.popping_count(), 0, "rebuild re-hides without a pop")


func test_colorblind_marks_phase_gates_by_shape() -> void:
	_view_for("w02_l01", "crystal_valley")
	var lvl: SimLevel = _session.sim_level
	var kit: ViewKit = ViewKit.new(WorldTheme.from_world(_app.catalog.world("crystal_valley")))
	var gate: int = -1
	for i: int in lvl.entity_count():
		if lvl.e_type[i] == SimConst.EntityType.PHASE_GATE:
			gate = i
			break
	assert_ge(float(gate), 0.0, "level has a phase gate")
	var ev: EntityView = _keep(EntityView.new()) as EntityView
	ev.configure(gate, lvl.e_type[gate], lvl, kit)
	assert_false(ev._parts[2].visible, "no marker by default")
	kit.colorblind = true
	ev.configure(gate, lvl.e_type[gate], lvl, kit)
	assert_true(ev._parts[2].visible, "shape marker shown")
	assert_eq(ev._parts[2].mesh, kit.phase_marker_mesh(lvl.e_color[gate]))
	assert_ne(kit.phase_marker_mesh(0), kit.phase_marker_mesh(1), "phases differ by shape")


func test_quality_flags_survive_world_changes() -> void:
	var view: GameplayView = _view_for("w01_l01", "neon_core")
	view.set_quality(false, 0.4, 8, false, false, false, false)
	assert_false(view.environment.glow_enabled, "glow off on low")
	assert_false(view._atmosphere.emitting, "ambient particles off")
	view.apply_world(WorldTheme.from_world(_app.catalog.world("molten_grid")))
	assert_false(view.environment.glow_enabled, "still off after a world change")
	assert_false(view._atmosphere.emitting, "still off after a world change")


func test_reduce_motion_scales_camera_motion() -> void:
	var view: GameplayView = _view_for("w01_l01", "neon_core")
	view.reduce_motion = true
	assert_near(view.camera_rig.shake_scale, GameplayView.REDUCED_CAMERA_MOTION, 0.0001)
	view.reduce_motion = false
	assert_near(view.camera_rig.shake_scale, 1.0, 0.0001)


func test_silhouette_roll_does_not_leak_between_worlds() -> void:
	var view: GameplayView = _view_for("w01_l01", "neon_core")
	_session.begin(0.0)
	for _i: int in 20:
		view._update_frame(0.5)
	assert_ne(view._silhouette.transform.basis, Basis.IDENTITY, "turbine turned")
	view.apply_world(WorldTheme.from_world(_app.catalog.world("crystal_valley")))
	assert_eq(view._silhouette.transform.basis, Basis.IDENTITY, "next world's silhouette upright")


func test_atmosphere_and_bursts_stay_within_budget() -> void:
	var view: GameplayView = _view_for("w01_l01", "neon_core")
	for id: String in ["neon_core", "molten_grid", "frozen_pulse", "void_space", "candy_reactor", "cloud_factory"]:
		view.apply_world(WorldTheme.from_world(_app.catalog.world(id)))
		assert_le(view._atmosphere.color.a, GameplayView.ATMOSPHERE_MAX_ALPHA + 0.0001, "%s motes" % id)
	view.bursts.set_amount_scale(1.25)
	for name: String in view.bursts._pools:
		for p: CPUParticles3D in view.bursts._pools[name] as Array[CPUParticles3D]:
			assert_le(float(p.amount), float(int((BurstPool.PRESETS[name] as Dictionary)["amount"])), name)


func test_auto_quality_step_reaches_the_viewport() -> void:
	_app.quality.set_preset(&"low")
	_app.bus.quality_changed.emit(&"low", true)
	var expected: float = float(_app.quality.params()["render_scale"])
	assert_near(_app.get_viewport().scaling_3d_scale, expected, 0.0001, "render scale applied")


func test_particle_effect_and_background_cosmetics_change_the_view() -> void:
	var view: GameplayView = _view_for("w01_l01", "neon_core")
	var c: CosmeticService = _app.cosmetics
	view.apply_effect_cosmetics(
		c.particle_params("particle_embers"), c.effect_params("fx_void"), c.background_params("bg_dusk")
	)
	var sky: Color = view._sky_mat.get_shader_parameter("sky_top") as Color
	assert_eq(sky, c.background_params("bg_dusk")["sky_top"] as Color, "the sky follows the background item")
	view.apply_world(WorldTheme.from_world(_app.catalog.world("molten_grid")))
	assert_eq(view._sky_mat.get_shader_parameter("sky_top") as Color, sky, "and survives a world change")
	var collect: CPUParticles3D = (view.bursts._pools["collect"] as Array[CPUParticles3D])[0]
	assert_near(collect.scale_amount_max, float(c.particle_params("particle_embers")["size_mult"]), 0.001)
	var ember: Color = (c.particle_params("particle_embers")["colors"] as Array)[0] as Color
	assert_eq(view._particle_color(0, Palette.PRIMARY), ember, "neutral spark bursts use the particle colours")
	assert_eq(view._effect_color("fail_color", Palette.FAILURE), c.effect_params("fx_void")["fail_color"] as Color)
	view._shock = 0.0
	view.shockwave(0.5)
	assert_near(view._shock, 0.5 * float(c.effect_params("fx_void")["shockwave"]), 0.001, "shockwave strength")
	view.apply_effect_cosmetics({}, {}, {})
	view.apply_world(WorldTheme.from_world(_app.catalog.world("neon_core")))
	assert_eq(view._sky_mat.get_shader_parameter("sky_top") as Color, view.theme.sky_top, "default: world sky")
	assert_eq(view._particle_color(0, Palette.PRIMARY), Palette.PRIMARY, "default: palette roles")


func test_environment_colours_stay_quiet_in_every_world() -> void:
	for w: Dictionary in _app.catalog.worlds:
		var t: WorldTheme = WorldTheme.from_world(w)
		for c: Color in [t.sky_top, t.sky_bottom, t.fog, t.floor_color, t.lane_color]:
			assert_le(c.s, WorldTheme.ENV_MAX_SATURATION + 0.001, "%s saturation" % str(w.get("id", "")))
			if not t.bright:
				assert_le(c.v, WorldTheme.ENV_MAX_VALUE + 0.001, "%s value" % str(w.get("id", "")))
