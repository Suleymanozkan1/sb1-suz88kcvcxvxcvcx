class_name MusicClock
extends RefCounted
## Keeps a run's music locked to the simulation clock (pure maths, no players).
##
## The level's beat grid starts at sim time 0, so the loop must too: audio
## position p belongs at sim time t modulo the loop length. Playback drifts
## (mix buffers, hit-stops, brief slow motion); small drift is pulled back by
## nudging the playback rate a few percent (inaudible, no splice), large jumps
## (a pause, a revive, an instant restart) by seeking straight to the run.

## Drift the ear forgives before a correction starts (a tight tap feels "on").
const TOLERANCE_S: float = 0.04
## A correction in progress stops once the drift is back under this.
const SETTLE_S: float = 0.01
## Beyond this the loop is somewhere else entirely: seek instead of nudging.
const SEEK_THRESHOLD_S: float = 0.25
## A seek is not re-checked for this long: the reported position lags a fresh seek.
const SEEK_COOLDOWN_S: float = 0.25
## Rate change per second of drift, and its cap (3 % ≈ half a semitone).
const RATE_GAIN: float = 0.5
const MAX_RATE_NUDGE: float = 0.03


## Where the loop should be at [param sim_time] (seconds since the run began).
static func target_position(sim_time: float, loop_length: float) -> float:
	if loop_length <= 0.0 or is_nan(sim_time):
		return 0.0
	return fposmod(maxf(sim_time, 0.0), loop_length)


## Signed drift of [param audio_pos] from where the run is (positive: the music
## is ahead), wrapped across the loop seam so a position just past the seam
## reads as slightly ahead, not a whole loop behind.
static func drift(audio_pos: float, sim_time: float, loop_length: float) -> float:
	if loop_length <= 0.0:
		return 0.0
	var half: float = loop_length * 0.5
	return fposmod(audio_pos - target_position(sim_time, loop_length) + half, loop_length) - half


## The position to seek to, or -1.0 while the drift is small enough to nudge.
static func seek_target(audio_pos: float, sim_time: float, loop_length: float) -> float:
	if loop_length <= 0.0 or absf(drift(audio_pos, sim_time, loop_length)) <= SEEK_THRESHOLD_S:
		return -1.0
	return target_position(sim_time, loop_length)


## Playback rate that pulls [param drift_s] back to zero. Hysteresis: a
## correction starts beyond [constant TOLERANCE_S] and runs (from
## [param current_rate] != 1) until the drift settles under [constant SETTLE_S].
static func playback_rate(drift_s: float, current_rate: float = 1.0) -> float:
	var size: float = absf(drift_s)
	if is_nan(drift_s) or size <= SETTLE_S:
		return 1.0
	if size <= TOLERANCE_S and is_equal_approx(current_rate, 1.0):
		return 1.0
	return 1.0 - clampf(drift_s * RATE_GAIN, -MAX_RATE_NUDGE, MAX_RATE_NUDGE)
