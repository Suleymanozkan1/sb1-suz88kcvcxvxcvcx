class_name RunResult
extends RefCounted
## Outcome of one run, derived from the final simulation state and level meta.

enum Grade { NONE = 0, NORMAL = 1, GOOD = 2, GREAT = 3, PERFECT = 4 }

var level_id: String = ""
var mode: StringName = &"classic"
var completed: bool = false
var fail_reason: int = SimConst.FailReason.NONE
## Entity type that ended the run (-1 when none), for the fail screen's tip.
var fail_entity_type: int = -1
## True when the run ended in the air or on landing after a launch pad.
var fail_in_air: bool = false
var score: int = 0
var sparks: int = 0
var spark_total: int = 0
var prisms: int = 0
var max_combo: int = 0
var near_misses: int = 0
var shatters: int = 0
var chain_links: int = 0
var gates: int = 0
var damage: int = 0
var portals_used: int = 0
var currents_ridden: int = 0
var overdrives: int = 0
var taps: int = 0
var time_seconds: float = 0.0
var distance: float = 0.0
var perfect: bool = false
var stars: int = 0
var grade: int = Grade.NONE
var score_target: int = 0
var combo_target: int = 0
var combo_target_met: bool = false
var revived: bool = false
var replay: RunReplay = null


static func from_sim(sim: FluxSim, meta: Dictionary, mode_id: StringName) -> RunResult:
	var r: RunResult = RunResult.new()
	r.level_id = sim.level.level_id
	r.mode = mode_id
	r.completed = sim.status == SimConst.Status.COMPLETED
	r.fail_reason = sim.fail_reason
	if sim.fail_entity >= 0 and sim.fail_entity < sim.level.entity_count():
		r.fail_entity_type = sim.level.e_type[sim.fail_entity]
	r.fail_in_air = sim.status == SimConst.Status.FAILED and sim.airborne
	r.score = sim.score
	r.sparks = sim.sparks
	r.spark_total = sim.level.spark_total
	r.prisms = sim.prisms
	r.max_combo = sim.max_combo
	r.near_misses = sim.near_misses
	r.shatters = sim.shatters
	r.chain_links = sim.chain_links
	r.gates = sim.gates
	r.damage = sim.damage
	r.portals_used = sim.portals_used
	r.currents_ridden = sim.currents_ridden
	r.overdrives = sim.overdrives
	r.taps = sim.taps
	r.time_seconds = sim.time()
	r.distance = sim.d
	r.score_target = int(meta.get("score_target", 0))
	r.combo_target = int(meta.get("combo_target", 0))
	r.perfect = sim.is_perfect()
	r.combo_target_met = r.combo_target > 0 and r.max_combo >= r.combo_target
	r.stars = compute_stars(r.completed, r.score, r.score_target, r.perfect)
	r.grade = compute_grade(r.completed, r.stars, r.perfect, r.combo_target_met)
	return r


static func compute_stars(completed: bool, score: int, score_target: int, perfect: bool) -> int:
	if not completed:
		return 0
	var s: int = 1
	if score >= score_target:
		s += 1
	if perfect:
		s += 1
	return s


static func compute_grade(completed: bool, stars: int, perfect: bool, combo_met: bool) -> int:
	if not completed:
		return Grade.NONE
	if perfect:
		return Grade.PERFECT
	if stars >= 2 and combo_met:
		return Grade.GREAT
	if stars >= 2:
		return Grade.GOOD
	return Grade.NORMAL
