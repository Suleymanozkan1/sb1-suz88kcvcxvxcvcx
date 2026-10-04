extends TestCase
## Cloud save regressions (review R-6), end to end against an in-memory
## server that every device shares (a backend that links installs, or a
## restored install id): a fresh install never wipes the account wallet, both
## devices' spends and earnings apply exactly once whatever their clocks say,
## a purchase or reward made on both devices counts once, a lost push answer
## never duplicates the wallet, changes made during a download still go up,
## server-supplied lists merge in linear time, a day the device clock has not
## reached is never adopted, and the pushed copy carries no device-local data
## and never exceeds what a download can return.

const BASE_URL: String = "https://saves.invalid"
const NOW: int = 1790000000
const DAY: int = 86400
const INSTALL_ID: String = "0123456789abcdef0123456789abcdef"
const OTHER_INSTALL_ID: String = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const COINS: StringName = EconomyService.COINS
const LARGE_LIST: int = 30000
## Generous wall-clock budget for one linear pass over LARGE_LIST items (the
## quadratic version took several seconds).
const LINEAR_BUDGET_MS: int = 1000
const VETERAN_LEVELS: int = 40


## In-memory cloud save server implementing the documented contract (GET /
## PUT, revisions, 409 on a stale base revision). With [member hold] every
## request waits for [signal released]; [member lost_answers] PUTs are stored
## but their answer never reaches the client.
class MemoryCloudServer:
	extends RefCounted
	signal released
	var online: bool = true
	var hold: bool = false
	var lost_answers: int = 0
	var blob: String = ""
	var revision_number: int = 0
	var puts: int = 0

	func request(method: String, _url: String, body: Dictionary) -> Dictionary:
		if hold:
			await released
		if not online:
			return {"ok": false, "status": 0, "body": null, "error": "timeout"}
		if method == "GET":
			if blob.is_empty():
				return {"ok": false, "status": 404, "body": {}, "error": ""}
			return {"ok": true, "status": 200, "body": {"blob": blob, "revision": revision()}, "error": ""}
		puts += 1
		if str(body.get("base_revision", "")) != revision():
			return {"ok": false, "status": 409, "body": {"blob": blob, "revision": revision()}, "error": ""}
		store(str(body.get("blob", "")))
		if lost_answers > 0:
			lost_answers -= 1
			return {"ok": false, "status": 0, "body": null, "error": "timeout"}
		return {"ok": true, "status": 200, "body": {"revision": revision()}, "error": ""}

	func store(text: String) -> void:
		blob = text
		revision_number += 1

	func revision() -> String:
		return "" if blob.is_empty() else "r%d" % revision_number

	func payload() -> Dictionary:
		return SaveService.decode(blob)["payload"] as Dictionary

	func profile() -> PlayerProfile:
		return PlayerProfile.from_dict(payload())


var _clock: GameClock
var _server: MemoryCloudServer


func before_each() -> void:
	_clock = GameClock.new()
	_clock.set_fixed_unix(NOW)
	_server = MemoryCloudServer.new()


func _device(profile: PlayerProfile, clock: GameClock = null) -> CloudSaveService:
	var provider: HttpCloudSaveProvider = HttpCloudSaveProvider.new(
		BASE_URL, _server.request, profile.install_id, "1.0.0"
	)
	return CloudSaveService.new(provider, profile, clock if clock != null else _clock, null)


static func _record(stars: int) -> Dictionary:
	return {
		"stars": stars,
		"best_score": 100 * stars,
		"perfect": stars == 3,
		"clears": 1,
		"attempts": 2,
		"best_combo": 4,
		"best_time": 20.0,
	}


## A long-played save: [param coins] and [param gems] earned, 40 levels.
func _veteran(coins: int, gems: int) -> PlayerProfile:
	var p: PlayerProfile = PlayerProfile.create_new(NOW - 90 * DAY)
	p.install_id = INSTALL_ID
	p.coins = coins
	p.gems = gems
	p.xp = 50000
	p.ledger.append({"t": NOW - 2 * DAY, "c": "coins", "d": coins, "s": "level:w01_l40", "b": coins})
	p.ledger.append({"t": NOW - 2 * DAY, "c": "gems", "d": gems, "s": "achievement:first_clear", "b": gems})
	for i: int in VETERAN_LEVELS:
		p.levels["w01_l%02d" % (i + 1)] = _record(3)
	return p


## A brand-new install holding only the starting balance.
func _fresh(created_at: int, install_id: String = INSTALL_ID, clock: GameClock = null) -> PlayerProfile:
	var p: PlayerProfile = PlayerProfile.create_new(created_at)
	p.install_id = install_id
	_economy(p, clock).apply_starting_balance()
	return p


func _economy(p: PlayerProfile, clock: GameClock = null) -> EconomyService:
	return EconomyService.new(p, null, clock if clock != null else _clock)


## Two devices on one cloud slot, both synced to a 1000 coin / 10 gem wallet:
## [a, a_cloud, b, b_cloud].
func _pair() -> Array:
	var a: PlayerProfile = _veteran(1000, 10)
	var a_cloud: CloudSaveService = _device(a)
	a.xp += 1
	a_cloud.mark_dirty()
	assert_eq(await a_cloud.sync(), CloudSaveService.STATUS_SYNCED, "A uploads")
	var b: PlayerProfile = _fresh(NOW - 3600)
	var b_cloud: CloudSaveService = _device(b)
	assert_eq(await b_cloud.sync(), CloudSaveService.STATUS_SYNCED, "B downloads")
	assert_eq(await a_cloud.sync(), CloudSaveService.STATUS_SYNCED, "A sees B's copy")
	assert_eq(b.coins, 1000, "a pristine install takes the account wallet")
	assert_eq(a.coins, 1000)
	return [a, a_cloud, b, b_cloud]


## Review R-6 finding 1 (link_wipe.gd): the fresh install's boot sync found no
## cloud copy and uploaded its starting balance; once the backend links the
## install and serves the account's older copy, the account wallet must win.
func test_fresh_install_never_wipes_the_linked_account_wallet() -> void:
	var phone: PlayerProfile = _fresh(NOW, OTHER_INSTALL_ID)
	var cloud: CloudSaveService = _device(phone)
	assert_eq(await cloud.sync(), CloudSaveService.STATUS_SYNCED, "no cloud copy yet: the fresh save goes up")
	var account: PlayerProfile = _veteran(8000, 250)
	_server.store(SaveService.encode(account, NOW - DAY))
	_clock.set_fixed_unix(NOW + 600)
	assert_eq(await cloud.sync(), CloudSaveService.STATUS_SYNCED)
	assert_eq(phone.coins, 8000, "the account's wallet, not the starting balance")
	assert_eq(phone.gems, 250)
	assert_eq(phone.levels.size(), VETERAN_LEVELS, "and the account's progress")
	assert_eq(_server.profile().coins, 8000, "the cloud keeps the account wallet")
	assert_eq(_server.profile().gems, 250)
	assert_empty(IntegrityMonitor.new(phone).check(), "the ledger explains the wallet")


## Review R-6 finding 1 (fresh_wipe.gd): a fresh install that played once
## before its first successful sync adds what it earned beyond the starting
## balance; it never replaces the account wallet.
func test_fresh_install_that_played_offline_adds_only_its_earnings() -> void:
	var tablet: PlayerProfile = _veteran(5000, 300)
	var tablet_cloud: CloudSaveService = _device(tablet)
	tablet.xp += 1
	tablet_cloud.mark_dirty()
	assert_eq(await tablet_cloud.sync(), CloudSaveService.STATUS_SYNCED)
	_clock.set_fixed_unix(NOW + 100)
	var phone: PlayerProfile = _fresh(NOW + 50)
	var phone_cloud: CloudSaveService = _device(phone)
	_server.online = false
	assert_eq(await phone_cloud.sync(), CloudSaveService.STATUS_OFFLINE)
	assert_false(phone_cloud.is_dirty(), "a pristine install has nothing to upload")
	_economy(phone).grant(COINS, 20, "level:w01_l01")
	phone.levels["w01_l01"] = _record(1)
	phone_cloud.mark_dirty()
	_server.online = true
	_clock.set_fixed_unix(NOW + 200)
	assert_eq(await phone_cloud.sync(), CloudSaveService.STATUS_CONFLICT_RESOLVED)
	assert_eq(phone.coins, 5020, "the account wallet plus the 20 coins earned on this phone")
	assert_eq(phone.gems, 300)
	assert_eq(phone.stars_for("w01_l01"), 3, "the better record")
	assert_eq(_server.profile().coins, 5020)
	assert_eq(_server.profile().gems, 300)
	assert_empty(IntegrityMonitor.new(phone).check(), "the merged ledger explains the wallet")


## Review R-6 findings 2 and 6 (stars_and_dup.gd): purchases made offline on
## both devices are both paid for, and bonus stars from two different
## achievements add up instead of keeping the larger side.
func test_both_devices_spends_and_star_rewards_apply_once() -> void:
	var pair: Array = await _pair()
	var a: PlayerProfile = pair[0]
	var a_cloud: CloudSaveService = pair[1]
	var b: PlayerProfile = pair[2]
	var b_cloud: CloudSaveService = pair[3]
	a.achievements["perfect_worlds_5"] = NOW
	a.bonus_stars += 3
	assert_true(_economy(a).spend(COINS, 500, "cosmetic:core_x"))
	a.cosmetics_owned.append("core_x")
	b.achievements["secret_time"] = NOW
	b.bonus_stars += 1
	assert_true(_economy(b).spend(COINS, 500, "cosmetic:trail_y"))
	b.cosmetics_owned.append("trail_y")
	a_cloud.mark_dirty()
	b_cloud.mark_dirty()
	await a_cloud.sync()
	await b_cloud.sync()
	await a_cloud.sync()
	for p: PlayerProfile in [a, b, _server.profile()]:
		assert_eq(p.coins, 0, "1000 coins of items cost 1000 coins")
		assert_eq(p.bonus_stars, 4, "3 + 1 stars from two different achievements")
		assert_has(p.cosmetics_owned, "core_x")
		assert_has(p.cosmetics_owned, "trail_y")
		assert_eq(p.gems, 10, "an untouched currency stays as it was")
	assert_empty(IntegrityMonitor.new(a).check())
	assert_empty(IntegrityMonitor.new(b).check())


## The same item bought and the same achievement paid on both devices before
## either synced: charged once, paid once; every other earning counts.
func test_a_purchase_or_reward_made_on_both_devices_counts_once() -> void:
	var pair: Array = await _pair()
	var a: PlayerProfile = pair[0]
	var a_cloud: CloudSaveService = pair[1]
	var b: PlayerProfile = pair[2]
	var b_cloud: CloudSaveService = pair[3]
	for p: PlayerProfile in [a, b]:
		assert_true(_economy(p).spend(COINS, 500, "cosmetic:core_x"))
		p.cosmetics_owned.append("core_x")
		p.achievements["combo_10"] = NOW
		_economy(p).grant(COINS, 50, "achievement:combo_10")
	_economy(a).grant(COINS, 40, "level:w01_l02")
	_economy(b).grant(COINS, 60, "level:w01_l03")
	a_cloud.mark_dirty()
	b_cloud.mark_dirty()
	await a_cloud.sync()
	await b_cloud.sync()
	await a_cloud.sync()
	for p: PlayerProfile in [a, b, _server.profile()]:
		assert_eq(p.coins, 1000 - 500 + 50 + 40 + 60, "one charge, one reward, both level earnings")
		assert_eq(p.cosmetics_owned.count("core_x"), 1)
	assert_empty(IntegrityMonitor.new(b).check(), "the ledger explains the refunded charge")


## Review R-6 finding 2 (skew.gd): a purchase made on a device whose clock
## runs an hour slow is not undone by the other device's newer timestamps.
func test_device_clock_skew_cannot_undo_a_purchase() -> void:
	var a: PlayerProfile = _veteran(1000, 0)
	var a_cloud: CloudSaveService = _device(a)
	a.xp += 1
	a_cloud.mark_dirty()
	assert_eq(await a_cloud.sync(), CloudSaveService.STATUS_SYNCED)
	var slow: GameClock = GameClock.new()
	slow.set_fixed_unix(NOW - 3600 + 60)
	var b: PlayerProfile = _fresh(NOW - 3600, INSTALL_ID, slow)
	var b_cloud: CloudSaveService = _device(b, slow)
	await b_cloud.sync()
	assert_eq(b.coins, 1000)
	slow.set_fixed_unix(NOW - 3600 + 120)
	assert_true(_economy(b, slow).spend(COINS, 600, "cosmetic:core_shadow"))
	b.cosmetics_owned.append("core_shadow")
	b_cloud.mark_dirty()
	assert_eq(await b_cloud.sync(), CloudSaveService.STATUS_SYNCED)
	_clock.set_fixed_unix(NOW + 180)
	await a_cloud.sync()
	assert_eq(a.coins, 400, "the purchase stays paid")
	assert_has(a.cosmetics_owned, "core_shadow")
	assert_eq(_server.profile().coins, 400)


## A push the server stored whose answer was lost: the next merges count this
## device's changes once, also after another device merged that copy.
func test_a_lost_push_answer_never_duplicates_the_wallet() -> void:
	var pair: Array = await _pair()
	var a: PlayerProfile = pair[0]
	var a_cloud: CloudSaveService = pair[1]
	var b: PlayerProfile = pair[2]
	var b_cloud: CloudSaveService = pair[3]
	_economy(a).grant(COINS, 200, "level:w02_l01")
	a_cloud.mark_dirty()
	_server.lost_answers = 1
	assert_eq(await a_cloud.sync(), CloudSaveService.STATUS_OFFLINE, "the answer never arrived")
	assert_true(a_cloud.is_dirty())
	assert_eq(_server.profile().coins, 1200, "but the server stored the push")
	_economy(a).grant(COINS, 50, "level:w02_l02")
	a_cloud.mark_dirty()
	_economy(b).grant(COINS, 10, "level:w01_l05")
	b_cloud.mark_dirty()
	await b_cloud.sync()
	assert_eq(b.coins, 1210, "B adds its 10 coins to A's stored copy")
	await a_cloud.sync()
	assert_eq(a.coins, 1260, "A's 200 count once, plus its 50 and B's 10")
	assert_eq(_server.profile().coins, 1260)
	await b_cloud.sync()
	assert_eq(b.coins, 1260)
	_economy(a).grant(COINS, 5, "level:w02_l03")
	a_cloud.mark_dirty()
	_server.lost_answers = 1
	await a_cloud.sync()
	_economy(a).grant(COINS, 7, "level:w02_l04")
	a_cloud.mark_dirty()
	await a_cloud.sync()
	assert_eq(a.coins, 1272, "its own stored copy coming back adds nothing")
	assert_eq(_server.profile().coins, 1272)
	assert_false(a_cloud.is_dirty())


## Review R-6 finding 5 (inflight.gd): a run that ends while a sync's download
## is in flight is never marked as synced without reaching the cloud.
func test_changes_during_a_download_still_go_up() -> void:
	var p: PlayerProfile = _veteran(100, 0)
	var cloud: CloudSaveService = _device(p)
	p.xp += 1
	cloud.mark_dirty()
	assert_eq(await cloud.sync(), CloudSaveService.STATUS_SYNCED)
	_server.hold = true
	var finished: Array[StringName] = []
	var run: Callable = func() -> void: finished.append(await cloud.sync())
	run.call()
	_economy(p).grant(COINS, 300, "level:w01_l41")
	p.levels["w02_l03"] = _record(3)
	_server.hold = false
	_server.released.emit()
	await wait_frames(1)
	assert_eq(finished.size(), 1, "the sync finished")
	var reached: bool = _server.profile().coins == 400
	assert_true(cloud.is_dirty() or reached, "unseen changes are never marked as synced")
	cloud.mark_dirty()
	await cloud.sync()
	assert_eq(_server.profile().coins, 400, "the run's coins reach the cloud")
	assert_true(_server.profile().levels.has("w02_l03"), "and its level record")
	assert_false(cloud.is_dirty())


## Review R-6 finding 4, defence in depth: a change that reached the disk
## without the cloud flag (a save written by an older build, or by any writer
## that skipped the flag) still goes up after a relaunch.
func test_a_change_saved_without_the_flag_still_goes_up() -> void:
	var p: PlayerProfile = _veteran(100, 0)
	var cloud: CloudSaveService = _device(p)
	p.xp += 1
	cloud.mark_dirty()
	assert_eq(await cloud.sync(), CloudSaveService.STATUS_SYNCED)
	_economy(p).grant(COINS, 75, "level:w01_l41")
	var storage: MemorySaveStorage = MemorySaveStorage.new()
	assert_eq(SaveService.new(storage, _clock).save_profile(p), OK)
	var reloaded: PlayerProfile = SaveService.new(storage, _clock).load_profile()
	assert_false(cloud.is_dirty(), "the flag never reached the disk")
	assert_eq(await _device(reloaded).sync(), CloudSaveService.STATUS_SYNCED)
	assert_eq(_server.profile().coins, 175, "the change still reaches the cloud")


## Review R-6 finding 7 (huge.gd): de-duplicating server-supplied lists is
## linear, keeps the original order and is bounded.
func test_large_cloud_lists_merge_in_linear_time() -> void:
	var ids: Array = []
	for i: int in LARGE_LIST:
		ids.append("p%d" % i)
	ids.append("p0")
	var started: int = Time.get_ticks_msec()
	var p: PlayerProfile = PlayerProfile.from_dict({"purchases": ids})
	assert_lt(Time.get_ticks_msec() - started, LINEAR_BUDGET_MS, "sanitising a long list is linear")
	assert_eq(p.purchases[0], "p0", "first occurrence order kept")
	assert_eq(p.purchases[1], "p1")
	assert_lt(p.purchases.size(), LARGE_LIST, "a damaged copy cannot grow the list without bound")
	assert_eq(p.purchases.count("p0"), 1, "no duplicates")
	started = Time.get_ticks_msec()
	var missions: Dictionary = ProfileMerge.merge_missions({}, {MissionService.HISTORY_KEY: ids})
	assert_lt(Time.get_ticks_msec() - started, LINEAR_BUDGET_MS, "the claimed-id union is linear")
	var history: Array = missions[MissionService.HISTORY_KEY] as Array
	assert_eq(history.size(), MissionService.CLAIM_HISTORY_LIMIT, "and bounded")
	assert_eq(str(history.back()), "p%d" % (LARGE_LIST - 1), "the newest ids are kept")
	var ledger: Array = []
	for i2: int in LARGE_LIST:
		ledger.append({"t": i2, "c": "coins", "d": 1, "s": "level:w01_l01", "b": i2 + 1})
	started = Time.get_ticks_msec()
	var trimmed: PlayerProfile = PlayerProfile.from_dict({"ledger": ledger})
	assert_lt(Time.get_ticks_msec() - started, LINEAR_BUDGET_MS, "trimming a long ledger is linear")
	assert_eq(trimmed.ledger.size(), PlayerProfile.LEDGER_LIMIT)
	assert_eq(int(trimmed.ledger.back()["b"]), LARGE_LIST, "the newest entries are kept")


## Review R-6 finding 8: a daily day (or bonus chest day) from a device whose
## clock runs ahead is never adopted beyond today plus the daily grace.
func test_a_day_from_a_clock_ahead_is_never_adopted() -> void:
	var today: int = _clock.day_number()
	var p: PlayerProfile = _veteran(100, 0)
	p.daily = {"last_day": today - 1, "streak": 3, "tier": 3, "streak_best": 3}
	p.flags["bonus_chest_day"] = today - 1
	var ahead: PlayerProfile = PlayerProfile.from_dict(p.to_dict())
	ahead.daily = {"last_day": today + 5, "streak": 9, "tier": 7, "streak_best": 9}
	ahead.flags["bonus_chest_day"] = today + 5
	ahead.levels["w02_l01"] = _record(2)
	_server.store(SaveService.encode(ahead, NOW))
	var cloud: CloudSaveService = _device(p)
	await cloud.sync()
	assert_true(p.levels.has("w02_l01"), "the rest of the copy is merged")
	assert_eq(int(p.daily["last_day"]), today - 1, "a future day would block every daily")
	assert_eq(int(p.daily["streak"]), 3, "the streak that belongs to it is not adopted either")
	assert_eq(int(p.daily["streak_best"]), 9, "the longest streak is still kept")
	assert_eq(int(p.flags["bonus_chest_day"]), today - 1, "today's chest stays available")
	var tomorrow: PlayerProfile = PlayerProfile.from_dict(_server.payload())
	tomorrow.daily = {"last_day": today + 1, "streak": 4, "tier": 4, "streak_best": 4}
	_server.store(SaveService.encode(tomorrow, NOW))
	await cloud.sync()
	assert_eq(int(p.daily["last_day"]), today + 1, "within the grace window (midnight runs) it is adopted")
	assert_eq(int(p.daily["streak"]), 4)


## Review R-6 finding 9: the pushed copy carries no device-local slices, and a
## copy larger than a download can return is refused before it is sent.
func test_pushed_copy_is_lean_and_never_larger_than_a_download() -> void:
	var p: PlayerProfile = _veteran(100, 0)
	for i: int in 40:
		p.pending_submissions.append({"kind": "leaderboard", "id": "run-%d" % i, "replay": "x".repeat(1000)})
	p.settings["sound"] = false
	p.cosmetics_equipped = {"core_skin": "core_fire"}
	var cloud: CloudSaveService = _device(p)
	p.xp += 1
	cloud.mark_dirty()
	assert_eq(await cloud.sync(), CloudSaveService.STATUS_SYNCED)
	var stored: Dictionary = _server.payload()
	assert_empty(stored.get("pending_submissions", []), "this device's queue never travels")
	assert_empty(stored.get("cosmetics_equipped", {}), "nor what it has equipped")
	for key: Variant in stored.get("flags", {}) as Dictionary:
		assert_false(str(key).begins_with("cloud."), "nor its cloud bookkeeping (%s)" % str(key))
	assert_eq(p.pending_submissions.size(), 40, "the queue stays here")
	assert_false(bool(p.settings["sound"]), "and so do the settings")
	var puts: int = _server.puts
	var http: HttpCloudSaveProvider = HttpCloudSaveProvider.new(BASE_URL, _server.request, INSTALL_ID, "1.0.0")
	var quoted: String = '"'.repeat(HttpTransport.MAX_BODY_BYTES / 2)
	var refused: Dictionary = await http.push(quoted, _server.revision())
	assert_eq(str(refused["error"]), HttpCloudSaveProvider.ERROR_TOO_LARGE, "its download would not fit")
	assert_false(bool(refused["retry"]), "retrying cannot help")
	assert_eq(_server.puts, puts, "nothing was sent")
	p.flags["note"] = '"'.repeat(HttpTransport.MAX_BODY_BYTES / 4)
	cloud.mark_dirty()
	assert_eq(await cloud.sync(), CloudSaveService.STATUS_ERROR, "an honest error, not a sync")
	assert_eq(cloud.last_error, HttpCloudSaveProvider.ERROR_TOO_LARGE)
	assert_true(cloud.is_dirty(), "the changes are still waiting")
	assert_eq(_server.puts, puts, "nothing was sent")
