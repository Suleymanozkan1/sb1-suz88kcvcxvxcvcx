class_name SparkField
extends Node3D
## All sparks (and prisms) of a level drawn with one MultiMesh each — a single
## draw call regardless of count; prisms carry an orbiting ring (a third
## MultiMesh sharing the prism slots). Collected items pop (scale 1 → 1.25 → 0 in
## 120 ms, ART_DIRECTION §8) and then stay zero-scaled; magnet pulls are
## animated per frame.

const SPARK_SHADER: Shader = preload("res://assets/shaders/spark.gdshader")
const SPARK_Y: float = 0.38
const TILTED: Basis = Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))
const POP_TIME: float = 0.12
const POP_PEAK_SCALE: float = 1.25
## Fraction of POP_TIME spent growing to the peak before collapsing.
const POP_PEAK_AT: float = 0.35
const HIDDEN: Transform3D = Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
## Prism ring: radius round the 0.18 shard, tube, tilt off the floor, spin and
## brightness (below the shard: the shard is the reward, the ring its frame).
const RING_RADIUS: float = 0.3
const RING_TUBE: float = 0.014
const RING_TILT: float = 1.15
const RING_SPIN: float = 1.7
const RING_INTENSITY_SCALE: float = 0.75

## Colour-blind aid: phase-B sparks lie on their side (a horizontal diamond
## next to phase A's upright one).
var colorblind: bool = false

var _spark_mm: MultiMeshInstance3D
var _prism_mm: MultiMeshInstance3D
var _ring_mm: MultiMeshInstance3D
## Entity index -> instance index in the relevant multimesh.
var _spark_slot: Dictionary = {}
var _prism_slot: Dictionary = {}
var _hidden: Dictionary = {}
var _base_pos: Dictionary = {}
## Sparks currently drawn displaced by the magnet pull -> drawn position.
var _pulled: Dictionary = {}
var _tilted: Dictionary = {}
## Collected entity index -> [elapsed seconds, position] while its pop plays.
var _popping: Dictionary = {}

var _built: bool = false


func _ready() -> void:
	_ensure_built()


func _process(delta: float) -> void:
	if not _popping.is_empty():
		advance_pops(delta)


## Plays the collect pops forward by [param delta] seconds.
func advance_pops(delta: float) -> void:
	for idx: Variant in _popping.keys():
		var k: int = int(idx)
		var state: Array = _popping[k] as Array
		var elapsed: float = float(state[0]) + delta
		if elapsed >= POP_TIME:
			_popping.erase(k)
			_set_instance(k, HIDDEN)
			continue
		state[0] = elapsed
		_set_instance(k, Transform3D(_basis_of(k).scaled(Vector3.ONE * pop_scale(elapsed)), state[1] as Vector3))


## Scale of a collected item [param elapsed] seconds into its pop.
static func pop_scale(elapsed: float) -> float:
	var t: float = clampf(elapsed / POP_TIME, 0.0, 1.0)
	if t < POP_PEAK_AT:
		return lerpf(1.0, POP_PEAK_SCALE, t / POP_PEAK_AT)
	return lerpf(POP_PEAK_SCALE, 0.0, (t - POP_PEAK_AT) / (1.0 - POP_PEAK_AT))


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	# One collectible silhouette family: the prism is the larger shard.
	_spark_mm = _make_mm(MeshFactory.shard(0.11, 0.3), Palette.ENERGY_SPARK)
	_prism_mm = _make_mm(MeshFactory.shard(0.18, 0.46), Palette.ENERGY_SPARK * 1.15)
	_ring_mm = _make_mm(
		MeshFactory.tilted_ring(RING_RADIUS, RING_TUBE, RING_TILT),
		Palette.ENERGY_SPARK * RING_INTENSITY_SCALE,
		RING_SPIN
	)


func _make_mm(mesh: Mesh, intensity: float, spin: float = -1.0) -> MultiMeshInstance3D:
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mmi.multimesh = mm
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SPARK_SHADER
	mat.set_shader_parameter("intensity", intensity)
	if spin >= 0.0:
		mat.set_shader_parameter("spin_speed", spin)
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func build(lvl: SimLevel, _theme: WorldTheme = null, from_index: int = 0) -> void:
	_ensure_built()
	_spark_slot.clear()
	_prism_slot.clear()
	_hidden.clear()
	_base_pos.clear()
	_pulled.clear()
	_tilted.clear()
	_popping.clear()
	var sparks: Array[int] = []
	var prisms: Array[int] = []
	for i: int in range(maxi(0, from_index), lvl.entity_count()):
		if lvl.e_type[i] == SimConst.EntityType.SPARK:
			sparks.append(i)
		elif lvl.e_type[i] == SimConst.EntityType.PRISM:
			prisms.append(i)
	_fill(_spark_mm.multimesh, sparks, lvl, _spark_slot)
	_fill(_prism_mm.multimesh, prisms, lvl, _prism_slot)
	# The ring shares the prism slots (same instance order, same bob phase).
	_fill(_ring_mm.multimesh, prisms, lvl, {})


## Extends the field for endless streaming. Only entities from
## [param from_index] (the simulation cursor) on are kept, so the cost stays
## bounded however long the run lasts.
func rebuild_append(lvl: SimLevel, from_index: int = 0) -> void:
	var hidden_before: Dictionary = _hidden.duplicate()
	build(lvl, null, from_index)
	for idx: Variant in hidden_before:
		if int(idx) >= from_index:
			hide_entity(int(idx), false)


func _fill(mm: MultiMesh, list: Array[int], lvl: SimLevel, slots: Dictionary) -> void:
	mm.instance_count = list.size()
	for n: int in list.size():
		var i: int = list[n]
		slots[i] = n
		var pos: Vector3 = Vector3(SimConst.lane_x(lvl.e_lane[i], lvl.lane_count), SPARK_Y, -lvl.e_d[i])
		_base_pos[i] = pos
		if colorblind and lvl.e_color[i] == 1:
			_tilted[i] = true
		mm.set_instance_transform(n, Transform3D(_basis_of(i), pos))
		mm.set_instance_color(n, color_of(i, lvl))


func _basis_of(index: int) -> Basis:
	return TILTED if _tilted.has(index) else Basis.IDENTITY


## Hides a collected item. With [param pop] it first plays the collect pop
## from where it is drawn (its magnet-pulled spot, if any).
func hide_entity(index: int, pop: bool = true) -> void:
	if _hidden.has(index):
		return
	_hidden[index] = true
	if pop and (_spark_slot.has(index) or _prism_slot.has(index)):
		_popping[index] = [0.0, _pulled.get(index, _base_pos.get(index, Vector3.ZERO))]
		return
	_set_instance(index, HIDDEN)


func _set_instance(index: int, xform: Transform3D) -> void:
	if _spark_slot.has(index):
		_spark_mm.multimesh.set_instance_transform(int(_spark_slot[index]), xform)
	elif _prism_slot.has(index):
		_prism_mm.multimesh.set_instance_transform(int(_prism_slot[index]), xform)
		_ring_mm.multimesh.set_instance_transform(int(_prism_slot[index]), xform)


## Prism rings in the field (one per prism; a collected prism's ring is
## hidden and popped with it through the shared slot).
func ring_count() -> int:
	return _ring_mm.multimesh.instance_count


## Entities whose collect pop is still playing.
func popping_count() -> int:
	return _popping.size()


func hidden_entities() -> Dictionary:
	return _hidden.duplicate()


func position_of(index: int) -> Vector3:
	return _base_pos.get(index, Vector3.ZERO) as Vector3


## Colour roles: sparks are PRIMARY energy (or their phase colour); prisms are
## rewards (ACCENT).
func color_of(index: int, lvl: SimLevel) -> Color:
	var c: int = lvl.e_color[index]
	if c >= 0:
		return Palette.PHASE[clampi(c, 0, 1)]
	return Palette.ACCENT if lvl.e_type[index] == SimConst.EntityType.PRISM else Palette.PRIMARY


## Pulls the sparks a magnet/overdrive will really collect towards the core:
## the same lane radius and phase rule as FluxSim._check_collect, so no spark
## is drawn flying in that the run then counts as missed. When the pull ends,
## displaced sparks go back to their lanes.
func apply_magnet(core: Vector3, lvl: SimLevel, from_index: int, active: bool, phase: int = -1) -> void:
	if not active:
		if not _pulled.is_empty():
			for idx: Variant in _pulled:
				var k: int = int(idx)
				if _spark_slot.has(k) and not _hidden.has(k):
					_spark_mm.multimesh.set_instance_transform(
						int(_spark_slot[k]), Transform3D(_basis_of(k), _base_pos[k] as Vector3)
					)
			_pulled.clear()
		return
	var n: int = lvl.entity_count()
	var i: int = from_index
	while i < n and lvl.e_d[i] < -core.z + 4.0:
		if _spark_slot.has(i) and not _hidden.has(i):
			var base: Vector3 = _base_pos[i] as Vector3
			var dist: float = absf(base.z - core.z)
			var color: int = lvl.e_color[i]
			var collectable: bool = (
				absf(base.x - core.x) <= SimConst.MAGNET_COLLECT_RADIUS and (color < 0 or color == phase)
			)
			if dist < 3.0 and collectable:
				var t: float = clampf(1.0 - dist / 3.0, 0.0, 1.0)
				var p: Vector3 = base.lerp(core, t * 0.6)
				_spark_mm.multimesh.set_instance_transform(int(_spark_slot[i]), Transform3D(_basis_of(i), p))
				_pulled[i] = p
		i += 1


func clear() -> void:
	_spark_mm.multimesh.instance_count = 0
	_prism_mm.multimesh.instance_count = 0
	_ring_mm.multimesh.instance_count = 0
	_spark_slot.clear()
	_prism_slot.clear()
	_hidden.clear()
	_base_pos.clear()
	_pulled.clear()
	_tilted.clear()
	_popping.clear()
