class_name CameraRig
extends Node3D
## Follow camera with trauma-based shake, directional impulses, FOV punch and a
## level-start reveal sweep. Shake is scaled by the accessibility setting.

const BASE_OFFSET: Vector3 = Vector3(0.0, 3.4, 6.2)
const LOOK_AHEAD: float = 8.0
const LOOK_HEIGHT: float = 0.1
const BASE_FOV: float = 64.0
const TRAUMA_DECAY: float = 2.4
const MAX_SHAKE: float = 0.16
const IMPULSE_DAMPING: float = 9.0
const IMPULSE_STIFFNESS: float = 140.0
const SPRING_STEP: float = 1.0 / 120.0
const MAX_SPRING_DELTA: float = 0.1
## How much the camera rises with a launched core (and how much its aim does).
const LIFT_FOLLOW: float = 0.4
const LIFT_LOOK: float = 0.25
## FOV kicks fade at this many degrees per second.
const FOV_PUNCH_DECAY: float = 30.0
## Lane follow: the camera slides a share of the core's x, eased at this rate.
const LATERAL_FOLLOW: float = 0.35
const LATERAL_RATE: float = 6.0
## Its aim follows a share of that slide (the core drifts in frame, the horizon
## stays calm).
const LOOK_LATERAL: float = 0.6
## Level-start reveal: the sweep (1 → 0) runs at this rate per second on an
## ease-in curve, starting this much higher and further back (world units) and
## wider (degrees of FOV).
const REVEAL_SPEED: float = 1.3
const REVEAL_EASE: float = 2.2
const REVEAL_RISE: float = 6.0
const REVEAL_PULL_BACK: float = 9.0
const REVEAL_FOV: float = 8.0
## Shake noise: two sine waves per axis at unrelated rates (radians per second),
## the second at SHAKE_OVERTONE of the first's amplitude, so it never repeats
## visibly.
const SHAKE_RATE_X: float = 47.0
const SHAKE_RATE_X2: float = 31.0
const SHAKE_RATE_Y: float = 53.0
const SHAKE_RATE_Y2: float = 23.0
const SHAKE_OVERTONE: float = 0.5
## The aim shakes at this share of the position, so the frame jolts rather
## than swings.
const SHAKE_ON_AIM: float = 0.5
## Roll (degrees) per unit of lateral lean impulse.
const ROLL_PER_IMPULSE: float = 3.0

var camera: Camera3D
var shake_scale: float = 1.0
var trauma: float = 0.0
var reveal: float = 0.0
var _impulse: Vector3 = Vector3.ZERO
var _impulse_vel: Vector3 = Vector3.ZERO
var _fov_punch: float = 0.0
var _lateral: float = 0.0
var _noise_t: float = 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = BASE_FOV
	camera.near = 0.1
	camera.far = 220.0
	camera.current = true
	add_child(camera)


## Orientation of the camera at rest (no lean, shake, reveal or lane follow):
## the frame the sky is laid out in.
static func rest_basis() -> Basis:
	return Basis.looking_at(Vector3(0.0, LOOK_HEIGHT, -LOOK_AHEAD) - BASE_OFFSET, Vector3.UP)


## Tangents of the half field of view (x across, y up) for [param aspect].
func tan_half_fov(aspect: float) -> Vector2:
	var tv: float = tan(deg_to_rad(camera.fov) * 0.5)
	return Vector2(tv * maxf(aspect, 0.01), tv)


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func impulse(direction: Vector3) -> void:
	_impulse_vel += direction


func fov_punch(amount: float) -> void:
	_fov_punch = maxf(_fov_punch, amount)


## Starts the camera reveal (1 → 0) used when a level begins.
func start_reveal(strength: float = 1.0) -> void:
	reveal = strength


## [param lift]: height of a launched core above its resting line (0 on the floor).
func follow(core_pos: Vector3, delta: float, lift: float = 0.0) -> void:
	_noise_t += delta
	# Spring back impulses in fixed sub-steps (stable on slow frames).
	var remaining: float = minf(delta, MAX_SPRING_DELTA)
	while remaining > 0.0:
		var h: float = minf(remaining, SPRING_STEP)
		_impulse_vel += (-_impulse * IMPULSE_STIFFNESS - _impulse_vel * IMPULSE_DAMPING * 2.0) * h
		_impulse += _impulse_vel * h
		remaining -= h
	trauma = maxf(0.0, trauma - TRAUMA_DECAY * delta)
	_fov_punch = move_toward(_fov_punch, 0.0, delta * FOV_PUNCH_DECAY)
	reveal = move_toward(reveal, 0.0, delta * REVEAL_SPEED)
	_lateral = lerpf(_lateral, core_pos.x * LATERAL_FOLLOW, 1.0 - exp(-LATERAL_RATE * delta))
	var r: float = ease(reveal, REVEAL_EASE)
	var offset: Vector3 = BASE_OFFSET + Vector3(0.0, REVEAL_RISE * r, REVEAL_PULL_BACK * r)
	var target: Vector3 = Vector3(_lateral, lift * LIFT_FOLLOW, core_pos.z)
	var shake: float = trauma * trauma * MAX_SHAKE * shake_scale
	var shake_x: float = sin(_noise_t * SHAKE_RATE_X) + sin(_noise_t * SHAKE_RATE_X2) * SHAKE_OVERTONE
	var shake_y: float = cos(_noise_t * SHAKE_RATE_Y) + sin(_noise_t * SHAKE_RATE_Y2) * SHAKE_OVERTONE
	var shake_v: Vector3 = Vector3(shake_x, shake_y, 0.0) * shake
	global_position = target + offset + _impulse * shake_scale + shake_v
	var look_y: float = LOOK_HEIGHT + lift * LIFT_LOOK
	var aim: Vector3 = Vector3(_lateral * LOOK_LATERAL, look_y, core_pos.z - LOOK_AHEAD)
	camera.look_at(aim + shake_v * SHAKE_ON_AIM, Vector3.UP)
	camera.rotate_object_local(Vector3.FORWARD, deg_to_rad(-_impulse.x * ROLL_PER_IMPULSE * shake_scale))
	camera.fov = BASE_FOV + (_fov_punch + REVEAL_FOV * r) * shake_scale


func reset_state() -> void:
	trauma = 0.0
	_impulse = Vector3.ZERO
	_impulse_vel = Vector3.ZERO
	_fov_punch = 0.0
	_lateral = 0.0
