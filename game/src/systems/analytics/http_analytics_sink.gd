class_name HttpAnalyticsSink
extends AnalyticsSink
## Uploads events in batches through the injected HTTP transport.
##
## [method send] only queues; [method flush] uploads. While offline (or when
## the server fails) events stay queued and are retried on the next flush.
## The queue is bounded: when full, the oldest events are dropped first so a
## long offline period can never grow memory without limit. An empty endpoint
## disables the sink entirely (nothing is queued).

enum Outcome { SENT, REJECTED, RETRY }

const DEFAULT_BATCH_SIZE: int = 25
const DEFAULT_MAX_QUEUE: int = 400
const PAYLOAD_FORMAT: String = "flux_drop.analytics"
const PAYLOAD_VERSION: int = 1
const HTTP_METHOD: String = "POST"
const STATUS_CLIENT_ERROR_MIN: int = 400
const STATUS_CLIENT_ERROR_MAX: int = 499
## Client errors that are worth retrying (timeout, too early, rate limited).
const RETRYABLE_CLIENT_STATUSES: Array[int] = [408, 425, 429]

var endpoint: String = ""
var batch_size: int = DEFAULT_BATCH_SIZE
var max_queue: int = DEFAULT_MAX_QUEUE
## Events discarded because the offline queue was full.
var dropped_count: int = 0
## Events discarded because the server permanently rejected their batch.
var rejected_count: int = 0
var sent_count: int = 0
var _transport: Callable = Callable()
var _queue: Array[Dictionary] = []
var _flushing: bool = false
## Bumped by [method clear] so an upload that is in flight while consent is
## withdrawn can never put its batch back into the queue.
var _generation: int = 0


func _init(
	endpoint_url: String,
	transport: Callable,
	batch: int = DEFAULT_BATCH_SIZE,
	queue_limit: int = DEFAULT_MAX_QUEUE
) -> void:
	endpoint = endpoint_url.strip_edges()
	_transport = transport
	batch_size = maxi(1, batch)
	max_queue = maxi(batch_size, queue_limit)


## True when an endpoint and a transport are configured.
func is_enabled() -> bool:
	return not endpoint.is_empty() and _transport.is_valid()


## Queues events for the next upload.
func send(batch: Array[Dictionary]) -> void:
	if not is_enabled():
		return
	for event: Dictionary in batch:
		_queue.append(event.duplicate(true))
	_enforce_bound()


## Events waiting to be uploaded.
func queued_count() -> int:
	return _queue.size()


## Drops queued events (consent withdrawn), including a batch in flight.
func clear() -> void:
	_queue.clear()
	_generation += 1


## Uploads queued events batch by batch. Stops at the first transport failure
## and keeps the remaining events queued. Returns true when the queue is empty.
func flush() -> bool:
	if not is_enabled():
		return true
	if _flushing:
		return false
	_flushing = true
	var generation: int = _generation
	while not _queue.is_empty():
		var count: int = mini(batch_size, _queue.size())
		var in_flight: Array[Dictionary] = _take_front(count)
		var body: Dictionary = {"format": PAYLOAD_FORMAT, "version": PAYLOAD_VERSION, "events": in_flight}
		var response: Variant = await _transport.call(HTTP_METHOD, endpoint, body)
		var outcome: Outcome = _classify(response)
		if outcome == Outcome.SENT:
			sent_count += in_flight.size()
		elif outcome == Outcome.REJECTED:
			rejected_count += in_flight.size()
			GameLog.warn("analytics", "server rejected a batch of %d events; dropped" % in_flight.size())
		if generation != _generation:
			# Cleared while the request was in flight: drop the batch, stop here.
			break
		if outcome == Outcome.RETRY:
			# Put the batch back in front (it is the oldest data) and retry later.
			# A new array: the transport may still hold the request body.
			var requeued: Array[Dictionary] = in_flight.duplicate()
			requeued.append_array(_queue)
			_queue = requeued
			_enforce_bound()
			break
	_flushing = false
	return _queue.is_empty()


func _classify(response: Variant) -> Outcome:
	if typeof(response) != TYPE_DICTIONARY:
		return Outcome.RETRY
	var r: Dictionary = response as Dictionary
	if typeof(r.get("ok")) == TYPE_BOOL and bool(r["ok"]):
		return Outcome.SENT
	var raw_status: Variant = r.get("status", 0)
	var status: int = int(raw_status) if typeof(raw_status) == TYPE_INT or typeof(raw_status) == TYPE_FLOAT else 0
	var client_error: bool = status >= STATUS_CLIENT_ERROR_MIN and status <= STATUS_CLIENT_ERROR_MAX
	if client_error and not RETRYABLE_CLIENT_STATUSES.has(status):
		return Outcome.REJECTED
	return Outcome.RETRY


func _enforce_bound() -> void:
	var overflow: int = _queue.size() - max_queue
	if overflow <= 0:
		return
	dropped_count += overflow
	_take_front(overflow)
	GameLog.info("analytics", "offline queue full; dropped %d oldest events" % overflow)


## Removes and returns the first [param count] queued events.
func _take_front(count: int) -> Array[Dictionary]:
	var front: Array[Dictionary] = []
	front.assign(_queue.slice(0, count))
	var rest: Array[Dictionary] = []
	rest.assign(_queue.slice(count))
	_queue = rest
	return front
