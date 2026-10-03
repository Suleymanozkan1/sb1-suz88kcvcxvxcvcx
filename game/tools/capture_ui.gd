extends SceneTree
## Screenshots every screen of the real app (GameFlow + real services with an
## in-memory save) for visual review. Needs a display:
##   xvfb-run -a godot --path game --rendering-driver opengl3 --resolution 540x960 \
##       -s res://tools/capture_ui.gd -- --out=/tmp/ui [--locale=tr] [--progress]
## --progress seeds a mid-game profile (cleared levels, currency, unlocked
## modes) so populated states are reviewed too.

const SETTLE_FRAMES: int = 24

var _out: String = "user://ui_captures"
var _locale: String = "en"
var _seed_progress: bool = false
var _app: AppServices
var _flow: GameFlow


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--locale="):
			_locale = arg.get_slice("=", 1)
		elif arg == "--progress":
			_seed_progress = true
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_app = AppServices.new()
	_app.auto_boot = false
	root.add_child(_app)
	_app.boot(MemorySaveStorage.new())
	_app.settings.set_value("language", _locale)
	if _seed_progress:
		_seed()
	_flow = (load("res://scenes/main.tscn") as PackedScene).instantiate() as GameFlow
	_flow.s = _app
	root.add_child(_flow)
	await _settle(60)
	# Seeded progress queues level-up reveals on the menu; they are captured on
	# their own (13_reward), so the menu is shot without them.
	while _flow.router.has_overlay(&"reward"):
		_flow._next_reveal()
	await _settle(20)
	await _shot("01_main_menu")
	_flow._show_worlds()
	await _shot("02_world_select")
	_flow._show_levels("neon_core")
	await _shot("03_level_select")
	_flow._show_modes()
	await _shot("04_modes")
	_flow._show_daily()
	await _shot("05_daily")
	_flow._on_tab(&"progress")
	await _shot("06_progress")
	var progress: ProgressScreen = _flow.router.screen(&"progress") as ProgressScreen
	progress._tabs.select("achievements", true)
	await _shot("06b_progress_achievements")
	_flow._on_tab(&"shop")
	await _shot("07_shop")
	_flow._on_tab(&"collection")
	await _shot("08_collection")
	_flow._on_tab(&"settings")
	await _shot("09_settings")
	# Gameplay: HUD mid-run, then pause.
	var level_id: String = "w01_l12" if _seed_progress else "w01_l01"
	_flow._play_campaign(level_id, &"classic")
	_flow.session.lockstep = true
	_flow.session.autopilot = _solution(_flow.session.level_data)
	await _until(func() -> bool: return _flow.session.sim != null and _flow.session.sim.time() > 4.0, 900)
	await _shot("10_gameplay_hud")
	_flow._pause()
	await _shot("11_pause")
	_flow._resume()
	await _until(func() -> bool: return _flow.router.has_overlay(&"complete"), 4000)
	await _settle(20)
	await _shot("12_complete")
	await _until(func() -> bool: return _flow.router.has_overlay(&"reward"), 300)
	if _flow.router.has_overlay(&"reward"):
		await _settle(50)
		await _shot("13_reward")
		while _flow.router.has_overlay(&"reward"):
			_flow._next_reveal()
			await _settle(4)
	# Fail screen: replay with no input.
	_flow._restart()
	_flow.session.lockstep = true
	_flow.session.autopilot = PackedInt32Array([100000000])
	await _until(func() -> bool: return _flow.router.has_overlay(&"fail"), 4000)
	await _settle(40)
	await _shot("14_fail")
	print("ui captures written to ", _out)
	quit(0)


func _seed() -> void:
	var p: PlayerProfile = _app.profile
	for local: int in range(1, 31):
		var id: String = WorldCatalog.level_id(1, local)
		var stars: int = 3 if local % 4 != 0 else 2
		p.levels[id] = {
			"stars": stars, "best_score": 900 + local * 37, "perfect": stars == 3, "clears": 1, "attempts": 2
		}
	p.stats["unique_levels_cleared"] = 30
	p.stats["levels_cleared"] = 34
	p.stats["unique_perfects"] = 22
	p.stats["perfects"] = 22
	p.stats["runs_played"] = 61
	p.stats["sparks_collected"] = 2480
	p.stats["max_combo"] = 46
	p.stats["near_misses"] = 133
	p.stats["time_played_seconds"] = 4210
	_app.economy.grant(EconomyService.COINS, 1150, "capture_fixture")
	_app.economy.grant(EconomyService.GEMS, 12, "capture_fixture")
	_app.progression.add_xp(2600)
	_app.achievements.evaluate()


func _solution(data: Dictionary) -> PackedInt32Array:
	var taps: PackedInt32Array = PackedInt32Array()
	for t: Variant in (data.get("solution", {}) as Dictionary).get("taps", []) as Array:
		taps.append(int(t))
	return taps


func _settle(frames: int = SETTLE_FRAMES) -> void:
	for _i: int in frames:
		await process_frame


func _until(cond: Callable, max_frames: int) -> void:
	for _i: int in max_frames:
		if bool(cond.call()):
			return
		await process_frame


func _shot(label: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(label + ".png"))
	print("captured ", label)
