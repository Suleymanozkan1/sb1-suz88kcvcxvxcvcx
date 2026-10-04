class_name FeelTuning
extends RefCounted
## The gameplay feel table: every hit-stop, slow motion, camera kick, core
## motion, post effect and feedback strength [GameplayView] applies when the
## simulation reports an event, by name instead of as inline numbers.
##
## The values implement docs/ART_DIRECTION.md §8 (motion language: the core is
## elastic and alive, obstacles heavy) and §9 (VFX rules: every effect has one
## job and a fixed budget; the camera shakes only on impacts, scaled by their
## weight; reduce motion cuts camera motion to 20 %). Change a budget here and
## in the document together. Reduce motion scales these values where they are
## applied (the REDUCED_* fractions), never by editing the table.

# --- Hit-stop: seconds the simulation holds on an impact (§9) -----------------

## Glass shattered: 30 ms.
const HIT_STOP_SHATTER: float = 0.03
## Each further link of a chain shatter: half a shatter, so chains stay fluid.
const HIT_STOP_CHAIN: float = 0.015
## The shield took a hit: 60 ms.
const HIT_STOP_SHIELD: float = 0.06
## The run failed: 90 ms, the heaviest beat in the game.
const HIT_STOP_FAIL: float = 0.09
## A full plate stack crashed through a barrier.
const HIT_STOP_STACK_CRASH: float = 0.05
## Reduce motion halves every hit-stop.
const REDUCED_HIT_STOP: float = 0.5

# --- Slow motion (§9) ---------------------------------------------------------

## A near miss slows time only from this combo on (a skill reward, not noise).
const NEAR_MISS_SLOWMO_COMBO: int = 10
## Near-miss slow motion: 80 ms at 0.75 × speed.
const NEAR_MISS_SLOWMO_SCALE: float = 0.75
const NEAR_MISS_SLOWMO_TIME: float = 0.08
## Run complete: time slows to this scale while the core dives into the sink.
const END_TIME_SCALE: float = 0.4

# --- Camera (§9: shake only on impacts, by weight) ----------------------------

## Shake trauma (0..1; [CameraRig] squares it into the offset): fail.
const SHAKE_FAIL: float = 0.6
## Shake trauma: the shield took a hit.
const SHAKE_SHIELD: float = 0.35
## Shake trauma: a Zen-mode bump, Zen's stand-in for a hit.
const SHAKE_ZEN_BUMP: float = 0.15
## Shake trauma: glass shattered (small).
const SHAKE_SHATTER: float = 0.12
## Shake trauma: landing after a launch pad (smallest).
const SHAKE_LAND: float = 0.08
## Lateral lean impulse (world units) of a hop or a current: the camera follows
## the sideways motion.
const HOP_LEAN: float = 0.15
## FOV kicks (degrees) meaning speed: a dash, and a surge into the heavy state.
const FOV_PUNCH_DASH: float = 4.0
const FOV_PUNCH_HEAVY: float = 3.0
## Reduce motion: shake, lean and FOV kicks at 20 % of the above.
const REDUCED_CAMERA_MOTION: float = 0.2

# --- Core motion (§8: elastic, anticipation then stretch) ---------------------

## Uniform scale kicks ([method CoreView.punch]); positive swells the core.
## Collecting: a spark is a tick, a prism (a reward) a clear swell.
const PUNCH_SPARK: float = 0.08
const PUNCH_PRISM: float = 0.2
## Picking up a shield or magnet.
const PUNCH_PICKUP: float = 0.25
## Loading a mass plate.
const PUNCH_PLATE: float = 0.15
## A full plate stack crashing through.
const PUNCH_STACK_CRASH: float = 0.3
## Negative kicks shrink the core: a refused dash (a "no") and a Zen bump.
const PUNCH_DENIED: float = -0.12
const PUNCH_ZEN_BUMP: float = -0.2
## Directional squash ([method CoreView.squash]); positive stretches along the
## axis, negative flattens. A dash stretches along the track.
const SQUASH_DASH: float = 0.45
## Surge: heavy flattens on the vertical axis, light stretches up.
const SQUASH_SURGE_HEAVY: float = -0.3
const SQUASH_SURGE_LIGHT: float = 0.25
## Launch pad: stretched upward on take-off, flattened on landing.
const SQUASH_LAUNCH: float = 0.4
const SQUASH_LAND: float = -0.35

# --- Bursts (§9) --------------------------------------------------------------

## Fail: the burst follows the core's implosion (60 ms).
const FAIL_BURST_DELAY: float = CoreView.IMPLODE_TIME
## Glass debris starts a little above the hazard's centre line.
const SHATTER_BURST_LIFT: Vector3 = Vector3(0, 0.1, 0)
## Perfect motes rise just ahead of the core, into the camera's view.
const PERFECT_BURST_OFFSET: Vector3 = Vector3(0, 0.2, -0.6)

# --- Post effects (post_fx.gdshader; strengths 0..1, decays per second) -------

## Chromatic split: the fail impact only (§9), fading out fast.
const FAIL_CHROMA: float = 0.8
const CHROMA_DECAY: float = 3.0
## Edge tint: fail (red), perfect (gold), entering a gravity well (surge colour).
const FAIL_EDGE_TINT: float = 0.55
const PERFECT_EDGE_TINT: float = 0.25
const GRAVITY_EDGE_TINT: float = 0.18
const TINT_DECAY: float = 1.6
## Distortion ring for a state change: perfect, form change, overdrive start.
const SHOCK_PERFECT: float = 0.6
const SHOCK_FORM_CHANGE: float = 0.35
const SHOCK_OVERDRIVE: float = 0.45
const SHOCK_DECAY: float = 2.2
## How fast the distortion ring's radius grows (shader units per second).
const SHOCK_EXPAND: float = 1.5
## An effect cosmetic's "shockwave" multiplier is clamped to 0..this.
const SHOCK_STYLE_MAX: float = 2.0
## Reduce motion halves the distortion ring.
const REDUCED_SHOCKWAVE: float = 0.5
## Below this every post effect is spent and the full-screen pass is skipped.
const POST_EPSILON: float = 0.01

# --- Trail and beat -----------------------------------------------------------

## Trail width: base, extra at full combo glow, extra in overdrive (§9:
## overdrive thickens the trail).
const TRAIL_WIDTH: float = 0.12
const TRAIL_COMBO_WIDTH: float = 0.06
const TRAIL_OVERDRIVE_WIDTH: float = 0.05
## The floor's music-beat pulse fades at this rate per second.
const BEAT_PULSE_DECAY: float = 3.0

# --- Feedback (audio level and haptic intensity, 0..1) ------------------------

## Strength sent with each [signal GameplayView.feedback] kind: audio plays the
## cue at this level and haptics vibrate at it. Impacts and the run's end are
## strongest, information cues (collect, miss) faintest. For &"combo" the entry
## is the floor of [method combo_strength].
const FEEDBACK_STRENGTH: Dictionary[StringName, float] = {
	# Taps (feedback).
	&"tap": 0.4,
	&"phase": 0.5,
	&"dash": 0.6,
	&"surge": 0.5,
	&"denied": 0.2,
	# Information, skill rewards, pickups and course forces.
	&"collect": 0.3,
	&"prism": 0.3,
	&"miss": 0.2,
	&"near_miss": 0.5,
	&"combo": 0.3,
	&"gate": 0.4,
	&"current": 0.4,
	&"gravity": 0.4,
	&"pickup": 0.5,
	&"plate": 0.4,
	&"launch": 0.6,
	&"land": 0.4,
	&"portal": 0.6,
	# State changes.
	&"form": 0.7,
	&"overdrive": 0.9,
	&"overdrive_end": 0.3,
	# Impacts.
	&"shatter": 0.6,
	&"chain": 0.6,
	&"bump": 0.3,
	&"shield_break": 0.8,
	&"stack_crash": 0.8,
	&"fail": 1.0,
	# The run's end.
	&"complete": 1.0,
	&"perfect": 1.0,
}
## Strength of a kind missing from [constant FEEDBACK_STRENGTH]: a middling
## cue, heard but never a full impact (every kind the view emits is listed).
const DEFAULT_FEEDBACK_STRENGTH: float = 0.5
## The combo-step cue reaches full strength at this combo.
const COMBO_FEEDBACK_FULL: float = 30.0


## Feedback strength of [param kind] ([constant DEFAULT_FEEDBACK_STRENGTH] for
## an unlisted kind).
static func strength(kind: StringName) -> float:
	return float(FEEDBACK_STRENGTH.get(kind, DEFAULT_FEEDBACK_STRENGTH))


## Strength of the combo-step cue at [param combo]: grows with the combo from
## the &"combo" entry up to 1.0 at [constant COMBO_FEEDBACK_FULL].
static func combo_strength(combo: int) -> float:
	return clampf(float(combo) / COMBO_FEEDBACK_FULL, strength(&"combo"), 1.0)
