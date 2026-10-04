class_name CloudSaveService
extends RefCounted
## Cloud copy of the player's save (REQ-182) and its offline behaviour
## (REQ-181).
##
## The local save stays the source of truth and works offline; the cloud copy
## is a [SaveService] envelope kept by a [CloudSaveProvider]. [method sync]
## fetches it, verifies it exactly like a local file ([method SaveService.decode]:
## format, checksum, no newer save version), migrates and sanitises it, merges
## it into the live profile with [ProfileMerge] and pushes the merged save with
## the fetched revision as its base. A 409 (the cloud moved on meanwhile) is
## merged once more and pushed again; a second conflict waits for the next
## sync. A damaged or newer-version cloud copy is never applied or overwritten:
## the local profile is kept and the status is "error".
##
## Bookkeeping lives in profile.flags: "cloud.dirty" (local changes the cloud
## has not seen), "cloud.revision" (the cloud revision this device last
## matched) and "cloud.synced_at" (the saved_at stamp of that cloud copy).
## [method mark_dirty] runs after every local save and flags real content
## changes only: device-local fields (settings, equipped cosmetics, queued
## submissions) and the cloud flags themselves never need a push. A failed
## sync keeps the dirty flag; the next trigger (boot, network back online, app
## pause, "Sync now") pushes it.
##
## Which wallet is newer ([ProfileMerge] never sums currencies): a device with
## changes the cloud has not seen dates its state "now"; otherwise its state is
## as old as the cloud copy it last matched (cloud.synced_at). A profile that
## never synced and has no play history (a fresh install) is never newer than
## an existing cloud copy, so its starting balance cannot replace a real wallet.
##
## Never blocks gameplay (callers do not wait for it) and never runs two syncs
## at once. With a disabled provider the status is "off" and nothing is sent.

## The status changed (see the STATUS_* constants).
signal status_changed(status: StringName)
## A sync attempt ended with [param status]; [param conflict] is true when two
## diverged copies had to be merged.
signal sync_finished(status: StringName, conflict: bool)
## The live profile now holds a merge with the cloud copy: owners of derived
## state refresh it, and the profile should be saved.
signal profile_merged
## The cloud.* bookkeeping flags changed: the profile should be saved.
signal flags_changed

const STATUS_OFF: StringName = &"off"
const STATUS_IDLE: StringName = &"idle"
const STATUS_SYNCING: StringName = &"syncing"
const STATUS_SYNCED: StringName = &"synced"
const STATUS_OFFLINE: StringName = &"offline"
const STATUS_CONFLICT_RESOLVED: StringName = &"conflict_resolved"
const STATUS_ERROR: StringName = &"error"
## Translation key of each status (the UI shows it as the section caption).
const STATUS_TEXT_KEYS: Dictionary = {
	STATUS_OFF: "cloud.status.off",
	STATUS_IDLE: "cloud.status.idle",
	STATUS_SYNCING: "cloud.status.syncing",
	STATUS_SYNCED: "cloud.status.synced",
	STATUS_OFFLINE: "cloud.status.offline",
	STATUS_CONFLICT_RESOLVED: "cloud.status.conflict_resolved",
	STATUS_ERROR: "cloud.status.error",
}
const FLAG_DIRTY: String = "cloud.dirty"
const FLAG_REVISION: String = "cloud.revision"
const FLAG_SYNCED_AT: String = "cloud.synced_at"
const ERROR_REMOTE_CORRUPT: String = "remote_corrupt"
const ERROR_REMOTE_NEWER: String = "remote_newer_version"
## Profile fields that never travel to another device (see [ProfileMerge]).
const DEVICE_LOCAL_KEYS: PackedStringArray = ["settings", "cosmetics_equipped", "pending_submissions"]
const FLAGS_KEY: String = "flags"
const CREATED_AT_KEY: String = "created_at"

## Current status (one of the STATUS_* constants).
var status: StringName = STATUS_IDLE
## Error code of the last failed sync ("" after a successful one).
var last_error: String = ""
## True when the last sync merged two diverged copies.
var last_conflict: bool = false

var _provider: CloudSaveProvider
var _profile: PlayerProfile
var _clock: GameClock
var _bus: EventBus
var _encode: Callable
var _decode: Callable
var _syncing: bool = false
## Fingerprint of the profile content the cloud is known to hold.
var _clean_fingerprint: String = ""
## Per sync: whether this device had changes the cloud had not seen, and the
## time its wallet dates from.
var _local_changed: bool = false
var _local_time: int = 0


## [param encode] is (profile: PlayerProfile, now_unix: int) -> String and
## [param decode] is (text: String) -> Dictionary, defaulting to
## [method SaveService.encode] / [method SaveService.decode]. A null provider
## means the feature is off.
func _init(
	provider: CloudSaveProvider,
	profile: PlayerProfile,
	clock: GameClock,
	bus: EventBus,
	encode: Callable = Callable(),
	decode: Callable = Callable()
) -> void:
	_provider = provider if provider != null else NullCloudSaveProvider.new()
	if profile == null:
		GameLog.error("cloud", "no profile injected; cloud save works on a blank profile")
		profile = PlayerProfile.new()
	_profile = profile
	_clock = clock if clock != null else GameClock.new()
	_bus = bus
	_encode = encode
	if not _encode.is_valid():
		_encode = func(p: PlayerProfile, now_unix: int) -> String: return SaveService.encode(p, now_unix)
	_decode = decode
	if not _decode.is_valid():
		_decode = func(text: String) -> Dictionary: return SaveService.decode(text)
	_clean_fingerprint = _fingerprint()
	status = STATUS_IDLE if is_enabled() else STATUS_OFF


## The provider for a configured base URL (remote config cloud_save.base_url):
## the HTTP client for a non-empty, secure URL (the same rule as every remote
## URL, [method RemoteConfig.is_secure_url_or_empty]), otherwise the null
## provider, which keeps the feature honestly off.
static func provider_for(
	base_url: String, transport: Callable, install_id: String, app_version: String = ""
) -> CloudSaveProvider:
	var url: String = base_url.strip_edges()
	if url.is_empty() or not RemoteConfig.is_secure_url_or_empty(url):
		return NullCloudSaveProvider.new()
	return HttpCloudSaveProvider.new(url, transport, install_id, app_version)


## Translation key describing [param value] (a STATUS_* constant).
static func status_text_key(value: StringName) -> String:
	return str(STATUS_TEXT_KEYS.get(value, STATUS_TEXT_KEYS[STATUS_IDLE]))


## True when a cloud server is configured.
func is_enabled() -> bool:
	return _provider.is_enabled()


## True while a sync is running.
func is_syncing() -> bool:
	return _syncing


## True when this device has changes the cloud has not seen yet.
func is_dirty() -> bool:
	return CloudSaveService._is_true(_profile.flags.get(FLAG_DIRTY, false))


## The cloud revision this device last matched ("" before the first sync).
func revision() -> String:
	return CloudSaveProvider.valid_revision(_profile.flags.get(FLAG_REVISION, ""))


## saved_at stamp (unix seconds) of the cloud copy this device last matched.
func synced_at() -> int:
	var raw: Variant = _profile.flags.get(FLAG_SYNCED_AT, 0)
	return maxi(0, int(raw)) if typeof(raw) == TYPE_INT else 0


## True when a sync could change something: enabled, idle, and either local
## changes are waiting or the last sync did not complete.
func needs_sync() -> bool:
	if not is_enabled() or _syncing:
		return false
	return is_dirty() or (status != STATUS_SYNCED and status != STATUS_CONFLICT_RESOLVED)


## Swaps the provider (remote config can enable or disable the feature at run
## time). A running sync finishes with the provider it started with.
func set_provider(provider: CloudSaveProvider) -> void:
	_provider = provider if provider != null else NullCloudSaveProvider.new()
	if not _syncing:
		_set_status(STATUS_IDLE if is_enabled() else STATUS_OFF)


## Called after every local save: flags the profile dirty when its content
## changed since the cloud last matched it.
func mark_dirty() -> void:
	if not is_enabled() or is_dirty():
		return
	if _fingerprint() == _clean_fingerprint:
		return
	_profile.flags[FLAG_DIRTY] = true
	flags_changed.emit()


## Fetches, merges and pushes (async; see the class description). Returns the
## final status. A call while a sync runs returns at once with the current
## status; with the feature off it returns "off" without any network traffic.
func sync() -> StringName:
	if _syncing:
		return status
	if not is_enabled():
		_set_status(STATUS_OFF)
		return status
	_syncing = true
	last_conflict = false
	last_error = ""
	_set_status(STATUS_SYNCING)
	var outcome: StringName = await _run(_provider)
	_syncing = false
	_set_status(outcome)
	sync_finished.emit(outcome, last_conflict)
	return outcome


func _run(provider: CloudSaveProvider) -> StringName:
	_local_changed = is_dirty() or (revision().is_empty() and ProfileMerge.has_progress(_profile.to_dict()))
	_local_time = _clock.now_unix() if _local_changed else synced_at()
	var fetched: Variant = await provider.fetch()
	var res: Dictionary = fetched as Dictionary if typeof(fetched) == TYPE_DICTIONARY else {}
	if not CloudSaveService._is_true(res.get("ok", false)):
		return _failed(res, false)
	var base: String = ""
	if CloudSaveService._is_true(res.get("found", false)):
		base = CloudSaveProvider.valid_revision(res.get("revision", ""))
		var unchanged: bool = not base.is_empty() and base == revision()
		if unchanged and not _local_changed and not is_dirty():
			_mark_synced(base, synced_at(), _fingerprint())
			return STATUS_SYNCED
		if not unchanged:
			var problem: String = _merge_in(str(res.get("blob", "")))
			if not problem.is_empty():
				return _failed({"retry": false, "error": problem}, false)
	return await _push(provider, base, true)


func _push(provider: CloudSaveProvider, base: String, may_retry: bool) -> StringName:
	var now: int = _clock.now_unix()
	var blob: String = str(_encode.call(_profile, now))
	var pushed: String = _fingerprint()
	var answer: Variant = await provider.push(blob, base)
	var res: Dictionary = answer as Dictionary if typeof(answer) == TYPE_DICTIONARY else {}
	if CloudSaveService._is_true(res.get("ok", false)):
		_mark_synced(CloudSaveProvider.valid_revision(res.get("revision", "")), now, pushed)
		return STATUS_CONFLICT_RESOLVED if last_conflict else STATUS_SYNCED
	if CloudSaveService._is_true(res.get("conflict", false)) and may_retry:
		last_conflict = true
		var problem: String = _merge_in(str(res.get("remote_blob", "")))
		if not problem.is_empty():
			return _failed({"retry": false, "error": problem}, true)
		return await _push(provider, CloudSaveProvider.valid_revision(res.get("remote_revision", "")), false)
	return _failed(res, true)


## Verifies, migrates and merges a cloud copy into the live profile. Returns
## "" on success or an error code (the profile is then left untouched).
func _merge_in(blob: String) -> String:
	var raw: Variant = _decode.call(blob)
	var decoded: Dictionary = raw as Dictionary if typeof(raw) == TYPE_DICTIONARY else {}
	var version: int = int(decoded.get("version", -1)) if CloudSaveService._is_int(decoded.get("version")) else -1
	if not CloudSaveService._is_true(decoded.get("ok", false)):
		var newer: bool = version > SaveService.CURRENT_VERSION
		GameLog.warn("cloud", "cloud copy refused: %s" % str(decoded.get("error", "unreadable")))
		return ERROR_REMOTE_NEWER if newer else ERROR_REMOTE_CORRUPT
	var payload: Variant = decoded.get("payload", null)
	if typeof(payload) != TYPE_DICTIONARY or not SaveMigrations.is_supported(version):
		return ERROR_REMOTE_CORRUPT
	var saved_at: Variant = decoded.get("saved_at", 0)
	# A copy dated in the future (a device clock running ahead) counts as now.
	var remote_time: int = clampi(int(saved_at) if CloudSaveService._is_int(saved_at) else 0, 0, _clock.now_unix())
	var data: Dictionary = payload as Dictionary
	if version < SaveService.CURRENT_VERSION:
		data = SaveMigrations.migrate(data, version)
		if not data.has(CREATED_AT_KEY):
			data[CREATED_AT_KEY] = remote_time
	var remote: Dictionary = PlayerProfile.from_dict(data).to_dict()
	if _local_changed:
		last_conflict = true
	_apply(ProfileMerge.merge(_profile.to_dict(), remote, _local_time, remote_time))
	_local_time = maxi(_local_time, remote_time)
	return ""


func _apply(merged: Dictionary) -> void:
	var coins_before: int = _profile.coins
	var gems_before: int = _profile.gems
	var clean: PlayerProfile = PlayerProfile.from_dict(merged)
	clean.install_id = _profile.install_id
	_profile.copy_from(clean)
	profile_merged.emit()
	if _bus == null:
		return
	if _profile.coins != coins_before:
		_bus.currency_changed.emit(EconomyService.COINS, _profile.coins, _profile.coins - coins_before)
	if _profile.gems != gems_before:
		_bus.currency_changed.emit(EconomyService.GEMS, _profile.gems, _profile.gems - gems_before)


func _mark_synced(new_revision: String, stamp: int, clean_fingerprint: String) -> void:
	_profile.flags[FLAG_REVISION] = new_revision
	_profile.flags[FLAG_SYNCED_AT] = maxi(0, stamp)
	_clean_fingerprint = clean_fingerprint
	# Changes made while the request was in flight still need a push.
	_profile.flags[FLAG_DIRTY] = _fingerprint() != clean_fingerprint
	flags_changed.emit()


## Records a failed sync: offline for transient failures, error otherwise. A
## device whose changes did not reach the cloud stays dirty.
func _failed(res: Dictionary, push_attempted: bool) -> StringName:
	last_error = str(res.get("error", ""))
	if (push_attempted or _local_changed) and not is_dirty():
		_profile.flags[FLAG_DIRTY] = true
		flags_changed.emit()
	GameLog.info("cloud", "sync did not complete (%s)" % last_error)
	return STATUS_OFFLINE if CloudSaveService._is_true(res.get("retry", false)) else STATUS_ERROR


func _set_status(value: StringName) -> void:
	if value == status:
		return
	status = value
	status_changed.emit(value)


## Hash of the profile content that travels to the cloud (device-local fields
## and the cloud bookkeeping excluded).
func _fingerprint() -> String:
	var data: Dictionary = _profile.to_dict()
	for key: String in DEVICE_LOCAL_KEYS:
		data.erase(key)
	var flags: Dictionary = data.get(FLAGS_KEY, {}) as Dictionary
	for key: Variant in flags.keys():
		if str(key).begins_with(ProfileMerge.CLOUD_FLAG_PREFIX):
			flags.erase(key)
	return JsonIO.canonical(data).sha256_text()


static func _is_int(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value as float))


## True only for a real boolean true (untrusted data).
static func _is_true(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL and bool(value)
