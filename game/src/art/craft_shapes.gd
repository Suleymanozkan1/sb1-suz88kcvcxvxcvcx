class_name CraftShapes
extends RefCounted
## The player character: a small flux craft carrying the energy core in its
## canopy (ART_DIRECTION §4). The camera sits behind it, so it reads by its
## back: wings, glowing engines and their flames. Each form is its own craft,
## so the silhouette still tells the tap meaning:
##
## * HOP: the Glider, a rounded hull with swept wings and twin engines;
## * PHASE: the Prism, a tall crystal hull with blade wings (all energy, so the
##   phase colour fills it);
## * DASH: the Dart, a long needle with wings swept right back and one big
##   engine;
## * SURGE: the Hauler, a chunky round hull (CoreView adds its ring).
##
## Built at the core's scale (radius 0.3): -Z is forward (the direction of
## travel), +Z is the back the camera sees, +Y is up. Every craft has three
## surfaces: 0 hull paint, 1 trim (metal: engines, fins), 2 energy (canopy core,
## crystal, nozzles, wing lights; drawn with the core shader so skins show).

const SURFACE_HULL: int = 0
const SURFACE_TRIM: int = 1
const SURFACE_ENERGY: int = 2
## Engines per form: nozzle centre (x, y, z) and radius (w). Flames start there
## and point back (+Z).
const ENGINES: Dictionary[int, Array] = {
	SimConst.Form.HOP: [Vector4(-0.1, -0.03, 0.3, 0.042), Vector4(0.1, -0.03, 0.3, 0.042)],
	SimConst.Form.PHASE: [Vector4(0.0, -0.01, 0.34, 0.05)],
	SimConst.Form.DASH: [Vector4(0.0, 0.0, 0.47, 0.07)],
	SimConst.Form.SURGE: [Vector4(-0.1, -0.03, 0.26, 0.045), Vector4(0.1, -0.03, 0.26, 0.045)],
}
const WING_THICK: float = 0.022
const FLAME_SIDES: int = 10

static var _cache: Dictionary[int, ArrayMesh] = {}
static var _flames: Dictionary[int, ArrayMesh] = {}


static func build(form: int) -> ArrayMesh:
	if _cache.has(form):
		return _cache[form]
	var hull: SurfaceTool = _begin()
	var trim: SurfaceTool = _begin()
	var energy: SurfaceTool = _begin()
	match form:
		SimConst.Form.PHASE:
			_prism(hull, trim, energy)
		SimConst.Form.DASH:
			_dart(hull, trim, energy)
		SimConst.Form.SURGE:
			_hauler(hull, trim, energy)
		_:
			_glider(hull, trim, energy)
	for e: Vector4 in engines(form):
		_nozzle(trim, energy, Vector3(e.x, e.y, e.z), e.w)
	var mesh: ArrayMesh = hull.commit()
	trim.commit(mesh)
	energy.commit(mesh)
	_cache[form] = mesh
	return mesh


static func engines(form: int) -> Array[Vector4]:
	var out: Array[Vector4] = []
	for e: Variant in ENGINES.get(form, ENGINES[SimConst.Form.HOP]) as Array:
		out.append(e as Vector4)
	return out


## Engine flames for [param form]: one cone per engine from its nozzle back
## along +Z, UV.y 0 at the nozzle and 1 at the tip (flame.gdshader).
static func flames(form: int) -> ArrayMesh:
	if _flames.has(form):
		return _flames[form]
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for e: Vector4 in engines(form):
		var base: Vector3 = Vector3(e.x, e.y, e.z)
		var tip: Vector3 = base + Vector3(0.0, 0.0, 1.0)
		for k: int in FLAME_SIDES:
			var a0: float = TAU * float(k) / float(FLAME_SIDES)
			var a1: float = TAU * float(k + 1) / float(FLAME_SIDES)
			var p0: Vector3 = base + Vector3(cos(a0), sin(a0), 0.0) * e.w
			var p1: Vector3 = base + Vector3(cos(a1), sin(a1), 0.0) * e.w
			for v: Array in [[p0, 0.0], [p1, 0.0], [tip, 1.0]]:
				var p: Vector3 = v[0]
				st.set_uv(Vector2(float(k) / float(FLAME_SIDES), float(v[1])))
				st.set_normal((p - base).normalized() if p != tip else Vector3.BACK)
				st.add_vertex(p)
	var mesh: ArrayMesh = st.commit()
	_flames[form] = mesh
	return mesh


static func _begin() -> SurfaceTool:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _at(scale: Vector3, pos: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(scale), pos)


## Glider (HOP): rounded hull, glass canopy with the core inside, swept wings
## with tip lights, a tail fin and twin engines.
static func _glider(hull: SurfaceTool, trim: SurfaceTool, energy: SurfaceTool) -> void:
	MeshFactory.add_ball(hull, 1.0, 6, 12, _at(Vector3(0.16, 0.12, 0.33), Vector3(0.0, 0.0, 0.02)))
	MeshFactory.add_ball(energy, 1.0, 5, 12, _at(Vector3(0.1, 0.085, 0.17), Vector3(0.0, 0.085, -0.07)))
	for side: float in [-1.0, 1.0]:
		var wing: PackedVector2Array = [
			Vector2(0.1 * side, -0.06), Vector2(0.37 * side, 0.12), Vector2(0.37 * side, 0.2), Vector2(0.1 * side, 0.18)
		]
		_slab(hull, wing, -0.02, WING_THICK, 0.06)
		_strip(energy, Vector3(0.1 * side, -0.004, -0.066), Vector3(0.37 * side, 0.056, 0.114), 0.016)
		MeshFactory.add_box(energy, Vector3(0.035, 0.03, 0.08), _at(Vector3.ONE, Vector3(0.375 * side, 0.0, 0.16)), 0.2)
		MeshFactory.add_prism(
			trim, 0.058, 0.05, 0.2, 8, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.1 * side, -0.03, 0.2))
		)
	_fin(hull, Vector3(0.0, 0.08, 0.08), Vector3(0.0, 0.2, 0.25), Vector3(0.0, 0.08, 0.27))


## Prism (PHASE): a tall crystal hull (energy) with two blade wings.
static func _prism(hull: SurfaceTool, trim: SurfaceTool, energy: SurfaceTool) -> void:
	var nose: Vector3 = Vector3(0.0, 0.0, -0.42)
	var tail: Vector3 = Vector3(0.0, 0.0, 0.3)
	var left: Vector3 = Vector3(-0.17, 0.0, -0.02)
	var right: Vector3 = Vector3(0.17, 0.0, -0.02)
	var top: Vector3 = Vector3(0.0, 0.27, -0.04)
	var bottom: Vector3 = Vector3(0.0, -0.13, -0.04)
	var ring: Array[Vector3] = [top, right, bottom, left]
	for k: int in 4:
		var a: Vector3 = ring[k]
		var b: Vector3 = ring[(k + 1) % 4]
		_face(energy, nose, a, b)
		_face(energy, tail, b, a)
	for side: float in [-1.0, 1.0]:
		var blade: PackedVector2Array = [
			Vector2(0.12 * side, -0.12),
			Vector2(0.43 * side, 0.18),
			Vector2(0.36 * side, 0.22),
			Vector2(0.14 * side, 0.14)
		]
		_slab(hull, blade, 0.02, WING_THICK * 0.8, 0.22)
		_strip(energy, Vector3(0.12 * side, 0.03, -0.126), Vector3(0.43 * side, 0.25, 0.174), 0.014)
	MeshFactory.add_prism(
		trim, 0.06, 0.055, 0.1, 8, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, -0.01, 0.29))
	)


## Dart (DASH): a long needle hull, canopy, wings swept right back, twin tail
## fins and one big engine.
static func _dart(hull: SurfaceTool, trim: SurfaceTool, energy: SurfaceTool) -> void:
	MeshFactory.add_ball(hull, 1.0, 6, 12, _at(Vector3(0.115, 0.105, 0.44), Vector3(0.0, 0.0, 0.0)))
	MeshFactory.add_ball(energy, 1.0, 5, 12, _at(Vector3(0.066, 0.055, 0.16), Vector3(0.0, 0.08, -0.1)))
	for side: float in [-1.0, 1.0]:
		var wing: PackedVector2Array = [
			Vector2(0.08 * side, 0.02), Vector2(0.3 * side, 0.3), Vector2(0.3 * side, 0.36), Vector2(0.08 * side, 0.28)
		]
		_slab(hull, wing, -0.03, WING_THICK, -0.04)
		_strip(energy, Vector3(0.08 * side, -0.018, 0.014), Vector3(0.3 * side, -0.058, 0.294), 0.016)
		MeshFactory.add_box(
			energy, Vector3(0.03, 0.025, 0.09), _at(Vector3.ONE, Vector3(0.3 * side, -0.045, 0.32)), 0.2
		)
		_fin(hull, Vector3(0.06 * side, 0.05, 0.2), Vector3(0.12 * side, 0.19, 0.36), Vector3(0.06 * side, 0.05, 0.38))
	MeshFactory.add_prism(
		trim, 0.085, 0.075, 0.14, 10, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, 0.4))
	)


## Hauler (SURGE): a chunky round hull with a canopy dome, side pods and twin
## engines; the weight ring is CoreView's.
static func _hauler(hull: SurfaceTool, trim: SurfaceTool, energy: SurfaceTool) -> void:
	MeshFactory.add_ball(hull, 1.0, 7, 12, _at(Vector3(0.21, 0.17, 0.25), Vector3(0.0, 0.0, 0.0)))
	MeshFactory.add_ball(energy, 1.0, 5, 12, _at(Vector3(0.1, 0.07, 0.11), Vector3(0.0, 0.14, -0.04)))
	for side: float in [-1.0, 1.0]:
		MeshFactory.add_ball(trim, 1.0, 4, 8, _at(Vector3(0.07, 0.07, 0.14), Vector3(0.2 * side, -0.02, 0.05)))
		MeshFactory.add_box(
			energy, Vector3(0.025, 0.025, 0.07), _at(Vector3.ONE, Vector3(0.27 * side, -0.02, 0.05)), 0.2
		)
		MeshFactory.add_prism(
			trim, 0.06, 0.05, 0.14, 8, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.1 * side, -0.03, 0.18))
		)


## A thin light strip from [param a] to [param b] (wing leading edges).
static func _strip(st: SurfaceTool, a: Vector3, b: Vector3, thickness: float) -> void:
	var dir: Vector3 = b - a
	var y: Vector3 = dir.normalized()
	var helper: Vector3 = Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x: Vector3 = helper.cross(y).normalized()
	var basis: Basis = Basis(x, y, x.cross(y))
	MeshFactory.add_prism(st, thickness * 0.7, thickness * 0.7, dir.length(), 4, Transform3D(basis, (a + b) * 0.5))


## A glowing nozzle disc closing the engine at [param at].
static func _nozzle(trim: SurfaceTool, energy: SurfaceTool, at: Vector3, radius: float) -> void:
	var xform: Transform3D = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at)
	MeshFactory.add_prism(
		trim, radius * 1.18, radius * 1.18, 0.012, 10, xform.translated_local(Vector3(0.0, -0.006, 0.0))
	)
	MeshFactory.add_prism(energy, radius, radius, 0.016, 10, xform.translated_local(Vector3(0.0, 0.006, 0.0)))


## A flat slab from a polygon in the XZ plane at height [param y], with
## [param thickness] and a dihedral: the outer end rises by [param lift] per
## unit of |x| (wings tilt up or down away from the hull).
static func _slab(st: SurfaceTool, poly: PackedVector2Array, y: float, thickness: float, lift: float) -> void:
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for p: Vector2 in poly:
		var h: float = y + absf(p.x) * lift / maxf(absf(poly[1].x), 0.001)
		top.append(Vector3(p.x, h + thickness * 0.5, p.y))
		bottom.append(Vector3(p.x, h - thickness * 0.5, p.y))
	var centre: Vector3 = Vector3.ZERO
	for p3: Vector3 in top:
		centre += p3
	centre /= float(top.size())
	var n: int = top.size()
	for k: int in range(1, n - 1):
		_tri(st, top[0], top[k], top[k + 1], Vector3.UP)
		_tri(st, bottom[0], bottom[k], bottom[k + 1], Vector3.DOWN)
	for k2: int in n:
		var a: Vector3 = top[k2]
		var b: Vector3 = top[(k2 + 1) % n]
		var c: Vector3 = bottom[(k2 + 1) % n]
		var d: Vector3 = bottom[k2]
		var side: Vector3 = (b - a).cross(Vector3.UP).normalized()
		if side.dot((a + b) * 0.5 - centre) < 0.0:
			side = -side
		_tri(st, a, b, c, side)
		_tri(st, a, c, d, side)


## A thin vertical fin through three points (root front, tip, root back).
static func _fin(st: SurfaceTool, root: Vector3, tip: Vector3, heel: Vector3) -> void:
	var n: Vector3 = (tip - root).cross(heel - root).normalized()
	var off: Vector3 = n * WING_THICK * 0.5
	_tri(st, root + off, tip + off, heel + off, n)
	_tri(st, root - off, tip - off, heel - off, -n)
	var mid: Vector3 = (root + tip + heel) / 3.0
	for pair: Array in [[root, tip], [tip, heel]]:
		var e0: Vector3 = pair[0]
		var e1: Vector3 = pair[1]
		var en: Vector3 = (e1 - e0).cross(n).normalized()
		if en.dot((e0 + e1) * 0.5 - mid) < 0.0:
			en = -en
		_tri(st, e0 + off, e1 + off, e1 - off, en)
		_tri(st, e0 + off, e1 - off, e0 - off, en)


## Flat triangle facing outwards from the origin (crystal faces).
static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	if n.dot((a + b + c) / 3.0) < 0.0:
		n = -n
	_tri(st, a, b, c, n)


## Flat triangle facing [param n], wound clockwise as seen from that side
## (Godot's front face), whatever order the corners come in.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var tmp: Vector3 = b
		b = c
		c = tmp
	for p: Vector3 in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(p)
