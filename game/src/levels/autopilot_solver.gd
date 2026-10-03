class_name AutopilotSolver
extends RefCounted
## Independent beam-search solver over the real simulation.
##
## Explores tap / no-tap decisions every [member decision_ticks] ticks, merging
## equivalent states via [method FluxSim.state_key] and keeping the best
## [member beam_width] states per layer (most sparks, then score, then fewest
## taps). It does not use the stored solution, so it cross-checks that a level
## is solvable at human decision granularity.

var decision_ticks: int = 3
var beam_width: int = 96
var max_ticks: int = 60 * 60 * 3

var best_taps: PackedInt32Array = PackedInt32Array()
var best_score: int = 0
var best_sparks: int = 0
var explored: int = 0


class SearchNode:
	var sim: FluxSim
	var taps: PackedInt32Array

	func _init(s: FluxSim, t: PackedInt32Array) -> void:
		sim = s
		taps = t


## Returns true if some decision sequence completes the level without damage.
func solve(level: SimLevel) -> bool:
	best_taps = PackedInt32Array()
	best_score = -1
	best_sparks = -1
	explored = 0
	var root: FluxSim = FluxSim.new()
	root.record_events = false
	root.shields_allowed = false
	root.setup(level)
	var frontier: Array[SearchNode] = [SearchNode.new(root, PackedInt32Array())]
	var found: bool = false
	while not frontier.is_empty():
		var layer: Dictionary = {}
		for node: SearchNode in frontier:
			for tap: bool in [false, true]:
				var child: FluxSim = node.sim.clone()
				var taps: PackedInt32Array = node.taps
				if tap:
					taps = node.taps.duplicate()
					taps.append(child.tick)
				child.step(tap)
				for _i: int in decision_ticks - 1:
					if not child.is_running():
						break
					child.step(false)
				explored += 1
				if child.status == SimConst.Status.FAILED:
					continue
				if child.status == SimConst.Status.COMPLETED:
					found = true
					if _better(child, taps):
						best_taps = taps
						best_score = child.score
						best_sparks = child.sparks
					continue
				if child.tick > max_ticks:
					continue
				var key: int = child.state_key()
				var existing: SearchNode = layer.get(key, null) as SearchNode
				if existing == null or _rank(child, taps) > _rank(existing.sim, existing.taps):
					layer[key] = SearchNode.new(child, taps)
		frontier = _prune(layer.values())
	return found


func _better(sim: FluxSim, taps: PackedInt32Array) -> bool:
	if sim.sparks != best_sparks:
		return sim.sparks > best_sparks
	if sim.score != best_score:
		return sim.score > best_score
	return best_taps.is_empty() or taps.size() < best_taps.size()


func _rank(sim: FluxSim, taps: PackedInt32Array) -> float:
	return float(sim.sparks) * 1.0e6 + float(sim.score) - float(taps.size()) * 0.001


func _prune(nodes: Array) -> Array[SearchNode]:
	var typed: Array[SearchNode] = []
	for n: Variant in nodes:
		typed.append(n as SearchNode)
	if typed.size() <= beam_width:
		return typed
	typed.sort_custom(func(a: SearchNode, b: SearchNode) -> bool: return _rank(a.sim, a.taps) > _rank(b.sim, b.taps))
	# Keep lateral diversity: the best state per (lane, phase, heavy) first.
	var kept: Array[SearchNode] = []
	var seen: Dictionary = {}
	for n: SearchNode in typed:
		var k: int = (n.sim.lane * 4 + n.sim.phase * 2 + (1 if n.sim.heavy else 0)) * 1000 + int(n.sim.speed * 2.0)
		if not seen.has(k):
			seen[k] = true
			kept.append(n)
	for n: SearchNode in typed:
		if kept.size() >= beam_width:
			break
		if not kept.has(n):
			kept.append(n)
	return kept
