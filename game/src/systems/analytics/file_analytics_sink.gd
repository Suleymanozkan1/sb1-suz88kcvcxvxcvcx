class_name FileAnalyticsSink
extends AnalyticsSink
## Appends events as JSON lines to a local file and keeps only the newest
## [member max_lines] lines (ring trim). Local diagnostics only: this sink
## never uploads anything.
##
## Rewriting the whole file on every event once it is full would cost a full
## read + atomic rewrite per event, so the file may temporarily hold up to
## [member trim_slack] extra (older) lines before it is trimmed in one go.
## Readers never see those: [method read_lines], [method read_events] and
## [method line_count] always report at most the newest [member max_lines].

const DEFAULT_PATH: String = "user://analytics/events.jsonl"
const DEFAULT_MAX_LINES: int = 500
const LINE_SEPARATOR: String = "\n"
const NEWLINE_BYTE: int = 10
## Slack is max_lines / this (at least 1): one rewrite per ~20% of capacity.
const TRIM_SLACK_DIVISOR: int = 5

var path: String = DEFAULT_PATH
var max_lines: int = DEFAULT_MAX_LINES
## Extra physical lines tolerated before the file is rewritten.
var trim_slack: int = 1
## Lines physically in the file; -1 until first counted.
var _line_count: int = -1


func _init(file_path: String = DEFAULT_PATH, max_line_count: int = DEFAULT_MAX_LINES) -> void:
	path = file_path if not file_path.is_empty() else DEFAULT_PATH
	max_lines = maxi(1, max_line_count)
	trim_slack = maxi(1, max_lines / TRIM_SLACK_DIVISOR)


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
		_line_count = _read_all_lines().size()
	var file: FileAccess = _open_for_append()
	if file == null:
		GameLog.warn("analytics", "cannot open %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	for event: Dictionary in batch:
		file.store_line(JSON.stringify(event))
		_line_count += 1
	file.close()
	if _line_count > max_lines + trim_slack:
		_trim()


## The newest non-empty lines (at most [member max_lines]), oldest first.
func read_lines() -> PackedStringArray:
	var lines: PackedStringArray = _read_all_lines()
	if lines.size() > max_lines:
		lines = lines.slice(lines.size() - max_lines)
	return lines


## Parsed events (corrupt lines, e.g. from a crash mid-write, are skipped).
func read_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line: String in read_lines():
		var json: JSON = JSON.new()
		if json.parse(line) == OK and typeof(json.data) == TYPE_DICTIONARY:
			out.append(json.data as Dictionary)
	return out


## Number of lines currently kept (never more than [member max_lines]).
func line_count() -> int:
	if _line_count < 0:
		_line_count = _read_all_lines().size()
	return mini(_line_count, max_lines)


## Deletes the file (truncates it when it cannot be deleted).
func clear() -> void:
	_line_count = 0
	if not FileAccess.file_exists(path):
		return
	var err: Error = DirAccess.remove_absolute(path)
	if err == OK:
		return
	GameLog.warn("analytics", "cannot delete %s (%s); truncating" % [path, error_string(err)])
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_line_count = -1
		return
	file.close()


## Opens the file positioned at its end. A last line cut short by a crash
## (no trailing newline) is terminated first so the next event stays intact.
func _open_for_append() -> FileAccess:
	if not FileAccess.file_exists(path):
		return FileAccess.open(path, FileAccess.WRITE)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		return null
	var length: int = file.get_length()
	if length > 0:
		file.seek(length - 1)
		var last: int = file.get_8()
		file.seek_end()
		if last != NEWLINE_BYTE:
			file.store_string(LINE_SEPARATOR)
	return file


## Every non-empty line physically in the file (oldest first).
func _read_all_lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if not FileAccess.file_exists(path):
		return out
	for line: String in FileAccess.get_file_as_string(path).split(LINE_SEPARATOR, false):
		if not line.strip_edges().is_empty():
			out.append(line)
	return out


func _trim() -> void:
	var lines: PackedStringArray = read_lines()
	var err: Error = JsonIO.write_atomic(path, LINE_SEPARATOR.join(lines) + LINE_SEPARATOR)
	if err != OK:
		GameLog.warn("analytics", "ring trim of %s failed (%s)" % [path, error_string(err)])
		_line_count = -1
		return
	_line_count = lines.size()
