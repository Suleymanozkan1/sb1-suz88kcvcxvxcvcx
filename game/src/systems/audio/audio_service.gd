class_name AudioService
extends Node
## Plays the procedural sound bank: pooled sound-effect voices and layered,
## beat-tracked music.
##
## Sound effects use a fixed pool of [AudioStreamPlayer] voices with per-kind
## polyphony limits and oldest-voice stealing; combo-driven kinds rise in pitch
## (capped) and gain a shimmer layer at high combos. Music runs on two decks
## (for crossfades), each a base stem plus an intensity stem started in the
## same call so they stay sample-aligned; [method set_intensity] fades the
## intensity stem in smoothly. [signal beat] is derived from the music playback
## position for visual sync. Settings (sound/music toggles, volumes) apply live
## to the Music/SFX/UI buses. Works headless with the Dummy audio driver.

## Emitted once per music beat (running index across loops) for visual sync.
signal beat(index: int)

const LOG_CHANNEL: String = "audio"
const MASTER_BUS: StringName = &"Master"
const MUSIC_BUS: StringName = &"Music"
const SFX_BUS: StringName = &"SFX"
const UI_BUS: StringName = &"UI"
const SHIMMER_KIND: StringName = &"shimmer"
const SHIMMER_POLYPHONY: int = 3
const SILENT_DB: float = -80.0
const MIN_GAIN: float = 0.0001
const MUTE_VOLUME: float = 0.001
const SEMITONES_PER_OCTAVE: float = 12.0
const SECONDS_PER_MINUTE: float = 60.0
const LOOP_WRAP_FRACTION: float = 0.5
const DECK_COUNT: int = 2
## Share of the bank's music fade used to bring a new track in.
const FADE_IN_FRACTION: float = 0.5
const MIN_DUCK_RELEASE_S: float = 0.01
## Frequency ratio of one octave (pitch_scale doubles every 12 semitones).
const OCTAVE_RATIO: float = 2.0
const NO_BEAT: int = -1


## One pair of synchronised stem players (base + intensity layer).
class MusicDeck:
	extends RefCounted

	var base: AudioStreamPlayer
	var hi: AudioStreamPlayer
	var track: String = ""
	var boss: bool = false
	var bpm: float = 0.0
	var beats_per_loop: int = 0
	var loop_length: float = 0.0
	var gain: float = 0.0
	var target: float = 0.0
	var rate: float = 0.0

	func _init(base_player: AudioStreamPlayer, hi_player: AudioStreamPlayer) -> void:
		base = base_player
		hi = hi_player

	## True while the base stem is playing.
	func is_playing() -> bool:
		return base.playing

	## Starts a linear fade of [member gain] toward [param to] over [param seconds].
	func fade_to(to: float, seconds: float) -> void:
		target = clampf(to, 0.0, 1.0)
		if seconds <= 0.0:
			gain = target
			rate = 0.0
		else:
			rate = absf(target - gain) / seconds

	## Advances the fade by [param delta] seconds.
	func advance(delta: float) -> void:
		if rate > 0.0:
			gain = move_toward(gain, target, rate * delta)
		else:
			gain = target

	## Stops both players and clears the deck.
	func halt() -> void:
		base.stop()
		hi.stop()
		track = ""
		boss = false
		gain = 0.0
		target = 0.0
		rate = 0.0


var _settings: SettingsService
var _bank: SoundBank
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _voices: Array[AudioStreamPlayer] = []
var _voice_kind: Array[StringName] = []
var _voice_seq: PackedInt64Array = PackedInt64Array()
var _seq: int = 0
var _decks: Array[MusicDeck] = []
var _active_deck: int = 0
var _stinger_player: AudioStreamPlayer
var _intensity: float = 0.0
var _intensity_target: float = 0.0
var _duck: float = 1.0
var _beat_index: int = NO_BEAT
var _beat_phase: float = 0.0
var _loop_count: int = 0
var _last_pos: float = 0.0
var _ready_ok: bool = false
var _warned_buses: Dictionary = {}


## Wires the service to settings and a sound bank and builds the player pool.
## Safe to call again (the previous pool is released first and a previously
## injected [SettingsService] stops driving the buses).
func setup(settings: SettingsService, bank: SoundBank) -> void:
	_teardown_players()
	if _settings != null and _settings != settings and _settings.changed.is_connected(_on_settings_changed):
		_settings.changed.disconnect(_on_settings_changed)
	_settings = settings
	_bank = bank if bank != null else SoundBank.new()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	for i: int in _bank.voices():
		var voice: AudioStreamPlayer = _make_player("Voice%d" % i, SFX_BUS)
		_voices.append(voice)
		_voice_kind.append(&"")
		_voice_seq.append(0)
	for d: int in DECK_COUNT:
		_decks.append(MusicDeck.new(_make_player("Deck%dBase" % d, MUSIC_BUS), _make_player("Deck%dHi" % d, MUSIC_BUS)))
	_stinger_player = _make_player("Stinger", MUSIC_BUS)
	if _settings != null and not _settings.changed.is_connected(_on_settings_changed):
		_settings.changed.connect(_on_settings_changed)
	_ensure_limiter()
	_ready_ok = true
	apply_settings()
	_bank.preload_sfx()


## True once [method setup] has run.
func is_ready() -> bool:
	return _ready_ok


## Plays a sound effect. [param pitch_step] raises the pitch by the kind's
## per-step semitone fraction (capped); [param strength] (0..1) scales loudness.
## Returns true when a voice was started (never before the service is in the tree).
func play_sfx(kind: StringName, pitch_step: int = 0, strength: float = 1.0) -> bool:
	if not _can_play() or (_settings != null and not _settings.get_bool("sound")):
		return false
	var entry: Dictionary = _bank.sfx(kind)
	if entry.is_empty():
		return false
	var stream: AudioStream = _bank.sfx_stream(kind)
	if stream == null:
		return false
	var semis: float = _pitch_semitones(entry, pitch_step)
	var volume: float = float(entry["volume_db"]) + _strength_db(strength)
	var bus: StringName = entry["bus"] as StringName
	_start_voice(kind, stream, bus, semis, volume, int(entry["max_polyphony"]))
	var shimmer: Dictionary = _bank.shimmer()
	if (shimmer["kinds"] as Array).has(kind) and pitch_step >= int(shimmer["min_step"]):
		_start_voice(SHIMMER_KIND, stream, bus, semis + float(shimmer["semitones"]),
			volume + float(shimmer["volume_db"]), SHIMMER_POLYPHONY)
	return true


## Signal-compatible with [signal GameplayView.feedback].
func on_feedback(kind: StringName, strength: float, pitch_step: int) -> void:
	play_sfx(kind, pitch_step, strength)


## Starts (or keeps) a music track: "menu" or a world id. [param boss] selects
## the world's boss loop. Crossfades from the current track. Returns false (with a
## warning) before [method setup] or while the service is outside the scene tree.
func play_music(track: String, boss: bool = false) -> bool:
	if not _can_play():
		GameLog.warn(LOG_CHANNEL, "play_music('%s') ignored: service not set up or not in the tree" % track)
		return false
	var entry: Dictionary = _bank.music(track)
	if entry.is_empty():
		GameLog.warn(LOG_CHANNEL, "unknown music track '%s'" % track)
		return false
	var fade_s: float = _bank.mixer_float("music_fade_s")
	var current: MusicDeck = _decks[_active_deck]
	if current.track == track and current.boss == boss and current.is_playing():
		current.fade_to(1.0, fade_s * FADE_IN_FRACTION)
		return true
	var other_index: int = (_active_deck + 1) % DECK_COUNT
	var other: MusicDeck = _decks[other_index]
	if other.track == track and other.boss == boss and other.is_playing():
		# Switching straight back: fade the still-sounding deck in again instead of
		# hard-cutting it mid fade-out (audible click) and restarting the loop.
		current.fade_to(0.0, fade_s)
		_active_deck = other_index
		other.fade_to(1.0, fade_s * FADE_IN_FRACTION)
		_reset_beat_tracking()
		return true
	var boss_path: String = str(entry["boss"])
	var use_boss: bool = boss and not boss_path.is_empty() and _bank.stream_at(boss_path) != null
	var base_stream: AudioStream = _bank.stream_at(boss_path if use_boss else str(entry["base"]))
	if base_stream == null:
		return false
	var hi_stream: AudioStream = null if use_boss else _bank.stream_at(str(entry["hi"]))
	_ensure_loop(base_stream)
	_ensure_loop(hi_stream)
	if current.is_playing():
		current.fade_to(0.0, fade_s)
	_active_deck = other_index
	var deck: MusicDeck = other
	deck.halt()
	deck.track = track
	deck.boss = boss
	deck.bpm = float(entry["boss_bpm"]) if use_boss else float(entry["bpm"])
	deck.beats_per_loop = int(entry["bars"]) * SoundBank.BEATS_PER_BAR
	deck.loop_length = base_stream.get_length()
	deck.base.stream = base_stream
	deck.hi.stream = hi_stream
	deck.fade_to(1.0, fade_s * FADE_IN_FRACTION)
	_apply_deck_volume(deck)
	deck.base.play()
	if hi_stream != null:
		deck.hi.play()
	_reset_beat_tracking()
	return true


## Fades the current music out over [param fade_s] seconds (negative = bank default).
func stop_music(fade_s: float = -1.0) -> void:
	if not _ready_ok:
		return
	var seconds: float = fade_s if fade_s >= 0.0 else _bank.mixer_float("music_fade_s")
	for deck: MusicDeck in _decks:
		if seconds <= 0.0:
			deck.halt()
		else:
			deck.fade_to(0.0, seconds)
	if seconds <= 0.0:
		_beat_index = NO_BEAT


## Target loudness (0..1) of the intensity stem; followed smoothly.
func set_intensity(value: float) -> void:
	_intensity_target = 0.0 if is_nan(value) else clampf(value, 0.0, 1.0)


## Maps a combo count to intensity (full at the bank's "intensity_full_combo").
func set_combo(combo: int) -> void:
	var full: float = maxf(1.0, _bank.mixer_float("intensity_full_combo")) if _bank != null else 1.0
	set_intensity(float(maxi(combo, 0)) / full)


## Current (smoothed) intensity.
func intensity() -> float:
	return _intensity


## Plays a stinger (e.g. &"level_complete") on the music bus, ducking the loop.
func play_stinger(stinger_name: StringName) -> bool:
	if not _can_play() or (_settings != null and not _settings.get_bool("music")):
		return false
	var entry: Dictionary = _bank.stinger(stinger_name)
	if entry.is_empty():
		return false
	var stream: AudioStream = _bank.stream_at(str(entry["file"]))
	if stream == null:
		return false
	_stinger_player.stop()
	_stinger_player.stream = stream
	_stinger_player.volume_db = float(entry["volume_db"])
	_stinger_player.play()
	return true


## Track id of the active music deck ("" when none).
func current_track() -> String:
	var deck: MusicDeck = _decks[_active_deck] if _ready_ok else null
	return deck.track if deck != null and deck.is_playing() else ""


## True while a music track is audible or fading.
func is_music_playing() -> bool:
	return _ready_ok and _decks[_active_deck].is_playing()


## Running beat index of the current track (-1 before the first beat).
func current_beat() -> int:
	return _beat_index


## Position inside the current beat (0..1), for pulsing visuals.
func beat_phase() -> float:
	return _beat_phase


## Volume in dB currently applied to a stem of the active deck ("base" or "hi").
func stem_volume_db(stem: String) -> float:
	if not _ready_ok:
		return SILENT_DB
	var deck: MusicDeck = _decks[_active_deck]
	return deck.hi.volume_db if stem == "hi" else deck.base.volume_db


## Number of pooled sfx voices.
func voice_count() -> int:
	return _voices.size()


## Voices currently playing (optionally only those playing [param kind]).
func active_voice_count(kind: StringName = &"") -> int:
	var n: int = 0
	for i: int in _voices.size():
		if _voices[i].playing and (kind == &"" or _voice_kind[i] == kind):
			n += 1
	return n


## Re-applies every audio setting to the buses (also done live on changes).
func apply_settings() -> void:
	if not _ready_ok:
		return
	_apply_bus(SFX_BUS, _setting_bool("sound"), _setting_float("sfx_volume"))
	_apply_bus(UI_BUS, _setting_bool("sound"), _setting_float("sfx_volume"))
	_apply_bus(MUSIC_BUS, _setting_bool("music"), _setting_float("music_volume"))


func _enter_tree() -> void:
	apply_settings()


func _exit_tree() -> void:
	if not _ready_ok:
		return
	for bus_name: StringName in [MUSIC_BUS, SFX_BUS, UI_BUS]:
		var idx: int = AudioServer.get_bus_index(bus_name)
		if idx >= 0:
			AudioServer.set_bus_mute(idx, false)
			AudioServer.set_bus_volume_db(idx, _bus_base_db(bus_name))


func _process(delta: float) -> void:
	tick(delta)


## Advances fades, intensity smoothing, ducking and beat tracking by [param delta]
## seconds (called every frame; public so tests can drive time deterministically).
func tick(delta: float) -> void:
	if not _ready_ok or is_nan(delta) or delta < 0.0:
		return
	var response: float = maxf(0.0, _bank.mixer_float("intensity_response"))
	_intensity += (_intensity_target - _intensity) * (1.0 - exp(-delta * response))
	var duck_target: float = db_to_linear(_bank.mixer_float("stinger_duck_db")) if _stinger_player.playing else 1.0
	var release: float = maxf(MIN_DUCK_RELEASE_S, _bank.mixer_float("stinger_duck_release_s"))
	_duck = move_toward(_duck, duck_target, delta / release)
	for deck: MusicDeck in _decks:
		deck.advance(delta)
		if deck.is_playing() and deck.gain <= 0.0 and deck.target <= 0.0:
			deck.halt()
		_apply_deck_volume(deck)
	_track_beat()


func _track_beat() -> void:
	var deck: MusicDeck = _decks[_active_deck]
	if not deck.is_playing() or deck.bpm <= 0.0:
		return
	var pos: float = deck.base.get_playback_position()
	pos = maxf(0.0, pos + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency())
	if deck.loop_length > 0.0 and pos + deck.loop_length * LOOP_WRAP_FRACTION < _last_pos:
		_loop_count += 1
	_last_pos = pos
	var beats: float = pos * deck.bpm / SECONDS_PER_MINUTE
	_beat_phase = beats - floorf(beats)
	var index: int = _loop_count * deck.beats_per_loop + int(floorf(beats))
	# Monotonic: position estimates can jitter backwards between mixes.
	if index > _beat_index:
		_beat_index = index
		beat.emit(index)


## The active deck changed: beat indices restart from its current position.
func _reset_beat_tracking() -> void:
	_beat_index = NO_BEAT
	_beat_phase = 0.0
	_loop_count = 0
	_last_pos = 0.0


func _apply_deck_volume(deck: MusicDeck) -> void:
	var g: float = deck.gain * _duck
	deck.base.volume_db = _gain_db(g) + _bank.mixer_float("base_volume_db")
	deck.hi.volume_db = _gain_db(g * _intensity) + _bank.mixer_float("hi_volume_db")


func _start_voice(kind: StringName, stream: AudioStream, bus: StringName, semis: float, volume_db: float,
		max_polyphony: int) -> void:
	var idx: int = _pick_voice(kind, max_polyphony)
	var voice: AudioStreamPlayer = _voices[idx]
	voice.stop()
	voice.stream = stream
	voice.bus = bus
	voice.pitch_scale = pow(OCTAVE_RATIO, semis / SEMITONES_PER_OCTAVE)
	voice.volume_db = volume_db
	_seq += 1
	_voice_seq[idx] = _seq
	_voice_kind[idx] = kind
	voice.play()


## Free voice if any; the oldest voice of [param kind] when its polyphony limit is
## reached; otherwise the oldest voice overall (voice stealing).
func _pick_voice(kind: StringName, max_polyphony: int) -> int:
	var same: int = 0
	var oldest_same: int = -1
	var free: int = -1
	var oldest: int = 0
	for i: int in _voices.size():
		if not _voices[i].playing:
			if free < 0:
				free = i
			continue
		if _voice_kind[i] == kind:
			same += 1
			if oldest_same < 0 or _voice_seq[i] < _voice_seq[oldest_same]:
				oldest_same = i
		if _voice_seq[i] < _voice_seq[oldest]:
			oldest = i
	if same >= max_polyphony and oldest_same >= 0:
		return oldest_same
	return free if free >= 0 else oldest


func _pitch_semitones(entry: Dictionary, pitch_step: int) -> float:
	var cap: float = _bank.mixer_float("max_pitch_semitones")
	var semis: float = clampf(float(pitch_step) * float(entry["pitch_step"]), -cap, cap)
	var jitter: float = float(entry["jitter"])
	if jitter > 0.0:
		semis += _rng.randf_range(-jitter, jitter)
	return semis


func _strength_db(strength: float) -> float:
	var s: float = 1.0 if is_nan(strength) else clampf(strength, 0.0, 1.0)
	var floor_gain: float = clampf(_bank.mixer_float("strength_floor"), MIN_GAIN, 1.0)
	return linear_to_db(lerpf(floor_gain, 1.0, s))


## Players can only start inside the scene tree (the engine errors otherwise).
func _can_play() -> bool:
	return _ready_ok and is_inside_tree()


func _gain_db(gain: float) -> float:
	return SILENT_DB if gain < MIN_GAIN else linear_to_db(gain)


func _on_settings_changed(key: StringName, _value: Variant) -> void:
	match String(key):
		"sound", "sfx_volume":
			apply_settings()
			if not _setting_bool("sound"):
				for voice: AudioStreamPlayer in _voices:
					voice.stop()
		"music", "music_volume":
			apply_settings()


func _apply_bus(bus_name: StringName, enabled: bool, volume: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		if not _warned_buses.has(bus_name):
			_warned_buses[bus_name] = true
			GameLog.warn(LOG_CHANNEL, "audio bus %s missing from the bus layout" % bus_name)
		return
	var audible: bool = enabled and volume > MUTE_VOLUME
	AudioServer.set_bus_mute(idx, not audible)
	AudioServer.set_bus_volume_db(idx, _bus_base_db(bus_name) + (linear_to_db(volume) if audible else SILENT_DB))


func _bus_base_db(bus_name: StringName) -> float:
	var levels: Variant = _bank.mixer("bus_base_db") if _bank != null else {}
	if typeof(levels) != TYPE_DICTIONARY:
		return 0.0
	var v: Variant = (levels as Dictionary).get(String(bus_name), 0.0)
	return float(v) if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT else 0.0


func _setting_bool(key: String) -> bool:
	return true if _settings == null else _settings.get_bool(key)


func _setting_float(key: String) -> float:
	if _settings == null:
		return float(PlayerProfile.DEFAULT_SETTINGS.get(key, 1.0))
	return _settings.get_float(key)


func _ensure_limiter() -> void:
	var idx: int = AudioServer.get_bus_index(MASTER_BUS)
	if idx < 0:
		return
	for e: int in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, e) is AudioEffectHardLimiter:
			return
	var limiter: AudioEffectHardLimiter = AudioEffectHardLimiter.new()
	limiter.ceiling_db = _bank.mixer_float("limiter_ceiling_db")
	AudioServer.add_bus_effect(idx, limiter)


## Imported loops carry loop points from the WAV "smpl" chunk; this is a safety
## net for streams imported without them.
func _ensure_loop(stream: AudioStream) -> void:
	var wav: AudioStreamWAV = stream as AudioStreamWAV
	if wav == null or wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		return
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))


func _make_player(player_name: String, bus: StringName) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.name = player_name
	p.bus = bus
	add_child(p)
	return p


func _teardown_players() -> void:
	for voice: AudioStreamPlayer in _voices:
		voice.queue_free()
	for deck: MusicDeck in _decks:
		deck.base.queue_free()
		deck.hi.queue_free()
	if _stinger_player != null:
		_stinger_player.queue_free()
	_voices.clear()
	_voice_kind.clear()
	_voice_seq.clear()
	_decks.clear()
	_stinger_player = null
	_ready_ok = false
