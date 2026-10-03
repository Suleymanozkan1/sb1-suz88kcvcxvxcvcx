class_name BurstPool
extends Node3D
## Pooled one-shot particle bursts (collect, shatter debris, hit, fail, perfect,
## combo ring, gate flash). CPUParticles3D so they look identical on Mobile and
## Compatibility renderers; counts scale with the quality preset.

const PRESETS: Dictionary = {
	"spark": {"amount": 14, "life": 0.45, "vel": Vector2(2.5, 5.5), "size": 0.14, "gravity": 0.0, "pool": 8},
	"tap": {"amount": 8, "life": 0.3, "vel": Vector2(1.0, 2.5), "size": 0.1, "gravity": 0.0, "pool": 4},
	"shatter": {"amount": 22, "life": 0.9, "vel": Vector2(4.0, 8.0), "size": 0.16, "gravity": -14.0, "pool": 6, "debris": true},
	"hit": {"amount": 30, "life": 0.5, "vel": Vector2(3.0, 7.0), "size": 0.16, "gravity": 0.0, "pool": 3},
	"fail": {"amount": 70, "life": 1.1, "vel": Vector2(4.0, 11.0), "size": 0.22, "gravity": -3.0, "pool": 2},
	"perfect": {"amount": 110, "life": 1.6, "vel": Vector2(5.0, 12.0), "size": 0.2, "gravity": -4.0, "pool": 2},
	"combo": {"amount": 28, "life": 0.55, "vel": Vector2(5.0, 6.0), "size": 0.13, "gravity": 0.0, "pool": 3, "ring": true},
	"gate": {"amount": 24, "life": 0.6, "vel": Vector2(1.5, 3.5), "size": 0.12, "gravity": 0.0, "pool": 3, "wide": true},
}

var amount_scale: float = 1.0
var _pools: Dictionary = {}
var _next: Dictionary = {}
var _glow_texture: GradientTexture2D


func _ready() -> void:
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


func set_amount_scale(value: float) -> void:
	amount_scale = clampf(value, 0.1, 2.0)
	for name: String in _pools:
		var cfg: Dictionary = PRESETS[name] as Dictionary
		for p: CPUParticles3D in _pools[name] as Array[CPUParticles3D]:
			p.amount = maxi(2, int(float(int(cfg["amount"])) * amount_scale))


func _make(cfg: Dictionary) -> CPUParticles3D:
	var p: CPUParticles3D = CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.95
	p.amount = int(cfg["amount"])
	p.lifetime = float(cfg["life"])
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = (cfg["vel"] as Vector2).x
	p.initial_velocity_max = (cfg["vel"] as Vector2).y
	p.gravity = Vector3(0, float(cfg["gravity"]), 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	if bool(cfg.get("ring", false)):
		p.direction = Vector3(1, 0, 0)
		p.spread = 180.0
		p.flatness = 1.0
	if bool(cfg.get("wide", false)):
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(2.0, 0.3, 0.1)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if bool(cfg.get("debris", false)):
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3.ONE * float(cfg["size"])
		mat.emission_enabled = true
		mat.emission_energy_multiplier = 1.5
		box.material = mat
		p.mesh = box
		p.angular_velocity_min = -540.0
		p.angular_velocity_max = 540.0
		p.particle_flag_rotate_y = true
	else:
		var quad: QuadMesh = QuadMesh.new()
		quad.size = Vector2.ONE * float(cfg["size"])
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_texture = _glow_texture
		quad.material = mat
		p.mesh = quad
	add_child(p)
	return p


func emit(preset: String, at: Vector3, color: Color) -> void:
	if not _pools.has(preset):
		return
	var list: Array[CPUParticles3D] = _pools[preset] as Array[CPUParticles3D]
	var idx: int = int(_next[preset])
	_next[preset] = (idx + 1) % list.size()
	var p: CPUParticles3D = list[idx]
	p.global_position = at
	p.color = color
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, color.lightened(0.4))
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = ramp
	p.restart()
	p.emitting = true


func stop_all() -> void:
	for name: String in _pools:
		for p: CPUParticles3D in _pools[name] as Array[CPUParticles3D]:
			p.emitting = false
