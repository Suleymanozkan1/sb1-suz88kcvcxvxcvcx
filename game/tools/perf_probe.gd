extends SceneTree
## Performance probe (REQ-205 memory, REQ-210 draw calls). Plays real levels
## through the app itself (isolated services, the main scene, the quality
## preset set through the settings path the Settings screen uses) and samples
## what the engine reports at each level's busiest moment: draw calls,
## primitives and objects per frame, node count, static and video memory. Frame
## time is recorded but never budgeted: a software renderer under Xvfb says
## nothing about a phone. Budgets: res://data/quality/budgets.json.
## Needs a display (use xvfb-run; the project's Mobile renderer needs a Vulkan
## driver, e.g. Mesa's lavapipe, or Godot falls back to OpenGL):
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path game -s res://tools/perf_probe.gd --
##       [--worlds=all|w01,w05] [--presets=low,medium,high,ultra] [--levels=20,52] [--frames=30]
##       [--report=<path.json>] [--check]
## Each world is probed on a mid-world level and its boss (--levels, local
## indices). Without --worlds only [constant DEFAULT_WORLDS] run (CI speed);
## --worlds=all is the full matrix the budgets come from. --frames sets how
## many frames are sampled. --check exits with code 1 when any run exceeds a
## budget.

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const FIXED_UNIX: int = 1790000000
const DEFAULT_LEVELS: PackedInt32Array = [20, 52]
## The worlds that set every per-preset maximum in the full matrix
## (docs/ARCHITECTURE.md §9): the default, CI-sized run.
const DEFAULT_WORLDS: PackedInt32Array = [5, 8, 10]
## Window size: draw calls, primitives, objects and nodes do not depend on it,
## and a small one keeps software rendering fast.
const WINDOW_SIZE: Vector2i = Vector2i(360, 640)
const SETTLE_FRAMES: int = 3
## Frames played (lockstep: one tick each) after the seek, before sampling,
## so the trail, bursts and pooled hazards are in their steady state.
const WARMUP_FRAMES: int = 20
const DEFAULT_SAMPLE_FRAMES: int = 30
const TEARDOWN_FRAMES: int = 3
const MAX_READY_FRAMES: int = 600
## Distance kept free before the finish so the run is still on during sampling.
const END_MARGIN: float = 8.0
const PERCENTILE: float = 0.95
const USEC_PER_MS: float = 1000.0
const RENDERER_NOTE: String = "budgets were measured on the '%s' renderer; this run uses '%s' (not comparable)"

var _worlds: PackedInt32Array = DEFAULT_WORLDS
var _all_worlds: bool = false
var _levels: PackedInt32Array = DEFAULT_LEVELS
var _presets: Array[StringName] = QualityService.PRESET_ORDER.duplicate()
var _report_path: String = ""
var _check: bool = false
var _sample_frames: int = DEFAULT_SAMPLE_FRAMES
var _budgets: PerfBudgets
var _budget_doc: Dictionary = {}
var _frame_usec: PackedInt64Array = PackedInt64Array()
var _last_draw_usec: int = 0


func _initialize() -> void:
	var problem: String = _parse_args()
	if not problem.is_empty():
		printerr(problem)
		quit(2)
		return
	DisplayServer.window_set_size(WINDOW_SIZE)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_budget_doc = JsonIO.read_dict(PerfBudgets.DEFAULT_PATH)
	_budgets = PerfBudgets.new(_budget_doc)
	_run.call_deferred()


func _parse_args() -> String:
	for arg: String in OS.get_cmdline_user_args():
		var value: String = arg.get_slice("=", 1)
		if arg.begins_with("--worlds="):
			_all_worlds = value == "all"
			_worlds = PackedInt32Array() if _all_worlds else _parse_worlds(value)
			if not _all_worlds and _worlds.is_empty():
				return "--worlds needs 'all' or ids like w01,w05"
		elif arg.begins_with("--presets="):
			var asked: PackedStringArray = value.split(",", false)
			for p: String in asked:
				if not QualityService.PRESET_ORDER.has(StringName(p)):
					return "unknown preset '%s'" % p
			# Always lowest first (see _run).
			_presets = QualityService.PRESET_ORDER.filter(func(p: StringName) -> bool: return asked.has(String(p)))
		elif arg.begins_with("--levels="):
			_levels = PackedInt32Array()
			for n: String in value.split(",", false):
				_levels.append(n.to_int())
		elif arg.begins_with("--report="):
			_report_path = value
		elif arg.begins_with("--frames="):
			_sample_frames = maxi(2, value.to_int())
		elif arg == "--check":
			_check = true
	return ""


static func _parse_worlds(value: String) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for w: String in value.split(",", false):
		var n: int = w.trim_prefix("w").to_int()
		if n > 0:
			out.append(n)
	return out


func _run() -> void:
	var catalog: WorldCatalog = WorldCatalog.load_default()
	if _all_worlds:
		for w: int in range(1, catalog.world_count() + 1):
			_worlds.append(w)
	var renderer: Dictionary = _renderer_info()
	print("perf probe: %s / %s on %s" % [renderer["method"], renderer["driver"], renderer["adapter"]])
	var expected: String = str(_budget_doc.get("renderer", ""))
	var mismatch: bool = not expected.is_empty() and expected != str(renderer["method"])
	if mismatch:
		print("NOTE: ", RENDERER_NOTE % [expected, renderer["method"]])
	var started: int = Time.get_ticks_msec()
	var runs: Array[Dictionary] = []
	var failures: PackedStringArray = PackedStringArray()
	print(
		(
			"%-8s %-6s %6s %8s %6s %6s %9s %9s %8s %7s"
			% ["level", "preset", "draws", "prims", "objs", "nodes", "static_mb", "video_mb", "frame_ms", "p95_ms"]
		)
	)
	# Presets run from the lowest up: GPU allocations a richer preset makes (the
	# reflection atlas, MSAA targets) stay for the rest of the process, as they
	# would in the game, so they must not be charged to a lower preset.
	for preset: StringName in _presets:
		for w: int in _worlds:
			for local: int in _levels:
				var row: Dictionary = await _measure(WorldCatalog.level_id(w, local), preset)
				if row.has("error"):
					failures.append(str(row["error"]))
					printerr(row["error"])
					continue
				runs.append(row)
				_print_row(row)
	var violations: PackedStringArray = _summarise(runs)
	print("probed %d runs in %.1fs" % [runs.size(), float(Time.get_ticks_msec() - started) / 1000.0])
	if not _report_path.is_empty():
		_write_report(renderer, runs, violations, failures)
	for v: String in violations:
		print("OVER BUDGET: ", v)
	var failed: bool = not failures.is_empty() or (_check and not violations.is_empty())
	if _check and mismatch:
		# Counts from another renderer cannot pass or fail these budgets: a CI
		# fallback to OpenGL must be loud, not a silent pass.
		printerr("RENDERER MISMATCH: ", RENDERER_NOTE % [expected, renderer["method"]])
		failed = true
	quit(1 if failed else 0)


## Boots a fresh, isolated app, plays [param level_id] on [param preset] to its
## busiest moment and samples [member _sample_frames] frames.
func _measure(level_id: String, preset: StringName) -> Dictionary:
	var app: AppServices = AppServices.new()
	app.auto_boot = false
	root.add_child(app)
	var clock: GameClock = GameClock.new()
	clock.set_fixed_unix(FIXED_UNIX)
	app.boot(MemorySaveStorage.new(), clock)
	# The Settings screen's path: settings -> QualityService -> quality_changed
	# -> viewport (render scale, MSAA, fps cap) and GameFlow -> view. Chosen
	# before the game first draws, as a saved choice would be: auto now starts
	# on Ultra, and buffers it allocated would otherwise count against the
	# lower presets.
	app.settings.set_value("quality", String(preset))
	var flow: GameFlow = (load(MAIN_SCENE_PATH) as PackedScene).instantiate() as GameFlow
	flow.s = app
	root.add_child(flow)
	await _frames(SETTLE_FRAMES)
	var row: Dictionary = await _play(flow, level_id)
	row["preset"] = String(preset)
	row["applied_preset"] = String(app.quality.effective_preset())
	if not row.has("error") and row["applied_preset"] != row["preset"]:
		row["error"] = "%s: preset %s was applied as %s" % [level_id, preset, row["applied_preset"]]
	flow.queue_free()
	app.queue_free()
	await _frames(TEARDOWN_FRAMES)
	return row


func _play(flow: GameFlow, level_id: String) -> Dictionary:
	flow._start_run(&"classic", level_id)
	var session: GameplaySession = flow.session
	if session.sim == null or str(session.level_data.get("id", "")) != level_id:
		return {"level": level_id, "error": "%s: level did not start" % level_id}
	var taps: PackedInt32Array = PackedInt32Array()
	for t: Variant in (session.level_data.get("solution", {}) as Dictionary).get("taps", []) as Array:
		taps.append(int(t))
	# The stored solution plays (player input is ignored), one tick per frame.
	session.autopilot = taps
	session.lockstep = true
	# The READY beat plays in real time: the camera's level-start reveal is over
	# when the run starts, as in the game.
	var waited: int = 0
	while session.phase == GameplaySession.Phase.READY and waited < MAX_READY_FRAMES:
		await process_frame
		waited += 1
	var at_d: float = _seek(session, taps)
	# Uncapped while sampling: the frame time is the frame's cost, not the cap.
	Engine.max_fps = 0
	await _frames(WARMUP_FRAMES)
	var row: Dictionary = await _sample()
	row["level"] = level_id
	row["at_d"] = snappedf(at_d, 0.1)
	row["running"] = session.is_running()
	return row


## Steps the run (stored solution, no frames) to just before its busiest
## stretch, so the sampled frames are centred on it. Returns the target distance.
func _seek(session: GameplaySession, taps: PackedInt32Array) -> float:
	var lvl: SimLevel = session.sim_level
	var top_speed: float = lvl.base_speed * (1.0 + maxf(0.0, lvl.speed_ramp))
	var played: float = float(WARMUP_FRAMES + _sample_frames) * SimConst.DT * top_speed
	var latest: float = maxf(0.0, lvl.length - played - END_MARGIN)
	var target: float = PerfBudgets.busiest_view_distance(
		lvl, GameplayView.VIEW_AHEAD, GameplayView.VIEW_BEHIND, latest
	)
	var lead: float = float(WARMUP_FRAMES + _sample_frames / 2) * SimConst.DT * top_speed
	while session.sim.is_running() and session.sim.d < target - lead:
		session.step_ticks(1, taps)
	return target


## Max draw calls / primitives / objects / nodes over the sampled frames,
## memory after the last one, frame time mean and 95th percentile.
func _sample() -> Dictionary:
	var peak: Dictionary = {}
	for metric: String in PerfBudgets.METRICS:
		peak[metric] = 0.0
	_frame_usec.clear()
	_last_draw_usec = Time.get_ticks_usec()
	for _i: int in _sample_frames:
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		_frame_usec.append(now - _last_draw_usec)
		_last_draw_usec = now
		_peak(peak, PerfBudgets.DRAW_CALLS, RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		_peak(peak, PerfBudgets.PRIMITIVES, RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		_peak(peak, PerfBudgets.OBJECTS, RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		peak[PerfBudgets.NODES] = maxf(
			float(peak[PerfBudgets.NODES]), float(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		)
	peak[PerfBudgets.STATIC_MEMORY_MB] = snappedf(
		Performance.get_monitor(Performance.MEMORY_STATIC) / PerfBudgets.BYTES_PER_MB, 0.1
	)
	peak[PerfBudgets.VIDEO_MEMORY_MB] = snappedf(
		(
			float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED))
			/ PerfBudgets.BYTES_PER_MB
		),
		0.1
	)
	var row: Dictionary = {}
	for metric: String in PerfBudgets.METRICS:
		var v: float = float(peak[metric])
		row[metric] = v if metric.ends_with("_mb") else int(v)
	# The first sample spans the warmup's last frame boundary: skip it.
	var times: PackedInt64Array = _frame_usec.slice(1)
	row["frame_ms_mean"] = snappedf(_mean(times) / USEC_PER_MS, 0.01)
	row["frame_ms_p95"] = snappedf(_percentile(times, PERCENTILE) / USEC_PER_MS, 0.01)
	return row


static func _peak(peak: Dictionary, metric: String, info: RenderingServer.RenderingInfo) -> void:
	peak[metric] = maxf(float(peak[metric]), float(RenderingServer.get_rendering_info(info)))


static func _mean(values: PackedInt64Array) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for v: int in values:
		total += float(v)
	return total / float(values.size())


static func _percentile(values: PackedInt64Array, q: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedInt64Array = values.duplicate()
	sorted.sort()
	return float(sorted[clampi(ceili(q * float(sorted.size())) - 1, 0, sorted.size() - 1)])


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame


func _renderer_info() -> Dictionary:
	return {
		"method": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"godot": Engine.get_version_info()["string"],
		"window": [WINDOW_SIZE.x, WINDOW_SIZE.y],
	}


func _print_row(row: Dictionary) -> void:
	var line: String = "%-8s %-6s" % [row["level"], row["preset"]]
	line += (
		" %6d %8d %6d %6d %9.1f %9.1f"
		% [
			row[PerfBudgets.DRAW_CALLS],
			row[PerfBudgets.PRIMITIVES],
			row[PerfBudgets.OBJECTS],
			row[PerfBudgets.NODES],
			row[PerfBudgets.STATIC_MEMORY_MB],
			row[PerfBudgets.VIDEO_MEMORY_MB],
		]
	)
	line += " %8.1f %7.1f" % [row["frame_ms_mean"], row["frame_ms_p95"]]
	if not bool(row["running"]):
		line += "  (run not running while sampled)"
	print(line)


## Prints the per-preset worst case against the budgets; returns every violation.
func _summarise(runs: Array[Dictionary]) -> PackedStringArray:
	var violations: PackedStringArray = PackedStringArray()
	print("")
	print(
		(
			"%-15s %6s %8s %6s %6s %9s %9s  most draws"
			% ["preset (max)", "draws", "prims", "objs", "nodes", "static_mb", "video_mb"]
		)
	)
	for preset: StringName in _presets:
		var worst: Dictionary = _worst(runs, preset)
		if worst.is_empty():
			continue
		var budgets: Dictionary = _budgets.budgets_for(preset)
		var line: String = "%-15s" % String(preset)
		var limits: String = "%-15s" % "  budget"
		for metric: String in PerfBudgets.METRICS:
			var width: int = 8 if metric == PerfBudgets.PRIMITIVES else (9 if metric.ends_with("_mb") else 6)
			line += " %*s" % [width, _cell(worst[metric])]
			limits += " %*s" % [width, _cell(budgets.get(metric, "-"))]
		print(line, "  ", (worst["levels"] as Dictionary)[PerfBudgets.DRAW_CALLS])
		print(limits)
		for row: Dictionary in runs:
			if row["preset"] == String(preset):
				for v: String in _budgets.violations(preset, row):
					violations.append("%s: %s" % [row["level"], v])
	return violations


static func _cell(v: Variant) -> String:
	if typeof(v) == TYPE_FLOAT and is_equal_approx(float(v), roundf(float(v))):
		return str(int(v))
	return str(v)


## Max of every metric over the runs of [param preset], with the level that set each.
static func _worst(runs: Array[Dictionary], preset: StringName) -> Dictionary:
	var worst: Dictionary = {}
	var by: Dictionary = {}
	for row: Dictionary in runs:
		if row["preset"] != String(preset):
			continue
		for metric: String in PerfBudgets.METRICS:
			if not worst.has(metric) or float(row[metric]) > float(worst[metric]):
				worst[metric] = row[metric]
				by[metric] = row["level"]
	if not worst.is_empty():
		worst["levels"] = by
	return worst


func _write_report(
	renderer: Dictionary, runs: Array[Dictionary], violations: PackedStringArray, failures: PackedStringArray
) -> void:
	var worst: Dictionary = {}
	var budgets: Dictionary = {}
	for preset: StringName in _presets:
		worst[String(preset)] = _worst(runs, preset)
		budgets[String(preset)] = _budgets.budgets_for(preset)
	var report: Dictionary = {
		"renderer": renderer,
		"frames": {"warmup": WARMUP_FRAMES, "sample": _sample_frames},
		"runs": runs,
		"worst": worst,
		"budgets": budgets,
		"violations": violations,
		"failures": failures,
	}
	var err: Error = JsonIO.write_json(_report_path, report)
	if err != OK:
		printerr("could not write %s: %s" % [_report_path, error_string(err)])
	else:
		print("report: ", _report_path)
