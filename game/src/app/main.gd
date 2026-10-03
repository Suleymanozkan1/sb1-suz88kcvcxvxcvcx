extends Node
## App root (bootstrap). Owns the persistent gameplay session + view so restarts
## never reload scenes; the UI layer and flow controller are attached here.

var catalog: WorldCatalog
var repo: LevelRepository
var session: GameplaySession
var view: GameplayView
var _title: Label
var _score: Label
var _attract: bool = true
var _level_id: String = "w01_l01"


func _ready() -> void:
	catalog = WorldCatalog.load_default()
	repo = LevelRepository.new(catalog)
	view = GameplayView.new()
	add_child(view)
	session = GameplaySession.new()
	add_child(session)
	view.bind(session)
	session.run_ended.connect(_on_run_ended)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_title = Label.new()
	_title.text = "FLUX DROP\n\nTAP TO PLAY"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_title.position = Vector2(-200, 180)
	_title.size = Vector2(400, 200)
	_title.add_theme_font_size_override("font_size", 48)
	layer.add_child(_title)
	_score = Label.new()
	_score.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_score.position = Vector2(-100, 40)
	_score.size = Vector2(200, 60)
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.add_theme_font_size_override("font_size", 40)
	layer.add_child(_score)
	_play(_level_id, true)


func _play(level_id: String, attract: bool) -> void:
	var data: Dictionary = repo.load_level(level_id)
	if data.is_empty():
		GameLog.error("main", "cannot load %s" % level_id)
		return
	_attract = attract
	_level_id = level_id
	session.load_level(data)
	session.autopilot = PackedInt32Array()
	if attract:
		for t: Variant in (data["solution"] as Dictionary)["taps"] as Array:
			session.autopilot.append(int(t))
	view.apply_world(WorldTheme.from_world(catalog.world(str(data["world"]))))
	view.setup_level()
	session.begin(0.8)
	_title.visible = attract


func _process(_delta: float) -> void:
	if session.sim != null:
		_score.text = str(session.sim.score)


func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = (
		(event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
		or (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo)
	)
	if not pressed:
		return
	if _attract:
		_play("w01_l01", false)
	else:
		session.request_tap()
	get_viewport().set_input_as_handled()


func _on_run_ended(result: RunResult) -> void:
	if _attract:
		_play(_level_id, true)
		return
	await get_tree().create_timer(0.6).timeout
	if result.completed:
		var next: String = repo.next_level_id(_level_id)
		_play(next if not next.is_empty() else _level_id, false)
	else:
		session.restart()
		view.reset_for_run(false)
