class_name SparkField
extends Node3D
## All sparks (and prisms) of a level drawn with one MultiMesh each — a single
## draw call regardless of count. Collected items are hidden by zero-scaling
## their instance transform; magnet pulls are animated per frame.

const SPARK_SHADER: Shader = preload("res://assets/shaders/spark.gdshader")
const SPARK_Y: float = 0.38

var _spark_mm: MultiMeshInstance3D
var _prism_mm: MultiMeshInstance3D
## Entity index -> instance index in the relevant multimesh.
var _spark_slot: Dictionary = {}
var _prism_slot: Dictionary = {}
var _hidden: Dictionary = {}
var _base_pos: Dictionary = {}

var _built: bool = false


func _ready() -> void:
	_ensure_built()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	# One collectible silhouette family: the prism is the larger shard.
	_spark_mm = _make_mm(0.11, 0.3, Palette.ENERGY_SPARK)
	_prism_mm = _make_mm(0.18, 0.46, Palette.ENERGY_SPARK * 1.15)


func _make_mm(radius: float, height: float, intensity: float) -> MultiMeshInstance3D:
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = MeshFactory.shard(radius, height)
	mmi.multimesh = mm
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SPARK_SHADER
	mat.set_shader_parameter("intensity", intensity)
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
	var sparks: Array[int] = []
	var prisms: Array[int] = []
	for i: int in range(maxi(0, from_index), lvl.entity_count()):
		if lvl.e_type[i] == SimConst.EntityType.SPARK:
			sparks.append(i)
		elif lvl.e_type[i] == SimConst.EntityType.PRISM:
			prisms.append(i)
	_fill(_spark_mm.multimesh, sparks, lvl, _spark_slot)
	_fill(_prism_mm.multimesh, prisms, lvl, _prism_slot)


## Extends the field for endless streaming. Only entities from
## [param from_index] (the simulation cursor) on are kept, so the cost stays
## bounded however long the run lasts.
func rebuild_append(lvl: SimLevel, from_index: int = 0) -> void:
	var hidden_before: Dictionary = _hidden.duplicate()
	build(lvl, null, from_index)
	for idx: Variant in hidden_before:
		if int(idx) >= from_index:
			hide_entity(int(idx))


func _fill(mm: MultiMesh, list: Array[int], lvl: SimLevel, slots: Dictionary) -> void:
	mm.instance_count = list.size()
	for n: int in list.size():
		var i: int = list[n]
		slots[i] = n
		var pos: Vector3 = Vector3(SimConst.lane_x(lvl.e_lane[i], lvl.lane_count), SPARK_Y, -lvl.e_d[i])
		_base_pos[i] = pos
		mm.set_instance_transform(n, Transform3D(Basis.IDENTITY, pos))
		mm.set_instance_color(n, color_of(i, lvl))


func hide_entity(index: int) -> void:
	_hidden[index] = true
	if _spark_slot.has(index):
		_spark_mm.multimesh.set_instance_transform(
			int(_spark_slot[index]), Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
		)
	elif _prism_slot.has(index):
		_prism_mm.multimesh.set_instance_transform(
			int(_prism_slot[index]), Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
		)


func position_of(index: int) -> Vector3:
	return _base_pos.get(index, Vector3.ZERO) as Vector3


## Colour roles: sparks are PRIMARY energy (or their phase colour); prisms are
## rewards (ACCENT).
func color_of(index: int, lvl: SimLevel) -> Color:
	var c: int = lvl.e_color[index]
	if c >= 0:
		return Palette.PHASE[clampi(c, 0, 1)]
	return Palette.ACCENT if lvl.e_type[index] == SimConst.EntityType.PRISM else Palette.PRIMARY


## Pulls nearby sparks towards the core while a magnet/overdrive is active.
func apply_magnet(core: Vector3, lvl: SimLevel, from_index: int, active: bool) -> void:
	if not active:
		return
	var n: int = lvl.entity_count()
	var i: int = from_index
	while i < n and lvl.e_d[i] < -core.z + 4.0:
		if _spark_slot.has(i) and not _hidden.has(i):
			var base: Vector3 = _base_pos[i] as Vector3
			var dist: float = absf(base.z - core.z)
			if dist < 3.0:
				var t: float = clampf(1.0 - dist / 3.0, 0.0, 1.0)
				var p: Vector3 = base.lerp(core, t * 0.6)
				_spark_mm.multimesh.set_instance_transform(int(_spark_slot[i]), Transform3D(Basis.IDENTITY, p))
		i += 1


func clear() -> void:
	_spark_mm.multimesh.instance_count = 0
	_prism_mm.multimesh.instance_count = 0
	_spark_slot.clear()
	_prism_slot.clear()
	_hidden.clear()
	_base_pos.clear()
