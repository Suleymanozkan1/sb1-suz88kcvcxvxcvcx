class_name ViewSync
extends Node
## Keeps the gameplay view (and the screens' motion) in step with the player's
## settings, worn cosmetics and quality preset as they change, lets the track
## breathe with the music, and dresses the view for each world: entering a
## different one passes through a short ink veil.
##
## A child of [GameFlow]; the veil sits between the 3D view and the UI.

## Seconds the veil takes to lift (shorter with reduce motion).
const WORLD_FADE: float = 0.6
## Canvas layer of the veil: above the 3D view, below the UI.
const VEIL_LAYER: int = 5

var _s: AppServices
var _view: GameplayView
var _router: ScreenRouter
var _veil: ColorRect
var _veil_tween: Tween
var _shown_world: String = ""


func _init(app: AppServices, gameplay_view: GameplayView, screen_router: ScreenRouter) -> void:
	_s = app
	_view = gameplay_view
	_router = screen_router


func _ready() -> void:
	var veil_layer: CanvasLayer = CanvasLayer.new()
	veil_layer.layer = VEIL_LAYER
	add_child(veil_layer)
	_veil = ColorRect.new()
	_veil.color = Palette.INK
	_veil.modulate.a = 0.0
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil_layer.add_child(_veil)
	apply_settings()
	_s.bus.cosmetic_equipped.connect(func(_c: StringName, _id: String) -> void: apply_cosmetics())
	_s.bus.settings_changed.connect(func(_k: StringName, _v: Variant) -> void: apply_settings())
	_s.bus.quality_changed.connect(func(_p: StringName, _a: bool) -> void: apply_quality())
	# The track breathes with the music: a stronger pulse on each bar's downbeat.
	_s.audio.beat.connect(func(i: int) -> void: _view.music_beat(1.0 if i % 4 == 0 else 0.45))
	apply_cosmetics()
	apply_quality()


## Dresses the view for [param world_id] with the worn cosmetics. With
## [param veiled] (never on the attract run), entering a different world than
## the one shown passes through the veil.
func show_world(world_id: String, veiled: bool) -> void:
	if veiled and not _shown_world.is_empty() and world_id != _shown_world:
		_lift_veil()
	_shown_world = world_id
	_view.apply_world(WorldTheme.from_world(_s.catalog.world(world_id)))
	apply_cosmetics()


func apply_cosmetics() -> void:
	_view.apply_cosmetics(_s.cosmetics.core_skin_params(), _s.cosmetics.trail_params())
	# Default items keep the art direction's own palette (no override).
	_view.apply_effect_cosmetics(
		Presenters.worn(_s, CosmeticCatalog.PARTICLE),
		Presenters.worn(_s, CosmeticCatalog.EFFECT),
		Presenters.worn(_s, CosmeticCatalog.BACKGROUND)
	)
	if UiTheme.apply_accent(Presenters.worn(_s, CosmeticCatalog.THEME)):
		# Buttons keep copies of the theme's boxes: rebuild screens on next show.
		_router.relocalize()


func apply_quality() -> void:
	var p: Dictionary = _s.quality.params()
	_view.set_quality(
		bool(p.get("post_fx", true)),
		float(p.get("particle_scale", 1.0)),
		int(p.get("trail_points", 18)),
		bool(p.get("dynamic_light", true)),
		bool(p.get("shadows", true)),
		bool(p.get("glow", true)),
		bool(p.get("ambient_particles", true)),
		bool(p.get("reflections", false)),
		bool(p.get("fine_glass", true))
	)
	_view.set_quality_extras(bool(p.get("cinematic", false)), int(p.get("shadow_quality", 1)))


func apply_settings() -> void:
	var reduce: bool = _s.settings.get_bool("reduce_motion")
	_router.reduce_motion = reduce
	_view.reduce_motion = reduce
	_view.core_view.reduce_motion = reduce
	_view.set_colorblind(_s.settings.get_bool("colorblind"))
	(_router.screen(&"reward") as RewardOverlay).reduce_motion = reduce


## The old world is gone behind ink, and the new one rises out of it (calm,
## ART_DIRECTION §8; shorter with reduce motion).
func _lift_veil() -> void:
	if _veil_tween != null:
		_veil_tween.kill()
	_veil.modulate.a = 1.0
	_veil_tween = create_tween()
	var seconds: float = WORLD_FADE * (0.4 if _router.reduce_motion else 1.0)
	_veil_tween.tween_property(_veil, "modulate:a", 0.0, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
