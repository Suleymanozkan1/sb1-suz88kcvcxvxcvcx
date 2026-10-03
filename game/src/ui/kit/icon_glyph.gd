@tool
class_name IconGlyph
extends Control
## The single icon system (ART_DIRECTION §10): every icon is drawn on a 24-unit
## grid with a 2-unit stroke, round caps and joins, and no fills except status
## dots. Vector drawing keeps icons crisp at any DPI and identical in style.

const GRID: float = 24.0

@export var icon: StringName = &"play":
	set(value):
		icon = value
		queue_redraw()
@export var color: Color = Palette.BONE:
	set(value):
		color = value
		queue_redraw()
@export var stroke_units: float = 2.0:
	set(value):
		stroke_units = value
		queue_redraw()

var _scale: float = 1.0
var _offset: Vector2 = Vector2.ZERO


static func names() -> PackedStringArray:
	return [
		"play", "pause", "retry", "home", "settings", "shop", "collection", "daily", "progress",
		"trophy", "star", "star_filled", "coin", "gem", "lock", "check", "close", "back", "chevron_right",
		"sound", "music", "haptics", "language", "quality", "battery", "info", "restore", "leaderboard",
		"plus", "form_orb", "form_prism", "form_comet", "form_surge", "shield", "magnet", "target",
		"combo", "notifications", "accessibility", "endless", "zen", "timer",
	]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(UiTokens.ICON_SIZE, UiTokens.ICON_SIZE)


func _draw() -> void:
	var s: float = minf(size.x, size.y)
	_scale = s / GRID
	_offset = (size - Vector2(s, s)) * 0.5
	match icon:
		&"play":
			_poly([Vector2(8, 5), Vector2(19, 12), Vector2(8, 19)], true)
		&"pause":
			_line([Vector2(9, 6), Vector2(9, 18)])
			_line([Vector2(15, 6), Vector2(15, 18)])
		&"retry":
			_arc(Vector2(12, 12), 7.0, deg_to_rad(-40), deg_to_rad(250))
			_line([Vector2(16.8, 4.2), Vector2(17.4, 7.6), Vector2(14.0, 8.2)])
		&"home":
			_line([Vector2(4, 11), Vector2(12, 4), Vector2(20, 11)])
			_line([Vector2(6, 9.5), Vector2(6, 20), Vector2(18, 20), Vector2(18, 9.5)])
			_line([Vector2(10, 20), Vector2(10, 15), Vector2(14, 15), Vector2(14, 20)])
		&"settings":
			_circle(Vector2(12, 12), 3.0)
			_circle(Vector2(12, 12), 6.5)
			for k: int in 8:
				var a: float = TAU * float(k) / 8.0
				var d: Vector2 = Vector2(cos(a), sin(a))
				_line([Vector2(12, 12) + d * 6.5, Vector2(12, 12) + d * 9.0])
		&"shop":
			_poly([Vector2(5, 9), Vector2(19, 9), Vector2(18, 20), Vector2(6, 20)], true)
			_arc(Vector2(12, 9), 3.5, PI, TAU)
		&"collection":
			for p: Vector2 in [Vector2(5, 5), Vector2(13, 5), Vector2(5, 13), Vector2(13, 13)]:
				_poly([p, p + Vector2(6, 0), p + Vector2(6, 6), p + Vector2(0, 6)], true)
		&"daily":
			_poly([Vector2(4, 6), Vector2(20, 6), Vector2(20, 20), Vector2(4, 20)], true)
			_line([Vector2(4, 10), Vector2(20, 10)])
			_line([Vector2(8, 3.5), Vector2(8, 7.5)])
			_line([Vector2(16, 3.5), Vector2(16, 7.5)])
			_dot(Vector2(12, 15), 1.6)
		&"progress":
			_line([Vector2(6, 4), Vector2(6, 20)])
			_poly([Vector2(6, 5), Vector2(18, 5), Vector2(15, 9), Vector2(18, 13), Vector2(6, 13)], false)
		&"trophy":
			_line([Vector2(7, 4), Vector2(17, 4), Vector2(17, 9)])
			_arc(Vector2(12, 9), 5.0, 0.0, PI)
			_line([Vector2(7, 9), Vector2(7, 4)])
			_line([Vector2(12, 14), Vector2(12, 17)])
			_line([Vector2(8, 20), Vector2(16, 20)])
			_arc(Vector2(5, 7.5), 2.2, PI * 0.5, PI * 1.5)
			_arc(Vector2(19, 7.5), 2.2, -PI * 0.5, PI * 0.5)
		&"star", &"star_filled":
			var pts: Array[Vector2] = _star_points(Vector2(12, 12.6), 8.6, 3.8)
			if icon == &"star_filled":
				draw_colored_polygon(_xf_arr(pts), color)
			_poly(pts, true)
		&"coin":
			_circle(Vector2(12, 12), 8.0)
			_circle(Vector2(12, 12), 4.5)
		&"gem":
			_poly([Vector2(6, 9), Vector2(9, 5), Vector2(15, 5), Vector2(18, 9), Vector2(12, 19)], true)
			_line([Vector2(6, 9), Vector2(18, 9)])
			_line([Vector2(9, 5), Vector2(12, 9), Vector2(15, 5)])
		&"lock":
			_poly([Vector2(6, 11), Vector2(18, 11), Vector2(18, 20), Vector2(6, 20)], true)
			_arc(Vector2(12, 11), 4.0, PI, TAU)
			_line([Vector2(8, 11), Vector2(8, 11)])
		&"check":
			_line([Vector2(5, 12.5), Vector2(10, 17.5), Vector2(19, 7)])
		&"close":
			_line([Vector2(6, 6), Vector2(18, 18)])
			_line([Vector2(18, 6), Vector2(6, 18)])
		&"back":
			_line([Vector2(15, 5), Vector2(8, 12), Vector2(15, 19)])
		&"chevron_right":
			_line([Vector2(9, 5), Vector2(16, 12), Vector2(9, 19)])
		&"sound":
			_poly([Vector2(4, 9.5), Vector2(8, 9.5), Vector2(12.5, 5.5), Vector2(12.5, 18.5), Vector2(8, 14.5), Vector2(4, 14.5)], true)
			_arc(Vector2(13, 12), 4.0, -PI * 0.3, PI * 0.3)
			_arc(Vector2(13, 12), 7.0, -PI * 0.3, PI * 0.3)
		&"music":
			_circle(Vector2(8.5, 17), 2.5)
			_circle(Vector2(16.5, 15), 2.5)
			_line([Vector2(11, 17), Vector2(11, 6), Vector2(19, 4), Vector2(19, 15)])
		&"haptics":
			_poly([Vector2(9, 4), Vector2(15, 4), Vector2(15, 20), Vector2(9, 20)], true)
			_line([Vector2(5, 9), Vector2(5, 15)])
			_line([Vector2(19, 9), Vector2(19, 15)])
		&"language":
			_circle(Vector2(12, 12), 8.0)
			_line([Vector2(4, 12), Vector2(20, 12)])
			_ellipse(Vector2(12, 12), 3.8, 8.0)
		&"quality":
			for row: int in 3:
				var y: float = 6.0 + float(row) * 6.0
				_line([Vector2(4, y), Vector2(20, y)])
				var kx: float = [15.0, 8.0, 13.0][row] as float
				_dot(Vector2(kx, y), 2.2)
		&"battery":
			_poly([Vector2(3, 8), Vector2(18, 8), Vector2(18, 16), Vector2(3, 16)], true)
			_line([Vector2(21, 10.5), Vector2(21, 13.5)])
			_line([Vector2(6, 11), Vector2(6, 13)])
			_line([Vector2(9, 11), Vector2(9, 13)])
		&"info":
			_circle(Vector2(12, 12), 8.0)
			_line([Vector2(12, 11), Vector2(12, 16)])
			_dot(Vector2(12, 8), 1.3)
		&"restore":
			_arc(Vector2(12, 12), 7.0, deg_to_rad(200), deg_to_rad(340))
			_arc(Vector2(12, 12), 7.0, deg_to_rad(20), deg_to_rad(160))
			_line([Vector2(18.2, 6.2), Vector2(18.6, 9.4), Vector2(15.4, 9.6)])
			_line([Vector2(5.8, 17.8), Vector2(5.4, 14.6), Vector2(8.6, 14.4)])
		&"leaderboard":
			_line([Vector2(6, 20), Vector2(6, 13)])
			_line([Vector2(12, 20), Vector2(12, 6)])
			_line([Vector2(18, 20), Vector2(18, 10)])
		&"plus":
			_line([Vector2(12, 5), Vector2(12, 19)])
			_line([Vector2(5, 12), Vector2(19, 12)])
		&"form_orb":
			_circle(Vector2(12, 12), 6.5)
		&"form_prism":
			_poly([Vector2(12, 3.5), Vector2(18.5, 12), Vector2(12, 20.5), Vector2(5.5, 12)], true)
		&"form_comet":
			_arc(Vector2(8.5, 12), 4.5, PI * 0.5, PI * 1.5)
			_arc(Vector2(15.5, 12), 4.5, -PI * 0.5, PI * 0.5)
			_line([Vector2(8.5, 7.5), Vector2(15.5, 7.5)])
			_line([Vector2(8.5, 16.5), Vector2(15.5, 16.5)])
		&"form_surge":
			_circle(Vector2(12, 12), 3.5)
			_ellipse(Vector2(12, 12), 9.0, 3.6)
		&"shield":
			var hex: Array[Vector2] = []
			for k2: int in 6:
				var a2: float = TAU * float(k2) / 6.0 - PI * 0.5
				hex.append(Vector2(12, 12) + Vector2(cos(a2), sin(a2)) * 8.0)
			_poly(hex, true)
		&"magnet":
			_arc(Vector2(12, 11), 6.0, 0.0, PI)
			_line([Vector2(6, 11), Vector2(6, 5)])
			_line([Vector2(18, 11), Vector2(18, 5)])
			_line([Vector2(4, 7), Vector2(8, 7)])
			_line([Vector2(16, 7), Vector2(20, 7)])
		&"target":
			_circle(Vector2(12, 12), 8.0)
			_circle(Vector2(12, 12), 4.0)
			_dot(Vector2(12, 12), 1.4)
		&"combo":
			_poly([Vector2(13, 3), Vector2(7, 13), Vector2(12, 13), Vector2(10, 21), Vector2(17, 10), Vector2(12, 10)], true)
		&"notifications":
			_arc(Vector2(12, 11), 5.5, PI, TAU)
			_line([Vector2(6.5, 11), Vector2(6.5, 16), Vector2(5, 17.5), Vector2(19, 17.5), Vector2(17.5, 16), Vector2(17.5, 11)])
			_line([Vector2(10.5, 20), Vector2(13.5, 20)])
		&"accessibility":
			_circle(Vector2(12, 5.5), 1.8)
			_line([Vector2(5, 9), Vector2(19, 9)])
			_line([Vector2(12, 9), Vector2(12, 14), Vector2(8.5, 20)])
			_line([Vector2(12, 14), Vector2(15.5, 20)])
		&"endless":
			_ellipse(Vector2(8, 12), 4.0, 4.0)
			_ellipse(Vector2(16, 12), 4.0, 4.0)
		&"zen":
			_arc(Vector2(12, 12), 8.0, PI * 0.15, PI * 1.85)
			_dot(Vector2(12, 12), 1.6)
		&"timer":
			_circle(Vector2(12, 13), 7.5)
			_line([Vector2(12, 13), Vector2(12, 9)])
			_line([Vector2(10, 3.5), Vector2(14, 3.5)])
		_:
			_circle(Vector2(12, 12), 8.0)


func _xf(p: Vector2) -> Vector2:
	return _offset + p * _scale


func _xf_arr(points: Array[Vector2]) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in points:
		out.append(_xf(p))
	return out


func _w() -> float:
	return maxf(1.0, stroke_units * _scale)


## Polyline with round joins and caps (the system's stroke style).
func _line(points: Array[Vector2]) -> void:
	var pts: PackedVector2Array = _xf_arr(points)
	draw_polyline(pts, color, _w(), true)
	for p: Vector2 in pts:
		draw_circle(p, _w() * 0.5, color, true, -1.0, true)


func _poly(points: Array[Vector2], closed: bool) -> void:
	var pts: Array[Vector2] = points.duplicate()
	if closed:
		pts.append(points[0])
	_line(pts)


func _circle(center: Vector2, radius: float) -> void:
	draw_arc(_xf(center), radius * _scale, 0.0, TAU, 48, color, _w(), true)


func _arc(center: Vector2, radius: float, from_angle: float, to_angle: float) -> void:
	draw_arc(_xf(center), radius * _scale, from_angle, to_angle, 32, color, _w(), true)
	for a: float in [from_angle, to_angle]:
		draw_circle(_xf(center + Vector2(cos(a), sin(a)) * radius), _w() * 0.5, color, true, -1.0, true)


func _ellipse(center: Vector2, rx: float, ry: float) -> void:
	var pts: Array[Vector2] = []
	for k: int in 41:
		var a: float = TAU * float(k) / 40.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(_xf_arr(pts), color, _w(), true)


func _dot(center: Vector2, radius: float) -> void:
	draw_circle(_xf(center), radius * _scale, color, true, -1.0, true)


static func _star_points(center: Vector2, outer: float, inner: float) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for k: int in 10:
		var a: float = -PI * 0.5 + PI * float(k) / 5.0
		var r: float = outer if k % 2 == 0 else inner
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts
