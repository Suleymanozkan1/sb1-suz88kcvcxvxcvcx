class_name WorldTheme
extends RefCounted
## Typed view of a world's environment identity (docs/ART_DIRECTION.md §3, §6, §7).
## Gameplay colours are NOT here: they are global roles in [Palette].

## Environment colour caps (ART_DIRECTION §3).
const ENV_MAX_SATURATION: float = 0.45
const ENV_MAX_VALUE: float = 0.55
## Structure hues closer than this (25° of the wheel) to a gameplay role are
## desaturated to ROLE_SAFE_SATURATION.
const ROLE_HUE_GAP: float = 25.0 / 360.0
const ROLE_SAFE_SATURATION: float = 0.18
const RIB_PROFILES: PackedStringArray = [
	"gate", "arch", "hex", "monolith", "lattice", "facet", "truss", "icicle", "ring", "candy"
]

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
## Faint light shafts of the key light far ahead (worlds with open light).
var shafts: bool = false
## Side detail between the ribs (MeshFactory.DETAIL_KINDS; "" for none).
var detail: String = ""
var silhouette: String = "turbine"
var caustics: bool = false
## Floor polish 0..1 (reflections of the shaft on High/Ultra).
var floor_gloss: float = 0.0
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
	t.shafts = bool(atmo.get("shafts", false))
	var detail_kind: String = str(a.get("detail", ""))
	t.detail = detail_kind if MeshFactory.DETAIL_KINDS.has(detail_kind) else ""
	t.silhouette = str(a.get("silhouette", t.silhouette))
	t.caustics = bool(a.get("caustics", false))
	t.floor_gloss = clampf(float(a.get("floor_gloss", 0.0)), 0.0, 1.0)
	t.bpm = float((world.get("music", {}) as Dictionary).get("bpm", 120))
	t.boss_name = str((world.get("boss", {}) as Dictionary).get("name", ""))
	t.bright = t.sky_bottom.get_luminance() > 0.5
	# ART_DIRECTION §3: environment colours stay quiet so gameplay colours win.
	# High-key worlds keep their light values (the core's ink shell keeps it
	# legible there) but are still held to the saturation cap.
	t.sky_top = WorldTheme.quiet(t.sky_top, t.bright)
	t.sky_bottom = WorldTheme.quiet(t.sky_bottom, t.bright)
	t.fog = WorldTheme.quiet(t.fog, t.bright)
	t.floor_color = WorldTheme.quiet(t.floor_color, t.bright)
	t.lane_color = WorldTheme.quiet(t.lane_color, t.bright)
	# Structure (ribs, arches, posts, pads) never wears a gameplay role colour.
	t.structure = WorldTheme.off_roles(t.structure)
	return t


static func _c(dict: Dictionary, key: String, fallback: Color) -> Color:
	var v: String = str(dict.get(key, ""))
	if v.is_empty() or not Color.html_is_valid(v):
		return fallback
	return Color(v)


## [param c] kept out of the gameplay colour roles: a structure colour whose
## hue is within ROLE_HUE_GAP of PRIMARY, SECONDARY, ACCENT or WARNING is
## desaturated to ROLE_SAFE_SATURATION, so it reads as a neutral tint of that
## hue rather than as a hazard, an energy or a reward.
static func off_roles(c: Color) -> Color:
	if c.s <= ROLE_SAFE_SATURATION:
		return c
	for role: Color in [Palette.PRIMARY, Palette.SECONDARY, Palette.ACCENT, Palette.WARNING]:
		if WorldTheme.hue_distance(c.h, role.h) < ROLE_HUE_GAP:
			return Color.from_hsv(c.h, ROLE_SAFE_SATURATION, c.v, c.a)
	return c


## Shortest distance between two hues on the colour wheel (0..0.5).
static func hue_distance(a: float, b: float) -> float:
	var d: float = absf(a - b)
	return minf(d, 1.0 - d)


## [param c] limited to the environment caps: saturation ≤ ENV_MAX_SATURATION
## and (unless [param high_key]) value ≤ ENV_MAX_VALUE.
static func quiet(c: Color, high_key: bool) -> Color:
	var v: float = c.v if high_key else minf(c.v, ENV_MAX_VALUE)
	return Color.from_hsv(c.h, minf(c.s, ENV_MAX_SATURATION), v, c.a)
