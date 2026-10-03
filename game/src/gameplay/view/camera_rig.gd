class_name CameraRig
extends Node3D
## Follow camera with trauma-based shake, directional impulses, FOV punch and a
## level-start reveal sweep. Shake is scaled by the accessibility setting.

const BASE_OFFSET: Vector3 = Vector3(0.0, 3.4, 6.2)
const LOOK_AHEAD: float = 8.0
const LOOK_HEIGHT: float = 0.1
const BASE_FOV: float = 64.0
const TRAUMA_DECAY: float = 2.4
const MAX_SHAKE: float = 0.22
const IMPULSE_DAMPING: float = 9.0
const IMPULSE_STIFFNESS: float = 140.0

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


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func impulse(direction: Vector3) -> void:
	_impulse_vel += direction


func fov_punch(amount: float) -> void:
	_fov_punch = maxf(_fov_punch, amount)


## Starts the camera reveal (1 → 0) used when a level begins.
func start_reveal(strength: float = 1.0) -> void:
	reveal = strength


func follow(core_pos: Vector3, delta: float) -> void:
	_noise_t += delta
	# Spring back impulses (critically damped-ish).
	_impulse_vel += (-_impulse * IMPULSE_STIFFNESS - _impulse_vel * IMPULSE_DAMPING * 2.0) * delta
	_impulse += _impulse_vel * delta
	trauma = maxf(0.0, trauma - TRAUMA_DECAY * delta)
	_fov_punch = move_toward(_fov_punch, 0.0, delta * 30.0)
	reveal = move_toward(reveal, 0.0, delta * 1.3)
	_lateral = lerpf(_lateral, core_pos.x * 0.35, 1.0 - exp(-6.0 * delta))
	var r: float = ease(reveal, 2.2)
	var offset: Vector3 = BASE_OFFSET + Vector3(0.0, 6.0 * r, 9.0 * r)
	var target: Vector3 = Vector3(_lateral, 0.0, core_pos.z)
	var shake: float = trauma * trauma * MAX_SHAKE * shake_scale
	var shake_v: Vector3 = Vector3(
		sin(_noise_t * 47.0) + sin(_noise_t * 31.0) * 0.5,
		cos(_noise_t * 53.0) + sin(_noise_t * 23.0) * 0.5,
		0.0
	) * shake
	global_position = target + offset + _impulse * shake_scale + shake_v
	camera.look_at(Vector3(_lateral * 0.6, LOOK_HEIGHT, core_pos.z - LOOK_AHEAD) + shake_v * 0.5, Vector3.UP)
	camera.rotate_object_local(Vector3.FORWARD, deg_to_rad(-_impulse.x * 6.0 * shake_scale))
	camera.fov = BASE_FOV + _fov_punch + 8.0 * r


func reset_state() -> void:
	trauma = 0.0
	_impulse = Vector3.ZERO
	_impulse_vel = Vector3.ZERO
	_fov_punch = 0.0
	_lateral = 0.0
