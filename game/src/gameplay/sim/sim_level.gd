class_name SimLevel
extends RefCounted
## Immutable, cache-friendly representation of a level for the simulation.
##
## Built from the level data dictionary (see docs/LEVEL_DESIGN.md for the schema).
## Entities are stored in parallel packed arrays sorted by distance so the sim can
## scan them with a single cursor and clone cheaply.

enum Objective { REACH_END = 0, COLLECT = 1, SHATTER = 2, SURVIVE = 3 }

const OBJECTIVE_NAMES: Dictionary = {
	"reach_end": Objective.REACH_END,
	"collect": Objective.COLLECT,
	"shatter": Objective.SHATTER,
	"survive": Objective.SURVIVE,
}

const ENDLESS_LENGTH: float = 1.0e12

var level_id: String = ""
var lane_count: int = 2
var base_speed: float = 8.0
var length: float = 100.0
var start_form: int = SimConst.Form.HOP
var start_lane: int = 0
var start_phase: int = 0
var hop_time: float = SimConst.HOP_TIME
var speed_ramp: float = 0.0
## Distance over which the speed ramp reaches its full value.
var ramp_distance: float = 100.0
var forgiving: bool = false
var start_shields: int = 0
var beat_seconds: float = 0.5
var objective_type: int = Objective.REACH_END
var objective_target: int = 0
var time_limit: float = 0.0
var endless: bool = false

var e_type: PackedInt32Array = PackedInt32Array()
var e_d: PackedFloat64Array = PackedFloat64Array()
var e_lane: PackedInt32Array = PackedInt32Array()
var e_mask: PackedInt32Array = PackedInt32Array()
var e_color: PackedInt32Array = PackedInt32Array()
var e_p0: PackedFloat64Array = PackedFloat64Array()
var e_p1: PackedFloat64Array = PackedFloat64Array()
var e_p2: PackedFloat64Array = PackedFloat64Array()
var e_p3: PackedFloat64Array = PackedFloat64Array()

var spark_total: int = 0
var prism_total: int = 0
var breakable_total: int = 0
var errors: PackedStringArray = PackedStringArray()


static func from_dict(data: Dictionary) -> SimLevel:
	var lvl: SimLevel = SimLevel.new()
	lvl.level_id = str(data.get("id", ""))
	lvl.lane_count = clampi(int(data.get("lanes", 2)), 2, 3)
	lvl.base_speed = float(data.get("speed", 8.0))
	lvl.endless = bool(data.get("endless", false))
	lvl.length = SimLevel.ENDLESS_LENGTH if lvl.endless else float(data.get("length", 100.0))
	lvl.start_form = SimConst.form_from_name(str(data.get("start_form", "hop")))
	if lvl.start_form < 0:
		lvl.errors.append("unknown start_form '%s'" % str(data.get("start_form")))
		lvl.start_form = SimConst.Form.HOP
	lvl.start_lane = clampi(int(data.get("start_lane", 0)), 0, lvl.lane_count - 1)
	lvl.start_phase = clampi(int(data.get("start_phase", 0)), 0, 1)
	lvl.forgiving = bool(data.get("forgiving", false))
	lvl.start_shields = 1 if lvl.forgiving else 0
	var mods: Dictionary = data.get("modifiers", {}) as Dictionary
	lvl.hop_time = float(mods.get("hop_time", SimConst.HOP_TIME))
	lvl.speed_ramp = float(mods.get("speed_ramp", 0.0))
	lvl.ramp_distance = maxf(1.0, float(mods.get("ramp_distance", lvl.length if not lvl.endless else 500.0)))
	lvl.beat_seconds = float(data.get("beat_seconds", 0.5))
	lvl.time_limit = float(data.get("time_limit", 0.0))
	var objective: Dictionary = data.get("objective", {}) as Dictionary
	var obj_name: String = str(objective.get("type", "reach_end"))
	if not OBJECTIVE_NAMES.has(obj_name):
		lvl.errors.append("unknown objective '%s'" % obj_name)
	lvl.objective_type = int(OBJECTIVE_NAMES.get(obj_name, Objective.REACH_END))
	lvl.objective_target = int(objective.get("target", 0))
	lvl.append_entities(data.get("entities", []) as Array)
	return lvl


## Appends entity dictionaries (used by level loading and by endless streaming).
## Entities must start at or after the last existing entity distance.
func append_entities(entities: Array) -> void:
	var parsed: Array[Dictionary] = []
	for raw: Variant in entities:
		if typeof(raw) != TYPE_DICTIONARY:
			errors.append("entity is not an object")
			continue
		parsed.append(raw as Dictionary)
	parsed.sort_custom(_entity_less)
	for ent: Dictionary in parsed:
		_append_one(ent)


func entity_count() -> int:
	return e_type.size()


static func _entity_less(a: Dictionary, b: Dictionary) -> bool:
	var da: float = float(a.get("d", 0.0))
	var db: float = float(b.get("d", 0.0))
	if da != db:
		return da < db
	return SimConst.entity_type_from_name(str(a.get("t", ""))) < SimConst.entity_type_from_name(str(b.get("t", "")))


func _append_one(ent: Dictionary) -> void:
	var type_id: int = SimConst.entity_type_from_name(str(ent.get("t", "")))
	if type_id < 0:
		errors.append("unknown entity type '%s'" % str(ent.get("t", "")))
		return
	var lane: int = int(ent.get("lane", 0))
	var mask: int = _mask_from(ent.get("lanes", null), lane)
	var p0: float = 0.0
	var p1: float = 0.0
	var p2: float = 0.0
	var p3: float = 0.0
	match type_id:
		SimConst.EntityType.SLIDER:
			p0 = float(ent.get("from", 0))
			p1 = float(ent.get("to", lane_count - 1))
			p2 = maxf(float(ent.get("period", 1.0)), 0.1)
			p3 = float(ent.get("offset", 0.0))
		SimConst.EntityType.PULSE_GATE:
			p0 = maxf(float(ent.get("period", 1.0)), 0.1)
			p1 = clampf(float(ent.get("open", 0.5)), 0.05, 0.95)
			p2 = float(ent.get("offset", 0.0))
		SimConst.EntityType.CURRENT, SimConst.EntityType.PORTAL:
			p0 = float(ent.get("to", 0))
		SimConst.EntityType.FORM_GATE:
			p0 = float(SimConst.form_from_name(str(ent.get("form", "hop"))))
		SimConst.EntityType.PHASE_GATE:
			mask = (1 << lane_count) - 1
		SimConst.EntityType.SPARK:
			spark_total += 1
		SimConst.EntityType.PRISM:
			prism_total += 1
		SimConst.EntityType.BREAKABLE:
			breakable_total += 1
	e_type.append(type_id)
	e_d.append(float(ent.get("d", 0.0)))
	e_lane.append(lane)
	e_mask.append(mask)
	e_color.append(int(ent.get("color", -1)))
	e_p0.append(p0)
	e_p1.append(p1)
	e_p2.append(p2)
	e_p3.append(p3)


func _mask_from(lanes: Variant, fallback_lane: int) -> int:
	if typeof(lanes) == TYPE_ARRAY:
		var m: int = 0
		for l: Variant in lanes as Array:
			var li: int = int(l)
			if li >= 0 and li < lane_count:
				m |= 1 << li
		return m
	return 1 << clampi(fallback_lane, 0, lane_count - 1)


## Slider centre x at simulation time [param time].
func slider_x(index: int, time: float) -> float:
	var from_x: float = SimConst.lane_x(int(e_p0[index]), lane_count)
	var to_x: float = SimConst.lane_x(int(e_p1[index]), lane_count)
	var u: float = SimConst.ping_pong01(time / e_p2[index] + e_p3[index])
	return from_x + (to_x - from_x) * u


## True when the pulse gate blocks its lanes at [param time].
func pulse_closed(index: int, time: float) -> bool:
	var u: float = SimConst.wrap01(time / e_p0[index] + e_p2[index])
	return u >= e_p1[index]


## Normalised open-cycle progress (0..1) used by the view for animation.
func pulse_cycle(index: int, time: float) -> float:
	return SimConst.wrap01(time / e_p0[index] + e_p2[index])
