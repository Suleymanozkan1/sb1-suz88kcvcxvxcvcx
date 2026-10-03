extends SceneTree
## Headless test runner.
##
## Usage:
##   godot --headless --path game -s res://tests/run_tests.gd [-- --filter=<substring>]
## Discovers every `test_*.gd` under res://tests/{unit,integration,gameplay},
## runs every `test_*` method and exits with code 1 on any failure.

const SUITE_DIRS: PackedStringArray = [
	"res://tests/unit",
	"res://tests/integration",
	"res://tests/gameplay",
]

var _total: int = 0
var _errors: ScriptErrorCounter = ScriptErrorCounter.new()
var _failed: int = 0
var _assertions: int = 0
var _failure_lines: PackedStringArray = PackedStringArray()


## Counts GDScript runtime errors (Logger, Godot 4.5+): a test whose body hits a
## script error is aborted by the engine without raising anything, so the
## runner fails it explicitly instead of reporting a silent "ok".
class ScriptErrorCounter:
	extends Logger
	var count: int = 0
	var last: String = ""
	var _mutex: Mutex = Mutex.new()

	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array[ScriptBacktrace]
	) -> void:
		if error_type != Logger.ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		count += 1
		last = "%s (%s:%d %s)" % [rationale if not rationale.is_empty() else code, file.get_file(), line, function]
		_mutex.unlock()


func _initialize() -> void:
	OS.add_logger(_errors)
	_run.call_deferred()


func _run() -> void:
	var filter: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.substr("--filter=".length())
	var files: PackedStringArray = PackedStringArray()
	for dir_path: String in SUITE_DIRS:
		_collect(dir_path, files)
	files.sort()
	var started: int = Time.get_ticks_msec()
	for path: String in files:
		if filter != "" and not path.contains(filter):
			continue
		await _run_file(path)
	var elapsed: float = float(Time.get_ticks_msec() - started) / 1000.0
	print("")
	print("==== %d tests, %d failed, %d assertions, %.2fs ====" % [_total, _failed, _assertions, elapsed])
	for line: String in _failure_lines:
		print("  FAIL ", line)
	quit(1 if _failed > 0 or _total == 0 else 0)


func _collect(dir_path: String, out: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for file: String in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			out.append(dir_path.path_join(file))


func _run_file(path: String) -> void:
	var script: GDScript = load(path) as GDScript
	if script == null:
		_total += 1
		_failed += 1
		_failure_lines.append("%s: could not load script" % path)
		return
	var methods: PackedStringArray = PackedStringArray()
	for m: Dictionary in script.get_script_method_list():
		var method_name: String = str(m.get("name", ""))
		if method_name.begins_with("test_") and not methods.has(method_name):
			methods.append(method_name)
	print("[suite] ", path.get_file(), " (", methods.size(), ")")
	for method_name: String in methods:
		var instance: Object = script.new()
		var test: TestCase = instance as TestCase
		if test == null:
			_failure_lines.append("%s does not extend TestCase" % path)
			_failed += 1
			_total += 1
			return
		test.tree = self
		test.current_test = "%s::%s" % [path.get_file(), method_name]
		_total += 1
		var t0: int = Time.get_ticks_usec()
		var errors_before: int = _errors.count
		await test.before_each()
		await test.call(method_name)
		await test.after_each()
		if _errors.count > errors_before:
			test.fail("script error during the test: %s" % _errors.last)
		var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		_assertions += test.assertions
		if test.failures.is_empty():
			print("   ok   %s (%.1f ms)" % [method_name, ms])
		else:
			_failed += 1
			print("   FAIL %s" % method_name)
			for f: String in test.failures:
				print("        ", f)
				_failure_lines.append(f)
