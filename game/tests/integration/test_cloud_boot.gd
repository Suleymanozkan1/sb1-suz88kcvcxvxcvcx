extends TestCase
## AppServices and the cloud save: off (and honestly labelled) in the shipped
## configuration, switched on by the remote cloud_save.base_url, a merge from
## the cloud refreshes everything derived from the profile without counting as
## earning, and the "changes not in the cloud yet" flag is part of every save
## written on pause (review R-6 findings 3 and 4).

const NOW: int = 1790553600  # 2026-09-28 (UTC)
const CLOUD_URL: String = "https://saves.invalid"


## In-memory cloud server (GET / PUT /v1/saves/{id} with revisions). With
## [member hold] every request waits for [signal released] (the OS suspends
## the app before the request completes).
class MemoryCloudServer:
	extends RefCounted
	signal released
	var hold: bool = false
	var blob: String = ""
	var revision_number: int = 0
	var calls: int = 0

	func request(method: String, _url: String, body: Dictionary) -> Dictionary:
		calls += 1
		if hold:
			await released
		if method == "GET":
			if blob.is_empty():
				return {"ok": false, "status": 404, "body": {}, "error": ""}
			return {"ok": true, "status": 200, "body": {"blob": blob, "revision": "r%d" % revision_number}, "error": ""}
		blob = str(body.get("blob", ""))
		revision_number += 1
		return {"ok": true, "status": 200, "body": {"revision": "r%d" % revision_number}, "error": ""}


var _app: AppServices


func _boot(storage: SaveStorage = null) -> void:
	_app = AppServices.new()
	_app.auto_boot = false
	tree.root.add_child(_app)
	var clock: GameClock = GameClock.new()
	clock.set_fixed_unix(NOW)
	_app.boot(storage if storage != null else MemorySaveStorage.new(), clock)


func _connect(server: MemoryCloudServer) -> void:
	_app.cloud.set_provider(HttpCloudSaveProvider.new(CLOUD_URL, server.request, _app.profile.install_id))


## The flags of the save on disk.
static func _disk_flags(storage: SaveStorage) -> Dictionary:
	var decoded: Dictionary = SaveService.decode(storage.read_text(SaveService.MAIN))
	return (decoded["payload"] as Dictionary).get("flags", {}) as Dictionary


static func _server_coins(server: MemoryCloudServer) -> int:
	return PlayerProfile.from_dict(SaveService.decode(server.blob)["payload"] as Dictionary).coins


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


## Review R-6 finding 3 (earned.gd): the other device's coins arrive with the
## merge; they were earned there, so they neither count as coins earned here
## nor unlock (and pay) a coin achievement at the next evaluation.
func test_a_merge_is_not_earning() -> void:
	_boot()
	var server: MemoryCloudServer = MemoryCloudServer.new()
	var other: PlayerProfile = PlayerProfile.from_dict(_app.profile.to_dict())
	other.coins = 30000
	other.stats[StatsService.COINS_EARNED] = 30000
	other.achievements["coins_1000"] = NOW - 5000
	other.achievements["coins_10000"] = NOW - 4000
	other.ledger.append({"t": NOW - 60, "c": "coins", "d": 29900, "s": "level:w01_l01", "b": 30000})
	server.blob = SaveService.encode(other, NOW - 60)
	server.revision_number = 3
	var earned_before: int = _app.profile.stat(StatsService.COINS_EARNED)
	_connect(server)
	assert_eq(await _app.cloud.sync(), CloudSaveService.STATUS_SYNCED)
	assert_eq(_app.economy.balance(EconomyService.COINS), 30000, "the account wallet arrived")
	assert_eq(
		_app.profile.stat(StatsService.COINS_EARNED),
		maxi(earned_before, 30000),
		"coins earned merge by maximum; the arrival is not earning"
	)
	assert_empty(_app.achievements.evaluate(), "no coin achievement for coins that only arrived")
	assert_eq(_app.economy.balance(EconomyService.COINS), 30000, "and nothing was paid out")
	assert_eq(_app.economy.balance(EconomyService.GEMS), 0)


## Review R-6 finding 4 (pause_flag.gd): the app is paused (and killed)
## seconds after a change, before the autosave and while the sync it started
## is still in flight: the save written on pause already says the cloud has
## not seen the change, so the next launch uploads it.
func test_pause_right_after_a_change_keeps_the_cloud_flag_on_disk() -> void:
	var storage: MemorySaveStorage = MemorySaveStorage.new()
	_boot(storage)
	var server: MemoryCloudServer = MemoryCloudServer.new()
	_connect(server)
	assert_eq(await _app.cloud.sync(), CloudSaveService.STATUS_SYNCED)
	_app.flush_now()
	assert_false(_app.cloud.is_dirty())
	assert_false(bool(_disk_flags(storage).get(CloudSaveService.FLAG_DIRTY, false)))
	_app.economy.grant(EconomyService.COINS, 250, "level:w01_l01")
	_app.save.mark_dirty()
	server.hold = true
	_app.flush_now()
	assert_true(_app.cloud.is_syncing(), "the pause starts a sync")
	assert_true(bool(_disk_flags(storage).get(CloudSaveService.FLAG_DIRTY, false)), "written with the save")
	var local_coins: int = _app.profile.coins
	_app.queue_free()
	await wait_frames(1)
	server.hold = false
	_boot(storage)
	_connect(server)
	assert_true(_app.cloud.is_dirty(), "the next launch knows the cloud is behind")
	assert_eq(await _app.cloud.sync(), CloudSaveService.STATUS_SYNCED)
	assert_eq(_server_coins(server), local_coins, "and uploads the change")


## Review R-6 finding 4, the commit-on-leave path: the pause flush finds
## nothing new, then the fail card's pending run is committed and flushed
## again while the app goes to the background.
func test_commit_on_leave_keeps_the_cloud_flag_on_disk() -> void:
	var storage: MemorySaveStorage = MemorySaveStorage.new()
	_boot(storage)
	var server: MemoryCloudServer = MemoryCloudServer.new()
	_connect(server)
	assert_eq(await _app.cloud.sync(), CloudSaveService.STATUS_SYNCED)
	_app.flush_now()
	server.hold = true
	_app.flush_now()
	assert_false(_app.cloud.is_syncing(), "nothing new: the first pause flush starts no sync")
	_app.economy.grant(EconomyService.COINS, 40, "level:w01_l02")
	_app.profile.levels["w01_l02"] = {"stars": 1, "clears": 1}
	_app.flush_now()
	assert_true(bool(_disk_flags(storage).get(CloudSaveService.FLAG_DIRTY, false)), "the committed run is flagged")
	server.hold = false
	server.released.emit()
	await wait_frames(1)
	assert_false(_app.cloud.is_dirty(), "the sync it started uploaded the run")
	assert_eq(_server_coins(server), _app.profile.coins)
	_app.flush_now()
	assert_false(bool(_disk_flags(storage).get(CloudSaveService.FLAG_DIRTY, true)), "and the next save says so")
