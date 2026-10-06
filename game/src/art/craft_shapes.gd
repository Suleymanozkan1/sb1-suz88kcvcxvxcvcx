class_name CraftShapes
extends RefCounted
## The player character: a small flux craft carrying the energy core under its
## glass canopy (ART_DIRECTION §4). The camera sits behind it, so it reads by
## its back: wings, fins, glowing engines and their flames. Each form is its
## own craft, so the silhouette still tells the tap meaning:
##
## * HOP: the Glider, a sleek fighter with swept delta wings, wingtip pods, twin
##   canted fins and twin engines;
## * PHASE: the Prism, a faceted energy crystal in a glass case on a keel, with
##   blade wings and shards floating off their tips (the phase colour fills it);
## * DASH: the Dart, a long needle with canards, wings swept right back, twin
##   fins and one big engine;
## * SURGE: the Hauler, a wide boxy hull with engine pods on stub wings
##   (CoreView adds its ring).
##
## Built at the core's scale (radius 0.3): -Z is forward (the direction of
## travel), +Z is the back the camera sees, +Y is up. Surfaces: 0 hull paint
## (craft_hull.gdshader: panel seams, stripes in the skin colour), 1 trim
## (dark metal: nacelles, nozzle petals, turbine blades, canopy frame, pods),
## 2 energy (the core under the canopy, the crystal, leading-edge strips,
## nozzle glow, wingtip lights; drawn with the core shader so skins show),
## 3 glass (craft_glass.gdshader: the canopy over the core).
##
## Hulls are lofted through superellipse cross-sections (rounder on top,
## flatter underneath) and wings and fins carry a real symmetric airfoil
## (NACA 00xx) that tapers to the tip, all smooth-shaded from the surface's own
## derivatives; nozzles have iris petals, a recessed glow and turbine blades in
## front of it, so the engines read as machinery from the camera's seat.

const SURFACE_HULL: int = 0
const SURFACE_TRIM: int = 1
const SURFACE_ENERGY: int = 2
const SURFACE_GLASS: int = 3
## Engines per form: nozzle centre (x, y, z) and radius (w). Flames start there
## and point back (+Z).
const ENGINES: Dictionary[int, Array] = {
	SimConst.Form.HOP: [Vector4(-0.1, -0.03, 0.345, 0.038), Vector4(0.1, -0.03, 0.345, 0.038)],
	SimConst.Form.PHASE: [Vector4(0.0, -0.005, 0.355, 0.045)],
	SimConst.Form.DASH: [Vector4(0.0, -0.004, 0.43, 0.062)],
	SimConst.Form.SURGE: [Vector4(-0.235, -0.02, 0.275, 0.05), Vector4(0.235, -0.02, 0.275, 0.05)],
}
## Wingtip trailing points (right side; mirrored for the left) where the
## vapour trails start (GameplayView).
const WINGTIPS: Dictionary[int, Vector3] = {
	SimConst.Form.HOP: Vector3(0.435, 0.025, 0.27),
	SimConst.Form.PHASE: Vector3(0.43, 0.12, 0.22),
	SimConst.Form.DASH: Vector3(0.33, -0.03, 0.38),
	SimConst.Form.SURGE: Vector3(0.235, 0.05, 0.2),
}
## Hull paint layout per form (craft_hull.gdshader): fuselage half width (the
## spine stripe and panel seams live inside it) and half span (the wing band
## sits near the tips).
const PAINT_LAYOUT: Dictionary[int, Vector2] = {
	SimConst.Form.HOP: Vector2(0.16, 0.44),
	SimConst.Form.PHASE: Vector2(0.06, 0.43),
	SimConst.Form.DASH: Vector2(0.1, 0.33),
	SimConst.Form.SURGE: Vector2(0.19, 0.3),
}
const FLAME_SIDES: int = 10
## Kept for the old flat parts (fins of the Prism's shards).
const WING_THICK: float = 0.022
## Tessellation.
const LOFT_SIDES: int = 24
const NACELLE_SIDES: int = 18
const WING_CHORD_POINTS: int = 9
const WING_SPAN_STEPS: int = 4
const DOME_RINGS: int = 7
const DOME_SEGMENTS: int = 20
const SMALL_RINGS: int = 8
const SMALL_SEGMENTS: int = 16
const TUBE_SIDES: int = 16
## Engine nozzle detail.
const NOZZLE_PETALS: int = 14
const PETAL_LENGTH: float = 0.03
const TURBINE_BLADES: int = 9
const BLADE_TWIST: float = 0.45

static var _cache: Dictionary[int, ArrayMesh] = {}
static var _flames: Dictionary[int, ArrayMesh] = {}


static func build(form: int) -> ArrayMesh:
	if _cache.has(form):
		return _cache[form]
	var hull: SurfaceTool = _begin()
	var trim: SurfaceTool = _begin()
	var energy: SurfaceTool = _begin()
	var glass: SurfaceTool = _begin()
	match form:
		SimConst.Form.PHASE:
			_prism(hull, trim, energy, glass)
		SimConst.Form.DASH:
			_dart(hull, trim, energy, glass)
		SimConst.Form.SURGE:
			_hauler(hull, trim, energy, glass)
		_:
			_glider(hull, trim, energy, glass)
	for e: Vector4 in engines(form):
		_nozzle(trim, energy, Vector3(e.x, e.y, e.z), e.w)
	var mesh: ArrayMesh = hull.commit()
	trim.commit(mesh)
	energy.commit(mesh)
	glass.commit(mesh)
	_cache[form] = mesh
	return mesh


static func engines(form: int) -> Array[Vector4]:
	var out: Array[Vector4] = []
	for e: Variant in ENGINES.get(form, ENGINES[SimConst.Form.HOP]) as Array:
		out.append(e as Vector4)
	return out


## Both wingtips' trailing points of [param form] (left, right).
static func wingtips(form: int) -> Array[Vector3]:
	var tip: Vector3 = WINGTIPS.get(form, WINGTIPS[SimConst.Form.HOP]) as Vector3
	return [Vector3(-tip.x, tip.y, tip.z), tip]


static func paint_layout(form: int) -> Vector2:
	return PAINT_LAYOUT.get(form, PAINT_LAYOUT[SimConst.Form.HOP]) as Vector2


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


# --- The four crafts ---------------------------------------------------------------


## Glider (HOP): lofted fighter hull, glass canopy over the core, swept delta
## wings with leading-edge lights and tip pods, twin canted fins, two engines in
## nacelles along the hull's flanks, ventral strakes and a spine antenna.
static func _glider(hull: SurfaceTool, trim: SurfaceTool, energy: SurfaceTool, glass: SurfaceTool) -> void:
	var body: Array[Vector4] = [
		Vector4(-0.44, 0.0, 0.0, -0.004),
		Vector4(-0.41, 0.022, 0.018, -0.004),
		Vector4(-0.35, 0.05, 0.04, -0.001),
		Vector4(-0.27, 0.078, 0.062, 0.006),
		Vector4(-0.17, 0.104, 0.078, 0.01),
		Vector4(-0.06, 0.124, 0.084, 0.01),
		Vector4(0.05, 0.14, 0.08, 0.005),
		Vector4(0.15, 0.148, 0.072, -0.002),
		Vector4(0.24, 0.142, 0.062, -0.01),
		Vector4(0.3, 0.126, 0.05, -0.016),
		Vector4(0.335, 0.1, 0.04, -0.018),
		Vector4(0.34, 0.0, 0.0, -0.018),
	]
	_loft(hull, body, 2.3, 3.4, 0.0)
	_canopy(glass, trim, energy, Vector3(0.0, 0.075, -0.14), Vector3(0.062, 0.07, 0.15))
	for side: float in [-1.0, 1.0]:
		_wing(hull, Vector3(0.1 * side, -0.004, -0.08), 0.36, Vector3(0.425 * side, 0.024, 0.15), 0.1, 0.085)
		_strip(energy, Vector3(0.105 * side, 0.0, -0.085), Vector3(0.425 * side, 0.026, 0.145), 0.012)
		# Tip pod with a light at its tail.
		_ball(trim, Vector3(0.016, 0.016, 0.075), Vector3(0.435 * side, 0.024, 0.2), SMALL_RINGS, SMALL_SEGMENTS)
		MeshFactory.add_box(
			energy, Vector3(0.022, 0.022, 0.03), _at(Vector3.ONE, Vector3(0.435 * side, 0.024, 0.27)), 0.3
		)
		# Twin fins canted outwards.
		_wing(hull, Vector3(0.07 * side, 0.045, 0.12), 0.19, Vector3(0.1 * side, 0.19, 0.25), 0.08, 0.07)
		# Engine nacelle along the flank, with its intake.
		_nacelle(
			hull,
			trim,
			Vector3(0.1 * side, -0.03, 0.0),
			[
				Vector2(-0.06, 0.03),
				Vector2(0.0, 0.045),
				Vector2(0.14, 0.05),
				Vector2(0.27, 0.048),
				Vector2(0.335, 0.044)
			]
		)
		# Ventral strake.
		_wing(hull, Vector3(0.05 * side, -0.05, 0.14), 0.14, Vector3(0.07 * side, -0.1, 0.24), 0.06, 0.06)
	# Spine antenna.
	MeshFactory.add_box(trim, Vector3(0.006, 0.04, 0.012), _at(Vector3.ONE, Vector3(0.0, 0.1, 0.06)), 0.3)


## Prism (PHASE): a faceted energy crystal in a glass case, carried on a slim
## keel, blade wings with energy edges and a shard floating off
## each tip; one engine at the keel's tail.
static func _prism(hull: SurfaceTool, trim: SurfaceTool, energy: SurfaceTool, glass: SurfaceTool) -> void:
	_gem(energy, Vector3(0.0, 0.05, -0.05), 1.0)
	_gem(glass, Vector3(0.0, 0.05, -0.05), 1.1)
	var keel: Array[Vector4] = [
		Vector4(-0.3, 0.0, 0.0, -0.06),
		Vector4(-0.24, 0.025, 0.02, -0.06),
		Vector4(-0.1, 0.045, 0.03, -0.065),
		Vector4(0.08, 0.055, 0.035, -0.055),
		Vector4(0.22, 0.055, 0.04, -0.03),
		Vector4(0.32, 0.05, 0.04, -0.012),
		Vector4(0.34, 0.0, 0.0, -0.01),
	]
	_loft(hull, keel, 2.4, 3.0, 0.0)
	for side: float in [-1.0, 1.0]:
		_wing(hull, Vector3(0.05 * side, -0.03, -0.04), 0.26, Vector3(0.42 * side, 0.1, 0.16), 0.06, 0.06)
		_strip(energy, Vector3(0.06 * side, -0.026, -0.046), Vector3(0.42 * side, 0.102, 0.155), 0.012)
		_shard(energy, Vector3(0.43 * side, 0.13, 0.24), side)
	_nacelle(hull, trim, Vector3(0.0, -0.005, 0.0), [Vector2(0.18, 0.05), Vector2(0.26, 0.055), Vector2(0.35, 0.05)])


## Dart (DASH): a long needle hull with a long canopy, canards, wings swept far
## back, twin canted fins and one big engine closing the tail.
static func _dart(hull: SurfaceTool, trim: SurfaceTool, energy: SurfaceTool, glass: SurfaceTool) -> void:
	var body: Array[Vector4] = [
		Vector4(-0.5, 0.0, 0.0, -0.002),
		Vector4(-0.46, 0.016, 0.014, -0.002),
		Vector4(-0.38, 0.038, 0.032, 0.002),
		Vector4(-0.26, 0.062, 0.052, 0.008),
		Vector4(-0.12, 0.082, 0.068, 0.01),
		Vector4(0.02, 0.094, 0.074, 0.008),
		Vector4(0.16, 0.1, 0.072, 0.004),
		Vector4(0.3, 0.094, 0.068, -0.002),
		Vector4(0.39, 0.082, 0.064, -0.004),
		Vector4(0.42, 0.074, 0.06, -0.004),
		Vector4(0.425, 0.0, 0.0, -0.004),
	]
	_loft(hull, body, 2.2, 3.0, 0.0)
	_canopy(glass, trim, energy, Vector3(0.0, 0.056, -0.2), Vector3(0.046, 0.058, 0.16))
	for side: float in [-1.0, 1.0]:
		_wing(hull, Vector3(0.05 * side, 0.0, -0.33), 0.09, Vector3(0.13 * side, 0.008, -0.27), 0.04, 0.07)
		_wing(hull, Vector3(0.075 * side, -0.01, 0.0), 0.36, Vector3(0.32 * side, -0.03, 0.28), 0.1, 0.07)
		_strip(energy, Vector3(0.08 * side, -0.006, -0.004), Vector3(0.32 * side, -0.028, 0.275), 0.012)
		MeshFactory.add_box(
			energy, Vector3(0.018, 0.016, 0.04), _at(Vector3.ONE, Vector3(0.325 * side, -0.03, 0.37)), 0.3
		)
		_wing(hull, Vector3(0.05 * side, 0.05, 0.18), 0.2, Vector3(0.1 * side, 0.19, 0.32), 0.08, 0.07)
	_ring(trim, Vector3(0.0, -0.004, 0.405), 0.082, 0.07, 0.03)
	MeshFactory.add_box(trim, Vector3(0.005, 0.035, 0.01), _at(Vector3.ONE, Vector3(0.0, 0.085, 0.1)), 0.3)


## Hauler (SURGE): a wide boxy hull with a broad canopy, engine pods on stub
## wings, intakes up front and a cargo spine; the weight ring is CoreView's.
static func _hauler(hull: SurfaceTool, trim: SurfaceTool, energy: SurfaceTool, glass: SurfaceTool) -> void:
	var body: Array[Vector4] = [
		Vector4(-0.3, 0.0, 0.0, 0.0),
		Vector4(-0.28, 0.06, 0.045, 0.0),
		Vector4(-0.22, 0.125, 0.09, 0.008),
		Vector4(-0.12, 0.172, 0.118, 0.01),
		Vector4(0.0, 0.188, 0.126, 0.008),
		Vector4(0.12, 0.18, 0.118, 0.0),
		Vector4(0.2, 0.15, 0.098, -0.01),
		Vector4(0.25, 0.11, 0.07, -0.016),
		Vector4(0.26, 0.0, 0.0, -0.016),
	]
	_loft(hull, body, 2.8, 4.5, 0.0)
	_canopy(glass, trim, energy, Vector3(0.0, 0.11, -0.12), Vector3(0.09, 0.066, 0.1))
	for side: float in [-1.0, 1.0]:
		_wing(hull, Vector3(0.15 * side, -0.01, -0.02), 0.2, Vector3(0.23 * side, -0.012, 0.0), 0.16, 0.1)
		_nacelle(
			hull,
			trim,
			Vector3(0.235 * side, -0.02, 0.0),
			[
				Vector2(-0.12, 0.05),
				Vector2(-0.06, 0.064),
				Vector2(0.1, 0.068),
				Vector2(0.22, 0.062),
				Vector2(0.275, 0.056)
			]
		)
		MeshFactory.add_box(
			energy, Vector3(0.016, 0.016, 0.05), _at(Vector3.ONE, Vector3(0.235 * side, 0.05, 0.05)), 0.3
		)
	# Cargo spine with panel ribs.
	MeshFactory.add_box(hull, Vector3(0.07, 0.03, 0.2), _at(Vector3.ONE, Vector3(0.0, 0.13, 0.08)), 0.25)
	for k: int in 3:
		MeshFactory.add_box(
			trim, Vector3(0.076, 0.012, 0.012), _at(Vector3.ONE, Vector3(0.0, 0.146, 0.02 + 0.06 * k)), 0.3
		)


# --- Parts ---------------------------------------------------------------------------


## Glass canopy dome over the core: the core glows inside it (energy), a thin
## frame bow crosses it and a sill runs round its base (trim).
static func _canopy(glass: SurfaceTool, trim: SurfaceTool, energy: SurfaceTool, at: Vector3, size: Vector3) -> void:
	_dome(glass, size, at)
	_ball(
		energy,
		size * Vector3(0.7, 0.62, 0.66),
		at + Vector3(0.0, size.y * 0.12, size.z * 0.05),
		SMALL_RINGS,
		SMALL_SEGMENTS
	)
	# Frame bow across the dome, a third of the way back.
	var dz: float = size.z * 0.3
	var f: float = sqrt(maxf(1.0 - pow(dz / size.z, 2.0), 0.0))
	var arc: Array[Vector3] = []
	for i: int in 7:
		var a: float = PI * float(i) / 6.0
		arc.append(at + Vector3(cos(a) * size.x * f * 1.04, sin(a) * size.y * f * 1.04, dz))
	for i: int in 6:
		_strip(trim, arc[i], arc[i + 1], 0.009)
	# Sill round the base.
	var sill: Array[Vector3] = []
	for i: int in 13:
		var b: float = TAU * float(i) / 12.0
		sill.append(at + Vector3(cos(b) * size.x * 1.03, 0.0, sin(b) * size.z * 1.03))
	for i: int in 12:
		_strip(trim, sill[i], sill[i + 1], 0.01)


## The Prism's crystal: an eight-sided gem (two rings between a long nose and a
## shorter tail point), flat faceted faces; [param grow] scales it (the glass
## case is the same gem, larger).
static func _gem(st: SurfaceTool, at: Vector3, grow: float) -> void:
	var nose: Vector3 = at + Vector3(0.0, -0.01, -0.39) * grow
	var tail: Vector3 = at + Vector3(0.0, 0.0, 0.3) * grow
	var front: Array[Vector3] = []
	var back: Array[Vector3] = []
	for k: int in 8:
		var a: float = TAU * float(k) / 8.0 + PI / 8.0
		var up: float = 1.0 if sin(a) > 0.0 else 0.62
		front.append(at + Vector3(cos(a) * 0.12, sin(a) * 0.16 * up, -0.08) * grow)
		back.append(at + Vector3(cos(a) * 0.095, sin(a) * 0.125 * up, 0.08) * grow)
	for k: int in 8:
		var k1: int = (k + 1) % 8
		_face_from(st, nose, front[k], front[k1], at)
		_face_from(st, front[k], back[k], back[k1], at)
		_face_from(st, front[k], back[k1], front[k1], at)
		_face_from(st, tail, back[k1], back[k], at)


## A crystal shard floating off a wingtip: a thin bipyramid leaning outwards.
static func _shard(st: SurfaceTool, at: Vector3, side: float) -> void:
	var top: Vector3 = at + Vector3(0.02 * side, 0.07, -0.01)
	var bottom: Vector3 = at + Vector3(-0.01 * side, -0.05, 0.01)
	var ring: Array[Vector3] = [
		at + Vector3(0.02, 0.0, 0.0),
		at + Vector3(0.0, 0.0, 0.03),
		at + Vector3(-0.02, 0.0, 0.0),
		at + Vector3(0.0, 0.0, -0.03)
	]
	for k: int in 4:
		_face_from(st, top, ring[k], ring[(k + 1) % 4], at)
		_face_from(st, bottom, ring[(k + 1) % 4], ring[k], at)


## Engine nacelle: a round loft along Z at [param at] (x, y) through
## (z, radius) stations, with a dark intake face at its front.
static func _nacelle(hull: SurfaceTool, trim: SurfaceTool, at: Vector3, stations: Array) -> void:
	var sections: Array[Vector4] = []
	for s: Variant in stations:
		var v: Vector2 = s as Vector2
		sections.append(Vector4(v.x, v.y, v.y, at.y))
	_loft(hull, sections, 2.0, 2.0, at.x, NACELLE_SIDES)
	var front: Vector4 = sections[0]
	_disc(trim, Vector3(at.x, at.y, front.x + 0.004), front.y * 0.86, Vector3.FORWARD, NACELLE_SIDES)
	_ring(trim, Vector3(at.x, at.y, front.x + 0.004), front.y * 1.04, front.y * 0.84, 0.012)


## A detailed nozzle at [param at]: a ring of iris petals converging a little
## behind it, a recessed glowing disc (energy), turbine blades and a centre
## cone in front of the glow (trim), so the glow shows between the blades.
static func _nozzle(trim: SurfaceTool, energy: SurfaceTool, at: Vector3, radius: float) -> void:
	_ring(trim, at + Vector3(0.0, 0.0, -0.006), radius * 1.16, radius * 0.98, 0.016)
	var gap: float = 0.035
	for k: int in NOZZLE_PETALS:
		var a0: float = TAU * float(k) / float(NOZZLE_PETALS) + gap
		var a1: float = TAU * float(k + 1) / float(NOZZLE_PETALS) - gap
		var f0: Vector3 = at + Vector3(cos(a0), sin(a0), 0.0) * radius * 1.12
		var f1: Vector3 = at + Vector3(cos(a1), sin(a1), 0.0) * radius * 1.12
		var b0: Vector3 = at + Vector3(cos(a0), sin(a0), 0.0) * radius * 1.0 + Vector3(0.0, 0.0, PETAL_LENGTH)
		var b1: Vector3 = at + Vector3(cos(a1), sin(a1), 0.0) * radius * 1.0 + Vector3(0.0, 0.0, PETAL_LENGTH)
		var mid: float = (a0 + a1) * 0.5
		var out: Vector3 = Vector3(cos(mid), sin(mid), 0.3).normalized()
		_tri(trim, f0, f1, b1, out)
		_tri(trim, f0, b1, b0, out)
		_tri(trim, f0, f1, b1, -out)
		_tri(trim, f0, b1, b0, -out)
	_disc(energy, at + Vector3(0.0, 0.0, -0.014), radius * 0.92, Vector3.BACK, TUBE_SIDES)
	for k: int in TURBINE_BLADES:
		var a: float = TAU * float(k) / float(TURBINE_BLADES)
		var dir: Vector3 = Vector3(cos(a), sin(a), 0.0)
		var across: Vector3 = Vector3(-sin(a), cos(a), 0.0)
		var tilt: Vector3 = (across + Vector3(0.0, 0.0, BLADE_TWIST)).normalized() * radius * 0.11
		var r0: Vector3 = at + dir * radius * 0.22 + Vector3(0.0, 0.0, -0.006)
		var r1: Vector3 = at + dir * radius * 0.84 + Vector3(0.0, 0.0, -0.006)
		_tri(trim, r0 - tilt, r1 - tilt, r1 + tilt, Vector3.BACK)
		_tri(trim, r0 - tilt, r1 + tilt, r0 + tilt, Vector3.BACK)
	var cone: Transform3D = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at + Vector3(0.0, 0.0, 0.004))
	MeshFactory.add_prism(trim, radius * 0.24, 0.0, 0.03, 10, cone)


# --- Surface builders ------------------------------------------------------------------


## A lofted body through cross-sections: each Vector4 is (z, half width, half
## height, centre y) at x = [param x]; the profile is a superellipse, rounder
## on top (exponent [param top_n]) than underneath ([param bottom_n]). A section
## of zero size closes that end in a point. Normals come from the surface's own
## partial derivatives, so the body shades as one smooth skin. [param sides]
## points go round each section.
static func _loft(
	st: SurfaceTool, sections: Array[Vector4], top_n: float, bottom_n: float, x: float, sides: int = LOFT_SIDES
) -> void:
	var rows: Array[PackedVector3Array] = []
	for s: Vector4 in sections:
		var row: PackedVector3Array = PackedVector3Array()
		for k: int in sides:
			row.append(_section_point(s, TAU * float(k) / float(sides), top_n, bottom_n, x))
		rows.append(row)
	var normals: Array[PackedVector3Array] = []
	var last: int = rows.size() - 1
	for i: int in rows.size():
		var nrow: PackedVector3Array = PackedVector3Array()
		var s: Vector4 = sections[i]
		var axis: Vector3 = Vector3(x, s.w, s.x)
		for k: int in sides:
			var p: Vector3 = rows[i][k]
			var around: Vector3 = rows[i][(k + 1) % sides] - rows[i][(k - 1 + sides) % sides]
			var along: Vector3 = rows[mini(i + 1, last)][k] - rows[maxi(i - 1, 0)][k]
			var n: Vector3 = around.cross(along)
			if around.length_squared() < 1e-10 or n.length_squared() < 1e-12:
				# A pointed end: the normal runs along the axis, away from the body.
				var neighbour: int = 1 if i == 0 else last - 1
				n = p - _centroid(rows[neighbour])
			elif n.dot(p - axis) < 0.0:
				n = -n
			nrow.append(n.normalized())
		normals.append(nrow)
	for i: int in last:
		for k: int in sides:
			var k1: int = (k + 1) % sides
			_quad_smooth(
				st,
				[rows[i][k], rows[i][k1], rows[i + 1][k1], rows[i + 1][k]],
				[normals[i][k], normals[i][k1], normals[i + 1][k1], normals[i + 1][k]]
			)


static func _section_point(s: Vector4, a: float, top_n: float, bottom_n: float, x: float) -> Vector3:
	var c: float = cos(a)
	var sn: float = sin(a)
	var e: float = 2.0 / (top_n if sn >= 0.0 else bottom_n)
	return Vector3(x + s.y * signf(c) * pow(absf(c), e), s.w + s.z * signf(sn) * pow(absf(sn), e), s.x)


static func _centroid(row: PackedVector3Array) -> Vector3:
	var c: Vector3 = Vector3.ZERO
	for p: Vector3 in row:
		c += p
	return c / float(maxi(row.size(), 1))


## A tapered wing (or fin) with a symmetric airfoil from the root's leading
## edge [param root_le] (chord [param root_chord] along +Z) to the tip's
## [param tip_le]; [param ratio] is the thickness over chord. The airfoil's
## thickness runs across the span in the XY plane, so the same builder makes
## wings, canted fins and strakes. Smooth along the chord and span, a flat cap
## closes the tip.
static func _wing(
	st: SurfaceTool, root_le: Vector3, root_chord: float, tip_le: Vector3, tip_chord: float, ratio: float
) -> void:
	var span_dir: Vector3 = tip_le - root_le
	var up: Vector3 = Vector3(span_dir.y, -span_dir.x, 0.0).normalized()
	var loop_n: int = WING_CHORD_POINTS * 2 - 2
	var rows: Array[PackedVector3Array] = []
	for j: int in WING_SPAN_STEPS + 1:
		var t: float = float(j) / float(WING_SPAN_STEPS)
		var le: Vector3 = root_le.lerp(tip_le, t)
		var chord: float = lerpf(root_chord, tip_chord, t)
		var row: PackedVector3Array = PackedVector3Array()
		for i: int in loop_n:
			var top: bool = i < WING_CHORD_POINTS
			var ci: int = i if top else 2 * WING_CHORD_POINTS - 2 - i
			var u: float = 0.5 - 0.5 * cos(PI * float(ci) / float(WING_CHORD_POINTS - 1))
			var half_t: float = _naca(u) * ratio * chord
			row.append(le + Vector3(0.0, 0.0, u * chord) + up * (half_t if top else -half_t))
		rows.append(row)
	var normals: Array[PackedVector3Array] = []
	var last: int = rows.size() - 1
	for j: int in rows.size():
		var nrow: PackedVector3Array = PackedVector3Array()
		var centre: Vector3 = _centroid(rows[j])
		for i: int in loop_n:
			var around: Vector3 = rows[j][(i + 1) % loop_n] - rows[j][(i - 1 + loop_n) % loop_n]
			var along: Vector3 = rows[mini(j + 1, last)][i] - rows[maxi(j - 1, 0)][i]
			var n: Vector3 = around.cross(along)
			if n.dot(rows[j][i] - centre) < 0.0:
				n = -n
			nrow.append(n.normalized())
		normals.append(nrow)
	for j: int in last:
		for i: int in loop_n:
			var i1: int = (i + 1) % loop_n
			_quad_smooth(
				st,
				[rows[j][i], rows[j][i1], rows[j + 1][i1], rows[j + 1][i]],
				[normals[j][i], normals[j][i1], normals[j + 1][i1], normals[j + 1][i]]
			)
	var tip: PackedVector3Array = rows[last]
	var tip_centre: Vector3 = _centroid(tip)
	var cap_n: Vector3 = span_dir.normalized()
	for i: int in loop_n:
		_tri(st, tip_centre, tip[i], tip[(i + 1) % loop_n], cap_n)


## Half thickness over chord of a NACA 00xx airfoil at chord position
## [param u] (0 leading edge, 1 trailing edge), for a thickness ratio of 1.
static func _naca(u: float) -> float:
	return 5.0 * (0.2969 * sqrt(u) - 0.126 * u - 0.3516 * u * u + 0.2843 * u * u * u - 0.1015 * u * u * u * u)


## Upper half of an ellipsoid (a canopy dome), smooth, open at its base.
static func _dome(st: SurfaceTool, scale: Vector3, center: Vector3) -> void:
	for r: int in DOME_RINGS:
		var lat0: float = PI * 0.5 * float(r) / float(DOME_RINGS)
		var lat1: float = PI * 0.5 * float(r + 1) / float(DOME_RINGS)
		for k: int in DOME_SEGMENTS:
			var lon0: float = TAU * float(k) / float(DOME_SEGMENTS)
			var lon1: float = TAU * float(k + 1) / float(DOME_SEGMENTS)
			var u00: Vector3 = _unit(lat0, lon0)
			var u01: Vector3 = _unit(lat0, lon1)
			var u10: Vector3 = _unit(lat1, lon0)
			var u11: Vector3 = _unit(lat1, lon1)
			_smooth_tri(st, scale, center, u00, u01, u11)
			if r < DOME_RINGS - 1:
				_smooth_tri(st, scale, center, u00, u11, u10)


## An open ring (short tube without caps) along Z at [param at]: outer and inner
## walls and the back face; used for nozzle lips, intakes and collars.
static func _ring(st: SurfaceTool, at: Vector3, outer: float, inner: float, length: float) -> void:
	var z0: float = at.z - length * 0.5
	var z1: float = at.z + length * 0.5
	for k: int in TUBE_SIDES:
		var a0: float = TAU * float(k) / float(TUBE_SIDES)
		var a1: float = TAU * float(k + 1) / float(TUBE_SIDES)
		var d0: Vector3 = Vector3(cos(a0), sin(a0), 0.0)
		var d1: Vector3 = Vector3(cos(a1), sin(a1), 0.0)
		var c: Vector3 = Vector3(at.x, at.y, 0.0)
		var o0: Vector3 = c + d0 * outer
		var o1: Vector3 = c + d1 * outer
		var i0: Vector3 = c + d0 * inner
		var i1: Vector3 = c + d1 * inner
		var zf: Vector3 = Vector3(0.0, 0.0, z0)
		var zb: Vector3 = Vector3(0.0, 0.0, z1)
		_quad_smooth(st, [o0 + zf, o1 + zf, o1 + zb, o0 + zb], [d0, d1, d1, d0])
		_quad_smooth(st, [i0 + zf, i1 + zf, i1 + zb, i0 + zb], [-d0, -d1, -d1, -d0])
		_tri(st, o0 + zb, o1 + zb, i1 + zb, Vector3.BACK)
		_tri(st, o0 + zb, i1 + zb, i0 + zb, Vector3.BACK)
		_tri(st, o0 + zf, o1 + zf, i1 + zf, Vector3.FORWARD)
		_tri(st, o0 + zf, i1 + zf, i0 + zf, Vector3.FORWARD)


## A flat disc facing [param n] (along ±Z).
static func _disc(st: SurfaceTool, at: Vector3, radius: float, n: Vector3, sides: int) -> void:
	for k: int in sides:
		var a0: float = TAU * float(k) / float(sides)
		var a1: float = TAU * float(k + 1) / float(sides)
		_tri(st, at, at + Vector3(cos(a0), sin(a0), 0.0) * radius, at + Vector3(cos(a1), sin(a1), 0.0) * radius, n)


## Smooth ellipsoid with half axes [param scale] at [param center]; normals are
## the ellipsoid's true normals, so it shades as one curved surface.
static func _ball(st: SurfaceTool, scale: Vector3, center: Vector3, rings: int, segments: int) -> void:
	for r: int in rings:
		var lat0: float = PI * float(r) / float(rings) - PI * 0.5
		var lat1: float = PI * float(r + 1) / float(rings) - PI * 0.5
		for k: int in segments:
			var lon0: float = TAU * float(k) / float(segments)
			var lon1: float = TAU * float(k + 1) / float(segments)
			var u00: Vector3 = _unit(lat0, lon0)
			var u01: Vector3 = _unit(lat0, lon1)
			var u10: Vector3 = _unit(lat1, lon0)
			var u11: Vector3 = _unit(lat1, lon1)
			if r > 0:
				_smooth_tri(st, scale, center, u00, u01, u11)
			if r < rings - 1:
				_smooth_tri(st, scale, center, u00, u11, u10)


static func _unit(lat: float, lon: float) -> Vector3:
	return Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))


## One triangle of a smooth ellipsoid from unit-sphere directions, wound as a
## front face seen from outside.
static func _smooth_tri(st: SurfaceTool, scale: Vector3, center: Vector3, a: Vector3, b: Vector3, c: Vector3) -> void:
	var corners: Array[Vector3] = [a, b, c]
	if (b - a).cross(c - a).dot(a + b + c) > 0.0:
		corners = [a, c, b]
	for u: Vector3 in corners:
		st.set_normal((u / scale).normalized())
		st.add_vertex(center + u * scale)


## Quad with per-corner normals, wound as a front face along those normals.
static func _quad_smooth(st: SurfaceTool, p: Array[Vector3], n: Array[Vector3]) -> void:
	var avg: Vector3 = (n[0] + n[1] + n[2] + n[3]).normalized()
	var order: PackedInt32Array = [0, 1, 2, 0, 2, 3]
	for t: int in 2:
		var i0: int = order[t * 3]
		var i1: int = order[t * 3 + 1]
		var i2: int = order[t * 3 + 2]
		if (p[i1] - p[i0]).cross(p[i2] - p[i0]).dot(avg) > 0.0:
			var tmp: int = i1
			i1 = i2
			i2 = tmp
		for j: int in [i0, i1, i2]:
			st.set_normal(n[j])
			st.add_vertex(p[j])


## A thin bar from [param a] to [param b] (light strips, frames).
static func _strip(st: SurfaceTool, a: Vector3, b: Vector3, thickness: float) -> void:
	var dir: Vector3 = b - a
	var y: Vector3 = dir.normalized()
	var helper: Vector3 = Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x: Vector3 = helper.cross(y).normalized()
	var basis: Basis = Basis(x, y, x.cross(y))
	MeshFactory.add_prism(st, thickness * 0.7, thickness * 0.7, dir.length(), 4, Transform3D(basis, (a + b) * 0.5))


## Flat triangle facing away from [param inside] (crystal facets).
static func _face_from(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
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
