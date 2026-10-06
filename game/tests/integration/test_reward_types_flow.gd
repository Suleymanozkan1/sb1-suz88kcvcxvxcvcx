extends TestCase
## Stars, skin and trail rewards through the running app: a star reward
## unlocks a world at once while the campaign "x / max" stays honest, and an
## achievement's skin is named and previewed in its reveal.

const NOW: int = 1790553600  # 2026-09-28 (UTC)

var _app: AppServices
var _nodes: Array[Node] = []


func before_each() -> void:
	_app = AppServices.new()
	_app.auto_boot = false
	tree.root.add_child(_app)
	var clock: GameClock = GameClock.new()
	clock.set_fixed_unix(NOW)
	_app.boot(MemorySaveStorage.new(), clock)
	_nodes = []


func after_each() -> void:
	for n: Node in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_app.queue_free()
	await wait_frames(2)


func test_star_reward_unlocks_a_world_right_away() -> void:
	var count: int = _app.catalog.levels_in(1)
	var second: Dictionary = _app.catalog.world_at(2)
	var needed: int = int(second.get("unlock_stars", 0))
	var left: int = needed - 2
	for local: int in range(1, count + 1):
		var stars: int = clampi(left, 0, 3)
		left -= stars
		_app.profile.levels[WorldCatalog.level_id(1, local)] = {"stars": stars, "clears": 1}
	_app.progression.refresh_world_unlocks()
	assert_false(_app.progression.is_world_unlocked(str(second["id"])), "two stars short")
	var unlocked: Array[String] = []
	_app.bus.world_unlocked.connect(func(id: String) -> void: unlocked.append(id))
	var bundle: RewardBundle = _app.grant_reward_spec({"stars": 2}, "achievement:secret_time")
	assert_eq(bundle.amount_of(RewardBundle.TYPE_STARS), 2)
	assert_eq(unlocked, [str(second["id"])] as Array[String], "unlocked by the reward itself")
	assert_eq(int(_app.mode_progress()["stars"]), needed, "mode unlocks see the bonus stars")
	var view: Dictionary = Presenters.progress(_app, "overview", {})
	assert_eq(int(view["stars"]), needed - 2, "the Progress tile shows campaign stars")
	assert_le(float(view["stars"]), float(view["max_stars"]))
	assert_eq(int(view["bonus_stars"]), 2, "bonus stars shown apart")


func test_achievement_skin_is_named_in_its_reveal() -> void:
	var granted: Array[RewardBundle] = []
	_app.bus.reward_granted.connect(func(b: RewardBundle) -> void: granted.append(b))
	_app.profile.stats["bosses_cleared"] = 10
	assert_has(_app.achievements.evaluate(), "boss_10")
	var bundle: RewardBundle = null
	for b: RewardBundle in granted:
		if b.source == AchievementService.REWARD_SOURCE_PREFIX + "boss_10":
			bundle = b
	assert_true(bundle != null, "boss_10 paid its reward")
	assert_eq(bundle.amount_of(RewardBundle.TYPE_SKIN), 1, "as a typed skin")
	assert_true(_app.cosmetics.owns("core_shadow"))
	var extras: Dictionary = Presenters.reward_items(_app, bundle)
	var name: String = Presenters.t(str(_app.cosmetics_catalog.item("core_shadow")["name_key"]))
	assert_eq(str((extras["item_names"] as Dictionary)["core_shadow"]), name)
	assert_eq(str((extras["cosmetic"] as Dictionary)["category"]), CosmeticCatalog.CORE_SKIN, "previewed")
	var overlay: RewardOverlay = RewardOverlay.new()
	_nodes.append(overlay)
	tree.root.add_child(overlay)
	overlay.build()
	var payload: Dictionary = {"eyebrow": "", "title": "", "subtitle": "", "bundle": bundle}
	payload.merge(extras)
	overlay.enter(payload)
	var texts: PackedStringArray = PackedStringArray()
	for label: Node in overlay.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	assert_has(texts, name, "the skin's name")
	assert_has(texts, Presenters.t("reward.label.skin"), 'and "New skin"')
	assert_true(Presenters.reward_items(_app, RewardBundle.new("x").add(RewardBundle.TYPE_COINS, 5)).is_empty())
