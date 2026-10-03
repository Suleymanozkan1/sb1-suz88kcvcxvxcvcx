class_name AdsService
extends RefCounted
## Player-respecting ad pacing.
##
## Interstitials appear only at natural breakpoints ("level_end",
## "world_end"), never before the player has cleared
## [member AdsPolicy.min_levels_cleared] levels, at most once every
## [member AdsPolicy.every_n_levels] completed levels, never during the
## tutorial, never within the cooldown, and never again once the player has
## bought any pack. Rewarded ads are always optional: the caller offers them,
## and grants the reward only when [method show_rewarded] returns
## granted=true. A revive can be earned at most once per run.

const KIND_INTERSTITIAL: StringName = &"interstitial"
const KIND_REWARDED: StringName = &"rewarded"
const PLACEMENT_REVIVE: String = "revive"
const REASON_DISABLED: String = "disabled"
const REASON_NOT_BREAKPOINT: String = "not_breakpoint"
const REASON_MIN_LEVEL: String = "min_level"
const REASON_FREQUENCY: String = "frequency"
const REASON_COOLDOWN: String = "cooldown"
const REASON_PURCHASED: String = "purchased"
const REASON_TUTORIAL: String = "tutorial"
const REASON_UNAVAILABLE: String = "unavailable"
const REASON_BUSY: String = "busy"
const REASON_UNKNOWN_PLACEMENT: String = "unknown_placement"
const REASON_REVIVE_USED: String = "revive_used"
const REASON_NOT_COMPLETED: String = "not_completed"
const EVENT_AD_STARTED: StringName = &"ad_started"
const EVENT_AD_COMPLETED: StringName = &"ad_completed"

var policy: AdsPolicy = null
## Set by the flow while a tutorial overlay is on screen (e.g. replayed from
## settings) so no interstitial interrupts it.
var tutorial_active: bool = false
var _profile: PlayerProfile = null
var _bus: EventBus = null
var _provider: AdProvider = null
var _track: Callable = Callable()
var _clock: GameClock = null
var _levels_since_interstitial: int = 0
var _last_interstitial_unix: int = -1
var _revives_this_run: int = 0
## True between a granted revive and the run_started its resume re-emits.
var _resuming_after_revive: bool = false
## Level of the current run (from run_started), so a revive that was never
## resumed cannot make the next level's run count as the same run.
var _run_level_id: String = ""
var _showing: bool = false


## [param policy_data] is ads_policy.json, optionally merged with remote
## overrides via [method AdsPolicy.merge_remote]. [param analytics_track] is
## (event: StringName, params: Dictionary) -> bool. [param clock] drives the
## cooldown (system time when null).
func _init(
	profile: PlayerProfile,
	bus: EventBus,
	provider: AdProvider,
	policy_data: Dictionary,
	analytics_track: Callable = Callable(),
	clock: GameClock = null
) -> void:
	_profile = profile if profile != null else PlayerProfile.new()
	_bus = bus
	_provider = provider if provider != null else NullAdProvider.new()
	_track = analytics_track
	_clock = clock if clock != null else GameClock.new()
	policy = AdsPolicy.from_dict(policy_data)
	if _bus != null:
		_bus.run_completed.connect(_on_run_completed)
		_bus.run_failed.connect(_on_run_failed)
		_bus.run_started.connect(_on_run_started)
		_bus.run_restarted.connect(_on_run_restarted)


## Replaces the policy (e.g. after a remote config fetch).
func set_policy(policy_data: Dictionary) -> void:
	policy = AdsPolicy.from_dict(policy_data)


## Starts a new run: the per-run revive allowance is reset.
func begin_run() -> void:
	_revives_this_run = 0
	_resuming_after_revive = false


## Completed levels since the last interstitial (this session).
func levels_since_interstitial() -> int:
	return _levels_since_interstitial


## Distinct levels the player has cleared.
func levels_cleared() -> int:
	var count: int = 0
	for level_id: String in _profile.levels:
		if _profile.is_cleared(level_id):
			count += 1
	return count


## True while onboarding is not finished (flag missing and too few clears) or
## while [member tutorial_active] is set.
func is_in_tutorial() -> bool:
	if tutorial_active:
		return true
	var flag: Variant = _profile.flags.get(policy.tutorial_flag, false)
	var done: bool = (typeof(flag) == TYPE_BOOL and bool(flag)) or (typeof(flag) == TYPE_INT and int(flag) != 0)
	if done:
		return false
	return levels_cleared() < policy.tutorial_assume_done_after


## Why an interstitial may not be shown at [param placement] now ("" = allowed).
func interstitial_block_reason(placement: StringName) -> String:
	var reason: String = ""
	if not policy.enabled or not policy.interstitial_enabled:
		reason = REASON_DISABLED
	elif not policy.interstitial_placements.has(String(placement)):
		reason = REASON_NOT_BREAKPOINT
	elif not _profile.purchases.is_empty():
		reason = REASON_PURCHASED
	elif is_in_tutorial():
		reason = REASON_TUTORIAL
	elif levels_cleared() < policy.min_levels_cleared:
		reason = REASON_MIN_LEVEL
	elif _levels_since_interstitial < policy.every_n_levels:
		reason = REASON_FREQUENCY
	elif _last_interstitial_unix >= 0 and _clock.now_unix() - _last_interstitial_unix < policy.cooldown_seconds:
		reason = REASON_COOLDOWN
	elif _showing:
		reason = REASON_BUSY
	elif not _provider.is_available(KIND_INTERSTITIAL):
		reason = REASON_UNAVAILABLE
	return reason


## True when every interstitial rule allows one at [param placement] now.
func can_show_interstitial(placement: StringName) -> bool:
	return interstitial_block_reason(placement).is_empty()


## Shows an interstitial if the policy allows it. Returns
## {"shown": bool, "reason": String}. Coroutine: always await it.
func show_interstitial(placement: StringName) -> Dictionary:
	var reason: String = interstitial_block_reason(placement)
	if not reason.is_empty():
		return {"shown": false, "reason": reason}
	_showing = true
	_track_event(EVENT_AD_STARTED, {"kind": String(KIND_INTERSTITIAL), "placement": String(placement)})
	var result: Dictionary = AdsService._normalize(await _provider.show(KIND_INTERSTITIAL, placement))
	_showing = false
	var shown: bool = bool(result["shown"])
	if shown:
		_levels_since_interstitial = 0
		_last_interstitial_unix = _clock.now_unix()
	_track_event(
		EVENT_AD_COMPLETED,
		{"kind": String(KIND_INTERSTITIAL), "placement": String(placement), "completed": shown},
	)
	if _bus != null:
		_bus.ad_finished.emit(placement, false)
	return {"shown": shown, "reason": "" if shown else REASON_UNAVAILABLE}


## Why a rewarded ad cannot be offered at [param placement] ("" = available).
func rewarded_block_reason(placement: StringName) -> String:
	var reason: String = ""
	if not AdsPolicy.REWARDED_PLACEMENTS.has(String(placement)):
		reason = REASON_UNKNOWN_PLACEMENT
	elif not policy.enabled or not policy.rewarded_enabled or not policy.rewarded_placements.has(String(placement)):
		reason = REASON_DISABLED
	elif String(placement) == PLACEMENT_REVIVE and _revives_this_run >= policy.revives_per_run:
		reason = REASON_REVIVE_USED
	elif _showing:
		reason = REASON_BUSY
	elif not _provider.is_available(KIND_REWARDED):
		reason = REASON_UNAVAILABLE
	return reason


## True when an optional rewarded ad can be offered at [param placement]
## (revive | double_reward | bonus_chest). Hide the offer when false.
func is_rewarded_available(placement: StringName) -> bool:
	return rewarded_block_reason(placement).is_empty()


## Shows an optional rewarded ad. Returns {"granted": bool, "reason": String};
## grant the reward only when granted is true (ad watched to the end).
## Coroutine: always await it.
func show_rewarded(placement: StringName) -> Dictionary:
	var reason: String = rewarded_block_reason(placement)
	if not reason.is_empty():
		return {"granted": false, "reason": reason}
	_showing = true
	_track_event(EVENT_AD_STARTED, {"kind": String(KIND_REWARDED), "placement": String(placement)})
	var result: Dictionary = AdsService._normalize(await _provider.show(KIND_REWARDED, placement))
	_showing = false
	var granted: bool = bool(result["shown"]) and bool(result["completed"])
	if granted and String(placement) == PLACEMENT_REVIVE:
		_revives_this_run += 1
		_resuming_after_revive = true
	_track_event(
		EVENT_AD_COMPLETED,
		{"kind": String(KIND_REWARDED), "placement": String(placement), "completed": granted},
	)
	if _bus != null:
		_bus.ad_finished.emit(placement, granted)
	if granted:
		return {"granted": true, "reason": ""}
	var failure: String = REASON_NOT_COMPLETED if bool(result["shown"]) else REASON_UNAVAILABLE
	return {"granted": false, "reason": failure}


func _on_run_completed(_result: RunResult) -> void:
	_levels_since_interstitial += 1
	_resuming_after_revive = false


func _on_run_failed(_result: RunResult) -> void:
	_resuming_after_revive = false


func _on_run_started(level_id: String, _mode: StringName) -> void:
	var resumed: bool = _resuming_after_revive and level_id == _run_level_id
	_run_level_id = level_id
	if resumed:
		# A revived run resumes and re-emits run_started: same run.
		_resuming_after_revive = false
		return
	begin_run()


func _on_run_restarted(_level_id: String) -> void:
	begin_run()


func _track_event(event: StringName, params: Dictionary) -> void:
	if _track.is_valid():
		_track.call(event, params)


## Provider results are untrusted: anything malformed counts as "not shown".
static func _normalize(raw: Variant) -> Dictionary:
	var out: Dictionary = {"shown": false, "completed": false}
	if typeof(raw) == TYPE_DICTIONARY:
		var d: Dictionary = raw as Dictionary
		out["shown"] = typeof(d.get("shown")) == TYPE_BOOL and bool(d["shown"])
		out["completed"] = bool(out["shown"]) and typeof(d.get("completed")) == TYPE_BOOL and bool(d["completed"])
	return out
