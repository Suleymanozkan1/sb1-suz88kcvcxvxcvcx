class_name MemorySaveStorage
extends SaveStorage
## In-memory [SaveStorage] for tests and for running without a writable disk.
##
## Writes replace whole entries, so they are trivially atomic. Test helpers:
## [method corrupt] overwrites an entry bypassing every rule, and
## [member fail_writes] makes every mutating operation fail (full or
## read-only disk) while leaving the stored entries untouched.

## When true, write/remove/rename fail with [constant ERR_FILE_CANT_WRITE].
var fail_writes: bool = false
## Number of successful [method write_text] calls (lets tests observe debouncing).
var write_count: int = 0
var _entries: Dictionary = {}


## Returns the entry's text, or "" when it is missing or unreadable.
func read_text(entry_name: String) -> String:
	var value: Variant = _entries.get(entry_name, "")
	return value as String if typeof(value) == TYPE_STRING else ""


## Replaces the entry; fails without changes while [member fail_writes] is set.
func write_text(entry_name: String, text: String) -> Error:
	if not _is_valid_name(entry_name):
		return _reject_name(entry_name)
	if fail_writes:
		return ERR_FILE_CANT_WRITE
	_entries[entry_name] = text
	write_count += 1
	return OK


## True when the entry exists.
func exists(entry_name: String) -> bool:
	return _entries.has(entry_name)


## Deletes the entry; [constant ERR_FILE_NOT_FOUND] when it is missing.
func remove(entry_name: String) -> Error:
	if not _is_valid_name(entry_name):
		return _reject_name(entry_name)
	if not _entries.has(entry_name):
		return ERR_FILE_NOT_FOUND
	if fail_writes:
		return ERR_FILE_CANT_WRITE
	_entries.erase(entry_name)
	return OK


## Renames an entry, replacing any existing entry with the target name.
func rename(from_name: String, to_name: String) -> Error:
	if not _is_valid_name(from_name):
		return _reject_name(from_name)
	if not _is_valid_name(to_name):
		return _reject_name(to_name)
	if not _entries.has(from_name):
		return ERR_FILE_NOT_FOUND
	if fail_writes:
		return ERR_FILE_CANT_WRITE
	if from_name != to_name:
		_entries[to_name] = _entries[from_name]
		_entries.erase(from_name)
	return OK


## Sorted names of the stored entries.
func list_names() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for key: Variant in _entries:
		out.append(str(key))
	out.sort()
	return out


## Test helper: stores [param text] under [param entry_name] unconditionally,
## simulating on-disk damage (ignores [member fail_writes] and name rules).
func corrupt(entry_name: String, text: String) -> void:
	_entries[entry_name] = text
