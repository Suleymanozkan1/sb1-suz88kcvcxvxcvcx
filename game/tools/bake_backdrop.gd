extends SceneTree
## Bakes a world's painted backdrop offline (ART_DIRECTION §6): renders the
## world's scene shader (tools/backdrops/<name>.gdshader, a path-traced-style
## raymarch far too heavy for a phone) tile by tile into one image, scales it
## down with Lanczos (anti-aliasing) and saves the JPG the sky shader maps over
## the view (art.sky.backdrop). Needs a display (use xvfb-run):
##   xvfb-run -a godot --path game -s res://tools/bake_backdrop.gd -- --scene=crystal_valley \
##       [--size=2048x1365] [--out-size=1536x1024] [--out=res://assets/backdrops/crystal_valley.jpg] \
##       [--rect=31.5,-12,28]
## The view window must match the world JSON's backdrop: --rect is az_half,
## el_bottom, el_top in degrees. The default frames the band of sky the game's
## camera actually shows above the course (about -10° to +21°, a margin above
## for the start reveal and launch pads).

const TILE: int = 256

var _scene: String = ""
var _size: Vector2i = Vector2i(2048, 1365)
var _out_size: Vector2i = Vector2i(1536, 1024)
var _out: String = ""
var _rect: Vector3 = Vector3(31.5, -12.0, 28.0)


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			_scene = arg.get_slice("=", 1)
		elif arg.begins_with("--size="):
			_size = _parse_size(arg.get_slice("=", 1))
		elif arg.begins_with("--out-size="):
			_out_size = _parse_size(arg.get_slice("=", 1))
		elif arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--rect="):
			var parts: PackedStringArray = arg.get_slice("=", 1).split(",")
			_rect = Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
	if _out.is_empty():
		_out = "res://assets/backdrops/%s.jpg" % _scene
	_bake.call_deferred()


## "2048" (square) or "2048x1365".
func _parse_size(text: String) -> Vector2i:
	if text.contains("x"):
		return Vector2i(text.get_slice("x", 0).to_int(), text.get_slice("x", 1).to_int())
	return Vector2i(text.to_int(), text.to_int())


func _bake() -> void:
	var shader: Shader = load("res://tools/backdrops/%s.gdshader" % _scene) as Shader
	if shader == null:
		printerr("no scene shader: ", _scene)
		quit(1)
		return
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(TILE, TILE)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.disable_3d = true
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("full_size", Vector2(_size))
	mat.set_shader_parameter("tile_size", Vector2(TILE, TILE))
	mat.set_shader_parameter("view_rect", Vector3(deg_to_rad(_rect.x), deg_to_rad(_rect.y), deg_to_rad(_rect.z)))
	var rect: ColorRect = ColorRect.new()
	rect.size = Vector2(TILE, TILE)
	rect.material = mat
	vp.add_child(rect)
	root.add_child(vp)
	var full: Image = Image.create(_size.x, _size.y, false, Image.FORMAT_RGB8)
	var tiles: Vector2i = Vector2i(ceili(float(_size.x) / TILE), ceili(float(_size.y) / TILE))
	var started: int = Time.get_ticks_msec()
	for ty: int in tiles.y:
		for tx: int in tiles.x:
			mat.set_shader_parameter("tile_origin", Vector2(tx * TILE, ty * TILE))
			await process_frame
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img: Image = vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			full.blit_rect(img, Rect2i(0, 0, TILE, TILE), Vector2i(tx * TILE, ty * TILE))
		print("row %d/%d  %.1f s" % [ty + 1, tiles.y, (Time.get_ticks_msec() - started) / 1000.0])
	if _out_size != _size:
		full.resize(_out_size.x, _out_size.y, Image.INTERPOLATE_LANCZOS)
	var path: String = ProjectSettings.globalize_path(_out) if _out.begins_with("res://") else _out
	var err: Error = full.save_jpg(path, 0.92) if path.ends_with(".jpg") else full.save_png(path)
	print("saved %s (%s)" % [path, error_string(err)])
	quit(0 if err == OK else 1)
