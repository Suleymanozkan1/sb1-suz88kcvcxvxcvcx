extends TestCase
## Early-game pacing. Player feedback: the game stayed too simple for too long
## (World 1 asked for a lane change every 3-5 s, some levels for one tap). From
## the end of the short tutorial the shipped levels keep the player busy, and
## World 1 brings its moving hazards in early.

## Fewest required taps per second any normal level may ask for after the tutorial.
const MIN_LEVEL_TAP_RATE: float = 0.25
## World 1's average after the tutorial (it was 0.27 before the pacing pass).
const MIN_WORLD1_TAP_RATE: float = 0.5
## Worlds 2-3 average.
const MIN_EARLY_WORLDS_TAP_RATE: float = 0.65
const TUTORIAL_LEVELS: int = 3


func _tap_rate(level: Dictionary) -> float:
	var taps: int = ((level["solution"] as Dictionary)["taps"] as Array).size()
	return float(taps) / maxf(float(level["duration"]), 0.001)


func test_the_tutorial_is_short() -> void:
	var model: DifficultyModel = DifficultyModel.new()
	for n: int in range(1, TUTORIAL_LEVELS + 1):
		assert_true(model.build_spec(n).tutorial, "level %d teaches" % n)
	assert_false(model.build_spec(TUTORIAL_LEVELS + 1).tutorial, "level 4 plays for real")
	assert_eq(model.build_spec(TUTORIAL_LEVELS + 1).tier, "early")


func test_no_slack_levels_in_the_first_three_worlds() -> void:
	var repo: LevelRepository = LevelRepository.new()
	var world1: Array[float] = []
	var later: Array[float] = []
	for wi: int in range(1, 4):
		for local: int in range(1, 52):
			if (wi == 1 and local <= TUTORIAL_LEVELS) or local == 26:
				continue
			var level: Dictionary = repo.load_level(WorldCatalog.level_id(wi, local))
			var rate: float = _tap_rate(level)
			assert_ge(rate, MIN_LEVEL_TAP_RATE, "%s asks for %.2f taps/s" % [level["id"], rate])
			(world1 if wi == 1 else later).append(rate)
	assert_ge(_mean(world1), MIN_WORLD1_TAP_RATE, "World 1 keeps the player busy")
	assert_ge(_mean(later), MIN_EARLY_WORLDS_TAP_RATE, "and Worlds 2-3 more so")


func test_tutorial_levels_still_teach_gently() -> void:
	var repo: LevelRepository = LevelRepository.new()
	for local: int in range(1, TUTORIAL_LEVELS + 1):
		var level: Dictionary = repo.load_level(WorldCatalog.level_id(1, local))
		var taps: int = ((level["solution"] as Dictionary)["taps"] as Array).size()
		assert_ge(taps, 3, "%s has something to do" % level["id"])
		assert_ge(float(level["min_tap_window"]), 0.42, "with the tutorial's wide tap window")


func test_world1_moves_early() -> void:
	# Sliders (moving hazards) arrive at L14, not L27; the shield follows at L27.
	var catalog: WorldCatalog = WorldCatalog.load_default()
	var chapters: Array = catalog.world_at(1)["chapters"] as Array
	assert_eq(str((chapters[1] as Dictionary)["intro"]), "slider")
	assert_eq(str((chapters[2] as Dictionary)["intro"]), "shield")
	var repo: LevelRepository = LevelRepository.new()
	var sliders: int = 0
	for local: int in range(14, 26):
		for e: Variant in repo.load_level(WorldCatalog.level_id(1, local))["entities"] as Array:
			if str((e as Dictionary)["t"]) == "slider":
				sliders += 1
	assert_gt(float(sliders), 12.0, "L14-25 teach sliders")


func _mean(values: Array[float]) -> float:
	var total: float = 0.0
	for v: float in values:
		total += v
	return total / float(maxi(values.size(), 1))
