class_name MemoryAnalyticsSink
extends AnalyticsSink
## Keeps the most recent events in memory (debug overlay, session summary,
## tests). Bounded: the oldest events are discarded first.

const DEFAULT_MAX_EVENTS: int = 1000

var events: Array[Dictionary] = []
var max_events: int = DEFAULT_MAX_EVENTS


func _init(max_event_count: int = DEFAULT_MAX_EVENTS) -> void:
	max_events = maxi(1, max_event_count)


## Stores deep copies so later mutation by the caller cannot alter history.
func send(batch: Array[Dictionary]) -> void:
	for event: Dictionary in batch:
		events.append(event.duplicate(true))
	var overflow: int = events.size() - max_events
	if overflow > 0:
		var kept: Array[Dictionary] = []
		kept.assign(events.slice(overflow))
		events = kept


## Forgets every stored event.
func clear() -> void:
	events.clear()


## Event names in recording order.
func names() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for event: Dictionary in events:
		out.append(str(event.get("event", "")))
	return out


## The most recent event, or an empty dictionary.
func last() -> Dictionary:
	return events.back() if not events.is_empty() else {}


## All stored events with the given name.
func with_name(event_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for event: Dictionary in events:
		if str(event.get("event", "")) == event_name:
			out.append(event)
	return out
