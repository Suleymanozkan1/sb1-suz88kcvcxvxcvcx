class_name TrailRibbon
extends MeshInstance3D
## Camera-facing energy ribbon behind the core (signature trail).
##
## Points are stored in a fixed ring buffer and the mesh is rebuilt with
## ImmediateMesh each frame — no per-frame allocations beyond the mesh surface.
## Works identically in Mobile and Compatibility renderers (GPU particle trails
## are unsupported in Compatibility).

const SHADER: Shader = preload("res://assets/shaders/trail.gdshader")

var max_points: int = 18
var width: float = 0.18
var min_spacing: float = 0.18
## World-space cap: the ribbon is read along the view axis, so a long ribbon
## turns into a beam aimed at the lens. Keep it a short speed cue.
var max_length: float = 1.6
## Fades the ribbon out where it approaches the camera (no near-lens flare).
var near_fade_start: float = 3.6
var near_fade_end: float = 2.2
var intensity: float = Palette.ENERGY_TRAIL

var _points: PackedVector3Array = PackedVector3Array()
var _head: int = 0
var _count: int = 0
var _mesh: ImmediateMesh = ImmediateMesh.new()
var _mat: ShaderMaterial = ShaderMaterial.new()


func _ready() -> void:
	mesh = _mesh
	_mat.shader = SHADER
	_mat.set_shader_parameter("intensity", intensity)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_points.resize(max_points)
	top_level = true


func set_length(points: int) -> void:
	max_points = clampi(points, 4, 64)
	_points.resize(max_points)
	clear_points()


func set_colors(head: Color, tail: Color) -> void:
	_mat.set_shader_parameter("head_color", head)
	_mat.set_shader_parameter("tail_color", tail)


func set_style(style: int) -> void:
	_mat.set_shader_parameter("style", style)


func set_intensity(value: float) -> void:
	intensity = value
	_mat.set_shader_parameter("intensity", value)


func clear_points() -> void:
	_head = 0
	_count = 0
	_mesh.clear_surfaces()


func push_point(p: Vector3) -> void:
	if _count > 0:
		var last: Vector3 = _points[(_head - 1 + max_points) % max_points]
		if last.distance_to(p) < min_spacing:
			_points[(_head - 1 + max_points) % max_points] = p
			return
	_points[_head] = p
	_head = (_head + 1) % max_points
	_count = mini(_count + 1, max_points)


func rebuild(camera: Camera3D) -> void:
	_mesh.clear_surfaces()
	if _count < 2 or camera == null:
		return
	var cam_pos: Vector3 = camera.global_position
	# Visible span: stop at max_length of accumulated ribbon length.
	var visible: int = 1
	var run: float = 0.0
	while visible < _count:
		var a: Vector3 = _points[(_head - visible + max_points * 2) % max_points]
		var b: Vector3 = _points[(_head - 1 - visible + max_points * 2) % max_points]
		run += a.distance_to(b)
		if run > max_length:
			break
		visible += 1
	if visible < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i: int in visible:
		var idx: int = (_head - 1 - i + max_points * 2) % max_points
		var p: Vector3 = _points[idx]
		var next_idx: int = (idx - 1 + max_points) % max_points if i < visible - 1 else idx
		var prev_idx: int = (idx + 1) % max_points if i > 0 else idx
		var dir: Vector3 = (_points[prev_idx] - _points[next_idx])
		if dir.length_squared() < 0.000001:
			dir = Vector3.FORWARD
		var to_cam: Vector3 = cam_pos - p
		var cam_dist: float = to_cam.length()
		var side: Vector3 = dir.cross(to_cam / maxf(cam_dist, 0.001)).normalized()
		var t: float = float(i) / float(visible - 1)
		var w: float = width * (1.0 - t * 0.9)
		var near: float = clampf((cam_dist - near_fade_end) / (near_fade_start - near_fade_end), 0.0, 1.0)
		var alpha: float = (1.0 - t * 0.2) * near
		_mesh.surface_set_color(Color(1, 1, 1, alpha))
		_mesh.surface_set_uv(Vector2(t, 0.0))
		_mesh.surface_add_vertex(p + side * w)
		_mesh.surface_set_color(Color(1, 1, 1, alpha))
		_mesh.surface_set_uv(Vector2(t, 1.0))
		_mesh.surface_add_vertex(p - side * w)
	_mesh.surface_end()
