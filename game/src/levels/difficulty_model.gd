class_name DifficultyModel
extends RefCounted
## Maps a campaign level number to a [LevelSpec] using data/difficulty/curve.json
## and the world's chapter data.
##
## Structure: each world has four chapters (A–D, a new main idea every 13
## levels), a mid-world challenge (local 26) and a boss (local 52). Inside a
## chapter levels follow Introduction → Mastery → Combination → High Pressure,
## producing a sawtooth curve on top of a smooth global ramp.

const CURVE_PATH: String = "res://data/difficulty/curve.json"
const CAMPAIGN_SALT: String = "fluxdrop-campaign-v1"

var curve: Dictionary = {}
var catalog: WorldCatalog


func _init(world_catalog: WorldCatalog = null, curve_path: String = CURVE_PATH) -> void:
	catalog = world_catalog if world_catalog != null else WorldCatalog.load_default()
	curve = JsonIO.read_dict(curve_path)


func tier_for(number: int) -> Dictionary:
	for t: Variant in curve.get("tiers", []) as Array:
		var tier: Dictionary = t as Dictionary
		if number >= int(tier["from"]) and number <= int(tier["to"]):
			return tier
	var tiers: Array = curve.get("tiers", []) as Array
	return tiers[tiers.size() - 1] as Dictionary if not tiers.is_empty() else {}


## Returns the chapter dictionary of [param world] containing [param local].
static func chapter_for(world: Dictionary, local: int) -> Dictionary:
	var chapters: Array = world.get("chapters", []) as Array
	for c: Variant in chapters:
		var chapter: Dictionary = c as Dictionary
		if local >= int(chapter["start"]) and local <= int(chapter["end"]):
			return chapter
	# Specials borrow the most recent chapter.
	var best: Dictionary = {}
	for c: Variant in chapters:
		var chapter2: Dictionary = c as Dictionary
		if int(chapter2["start"]) <= local:
			best = chapter2
	return best


func chapter_phase(chapter: Dictionary, local: int) -> String:
	var offset: int = local - int(chapter.get("start", local))
	var phases: Dictionary = curve.get("chapter_phases", {}) as Dictionary
	var acc: int = 0
	for name: String in ["introduction", "mastery", "combination", "high_pressure"]:
		acc += int((phases.get(name, {}) as Dictionary).get("levels", 3))
		if offset < acc:
			return name
	return "high_pressure"


func _lerp_param(key: String, t: float) -> float:
	var p: Dictionary = curve.get(key, {}) as Dictionary
	var e: float = float(p.get("exponent", 1.0))
	return lerpf(float(p.get("start", 0.0)), float(p.get("end", 0.0)), pow(clampf(t, 0.0, 1.0), e))


func build_spec(number: int) -> LevelSpec:
	var loc: Dictionary = catalog.locate(number)
	if loc.is_empty():
		push_error("level number out of range: %d" % number)
		return null
	var wi: int = int(loc["world_index"])
	var local: int = int(loc["local_index"])
	var world: Dictionary = catalog.world_at(wi)
	var total: int = catalog.total_levels()
	var t: float = float(number - 1) / float(maxi(total - 1, 1))
	var spec: LevelSpec = LevelSpec.new()
	spec.number = number
	spec.world_index = wi
	spec.local_index = local
	spec.world_id = str(world.get("id", ""))
	spec.id = WorldCatalog.level_id(wi, local)
	spec.seed = DetRng.hash_string("%s:%s" % [CAMPAIGN_SALT, spec.id])
	spec.lanes = int(world.get("lanes", 2))
	spec.environment = spec.world_id
	var music: Dictionary = world.get("music", {}) as Dictionary
	spec.music = str(music.get("track", spec.world_id))
	spec.beat_seconds = 60.0 / maxf(float(music.get("bpm", 120)), 40.0)
	var tier: Dictionary = tier_for(number)
	spec.tier = str(tier.get("id", "early"))
	spec.min_window = float(tier.get("min_window", 0.3))
	var bounds: Dictionary = curve.get("duration_bounds", {}) as Dictionary
	var tb: Array = bounds.get(spec.tier, [5, 60]) as Array
	spec.duration_bounds = Vector2(float(tb[0]), float(tb[1]))
	spec.unlock_requires = "" if number == 1 else _previous_id(wi, local)
	spec.unlock_stars = int(world.get("unlock_stars", 0)) if local == 1 else 0

	var challenge_level: int = int(world.get("challenge_level", 26))
	var boss_level: int = int(world.get("boss_level", 52))
	var chapter: Dictionary = chapter_for(world, local)
	spec.chapter = _chapter_letter(world, chapter)
	if local == challenge_level:
		spec.kind = "challenge"
	elif local == boss_level:
		spec.kind = "boss"
	spec.chapter_phase = "high_pressure" if spec.is_special() else chapter_phase(chapter, local)
	var phase_cfg: Dictionary = (
		(curve.get("chapter_phases", {}) as Dictionary).get(spec.chapter_phase, {}) as Dictionary
	)
	var wave: float = float(phase_cfg.get("wave", 0.0))
	spec.intensity = clampf(t + wave * 0.03, 0.0, 1.0)

	var speed_cfg: Dictionary = curve.get("speed", {}) as Dictionary
	var spacing_cfg: Dictionary = curve.get("spacing", {}) as Dictionary
	spec.speed = _lerp_param("speed", t) * (1.0 + float(speed_cfg.get("wave", 0.0)) * wave)
	spec.spacing = _lerp_param("spacing", t) * (1.0 - float(spacing_cfg.get("wave", 0.0)) * wave)
	spec.spacing_jitter = float(spacing_cfg.get("jitter", 0.1))
	spec.change_prob = _lerp_param("change_prob", t)
	spec.density = _lerp_param("density", t) * float(phase_cfg.get("density_scale", 1.0))
	spec.spark_density = _lerp_param("spark_density", t)
	spec.score_ratio = _lerp_param("score_target_ratio", t)
	spec.combo_ratio = float(curve.get("combo_target_ratio", 0.6))

	_apply_chapter(spec, chapter)
	if spec.chapter_phase == "combination":
		_blend_previous(spec, _previous_chapter(wi, chapter), float(phase_cfg.get("blend_previous", 0.0)))
	spec.intro_mechanic = str(chapter.get("intro", "")) if spec.chapter_phase == "introduction" else ""

	var tutorial_until: int = int(chapter.get("tutorial_until", 0))
	if local <= tutorial_until:
		_apply_tutorial(spec, local, int(chapter.get("forgiving_until", 0)))
	if spec.kind == "challenge":
		_apply_special(spec, world.get("challenge", {}) as Dictionary)
	elif spec.kind == "boss":
		_apply_special(spec, world.get("boss", {}) as Dictionary)

	_choose_objective(spec)
	_fit_duration(spec, chapter)
	return spec


func _previous_id(wi: int, local: int) -> String:
	if local > 1:
		return WorldCatalog.level_id(wi, local - 1)
	return WorldCatalog.level_id(wi - 1, catalog.levels_in(wi - 1))


func _chapter_letter(world: Dictionary, chapter: Dictionary) -> String:
	var chapters: Array = world.get("chapters", []) as Array
	var idx: int = chapters.find(chapter)
	return ["A", "B", "C", "D"][clampi(idx, 0, 3)]


func _apply_chapter(spec: LevelSpec, chapter: Dictionary) -> void:
	spec.forms = (chapter.get("forms", {"hop": 1}) as Dictionary).duplicate()
	spec.hazards = (chapter.get("hazards", {"barrier": 1}) as Dictionary).duplicate()
	spec.prism_chance = float(chapter.get("prism", 0.0))
	spec.shield_chance = float(chapter.get("shield", 0.0))
	spec.magnet_chance = float(chapter.get("magnet", 0.0))
	spec.current_chance = float(chapter.get("current", 0.0))
	spec.portal_chance = float(chapter.get("portal", 0.0))
	spec.cluster_chance = float(chapter.get("cluster", 0.0))
	spec.hop_time = float(chapter.get("hop_time", SimConst.HOP_TIME))
	spec.speed_ramp = float(chapter.get("speed_ramp", 0.0))
	spec.form_segment = int(chapter.get("form_segment", 6))
	spec.spark_density = minf(1.0, spec.spark_density + float(chapter.get("spark_bonus", 0.0)))
	_apply_mass_gravity(spec, chapter)
	if spec.chapter_phase == "introduction":
		# Teach the new idea safely: slower, fewer simultaneous threats.
		spec.speed *= 0.94
		spec.change_prob *= 0.8
	spec.start_form = _first_form(spec)


## The chapter before [param chapter] (the previous world's last one for a
## world's first chapter; empty at the very start of the campaign).
func _previous_chapter(wi: int, chapter: Dictionary) -> Dictionary:
	var chapters: Array = catalog.world_at(wi).get("chapters", []) as Array
	var idx: int = chapters.find(chapter)
	if idx > 0:
		return chapters[idx - 1] as Dictionary
	if wi > 1:
		var before: Array = catalog.world_at(wi - 1).get("chapters", []) as Array
		if not before.is_empty():
			return before[before.size() - 1] as Dictionary
	return {}


## Combination phase: the previous chapter's idea comes back explicitly. Its
## hazards and forms join the mix at [param amount] of their weight, and its
## special elements (currents, portals, pads, wells, plates, clusters) keep at
## least [param amount] of their chance.
func _blend_previous(spec: LevelSpec, previous: Dictionary, amount: float) -> void:
	if previous.is_empty() or amount <= 0.0:
		return
	var hazards: Dictionary = previous.get("hazards", {}) as Dictionary
	for h: String in hazards:
		spec.hazards[h] = float(spec.hazards.get(h, 0.0)) + amount * float(hazards[h])
	var forms: Dictionary = previous.get("forms", {}) as Dictionary
	for f: String in forms:
		spec.forms[f] = float(spec.forms.get(f, 0.0)) + amount * float(forms[f])
	spec.current_chance = maxf(spec.current_chance, amount * float(previous.get("current", 0.0)))
	spec.portal_chance = maxf(spec.portal_chance, amount * float(previous.get("portal", 0.0)))
	spec.launch_chance = maxf(spec.launch_chance, amount * float(previous.get("launch", 0.0)))
	spec.gravity_chance = maxf(spec.gravity_chance, amount * float(previous.get("gravity", 0.0)))
	spec.plate_chance = maxf(spec.plate_chance, amount * float(previous.get("plate", 0.0)))
	spec.cluster_chance = maxf(spec.cluster_chance, amount * float(previous.get("cluster", 0.0)))
	spec.start_form = _first_form(spec)


## Launch pads, gravity wells and mass plates from chapter or special data
## (missing keys switch them off).
static func _apply_mass_gravity(spec: LevelSpec, source: Dictionary) -> void:
	spec.gravity_chance = float(source.get("gravity", 0.0))
	spec.launch_chance = float(source.get("launch", 0.0))
	spec.plate_chance = float(source.get("plate", 0.0))
	var values: Array = source.get("gravity_g", []) as Array
	if not values.is_empty():
		spec.gravity_values.clear()
		for g: Variant in values:
			spec.gravity_values.append(float(g))
	var slots: Array = source.get("gravity_slots", []) as Array
	if slots.size() == 2:
		spec.gravity_slots = Vector2i(int(slots[0]), int(slots[1]))


func _first_form(spec: LevelSpec) -> String:
	var best: String = "hop"
	var best_w: float = -1.0
	for f: String in spec.forms:
		if float(spec.forms[f]) > best_w:
			best_w = float(spec.forms[f])
			best = f
	# If the chapter introduces a new form, start in it so it is taught first.
	for f: String in ["phase", "dash", "surge"]:
		if spec.forms.has(f) and spec.forms.size() == 1:
			return f
	return best


func _apply_tutorial(spec: LevelSpec, local: int, forgiving_until: int) -> void:
	var tut: Dictionary = curve.get("tutorial", {}) as Dictionary
	spec.tutorial = true
	spec.forgiving = local <= forgiving_until
	spec.speed = float(tut.get("speed", 6.0)) + 0.15 * float(local - 1)
	spec.spacing = float(tut.get("spacing", 8.5)) - 0.3 * float(local - 1)
	spec.change_prob = float(tut.get("change_prob", 0.5))
	spec.density = float(tut.get("density", 0.6))
	spec.prism_chance = 0.0
	spec.shield_chance = 0.0


func _apply_special(spec: LevelSpec, special: Dictionary) -> void:
	spec.pattern = str(special.get("pattern", ""))
	spec.boss_name = str(special.get("name", ""))
	if special.has("hazards"):
		spec.hazards = (special["hazards"] as Dictionary).duplicate()
	if special.has("forms"):
		spec.forms = (special["forms"] as Dictionary).duplicate()
		spec.start_form = _first_form(spec)
	spec.speed *= 1.0 + float(special.get("speed_bonus", 0.0))
	spec.speed_ramp = float(special.get("speed_ramp", spec.speed_ramp))
	spec.current_chance = float(special.get("current", spec.current_chance))
	spec.portal_chance = float(special.get("portal", spec.portal_chance))
	spec.cluster_chance = float(special.get("cluster", spec.cluster_chance))
	spec.hop_time = float(special.get("hop_time", spec.hop_time))
	spec.form_segment = int(special.get("form_segment", spec.form_segment))
	# Set pieces opt in to the mass & gravity family explicitly.
	_apply_mass_gravity(spec, special)
	spec.density = 1.0
	match spec.pattern:
		"color_cascade":
			# The colour flips almost every row: a cascade to read and follow.
			spec.change_prob = maxf(spec.change_prob, 0.85)
		"chain_smasher":
			# Dense breakable clusters: one dash sets off long chains.
			spec.cluster_chance = maxf(spec.cluster_chance, 0.75)
	var bounds: Dictionary = curve.get("duration_bounds", {}) as Dictionary
	var key: String = "special_boss" if spec.kind == "boss" else "special_challenge"
	var b: Array = bounds.get(key, [30, 120]) as Array
	spec.duration_bounds = Vector2(float(b[0]), float(b[1]))
	if spec.kind == "boss":
		spec.target_duration = float(special.get("duration", 70))
	else:
		spec.target_duration = lerpf(spec.duration_bounds.x, spec.duration_bounds.y, 0.35)


func _choose_objective(spec: LevelSpec) -> void:
	if spec.tutorial:
		spec.objective_type = "reach_end"
		return
	if spec.kind == "boss":
		spec.objective_type = "survive"
		return
	if spec.forms.has("dash") and spec.local_index % 3 == 0:
		spec.objective_type = "shatter"
		spec.objective_fraction = 0.6
	elif spec.local_index % 4 == 2:
		spec.objective_type = "collect"
		spec.objective_fraction = 0.55
	else:
		spec.objective_type = "reach_end"


## Slot count is derived from the target duration inside the tier's bounds.
func _fit_duration(spec: LevelSpec, chapter: Dictionary) -> void:
	if not spec.is_special():
		var tier: Dictionary = tier_for(spec.number)
		var d: Array = tier.get("duration", [8, 15]) as Array
		var start: int = int(chapter.get("start", 1))
		var end: int = int(chapter.get("end", 13))
		var p: float = float(spec.local_index - start) / float(maxi(end - start, 1))
		spec.target_duration = lerpf(float(d[0]), float(d[1]), clampf(0.15 + 0.75 * p, 0.0, 1.0))
	var avg_speed: float = spec.speed * (1.0 + spec.speed_ramp * 0.5)
	var usable: float = spec.target_duration * avg_speed - LevelGenerator.LEAD_IN - LevelGenerator.TAIL
	spec.slot_count = maxi(4, int(usable / spec.spacing))
