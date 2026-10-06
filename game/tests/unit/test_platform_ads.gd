extends TestCase
## Ads: interstitial pacing rules, optional rewarded ads, revive limits.

const START: int = 1790000000

var _bus: EventBus
var _clock: GameClock
var _profile: PlayerProfile
var _tracker: RecordingTracker
var _finished: Array[Dictionary] = []


## Ad provider double with scripted inventory and results.
class ScriptedAdProvider:
	extends AdProvider
	var available: Dictionary = {&"interstitial": true, &"rewarded": true}
	## Result returned by show(); Variant so malformed answers can be tested.
	var result: Variant = {"shown": true, "completed": true}
	var shows: Array[String] = []
	## When set, show() resolves one frame later (coroutine path).
	var tree: SceneTree = null

	func is_available(kind: StringName) -> bool:
		return bool(available.get(kind, false))

	func show(kind: StringName, placement: StringName) -> Dictionary:
		shows.append("%s:%s" % [kind, placement])
		if tree != null:
			await tree.process_frame
		return result if typeof(result) == TYPE_DICTIONARY else {"garbage": result}


## Records analytics calls made through the injected Callable.
class RecordingTracker:
	extends RefCounted
	var calls: Array[Dictionary] = []

	func track(event: StringName, params: Dictionary) -> bool:
		calls.append({"event": String(event), "params": params.duplicate()})
		return true

	func names() -> PackedStringArray:
		var out: PackedStringArray = PackedStringArray()
		for c: Dictionary in calls:
			out.append(str(c["event"]))
		return out


func before_each() -> void:
	_bus = EventBus.new()
	_clock = GameClock.new()
	_clock.set_fixed_unix(START)
	_profile = PlayerProfile.create_new(START)
	_tracker = RecordingTracker.new()
	# Capture a local array (not self) so the bus connection creates no cycle.
	var finished: Array[Dictionary] = []
	_finished = finished
	_bus.ad_finished.connect(
		func(placement: StringName, rewarded: bool) -> void:
			finished.append({"placement": String(placement), "rewarded": rewarded})
	)


func _clear_levels(count: int) -> void:
	for i: int in count:
		_profile.levels["w01_l%02d" % (i + 1)] = {"stars": 1, "clears": 1}


func _eligible_profile() -> void:
	_clear_levels(10)
	_profile.flags["tutorial_done"] = true


func _service(provider: AdProvider, policy: Dictionary = {}) -> AdsService:
	var data: Dictionary = policy if not policy.is_empty() else AdsPolicy.load_default()
	return AdsService.new(_profile, _bus, provider, data, _tracker.track, _clock)


func _complete_levels(count: int) -> void:
	for i: int in count:
		var result: RunResult = RunResult.new()
		result.completed = true
		_bus.run_completed.emit(result)


func test_bundled_policy_matches_rules() -> void:
	var policy: AdsPolicy = AdsPolicy.from_dict(AdsPolicy.load_default())
	assert_true(policy.enabled)
	assert_eq(policy.interstitial_placements, PackedStringArray(["level_end", "world_end"]))
	assert_eq(policy.rewarded_placements, PackedStringArray(["revive", "double_reward", "bonus_chest"]))
	assert_ge(policy.min_levels_cleared, 1)
	assert_ge(policy.every_n_levels, AdsPolicy.MIN_EVERY_N_LEVELS)
	assert_ge(policy.cooldown_seconds, AdsPolicy.MIN_COOLDOWN_SECONDS)
	assert_eq(policy.revives_per_run, 1)


func test_rewarded_unavailable_with_null_provider() -> void:
	_eligible_profile()
	var ads: AdsService = _service(NullAdProvider.new())
	for placement: StringName in [&"revive", &"double_reward", &"bonus_chest"]:
		assert_false(ads.is_rewarded_available(placement), "%s hidden without inventory" % placement)
	var result: Dictionary = await ads.show_rewarded(&"double_reward")
	assert_false(bool(result["granted"]))
	assert_eq(result["reason"], AdsService.REASON_UNAVAILABLE)
	_complete_levels(5)
	assert_eq(ads.interstitial_block_reason(&"level_end"), AdsService.REASON_UNAVAILABLE)
	var inter: Dictionary = await ads.show_interstitial(&"level_end")
	assert_false(bool(inter["shown"]))
	assert_empty(_tracker.calls, "nothing tracked when no ad started")
	assert_empty(_finished)


func test_rewarded_available_with_scripted_provider() -> void:
	var provider: ScriptedAdProvider = ScriptedAdProvider.new()
	var ads: AdsService = _service(provider)
	for placement: StringName in [&"revive", &"double_reward", &"bonus_chest"]:
		assert_true(ads.is_rewarded_available(placement), "%s offered" % placement)
	assert_false(ads.is_rewarded_available(&"shop_banner"), "unknown placements are never rewarded")
	var result: Dictionary = await ads.show_rewarded(&"double_reward")
	assert_true(bool(result["granted"]))
	assert_eq(provider.shows, ["rewarded:double_reward"] as Array[String])
	assert_eq(_tracker.names(), PackedStringArray(["ad_started", "ad_completed"]))
	assert_eq((_tracker.calls[1]["params"] as Dictionary)["completed"], true)
	assert_eq(_finished, [{"placement": "double_reward", "rewarded": true}] as Array[Dictionary])


func test_rewarded_not_granted_when_not_watched_to_end() -> void:
	var provider: ScriptedAdProvider = ScriptedAdProvider.new()
	provider.result = {"shown": true, "completed": false}
	var ads: AdsService = _service(provider)
	var result: Dictionary = await ads.show_rewarded(&"bonus_chest")
	assert_false(bool(result["granted"]))
	assert_eq(result["reason"], AdsService.REASON_NOT_COMPLETED)
	assert_eq(_finished[0]["rewarded"], false)
	provider.result = "nonsense"
	result = await ads.show_rewarded(&"bonus_chest")
	assert_false(bool(result["granted"]), "malformed provider answers never grant")


func test_rewarded_with_coroutine_provider() -> void:
	var provider: ScriptedAdProvider = ScriptedAdProvider.new()
	provider.tree = tree
	var ads: AdsService = _service(provider)
	var result: Dictionary = await ads.show_rewarded(&"revive")
	assert_true(bool(result["granted"]))


func test_revive_allowed_once_per_run() -> void:
	var provider: ScriptedAdProvider = ScriptedAdProvider.new()
	var ads: AdsService = _service(provider)
	_bus.run_started.emit("w01_l04", &"classic")
	assert_true(ads.is_rewarded_available(&"revive"))
	var first: Dictionary = await ads.show_rewarded(&"revive")
	assert_true(bool(first["granted"]))
	assert_false(ads.is_rewarded_available(&"revive"), "second revive in the same run refused")
	assert_eq(ads.rewarded_block_reason(&"revive"), AdsService.REASON_REVIVE_USED)
	var second: Dictionary = await ads.show_rewarded(&"revive")
	assert_false(bool(second["granted"]))
	assert_eq(provider.shows.size(), 1, "no ad shown for a refused revive")
	_bus.run_started.emit("w01_l04", &"classic")
	assert_false(ads.is_rewarded_available(&"revive"), "the resumed run is the same run")
	assert_true(ads.is_rewarded_available(&"double_reward"), "other rewarded placements unaffected")
	_bus.run_failed.emit(RunResult.new())
	assert_false(ads.is_rewarded_available(&"revive"))
	_bus.run_started.emit("w01_l04", &"classic")
	assert_true(ads.is_rewarded_available(&"revive"), "a new attempt gets a new revive")
	await ads.show_rewarded(&"revive")
	_bus.run_restarted.emit("w01_l04")
	assert_true(ads.is_rewarded_available(&"revive"), "restart starts a new run")


func test_unresumed_revive_does_not_cost_the_next_level_its_revive() -> void:
	var provider: ScriptedAdProvider = ScriptedAdProvider.new()
	var ads: AdsService = _service(provider)
	_bus.run_started.emit("w01_l04", &"classic")
	assert_true(bool((await ads.show_rewarded(&"revive"))["granted"]))
	# The player watched the revive ad but left before the run resumed, so no
	# run_started/run_failed followed. The next run is on another level.
	_bus.run_started.emit("w01_l05", &"classic")
	assert_true(ads.is_rewarded_available(&"revive"), "a different level is a new run")
	assert_true(bool((await ads.show_rewarded(&"revive"))["granted"]))
	_bus.run_started.emit("w01_l05", &"classic")
	assert_false(ads.is_rewarded_available(&"revive"), "the resume of that run is still the same run")


func test_interstitial_only_at_natural_breakpoints() -> void:
	_eligible_profile()
	var ads: AdsService = _service(ScriptedAdProvider.new())
	_complete_levels(3)
	for placement: StringName in [&"level_start", &"gameplay", &"pause", &"revive", &"app_open", &"shop"]:
		assert_eq(ads.interstitial_block_reason(placement), AdsService.REASON_NOT_BREAKPOINT, String(placement))
	assert_true(ads.can_show_interstitial(&"level_end"))
	assert_true(ads.can_show_interstitial(&"world_end"))
	var result: Dictionary = await ads.show_interstitial(&"gameplay")
	assert_false(bool(result["shown"]))


func test_interstitial_requires_min_levels_cleared() -> void:
	_clear_levels(3)
	_profile.flags["tutorial_done"] = true
	var ads: AdsService = _service(ScriptedAdProvider.new())
	_complete_levels(5)
	assert_eq(ads.interstitial_block_reason(&"level_end"), AdsService.REASON_MIN_LEVEL)
	_clear_levels(6)
	assert_true(ads.can_show_interstitial(&"level_end"))


func test_interstitial_frequency_and_tracking() -> void:
	_eligible_profile()
	var provider: ScriptedAdProvider = ScriptedAdProvider.new()
	var ads: AdsService = _service(provider)
	_complete_levels(2)
	assert_eq(ads.interstitial_block_reason(&"level_end"), AdsService.REASON_FREQUENCY)
	_complete_levels(1)
	var result: Dictionary = await ads.show_interstitial(&"level_end")
	assert_true(bool(result["shown"]))
	assert_eq(ads.levels_since_interstitial(), 0)
	assert_eq(_tracker.names(), PackedStringArray(["ad_started", "ad_completed"]))
	assert_eq((_tracker.calls[0]["params"] as Dictionary)["kind"], "interstitial")
	assert_eq(_finished, [{"placement": "level_end", "rewarded": false}] as Array[Dictionary])
	_clock.set_fixed_unix(START + 3600)
	_complete_levels(2)
	assert_eq(ads.interstitial_block_reason(&"level_end"), AdsService.REASON_FREQUENCY)
	_complete_levels(1)
	assert_true(ads.can_show_interstitial(&"level_end"))


func test_interstitial_cooldown() -> void:
	_eligible_profile()
	var policy: Dictionary = AdsPolicy.load_default()
	(policy["interstitial"] as Dictionary)["every_n_levels"] = 2
	(policy["interstitial"] as Dictionary)["cooldown_seconds"] = 300
	var ads: AdsService = _service(ScriptedAdProvider.new(), policy)
	_complete_levels(2)
	assert_true(bool((await ads.show_interstitial(&"level_end"))["shown"]))
	_complete_levels(2)
	_clock.set_fixed_unix(START + 120)
	assert_eq(ads.interstitial_block_reason(&"world_end"), AdsService.REASON_COOLDOWN)
	var blocked: Dictionary = await ads.show_interstitial(&"world_end")
	assert_false(bool(blocked["shown"]))
	_clock.set_fixed_unix(START + 301)
	assert_true(ads.can_show_interstitial(&"world_end"))


func test_no_interstitial_after_any_purchase() -> void:
	_eligible_profile()
	_profile.purchases.append("pack_neon_pulse")
	var ads: AdsService = _service(ScriptedAdProvider.new())
	_complete_levels(10)
	assert_eq(ads.interstitial_block_reason(&"level_end"), AdsService.REASON_PURCHASED)
	assert_true(ads.is_rewarded_available(&"double_reward"), "optional rewarded ads stay available")


func test_no_interstitial_during_tutorial() -> void:
	_clear_levels(7)
	var ads: AdsService = _service(ScriptedAdProvider.new())
	_complete_levels(5)
	assert_true(ads.is_in_tutorial())
	assert_eq(ads.interstitial_block_reason(&"level_end"), AdsService.REASON_TUTORIAL)
	_profile.flags["tutorial_done"] = true
	assert_true(ads.can_show_interstitial(&"level_end"))
	ads.tutorial_active = true
	assert_eq(ads.interstitial_block_reason(&"level_end"), AdsService.REASON_TUTORIAL, "replayed tutorial")
	ads.tutorial_active = false
	_profile.flags.erase("tutorial_done")
	_clear_levels(9)
	assert_false(ads.is_in_tutorial(), "enough clears count as onboarding done even without the flag")


func test_disabled_policy_blocks_everything() -> void:
	_eligible_profile()
	var policy: Dictionary = AdsPolicy.load_default()
	policy["enabled"] = false
	var ads: AdsService = _service(ScriptedAdProvider.new(), policy)
	_complete_levels(5)
	assert_eq(ads.interstitial_block_reason(&"level_end"), AdsService.REASON_DISABLED)
	assert_false(ads.is_rewarded_available(&"revive"))


func test_policy_data_cannot_loosen_hard_rules() -> void:
	var data: Dictionary = {
		"interstitial":
		{
			"placements": ["level_end", "gameplay", "app_open"],
			"every_n_levels": 1,
			"cooldown_seconds": 0,
			"min_levels_cleared": -4,
		},
		"rewarded": {"placements": ["revive", "auto_play"], "revives_per_run": 5},
	}
	var policy: AdsPolicy = AdsPolicy.from_dict(data)
	assert_eq(policy.interstitial_placements, PackedStringArray(["level_end"]))
	assert_eq(policy.every_n_levels, AdsPolicy.MIN_EVERY_N_LEVELS)
	assert_eq(policy.cooldown_seconds, AdsPolicy.MIN_COOLDOWN_SECONDS)
	assert_eq(policy.min_levels_cleared, 0)
	assert_eq(policy.rewarded_placements, PackedStringArray(["revive"]))
	assert_eq(policy.revives_per_run, 1)
	var empty: AdsPolicy = AdsPolicy.from_dict({"interstitial": "broken", "rewarded": 3})
	assert_eq(empty.every_n_levels, AdsPolicy.DEFAULT_EVERY_N_LEVELS, "malformed sections use defaults")


func test_remote_overrides_merge_into_policy() -> void:
	var rc: RemoteConfig = RemoteConfig.new(RemoteConfig.load_defaults(), Callable(), Callable())
	var base: Dictionary = AdsPolicy.load_default()
	var untouched: AdsPolicy = AdsPolicy.from_dict(AdsPolicy.merge_remote(base, rc))
	assert_eq(untouched.every_n_levels, AdsPolicy.from_dict(base).every_n_levels, "remote defaults do not override")
	rc.apply_overrides({"ads.interstitial_every_n_levels": 5, "ads.interstitial_min_level": 12})
	var merged: AdsPolicy = AdsPolicy.from_dict(AdsPolicy.merge_remote(base, rc))
	assert_eq(merged.every_n_levels, 5)
	assert_eq(merged.min_levels_cleared, 12)
	rc.apply_overrides({"ads.enabled": false})
	assert_false(AdsPolicy.from_dict(AdsPolicy.merge_remote(base, rc)).enabled)
	base["enabled"] = false
	rc.apply_overrides({"ads.enabled": true})
	assert_false(AdsPolicy.from_dict(AdsPolicy.merge_remote(base, rc)).enabled, "remote cannot force ads on")
	_eligible_profile()
	var ads: AdsService = _service(ScriptedAdProvider.new())
	ads.set_policy(AdsPolicy.merge_remote(AdsPolicy.load_default(), rc))
	assert_eq(ads.policy.every_n_levels, 5)
