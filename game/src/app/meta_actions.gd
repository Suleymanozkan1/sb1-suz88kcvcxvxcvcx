class_name MetaActions
extends Node
## Answers the meta screens' intents outside a run: mission claims and the
## optional bonus chest (Daily), the optional double reward (result card),
## leaderboards (Progress), buying, equipping and store packs (Shop,
## Collection) and restoring purchases (Settings). Everything it grants is
## shown through the [RevealQueue].
##
## A child of [GameFlow]: an ad or store call in progress ends with the app root.

var _s: AppServices
var _router: ScreenRouter
var _runs: RunController
var _reveals: RevealQueue
var _restore_status: String = ""


func _init(app: AppServices, screen_router: ScreenRouter, run_controller: RunController, queue: RevealQueue) -> void:
	_s = app
	_router = screen_router
	_runs = run_controller
	_reveals = queue


## The Settings payload, with the status line of the last purchase restore.
func settings_payload() -> Dictionary:
	return Presenters.settings(_s, _restore_status)


func claim_mission(mission_id: String) -> void:
	var bundle: RewardBundle = _s.missions.claim(mission_id)
	if bundle == null or bundle.is_empty():
		return
	_s.analytics.track(&"mission_claimed", {"mission_id": mission_id})
	_reveals.add_level_ups()
	_router.show_screen(&"daily", Presenters.daily(_s))
	_reveals.add(
		{
			"eyebrow": Presenters.t("reveal.mission"),
			"title": Presenters.t("reveal.mission_done"),
			"subtitle": "",
			"bundle": bundle
		}
	)
	_reveals.show_next()


## Optional rewarded bonus chest (Daily screen, once a day): the fixed
## reward_tables bonus_chest contents, granted only after the ad completed.
func open_bonus_chest() -> void:
	if not Presenters.bonus_chest_offered(_s):
		return
	var shown: Dictionary = await _s.ads.show_rewarded(&"bonus_chest")
	if not bool(shown.get("granted", false)):
		return
	_s.profile.flags[Presenters.BONUS_CHEST_FLAG] = _s.clock.day_number()
	var bundle: RewardBundle = _s.rewards.grant(_s.rewards.compute(RewardEngine.TABLE_BONUS_CHEST))
	_s.save.mark_dirty()
	(_router.screen(&"daily") as DailyScreen).enter(Presenters.daily(_s))
	var title: String = Presenters.t("reveal.bonus_chest")
	_reveals.add({"eyebrow": Presenters.t("reveal.bonus"), "title": title, "subtitle": "", "bundle": bundle})
	# The chest's XP can level the player up: say so now, not after the next run.
	_reveals.add_level_ups()
	_reveals.show_next()


## The optional rewarded double of the result card showing [param outcome]
## ([method RunController.finish]). One per result: the outcome is marked and
## the button goes away before the ad runs; the extra is granted only after
## the ad completed.
func double_reward(outcome: Dictionary) -> void:
	var bundle: RewardBundle = outcome.get("reward") as RewardBundle
	if bundle == null or bool(outcome.get("doubled", false)):
		return
	outcome["doubled"] = true
	outcome["can_double"] = false
	(_router.screen(&"complete") as CompleteOverlay).disable_double()
	var shown: Dictionary = await _s.ads.show_rewarded(&"double_reward")
	if not bool(shown.get("granted", false)):
		return
	var extra: RewardBundle = _runs.grant_double(bundle)
	_reveals.add(
		{
			"eyebrow": Presenters.t("reveal.bonus"),
			"title": Presenters.t("reveal.doubled"),
			"subtitle": "",
			"bundle": extra
		}
	)
	_reveals.show_next()


## Fetches [param board_id] and shows it if Progress is still the screen.
func load_board(board_id: String) -> void:
	var fetched: Dictionary = await _s.leaderboard.fetch(board_id)
	var screen: ProgressScreen = _router.screen(&"progress") as ProgressScreen
	if screen != null and _router.current_id == &"progress":
		screen.show_board(Presenters.board_view(_s, fetched))


func buy(item_id: String) -> void:
	if _s.cosmetics.purchase(item_id):
		_s.cosmetics.equip(item_id)
		_s.achievements.evaluate()
	_refresh_cosmetics()


func equip(item_id: String) -> void:
	_s.cosmetics.equip(item_id)
	_refresh_cosmetics()


func buy_pack(product_id: String) -> void:
	var result: Dictionary = await _s.store.purchase(product_id)
	if not bool(result.get("ok", false)):
		_s.bus.toast_requested.emit(Presenters.t(StoreService.message_key(str(result.get("error", "")))), &"info")
	_refresh_cosmetics()


func restore_purchases() -> void:
	_restore_status = Presenters.t("settings.restoring")
	var screen: SettingsScreen = _router.screen(&"settings") as SettingsScreen
	screen.set_restore_status(_restore_status)
	var result: Dictionary = await _s.store.restore_purchases()
	if bool(result.get("ok", false)):
		_restore_status = Presenters.t("settings.restored").format(
			{"n": (result.get("product_ids", []) as Array).size()}
		)
	else:
		_restore_status = Presenters.t(StoreService.message_key(str(result.get("error", ""))))
	screen.set_restore_status(_restore_status)


## Shop or Collection, rebuilt in place after a purchase or an equip.
func _refresh_cosmetics() -> void:
	_router.show_screen(_router.current_id, Presenters.cosmetics(_s, _router.current_id))
