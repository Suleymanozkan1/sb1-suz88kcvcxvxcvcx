extends TestCase
## REQ-076: content grows without retuning what shipped. The difficulty ramp is
## measured against a fixed campaign span, and hand-authored levels are
## validated like every other level but kept out of the generator's way.

const SPEC_FIELDS: Array[String] = [
	"seed", "tier", "speed", "spacing", "density", "change_prob", "spark_density", "score_ratio", "intensity"
]


func _grown_catalog() -> WorldCatalog:
	var grown: WorldCatalog = WorldCatalog.load_default()
	var extra: Dictionary = grown.worlds[grown.worlds.size() - 1].duplicate(true)
	extra["id"] = "growth_probe"
	extra["index"] = grown.worlds.size() + 1
	grown.worlds.append(extra)
	return grown


func test_campaign_span_is_the_shipped_campaign() -> void:
	var curve: Dictionary = JsonIO.read_dict(DifficultyModel.CURVE_PATH)
	assert_eq(int(curve.get("campaign_span", 0)), WorldCatalog.load_default().total_levels())


func test_appending_a_world_never_retunes_shipped_levels() -> void:
	var shipped: DifficultyModel = DifficultyModel.new()
	var grown_catalog: WorldCatalog = _grown_catalog()
	assert_gt(float(grown_catalog.total_levels()), 520.0, "the probe catalog really grew")
	var grown: DifficultyModel = DifficultyModel.new(grown_catalog)
	for n: int in [1, 60, 233, 401, 520]:
		var a: LevelSpec = shipped.build_spec(n)
		var b: LevelSpec = grown.build_spec(n)
		for field: String in SPEC_FIELDS:
			assert_eq(a.get(field), b.get(field), "level %d %s unchanged" % [n, field])
	var level_a: Dictionary = LevelGenerator.new().generate(shipped.build_spec(60))
	var level_b: Dictionary = LevelGenerator.new().generate(grown.build_spec(60))
	assert_eq(JsonIO.canonical(level_a), JsonIO.canonical(level_b), "w02_l08 regenerates identically")


func test_levels_past_the_span_hold_the_curve_end() -> void:
	var catalog: WorldCatalog = _grown_catalog()
	var model: DifficultyModel = DifficultyModel.new(catalog)
	var last: LevelSpec = model.build_spec(catalog.total_levels())
	assert_true(last != null, "an appended level builds a spec")
	assert_le(last.intensity, 1.0)
	assert_le(last.spacing, model.build_spec(520).spacing * 1.2, "no runaway past the span")
	assert_le(last.speed, model.build_spec(520).speed * 1.2, "no runaway past the span")


func test_handmade_levels_are_validated_and_flagged() -> void:
	var repo: LevelRepository = LevelRepository.new()
	var shipped: Dictionary = repo.load_level("w01_l10")
	assert_false(LevelRepository.is_handmade(shipped), "generated levels are not handmade")
	var hand: Dictionary = shipped.duplicate(true)
	hand["handmade"] = true
	assert_true(LevelRepository.is_handmade(hand))
	var v: LevelValidator = LevelValidator.new()
	v.check_assets = false
	assert_true(v.validate(hand).ok(), "the flag itself is valid data")
	(hand["entities"] as Array).append({"t": "barrier", "d": float(hand["length"]) * 0.5, "lanes": [0, 1]})
	assert_false(v.validate(hand).ok(), "a handmade level still has to be fair")
