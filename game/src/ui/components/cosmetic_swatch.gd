class_name CosmeticSwatch
extends Control
## Flat, consistent preview of a cosmetic. Every category is drawn with the same
## grammar as the icon system (24-unit grid, 2-unit round strokes, the item's
## own colours on a graphite field) so the grid reads as one family. Avatars and
## badges are geometric symbols — never faces or mascots.

const STROKE_UNITS: float = 2.0
const GRID: float = 24.0

var category: String = ""
var params: Dictionary = {}
var owned: bool = true
var _u: float = 1.0
var _dim: float = 1.0


func setup(cat: String, item_params: Dictionary, is_owned: bool) -> void:
	category = cat
	params = item_params
	owned = is_owned
	queue_redraw()


func _c(key: String, fallback: Color) -> Color:
	var v: Variant = params.get(key, null)
	var col: Color = fallback
	if typeof(v) == TYPE_COLOR:
		col = v as Color
	elif typeof(v) == TYPE_STRING and Color.html_is_valid(str(v)):
		col = Color(str(v))
	return Color(col.r, col.g, col.b, col.a * _dim)


func _w() -> float:
	return maxf(1.5, STROKE_UNITS * _u)


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var side: float = minf(size.x, size.y)
	_u = side / (GRID * 1.6)
	_dim = 1.0 if owned else 0.45
	var r: float = side * 0.3
	match category:
		"core_skin":
			_draw_core(c, r)
		"trail":
			_draw_trail(c, r)
		"particle":
			_draw_particle(c, r)
		"background":
			_draw_background(c, r)
		"theme":
			_draw_theme(c, r)
		"effect":
			_draw_effect(c, r)
		"badge":
			_draw_badge(c, r)
		"frame":
			_draw_frame(c, r)
		"avatar":
			_draw_avatar(c, r)
		_:
			draw_circle(c, r, _c("color", Palette.PRIMARY), true, -1.0, true)


func _draw_core(c: Vector2, r: float) -> void:
	draw_circle(c, r, _c("color_a", Palette.PRIMARY), true, -1.0, true)
	draw_arc(c, r * 0.62, 0.0, TAU, 40, _c("color_b", Palette.SECONDARY), _w(), true)
	var rim: Color = _c("rim", Palette.BONE)
	draw_arc(c, r + _w() * 1.5, 0.0, TAU, 48, Color(rim, rim.a * 0.45), _w(), true)


func _draw_trail(c: Vector2, r: float) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for k: int in 24:
		var t: float = float(k) / 23.0
		pts.append(c + Vector2(lerpf(-r * 1.3, r * 1.3, t), sin(t * PI * 1.5) * r * 0.4))
	draw_polyline(pts, _c("tail", Palette.SECONDARY), _w() * 3.0, true)
	draw_polyline(pts, _c("head", Palette.PRIMARY), _w(), true)
	draw_circle(pts[pts.size() - 1], _w() * 2.2, _c("head", Palette.PRIMARY), true, -1.0, true)


func _draw_particle(c: Vector2, r: float) -> void:
	var colors: Array = params.get("colors", []) as Array
	var dot_scale: float = clampf(float(params.get("size_mult", 1.0)), 0.5, 1.6)
	var count: int = clampi(int(round(7.0 * float(params.get("count_mult", 1.0)))), 5, 11)
	for k: int in count:
		var ang: float = TAU * float(k) / float(count)
		var col: Color = Palette.PRIMARY
		if not colors.is_empty() and typeof(colors[k % colors.size()]) == TYPE_COLOR:
			col = colors[k % colors.size()] as Color
		var dist: float = r * (0.7 if k % 2 == 0 else 1.0)
		var pos: Vector2 = c + Vector2(cos(ang), sin(ang)) * dist
		draw_circle(pos, _u * 2.4 * dot_scale, Color(col, col.a * _dim), true, -1.0, true)
	draw_circle(c, _u * 2.0, Palette.with_alpha(Palette.BONE, _dim), true, -1.0, true)


func _draw_background(c: Vector2, r: float) -> void:
	var rect: Rect2 = Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
	var top: Color = _c("sky_top", Palette.GRAPHITE)
	var bottom: Color = _c("sky_bottom", Palette.SLATE)
	var bands: int = 8
	for i: int in bands:
		var t: float = float(i) / float(bands - 1)
		var band_pos: Vector2 = rect.position + Vector2(0, rect.size.y * float(i) / float(bands))
		draw_rect(Rect2(band_pos, Vector2(rect.size.x, rect.size.y / float(bands) + 1.0)), top.lerp(bottom, t))
	var density: float = clampf(float(params.get("star_density", 0.0)), 0.0, 1.0)
	var stars: int = int(round(density * 9.0))
	for k: int in stars:
		var h: float = float((k * 37 + 11) % 97) / 97.0
		var v: float = float((k * 53 + 29) % 89) / 89.0
		draw_circle(
			rect.position + Vector2(h, v * 0.6) * rect.size, _u * 0.9, Palette.with_alpha(Palette.BONE, 0.8 * _dim)
		)
	if bool(params.get("use_world_palette", false)):
		draw_rect(rect, Palette.with_alpha(Palette.BONE, 0.5 * _dim), false, _w())


func _draw_theme(c: Vector2, r: float) -> void:
	var panel: Rect2 = Rect2(c - Vector2(r, r * 0.8), Vector2(r * 2.0, r * 1.6))
	draw_rect(panel, _c("panel_tint", Palette.GRAPHITE))
	draw_rect(panel, Palette.with_alpha(Palette.SLATE, _dim), false, maxf(1.0, _u))
	draw_rect(
		Rect2(panel.position + Vector2(r * 0.2, r * 0.25), Vector2(r * 1.6, r * 0.32)), _c("accent", Palette.PRIMARY)
	)
	draw_rect(
		Rect2(panel.position + Vector2(r * 0.2, r * 0.75), Vector2(r * 1.0, r * 0.22)),
		_c("accent_2", Palette.SECONDARY)
	)
	draw_rect(
		Rect2(panel.position + Vector2(r * 0.2, r * 1.12), Vector2(r * 0.7, r * 0.16)),
		Palette.with_alpha(Palette.FOG, _dim)
	)


func _draw_effect(c: Vector2, r: float) -> void:
	var shock: float = clampf(float(params.get("shockwave", 0.5)), 0.0, 1.0)
	draw_arc(c, r, 0.0, TAU, 48, _c("perfect_color", Palette.PRIMARY), _w() * (1.0 + shock), true)
	draw_arc(c, r * 0.58, 0.0, TAU, 40, _c("fail_color", Palette.FAILURE), _w(), true)
	for k: int in 8:
		var dir: Vector2 = Vector2.from_angle(TAU * float(k) / 8.0)
		draw_line(c + dir * r * 1.12, c + dir * r * (1.3 + 0.15 * shock), _c("accent", Palette.ACCENT), _w(), true)


func _draw_badge(c: Vector2, r: float) -> void:
	var col: Color = _c("color", Palette.ACCENT)
	var hex: PackedVector2Array = _ring(c, r * 1.1, 6, -PI * 0.5)
	draw_colored_polygon(hex, Palette.with_alpha(Palette.GRAPHITE, _dim))
	draw_polyline(hex, col, _w(), true)
	_draw_symbol(str(params.get("icon", "star")), c, r * 0.6, col)


func _draw_frame(c: Vector2, r: float) -> void:
	var col: Color = _c("color", Palette.PRIMARY)
	var accent: Color = _c("accent", Palette.ACCENT)
	var sq: Rect2 = Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
	var w: float = _w()
	match str(params.get("pattern", "plain")):
		"double":
			draw_rect(sq, col, false, w)
			draw_rect(sq.grow(-w * 2.5), accent, false, w * 0.75)
		"dashed":
			_dashed_rect(sq, col, w, 6)
		"dotted":
			_dashed_rect(sq, col, w, 12)
		"chevron":
			draw_rect(sq, col, false, w)
			for corner: Vector2 in [
				sq.position, Vector2(sq.end.x, sq.position.y), sq.end, Vector2(sq.position.x, sq.end.y)
			]:
				var into: Vector2 = (c - corner) * 0.35
				var arm: PackedVector2Array = PackedVector2Array(
					[corner + Vector2(into.x, 0), corner + into * 0.5, corner + Vector2(0, into.y)]
				)
				draw_polyline(arm, accent, w, true)
		"circuit":
			draw_rect(sq, col, false, w)
			for k: int in 4:
				var p: Vector2 = (
					sq.position + Vector2(sq.size.x * (0.25 + 0.5 * float(k % 2)), 0.0 if k < 2 else sq.size.y)
				)
				draw_circle(p, w * 1.6, accent, true, -1.0, true)
		"laurel":
			draw_arc(c, r * 1.05, PI * 0.6, PI * 1.4, 16, col, w, true)
			draw_arc(c, r * 1.05, -PI * 0.4, PI * 0.4, 16, col, w, true)
			for k: int in 5:
				var a: float = PI * 0.65 + float(k) * PI * 0.17
				draw_circle(c + Vector2(cos(a), sin(a)) * r * 1.05, w * 1.3, accent, true, -1.0, true)
				draw_circle(c + Vector2(-cos(a), sin(a)) * r * 1.05, w * 1.3, accent, true, -1.0, true)
		"crown":
			draw_rect(sq, col, false, w)
			var top: PackedVector2Array = PackedVector2Array(
				[
					sq.position + Vector2(r * 0.4, 0),
					sq.position + Vector2(r * 0.6, -r * 0.35),
					sq.position + Vector2(r, -r * 0.1),
					sq.position + Vector2(r * 1.4, -r * 0.35),
					sq.position + Vector2(r * 1.6, 0),
				]
			)
			draw_polyline(top, accent, w, true)
		_:
			draw_rect(sq, col, false, w)


func _dashed_rect(rect: Rect2, col: Color, w: float, segments: int) -> void:
	var corners: Array[Vector2] = [
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)
	]
	for side: int in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		for k: int in segments:
			if k % 2 == 0:
				draw_line(
					a.lerp(b, float(k) / float(segments)), a.lerp(b, float(k + 1) / float(segments)), col, w, true
				)


func _draw_avatar(c: Vector2, r: float) -> void:
	draw_circle(c, r * 1.1, _c("bg", Palette.SLATE), true, -1.0, true)
	_draw_symbol(str(params.get("glyph", "orb")), c, r * 0.62, _c("fg", Palette.PRIMARY))


## One geometric symbol vocabulary for avatar glyphs and badge icons.
func _draw_symbol(id: String, c: Vector2, r: float, col: Color) -> void:
	var w: float = _w()
	match id:
		"orb":
			draw_circle(c, r * 0.75, col, true, -1.0, true)
		"bolt":
			_line(c, r, [Vector2(0.25, -1), Vector2(-0.35, 0.1), Vector2(0.25, 0.1), Vector2(-0.25, 1)], col, w)
		"triangle":
			draw_polyline(_ring(c, r, 3, -PI * 0.5), col, w, true)
		"diamond":
			draw_polyline(_ring(c, r, 4, -PI * 0.5), col, w, true)
		"hexagon":
			draw_polyline(_ring(c, r, 6, -PI * 0.5), col, w, true)
		"wave":
			var pts: PackedVector2Array = PackedVector2Array()
			for k: int in 17:
				var t: float = float(k) / 16.0
				pts.append(c + Vector2(lerpf(-r, r, t), sin(t * TAU) * r * 0.4))
			draw_polyline(pts, col, w, true)
		"plus":
			draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), col, w, true)
			draw_line(c + Vector2(0, -r), c + Vector2(0, r), col, w, true)
		"star":
			var star: PackedVector2Array = PackedVector2Array()
			for k: int in 11:
				var a: float = -PI * 0.5 + PI * float(k) / 5.0
				star.append(c + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.45))
			draw_polyline(star, col, w, true)
		"eye":
			draw_arc(c + Vector2(0, r * 0.55), r * 1.05, -PI * 0.78, -PI * 0.22, 16, col, w, true)
			draw_arc(c - Vector2(0, r * 0.55), r * 1.05, PI * 0.22, PI * 0.78, 16, col, w, true)
			draw_circle(c, r * 0.22, col, true, -1.0, true)
		"spiral":
			var sp: PackedVector2Array = PackedVector2Array()
			for k: int in 40:
				var t2: float = float(k) / 39.0
				sp.append(c + Vector2.from_angle(t2 * TAU * 2.2) * r * t2)
			draw_polyline(sp, col, w, true)
		"moon":
			draw_arc(c, r * 0.85, PI * 0.35, PI * 1.65, 24, col, w, true)
			draw_arc(c + Vector2(r * 0.35, 0), r * 0.62, PI * 0.55, PI * 1.45, 20, col, w, true)
		"crown":
			_line(
				c,
				r,
				[
					Vector2(-1, 0.5),
					Vector2(-1, -0.4),
					Vector2(-0.4, 0.05),
					Vector2(0, -0.6),
					Vector2(0.4, 0.05),
					Vector2(1, -0.4),
					Vector2(1, 0.5),
					Vector2(-1, 0.5)
				],
				col,
				w
			)
		"comet":
			draw_circle(c + Vector2(r * 0.4, -r * 0.4), r * 0.35, col, true, -1.0, true)
			for k: int in 3:
				var off: float = float(k - 1) * r * 0.22
				draw_line(
					c + Vector2(r * 0.2 + off, -r * 0.2 + off),
					c + Vector2(-r + off * 0.5, r + off * 0.5),
					col,
					w * 0.8,
					true
				)
		"spark":
			for k: int in 4:
				draw_line(c, c + Vector2.from_angle(PI * 0.5 * float(k)) * r, col, w, true)
			draw_circle(c, r * 0.18, col, true, -1.0, true)
		"flame":
			_line(
				c,
				r,
				[
					Vector2(0, -1),
					Vector2(0.55, 0.1),
					Vector2(0.35, 0.8),
					Vector2(-0.35, 0.8),
					Vector2(-0.55, 0.1),
					Vector2(0, -1)
				],
				col,
				w
			)
		"shield":
			_line(
				c,
				r,
				[
					Vector2(0, -1),
					Vector2(0.8, -0.6),
					Vector2(0.6, 0.4),
					Vector2(0, 1),
					Vector2(-0.6, 0.4),
					Vector2(-0.8, -0.6),
					Vector2(0, -1)
				],
				col,
				w
			)
		"sun":
			draw_arc(c, r * 0.45, 0.0, TAU, 24, col, w, true)
			for k: int in 8:
				var dir: Vector2 = Vector2.from_angle(TAU * float(k) / 8.0)
				draw_line(c + dir * r * 0.7, c + dir * r, col, w, true)
		"planet":
			draw_arc(c, r * 0.55, 0.0, TAU, 24, col, w, true)
			draw_line(c + Vector2(-r, r * 0.3), c + Vector2(r, -r * 0.3), col, w, true)
		"trophy":
			_line(
				c,
				r,
				[
					Vector2(-0.6, -1),
					Vector2(0.6, -1),
					Vector2(0.45, -0.1),
					Vector2(0, 0.25),
					Vector2(-0.45, -0.1),
					Vector2(-0.6, -1)
				],
				col,
				w
			)
			draw_line(c + Vector2(0, r * 0.25), c + Vector2(0, r * 0.75), col, w, true)
			draw_line(c + Vector2(-r * 0.45, r * 0.85), c + Vector2(r * 0.45, r * 0.85), col, w, true)
		_:
			draw_polyline(_ring(c, r, 5, -PI * 0.5), col, w, true)


## Polyline through unit-space points scaled by [param r] around [param c].
func _line(c: Vector2, r: float, unit_points: Array, col: Color, w: float) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for p: Variant in unit_points:
		pts.append(c + (p as Vector2) * r)
	draw_polyline(pts, col, w, true)


static func _ring(c: Vector2, r: float, sides: int, rot: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for k: int in sides + 1:
		pts.append(c + Vector2.from_angle(rot + TAU * float(k) / float(sides)) * r)
	return pts
