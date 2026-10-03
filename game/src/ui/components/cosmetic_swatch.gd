class_name CosmeticSwatch
extends Control
## Flat, consistent preview glyph for a cosmetic tile. Every category is drawn
## with the same visual grammar (circle field, 2 px strokes, item colours) so
## the grid reads as one family instead of a mix of icon styles.

var category: String = ""
var params: Dictionary = {}
var owned: bool = true


func setup(cat: String, item_params: Dictionary, is_owned: bool) -> void:
	category = cat
	params = item_params
	owned = is_owned
	queue_redraw()


func _c(key: String, fallback: Color) -> Color:
	var v: Variant = params.get(key, null)
	if typeof(v) == TYPE_COLOR:
		return v as Color
	if typeof(v) == TYPE_STRING and Color.html_is_valid(str(v)):
		return Color(str(v))
	return fallback


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.3
	var a: Color = _c("color_a", _c("head", _c("accent", _c("color", Palette.PRIMARY))))
	var b: Color = _c("color_b", _c("tail", _c("accent_2", Palette.SECONDARY)))
	var dim: float = 1.0 if owned else 0.45
	a = Color(a.r, a.g, a.b, dim)
	b = Color(b.r, b.g, b.b, dim)
	match category:
		"core_skin":
			draw_circle(c, r, a, true, -1.0, true)
			draw_arc(c, r * 0.62, 0.0, TAU, 40, b, 2.0, true)
			draw_arc(c, r + 3.0, 0.0, TAU, 48, Palette.with_alpha(Palette.BONE, 0.35 * dim), 2.0, true)
		"trail":
			var pts: PackedVector2Array = PackedVector2Array()
			for k: int in 24:
				var t: float = float(k) / 23.0
				pts.append(c + Vector2(lerpf(-r * 1.3, r * 1.3, t), sin(t * PI * 1.5) * r * 0.4))
			draw_polyline(pts, a, 6.0, true)
			draw_polyline(pts, b, 2.0, true)
		"particle":
			for k2: int in 7:
				var ang: float = TAU * float(k2) / 7.0
				draw_circle(
					c + Vector2(cos(ang), sin(ang)) * r * 0.85,
					4.0 + float(k2 % 3),
					a if k2 % 2 == 0 else b,
					true,
					-1.0,
					true
				)
		"background":
			var top: Color = _c("sky_top", a)
			var bottom: Color = _c("sky_bottom", b)
			draw_rect(Rect2(c - Vector2(r, r), Vector2(r * 2, r)), Color(top.r, top.g, top.b, dim))
			draw_rect(Rect2(c - Vector2(r, 0), Vector2(r * 2, r)), Color(bottom.r, bottom.g, bottom.b, dim))
			draw_circle(c, r * 0.18, Palette.with_alpha(Palette.BONE, dim), true, -1.0, true)
		"theme":
			draw_rect(Rect2(c - Vector2(r, r * 0.5), Vector2(r * 2, r * 0.3)), a)
			draw_rect(Rect2(c - Vector2(r, 0), Vector2(r * 1.3, r * 0.3)), b)
			draw_rect(
				Rect2(c + Vector2(-r, r * 0.45), Vector2(r * 0.9, r * 0.3)), Palette.with_alpha(Palette.BONE, 0.5 * dim)
			)
		"effect":
			draw_arc(c, r, 0.0, TAU, 48, a, 3.0, true)
			draw_arc(c, r * 0.6, 0.0, TAU, 40, b, 2.0, true)
			for k3: int in 8:
				var ang2: float = TAU * float(k3) / 8.0
				draw_line(
					c + Vector2(cos(ang2), sin(ang2)) * r * 1.1,
					c + Vector2(cos(ang2), sin(ang2)) * r * 1.35,
					a,
					2.0,
					true
				)
		"badge":
			var hex: PackedVector2Array = PackedVector2Array()
			for k4: int in 7:
				var ang3: float = TAU * float(k4) / 6.0 - PI * 0.5
				hex.append(c + Vector2(cos(ang3), sin(ang3)) * r)
			draw_polyline(hex, a, 3.0, true)
			draw_circle(c, r * 0.28, b, true, -1.0, true)
		"frame":
			var sq: Rect2 = Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2))
			draw_rect(sq, a, false, 3.0)
			draw_rect(sq.grow(-6.0), b, false, 1.5)
		"avatar":
			draw_circle(c, r, Palette.with_alpha(Palette.SLATE, dim), true, -1.0, true)
			var glyph_id: int = int(params.get("glyph", 0))
			_draw_avatar_glyph(c, r * 0.55, glyph_id, a)
		_:
			draw_circle(c, r, a, true, -1.0, true)


## Avatars are geometric glyphs (never faces): consistent with the shape language.
func _draw_avatar_glyph(c: Vector2, r: float, glyph_id: int, color: Color) -> void:
	var sides: int = 3 + (glyph_id % 5)
	var pts: PackedVector2Array = PackedVector2Array()
	var rot: float = float(glyph_id) * 0.37
	for k: int in sides + 1:
		var ang: float = TAU * float(k) / float(sides) + rot
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	draw_polyline(pts, color, 3.0, true)
	if glyph_id >= 5:
		draw_circle(c, r * 0.3, color, true, -1.0, true)
