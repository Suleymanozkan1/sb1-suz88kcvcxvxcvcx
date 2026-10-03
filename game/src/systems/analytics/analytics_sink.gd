class_name AnalyticsSink
extends RefCounted
## Destination for recorded analytics events.
##
## The base class discards everything. Sinks receive events that the
## [AnalyticsService] has already validated, stripped of anything undeclared
## and enriched; they never see raw caller parameters.


## Receives a batch of validated, enriched events.
func send(_events: Array[Dictionary]) -> void:
	pass


## Delivers anything buffered (network sinks may be coroutines; callers always
## [code]await[/code] this). Returns true when nothing is left pending.
func flush() -> bool:
	return true


## Drops everything buffered or stored (used when consent is withdrawn).
func clear() -> void:
	pass
