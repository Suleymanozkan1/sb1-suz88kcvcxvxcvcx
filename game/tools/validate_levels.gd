extends SceneTree
## Validates every campaign level file.
##
## godot --headless --path game -s res://tools/validate_levels.gd -- [--dir=res://data/levels]
##     [--from=1] [--to=520] [--solver] [--no-assets] [--report=<path.json>]
## Exits with code 1 if any level has an error.


func _initialize() -> void:
	var dir: String = LevelRepository.LEVEL_DIR
	var from_n: int = 1
	var to_n: int = -1
	var solver: bool = false
	var assets: bool = true
	var report_path: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			dir = arg.get_slice("=", 1)
		elif arg.begins_with("--from="):
			from_n = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--to="):
			to_n = arg.get_slice("=", 1).to_int()
		elif arg == "--solver":
			solver = true
		elif arg == "--no-assets":
			assets = false
		elif arg.begins_with("--report="):
			report_path = arg.get_slice("=", 1)
	var catalog: WorldCatalog = WorldCatalog.load_default()
	var repo: LevelRepository = LevelRepository.new(catalog, dir)
	var validator: LevelValidator = LevelValidator.new(catalog)
	validator.check_assets = assets
	validator.run_solver = solver
	if to_n < 0:
		to_n = catalog.total_levels()
	var started: int = Time.get_ticks_msec()
	var failed: int = 0
	var warned: int = 0
	var checked: int = 0
	var code_counts: Dictionary = {}
	var rows: Array = []
	var worst_window: float = INF
	for n: int in range(from_n, to_n + 1):
		var id: String = repo.level_id_for_number(n)
		var data: Dictionary = repo.load_level(id)
		checked += 1
		if data.is_empty():
			failed += 1
			code_counts["missing_asset"] = int(code_counts.get("missing_asset", 0)) + 1
			printerr("%s: level file missing or unreadable" % id)
			rows.append({"id": id, "ok": false, "errors": [{"code": "missing_asset", "message": "file missing"}]})
			continue
		var report: LevelValidator.Report = validator.validate(data)
		if not report.ok():
			failed += 1
			for e: Dictionary in report.errors:
				code_counts[e["code"]] = int(code_counts.get(e["code"], 0)) + 1
				printerr("%s: [%s] %s" % [id, e["code"], e["message"]])
		if not report.warnings.is_empty():
			warned += 1
			for w: Dictionary in report.warnings:
				print("%s: warning [%s] %s" % [id, w["code"], w["message"]])
		worst_window = minf(worst_window, float(report.stats.get("min_window", INF)))
		rows.append({"id": id, "ok": report.ok(), "errors": report.errors, "warnings": report.warnings, "stats": report.stats})
	var secs: float = float(Time.get_ticks_msec() - started) / 1000.0
	print(
		"validated %d levels in %.1fs: %d failed, %d with warnings, worst tap window %.0f ms"
		% [checked, secs, failed, warned, worst_window * 1000.0]
	)
	if not code_counts.is_empty():
		print("error codes: ", code_counts)
	if not report_path.is_empty():
		JsonIO.write_json(
			report_path,
			{"checked": checked, "failed": failed, "warned": warned, "codes": code_counts, "levels": rows}
		)
	quit(1 if failed > 0 else 0)
