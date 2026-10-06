class_name LeaderboardBackend
extends RefCounted
## Storage/transport interface for leaderboards.
##
## Implementations: [LocalLeaderboardBackend] (the player's own best entries,
## on device, never invents other players) and [HttpLeaderboardBackend]
## (remote, server-verified). Callers always `await` [method submit] and
## [method fetch]: remote implementations are coroutines, local ones return
## immediately — `await` handles both.
##
## submit() result: {"ok": bool (request handled), "accepted": bool (score
## stored), "retry": bool (transient failure: queue and try again later),
## "rank": int (0 = unknown), "error": String}.
## fetch() result: {"ok": bool, "entries": [{"rank", "name", "score"}, ...],
## "player": {"rank", "name", "score"} or {}, "error": String}.

const ERROR_UNSUPPORTED: String = "unsupported"


## Submits [param entry] ({"score", "level_id", "mode", "at", "replay",
## "sim_version"}) to [param board_id]. Coroutine-compatible.
func submit(board_id: String, entry: Dictionary) -> Dictionary:
	GameLog.warn("leaderboard", "submit(%s) on abstract backend (score %s)" % [board_id, str(entry.get("score", 0))])
	return LeaderboardBackend.submit_result(false, false, false, ERROR_UNSUPPORTED)


## Fetches up to [param limit] ranked entries of [param board_id].
## Coroutine-compatible.
func fetch(board_id: String, limit: int) -> Dictionary:
	GameLog.warn("leaderboard", "fetch(%s, %d) on abstract backend" % [board_id, limit])
	return LeaderboardBackend.fetch_result(false, [], {}, ERROR_UNSUPPORTED)


## True for backends that talk to a server.
func is_remote() -> bool:
	return false


## False when the backend is configured off (e.g. no server URL).
func is_enabled() -> bool:
	return true


## Builds a well-formed submit() result dictionary.
static func submit_result(ok: bool, accepted: bool, retry: bool, error: String = "", rank: int = 0) -> Dictionary:
	return {"ok": ok, "accepted": accepted, "retry": retry, "error": error, "rank": rank}


## Builds a well-formed fetch() result dictionary.
static func fetch_result(ok: bool, entries: Array, player: Dictionary, error: String = "") -> Dictionary:
	return {"ok": ok, "entries": entries, "player": player, "error": error}
