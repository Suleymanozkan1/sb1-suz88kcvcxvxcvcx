extends TestCase
## REQ-224: the music loop is locked to the run's simulation clock. Pure maths
## ([MusicClock]) and the AudioService lock (hold, seek, rate nudge, release).

var _audio: AudioService


func after_each() -> void:
	if _audio != null and is_instance_valid(_audio):
		_audio.free()
	_audio = null


func _spawn_audio() -> AudioService:
	_audio = AudioService.new()
	tree.root.add_child(_audio)
	_audio.setup(SettingsService.new(PlayerProfile.new(), EventBus.new()), SoundBank.from_file())
	return _audio


func _deck(audio: AudioService) -> AudioService.MusicDeck:
	return audio._decks[audio._active_deck]


func test_target_position_wraps_the_loop() -> void:
	assert_near(MusicClock.target_position(0.0, 8.0), 0.0, 0.0001)
	assert_near(MusicClock.target_position(3.5, 8.0), 3.5, 0.0001)
	assert_near(MusicClock.target_position(19.0, 8.0), 3.0, 0.0001, "two loops in")
	assert_near(MusicClock.target_position(-1.0, 8.0), 0.0, 0.0001, "never before the start")
	assert_near(MusicClock.target_position(5.0, 0.0), 0.0, 0.0001, "no loop, no position")
	assert_near(MusicClock.target_position(NAN, 8.0), 0.0, 0.0001)


func test_drift_is_signed_and_wraps_across_the_seam() -> void:
	assert_near(MusicClock.drift(2.05, 2.0, 8.0), 0.05, 0.0001, "music ahead is positive")
	assert_near(MusicClock.drift(1.95, 2.0, 8.0), -0.05, 0.0001, "music behind is negative")
	assert_near(MusicClock.drift(0.02, 7.99, 8.0), 0.03, 0.0001, "just past the seam is slightly ahead")
	assert_near(MusicClock.drift(7.99, 8.02, 8.0), -0.03, 0.0001, "just before the seam is slightly behind")
	assert_near(MusicClock.drift(3.0, 1.0, 0.0), 0.0, 0.0001)


func test_large_jumps_seek_and_small_drift_does_not() -> void:
	assert_eq(MusicClock.seek_target(2.1, 2.0, 8.0), -1.0, "100 ms is nudged, not sought")
	assert_near(MusicClock.seek_target(5.0, 0.0, 8.0), 0.0, 0.0001, "an instant restart goes back to the top")
	assert_near(MusicClock.seek_target(1.0, 12.5, 8.0), 4.5, 0.0001, "a revive goes to where the run is")
	assert_eq(MusicClock.seek_target(1.0, 12.5, 0.0), -1.0, "no loop length, no seek")


func test_rate_nudge_has_hysteresis_and_a_cap() -> void:
	assert_eq(MusicClock.playback_rate(0.0), 1.0)
	assert_eq(MusicClock.playback_rate(0.03, 1.0), 1.0, "inside the tolerance nothing starts")
	assert_lt(MusicClock.playback_rate(0.03, 0.98), 1.0, "a running correction carries on")
	assert_eq(MusicClock.playback_rate(0.005, 0.98), 1.0, "and stops once settled")
	assert_lt(MusicClock.playback_rate(0.05), 1.0, "music ahead slows down")
	assert_gt(MusicClock.playback_rate(-0.05), 1.0, "music behind speeds up")
	assert_near(MusicClock.playback_rate(0.2), 1.0 - MusicClock.MAX_RATE_NUDGE, 0.0001, "capped")
	assert_near(MusicClock.playback_rate(-0.2), 1.0 + MusicClock.MAX_RATE_NUDGE, 0.0001, "capped")
	assert_eq(MusicClock.playback_rate(NAN), 1.0)


func test_held_through_ready_and_pause() -> void:
	var audio: AudioService = _spawn_audio()
	assert_true(audio.play_music("neon_core"))
	var deck: AudioService.MusicDeck = _deck(audio)
	assert_near(audio.sync_run(0.0, false), 0.0, 0.0001)
	assert_true(deck.base.stream_paused, "the READY beat holds the loop at the top")
	assert_true(deck.hi.stream_paused, "both stems together")
	audio.sync_run(0.0, true)
	assert_false(deck.base.stream_paused, "the run starts the loop")
	audio.sync_run(0.2, false)
	assert_true(deck.base.stream_paused, "pause holds it")
	audio.sync_run(0.2, true)
	assert_false(deck.base.stream_paused)
	assert_false(deck.hi.stream_paused)


func test_a_jump_is_sought_and_beats_restart() -> void:
	var audio: AudioService = _spawn_audio()
	assert_true(audio.play_music("neon_core"))
	var deck: AudioService.MusicDeck = _deck(audio)
	# A third of the loop away: past the seek threshold, and the short way round is back.
	var target: float = deck.loop_length * 0.3
	assert_gt(target, MusicClock.SEEK_THRESHOLD_S * 2.0, "loops are long enough to test")
	var drift_s: float = audio.sync_run(target, true)
	assert_lt(drift_s, -MusicClock.SEEK_THRESHOLD_S, "the loop was far behind the run")
	var expected: float = MusicClock.target_position(target + AudioServer.get_output_latency(), deck.loop_length)
	assert_near(deck.base.get_playback_position(), expected, 0.05, "sought to the run")
	assert_near(deck.hi.get_playback_position(), expected, 0.05, "the intensity stem too")
	assert_eq(audio._beat_index, AudioService.NO_BEAT, "beat indices restart from the new position")
	assert_eq(deck.base.pitch_scale, 1.0)


func test_small_drift_is_nudged_through_the_rate() -> void:
	var audio: AudioService = _spawn_audio()
	assert_true(audio.play_music("neon_core"))
	var deck: AudioService.MusicDeck = _deck(audio)
	var latency: float = AudioServer.get_output_latency()
	audio.sync_run(2.0, true)
	audio.tick(MusicClock.SEEK_COOLDOWN_S + 0.05)
	var pos: float = deck.base.get_playback_position()
	assert_near(pos, 2.0 + latency, 0.1, "the loop sits two seconds in")
	# The run is 80 ms behind the music (a hit-stop): slow the loop down a touch.
	audio.sync_run(pos - 0.08 - latency, true)
	assert_lt(deck.base.pitch_scale, 1.0, "music ahead plays a little slower")
	assert_ge(deck.base.pitch_scale, 1.0 - MusicClock.MAX_RATE_NUDGE - 0.0001)
	assert_eq(deck.hi.pitch_scale, deck.base.pitch_scale, "stems stay together")
	assert_near(deck.base.get_playback_position(), pos, 0.1, "no seek for small drift")
	audio.sync_run(pos + 0.08 - latency, true)
	assert_gt(deck.base.pitch_scale, 1.0, "music behind plays a little faster")


func test_lock_lets_go_when_the_run_stops_driving_it() -> void:
	var audio: AudioService = _spawn_audio()
	assert_true(audio.play_music("neon_core"))
	var deck: AudioService.MusicDeck = _deck(audio)
	audio.sync_run(0.0, false)
	assert_true(deck.base.stream_paused)
	audio.tick(AudioService.LOCK_RELEASE_S + 0.05)
	assert_false(deck.base.stream_paused, "the run ended: the loop plays on")
	assert_eq(deck.base.pitch_scale, 1.0)
	audio.sync_run(0.0, false)
	assert_true(audio.play_music("menu"))
	assert_false(deck.base.stream_paused, "a new track always starts free")


func test_no_track_no_lock() -> void:
	var audio: AudioService = _spawn_audio()
	assert_near(audio.sync_run(3.0, true), 0.0, 0.0001)
	assert_false(audio._locked, "nothing to lock")
	var bare: AudioService = AudioService.new()
	assert_near(bare.sync_run(3.0, true), 0.0, 0.0001, "safe before setup")
	bare.free()
