class_name FileAnalyticsSink
extends AnalyticsSink
## Appends events as JSON lines to a local file and keeps only the newest
## [member max_lines] lines (ring trim). Local diagnostics only: this sink
## never uploads anything.

const DEFAULT_PATH: String = "user://analytics/events.jsonl"
const DEFAULT_MAX_LINES: int = 500
const LINE_SEPARATOR: String = "\n"

var path: String = DEFAULT_PATH
var max_lines: int = DEFAULT_MAX_LINES
## Lines currently in the file; -1 until first counted.
var _line_count: int = -1


func _init(file_path: String = DEFAULT_PATH, max_line_count: int = DEFAULT_MAX_LINES) -> void:
	path = file_path if not file_path.is_empty() else DEFAULT_PATH
	max_lines = maxi(1, max_line_count)


## Appends one JSON line per event, then trims the oldest lines if needed.
func send(batch: Array[Dictionary]) -> void:
	if batch.is_empty():
		return
	var dir_path: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var mk: Error = DirAccess.make_dir_recursive_absolute(dir_path)
		if mk != OK:
			GameLog.warn("analytics", "cannot create %s (%s)" % [dir_path, error_string(mk)])
			return
	if _line_count < 0:
		_line_count = read_lines().size()
	var file: FileAccess = null
	if FileAccess.file_exists(path):
		file = FileAccess.open(path, FileAccess.READ_WRITE)
		if file != null:
			file.seek_end()
	else:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		GameLog.warn("analytics", "cannot open %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	for event: Dictionary in batch:
		file.store_line(JSON.stringify(event))
		_line_count += 1
	file.close()
	if _line_count > max_lines:
		_trim()


## Non-empty lines currently stored (oldest first).
func read_lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if not FileAccess.file_exists(path):
		return out
	for line: String in FileAccess.get_file_as_string(path).split(LINE_SEPARATOR, false):
		if not line.strip_edges().is_empty():
			out.append(line)
	return out


## Parsed events (corrupt lines, e.g. from a crash mid-write, are skipped).
func read_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line: String in read_lines():
		var json: JSON = JSON.new()
		if json.parse(line) == OK and typeof(json.data) == TYPE_DICTIONARY:
			out.append(json.data as Dictionary)
	return out


## Number of lines currently stored.
func line_count() -> int:
	if _line_count < 0:
		_line_count = read_lines().size()
	return _line_count


## Deletes the file.
func clear() -> void:
	if FileAccess.file_exists(path):
		var err: Error = DirAccess.remove_absolute(path)
		if err != OK:
			GameLog.warn("analytics", "cannot delete %s (%s)" % [path, error_string(err)])
	_line_count = 0


func _trim() -> void:
	var lines: PackedStringArray = read_lines()
	if lines.size() > max_lines:
		lines = lines.slice(lines.size() - max_lines)
	var err: Error = JsonIO.write_atomic(path, LINE_SEPARATOR.join(lines) + LINE_SEPARATOR)
	if err != OK:
		GameLog.warn("analytics", "ring trim of %s failed (%s)" % [path, error_string(err)])
	_line_count = lines.size()
