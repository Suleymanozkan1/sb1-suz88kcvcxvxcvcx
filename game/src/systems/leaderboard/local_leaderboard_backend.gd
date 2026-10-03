class_name LocalLeaderboardBackend
extends LeaderboardBackend
## On-device leaderboard: the player's own best entries per board.
##
## Entries live in a caller-provided dictionary (normally the profile slice
## returned by [method profile_store], so they are saved with the profile).
## It never fabricates other players: every entry is one of the player's own
## runs, and fetch() marks each one with "is_player": true. Each board keeps
## the best [member entries_per_board] runs. Beyond [member board_limit]
## boards, the least recently *played* board is dropped (every submit touches
## its board, even when the run is not a personal top score); all-time boards
## ("alltime:<mode>", one per mode) are never dropped, so long-held personal
## records survive any number of daily / weekly / level boards.
##
## Store layout: {board_id: {"updated": unix, "entries": [{"score",
## "level_id", "mode", "at"}, ...]}} sorted by score, best first.

const STORE_KEY: String = "boards"
const NAME_KEY: String = "online.lb.you"
## Boards with this prefix are kept regardless of [member board_limit].
const PINNED_PREFIX: String = "alltime:"
const DEFAULT_ENTRIES_PER_BOARD: int = 10
const DEFAULT_BOARD_LIMIT: int = 120
const ERROR_INVALID_BOARD: String = "invalid_board"
const ERROR_INVALID_SCORE: String = "invalid_score"

var store: Dictionary
var entries_per_board: int = DEFAULT_ENTRIES_PER_BOARD
var board_limit: int = DEFAULT_BOARD_LIMIT
## Display name for the player's rows ("" = UI shows the NAME_KEY text).
var player_name: String = ""


## [param p_store] is mutated in place; [param config] is the "leaderboard"
## section of data/daily/daily.json.
func _init(p_store: Dictionary = {}, config: Dictionary = {}, p_player_name: String = "") -> void:
	store = p_store
	entries_per_board = maxi(1, int(config.get("local_entries_per_board", DEFAULT_ENTRIES_PER_BOARD)))
	board_limit = maxi(1, int(config.get("local_board_limit", DEFAULT_BOARD_LIMIT)))
	player_name = p_player_name


## The personal-board dictionary inside the profile's daily/online slice
## (created on first use). Pass it to the constructor.
static func profile_store(profile: PlayerProfile) -> Dictionary:
	var raw: Variant = profile.daily.get(STORE_KEY, null)
	if typeof(raw) != TYPE_DICTIONARY:
		var fresh: Dictionary = {}
		profile.daily[STORE_KEY] = fresh
		return fresh
	return raw as Dictionary


## Records the run if it is among the player's best on this board. Result
## adds "stored": bool and "personal_best": bool; "rank" is the personal
## rank of the run (0 when it did not make the personal top list).
func submit(board_id: String, entry: Dictionary) -> Dictionary:
	if board_id.strip_edges().is_empty():
		return LeaderboardBackend.submit_result(false, false, false, ERROR_INVALID_BOARD)
	var raw_score: Variant = entry.get("score", null)
	if not _is_number(raw_score) or int(raw_score) < 0:
		return LeaderboardBackend.submit_result(false, false, false, ERROR_INVALID_SCORE)
	var score: int = int(raw_score)
	var board: Dictionary = _board(board_id)
	var entries: Array = board["entries"] as Array
	var pos: int = entries.size()
	for i: int in entries.size():
		if score > int((entries[i] as Dictionary).get("score", 0)):
			pos = i
			break
	var result: Dictionary = LeaderboardBackend.submit_result(true, true, false)
	result["stored"] = false
	result["personal_best"] = false
	var raw_at: Variant = entry.get("at", 0)
	var at: int = int(raw_at) if _is_number(raw_at) else 0
	# Touch the board on every run so a full board is not mistaken for unused.
	board["updated"] = maxi(int(board["updated"]), at)
	if pos >= entries_per_board:
		return result
	(
		entries
		. insert(
			pos,
			{
				"score": score,
				"level_id": str(entry.get("level_id", "")),
				"mode": str(entry.get("mode", "")),
				"at": at,
			}
		)
	)
	while entries.size() > entries_per_board:
		entries.pop_back()
	result["stored"] = true
	result["personal_best"] = pos == 0
	result["rank"] = pos + 1
	_prune_boards(board_id)
	return result


## The player's best entries on [param board_id], ranked 1..n.
func fetch(board_id: String, limit: int) -> Dictionary:
	var entries: Array = []
	if not store.has(board_id):
		return LeaderboardBackend.fetch_result(true, entries, {})
	var stored: Array = _board(board_id)["entries"] as Array
	var n: int = mini(maxi(limit, 0), stored.size())
	for i: int in n:
		var e: Dictionary = stored[i] as Dictionary
		(
			entries
			. append(
				{
					"rank": i + 1,
					"name": player_name,
					"name_key": NAME_KEY,
					"score": _int_or(e.get("score", 0), 0),
					"level_id": str(e.get("level_id", "")),
					"at": _int_or(e.get("at", 0), 0),
					"is_player": true,
				}
			)
		)
	var player: Dictionary = (entries[0] as Dictionary).duplicate() if not entries.is_empty() else {}
	return LeaderboardBackend.fetch_result(true, entries, player)


## Personal best on [param board_id] (-1 when the board has no entry).
func best_score(board_id: String) -> int:
	if not store.has(board_id):
		return -1
	var entries: Array = _board(board_id)["entries"] as Array
	return int((entries[0] as Dictionary).get("score", 0)) if not entries.is_empty() else -1


## Ids of the boards that hold at least one personal entry.
func board_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k: Variant in store:
		out.append(str(k))
	out.sort()
	return out


## Returns the (sanitised) board dictionary, creating it when missing.
func _board(board_id: String) -> Dictionary:
	var raw: Variant = store.get(board_id, null)
	var board: Dictionary = raw as Dictionary if typeof(raw) == TYPE_DICTIONARY else {}
	var clean: Array = []
	var raw_entries: Variant = board.get("entries", null)
	var is_array: bool = typeof(raw_entries) == TYPE_ARRAY
	if is_array:
		for e: Variant in raw_entries as Array:
			if typeof(e) == TYPE_DICTIONARY and _is_number((e as Dictionary).get("score", null)):
				clean.append(e)
	if not is_array or clean.size() != (raw_entries as Array).size():
		clean.sort_custom(_score_desc)
		board["entries"] = clean
	if not _is_number(board.get("updated", null)):
		board["updated"] = 0
	store[board_id] = board
	return board


func _prune_boards(keep: String) -> void:
	while store.size() > board_limit:
		var oldest: String = ""
		var oldest_t: int = 0
		for k: Variant in store:
			var id: String = str(k)
			if id == keep or id.begins_with(PINNED_PREFIX):
				continue
			var raw: Variant = store[k]
			var t: int = -1
			if typeof(raw) == TYPE_DICTIONARY and _is_number((raw as Dictionary).get("updated", null)):
				t = int((raw as Dictionary)["updated"])
			if oldest.is_empty() or t < oldest_t or (t == oldest_t and id < oldest):
				oldest = id
				oldest_t = t
		if oldest.is_empty():
			return
		store.erase(oldest)


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


## int() of a stored value, [param fallback] when it is not a number.
static func _int_or(v: Variant, fallback: int) -> int:
	return int(v) if _is_number(v) else fallback


static func _score_desc(a: Variant, b: Variant) -> bool:
	return int((a as Dictionary).get("score", 0)) > int((b as Dictionary).get("score", 0))
