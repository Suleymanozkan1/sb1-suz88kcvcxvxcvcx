class_name Palette
extends RefCounted
## Global colour roles (docs/ART_DIRECTION.md §3). Gameplay roles are identical
## in every world; worlds only change environment colours, light and materials.

const PRIMARY: Color = Color("#46e6f0")
const SECONDARY: Color = Color("#f0468c")
const ACCENT: Color = Color("#f5c451")
const WARNING: Color = Color("#ff6a3d")
const SUCCESS: Color = Color("#5be3a1")
const FAILURE: Color = Color("#e5484d")

const INK: Color = Color("#0b0e14")
const GRAPHITE: Color = Color("#1a1f29")
const SLATE: Color = Color("#2a3140")
const FOG: Color = Color("#8a93a6")
const BONE: Color = Color("#e8ecf2")

## Form tints are functional (they tell the tap meaning together with shape).
const FORM_HOP: Color = PRIMARY
const FORM_DASH: Color = Color("#fff3d6")
const FORM_SURGE_LIGHT: Color = Color("#bff6fa")
const FORM_SURGE_HEAVY: Color = Color("#7c6cf0")
const PHASE: Array[Color] = [PRIMARY, SECONDARY]

## Breakable glass tint: WARNING family, lighter and cooler so "destructible"
## reads differently from a solid barrier.
const GLASS_TINT: Color = Color("#ffb38f")

## HDR multipliers for energy (only energy may exceed 1.0 and bloom).
const ENERGY_CORE: float = 2.4
const ENERGY_SPARK: float = 1.6
const ENERGY_MEMBRANE: float = 1.15
const ENERGY_TRAIL: float = 0.7


static func form_color(form: int, phase: int, heavy: bool) -> Color:
	match form:
		SimConst.Form.PHASE:
			return PHASE[clampi(phase, 0, 1)]
		SimConst.Form.DASH:
			return FORM_DASH
		SimConst.Form.SURGE:
			return FORM_SURGE_HEAVY if heavy else FORM_SURGE_LIGHT
	return FORM_HOP


static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)
