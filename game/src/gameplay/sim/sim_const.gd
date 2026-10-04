class_name SimConst
extends RefCounted
## Shared constants and enums of the deterministic FLUX DROP simulation.
##
## Every gameplay rule number lives here (or in level data) so that the sim, the
## generator, the validator, the replay verifier and the view agree exactly.

enum EntityType {
	BARRIER = 0,
	PHASE_GATE = 1,
	SLIDER = 2,
	PULSE_GATE = 3,
	BREAKABLE = 4,
	CURRENT = 5,
	PORTAL = 6,
	FORM_GATE = 7,
	SPARK = 8,
	PRISM = 9,
	SHIELD = 10,
	MAGNET = 11,
	GRAVITY = 12,
	LAUNCH_PAD = 13,
	PLATE = 14,
}

enum Form { HOP = 0, PHASE = 1, DASH = 2, SURGE = 3 }

enum Status { RUNNING = 0, FAILED = 1, COMPLETED = 2 }

enum FailReason {
	NONE = 0,
	COLLISION = 1,
	WRONG_PHASE = 2,
	OBJECTIVE = 3,
	TIME_UP = 4,
	MISSED_SPARK = 5,
}

## Events written into the sim's event buffer for presentation layers.
enum EventType {
	TAP_HOP = 0,
	TAP_PHASE = 1,
	TAP_DASH = 2,
	TAP_DASH_DENIED = 3,
	TAP_SURGE = 4,
	SPARK = 5,
	PRISM = 6,
	SPARK_MISSED = 7,
	NEAR_MISS = 8,
	SHATTER = 9,
	CHAIN = 10,
	GATE_PASS = 11,
	HIT_SHIELDED = 12,
	FAIL = 13,
	COMPLETE = 14,
	FORM_CHANGE = 15,
	PORTAL = 16,
	CURRENT = 17,
	SHIELD_UP = 18,
	MAGNET_UP = 19,
	OVERDRIVE_START = 20,
	OVERDRIVE_END = 21,
	COMBO_STEP = 22,
	ZEN_BUMP = 23,
	LAUNCH = 24,
	LAND = 25,
	## value: gravity factor × 100.
	GRAVITY_ENTER = 26,
	GRAVITY_EXIT = 27,
	## value: plates now stacked.
	PLATE_UP = 28,
	STACK_CRASH = 29,
	VAULT = 30,
}

## Fixed simulation rate. Inputs are applied on tick boundaries.
const TICK_RATE: int = 60
const DT: float = 1.0 / 60.0

## Geometry (world units).
const LANE_WIDTH: float = 1.6
const CORE_RADIUS: float = 0.3
const BLOCK_HALF_WIDTH: float = 0.58
const HAZARD_HALF_DEPTH: float = 0.22
const GATE_HALF_DEPTH: float = 0.12
const SPARK_COLLECT_RADIUS: float = 0.6
const SPARK_COLLECT_DEPTH: float = 0.55
const MAGNET_COLLECT_RADIUS: float = 2.0
const PICKUP_RADIUS: float = 0.7
## Closest approach that still counts as a near miss: about 50 ms before the
## last moment for a hop past a block (a settled core in the next lane is 0.72
## away, so riding a lane is never a near miss).
const NEAR_MISS_MARGIN: float = 0.6
const PORTAL_CAPTURE_HALF_WIDTH: float = 0.55
## How far ahead/behind the core the sim inspects entities (units).
const ENTITY_REACH: float = 1.2

## Movement.
const HOP_TIME: float = 0.13
const HOP_MIN_TIME_FRACTION: float = 0.55
const DASH_TIME: float = 0.34
const DASH_COOLDOWN: float = 0.8
const DASH_SPEED_FACTOR: float = 1.6
const SURGE_HEAVY_FACTOR: float = 1.4
const SURGE_LIGHT_FACTOR: float = 0.72
const SURGE_ACCEL: float = 9.0
const DEFAULT_ACCEL: float = 80.0
const HIT_INVULN_TIME: float = 0.6
const MAGNET_TIME: float = 4.0
const OVERDRIVE_TIME: float = 3.0
const MAX_CHARGES: int = 8
const MAX_SHIELDS: int = 1
const CHAIN_DISTANCE: float = 2.6

## Mass and gravity (launch pads, gravity wells, mass plates).
## Gravity pulling the core back down after a launch (units/s²) at factor 1.
const G0: float = 30.0
## Upward speed a launch pad gives an unweighted core (units/s).
const LAUNCH_VY: float = 10.0
## Height above the floor at which the core clears a block (block top 0.9
## minus the core's resting centre 0.38 plus its radius 0.3).
const AIR_CLEARANCE: float = 0.85
## Highest a core can be and still collect sparks and pickups.
const PICKUP_HEIGHT: float = 0.5
const PAD_CAPTURE_HALF_WIDTH: float = 0.55
## Each stacked plate adds this much mass: a launch's upward speed is divided by
## 1 + MASS_PER_PLATE × plates.
const MASS_PER_PLATE: float = 0.15
const MAX_PLATES: int = 3
## Gravity factor g scales forward speed by 1 + GRAV_SPEED_K × (g − 1) and hop
## time by 1 − GRAV_HOP_K × (g − 1), clamped to the hop scale bounds.
const GRAV_SPEED_K: float = 0.3
const GRAV_HOP_K: float = 0.5
const GRAV_HOP_SCALE_MIN: float = 0.6
const GRAV_HOP_SCALE_MAX: float = 1.4
const GRAVITY_MIN: float = 0.5
const GRAVITY_MAX: float = 2.0

## Scoring.
const SCORE_SPARK: int = 10
const SCORE_PRISM: int = 50
const SCORE_NEAR_MISS: int = 25
const SCORE_SHATTER: int = 30
const SCORE_CHAIN_LINK: int = 15
const SCORE_GATE_PASS: int = 20
const SCORE_CLEAR_BONUS: int = 100
const SCORE_VAULT: int = 20
const SCORE_PLATE: int = 10
const COMBO_STEP: int = 5
const COMBO_MULT_STEP: float = 0.5
const COMBO_MULT_MAX: float = 4.0
const OVERDRIVE_MULT: float = 2.0

const ENTITY_NAMES: Dictionary = {
	"barrier": EntityType.BARRIER,
	"phase_gate": EntityType.PHASE_GATE,
	"slider": EntityType.SLIDER,
	"pulse_gate": EntityType.PULSE_GATE,
	"breakable": EntityType.BREAKABLE,
	"current": EntityType.CURRENT,
	"portal": EntityType.PORTAL,
	"form_gate": EntityType.FORM_GATE,
	"spark": EntityType.SPARK,
	"prism": EntityType.PRISM,
	"shield": EntityType.SHIELD,
	"magnet": EntityType.MAGNET,
	"gravity": EntityType.GRAVITY,
	"launch_pad": EntityType.LAUNCH_PAD,
	"plate": EntityType.PLATE,
}

const FORM_NAMES: Dictionary = {
	"hop": Form.HOP,
	"phase": Form.PHASE,
	"dash": Form.DASH,
	"surge": Form.SURGE,
}


static func entity_type_from_name(type_name: String) -> int:
	return int(ENTITY_NAMES.get(type_name, -1))


static func entity_name(type_id: int) -> String:
	for key: String in ENTITY_NAMES:
		if int(ENTITY_NAMES[key]) == type_id:
			return key
	return ""


static func form_from_name(form_name: String) -> int:
	return int(FORM_NAMES.get(form_name, -1))


static func form_name(form_id: int) -> String:
	for key: String in FORM_NAMES:
		if int(FORM_NAMES[key]) == form_id:
			return key
	return ""


static func is_hazard(type_id: int) -> bool:
	return (
		type_id == EntityType.BARRIER
		or type_id == EntityType.SLIDER
		or type_id == EntityType.PULSE_GATE
		or type_id == EntityType.BREAKABLE
		or type_id == EntityType.PHASE_GATE
	)


## Ground hazards a launched core can clear by height (phase gates span the
## whole shaft and still apply in the air).
static func is_vaultable(type_id: int) -> bool:
	return (
		type_id == EntityType.BARRIER
		or type_id == EntityType.SLIDER
		or type_id == EntityType.PULSE_GATE
		or type_id == EntityType.BREAKABLE
	)


## Forward-speed factor of gravity [param g] (1.0 outside gravity wells).
static func gravity_speed_factor(g: float) -> float:
	return 1.0 + GRAV_SPEED_K * (g - 1.0)


## Hop-time factor of gravity [param g]: heavier gravity snaps hops quicker.
static func gravity_hop_factor(g: float) -> float:
	return clampf(1.0 - GRAV_HOP_K * (g - 1.0), GRAV_HOP_SCALE_MIN, GRAV_HOP_SCALE_MAX)


## Upward launch speed of a core carrying [param plates] stacked plates.
static func launch_speed(plates: int) -> float:
	return LAUNCH_VY / (1.0 + MASS_PER_PLATE * float(plates))


static func lane_x(lane: int, lane_count: int) -> float:
	return (float(lane) - float(lane_count - 1) * 0.5) * LANE_WIDTH


## Smooth (C1) easing used for hops; pure arithmetic for cross-platform determinism.
static func smoothstep01(t: float) -> float:
	var c: float = clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


## Positive modulo without relying on transcendental functions.
static func wrap01(u: float) -> float:
	return u - floorf(u)


## Smoothed triangle wave in [0,1] with period 1 — used by sliders instead of cos()
## so every platform computes bit-identical positions.
static func ping_pong01(u: float) -> float:
	var f: float = wrap01(u)
	var tri: float = 1.0 - absf(2.0 * f - 1.0)
	return tri * tri * (3.0 - 2.0 * tri)


static func combo_multiplier(combo: int) -> float:
	var steps: int = combo / COMBO_STEP
	return minf(1.0 + float(steps) * COMBO_MULT_STEP, COMBO_MULT_MAX)
