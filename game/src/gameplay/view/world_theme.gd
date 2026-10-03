class_name WorldTheme
extends RefCounted
## Typed view of a world's environment identity (docs/ART_DIRECTION.md §3, §6, §7).
## Gameplay colours are NOT here: they are global roles in [Palette].

const RIB_PROFILES: PackedStringArray = ["gate", "arch", "hex", "monolith", "lattice", "facet"]

var id: String = "neon_core"
var display_name: String = "Neon Core"
var index: int = 1
var story: String = ""
var sky_top: Color = Color("#0e1320")
var sky_bottom: Color = Color("#1b2436")
var fog: Color = Color("#151c2a")
var floor_color: Color = Color("#121823")
var lane_color: Color = Color("#19202d")
var structure: Color = Color("#2b3444")
var key_color: Color = Color("#c9d6ea")
var key_energy: float = 1.1
var key_pitch: float = -52.0
var key_yaw: float = 18.0
var ambient: Color = Color("#2a3446")
var ambient_energy: float = 0.5
var sink: Color = Palette.PRIMARY
var story_accent: Color = Color("#3a5a7a")
var rib_profile: String = "gate"
var rib_material: String = "anodised"
var atmosphere: String = "dust"
var atmosphere_count: int = 16
var silhouette: String = "turbine"
var caustics: bool = false
var bpm: float = 120.0
var boss_name: String = ""
## High-key world (light background): UI and hazard bodies adapt contrast.
var bright: bool = false


static func from_world(world: Dictionary) -> WorldTheme:
	var t: WorldTheme = WorldTheme.new()
	if world.is_empty():
		return t
	t.id = str(world.get("id", t.id))
	t.display_name = str(world.get("name", t.display_name))
	t.index = int(world.get("index", 1))
	var a: Dictionary = world.get("art", {}) as Dictionary
	t.story = str(a.get("story", ""))
	t.sky_top = _c(a, "sky_top", t.sky_top)
	t.sky_bottom = _c(a, "sky_bottom", t.sky_bottom)
	t.fog = _c(a, "fog", t.fog)
	t.floor_color = _c(a, "floor", t.floor_color)
	t.lane_color = _c(a, "lane", t.lane_color)
	t.structure = _c(a, "structure", t.structure)
	t.sink = _c(a, "sink", t.sink)
	t.story_accent = _c(a, "story_accent", t.story_accent)
	var key: Dictionary = a.get("key_light", {}) as Dictionary
	t.key_color = _c(key, "color", t.key_color)
	t.key_energy = float(key.get("energy", t.key_energy))
	t.key_pitch = float(key.get("pitch", t.key_pitch))
	t.key_yaw = float(key.get("yaw", t.key_yaw))
	var amb: Dictionary = a.get("ambient", {}) as Dictionary
	t.ambient = _c(amb, "color", t.ambient)
	t.ambient_energy = float(amb.get("energy", t.ambient_energy))
	var profile: String = str(a.get("rib_profile", t.rib_profile))
	t.rib_profile = profile if RIB_PROFILES.has(profile) else "gate"
	t.rib_material = str(a.get("rib_material", t.rib_material))
	var atmo: Dictionary = a.get("atmosphere", {}) as Dictionary
	t.atmosphere = str(atmo.get("type", t.atmosphere))
	t.atmosphere_count = clampi(int(atmo.get("count", t.atmosphere_count)), 0, 24)
	t.silhouette = str(a.get("silhouette", t.silhouette))
	t.caustics = bool(a.get("caustics", false))
	t.bpm = float((world.get("music", {}) as Dictionary).get("bpm", 120))
	t.boss_name = str((world.get("boss", {}) as Dictionary).get("name", ""))
	t.bright = t.sky_bottom.get_luminance() > 0.5
	return t


static func _c(dict: Dictionary, key: String, fallback: Color) -> Color:
	var v: String = str(dict.get(key, ""))
	if v.is_empty() or not Color.html_is_valid(v):
		return fallback
	return Color(v)
