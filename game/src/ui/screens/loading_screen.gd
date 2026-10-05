class_name LoadingScreen
extends CanvasLayer
## The startup loading screen (ART_DIRECTION §10): the boot splash brought to
## life. At first it is the splash image exactly (the image is rendered from
## this screen by tools/render_splash.gd): the splash colour, a soft glow, the
## flux craft emblem and the wordmark, laid out in the centred square the
## splash image fills. Then speed streaks and the sink glow fade in, a progress
## bar and status appear, and once the language is known a gameplay tip. It
## covers the game while it boots and compiles its shaders, then fades away.

const LAYER: int = 100
const GLOW_CENTER: Vector2 = Vector2(0.5, 0.42)
## Emblem: centre (square space) and width as a share of the square's side.
const EMBLEM_CENTER: Vector2 = Vector2(0.5, 0.4)
const EMBLEM_WIDTH: float = 0.36
## Wordmark: top (square space) and cap height as a share of the side.
const WORDMARK_TOP: float = 0.6
const WORDMARK_SIZE: float = 0.105
const WORDMARK_TRACKING: float = 0.012
## Progress bar: top (square space), width share, thickness (px at 720 wide).
const BAR_TOP: float = 0.8
const BAR_WIDTH: float = 0.5
const BAR_THICKNESS: float = 6.0
## Shown progress eases towards the target at this rate (share per second).
const BAR_RATE: float = 2.6
## The animated layers fade in over this many seconds.
const REVEAL_TIME: float = 0.5
const FADE_OUT_TIME: float = 0.4
const TIP_KEYS: PackedStringArray = ["tip.timing", "tip.combo", "tip.near_miss", "tip.phase", "tip.dash", "tip.surge"]
const BG_SHADER: Shader = preload("res://assets/shaders/loading_bg.gdshader")
const HULL: Color = Color("#e8ecf2")
const HULL_SHADE: Color = Color("#b9c3d2")
const TRIM: Color = Color("#2a3140")

## Splash mode: the static frame the boot splash image is rendered from.
var splash: bool = false
var progress: float = 0.0
var shown_progress: float = 0.0
var root: Control
var status: Label
var tip: Label

var _bg: ColorRect
var _bg_mat: ShaderMaterial = ShaderMaterial.new()
var _art: Control
var _reveal: float = 0.0
var _time: float = 0.0
var _text_ready: bool = false
var _finishing: bool = false


func _ready() -> void:
	layer = LAYER
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Nothing behind reacts to touches while the game loads.
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_mat.shader = BG_SHADER
	_bg_mat.set_shader_parameter("base", ProjectSettings.get_setting("application/boot_splash/bg_color"))
	_bg_mat.set_shader_parameter("glow", Palette.PRIMARY)
	_bg_mat.set_shader_parameter("glow_center", GLOW_CENTER)
	_bg.material = _bg_mat
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bg)
	_art = Control.new()
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.draw.connect(_draw_art)
	root.add_child(_art)
	status = UiKit.text("", &"caption", UiTokens.TEXT_MUTED)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(status)
	tip = UiKit.text("", &"body", UiTokens.TEXT_MUTED)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(tip)
	root.resized.connect(_layout)
	_layout()


## Target progress 0..1 (the bar eases towards it; it never goes back).
func set_progress(value: float) -> void:
	progress = maxf(progress, clampf(value, 0.0, 1.0))


## Once the services are booted the language is known: the status line and a
## tip (chosen by [param seed]) appear in it.
func show_text(seed: int) -> void:
	_text_ready = true
	status.text = tr("boot.loading")
	tip.text = tr(TIP_KEYS[posmod(seed, TIP_KEYS.size())])


## Fills the bar, fades the screen out and frees it; await it.
func finish() -> void:
	if _finishing:
		return
	_finishing = true
	set_progress(1.0)
	shown_progress = 1.0
	status.text = tr("boot.ready") if _text_ready else ""
	_art.queue_redraw()
	var tween: Tween = create_tween()
	tween.tween_property(root, "modulate:a", 0.0, FADE_OUT_TIME).set_ease(Tween.EASE_IN)
	await tween.finished
	queue_free()


func _process(delta: float) -> void:
	if splash:
		return
	_time += delta
	_reveal = minf(1.0, _reveal + delta / REVEAL_TIME)
	_bg_mat.set_shader_parameter("reveal", _reveal)
	shown_progress = move_toward(shown_progress, progress, delta * BAR_RATE)
	var text_alpha: float = _reveal if _text_ready else 0.0
	status.modulate.a = text_alpha
	tip.modulate.a = text_alpha
	_art.queue_redraw()


func _layout() -> void:
	var size: Vector2 = root.size
	_bg_mat.set_shader_parameter("size", size)
	var side: float = minf(size.x, size.y)
	var top: float = (size.y - side) * 0.5
	status.position = Vector2(0.0, top + side * BAR_TOP + side * 0.03)
	status.size = Vector2(size.x, 32.0)
	var tip_w: float = minf(size.x - float(UiTokens.MARGIN) * 2.0, side * 0.8)
	tip.position = Vector2((size.x - tip_w) * 0.5, size.y - side * 0.22)
	tip.size = Vector2(tip_w, side * 0.16)
	status.visible = not splash
	tip.visible = not splash
	_art.queue_redraw()


## The square the boot splash image fills: origin and side.
func _square() -> Rect2:
	var size: Vector2 = root.size
	var side: float = minf(size.x, size.y)
	return Rect2(Vector2((size.x - side) * 0.5, (size.y - side) * 0.5), Vector2(side, side))


func _draw_art() -> void:
	var sq: Rect2 = _square()
	var side: float = sq.size.x
	var flicker: float = 0.0 if splash else sin(_time * 31.0) * 0.5 + sin(_time * 17.0) * 0.5
	_draw_craft(sq.position + EMBLEM_CENTER * side, side * EMBLEM_WIDTH * 0.5, flicker)
	_draw_wordmark(sq.position.y + WORDMARK_TOP * side, side)
	if not splash:
		_draw_bar(sq, side)


## The flux craft seen from above, nose up, engines and flames below: the same
## Glider the player flies. [param half] is half its wingspan in pixels.
func _draw_craft(c: Vector2, half: float, flicker: float) -> void:
	var k: float = half
	# Flames first (under the hull): white-hot to the form colour, fading out.
	for side: float in [-1.0, 1.0]:
		var n: Vector2 = c + Vector2(0.1 * side, 0.64) * k
		var length: float = (0.5 + 0.06 * flicker) * k
		var pts: PackedVector2Array = [
			n + Vector2(-0.055 * k, 0.0), n + Vector2(0.055 * k, 0.0), n + Vector2(0.0, length)
		]
		var cols: PackedColorArray = [
			Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.95), Palette.with_alpha(Palette.PRIMARY, 0.0)
		]
		_art.draw_polygon(pts, cols)
		_art.draw_circle(n, 0.12 * k, Palette.with_alpha(Palette.PRIMARY, 0.22))
	var wing: PackedVector2Array = [Vector2(-0.18, -0.2), Vector2(-0.95, 0.35), Vector2(-0.95, 0.5), Vector2(-0.2, 0.3)]
	var tail: PackedVector2Array = [
		Vector2(-0.15, 0.35), Vector2(-0.45, 0.62), Vector2(-0.45, 0.7), Vector2(-0.14, 0.56)
	]
	for side2: float in [-1.0, 1.0]:
		# The left half catches the light, the right half is a shade darker.
		var tone: Color = HULL if side2 < 0.0 else HULL_SHADE
		_fill(wing if side2 < 0.0 else _mirror(wing), c, k, tone)
		_fill(tail if side2 < 0.0 else _mirror(tail), c, k, tone)
		_art.draw_circle(c + Vector2(0.95 * side2, 0.42) * k, 0.035 * k, Palette.PRIMARY)
		_art.draw_circle(c + Vector2(0.1 * side2, 0.62) * k, 0.07 * k, TRIM)
		_art.draw_circle(c + Vector2(0.1 * side2, 0.63) * k, 0.045 * k, Palette.PRIMARY.lightened(0.5))
	var hull_l: PackedVector2Array = [
		Vector2(0.0, -0.95),
		Vector2(-0.13, -0.6),
		Vector2(-0.2, -0.1),
		Vector2(-0.2, 0.45),
		Vector2(-0.12, 0.62),
		Vector2(0.0, 0.62)
	]
	_fill(hull_l, c, k, HULL)
	_fill(_mirror(hull_l), c, k, HULL_SHADE)
	# Canopy: the energy core under glass.
	var canopy: PackedVector2Array = []
	for i: int in 20:
		var a: float = TAU * float(i) / 20.0
		canopy.append(c + Vector2(cos(a) * 0.085, sin(a) * 0.2 - 0.42) * k)
	_art.draw_colored_polygon(canopy, Palette.PRIMARY)
	_art.draw_polyline(_closed(canopy), Palette.PRIMARY.lightened(0.4), maxf(1.0, k * 0.012), true)
	_art.draw_circle(c + Vector2(-0.02, -0.48) * k, 0.03 * k, Color(1, 1, 1, 0.8))


## [param poly] mirrored left to right.
func _mirror(poly: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = []
	for p: Vector2 in poly:
		out.append(Vector2(-p.x, p.y))
	return out


func _fill(poly: PackedVector2Array, c: Vector2, k: float, color: Color) -> void:
	var pts: PackedVector2Array = []
	for p: Vector2 in poly:
		pts.append(c + p * k)
	_art.draw_colored_polygon(pts, color)
	# Antialiased edge (polygons themselves are not antialiased).
	_art.draw_polyline(_closed(pts), color, 1.2, true)


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = pts.duplicate()
	out.append(pts[0])
	return out


func _draw_wordmark(top: float, side: float) -> void:
	var font: Font = UiFonts.get_font(800)
	var font_size: int = int(side * WORDMARK_SIZE)
	var text: String = "FLUX DROP"
	var spacing: float = side * WORDMARK_TRACKING
	var width: float = 0.0
	for ch: String in text:
		width += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + spacing
	width -= spacing
	var x: float = (root.size.x - width) * 0.5
	var baseline: float = top + font.get_ascent(font_size)
	for ch2: String in text:
		_art.draw_string(font, Vector2(x, baseline), ch2, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiTokens.TEXT)
		x += font.get_string_size(ch2, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + spacing
	# A thin energy line under the wordmark.
	var line_y: float = baseline + side * 0.035
	var half: float = side * 0.09
	var mid: float = root.size.x * 0.5
	_art.draw_line(
		Vector2(mid - half, line_y), Vector2(mid + half, line_y), Palette.PRIMARY, maxf(2.0, side * 0.004), true
	)


func _draw_bar(sq: Rect2, side: float) -> void:
	var w: float = side * BAR_WIDTH
	var h: float = BAR_THICKNESS * side / 720.0
	var pos: Vector2 = Vector2(root.size.x * 0.5 - w * 0.5, sq.position.y + BAR_TOP * side)
	var alpha: float = _reveal
	_art.draw_rect(Rect2(pos, Vector2(w, h)), Palette.with_alpha(Palette.SLATE, alpha))
	var fill: float = w * shown_progress
	if fill > 0.5:
		_art.draw_rect(Rect2(pos, Vector2(fill, h)), Palette.with_alpha(Palette.PRIMARY, alpha))
		_art.draw_circle(
			pos + Vector2(fill, h * 0.5), h * 1.6, Palette.with_alpha(Palette.PRIMARY.lightened(0.5), alpha * 0.9)
		)
