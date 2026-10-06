extends SceneTree
## Renders a level with the autopilot (stored solution) and saves screenshots.
## Needs a display (use xvfb-run):
##   xvfb-run -a godot --path game --rendering-driver opengl3 --resolution 540x960 \
##       -s res://tools/capture_level.gd -- --level=w01_l05 --out=/tmp/shots --at=1.5,4,7 [--stop] [--fail]
## --stop quits after the last --at shot instead of playing the level to its end.
## --quality=<low|medium|high|ultra> applies that preset's view settings.
## --closeup frames the core from close by (a camera riding with it) to judge
## the character's detail.

var _session: GameplaySession
var _view: GameplayView
var _taps: PackedInt32Array = PackedInt32Array()
var _shots: PackedFloat64Array = PackedFloat64Array()
var _out: String = "user://captures"
var _level_id: String = "w01_l01"
var _shot_index: int = 0
var _frames: int = 0
var _done: bool = false
var _fail_on_purpose: bool = false
var _stop_after_shots: bool = false
var _quality: String = ""
var _closeup: bool = false


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			_level_id = arg.get_slice("=", 1)
		elif arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--at="):
			for s: String in arg.get_slice("=", 1).split(","):
				_shots.append(s.to_float())
		elif arg.begins_with("--quality="):
			_quality = arg.get_slice("=", 1)
		elif arg == "--stop":
			_stop_after_shots = true
		elif arg == "--fail":
			_fail_on_purpose = true
		elif arg == "--closeup":
			_closeup = true
	if _shots.is_empty():
		_shots = PackedFloat64Array([1.0, 3.0, 6.0])
	DirAccess.make_dir_recursive_absolute(_out)
	_setup.call_deferred()


func _setup() -> void:
	var repo: LevelRepository = LevelRepository.new()
	var data: Dictionary = repo.load_level(_level_id)
	if data.is_empty():
		printerr("level not found: ", _level_id)
		quit(1)
		return
	var catalog: WorldCatalog = WorldCatalog.load_default()
	_view = GameplayView.new()
	root.add_child(_view)
	_session = GameplaySession.new()
	root.add_child(_session)
	_session.load_level(data)
	_view.bind(_session)
	_view.apply_world(WorldTheme.from_world(catalog.world(str(data["world"]))))
	_view.setup_level()
	if not _quality.is_empty():
		var presets: Dictionary = JsonIO.read_dict("res://data/quality/presets.json").get("presets", {}) as Dictionary
		var p: Dictionary = presets.get(_quality, {}) as Dictionary
		_view.set_quality(
			bool(p.get("post_fx", true)),
			float(p.get("particle_scale", 1.0)),
			int(p.get("trail_points", 18)),
			bool(p.get("dynamic_light", true)),
			bool(p.get("shadows", true)),
			bool(p.get("glow", true)),
			bool(p.get("ambient_particles", true)),
			bool(p.get("reflections", false)),
			bool(p.get("fine_glass", true))
		)
		_view.set_quality_extras(bool(p.get("cinematic", false)), int(p.get("shadow_quality", 1)))
	if _closeup:
		var cam: Camera3D = Camera3D.new()
		cam.fov = 34.0
		_view.core_view.add_child(cam)
		var eye: Vector3 = Vector3(1.5, 1.0, 3.1)
		cam.transform = Transform3D(Basis.looking_at(Vector3(0.0, 0.02, 0.0) - eye), eye)
		cam.make_current()
	if not _fail_on_purpose:
		for t: Variant in (data["solution"] as Dictionary)["taps"] as Array:
			_taps.append(int(t))
	else:
		_taps.append(1000000)
	_session.autopilot = _taps
	_session.lockstep = true
	_session.begin(0.0)
	_session.run_ended.connect(_on_end)


func _process(_delta: float) -> bool:
	if _done or _session == null or _session.sim == null:
		return true
	_frames += 1
	if _shot_index < _shots.size() and _session.sim.time() >= _shots[_shot_index]:
		_capture("t%05.1f" % _shots[_shot_index])
		_shot_index += 1
	var shots_done: bool = _shot_index >= _shots.size()
	if shots_done and (_stop_after_shots or _session.phase == GameplaySession.Phase.ENDED):
		_done = true
		quit(0)
	if _frames > 60 * 200:
		quit(0)
	return false


func _capture(label: String) -> void:
	var img: Image = root.get_viewport().get_texture().get_image()
	var path: String = _out.path_join("%s_%s.png" % [_level_id, label])
	img.save_png(path)
	print("captured ", path, " d=", snappedf(_session.sim.d, 0.1), " score=", _session.sim.score)


func _on_end(result: RunResult) -> void:
	print("run ended completed=", result.completed, " score=", result.score, " stars=", result.stars)
	# Let the end effects play for a moment and capture them.
	for _i: int in 20:
		await process_frame
	_capture("end")
	_done = true
	quit(0)
