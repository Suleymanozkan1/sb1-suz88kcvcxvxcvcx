class_name ModeCatalog
extends RefCounted
## Data-driven game modes (data/modes/modes.json). A mode is a set of rules on
## top of the one deterministic simulation: sim modifiers, where the course
## comes from (campaign, daily, endless stream, boss rush), how it unlocks,
## which leaderboard it feeds and how it rewards. Modes never change the
## simulation code path, so every mode is replay-verifiable.

const DATA_PATH: String = "res://data/modes/modes.json"
const MODIFIER_KEYS: PackedStringArray = ["zen", "speed_scale", "shields_allowed", "strict", "time_limit"]
const SOURCES: PackedStringArray = ["campaign", "campaign_pick", "daily", "endless", "boss_rush"]
const UNLOCK_TYPES: PackedStringArray = [
	"none", "levels_cleared", "perfects", "bosses_cleared", "world_cleared", "stars"
]
const ENDLESS_SEED_SALT: String = "fluxdrop-endless-v1:"

static var _shared: ModeCatalog

var modes: Array[Dictionary] = []
var score_rewards: Dictionary = {}
## Mode id -> its mode document (the same dictionaries as in [member modes]).
var _by_id: Dictionary[String, Dictionary] = {}


## Process-wide read-only instance (client and server read the same rules).
static func shared() -> ModeCatalog:
	if _shared == null:
		_shared = load_default()
	return _shared


static func load_default() -> ModeCatalog:
	var c: ModeCatalog = ModeCatalog.new()
	c.load_from(JsonIO.read_dict(DATA_PATH))
	return c


func load_from(data: Dictionary) -> void:
	modes.clear()
	_by_id.clear()
	for raw: Variant in data.get("modes", []) as Array:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = raw as Dictionary
		var id: String = str(m.get("id", ""))
		if id.is_empty() or _by_id.has(id):
			GameLog.warn("modes", "skipping invalid or duplicate mode '%s'" % id)
			continue
		modes.append(m)
		_by_id[id] = m
	score_rewards = data.get("score_rewards", {}) as Dictionary


func ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for m: Dictionary in modes:
		out.append(str(m["id"]))
	return out


func has(mode_id: StringName) -> bool:
	return _by_id.has(String(mode_id))


func mode(mode_id: StringName) -> Dictionary:
	return _by_id.get(String(mode_id), {}) as Dictionary


func source(mode_id: StringName) -> String:
	return str(mode(mode_id).get("source", "campaign"))


## Session modifiers for [method GameplaySession.load_level] (always carries "mode").
func sim_modifiers(mode_id: StringName) -> Dictionary:
	var out: Dictionary = {"mode": String(mode_id)}
	var mods: Dictionary = mode(mode_id).get("modifiers", {}) as Dictionary
	for key: String in MODIFIER_KEYS:
		if mods.has(key):
			out[key] = mods[key]
	return out


## Sim modifiers in the verifier's rule vocabulary ("shields" instead of
## "shields_allowed"); merged over the ranking rules by [LeaderboardService].
func verifier_modifiers(mode_id: StringName) -> Dictionary:
	if not has(mode_id):
		return {}
	var mods: Dictionary = sim_modifiers(mode_id)
	return {
		"zen": bool(mods.get("zen", false)),
		"speed_scale": float(mods.get("speed_scale", 1.0)),
		"shields": bool(mods.get("shields_allowed", true)),
		"strict": bool(mods.get("strict", false)),
		"time_limit": float(mods.get("time_limit", 0.0)),
	}


## progress: {"levels_cleared", "perfects", "bosses_cleared", "worlds_cleared", "stars"}.
func is_unlocked(mode_id: StringName, progress: Dictionary) -> bool:
	var unlock: Dictionary = mode(mode_id).get("unlock", {}) as Dictionary
	var value: int = int(unlock.get("value", 0))
	match str(unlock.get("type", "none")):
		"levels_cleared":
			return int(progress.get("levels_cleared", 0)) >= value
		"perfects":
			return int(progress.get("perfects", 0)) >= value
		"bosses_cleared":
			return int(progress.get("bosses_cleared", 0)) >= value
		"world_cleared":
			return int(progress.get("worlds_cleared", 0)) >= value
		"stars":
			return int(progress.get("stars", 0)) >= value
	return true


## Translation key + format args describing the honest unlock requirement.
func requirement(mode_id: StringName) -> Dictionary:
	var unlock: Dictionary = mode(mode_id).get("unlock", {}) as Dictionary
	var type: String = str(unlock.get("type", "none"))
	return {"key": "mode.unlock." + type, "args": {"n": int(unlock.get("value", 0))}}


## Leaderboards are disabled for zen and modes without a board.
func has_board(mode_id: StringName) -> bool:
	return str(mode(mode_id).get("board", "none")) != "none"


## Deterministic per-week seed so everyone races the same endless course and
## the server can regenerate it for replay verification.
static func endless_seed(mode_id: StringName, week_key: String) -> int:
	return DetRng.hash_string(ENDLESS_SEED_SALT + String(mode_id) + ":" + week_key)


## Level id of a streamed course: "<mode>_<seed>" (see [method parse_stream_id]).
static func stream_id(mode_id: StringName, stream_seed: int) -> String:
	return "%s_%d" % [String(mode_id), stream_seed]


## {"mode": StringName, "seed": int} for a streamed course id, {} otherwise.
func parse_stream_id(level_id: String) -> Dictionary:
	var cut: int = level_id.rfind("_")
	if cut <= 0:
		return {}
	var mode_id: StringName = StringName(level_id.substr(0, cut))
	var seed_text: String = level_id.substr(cut + 1)
	if not has(mode_id) or source(mode_id) != "endless" or not seed_text.is_valid_int():
		return {}
	return {"mode": mode_id, "seed": seed_text.to_int()}


## The world a streamed course is themed in (derived from the seed only).
static func stream_world_index(stream_seed: int, world_count: int) -> int:
	return 1 + absi(stream_seed) % maxi(1, world_count)


## A ready streamer for [param mode_id] / [param stream_seed]; the client and
## the replay verifier both build courses through this one function.
func make_streamer(
	mode_id: StringName, stream_seed: int, catalog: WorldCatalog, model: DifficultyModel
) -> EndlessStreamer:
	var world: Dictionary = catalog.world_at(ModeCatalog.stream_world_index(stream_seed, catalog.world_count()))
	return EndlessStreamer.new(stream_spec(mode_id, stream_seed, world, model))


## LevelSpec for an endless stream (endless, time attack, zen).
func stream_spec(mode_id: StringName, stream_seed: int, world: Dictionary, model: DifficultyModel) -> LevelSpec:
	var cfg: Dictionary = mode(mode_id).get("stream", {}) as Dictionary
	var base_number: int = clampi(int(cfg.get("difficulty_number", 120)), 1, 520)
	var spec: LevelSpec = model.build_spec(base_number)
	spec.id = ModeCatalog.stream_id(mode_id, stream_seed)
	spec.kind = "endless"
	spec.seed = stream_seed
	spec.endless = true
	spec.tutorial = false
	spec.forgiving = false
	spec.lanes = clampi(int(cfg.get("lanes", spec.lanes)), 2, 3)
	spec.speed = float(cfg.get("speed", spec.speed))
	spec.speed_ramp = float(cfg.get("speed_ramp", spec.speed_ramp))
	spec.ramp_distance = float(cfg.get("ramp_distance", 0.0))
	spec.spacing = spec.spacing * float(cfg.get("spacing_scale", 1.0))
	# Pinned per mode, so retuning the campaign curve never silently changes how
	# busy a ranked or calm stream is.
	spec.change_prob = float(cfg.get("change_prob", spec.change_prob))
	spec.density = float(cfg.get("density", spec.density))
	if not world.is_empty():
		spec.world_id = str(world.get("id", spec.world_id))
		spec.world_index = int(world.get("index", spec.world_index))
	return spec


## Coins and XP for score-based modes: proportional and capped (no spikes).
func score_reward(mode_id: StringName, score: int) -> Dictionary:
	if str(mode(mode_id).get("rewards", "none")) != "score_based":
		return {}
	var k: float = float(maxi(0, score)) / 1000.0
	var coins: int = mini(
		int(score_rewards.get("max_coins", 0)), int(floor(k * float(score_rewards.get("coins_per_1000_score", 0))))
	)
	var xp: int = mini(
		int(score_rewards.get("max_xp", 0)), int(floor(k * float(score_rewards.get("xp_per_1000_score", 0))))
	)
	var out: Dictionary = {}
	if coins > 0:
		out["coins"] = coins
	if xp > 0:
		out["xp"] = xp
	return out


## Data problems (used by tests and the validation tool).
func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	for m: Dictionary in modes:
		var id: String = str(m["id"])
		if not SOURCES.has(str(m.get("source", ""))):
			errors.append("%s: unknown source" % id)
		var unlock: Dictionary = m.get("unlock", {}) as Dictionary
		if not UNLOCK_TYPES.has(str(unlock.get("type", ""))):
			errors.append("%s: unknown unlock type" % id)
		for key: Variant in (m.get("modifiers", {}) as Dictionary).keys():
			if not MODIFIER_KEYS.has(str(key)):
				errors.append("%s: unknown modifier %s" % [id, str(key)])
		if str(m.get("source", "")) == "endless" and not m.has("stream"):
			errors.append("%s: endless source needs a stream block" % id)
	return errors
