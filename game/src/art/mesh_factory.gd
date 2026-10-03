class_name MeshFactory
extends RefCounted
## Procedural meshes that implement the shape language (docs/ART_DIRECTION.md §4).
## Every block shares one chamfer ratio; ribs and silhouettes are composed from
## the same chamfered primitive so the whole world speaks one geometric language.

const CHAMFER_RATIO: float = 0.08
const RIB_SPAN: float = 3.5
const RIB_HEIGHT: float = 3.8
const RIB_THICK: float = 0.22

static var _cache: Dictionary = {}


## Box with 45° chamfered edges and corners (flat-shaded facets catch light).
static func chamfered_box(size: Vector3, chamfer_ratio: float = CHAMFER_RATIO) -> ArrayMesh:
	var key: String = "cbox:%s:%f" % [str(size), chamfer_ratio]
	if _cache.has(key):
		return _cache[key] as ArrayMesh
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_chamfered_box(st, size, chamfer_ratio, Transform3D.IDENTITY)
	var mesh: ArrayMesh = st.commit()
	_cache[key] = mesh
	return mesh


static func _append_chamfered_box(st: SurfaceTool, size: Vector3, ratio: float, xform: Transform3D) -> void:
	var h: Vector3 = size * 0.5
	var c: float = minf(minf(size.x, size.y), size.z) * ratio
	var i: Vector3 = h - Vector3(c, c, c)
	# Main faces.
	for axis: int in 3:
		for s: float in [-1.0, 1.0]:
			var quad: Array[Vector3] = []
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p: Vector3 = Vector3.ZERO
				p[axis] = s * h[axis]
				p[(axis + 1) % 3] = corner.x * i[(axis + 1) % 3]
				p[(axis + 2) % 3] = corner.y * i[(axis + 2) % 3]
				quad.append(p)
			_add_quad(st, quad, xform)
	# Edge bevels.
	for a: int in 3:
		var b: int = (a + 1) % 3
		var third: int = (a + 2) % 3
		for sa: float in [-1.0, 1.0]:
			for sb: float in [-1.0, 1.0]:
				var quad2: Array[Vector3] = []
				for st3: float in [-1.0, 1.0]:
					var p1: Vector3 = Vector3.ZERO
					p1[a] = sa * h[a]
					p1[b] = sb * i[b]
					p1[third] = st3 * i[third]
					quad2.append(p1)
				for st4: float in [1.0, -1.0]:
					var p2: Vector3 = Vector3.ZERO
					p2[a] = sa * i[a]
					p2[b] = sb * h[b]
					p2[third] = st4 * i[third]
					quad2.append(p2)
				_add_quad(st, quad2, xform)
	# Corner facets.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var tri: Array[Vector3] = [
					Vector3(sx * h.x, sy * i.y, sz * i.z),
					Vector3(sx * i.x, sy * h.y, sz * i.z),
					Vector3(sx * i.x, sy * i.y, sz * h.z),
				]
				_add_tri(st, tri[0], tri[1], tri[2], xform)


static func _add_quad(st: SurfaceTool, q: Array[Vector3], xform: Transform3D) -> void:
	_add_tri(st, q[0], q[1], q[2], xform)
	_add_tri(st, q[0], q[2], q[3], xform)


## Adds a flat-shaded triangle with clockwise (Godot front-face) winding as
## seen from outside (away from the local origin).
static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, xform: Transform3D) -> void:
	var centroid: Vector3 = (a + b + c) / 3.0
	var n: Vector3 = (b - a).cross(c - a)
	if n.dot(centroid) > 0.0:
		var tmp: Vector3 = b
		b = c
		c = tmp
		n = -n
	var outward: Vector3 = (-n).normalized()
	var wn: Vector3 = (xform.basis * outward).normalized()
	for v: Vector3 in [a, b, c]:
		st.set_normal(wn)
		st.add_vertex(xform * v)


## Octahedral shard: the single collectible silhouette.
static func shard(radius: float, height: float) -> SphereMesh:
	var key: String = "shard:%f:%f" % [radius, height]
	if _cache.has(key):
		return _cache[key] as SphereMesh
	var d: SphereMesh = SphereMesh.new()
	d.radius = radius
	d.height = height
	d.radial_segments = 4
	d.rings = 2
	_cache[key] = d
	return d


## Shaft rib for a world profile, built from chamfered parts.
static func rib(profile: String) -> ArrayMesh:
	var key: String = "rib:" + profile
	if _cache.has(key):
		return _cache[key] as ArrayMesh
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var t: float = RIB_THICK
	match profile:
		"arch":
			_pillars(st, RIB_HEIGHT * 0.62, t)
			var segments: int = 9
			for s: int in segments:
				var a0: float = PI * float(s) / float(segments)
				var a1: float = PI * float(s + 1) / float(segments)
				var am: float = (a0 + a1) * 0.5
				var r: float = RIB_SPAN
				var center: Vector3 = Vector3(cos(am) * r, RIB_HEIGHT * 0.62 + sin(am) * r * 0.62, 0.0)
				var length: float = r * (a1 - a0) * 1.08
				var basis: Basis = Basis(Vector3.FORWARD, -(am - PI * 0.5) * 0.85)
				_append_chamfered_box(st, Vector3(length, t, t), CHAMFER_RATIO, Transform3D(basis, center))
		"hex":
			var radius: float = RIB_SPAN * 1.08
			var cy: float = RIB_HEIGHT * 0.45
			for s2: int in 6:
				if s2 == 4:
					continue
				var a: float = TAU * float(s2) / 6.0 + PI / 6.0
				var b: float = TAU * float(s2 + 1) / 6.0 + PI / 6.0
				var p0: Vector3 = Vector3(cos(a) * radius, cy + sin(a) * radius, 0.0)
				var p1: Vector3 = Vector3(cos(b) * radius, cy + sin(b) * radius, 0.0)
				var mid: Vector3 = (p0 + p1) * 0.5
				var ang: float = atan2(p1.y - p0.y, p1.x - p0.x)
				_append_chamfered_box(
					st, Vector3(p0.distance_to(p1) + t, t, t), CHAMFER_RATIO, Transform3D(Basis(Vector3.BACK, ang), mid)
				)
		"monolith":
			for side: float in [-1.0, 1.0]:
				_append_chamfered_box(
					st,
					Vector3(0.55, RIB_HEIGHT * 1.15, 1.1),
					CHAMFER_RATIO,
					Transform3D(Basis.IDENTITY, Vector3(side * (RIB_SPAN + 0.3), RIB_HEIGHT * 0.575, 0.0))
				)
		"lattice":
			for dz: float in [-0.35, 0.35]:
				_pillars(st, RIB_HEIGHT, t * 0.6, dz)
				_append_chamfered_box(
					st,
					Vector3(RIB_SPAN * 2.0 + t, t * 0.6, t * 0.6),
					CHAMFER_RATIO,
					Transform3D(Basis.IDENTITY, Vector3(0, RIB_HEIGHT, dz))
				)
			for side2: float in [-1.0, 1.0]:
				# Diagonal brace inside each pillar pair (structural, not ornamental).
				var brace: Basis = Basis(Vector3.BACK, side2 * 0.32)
				_append_chamfered_box(
					st,
					Vector3(t * 0.45, RIB_HEIGHT * 0.92, t * 0.45),
					CHAMFER_RATIO,
					Transform3D(brace, Vector3(side2 * (RIB_SPAN - 0.55), RIB_HEIGHT * 0.5, 0.0))
				)
		"facet":
			# Crystal clusters: hexagonal prisms with pyramid tips, a tall central
			# crystal flanked by two shorter ones leaning outwards (fixed rule).
			for side3: float in [-1.0, 1.0]:
				var base_x: float = side3 * (RIB_SPAN + 0.45)
				_crystal(st, Vector3(base_x, 0.0, 0.0), 0.34, RIB_HEIGHT * 0.95, 0.0)
				_crystal(st, Vector3(base_x - side3 * 0.42, 0.0, 0.18), 0.22, RIB_HEIGHT * 0.55, -side3 * 0.22)
				_crystal(st, Vector3(base_x + side3 * 0.38, 0.0, -0.2), 0.2, RIB_HEIGHT * 0.45, side3 * 0.3)
		"truss":
			# Foundry gantry: heavy columns, a crane beam and K-bracing under it.
			_pillars(st, RIB_HEIGHT, t * 1.5)
			_append_chamfered_box(
				st,
				Vector3(RIB_SPAN * 2.0 + t * 2.0, t * 1.6, t * 1.3),
				CHAMFER_RATIO,
				Transform3D(Basis.IDENTITY, Vector3(0, RIB_HEIGHT, 0))
			)
			for side5: float in [-1.0, 1.0]:
				var from: Vector3 = Vector3(side5 * RIB_SPAN, RIB_HEIGHT * 0.62, 0.0)
				var to: Vector3 = Vector3(side5 * RIB_SPAN * 0.35, RIB_HEIGHT - t * 0.8, 0.0)
				_strut(st, from, to, t * 0.7)
		"icicle":
			# Pointed ice arch (two straight limbs meeting at the apex) with spikes
			# hanging from it; the spike lengths follow a fixed rule, not noise.
			var apex: Vector3 = Vector3(0.0, RIB_HEIGHT * 1.12, 0.0)
			for side6: float in [-1.0, 1.0]:
				var foot: Vector3 = Vector3(side6 * RIB_SPAN, 0.0, 0.0)
				var knee: Vector3 = Vector3(side6 * RIB_SPAN, RIB_HEIGHT * 0.55, 0.0)
				_strut(st, foot, knee, t)
				_strut(st, knee, apex, t)
				for k: int in 3:
					var u: float = 0.25 + 0.25 * float(k)
					var at: Vector3 = knee.lerp(apex, u) - Vector3(0, t * 0.5, 0)
					_spike(st, at, t * 0.55, 0.35 + 0.22 * float((k + 1) % 3))
		"ring":
			# Station hoop: a near-complete circle around the shaft (the part
			# that would sit below the floor is omitted).
			var ring_r: float = RIB_SPAN * 1.12
			var ring_c: Vector3 = Vector3(0.0, RIB_HEIGHT * 0.5, 0.0)
			var seg_count: int = 14
			for s3: int in seg_count:
				var a0r: float = TAU * float(s3) / float(seg_count)
				var a1r: float = TAU * float(s3 + 1) / float(seg_count)
				var q0: Vector3 = ring_c + Vector3(cos(a0r), sin(a0r), 0.0) * ring_r
				var q1: Vector3 = ring_c + Vector3(cos(a1r), sin(a1r), 0.0) * ring_r
				if minf(q0.y, q1.y) < 0.05:
					continue
				_strut(st, q0, q1, t)
		"candy":
			# Twisted columns (stacked chamfered blocks turned a fixed step) and a
			# scalloped beam: playful, but still the one block family.
			for side7: float in [-1.0, 1.0]:
				var blocks: int = 9
				var bh: float = RIB_HEIGHT / float(blocks)
				for b: int in blocks:
					var twist: Basis = Basis(Vector3.UP, float(b) * PI / 9.0)
					_append_chamfered_box(
						st,
						Vector3(t * 1.7, bh * 0.92, t * 1.7),
						CHAMFER_RATIO * 2.0,
						Transform3D(twist, Vector3(side7 * RIB_SPAN, bh * (float(b) + 0.5), 0.0))
					)
			var scallops: int = 5
			for k2: int in scallops:
				var x0: float = lerpf(-RIB_SPAN, RIB_SPAN, float(k2) / float(scallops))
				var x1: float = lerpf(-RIB_SPAN, RIB_SPAN, float(k2 + 1) / float(scallops))
				var lift: float = 0.22
				_strut(st, Vector3(x0, RIB_HEIGHT, 0.0), Vector3((x0 + x1) * 0.5, RIB_HEIGHT + lift, 0.0), t)
				_strut(st, Vector3((x0 + x1) * 0.5, RIB_HEIGHT + lift, 0.0), Vector3(x1, RIB_HEIGHT, 0.0), t)
		_:
			_pillars(st, RIB_HEIGHT, t)
			_append_chamfered_box(
				st,
				Vector3(RIB_SPAN * 2.0 + t, t, t),
				CHAMFER_RATIO,
				Transform3D(Basis.IDENTITY, Vector3(0, RIB_HEIGHT, 0))
			)
	st.index()
	var mesh: ArrayMesh = st.commit()
	_cache[key] = mesh
	return mesh


## Chamfered beam from [param a] to [param b] (in the XY plane of the rib).
static func _strut(st: SurfaceTool, a: Vector3, b: Vector3, thickness: float) -> void:
	var mid: Vector3 = (a + b) * 0.5
	var ang: float = atan2(b.y - a.y, b.x - a.x)
	_append_chamfered_box(
		st,
		Vector3(a.distance_to(b) + thickness, thickness, thickness),
		CHAMFER_RATIO,
		Transform3D(Basis(Vector3.BACK, ang), mid)
	)


## Downward hexagonal spike hanging from [param top], built from the same
## flat-shaded triangles as the blocks (one vertex format per mesh).
static func _spike(st: SurfaceTool, top: Vector3, radius: float, length: float) -> void:
	var xform: Transform3D = Transform3D(Basis.IDENTITY, top - Vector3(0, length * 0.5, 0))
	var apex: Vector3 = Vector3(0, -length * 0.5, 0)
	var cap: Vector3 = Vector3(0, length * 0.5, 0)
	for k: int in 6:
		var a0: float = TAU * float(k) / 6.0
		var a1: float = TAU * float(k + 1) / 6.0
		var p0: Vector3 = Vector3(cos(a0) * radius, length * 0.5, sin(a0) * radius)
		var p1: Vector3 = Vector3(cos(a1) * radius, length * 0.5, sin(a1) * radius)
		_add_tri(st, p0, p1, apex, xform)
		_add_tri(st, p1, p0, cap, xform)


static func _crystal(st: SurfaceTool, base: Vector3, radius: float, height: float, lean: float) -> void:
	var body_h: float = height * 0.82
	var basis: Basis = Basis(Vector3.BACK, lean)
	var prism: CylinderMesh = CylinderMesh.new()
	prism.top_radius = radius
	prism.bottom_radius = radius
	prism.height = body_h
	prism.radial_segments = 6
	prism.rings = 1
	st.append_from(prism, 0, Transform3D(basis, base + basis * Vector3(0, body_h * 0.5, 0)))
	var tip: CylinderMesh = CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = radius
	tip.height = height - body_h
	tip.radial_segments = 6
	tip.rings = 1
	st.append_from(tip, 0, Transform3D(basis, base + basis * Vector3(0, body_h + (height - body_h) * 0.5, 0)))


static func _pillars(st: SurfaceTool, height: float, t: float, dz: float = 0.0) -> void:
	for side: float in [-1.0, 1.0]:
		_append_chamfered_box(
			st,
			Vector3(t, height, t),
			CHAMFER_RATIO,
			Transform3D(Basis.IDENTITY, Vector3(side * RIB_SPAN, height * 0.5, dz))
		)
		_append_chamfered_box(
			st,
			Vector3(t * 2.2, 0.08, t * 2.2),
			CHAMFER_RATIO,
			Transform3D(Basis.IDENTITY, Vector3(side * RIB_SPAN, 0.04, dz))
		)


## Far-background story silhouette for a world (flat, fog-tinted, no detail noise).
static func silhouette(kind: String) -> ArrayMesh:
	var key: String = "sil:" + kind
	if _cache.has(key):
		return _cache[key] as ArrayMesh
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"turbine":
			# A giant rotor: hub and six radial blades (one surface), outer ring
			# committed as a second surface (formats never mixed).
			var hub: Vector3 = Vector3(0, 30, 0)
			for b: int in 6:
				var a: float = TAU * float(b) / 6.0
				var dir: Vector3 = Vector3(cos(a), sin(a), 0)
				_append_chamfered_box(
					st, Vector3(19.0, 3.6, 1.0), 0.12, Transform3D(Basis(Vector3.BACK, a), hub + dir * 12.5)
				)
			_append_chamfered_box(st, Vector3(7, 7, 2.4), 0.25, Transform3D(Basis.IDENTITY, hub))
			var blades: ArrayMesh = st.commit()
			var ring_st: SurfaceTool = SurfaceTool.new()
			ring_st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var rim: TorusMesh = TorusMesh.new()
			rim.inner_radius = 23.0
			rim.outer_radius = 24.5
			rim.rings = 48
			rim.ring_segments = 6
			ring_st.append_from(rim, 0, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1, 1, 0.5)), hub))
			ring_st.commit(blades)
			_cache[key] = blades
			return blades
		"ridge", "glacier":
			# Mountain range: triangular prisms with rule-based widths/heights.
			var peaks: Array[Vector3] = [
				Vector3(-64, 20, 26),
				Vector3(-40, 32, 30),
				Vector3(-18, 24, 24),
				Vector3(4, 42, 34),
				Vector3(28, 28, 26),
				Vector3(50, 36, 30),
				Vector3(70, 18, 22)
			]
			var sharp: float = 0.5 if kind == "ridge" else 0.62
			for p: Vector3 in peaks:
				var pm: PrismMesh = PrismMesh.new()
				pm.left_to_right = sharp
				pm.size = Vector3(p.z, p.y, 4.0)
				st.append_from(pm, 0, Transform3D(Basis.IDENTITY, Vector3(p.x, p.y * 0.5, 0.0)))
		"chimneys", "towers", "pylons":
			var heights: Array[float] = [34.0, 46.0, 28.0, 52.0, 38.0, 30.0]
			var xs: Array[float] = [-48.0, -30.0, -14.0, 14.0, 32.0, 50.0]
			var width: float = 5.0 if kind == "chimneys" else (7.0 if kind == "towers" else 2.2)
			for n: int in xs.size():
				_append_chamfered_box(
					st,
					Vector3(width, heights[n], width),
					0.15,
					Transform3D(Basis.IDENTITY, Vector3(xs[n], heights[n] * 0.5, 0.0))
				)
		"dome", "reactor", "canopy":
			var dome: SphereMesh = SphereMesh.new()
			dome.radius = 30.0
			dome.height = 60.0
			dome.radial_segments = 24
			dome.rings = 12
			dome.is_hemisphere = true
			st.append_from(dome, 0, Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 0.7, 0.4)), Vector3(0, -2, 0)))
			if kind == "reactor":
				var torus: TorusMesh = TorusMesh.new()
				torus.inner_radius = 34.0
				torus.outer_radius = 36.0
				st.append_from(
					torus, 0, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1, 1, 0.3)), Vector3(0, 18, 0))
				)
		_:
			var ring: TorusMesh = TorusMesh.new()
			ring.inner_radius = 44.0
			ring.outer_radius = 46.0
			ring.rings = 48
			st.append_from(
				ring, 0, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1, 1, 0.25)), Vector3(0, 12, 0))
			)
	var mesh: ArrayMesh = st.commit()
	_cache[key] = mesh
	return mesh
