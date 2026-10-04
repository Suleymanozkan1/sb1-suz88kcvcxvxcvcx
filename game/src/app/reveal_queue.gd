class_name RevealQueue
extends Node
## Reveals (level-ups, unlocks, achievements, mission, chest and doubled
## rewards) waiting to be shown one at a time on the reward overlay, each with
## its own sound cue. The screen underneath stays; when the last reveal closes
## the state machine returns to the state it came from. Reveals celebrate on a
## cleared result; otherwise they wait for the next calm moment (the menu), so
## nothing ever covers PLAY AGAIN or a revive still on offer.
##
## A child of [GameFlow]: a wait in progress ends with the app root.

## Reveals on a cleared result wait for its sequence (stars, count-up).
const AFTER_COMPLETE_DELAY: float = 2.2
## Cue for reveals that name none (achievements, missions, chests).
const DEFAULT_SOUND: String = "reward"

var _s: AppServices
var _router: ScreenRouter
var _fsm: GameStateMachine
## Returns true while a reveal may cover the screen (no attract run behind the
## menu, no revive ad showing).
var _calm: Callable
var _queue: Array[Dictionary] = []
var _return_state: GameStateMachine.State = GameStateMachine.State.MAIN_MENU


func _init(app: AppServices, screen_router: ScreenRouter, state_machine: GameStateMachine, calm: Callable) -> void:
	_s = app
	_router = screen_router
	_fsm = state_machine
	_calm = calm


## Queues one reveal payload (the shape [method RewardOverlay.enter] takes).
func add(reveal: Dictionary) -> void:
	_queue.append(reveal)


## Queues [param list] in order (a run outcome's "reveals").
func add_all(list: Array) -> void:
	_queue.append_array(list)


## Queues the level-ups gained since the last call (run, mission or chest XP),
## so they are said now, not after the next run.
func add_level_ups() -> void:
	_queue.append_array(_s.take_level_up_reveals())


## Drops every waiting reveal (a revived run is applied, and revealed, when it ends).
func clear() -> void:
	_queue.clear()


func is_empty() -> bool:
	return _queue.is_empty()


## The reveals still waiting, oldest first (a copy).
func pending() -> Array[Dictionary]:
	return _queue.duplicate()


## Shows the first waiting reveal, if any (the menu is a calm moment).
func show_pending() -> void:
	if not _queue.is_empty():
		show_next()


## Shows the next reveal on top of the current screen, which stays underneath.
## With none left the overlay closes and the state machine returns to the
## state the first reveal covered.
func show_next() -> void:
	_router.close_overlay(&"reward")
	if _queue.is_empty():
		if _fsm.current == GameStateMachine.State.REWARD and _return_state != GameStateMachine.State.REWARD:
			_fsm.transition_to(_return_state)
		return
	var r: Dictionary = _queue.pop_front()
	if _fsm.current != GameStateMachine.State.REWARD:
		_return_state = _fsm.current
		_fsm.transition_to(GameStateMachine.State.REWARD)
	_router.push_overlay(&"reward", r)
	# Each reveal has its own cue: level-up, unlock (world, cosmetic) or reward.
	_s.audio.play_sfx(StringName(str(r.get("sound", DEFAULT_SOUND))))


## A result card is up: the waiting reveals celebrate a cleared run once its
## sequence has played. After a fail they wait for the menu; if the player
## moves on first they stay queued for the next calm moment.
func after_result(completed: bool) -> void:
	if _queue.is_empty() or not completed:
		return
	var host: StringName = _router.top_id()
	await get_tree().create_timer(AFTER_COMPLETE_DELAY).timeout
	# Never over a pending revive: the revived run must return to PLAYING.
	if _router.top_id() == host and bool(_calm.call()):
		show_next()
