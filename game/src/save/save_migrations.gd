class_name SaveMigrations
extends RefCounted
## Upgrades saved payloads from older save versions to the current
## [PlayerProfile] dictionary shape, one version step at a time.
##
## Version history:
## [br]- v0: legacy shape [code]{"coins": int, "stars": {level_id: int}, "best": {level_id: int}}[/code].
## [br]- v1: [method PlayerProfile.to_dict] shape (levels{id: {stars, best_score, clears, ...}}).
## [br]Migrations only reshape data; [method PlayerProfile.from_dict] still
## sanitises every value afterwards, so hostile legacy values are harmless.

const LEGACY_VERSION: int = 0
const CURRENT_VERSION: int = PlayerProfile.SCHEMA_VERSION
## Upper bound for a level's stars (clear + score target + perfect).
const MAX_STARS: int = 3
## Largest magnitude converted from a JSON number (beyond it int() would overflow).
const MAX_SAFE_NUMBER: float = 9.0e15


## True when [param version] can be migrated to (or already is) the current version.
static func is_supported(version: int) -> bool:
	return version >= LEGACY_VERSION and version <= CURRENT_VERSION


## Returns a new dictionary in the current payload shape. The input is never
## modified. Unsupported versions (negative or newer than this build) return
## an empty dictionary so callers can refuse them without losing the original.
static func migrate(payload: Dictionary, from_version: int) -> Dictionary:
	if not is_supported(from_version):
		GameLog.warn(
			"save",
			"cannot migrate save version %d (supported %d..%d)" % [from_version, LEGACY_VERSION, CURRENT_VERSION]
		)
		return {}
	var data: Dictionary = payload.duplicate(true)
	var version: int = from_version
	while version < CURRENT_VERSION:
		data = _step(data, version)
		version += 1
		GameLog.info("save", "migrated save payload to v%d" % version)
	data["schema_version"] = CURRENT_VERSION
	return data


## Applies the single migration step that turns version [param version] into
## version + 1.
static func _step(data: Dictionary, version: int) -> Dictionary:
	match version:
		0:
			return _v0_to_v1(data)
	return data


## v0 kept only coins plus per-level star and best-score maps. A level with
## stars was cleared at least once; three stars imply the perfect star.
static func _v0_to_v1(old: Dictionary) -> Dictionary:
	var stars: Dictionary = _by_level_id(old.get("stars", {}))
	var best: Dictionary = _by_level_id(old.get("best", {}))
	var ids: Array[String] = []
	for id: String in stars:
		ids.append(id)
	for id: String in best:
		if not stars.has(id):
			ids.append(id)
	ids.sort()
	var levels: Dictionary = {}
	for id: String in ids:
		var level_stars: int = clampi(int(stars.get(id, 0)), 0, MAX_STARS)
		var best_score: int = maxi(0, int(best.get(id, 0)))
		var clears: int = 1 if level_stars > 0 else 0
		var attempts: int = 1 if clears > 0 or best_score > 0 else 0
		levels[id] = {
			"stars": level_stars,
			"best_score": best_score,
			"perfect": level_stars >= MAX_STARS,
			"clears": clears,
			"attempts": attempts,
			"best_combo": 0,
			"best_time": 0.0,
		}
	return {
		"schema_version": LEGACY_VERSION + 1,
		"coins": maxi(0, _int(old.get("coins", 0))),
		"levels": levels,
	}


## Legacy {level_id: number} map as trimmed level id -> int. Empty ids are
## dropped; ids that collide after trimming keep the highest value. Linear in
## the map size, so a huge or hostile legacy file cannot stall loading.
static func _by_level_id(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(value) != TYPE_DICTIONARY:
		return out
	var source: Dictionary = value as Dictionary
	for key: Variant in source:
		var id: String = str(key).strip_edges()
		if id.is_empty():
			continue
		var number: int = _int(source[key])
		out[id] = maxi(number, int(out[id])) if out.has(id) else number
	return out


static func _int(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return value as int
	if typeof(value) == TYPE_FLOAT and is_finite(value as float):
		return int(clampf(value as float, -MAX_SAFE_NUMBER, MAX_SAFE_NUMBER))
	return 0
