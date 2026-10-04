extends TestCase
## CosmeticCatalog: shipped data integrity, parsing and validation of broken data.

const SPEC_MINIMUMS: Dictionary = {
	"core_skin": 14,
	"trail": 10,
	"particle": 8,
	"background": 8,
	"theme": 6,
	"effect": 8,
	"badge": 16,
	"frame": 8,
	"avatar": 12,
}
const CORE_STYLE_COUNT: int = 19
const TRAIL_STYLE_COUNT: int = 12

var _catalog: CosmeticCatalog = null


func before_each() -> void:
	_catalog = CosmeticCatalog.load_default()


# --- shipped data ------------------------------------------------------------


func test_shipped_catalog_validates_clean() -> void:
	var errors: PackedStringArray = _catalog.validate()
	assert_empty(errors, "shipped catalog errors: %s" % "\n".join(errors))
	assert_gt(_catalog.items.size(), 0, "items loaded")
	assert_gt(_catalog.products.size(), 0, "products loaded")


func test_category_counts_meet_minimums() -> void:
	for category: String in SPEC_MINIMUMS:
		var count: int = _catalog.in_category(category).size()
		assert_ge(count, int(SPEC_MINIMUMS[category]), "%s count %d" % [category, count])
	assert_eq(_catalog.categories().size(), SPEC_MINIMUMS.size(), "nine categories")


func test_every_core_shader_style_used() -> void:
	var used: Dictionary = {}
	for it: Dictionary in _catalog.in_category(CosmeticCatalog.CORE_SKIN):
		var style: int = int(_catalog.typed_params(str(it["id"]))["style"])
		used[style] = true
	for style: int in CORE_STYLE_COUNT:
		assert_true(used.has(style), "core style %d used" % style)
	assert_eq(_catalog.options("core_styles").size(), CORE_STYLE_COUNT)


func test_every_trail_shader_style_used() -> void:
	var used: Dictionary = {}
	for it: Dictionary in _catalog.in_category(CosmeticCatalog.TRAIL):
		used[int(_catalog.typed_params(str(it["id"]))["style"])] = true
	for style: int in TRAIL_STYLE_COUNT:
		assert_true(used.has(style), "trail style %d used" % style)
	assert_eq(_catalog.options("trail_styles").size(), TRAIL_STYLE_COUNT)


func test_every_core_skin_and_trail_has_its_own_style() -> void:
	for category: String in [CosmeticCatalog.CORE_SKIN, CosmeticCatalog.TRAIL]:
		var owner: Dictionary = {}
		for it: Dictionary in _catalog.in_category(category):
			var style: int = int(_catalog.typed_params(str(it["id"]))["style"])
			assert_false(owner.has(style), "%s shares style %d with %s" % [it["id"], style, str(owner.get(style))])
			owner[style] = it["id"]


func test_shop_swatch_plays_each_core_skin_live() -> void:
	for it: Dictionary in _catalog.in_category(CosmeticCatalog.CORE_SKIN):
		var params: Dictionary = it.get("params", {}) as Dictionary
		var swatch: CosmeticSwatch = CosmeticSwatch.new()
		swatch.setup(CosmeticCatalog.CORE_SKIN, params, false)
		assert_true(swatch.is_live(), "%s is shown with its own style before purchase" % it["id"])
		var mat: ShaderMaterial = swatch._live.material as ShaderMaterial
		assert_eq(int(mat.get_shader_parameter("style")), int(params["style"]), "%s style" % it["id"])
		assert_near(float(mat.get_shader_parameter("dim")), CosmeticSwatch.LOCKED_DIM, 0.0001, "not owned yet")
		swatch.free()
	var trail: CosmeticSwatch = CosmeticSwatch.new()
	trail.setup(CosmeticCatalog.TRAIL, {"style": 3}, true)
	assert_false(trail.is_live(), "other categories keep the flat drawing")
	trail.free()


func test_extra_core_skins_vary_colours_and_animation() -> void:
	var seen: Dictionary = {}
	for it: Dictionary in _catalog.in_category(CosmeticCatalog.CORE_SKIN):
		var p: Dictionary = _catalog.typed_params(str(it["id"]))
		var signature: String = (
			"%d|%s|%s|%s|%.2f"
			% [
				int(p["style"]),
				(p["color_a"] as Color).to_html(),
				(p["color_b"] as Color).to_html(),
				(p["rim"] as Color).to_html(),
				float(p["anim_speed"]),
			]
		)
		assert_false(seen.has(signature), "core skin %s duplicates %s" % [it["id"], str(seen.get(signature))])
		seen[signature] = it["id"]


func test_exactly_one_default_per_category() -> void:
	for category: String in _catalog.categories():
		var defaults: int = 0
		for it: Dictionary in _catalog.in_category(category):
			if _catalog.unlock_of(str(it["id"]))["type"] == CosmeticCatalog.UNLOCK_DEFAULT:
				defaults += 1
		assert_eq(defaults, 1, "defaults in %s" % category)
		assert_false(_catalog.default_for(category).is_empty(), "default id for %s" % category)


func test_badges_are_never_purchasable() -> void:
	for it: Dictionary in _catalog.in_category(CosmeticCatalog.BADGE):
		var type: String = str(_catalog.unlock_of(str(it["id"]))["type"])
		assert_has(CosmeticCatalog.BADGE_UNLOCKS, type, "badge %s unlock" % it["id"])
		assert_empty(_catalog.products_containing(str(it["id"])), "badge %s sold" % it["id"])


func test_badges_cover_every_perfect_tier() -> void:
	# The reward engine grants "badge_perfect_<tier>" on a tier's first perfect.
	var tiers: PackedStringArray = _catalog.options("perfect_tiers")
	assert_eq(tiers.size(), 10, "ten difficulty tiers")
	for tier: String in tiers:
		var id: String = "badge_perfect_%s" % tier
		assert_true(_catalog.has_item(id), "%s defined" % id)
		assert_eq(_catalog.unlock_of(id), {"type": "perfects", "value": tier}, "%s unlock" % id)


func test_premium_items_only_in_products() -> void:
	for it: Dictionary in _catalog.items:
		var id: String = str(it["id"])
		var premium: bool = _catalog.unlock_of(id)["type"] == CosmeticCatalog.UNLOCK_PREMIUM
		var sold: bool = not _catalog.products_containing(id).is_empty()
		assert_eq(premium, sold, "%s premium=%s sold=%s" % [id, str(premium), str(sold)])


func test_shipped_params_parse_to_typed_values() -> void:
	var core: Dictionary = _catalog.typed_params("core_fire")
	assert_eq(typeof(core["color_a"]), TYPE_COLOR, "color_a is Color")
	assert_eq(typeof(core["style"]), TYPE_INT, "style is int")
	assert_eq(typeof(core["anim_speed"]), TYPE_FLOAT, "anim_speed is float")
	assert_eq(int(core["style"]), 1, "fire style")
	assert_true((core["color_a"] as Color).is_equal_approx(Color.html("#ff7a1a")), "fire colour")
	var particle: Dictionary = _catalog.typed_params("particle_confetti")
	var colors: Array[Color] = particle["colors"] as Array[Color]
	assert_eq(colors.size(), 4, "confetti colours")
	var bg: Dictionary = _catalog.typed_params("bg_world")
	assert_true(bool(bg["use_world_palette"]), "default sky follows the world palette")
	assert_eq(typeof(_catalog.typed_params("badge_newcomer")["color"]), TYPE_COLOR)
	assert_empty(_catalog.typed_params("no_such_item"), "unknown id")


func test_item_returns_copy() -> void:
	var it: Dictionary = _catalog.item("core_fire")
	it["rarity"] = "legendary"
	assert_eq(str(_catalog.item("core_fire")["rarity"]), "common", "catalog not mutated through item()")
	assert_empty(_catalog.item("missing"), "unknown item")
