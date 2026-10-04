extends TestCase
## Performance budgets (data/quality/budgets.json; REQ-205 memory, REQ-210
## draw calls): the document's shape and preset order, the rules that check
## it, and the part that can be measured headless. With no renderer every
## rendering counter reads 0, so only the node count and static memory of a
## busy boss level on the Low preset are checked here; draw calls, primitives
## and video memory are checked by tools/perf_probe.gd with a display.

const FIXED_UNIX: int = 1790000000
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## The last boss: the longest, densest level in the campaign.
const BUSY_LEVEL: String = "w10_l52"
const SETTLE_FRAMES: int = 3
const PLAY_FRAMES: int = 10
## A lone barrier early, three together later, sparks (one MultiMesh, never
## counted) in between.
const STRETCH_ENTITIES: Array[Dictionary] = [
	{"t": "barrier", "d": 20.0, "lane": 0},
	{"t": "spark", "d": 30.0, "lane": 1},
	{"t": "spark", "d": 31.0, "lane": 1},
	{"t": "spark", "d": 32.0, "lane": 1},
	{"t": "spark", "d": 33.0, "lane": 1},
	{"t": "barrier", "d": 200.0, "lane": 0},
	{"t": "barrier", "d": 205.0, "lane": 1},
	{"t": "barrier", "d": 210.0, "lane": 2},
]
const BROKEN_CASES: PackedStringArray = [
	"missing metric", "zero budget", "text budget", "missing preset", "shrinking draw calls", "shrinking primitives"
]

var _app: AppServices
var _flow: GameFlow
var _saved_max_fps: int = 0
var _saved_msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
var _saved_scale: float = 1.0


func before_each() -> void:
	_saved_max_fps = Engine.max_fps
	_saved_msaa = tree.root.msaa_3d
	_saved_scale = tree.root.scaling_3d_scale
	_app = AppServices.new()
	_app.auto_boot = false
	tree.root.add_child(_app)
	var clock: GameClock = GameClock.new()
	clock.set_fixed_unix(FIXED_UNIX)
	_app.boot(MemorySaveStorage.new(), clock)
	_flow = null


func after_each() -> void:
	if _flow != null:
		_flow.queue_free()
	_app.queue_free()
	await wait_frames(2)
	Engine.max_fps = _saved_max_fps
	tree.root.msaa_3d = _saved_msaa
	tree.root.scaling_3d_scale = _saved_scale


func _doc() -> Dictionary:
	return JsonIO.read_dict(PerfBudgets.DEFAULT_PATH)


## The real document with one defect of kind [param case].
func _broken(case: String) -> Dictionary:
	var doc: Dictionary = _doc().duplicate(true)
	var presets: Dictionary = doc["presets"] as Dictionary
	var low: Dictionary = presets["low"] as Dictionary
	var medium: Dictionary = presets["medium"] as Dictionary
	var high: Dictionary = presets["high"] as Dictionary
	match case:
		"missing metric":
			low.erase(PerfBudgets.NODES)
		"zero budget":
			medium[PerfBudgets.OBJECTS] = 0
		"text budget":
			high[PerfBudgets.VIDEO_MEMORY_MB] = "64"
		"missing preset":
			presets.erase("ultra")
		"shrinking draw calls":
			(presets["ultra"] as Dictionary)[PerfBudgets.DRAW_CALLS] = float(high[PerfBudgets.DRAW_CALLS]) - 1.0
		"shrinking primitives":
			medium[PerfBudgets.PRIMITIVES] = float(low[PerfBudgets.PRIMITIVES]) - 1.0
	return doc


func test_every_preset_has_every_metric_as_a_positive_number() -> void:
	var doc: Dictionary = _doc()
	assert_empty(PerfBudgets.validate_document(doc), "budgets.json is complete and valid")
	var budgets: Dictionary = doc.get("presets", {}) as Dictionary
	var quality: Dictionary = JsonIO.read_dict(QualityService.DEFAULT_PRESETS_PATH)["presets"] as Dictionary
	assert_eq(budgets.size(), quality.size(), "one budget set per quality preset")
	for preset: String in quality:
		assert_has(budgets, preset, "budgets for preset %s" % preset)
		var entry: Dictionary = budgets.get(preset, {}) as Dictionary
		for metric: String in PerfBudgets.METRICS:
			var v: Variant = entry.get(metric, null)
			var is_number: bool = typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
			assert_true(is_number, "%s %s is a number" % [preset, metric])
			assert_gt(float(v) if is_number else 0.0, 0.0, "%s %s is positive" % [preset, metric])


func test_draw_calls_and_primitives_never_shrink_from_low_to_ultra() -> void:
	var budgets: PerfBudgets = PerfBudgets.new(_doc())
	var order: Array[StringName] = QualityService.PRESET_ORDER
	for i: int in range(1, order.size()):
		for metric: String in PerfBudgets.NON_DECREASING:
			assert_ge(
				budgets.budget(order[i], metric),
				budgets.budget(order[i - 1], metric),
				"%s %s >= %s" % [order[i], metric, order[i - 1]]
			)


func test_validation_catches_missing_bad_and_shrinking_budgets() -> void:
	for case: String in BROKEN_CASES:
		assert_false(PerfBudgets.validate_document(_broken(case)).is_empty(), "%s is reported" % case)


func test_violations_name_each_metric_over_its_budget() -> void:
	var budgets: PerfBudgets = PerfBudgets.new(_doc())
	var measured: Dictionary = budgets.budgets_for(&"low")
	assert_eq(measured.size(), PerfBudgets.METRICS.size(), "every metric budgeted on low")
	assert_empty(budgets.violations(&"low", measured), "exactly at budget is within it")
	measured[PerfBudgets.DRAW_CALLS] = float(measured[PerfBudgets.DRAW_CALLS]) + 1.0
	measured[PerfBudgets.STATIC_MEMORY_MB] = float(measured[PerfBudgets.STATIC_MEMORY_MB]) + 0.5
	var over: PackedStringArray = budgets.violations(&"low", measured)
	assert_eq(over.size(), 2, "one line per metric over budget")
	assert_has(" ".join(over), PerfBudgets.DRAW_CALLS)
	assert_has(" ".join(over), PerfBudgets.STATIC_MEMORY_MB)
	assert_empty(budgets.violations(&"ultra", budgets.budgets_for(&"low")), "low's numbers fit ultra")


func test_busiest_view_distance_finds_the_densest_stretch() -> void:
	var lvl: SimLevel = SimLevel.from_dict({"id": "stretch", "length": 400.0, "lanes": 3, "entities": STRETCH_ENTITIES})
	var d: float = PerfBudgets.busiest_view_distance(lvl, 75.0, 6.0, 1000.0)
	assert_true(d + 75.0 > 210.0 and d - 6.0 <= 200.0, "the three barriers are in view at %.1f" % d)
	assert_eq(PerfBudgets.busiest_view_distance(lvl, 75.0, 6.0, 0.0), 0.0, "never past the latest distance")


func test_busy_boss_level_fits_the_low_node_and_memory_budgets() -> void:
	var budgets: PerfBudgets = PerfBudgets.new(_doc())
	_flow = MAIN_SCENE.instantiate() as GameFlow
	_flow.s = _app
	tree.root.add_child(_flow)
	await wait_frames(SETTLE_FRAMES)
	# The Settings screen's path, as in the game.
	assert_true(_app.settings.set_value("quality", "low"), "the settings path takes the preset")
	assert_eq(_app.quality.effective_preset(), &"low")
	_flow._start_run(&"classic", BUSY_LEVEL)
	var session: GameplaySession = _flow.session
	assert_eq(str(session.level_data.get("id", "")), BUSY_LEVEL, "the boss run started")
	var taps: PackedInt32Array = PackedInt32Array()
	for t: Variant in (session.level_data["solution"] as Dictionary)["taps"] as Array:
		taps.append(int(t))
	var lvl: SimLevel = session.sim_level
	var target: float = PerfBudgets.busiest_view_distance(
		lvl, GameplayView.VIEW_AHEAD, GameplayView.VIEW_BEHIND, lvl.length
	)
	session.autopilot = taps
	session.lockstep = true
	session.begin(0.0)
	while session.sim.is_running() and session.sim.d < target:
		session.step_ticks(1, taps)
	assert_true(session.sim.is_running(), "the stored solution is still going at the busiest stretch")
	await wait_frames(PLAY_FRAMES)
	assert_gt(float(_flow.view._active.size()), 0.0, "hazards are on screen")
	var nodes: float = float(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	assert_le(nodes, budgets.budget(&"low", PerfBudgets.NODES), "node count within the low budget")
	var static_mb: float = Performance.get_monitor(Performance.MEMORY_STATIC) / PerfBudgets.BYTES_PER_MB
	assert_le(static_mb, budgets.budget(&"low", PerfBudgets.STATIC_MEMORY_MB), "static memory within the low budget")
