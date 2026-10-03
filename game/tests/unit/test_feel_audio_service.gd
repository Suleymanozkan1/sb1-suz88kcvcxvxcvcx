extends TestCase
## AudioService behaviour (headless, Dummy driver): playback, polyphony, shimmer,
## live settings, intensity fades, beat signal, setup/teardown and bad data.

var _audio: AudioService
var _settings: SettingsService


func after_each() -> void:
	if _audio != null and is_instance_valid(_audio):
		_audio.free()
	_audio = null


## Frees the service and gives the audio thread time to drop finished playbacks.
func _release_audio() -> void:
	if _audio != null and is_instance_valid(_audio):
		_audio.free()
	_audio = null
	await tree.create_timer(0.1).timeout


func _spawn_audio() -> AudioService:
	_settings = SettingsService.new(PlayerProfile.new(), EventBus.new())
	_audio = AudioService.new()
	tree.root.add_child(_audio)
	_audio.setup(_settings, SoundBank.from_file())
	return _audio


func test_malformed_shimmer_config_is_sanitised() -> void:
	var data: Dictionary = JsonIO.read_dict(SoundBank.DEFAULT_PATH)
	(data["mixer"] as Dictionary)["shimmer"] = {
		"kinds": "collect", "min_step": "ten", "semitones": {}, "volume_db": [1]
	}
	var bank: SoundBank = SoundBank.new(data)
	assert_false(bank.is_valid())
	assert_has(bank.problems, "mixer.shimmer.kinds must be a list")
	assert_has(bank.problems, "mixer.shimmer.min_step must be a number")
	assert_has(bank.problems, "mixer.shimmer.semitones must be a number")
	assert_has(bank.problems, "mixer.shimmer.volume_db must be a number")
	var defaults: Dictionary = SoundBank.DEFAULT_MIXER["shimmer"] as Dictionary
	var shimmer: Dictionary = bank.shimmer()
	assert_empty(shimmer["kinds"] as Array)
	assert_eq(shimmer["min_step"], int(defaults["min_step"]))
	assert_near(float(shimmer["semitones"]), float(defaults["semitones"]), 0.0001)
	(data["mixer"] as Dictionary)["shimmer"] = {"kinds": ["collect", 7, "nope", "collect"], "min_step": 4}
	var mixed: SoundBank = SoundBank.new(data)
	assert_eq(mixed.shimmer()["kinds"], [&"collect"] as Array[StringName], "valid kinds kept once")
	assert_has(mixed.problems, "mixer.shimmer.kinds: '7' is not a sound effect kind")
	assert_has(mixed.problems, "mixer.shimmer.kinds: 'nope' is not a sound effect kind")
	_settings = SettingsService.new(PlayerProfile.new(), EventBus.new())
	_audio = AudioService.new()
	tree.root.add_child(_audio)
	_audio.setup(_settings, bank)
	assert_true(_audio.play_sfx(&"collect", 20), "broken shimmer data never breaks playback")
	assert_eq(_audio.active_voice_count(AudioService.SHIMMER_KIND), 0)
	_audio.setup(_settings, mixed)
	assert_true(_audio.play_sfx(&"collect", 4))
	assert_eq(_audio.active_voice_count(AudioService.SHIMMER_KIND), 1, "sanitised min_step honoured")
	await _release_audio()


func test_playback_needs_the_scene_tree() -> void:
	_settings = SettingsService.new(PlayerProfile.new(), EventBus.new())
	_audio = AudioService.new()
	_audio.setup(_settings, SoundBank.from_file())
	assert_false(_audio.play_sfx(&"tap"), "no engine error and no false success outside the tree")
	assert_false(_audio.play_music("menu"))
	assert_false(_audio.play_stinger(&"level_complete"))
	tree.root.add_child(_audio)
	assert_true(_audio.play_sfx(&"tap"))
	assert_true(_audio.play_music("menu"))
	await _release_audio()


func test_switching_back_reuses_the_fading_deck() -> void:
	var audio: AudioService = _spawn_audio()
	assert_true(audio.play_music("neon_core"))
	var neon: AudioStreamPlayer = audio.get_node("Deck1Base") as AudioStreamPlayer
	assert_true(neon.playing, "first track starts on the second deck")
	await tree.create_timer(0.3).timeout
	assert_true(audio.play_music("menu"))
	await wait_frames(2)
	assert_true(neon.playing, "old track is fading out, not cut")
	assert_true(audio.play_music("neon_core"))
	assert_eq(audio.current_track(), "neon_core")
	assert_true(neon.playing)
	assert_gt(neon.get_playback_position(), 0.1, "the fading loop was brought back, not restarted")
	await _release_audio()


func test_setup_with_new_settings_drops_the_old_ones() -> void:
	var audio: AudioService = _spawn_audio()
	var old_settings: SettingsService = _settings
	var fresh: SettingsService = SettingsService.new(PlayerProfile.new(), EventBus.new())
	audio.setup(fresh, SoundBank.from_file())
	var sfx_idx: int = AudioServer.get_bus_index(AudioService.SFX_BUS)
	old_settings.set_value("sound", false)
	assert_false(AudioServer.is_bus_mute(sfx_idx), "the replaced settings no longer drive the buses")
	fresh.set_value("sound", false)
	assert_true(AudioServer.is_bus_mute(sfx_idx))
	fresh.set_value("sound", true)
	await _release_audio()


func test_audio_service_plays_everything_headless() -> void:
	var audio: AudioService = _spawn_audio()
	assert_true(audio.is_ready())
	assert_eq(audio.voice_count(), 12)
	var bank: SoundBank = SoundBank.from_file()
	for kind: StringName in bank.kinds():
		assert_true(audio.play_sfx(kind, 3, 0.8), String(kind))
	assert_le(audio.active_voice_count(), audio.voice_count())
	assert_false(audio.play_sfx(&"unknown_kind"))
	assert_true(audio.play_music("neon_core"))
	await wait_frames(3)
	assert_true(audio.is_music_playing())
	assert_eq(audio.current_track(), "neon_core")
	assert_true(audio.play_music("neon_core"), "same track keeps playing")
	assert_true(audio.play_music("neon_core", true), "boss loop")
	assert_true(audio.play_music("menu"))
	assert_false(audio.play_music("not_a_world"))
	assert_true(audio.play_stinger(&"level_complete"))
	assert_false(audio.play_stinger(&"nope"))
	await wait_frames(3)
	audio.stop_music(0.0)
	assert_false(audio.is_music_playing())
	assert_eq(audio.current_track(), "")
	await _release_audio()


func test_polyphony_limit_and_voice_stealing() -> void:
	var audio: AudioService = _spawn_audio()
	for i: int in 4:
		audio.play_sfx(&"fail")
	assert_eq(audio.active_voice_count(&"fail"), 1, "max_polyphony 1 steals its own oldest voice")
	for i: int in 40:
		audio.play_sfx(&"collect", i)
		audio.play_sfx(&"shatter", i)
	assert_le(audio.active_voice_count(), audio.voice_count())
	assert_le(audio.active_voice_count(&"collect"), int(SoundBank.from_file().sfx(&"collect")["max_polyphony"]))
	await _release_audio()


func test_combo_shimmer_layer_only_at_high_combo() -> void:
	var audio: AudioService = _spawn_audio()
	audio.play_sfx(&"combo", 5)
	assert_eq(audio.active_voice_count(AudioService.SHIMMER_KIND), 0)
	audio.play_sfx(&"combo", 10)
	assert_eq(audio.active_voice_count(AudioService.SHIMMER_KIND), 1)
	await _release_audio()


func test_settings_apply_live_to_buses() -> void:
	var audio: AudioService = _spawn_audio()
	var sfx_idx: int = AudioServer.get_bus_index(AudioService.SFX_BUS)
	var music_idx: int = AudioServer.get_bus_index(AudioService.MUSIC_BUS)
	assert_false(AudioServer.is_bus_mute(sfx_idx))
	_settings.set_value("sound", false)
	assert_true(AudioServer.is_bus_mute(sfx_idx))
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioService.UI_BUS)))
	assert_false(audio.play_sfx(&"tap"), "sound off skips playback")
	_settings.set_value("sound", true)
	assert_true(audio.play_sfx(&"tap"))
	_settings.set_value("music_volume", 0.5)
	assert_near(AudioServer.get_bus_volume_db(music_idx), -4.0 + linear_to_db(0.5), 0.01)
	_settings.set_value("music", false)
	assert_true(AudioServer.is_bus_mute(music_idx))
	_settings.set_value("music_volume", 0.0)
	_settings.set_value("music", true)
	assert_true(AudioServer.is_bus_mute(music_idx), "zero volume mutes")
	audio.free()
	_audio = null
	assert_false(AudioServer.is_bus_mute(music_idx), "bus state restored when the service leaves")
	assert_near(AudioServer.get_bus_volume_db(music_idx), -4.0, 0.01)
	await _release_audio()


func test_intensity_layer_fades_smoothly() -> void:
	var audio: AudioService = _spawn_audio()
	audio.set_process(false)
	assert_true(audio.play_music("crystal_valley"))
	audio.set_intensity(0.0)
	for i: int in 120:
		audio.tick(1.0 / 60.0)
	var base_db: float = audio.stem_volume_db("base")
	assert_le(audio.stem_volume_db("hi"), AudioService.SILENT_DB + 0.1, "intensity 0 silences the hi stem")
	audio.set_intensity(1.0)
	audio.tick(1.0 / 60.0)
	var first: float = audio.intensity()
	assert_gt(first, 0.0)
	assert_lt(first, 0.2, "no jump: the layer fades in")
	for i: int in 240:
		audio.tick(1.0 / 60.0)
	assert_near(audio.intensity(), 1.0, 0.01)
	assert_near(audio.stem_volume_db("hi") - base_db, -3.0, 0.1, "hi sits at its mix level over base")
	audio.set_combo(10)
	for i: int in 240:
		audio.tick(1.0 / 60.0)
	assert_near(audio.intensity(), 0.5, 0.01, "combo 10 of 20 = half intensity")
	audio.set_intensity(NAN)
	for i: int in 240:
		audio.tick(1.0 / 60.0)
	assert_near(audio.intensity(), 0.0, 0.01)
	await _release_audio()


func test_beat_signal_follows_playback() -> void:
	var audio: AudioService = _spawn_audio()
	var beats: Array[int] = []
	audio.beat.connect(func(index: int) -> void: beats.append(index))
	assert_true(audio.play_music("candy_reactor"))
	await tree.create_timer(1.0).timeout
	assert_ge(beats.size(), 2, "146 bpm gives a beat every 0.41 s")
	for i: int in range(1, beats.size()):
		assert_eq(beats[i], beats[i - 1] + 1, "beats are consecutive")
	assert_ge(audio.beat_phase(), 0.0)
	assert_lt(audio.beat_phase(), 1.0)
	await _release_audio()


func test_on_feedback_connects_to_gameplay_view_signal() -> void:
	var audio: AudioService = _spawn_audio()
	var view: GameplayView = GameplayView.new()
	view.feedback.connect(audio.on_feedback)
	view.feedback.emit(&"tap", 0.4, 1)
	assert_eq(audio.active_voice_count(&"tap"), 1)
	view.free()
	await _release_audio()


func test_setup_twice_rebuilds_pool() -> void:
	var audio: AudioService = _spawn_audio()
	audio.setup(_settings, SoundBank.from_file())
	await wait_frames(1)
	assert_eq(audio.voice_count(), 12)
	assert_eq(audio.get_child_count(), 12 + 2 * AudioService.DECK_COUNT + 1)
	assert_true(audio.play_sfx(&"coin"))
	await _release_audio()
