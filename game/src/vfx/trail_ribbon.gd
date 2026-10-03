class_name TrailRibbon
extends MeshInstance3D
## Camera-facing energy ribbon behind the core (signature trail).
##
## Points are stored in a fixed ring buffer and the mesh is rebuilt with
## ImmediateMesh each frame — no per-frame allocations beyond the mesh surface.
## Works identically in Mobile and Compatibility renderers (GPU particle trails
## are unsupported in Compatibility).

const SHADER: Shader = preload("res://assets/shaders/trail.gdshader")

var max_points: int = 28
var width: float = 0.42
var min_spacing: float = 0.18
var intensity: float = 1.0

var _points: PackedVector3Array = PackedVector3Array()
var _head: int = 0
var _count: int = 0
var _mesh: ImmediateMesh = ImmediateMesh.new()
var _mat: ShaderMaterial = ShaderMaterial.new()


func _ready() -> void:
	mesh = _mesh
	_mat.shader = SHADER
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
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i: int in _count:
		var idx: int = (_head - 1 - i + max_points * 2) % max_points
		var p: Vector3 = _points[idx]
		var next_idx: int = (idx - 1 + max_points) % max_points if i < _count - 1 else idx
		var prev_idx: int = (idx + 1) % max_points if i > 0 else idx
		var dir: Vector3 = (_points[prev_idx] - _points[next_idx])
		if dir.length_squared() < 0.000001:
			dir = Vector3.FORWARD
		var to_cam: Vector3 = (cam_pos - p).normalized()
		var side: Vector3 = dir.cross(to_cam).normalized()
		var t: float = float(i) / float(_count - 1)
		var w: float = width * (1.0 - t * 0.85)
		_mesh.surface_set_color(Color(1, 1, 1, 1.0 - t * 0.2))
		_mesh.surface_set_uv(Vector2(t, 0.0))
		_mesh.surface_add_vertex(p + side * w)
		_mesh.surface_set_color(Color(1, 1, 1, 1.0 - t * 0.2))
		_mesh.surface_set_uv(Vector2(t, 1.0))
		_mesh.surface_add_vertex(p - side * w)
	_mesh.surface_end()
