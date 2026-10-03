class_name ScreenRouter
extends Control
## Owns every UI screen: one base screen at a time plus a stack of overlays.
## Screens are built lazily on first use, then reused (no per-visit allocation).
## Android back / Escape goes to the top-most screen's handle_back().

signal screen_changed(screen_id: StringName)
signal back_unhandled

var reduce_motion: bool = false
var current_id: StringName = &""
var _screens: Dictionary = {}
var _built: Dictionary = {}
var _overlays: Array[StringName] = []


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func register(id: StringName, screen: UiScreen) -> void:
	_screens[id] = screen
	screen.visible = false
	add_child(screen)


func screen(id: StringName) -> UiScreen:
	return _screens.get(id, null) as UiScreen


func has_screen(id: StringName) -> bool:
	return _screens.has(id)


func _ensure_built(id: StringName) -> UiScreen:
	var s: UiScreen = screen(id)
	if s != null and not _built.has(id):
		s.build()
		_built[id] = true
	return s


## Replaces the base screen (closes all overlays).
func show_screen(id: StringName, payload: Dictionary = {}) -> void:
	var next: UiScreen = _ensure_built(id)
	if next == null:
		GameLog.error("router", "unknown screen %s" % id)
		return
	close_overlays()
	if current_id != &"" and current_id != id:
		var prev: UiScreen = screen(current_id)
		prev.exit()
		prev.transition_out(reduce_motion)
	current_id = id
	move_child(next, get_child_count() - 1)
	next.enter(payload)
	next.transition_in(reduce_motion)
	screen_changed.emit(id)


## Hides the base screen entirely (e.g. while playing with only the HUD).
func clear_screen() -> void:
	close_overlays()
	if current_id != &"":
		var prev: UiScreen = screen(current_id)
		prev.exit()
		prev.transition_out(reduce_motion)
	current_id = &""


func push_overlay(id: StringName, payload: Dictionary = {}) -> void:
	var o: UiScreen = _ensure_built(id)
	if o == null:
		GameLog.error("router", "unknown overlay %s" % id)
		return
	_overlays.erase(id)
	_overlays.append(id)
	move_child(o, get_child_count() - 1)
	o.enter(payload)
	o.transition_in(reduce_motion)


func pop_overlay() -> void:
	if _overlays.is_empty():
		return
	var id: StringName = _overlays.pop_back()
	var o: UiScreen = screen(id)
	o.exit()
	o.transition_out(reduce_motion)


func close_overlay(id: StringName) -> void:
	if not _overlays.has(id):
		return
	_overlays.erase(id)
	var o: UiScreen = screen(id)
	o.exit()
	o.transition_out(reduce_motion)


func close_overlays() -> void:
	while not _overlays.is_empty():
		pop_overlay()


func top_id() -> StringName:
	return _overlays.back() if not _overlays.is_empty() else current_id


func has_overlay(id: StringName) -> bool:
	return _overlays.has(id)


## Routes a back request to the top-most screen. Returns true when handled.
func back() -> bool:
	var id: StringName = top_id()
	if id != &"" and screen(id).handle_back():
		return true
	back_unhandled.emit()
	return false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		back()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back()
