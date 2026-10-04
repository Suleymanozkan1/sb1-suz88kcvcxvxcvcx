class_name CloudSaveProvider
extends RefCounted
## Storage interface for the cloud copy of the save (REQ-182).
##
## Implementations: [NullCloudSaveProvider] (no server configured: the feature
## is off and says so) and [HttpCloudSaveProvider] (one remote save slot per
## install). Callers always `await` [method fetch] and [method push]: remote
## implementations are coroutines, the others return immediately.
##
## fetch() result: {"ok": bool (request handled), "found": bool (a cloud copy
## exists), "blob": String (that copy: a [SaveService] envelope), "revision":
## String (opaque server version of the blob), "retry": bool (transient
## failure: try again later), "error": String}.
## [br]push() result: {"ok": bool (stored), "revision": String (the new
## revision), "conflict": bool (the cloud moved on since the base revision; the
## server's current copy is in "remote_blob" / "remote_revision"), "retry":
## bool, "error": String, "remote_blob": String, "remote_revision": String}.

const ERROR_UNSUPPORTED: String = "unsupported"
## Honest answer of a build without a cloud save server.
const ERROR_UNAVAILABLE: String = "cloud_unavailable"
## Revisions are opaque tokens of 1..MAX_REVISION_LENGTH characters from
## [constant REVISION_CHARS]; anything else is refused.
const MAX_REVISION_LENGTH: int = 128
const REVISION_CHARS: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-"


## False when no server is configured.
func is_enabled() -> bool:
	return false


## Downloads the cloud copy. Coroutine-compatible.
func fetch() -> Dictionary:
	GameLog.warn("cloud", "fetch() on abstract provider")
	return CloudSaveProvider.fetch_result(false, false, "", "", false, ERROR_UNSUPPORTED)


## Uploads [param blob] (a save envelope) as the successor of
## [param base_revision] ("" when no cloud copy is known). Coroutine-compatible.
func push(blob: String, base_revision: String) -> Dictionary:
	GameLog.warn("cloud", "push(%d chars, base '%s') on abstract provider" % [blob.length(), base_revision])
	return CloudSaveProvider.push_result(false, "", false, false, ERROR_UNSUPPORTED)


## [param raw] when it is a well-formed revision token, else "".
static func valid_revision(raw: Variant) -> String:
	if typeof(raw) != TYPE_STRING:
		return ""
	var text: String = raw as String
	if text.is_empty() or text.length() > MAX_REVISION_LENGTH:
		return ""
	for i: int in text.length():
		if not REVISION_CHARS.contains(text[i]):
			return ""
	return text


## Builds a well-formed fetch() result dictionary.
static func fetch_result(
	ok: bool, found: bool, blob: String, revision: String, retry: bool, error: String = ""
) -> Dictionary:
	return {"ok": ok, "found": found, "blob": blob, "revision": revision, "retry": retry, "error": error}


## Builds a well-formed push() result dictionary.
static func push_result(
	ok: bool,
	revision: String,
	conflict: bool,
	retry: bool,
	error: String = "",
	remote_blob: String = "",
	remote_revision: String = ""
) -> Dictionary:
	return {
		"ok": ok,
		"revision": revision,
		"conflict": conflict,
		"retry": retry,
		"error": error,
		"remote_blob": remote_blob,
		"remote_revision": remote_revision,
	}
