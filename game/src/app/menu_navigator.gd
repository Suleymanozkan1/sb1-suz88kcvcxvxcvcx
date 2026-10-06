class_name MenuNavigator
extends RefCounted
## Moves between the menu screens (worlds, levels, modes, daily and the main
## menu's tabs: progress, shop, collection, settings), each with its payload
## from [Presenters] and its state in the state machine, and turns the
## player's mode and level picks into run requests. Settings opens as a screen
## from the menu or over the pause card, remembers which, and is rebuilt in
## place when the language changes. The main menu and the runs themselves
## belong to [GameFlow].

## A campaign level was picked, to be played with [param mode_id]'s rules.
signal campaign_requested(level_id: String, mode_id: StringName)
## A mode that is not played level by level was picked.
signal run_requested(mode_id: StringName)
## Settings opened from the main menu was closed.
signal home_requested

var _s: AppServices
var _router: ScreenRouter
var _fsm: GameStateMachine
var _meta: MetaActions
## Rules for the next campaign pick (a "campaign_pick" mode), or CLASSIC.
var _pick_mode: StringName = &""
var _settings_return: StringName = &""


func _init(app: AppServices, screen_router: ScreenRouter, state_machine: GameStateMachine, meta: MetaActions) -> void:
	_s = app
	_router = screen_router
	_fsm = state_machine
	_meta = meta


## The world map for a plain campaign pick (CLASSIC rules).
func show_campaign() -> void:
	_pick_mode = &""
	show_worlds()


func show_worlds() -> void:
	_go(GameStateMachine.State.WORLD_SELECT)
	_router.show_screen(&"worlds", Presenters.worlds(_s))


func show_levels(world_id: String) -> void:
	_s.audio.prefetch_music(world_id)
	_go(GameStateMachine.State.LEVEL_SELECT)
	_router.show_screen(&"levels", Presenters.level_grid(_s, world_id))


func show_modes() -> void:
	_go(GameStateMachine.State.MODES)
	_router.show_screen(&"modes", Presenters.modes(_s))


func show_daily() -> void:
	_s.missions.refresh()
	_go(GameStateMachine.State.DAILY)
	_router.show_screen(&"daily", Presenters.daily(_s))
	var daily_status: Dictionary = _s.daily.status()
	_s.analytics.track(
		&"daily_started",
		{"date_key": str(daily_status.get("date_key", "")), "streak": int(daily_status.get("streak", 0))}
	)


## One of the main menu's tabs: progress (with the first board), shop,
## collection or settings.
func show_tab(tab: StringName) -> void:
	match tab:
		&"progress":
			_go(GameStateMachine.State.PROGRESS)
			_router.show_screen(&"progress", Presenters.progress(_s, "overview", {}))
			_meta.load_board(Presenters.board_ids(_s)[0])
		&"shop":
			_go(GameStateMachine.State.SHOP)
			_router.show_screen(&"shop", Presenters.cosmetics(_s, &"shop"))
			_s.analytics.track(&"shop_opened", {"source": "menu", "tab": "shop"})
		&"collection":
			_go(GameStateMachine.State.COLLECTION)
			_router.show_screen(&"collection", Presenters.cosmetics(_s, &"collection"))
		&"settings":
			_settings_return = &""
			_go(GameStateMachine.State.SETTINGS)
			_router.show_screen(&"settings", _meta.settings_payload())


## A mode picked on the Modes screen: some pick a level first, the daily has
## its own screen, the rest start a run.
func select_mode(mode_id: StringName) -> void:
	match _s.modes.source(mode_id):
		"campaign_pick":
			_pick_mode = mode_id
			show_worlds()
		"daily":
			show_daily()
		"campaign":
			campaign_requested.emit(_s.progression.next_level_to_play(), mode_id)
		_:
			run_requested.emit(mode_id)


func select_level(level_id: String) -> void:
	campaign_requested.emit(level_id, _pick_mode if _pick_mode != &"" else &"classic")


## Settings over the pause card; closing it returns to the paused run.
func open_settings_over_pause() -> void:
	_settings_return = &"pause"
	_router.push_overlay(&"settings", _meta.settings_payload())


func close_settings() -> void:
	if _settings_return == &"pause":
		_settings_return = &""
		_router.close_overlay(&"settings")
		return
	home_requested.emit()


## The language changed (from Settings): every screen is rebuilt in the new
## language on its next show, and Settings itself is rebuilt in place.
func relocalize() -> void:
	_router.relocalize()
	if _router.top_id() != &"settings":
		return
	if _settings_return == &"pause":
		_router.push_overlay(&"settings", _meta.settings_payload())
	else:
		_router.show_screen(&"settings", _meta.settings_payload())


func _go(state: GameStateMachine.State) -> void:
	if _fsm.current != state:
		_fsm.transition_to(state)
