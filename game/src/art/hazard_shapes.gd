class_name HazardShapes
extends RefCounted
## Obstacle silhouettes per world style (ART_DIRECTION §4 hazard row). Every
## world draws its lane blockers in its own family of shapes, and a row mixes
## two or three of them, so obstacles no longer read as one orange box.
##
## Every mesh fits the barrier's collision footprint (one lane wide, the
## hazard depth deep, about the block height tall) and is centred like the old
## block (y from -HALF_H to +HALF_H, placed at half the block height). Surface 0
## is the body (hazard.gdshader); surface 1, when present, is the warning light
## geometry (an emissive material): the one cue every world shares.

const STYLES: PackedStringArray = [
	"machined", "crystal", "basalt", "industrial", "mine", "pods", "ice", "rust", "monolith", "candy"
]
## hazard.gdshader pattern per style (0 machined band, 1 stripes, 2 cracks,
## 3 glyphs, 4 inner glow, 5 candy, 6 veins).
const PATTERNS: Dictionary[String, int] = {
	"machined": 0,
	"crystal": 4,
	"basalt": 2,
	"industrial": 1,
	"mine": 0,
	"pods": 6,
	"ice": 4,
	"rust": 1,
	"monolith": 3,
	"candy": 5,
}
## Body roughness / metallic / clearcoat per style.
const SURFACES: Dictionary[String, Vector3] = {
	"machined": Vector3(0.34, 0.35, 0.0),
	"crystal": Vector3(0.1, 0.0, 0.8),
	"basalt": Vector3(0.9, 0.0, 0.0),
	"industrial": Vector3(0.5, 0.15, 0.0),
	"mine": Vector3(0.4, 0.4, 0.0),
	"pods": Vector3(0.5, 0.0, 0.3),
	"ice": Vector3(0.08, 0.0, 0.6),
	"rust": Vector3(0.75, 0.55, 0.0),
	"monolith": Vector3(0.2, 0.3, 0.5),
	"candy": Vector3(0.18, 0.0, 1.0),
}
const WIDTH: float = SimConst.BLOCK_HALF_WIDTH * 2.0
const DEPTH: float = SimConst.HAZARD_HALF_DEPTH * 2.0
const HALF_H: float = 0.45
const VARIANTS_PER_STYLE: int = 2
## Styles whose shapes carry warning-light geometry (the others light up
## through the body pattern alone).
const LIT_STYLES: PackedStringArray = ["machined", "industrial", "mine", "pods", "rust"]


## The barrier variants of [param style] (unknown styles fall back to machined).
## Fresh meshes: the caller assigns its world's materials to their surfaces.
static func barriers(style: String) -> Array[ArrayMesh]:
	var s: String = style if STYLES.has(style) else "machined"
	var out: Array[ArrayMesh] = []
	for v: int in VARIANTS_PER_STYLE:
		out.append(_build(s, v))
	return out


## The slider sled: a rounded block with a warning strip, in any style.
static func sled() -> ArrayMesh:
	var body: SurfaceTool = _begin()
	var light: SurfaceTool = _begin()
	MeshFactory.add_box(body, Vector3(WIDTH, 0.74, DEPTH * 1.15), _at(0, 0, 0), 0.2)
	MeshFactory.add_box(light, Vector3(WIDTH * 0.8, 0.05, 0.06), _at(0, 0.38, DEPTH * 0.58), 0.3)
	return _commit(body, light, true)


static func _build(style: String, variant: int) -> ArrayMesh:
	var body: SurfaceTool = _begin()
	var light: SurfaceTool = _begin()
	match style:
		"crystal":
			_crystal(body, variant)
		"basalt":
			_basalt(body, variant)
		"industrial":
			_industrial(body, light, variant)
		"mine":
			_mine(body, light, variant)
		"pods":
			_pods(body, light, variant)
		"ice":
			_ice(body, variant)
		"rust":
			_rust(body, light, variant)
		"monolith":
			_monolith(body, variant)
		"candy":
			_candy(body, variant)
		_:
			_machined(body, light, variant)
	return _commit(body, light, LIT_STYLES.has(style))


static func _machined(body: SurfaceTool, light: SurfaceTool, variant: int) -> void:
	if variant == 0:
		# Machined block with a warning lamp strip along its top front edge.
		MeshFactory.add_box(body, Vector3(WIDTH, HALF_H * 2.0, DEPTH), _at(0, 0, 0), 0.16)
		MeshFactory.add_box(light, Vector3(WIDTH * 0.78, 0.05, 0.05), _at(0, HALF_H - 0.02, DEPTH * 0.5), 0.3)
	else:
		# Laser fence: two posts and three hot beams between them.
		for side: float in [-1.0, 1.0]:
			MeshFactory.add_box(body, Vector3(0.16, HALF_H * 2.1, DEPTH * 0.7), _at(side * 0.46, 0.02, 0), 0.18)
			MeshFactory.add_box(body, Vector3(0.24, 0.1, DEPTH), _at(side * 0.46, -HALF_H + 0.05, 0), 0.2)
		for y: float in [-0.26, -0.06, 0.14, 0.34]:
			MeshFactory.add_box(light, Vector3(0.86, 0.07, 0.07), _at(0, y, 0), 0.3)


static func _crystal(body: SurfaceTool, variant: int) -> void:
	# Ruby crystals growing from a rubble base; the shader lights them inside.
	# Outer crystals lean inwards so the cluster stays inside its lane.
	MeshFactory.add_box(body, Vector3(WIDTH * 0.95, 0.14, DEPTH * 0.9), _at(0, -HALF_H + 0.07, 0), 0.4)
	var spikes: Array = (
		[
			[-0.4, 0.62, 0.12, -0.22],
			[-0.18, 0.86, 0.14, -0.1],
			[0.04, 0.98, 0.16, 0.04],
			[0.26, 0.8, 0.13, 0.12],
			[0.42, 0.58, 0.11, 0.24]
		]
		if variant == 0
		else [[-0.26, 0.98, 0.21, -0.14], [0.24, 0.84, 0.2, 0.18], [0.0, 0.5, 0.13, 0.0]]
	)
	for s: Array in spikes:
		_crystal_spike(body, float(s[0]), float(s[1]), float(s[2]), float(s[3]))


static func _crystal_spike(st: SurfaceTool, x: float, height: float, radius: float, lean: float) -> void:
	var basis: Basis = Basis(Vector3.BACK, lean)
	var body_h: float = height * 0.75
	var base: Vector3 = Vector3(x, -HALF_H + 0.08, 0)
	MeshFactory.add_prism(st, radius, radius, body_h, 6, Transform3D(basis, base + basis * Vector3(0, body_h * 0.5, 0)))
	var tip_h: float = height - body_h
	MeshFactory.add_prism(
		st, radius, 0.0, tip_h, 6, Transform3D(basis, base + basis * Vector3(0, body_h + tip_h * 0.5, 0))
	)


static func _basalt(body: SurfaceTool, variant: int) -> void:
	if variant == 0:
		MeshFactory.add_box(body, Vector3(WIDTH, HALF_H * 2.0, DEPTH), _at(0, 0, 0), 0.34)
	else:
		MeshFactory.add_box(body, Vector3(WIDTH, 0.52, DEPTH), _at(0, -HALF_H + 0.26, 0), 0.3)
		var tilt: Transform3D = Transform3D(Basis(Vector3.UP, 0.12), Vector3(0.1, 0.25, 0))
		MeshFactory.add_box(body, Vector3(WIDTH * 0.72, 0.42, DEPTH * 0.85), tilt, 0.32)


static func _industrial(body: SurfaceTool, light: SurfaceTool, variant: int) -> void:
	if variant == 0:
		# Striped block with a beacon on top.
		MeshFactory.add_box(body, Vector3(WIDTH, HALF_H * 2.0 - 0.1, DEPTH), _at(0, -0.05, 0), 0.1)
		MeshFactory.add_box(light, Vector3(0.18, 0.12, 0.18), _at(0, HALF_H - 0.04, 0), 0.25)
	else:
		# Two drums stacked across the lane, each with lit end rings.
		for y: float in [-0.23, 0.22]:
			var drum: Transform3D = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, y, 0))
			MeshFactory.add_prism(body, 0.22, 0.22, WIDTH * 0.96, 10, drum)
			for x: float in [-0.42, 0.42]:
				var ring: Transform3D = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x, y, 0))
				MeshFactory.add_prism(light, 0.226, 0.226, 0.05, 10, ring)


static func _mine(body: SurfaceTool, light: SurfaceTool, variant: int) -> void:
	# Sea mines on a short mooring post; spikes stay in the lane's plane so the
	# mine is no deeper than the hazard it stands for.
	var mines: Array = [[0.0, 0.05, 0.3]] if variant == 0 else [[-0.26, -0.04, 0.21], [0.26, 0.04, 0.21]]
	for m: Array in mines:
		var c: Vector3 = Vector3(float(m[0]), float(m[1]), 0)
		var r: float = float(m[2])
		MeshFactory.add_ball(body, r, 6, 10, _at(c.x, c.y, 0))
		var post_h: float = c.y - r + HALF_H
		MeshFactory.add_prism(body, 0.035, 0.035, post_h, 6, _at(c.x, -HALF_H + post_h * 0.5, 0))
		for k: int in 6:
			var ang: float = TAU * float(k) / 6.0 + 0.26
			var dir: Vector3 = Vector3(cos(ang), sin(ang), 0)
			var spike: Transform3D = Transform3D(Basis(Vector3.BACK, ang - PI * 0.5), c + dir * (r + 0.05))
			MeshFactory.add_prism(body, 0.045, 0.0, 0.12, 5, spike)
		MeshFactory.add_ball(light, 0.055, 3, 6, _at(c.x, c.y + r + 0.02, 0))


static func _pods(body: SurfaceTool, light: SurfaceTool, variant: int) -> void:
	var pods: Array = (
		[[-0.36, 0.78, 0.15], [0.0, 0.92, 0.17], [0.36, 0.7, 0.15]]
		if variant == 0
		else [[-0.22, 0.62, 0.2], [0.24, 0.9, 0.22]]
	)
	for p: Array in pods:
		var x: float = float(p[0])
		var h: float = float(p[1])
		var r: float = float(p[2])
		var stem_h: float = h - r
		MeshFactory.add_prism(body, r * 0.75, r, stem_h, 8, _at(x, -HALF_H + stem_h * 0.5, 0))
		MeshFactory.add_ball(body, r, 4, 8, _at(x, -HALF_H + stem_h, 0))
		MeshFactory.add_ball(light, r * 0.32, 3, 6, _at(x, -HALF_H + stem_h + r * 0.9, 0))


static func _ice(body: SurfaceTool, variant: int) -> void:
	if variant == 0:
		MeshFactory.add_box(body, Vector3(WIDTH, HALF_H * 2.0, DEPTH), _at(0, 0, 0), 0.12)
	else:
		MeshFactory.add_box(body, Vector3(WIDTH, 0.18, DEPTH), _at(0, -HALF_H + 0.09, 0), 0.25)
		for s: Vector2 in [Vector2(-0.42, 0.7), Vector2(-0.14, 0.86), Vector2(0.14, 0.78), Vector2(0.42, 0.66)]:
			MeshFactory.add_prism(body, 0.14, 0.0, s.y, 6, _at(s.x, -HALF_H + 0.16 + s.y * 0.5, 0))


static func _rust(body: SurfaceTool, light: SurfaceTool, variant: int) -> void:
	if variant == 0:
		# Two upright barrels with a lit warning ring.
		for x: float in [-0.29, 0.29]:
			MeshFactory.add_prism(body, 0.23, 0.23, HALF_H * 2.0, 10, _at(x, 0, 0))
			MeshFactory.add_prism(light, 0.236, 0.236, 0.05, 10, _at(x, 0.16, 0))
	else:
		MeshFactory.add_box(body, Vector3(WIDTH, HALF_H * 2.0, DEPTH), _at(0, 0, 0), 0.06)
		MeshFactory.add_box(light, Vector3(0.16, 0.1, 0.16), _at(0.38, HALF_H + 0.04, 0), 0.25)


static func _monolith(body: SurfaceTool, variant: int) -> void:
	if variant == 0:
		MeshFactory.add_box(body, Vector3(WIDTH * 0.9, 1.0, DEPTH * 0.7), _at(0, 0.05, 0), 0.05)
	else:
		# Flattened obelisk: a four-sided frustum squashed to the hazard depth.
		var turn: Basis = Basis(Vector3.UP, PI * 0.25)
		var xform: Transform3D = Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.42)) * turn, Vector3(0, 0.07, 0))
		MeshFactory.add_prism(body, 0.62, 0.2, 1.04, 4, xform)


static func _candy(body: SurfaceTool, variant: int) -> void:
	if variant == 0:
		MeshFactory.add_box(body, Vector3(WIDTH, HALF_H * 2.0, DEPTH), _at(0, 0, 0), 0.38)
	else:
		# Lollipop facing the player on a short stick.
		var disc: Transform3D = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.12, 0))
		MeshFactory.add_prism(body, 0.4, 0.4, DEPTH * 0.55, 16, disc)
		MeshFactory.add_prism(body, 0.045, 0.045, 0.4, 6, _at(0, -HALF_H + 0.2, 0))


static func _begin() -> SurfaceTool:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


static func _commit(body: SurfaceTool, light: SurfaceTool, lit: bool) -> ArrayMesh:
	var mesh: ArrayMesh = body.commit()
	if lit:
		light.commit(mesh)
	return mesh
