extends TestCase
## CosmeticCatalog parsing helpers and validation of broken / hostile data.

const CORE_STYLE_COUNT: int = 10

var _catalog: CosmeticCatalog = null


func before_each() -> void:
	_catalog = CosmeticCatalog.load_default()


# --- parsing helpers -----------------------------------------------------------


func test_parse_color_accepts_hex_and_rejects_garbage() -> void:
	assert_true(CosmeticCatalog.parse_color("#ff0000").is_equal_approx(Color(1, 0, 0, 1)))
	assert_near(CosmeticCatalog.parse_color("#00ff0080").a, 128.0 / 255.0, 0.01, "alpha")
	var fallback: Color = Color(0.1, 0.2, 0.3, 1.0)
	assert_eq(CosmeticCatalog.parse_color("red", fallback), fallback, "named colours rejected")
	assert_eq(CosmeticCatalog.parse_color("#12345", fallback), fallback, "short hex rejected")
	assert_eq(CosmeticCatalog.parse_color("#gg0000", fallback), fallback, "non-hex rejected")
	assert_eq(CosmeticCatalog.parse_color(42, fallback), fallback, "non-string rejected")
	assert_true(CosmeticCatalog.is_hex_color("#a1B2c3"))
	assert_false(CosmeticCatalog.is_hex_color("a1b2c3"))


func test_parse_params_falls_back_and_clamps() -> void:
	var p: Dictionary = _catalog.parse_params(
		CosmeticCatalog.CORE_SKIN, {"style": 99, "color_a": "nope", "anim_speed": 50.0}
	)
	assert_eq(int(p["style"]), CORE_STYLE_COUNT - 1, "style clamped to last shader style")
	assert_eq(p["color_a"], CosmeticCatalog.FALLBACK_COLOR, "bad colour falls back")
	assert_eq(typeof(p["rim"]), TYPE_COLOR, "missing colour still a Color")
	assert_le(float(p["anim_speed"]), 3.0, "anim speed clamped")
	var frame: Dictionary = _catalog.parse_params(CosmeticCatalog.FRAME, {"pattern": "bogus"})
	assert_eq(str(frame["pattern"]), "plain", "unknown pattern falls back to first option")
	var particle: Dictionary = _catalog.parse_params(CosmeticCatalog.PARTICLE, "garbage")
	assert_eq((particle["colors"] as Array).size(), 1, "fallback colour list")
	assert_eq(typeof(particle["size_mult"]), TYPE_FLOAT)


# --- validation of broken data ---------------------------------------------------


func test_minimal_fixture_is_valid() -> void:
	var c: CosmeticCatalog = CosmeticCatalog.from_data(_fixture(), _fixture_products())
	assert_empty(c.validate(), "fixture errors: %s" % str(c.validate()))


func test_detects_duplicate_ids() -> void:
	var data: Dictionary = _fixture()
	var first: Dictionary = (data["items"] as Array)[0] as Dictionary
	(data["items"] as Array).append(first.duplicate(true))
	_expect_error(CosmeticCatalog.from_data(data, _fixture_products()), "duplicate item id")


func test_detects_missing_default() -> void:
	var data: Dictionary = _fixture()
	for raw: Variant in data["items"] as Array:
		var it: Dictionary = raw as Dictionary
		if it["id"] == "t_trail":
			it["unlock"] = {"type": "coins", "value": 10}
	var c: CosmeticCatalog = CosmeticCatalog.from_data(data, _fixture_products())
	_expect_error(c, "category trail has no default")
	assert_eq(c.default_for("trail"), "", "no default id")


func test_detects_second_default() -> void:
	var data: Dictionary = _fixture()
	(data["items"] as Array).append(_item("t_trail_2", "trail", {"type": "default"}, _params_for("trail")))
	_expect_error(CosmeticCatalog.from_data(data, _fixture_products()), "exactly one allowed")


func test_detects_unknown_unlock_type() -> void:
	var data: Dictionary = _fixture()
	(data["items"] as Array).append(_item("t_odd", "theme", {"type": "lottery", "value": 1}, _params_for("theme")))
	_expect_error(CosmeticCatalog.from_data(data, _fixture_products()), "unknown unlock type")


func test_detects_bad_unlock_values() -> void:
	var data: Dictionary = _fixture()
	var items: Array = data["items"] as Array
	items.append(_item("t_free", "theme", {"type": "coins", "value": 0}, _params_for("theme")))
	items.append(_item("t_ach", "theme", {"type": "achievement"}, _params_for("theme")))
	items.append(_item("t_tier", "theme", {"type": "perfects", "value": "nowhere"}, _params_for("theme")))
	var c: CosmeticCatalog = CosmeticCatalog.from_data(data, _fixture_products())
	_expect_error(c, "t_free: unlock coins needs a positive integer")
	_expect_error(c, "t_ach: achievement unlock needs")
	_expect_error(c, "t_tier: perfects unlock needs")


func test_detects_missing_and_invalid_params() -> void:
	var data: Dictionary = _fixture()
	var items: Array = data["items"] as Array
	var no_params: Dictionary = _item("t_np", "core_skin", {"type": "coins", "value": 5}, {})
	no_params.erase("params")
	items.append(no_params)
	items.append(_item("t_mp", "core_skin", {"type": "coins", "value": 5}, {"style": 1}))
	var bad: Dictionary = _params_for("core_skin")
	bad["style"] = 12
	bad["rim"] = "white"
	bad["anim_speed"] = 9.0
	items.append(_item("t_bp", "core_skin", {"type": "coins", "value": 5}, bad))
	var c: CosmeticCatalog = CosmeticCatalog.from_data(data, _fixture_products())
	_expect_error(c, "t_np: params missing")
	_expect_error(c, "t_mp: missing param 'color_a'")
	_expect_error(c, "t_bp: param 'style' out of range")
	_expect_error(c, "t_bp: param 'rim' must be a #rrggbb colour")
	_expect_error(c, "t_bp: param 'anim_speed' out of range")


func test_detects_purchasable_badge() -> void:
	var data: Dictionary = _fixture()
	(data["items"] as Array).append(_item("t_badge_buy", "badge", {"type": "gems", "value": 5}, _params_for("badge")))
	_expect_error(CosmeticCatalog.from_data(data, _fixture_products()), "badges can only be earned")


func test_detects_premium_item_not_sold() -> void:
	var data: Dictionary = _fixture()
	(data["items"] as Array).append(_item("t_orphan", "core_skin", {"type": "premium"}, _params_for("core_skin")))
	_expect_error(CosmeticCatalog.from_data(data, _fixture_products()), "t_orphan: premium item is not sold")


func test_detects_products_with_unknown_or_non_cosmetic_content() -> void:
	var products: Dictionary = _fixture_products()
	var list: Array = products["products"] as Array
	list.append(
		{
			"id": "pack_bad",
			"type": "non_consumable",
			"name_key": "cos.product.pack_bad.name",
			"items": ["ghost_item", "t_core"],
			"coins": 5000,
		}
	)
	list.append({"id": "pack_gems", "type": "consumable", "name_key": "cos.product.pack_gems.name", "items": []})
	var c: CosmeticCatalog = CosmeticCatalog.from_data(_fixture(), products)
	_expect_error(c, "pack_bad: unknown cosmetic id 'ghost_item'")
	_expect_error(c, "pack_bad: unexpected field 'coins'")
	_expect_error(c, "pack_bad: item 't_core' is not a premium item")
	_expect_error(c, "pack_gems: product type must be non_consumable")
	_expect_error(c, "pack_gems: items must be a non-empty array")


func test_detects_item_sold_twice() -> void:
	var products: Dictionary = _fixture_products()
	(products["products"] as Array).append(
		{"id": "pack_again", "type": "non_consumable", "name_key": "cos.p.again", "items": ["t_premium"]}
	)
	_expect_error(CosmeticCatalog.from_data(_fixture(), products), "already sold by pack_t")


func test_skips_malformed_entries_without_crashing() -> void:
	var data: Dictionary = _fixture()
	var items: Array = data["items"] as Array
	items.append("not an item")
	items.append({"id": "Bad Id!", "category": "trail"})
	items.append({"id": "t_mystery", "category": "hats"})
	var c: CosmeticCatalog = CosmeticCatalog.from_data(data, {"products": "nope"})
	_expect_error(c, "item entry is not an object")
	_expect_error(c, "invalid item id")
	_expect_error(c, "unknown category 'hats'")
	_expect_error(c, "products 'products' must be an array")
	assert_false(c.has_item("t_mystery"), "unknown category item skipped")
	assert_true(c.has_item("t_core"), "valid items still loaded")


func test_missing_files_give_empty_catalog_with_errors() -> void:
	var c: CosmeticCatalog = CosmeticCatalog.new()
	c.load_from("res://data/cosmetics/does_not_exist.json", "res://data/store/does_not_exist.json")
	assert_empty(c.items, "no items")
	_expect_error(c, "cosmetics file missing")
	_expect_error(c, "products file missing")
	_expect_error(c, "has no default item")
	assert_eq(c.categories().size(), CosmeticCatalog.REQUIRED_CATEGORIES.size(), "categories fall back")


func test_detects_category_below_minimum() -> void:
	var data: Dictionary = _fixture()
	data["min_per_category"] = {"avatar": 3}
	_expect_error(CosmeticCatalog.from_data(data, _fixture_products()), "category avatar has 1 items, needs at least 3")


# --- helpers -------------------------------------------------------------------


func _expect_error(c: CosmeticCatalog, fragment: String) -> void:
	var errors: PackedStringArray = c.validate()
	for e: String in errors:
		if e.contains(fragment):
			assert_true(true)
			return
	fail("expected an error containing '%s' in %s" % [fragment, str(errors)])


func _fixture() -> Dictionary:
	var items: Array = []
	for category: String in CosmeticCatalog.REQUIRED_CATEGORIES:
		var id: String = "t_%s" % category.get_slice("_", 0)
		items.append(_item(id, category, {"type": "default"}, _params_for(category)))
	items.append(_item("t_premium", "core_skin", {"type": "premium"}, _params_for("core_skin")))
	items.append(_item("badge_perfect_expert", "badge", {"type": "perfects", "value": "expert"}, _params_for("badge")))
	var real: CosmeticCatalog = CosmeticCatalog.load_default()
	return {
		"schema_version": 1,
		"categories": Array(CosmeticCatalog.REQUIRED_CATEGORIES),
		"rarities": ["common", "rare", "epic", "legendary"],
		"core_styles": Array(real.options("core_styles")),
		"trail_styles": Array(real.options("trail_styles")),
		"frame_patterns": Array(real.options("frame_patterns")),
		"avatar_glyphs": Array(real.options("avatar_glyphs")),
		"badge_icons": Array(real.options("badge_icons")),
		"perfect_tiers": ["expert"],
		"ranges": {"core_skin.anim_speed": [0.25, 3.0], "effect.shockwave": [0.0, 2.0]},
		"items": items,
	}


func _fixture_products() -> Dictionary:
	return {
		"products": [
			{
				"id": "pack_t",
				"type": "non_consumable",
				"name_key": "cos.product.pack_t.name",
				"items": ["t_premium"],
				"display_price_hint": "—",
			},
		],
	}


func _item(id: String, category: String, unlock: Dictionary, params: Dictionary) -> Dictionary:
	return {
		"id": id,
		"category": category,
		"name_key": "cos.%s.name" % id,
		"rarity": "common",
		"unlock": unlock,
		"params": params,
	}


func _params_for(category: String) -> Dictionary:
	var by_category: Dictionary = {
		"core_skin": {"style": 0, "color_a": "#112233", "color_b": "#445566", "rim": "#ffffff", "anim_speed": 1.0},
		"trail": {"style": 0, "head": "#112233", "tail": "#445566"},
		"particle": {"colors": ["#112233"], "size_mult": 1.0, "count_mult": 1.0},
		"background": {"use_world_palette": true, "sky_top": "#000000", "sky_bottom": "#111111", "star_density": 0.5},
		"theme": {"accent": "#112233", "accent_2": "#445566", "panel_tint": "#000000"},
		"effect": {"fail_color": "#ff0000", "perfect_color": "#00ff00", "accent": "#ffffff", "shockwave": 1.0},
		"badge": {"icon": "star", "color": "#ffd23d"},
		"frame": {"color": "#112233", "accent": "#445566", "pattern": "plain"},
		"avatar": {"glyph": "orb", "bg": "#000000", "fg": "#ffffff"},
	}
	return (by_category[category] as Dictionary).duplicate(true)
