extends TestCase
## AppServices and the cloud save: off (and honestly labelled) in the shipped
## configuration, switched on by the remote cloud_save.base_url, and a merge
## from the cloud refreshes everything derived from the profile.

const NOW: int = 1790553600  # 2026-09-28 (UTC)
const CLOUD_URL: String = "https://saves.invalid"


## In-memory cloud server (GET / PUT /v1/saves/{id} with revisions).
class MemoryCloudServer:
	extends RefCounted
	var blob: String = ""
	var revision_number: int = 0
	var calls: int = 0

	func request(method: String, _url: String, body: Dictionary) -> Dictionary:
		calls += 1
		if method == "GET":
			if blob.is_empty():
				return {"ok": false, "status": 404, "body": {}, "error": ""}
			return {"ok": true, "status": 200, "body": {"blob": blob, "revision": "r%d" % revision_number}, "error": ""}
		blob = str(body.get("blob", ""))
		revision_number += 1
		return {"ok": true, "status": 200, "body": {"revision": "r%d" % revision_number}, "error": ""}


var _app: AppServices


func _boot() -> void:
	_app = AppServices.new()
	_app.auto_boot = false
	tree.root.add_child(_app)
	var clock: GameClock = GameClock.new()
	clock.set_fixed_unix(NOW)
	_app.boot(MemorySaveStorage.new(), clock)


func after_each() -> void:
	if _app != null:
		_app.queue_free()
	await wait_frames(2)


func test_cloud_is_off_by_default() -> void:
	_boot()
	assert_eq(_app.remote_config.get_string(AppServices.CLOUD_URL_KEY), "", "no server in the shipped config")
	assert_false(_app.cloud.is_enabled())
	assert_eq(_app.cloud.status, CloudSaveService.STATUS_OFF)
	var view: Dictionary = Presenters.cloud_status(_app)
	assert_false(bool(view["enabled"]), "Sync now is disabled")
	assert_eq(str(view["text"]), Presenters.t("cloud.status.off"), "and says the feature is not available")
	assert_true(Presenters.settings(_app, "").has("cloud"), "the Settings payload carries it")
	assert_eq(await _app.cloud.sync(), CloudSaveService.STATUS_OFF, "a manual sync does nothing")
	_app.flush_now()
	assert_false(_app.cloud.is_syncing(), "pausing never starts a sync while off")


func test_remote_url_turns_the_cloud_on() -> void:
	_boot()
	var insecure: Dictionary = {AppServices.CLOUD_URL_KEY: "http://saves.invalid"}
	var rejected: PackedStringArray = _app.remote_config.apply_overrides(insecure)
	assert_has(rejected, AppServices.CLOUD_URL_KEY, "insecure URLs are refused like every remote URL")
	assert_false(_app.cloud.is_enabled())
	_app.remote_config.apply_overrides({AppServices.CLOUD_URL_KEY: CLOUD_URL})
	assert_true(_app.cloud.is_enabled(), "the configured server turns it on")
	assert_eq(_app.cloud.status, CloudSaveService.STATUS_IDLE)
	assert_true(bool(Presenters.cloud_status(_app)["enabled"]))
	_app.remote_config.reset_overrides()
	assert_false(_app.cloud.is_enabled(), "and off again")
	assert_eq(_app.cloud.status, CloudSaveService.STATUS_OFF)


func test_cloud_merge_refreshes_the_game() -> void:
	_boot()
	var server: MemoryCloudServer = MemoryCloudServer.new()
	var other: PlayerProfile = PlayerProfile.from_dict(_app.profile.to_dict())
	other.coins = 2400
	other.ledger.append({"t": NOW - 60, "c": "coins", "d": 2300, "s": "daily_streak:3", "b": 2400})
	other.bonus_stars = 3
	other.achievements["first_clear"] = NOW - 600
	other.levels["w01_l01"] = {"stars": 3, "clears": 1, "perfect": true}
	server.blob = SaveService.encode(other, NOW - 60)
	server.revision_number = 4
	var tracked: Array[String] = []
	_app.cloud.sync_finished.connect(func(status: StringName, _c: bool) -> void: tracked.append(String(status)))
	_app.cloud.set_provider(HttpCloudSaveProvider.new(CLOUD_URL, server.request, _app.profile.install_id))
	assert_eq(await _app.cloud.sync(), CloudSaveService.STATUS_SYNCED)
	assert_eq(_app.economy.balance(EconomyService.COINS), 2400, "the newer wallet")
	assert_eq(_app.progression.bonus_stars(), 3)
	assert_eq(_app.progression.total_stars(), _app.progression.campaign_stars() + 3)
	assert_true(_app.achievements.progress("first_clear")["unlocked"] as bool, "achievement carried over")
	assert_true(_app.progression.is_level_unlocked("w01_l02"), "the next level opens")
	assert_eq(_app.profile.stat(StatsService.UNIQUE_LEVELS_CLEARED), 1, "distinct counters follow the records")
	assert_eq(_app.profile.stat(StatsService.UNIQUE_PERFECTS), 1)
	assert_eq(_app.profile.stat(AchievementService.STAT_ACHIEVEMENTS_UNLOCKED), 1)
	assert_empty(_app.check_integrity(), "wallet and ledger still agree")
	assert_true(_app.save.dirty, "the merged profile is saved")
	assert_eq(tracked, ["synced"])
	assert_eq(_app.cloud.revision(), "r5")
