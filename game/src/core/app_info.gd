class_name AppInfo
extends RefCounted
## Static facts about the running build (no PII).


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


static func platform() -> String:
	return OS.get_name()


static func engine_version() -> String:
	return str(Engine.get_version_info().get("string", ""))


static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]


static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func context() -> Dictionary:
	return {
		"app_version": version(),
		"platform": platform(),
		"engine": engine_version(),
		"locale": TranslationServer.get_locale(),
	}
