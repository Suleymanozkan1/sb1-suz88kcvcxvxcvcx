class_name RunController
extends RefCounted
## Prepares runs for every mode and applies their results to the systems.
##
## Preparation turns a request (mode + optional level) into level data plus sim
## modifiers. Finishing a run records stats and progression, grants the exact
## rewards, submits ranked runs, evaluates achievements and collects "reveals"
## (level-ups, unlocks, achievements) for the reward screens. All of it is
## deterministic and headless-testable: no nodes, no UI.

const MODE_BEST_FLAG: String = "mode_best"
const LAST_LEVEL_FLAG: String = "last_level"
const BOSS_LOCAL_INDEX: int = 52
const TUTORIAL_DONE_FLAG: String = "tutorial_done"
const TUTORIAL_LAST_LEVEL: String = "w01_l05"
## Runs reaching this combo are reported (funnel for the combo system).
const COMBO_EVENT_MIN: int = 10
const FAIL_CAUSES: Dictionary = {
	SimConst.FailReason.COLLISION: "collision",
	SimConst.FailReason.WRONG_PHASE: "wrong_phase",
	SimConst.FailReason.OBJECTIVE: "objective",
	SimConst.FailReason.TIME_UP: "time_up",
	SimConst.FailReason.MISSED_SPARK: "missed_spark",
}

var services: AppServices
var session: GameplaySession
## Current run request: {"mode", "source", "level_id", "kind", "world_id",
## "boss_queue", "rush_index", "rush_score", "design_duration", "tier"}.
var context: Dictionary = {}
var streamer: EndlessStreamer
var _worlds_unlocked: Array[String] = []


func _init(app: AppServices, gameplay_session: GameplaySession) -> void:
	services = app
	session = gameplay_session
	services.bus.world_unlocked.connect(func(world_id: String) -> void: _worlds_unlocked.append(world_id))


# --- Preparation -----------------------------------------------------------------


## Starts a request for [param mode_id]; [param level_id] is used by campaign
## sources. Returns false (and logs) when the request cannot be served.
func prepare(mode_id: StringName, level_id: String = "") -> bool:
	streamer = null
	var src: String = services.modes.source(mode_id)
	context = {"mode": mode_id, "source": src, "level_id": level_id, "rush_index": 0, "rush_score": 0}
	var data: Dictionary = {}
	match src:
		"campaign", "campaign_pick":
			data = services.levels.load_level(level_id)
		"daily":
			data = services.daily.today_level()
		"endless":
			data = _prepare_stream(mode_id)
		"boss_rush":
			var queue: PackedStringArray = boss_rush_queue()
			if queue.is_empty():
				return false
			context["boss_queue"] = queue
			data = services.levels.load_level(queue[0])
	return _load(data)


func _load(data: Dictionary) -> bool:
	if data.is_empty():
		GameLog.error("run", "no level data for %s" % str(context))
		return false
	context["level_id"] = str(data.get("id", context.get("level_id", "")))
	context["kind"] = str(data.get("kind", "normal"))
	context["world_id"] = str(data.get("world", "neon_core"))
	context["tier"] = str(data.get("tier", "early"))
	context["design_duration"] = float(data.get("duration", 0.0))
	var mods: Dictionary = services.modes.sim_modifiers(context["mode"] as StringName)
	if not session.load_level(data, mods):
		return false
	services.profile.flags[LAST_LEVEL_FLAG] = context["level_id"]
	services.ads.begin_run()
	return true


func _prepare_stream(mode_id: StringName) -> Dictionary:
	var seed_value: int = ModeCatalog.endless_seed(mode_id, services.clock.week_key())
	streamer = services.modes.make_streamer(mode_id, seed_value, services.catalog, services.difficulty)
	return streamer.begin()


## Bosses of every world whose boss the player has already beaten, in order.
func boss_rush_queue() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for i: int in range(1, services.catalog.world_count() + 1):
		var id: String = WorldCatalog.level_id(i, BOSS_LOCAL_INDEX)
		if services.profile.is_cleared(id):
			out.append(id)
	return out


## Endless streaming: call every frame while running. True if the course grew.
func pump() -> bool:
	if streamer == null or session.sim == null or not session.sim.is_running():
		return false
	return not streamer.pump(session.sim).is_empty()


## Boss rush: loads the next boss after a cleared one. False when the rush is over.
func advance_rush(result: RunResult) -> bool:
	if str(context.get("source", "")) != "boss_rush" or not result.completed:
		return false
	var queue: PackedStringArray = context["boss_queue"] as PackedStringArray
	var next_index: int = int(context["rush_index"]) + 1
	if next_index >= queue.size():
		return false
	# Bank only bosses that are followed by another; finish() adds the bank to
	# the final boss's own score exactly once.
	context["rush_score"] = int(context["rush_score"]) + result.score
	context["rush_index"] = next_index
	return _load(services.levels.load_level(queue[next_index]))


# --- Results -----------------------------------------------------------------------


## True when a failed run may be continued with the optional rewarded revive
## (never for dailies, revived runs, or failures a revive cannot help).
func can_offer_revive(result: RunResult) -> bool:
	return (
		not result.completed
		and not session.revived
		and str(context.get("source", "")) != "daily"
		and GameplaySession.can_revive_reason(result.fail_reason)
		and services.ads.is_rewarded_available(&"revive")
	)


## The fail screen's numbers without applying anything (used while a revive is
## still possible; [method finish] applies the run exactly once later).
func preview(result: RunResult) -> Dictionary:
	var src: String = str(context.get("source", "campaign"))
	var best: int = result.score
	if src == "campaign":
		best = maxi(
			int(services.profile.level_result(str(context.get("level_id", ""))).get("best_score", 0)), result.score
		)
	return {
		"result": result,
		"reveals": [],
		"reward": RewardBundle.new("run"),
		"best": best,
		"new_best": false,
		"progress": _progress_of(result),
		"can_revive": true,
		"can_double": false,
		"has_next": false,
		"next_level_id": "",
	}


## Applies a finished run. Returns the outcome for the UI:
## {"result", "best", "new_best", "reward": RewardBundle, "has_next", "next_level_id",
##  "progress", "can_revive", "can_double", "reveals": Array[Dictionary], "daily": Dictionary}
func finish(result: RunResult) -> Dictionary:
	_worlds_unlocked.clear()
	var mode_id: StringName = context.get("mode", &"classic") as StringName
	var src: String = str(context.get("source", "campaign"))
	if src == "boss_rush":
		result.score += int(context.get("rush_score", 0))
	var outcome: Dictionary = {"result": result, "reveals": [], "has_next": false, "next_level_id": ""}
	# Missions track the best combo of the day from this fact.
	services.bus.combo_reached.emit(result.max_combo)
	var reward: RewardBundle = RewardBundle.new("run")
	var stat_ctx: Dictionary = {
		"kind": str(context.get("kind", "normal")),
		"first_clear": false,
		"first_perfect": false,
		"design_duration": float(context.get("design_duration", 0.0)),
		"mode": mode_id,
	}
	match src:
		"campaign":
			reward = _finish_campaign(result, outcome)
		"daily":
			services.stats.record_run(result, stat_ctx)
			var daily_out: Dictionary = services.daily.record_result(result)
			services.stats.record_daily(bool(daily_out.get("first_completion", false)), int(daily_out.get("streak", 0)))
			outcome["daily"] = daily_out
			outcome["new_best"] = bool(daily_out.get("best", false))
			outcome["best"] = int(services.daily.status().get("best_score", result.score))
			var granted: Variant = daily_out.get("reward", null)
			if granted is RewardBundle:
				reward = granted as RewardBundle
		_:
			services.stats.record_run(result, stat_ctx)
			reward = _finish_scored(mode_id, result, outcome)
	outcome["reward"] = reward
	outcome["progress"] = _progress_of(result)
	services.check_integrity()
	# finish() is final: a revive is only offered from preview().
	outcome["can_revive"] = false
	outcome["can_double"] = (
		result.completed and not reward.is_empty() and services.ads.is_rewarded_available(&"double_reward")
	)
	if services.modes.has_board(mode_id) and not session.revived:
		services.leaderboard.submit_run(result)
	_track_run(result, mode_id)
	_collect_reveals(outcome)
	services.save.mark_dirty()
	return outcome


func _finish_campaign(result: RunResult, outcome: Dictionary) -> RewardBundle:
	var level_id: String = str(context["level_id"])
	var before: Dictionary = services.profile.level_result(level_id).duplicate()
	var level_data: Dictionary = session.level_data
	var prog: Dictionary = services.progression.record_level_result(result, level_data)
	services.stats.record_run(result, StatsService.build_context(result, level_data, prog))
	if result.completed and (str(level_data.get("tier", "")) != "tutorial" or level_id == TUTORIAL_LAST_LEVEL):
		# Onboarding is over: optional interstitials may now be considered.
		services.profile.flags[TUTORIAL_DONE_FLAG] = true
	outcome["best"] = maxi(int(before.get("best_score", 0)), result.score)
	outcome["new_best"] = bool(prog.get("new_best", false))
	var next_id: String = services.levels.next_level_id(level_id)
	outcome["next_level_id"] = next_id
	outcome["has_next"] = (
		result.completed and not next_id.is_empty() and services.progression.is_level_unlocked(next_id)
	)
	var reward_ctx: Dictionary = {
		"tier": context.get("tier", "early"),
		"kind": context.get("kind", "normal"),
		"first_clear": prog.get("first_clear", false),
		"prev_stars": prog.get("prev_stars", 0),
		"new_stars": prog.get("new_stars", 0),
		"first_perfect": prog.get("first_perfect", false),
	}
	var bundle: RewardBundle = services.rewards.compute_level_reward(result, reward_ctx)
	return services.rewards.grant(bundle)


func _finish_scored(mode_id: StringName, result: RunResult, outcome: Dictionary) -> RewardBundle:
	var metric: String = str(services.modes.mode(mode_id).get("best_metric", "score"))
	var value: int = int(result.distance) if metric == "distance" else result.score
	var raw_bests: Variant = services.profile.flags.get(MODE_BEST_FLAG, {})
	var bests: Dictionary = raw_bests as Dictionary if typeof(raw_bests) == TYPE_DICTIONARY else {}
	var prev: int = int(bests.get(String(mode_id), 0))
	outcome["new_best"] = value > prev
	outcome["best"] = maxi(prev, value)
	bests[String(mode_id)] = maxi(prev, value)
	services.profile.flags[MODE_BEST_FLAG] = bests
	var source: String = str(context.get("source", ""))
	var eligible: bool = result.completed or source == "endless"
	var spec: Dictionary = services.modes.score_reward(mode_id, result.score) if eligible else {}
	if spec.is_empty():
		return RewardBundle.new("mode:" + String(mode_id))
	return services.grant_reward_spec(services.rewards.with_coin_scale(spec), "mode:" + String(mode_id))


## Grants the optional rewarded-ad double. Only called after the ad completed.
func grant_double(bundle: RewardBundle) -> RewardBundle:
	return services.rewards.grant(services.rewards.double_for_ad(bundle))


## Share of the course covered, or -1 for streamed courses (no finish line:
## the fail screen shows the distance instead of a bar).
func _progress_of(result: RunResult) -> float:
	if session.sim_level != null and session.sim_level.endless:
		return -1.0
	var length: float = session.sim_level.length if session.sim_level != null else 0.0
	if length <= 0.0:
		return 1.0 if result.completed else 0.0
	return clampf(result.distance / length, 0.0, 1.0)


## Funnel events with the schema's parameter names (data/analytics/events.json).
func _track_run(result: RunResult, mode_id: StringName) -> void:
	var attempt: int = int(services.profile.level_result(result.level_id).get("attempts", 1))
	var params: Dictionary = {
		"level_id": result.level_id,
		"world_id": str(context.get("world_id", "")),
		"mode": String(mode_id),
		"score": result.score,
		"time_seconds": snappedf(result.time_seconds, 0.1),
		"attempt": attempt,
	}
	if result.completed:
		params["stars"] = result.stars
		params["grade"] = str(RunResult.Grade.keys()[result.grade]).to_lower()
		params["max_combo"] = result.max_combo
		params["taps"] = result.taps
		params["revived"] = result.revived
		services.analytics.track(&"level_completed", params)
		if result.perfect:
			services.analytics.track(
				&"perfect_completed", {"level_id": result.level_id, "mode": String(mode_id), "score": result.score}
			)
	else:
		params["distance"] = snappedf(result.distance, 0.1)
		params["cause"] = str(FAIL_CAUSES.get(result.fail_reason, "other"))
		services.analytics.track(&"level_failed", params)
	if result.max_combo >= COMBO_EVENT_MIN:
		services.analytics.track(&"combo_reached", {"level_id": result.level_id, "combo": result.max_combo})


## Level-ups (granting their table reward), worlds, achievements and cosmetics
## unlocked by this run, in the order the player should see them.
func _collect_reveals(outcome: Dictionary) -> void:
	var reveals: Array = outcome["reveals"] as Array
	# Level-up rewards are granted by AppServices the moment a level is gained
	# (also outside runs, e.g. mission XP); here they are only revealed.
	reveals.append_array(services.take_level_up_reveals())
	for world_id: String in _worlds_unlocked.duplicate():
		var world: Dictionary = services.catalog.world(world_id)
		reveals.append(
			{
				"eyebrow": tr_key("reveal.world_unlocked"),
				"title": Presenters.world_name(world),
				"subtitle": str((world.get("art", {}) as Dictionary).get("story", "")),
				"bundle": null
			}
		)
	var granted: Array[RewardBundle] = []
	var capture: Callable = func(b: RewardBundle) -> void: granted.append(b)
	services.bus.reward_granted.connect(capture)
	var unlocked: Array[String] = services.achievements.evaluate()
	services.bus.reward_granted.disconnect(capture)
	for ach_id: String in unlocked:
		var def: Dictionary = _achievement_def(ach_id)
		var bundle: RewardBundle = _granted_for(granted, ach_id)
		var reveal: Dictionary = {
			"eyebrow": tr_key("reveal.achievement"),
			"title": tr_key(str(def.get("name_key", ach_id))),
			"subtitle":
			tr_key(str(def.get("desc_key", ""))).format(
				{"target": int(def.get("target", 0)), "n": int(def.get("target", 0))}
			),
			"bundle": bundle
		}
		# A skin or trail reward is named and previewed ("New skin: ...").
		reveal.merge(Presenters.reward_items(services, bundle))
		reveals.append(reveal)
	for item_id: String in services.cosmetics.check_auto_unlocks():
		var item: Dictionary = services.cosmetics_catalog.item(item_id)
		var category: String = str(item.get("category", ""))
		reveals.append(
			{
				"eyebrow": tr_key("reveal.cosmetic"),
				"title": tr_key(str(item.get("name_key", item_id))),
				"subtitle": "",
				"bundle": null,
				"cosmetic": {"category": category, "params": item.get("params", {})}
			}
		)


## The bundle the achievement service actually granted for [param id] (its
## source names the achievement), or null when it carried no reward.
static func _granted_for(bundles: Array[RewardBundle], id: String) -> RewardBundle:
	for b: RewardBundle in bundles:
		if b.source.ends_with(id):
			return b
	return null


func _achievement_def(id: String) -> Dictionary:
	for d: Dictionary in services.achievements.list(true):
		if str(d.get("id", "")) == id:
			return d
	return {}


static func tr_key(key: String) -> String:
	return TranslationServer.translate(key)
