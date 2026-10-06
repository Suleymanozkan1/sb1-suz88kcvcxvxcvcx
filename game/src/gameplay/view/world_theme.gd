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
## Far scenery on the sky's horizon (sky.gdshader `skyline`, same order).
const SKYLINES: PackedStringArray = [
	"none", "city", "spires", "volcano", "stacks", "reef", "canopy", "ice", "dunes", "rocks", "candy"
]
## Celestial body in the sky (sky.gdshader `body_kind`, same order).
const BODY_KINDS: PackedStringArray = ["none", "sun", "moon", "ringed"]
## Lights in the scenery (windows, lava, glints, beacons, aurora) may be a
## little more saturated than the environment, never more than this.
const SKY_LIGHT_MAX_SATURATION: float = 0.6

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
## Obstacles (ART_DIRECTION §4, §5): the world's shape family (HazardShapes),
## its body colour and its warning light. The warning light is the cue every
## world shares: always red to orange-red, so a hazard reads as one at a glance
## however it is built.
var hazard_style: String = "machined"
var hazard_body: Color = Color("#39404d")
var hazard_warn: Color = Palette.WARNING
## Sky scenery (ART_DIRECTION §7), `art.sky`: skyline silhouette and its
## lights, nebula, clouds, aurora, light rays, a sun / moon / ringed planet and
## the star density. Angles are stored in radians (degrees in the data).
var skyline: String = "none"
var skyline_color: Color = Color("#0a0e16")
var skyline_light: Color = Color("#8fb6c8")
var nebula: float = 0.0
var nebula_a: Color = Color("#2a2550")
var nebula_b: Color = Color("#1b3a4a")
var clouds: float = 0.0
var cloud_color: Color = Color("#d8dde6")
var cloud_shade: Color = Color("#7c8696")
var aurora: float = 0.0
var aurora_a: Color = Color("#5fd1a6")
var aurora_b: Color = Color("#6a8de0")
var rays: float = 0.0
var ray_dir: Vector2 = Vector2(0.0, deg_to_rad(60.0))
var body_kind: String = "none"
var body: Vector3 = Vector3(0.0, deg_to_rad(18.0), deg_to_rad(3.0))
var body_color: Color = Color("#e8ecf2")
var stars: float = 0.0
## Painted backdrop (art.sky.backdrop): image path ("" for the procedural
## scenery), its placement (half width, bottom, top; radians) and grade.
var backdrop: String = ""
var backdrop_rect: Vector3 = Vector3(deg_to_rad(31.5), deg_to_rad(-14.0), deg_to_rad(49.0))
var backdrop_gain: float = 0.9
var backdrop_saturation: float = 0.9


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
	var hz: Dictionary = a.get("hazard", {}) as Dictionary
	var style: String = str(hz.get("style", t.hazard_style))
	t.hazard_style = style if HazardShapes.STYLES.has(style) else "machined"
	t.hazard_body = _c(hz, "body", t.hazard_body)
	t.hazard_warn = _c(hz, "warn", t.hazard_warn)
	t._read_sky(a.get("sky", {}) as Dictionary)
	if t.atmosphere == "stars":
		t.stars = maxf(t.stars, 1.0)
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
	t.skyline_color = WorldTheme.quiet(t.skyline_color, t.bright)
	t.nebula_a = WorldTheme.quiet(t.nebula_a, t.bright)
	t.nebula_b = WorldTheme.quiet(t.nebula_b, t.bright)
	t.cloud_color = WorldTheme.quiet(t.cloud_color, true)
	t.cloud_shade = WorldTheme.quiet(t.cloud_shade, true)
	t.body_color = WorldTheme.quiet(t.body_color, true)
	t.skyline_light = WorldTheme.sky_light(t.skyline_light)
	t.aurora_a = WorldTheme.sky_light(t.aurora_a)
	t.aurora_b = WorldTheme.sky_light(t.aurora_b)
	return t


func _read_sky(sky: Dictionary) -> void:
	var line: String = str(sky.get("skyline", skyline))
	skyline = line if SKYLINES.has(line) else "none"
	skyline_color = _c(sky, "skyline_color", skyline_color)
	skyline_light = _c(sky, "skyline_light", skyline_light)
	nebula = clampf(float(sky.get("nebula", 0.0)), 0.0, 1.0)
	nebula_a = _c(sky, "nebula_a", nebula_a)
	nebula_b = _c(sky, "nebula_b", nebula_b)
	clouds = clampf(float(sky.get("clouds", 0.0)), 0.0, 1.0)
	cloud_color = _c(sky, "cloud_color", cloud_color)
	cloud_shade = _c(sky, "cloud_shade", cloud_shade)
	aurora = clampf(float(sky.get("aurora", 0.0)), 0.0, 1.0)
	aurora_a = _c(sky, "aurora_a", aurora_a)
	aurora_b = _c(sky, "aurora_b", aurora_b)
	stars = clampf(float(sky.get("stars", 0.0)), 0.0, 1.0)
	var ray: Dictionary = sky.get("rays", {}) as Dictionary
	rays = clampf(float(ray.get("amount", 0.0)), 0.0, 1.0)
	ray_dir = Vector2(deg_to_rad(float(ray.get("az", 0.0))), deg_to_rad(float(ray.get("el", 60.0))))
	var b: Dictionary = sky.get("body", {}) as Dictionary
	var kind: String = str(b.get("kind", "none"))
	body_kind = kind if BODY_KINDS.has(kind) else "none"
	body = Vector3(
		deg_to_rad(float(b.get("az", 0.0))),
		deg_to_rad(float(b.get("el", 18.0))),
		deg_to_rad(clampf(float(b.get("size", 3.0)), 0.5, 12.0))
	)
	body_color = _c(b, "color", body_color)
	var bd: Dictionary = sky.get("backdrop", {}) as Dictionary
	var image: String = str(bd.get("image", ""))
	backdrop = image if not image.is_empty() and ResourceLoader.exists(image) else ""
	backdrop_rect = Vector3(
		deg_to_rad(clampf(float(bd.get("az_half", 31.5)), 10.0, 90.0)),
		deg_to_rad(float(bd.get("el_bottom", -14.0))),
		deg_to_rad(float(bd.get("el_top", 49.0)))
	)
	backdrop_gain = clampf(float(bd.get("gain", 0.9)), 0.2, 1.5)
	backdrop_saturation = clampf(float(bd.get("saturation", 0.9)), 0.0, 1.5)


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


## A light in the scenery: saturation held to SKY_LIGHT_MAX_SATURATION.
static func sky_light(c: Color) -> Color:
	return Color.from_hsv(c.h, minf(c.s, SKY_LIGHT_MAX_SATURATION), c.v, c.a)


## Shortest distance between two hues on the colour wheel (0..0.5).
static func hue_distance(a: float, b: float) -> float:
	var d: float = absf(a - b)
	return minf(d, 1.0 - d)


## [param c] limited to the environment caps: saturation ≤ ENV_MAX_SATURATION
## and (unless [param high_key]) value ≤ ENV_MAX_VALUE.
static func quiet(c: Color, high_key: bool) -> Color:
	var v: float = c.v if high_key else minf(c.v, ENV_MAX_VALUE)
	return Color.from_hsv(c.h, minf(c.s, ENV_MAX_SATURATION), v, c.a)
