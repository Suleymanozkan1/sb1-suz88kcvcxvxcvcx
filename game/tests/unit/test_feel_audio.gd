extends TestCase
## SoundBank data and asset coverage: every kind and file present, WAV format,
## exact loop lengths, normalisation, size budget, licensing and bad data.

const SAMPLE_RATE: int = 22050
const PEAK_LIMIT: int = 29205  # -1 dBFS of 16-bit full scale, rounded up
const SFX_MIN_S: float = 0.05
const SFX_MAX_S: float = 1.5
const AUDIO_BUDGET_BYTES: int = 25 * 1024 * 1024
const GAMEPLAY_VIEW_PATH: String = "res://src/gameplay/view/gameplay_view.gd"
const WORLD_INDEX_PATH: String = "res://data/worlds/index.json"
const LICENSES_PATH: String = "res://assets/LICENSES.json"


## Parses a RIFF/WAVE file: {"channels", "rate", "bits", "format", "frames", "loop", "data_offset"}.
func _wav_info(path: String) -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return {}
	var info: Dictionary = {"loop": false}
	var pos: int = 12
	while pos + 8 <= bytes.size():
		var id: String = bytes.slice(pos, pos + 4).get_string_from_ascii()
		var size: int = bytes.decode_u32(pos + 4)
		if id == "fmt ":
			info["format"] = bytes.decode_u16(pos + 8)
			info["channels"] = bytes.decode_u16(pos + 10)
			info["rate"] = bytes.decode_u32(pos + 12)
			info["bits"] = bytes.decode_u16(pos + 22)
		elif id == "smpl":
			info["loop"] = bytes.decode_u32(pos + 8 + 28) > 0
		elif id == "data":
			info["frames"] = size / 2
			info["data_offset"] = pos + 8
		pos += 8 + size + (size & 1)
	return info


func _world_ids() -> Array[String]:
	var out: Array[String] = []
	for raw: Variant in JsonIO.read_dict(WORLD_INDEX_PATH).get("worlds", []) as Array:
		out.append(str((raw as Dictionary)["id"]))
	return out


func test_bank_loads_without_problems() -> void:
	var bank: SoundBank = SoundBank.from_file()
	assert_empty(bank.problems)
	assert_true(bank.is_valid())
	assert_eq(bank.voices(), 12)


func test_bank_covers_every_kind_with_sane_entries() -> void:
	var bank: SoundBank = SoundBank.from_file()
	for kind: StringName in SoundBank.REQUIRED_KINDS:
		assert_true(bank.has_kind(kind), String(kind))
		var e: Dictionary = bank.sfx(kind)
		assert_true(SoundBank.SFX_BUSES.has(e["bus"] as StringName), "%s bus" % kind)
		assert_ge(int(e["max_polyphony"]), 1)
		assert_le(float(e["volume_db"]), 0.0, "%s leaves headroom" % kind)
		assert_eq(str(e["file"]), "res://assets/audio/sfx/%s.wav" % kind)
	for kind: StringName in [&"collect", &"combo"]:
		assert_gt(float(bank.sfx(kind)["pitch_step"]), 0.0, "%s rises with combo" % kind)


func test_every_gameplay_feedback_kind_has_a_sound() -> void:
	var source: String = FileAccess.get_file_as_string(GAMEPLAY_VIEW_PATH)
	assert_false(source.is_empty())
	var re: RegEx = RegEx.create_from_string('&"([a-z_]+)"')
	var bank: SoundBank = SoundBank.from_file()
	var found: int = 0
	for line: String in source.split("\n"):
		if not line.contains("feedback.emit("):
			continue
		for m: RegExMatch in re.search_all(line):
			found += 1
			assert_true(bank.has_kind(StringName(m.get_string(1))), "feedback kind %s" % m.get_string(1))
	assert_gt(found, 20, "scanned the gameplay feedback calls")


func test_all_referenced_files_exist_and_load() -> void:
	var bank: SoundBank = SoundBank.from_file()
	assert_empty(bank.missing_files())
	assert_eq(bank.preload_sfx(), SoundBank.REQUIRED_KINDS.size())
	for path: String in bank.all_files():
		assert_true(bank.stream_at(path) is AudioStreamWAV, path)


func test_music_covers_every_world_and_matches_tempo() -> void:
	var bank: SoundBank = SoundBank.from_file()
	assert_false(bank.music(SoundBank.MENU_TRACK).is_empty(), "menu loop")
	var ids: Array[String] = _world_ids()
	assert_eq(ids.size(), 10)
	for id: String in ids:
		var m: Dictionary = bank.music(id)
		assert_false(m.is_empty(), id)
		for stem: String in ["base", "hi", "boss"]:
			assert_false(str(m.get(stem, "")).is_empty(), "%s %s" % [id, stem])
		var world: Dictionary = JsonIO.read_dict("res://data/worlds/%s" % _world_file(id))
		var bpm: float = float((world["music"] as Dictionary)["bpm"])
		assert_near(float(m["bpm"]), bpm, 0.001, "%s bpm" % id)
		assert_gt(float(m["boss_bpm"]), bpm, "%s boss is faster" % id)
	for s: StringName in SoundBank.REQUIRED_STINGERS:
		assert_false(bank.stinger(s).is_empty(), String(s))


func _world_file(id: String) -> String:
	for raw: Variant in JsonIO.read_dict(WORLD_INDEX_PATH).get("worlds", []) as Array:
		if str((raw as Dictionary)["id"]) == id:
			return str((raw as Dictionary)["file"])
	return ""


func test_wav_format_lengths_and_loops() -> void:
	var bank: SoundBank = SoundBank.from_file()
	for kind: StringName in bank.kinds():
		var info: Dictionary = _wav_info(str(bank.sfx(kind)["file"]))
		assert_false(info.is_empty(), String(kind))
		assert_eq(info["format"], 1, "PCM")
		assert_eq(info["channels"], 1, "mono")
		assert_eq(info["rate"], SAMPLE_RATE)
		assert_eq(info["bits"], 16)
		var seconds: float = float(info["frames"]) / SAMPLE_RATE
		assert_ge(seconds, SFX_MIN_S - 0.001, "%s length" % kind)
		assert_le(seconds, SFX_MAX_S, "%s length" % kind)
	for track: String in bank.tracks():
		var m: Dictionary = bank.music(track)
		var beats: int = int(m["bars"]) * SoundBank.BEATS_PER_BAR
		var stems: Dictionary = {"base": float(m["bpm"]), "hi": float(m["bpm"]), "boss": float(m["boss_bpm"])}
		for stem: String in stems:
			var path: String = str(m[stem])
			if path.is_empty():
				continue
			var info: Dictionary = _wav_info(path)
			var expected: int = roundi(beats * 60.0 / float(stems[stem]) * SAMPLE_RATE)
			assert_eq(info["frames"], expected, "%s exactly %d beats" % [path, beats])
			assert_true(info["loop"] as bool, "%s carries loop points" % path)
			var stream: AudioStreamWAV = bank.stream_at(path) as AudioStreamWAV
			assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s imported as a loop" % path)


func test_sfx_are_normalised_without_clipping() -> void:
	var bank: SoundBank = SoundBank.from_file()
	for kind: StringName in bank.kinds():
		var path: String = str(bank.sfx(kind)["file"])
		var info: Dictionary = _wav_info(path)
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		var offset: int = int(info["data_offset"])
		var peak: int = 0
		for i: int in int(info["frames"]):
			peak = maxi(peak, absi(bytes.decode_s16(offset + i * 2)))
		assert_le(peak, PEAK_LIMIT, "%s peak" % kind)
		assert_gt(peak, PEAK_LIMIT - 400, "%s normalised to about -1 dBFS" % kind)


func test_audio_fits_size_budget_and_is_licensed() -> void:
	var total: int = 0
	for dir_path: String in ["res://assets/audio/sfx", "res://assets/audio/music"]:
		for file: String in DirAccess.get_files_at(dir_path):
			if file.ends_with(".wav"):
				total += FileAccess.get_file_as_bytes(dir_path.path_join(file)).size()
	assert_gt(total, 0)
	assert_lt(total, AUDIO_BUDGET_BYTES)
	var licenses: Dictionary = JsonIO.read_dict(LICENSES_PATH)
	var found: bool = false
	for raw: Variant in licenses.get("entries", []) as Array:
		var e: Dictionary = raw as Dictionary
		if str(e.get("path", "")) == "game/assets/audio/":
			found = str(e.get("generated_by", "")) == "tools/audio/synth_bank.py"
	assert_true(found, "audio listed as generated by the synth tool")


func test_bank_survives_bad_data() -> void:
	var bank: SoundBank = (
		SoundBank
		. new(
			{
				"mixer": {"voices": "many"},
				"sfx": {"tap": {"file": "res://assets/audio/sfx/none.wav", "bus": "Bogus", "volume_db": "loud"}},
				"music": {"neon_core": {"base": "", "bpm": 120}},
			}
		)
	)
	assert_false(bank.is_valid())
	assert_has(bank.problems, "missing file res://assets/audio/sfx/none.wav")
	assert_eq(bank.sfx(&"tap")["bus"], &"SFX", "unknown bus falls back")
	assert_near(float(bank.sfx(&"tap")["volume_db"]), 0.0, 0.0001)
	assert_eq(bank.sfx_stream(&"tap"), null)
	assert_true(bank.music("neon_core").is_empty(), "entry without base stem dropped")
	assert_eq(bank.voices(), 12, "default voices")
	var empty: SoundBank = SoundBank.from_file("res://data/audio/does_not_exist.json")
	assert_false(empty.is_valid())
	assert_true(empty.kinds().is_empty())
