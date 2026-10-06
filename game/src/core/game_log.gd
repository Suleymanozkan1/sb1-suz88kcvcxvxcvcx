class_name GameLog
extends RefCounted
## Static structured logger with an in-memory ring buffer.
##
## The ring buffer is attached to crash/error reports so they carry the last
## events leading up to a problem. Logging never allocates per frame in the
## hot gameplay path (callers log only on state changes).

enum Level { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 }

const RING_SIZE: int = 200
const LEVEL_TAGS: PackedStringArray = ["DEBUG", "INFO", "WARN", "ERROR"]

static var min_level: int = Level.INFO
static var echo_to_stdout: bool = true
static var _ring: PackedStringArray = PackedStringArray()
static var _ring_pos: int = 0


static func debug(channel: String, message: String) -> void:
	_write(Level.DEBUG, channel, message)


static func info(channel: String, message: String) -> void:
	_write(Level.INFO, channel, message)


static func warn(channel: String, message: String) -> void:
	_write(Level.WARN, channel, message)


static func error(channel: String, message: String) -> void:
	_write(Level.ERROR, channel, message)


## Returns the buffered lines in chronological order.
static func recent_lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var n: int = _ring.size()
	if n < RING_SIZE:
		return _ring.duplicate()
	for i: int in n:
		out.append(_ring[(_ring_pos + i) % n])
	return out


static func clear() -> void:
	_ring.clear()
	_ring_pos = 0


static func _write(level: int, channel: String, message: String) -> void:
	if level < min_level:
		return
	var line: String = "[%s][%s] %s" % [LEVEL_TAGS[level], channel, message]
	if _ring.size() < RING_SIZE:
		_ring.append(line)
	else:
		_ring[_ring_pos] = line
		_ring_pos = (_ring_pos + 1) % RING_SIZE
	if echo_to_stdout:
		if level >= Level.WARN:
			# push_warning/push_error would feed the error reporter recursively;
			# printerr keeps logging side-effect free.
			printerr(line)
		else:
			print(line)
