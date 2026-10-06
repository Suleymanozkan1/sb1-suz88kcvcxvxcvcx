extends TestCase
## Regression tests for the integrated review (R-INT) findings in the UI:
## input handling, result/fail/shop/daily/progress/settings screens and the
## runtime language change.

const FIXED_UNIX: int = 1790000000

var _app: AppServices
var _session: GameplaySession
var _runs: RunController
var _last: RunResult
var _nodes: Array[Node] = []


func before_each() -> void:
	_app = AppServices.new()
	_app.auto_boot = false
	tree.root.add_child(_app)
	var clock: GameClock = GameClock.new()
	clock.set_fixed_unix(FIXED_UNIX)
	_app.boot(MemorySaveStorage.new(), clock)
	_session = GameplaySession.new()
	tree.root.add_child(_session)
	_runs = RunController.new(_app, _session)
	_last = null
	_session.run_ended.connect(func(r: RunResult) -> void: _last = r)
	_nodes.clear()


func after_each() -> void:
	TranslationServer.set_locale("en")
	for n: Node in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_session.queue_free()
	_app.queue_free()
	await wait_frames(2)


func _keep(n: Node) -> Node:
	_nodes.append(n)
	tree.root.add_child(n)
	return n


func _screen(s: UiScreen) -> UiScreen:
	_keep(s)
	s.build()
	return s


static func _touch(pressed: bool) -> InputEventScreenTouch:
	var e: InputEventScreenTouch = InputEventScreenTouch.new()
	e.pressed = pressed
	return e


static func _click(pressed: bool) -> InputEventMouseButton:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	return e


# --- UI --------------------------------------------------------------------------


func test_toggle_flips_once_per_physical_tap() -> void:
	var t: UiToggle = _keep(UiToggle.new()) as UiToggle
	var emitted: Array[bool] = []
	t.toggled_on.connect(func(v: bool) -> void: emitted.append(v))
	# One tap on a phone = a touch plus the emulated mouse click.
	t._gui_input(_touch(true))
	t._gui_input(_click(true))
	assert_true(t.value, "the switch changed")
	assert_eq(emitted.size(), 1, "one tap, one change")


func test_result_actions_take_no_taps_during_the_sequence() -> void:
	var c: CompleteOverlay = _screen(CompleteOverlay.new()) as CompleteOverlay
	var r: RunResult = RunResult.new()
	r.completed = true
	r.score = 1200
	r.stars = 2
	c.enter({"result": r, "reward": RewardBundle.new("run"), "can_double": true, "has_next": true})
	assert_eq(c._actions.mouse_behavior_recursive, Control.MOUSE_BEHAVIOR_DISABLED, "hidden actions are inert")
	c._seq_tween.custom_step(10.0)
	assert_eq(c._actions.mouse_behavior_recursive, Control.MOUSE_BEHAVIOR_INHERITED, "live once shown")


func test_leaving_overlay_releases_input_immediately() -> void:
	var router: ScreenRouter = _keep(ScreenRouter.new()) as ScreenRouter
	var pause: PauseOverlay = PauseOverlay.new()
	router.register(&"pause", pause)
	router.push_overlay(&"pause", {})
	assert_eq(pause.mouse_behavior_recursive, Control.MOUSE_BEHAVIOR_INHERITED)
	router.pop_overlay()
	assert_true(pause.visible, "still fading out")
	assert_eq(pause.mouse_behavior_recursive, Control.MOUSE_BEHAVIOR_DISABLED, "fading overlay takes no taps")


func test_language_change_rebuilds_built_screens() -> void:
	var router: ScreenRouter = _keep(ScreenRouter.new()) as ScreenRouter
	var settings: SettingsScreen = SettingsScreen.new()
	router.register(&"settings", settings)
	router.show_screen(&"settings", Presenters.settings(_app, ""))
	var first_child: Node = settings.get_child(0)
	router.relocalize()
	router.show_screen(&"settings", Presenters.settings(_app, ""))
	assert_ne(settings.get_child(settings.get_child_count() - 1), first_child, "controls were rebuilt")
	assert_true(first_child.is_queued_for_deletion(), "old controls are freed")


func test_shop_shows_price_and_shortfall_before_purchase() -> void:
	var shop: CosmeticsScreen = CosmeticsScreen.new()
	shop.mode = &"shop"
	_screen(shop)
	var payload: Dictionary = Presenters.cosmetics(_app, &"shop")
	var item: Dictionary = {}
	for raw: Variant in payload["items"] as Array:
		var it: Dictionary = raw as Dictionary
		if not (it.get("price", {}) as Dictionary).is_empty() and not bool(it.get("owned", false)):
			item = it
			break
	assert_false(item.is_empty(), "the shop sells something for currency")
	item["affordable"] = false
	payload["items"] = [item]
	shop.enter(payload)
	shop._selected = str(item["id"])
	shop._update_detail()
	var price: Dictionary = item["price"] as Dictionary
	var amount: int = int(price.values()[0])
	assert_true(shop._action.text.contains(UiKit.format_int(amount)), "price on the button: %s" % shop._action.text)
	assert_true(shop._action.disabled, "unaffordable item cannot be bought")
	assert_true(shop._detail_info.text.contains(" · ") or shop._detail_info.text.contains("·"), "shortfall explained")


func test_owned_pack_reads_owned_and_price_is_shown() -> void:
	var shop: CosmeticsScreen = CosmeticsScreen.new()
	shop.mode = &"shop"
	_screen(shop)
	var payload: Dictionary = {
		"items": [],
		"categories": [],
		"store_available": true,
		"packs":
		[
			{"id": "a", "name": "A", "items_label": "3", "owned": true, "price": "$1.99", "available": false},
			{"id": "b", "name": "B", "items_label": "3", "owned": false, "price": "$2.99", "available": true},
		]
	}
	shop.enter(payload)
	var buttons: Array[UiButton] = []
	for n: Node in shop.find_children("*", "UiButton", true, false):
		var b: UiButton = n as UiButton
		if b.text == TranslationServer.translate("shop.owned") or b.text == "$2.99":
			buttons.append(b)
	assert_eq(buttons.size(), 2, "owned label and store price both shown")
	for b: UiButton in buttons:
		assert_eq(b.disabled, b.text != "$2.99", "only the unowned pack is purchasable")


func test_daily_rank_uses_the_service_total() -> void:
	var daily: DailyScreen = _screen(DailyScreen.new()) as DailyScreen
	daily.enter({"status": {"played": true, "best_score": 900}, "rank": {"rank": 2, "total": 5}, "unlocked": true})
	assert_eq(daily._rank.text, TranslationServer.translate("daily.rank_of").format({"rank": 2, "of": 5}))
	daily.enter({"status": {"played": false}, "rank": {"rank": 1, "total": 1}, "unlocked": true})
	assert_eq(daily._rank.text, "—", "no rank before playing")


func test_locked_daily_button_fits_the_screen() -> void:
	var limit: float = 720.0 - 2.0 * UiTokens.MARGIN
	for locale: String in ["en", "tr"]:
		TranslationServer.set_locale(locale)
		var daily: DailyScreen = _screen(DailyScreen.new()) as DailyScreen
		for key: String in ["daily.paused", "mode.unlock.levels_cleared"]:
			var label: String = TranslationServer.translate(key).format({"n": 20})
			daily.enter({"status": {}, "unlocked": false, "requirement": label})
			assert_true(daily._play.disabled, "locked button is inert")
			assert_le(daily._play.get_combined_minimum_size().x, limit, "%s %s fits" % [locale, key])


func test_intro_levels_name_their_new_mechanic() -> void:
	var intros: Array[String] = []
	for w: Dictionary in WorldCatalog.load_default().worlds:
		for c: Variant in w.get("chapters", []) as Array:
			intros.append(str((c as Dictionary).get("intro", "")))
	assert_eq(intros.size(), 40, "four chapters in each of ten worlds")
	for locale: String in ["en", "tr"]:
		TranslationServer.set_locale(locale)
		for intro: String in intros:
			var key: String = Hud.intro_hint_key(intro)
			assert_ne(TranslationServer.translate(key), key, "%s hint for %s" % [locale, intro])
	TranslationServer.set_locale("en")
	var hud: Hud = _screen(Hud.new()) as Hud
	hud.bind(_session)
	_session.level_data = {"intro_mechanic": "launch_pads", "mechanics": ["hop", "launch"]}
	hud.enter({})
	assert_eq(hud._intro_hint.text, str(TranslationServer.translate("hint.mechanic.launch_pads")), "named at the start")
	assert_gt(hud._intro_hint.modulate.a, 0.5, "and visible")
	_session.level_data = {"intro_mechanic": "", "mechanics": ["hop"]}
	hud.enter({})
	assert_eq(hud._intro_hint.text, "", "regular levels show no caption")


func test_durations_use_localized_units() -> void:
	TranslationServer.set_locale("tr")
	assert_eq(DailyScreen.format_duration(2 * 86400 + 3 * 3600), "2 g 03 sa")
	assert_eq(DailyScreen.format_duration(5 * 3600 + 4 * 60), "5 sa 04 dk")
	TranslationServer.set_locale("en")
	assert_eq(DailyScreen.format_duration(12 * 60 + 9), "12m 09s")


func test_endless_fail_shows_distance_not_zero_percent() -> void:
	var fail: FailOverlay = _screen(FailOverlay.new()) as FailOverlay
	var r: RunResult = RunResult.new()
	r.distance = 3000.4
	fail.enter({"result": r, "best": 0, "progress": -1.0, "can_revive": false})
	assert_false(fail._progress.visible, "no progress bar on a course without an end")
	assert_true(fail._progress_label.text.contains(UiKit.format_int(3000)), fail._progress_label.text)
	assert_true(_runs.prepare(&"endless"), "endless prepared")
	_session.begin(0.0)
	_session.step_ticks(60 * 120)
	assert_true(_last != null and not _last.completed, "endless run ended")
	assert_lt(float(_runs.preview(_last)["progress"]), 0.0, "streamed course reports no percentage")


func test_hud_score_is_centred_without_objective() -> void:
	assert_true(_runs.prepare(&"classic", "w01_l01"))
	var hud: Hud = Hud.new()
	hud.bind(_session)
	_screen(hud)
	hud.enter({})
	assert_false(hud._objective.visible, "reach-the-end level hides the objective")
	await wait_frames(3)
	var centre: float = hud._score.get_global_rect().get_center().x
	assert_near(centre, hud.get_global_rect().get_center().x, 2.0, "score at top centre")


func test_leaderboard_segment_matches_first_board_on_entry() -> void:
	var progress: ProgressScreen = _screen(ProgressScreen.new()) as ProgressScreen
	var payload: Dictionary = Presenters.progress(_app, "overview", {})
	progress.enter(payload)
	progress._boards.select("endless", false)
	progress.enter(payload)
	assert_eq(progress._boards.current, "daily", "segment shows the board the flow loads")


func test_volume_sliders_meet_touch_target() -> void:
	var settings: SettingsScreen = _screen(SettingsScreen.new()) as SettingsScreen
	var sliders: Array[Node] = settings.find_children("*", "HSlider", true, false)
	assert_gt(float(sliders.size()), 0.0)
	for n: Node in sliders:
		assert_ge((n as HSlider).custom_minimum_size.y, float(UiTokens.MIN_TOUCH), "slider height")


func test_theme_cosmetic_recolours_the_ui_and_default_restores_it() -> void:
	var t: Theme = UiTheme.get_theme()
	var params: Dictionary = _app.cosmetics.theme_params("theme_ember")
	assert_true(UiTheme.apply_accent(params), "changed")
	assert_eq((t.get_stylebox("normal", "PrimaryButton") as StyleBoxFlat).bg_color, params["accent"] as Color)
	assert_eq((t.get_stylebox("fill", "ProgressBar") as StyleBoxFlat).bg_color, params["accent"] as Color)
	assert_true(UiTheme.apply_accent({}), "restored")
	assert_eq((t.get_stylebox("normal", "PrimaryButton") as StyleBoxFlat).bg_color, Palette.PRIMARY)
	assert_false(UiTheme.apply_accent({}), "no change twice")


func test_emblem_shows_the_worn_avatar_frame_and_badge() -> void:
	assert_true(Presenters.worn(_app, CosmeticCatalog.THEME).is_empty(), "default items override nothing")
	var em: Dictionary = Presenters.emblem(_app)
	assert_true(em["badge"] is Dictionary and (em["badge"] as Dictionary).is_empty(), "starter badge stays quiet")
	var emblem: ProfileEmblem = _keep(ProfileEmblem.new()) as ProfileEmblem
	emblem.size = Vector2(88, 88)
	emblem.setup(em)
	assert_eq(emblem._avatar.category, "avatar")
	assert_eq(emblem._frame.category, "frame")
	assert_false(emblem._badge.visible)
	assert_eq(emblem._avatar.params, em["avatar"] as Dictionary, "the equipped avatar is drawn")


func test_shop_says_what_an_item_changes() -> void:
	var shop: CosmeticsScreen = CosmeticsScreen.new()
	shop.mode = &"shop"
	_screen(shop)
	var payload: Dictionary = Presenters.cosmetics(_app, &"shop")
	var seen: Dictionary = {}
	for raw: Variant in payload["items"] as Array:
		var it: Dictionary = raw as Dictionary
		if seen.has(it["category"]):
			continue
		seen[it["category"]] = true
		shop.enter(payload)
		shop._selected = str(it["id"])
		shop._update_detail()
		var key: String = "shop.affects." + str(it["category"])
		assert_eq(shop._detail_effect.text, str(TranslationServer.translate(key)), str(it["id"]))
		assert_ne(shop._detail_effect.text, key, "translated: %s" % key)


func test_daily_result_card_shows_the_rank() -> void:
	var c: CompleteOverlay = _screen(CompleteOverlay.new()) as CompleteOverlay
	var r: RunResult = RunResult.new()
	r.completed = true
	r.score = 900
	var rank: Dictionary = _app.daily.rank_text_local(900)
	var text: String = Presenters.t(str(rank["key"])).format(rank["params"] as Dictionary)
	c.enter({"result": r, "reward": RewardBundle.new("run"), "rank_text": text})
	assert_true(c._rank.visible and c._rank.text == text, "rank line on the daily card")
	c.enter({"result": r, "reward": RewardBundle.new("run")})
	assert_false(c._rank.visible, "no rank line for other modes")
