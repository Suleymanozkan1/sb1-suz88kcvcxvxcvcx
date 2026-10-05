class_name BootLoader
extends Node
## The game's first scene. It puts the [LoadingScreen] on screen at once (it
## continues the boot splash image), and only then does the slow work, a step
## per frame so the bar moves between them: boot the service graph, load and
## build the main scene ([GameFlow]: gameplay view, UI, the attract run), and
## let a few frames render under the cover so the first shaders compile there.
## Then the loading screen fades into the main menu. Before this the player
## waited on a blank screen for all of it.

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
## Frames rendered under the cover after the main scene is built (the attract
## run's materials compile in the first of them).
const WARMUP_FRAMES: int = 4
## The loading screen stays at least this long, so it never just flashes.
const MIN_SHOW: float = 1.2
## Progress after each step.
const STEP_SHOWN: float = 0.08
const STEP_BOOTED: float = 0.35
const STEP_LOADED: float = 0.55
const STEP_BUILT: float = 0.8

var services: AppServices
## Injected by tests (in-memory save, fixed clock); the game uses the defaults.
var boot_storage: SaveStorage = null
var boot_clock: GameClock = null
var loading: LoadingScreen
var flow: GameFlow
## True once the menu is showing (the loading screen has faded out).
var done: bool = false

var _started_ms: int = 0


func _ready() -> void:
	_started_ms = Time.get_ticks_msec()
	if services == null:
		services = get_node("/root/Services") as AppServices
	# The graph boots below, after the loading screen has been drawn.
	services.auto_boot = false
	loading = LoadingScreen.new()
	add_child(loading)
	_start_up.call_deferred()


func _start_up() -> void:
	await _frames(2)
	loading.set_progress(STEP_SHOWN)
	await _frames(1)
	if not services.is_booted:
		services.boot(boot_storage, boot_clock)
	loading.show_text(Time.get_ticks_usec())
	loading.set_progress(STEP_BOOTED)
	await _frames(1)
	var scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	loading.set_progress(STEP_LOADED)
	await _frames(1)
	flow = scene.instantiate() as GameFlow
	flow.s = services
	# Under the loading screen (its layer is above every game layer).
	add_child(flow)
	move_child(loading, get_child_count() - 1)
	loading.set_progress(STEP_BUILT)
	await _frames(WARMUP_FRAMES)
	var left: float = MIN_SHOW - float(Time.get_ticks_msec() - _started_ms) / 1000.0
	if left > 0.0:
		loading.set_progress(1.0)
		await get_tree().create_timer(left).timeout
	await loading.finish()
	loading = null
	done = true


func _frames(count: int) -> void:
	for _i: int in count:
		await get_tree().process_frame
