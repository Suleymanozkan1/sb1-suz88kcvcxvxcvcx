class_name GameStateMachine
extends RefCounted
## Table-driven application state machine.
##
## Every screen/flow change goes through [method transition_to], which rejects
## transitions not listed in [constant TRANSITIONS] (logged, never silent).

signal state_changed(from: State, to: State, payload: Dictionary)
signal transition_rejected(from: State, to: State)

enum State {
	BOOT,
	MAIN_MENU,
	WORLD_SELECT,
	LEVEL_SELECT,
	COUNTDOWN,
	PLAYING,
	PAUSED,
	FAILED,
	COMPLETE,
	REWARD,
	SHOP,
	COLLECTION,
	SETTINGS,
	DAILY,
	ENDLESS,
	PROGRESS,
}

const MENU_STATES: Array[State] = [
	State.MAIN_MENU,
	State.WORLD_SELECT,
	State.LEVEL_SELECT,
	State.SHOP,
	State.COLLECTION,
	State.SETTINGS,
	State.DAILY,
	State.PROGRESS,
]

## Allowed transitions: from -> [to...]. Menu screens can reach each other.
static var TRANSITIONS: Dictionary = _build_transitions()

var current: State = State.BOOT
var previous: State = State.BOOT
var payload: Dictionary = {}
var history: Array[State] = []


static func _build_transitions() -> Dictionary:
	var t: Dictionary = {}
	t[State.BOOT] = [State.MAIN_MENU]
	for s: State in MENU_STATES:
		var targets: Array = MENU_STATES.duplicate()
		targets.erase(s)
		targets.append(State.COUNTDOWN)
		targets.append(State.ENDLESS)
		t[s] = targets
	t[State.COUNTDOWN] = [State.PLAYING, State.MAIN_MENU, State.LEVEL_SELECT]
	t[State.ENDLESS] = [State.COUNTDOWN, State.MAIN_MENU]
	t[State.PLAYING] = [State.PAUSED, State.FAILED, State.COMPLETE, State.COUNTDOWN]
	t[State.PAUSED] = [State.PLAYING, State.COUNTDOWN, State.MAIN_MENU, State.LEVEL_SELECT, State.SETTINGS]
	t[State.FAILED] = [State.COUNTDOWN, State.PLAYING, State.MAIN_MENU, State.LEVEL_SELECT, State.REWARD, State.DAILY]
	t[State.COMPLETE] = [State.REWARD, State.COUNTDOWN, State.MAIN_MENU, State.LEVEL_SELECT]
	t[State.REWARD] = [State.COUNTDOWN, State.MAIN_MENU, State.LEVEL_SELECT, State.WORLD_SELECT, State.DAILY]
	return t


static func state_name(state: State) -> String:
	return State.keys()[state]


func can_transition(to: State) -> bool:
	var allowed: Array = TRANSITIONS.get(current, []) as Array
	return allowed.has(to)


## Returns true if the transition happened.
func transition_to(to: State, data: Dictionary = {}) -> bool:
	if to == current and to != State.COUNTDOWN:
		payload = data
		return true
	if not can_transition(to):
		GameLog.warn("fsm", "rejected %s -> %s" % [state_name(current), state_name(to)])
		transition_rejected.emit(current, to)
		return false
	previous = current
	current = to
	payload = data
	history.append(to)
	if history.size() > 32:
		history.remove_at(0)
	GameLog.debug("fsm", "%s -> %s" % [state_name(previous), state_name(current)])
	state_changed.emit(previous, current, data)
	return true


func is_in(state: State) -> bool:
	return current == state


func is_gameplay() -> bool:
	return current in [State.COUNTDOWN, State.PLAYING, State.PAUSED, State.FAILED, State.COMPLETE]
