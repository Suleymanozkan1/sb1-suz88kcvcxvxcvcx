class_name AdsPolicy
extends RefCounted
## Sanitised ad rules from data/config/ads_policy.json plus remote overrides.
##
## Data can make the policy stricter but never looser than the hard rules:
## interstitials only at natural breakpoints (level_end / world_end), rewarded
## ads only for the known optional placements, at most one revive per run,
## and a minimum spacing between interstitials. "No interstitials after any
## purchase" is not configurable at all (see [AdsService]).

const DEFAULT_PATH: String = "res://data/config/ads_policy.json"
const NATURAL_BREAKPOINTS: PackedStringArray = ["level_end", "world_end"]
const REWARDED_PLACEMENTS: PackedStringArray = ["revive", "double_reward", "bonus_chest"]
const DEFAULT_MIN_LEVELS_CLEARED: int = 6
const DEFAULT_EVERY_N_LEVELS: int = 3
## Interstitials can never be more frequent than every second completed level.
const MIN_EVERY_N_LEVELS: int = 2
const DEFAULT_COOLDOWN_SECONDS: int = 180
## Floor for the interstitial cooldown regardless of data.
const MIN_COOLDOWN_SECONDS: int = 60
const MAX_REVIVES_PER_RUN: int = 1
const DEFAULT_TUTORIAL_FLAG: String = "tutorial_done"
const DEFAULT_TUTORIAL_ASSUME_DONE: int = 8
const REMOTE_ENABLED: String = "ads.enabled"
const REMOTE_EVERY_N: String = "ads.interstitial_every_n_levels"
const REMOTE_MIN_LEVEL: String = "ads.interstitial_min_level"

var enabled: bool = true
var interstitial_enabled: bool = true
var interstitial_placements: PackedStringArray = NATURAL_BREAKPOINTS.duplicate()
var min_levels_cleared: int = DEFAULT_MIN_LEVELS_CLEARED
var every_n_levels: int = DEFAULT_EVERY_N_LEVELS
var cooldown_seconds: int = DEFAULT_COOLDOWN_SECONDS
var rewarded_enabled: bool = true
var rewarded_placements: PackedStringArray = REWARDED_PLACEMENTS.duplicate()
var revives_per_run: int = MAX_REVIVES_PER_RUN
## profile.flags key set by the tutorial flow once onboarding is finished.
var tutorial_flag: String = DEFAULT_TUTORIAL_FLAG
## Fallback: after this many cleared levels the tutorial counts as done even
## if the flag was never written (keeps a missing flag from hiding a bug).
var tutorial_assume_done_after: int = DEFAULT_TUTORIAL_ASSUME_DONE


## Reads the bundled policy (safe defaults when missing).
static func load_default(path: String = DEFAULT_PATH) -> Dictionary:
	return JsonIO.read_dict(path)


## Builds a sanitised policy from parsed JSON (missing parts use defaults).
static func from_dict(data: Dictionary) -> AdsPolicy:
	var p: AdsPolicy = AdsPolicy.new()
	p.enabled = AdsPolicy._bool(data, "enabled", true)
	var inter: Dictionary = AdsPolicy._section(data, "interstitial")
	p.interstitial_enabled = AdsPolicy._bool(inter, "enabled", true)
	p.interstitial_placements = AdsPolicy._subset(inter.get("placements"), NATURAL_BREAKPOINTS)
	p.min_levels_cleared = maxi(0, AdsPolicy._int(inter, "min_levels_cleared", DEFAULT_MIN_LEVELS_CLEARED))
	p.every_n_levels = maxi(MIN_EVERY_N_LEVELS, AdsPolicy._int(inter, "every_n_levels", DEFAULT_EVERY_N_LEVELS))
	p.cooldown_seconds = maxi(MIN_COOLDOWN_SECONDS, AdsPolicy._int(inter, "cooldown_seconds", DEFAULT_COOLDOWN_SECONDS))
	var rewarded: Dictionary = AdsPolicy._section(data, "rewarded")
	p.rewarded_enabled = AdsPolicy._bool(rewarded, "enabled", true)
	p.rewarded_placements = AdsPolicy._subset(rewarded.get("placements"), REWARDED_PLACEMENTS)
	p.revives_per_run = clampi(AdsPolicy._int(rewarded, "revives_per_run", MAX_REVIVES_PER_RUN), 0, MAX_REVIVES_PER_RUN)
	var tutorial: Dictionary = AdsPolicy._section(data, "tutorial")
	var flag: String = str(tutorial.get("done_flag", DEFAULT_TUTORIAL_FLAG)).strip_edges()
	p.tutorial_flag = flag if not flag.is_empty() else DEFAULT_TUTORIAL_FLAG
	p.tutorial_assume_done_after = maxi(
		1, AdsPolicy._int(tutorial, "assume_done_after_levels", DEFAULT_TUTORIAL_ASSUME_DONE)
	)
	return p


## Returns [param data] with explicit remote overrides applied. Remote config
## can switch ads off but not on when the bundled policy disables them, and
## values it supplies are already range-checked by [RemoteConfig].
static func merge_remote(data: Dictionary, remote: RemoteConfig) -> Dictionary:
	var out: Dictionary = data.duplicate(true)
	if remote == null:
		return out
	var inter: Dictionary = AdsPolicy._section(out, "interstitial")
	if remote.has_override(REMOTE_ENABLED):
		out["enabled"] = AdsPolicy._bool(out, "enabled", true) and remote.get_bool(REMOTE_ENABLED, true)
	if remote.has_override(REMOTE_EVERY_N):
		inter["every_n_levels"] = remote.get_int(REMOTE_EVERY_N, DEFAULT_EVERY_N_LEVELS)
	if remote.has_override(REMOTE_MIN_LEVEL):
		inter["min_levels_cleared"] = remote.get_int(REMOTE_MIN_LEVEL, DEFAULT_MIN_LEVELS_CLEARED)
	out["interstitial"] = inter
	return out


## Plain dictionary form (same shape as ads_policy.json).
func to_dict() -> Dictionary:
	return {
		"enabled": enabled,
		"interstitial":
		{
			"enabled": interstitial_enabled,
			"placements": Array(interstitial_placements),
			"min_levels_cleared": min_levels_cleared,
			"every_n_levels": every_n_levels,
			"cooldown_seconds": cooldown_seconds,
		},
		"rewarded":
		{
			"enabled": rewarded_enabled,
			"placements": Array(rewarded_placements),
			"revives_per_run": revives_per_run,
		},
		"tutorial": {"done_flag": tutorial_flag, "assume_done_after_levels": tutorial_assume_done_after},
	}


static func _section(data: Dictionary, key: String) -> Dictionary:
	var v: Variant = data.get(key, {})
	return (v as Dictionary).duplicate(true) if typeof(v) == TYPE_DICTIONARY else {}


static func _bool(data: Dictionary, key: String, fallback: bool) -> bool:
	var v: Variant = data.get(key, fallback)
	return bool(v) if typeof(v) == TYPE_BOOL else fallback


static func _int(data: Dictionary, key: String, fallback: int) -> int:
	var v: Variant = data.get(key, fallback)
	return int(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else fallback


## Intersection of the data list with [param allowed]; the full allowed list
## when the data is missing or malformed.
static func _subset(raw: Variant, allowed: PackedStringArray) -> PackedStringArray:
	if typeof(raw) != TYPE_ARRAY:
		return allowed.duplicate()
	var out: PackedStringArray = PackedStringArray()
	for item: Variant in raw as Array:
		var s: String = str(item)
		if allowed.has(s) and not out.has(s):
			out.append(s)
		elif not allowed.has(s):
			GameLog.warn("ads", "placement '%s' is not allowed by policy and is ignored" % s)
	return out
