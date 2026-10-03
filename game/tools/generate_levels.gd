extends SceneTree
## Regenerates campaign level data deterministically.
##
## godot --headless --path game -s res://tools/generate_levels.gd -- [--from=1] [--to=520]
##     [--out=res://data/levels] [--check]
## With --check nothing is written; the tool exits 1 if any committed file differs
## from freshly generated output (used by CI to prove data == generator).

const DEFAULT_OUT: String = "res://data/levels"


func _initialize() -> void:
	var from_n: int = 1
	var to_n: int = -1
	var out_dir: String = DEFAULT_OUT
	var check: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--from="):
			from_n = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--to="):
			to_n = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--out="):
			out_dir = arg.get_slice("=", 1)
		elif arg == "--check":
			check = true
	var catalog: WorldCatalog = WorldCatalog.load_default()
	var model: DifficultyModel = DifficultyModel.new(catalog)
	if to_n < 0:
		to_n = catalog.total_levels()
	var started: int = Time.get_ticks_msec()
	var failures: int = 0
	var mismatches: int = 0
	var manifest: Array = []
	for n: int in range(from_n, to_n + 1):
		var spec: LevelSpec = model.build_spec(n)
		var gen: LevelGenerator = LevelGenerator.new()
		var t0: int = Time.get_ticks_msec()
		var level: Dictionary = gen.generate(spec)
		var ms: int = Time.get_ticks_msec() - t0
		if level.is_empty():
			failures += 1
			printerr("FAILED %s: %s" % [spec.id, ", ".join(gen.errors)])
			continue
		var path: String = LevelRepository.level_path(out_dir, spec.world_index, spec.local_index)
		var text: String = JsonIO.canonical(level, "\t") + "\n"
		if check:
			var existing: String = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
			if existing != text:
				mismatches += 1
				printerr("MISMATCH %s" % path)
		else:
			var err: Error = JsonIO.write_atomic(ProjectSettings.globalize_path(path), text)
			if err != OK:
				failures += 1
				printerr("WRITE FAILED %s: %s" % [path, error_string(err)])
		manifest.append(spec.id)
		print(
			(
				"%s n=%d %s/%s %s dur=%.1fs slots=%d ents=%d taps=%d win=%.3f att=%d (%d ms)"
				% [
					spec.id,
					n,
					spec.tier,
					spec.kind,
					spec.chapter_phase,
					float(level["duration"]),
					int((level["spawn"] as Dictionary)["slots"]),
					(level["entities"] as Array).size(),
					((level["solution"] as Dictionary)["taps"] as Array).size(),
					float(level["min_tap_window"]),
					int((level["generator"] as Dictionary)["attempt"]),
					ms,
				]
			)
		)
	var secs: float = float(Time.get_ticks_msec() - started) / 1000.0
	print("generated %d levels in %.1fs, failures=%d mismatches=%d" % [manifest.size(), secs, failures, mismatches])
	quit(1 if failures > 0 or mismatches > 0 else 0)
