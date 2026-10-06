extends TestCase
## Startup (player feedback: "we wait on a blank page"): the boot splash image
## shows while the engine starts, the loading screen continues it before any
## slow work, and it fades into the main menu once the game is built.

const BOOT_SCENE: PackedScene = preload("res://scenes/boot.tscn")
const FIXED_UNIX: int = 1790000000
## Frame cap while waiting for the menu (the loading screen stays >= 1.2 s).
const MAX_FRAMES: int = 2000

var _app: AppServices
var _boot: BootLoader


func before_each() -> void:
	_app = AppServices.new()
	_app.auto_boot = false
	tree.root.add_child(_app)
	_boot = BOOT_SCENE.instantiate() as BootLoader
	_boot.services = _app
	_boot.boot_storage = MemorySaveStorage.new()
	var clock: GameClock = GameClock.new()
	clock.set_fixed_unix(FIXED_UNIX)
	_boot.boot_clock = clock


func after_each() -> void:
	if is_instance_valid(_boot):
		_boot.queue_free()
	_app.queue_free()
	await wait_frames(2)


func test_the_loading_screen_is_up_before_anything_slow() -> void:
	tree.root.add_child(_boot)
	assert_true(_boot.loading != null and _boot.loading.is_inside_tree(), "on screen in the very first frame")
	assert_false(_app.is_booted, "the services are not booted yet")
	assert_true(_boot.flow == null, "nor is the game built")
	assert_gt(float(_boot.loading.layer), float(GameFlow.UI_LAYER), "it covers the game and its UI")
	assert_eq(_boot.loading.root.mouse_filter, Control.MOUSE_FILTER_STOP, "touches wait for the menu")
	await wait_frames(1)
	assert_false(_app.is_booted, "a frame is drawn before the boot starts")


func test_it_boots_builds_and_fades_into_the_menu() -> void:
	tree.root.add_child(_boot)
	var frames: int = 0
	var shown: float = 0.0
	var went_back: bool = false
	while not _boot.done and frames < MAX_FRAMES:
		await wait_frames(1)
		frames += 1
		if _boot.loading != null:
			went_back = went_back or _boot.loading.shown_progress < shown - 0.0001
			shown = _boot.loading.shown_progress
	assert_true(_boot.done, "the menu shows within the frame cap")
	assert_false(went_back, "the bar never goes back")
	assert_true(_app.is_booted)
	assert_true(_boot.flow != null and _boot.flow.get_parent() == _boot, "the game is built under the boot scene")
	assert_eq(_boot.flow.router.current_id, &"main", "the main menu is the first screen")
	assert_true(_boot.loading == null, "the loading screen is gone")
	assert_eq(_boot.get_children().filter(func(n: Node) -> bool: return n is LoadingScreen).size(), 0)


func test_the_text_is_in_the_players_language() -> void:
	tree.root.add_child(_boot)
	while not _app.is_booted:
		await wait_frames(1)
	var screen: LoadingScreen = _boot.loading
	assert_ne(screen.status.text, "boot.loading", "the status is translated")
	assert_true(LoadingScreen.TIP_KEYS.has(_tip_key(screen.tip.text)), "and the tip is one of the game's tips")


func test_the_splash_image_is_the_first_frame() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://scenes/boot.tscn")
	assert_true(bool(ProjectSettings.get_setting("application/boot_splash/show_image")))
	var image_path: String = str(ProjectSettings.get_setting("application/boot_splash/image"))
	assert_true(FileAccess.file_exists(image_path), "the splash image ships")
	var img: Image = Image.load_from_file(image_path)
	assert_eq(img.get_width(), img.get_height(), "square: the engine fits it to the phone's width")
	var bg: Color = ProjectSettings.get_setting("application/boot_splash/bg_color") as Color
	var corner: Color = img.get_pixel(2, 2)
	assert_near(corner.r, bg.r, 0.01, "its edge is the splash colour, so no seam shows")
	assert_near(corner.g, bg.g, 0.01)
	assert_near(corner.b, bg.b, 0.01)


func _tip_key(text: String) -> String:
	for key: String in LoadingScreen.TIP_KEYS:
		if TranslationServer.translate(key) == text:
			return key
	return ""
