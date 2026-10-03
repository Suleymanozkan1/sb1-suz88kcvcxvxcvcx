class_name StoreProvider
extends RefCounted
## Adapter around the platform billing service (App Store / Google Play).
##
## No billing SDK is linked into this build, so the composition root uses
## [NullStoreProvider]. A platform plugin would subclass this; [method purchase]
## and [method restore] may then be coroutines (callers always await them).
## The base class is honest about being unavailable and never reports a
## purchase that did not happen.

const ERR_UNAVAILABLE: String = "store_unavailable"


## True when the platform store can take purchases right now.
func is_available() -> bool:
	return false


## Store listings from the platform: [{"id": String, "price": String}, ...]
## where "price" is the localized price text supplied by the platform.
func products() -> Array:
	return []


## Starts a purchase. Returns {"ok": bool, "receipt": String, "error": String}.
func purchase(_product_id: String) -> Dictionary:
	return {"ok": false, "receipt": "", "error": ERR_UNAVAILABLE}


## Restores non-consumable purchases. Returns
## {"ok": bool, "product_ids": Array, "error": String}.
func restore() -> Dictionary:
	return {"ok": false, "product_ids": [], "error": ERR_UNAVAILABLE}
