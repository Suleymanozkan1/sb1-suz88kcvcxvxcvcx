class_name PlayerProfile
extends RefCounted
## The complete persisted player state (single source of truth for saves).
##
## Systems own the *logic* for their slice (economy, progression, cosmetics…)
## but the data lives here so saving/loading/migrating is one place. Every
## field is sanitised in [method from_dict]: corrupted or hostile values are
## clamped to safe defaults instead of propagating.

const SCHEMA_VERSION: int = 1
const LEDGER_LIMIT: int = 50
## Upper bound of [member bonus_stars]. Rewards pay a handful of stars in
## total; the cap only bounds a damaged or edited save.
const MAX_BONUS_STARS: int = 999
## Flags other systems read with a fixed type (mode bests are a dictionary of
## whole numbers; the cloud.* flags are [CloudSaveService] bookkeeping).
const TYPED_FLAGS: Dictionary[String, Variant.Type] = {
	"mode_best": TYPE_DICTIONARY,
	"economy_starting_granted": TYPE_BOOL,
	"tutorial_done": TYPE_BOOL,
	"last_level": TYPE_STRING,
	"notifications.daily_day": TYPE_INT,
	"bonus_chest_day": TYPE_INT,
	"cloud.dirty": TYPE_BOOL,
	"cloud.revision": TYPE_STRING,
	"cloud.synced_at": TYPE_INT,
}

const DEFAULT_SETTINGS: Dictionary = {
	"sound": true,
	"music": true,
	"sfx_volume": 1.0,
	"music_volume": 0.8,
	"haptics": true,
	"notifications": false,
	"quality": "auto",
	"battery_saver": false,
	"language": "auto",
	"analytics": false,
	"reduce_motion": false,
	"colorblind": false,
}

## Opaque random install id (not derived from device identifiers, not PII).
var install_id: String = ""
var created_at: int = 0
var coins: int = 0
var gems: int = 0
var xp: int = 0
var player_level: int = 1
## Stars granted by rewards (achievements, events) on top of the campaign
## stars of [member levels]. They count toward star unlocks (worlds, modes,
## cosmetics: see [method ProgressionService.total_stars]) but never toward a
## level's 3 stars or the campaign "x / max" totals.
var bonus_stars: int = 0
## level_id -> {"stars", "best_score", "perfect", "clears", "attempts", "best_combo", "best_time"}
var levels: Dictionary = {}
var unlocked_worlds: Array[String] = ["neon_core"]
## stat name -> int lifetime counters (see StatsService).
var stats: Dictionary = {}
var cosmetics_owned: Array[String] = []
## category -> item id
var cosmetics_equipped: Dictionary = {}
## achievement id -> unix time unlocked
var achievements: Dictionary = {}
## {"daily": {...}, "weekly": {...}} — owned by MissionService.
var missions: Dictionary = {}
## Daily challenge state — owned by DailyChallengeService.
var daily: Dictionary = {}
var settings: Dictionary = DEFAULT_SETTINGS.duplicate()
## Non-consumable store product ids (restorable).
var purchases: Array[String] = []
## Pending online submissions (leaderboard / analytics), flushed when online.
var pending_submissions: Array[Dictionary] = []
## Misc one-off flags (tutorial seen, rated, ...).
var flags: Dictionary = {}
## Recent currency transactions (audit trail for integrity checks).
var ledger: Array[Dictionary] = []


static func create_new(now_unix: int) -> PlayerProfile:
	var p: PlayerProfile = PlayerProfile.new()
	p.install_id = _random_id()
	p.created_at = now_unix
	return p


static func _random_id() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	return bytes.hex_encode()


func level_result(level_id: String) -> Dictionary:
	return levels.get(level_id, {}) as Dictionary


func stars_for(level_id: String) -> int:
	return _int(level_result(level_id), "stars", 0)


func is_cleared(level_id: String) -> bool:
	return _int(level_result(level_id), "clears", 0) > 0


## Campaign stars only: the sum of the stored level records (0..3 each).
## [member bonus_stars] are not included; the unlock total that adds them (and
## ignores records of unknown levels) is [method ProgressionService.total_stars].
func total_stars() -> int:
	var total: int = 0
	for id: Variant in levels:
		var r: Variant = levels[id]
		if typeof(r) == TYPE_DICTIONARY:
			total += _int(r as Dictionary, "stars", 0)
	return total


func stat(name: String) -> int:
	return _int(stats, name, 0)


func setting(key: String) -> Variant:
	return settings.get(key, DEFAULT_SETTINGS.get(key))


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"install_id": install_id,
		"created_at": created_at,
		"coins": coins,
		"gems": gems,
		"xp": xp,
		"player_level": player_level,
		"bonus_stars": bonus_stars,
		"levels": levels.duplicate(true),
		"unlocked_worlds": Array(unlocked_worlds),
		"stats": stats.duplicate(),
		"cosmetics_owned": Array(cosmetics_owned),
		"cosmetics_equipped": cosmetics_equipped.duplicate(),
		"achievements": achievements.duplicate(),
		"missions": missions.duplicate(true),
		"daily": daily.duplicate(true),
		"settings": settings.duplicate(),
		"purchases": Array(purchases),
		"pending_submissions": pending_submissions.duplicate(true),
		"flags": flags.duplicate(),
		"ledger": ledger.duplicate(true),
	}


## Builds a profile from (possibly corrupted) data. Never fails: invalid parts
## fall back to defaults. [member issues] lists anything that was repaired.
static func from_dict(data: Dictionary) -> PlayerProfile:
	var p: PlayerProfile = PlayerProfile.new()
	p.install_id = str(data.get("install_id", ""))
	if p.install_id.length() != 32 or not p.install_id.is_valid_hex_number():
		p.install_id = _random_id()
	p.created_at = maxi(0, _int(data, "created_at", 0))
	p.coins = maxi(0, _int(data, "coins", 0))
	p.gems = maxi(0, _int(data, "gems", 0))
	p.xp = maxi(0, _int(data, "xp", 0))
	p.player_level = maxi(1, _int(data, "player_level", 1))
	p.bonus_stars = clampi(_int(data, "bonus_stars", 0), 0, MAX_BONUS_STARS)
	p.levels = _sanitize_levels(data.get("levels", {}))
	p.unlocked_worlds = _string_array(data.get("unlocked_worlds", ["neon_core"]))
	if not p.unlocked_worlds.has("neon_core"):
		p.unlocked_worlds.insert(0, "neon_core")
	p.stats = _int_dict(data.get("stats", {}))
	p.cosmetics_owned = _string_array(data.get("cosmetics_owned", []))
	p.cosmetics_equipped = _string_dict(data.get("cosmetics_equipped", {}))
	p.achievements = _int_dict(data.get("achievements", {}))
	p.missions = _dict(data.get("missions", {}))
	p.daily = _dict(data.get("daily", {}))
	p.settings = DEFAULT_SETTINGS.duplicate()
	var s: Dictionary = _dict(data.get("settings", {}))
	for key: String in DEFAULT_SETTINGS:
		if s.has(key) and typeof(s[key]) == typeof(DEFAULT_SETTINGS[key]):
			p.settings[key] = s[key]
		elif s.has(key) and typeof(DEFAULT_SETTINGS[key]) == TYPE_FLOAT and typeof(s[key]) == TYPE_INT:
			p.settings[key] = float(s[key])
	p.purchases = _string_array(data.get("purchases", []))
	for raw: Variant in _array(data.get("pending_submissions", [])):
		if typeof(raw) == TYPE_DICTIONARY:
			p.pending_submissions.append(raw as Dictionary)
	p.flags = PlayerProfile._sanitize_flags(_dict(data.get("flags", {})))
	for raw2: Variant in _array(data.get("ledger", [])):
		if typeof(raw2) == TYPE_DICTIONARY:
			p.ledger.append(raw2 as Dictionary)
	while p.ledger.size() > LEDGER_LIMIT:
		p.ledger.remove_at(0)
	return p


## Replaces every persisted field of this profile with a copy of
## [param other]'s, keeping this object (every service holds a reference to
## it) and the identity of its top-level containers. Used when a cloud merge
## is applied; [param other] should come from [method from_dict].
func copy_from(other: PlayerProfile) -> void:
	if other == null:
		return
	install_id = other.install_id
	created_at = other.created_at
	coins = other.coins
	gems = other.gems
	xp = other.xp
	player_level = other.player_level
	bonus_stars = other.bonus_stars
	PlayerProfile._replace_dict(levels, other.levels)
	unlocked_worlds.assign(other.unlocked_worlds)
	PlayerProfile._replace_dict(stats, other.stats)
	cosmetics_owned.assign(other.cosmetics_owned)
	PlayerProfile._replace_dict(cosmetics_equipped, other.cosmetics_equipped)
	PlayerProfile._replace_dict(achievements, other.achievements)
	PlayerProfile._replace_dict(missions, other.missions)
	PlayerProfile._replace_dict(daily, other.daily)
	PlayerProfile._replace_dict(settings, other.settings)
	purchases.assign(other.purchases)
	pending_submissions.assign(other.pending_submissions.duplicate(true))
	PlayerProfile._replace_dict(flags, other.flags)
	ledger.assign(other.ledger.duplicate(true))


static func _replace_dict(target: Dictionary, source: Dictionary) -> void:
	target.clear()
	target.merge(source.duplicate(true))


static func _int(d: Dictionary, key: String, fallback: int) -> int:
	var v: Variant = d.get(key, fallback)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return int(v)
	return fallback


## Hostile or corrupted saves can hold any JSON type: only real booleans (or
## numbers) count as true, everything else falls back to false.
static func _bool(d: Dictionary, key: String) -> bool:
	var v: Variant = d.get(key, false)
	match typeof(v):
		TYPE_BOOL:
			return v as bool
		TYPE_INT, TYPE_FLOAT:
			return float(v) != 0.0
	return false


static func _float(d: Dictionary, key: String) -> float:
	var v: Variant = d.get(key, 0.0)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		var f: float = float(v)
		return f if is_finite(f) else 0.0
	return 0.0


static func _array(v: Variant) -> Array:
	return v as Array if typeof(v) == TYPE_ARRAY else []


static func _dict(v: Variant) -> Dictionary:
	return (v as Dictionary).duplicate(true) if typeof(v) == TYPE_DICTIONARY else {}


static func _string_array(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(v) == TYPE_ARRAY:
		for item: Variant in v as Array:
			var s: String = str(item)
			if not s.is_empty() and not out.has(s):
				out.append(s)
	return out


static func _string_dict(v: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(v) == TYPE_DICTIONARY:
		for k: Variant in v as Dictionary:
			out[str(k)] = str((v as Dictionary)[k])
	return out


static func _int_dict(v: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(v) == TYPE_DICTIONARY:
		for k: Variant in v as Dictionary:
			var val: Variant = (v as Dictionary)[k]
			if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
				out[str(k)] = maxi(0, int(val))
	return out


static func _sanitize_levels(v: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(v) != TYPE_DICTIONARY:
		return out
	for k: Variant in v as Dictionary:
		var raw: Variant = (v as Dictionary)[k]
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = raw as Dictionary
		out[str(k)] = {
			"stars": clampi(_int(r, "stars", 0), 0, 3),
			"best_score": maxi(0, _int(r, "best_score", 0)),
			"perfect": _bool(r, "perfect"),
			"clears": maxi(0, _int(r, "clears", 0)),
			"attempts": maxi(0, _int(r, "attempts", 0)),
			"best_combo": maxi(0, _int(r, "best_combo", 0)),
			"best_time": maxf(0.0, _float(r, "best_time")),
		}
	return out


## Known flags with the wrong type (a damaged or edited save) are dropped, so
## readers never meet e.g. a list where a dictionary of bests belongs.
## Unknown flags are kept as they are.
static func _sanitize_flags(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in raw:
		var key: String = str(k)
		var v: Variant = raw[k]
		if not TYPED_FLAGS.has(key):
			out[key] = v
			continue
		match TYPED_FLAGS[key]:
			TYPE_BOOL:
				if typeof(v) == TYPE_BOOL:
					out[key] = v
			TYPE_STRING:
				if typeof(v) == TYPE_STRING:
					out[key] = v
			TYPE_INT:
				if typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and is_finite(float(v))):
					out[key] = int(v)
			TYPE_DICTIONARY:
				if typeof(v) == TYPE_DICTIONARY:
					var numbers: Dictionary = {}
					for sub: Variant in v as Dictionary:
						var n: Variant = (v as Dictionary)[sub]
						if typeof(n) == TYPE_INT or (typeof(n) == TYPE_FLOAT and is_finite(float(n))):
							numbers[str(sub)] = maxi(0, int(n))
					out[key] = numbers
	return out
