class_name AmbientMotes
extends RefCounted
## Ambient motes of a world's atmosphere (docs/ART_DIRECTION.md §7: decoration
## with a reason, such as dust in the key light, rising embers or bubbles, and
## at most 8 % opacity). [method configure] dresses the view's one
## CPUParticles3D for a world's `art.atmosphere` style; [GameplayView] places
## it and scales its amount with the quality preset.

## Decoration never exceeds 8 % opacity (§7).
const MAX_ALPHA: float = 0.08
## Every style starts from a slow upward drift of small soft dots through a box
## around the shaft ahead of the core.
const LIFETIME: float = 5.0
const BOX_EXTENTS: Vector3 = Vector3(5.5, 2.2, 18.0)
const SPREAD_DEGREES: float = 25.0
const SPEED_MIN: float = 0.08
const SPEED_MAX: float = 0.25
const SCALE_MIN: float = 0.6
const SIZE: float = 0.06
const ALPHA: float = 0.06
## Styles that read as points of light sit at the opacity cap.
const ALPHA_BRIGHT: float = MAX_ALPHA
## Embers: warm, rising on the heat.
const EMBER_COLOR: Color = Color("#ffb37a")
const EMBER_GRAVITY: Vector3 = Vector3(0, 0.35, 0)
## Bubbles: a little larger, rising.
const BUBBLE_GRAVITY: Vector3 = Vector3(0, 0.3, 0)
const BUBBLE_SIZE: float = 0.07
## Snow: falling.
const SNOW_GRAVITY: Vector3 = Vector3(0, -0.35, 0)
## Sand: blown sideways, barely sinking.
const SAND_GRAVITY: Vector3 = Vector3(0.6, -0.05, 0)
## Stars: streaming past the camera.
const STAR_COLOR: Color = Color("#c8c6e8")
const STAR_DIRECTION: Vector3 = Vector3(0, 0, 1)
const STAR_SPEED_MIN: float = 2.0
const STAR_SPEED_MAX: float = 3.0
## Puffs: large soft clouds, kept fainter.
const PUFF_SIZE: float = 0.4
const PUFF_ALPHA: float = 0.05
## Sprinkles: the world's story accent, lightened, falling.
const SPRINKLE_LIGHTEN: float = 0.4
const SPRINKLE_GRAVITY: Vector3 = Vector3(0, -0.25, 0)
## Glitter: crystal dust, tiny and nearly still, white with a hint of the key
## light, each mote catching the light in turn.
const GLITTER_KEY_TINT: float = 0.3
const GLITTER_SIZE: float = 0.035
const GLITTER_GRAVITY: Vector3 = Vector3(0, -0.04, 0)
## Spores: larger, soft, rising slowly on a sideways drift.
const SPORE_LIGHTEN: float = 0.35
const SPORE_SIZE: float = 0.09
const SPORE_DIRECTION: Vector3 = Vector3(0.35, 1.0, 0.0)
const SPORE_SPEED_MIN: float = 0.04
const SPORE_SPEED_MAX: float = 0.12
const SPORE_GRAVITY: Vector3 = Vector3(0.05, 0.08, 0)
const SPORE_ALPHA: float = 0.07
## Twinkle (glitter): alpha keys over a mote's life, dark, a flash, dark, a
## second fainter flash.
const TWINKLE_OFFSETS: PackedFloat32Array = [0.0, 0.2, 0.3, 0.55, 0.65, 0.8, 1.0]
const TWINKLE_DIM: float = 0.15
const TWINKLE_SECOND_FLASH: float = 0.7


## Sets up [param p] (lifetime, emission, motion and a soft-dot mesh) for
## [param theme]'s atmosphere style; the colour's alpha is capped at
## [constant MAX_ALPHA].
static func configure(p: CPUParticles3D, theme: WorldTheme) -> void:
	p.lifetime = LIFETIME
	p.preprocess = LIFETIME
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = BOX_EXTENTS
	p.direction = Vector3(0, 1, 0)
	p.spread = SPREAD_DEGREES
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = SPEED_MIN
	p.initial_velocity_max = SPEED_MAX
	p.scale_amount_min = SCALE_MIN
	p.scale_amount_max = 1.0
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(SIZE, SIZE)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	# Soft round mote (never a hard square sprite).
	mat.albedo_texture = ViewKit.soft_dot_texture()
	quad.material = mat
	p.mesh = quad
	var color: Color = theme.key_color
	var alpha: float = ALPHA
	match theme.atmosphere:
		"embers":
			color = EMBER_COLOR
			p.gravity = EMBER_GRAVITY
			alpha = ALPHA_BRIGHT
		"bubbles":
			color = theme.key_color
			p.gravity = BUBBLE_GRAVITY
			quad.size = Vector2(BUBBLE_SIZE, BUBBLE_SIZE)
		"snow":
			color = Color.WHITE
			p.gravity = SNOW_GRAVITY
			alpha = ALPHA_BRIGHT
		"sand":
			color = theme.key_color
			p.gravity = SAND_GRAVITY
		"stars":
			color = STAR_COLOR
			p.direction = STAR_DIRECTION
			p.initial_velocity_min = STAR_SPEED_MIN
			p.initial_velocity_max = STAR_SPEED_MAX
			alpha = ALPHA_BRIGHT
		"puffs":
			color = Color.WHITE
			quad.size = Vector2(PUFF_SIZE, PUFF_SIZE)
			alpha = PUFF_ALPHA
		"sprinkles":
			color = theme.story_accent.lightened(SPRINKLE_LIGHTEN)
			p.gravity = SPRINKLE_GRAVITY
			alpha = ALPHA_BRIGHT
		"glitter":
			color = Color.WHITE.lerp(theme.key_color, GLITTER_KEY_TINT)
			quad.size = Vector2(GLITTER_SIZE, GLITTER_SIZE)
			p.gravity = GLITTER_GRAVITY
			p.color_ramp = twinkle_ramp()
			alpha = ALPHA_BRIGHT
		"spores":
			color = theme.key_color.lightened(SPORE_LIGHTEN)
			quad.size = Vector2(SPORE_SIZE, SPORE_SIZE)
			p.direction = SPORE_DIRECTION
			p.initial_velocity_min = SPORE_SPEED_MIN
			p.initial_velocity_max = SPORE_SPEED_MAX
			p.gravity = SPORE_GRAVITY
			alpha = SPORE_ALPHA
	p.color = Palette.with_alpha(color, minf(alpha, MAX_ALPHA))


## Alpha over a mote's life: dark, a flash, dark, a second fainter flash.
static func twinkle_ramp() -> Gradient:
	var g: Gradient = Gradient.new()
	g.offsets = TWINKLE_OFFSETS
	var off: Color = Color(1, 1, 1, 0)
	var dim: Color = Color(1, 1, 1, TWINKLE_DIM)
	g.colors = PackedColorArray([off, dim, Color.WHITE, dim, Color(1, 1, 1, TWINKLE_SECOND_FLASH), dim, off])
	return g
