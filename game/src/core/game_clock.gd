class_name GameClock
extends RefCounted
## Injectable wall-clock (UTC). Daily content, streaks and missions use this so
## tests can simulate arbitrary dates without touching the system clock.

var _fixed_unix: int = -1


func set_fixed_unix(unix_seconds: int) -> void:
	_fixed_unix = unix_seconds


func now_unix() -> int:
	if _fixed_unix >= 0:
		return _fixed_unix
	return int(Time.get_unix_time_from_system())


## Days since the Unix epoch in UTC — the canonical "day number".
func day_number() -> int:
	return now_unix() / 86400


## ISO-8601 week key "YYYY-Www" (UTC).
func week_key() -> String:
	return GameClock.week_key_for_day(day_number())


func date_key() -> String:
	return GameClock.date_key_for_day(day_number())


static func date_key_for_day(day: int) -> String:
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(day * 86400)
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


static func week_key_for_day(day: int) -> String:
	# 1970-01-01 was a Thursday; ISO weeks start on Monday.
	var monday_based: int = (day + 3) % 7
	var thursday: int = day - monday_based + 3
	var td: Dictionary = Time.get_datetime_dict_from_unix_time(thursday * 86400)
	var year: int = int(td["year"])
	var jan1: int = int(Time.get_unix_time_from_datetime_dict({"year": year, "month": 1, "day": 1})) / 86400
	var week: int = (thursday - jan1) / 7 + 1
	return "%04d-W%02d" % [year, week]
