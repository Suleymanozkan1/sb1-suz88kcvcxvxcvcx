class_name AppServices
extends Node
## Composition root (autoload "Services"). Builds every system once with
## constructor injection, wires them through the [EventBus], and owns the save
## cadence. Systems never reach for this node themselves: only the app layer
## (GameFlow and screens' presenters) reads it, which keeps modules testable.

signal booted

const SAVE_INTERVAL: float = 1.5
const ANALYTICS_FILE: String = "user://analytics/events.jsonl"
const REMOTE_CACHE: String = "user://remote_config.json"
## 1970-01-01 (day 0) was a Thursday; weekdays count from Sunday = 0.
const EPOCH_WEEKDAY: int = 4
const DAYS_PER_WEEK: int = 7
const SATURDAY: int = 6
const SUNDAY: int = 0
const DEFAULT_PLAYER_NAME: String = "You"

var bus: EventBus
var clock: GameClock
var errors: ErrorReporter
var catalog: WorldCatalog
var levels: LevelRepository
var difficulty: DifficultyModel
var modes: ModeCatalog
var save: SaveService
var profile: PlayerProfile
var settings: SettingsService
var localization: Localization
var economy: EconomyService
var integrity: IntegrityMonitor
var stats: StatsService
var progression: ProgressionService
var cosmetics_catalog: CosmeticCatalog
var cosmetics: CosmeticService
var rewards: RewardEngine
var achievements: AchievementService
var missions: MissionService
var daily: DailyChallengeService
var online_config: Dictionary = {}
var remote_config: RemoteConfig
var transport: HttpTransport
var network: NetworkMonitor
var analytics: AnalyticsService
var leaderboard: LeaderboardService
var ads: AdsService
var store: StoreService
var notifications: NotificationService
var haptics: HapticsService
var audio: AudioService
var quality: QualityService
var is_booted: bool = false
## Tests construct their own instance with auto_boot off and call [method boot]
## with in-memory storage and a fixed clock.
var auto_boot: bool = true
## True while a run is being played (set by the flow): the debounced autosave
## waits for the result screen or a menu, so a save never hitches gameplay.
## Pause, focus loss and quit still save at once (flush_now).
var hold_autosave: bool = false

var _save_left: float = 0.0
var _integrity_reported: String = ""
## Level-up reveals waiting to be shown ({eyebrow, title, subtitle, bundle}).
var _level_up_reveals: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Tools and the test runner run as SceneTree scripts: they build their own
	# isolated services, so the global graph only boots for the real game.
	if auto_boot and get_tree().get_script() == null:
		boot()


## Builds the whole service graph. Safe to call once; later calls are ignored.
## [param storage] and [param game_clock] are injection points for tests.
func boot(storage: SaveStorage = null, game_clock: GameClock = null) -> void:
	if is_booted:
		return
	bus = EventBus.new()
	clock = game_clock if game_clock != null else GameClock.new()
	errors = ErrorReporter.new()
	errors.context_provider = _error_context
	errors.install()
	catalog = WorldCatalog.load_default()
	levels = LevelRepository.new(catalog)
	difficulty = DifficultyModel.new(catalog)
	modes = ModeCatalog.load_default()
	_boot_save(storage if storage != null else FileSaveStorage.new())
	settings = SettingsService.new(profile, bus)
	localization = Localization.new(Localization.DEFAULT_DIR, bus)
	localization.install(settings.get_string("language"))
	localization.bind_settings(settings)
	_boot_economy()
	_boot_meta()
	_boot_platform()
	_boot_feel()
	_wire()
	is_booted = true
	analytics.track(
		&"session_started", {"locale": localization.current_locale(), "quality": String(quality.effective_preset())}
	)
	booted.emit()


func _boot_save(storage: SaveStorage) -> void:
	save = SaveService.new(storage, clock)
	save.recovered.connect(func(source: String) -> void: bus.save_recovered.emit(source))
	profile = save.load_profile()


func _boot_economy() -> void:
	economy = EconomyService.new(profile, bus, clock)
	economy.apply_starting_balance()
	integrity = IntegrityMonitor.new(profile, {}, clock)
	var progression_cfg: Dictionary = ProgressionService.load_config()
	progression = ProgressionService.new(profile, bus, catalog, progression_cfg)
	stats = StatsService.new(profile, bus, progression_cfg)
	stats.connect_bus()
	cosmetics_catalog = CosmeticCatalog.load_default()
	cosmetics = CosmeticService.new(profile, bus, cosmetics_catalog, economy, _progress_query)
	cosmetics.ensure_defaults()
	stats.set_value("cosmetics_owned", cosmetics.owned_count())
	rewards = RewardEngine.new(
		profile,
		bus,
		economy,
		func(amount: int) -> void: progression.add_xp(amount),
		func(item_id: String) -> bool: return cosmetics.grant(item_id)
	)


func _boot_meta() -> void:
	achievements = AchievementService.new(profile, bus, clock, rewards.grant_spec)
	missions = MissionService.new(profile, bus, clock, rewards.grant_spec)
	missions.refresh()
	online_config = DailyChallengeService.load_config()
	daily = DailyChallengeService.new(profile, bus, clock, catalog, rewards.grant_table, online_config)
	progression.refresh_world_unlocks()


func _boot_platform() -> void:
	remote_config = RemoteConfig.new(
		RemoteConfig.load_defaults(), RemoteConfig.file_reader(REMOTE_CACHE), RemoteConfig.file_writer(REMOTE_CACHE)
	)
	remote_config.load_cache()
	_apply_remote_tuning()
	remote_config.applied.connect(func(_keys: PackedStringArray) -> void: _apply_remote_tuning())
	bus.run_started.connect(func(_level: String, _mode: StringName) -> void: _apply_remote_tuning())
	transport = HttpTransport.new()
	transport.name = "HttpTransport"
	add_child(transport)
	network = NetworkMonitor.new(bus)
	var net: Callable = network.wrap(transport.as_callable())
	analytics = AnalyticsService.new(profile.install_id, clock)
	analytics.enabled = settings.get_bool("analytics")
	analytics.add_sink(FileAnalyticsSink.new(ANALYTICS_FILE))
	var endpoint: String = remote_config.get_string("analytics.endpoint")
	if not endpoint.is_empty():
		analytics.add_sink(HttpAnalyticsSink.new(endpoint, net))
	var board_cfg: Dictionary = online_config.get("leaderboard", {}) as Dictionary
	var local_board: LocalLeaderboardBackend = LocalLeaderboardBackend.new(
		LocalLeaderboardBackend.profile_store(profile), board_cfg, DEFAULT_PLAYER_NAME
	)
	var base_url: String = remote_config.get_string("leaderboard.base_url")
	var remote_board: LeaderboardBackend = null
	if not base_url.is_empty():
		remote_board = HttpLeaderboardBackend.new(base_url, net, profile.install_id, AppInfo.version(), board_cfg)
	leaderboard = LeaderboardService.new(profile, bus, clock, local_board, remote_board, online_config)
	leaderboard.integrity = integrity
	var policy: Dictionary = AdsPolicy.merge_remote(AdsPolicy.load_default(), remote_config)
	ads = AdsService.new(profile, bus, NullAdProvider.new(), policy, analytics.track, clock)
	store = StoreService.new(
		profile,
		bus,
		NullStoreProvider.new(),
		StoreService.load_products(),
		cosmetics.grant_from_product,
		analytics.track
	)
	notifications = NotificationService.new(profile, clock, NullNotificationProvider.new())
	store.reconcile_owned()
	analytics.track_error_reports(errors.collect_reports(true))
	_fetch_remote_config.call_deferred(net)
	# Scores queued offline in an earlier session (the network may simply be
	# up from the start, so no offline->online change would trigger it).
	leaderboard.flush_queue.call_deferred()
	check_integrity()


func _boot_feel() -> void:
	haptics = HapticsService.new(settings)
	audio = AudioService.new()
	audio.name = "AudioService"
	add_child(audio)
	audio.setup(settings, SoundBank.from_file())
	quality = QualityService.new(settings, bus)
	quality.apply_to_viewport(get_viewport())


func _wire() -> void:
	for sig: Signal in [
		bus.currency_changed,
		bus.reward_granted,
		bus.stars_changed,
		bus.cosmetic_equipped,
		bus.cosmetic_unlocked,
		bus.achievement_unlocked,
		bus.mission_completed,
		bus.settings_changed,
		bus.daily_completed,
		bus.purchase_completed,
		bus.player_level_up,
		bus.world_unlocked
	]:
		sig.connect(_on_state_fact)
	bus.settings_changed.connect(_on_setting)
	# Every preset change (including the automatic step-down on slow frames)
	# reaches the viewport: render scale, MSAA and the fps cap are what
	# actually relieve a struggling GPU.
	bus.quality_changed.connect(
		func(preset: StringName, automatic: bool) -> void:
			quality.apply_to_viewport(get_viewport())
			if automatic:
				analytics.track(&"quality_auto_reduced", {"to": String(preset)})
	)
	bus.save_recovered.connect(func(source: String) -> void: analytics.track(&"save_recovered", {"source": source}))
	bus.achievement_unlocked.connect(
		func(id: String) -> void: analytics.track(&"achievement_unlocked", {"achievement_id": id})
	)
	bus.player_level_up.connect(_on_level_up)
	bus.reward_granted.connect(_on_reward_granted)
	bus.world_unlocked.connect(
		func(world_id: String) -> void:
			analytics.track(&"world_unlocked", {"world_id": world_id, "total_stars": profile.total_stars()})
	)
	bus.daily_completed.connect(
		func(date_key: String, score: int) -> void:
			analytics.track(
				&"daily_completed",
				{
					"date_key": date_key,
					"score": score,
					"streak": int(daily.status().get("streak", 0)),
					"first_clear": true
				}
			)
	)
	bus.network_state_changed.connect(
		func(online: bool) -> void:
			if online:
				leaderboard.flush_queue()
	)
	leaderboard.queue_changed.connect(save.mark_dirty)
	bus.cosmetic_unlocked.connect(
		func(_id: String) -> void: stats.set_value("cosmetics_owned", cosmetics.owned_count())
	)
	UiKit.feedback_hook = ui_feedback


## Any persisted fact changed: save soon (debounced).
func _on_state_fact(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	save.mark_dirty()


func _on_setting(key: StringName, value: Variant) -> void:
	save.mark_dirty()
	match String(key):
		"analytics":
			analytics.enabled = bool(value)
		"notifications":
			notifications.refresh()
		"quality":
			quality.set_preset(StringName(str(value)))
			quality.apply_to_viewport(get_viewport())
		"battery_saver":
			quality.apply_to_viewport(get_viewport())
	analytics.track(&"settings_changed", {"key": String(key), "value": str(value)})


## Reward specs ({"coins", "gems", "xp", "cosmetic", "badge"} or a table
## request {"table", ...}) become real, applied bundles: the returned bundle is
## exactly what was granted.
func grant_reward_spec(spec: Dictionary, source: String = "reward") -> RewardBundle:
	if spec.has(RewardEngine.REQUEST_TABLE):
		return rewards.grant_table(spec)
	return rewards.grant_spec(spec, source)


## Every level gained (in a run, from a mission claim, from an achievement)
## pays its level-up table reward right away and queues a reveal.
func _on_level_up(level: int) -> void:
	var bundle: RewardBundle = rewards.grant_table({"table": RewardEngine.TABLE_LEVEL_UP, "level": level})
	(
		_level_up_reveals
		. append(
			{
				"eyebrow": TranslationServer.translate("reveal.level_up"),
				"title": TranslationServer.translate("reveal.level_n").format({"n": level}),
				"subtitle": "",
				"bundle": bundle,
			}
		)
	)


## Pending level-up reveals (cleared by the call).
func take_level_up_reveals() -> Array[Dictionary]:
	var out: Array[Dictionary] = _level_up_reveals.duplicate()
	_level_up_reveals.clear()
	return out


func _on_reward_granted(bundle: RewardBundle) -> void:
	if bundle == null or bundle.is_empty():
		return
	(
		analytics
		. track(
			&"reward_claimed",
			{
				"source": bundle.source,
				"coins": bundle.amount_of(&"coins"),
				"gems": bundle.amount_of(&"gems"),
				"xp": bundle.amount_of(&"xp"),
				"doubled": bundle.source.ends_with(RewardEngine.AD_DOUBLE_SOURCE_SUFFIX),
			}
		)
	)


## Remote overrides never block boot: applied, cached and pushed into the ad
## policy when reachable; offline keeps the cached or default values.
func _fetch_remote_config(net: Callable) -> void:
	var url: String = remote_config.get_string("config.url")
	if url.is_empty():
		return
	if await remote_config.fetch(net, url):
		ads.set_policy(AdsPolicy.merge_remote(AdsPolicy.load_default(), remote_config))


## Facts the cosmetics service needs for automatic unlocks.
func _progress_query() -> Dictionary:
	var unlocked: Array[String] = []
	for id: Variant in profile.achievements.keys():
		unlocked.append(str(id))
	return {
		"total_stars": profile.total_stars(),
		"player_level": profile.player_level,
		"perfects": profile.stat("unique_perfects"),
		"achievements": unlocked,
	}


## Mode unlock facts (see [ModeCatalog.is_unlocked]).
func mode_progress() -> Dictionary:
	# Distinct achievements only: replaying one boss must not unlock modes
	# that promise "beat 2 bosses" / "finish 2 worlds".
	var distinct_bosses: int = 0
	for i: int in range(1, catalog.world_count() + 1):
		if profile.is_cleared(WorldCatalog.level_id(i, catalog.levels_in(i))):
			distinct_bosses += 1
	return {
		"levels_cleared": profile.stat("unique_levels_cleared"),
		"perfects": profile.stat("unique_perfects"),
		"bosses_cleared": distinct_bosses,
		"worlds_cleared": profile.stat("worlds_completed"),
		"stars": progression.total_stars(),
	}


## UI feedback (clicks, toggles): sound + haptic through the same rules as gameplay.
func ui_feedback(kind: StringName) -> void:
	audio.play_sfx(kind)
	haptics.play(&"ui")


func _process(delta: float) -> void:
	if not is_booted:
		return
	# Crash reports are written as soon as they are captured (a later native
	# crash or OS kill must not lose them).
	if errors.has_pending():
		errors.flush()
	_save_left -= delta
	if _save_left <= 0.0 and not hold_autosave:
		_save_left = SAVE_INTERVAL
		save.flush_if_dirty(profile)


## Remote economy tuning: coin multiplier (times the weekend event bonus on
## UTC Saturdays and Sundays) and daily reward multiplier. Recomputed at boot,
## when a config snapshot arrives and at every run start (the weekend begins
## and ends at midnight).
func _apply_remote_tuning() -> void:
	var weekday: int = posmod(clock.day_number() + EPOCH_WEEKDAY, DAYS_PER_WEEK)
	var weekend: bool = weekday == SATURDAY or weekday == SUNDAY
	var bonus: float = remote_config.get_float("events.weekend_coin_bonus", 0.0) if weekend else 0.0
	rewards.coin_scale = remote_config.get_float("economy.coin_multiplier", 1.0) * (1.0 + bonus)
	rewards.daily_scale = remote_config.get_float("economy.daily_reward_multiplier", 1.0)


## Wallet/ledger consistency (after load and after every run). Detection
## only: anomalies are reported once per session as analytics and travel with
## score submissions for server review; the player is never penalised.
func check_integrity() -> Array[String]:
	var codes: Array[String] = integrity.check()
	var key: String = ",".join(codes)
	if not codes.is_empty() and key != _integrity_reported:
		_integrity_reported = key
		analytics.track(&"integrity_flagged", {"codes": key})
	return codes


## Persists everything now (app pause, quit, focus loss).
func flush_now() -> void:
	if not is_booted:
		return
	save.mark_dirty()
	save.flush_if_dirty(profile)
	analytics.flush()
	errors.flush()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			flush_now()
			if is_booted:
				notifications.refresh()
		NOTIFICATION_PREDELETE:
			if errors != null:
				errors.uninstall()
			if localization != null:
				localization.uninstall()


func _error_context() -> Dictionary:
	var ctx: Dictionary = AppInfo.context()
	ctx["level"] = str(profile.flags.get("last_level", "")) if profile != null else ""
	return ctx
