extends TestCase
## ProgressionService: XP curve, level-ups, grant caps and config validation.

var profile: PlayerProfile
var bus: EventBus
var catalog: WorldCatalog
var svc: ProgressionService
var xp_events: Array[Vector2i] = []
var level_ups: Array[int] = []


func before_each() -> void:
	profile = PlayerProfile.new()
	bus = EventBus.new()
	catalog = WorldCatalog.load_default()
	svc = ProgressionService.new(profile, bus, catalog)
	# Lambdas capture local arrays (shared by reference), never `self`, so the
	# bus does not keep this test case alive.
	var xp_sink: Array[Vector2i] = []
	var level_sink: Array[int] = []
	xp_events = xp_sink
	level_ups = level_sink
	bus.xp_gained.connect(func(amount: int, total: int) -> void: xp_sink.append(Vector2i(amount, total)))
	bus.player_level_up.connect(func(level: int) -> void: level_sink.append(level))


func test_config_file_is_valid() -> void:
	var cfg: Dictionary = ProgressionService.load_config()
	assert_false(cfg.is_empty(), "progression.json loads")
	assert_eq(int(cfg.get("schema_version", 0)), 1)
	for key: String in ["xp_curve", "xp_caps", "unlock_rules", "record_modes", "stats"]:
		assert_has(cfg, key, "config has %s" % key)
	assert_near(svc.xp_base, 120.0, 0.001, "base read from data")
	assert_near(svc.xp_exponent, 1.25, 0.001, "exponent read from data")
	assert_eq(svc.max_player_level, 100)
	assert_eq(svc.max_xp_grant, 5000)


func test_xp_curve_matches_formula() -> void:
	assert_eq(svc.xp_for_next(1), 120, "120 * 1^1.25")
	assert_eq(svc.xp_for_next(2), 285, "120 * 2^1.25 = 285.4 rounded to step 5")
	assert_eq(svc.xp_for_next(10), 2135)
	assert_eq(svc.xp_for_next(0), 120, "levels below 1 clamp to level 1")
	assert_eq(svc.xp_for_next(-4), 120)


func test_xp_curve_monotonic() -> void:
	var prev: int = 0
	for level: int in range(1, svc.max_player_level + 25):
		var need: int = svc.xp_for_next(level)
		assert_gt(need, prev, "xp_for_next(%d) strictly increasing" % level)
		prev = need


func test_flat_config_curve_still_strictly_increasing() -> void:
	var cfg: Dictionary = {"xp_curve": {"base": 100, "exponent": 0.5, "step": 50}, "xp_caps": {"max_player_level": 30}}
	var flat: ProgressionService = ProgressionService.new(PlayerProfile.new(), EventBus.new(), catalog, cfg)
	var prev: int = 0
	for level: int in range(1, 40):
		var need: int = flat.xp_for_next(level)
		assert_gt(need, prev, "level %d" % level)
		prev = need


func test_custom_linear_curve() -> void:
	var cfg: Dictionary = {"xp_curve": {"base": 100, "exponent": 1.0, "step": 1}}
	var linear: ProgressionService = ProgressionService.new(PlayerProfile.new(), EventBus.new(), catalog, cfg)
	for level: int in [1, 2, 7, 50]:
		assert_eq(linear.xp_for_next(level), 100 * level)


func test_multi_level_up_from_one_big_grant() -> void:
	var need: int = svc.xp_for_next(1) + svc.xp_for_next(2) + svc.xp_for_next(3)
	var gained: int = svc.add_xp(need + 20)
	assert_eq(gained, 3, "three levels from one grant")
	assert_eq(profile.player_level, 4)
	assert_eq(profile.xp, need + 20, "xp is lifetime total")
	assert_eq(xp_events.size(), 1, "xp_gained emitted once")
	assert_eq(xp_events[0], Vector2i(need + 20, need + 20))
	assert_eq(level_ups.size(), 3, "player_level_up per level")
	assert_eq(level_ups[0], 2)
	assert_eq(level_ups[1], 3)
	assert_eq(level_ups[2], 4)
	var bar: Dictionary = svc.xp_progress()
	assert_eq(int(bar["level"]), 4)
	assert_eq(int(bar["into_level"]), 20)
	assert_eq(int(bar["needed"]), svc.xp_for_next(4))
	assert_false(bool(bar["at_max"]))


func test_partial_progress_and_exact_threshold() -> void:
	assert_eq(svc.add_xp(100), 0)
	assert_eq(profile.player_level, 1)
	assert_eq(int(svc.xp_progress()["into_level"]), 100)
	assert_eq(svc.add_xp(20), 1, "exactly reaching the threshold levels up")
	assert_eq(profile.player_level, 2)
	assert_eq(int(svc.xp_progress()["into_level"]), 0)
	assert_eq(xp_events.size(), 2)
	assert_eq(xp_events[1], Vector2i(20, 120))


func test_invalid_grants_ignored() -> void:
	assert_eq(svc.add_xp(0), 0)
	assert_eq(svc.add_xp(-50), 0)
	assert_eq(profile.xp, 0)
	assert_empty(xp_events, "no signal for ignored grants")
	assert_empty(level_ups)


func test_single_grant_is_capped() -> void:
	svc.add_xp(10_000_000)
	assert_eq(profile.xp, svc.max_xp_grant, "implausible grant clamped to the cap")
	assert_eq(xp_events[0].x, svc.max_xp_grant)


func test_max_player_level_cap() -> void:
	var cfg: Dictionary = ProgressionService.load_config()
	cfg["xp_caps"] = {"max_player_level": 5, "max_single_grant": 100000, "max_total_xp": 1000000}
	var p: PlayerProfile = PlayerProfile.new()
	var capped: ProgressionService = ProgressionService.new(p, bus, catalog, cfg)
	assert_eq(capped.add_xp(100000), 4, "levels 2..5")
	assert_eq(p.player_level, 5)
	var bar: Dictionary = capped.xp_progress()
	assert_true(bool(bar["at_max"]))
	assert_eq(int(bar["into_level"]), int(bar["needed"]), "full bar at max")
	assert_eq(capped.add_xp(5000), 0, "no levels past the cap")
	assert_eq(p.player_level, 5)
	assert_eq(p.xp, 105000, "xp keeps accumulating at max level")


func test_lagging_level_catches_up() -> void:
	profile.xp = 1000
	assert_eq(svc.add_xp(1), 3, "1001 xp -> level 4 (thresholds 120 / 405 / 880 / 1560)")
	assert_eq(profile.player_level, 4)


func test_invalid_config_falls_back_to_defaults() -> void:
	var cfg: Dictionary = {
		"xp_curve": {"base": "lots", "exponent": 99, "step": -1},
		"xp_caps": "nope",
		"record_modes": 5,
		"stats": {"fast_clear_ratio": "fast"},
	}
	var safe: ProgressionService = ProgressionService.new(PlayerProfile.new(), EventBus.new(), catalog, cfg)
	assert_near(safe.xp_base, ProgressionService.DEFAULT_XP_BASE, 0.001)
	assert_near(safe.xp_exponent, ProgressionService.DEFAULT_XP_EXPONENT, 0.001)
	assert_eq(safe.xp_step, ProgressionService.DEFAULT_XP_STEP)
	assert_eq(safe.max_player_level, ProgressionService.DEFAULT_MAX_PLAYER_LEVEL)
	assert_eq(safe.xp_for_next(1), 120)
	assert_true(safe.record_modes.has("classic"), "default record modes")


func test_missing_dependencies_do_not_crash() -> void:
	var lonely: ProgressionService = ProgressionService.new(null, null, catalog, {"xp_curve": {}})
	assert_eq(lonely.add_xp(500), 2, "works without a bus")
	assert_true(lonely.is_level_unlocked("w01_l01"))
