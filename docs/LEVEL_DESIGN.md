# FLUX DROP — Level Design

520 campaign levels (10 worlds × 52) plus a daily level per UTC date and seeded endless courses. All of
them come from one deterministic pipeline and are **proven** solvable and fair before they ship.

```
DifficultyModel ──► LevelSpec ──► LevelGenerator ──► level JSON ──► LevelValidator (+ AutopilotSolver)
 (curve.json,         (tier, chapter,   (builds slots around     (data/levels/wNN/   (independent re-check:
  world chapters)      params, seed)     a planned tap path,      wNN_lMM.json)       schema … solvability)
                                         measures windows by sim)
```

The same `FluxSim` (60 Hz fixed tick, no transcendental math in rules) runs gameplay, generation,
validation, the autopilot, the replay verifier and the tests, so "solvable in the validator" means
"solvable in the game" and "verifiable on the server".

## 1. Difficulty model (`game/src/levels/difficulty_model.gd`, `game/data/difficulty/curve.json`)

* **Tiers** by global level number, each with a duration band and a minimum tap window:

| Tier | Levels | Duration (s) | Min tap window |
|---|---|---|---|
| Tutorial | 1–5 | 6–14 | 420 ms |
| Early | 6–26 | 8–15 | 340 ms |
| Core Learning | 27–52 | 12–28 | 280 ms |
| Mechanic Expansion | 53–156 | 14–30 | 240 ms |
| Combination | 157–260 | 16–30 | 210 ms |
| Advanced Timing | 261–364 | 22–45 | 180 ms |
| Expert | 365–416 | 24–50 | 160 ms |
| Master | 417–468 | 26–55 | 150 ms |
| Challenge | 469–494 | 28–58 | 140 ms |
| Endgame | 495–520 | 30–60 | 130 ms |

  Specials override the band: challenge levels (L26) and bosses (L52) run 60–120 s.
* **Continuous parameters** interpolate over the campaign with a gentle exponent and a small wave:
  speed 6.5 → 12.0 m/s, slot spacing 7.2 → 4.1 m, change probability 0.35 → 0.78, hazard density
  0.70 → 1.00, spark density 0.90 → 0.60, score-target ratio 0.55 → 0.72.
* **Chapters**: every world is a sequence of 13-level chapters, each introducing one mechanic and then
  walking it through four phases — *introduction* (3 levels, wave −1, density ×0.75: a breather),
  *mastery* (4), *combination* with earlier mechanics (4: the previous chapter's hazards, forms and
  special elements come back at 30 % of their weight, `chapter_phases.combination.blend_previous`),
  *high pressure* (2, wave +1). This is the
  sawtooth: difficulty rises inside a chapter, relaxes when the next idea arrives. A new idea arrives
  every 13 levels (40 introductions: hop, shield, slider, pulse, phase, form gate, moving colours,
  3 lanes, currents, dash, chains, surge, portals, overdrive, ice, beat lock, speed ramp, …).
* The tutorial (1–5) uses fixed gentle parameters, a forgiving first hit and on-screen tap hints.
* **Teaching:** every chapter's introduction levels name the new idea in one short HUD line at the
  start (`hint.mechanic.<intro>`, EN/TR, tested for all 40 chapters).
* **Mass & gravity chapters** (W9 L14–25 launch pads, W9 L40–51 gravity wells, W10 L1–13 plates,
  W10 L27–39 all three): chapter keys `launch`, `gravity`, `plate` (chances), optional `gravity_g`
  and `gravity_slots`. Set pieces never inherit them (they opt in explicitly).
* **Set pieces.** Each world's challenge (L26) and boss (L52) names a pattern that changes how the
  level is built, not just its label:

  | Pattern | What it does |
  |---|---|
  | `rotor_gauntlet` | sliders wherever one fits, all sweeping with one shared period: the blades read as one turning machine |
  | `rhythm_gauntlet` | every pulse gate opens on the same beat, in unison with the world's boss loop |
  | `pattern_memory` | the hazard type of the first rows becomes a 4-row motif that repeats row by row |
  | `color_cascade` | colour flips on most rows (change probability ≥ 0.85) |
  | `chain_smasher` | dense breakable clusters (cluster chance ≥ 0.75), so one dash sets off chains |
  | `escape` | a speed ramp through the level |
  | `survival` | survive-to-the-end objective over a long, dense course |
  | `fast_field` | a speed bonus with a dense obstacle field |

  Every set piece still goes through the same planning, window measurement and validator.

## 2. Generator (`game/src/levels/level_generator.gd`)

The generator does not place hazards and hope; it **plans the player's path first** and builds the level
around it:

1. Start from the spec seed (`DetRng`, xorshift32) and a planned form/lane/phase state.
2. For each slot, choose the desired change (hop, colour switch, dash, weight toggle — or none) and
   place hazards that make exactly that change necessary.
3. **Measure the real tap window** by simulating every candidate tap tick with `FluxSim` from a
   checkpoint. Accept the slot only if the window is at least the tier's minimum; otherwise retry with
   different placement (bounded retries), or advance empty space.
4. Reserve reaction room after each required tap; sliders are placed adjacent only; gaps scale with the
   checkpoint speed so faster sections stay fair.
5. Place sparks along the planned path, optional prisms off it (must be fairly collectible), shields
   and magnets by tier chance.
6. Replay the whole plan from scratch on the final data; drop any spark the plan misses (so Perfect is
   always achievable); derive the score target (ratio of the plan's score) and combo target.
7. Run the independent validator on the candidate; on fairness/solvability codes retry with the next
   deterministic attempt (`MAX_ATTEMPTS = 8`).

The planned taps are stored in the level as `solution.taps`. They drive the attract mode, the tutorial
hints and the autopilot tests — and they are the generator's proof of solvability.

Mass & gravity slots are planned the same way, never assumed:

* **Launch slot** – the pad goes on the lane the plan reaches (a measured hop onto it, or the lane the
  core rides). The flight is simulated; a wall row across every lane goes in the middle of the stretch
  where the core is really above block height (≥ 1.64 m, else the slot falls back to a normal one, so
  heavy stacks and high gravity are handled by measurement). Nothing is placed under the arc, and the
  next slot waits for the landing plus the reaction room.
* **Gravity well** – spans 3–5 slots; the following slots are measured with the new gravity.
* **Plate slot** – a calm slot with the plate on the ridden lane; once three plates are carried, the
  next slot is a **crash row** (crystal on the path, crystal or blocks elsewhere).
* Levels without these chapters draw exactly the same random numbers as before (the new bands reuse
  the special-slot roll and exist only when their chance is above zero), so the other 470 levels are
  byte-identical.

Endless/time-attack courses use the same generator in streaming mode (`EndlessStreamer`): slots are
built one per frame when the core gets within 70 m of the frontier and released once safely behind it,
so entity order stays monotonic and the course depends only on the seed (the server rebuilds it to
verify replays).

## 3. Validator (`game/src/levels/level_validator.gd`)

Independent of the generator. Error codes (stable, used by CI and reports):

| Code | Checks |
|---|---|
| `schema` | required fields, types, ranges, lanes, speeds, ids |
| `missing_objective` | objective type/target present and achievable |
| `invalid_mechanic` | every entity/mechanic is known in `mechanics.json` |
| `missing_asset` | world music track exists |
| `spawn_collision` | no overlapping hazards / impossible stacks; pads on clear floor; gravity wells inside the level, never overlapping |
| `broken_trigger` | form gates, portals, currents reference valid targets; gravity factor 0.5–2 (≠ 1), span ≥ 2 m |
| `invalid_sequence` | entities ordered by distance; nothing before the safe lead-in (10 m) |
| `impossible_level` | the stored solution completes the level without damage |
| `unreachable_state` | the planned path never needs a state the core cannot reach |
| `dead_end` | currents, portals and launch flights never push the core into an unavoidable hit |
| `unfair_window` | every required tap tolerates the tier's minimum window early/late (re-simulated) |
| `duration` | duration inside the tier band (special bands for challenge/boss) |
| `solver` | optional: the independent beam-search autopilot also finds a path (warning) |

`AutopilotSolver` is a beam search over the real sim at human decision granularity (3 ticks), merging
equivalent states and keeping diversity across lane, phase, weight, speed band and distance band (the
distance band is what lets it solve surge-timing levels).

Tools:

```
godot --headless --path game -s res://tools/validate_levels.gd -- [--from=N --to=N] [--solver] [--no-assets] [--report=out.json]
godot --headless --path game -s res://tools/generate_levels.gd -- [--from=N --to=N] [--check]   # --check = regenerate and diff
```

CI runs both: all 520 levels must validate and regenerated output must equal the committed JSON.

## 4. Level file

```json
{
  "id": "w01_l05", "world": "neon_core", "number": 5, "local_index": 5,
  "kind": "normal", "tier": "tutorial", "chapter": "A", "chapter_phase": "mastery",
  "seed": 2086097298, "lanes": 2, "speed": 6.6, "length": 56.23, "duration": 8.53,
  "start_form": "hop", "modifiers": {"hop_time": 0.13, "speed_ramp": 0.0, "ramp_distance": 57.2},
  "objective": {"type": "reach_end", "target": 0},
  "score_target": 340, "combo_target": 10, "perfect_target": 18, "min_tap_window": 0.7,
  "mechanics": ["hop", "spark"], "intro_mechanic": "",
  "entities": [{"t": "barrier", "d": 18.4, "lane": 1}, {"t": "spark", "d": 20.1, "lane": 0}, "…"],
  "solution": {"taps": [64, 141, "…"]},
  "unlock": {"requires_level": "w01_l04", "requires_stars": 0},
  "generator": {"version": 1, "attempt": 0}
}
```

## 5. Designer workflow

1. Adjust `curve.json` (global feel), world chapters in `data/worlds/wNN_*.json` (which mechanic each
   chapter introduces) or `mechanics.json`.
2. `generate_levels.gd --from=… --to=…` to regenerate a range; the generator self-validates.
3. `validate_levels.gd --solver --report=…` for the full report (worst tap window, codes per level).
4. Capture a level visually: `tools/capture_level.gd -- --level=w03_l20 --at=2,6 --out=…` (needs a display).
5. Commit the JSON; CI re-checks determinism (`--check`) and fairness on every push.
