class_name NullCloudSaveProvider
extends CloudSaveProvider
## Provider of a build without a cloud save server (the shipped configuration:
## remote config cloud_save.base_url is empty). The feature is off: nothing is
## sent anywhere, and every call answers "cloud_unavailable" instead of
## pretending to sync. Progress stays in the local save, which works offline.


## Always false.
func is_enabled() -> bool:
	return false


## Never reaches a server.
func fetch() -> Dictionary:
	return CloudSaveProvider.fetch_result(false, false, "", "", false, ERROR_UNAVAILABLE)


## Never uploads anything.
func push(_blob: String, _base_revision: String) -> Dictionary:
	return CloudSaveProvider.push_result(false, "", false, false, ERROR_UNAVAILABLE)
