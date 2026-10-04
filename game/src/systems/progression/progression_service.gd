class_name ProgressionService
extends RefCounted
## Campaign progression: level records, stars, level/world unlocks, player XP
## and levels, plus the "what next" hint and the Progress screen summary.
##
## Owns these profile slices: [member PlayerProfile.levels],
## [member PlayerProfile.unlocked_worlds], [member PlayerProfile.xp] (lifetime
## total XP), [member PlayerProfile.player_level] and the world stats
## (worlds_completed / worlds_perfected, written through [StatsService]).
##
## Unlock rules (also described in data/progression/progression.json):
## [br]- w01_l01 is always playable; every other level needs the previous level
## in campaign order cleared and its world unlocked.
## [br]- World N (N >= 2) unlocks when world N-1 is unlocked, its boss level is
## cleared AND total stars >= the world's unlock_stars. Unlocks are permanent.
## [br]Stars: [method campaign_stars] are earned on levels (0..3 each, at most
## [method max_stars]); [method total_stars] adds the bonus stars rewards
## grant ([member PlayerProfile.bonus_stars]) and is the count every star
## unlock uses (worlds, modes, cosmetics). "x / max" displays use the campaign
## count so they never exceed the maximum.
## Construction silently syncs world unlocks that already hold (e.g. after a
## save migration); later unlocks emit [signal EventBus.world_unlocked].

const CONFIG_PATH: String = "res://data/progression/progression.json"
const MAX_LEVEL_STARS: int = 3
const DEFAULT_XP_BASE: float = 120.0
const DEFAULT_XP_EXPONENT: float = 1.25
const DEFAULT_XP_STEP: int = 5
const DEFAULT_MAX_PLAYER_LEVEL: int = 100
const DEFAULT_MAX_XP_GRANT: int = 5000
const DEFAULT_MAX_TOTAL_XP: int = 50_000_000
const DEFAULT_RECORD_MODES: PackedStringArray = ["classic"]
const XP_BASE_MIN: float = 1.0
const XP_BASE_MAX: float = 100_000.0
const XP_EXPONENT_MIN: float = 0.5
const XP_EXPONENT_MAX: float = 3.0
const XP_STEP_MAX: int = 1000
## Hard ceilings that hold whatever the data says.
const PLAYER_LEVEL_LIMIT: int = 999
const TOTAL_XP_LIMIT: int = 1_000_000_000_000
const HINT_WORLD: String = "world"
const HINT_LEVEL: String = "level"
const HINT_PLAYER_LEVEL: String = "player_level"
const HINT_KEY_LEVEL: String = "progression.hint.level"
const HINT_KEY_WORLD: String = "progression.hint.world"
const HINT_KEY_STARS: String = "progression.hint.stars"
const HINT_KEY_PLAYER_LEVEL: String = "progression.hint.player_level"
const HINT_KEY_COMPLETE: String = "progression.hint.complete"
## Translation key of a world's display name (strings owned by the UI texts).
const WORLD_NAME_KEY: String = "world.%s.name"
## Largest magnitude accepted when reading stored numbers (keeps float -> int
## conversions exact and platform-independent).
const READ_LIMIT: float = 1_000_000_000_000.0
## Shared read-only stand-in for a missing level record.
const EMPTY_RECORD: Dictionary = {}

## The configuration actually in use (after validation).
var config: Dictionary = {}
var xp_base: float = DEFAULT_XP_BASE
var xp_exponent: float = DEFAULT_XP_EXPONENT
var xp_step: int = DEFAULT_XP_STEP
var max_player_level: int = DEFAULT_MAX_PLAYER_LEVEL
var max_xp_grant: int = DEFAULT_MAX_XP_GRANT
var max_total_xp: int = DEFAULT_MAX_TOTAL_XP
## Run modes whose results update level records (zen/endless never unlock).
var record_modes: PackedStringArray = DEFAULT_RECORD_MODES.duplicate()

var _profile: PlayerProfile
var _bus: EventBus
var _catalog: WorldCatalog
var _stats: StatsService
## Campaign order: index (global number - 1) -> level id.
var _ids: PackedStringArray = PackedStringArray()
## level id -> global number (1-based).
var _number: Dictionary[String, int] = {}
## index (global number - 1) -> 1-based world index.
var _level_world: PackedInt32Array = PackedInt32Array()
## index (world index - 1) -> world id.
var _world_ids: PackedStringArray = PackedStringArray()
## index (world index - 1) -> index into [member _ids] of the world's first level.
var _world_start: PackedInt32Array = PackedInt32Array()
## index L -> XP needed to go from level L to L + 1 (index 0 unused).
var _xp_needed: PackedInt64Array = PackedInt64Array()
## index L -> lifetime XP at which level L starts (indices 0 and 1 are 0).
var _xp_threshold: PackedInt64Array = PackedInt64Array()


## [param cfg] is data/progression/progression.json (the spec's `config`
## argument); an empty dictionary loads the default file. Invalid values fall
## back to defaults (logged). A null profile or catalog is replaced (logged).
func _init(profile: PlayerProfile, bus: EventBus, catalog: WorldCatalog, cfg: Dictionary = {}) -> void:
	if profile == null:
		GameLog.error("progression", "no profile injected; using a blank in-memory profile")
		profile = PlayerProfile.new()
	if catalog == null:
		GameLog.error("progression", "no world catalog injected; loading the default catalog")
		catalog = WorldCatalog.load_default()
	_profile = profile
	_bus = bus
	_catalog = catalog
	_apply_config(cfg if not cfg.is_empty() else ProgressionService.load_config())
	_stats = StatsService.new(_profile, _bus, config)
	_index_levels()
	_build_xp_table()
	_sync_world_unlocks(false)


## Reads the progression config file; returns {} (logged) when unreadable.
static func load_config(path: String = CONFIG_PATH) -> Dictionary:
	var data: Dictionary = JsonIO.read_dict(path)
	if data.is_empty():
		GameLog.warn("progression", "progression config %s missing or invalid; using defaults" % path)
	return data


## Records one finished campaign run. Failed runs only count an attempt.
## Returns {"first_clear", "prev_stars", "new_stars" (delta), "new_best",
## "first_perfect", "unlocked_level", "unlocked_worlds"} plus "accepted",
## "level_id", "stars" (now), "world_completed" / "world_perfected" (world id
## when this run completed or perfected its world for the first time, else "").
func record_level_result(result: RunResult, level_meta: Dictionary = {}) -> Dictionary:
	var outcome: Dictionary = _empty_outcome()
	var level_id: String = _result_level_id(result, level_meta)
	if level_id.is_empty():
		return outcome
	var entry: Dictionary = _entry(level_id)
	outcome["level_id"] = level_id
	outcome["prev_stars"] = int(entry["stars"])
	outcome["stars"] = int(entry["stars"])
	outcome["accepted"] = true
	entry["attempts"] = mini(int(entry["attempts"]) + 1, StatsService.MAX_VALUE)
	if not result.completed:
		_profile.levels[level_id] = entry
		return outcome
	var world_index: int = _level_world[_number[level_id] - 1]
	var was_complete: bool = world_complete(world_index)
	var was_perfect: bool = world_perfect(world_index)
	var next_id: String = _next_id(level_id)
	var next_was_unlocked: bool = next_id.is_empty() or is_level_unlocked(next_id)
	_apply_completion(entry, result, outcome)
	_profile.levels[level_id] = entry
	if int(outcome["new_stars"]) > 0 and _bus != null:
		_bus.stars_changed.emit(total_stars())
	var worlds: Array[String] = _sync_world_unlocks(true)
	outcome["unlocked_worlds"] = worlds
	_announce_unlocks(outcome, next_id, next_was_unlocked, worlds)
	if not was_complete and world_complete(world_index):
		outcome["world_completed"] = _world_id(world_index)
	if not was_perfect and world_perfect(world_index):
		outcome["world_perfected"] = _world_id(world_index)
	_update_world_stats()
	return outcome


## XP needed to go from [param level] to the next one (strictly increasing up
## to [constant PLAYER_LEVEL_LIMIT]; higher levels use the limit's value).
func xp_for_next(level: int) -> int:
	var lvl: int = clampi(level, 1, PLAYER_LEVEL_LIMIT)
	var last: int = _xp_needed.size() - 1
	if lvl <= last:
		return _xp_needed[lvl]
	var floor_value: int = _xp_needed[last] + xp_step * (lvl - last)
	return maxi(_curve_value(lvl), floor_value)


## Grants XP (lifetime total) and levels up as many times as earned.
## Emits xp_gained once, then player_level_up for every level gained.
## Returns the number of levels gained. Non-positive amounts are ignored and
## single grants above the configured cap are clamped (logged). Neither XP nor
## the player level is ever lowered, even when a data update lowers a cap.
func add_xp(amount: int) -> int:
	if amount <= 0:
		if amount < 0:
			GameLog.warn("progression", "rejected negative xp grant %d" % amount)
		return 0
	var granted: int = amount
	if granted > max_xp_grant:
		GameLog.warn("progression", "xp grant %d above cap %d; clamped" % [amount, max_xp_grant])
		granted = max_xp_grant
	var before: int = maxi(_profile.xp, 0)
	var after: int = before + mini(granted, maxi(max_total_xp - before, 0))
	_profile.xp = after
	if after > before and _bus != null:
		_bus.xp_gained.emit(after - before, after)
	var level: int = maxi(_profile.player_level, 1)
	var gained: int = 0
	while level < max_player_level and after >= _xp_threshold[level + 1]:
		level += 1
		gained += 1
		_profile.player_level = level
		if _bus != null:
			_bus.player_level_up.emit(level)
	if _profile.player_level < level:
		_profile.player_level = level
	return gained


## XP bar state: {"level", "total_xp", "into_level", "needed", "at_max"}.
## A level at or above the cap shows a full bar.
func xp_progress() -> Dictionary:
	var level: int = maxi(_profile.player_level, 1)
	var at_max: bool = level >= max_player_level
	var needed: int = xp_for_next(mini(level, max_player_level))
	var into: int = needed
	if not at_max:
		into = clampi(_profile.xp - _xp_threshold[level], 0, needed)
	return {"level": level, "total_xp": _profile.xp, "into_level": into, "needed": needed, "at_max": at_max}


## True when [param level_id] can be played now.
func is_level_unlocked(level_id: String) -> bool:
	var n: int = int(_number.get(level_id, 0))
	if n <= 0:
		return false
	if n == 1:
		return true
	var world_index: int = _level_world[n - 1]
	if world_index != 1 and not _profile.unlocked_worlds.has(_world_id(world_index)):
		return false
	return _is_cleared(_ids[n - 2])


## True for the first world and every world recorded as unlocked.
func is_world_unlocked(world_id: String) -> bool:
	var index: int = _world_index(world_id)
	if index <= 0:
		return false
	return index == 1 or _profile.unlocked_worlds.has(world_id)


## Unlocks every world whose rule now holds; returns the newly unlocked ids
## (in order) and emits world_unlocked for each. Also brings the
## worlds_completed / worlds_perfected stats up to date (e.g. after a save
## load or migration), so call it once after loading.
func refresh_world_unlocks() -> Array[String]:
	var unlocked: Array[String] = _sync_world_unlocks(true)
	_update_world_stats()
	return unlocked


## Stars still missing for [param world_id]'s star requirement (0 when met,
## unlocked or unknown). The boss requirement is separate.
func stars_needed_for(world_id: String) -> int:
	var index: int = _world_index(world_id)
	if index <= 0:
		GameLog.warn("progression", "stars_needed_for unknown world %s" % world_id)
		return 0
	if is_world_unlocked(world_id):
		return 0
	return maxi(_unlock_stars(index) - total_stars(), 0)


## Stars earned in the world at 1-based [param world_index].
func world_stars(world_index: int) -> int:
	var total: int = 0
	for id: String in _world_level_ids(world_index):
		total += _stars_of(id)
	return total


## Number of cleared levels in the world at [param world_index].
func world_cleared_count(world_index: int) -> int:
	var count: int = 0
	for id: String in _world_level_ids(world_index):
		if _is_cleared(id):
			count += 1
	return count


## True when every level of the world is cleared.
func world_complete(world_index: int) -> bool:
	var count: int = _catalog.levels_in(world_index)
	return count > 0 and world_cleared_count(world_index) == count


## True when every level of the world has all three stars (which includes a
## perfect run on each).
func world_perfect(world_index: int) -> bool:
	var count: int = _catalog.levels_in(world_index)
	return count > 0 and world_stars(world_index) == count * MAX_LEVEL_STARS


## Stars that count toward unlocks: [method campaign_stars] plus the bonus
## stars granted by rewards.
func total_stars() -> int:
	return campaign_stars() + bonus_stars()


## Campaign stars (only valid catalog levels count, 0..3 each); never more
## than [method max_stars].
func campaign_stars() -> int:
	var total: int = 0
	for key: Variant in _profile.levels:
		var id: String = str(key)
		if _number.has(id):
			total += _stars_of(id)
	return total


## Bonus stars granted by rewards (sanitised, 0..PlayerProfile.MAX_BONUS_STARS).
func bonus_stars() -> int:
	return clampi(_profile.bonus_stars, 0, PlayerProfile.MAX_BONUS_STARS)


## Maximum campaign stars (levels x 3).
func max_stars() -> int:
	return _ids.size() * MAX_LEVEL_STARS


## The furthest level (campaign order) that is unlocked.
func highest_unlocked_level() -> String:
	var best: String = ""
	for id: String in _ids:
		if is_level_unlocked(id):
			best = id
	return best


## First unlocked level not cleared yet, else the highest unlocked level.
func next_level_to_play() -> String:
	for id: String in _ids:
		if is_level_unlocked(id) and not _is_cleared(id):
			return id
	return highest_unlocked_level()


## The nearest goal for the main menu:
## {"type": "world"|"level"|"player_level", "id", "progress", "target", "label_key"}.
## Priority: a world blocked only by stars -> the next level to clear (world
## progress) -> improving stars once everything is cleared -> player level.
func next_unlock_hint() -> Dictionary:
	var stars: int = total_stars()
	var blocked: int = _star_blocked_world(stars)
	if blocked > 0:
		return _hint(HINT_WORLD, _world_id(blocked), stars, _unlock_stars(blocked), HINT_KEY_WORLD)
	var next_id: String = next_level_to_play()
	if not next_id.is_empty() and not _is_cleared(next_id):
		var world_index: int = _level_world[_number[next_id] - 1]
		var progress: int = world_cleared_count(world_index)
		return _hint(HINT_LEVEL, next_id, progress, _catalog.levels_in(world_index), HINT_KEY_LEVEL)
	var to_improve: String = _first_level_below_max_stars()
	if not to_improve.is_empty():
		return _hint(HINT_LEVEL, to_improve, campaign_stars(), max_stars(), HINT_KEY_STARS)
	var xp: Dictionary = xp_progress()
	var level: int = int(xp["level"])
	if bool(xp["at_max"]):
		return _hint(HINT_PLAYER_LEVEL, str(level), int(xp["needed"]), int(xp["needed"]), HINT_KEY_COMPLETE)
	return _hint(HINT_PLAYER_LEVEL, str(level + 1), int(xp["into_level"]), int(xp["needed"]), HINT_KEY_PLAYER_LEVEL)


## Data for the Progress screen: {"worlds": [{"index", "id", "name",
## "name_key", "stars", "max", "cleared", "levels", "unlocked", "perfect",
## "complete", "stars_required", "stars_needed", "boss_cleared"}...],
## "total_stars", "max_stars", "bonus_stars", "unlock_stars", "levels_cleared",
## "total_levels", "worlds_unlocked", "player_level", "xp"}. "total_stars" is
## the campaign count shown against "max_stars"; "unlock_stars" adds the bonus
## stars and drives "stars_needed". Show the translated "name_key"
## ("world.<id>.name"); "name" is the untranslated data fallback.
func progress_summary() -> Dictionary:
	var worlds: Array[Dictionary] = []
	var cleared_total: int = 0
	var unlocked_count: int = 0
	var total: int = total_stars()
	for index: int in range(1, _catalog.world_count() + 1):
		var id: String = _world_id(index)
		var levels: int = _catalog.levels_in(index)
		var cleared: int = world_cleared_count(index)
		var stars: int = world_stars(index)
		var unlocked: bool = is_world_unlocked(id)
		cleared_total += cleared
		unlocked_count += 1 if unlocked else 0
		(
			worlds
			. append(
				{
					"index": index,
					"id": id,
					"name": str(_catalog.world_at(index).get("name", id)),
					"name_key": WORLD_NAME_KEY % id,
					"stars": stars,
					"max": levels * MAX_LEVEL_STARS,
					"cleared": cleared,
					"levels": levels,
					"unlocked": unlocked,
					"perfect": levels > 0 and stars == levels * MAX_LEVEL_STARS,
					"complete": levels > 0 and cleared == levels,
					"stars_required": _unlock_stars(index),
					"stars_needed": 0 if unlocked else maxi(_unlock_stars(index) - total, 0),
					"boss_cleared": _boss_cleared(index),
				}
			)
		)
	return {
		"worlds": worlds,
		"total_stars": campaign_stars(),
		"max_stars": max_stars(),
		"bonus_stars": bonus_stars(),
		"unlock_stars": total,
		"levels_cleared": cleared_total,
		"total_levels": _ids.size(),
		"worlds_unlocked": unlocked_count,
		"player_level": maxi(_profile.player_level, 1),
		"xp": xp_progress(),
	}


func _apply_config(cfg: Dictionary) -> void:
	config = cfg.duplicate(true)
	var curve: Dictionary = _section(cfg, "xp_curve")
	xp_base = _num(curve, "base", DEFAULT_XP_BASE, XP_BASE_MIN, XP_BASE_MAX)
	xp_exponent = _num(curve, "exponent", DEFAULT_XP_EXPONENT, XP_EXPONENT_MIN, XP_EXPONENT_MAX)
	xp_step = roundi(_num(curve, "step", DEFAULT_XP_STEP, 1.0, XP_STEP_MAX))
	var caps: Dictionary = _section(cfg, "xp_caps")
	max_player_level = roundi(_num(caps, "max_player_level", DEFAULT_MAX_PLAYER_LEVEL, 2.0, PLAYER_LEVEL_LIMIT))
	max_xp_grant = roundi(_num(caps, "max_single_grant", DEFAULT_MAX_XP_GRANT, 1.0, TOTAL_XP_LIMIT))
	max_total_xp = roundi(_num(caps, "max_total_xp", DEFAULT_MAX_TOTAL_XP, 1.0, TOTAL_XP_LIMIT))
	record_modes = DEFAULT_RECORD_MODES.duplicate()
	var modes: Variant = cfg.get("record_modes", null)
	if typeof(modes) == TYPE_ARRAY and not (modes as Array).is_empty():
		record_modes = PackedStringArray()
		for mode: Variant in modes as Array:
			record_modes.append(str(mode))
	elif modes != null:
		GameLog.warn("progression", "record_modes must be a non-empty array; using defaults")


func _index_levels() -> void:
	_ids.clear()
	_number.clear()
	_level_world.clear()
	_world_ids.clear()
	_world_start.clear()
	for world_index: int in range(1, _catalog.world_count() + 1):
		_world_ids.append(str(_catalog.world_at(world_index).get("id", "")))
		_world_start.append(_ids.size())
		for local_index: int in range(1, _catalog.levels_in(world_index) + 1):
			var id: String = WorldCatalog.level_id(world_index, local_index)
			_ids.append(id)
			_level_world.append(world_index)
			_number[id] = _ids.size()
	if _ids.is_empty():
		GameLog.error("progression", "world catalog has no levels; progression is empty")


func _build_xp_table() -> void:
	_xp_needed.resize(max_player_level + 1)
	_xp_threshold.resize(max_player_level + 1)
	_xp_needed[0] = 0
	_xp_threshold[0] = 0
	_xp_threshold[1] = 0
	for level: int in range(1, max_player_level + 1):
		var need: int = _curve_value(level)
		if level > 1:
			need = maxi(need, _xp_needed[level - 1] + xp_step)
		_xp_needed[level] = need
		if level < max_player_level:
			_xp_threshold[level + 1] = mini(_xp_threshold[level] + need, TOTAL_XP_LIMIT)


func _curve_value(level: int) -> int:
	# Clamped before the float -> int conversion, which is platform-specific
	# (and meaningless) for values beyond the int range.
	var raw: float = minf(xp_base * pow(float(level), xp_exponent), float(TOTAL_XP_LIMIT))
	return maxi(roundi(raw / float(xp_step)) * xp_step, xp_step)


func _result_level_id(result: RunResult, level_meta: Dictionary) -> String:
	if result == null:
		GameLog.warn("progression", "record_level_result called without a result")
		return ""
	var level_id: String = result.level_id if not result.level_id.is_empty() else str(level_meta.get("id", ""))
	if not _number.has(level_id):
		GameLog.warn("progression", "ignored result for unknown level '%s'" % level_id)
		return ""
	if not record_modes.has(str(result.mode)):
		GameLog.debug("progression", "mode %s does not update level records" % result.mode)
		return ""
	if not is_level_unlocked(level_id):
		GameLog.warn("progression", "ignored result for locked level %s" % level_id)
		return ""
	return level_id


func _apply_completion(entry: Dictionary, result: RunResult, outcome: Dictionary) -> void:
	var prev_stars: int = int(entry["stars"])
	var prev_best: int = int(entry["best_score"])
	var first_clear: bool = int(entry["clears"]) == 0
	var run_stars: int = clampi(result.stars, 1, MAX_LEVEL_STARS)
	entry["clears"] = mini(int(entry["clears"]) + 1, StatsService.MAX_VALUE)
	entry["stars"] = maxi(prev_stars, run_stars)
	entry["best_score"] = maxi(prev_best, result.score)
	entry["best_combo"] = maxi(int(entry["best_combo"]), result.max_combo)
	var first_perfect: bool = result.perfect and not bool(entry["perfect"])
	entry["perfect"] = bool(entry["perfect"]) or result.perfect
	var best_time: float = float(entry["best_time"])
	var run_time: float = result.time_seconds
	if is_finite(run_time) and run_time > 0.0 and (best_time <= 0.0 or run_time < best_time):
		entry["best_time"] = run_time
	outcome["first_clear"] = first_clear
	outcome["new_stars"] = int(entry["stars"]) - prev_stars
	outcome["stars"] = int(entry["stars"])
	outcome["new_best"] = not first_clear and result.score > prev_best
	outcome["first_perfect"] = first_perfect


func _announce_unlocks(outcome: Dictionary, next_id: String, next_was_open: bool, worlds: Array[String]) -> void:
	var announced: Array[String] = []
	if not next_was_open and is_level_unlocked(next_id):
		announced.append(next_id)
	for world_id: String in worlds:
		var first_id: String = WorldCatalog.level_id(_world_index(world_id), 1)
		if not announced.has(first_id) and is_level_unlocked(first_id):
			announced.append(first_id)
	if announced.is_empty():
		return
	outcome["unlocked_level"] = announced[0]
	if _bus != null:
		for id: String in announced:
			_bus.level_unlocked.emit(id)


func _sync_world_unlocks(announce: bool) -> Array[String]:
	var unlocked: Array[String] = []
	var stars: int = total_stars()
	for index: int in range(2, _catalog.world_count() + 1):
		var id: String = _world_id(index)
		if id.is_empty() or _profile.unlocked_worlds.has(id):
			continue
		if not is_world_unlocked(_world_id(index - 1)) or not _boss_cleared(index - 1):
			continue
		if stars < _unlock_stars(index):
			continue
		_profile.unlocked_worlds.append(id)
		unlocked.append(id)
		if announce and _bus != null:
			_bus.world_unlocked.emit(id)
	return unlocked


func _update_world_stats() -> void:
	var completed: int = 0
	var perfected: int = 0
	for index: int in range(1, _catalog.world_count() + 1):
		if world_complete(index):
			completed += 1
		if world_perfect(index):
			perfected += 1
	_stats.set_max(StatsService.WORLDS_COMPLETED, completed)
	_stats.set_max(StatsService.WORLDS_PERFECTED, perfected)


## Lowest locked world whose previous boss is beaten and that still lacks
## stars ([param stars] = current total), else 0.
func _star_blocked_world(stars: int) -> int:
	for index: int in range(2, _catalog.world_count() + 1):
		if is_world_unlocked(_world_id(index)):
			continue
		var boss_beaten: bool = is_world_unlocked(_world_id(index - 1)) and _boss_cleared(index - 1)
		if boss_beaten and stars < _unlock_stars(index):
			return index
		return 0
	return 0


func _first_level_below_max_stars() -> String:
	for id: String in _ids:
		if is_level_unlocked(id) and _stars_of(id) < MAX_LEVEL_STARS:
			return id
	return ""


func _boss_cleared(world_index: int) -> bool:
	var count: int = _catalog.levels_in(world_index)
	if count <= 0:
		return false
	var boss: int = _int_of(_catalog.world_at(world_index), "boss_level", count)
	if boss < 1 or boss > count:
		boss = count
	return _is_cleared(WorldCatalog.level_id(world_index, boss))


func _unlock_stars(world_index: int) -> int:
	return maxi(_int_of(_catalog.world_at(world_index), "unlock_stars"), 0)


func _world_id(world_index: int) -> String:
	if world_index < 1 or world_index > _world_ids.size():
		return ""
	return _world_ids[world_index - 1]


func _world_index(world_id: String) -> int:
	if world_id.is_empty():
		return 0
	return _world_ids.find(world_id) + 1


func _world_level_ids(world_index: int) -> PackedStringArray:
	if world_index < 1 or world_index > _world_start.size():
		return PackedStringArray()
	var start: int = _world_start[world_index - 1]
	return _ids.slice(start, start + _catalog.levels_in(world_index))


func _next_id(level_id: String) -> String:
	var n: int = int(_number.get(level_id, 0))
	if n <= 0 or n >= _ids.size():
		return ""
	return _ids[n]


## The stored record of [param level_id], or a shared read-only empty record
## (never mutate the result). Wrongly typed records read as empty.
func _raw_record(level_id: String) -> Dictionary:
	var raw: Variant = _profile.levels.get(level_id)
	if typeof(raw) == TYPE_DICTIONARY:
		return raw as Dictionary
	return EMPTY_RECORD


## Type-safe reads of the profile slice: wrongly typed values count as 0 instead
## of raising script errors.
func _is_cleared(level_id: String) -> bool:
	return _int_of(_raw_record(level_id), "clears") > 0


func _stars_of(level_id: String) -> int:
	return clampi(_int_of(_raw_record(level_id), "stars"), 0, MAX_LEVEL_STARS)


## A complete, well-typed record for [param level_id] (missing keys defaulted).
func _entry(level_id: String) -> Dictionary:
	var r: Dictionary = _raw_record(level_id)
	return {
		"stars": clampi(_int_of(r, "stars"), 0, MAX_LEVEL_STARS),
		"best_score": maxi(_int_of(r, "best_score"), 0),
		"perfect": _bool_of(r, "perfect"),
		"clears": maxi(_int_of(r, "clears"), 0),
		"attempts": maxi(_int_of(r, "attempts"), 0),
		"best_combo": maxi(_int_of(r, "best_combo"), 0),
		"best_time": maxf(_float_of(r, "best_time"), 0.0),
	}


func _hint(hint_type: String, id: String, progress: int, target: int, label_key: String) -> Dictionary:
	return {"type": hint_type, "id": id, "progress": progress, "target": target, "label_key": label_key}


static func _empty_outcome() -> Dictionary:
	var worlds: Array[String] = []
	return {
		"accepted": false,
		"level_id": "",
		"first_clear": false,
		"prev_stars": 0,
		"new_stars": 0,
		"stars": 0,
		"new_best": false,
		"first_perfect": false,
		"unlocked_level": "",
		"unlocked_worlds": worlds,
		"world_completed": "",
		"world_perfected": "",
	}


static func _section(cfg: Dictionary, key: String) -> Dictionary:
	var raw: Variant = cfg.get(key, {})
	if typeof(raw) != TYPE_DICTIONARY:
		GameLog.warn("progression", "config section %s is not an object; using defaults" % key)
		return {}
	return raw as Dictionary


static func _num(section: Dictionary, key: String, fallback: float, min_value: float, max_value: float) -> float:
	if not section.has(key):
		return fallback
	var raw: Variant = section[key]
	if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
		GameLog.warn("progression", "config %s is not a number; using %s" % [key, str(fallback)])
		return fallback
	var v: float = float(raw)
	if is_nan(v) or v < min_value or v > max_value:
		GameLog.warn("progression", "config %s=%s out of range; using %s" % [key, str(v), str(fallback)])
		return fallback
	return v


## Numeric read; non-numbers and non-finite floats give [param fallback].
static func _int_of(d: Dictionary, key: String, fallback: int = 0) -> int:
	var v: Variant = d.get(key, fallback)
	if typeof(v) == TYPE_INT:
		return v as int
	if typeof(v) == TYPE_FLOAT and is_finite(v as float):
		return int(clampf(v as float, -READ_LIMIT, READ_LIMIT))
	return fallback


static func _float_of(d: Dictionary, key: String) -> float:
	var v: Variant = d.get(key, 0.0)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		var f: float = float(v)
		return clampf(f, -READ_LIMIT, READ_LIMIT) if is_finite(f) else 0.0
	return 0.0


## Only real booleans (or non-zero numbers) are true; anything else is false.
static func _bool_of(d: Dictionary, key: String) -> bool:
	var v: Variant = d.get(key, false)
	if typeof(v) == TYPE_BOOL:
		return v as bool
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return float(v) != 0.0
	return false
