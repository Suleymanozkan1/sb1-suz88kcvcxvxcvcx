class_name LeaderboardService
extends RefCounted
## Leaderboards: board ids, local recording, remote submission with an
## offline queue.
##
## Boards for a ranked run (see [method board_ids_for]):
##   "daily:<YYYY-MM-DD>"            daily mode only (date of the daily level)
##   "weekly:<YYYY-Www>:<mode>"      ISO week of the run (UTC)
##   "alltime:<mode>"
##   "level:<level_id>"              classic only (modes with level_board)
## Revived runs and unranked modes (zen) are never submitted; modes that
## require completion (classic, daily, …) submit completed runs only, and
## daily levels are ranked in daily mode only — the same rules
## [ReplayVerifier] enforces on the server.
##
## Every ranked run is recorded in the local backend (the player's own bests,
## works offline). With an enabled remote backend the run is also POSTed;
## transient failures go to profile.pending_submissions (kind "leaderboard",
## bounded, deduplicated by board+score+level) and [method flush_queue]
## retries them later. bus.leaderboard_submitted(board, accepted) is emitted
## once per board when a final outcome is known: remote accepted/rejected,
## or — without a remote backend — after the local record. A run without a
## replay cannot be verified, so with a remote backend it is reported as not
## accepted (it still counts on the personal boards).

const QUEUE_KIND: String = "leaderboard"
const BOARD_DAILY: String = "daily"
const BOARD_WEEKLY: String = "weekly"
const BOARD_ALLTIME: String = "alltime"
const BOARD_LEVEL: String = "level"
const SEPARATOR: String = ":"
const SECONDS_PER_DAY: int = 86400
const DAYS_PER_WEEK: int = 7
const DEFAULT_QUEUE_LIMIT: int = 50
const DEFAULT_QUEUE_MAX_AGE_DAYS: int = 14
const DEFAULT_FETCH_LIMIT: int = 50
const DEFAULT_DAILY_ACCEPT_DAYS_BACK: int = 1
const DEFAULT_WEEKLY_ACCEPT_WEEKS_BACK: int = 1
## Used only when data/daily/daily.json has no "modes" table.
const DEFAULT_MODES: Dictionary = {
	"classic": {"ranked": true, "requires_completion": true, "level_board": true, "shields": true},
	"daily": {"ranked": true, "requires_completion": true, "level_board": false, "shields": true},
	"zen": {"ranked": false, "requires_completion": false, "level_board": false, "shields": true, "zen": true},
}

var profile: PlayerProfile
var bus: EventBus
var clock: GameClock
var local: LeaderboardBackend
var remote: LeaderboardBackend
var config: Dictionary = {}

var _lb_cfg: Dictionary = {}
var _flushing: bool = false


## [param p_config] is data/daily/daily.json (loaded when empty).
func _init(
	p_profile: PlayerProfile,
	p_bus: EventBus,
	p_clock: GameClock,
	p_local: LeaderboardBackend,
	p_remote: LeaderboardBackend = null,
	p_config: Dictionary = {}
) -> void:
	profile = p_profile if p_profile != null else PlayerProfile.new()
	bus = p_bus
	clock = p_clock if p_clock != null else GameClock.new()
	remote = p_remote
	config = p_config if not p_config.is_empty() else DailyChallengeService.load_config()
	var raw: Variant = config.get("leaderboard", {})
	_lb_cfg = raw as Dictionary if typeof(raw) == TYPE_DICTIONARY else {}
	local = p_local
	if local == null:
		local = LocalLeaderboardBackend.new(LocalLeaderboardBackend.profile_store(profile), _lb_cfg)


# --- board ids -------------------------------------------------------------------


## "daily:<date_key>".
static func daily_board(date_key: String) -> String:
	return BOARD_DAILY + SEPARATOR + date_key


## "weekly:<week_key>:<mode>".
static func weekly_board(week_key: String, mode: String) -> String:
	return BOARD_WEEKLY + SEPARATOR + week_key + SEPARATOR + mode


## "alltime:<mode>".
static func alltime_board(mode: String) -> String:
	return BOARD_ALLTIME + SEPARATOR + mode


## "level:<level_id>".
static func level_board(level_id: String) -> String:
	return BOARD_LEVEL + SEPARATOR + level_id


## Splits a board id into {"type", "date_key" | "week_key" + "mode" | "mode" |
## "level_id"}; {} when malformed.
static func parse_board(board_id: String) -> Dictionary:
	var parts: PackedStringArray = board_id.split(SEPARATOR)
	if parts.is_empty():
		return {}
	var type: String = parts[0]
	match type:
		BOARD_DAILY:
			if parts.size() == 2 and DailyChallengeService.day_for_date_key(parts[1]) >= 0:
				return {"type": type, "date_key": parts[1]}
		BOARD_WEEKLY:
			if parts.size() == 3 and not parts[1].is_empty() and not parts[2].is_empty():
				return {"type": type, "week_key": parts[1], "mode": parts[2]}
		BOARD_ALLTIME:
			if parts.size() == 2 and not parts[1].is_empty():
				return {"type": type, "mode": parts[1]}
		BOARD_LEVEL:
			if parts.size() == 2 and not parts[1].is_empty():
				return {"type": type, "level_id": parts[1]}
	return {}


## ISO week keys accepted on [param today] (epoch day): the current week
## and [param weeks_back] previous ones, newest first. Shared with
## [ReplayVerifier] so client pruning and server checks agree.
static func recent_week_keys(today: int, weeks_back: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k: int in maxi(0, weeks_back) + 1:
		out.append(GameClock.week_key_for_day(today - k * DAYS_PER_WEEK))
	return out


## Ranking rules of [param mode] from the "modes" table of [param cfg]
## ({} for unknown modes, which are never ranked).
static func mode_rules_in(cfg: Dictionary, mode: String) -> Dictionary:
	var modes: Variant = cfg.get("modes", null)
	var table: Dictionary = modes as Dictionary if typeof(modes) == TYPE_DICTIONARY else DEFAULT_MODES
	var raw: Variant = table.get(mode, {})
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var rules: Dictionary = (raw as Dictionary).duplicate()
	# Sim modifiers come from the one shared mode table (data/modes/modes.json)
	# so client runs and server re-simulation can never disagree.
	rules.merge(ModeCatalog.shared().verifier_modifiers(StringName(mode)), true)
	return rules


## Ranking rules of [param mode] in this service's configuration.
func mode_rules(mode: StringName) -> Dictionary:
	return LeaderboardService.mode_rules_in(config, String(mode))


## Whether [param result] may be ranked at all (not revived, ranked mode,
## completed when the mode requires it, daily levels in daily mode only).
func is_ranked(result: RunResult) -> bool:
	if result == null or result.revived or result.level_id.is_empty():
		return false
	var rules: Dictionary = mode_rules(result.mode)
	if not bool(rules.get("ranked", false)):
		return false
	if bool(rules.get("requires_completion", true)) and not result.completed:
		return false
	var is_daily_level: bool = not DailyChallengeService.date_key_from_level_id(result.level_id).is_empty()
	return is_daily_level == (String(result.mode) == BOARD_DAILY)


## Boards [param result] counts for, given the UTC [param date_key] of the
## run (falls back to the clock when invalid). Empty when not ranked.
func board_ids_for(result: RunResult, date_key: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if not is_ranked(result):
		return out
	var mode: String = String(result.mode)
	var day: int = DailyChallengeService.day_for_date_key(date_key)
	if day < 0:
		day = clock.day_number()
	if mode == BOARD_DAILY:
		out.append(LeaderboardService.daily_board(DailyChallengeService.date_key_from_level_id(result.level_id)))
	out.append(LeaderboardService.weekly_board(GameClock.week_key_for_day(day), mode))
	out.append(LeaderboardService.alltime_board(mode))
	if bool(mode_rules(result.mode).get("level_board", false)):
		out.append(LeaderboardService.level_board(result.level_id))
	return out


# --- submission ----------------------------------------------------------------


## Records a finished run on every board it counts for (async: await it).
## Local recording always happens; remote failures are queued for retry.
func submit_run(result: RunResult) -> void:
	var boards: PackedStringArray = board_ids_for(result, clock.date_key())
	if boards.is_empty():
		return
	var entry: Dictionary = _entry_for(result)
	for board: String in boards:
		await local.submit(board, entry)
	var remote_ready: bool = remote != null and remote.is_enabled()
	if not remote_ready:
		for board: String in boards:
			_emit_submitted(board, true)
		return
	if (entry["replay"] as Dictionary).is_empty():
		GameLog.warn("leaderboard", "run on %s has no replay; not sent for verification" % result.level_id)
		for board: String in boards:
			_emit_submitted(board, false)
		return
	var offline: bool = false
	for board: String in boards:
		if offline:
			_enqueue(board, entry)
			continue
		var res: Dictionary = await remote.submit(board, entry)
		if LeaderboardService._is_true(res.get("retry", false)):
			offline = true
			_enqueue(board, entry)
		else:
			_emit_submitted(board, LeaderboardService._accepted(res))


## Retries queued remote submissions (async). Stops at the first transient
## failure (still offline); that item moves to the back of the queue so one
## submission the server keeps failing on cannot block every other one.
## Returns how many queued submissions reached a final server verdict
## (accepted or rejected) and left the queue.
func flush_queue() -> int:
	if _flushing or remote == null or not remote.is_enabled():
		return 0
	_flushing = true
	_prune_queue()
	var batch: Array[Dictionary] = []
	for item: Dictionary in profile.pending_submissions:
		if str(item.get("kind", "")) == QUEUE_KIND:
			batch.append(item)
	var delivered: int = 0
	for item: Dictionary in batch:
		var entry: Variant = item.get("entry", {})
		var board: String = str(item.get("board", ""))
		var id: String = str(item.get("id", ""))
		if typeof(entry) != TYPE_DICTIONARY or board.is_empty():
			_remove_queued(id)
			continue
		var res: Dictionary = await remote.submit(board, entry as Dictionary)
		if LeaderboardService._is_true(res.get("retry", false)):
			item["attempts"] = LeaderboardService._as_int(item.get("attempts", 0), 0) + 1
			_move_to_back(item)
			break
		_remove_queued(id)
		delivered += 1
		_emit_submitted(board, LeaderboardService._accepted(res))
	_flushing = false
	return delivered


## Number of leaderboard submissions waiting for the network.
func pending_count() -> int:
	var n: int = 0
	for item: Dictionary in profile.pending_submissions:
		if str(item.get("kind", "")) == QUEUE_KIND:
			n += 1
	return n


## Board entries for the UI (async). Uses the remote board when reachable,
## otherwise the player's own local bests. Adds "source" ("remote"/"local")
## and "status_key" (i18n key describing an offline/disabled fallback, or "").
func fetch(board_id: String, limit: int = -1) -> Dictionary:
	var n: int = limit if limit > 0 else int(_lb_cfg.get("fetch_default_limit", DEFAULT_FETCH_LIMIT))
	var has_remote: bool = remote != null and remote.is_enabled()
	if has_remote:
		var r: Dictionary = await remote.fetch(board_id, n)
		if LeaderboardService._is_true(r.get("ok", false)):
			r["source"] = "remote"
			r["status_key"] = ""
			return r
	var l: Dictionary = await local.fetch(board_id, n)
	l["source"] = "local"
	l["status_key"] = "online.lb.offline" if has_remote else "online.lb.local_only"
	return l


func _entry_for(result: RunResult) -> Dictionary:
	var replay: Dictionary = result.replay.to_dict() if result.replay != null else {}
	return {
		"score": maxi(0, result.score),
		"level_id": result.level_id,
		"mode": String(result.mode),
		"at": clock.now_unix(),
		"replay": replay,
		"sim_version": int(replay.get("sim_version", RunReplay.SIM_VERSION)),
	}


func _emit_submitted(board: String, accepted: bool) -> void:
	if bus != null:
		bus.leaderboard_submitted.emit(board, accepted)


static func _queue_id(board: String, entry: Dictionary) -> String:
	return "%s|%s|%d" % [board, str(entry.get("level_id", "")), int(entry.get("score", 0))]


func _enqueue(board: String, entry: Dictionary) -> void:
	var id: String = LeaderboardService._queue_id(board, entry)
	for item: Dictionary in profile.pending_submissions:
		if str(item.get("kind", "")) == QUEUE_KIND and str(item.get("id", "")) == id:
			return
	(
		profile
		. pending_submissions
		. append(
			{
				"kind": QUEUE_KIND,
				"id": id,
				"board": board,
				"entry": entry.duplicate(true),
				"queued_at": clock.now_unix(),
				"attempts": 0,
			}
		)
	)
	var limit: int = maxi(1, int(_lb_cfg.get("queue_limit", DEFAULT_QUEUE_LIMIT)))
	while pending_count() > limit:
		_drop_oldest_queued()


func _move_to_back(item: Dictionary) -> void:
	var i: int = profile.pending_submissions.find(item)
	if i < 0:
		return
	profile.pending_submissions.remove_at(i)
	profile.pending_submissions.append(item)


func _drop_oldest_queued() -> void:
	for i: int in profile.pending_submissions.size():
		if str(profile.pending_submissions[i].get("kind", "")) == QUEUE_KIND:
			GameLog.info("leaderboard", "queue full, dropping %s" % str(profile.pending_submissions[i].get("id", "")))
			profile.pending_submissions.remove_at(i)
			return


func _remove_queued(id: String) -> void:
	for i: int in profile.pending_submissions.size():
		var item: Dictionary = profile.pending_submissions[i]
		if str(item.get("kind", "")) == QUEUE_KIND and str(item.get("id", "")) == id:
			profile.pending_submissions.remove_at(i)
			return


## Drops queued items the server would refuse anyway: older than the maximum
## age, or daily / weekly boards outside the server's accepted window.
func _prune_queue() -> void:
	var now: int = clock.now_unix()
	var today: int = clock.day_number()
	var max_age: int = int(_lb_cfg.get("queue_max_age_days", DEFAULT_QUEUE_MAX_AGE_DAYS)) * SECONDS_PER_DAY
	var verifier: Variant = config.get("verifier", {})
	var days_back: int = DEFAULT_DAILY_ACCEPT_DAYS_BACK
	var weeks_back: int = DEFAULT_WEEKLY_ACCEPT_WEEKS_BACK
	if typeof(verifier) == TYPE_DICTIONARY:
		days_back = int((verifier as Dictionary).get("daily_accept_days_back", days_back))
		weeks_back = int((verifier as Dictionary).get("weekly_accept_weeks_back", weeks_back))
	var weeks: PackedStringArray = LeaderboardService.recent_week_keys(today, weeks_back)
	var i: int = profile.pending_submissions.size() - 1
	while i >= 0:
		var item: Dictionary = profile.pending_submissions[i]
		if str(item.get("kind", "")) == QUEUE_KIND:
			var queued_at: int = LeaderboardService._as_int(item.get("queued_at", null), 0)
			var stale: bool = now - queued_at > max_age
			var board: Dictionary = LeaderboardService.parse_board(str(item.get("board", "")))
			if board.is_empty():
				stale = true
			elif str(board["type"]) == BOARD_DAILY:
				stale = stale or DailyChallengeService.day_for_date_key(str(board["date_key"])) < today - days_back
			elif str(board["type"]) == BOARD_WEEKLY:
				stale = stale or not weeks.has(str(board["week_key"]))
			if stale:
				profile.pending_submissions.remove_at(i)
		i -= 1


## int() of a persisted value; [param fallback] for anything non-numeric
## (int(null) would abort the caller with a script error).
static func _as_int(v: Variant, fallback: int) -> int:
	return int(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else fallback


## True only for a real boolean true (untrusted data: comparing a string or
## number with == true is a script error in Godot 4).
static func _is_true(v: Variant) -> bool:
	return typeof(v) == TYPE_BOOL and bool(v)


## Final verdict of a backend submit() result: handled and accepted.
static func _accepted(res: Dictionary) -> bool:
	return LeaderboardService._is_true(res.get("ok", false)) and LeaderboardService._is_true(res.get("accepted", false))
