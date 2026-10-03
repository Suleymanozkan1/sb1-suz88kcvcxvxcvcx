class_name ErrorReporter
extends RefCounted
## Global error capture.
##
## Registers an engine [Logger] (Godot 4.5+ `OS.add_logger`) so every script and
## engine error is captured together with the app context (state, level, version,
## platform). Reports are written as JSON files under user://crash/ (bounded) and
## surfaced to analytics on next boot. No personal data is collected.

const REPORT_DIR: String = "user://crash"
const MAX_REPORTS: int = 20
const MAX_PER_SESSION: int = 25

var context_provider: Callable = Callable()
var reports_this_session: int = 0
var enabled: bool = true
var _logger: CaptureLogger = null
var _mutex: Mutex = Mutex.new()
var _pending: Array[Dictionary] = []


## Engine logger that forwards errors to the reporter. Loggers may be called
## from any thread, so it only queues data under a mutex.
class CaptureLogger:
	extends Logger
	var owner_ref: WeakRef

	func _init(owner: ErrorReporter) -> void:
		owner_ref = weakref(owner)

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
		var reporter: ErrorReporter = owner_ref.get_ref() as ErrorReporter
		if reporter == null:
			return
		reporter.enqueue(
			{
				"function": function,
				"file": file,
				"line": line,
				"code": code,
				"message": rationale,
				"error_type": error_type,
			}
		)

	func _log_message(_message: String, _error: bool) -> void:
		pass


func install() -> void:
	if _logger != null:
		return
	_logger = CaptureLogger.new(self)
	OS.add_logger(_logger)


func uninstall() -> void:
	if _logger != null:
		OS.remove_logger(_logger)
		_logger = null


func enqueue(error: Dictionary) -> void:
	_mutex.lock()
	if _pending.size() < MAX_PER_SESSION:
		_pending.append(error)
	_mutex.unlock()


## Call from the main thread (once per frame or on demand) to persist reports.
func flush() -> int:
	_mutex.lock()
	var batch: Array[Dictionary] = _pending.duplicate()
	_pending.clear()
	_mutex.unlock()
	var written: int = 0
	for error: Dictionary in batch:
		if write_report(error):
			written += 1
	return written


func build_report(error: Dictionary) -> Dictionary:
	var report: Dictionary = AppInfo.context()
	report["timestamp"] = int(Time.get_unix_time_from_system())
	report["error"] = error
	if context_provider.is_valid():
		var extra: Variant = context_provider.call()
		if typeof(extra) == TYPE_DICTIONARY:
			report["context"] = extra
	report["log_tail"] = Array(GameLog.recent_lines().slice(-30))
	return report


func write_report(error: Dictionary) -> bool:
	if not enabled or reports_this_session >= MAX_PER_SESSION:
		return false
	reports_this_session += 1
	var report: Dictionary = build_report(error)
	var name: String = "crash_%d_%d.json" % [int(report["timestamp"]), reports_this_session]
	var err: Error = JsonIO.write_json(REPORT_DIR.path_join(name), report)
	if err != OK:
		return false
	_prune()
	return true


## Reads stored reports (oldest first) and deletes them when [param consume].
func collect_reports(consume: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir: DirAccess = DirAccess.open(REPORT_DIR)
	if dir == null:
		return out
	var files: PackedStringArray = dir.get_files()
	files.sort()
	for f: String in files:
		if not f.ends_with(".json"):
			continue
		var data: Dictionary = JsonIO.read_dict(REPORT_DIR.path_join(f))
		if not data.is_empty():
			out.append(data)
		if consume:
			DirAccess.remove_absolute(REPORT_DIR.path_join(f))
	return out


func _prune() -> void:
	var dir: DirAccess = DirAccess.open(REPORT_DIR)
	if dir == null:
		return
	var files: PackedStringArray = dir.get_files()
	files.sort()
	while files.size() > MAX_REPORTS:
		DirAccess.remove_absolute(REPORT_DIR.path_join(files[0]))
		files.remove_at(0)
