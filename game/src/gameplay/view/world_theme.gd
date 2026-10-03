class_name WorldTheme
extends RefCounted
## Typed view of a world's visual/audio identity (palette, lighting, materials).

const MATERIAL_STYLES: Dictionary = {
	"glass": 0,
	"crystal": 1,
	"magma": 2,
	"porcelain": 3,
	"coral": 4,
	"circuit": 5,
	"ice": 6,
	"sandstone": 7,
	"void": 8,
	"candy": 9,
}

var id: String = "neon_core"
var display_name: String = "Neon Core"
var index: int = 1
var sky_top: Color = Color("#05081a")
var sky_bottom: Color = Color("#0d1a4a")
var fog: Color = Color("#0a1236")
var primary: Color = Color("#3df5ff")
var secondary: Color = Color("#ff3dcb")
var accent: Color = Color("#ffe45c")
var hazard: Color = Color("#ff4d6d")
var floor_color: Color = Color("#0b1538")
var grid: Color = Color("#2a5cff")
var sun_color: Color = Color("#9fc4ff")
var sun_energy: float = 0.6
var ambient: Color = Color("#1a2a66")
var ambient_energy: float = 0.6
var glow: float = 0.9
var fog_density: float = 0.018
var hazard_style: int = 0
var ambient_particles: String = "dust"
var bpm: float = 120.0
var boss_name: String = ""
var bright: bool = false


static func from_world(world: Dictionary) -> WorldTheme:
	var t: WorldTheme = WorldTheme.new()
	if world.is_empty():
		return t
	t.id = str(world.get("id", t.id))
	t.display_name = str(world.get("name", t.display_name))
	t.index = int(world.get("index", 1))
	var p: Dictionary = world.get("palette", {}) as Dictionary
	t.sky_top = _c(p, "sky_top", t.sky_top)
	t.sky_bottom = _c(p, "sky_bottom", t.sky_bottom)
	t.fog = _c(p, "fog", t.fog)
	t.primary = _c(p, "primary", t.primary)
	t.secondary = _c(p, "secondary", t.secondary)
	t.accent = _c(p, "accent", t.accent)
	t.hazard = _c(p, "hazard", t.hazard)
	t.floor_color = _c(p, "floor", t.floor_color)
	t.grid = _c(p, "grid", t.grid)
	var l: Dictionary = world.get("lighting", {}) as Dictionary
	t.sun_color = _c(l, "sun_color", t.sun_color)
	t.sun_energy = float(l.get("sun_energy", t.sun_energy))
	t.ambient = _c(l, "ambient", t.ambient)
	t.ambient_energy = float(l.get("ambient_energy", t.ambient_energy))
	t.glow = float(l.get("glow", t.glow))
	t.fog_density = float(l.get("fog_density", t.fog_density))
	t.hazard_style = int(MATERIAL_STYLES.get(str(world.get("hazard_material", "glass")), 0))
	t.ambient_particles = str(world.get("ambient_particles", "dust"))
	t.bpm = float((world.get("music", {}) as Dictionary).get("bpm", 120))
	t.boss_name = str((world.get("boss", {}) as Dictionary).get("name", ""))
	# Bright worlds (e.g. Cloud Factory) need darker hazard bodies for contrast.
	t.bright = t.sky_bottom.get_luminance() > 0.5
	return t


static func _c(dict: Dictionary, key: String, fallback: Color) -> Color:
	var v: String = str(dict.get(key, ""))
	if v.is_empty() or not Color.html_is_valid(v):
		return fallback
	return Color(v)
