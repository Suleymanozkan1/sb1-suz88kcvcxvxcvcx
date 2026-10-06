class_name WingTrails
extends Node3D
## Vapour trails off the craft's wingtips (docs/ART_DIRECTION.md §9: their one
## job is speed, and they show the craft's span and banking): two hairline
## ribbons in near white, short and faint (below the bloom threshold, so the
## energy trail stays the bright one). Each form starts them at its own tips
## (CraftShapes.wingtips). High and Ultra only, off with reduce motion;
## [GameplayView] feeds them every frame.

const WIDTH: float = 0.012
const MAX_LENGTH: float = 1.3
const POINTS: int = 14
const SPACING: float = 0.12
const INTENSITY: float = 0.45
const HEAD: Color = Color(0.92, 0.96, 1.0, 0.55)
const TAIL: Color = Color(0.92, 0.96, 1.0, 0.0)

var ribbons: Array[TrailRibbon] = []
var allowed: bool = false
var _form: int = -1


func _init() -> void:
	for i: int in 2:
		var r: TrailRibbon = TrailRibbon.new()
		r.width = WIDTH
		r.max_length = MAX_LENGTH
		r.min_spacing = SPACING
		add_child(r)
		ribbons.append(r)


func _ready() -> void:
	for r: TrailRibbon in ribbons:
		r.set_length(POINTS)
		r.set_colors(HEAD, TAIL)
		r.set_intensity(INTENSITY)
	visible = allowed


## Quality and accessibility gate.
func set_allowed(value: bool) -> void:
	allowed = value
	visible = value
	if not value:
		clear()


func clear() -> void:
	for r: TrailRibbon in ribbons:
		r.clear_points()


## Per frame: extend both trails from [param body]'s wingtips for [param form]
## while [param active] (the run is on); a form change starts them afresh.
func follow(body: Node3D, form: int, camera: Camera3D, active: bool) -> void:
	if not allowed:
		return
	if form != _form or not active:
		_form = form
		clear()
		if not active:
			return
	var tips: Array[Vector3] = CraftShapes.wingtips(form)
	for i: int in ribbons.size():
		ribbons[i].push_point(body.global_transform * tips[i])
		ribbons[i].rebuild(camera)
