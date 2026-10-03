extends TestCase
## GameStateMachine: every brief state exists, the transition table allows the
## app's real paths and rejects shortcuts, and changes are signalled.

const BRIEF_STATES: PackedStringArray = [
	"BOOT", "MAIN_MENU", "WORLD_SELECT", "LEVEL_SELECT", "COUNTDOWN", "PLAYING", "PAUSED", "FAILED",
	"COMPLETE", "REWARD", "SHOP", "COLLECTION", "SETTINGS", "DAILY", "ENDLESS"
]


func _walk(fsm: GameStateMachine, path: Array) -> bool:
	for st: Variant in path:
		if not fsm.transition_to(st as GameStateMachine.State):
			return false
	return true


func test_every_state_of_the_brief_exists() -> void:
	var names: Array = GameStateMachine.State.keys()
	for n: String in BRIEF_STATES:
		assert_has(names, n)


func test_campaign_endless_and_menu_paths() -> void:
	var st: Dictionary = GameStateMachine.State
	var fsm: GameStateMachine = GameStateMachine.new()
	var menu_to_play: Array = [st.MAIN_MENU, st.WORLD_SELECT, st.LEVEL_SELECT, st.COUNTDOWN, st.PLAYING]
	assert_true(_walk(fsm, menu_to_play + [st.PAUSED, st.PLAYING]), "campaign start, pause, resume")
	assert_true(_walk(fsm, [st.COMPLETE, st.REWARD, st.MAIN_MENU]), "clear -> reveal -> menu")
	assert_true(_walk(fsm, [st.ENDLESS, st.COUNTDOWN, st.PLAYING, st.FAILED, st.COUNTDOWN]), "endless and retry")
	assert_true(_walk(fsm, [st.PLAYING, st.FAILED, st.MAIN_MENU, st.SHOP, st.COLLECTION, st.SETTINGS, st.DAILY]))


func test_shortcuts_are_rejected_and_signalled() -> void:
	var st: Dictionary = GameStateMachine.State
	var fsm: GameStateMachine = GameStateMachine.new()
	var changes: Array[int] = []
	var rejected: Array[int] = []
	fsm.state_changed.connect(func(_f: int, to: int, _p: Dictionary) -> void: changes.append(to))
	fsm.transition_rejected.connect(func(_f: int, to: int) -> void: rejected.append(to))
	assert_true(fsm.transition_to(st.MAIN_MENU))
	assert_false(fsm.transition_to(st.PLAYING), "no play without a countdown")
	assert_false(fsm.transition_to(st.COMPLETE), "no result without a run")
	assert_eq(fsm.current, st.MAIN_MENU)
	assert_eq(changes, [st.MAIN_MENU] as Array[int])
	assert_eq(rejected.size(), 2)
	assert_true(fsm.transition_to(st.COUNTDOWN))
	assert_true(fsm.is_gameplay(), "countdown counts as gameplay")
