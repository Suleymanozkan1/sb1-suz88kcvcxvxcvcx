extends TestCase
## Typed dictionaries (REQ-239): maps filled from JSON data hold their declared
## value type, and data that leaves the game (level files) stays plain JSON.


func test_level_spec_weights_are_typed_floats() -> void:
	var spec: LevelSpec = DifficultyModel.new().build_spec(1)
	for table: Dictionary in [spec.forms, spec.hazards]:
		assert_true(table.is_typed(), "weights are a typed map")
		assert_false(table.is_empty(), "weights come from the chapter data")
		for key: Variant in table:
			assert_eq(typeof(key), TYPE_STRING, "weight names are strings")
			assert_eq(typeof(table[key]), TYPE_FLOAT, "weight %s is a float" % str(key))


func test_generated_mechanics_stay_a_plain_array() -> void:
	var level: Dictionary = LevelGenerator.new().generate(DifficultyModel.new().build_spec(3))
	var mechanics: Array = level["mechanics"] as Array
	assert_false(mechanics.is_typed(), "level JSON holds plain arrays")
	assert_has(mechanics, "spark")


func test_economy_currency_maps_take_whole_numbers_from_json() -> void:
	var raw: Variant = JSON.parse_string(
		'{"max_single_grant": {"coins": 4000, "gems": 40}, "starting": {"coins": 10.0, "gems": 0}}'
	)
	var config: Dictionary = EconomyService.sanitize_config(raw as Dictionary)
	for section: String in [EconomyService.KEY_MAX_SINGLE_GRANT, EconomyService.KEY_STARTING]:
		var amounts: Dictionary = config[section] as Dictionary
		assert_true(amounts.is_typed(), "%s is a typed map" % section)
		for currency: String in amounts:
			assert_eq(typeof(amounts[currency]), TYPE_INT, "%s.%s is a whole number" % [section, currency])
	assert_eq((config[EconomyService.KEY_STARTING] as Dictionary)["coins"], 10)


func test_analytics_param_types_of_known_and_unknown_events() -> void:
	var schema: AnalyticsSchema = AnalyticsSchema.from_dict({"events": {"level_end": {"params": {"score": "int"}}}})
	assert_eq(schema.param_types("level_end"), {"score": "int"})
	assert_empty(schema.param_types("never_declared"), "unknown event has no params")
