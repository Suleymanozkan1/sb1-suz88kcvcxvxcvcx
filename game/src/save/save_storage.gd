class_name SaveStorage
extends RefCounted
## Abstract named-blob store used by [SaveService].
##
## Entries are flat names (no directories) holding UTF-8 text. Implementations
## must make [method write_text] atomic: after it returns, the entry holds
## either the complete previous text or the complete new text, never a mix.
## The base class stores nothing; every operation reports
## [constant ERR_UNAVAILABLE] so a missing subclass override is obvious.

## Suffix reserved for in-flight atomic writes; stored names may not use it.
const TEMP_SUFFIX: String = ".tmp"
## Longest accepted entry name (well below every platform's file name limit).
const MAX_NAME_LENGTH: int = 96
## Characters that would let a name escape the storage directory.
const FORBIDDEN_NAME_CHARS: PackedStringArray = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]
## Lowest character code allowed in a name (everything below is a control code).
const FIRST_PRINTABLE_CODE: int = 0x20
## The DEL control character, also refused in names.
const DELETE_CODE: int = 0x7F


## Returns the stored text, or "" when the entry is missing or unreadable.
func read_text(_name: String) -> String:
	return ""


## Atomically replaces the entry's text (temp entry first, then rename).
func write_text(_name: String, _text: String) -> Error:
	return ERR_UNAVAILABLE


## True when an entry with this name exists.
func exists(_name: String) -> bool:
	return false


## Deletes the entry. Returns [constant ERR_FILE_NOT_FOUND] when it is missing.
func remove(_name: String) -> Error:
	return ERR_UNAVAILABLE


## Renames an entry, replacing any existing entry called [param _to_name].
func rename(_from_name: String, _to_name: String) -> Error:
	return ERR_UNAVAILABLE


## Lists stored entry names, sorted (in-flight temp entries are excluded).
func list_names() -> PackedStringArray:
	return PackedStringArray()


## Shared name rule for every implementation: a plain, short, printable file
## name that cannot traverse directories or collide with a temp entry.
func _is_valid_name(entry_name: String) -> bool:
	if entry_name.is_empty() or entry_name.length() > MAX_NAME_LENGTH:
		return false
	if entry_name.begins_with(".") or entry_name.ends_with(TEMP_SUFFIX):
		return false
	for ch: String in FORBIDDEN_NAME_CHARS:
		if entry_name.contains(ch):
			return false
	for i: int in entry_name.length():
		var code: int = entry_name.unicode_at(i)
		if code < FIRST_PRINTABLE_CODE or code == DELETE_CODE:
			return false
	return true


## Logs and returns the error used for rejected names.
func _reject_name(entry_name: String) -> Error:
	GameLog.warn("save", "rejected storage entry name '%s'" % entry_name)
	return ERR_INVALID_PARAMETER
