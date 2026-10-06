class_name SpeedStreaks
extends CPUParticles3D
## Wind lines rushing past the shaft (docs/ART_DIRECTION.md §9: their one job
## is speed). Thin streaks in the key-light colour start ahead, outside the
## lanes (above the blocks and beside the rib pillars, never over the course),
## and stream toward the camera faster than the run. Faint at cruising speed,
## they brighten with a dash, a light surge or a speed ramp, within the 20 %
## decoration cap. High and Ultra only (the particle budget), off with reduce
## motion. [GameplayView] keeps the emitter just ahead of the core.

## Decoration never exceeds 20 % opacity (§7).
const MAX_ALPHA: float = 0.2
## Opacity at the level's own speed; full at [constant FULL_SPEED_RATIO] times it.
const CRUISE_ALPHA: float = 0.06
const FULL_SPEED_RATIO: float = 1.5
const AMOUNT: int = 24
const LIFETIME: float = 0.8
## Streak size: long and hairline thin.
const LENGTH: float = 2.4
const WIDTH: float = 0.016
## Rush toward the camera on top of the run's own speed.
const RUSH_MIN: float = 16.0
const RUSH_MAX: float = 26.0
## Emission zone, relative to the emitter: a band above the blocks across the
## shaft, and a band each side beside the pillars, from a little ahead of the
## core to [constant DEPTH] further.
const TOP_Y: Vector2 = Vector2(2.6, 4.2)
const TOP_HALF_WIDTH: float = 4.2
const SIDE_X: Vector2 = Vector2(2.9, 4.6)
const SIDE_Y: Vector2 = Vector2(0.4, 4.2)
const DEPTH: float = 22.0
## Emission points are fixed (no per-run randomness in their layout).
const POINT_COUNT: int = 96
const POINT_SEED: int = 1907

var _mat: StandardMaterial3D
var _color: Color = Color.WHITE
var _allowed: bool = false


func _init() -> void:
	amount = AMOUNT
	lifetime = LIFETIME
	local_coords = false
	emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	emission_points = emission_layout()
	direction = Vector3(0, 0, 1)
	spread = 0.0
	gravity = Vector3.ZERO
	initial_velocity_min = RUSH_MIN
	initial_velocity_max = RUSH_MAX
	color_ramp = _fade_ramp()
	mesh = streak_mesh()
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitting = false


## Fixed emission points in the three bands (top, left, right), never over
## the lanes below the blocks' height.
static func emission_layout() -> PackedVector3Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = POINT_SEED
	var points: PackedVector3Array = PackedVector3Array()
	for i: int in POINT_COUNT:
		var z: float = -rng.randf() * DEPTH
		match i % 3:
			0:
				points.append(
					Vector3(rng.randf_range(-TOP_HALF_WIDTH, TOP_HALF_WIDTH), rng.randf_range(TOP_Y.x, TOP_Y.y), z)
				)
			1:
				points.append(Vector3(-rng.randf_range(SIDE_X.x, SIDE_X.y), rng.randf_range(SIDE_Y.x, SIDE_Y.y), z))
			_:
				points.append(Vector3(rng.randf_range(SIDE_X.x, SIDE_X.y), rng.randf_range(SIDE_Y.x, SIDE_Y.y), z))
	return points


## Two crossed hairline quads along z (a line from every angle), bright in the
## middle and fading to nothing at both ends.
static func streak_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half: float = LENGTH * 0.5
	for axis: Vector3 in [Vector3(WIDTH, 0, 0), Vector3(0, WIDTH, 0)]:
		var rows: Array[float] = [-half, 0.0, half]
		var alphas: Array[float] = [0.0, 1.0, 0.0]
		for r: int in 2:
			var z0: float = rows[r]
			var z1: float = rows[r + 1]
			var c0: Color = Color(1, 1, 1, alphas[r])
			var c1: Color = Color(1, 1, 1, alphas[r + 1])
			var quad: Array[Vector3] = [
				-axis + Vector3(0, 0, z0), axis + Vector3(0, 0, z0), axis + Vector3(0, 0, z1), -axis + Vector3(0, 0, z1)
			]
			var cols: Array[Color] = [c0, c0, c1, c1]
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.set_color(cols[k])
				st.add_vertex(quad[k])
	return st.commit()


## Fades in after the spawn and out before the camera, so no streak pops.
static func _fade_ramp() -> Gradient:
	var g: Gradient = Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	return g


## The world's key-light colour.
func set_tint(c: Color) -> void:
	_color = c
	_mat.albedo_color = Palette.with_alpha(_color, CRUISE_ALPHA)


## Quality and accessibility gate: High and above, not with reduce motion.
func set_allowed(allowed: bool) -> void:
	_allowed = allowed
	if not allowed:
		emitting = false


## Opacity for a run speed against the level's own speed (pure, tested).
static func alpha_for(speed: float, base_speed: float) -> float:
	if base_speed <= 0.0:
		return CRUISE_ALPHA
	var over: float = clampf((speed / base_speed - 1.0) / (FULL_SPEED_RATIO - 1.0), 0.0, 1.0)
	return lerpf(CRUISE_ALPHA, MAX_ALPHA, over)


## Per frame: follow the run's speed while it runs.
func update_run(running: bool, speed: float, base_speed: float) -> void:
	emitting = _allowed and running and speed > 0.0
	_mat.albedo_color = Palette.with_alpha(_color, alpha_for(speed, base_speed))
