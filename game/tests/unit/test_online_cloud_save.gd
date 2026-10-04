extends TestCase
## Cloud save (REQ-182, REQ-181): the HTTP provider's status mapping and
## contract, and CloudSaveService end to end against an in-memory server:
## first upload, newer download, 409 conflicts, offline behaviour, refused
## cloud copies and one sync at a time.

const BASE_URL: String = "https://saves.invalid"
const NOW: int = 1790000000
const INSTALL_ID: String = "0123456789abcdef0123456789abcdef"


## Test double for the HTTP transport: returns [member next] for every call
## and records the calls.
class ScriptedTransport:
	extends RefCounted
	var next: Variant = {"ok": true, "status": 200, "body": {}, "error": ""}
	var calls: Array[Dictionary] = []

	func request(method: String, url: String, body: Dictionary) -> Dictionary:
		calls.append({"method": method, "url": url, "body": body.duplicate(true)})
		return next as Dictionary if typeof(next) == TYPE_DICTIONARY else {}


## In-memory cloud save server implementing the documented contract
## (GET / PUT /v1/saves/{id}, revisions, 409 on a stale base revision).
## [member interleaved] blobs are written by "another device" just before the
## next PUT is handled; with [member hold] every request waits for [signal released].
class MemoryCloudServer:
	extends RefCounted
	signal released
	var online: bool = true
	var hold: bool = false
	var blob: String = ""
	var revision_number: int = 0
	var interleaved: Array[String] = []
	var calls: Array[Dictionary] = []

	func request(method: String, url: String, body: Dictionary) -> Dictionary:
		calls.append({"method": method, "url": url, "body": body.duplicate(true)})
		if hold:
			await released
		if not online:
			return {"ok": false, "status": 0, "body": null, "error": "timeout"}
		if method == "GET":
			if blob.is_empty():
				return {"ok": false, "status": 404, "body": {}, "error": ""}
			return {"ok": true, "status": 200, "body": {"blob": blob, "revision": revision()}, "error": ""}
		if not interleaved.is_empty():
			store(interleaved.pop_front())
		if str(body.get("base_revision", "")) != revision():
			return {"ok": false, "status": 409, "body": {"blob": blob, "revision": revision()}, "error": ""}
		store(str(body.get("blob", "")))
		return {"ok": true, "status": 200, "body": {"revision": revision()}, "error": ""}

	func store(text: String) -> void:
		blob = text
		revision_number += 1

	func revision() -> String:
		return "" if blob.is_empty() else "r%d" % revision_number

	func count(method: String) -> int:
		var n: int = 0
		for call: Dictionary in calls:
			if str(call["method"]) == method:
				n += 1
		return n


var _clock: GameClock
var _bus: EventBus
var _server: MemoryCloudServer
var _merged: int = 0


func before_each() -> void:
	_clock = GameClock.new()
	_clock.set_fixed_unix(NOW)
	_bus = EventBus.new()
	_server = MemoryCloudServer.new()
	_merged = 0


func _player(coins: int, levels: Dictionary = {}) -> PlayerProfile:
	var p: PlayerProfile = PlayerProfile.create_new(NOW - 5000)
	p.install_id = INSTALL_ID
	p.coins = coins
	p.ledger.append({"t": NOW - 4000, "c": "coins", "d": coins, "s": "level:w01_l01", "b": coins})
	for id: String in levels:
		p.levels[id] = {
			"stars": int(levels[id]),
			"best_score": 100,
			"perfect": false,
			"clears": 1,
			"attempts": 1,
			"best_combo": 1,
			"best_time": 0.0,
		}
	return p


func _service(profile: PlayerProfile) -> CloudSaveService:
	var provider: HttpCloudSaveProvider = HttpCloudSaveProvider.new(BASE_URL, _server.request, INSTALL_ID, "1.0.0")
	var service: CloudSaveService = CloudSaveService.new(provider, profile, _clock, _bus)
	service.profile_merged.connect(func() -> void: _merged += 1)
	return service


## The profile the server holds now.
func _server_profile() -> PlayerProfile:
	return PlayerProfile.from_dict(SaveService.decode(_server.blob)["payload"] as Dictionary)


func test_http_provider_is_off_without_configuration() -> void:
	var transport: ScriptedTransport = ScriptedTransport.new()
	assert_false(HttpCloudSaveProvider.new("", transport.request, INSTALL_ID).is_enabled(), "needs a URL")
	assert_false(HttpCloudSaveProvider.new(BASE_URL, Callable(), INSTALL_ID).is_enabled(), "needs a transport")
	assert_false(HttpCloudSaveProvider.new(BASE_URL, transport.request, "").is_enabled(), "needs an install id")
	var off: HttpCloudSaveProvider = HttpCloudSaveProvider.new("", transport.request, INSTALL_ID)
	assert_eq(str((await off.fetch())["error"]), "disabled")
	assert_false(bool((await off.push("x", ""))["retry"]), "disabled is not transient")
	assert_empty(transport.calls, "no traffic while disabled")
	for refused: String in ["", "  ", "http://saves.invalid", "https://a@b.invalid", "https://"]:
		var provider: CloudSaveProvider = CloudSaveService.provider_for(refused, transport.request, INSTALL_ID)
		assert_true(provider is NullCloudSaveProvider, "'%s' keeps the feature off" % refused)
	var on: CloudSaveProvider = CloudSaveService.provider_for(BASE_URL, transport.request, INSTALL_ID)
	assert_true(on is HttpCloudSaveProvider and on.is_enabled(), "a secure URL turns it on")
	var null_provider: NullCloudSaveProvider = NullCloudSaveProvider.new()
	assert_eq(str((await null_provider.fetch())["error"]), CloudSaveProvider.ERROR_UNAVAILABLE, "honest answer")


func test_http_fetch_status_mapping() -> void:
	var transport: ScriptedTransport = ScriptedTransport.new()
	var http: HttpCloudSaveProvider = HttpCloudSaveProvider.new(BASE_URL + "/", transport.request, INSTALL_ID)
	transport.next = {"ok": true, "status": 200, "body": {"blob": "{}", "revision": "r7"}, "error": ""}
	var found: Dictionary = await http.fetch()
	assert_true(bool(found["ok"]) and bool(found["found"]))
	assert_eq(str(found["revision"]), "r7")
	assert_eq(str(transport.calls[0]["method"]), "GET")
	assert_eq(str(transport.calls[0]["url"]), BASE_URL + "/v1/saves/" + INSTALL_ID, "slot per install")
	transport.next = {"ok": false, "status": 404, "body": {}, "error": ""}
	var missing: Dictionary = await http.fetch()
	assert_true(bool(missing["ok"]), "404 = no cloud copy yet")
	assert_false(bool(missing["found"]))
	for transient: Dictionary in [
		{"ok": false, "status": 0, "body": null, "error": "timeout"},
		{"ok": false, "status": 429, "body": {}, "error": ""},
		{"ok": false, "status": 503, "body": {}, "error": ""},
		{"ok": true, "status": 200, "body": "<html>maintenance</html>", "error": ""},
		{"ok": true, "status": 204, "body": "", "error": ""},
		{"ok": true, "status": 200, "body": {"blob": 12, "revision": "r1"}, "error": ""},
		{"ok": true, "status": 200, "body": {"blob": "{}", "revision": "bad revision!"}, "error": ""},
		{"ok": true, "status": 200, "body": {"blob": "{}", "revision": 3}, "error": ""},
	]:
		transport.next = transient
		var r: Dictionary = await http.fetch()
		assert_false(bool(r["ok"]), "not applied: %s" % str(transient))
		assert_true(bool(r["retry"]), "retried later: %s" % str(transient))
	for final: int in [400, 401, 403, 410, 422]:
		transport.next = {"ok": false, "status": final, "body": {}, "error": ""}
		var f: Dictionary = await http.fetch()
		assert_false(bool(f["ok"]) or bool(f["retry"]), "%d is final" % final)
		assert_eq(str(f["error"]), "http_%d" % final)


func test_http_push_contract_and_conflicts() -> void:
	var transport: ScriptedTransport = ScriptedTransport.new()
	var http: HttpCloudSaveProvider = HttpCloudSaveProvider.new(BASE_URL, transport.request, INSTALL_ID, "2.0.0")
	transport.next = {"ok": true, "status": 200, "body": {"revision": "r8"}, "error": ""}
	var stored: Dictionary = await http.push("envelope", "r7")
	assert_true(bool(stored["ok"]))
	assert_eq(str(stored["revision"]), "r8")
	var call: Dictionary = transport.calls[0]
	assert_eq(str(call["method"]), "PUT")
	assert_eq(call["body"], {"blob": "envelope", "base_revision": "r7", "app_version": "2.0.0"})
	transport.next = {"ok": false, "status": 409, "body": {"blob": "theirs", "revision": "r9"}, "error": ""}
	var conflict: Dictionary = await http.push("envelope", "r7")
	assert_true(bool(conflict["conflict"]))
	assert_false(bool(conflict["ok"]) or bool(conflict["retry"]))
	assert_eq(str(conflict["remote_blob"]), "theirs")
	assert_eq(str(conflict["remote_revision"]), "r9")
	for transient: Dictionary in [
		{"ok": false, "status": 409, "body": {"blob": null}, "error": ""},
		{"ok": true, "status": 200, "body": {"stored": true}, "error": ""},
		{"ok": false, "status": 500, "body": {}, "error": ""},
		{"ok": false, "status": 0, "body": null, "error": "cant_connect"},
	]:
		transport.next = transient
		var t: Dictionary = await http.push("envelope", "r7")
		assert_true(bool(t["retry"]) and not bool(t["ok"]), "transient: %s" % str(transient))
	transport.next = {"ok": false, "status": 413, "body": {}, "error": ""}
	assert_false(bool((await http.push("envelope", "r7"))["retry"]), "other 4xx are final")


func test_http_push_refuses_empty_or_oversized_blobs() -> void:
	var transport: ScriptedTransport = ScriptedTransport.new()
	var http: HttpCloudSaveProvider = HttpCloudSaveProvider.new(BASE_URL, transport.request, INSTALL_ID)
	assert_eq(str((await http.push("", ""))["error"]), HttpCloudSaveProvider.ERROR_EMPTY_BLOB)
	var huge: String = "x".repeat(SaveService.MAX_SAVE_CHARS + 1)
	var refused: Dictionary = await http.push(huge, "")
	assert_eq(str(refused["error"]), HttpCloudSaveProvider.ERROR_TOO_LARGE)
	assert_false(bool(refused["retry"]))
	assert_empty(transport.calls, "nothing sent")
	assert_eq(HttpCloudSaveProvider.valid_blob(huge), "", "an oversized cloud copy is refused too")
	assert_eq(CloudSaveProvider.valid_revision("r".repeat(CloudSaveProvider.MAX_REVISION_LENGTH + 1)), "")
	assert_eq(CloudSaveProvider.valid_revision("2026-10-04T12:00:00.5"), "2026-10-04T12:00:00.5")


func test_off_without_a_server() -> void:
	var profile: PlayerProfile = _player(10, {"w01_l01": 3})
	var cloud: CloudSaveService = CloudSaveService.new(NullCloudSaveProvider.new(), profile, _clock, _bus)
	assert_false(cloud.is_enabled())
	assert_eq(cloud.status, CloudSaveService.STATUS_OFF)
	assert_eq(await cloud.sync(), CloudSaveService.STATUS_OFF)
	assert_false(cloud.needs_sync())
	profile.coins = 99
	cloud.mark_dirty()
	assert_false(cloud.is_dirty(), "no bookkeeping while off")
	assert_eq(CloudSaveService.status_text_key(cloud.status), "cloud.status.off")


func test_first_upload() -> void:
	var profile: PlayerProfile = _player(120, {"w01_l01": 2})
	var cloud: CloudSaveService = _service(profile)
	assert_eq(cloud.status, CloudSaveService.STATUS_IDLE)
	assert_eq(await cloud.sync(), CloudSaveService.STATUS_SYNCED)
	assert_eq(_server.count("PUT"), 1)
	var put_body: Dictionary = _server.calls[1]["body"] as Dictionary
	assert_eq(str(put_body["base_revision"]), "", "no base for the first copy")
	var stored: PlayerProfile = _server_profile()
	assert_eq(stored.coins, 120)
	assert_eq(stored.stars_for("w01_l01"), 2)
	assert_eq(cloud.revision(), "r1")
	assert_eq(cloud.synced_at(), NOW)
	assert_false(cloud.is_dirty())
	assert_eq(_merged, 0, "nothing to merge")
	assert_eq(await cloud.sync(), CloudSaveService.STATUS_SYNCED, "nothing changed")
	assert_eq(_server.count("PUT"), 1, "an unchanged profile is not pushed again")


func test_download_newer_cloud_copy() -> void:
	var profile: PlayerProfile = _player(50, {"w01_l01": 1})
	profile.flags[CloudSaveService.FLAG_REVISION] = "r1"
	profile.flags[CloudSaveService.FLAG_SYNCED_AT] = NOW - 3000
	var other: PlayerProfile = _player(900, {"w01_l01": 3, "w01_l02": 2})
	_server.revision_number = 1
	_server.store(SaveService.encode(other, NOW - 100))
	var cloud: CloudSaveService = _service(profile)
	assert_eq(await cloud.sync(), CloudSaveService.STATUS_SYNCED, "no local changes: a plain download")
	assert_eq(_merged, 1)
	assert_eq(profile.coins, 900, "the newer wallet")
	assert_eq(profile.stars_for("w01_l01"), 3)
	assert_eq(profile.stars_for("w01_l02"), 2)
	assert_eq(profile.install_id, INSTALL_ID)
	assert_false(cloud.last_conflict)
	assert_eq(cloud.revision(), _server.revision())
	assert_eq(_server_profile().stars_for("w01_l02"), 2, "the merged copy went back up")


func test_conflict_merges_and_pushes_again() -> void:
	var profile: PlayerProfile = _player(300, {"w01_l01": 3})
	var cloud: CloudSaveService = _service(profile)
	assert_eq(await cloud.sync(), CloudSaveService.STATUS_SYNCED)
	profile.levels["w01_l03"] = _player(0, {"w01_l03": 2}).levels["w01_l03"]
	cloud.mark_dirty()
	assert_true(cloud.is_dirty(), "a new level record needs a push")
	var other: PlayerProfile = _server_profile()
	other.levels["w02_l01"] = _player(0, {"w02_l01": 1}).levels["w02_l01"]
	_server.interleaved.append(SaveService.encode(other, NOW - 10))
	assert_eq(await cloud.sync(), CloudSaveService.STATUS_CONFLICT_RESOLVED)
	assert_true(cloud.last_conflict)
	assert_eq(_server.count("PUT"), 3, "first upload, the 409, the merged retry")
	var stored: PlayerProfile = _server_profile()
	assert_eq(stored.stars_for("w01_l03"), 2, "this device's level")
	assert_eq(stored.stars_for("w02_l01"), 1, "the other device's level")
	assert_eq(profile.stars_for("w02_l01"), 1, "and locally")
	assert_eq(profile.coins, 300, "this device changed last: its wallet")
	assert_false(cloud.is_dirty())


func test_offline_keeps_dirty_and_syncs_on_reconnect() -> void:
	var profile: PlayerProfile = _player(40, {"w01_l01": 1})
	var cloud: CloudSaveService = _service(profile)
	_server.online = false
	assert_eq(await cloud.sync(), CloudSaveService.STATUS_OFFLINE)
	assert_true(cloud.is_dirty(), "the local history still has to go up")
	assert_true(bool(profile.flags[CloudSaveService.FLAG_DIRTY]), "persisted in the profile")
	assert_true(cloud.needs_sync())
	assert_eq(profile.coins, 40, "gameplay state untouched")
	_server.online = true
	assert_eq(await cloud.sync(), CloudSaveService.STATUS_SYNCED)
	assert_false(cloud.is_dirty())
	assert_eq(_server_profile().coins, 40)
	profile.settings["sound"] = false
	profile.flags[CloudSaveService.FLAG_SYNCED_AT] = NOW
	cloud.mark_dirty()
	assert_false(cloud.is_dirty(), "settings and cloud bookkeeping alone need no push")
	profile.coins += 5
	cloud.mark_dirty()
	assert_true(cloud.is_dirty(), "a wallet change does")


func test_corrupted_cloud_copy_is_refused() -> void:
	var profile: PlayerProfile = _player(70, {"w01_l01": 2})
	var text: String = SaveService.encode(_player(99999, {"w01_l01": 3}), NOW - 10)
	_server.store(text.replace("99999", "99998"))
	var cloud: CloudSaveService = _service(profile)
	assert_eq(await cloud.sync(), CloudSaveService.STATUS_ERROR)
	assert_eq(cloud.last_error, CloudSaveService.ERROR_REMOTE_CORRUPT)
	assert_eq(profile.coins, 70, "local profile kept")
	assert_eq(profile.stars_for("w01_l01"), 2)
	assert_eq(_merged, 0)
	assert_eq(_server.count("PUT"), 0, "the cloud copy is not overwritten either")
	assert_true(cloud.is_dirty(), "this device's history still has to go up")


func test_newer_version_cloud_copy_is_refused() -> void:
	var profile: PlayerProfile = _player(70, {"w01_l01": 2})
	var future: Dictionary = _player(5000).to_dict()
	_server.store(SaveService.encode_payload(future, SaveService.CURRENT_VERSION + 1, NOW - 10))
	var cloud: CloudSaveService = _service(profile)
	assert_eq(await cloud.sync(), CloudSaveService.STATUS_ERROR)
	assert_eq(cloud.last_error, CloudSaveService.ERROR_REMOTE_NEWER)
	assert_eq(profile.coins, 70, "nothing from a newer game version is applied")
	assert_eq(_server.count("PUT"), 0, "and nothing written by it is overwritten")


func test_only_one_sync_at_a_time() -> void:
	var profile: PlayerProfile = _player(10, {"w01_l01": 1})
	var cloud: CloudSaveService = _service(profile)
	_server.hold = true
	cloud.sync()
	assert_true(cloud.is_syncing())
	assert_eq(cloud.status, CloudSaveService.STATUS_SYNCING)
	assert_eq(await cloud.sync(), CloudSaveService.STATUS_SYNCING, "a second call returns at once")
	assert_false(cloud.needs_sync())
	assert_eq(_server.calls.size(), 1, "one fetch in flight")
	_server.hold = false
	_server.released.emit()
	assert_false(cloud.is_syncing())
	assert_eq(cloud.status, CloudSaveService.STATUS_SYNCED)
	assert_eq(_server.count("GET"), 1)
	assert_eq(_server.count("PUT"), 1)


func test_fresh_install_takes_the_cloud_wallet() -> void:
	var fresh: PlayerProfile = PlayerProfile.create_new(NOW)
	fresh.install_id = INSTALL_ID
	fresh.coins = 100
	var other: PlayerProfile = _player(4200, {"w01_l01": 3})
	other.achievements["first_clear"] = NOW - 9000
	_server.store(SaveService.encode(other, NOW - 9000))
	var cloud: CloudSaveService = _service(fresh)
	assert_eq(await cloud.sync(), CloudSaveService.STATUS_SYNCED)
	assert_eq(fresh.coins, 4200, "a starting balance never replaces a real wallet")
	assert_eq(fresh.stars_for("w01_l01"), 3)
	assert_true(fresh.achievements.has("first_clear"))
	var played: PlayerProfile = _player(800, {"w02_l01": 1})
	var cloud2: CloudSaveService = _service(played)
	assert_eq(await cloud2.sync(), CloudSaveService.STATUS_CONFLICT_RESOLVED, "two histories combined")
	assert_eq(played.coins, 800, "a device with its own history keeps its newer wallet")
	assert_eq(played.stars_for("w01_l01"), 3)
