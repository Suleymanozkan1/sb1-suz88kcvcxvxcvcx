class_name NullNotificationProvider
extends NotificationProvider
## Provider used when the platform has no local notification support: every
## schedule request is declined (returns false) and nothing is ever shown.


## Always declines.
func schedule(_id: String, _title: String, _body: String, _at_unix: int) -> bool:
	return false


## Nothing to cancel.
func cancel_all() -> void:
	pass
