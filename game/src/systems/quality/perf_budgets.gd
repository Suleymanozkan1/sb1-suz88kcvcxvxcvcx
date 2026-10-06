class_name PerfBudgets
extends RefCounted
## Per-preset performance budgets (data/quality/budgets.json; REQ-205 memory,
## REQ-210 draw calls): ceilings for what the renderer and the engine report
## during a gameplay frame. tools/perf_probe.gd measures real runs against them
## with a display; tests/unit/test_perf_budgets.gd checks the document and the
## headless-measurable part (node count, static memory).

const LOG_CHANNEL: String = "perf"
const DEFAULT_PATH: String = "res://data/quality/budgets.json"
const DRAW_CALLS: String = "draw_calls"
const PRIMITIVES: String = "primitives"
const OBJECTS: String = "objects"
const NODES: String = "nodes"
const STATIC_MEMORY_MB: String = "static_memory_mb"
const VIDEO_MEMORY_MB: String = "video_memory_mb"
## Every budgeted metric, in report order.
const METRICS: PackedStringArray = [DRAW_CALLS, PRIMITIVES, OBJECTS, NODES, STATIC_MEMORY_MB, VIDEO_MEMORY_MB]
## Metrics whose budget may never shrink from a lower preset to a higher one:
## a richer preset draws at least as much.
const NON_DECREASING: PackedStringArray = [DRAW_CALLS, PRIMITIVES]
const BYTES_PER_MB: float = 1048576.0

var _presets: Dictionary = {}


## [param doc] is a budgets document; empty loads [constant DEFAULT_PATH].
func _init(doc: Dictionary = {}) -> void:
	var source: Dictionary = doc if not doc.is_empty() else JsonIO.read_dict(DEFAULT_PATH)
	for p: String in validate_document(source):
		GameLog.warn(LOG_CHANNEL, p)
	var raw: Variant = source.get("presets", {})
	_presets = raw as Dictionary if typeof(raw) == TYPE_DICTIONARY else {}


## Problems in a budgets document (empty when complete and valid): every
## quality preset needs every metric as a positive number, and the
## [constant NON_DECREASING] metrics must not shrink from low to ultra.
static func validate_document(doc: Dictionary) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var raw: Variant = doc.get("presets", {})
	var presets: Dictionary = raw as Dictionary if typeof(raw) == TYPE_DICTIONARY else {}
	var previous: Dictionary = {}
	for name: StringName in QualityService.PRESET_ORDER:
		var entry: Variant = presets.get(String(name), null)
		if typeof(entry) != TYPE_DICTIONARY:
			problems.append("preset '%s' missing" % name)
			previous = {}
			continue
		var budgets: Dictionary = entry as Dictionary
		for metric: String in METRICS:
			var v: Variant = budgets.get(metric, null)
			if not _is_number(v):
				problems.append("preset '%s' lacks %s" % [name, metric])
			elif float(v) <= 0.0:
				problems.append("preset '%s' %s must be positive" % [name, metric])
		for metric: String in NON_DECREASING:
			if _is_number(previous.get(metric)) and _is_number(budgets.get(metric)):
				if float(budgets[metric]) < float(previous[metric]):
					problems.append("preset '%s' %s is below the preset under it" % [name, metric])
		previous = budgets
	return problems


## Budget of [param metric] on [param preset]; INF when not budgeted.
func budget(preset: StringName, metric: String) -> float:
	var entry: Variant = _presets.get(String(preset), {})
	if typeof(entry) != TYPE_DICTIONARY:
		return INF
	var v: Variant = (entry as Dictionary).get(metric, null)
	return float(v) if _is_number(v) and float(v) > 0.0 else INF


## The budgets of [param preset] ({metric: value}; missing metrics left out).
func budgets_for(preset: StringName) -> Dictionary:
	var out: Dictionary = {}
	for metric: String in METRICS:
		var b: float = budget(preset, metric)
		if b != INF:
			out[metric] = b
	return out


## One line per metric of [param measured] ({metric: value}) above its budget.
func violations(preset: StringName, measured: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for metric: String in METRICS:
		if not measured.has(metric):
			continue
		var value: float = float(measured[metric])
		var limit: float = budget(preset, metric)
		if value > limit:
			out.append("%s %s = %s > budget %s" % [preset, metric, _fmt(value), _fmt(limit)])
	return out


## Core distance whose view window ([param behind] behind it, [param ahead]
## ahead) holds the most pooled hazard views (sparks and prisms are one
## MultiMesh, so they do not add draw calls): the level's busiest frame, no
## further than [param latest].
static func busiest_view_distance(lvl: SimLevel, ahead: float, behind: float, latest: float) -> float:
	var ds: PackedFloat64Array = PackedFloat64Array()
	for i: int in lvl.entity_count():
		var type: int = lvl.e_type[i]
		if type != SimConst.EntityType.SPARK and type != SimConst.EntityType.PRISM:
			ds.append(lvl.e_d[i])
	var best_d: float = 0.0
	var best_count: int = 0
	var lo: int = 0
	for hi: int in ds.size():
		var core_d: float = maxf(0.0, ds[hi] - ahead + 0.01)
		if core_d > latest:
			break
		while ds[lo] < core_d - behind:
			lo += 1
		if hi - lo + 1 > best_count:
			best_count = hi - lo + 1
			best_d = core_d
	return best_d


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _fmt(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v
