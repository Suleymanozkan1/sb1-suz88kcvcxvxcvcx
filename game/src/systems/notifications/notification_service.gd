class_name NotificationService
extends RefCounted
## Opt-in daily reminder.
##
## Nothing is scheduled unless the player enabled settings.notifications
## (off by default). At most one reminder exists at a time (fixed id) and at
## most one is scheduled per local day. It is always placed on the day after
## the player last played, at a friendly local hour, so nobody is reminded on
## a day they already played. The copy is neutral (no urgency, no streak
## threats). Turning the setting off cancels everything.

const SETTING_KEY: String = "notifications"
const DAILY_REMINDER_ID: String = "daily_reminder"
const TITLE_KEY: String = "notif.daily.title"
const BODY_KEY: String = "notif.daily.body"
## profile.flags key owned by this service: local day number of the pending reminder.
const STATE_FLAG: String = "notifications.daily_day"
const DEFAULT_REMINDER_HOUR: int = 18
const EARLIEST_FRIENDLY_HOUR: int = 10
const LATEST_FRIENDLY_HOUR: int = 20
const SECONDS_PER_MINUTE: int = 60
const SECONDS_PER_HOUR: int = 3600
const SECONDS_PER_DAY: int = 86400

## Local hour (clamped to the friendly window) the reminder is shown at.
var reminder_hour: int = DEFAULT_REMINDER_HOUR
## Local time offset from UTC in minutes (system time zone by default).
var utc_offset_minutes: int = 0
var _profile: PlayerProfile = null
var _clock: GameClock = null
var _provider: NotificationProvider = null


func _init(profile: PlayerProfile, clock: GameClock, provider: NotificationProvider) -> void:
	_profile = profile if profile != null else PlayerProfile.new()
	_clock = clock if clock != null else GameClock.new()
	_provider = provider if provider != null else NullNotificationProvider.new()
	utc_offset_minutes = int(Time.get_time_zone_from_system().get("bias", 0))


## True only when the player opted in.
func is_enabled() -> bool:
	var v: Variant = _profile.setting(SETTING_KEY)
	return typeof(v) == TYPE_BOOL and bool(v)


## Schedules the reminder for the next local day at [member reminder_hour].
## Returns true when a reminder was newly scheduled; false when opted out
## (everything is cancelled), already scheduled for that day, the reminder
## text is not translated, or the platform declined.
func schedule_daily_reminder() -> bool:
	if not is_enabled():
		cancel_all()
		return false
	var target: int = next_reminder_unix()
	var target_day: int = local_day(target)
	if scheduled_day() == target_day:
		return false
	var title: String = tr(TITLE_KEY)
	var body: String = tr(BODY_KEY)
	if title == TITLE_KEY or body == BODY_KEY:
		# Strings not loaded: never push a raw translation key to the player.
		GameLog.warn("notifications", "reminder text is not translated; nothing scheduled")
		return false
	var ok: bool = _provider.schedule(DAILY_REMINDER_ID, title, body, target)
	if ok:
		_profile.flags[STATE_FLAG] = target_day
	return ok


## Applies the current opt-in setting: schedules when enabled, cancels when
## not. Call after settings change and when the app goes to background.
func refresh() -> bool:
	if is_enabled():
		return schedule_daily_reminder()
	cancel_all()
	return false


## Cancels every pending reminder and forgets the schedule.
func cancel_all() -> void:
	_provider.cancel_all()
	_profile.flags.erase(STATE_FLAG)


## UTC time of the next reminder slot: tomorrow (local) at the friendly hour.
func next_reminder_unix() -> int:
	var hour: int = clampi(reminder_hour, EARLIEST_FRIENDLY_HOUR, LATEST_FRIENDLY_HOUR)
	var offset: int = utc_offset_minutes * SECONDS_PER_MINUTE
	var tomorrow: int = local_day(_clock.now_unix()) + 1
	return tomorrow * SECONDS_PER_DAY + hour * SECONDS_PER_HOUR - offset


## Local day number (days since epoch in local time) of [param unix_seconds].
func local_day(unix_seconds: int) -> int:
	return floori(float(unix_seconds + utc_offset_minutes * SECONDS_PER_MINUTE) / SECONDS_PER_DAY)


## Local day of the pending reminder, or -1 when none is scheduled.
func scheduled_day() -> int:
	var v: Variant = _profile.flags.get(STATE_FLAG, -1)
	return int(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else -1
