class_name NotificationProvider
extends RefCounted
## Adapter around the platform's local notification API.
##
## No notification plugin is linked into this build, so the composition root
## uses [NullNotificationProvider]. Scheduling with an id that is already
## pending replaces it, so a single id means at most one pending reminder.


## Schedules a local notification at [param at_unix] (UTC seconds). Returns
## false when the platform refused or does not support it.
func schedule(_id: String, _title: String, _body: String, _at_unix: int) -> bool:
	return false


## Cancels every pending notification of this app.
func cancel_all() -> void:
	pass
