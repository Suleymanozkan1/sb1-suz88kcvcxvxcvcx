# FLUX DROP — Art Direction

This document governs every visual, motion and audio decision in the game. Any asset, effect, screen or
sound that breaks a rule here gets redesigned. Code implements these rules in
`game/src/art/` (palette, materials, motion curves) and the UI design system in `game/src/ui/kit/`.

## 1. Concept: "instrument-grade calm"

The shaft is a precise, physical apparatus: architectural, matte, quiet. The **energy core** is the only
thing truly alive in it. The player's eye should always land on the core first, the next hazard second,
and never on the scenery.

**Rule zero: only energy glows. Matter never glows.**

| Energy (may emit and bloom) | Matter (lit only; never emissive) |
|---|---|
| Core, its trail, sparks, prisms, phase membranes, portal membranes, the far "flux sink" | Barriers, sliders, shutters, breakable glass, frames/ribs, floor, gate arches |

Small *functional* indicator lights on matter (for example a shutter's "closing" lamp) are allowed, because
they carry gameplay information. Decoration never glows.

## 2. Visual priority (enforced by value, saturation and motion)

1. **Player** (core): highest value, the only strong bloom, always in motion.
2. **Immediate hazard**: WARNING hue, strong silhouette, mid-high value, matte-satin finish.
3. **Objective**: HUD objective chip; collectibles that form the path.
4. **Interaction**: gates and pickups, each with a unique silhouette.
5. **Score / combo**: top-centre HUD, quiet until it changes.
6. **Environment**: low saturation, mid-low value, no emission.
7. **Decoration**: almost none. Every detail must answer "what does this communicate?".

## 3. Colour system

Gameplay colour roles are **global** and identical in every world, so players learn them once.
Worlds change only environment colours, light and materials.

| Role | Hex | Used for |
|---|---|---|
| PRIMARY | `#46E6F0` | Core default energy, phase A, primary UI action |
| SECONDARY | `#F0468C` | Phase B energy, secondary emphasis |
| ACCENT | `#F5C451` | Rewards: prisms, stars, coins, best scores |
| WARNING | `#FF6A3D` | Every hazard body; danger cues |
| SUCCESS | `#5BE3A1` | Shield, cleared states, positive confirmation |
| FAILURE | `#E5484D` | Fail state, damage, destructive actions |
| Ink / Graphite / Slate | `#0B0E14` / `#1A1F29` / `#2A3140` | UI surfaces, environment darks |
| Fog / Bone | `#8A93A6` / `#E8ECF2` | Secondary text / primary text |

Environment palettes stay within saturation ≤ 0.45 and value ≤ 0.55 (sky, fog, floor and lanes), so
gameplay colours always win. `WorldTheme.quiet()` enforces this on load; high-key worlds (sky
luminance > 0.5, e.g. Cloud Factory) keep their light values and rely on the core's ink shell for
contrast, but stay within the saturation cap. Each world defines `sky_top`, `sky_bottom`, `fog`, `floor`, `structure`,
`key_light`, `sink` and a **story accent** (one hue, used only in the far background).

## 4. Shape language

* **Core family:** circle-derived primitives that tell the form at a glance. ORB = sphere, PRISM =
  octahedron, COMET = capsule along the motion axis, SURGE = sphere inside a ring. The silhouette, not
  the colour, communicates the tap meaning.
* **Collectibles:** spark = small octahedral shard (always the same silhouette); prism = larger shard
  with an orbiting ring (the "premium" version of the same family).
* **Obstacles:** chamfered blocks. Every hazard uses the same, bolder chamfer ratio (16 % of the
  shortest edge, `ViewKit.HAZARD_CHAMFER`; structure, posts and ribs use 8 %, `MeshFactory.CHAMFER_RATIO`)
  and the same height (0.9 u). Variation comes from what they do: a *barrier* is a solid block; a
  *slider* is a block on a visible floor track whose length shows its range; a *shutter* (pulse gate)
  is a panel that physically drops into the floor when open; a *breakable* is the same block in glass
  with fracture lines.
* **Gates:** a chamfered arch spanning all lanes; the membrane inside is energy.
* **Mass & gravity:** a *launch pad* is a matte slab in the structure material with a PRIMARY chevron
  insert pointing down the track (a force, like a current); a *plate* is matte ballast (heavy-surge
  violet, darkened, metallic) with a thin energy ring because it is collected, and stacks as discs on
  the core; a *gravity well* is a chevron strip across the lanes between two matte rails: heavy-surge
  colour with arrows rushing forward for high gravity, light-surge colour drifting back for low gravity
  (direction is the second cue for colour-blind players). A launched core is drawn at its height with
  a soft ground shadow that shrinks as it rises.
* **Environment:** repeating ribs (frames) on a 7 u rhythm, built from the same chamfered profile.
  Each world picks one rib profile (gate, arch, hex, monolith pair, lattice) and one material.

Proportions: lane width 1.6 u, block width 1.16 u, block height 0.9 u, core radius 0.3 u, spark
height 0.32 u. Everything is measured against the core.

## 5. Material language (stylised PBR, physically consistent)

| Material | Albedo value | Roughness | Metallic | Specular | Emission | Notes |
|---|---|---|---|---|---|---|
| Anodised metal (ribs) | 0.18–0.30 | 0.42 | 0.85 | 0.5 | 0 | Clear key-light highlights |
| Satin hazard paint | WARNING | 0.55 | 0.0 | 0.5 | 0 | Bevel catches light, giving a crisp silhouette |
| Ceramic / porcelain | 0.75–0.9 | 0.3 | 0.0 | 0.6 | 0 | High-key world (Cloud Factory) |
| Stone / sandstone | 0.35–0.55 | 0.85 | 0.0 | 0.3 | 0 | Desert, Crystal Valley rock |
| Glass (breakables) | tint 0.6 | 0.08 | 0.0 | 0.7 | 0 | Fresnel-strong; fracture lines are darker, never glowing |
| Ice | 0.7 | 0.18 | 0.0 | 0.6 | 0 | Subsurface-ish lift via wrap lighting |
| Floor panels | 0.08–0.18 | 0.8 | 0.2 | 0.4 | 0 | Seams are recessed (darker), never lit lines |
| Energy | colour | — | — | — | 1.5–3.0 HDR | Only energy may exceed 1.0 and bloom |

There are no image textures for surfaces. Detail comes from geometry (chamfers, grooves) and from a few
authored procedural masks (panel seams, fracture lines, facets) whose scale is tied to world units, so
nothing stretches or tiles visibly.

## 6. Lighting language

* **Key:** one directional light per world (colour and angle from world data); shadows on Medium and
  above.
* **Fill:** ambient colour at 25–40 % of the key.
* **Rim / local:** the core's own point light. Hazards near the core light up, which is gameplay
  information: you see what is close to you.
* **Background:** the "flux sink" glow on the horizon is the only large light shape. It gives the run a
  direction.
* **Glow/bloom:** HDR threshold ≥ 1.0. Only energy exceeds it. Tonemapper: AgX (Mobile) / ACES
  (Compatibility).
* No lens flares, no volumetric fog, no motion blur. Fog is distance-only, for depth.

## 7. Environment layering

* **Foreground:** floor panels and lane grooves (orientation and speed read).
* **Midground:** ribs every 7 u (rhythm, speed and depth via parallax).
* **Background:** the sky gradient and sink, plus one world "story" silhouette far away (for example
  The Turbine's rotor for Neon Core's boss, a crystal ridge, foundry chimneys), drawn in fog colour.
* **Atmosphere particles:** at most 24 on screen, at most 8 % opacity, with a reason (dust in the key
  light, rising embers, bubbles). Never "particle rain".

## 8. Motion language

| Class | Character | Recipe |
|---|---|---|
| Player | Elastic, alive | Anticipation squash 40 ms → stretch along the motion → settle with one overshoot |
| Collectible | Light, quick | Idle bob 0.06 u; pop: scale 1→1.25→0 in 120 ms; never squash |
| Obstacle | Heavy, mechanical | Linear or ease-in-out only; shutters drop with a short settle; no overshoot |
| Button | Tactile | Press: scale 0.96 in 60 ms; release: 1.02 overshoot, settle in 140 ms |
| Reward | Celebratory but brief | Count-up ease-out; stars land 120 ms apart with overshoot; one chime each |
| Transition | Calm | 180–240 ms slide of 24 px plus fade, ease-out cubic; never bounce |

## 9. VFX rules (each effect has one job)

| Event | Job | Effect budget |
|---|---|---|
| Tap | feedback | Flat floor ripple ring under the core (180 ms, form colour; grey when a dash is refused) and a 1.03 score nudge; no shake |
| Collect | information | 6 shard motes + 120 ms ring; no shake |
| Near miss | information / skill reward | Thin streak on the hazard edge; slow-motion only at combo ≥ 10 (80 ms × 0.75) |
| Shatter | impact | 10–14 glass shards with gravity, 30 ms hit-stop, small shake |
| Shield hit | impact | Shield ring fragments (SUCCESS), 60 ms hit-stop, medium shake |
| Fail | impact | Core implodes 60 ms then bursts (≤ 28 motes), 90 ms hit-stop, FAILURE vignette; the only chromatic split |
| Form change | state change | Core morph, gate membrane ripple, short distortion ring |
| Combo step | progression | Thin ring around the core plus HUD multiplier punch |
| Overdrive | state change | Trail thickens; brief distortion ring |
| Complete / Perfect | reward | Slow-down, core dives into the sink; Perfect adds a gold ring sweep and ≤ 30 rising motes |

The camera shakes only on impacts: fail (0.6 trauma), shield hit (0.35), a Zen-mode bump (0.15, Zen's
stand-in for a hit), a shatter (0.12, small) and a landing after a launch pad (0.08, smallest). Collecting, near misses and taps never shake. Hops get a
0.15 u lean, and dash or heavy surge get a small FOV kick (meaning: speed). Reduce motion scales all of
it to 20 %.

## 10. UI design system

* **Grid:** 8 px unit on a 720 × 1280 reference; 32 px outer margins; 16 px gutters; safe-area aware.
* **Typography:** one family, Outfit (OFL), in three weights.

| Style | Size / weight | Use |
|---|---|---|
| H1 | 64 / 800, tracking −1 | Screen titles (rare) |
| H2 | 40 / 800 | Section titles |
| H3 | 28 / 600 | Card titles |
| Body | 24 / 400 | Descriptions |
| Caption | 18 / 600, upper-case, +2 tracking | Labels, stats |
| Score | 72 / 800 | HUD score |
| Button | 26 / 800, upper-case, +1.5 tracking | Button labels |
| Reward | 44 / 800, ACCENT | Reward amounts |

* **Surfaces:** flat Graphite panels with a 1 px Slate hairline and a 4 px corner radius. No gradients,
  no glass blur, no glow.
* **Buttons:**
  * **Primary:** solid PRIMARY with Ink label, 96 px tall. One per screen.
  * **Secondary:** 2 px Bone-40 % outline.
  * **Tertiary:** text only.
  * **Icon button:** 88 px hit area, 28 px glyph. Every interactive control is at least 88 px
    (about 48 pt / dp on a phone, since the 720 px canvas spans the screen width).
  * **Destructive:** FAILURE outline.
* **Icons:** one system drawn in code (`IconGlyph`). 24-unit grid, 2-unit stroke, round caps and joins,
  no fills except status dots. No emoji, 3D, flat-mixed or raster icons.

## 11. Audio language

One synthesised palette shared by all sound effects and music:
* soft sine/triangle bodies with short filtered-noise transients;
* the pentatonic or modal scale of the current world for all pitched feedback, so collects play *in key*
  with the music;
* no stock samples, no harsh square leads.

Music is two stems (base plus intensity) so that combo raises the energy without new themes.

## 12. Asset gate (every new asset)

Before it ships, an asset must pass all of these:

* consistent style
* correct scale
* correct perspective
* correct material
* correct lighting
* sensible topology
* no visible repetition
* no artefacts or weird geometry
* unambiguous meaning
* acceptable mobile cost

If any check fails, the asset is redesigned. Procedural generation is constrained by this document
(palette, proportions, rhythm, shape family). Random variation is never a goal in itself.

The per-asset record of this gate is `docs/ASSET_GATE.md`, rendered from `game/data/art/asset_gate.json` by
`tools/report/asset_gate.py` (CI fails when an asset file is not covered).

## 13. Detail audit

Rule (§2 item 7, REQ-325): every detail answers "what is this communicating?"; otherwise it is removed. The
tables below list every visual element on screen in gameplay and in the UI, read from the code that draws it
(`game/src/gameplay/view/`, `game/src/vfx/`, `game/src/ui/screens/`, `game/src/ui/components/`,
`game/src/app/game_flow.gd`). "Kept" means the element has a job; "kept, open" means it has a job but the audit
found a gap, listed in 13.11. Elements removed during the polish passes are in 13.10.

### 13.1 Player (core)

| Element | Where | Communicates | Kept / removed |
|---|---|---|---|
| Core body: ORB sphere, PRISM shard, COMET capsule, SURGE sphere | `core_view.gd` | Where the player is and what a tap does now (the form, by silhouette) | Kept |
| Core colour and shader style | `core.gdshader` | HOP: the equipped skin; PHASE / DASH / SURGE: the form or phase colour (gameplay meaning) | Kept, open (style 3 body ignores the form colour) |
| SURGE ring | `core_view.gd` `ring` | The SURGE form (sphere-in-ring silhouette) | Kept |
| Ink shell | `ink_shell.gdshader` | Separates the core from the light floor of high-key worlds | Kept |
| Halo | `glow_sprite.gdshader` | Core position; grows with the combo | Kept |
| Core point light | `core_view.gd` `light` | Proximity: hazards near the core light up (§6) | Kept |
| Shield ring on the core | `core_view.gd` `shield_ring` | A shield is active (one hit absorbed) | Kept |
| Hop direction chevron | `core_view.gd` `chevron` | Which way the next hop goes (3+ lanes) | Kept |
| Orbiting charge shards (up to 8) | `core_view.gd` `shards` | Charges collected towards overdrive | Kept |
| Plate stack discs (up to 3) | `core_view.gd` `stack_discs` | Plates carried; a full stack breaks glass | Kept |
| Ground shadow under the core | `gameplay_view.gd` `_make_core_shadow` | Height of a launched core | Kept |
| Squash, stretch, spin, implode | `core_view.gd` | Tap accepted, the form's motion, the fail moment (§8) | Kept |
| Trail ribbon | `trail_ribbon.gd`, `trail.gdshader` | Speed and direction; in PHASE / DASH / SURGE its colour is the form colour | Kept, open (rainbow style) |
| Tap ripple | `tap_ripple.gd`, `ripple.gdshader` | Tap accepted (form colour) or refused dash (grey) | Kept |

### 13.2 Collectibles and pickups

| Element | Where | Communicates | Kept / removed |
|---|---|---|---|
| Sparks (shards) | `spark_field.gd` | The path and score; a phase-coloured spark needs that phase | Kept |
| Prisms (larger ACCENT shard) | `spark_field.gd` | A premium reward | Kept, open (§4 ring not drawn) |
| Colour-blind tilt of phase-B sparks | `spark_field.gd` `TILTED` | Phase B by shape (setting) | Kept |
| Collect pop (1 → 1.25 → 0 in 120 ms) | `spark_field.gd` | Collected | Kept |
| Magnet pull of sparks | `spark_field.gd` `apply_magnet` | Which sparks the magnet will collect (only those) | Kept |
| Shield pickup (hexagonal ring) | `entity_view.gd`, `view_kit.gd` | Protection power-up | Kept |
| Magnet pickup (striped capsule) | `entity_view.gd`, `view_kit.gd` | Attraction power-up | Kept |
| Mass plate (ballast tile + energy ring) | `entity_view.gd`, `view_kit.gd` | Weight you collect and carry | Kept |

### 13.3 Hazards

| Element | Where | Communicates | Kept / removed |
|---|---|---|---|
| Barrier block | `entity_view.gd` | Solid: do not touch | Kept |
| Slider block and its floor track | `entity_view.gd`, `view_kit.gd` `track_mesh` | A moving hazard and its full range | Kept |
| Pulse-gate shutter, posts, floor slot | `entity_view.gd` `_animate_shutter` | Timed gate: open when dropped, shut when raised | Kept |
| Pulse-gate lamps | `entity_view.gd` | Closing soon / closed (the one functional light on matter, §1) | Kept |
| Breakable glass block with cracks | `glass.gdshader` | Breakable by a dash or a full plate stack | Kept |
| Contact shadows (blobs) | `view_kit.gd` `blob_mesh` | Grounds each object in its lane | Kept |
| Appear rise out of the floor | `entity_view.gd` `animate` | A new object entering the view (mechanical, no overshoot) | Kept |

### 13.4 Gates, forces and the finish

| Element | Where | Communicates | Kept / removed |
|---|---|---|---|
| Phase gate: arch + membrane | `entity_view.gd`, `membrane.gdshader` | A phase rule; the membrane colour is the phase you must be in | Kept |
| Colour-blind phase marker (ring / diamond) | `view_kit.gd` `phase_marker_mesh` | Phase A or B by shape (setting) | Kept |
| Form gate: arch + membrane + spinning form icon | `entity_view.gd` | The tap meaning switches to this form | Kept |
| Membrane ripple and dissolve | `entity_view.gd` | The gate was used / is done | Kept |
| Portal ring, entry disc, exit floor disc | `entity_view.gd` | Teleport: where you enter and the lane you come out in | Kept |
| Current chevron strip | `chevron.gdshader` | A sideways push and its direction | Kept |
| Launch pad slab with chevron insert | `entity_view.gd` | It throws you forward over hazards | Kept |
| Gravity well strip and two rails | `entity_view.gd` | Heavier or lighter zone (colour + arrow direction) and where it starts and ends | Kept |
| Finish arch and membrane | `gameplay_view.gd` `_finish` | The end of the level; the membrane opens at completion | Kept |

### 13.5 Environment

| Element | Where | Communicates | Kept / removed |
|---|---|---|---|
| Lane surfaces (lighter than the outer floor) | `floor.gdshader` | The playable width | Kept |
| Lane grooves | `floor.gdshader` | Lane boundaries | Kept |
| Groove lips (brighten on the beat) | `floor.gdshader` `beat` | Lane edges; the music beat (off with reduce motion) | Kept |
| Panel seams | `floor.gdshader` | Speed | Kept |
| Deep Ocean caustics (albedo only) | `floor.gdshader` | The underwater world | Kept |
| Ribs every 7 u, one profile and material per world | `mesh_factory.gd` `rib`, `gameplay_view.gd` | Speed, depth and which world you are in | Kept |
| Monolith height pattern | `gameplay_view.gd` `RIB_HEIGHT_PATTERN` | Desert Reactor's slabs (fixed rule, not random) | Kept |
| Story silhouette | `mesh_factory.gd` `silhouette` | The world's story far away (e.g. the World 1 boss turbine) | Kept |
| Turbine rotation | `gameplay_view.gd` | The boss machine is running | Kept |
| Atmosphere motes (≤ 24, ≤ 8 %) | `gameplay_view.gd` `_setup_atmosphere` | The world's air: dust in the key light, embers, bubbles, snow, sand | Kept, open (glitter, spores) |
| Sky gradient | `sky.gdshader` | The world's light and mood | Kept |
| Flux sink | `sky.gdshader` | The direction of the run | Kept |
| Sparse stars | `sky.gdshader` | Space (Void Space, or a background cosmetic) | Kept |
| Depth fog | `gameplay_view.gd` | Depth | Kept |
| Key-light shadows (high and ultra presets) | `gameplay_view.gd` | Grounds hazards and the core | Kept |

### 13.6 Feedback, camera and screen effects

| Element | Where | Communicates | Kept / removed |
|---|---|---|---|
| Collect motes (6) | `burst_pool.gd` | Spark collected | Kept |
| Prism burst (10) | `burst_pool.gd` | Prism collected | Kept |
| Near-miss / vault streak (5) | `burst_pool.gd` | A close call rewarded | Kept |
| Glass debris (12 lit boxes) | `burst_pool.gd` | Glass broken | Kept |
| Shield fragments (10) | `burst_pool.gd` | The shield is used up | Kept |
| Fail implosion and motes (≤ 28) | `core_view.gd`, `burst_pool.gd` | The run is over | Kept |
| Perfect motes (≤ 30), gold edge tint, shockwave | `gameplay_view.gd` | A perfect run | Kept |
| Combo ring, launch ring | `burst_pool.gd` `_emit_ring` | A combo step; a launch | Kept |
| Camera shake (fail, shield, shatter, Zen bump, landing) | `camera_rig.gd` | Impact, scaled by its weight (§9) | Kept |
| Camera lean (hop, current) and FOV kick (dash, heavy surge) | `camera_rig.gd` | Lateral motion; speed | Kept |
| Level-start camera sweep | `camera_rig.gd` `start_reveal` | The level begins | Kept |
| Hit-stop and slow motion | `gameplay_view.gd` | Impact weight; near miss at combo ≥ 10; the ending | Kept |
| Chromatic split | `post_fx.gdshader` | Fail impact | Kept, open (also at overdrive start) |
| Distortion ring | `post_fx.gdshader` | A state change: form change, overdrive, perfect | Kept |
| Edge tint | `post_fx.gdshader` | Fail (red), perfect (gold), entering a gravity well (surge colour) | Kept |
| World transition ink veil | `game_flow.gd` `_world_transition` | A different world begins | Kept |

### 13.7 HUD

| Element | Where | Communicates | Kept / removed |
|---|---|---|---|
| Score, top centre | `hud.gd` | The score; a 1.03 nudge per accepted tap, a 1.06 punch on points | Kept |
| Combo "×N · combo" | `hud.gd` | Multiplier and combo count; ACCENT during overdrive | Kept |
| Objective chip (target glyph, n / m) | `hud.gd` | Collect / shatter objective progress (hidden on reach-the-end levels) | Kept |
| Level progress bar (3 px) | `hud.gd` | Distance to the finish (hidden in streamed runs) | Kept |
| Shield glyph | `hud.gd` | A shield is active | Kept |
| Stack pips (3) | `hud.gd` | Plates on the core (stack levels only) | Kept |
| Pause button | `hud.gd` | Pause | Kept |
| Chapter intro hint (2.8 s) | `hud.gd` `_show_intro_hint` | Names the chapter's new mechanic on its introduction levels | Kept |
| Form hint (glyph + label, 1.6 s) | `hud.gd` | The new tap meaning after a form change | Kept |
| Tutorial tap hint (pulsing target + TAP) | `hud.gd` | When to tap, in tutorial levels | Kept |

### 13.8 Result and pause overlays

| Element | Where | Communicates | Kept / removed |
|---|---|---|---|
| Scrims (55 %, 60 %, 70 %, 93 % ink) | `ui_screen.gd` `add_scrim` | The overlay owns the screen; the run behind is paused or over | Kept |
| Complete: grade, three stars landing, score count-up, best / new best, daily rank | `complete_overlay.gd` | How well the run went | Kept |
| Complete: reward chips (coins, gems, XP) | `complete_overlay.gd` | Exactly what was granted | Kept |
| Complete: Next (primary), Double it (optional ad), Replay, Home | `complete_overlay.gd` | What to do next; inert during the sequence | Kept |
| Fail card: FAIL caption, score, best, progress bar or distance, tip | `fail_overlay.gd` | How far you got and one useful tip | Kept |
| Fail: Play again (primary), Revive (optional ad, only when available), Home | `fail_overlay.gd` | One more try first | Kept |
| Reward reveal: eyebrow, title, subtitle, cosmetic preview, reward cells | `reward_overlay.gd` | What was granted and why (level-up, achievement, mission, daily, world) | Kept |
| Pause: title, Resume, Restart, Settings, Home | `pause_overlay.gd` | One decision, no pressure | Kept |

### 13.9 Menus and the UI system

| Element | Where | Communicates | Kept / removed |
|---|---|---|---|
| Live attract run behind the main menu, 35 % ink shade | `main_menu.gd` | What the game is | Kept |
| Ink edge fades (top 34 %, bottom 46 %) | `main_menu.gd` `_edge_fade` | Keeps the wordmark and controls on ink | Kept |
| Top bar: profile emblem, level badge, XP bar, coins, gems | `main_menu.gd`, `profile_emblem.gd` | Who you are, your level and wallet | Kept |
| Wordmark and tagline | `main_menu.gd` | The game's name and promise | Kept |
| Unlock card (lock glyph, goal, n / m, meter) | `main_menu.gd` | The next unlock and how far away it is | Kept |
| Play (primary), next-level caption, Daily / Worlds / Modes, daily badge | `main_menu.gd` | The main action; today's daily is waiting | Kept |
| Tab bar (Progress, Shop, Collection, Settings) | `main_menu.gd` | The other places | Kept |
| World cards: sink-colour stripe, index, name, story or requirement, stars + meter, lock | `world_select.gd` | Which world, its progress, or exactly what unlocks it | Kept |
| Level tiles: number, three stars, boss / challenge glyph (WARNING), lock | `level_select.gd` | Level progress and the special levels | Kept |
| Mode cards: glyph, name, rule or requirement, best | `modes_screen.gd` | What each mode asks and your best | Kept |
| Daily: challenge card, reset countdown, best, personal rank, streak tier dots, bonus chest, missions | `daily_screen.gd` | Today's level, the gentle streak, optional extras and missions | Kept |
| Progress: overview, world rows, stats, achievements, leaderboard rows (your row in PRIMARY) | `progress_screen.gd` | Long-term progress; only real entries | Kept |
| Shop / Collection: currency chips, preview stage, name, rarity, "what it changes", action, tabs, swatch grid, equipped check, packs, cosmetic-only note | `cosmetics_screen.gd`, `cosmetic_swatch.gd` | What an item is, what it changes and what it costs, before buying | Kept, open (core-skin swatch) |
| Settings rows: glyph, label, toggle / slider / segments; restore, version, licences | `settings_screen.gd` | One setting per row | Kept |
| Buttons in five roles (one primary per screen) | `ui_button.gd`, `ui_theme.gd` | Action priority | Kept |
| Cards (flat Graphite, Slate hairline; raised; selected with a PRIMARY border) | `ui_theme.gd` | Grouping; the selected item | Kept |
| Toggles, segmented controls, sliders, focus rings | `ui_toggle.gd`, `ui_segmented.gd`, `ui_theme.gd` | State and keyboard / controller focus | Kept |
| Toasts (one at a time, 2.4 s) | `toast_view.gd` | Transient status: save recovered, offline, locked | Kept |
| Stroke icons (IconGlyph, 42 glyphs) | `icon_glyph.gd` | The meaning of an action or value | Kept |
| Screen transitions (24 px slide + fade) | `ui_screen.gd` | Navigation; calm (§8) | Kept |

### 13.10 Removed during polish

| Removed | Why it went | Commit | Where it is checkable now |
|---|---|---|---|
| Finish membrane lit behind the result screen (the result backdrop) | It said nothing once the run was over and competed with the result card | `26c2427` | `gameplay_view.gd` `_finish_open`: the membrane opens and dissolves at completion |
| Attract-run structure crossing the menu wordmark (the title band) | Scenery crossing text (visual priority: UI over decoration) | `26c2427` | `main_menu.gd` `_edge_fade(true, 0.34, 0.6)` holds 86 % ink over the title |
| App icon gradients (three gradient fills) and its 18 % glow halo | Meaningless gradients and glow | `26c2427` | `game/assets/icons/app_icon.svg`: flat palette shapes only |
| Emissive Deep Ocean floor caustics | Matter must not glow (§1) | `4d3eb5f` | `floor.gdshader`: caustics mixed into albedo, no EMISSION |
| Atmosphere above 8 % opacity (alphas 0.12-0.5) | Above the §7 cap; read as particle rain | `055562e` | `gameplay_view.gd` `ATMOSPHERE_MAX_ALPHA` |
| Bursts above their §9 budget on ultra (fail 35, perfect 37) | Over budget | `055562e` | `burst_pool.gd` `set_amount_scale` never scales above the budget |
| Live 3D core preview in the shop (SubViewport + CoreView) | Its colour-space conversion showed colours that differ from the item | `25f2423` | `cosmetics_screen.gd` `_build_preview` (flat swatch) |
| HUD visible under the result cards | Two layers saying the same thing | `25f2423` | `game_flow.gd` (the HUD steps away under the result card) |
| Level-up reveal over the fail card's PLAY AGAIN | Covered the main action | `26c2427` | `test_app_flow.gd::test_fail_card_stays_clear_and_music_follows_the_run` |
| Rib shadows | Thin ribs made noisy, wavering shadow lines that read as render artefacts | `53e1a0f` | `gameplay_view.gd` (ribs `SHADOW_CASTING_SETTING_OFF`) |
| Long trail aimed at the lens | A beam into the camera, not a speed cue | `53e1a0f` | `trail_ribbon.gd` `max_length` 1.6 u and the near-camera fade |

### 13.11 Open points found by this audit

These elements have a job, but the audit found a gap. Each is also a `pass_with_note` in `docs/ASSET_GATE.md`.

* Core style 3 (void) never reads `color_a`, so in PHASE / DASH / SURGE the core body does not show the form
  colour (the halo, light and trail still do).
* Trail style 4 (rainbow) replaces the trail colour in every form, hiding the form colour that the other styles keep.
* §4 describes prisms with an orbiting ring; the build draws a larger ACCENT shard without a ring.
* World data asks for `glitter` (Crystal Valley) and `spores` (Cyber Garden) atmospheres; `_setup_atmosphere`
  has no branch for them, so both draw the default dust.
* The chromatic split also fires at overdrive start (`gameplay_view.gd`), while §9 names fail as the only one.
* The sky is screen-locked (`SCREEN_UV`): camera lean and shake move the world but not the sink.
* The shop's core-skin swatch draws every style as the same disc and rings, so the ten shader styles are not
  visible before purchase; the header comment of `cosmetics_screen.gd` still describes the removed 3D preview.
* Audio, by the same rule: `reward.wav`, `level_up.wav` and `unlock.wav` are synthesised and listed in the sound
  bank, but nothing in `game/src` plays them; they should be wired to their reveals or removed.
