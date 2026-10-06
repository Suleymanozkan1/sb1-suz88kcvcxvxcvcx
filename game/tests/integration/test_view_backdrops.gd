extends TestCase
## Painted backdrops (player feedback: "still the same, make it a much better
## level"): every world's sky shows a painting of its far scenery, mapped over
## the band of sky the camera sees; a background cosmetic hides it. And the
## speed streaks that rush past the shaft on High and Ultra.

const FIXED_UNIX: int = 1790000000
## The camera shows about -10° to +21° of sky above the course: a backdrop must
## cover that band.
const VISIBLE_EL_LOW: float = deg_to_rad(-8.0)
const VISIBLE_EL_HIGH: float = deg_to_rad(21.0)
const VISIBLE_AZ_HALF: float = deg_to_rad(19.0)
## Nothing drawn over the course: the widest course (3 lanes) plus its runway
## lamps, below the top of a launch-pad flight.
const COURSE_HALF_WIDTH: float = 1.5 * SimConst.LANE_WIDTH + 0.3
const COURSE_CEILING: float = 2.4

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


func test_every_world_has_a_painting_covering_the_visible_sky() -> void:
	var images: Dictionary[String, bool] = {}
	for w: Dictionary in _app.catalog.worlds:
		var t: WorldTheme = WorldTheme.from_world(w)
		assert_false(t.backdrop.is_empty(), "%s has a painted backdrop" % w["id"])
		assert_true(ResourceLoader.exists(t.backdrop), "%s backdrop is imported" % w["id"])
		images[t.backdrop] = true
		assert_ge(t.backdrop_rect.x, VISIBLE_AZ_HALF, "%s covers the view's width" % w["id"])
		assert_le(t.backdrop_rect.y, VISIBLE_EL_LOW, "%s reaches down to the horizon" % w["id"])
		assert_ge(t.backdrop_rect.z, VISIBLE_EL_HIGH, "%s reaches the top of the view" % w["id"])
		assert_le(t.backdrop_gain, 1.0, "%s painting stays behind the course" % w["id"])
	assert_eq(images.size(), _app.catalog.worlds.size(), "a painting of its own for every world")


func test_a_missing_or_absent_painting_keeps_the_procedural_sky() -> void:
	var w: Dictionary = (_app.catalog.world("neon_core") as Dictionary).duplicate(true)
	var art: Dictionary = w["art"] as Dictionary
	var sky: Dictionary = art["sky"] as Dictionary
	sky["backdrop"] = {"image": "res://assets/backdrops/no_such_world.jpg"}
	assert_true(WorldTheme.from_world(w).backdrop.is_empty(), "a missing file falls back")
	sky.erase("backdrop")
	assert_true(WorldTheme.from_world(w).backdrop.is_empty(), "no entry, no painting")


func test_the_sky_shows_the_painting_until_a_background_cosmetic_replaces_it() -> void:
	var view: GameplayView = _view_for("w07_l20")
	var mat: ShaderMaterial = view._sky_mat
	assert_true(bool(mat.get_shader_parameter("backdrop_on")), "the painting is on")
	assert_true(mat.get_shader_parameter("backdrop") is Texture2D, "with its texture")
	assert_false(view._silhouette.visible, "the painting carries the far landmarks")
	var custom: Dictionary = {"use_world_palette": false, "sky_top": Color.BLACK, "sky_bottom": Color.NAVY_BLUE}
	view.apply_effect_cosmetics({}, {}, custom)
	assert_false(bool(mat.get_shader_parameter("backdrop_on")), "a background cosmetic replaces it")
	assert_true(view._silhouette.visible, "and the landmark silhouette returns")
	view.apply_effect_cosmetics({}, {}, {})
	assert_true(bool(mat.get_shader_parameter("backdrop_on")), "back to the world's own sky")


func test_streaks_never_cross_the_course() -> void:
	for p: Vector3 in SpeedStreaks.emission_layout():
		assert_true(
			absf(p.x) >= COURSE_HALF_WIDTH or p.y >= COURSE_CEILING, "streak start %s is off the course" % str(p)
		)
		assert_le(p.z, 0.0, "streaks start ahead")


func test_streaks_follow_speed_within_the_decoration_cap() -> void:
	var cruise: float = SpeedStreaks.alpha_for(10.0, 10.0)
	var dash: float = SpeedStreaks.alpha_for(15.0, 10.0)
	assert_eq(cruise, SpeedStreaks.CRUISE_ALPHA, "faint at the level's own speed")
	assert_gt(dash, cruise, "brighter on a dash")
	assert_le(SpeedStreaks.alpha_for(40.0, 10.0), AmbientMotes.MAX_ALPHA, "never above the 20 % cap")
	assert_eq(SpeedStreaks.alpha_for(5.0, 10.0), SpeedStreaks.CRUISE_ALPHA, "no darker when slower")


func test_streaks_only_on_high_and_not_with_reduce_motion() -> void:
	var view: GameplayView = _view_for("w01_l20")
	var sim: FluxSim = _session.sim
	view.set_quality(true, 1.0, 28, true, true)
	view.streaks.update_run(true, sim.speed, sim.level.base_speed)
	assert_true(view.streaks.emitting, "High streams them during a run")
	view.streaks.update_run(false, sim.speed, sim.level.base_speed)
	assert_false(view.streaks.emitting, "none once the run is over")
	view.set_quality(true, 0.7, 20, true, false)
	view.streaks.update_run(true, sim.speed, sim.level.base_speed)
	assert_false(view.streaks.emitting, "Medium keeps the particle budget")
	view.set_quality(true, 1.0, 28, true, true)
	view.reduce_motion = true
	view._update_frame(1.0 / 60.0)
	assert_false(view.streaks.emitting, "reduce motion turns them off")
