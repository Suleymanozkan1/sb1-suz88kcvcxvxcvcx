extends TestCase
## Early-game pacing. Player feedback: the game stayed too simple for too long
## (World 1 asked for a lane change every 3-5 s, some levels for one tap, and
## every level opened on 16 m of empty shaft). From the end of the short
## tutorial the shipped levels keep the player busy, the first decision still
## leaves time to read, World 1 brings its moving hazards in early, and the
## streamed modes keep the pace they are designed for.

## Fewest required taps per second any normal level of Worlds 1-3 may ask for
## after the tutorial (World 1 averaged 0.27 before the pacing pass).
const MIN_LEVEL_TAP_RATE: float = 0.3
const MIN_WORLD1_TAP_RATE: float = 0.6
const MIN_EARLY_WORLDS_TAP_RATE: float = 0.75
## The first hazard row reaches the core within this many seconds of GO (the
## old 16 m lead-in took over 3 s at World 1 speeds).
const MAX_FIRST_HAZARD_S: float = 2.8
const TUTORIAL_LEVELS: int = 3
const HAZARDS: PackedStringArray = ["barrier", "slider", "pulse_gate", "phase_gate", "breakable"]
const STREAM_SEEDS: Array[int] = [11, 222, 3333]
const STREAM_DISTANCE: float = 400.0


func _taps(level: Dictionary) -> int:
	return ((level["solution"] as Dictionary)["taps"] as Array).size()


func _tap_rate(level: Dictionary) -> float:
	return float(_taps(level)) / maxf(float(level["duration"]), 0.001)


func _first_hazard_d(level: Dictionary) -> float:
	var first: float = INF
	for e: Variant in level["entities"] as Array:
		if HAZARDS.has(str((e as Dictionary)["t"])):
			first = minf(first, float((e as Dictionary)["d"]))
	return first


func test_the_tutorial_is_short() -> void:
	var model: DifficultyModel = DifficultyModel.new()
	for n: int in range(1, TUTORIAL_LEVELS + 1):
		assert_true(model.build_spec(n).tutorial, "level %d teaches" % n)
	assert_false(model.build_spec(TUTORIAL_LEVELS + 1).tutorial, "level 4 plays for real")
	assert_eq(model.build_spec(TUTORIAL_LEVELS + 1).tier, "early")
	# Finishing the last tutorial level ends onboarding (ads gate).
	var repo: LevelRepository = LevelRepository.new()
	var last: Dictionary = repo.load_level(RunController.TUTORIAL_LAST_LEVEL)
	assert_eq(str(last["tier"]), "tutorial", "the onboarding end is a tutorial level")
	var after: Dictionary = repo.load_level(repo.next_level_id(RunController.TUTORIAL_LAST_LEVEL))
	assert_ne(str(after["tier"]), "tutorial", "and the last one")


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
			var first_s: float = _first_hazard_d(level) / float(level["speed"])
			assert_le(first_s, MAX_FIRST_HAZARD_S, "%s: first row after %.1f s" % [level["id"], first_s])
			(world1 if wi == 1 else later).append(rate)
	assert_ge(_mean(world1), MIN_WORLD1_TAP_RATE, "World 1 keeps the player busy")
	assert_ge(_mean(later), MIN_EARLY_WORLDS_TAP_RATE, "and Worlds 2-3 more so")


func test_the_first_decision_leaves_time_to_read() -> void:
	# Validator rule: no tap may be due before FIRST_DECISION_S after GO. A row
	# 12 m ahead at 20 m/s must be dodged within about half a second.
	var v: LevelValidator = LevelValidator.new()
	var rushed: LevelValidator.Report = LevelValidator.Report.new()
	v._check_windows(_one_row_level(20.0), rushed)
	assert_true(_mentions_first_tap(rushed), "a decision due at once is refused")
	var calm: LevelValidator.Report = LevelValidator.Report.new()
	v._check_windows(_one_row_level(6.0), calm)
	assert_false(_mentions_first_tap(calm), "two seconds of shaft is fine")


func test_tutorial_levels_still_teach_gently() -> void:
	var repo: LevelRepository = LevelRepository.new()
	var first_real: Dictionary = repo.load_level(WorldCatalog.level_id(1, TUTORIAL_LEVELS + 1))
	for local: int in range(1, TUTORIAL_LEVELS + 1):
		var level: Dictionary = repo.load_level(WorldCatalog.level_id(1, local))
		var taps: int = _taps(level)
		assert_ge(taps, 3, "%s has something to do" % level["id"])
		assert_le(taps, 6, "but not much")
		assert_lt(float(level["speed"]), float(first_real["speed"]), "and runs slower than level 4")
		assert_lt(float(level["duration"]), 10.0, "in under ten seconds")
	assert_true(bool(repo.load_level("w01_l01")["forgiving"]), "the first hit is forgiven early on")
	assert_false(bool(repo.load_level(WorldCatalog.level_id(1, TUTORIAL_LEVELS))["forgiving"]))


func test_every_introduction_level_shows_its_idea() -> void:
	# The HUD names the chapter's new idea on each introduction level: the
	# idea's entity must be in that very level (w01_l27 named the shield and
	# had none).
	var mechanics: Dictionary = JsonIO.read_dict(LevelValidator.MECHANICS_PATH)["mechanics"] as Dictionary
	var repo: LevelRepository = LevelRepository.new()
	var checked: int = 0
	for id: String in repo.all_level_ids():
		var level: Dictionary = repo.load_level(id)
		var intro: String = str(level.get("intro_mechanic", ""))
		var wanted: Array = (mechanics.get(intro, {}) as Dictionary).get("entities", []) as Array
		if wanted.is_empty():
			continue
		var found: bool = false
		for e: Variant in level["entities"] as Array:
			found = found or wanted.has((e as Dictionary)["t"])
		assert_true(found, "%s introduces %s" % [id, intro])
		checked += 1
	assert_gt(float(checked), 20.0, "introduction levels checked")


func test_world1_moves_early() -> void:
	# Sliders (moving hazards) arrive at L14, not L27; the shield follows at L27.
	var chapters: Array = WorldCatalog.load_default().world_at(1)["chapters"] as Array
	assert_eq(str((chapters[1] as Dictionary)["intro"]), "slider")
	assert_eq(str((chapters[2] as Dictionary)["intro"]), "shield")
	var repo: LevelRepository = LevelRepository.new()
	for local: int in range(14, 26):
		var sliders: int = 0
		for e: Variant in repo.load_level(WorldCatalog.level_id(1, local))["entities"] as Array:
			if str((e as Dictionary)["t"]) == "slider":
				sliders += 1
		assert_gt(float(sliders), 0.0, "w01_l%02d has sliders" % local)


func test_streamed_modes_keep_their_pace() -> void:
	# Pinned per mode in modes.json: Zen stays calm, the ranked streams busy.
	var zen: float = _stream_rate(&"zen")
	var endless: float = _stream_rate(&"endless")
	var time_attack: float = _stream_rate(&"time_attack")
	assert_le(zen, 0.5, "Zen is calm (%.2f taps/s)" % zen)
	assert_lt(zen, endless, "and calmer than Endless")
	assert_ge(endless, 0.55, "Endless keeps the player busy (%.2f taps/s)" % endless)
	assert_ge(time_attack, 0.45, "Time Attack too (%.2f taps/s)" % time_attack)


func _stream_rate(mode_id: StringName) -> float:
	var catalog: WorldCatalog = WorldCatalog.load_default()
	var model: DifficultyModel = DifficultyModel.new(catalog)
	var modes: ModeCatalog = ModeCatalog.load_default()
	var total: float = 0.0
	for s: int in STREAM_SEEDS:
		var streamer: EndlessStreamer = modes.make_streamer(mode_id, s, catalog, model)
		streamer.course_until(STREAM_DISTANCE)
		var horizon: float = STREAM_DISTANCE / streamer.spec.speed
		var n: int = 0
		for t: int in streamer.planned_taps():
			if float(t) * SimConst.DT <= horizon:
				n += 1
		total += float(n) / horizon
	return total / float(STREAM_SEEDS.size())


func _one_row_level(speed: float) -> Dictionary:
	return {
		"id": "pacing_probe",
		"tier": "early",
		"lanes": 2,
		"speed": speed,
		"length": 40.0,
		"start_form": "hop",
		"start_lane": 0,
		"start_phase": 0,
		"forgiving": false,
		"beat_seconds": 0.5,
		"modifiers": {"hop_time": SimConst.HOP_TIME, "speed_ramp": 0.0, "ramp_distance": 40.0},
		"objective": {"type": "reach_end", "target": 0},
		"entities": [{"t": "barrier", "d": 12.0, "lanes": [0]}],
		"solution": {"taps": [3]},
	}


func _mentions_first_tap(report: LevelValidator.Report) -> bool:
	for e: Dictionary in report.errors:
		if str(e["code"]) == "unfair_window" and str(e["message"]).contains("first tap"):
			return true
	return false


func _mean(values: Array[float]) -> float:
	var total: float = 0.0
	for v: float in values:
		total += v
	return total / float(maxi(values.size(), 1))
