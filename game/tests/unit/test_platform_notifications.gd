extends TestCase
## Notifications: opt-in only, at most one per day, friendly local time.

const ISTANBUL_OFFSET_MINUTES: int = 180
const NEW_YORK_OFFSET_MINUTES: int = -240

var _profile: PlayerProfile
var _clock: GameClock
var _provider: RecordingNotificationProvider


## Records schedule/cancel calls; can be told to decline.
class RecordingNotificationProvider:
	extends NotificationProvider
	var accept: bool = true
	var scheduled: Array[Dictionary] = []
	var cancel_calls: int = 0

	func schedule(id: String, title: String, body: String, at_unix: int) -> bool:
		if accept:
			scheduled.append({"id": id, "title": title, "body": body, "at": at_unix})
		return accept

	func cancel_all() -> void:
		cancel_calls += 1


func before_each() -> void:
	_profile = PlayerProfile.create_new(0)
	_clock = GameClock.new()
	_clock.set_fixed_unix(_utc(2026, 10, 3, 9, 30))
	_provider = RecordingNotificationProvider.new()


func _utc(year: int, month: int, day: int, hour: int, minute: int = 0) -> int:
	var dict: Dictionary = {"year": year, "month": month, "day": day, "hour": hour, "minute": minute, "second": 0}
	return int(Time.get_unix_time_from_datetime_dict(dict))


func _service(offset_minutes: int = ISTANBUL_OFFSET_MINUTES) -> NotificationService:
	var svc: NotificationService = NotificationService.new(_profile, _clock, _provider)
	svc.utc_offset_minutes = offset_minutes
	return svc


func test_opt_in_is_required() -> void:
	assert_eq(PlayerProfile.DEFAULT_SETTINGS["notifications"], false, "off by default")
	var svc: NotificationService = _service()
	assert_false(svc.is_enabled())
	assert_false(svc.schedule_daily_reminder())
	assert_empty(_provider.scheduled, "nothing scheduled without opt-in")
	assert_eq(_provider.cancel_calls, 1, "opted-out state is enforced by cancelling")
	_profile.settings["notifications"] = "yes"
	assert_false(svc.is_enabled(), "only a real true opts in")


func test_schedules_next_day_at_friendly_local_hour() -> void:
	_profile.settings["notifications"] = true
	var svc: NotificationService = _service()
	assert_true(svc.schedule_daily_reminder())
	assert_eq(_provider.scheduled.size(), 1)
	var entry: Dictionary = _provider.scheduled[0]
	assert_eq(entry["id"], NotificationService.DAILY_REMINDER_ID)
	# 09:30 UTC = 12:30 in Istanbul -> tomorrow 18:00 local = 15:00 UTC.
	assert_eq(entry["at"], _utc(2026, 10, 4, 15))
	assert_eq(entry["title"], String(TranslationServer.translate(NotificationService.TITLE_KEY)))
	assert_eq(entry["body"], String(TranslationServer.translate(NotificationService.BODY_KEY)))
	assert_eq(svc.scheduled_day(), svc.local_day(_utc(2026, 10, 4, 15)))


func test_negative_utc_offset() -> void:
	_profile.settings["notifications"] = true
	_clock.set_fixed_unix(_utc(2026, 10, 3, 2))
	var svc: NotificationService = _service(NEW_YORK_OFFSET_MINUTES)
	assert_true(svc.schedule_daily_reminder())
	# 02:00 UTC = 22:00 on Oct 2 in New York -> Oct 3 18:00 local = 22:00 UTC.
	assert_eq(_provider.scheduled[0]["at"], _utc(2026, 10, 3, 22))


func test_at_most_one_per_day() -> void:
	_profile.settings["notifications"] = true
	var svc: NotificationService = _service()
	assert_true(svc.schedule_daily_reminder())
	_clock.set_fixed_unix(_utc(2026, 10, 3, 13))
	assert_false(svc.schedule_daily_reminder(), "same day: not scheduled again")
	assert_false(svc.refresh())
	assert_eq(_provider.scheduled.size(), 1)
	_clock.set_fixed_unix(_utc(2026, 10, 4, 8))
	assert_true(svc.schedule_daily_reminder(), "playing the next day moves the reminder one day on")
	assert_eq(_provider.scheduled.size(), 2)
	assert_eq(_provider.scheduled[1]["at"], _utc(2026, 10, 5, 15))
	assert_eq(_provider.scheduled[1]["id"], _provider.scheduled[0]["id"], "same id replaces the pending one")


func test_disabling_cancels_everything() -> void:
	_profile.settings["notifications"] = true
	var svc: NotificationService = _service()
	assert_true(svc.refresh())
	_profile.settings["notifications"] = false
	assert_false(svc.refresh())
	assert_eq(_provider.cancel_calls, 1)
	assert_eq(svc.scheduled_day(), -1)
	_profile.settings["notifications"] = true
	assert_true(svc.refresh(), "re-enabling schedules again")


func test_reminder_hour_is_clamped_to_friendly_window() -> void:
	_profile.settings["notifications"] = true
	var svc: NotificationService = _service(0)
	svc.reminder_hour = 3
	assert_eq(svc.next_reminder_unix(), _utc(2026, 10, 4, NotificationService.EARLIEST_FRIENDLY_HOUR))
	svc.reminder_hour = 23
	assert_eq(svc.next_reminder_unix(), _utc(2026, 10, 4, NotificationService.LATEST_FRIENDLY_HOUR))


func test_declined_or_unsupported_provider() -> void:
	_profile.settings["notifications"] = true
	_provider.accept = false
	var svc: NotificationService = _service()
	assert_false(svc.schedule_daily_reminder())
	assert_eq(svc.scheduled_day(), -1, "nothing recorded when the platform declines")
	var null_svc: NotificationService = NotificationService.new(_profile, _clock, NullNotificationProvider.new())
	assert_false(null_svc.schedule_daily_reminder())


func test_schedule_state_survives_save_round_trip() -> void:
	_profile.settings["notifications"] = true
	var svc: NotificationService = _service()
	svc.schedule_daily_reminder()
	var day: int = svc.scheduled_day()
	var parsed: Variant = JSON.parse_string(JSON.stringify(_profile.to_dict()))
	_profile = PlayerProfile.from_dict(parsed as Dictionary)
	var reloaded: NotificationService = _service()
	assert_eq(reloaded.scheduled_day(), day)
	assert_false(reloaded.schedule_daily_reminder(), "still once per day after a restart")
	assert_eq(_provider.scheduled.size(), 1)
