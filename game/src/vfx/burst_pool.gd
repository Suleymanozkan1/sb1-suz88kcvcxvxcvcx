class_name BurstPool
extends Node3D
## Pooled one-shot effects with fixed budgets (ART_DIRECTION §9). Each preset
## exists for one job; counts scale with the quality preset. CPUParticles3D so
## Mobile and Compatibility renderers look identical.

const PRESETS: Dictionary = {
	"collect":
	{"amount": 6, "life": 0.28, "vel": Vector2(1.2, 2.4), "size": 0.06, "gravity": 0.0, "pool": 8, "energy": true},
	# information
	"prism":
	{"amount": 10, "life": 0.4, "vel": Vector2(1.6, 3.0), "size": 0.08, "gravity": 0.0, "pool": 3, "energy": true},
	"streak":
	{
		"amount": 5,
		"life": 0.22,
		"vel": Vector2(0.4, 0.8),
		"size": 0.05,
		"gravity": 0.0,
		"pool": 3,
		"energy": true,
		"line": true
	},
	# impact (matter: lit debris, never glowing)
	"shatter":
	{"amount": 12, "life": 0.8, "vel": Vector2(2.5, 5.0), "size": 0.13, "gravity": -12.0, "pool": 4, "debris": true},
	"shield":
	{"amount": 10, "life": 0.45, "vel": Vector2(2.0, 3.6), "size": 0.07, "gravity": 0.0, "pool": 2, "energy": true},
	"fail":
	{"amount": 28, "life": 0.8, "vel": Vector2(2.5, 6.0), "size": 0.08, "gravity": -2.0, "pool": 2, "energy": true},
	"perfect":
	{
		# reward
		"amount": 30,
		"life": 1.3,
		"vel": Vector2(1.5, 3.2),
		"size": 0.07,
		"gravity": 1.6,
		"pool": 1,
		"energy": true,
		"rise": true
	},
}
const RING_POOL: int = 4
const RING_LIFE: float = 0.32
const GLOW_SHADER: Shader = preload("res://assets/shaders/glow_sprite.gdshader")

var amount_scale: float = 1.0
var _pools: Dictionary = {}
var _next: Dictionary = {}
var _ramps: Dictionary = {}
var _rings: Array[MeshInstance3D] = []
var _ring_age: Array[float] = []
var _ring_next: int = 0
var _delayed: Array[Dictionary] = []
var _glow_texture: GradientTexture2D
var _built: bool = false


func _ready() -> void:
	_ensure_built()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_glow_texture = GradientTexture2D.new()
	var g: Gradient = Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	_glow_texture.gradient = g
	_glow_texture.fill = GradientTexture2D.FILL_RADIAL
	_glow_texture.fill_from = Vector2(0.5, 0.5)
	_glow_texture.fill_to = Vector2(0.5, 0.0)
	_glow_texture.width = 32
	_glow_texture.height = 32
	for name: String in PRESETS:
		var list: Array[CPUParticles3D] = []
		var cfg: Dictionary = PRESETS[name] as Dictionary
		for _i: int in int(cfg["pool"]):
			list.append(_make(cfg))
		_pools[name] = list
		_next[name] = 0
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	for _r: int in RING_POOL:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = quad
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = GLOW_SHADER
		mat.set_shader_parameter("size", 1.3)
		mat.set_shader_parameter("ring", 0.9)
		mat.set_shader_parameter("intensity", 1.2)
		mi.material_override = mat
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_rings.append(mi)
		_ring_age.append(-1.0)


func set_amount_scale(value: float) -> void:
	_ensure_built()
	amount_scale = clampf(value, 0.1, 1.5)
	for name: String in _pools:
		var cfg: Dictionary = PRESETS[name] as Dictionary
		for p: CPUParticles3D in _pools[name] as Array[CPUParticles3D]:
			# Presets are the art-direction budget: lower presets scale down,
			# none scales a burst above it.
			p.amount = maxi(2, int(float(int(cfg["amount"])) * minf(amount_scale, 1.0)))


func _make(cfg: Dictionary) -> CPUParticles3D:
	var p: CPUParticles3D = CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.92
	p.amount = int(cfg["amount"])
	p.lifetime = float(cfg["life"])
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = (cfg["vel"] as Vector2).x
	p.initial_velocity_max = (cfg["vel"] as Vector2).y
	p.gravity = Vector3(0, float(cfg["gravity"]), 0)
	p.damping_min = 3.0
	p.damping_max = 5.0
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.7, 0.6))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	if bool(cfg.get("rise", false)):
		p.direction = Vector3(0, 1, 0)
		p.spread = 35.0
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.8
	if bool(cfg.get("line", false)):
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(0.05, 0.4, 0.05)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	if bool(cfg.get("debris", false)):
		# Lit glass fragments: matter, never emissive.
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(float(cfg["size"]), float(cfg["size"]) * 0.6, float(cfg["size"]) * 0.2)
		mat.roughness = 0.1
		mat.metallic_specular = 0.8
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		box.material = mat
		p.mesh = box
		p.angular_velocity_min = -420.0
		p.angular_velocity_max = 420.0
		p.particle_flag_rotate_y = true
	else:
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2.ONE * float(cfg["size"])
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_texture = _glow_texture
		quad.material = mat
		p.mesh = quad
	add_child(p)
	return p


func _ramp_for(color: Color) -> Gradient:
	var key: int = color.to_rgba32()
	if _ramps.has(key):
		return _ramps[key] as Gradient
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	_ramps[key] = ramp
	return ramp


func emit(preset: String, at: Vector3, color: Color) -> void:
	_ensure_built()
	if preset == "ring":
		_emit_ring(at, color)
		return
	if not _pools.has(preset):
		return
	var list: Array[CPUParticles3D] = _pools[preset] as Array[CPUParticles3D]
	var idx: int = int(_next[preset])
	_next[preset] = (idx + 1) % list.size()
	var p: CPUParticles3D = list[idx]
	p.global_position = at
	p.color = color
	p.color_ramp = _ramp_for(color)
	p.restart()
	p.emitting = true


## Emits after [param delay] seconds (e.g. the fail burst follows the implosion).
func emit_delayed(preset: String, at: Vector3, color: Color, delay: float) -> void:
	_delayed.append({"preset": preset, "at": at, "color": color, "t": delay})


func _emit_ring(at: Vector3, color: Color) -> void:
	var mi: MeshInstance3D = _rings[_ring_next]
	_ring_age[_ring_next] = 0.0
	_ring_next = (_ring_next + 1) % _rings.size()
	mi.global_position = at
	(mi.material_override as ShaderMaterial).set_shader_parameter("glow_color", color)
	mi.visible = true


func _process(delta: float) -> void:
	for i: int in _rings.size():
		if _ring_age[i] < 0.0:
			continue
		_ring_age[i] += delta
		var k: float = _ring_age[i] / RING_LIFE
		if k >= 1.0:
			_ring_age[i] = -1.0
			_rings[i].visible = false
			continue
		_rings[i].set_instance_shader_parameter("progress", ease(k, 0.4))
		_rings[i].set_instance_shader_parameter("fade", 1.0 - k)
	var j: int = _delayed.size() - 1
	while j >= 0:
		var d: Dictionary = _delayed[j]
		d["t"] = float(d["t"]) - delta
		if float(d["t"]) <= 0.0:
			emit(str(d["preset"]), d["at"] as Vector3, d["color"] as Color)
			_delayed.remove_at(j)
		j -= 1


func stop_all() -> void:
	_ensure_built()
	_delayed.clear()
	for name: String in _pools:
		for p: CPUParticles3D in _pools[name] as Array[CPUParticles3D]:
			p.emitting = false
	for i: int in _rings.size():
		_ring_age[i] = -1.0
		_rings[i].visible = false
