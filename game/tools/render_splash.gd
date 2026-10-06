extends SceneTree
## Renders the boot splash image from the loading screen's static frame, so the
## splash and the loading screen that follows it line up exactly. Needs a
## display (use xvfb-run):
##   xvfb-run -a godot --path game -s res://tools/render_splash.gd
## Writes res://assets/splash/boot_splash.png (square: the engine fits it to
## the screen width on a phone and fills the rest with the splash colour).

const OUT: String = "res://assets/splash/boot_splash.png"
const SIZE: int = 1080
const SETTLE_FRAMES: int = 4


func _initialize() -> void:
	_render.call_deferred()


func _render() -> void:
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var screen: LoadingScreen = LoadingScreen.new()
	screen.splash = true
	vp.add_child(screen)
	for _i: int in SETTLE_FRAMES:
		await process_frame
	var img: Image = vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err: Error = img.save_png(ProjectSettings.globalize_path(OUT))
	print("splash ", OUT, " ", img.get_size(), " err=", err)
	quit(0 if err == OK else 1)
