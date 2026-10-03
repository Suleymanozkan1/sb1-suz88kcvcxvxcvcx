extends TestCase
## ProgressionService.next_unlock_hint: the main-menu goal at every stage.

var profile: PlayerProfile
var catalog: WorldCatalog


func before_each() -> void:
	profile = PlayerProfile.new()
	catalog = WorldCatalog.load_default()


func _service() -> ProgressionService:
	return ProgressionService.new(profile, EventBus.new(), catalog)


func _clear_direct(world_index: int, from_local: int, to_local: int, stars: int) -> void:
	for local_index: int in range(from_local, to_local + 1):
		profile.levels[WorldCatalog.level_id(world_index, local_index)] = {
			"stars": stars, "best_score": 100, "perfect": stars == 3, "clears": 1,
			"attempts": 1, "best_combo": 3, "best_time": 20.0,
		}


func _assert_shape(hint: Dictionary) -> void:
	for key: String in ["type", "id", "progress", "target", "label_key"]:
		assert_has(hint, key, "hint has %s" % key)
	assert_true(["world", "level", "player_level"].has(str(hint["type"])), "known hint type")
	assert_le(int(hint["progress"]), int(hint["target"]), "progress never exceeds target")
	assert_true(str(hint["label_key"]).begins_with("progression.hint."))


func test_fresh_profile_points_to_first_level() -> void:
	var hint: Dictionary = _service().next_unlock_hint()
	_assert_shape(hint)
	assert_eq(hint["type"], "level")
	assert_eq(hint["id"], "w01_l01")
	assert_eq(int(hint["progress"]), 0)
	assert_eq(int(hint["target"]), 52, "progress through the first world")


func test_mid_world_points_to_next_level() -> void:
	_clear_direct(1, 1, 10, 2)
	var hint: Dictionary = _service().next_unlock_hint()
	_assert_shape(hint)
	assert_eq(hint["type"], "level")
	assert_eq(hint["id"], "w01_l11")
	assert_eq(int(hint["progress"]), 10)
	assert_eq(int(hint["target"]), 52)


func test_star_blocked_world_shows_star_goal() -> void:
	_clear_direct(1, 1, 52, 1)
	var hint: Dictionary = _service().next_unlock_hint()
	_assert_shape(hint)
	assert_eq(hint["type"], "world", "boss beaten but stars short")
	assert_eq(hint["id"], "crystal_valley")
	assert_eq(int(hint["progress"]), 52)
	assert_eq(int(hint["target"]), 90)


func test_mid_game_after_world_unlock_points_into_new_world() -> void:
	_clear_direct(1, 1, 52, 2)
	_clear_direct(2, 1, 20, 2)
	var hint: Dictionary = _service().next_unlock_hint()
	_assert_shape(hint)
	assert_eq(hint["type"], "level")
	assert_eq(hint["id"], "w02_l21")
	assert_eq(int(hint["progress"]), 20)


func test_campaign_cleared_then_stars_then_player_level() -> void:
	for w: int in range(1, 11):
		_clear_direct(w, 1, 52, 2)
	var svc: ProgressionService = _service()
	assert_true(svc.is_world_unlocked("candy_reactor"), "1040 stars open every world")
	var stars_hint: Dictionary = svc.next_unlock_hint()
	_assert_shape(stars_hint)
	assert_eq(stars_hint["type"], "level")
	assert_eq(stars_hint["label_key"], ProgressionService.HINT_KEY_STARS, "improve stars once all is cleared")
	assert_eq(stars_hint["id"], "w01_l01")
	assert_eq(int(stars_hint["progress"]), 1040)
	assert_eq(int(stars_hint["target"]), 1560)
	assert_eq(svc.next_level_to_play(), "w10_l52", "nothing uncleared: highest unlocked")
	for w2: int in range(1, 11):
		_clear_direct(w2, 1, 52, 3)
	var level_hint: Dictionary = svc.next_unlock_hint()
	_assert_shape(level_hint)
	assert_eq(level_hint["type"], "player_level")
	assert_eq(level_hint["id"], "2")
	assert_eq(int(level_hint["target"]), svc.xp_for_next(1))


func test_max_level_everything_done() -> void:
	for w: int in range(1, 11):
		_clear_direct(w, 1, 52, 3)
	var cfg: Dictionary = {"xp_caps": {"max_player_level": 3}}
	var svc: ProgressionService = ProgressionService.new(profile, EventBus.new(), catalog, cfg)
	svc.add_xp(5000)
	var hint: Dictionary = svc.next_unlock_hint()
	_assert_shape(hint)
	assert_eq(hint["type"], "player_level")
	assert_eq(hint["label_key"], ProgressionService.HINT_KEY_COMPLETE)
	assert_eq(int(hint["progress"]), int(hint["target"]))
