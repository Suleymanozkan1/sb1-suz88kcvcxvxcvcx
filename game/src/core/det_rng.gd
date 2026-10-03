class_name DetRng
extends RefCounted
## Deterministic xorshift32 random generator with stable string hashing.
##
## Implemented with shifts/xors on 32-bit masked integers only, so sequences are
## identical on every platform and engine version (unlike engine RNG helpers
## whose range mapping may change). Used for level generation, daily seeds and
## mission selection.

const MASK32: int = 0xFFFFFFFF
const FNV_OFFSET: int = 2166136261
const FNV_PRIME: int = 16777619

var _state: int = 1


func _init(seed_value: int = 1) -> void:
	set_seed(seed_value)


func set_seed(seed_value: int) -> void:
	_state = seed_value & MASK32
	if _state == 0:
		_state = 0x9E3779B9
	# Warm up so close seeds diverge quickly.
	for _i: int in 4:
		next_u32()


func get_state() -> int:
	return _state


func next_u32() -> int:
	var s: int = _state
	s ^= (s << 13) & MASK32
	s ^= s >> 17
	s ^= (s << 5) & MASK32
	_state = s & MASK32
	return _state


## Float in [0, 1).
func next_float() -> float:
	return float(next_u32()) / 4294967296.0


## Integer in [min_value, max_value] inclusive.
func range_int(min_value: int, max_value: int) -> int:
	if max_value <= min_value:
		return min_value
	var span: int = max_value - min_value + 1
	return min_value + int(next_u32() % span)


func range_float(min_value: float, max_value: float) -> float:
	return min_value + (max_value - min_value) * next_float()


func chance(probability: float) -> bool:
	return next_float() < probability


func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[range_int(0, items.size() - 1)]


## Weighted pick from {key: weight}; keys iterate in insertion order (deterministic).
func pick_weighted(weights: Dictionary) -> Variant:
	var total: float = 0.0
	for k: Variant in weights:
		total += maxf(0.0, float(weights[k]))
	if total <= 0.0:
		return null
	var roll: float = next_float() * total
	var last: Variant = null
	for k: Variant in weights:
		var w: float = maxf(0.0, float(weights[k]))
		if w <= 0.0:
			continue
		last = k
		if roll < w:
			return k
		roll -= w
	return last


func shuffle(items: Array) -> void:
	for i: int in range(items.size() - 1, 0, -1):
		var j: int = range_int(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp


## 32-bit FNV-1a hash of a UTF-8 string (stable across platforms).
static func hash_string(text: String) -> int:
	var h: int = FNV_OFFSET
	for byte: int in text.to_utf8_buffer():
		h ^= byte
		h = (h * FNV_PRIME) & MASK32
	return h


static func combine(a: int, b: int) -> int:
	return hash_string("%d:%d" % [a & MASK32, b & MASK32])
