class_name TapRipple
extends Node3D
## Floor ripples under the core, one per accepted tap: the visual-impact step
## of the tap feedback chain (ART_DIRECTION §9). A small fixed pool of flat
## rings, never allocated during play; a new tap reuses the oldest ring.

const RIPPLE_SHADER: Shader = preload("res://assets/shaders/ripple.gdshader")
const POOL_SIZE: int = 3
const LIFE: float = 0.18
const SIZE: float = 1.4
## Just above the floor, below every other floor decal.
const FLOOR_Y: float = 0.012

var _rings: Array[MeshInstance3D] = []
var _age: PackedFloat32Array = PackedFloat32Array()
var _next: int = 0


func _init() -> void:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(SIZE, SIZE)
	quad.orientation = PlaneMesh.FACE_Y
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = RIPPLE_SHADER
	for _i: int in POOL_SIZE:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_rings.append(mi)
		_age.append(LIFE)


## Starts a ripple on the floor under [param at] in [param color].
func emit(at: Vector3, color: Color) -> void:
	var i: int = _next
	_next = (_next + 1) % POOL_SIZE
	var mi: MeshInstance3D = _rings[i]
	mi.position = Vector3(at.x, FLOOR_Y, at.z)
	mi.set_instance_shader_parameter("tint", color)
	mi.set_instance_shader_parameter("progress", 0.0)
	mi.visible = true
	_age[i] = 0.0


## Rings still spreading (for tests and budgets).
func active_count() -> int:
	var n: int = 0
	for mi: MeshInstance3D in _rings:
		if mi.visible:
			n += 1
	return n


func _process(delta: float) -> void:
	advance(delta)


## Moves every ring [param delta] seconds on.
func advance(delta: float) -> void:
	for i: int in POOL_SIZE:
		if not _rings[i].visible:
			continue
		_age[i] += delta
		if _age[i] >= LIFE:
			_rings[i].visible = false
			continue
		_rings[i].set_instance_shader_parameter("progress", _age[i] / LIFE)
