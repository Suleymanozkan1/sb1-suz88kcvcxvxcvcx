extends TestCase
## Shipped level content: world data names real hazards, chapters place the
## mechanic they introduce, and boss set pieces shape their levels.


func test_world_hazard_weights_name_real_hazards() -> void:
	var catalog: WorldCatalog = WorldCatalog.load_default()
	var checked: int = 0
	for w: Dictionary in catalog.worlds:
		var groups: Array = (w.get("chapters", []) as Array).duplicate()
		groups.append(w.get("challenge", {}))
		groups.append(w.get("boss", {}))
		for g: Variant in groups:
			for key: Variant in (g as Dictionary).get("hazards", {}) as Dictionary:
				assert_has(LevelGenerator.HAZARD_KINDS, str(key), "%s hazard '%s'" % [str(w.get("id", "")), str(key)])
				checked += 1
	assert_gt(float(checked), 50.0, "hazard weights found")


func test_pulse_chapters_place_pulse_gates() -> void:
	var repo: LevelRepository = LevelRepository.new()
	var gates: int = 0
	for n: int in range(40, 52):
		for e: Variant in repo.load_level("w01_l%02d" % n)["entities"] as Array:
			if str((e as Dictionary)["t"]) == "pulse_gate":
				gates += 1
	assert_gt(float(gates), 12.0, "World 1's pulse chapter (L40-51) teaches pulse gates")


func test_boss_set_pieces_shape_their_levels() -> void:
	var repo: LevelRepository = LevelRepository.new()
	var rotor: Dictionary = repo.load_level("w01_l52")
	var rhythm: Dictionary = repo.load_level("w07_l52")
	assert_eq(str((rotor["special"] as Dictionary)["pattern"]), "rotor_gauntlet")
	for pair: Array in [[rotor, "slider"], [rhythm, "pulse_gate"]]:
		var periods: Dictionary = {}
		for e: Variant in (pair[0] as Dictionary)["entities"] as Array:
			if str((e as Dictionary)["t"]) == pair[1]:
				periods[(e as Dictionary)["period"]] = true
		var id: String = str((pair[0] as Dictionary)["id"])
		assert_eq(periods.size(), 1, "%s: every %s shares one period" % [id, pair[1]])
	var model: DifficultyModel = DifficultyModel.new()
	assert_ge(model.build_spec(104).change_prob, 0.85, "color_cascade flips colour most rows")
	assert_ge(model.build_spec(208).cluster_chance, 0.75, "chain_smasher clusters breakables")
	var gen: LevelGenerator = LevelGenerator.new()
	gen.generate(model.build_spec(312))
	assert_eq(gen._motif.size(), LevelGenerator.MOTIF_LENGTH, "pattern_memory learns a motif")


func test_validator_reports_unreachable_targets() -> void:
	var data: Dictionary = LevelRepository.new().load_level("w02_l10")
	var v: LevelValidator = LevelValidator.new()
	v.check_assets = false
	assert_false(v.validate(data).codes().has("unreachable_state"), "shipped targets are reachable")
	data["score_target"] = 9999999
	assert_true(v.validate(data).codes().has("unreachable_state"), "a score target above the solution is caught")
	data = LevelRepository.new().load_level("w02_l10")
	data["combo_target"] = 9999
	assert_true(v.validate(data).codes().has("unreachable_state"), "and a combo target above it")


func test_combination_phase_brings_back_the_previous_chapter() -> void:
	var model: DifficultyModel = DifficultyModel.new()
	var catalog: WorldCatalog = WorldCatalog.load_default()
	var checked: int = 0
	for wi: int in range(1, catalog.world_count() + 1):
		var chapters: Array = catalog.world_at(wi).get("chapters", []) as Array
		for ci: int in chapters.size():
			if wi == 1 and ci == 0:
				continue
			var previous: Dictionary = (
				chapters[ci - 1] as Dictionary if ci > 0 else (catalog.world_at(wi - 1)["chapters"] as Array).back()
				as Dictionary
			)
			var local: int = int((chapters[ci] as Dictionary)["start"]) + 7
			var spec: LevelSpec = model.build_spec(catalog.global_number(wi, local))
			assert_eq(spec.chapter_phase, "combination", spec.id)
			for h: String in previous.get("hazards", {}) as Dictionary:
				assert_gt(float(spec.hazards.get(h, 0.0)), 0.0, "%s brings back %s" % [spec.id, h])
			for f: String in previous.get("forms", {}) as Dictionary:
				assert_gt(float(spec.forms.get(f, 0.0)), 0.0, "%s brings back the %s form" % [spec.id, f])
			checked += 1
	assert_eq(checked, 39, "every combination phase after the first chapter")
