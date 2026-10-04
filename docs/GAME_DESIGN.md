# FLUX DROP — Game Design

> One tap. The core decides.

FLUX DROP is a portrait, one-input arcade game for iOS and Android. An energy core falls down a shaft
on rails; the player has exactly one input — a tap — and what that tap *does* depends on the core's
current **form**. Levels change the form mid-run through form gates, so the same thumb movement means
"hop", "switch colour", "dash" or "go heavy" depending on the moment. That is the hook: one input, four
verbs, read from the shape of the thing you control.

Everything in this document is implemented. Data lives in `game/data/`; numbers below are read from it.

## 1. Core loop

1. Tap PLAY (one primary action on the main menu; the next level is pre-selected).
2. The core spawns (0.8 s anticipation beat; tapping skips it) and falls on its own.
3. Read hazards and sparks ahead, tap at the right moment for the current form.
4. Reach the finish arch → stars land, score and rewards count up → **NEXT LEVEL** is the primary button.
5. Fail → the fail card shows how far you got and a specific tip → **PLAY AGAIN** is instant (no scene reload).

A typical early level lasts 8–15 s, late levels 30–60 s; specials (mid-world challenges and bosses) 60–120 s.

## 2. Controls and forms

| Form | Silhouette | Tap does | Teaches |
|---|---|---|---|
| **HOP** (orb) | sphere | jump to the neighbouring lane (2 lanes: toggle; 3 lanes: ping-pong with a chevron showing direction) | spacing, anticipation |
| **PHASE** (prism) | octahedron | switch colour between cyan and magenta; phase gates only let the matching colour through | colour reading |
| **DASH** (comet) | capsule | short burst: smashes breakables, chain-reacts nearby ones; cooldown | commitment, chains |
| **SURGE** (sphere-in-ring) | sphere + ring | toggle heavy / light: heavy falls faster, light slower | timing through moving hazards |

The form is always visible from **shape first, colour second** (colour-blind safe). A form change is
announced by a form gate, a morph animation, a HUD hint (`TAP = …`) and a distinct sound.

## 3. Elements (15 entity types)

`barrier`, `phase_gate`, `slider` (moves between lanes), `pulse_gate` (opens/closes on the beat),
`breakable` (dash through), `current` (forced lane shift), `portal` (teleport), `form_gate`,
`spark` (collectible, builds combo and Overdrive charge), `prism` (risk/reward collectible),
`shield` (absorbs one hit), `magnet` (pulls sparks for 4 s), and the late-game **mass & gravity** family:

* `launch_pad`: a core that crosses it in its lane is thrown into a real ballistic arc (gravity 30 u/s²,
  launch speed 10 u/s). High in the air it vaults blocks, sliders, shutters and crystals (+20, combo).
  Phase and form gates still apply, a floor current misses a flying core, pickups need a low core, and
  a tap keeps its meaning (a hop steers in the air). Landing on a block is a hit.
* `gravity` well: a stretch of the shaft where gravity is 0.7× or 1.4×. Heavier gravity speeds the fall
  (+12 %), snaps hops quicker and flattens launch arcs; lighter gravity does the opposite.
* `plate`: ballast that stacks on the core (up to 3, shown as discs on the core and pips on the HUD).
  Each plate lowers launch arcs (a full stack only clears a wall in low gravity); a full stack smashes
  the next crystal row on contact (a *stack crash*, which still sets off chains) and is spent. A shield
  hit knocks the stack off.

The three fuse into one system (stacking × physics × gravity): Void Space teaches launch pads (L14–25)
and gravity wells over pads (L40–51), Candy Reactor teaches plates (L1–13) and mixes all three
(L27–39).

Collisions: with a shield the hit consumes it (brief invulnerability); without one the run fails.
Near misses — a last-moment dodge that brings the core within 0.6 m of a hazard at any point of the
pass (about 50 ms before it would have hit) — score and build combo. Riding the next lane is never one.

## 4. Scoring, combo, grades and stars

* Sparks 10, prisms 50, near miss 25, shatter 30, chain link 15, gate pass 20, vault 20, plate 10,
  clear bonus 100.
* **Combo**: every 5 consecutive clean actions raise the multiplier by ×0.5 up to ×4.0; a missed spark or
  a hit breaks it. Collecting 8 sparks fills **Overdrive** (3 s, ×2 score, magnet, ring burst).
* **Stars**: ★ clear · ★★ score ≥ the level's score target · ★★★ Perfect (no damage and every spark).
* **Grades**: Normal / Good / Great / Perfect, from stars and the level's combo target.

The score target and combo target are generated per level from the stored solution (see
`LEVEL_DESIGN.md`), so every star is reachable and none is fake.

## 5. Structure: 10 worlds × 52 levels = 520 levels

| # | World | Mood | Challenge (L26) | Boss (L52) | Unlock |
|---|---|---|---|---|---|
| 1 | Neon Core | calibration shaft, cool and clinical | Overclock Run | The Turbine | — |
| 2 | Crystal Valley | faceted crystal ravine | Prism Storm | Prism Cascade | W1 boss + 90 ★ |
| 3 | Molten Grid | abandoned foundry, heat from below | Lava Rush | Meltdown Escape | W2 boss + 190 ★ |
| 4 | Cloud Factory | sunlit porcelain plant (only high-key world) | Conveyor Crush | Press Line | W3 boss + 300 ★ |
| 5 | Deep Ocean | pressure pylons, caustics | Riptide | Abyss Current | W4 boss + 410 ★ |
| 6 | Cyber Garden | lattice canopy, spores | Bloom Rush | Bloom Grid | W5 boss + 520 ★ |
| 7 | Frozen Pulse | glacier arches, snow | Whiteout | Glacier Metronome | W6 boss + 640 ★ |
| 8 | Desert Reactor | domes and monoliths, sand drift | Sandstorm Sprint | Reactor Core | W7 boss + 770 ★ |
| 9 | Void Space | ring station, star field | Singularity Slip | Event Horizon | W8 boss + 900 ★ |
| 10 | Candy Reactor | playful reactor, sprinkles | Sugar High | Sugar Singularity | W9 boss + 1030 ★ |

Each world has its own environment art (sky, fog, floor, structure profile, silhouette, key light,
atmosphere particles), its own procedurally synthesised music (base loop, high-intensity stem that fades in
with combo, boss loop) and its own challenge/boss identity. World unlocks need roughly 60 % of the stars
available so far, so progress is skill-based but forgiving.

Difficulty tiers across the campaign: Tutorial (1–5) → Early → Core Learning → Mechanic Expansion →
Combination → Advanced Timing → Expert → Master → Challenge → Endgame (495–520). A new mechanic is
introduced every 13 levels (introduce → master → combine → high pressure) — 40 introductions in total.

## 6. Modes

All modes run the same deterministic simulation with different rules (`data/modes/modes.json`):

| Mode | Rule | Unlock | Board |
|---|---|---|---|
| Classic | campaign levels, stars, rewards | always | all-time per mode + per level |
| Endless | seeded infinite course, weekly seed (everyone races the same course) | 10 levels | weekly |
| Time Attack | 60 s on a fast streamed course, no shields, highest score | 60 stars | weekly |
| Daily | one generated level per UTC day, same for everyone | 3 levels | daily |
| Perfect Run | any campaign level; a missed spark or a hit ends the run | 5 perfects | all-time |
| Zen | never fails, slower, no score pressure, no boards | always | — |
| Hard | any campaign level at +12 % speed, no shields | finish 2 worlds | all-time |
| Boss Rush | every beaten boss back to back, one life | beat 2 bosses | — (a summed score has no single verifiable replay) |

## 7. Progression and economy (no pay-to-win)

* **XP and player level**: XP from every run (more for stars and first clears); level-ups grant a small
  coin/gem reward and are shown as a reveal.
* **Coins** come only from play (first clears, new stars, missions, achievements, daily streak). Replays
  give a small floor so farming has no spikes. **Gems** are rare (first perfects, achievements, high
  streak tiers).
* Currency buys **cosmetics only**: 112 items in 9 categories, and every category changes something
  the player sees (the shop states it before purchase): core skins (19, ten distinct animated shader
  styles), trails (12, eight styles), bursts (9: colour and size of neutral-spark, prism and near-miss
  bursts — phase colours stay information), fail/perfect effects (9: fail flash, perfect burst,
  shockwave strength), skies (10: replace the world sky), UI themes (8: buttons, meters, panels),
  avatar frames (10), avatars (14 geometric glyphs) and badges (21, earned only) — the last three form
  the profile emblem on the menu and Progress. Default items keep the art direction's palette.
* Live tuning without a release: remote config `economy.coin_multiplier`,
  `economy.daily_reward_multiplier` and `events.weekend_coin_bonus` (UTC Saturday/Sunday) scale coin
  rewards; the server's reward-claim bounds use the same factors. Difficulty is tuned through
  `data/difficulty/curve.json` and the generator (levels are validated content, so speed is never
  changed under a shipped level at runtime).
* Optional store packs (`data/store/products.json`) contain cosmetics only; a test enforces that no
  product contains currency or gameplay items. This build ships with a null store provider, which
  says honestly that the store is unavailable.
* No energy/lives timers, no loot boxes, no gacha odds, no paid continues, no forced ads.

## 8. Daily challenge, missions, achievements

* **Daily**: one level per UTC date generated from the date seed (difficulty follows the weekday,
  Monday easiest); first completion rewards a streak tier 1–7. Missing a day lowers the tier by one step —
  it never resets to zero. The reset countdown shows the real UTC reset. The challenge can be paused
  remotely (`daily.enabled`); missions stay available and the screen says why.
* **Bonus chest**: once per UTC day on the Daily screen, fixed contents (`reward_tables.json`), offered
  only when a rewarded ad can really play; watching is never required.
* **Missions**: 3 daily + 3 weekly picked deterministically per period from 15 + 13 templates; progress
  is measured from real stats; rewards are claimed explicitly; unclaimed missions simply expire.
* **Achievements**: 82 (progress, skill, combo, collection, daily, boss, mastery, secret), each with a
  real stat target and a reward; some award badges.

## 9. Leaderboards and anti-cheat

Boards: daily, weekly per mode, all-time per mode, per level (classic); streamed courses (endless,
time attack) rank only on the weekly board of the week whose official seed built them. Offline, the game records the
player's own bests locally and queues submissions; it never shows invented players. A run is submitted
as a replay (tap ticks + level id + mode + sim version). The server verifier (`game/server/`) re-simulates
the replay with the same code and rejects score mismatches, impossible tap rates, wrong versions, stale
dailies and incomplete runs. Streamed courses are rebuilt from their seed for verification (after
cheap seed/mode/length checks). Server-side reward claims are bounded by what the content really pays,
one claim per verified run. Wallet/ledger anomalies (IntegrityMonitor) are reported once per session as
analytics and sent with submissions for review — never punished on the device. No hosted backend is
part of this build (see `game/server/README.md`).

## 10. Feel: juice with a budget

Feedback is layered by importance (see `ART_DIRECTION.md` §8–9): hit-stop and slow motion only on
meaningful events, camera shake capped, chromatic aberration only on fail and Overdrive, collect bursts
pooled. Audio: procedural SFX bank (36 sounds), combo pitch steps, music intensity stem that follows the
live combo (and drops on a break), boss loops for bosses and mid-world challenges, stingers for
complete/perfect; the floor's lane lips breathe with the music beat; the next world's music loads in the
background. The loop is locked to the run: it starts with the run's first tick (held through the READY
beat and pause), and drift past 40 ms is pulled back through the playback rate, so the beat grid the
levels are built on stays on the music. Haptics: per-event patterns with a 40 ms global floor and
per-kind rate limits; battery saver halves amplitude. Reduce Motion and Colour-blind options are in
Settings.

## 11. Tutorial (≤ 20 s)

Levels 1–5 (tutorial-flagged) teach hop with a pulsing tap hint placed exactly on the stored
solution's tap ticks. The first hit in levels 1–3 is forgiven. Every new
form is introduced by a form gate with a one-line HUD hint (`TAP = SWITCH COLOUR`).

## 12. Ethics

No dark patterns: no fake urgency (countdowns are real resets), no fake rewards (the UI animates the
exact bundle granted), interstitial ads only at natural breaks with a frequency cap and never during
the tutorial or after any purchase, rewarded ads always optional (revive, double, bonus chest),
nothing covers PLAY AGAIN after a fail, notifications opt-in
with neutral copy, analytics opt-in and free of personal data.
