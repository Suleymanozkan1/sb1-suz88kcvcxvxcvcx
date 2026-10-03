class_name RunReplay
extends RefCounted
## Input log of a run: the ticks on which the player tapped.
##
## Because [FluxSim] is deterministic, a replay plus the level data reproduces the
## run exactly. Leaderboard / daily submissions carry a replay so the server can
## re-simulate and compute the authoritative score (see server/verify_replay.gd).

const SIM_VERSION: int = 1
## A human cannot produce two distinct taps less than this many ticks apart.
const MIN_TAP_GAP_TICKS: int = 2
## Human tap-rate ceiling shared by the client queue and the server verifier
## (data/daily/daily.json "verifier" mirrors these; a test keeps them equal).
const MAX_TAPS_PER_WINDOW: int = 12
const TAP_WINDOW_TICKS: int = 60

var level_id: String = ""
var level_seed: int = 0
var mode: StringName = &"classic"
var sim_version: int = SIM_VERSION
var tap_ticks: PackedInt32Array = PackedInt32Array()
var end_tick: int = 0


func record_tap(tick: int) -> void:
	tap_ticks.append(tick)


func to_dict() -> Dictionary:
	return {
		"level_id": level_id,
		"seed": level_seed,
		"mode": String(mode),
		"sim_version": sim_version,
		"taps": Array(tap_ticks),
		"end_tick": end_tick,
	}


static func from_dict(data: Dictionary) -> RunReplay:
	var r: RunReplay = RunReplay.new()
	r.level_id = str(data.get("level_id", ""))
	r.level_seed = int(data.get("seed", 0))
	r.mode = StringName(str(data.get("mode", "classic")))
	r.sim_version = int(data.get("sim_version", 0))
	r.end_tick = int(data.get("end_tick", 0))
	var taps: Variant = data.get("taps", [])
	if typeof(taps) == TYPE_ARRAY:
		for t: Variant in taps as Array:
			r.tap_ticks.append(int(t))
	return r


## Structural plausibility checks (monotonic ticks, human-possible spacing).
func validate_structure() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if sim_version != SIM_VERSION:
		problems.append("sim_version mismatch")
	var last: int = -MIN_TAP_GAP_TICKS
	for t: int in tap_ticks:
		if t < 0:
			problems.append("negative tap tick")
			break
		if t - last < MIN_TAP_GAP_TICKS:
			problems.append("taps closer than %d ticks" % MIN_TAP_GAP_TICKS)
			break
		last = t
	if end_tick > 0 and tap_ticks.size() > 0 and tap_ticks[tap_ticks.size() - 1] > end_tick:
		problems.append("tap after end of run")
	return problems


## Re-simulates the run on [param sim] (already set up for the level) and returns it.
func play_on(sim: FluxSim, max_ticks: int = 60 * 60 * 10) -> FluxSim:
	sim.reset()
	var tap_index: int = 0
	var count: int = tap_ticks.size()
	while sim.is_running() and sim.tick < max_ticks:
		var tap: bool = tap_index < count and tap_ticks[tap_index] == sim.tick
		if tap:
			tap_index += 1
		sim.step(tap)
	return sim
