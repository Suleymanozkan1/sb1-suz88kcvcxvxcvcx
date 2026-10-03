class_name NullStoreProvider
extends StoreProvider
## Provider used when no billing SDK is present. Every call fails with a clear
## "store_unavailable" error so the UI can say so instead of faking success.


## Always false.
func is_available() -> bool:
	return false


## No listings.
func products() -> Array:
	return []


## Always fails with "store_unavailable".
func purchase(_product_id: String) -> Dictionary:
	return {"ok": false, "receipt": "", "error": ERR_UNAVAILABLE}


## Always fails with "store_unavailable".
func restore() -> Dictionary:
	return {"ok": false, "product_ids": [], "error": ERR_UNAVAILABLE}
