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
## matched), "cloud.synced_at" (the saved_at stamp of that cloud copy),
## "cloud.synced_hash" (the fingerprint of the content the cloud holds), and
## the wallet base of the three-way merge with the push in flight
## (cloud.base, cloud.pending, cloud.device and the travelling sync.pushes;
## see [ProfileMerge]). [method mark_dirty] flags real content changes only:
## device-local fields (settings, equipped cosmetics, queued submissions) and
## the cloud flags themselves never need a push. The owner calls it before
## writing a save, so the flag is part of what is written (an app killed on
## pause still knows the cloud is behind), and again after; a sync also
## compares the content with cloud.synced_hash, so a change saved without the
## flag still goes up. A failed sync keeps the dirty flag; the next trigger
## (boot, network back online, app pause, "Sync now") pushes it.
##
## The wallet is never taken whole from one side: both devices' spends and
## earnings since the base apply once ([WalletMerge]), so neither a fresh
## install nor a device clock can replace or undo the other's wallet. A merge
## is not earning: it never publishes [signal EventBus.currency_changed], and
## lifetime stats (coins_earned) merge by maximum.
##
## A sync remembers the profile content it started from: anything that changes
## while a request is in flight stays dirty or is pushed at once. The pushed
## copy carries no device-local fields and no cloud bookkeeping
## ([method ProfileMerge.travelling]). Never blocks gameplay (callers do not
## wait for it) and never runs two syncs at once. With a disabled provider the
## status is "off" and nothing is sent.

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
## A push is about to be sent and the profile records it (cloud.pending and
## sync.pushes): write the save now, before the request can complete, so a
## device killed meanwhile still recognises its own copy in the cloud.
signal push_prepared

const STATUS_OFF: StringName = &"off"
const STATUS_IDLE: StringName = &"idle"
const STATUS_SYNCING: StringName = &"syncing"
const STATUS_SYNCED: StringName = &"synced"
const STATUS_OFFLINE: StringName = &"offline"
const STATUS_CONFLICT_RESOLVED: StringName = &"conflict_resolved"
const STATUS_ERROR: StringName = &"error"
## Translation key of each status (the UI shows it as the section caption).
const STATUS_TEXT_KEYS: Dictionary[StringName, String] = {
	STATUS_OFF: "cloud.status.off",
	STATUS_IDLE: "cloud.status.idle",
	STATUS_SYNCING: "cloud.status.syncing",
	STATUS_SYNCED: "cloud.status.synced",
	STATUS_OFFLINE: "cloud.status.offline",
	STATUS_CONFLICT_RESOLVED: "cloud.status.conflict_resolved",
	STATUS_ERROR: "cloud.status.error",
}
const FLAG_DIRTY: String = "cloud.dirty"
const FLAG_REVISION: String = ProfileMerge.FLAG_REVISION
const FLAG_SYNCED_AT: String = ProfileMerge.FLAG_SYNCED_AT
const FLAG_SYNCED_HASH: String = "cloud.synced_hash"
const ERROR_REMOTE_CORRUPT: String = "remote_corrupt"
const ERROR_REMOTE_NEWER: String = "remote_newer_version"
## Profile fields that never travel to another device (see [ProfileMerge]).
const DEVICE_LOCAL_KEYS: PackedStringArray = ProfileMerge.DEVICE_LOCAL_KEYS
const CREATED_AT_KEY: String = "created_at"
## Random bytes of the cloud.device id (hex encoded).
const DEVICE_ID_BYTES: int = 16

## Current status (one of the STATUS_* constants).
var status: StringName = STATUS_IDLE
## Error code of the last failed sync ("" after a successful one).
var last_error: String = ""
## True when the last sync merged two diverged copies.
var last_conflict: bool = false
## The wallet a new install starts with ({"coins", "gems"}, the economy's
## starting balance): a device that never synced earned only what it holds
## beyond it.
var starting_wallet: Dictionary = EconomyService.FALLBACK_STARTING.duplicate()
## Days a daily completion may lie after today (the daily challenge's late
## grace): a cloud copy's later day is never adopted.
var daily_grace_days: int = DailyChallengeService.DEFAULT_GRACE_DAYS

var _provider: CloudSaveProvider
var _profile: PlayerProfile
var _clock: GameClock
var _encode: Callable
var _decode: Callable
var _syncing: bool = false
## Fingerprint of the profile content the cloud is known to hold.
var _clean_fingerprint: String = ""
## Per sync: whether this device had changes the cloud had not seen.
var _local_changed: bool = false


## [param encode] is (profile: PlayerProfile, now_unix: int) -> String and
## [param decode] is (text: String) -> Dictionary, defaulting to
## [method SaveService.encode] / [method SaveService.decode]. A null provider
## means the feature is off. [param _bus] is not used: a merge publishes no
## currency change (it is not earning), only [signal profile_merged].
func _init(
	provider: CloudSaveProvider,
	profile: PlayerProfile,
	clock: GameClock,
	_bus: EventBus,
	encode: Callable = Callable(),
	decode: Callable = Callable()
) -> void:
	_provider = provider if provider != null else NullCloudSaveProvider.new()
	if profile == null:
		GameLog.error("cloud", "no profile injected; cloud save works on a blank profile")
		profile = PlayerProfile.new()
	_profile = profile
	_clock = clock if clock != null else GameClock.new()
	_encode = encode
	if not _encode.is_valid():
		_encode = func(p: PlayerProfile, now_unix: int) -> String: return SaveService.encode(p, now_unix)
	_decode = decode
	if not _decode.is_valid():
		_decode = func(text: String) -> Dictionary: return SaveService.decode(text)
	var synced_hash: Variant = _profile.flags.get(FLAG_SYNCED_HASH, "")
	var known: bool = typeof(synced_hash) == TYPE_STRING and not (synced_hash as String).is_empty()
	_clean_fingerprint = synced_hash as String if known else _fingerprint()
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


## Flags the profile dirty when its content changed since the cloud last
## matched it. Call it before writing a save (so the flag is written with it)
## and after.
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
	# Remote config may have switched the feature off while the request ran.
	_set_status(outcome if is_enabled() else STATUS_OFF)
	sync_finished.emit(outcome, last_conflict)
	return outcome


func _run(provider: CloudSaveProvider) -> StringName:
	# What the profile held when the request left: a change made while it is
	# in flight is not something the cloud has seen.
	var started_from: String = _fingerprint()
	_local_changed = (
		is_dirty()
		or started_from != _clean_fingerprint
		or (revision().is_empty() and ProfileMerge.has_progress(_profile.to_dict()))
	)
	var fetched: Variant = await provider.fetch()
	var res: Dictionary = fetched as Dictionary if typeof(fetched) == TYPE_DICTIONARY else {}
	if not CloudSaveService._is_true(res.get("ok", false)):
		return _failed(res, false)
	var base: String = ""
	if CloudSaveService._is_true(res.get("found", false)):
		base = CloudSaveProvider.valid_revision(res.get("revision", ""))
		var unchanged: bool = not base.is_empty() and base == revision()
		var idle: bool = not _local_changed and not is_dirty() and _fingerprint() == started_from
		if unchanged and idle:
			_mark_synced(base, synced_at(), started_from)
			return STATUS_SYNCED
		if not unchanged:
			var problem: String = _merge_in(str(res.get("blob", "")))
			if not problem.is_empty():
				return _failed({"retry": false, "error": problem}, false)
	return await _push(provider, base, true)


func _push(provider: CloudSaveProvider, base: String, may_retry: bool) -> StringName:
	var now: int = _clock.now_unix()
	_prepare_push()
	var blob: String = str(_encode.call(PlayerProfile.from_dict(ProfileMerge.travelling(_profile.to_dict())), now))
	var pushed: String = _fingerprint()
	var answer: Variant = await provider.push(blob, base)
	var res: Dictionary = answer as Dictionary if typeof(answer) == TYPE_DICTIONARY else {}
	if CloudSaveService._is_true(res.get("ok", false)):
		_adopt_pending()
		_mark_synced(CloudSaveProvider.valid_revision(res.get("revision", "")), now, pushed)
		return STATUS_CONFLICT_RESOLVED if last_conflict else STATUS_SYNCED
	if CloudSaveService._is_true(res.get("conflict", false)) and may_retry:
		last_conflict = true
		var problem: String = _merge_in(str(res.get("remote_blob", "")))
		if not problem.is_empty():
			return _failed({"retry": false, "error": problem}, true)
		return await _push(provider, CloudSaveProvider.valid_revision(res.get("remote_revision", "")), false)
	return _failed(res, true)


## Counts the push about to be sent in sync.pushes and records the copy it
## carries as cloud.pending (see [ProfileMerge]), then asks the owner to
## persist both.
func _prepare_push() -> void:
	var device: String = _device_id()
	var pushes: Dictionary = CloudSaveService._dict(_profile.flags.get(ProfileMerge.FLAG_PUSHES)).duplicate()
	var seq: int = maxi(0, int(pushes.get(device, 0))) + 1
	pushes[device] = seq
	_profile.flags[ProfileMerge.FLAG_PUSHES] = pushes
	var pending: Dictionary = WalletMerge.wallet_of(_profile.to_dict())
	pending[ProfileMerge.PENDING_SEQ] = seq
	_profile.flags[ProfileMerge.FLAG_PENDING] = pending
	_profile.flags[ProfileMerge.FLAG_PENDING_LEDGER] = WalletMerge.ledger_ids(_profile.ledger)
	push_prepared.emit()


## The cloud accepted the pending copy: it is the new base.
func _adopt_pending() -> void:
	var pending: Dictionary = CloudSaveService._dict(_profile.flags.get(ProfileMerge.FLAG_PENDING)).duplicate()
	pending.erase(ProfileMerge.PENDING_SEQ)
	_profile.flags[ProfileMerge.FLAG_BASE] = pending
	_profile.flags[ProfileMerge.FLAG_BASE_LEDGER] = CloudSaveService._dict(
		_profile.flags.get(ProfileMerge.FLAG_PENDING_LEDGER)
	)
	_profile.flags.erase(ProfileMerge.FLAG_PENDING)
	_profile.flags.erase(ProfileMerge.FLAG_PENDING_LEDGER)


## This device's id in sync.pushes (cloud.device; created on first use).
func _device_id() -> String:
	var id: Variant = _profile.flags.get(ProfileMerge.FLAG_DEVICE, "")
	if typeof(id) == TYPE_STRING and not (id as String).is_empty():
		return id as String
	var created: String = Crypto.new().generate_random_bytes(DEVICE_ID_BYTES).hex_encode()
	_profile.flags[ProfileMerge.FLAG_DEVICE] = created
	return created


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
	var remote_time: int = clampi(int(saved_at) if CloudSaveService._is_int(saved_at) else 0, 0, _clock.now_unix())
	var data: Dictionary = payload as Dictionary
	if version < SaveService.CURRENT_VERSION:
		data = SaveMigrations.migrate(data, version)
		if not data.has(CREATED_AT_KEY):
			data[CREATED_AT_KEY] = remote_time
	var remote: Dictionary = PlayerProfile.from_dict(data).to_dict()
	if _local_changed:
		last_conflict = true
	_apply(ProfileMerge.merge(_profile.to_dict(), remote, _clock.now_unix(), starting_wallet, daily_grace_days))
	return ""


## Replaces the live profile with [param merged]. Coins and gems that arrive
## this way were earned on another device: no currency change is published,
## so nothing counts them as earned here.
func _apply(merged: Dictionary) -> void:
	var clean: PlayerProfile = PlayerProfile.from_dict(merged)
	clean.install_id = _profile.install_id
	_profile.copy_from(clean)
	profile_merged.emit()


func _mark_synced(new_revision: String, stamp: int, clean_fingerprint: String) -> void:
	_profile.flags[FLAG_REVISION] = new_revision
	_profile.flags[FLAG_SYNCED_AT] = maxi(0, stamp)
	_profile.flags[FLAG_SYNCED_HASH] = clean_fingerprint
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


## Hash of the profile content that travels to the cloud.
func _fingerprint() -> String:
	return JsonIO.canonical(ProfileMerge.travelling(_profile.to_dict())).sha256_text()


static func _dict(value: Variant) -> Dictionary:
	return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


static func _is_int(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value as float))


## True only for a real boolean true (untrusted data).
static func _is_true(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL and bool(value)
