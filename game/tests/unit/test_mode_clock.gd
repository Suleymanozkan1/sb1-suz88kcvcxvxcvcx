extends TestCase
## Mode speed is a game clock. Hard (x1.12) used to speed up only the core, so
## sliders and pulse gates (timed for Classic) met it in the wrong place: 49 of
## the first 104 levels could not be finished at all and an idle run died within
## about 1.5 s. Now the whole run plays faster in real time on the Classic
## simulation, so every level stays solvable and only reaction time shrinks.

const SLIDER_LEVELS: PackedStringArray = ["w01_l16", "w01_l27", "w01_l40", "w02_l34", "w02_l51"]

var _sessions: Array[GameplaySession] = []
var _audio: AudioService


func after_each() -> void:
	for s: GameplaySession in _sessions:
		if is_instance_valid(s):
			s.free()
	_sessions.clear()
	if _audio != null and is_instance_valid(_audio):
		_audio.free()
	_audio = null


func _session(level_id: String, mode_id: StringName) -> GameplaySession:
	var s: GameplaySession = GameplaySession.new()
	_sessions.append(s)
	var mods: Dictionary = ModeCatalog.load_default().sim_modifiers(mode_id)
	assert_true(s.load_level(LevelRepository.new().load_level(level_id), mods), "loaded %s" % level_id)
	return s


func _run_with(sim: FluxSim, taps: PackedInt32Array) -> int:
	var ti: int = 0
	while sim.is_running() and sim.tick < 60 * 200:
		var tap: bool = ti < taps.size() and sim.tick == taps[ti]
		if tap:
			ti += 1
		sim.step(tap)
	return sim.status


func test_hard_levels_keep_their_classic_solution() -> void:
	for id: String in SLIDER_LEVELS:
		var s: GameplaySession = _session(id, &"hard")
		assert_eq(s.sim.speed_scale, 1.0, "%s: the simulation is the Classic one" % id)
		assert_false(s.sim.shields_allowed, "Hard still has no shields")
		var taps: PackedInt32Array = RunController.solution_taps(s.level_data)
		assert_eq(_run_with(s.sim, taps), SimConst.Status.COMPLETED, "%s can be finished in Hard" % id)


func test_hard_plays_faster_in_real_time() -> void:
	var classic: GameplaySession = _session("w01_l16", &"classic")
	var hard: GameplaySession = _session("w01_l16", &"hard")
	var zen: GameplaySession = _session("w01_l16", &"zen")
	assert_near(hard.clock_scale, 1.12, 0.0001)
	assert_near(zen.clock_scale, 0.85, 0.0001)
	for s: GameplaySession in [classic, hard, zen]:
		s.begin(0.0)
		for _f: int in 60:
			s._process(1.0 / 60.0)
	assert_eq(classic.sim.tick, 60, "one real second is 60 ticks in Classic")
	assert_near(float(hard.sim.tick), 67.0, 1.0, "and about 67 in Hard")
	assert_near(float(zen.sim.tick), 51.0, 1.0, "and about 51 in Zen")


func test_out_of_range_clock_scales_are_bounded() -> void:
	assert_eq(GameplaySession.clock_scale_for({}), 1.0)
	assert_eq(GameplaySession.clock_scale_for({"speed_scale": 9.0}), GameplaySession.MAX_CLOCK_SCALE)
	assert_eq(GameplaySession.clock_scale_for({"speed_scale": 0.0}), GameplaySession.MIN_CLOCK_SCALE)
	assert_eq(GameplaySession.clock_scale_for({"speed_scale": NAN}), 1.0)


func test_the_music_follows_a_faster_clock() -> void:
	_audio = AudioService.new()
	tree.root.add_child(_audio)
	_audio.setup(SettingsService.new(PlayerProfile.new(), EventBus.new()), SoundBank.from_file())
	assert_true(_audio.play_music("neon_core"))
	var deck: AudioService.MusicDeck = _audio._decks[_audio._active_deck]
	_audio.sync_run(deck.loop_length * 0.3, true, 1.12)
	assert_near(deck.base.pitch_scale, 1.12, 0.0001, "the loop plays at the run's clock")
	assert_eq(deck.hi.pitch_scale, deck.base.pitch_scale, "stems stay together")


func test_the_server_replays_hard_runs_on_the_classic_simulation() -> void:
	var level: Dictionary = LevelRepository.new().load_level("w01_l16")
	var replay: RunReplay = RunReplay.new()
	replay.level_id = "w01_l16"
	replay.mode = &"hard"
	replay.tap_ticks = RunController.solution_taps(level)
	var sim: FluxSim = ReplayVerifier.new().simulate(level, replay, {"speed_scale": 1.12, "shields": false})
	assert_eq(sim.status, SimConst.Status.COMPLETED, "a Hard run verifies with the taps the player made")
