class_name NetworkMonitor
extends RefCounted
## Tracks connectivity from real request outcomes (no polling, no pinging).
##
## Every request made through a transport wrapped with [method wrap] reports
## whether the server could be reached. [member online] flips only on real
## evidence and [signal EventBus.network_state_changed] is emitted on each
## transition. Being offline never blocks gameplay; online features simply
## queue their work until a request succeeds again.

## Current connectivity belief (optimistic until a request fails).
var online: bool = true
## Consecutive unreachable requests.
var failures_in_row: int = 0
## Total transitions observed (diagnostics).
var transitions: int = 0
var _bus: EventBus = null


func _init(bus: EventBus) -> void:
	_bus = bus


## Records a request outcome: [param ok] is true when the server was reached.
func report(ok: bool) -> void:
	failures_in_row = 0 if ok else failures_in_row + 1
	if ok == online:
		return
	online = ok
	transitions += 1
	GameLog.info("network", "now %s" % ("online" if online else "offline"))
	if _bus != null:
		_bus.network_state_changed.emit(online)


## True when a transport response proves the server was reached: ok=true or
## any HTTP status (status 0 = timeout, DNS failure, no connection).
static func server_reached(response: Dictionary) -> bool:
	var ok: Variant = response.get("ok", false)
	var status: Variant = response.get("status", 0)
	var has_status: bool = (typeof(status) == TYPE_INT or typeof(status) == TYPE_FLOAT) and int(status) > 0
	return (typeof(ok) == TYPE_BOOL and bool(ok)) or has_status


## Wraps a transport Callable ((method, url, body) -> Dictionary) so that each
## response is reported here. Any HTTP status means the server was reached;
## status 0 (timeout, DNS, no connection) means offline.
func wrap(transport: Callable) -> Callable:
	return func(method: String, url: String, body: Dictionary) -> Dictionary:
		var response: Variant = await transport.call(method, url, body)
		var result: Dictionary = {"ok": false, "status": 0, "body": null, "error": "invalid_response"}
		if typeof(response) == TYPE_DICTIONARY:
			result = response as Dictionary
		report(NetworkMonitor.server_reached(result))
		return result
