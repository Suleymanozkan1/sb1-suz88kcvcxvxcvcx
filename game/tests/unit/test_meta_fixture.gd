extends TestCase
## Shared fixture for the meta module suites (achievements + missions).
##
## Holds no tests itself: the suites extend this script by path. Every test
## gets a fresh profile, bus, fixed clock and a recording reward handler.

const DAY: int = 86400
## Monday 2026-10-05 00:00 UTC.
const MONDAY: int = 1791158400
## Wednesday 2026-10-07 12:00 UTC.
const NOW: int = 1791374400

var _clock: GameClock
var _bus: EventBus
var _profile: PlayerProfile
var _rewards: RewardRecorder
## Ids from EventBus.achievement_unlocked, in emission order.
var _unlocked_events: Array[String] = []
## Ids from EventBus.mission_completed, in emission order.
var _completed_events: Array[String] = []


## Records reward grants (stands in for RewardEngine.grant).
class RewardRecorder:
	extends RefCounted
	var calls: Array[Dictionary] = []

	func grant(spec: Dictionary, source: String) -> RewardBundle:
		calls.append({"spec": spec, "source": source})
		var bundle: RewardBundle = RewardBundle.new(source)
		bundle.add(RewardBundle.TYPE_COINS, int(spec.get("coins", 0)))
		bundle.add(RewardBundle.TYPE_GEMS, int(spec.get("gems", 0)))
		bundle.add(RewardBundle.TYPE_XP, int(spec.get("xp", 0)))
		if spec.has("badge"):
			bundle.add(RewardBundle.TYPE_BADGE, 1, str(spec["badge"]))
		return bundle

	func count_for(source: String) -> int:
		var n: int = 0
		for call: Dictionary in calls:
			if call["source"] == source:
				n += 1
		return n


func before_each() -> void:
	_clock = GameClock.new()
	_clock.set_fixed_unix(NOW)
	_bus = EventBus.new()
	_profile = PlayerProfile.create_new(NOW)
	_rewards = RewardRecorder.new()
	# The lambdas capture only local arrays (never self) so no
	# test -> bus -> lambda -> test reference cycle is created.
	var unlocked: Array[String] = []
	var completed: Array[String] = []
	_unlocked_events = unlocked
	_completed_events = completed
	_bus.achievement_unlocked.connect(func(id: String) -> void: unlocked.append(id))
	_bus.mission_completed.connect(func(id: String) -> void: completed.append(id))


func _achievements(definitions: Array = []) -> AchievementService:
	return AchievementService.new(_profile, _bus, _clock, _rewards.grant, definitions)


func _missions(config: Dictionary = {}) -> MissionService:
	return MissionService.new(_profile, _bus, _clock, _rewards.grant, config)


## A mission service on its own fresh profile and bus (for comparing players).
func _missions_for_new_player(config: Dictionary = {}) -> MissionService:
	var profile: PlayerProfile = PlayerProfile.create_new(_clock.now_unix())
	return MissionService.new(profile, EventBus.new(), _clock, _rewards.grant, config)


func _def(id: String, stat: String, target: Variant, extra: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"id": id,
		"name_key": "ach.%s.name" % id,
		"desc_key": "ach.%s.desc" % id,
		"category": "progress",
		"stat": stat,
		"target": target,
		"reward": {"coins": 10, "gems": 0},
		"hidden": false,
	}
	d.merge(extra, true)
	return d


func _template(id: String, stat: String, targets: Array, extra: Dictionary = {}) -> Dictionary:
	var t: Dictionary = {
		"id": id,
		"desc_key": "mis.%s.desc" % id,
		"stat": stat,
		"targets": targets,
		"reward": {"coins": 100, "xp": 40},
	}
	t.merge(extra, true)
	return t


## One daily mission on [param daily_stat] and one weekly mission (target 30).
func _single_config(daily_stat: String, daily_target: int, weekly_stat: String = "levels_cleared") -> Dictionary:
	return {
		"daily_count": 1,
		"weekly_count": 1,
		"daily_templates": [_template("d", daily_stat, [daily_target])],
		"weekly_templates": [_template("w", weekly_stat, [30])],
	}


func _shipped_achievements() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Variant in AchievementService.load_definitions():
		out.append(raw as Dictionary)
	return out
