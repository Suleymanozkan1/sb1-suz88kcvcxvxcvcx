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

Small *functional* indicator lights on matter (for example a shutter's "closing" lamp, an obstacle's
warning light, the runway lamps at the lane edges) are allowed, because they carry gameplay
information. Decoration never glows.

## 2. Visual priority (enforced by value, saturation and motion)

1. **Player** (the flux craft carrying the core): its energy parts and engine flames are the highest
   value and the strongest bloom; always in motion.
2. **Immediate hazard**: a strong silhouette in the world's own obstacle family, always marked by a warm
   warning light (red to orange-red) and a warm rim; the body material belongs to the world.
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
| WARNING | `#FF6A3D` | Danger cues; each world tunes its obstacle warning light inside the red to orange-red band |
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

* **Player craft (`CraftShapes`):** the player is a small flux craft with the energy core in its
  canopy, seen from behind: wings, glowing engines and their flames. Each form is its own craft, so the
  silhouette still tells the tap meaning: HOP = the Glider (rounded hull, swept wings, twin engines),
  PHASE = the Prism (a tall crystal hull with blade wings, all energy so the phase colour fills it),
  DASH = the Dart (a long needle, wings swept right back, one big engine and a long flame), SURGE = the
  Hauler (a chunky round hull inside its ring). Hull: ceramic paint tinted by the skin or form colour
  (dark graphite in high-key worlds); trim: dark metal; energy parts (canopy, crystal, nozzles, wing
  lights) wear the core shader, so skins show there. Drawn 1.3x the core radius, with its half span
  kept under 0.6 u so the wings never seem to touch the next lane's blocks. It banks into lane
  changes, hovers, and barrel-rolls on a phase change (off with reduce motion). Curved parts (hull,
  canopy, engines, pods) are smooth-shaded; the hull paint (`craft_hull.gdshader`) carries recessed
  panel seams, a seam round the waist, a racing stripe down the spine and on the wings in the skin or
  form colour, and a faint clearcoat flake (flat paint on Low). The silhouette, not
  the colour, communicates the tap meaning.
* **Collectibles:** spark = small octahedral shard (always the same silhouette); prism = larger shard
  with an orbiting ring (the "premium" version of the same family).
* **Obstacles:** each world builds its lane blockers from its own shape family
  (`HazardShapes`, `art.hazard.style`), two shapes per world mixed along a row so a run never shows a
  wall of identical boxes: machined blocks and laser fences (Neon Core), crystal clusters (Crystal
  Valley), lava rock with glowing cracks (Molten Grid), striped industrial blocks and drum stacks
  (Cloud Factory), spiked sea mines (Deep Ocean), organic pods with pulsing veins (Cyber Garden), ice
  spikes with a warm core (Frozen Pulse), rusted barrels and crates (Desert Reactor), glyph monoliths
  (Void Space) and candy blocks and lollipops (Candy Reactor). Every shape fits the lane block
  (1.16 u wide, 0.44 u deep, at least 0.75 u tall, standing on the floor), so the silhouette never
  lies about the collision box. One cue is shared by all of them: a warm warning light (a lamp, a
  band, cracks, veins or an inner glow; red to orange-red, ≥ 25° from every role hue) and a warm
  fresnel rim that keeps dark bodies readable on dark floors. Body colours that sit near a role hue
  stay desaturated (≤ 0.35). Behaviour still tells the type: a *slider* is a sled on a visible floor
  track whose length shows its range; a *shutter* (pulse gate) is a striped panel that physically
  drops into the floor when open; a *breakable* is a glass block with fracture lines.
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
| Hazard body (per world) | world `art.hazard.body` | 0.08–0.9 | 0.0–0.55 | 0.5 | warning light only | `hazard.gdshader`: machined, crystal, lava rock, painted stripes, glyphs, ice, candy, organic; clearcoat on glassy and candy families |
| Ceramic / porcelain | 0.75–0.9 | 0.3 | 0.0 | 0.6 | 0 | High-key world (Cloud Factory) |
| Stone / sandstone | 0.35–0.55 | 0.85 | 0.0 | 0.3 | 0 | Desert, Crystal Valley rock |
| Glass (breakables) | tint 0.6 | 0.08 | 0.0 | 0.7 | 0 | Fresnel-strong; fracture lines are darker, never glowing |
| Ice | 0.7 | 0.18 | 0.0 | 0.6 | 0 | Subsurface-ish lift via wrap lighting |
| Floor panels | 0.08–0.18 | 0.8 | 0.2 | 0.4 | 0 | Seams are recessed (darker), never lit lines |
| Energy | colour | — | — | — | 1.5–3.0 HDR | Only energy may exceed 1.0 and bloom |

There are no image textures for surfaces. Detail comes from geometry (chamfers, grooves), from a few
authored procedural masks (panel seams, fracture lines, facets) and, on structure, from a procedural
relief per material (`structure.gdshader`): brushed streaks on anodised metal and steel, grain on stone
and sandstone (with wind strata), crackle glaze on ceramic, orange peel on coated metal, facets on ice
and crystal, conchoidal ripples on obsidian, none on lacquer. The relief is a height field turned into
a normal with screen-space derivatives (no textures, no tangents), a few millimetres deep, tied to
world units so nothing stretches or tiles visibly; Low quality and battery saver switch it off.

## 6. Lighting language

* **Key:** one directional light per world (colour and angle from world data); shadows on Medium and
  above (the default on phones). Hazards, pads and the core cast; ribs and wall details do not (their
  thin shadows read as cracks across the floor).
* **Reflections (High/Ultra):** one reflection probe steps along the shaft every 21 u (three ribs; the
  shaft is periodic, so it re-captures rarely); polished floors (`floor_gloss`: Crystal Valley, Deep
  Ocean, Frozen Pulse, Void Space) and metals reflect the structure. Lower presets use the sky only.
* **Fill:** ambient colour at 25–40 % of the key.
* **Rim / local:** the core's own point light. Hazards near the core light up, which is gameplay
  information: you see what is close to you.
* **Background:** the "flux sink" glow on the horizon is the only large light shape. It gives the run a
  direction.
* **Glow/bloom:** HDR threshold ≥ 1.0. Only energy and the functional warning lights exceed it.
  Tonemapper: AgX (Mobile) / ACES (Compatibility).
* **Grade:** a light global adjustment (contrast 1.08, saturation 1.12, `gameplay_view.gd`) so the
  materials do not look washed out after tonemapping; environment colours are still capped by
  `WorldTheme.quiet()` before the grade.
* **Runway lamps:** dashed lights just outside the lanes in the key-light colour (`floor.gdshader`
  `edge_light`), dimmer in high-key worlds. They mark the playable width at speed.
* No lens flares, no volumetric fog, no motion blur. Fog is distance-only, for depth.
* **Light shafts:** in worlds with open light (Crystal Valley, Deep Ocean, Cyber Garden, Desert Reactor)
  four faint beams of the key light colour lean through the far shaft at 6 % opacity (within the 20 %
  atmosphere cap), Medium and above; they are the volumetric look without volumetric fog.

## 7. Environment layering

* **Foreground:** floor panels and lane grooves (orientation and speed read).
* **Midground:** ribs every 7 u (rhythm, speed and depth via parallax), and one kind of wall detail
  between them per world (`art.detail`: conduits, pipes, panels, crystals or sagging cables), outside
  the rib pillars so the lanes stay clear.
* **Background:** the sky gradient and sink, one world "story" silhouette far away (for example
  The Turbine's rotor for Neon Core's boss, a crystal ridge, foundry chimneys), drawn in fog colour,
  and each world's own far scenery in the sky (`art.sky`, `sky.gdshader`): a skyline on the horizon
  (a city with lit windows, crystal spires, volcanoes with lava runs, chimneys with steam, a kelp reef,
  giant glowing fungi, snow-capped ice peaks, dunes with beacon pylons, floating rocks, candy hills)
  and above it nebula, clouds, aurora, light rays, a sun, moon or ringed planet and stars. Silhouettes
  use quiet environment colours; their lights stay at saturation ≤ 0.6 and below the bloom threshold.
  The sky is static (no TIME: a time-driven sky would re-bake its radiance every frame); its soft
  layers are drawn at half resolution and dropped on Low.
* **Painted backdrops:** each world can instead show a painting of its far scenery (`art.sky.backdrop`:
  image, azimuth half-width and elevation range). The sky shader maps it by view direction across the
  band of sky the camera shows above the course (about -8° to +21°; the paintings span -12° to +28°), fades its top edge into the world gradient, grades it (gain 0.9, saturation 0.9) and keeps the
  flux sink glowing over it; the mesh silhouette is hidden while it shows, and a background cosmetic
  turns it off. All ten are baked offline by `game/tools/bake_backdrop.gd` from scene shaders in
  `game/tools/backdrops/` (raymarched terrain, SDF props, volumetric clouds, far too heavy for a phone),
  so every one is original project art. Rules for a painting: the hero element (spire,
  volcano, reactor, planet, aurora) sits above the vanishing point inside the visible band; nothing in it
  looks like a hazard (Molten Grid's plain lava is crusted and dim, only the far volcano burns); and it
  stays darker and softer than the course.
* **Atmosphere particles:** up to 48 on screen (twice the world's `atmosphere.count` on High), at most
  20 % opacity, with a reason (dust in the key light, rising embers, bubbles). Never "particle rain".

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
| Speed (always, stronger on dash / surge / ramp) | speed | 24 hairline streaks in the key-light colour rush past above the blocks and beside the pillars, never over the course; 6 % opacity at the level's speed up to 20 % at 1.5×; High and Ultra only, off with reduce motion |

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
* **Start-up:** never a blank screen. The engine shows the boot splash image (splash colour, a soft
  glow, the Glider emblem seen from above and the wordmark; `assets/splash/boot_splash.png`, rendered
  from the loading screen by `tools/render_splash.gd`, square and fitted to the screen width). The
  first scene (`BootLoader`) puts the `LoadingScreen` up at once, laid out in the same square so the
  hand-over shows no jump; then the Neon Core painting rises out of the dark behind the emblem with a
  slow push-in (dimmed to 42 %, darker where text sits), speed streaks and the sink glow fade in, a thin
  PRIMARY progress bar,
  a caption status and, once the language is known, one gameplay tip. It covers the boot, the main
  scene build and the first frames' shader compilation (at least 1.2 s), then fades out in 0.4 s.
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

### 13.1 Player (flux craft and core)

| Element | Where | Communicates | Kept / removed |
|---|---|---|---|
| Craft per form: Glider, crystal Prism, needle Dart, round Hauler | `craft_shapes.gd`, `core_view.gd` | Where the player is and what a tap does now (the form, by silhouette) | Kept (replaced the orb, shard, capsule and sphere) |
| Energy parts colour and shader style (canopy core, crystal, nozzles, wing lights) | `core.gdshader` | HOP: the equipped skin; PHASE / DASH / SURGE: the form or phase colour (gameplay meaning) | Kept (colour-overriding styles yield to the form colour, `form_lock`) |
| Hull paint tint | `core_view.gd` `_apply_paint` | The skin in HOP, the form colour otherwise; dark in high-key worlds | Kept |
| Engine flames | `flame.gdshader` | Speed; a long flame in DASH and overdrive | Kept |
| Engine sparks | `core_view.gd` `ions` | Thrust; streams behind the craft (fewer on lower presets) | Kept |
| Bank, yaw, hover, phase barrel roll | `core_view.gd` `_update_flight` | A lane change in progress; a phase change (§8) | Kept |
| SURGE ring | `core_view.gd` `ring` | The SURGE form (craft-in-ring silhouette) | Kept |
| Ink shell | `ink_shell.gdshader` | Separates the core from the light floor of high-key worlds | Kept |
| Halo with a soft rayed corona | `glow_sprite.gdshader` | Player position; grows with the combo | Kept |
| Core point light | `core_view.gd` `light` | Proximity: hazards near the core light up (§6) | Kept |
| Shield ring on the core | `core_view.gd` `shield_ring` | A shield is active (one hit absorbed) | Kept |
| Hop direction chevron | `core_view.gd` `chevron` | Which way the next hop goes (3+ lanes) | Kept |
| Orbiting charge shards (up to 8) | `core_view.gd` `shards` | Charges collected towards overdrive | Kept |
| Plate stack discs (up to 3) | `core_view.gd` `stack_discs` | Plates carried; a full stack breaks glass | Kept |
| Ground shadow under the core | `gameplay_view.gd` `_make_core_shadow` | Height of a launched core | Kept |
| Squash, stretch, implode | `core_view.gd` | Tap accepted, the form's motion, the fail moment (§8) | Kept |
| Trail ribbon | `trail_ribbon.gd`, `trail.gdshader` | Speed and direction; in PHASE / DASH / SURGE its colour is the form colour | Kept (the rainbow style yields to it, `form_lock`) |
| Tap ripple | `tap_ripple.gd`, `ripple.gdshader` | Tap accepted (form colour) or refused dash (grey) | Kept |

### 13.2 Collectibles and pickups

| Element | Where | Communicates | Kept / removed |
|---|---|---|---|
| Sparks (shards) | `spark_field.gd` | The path and score; a phase-coloured spark needs that phase | Kept |
| Prisms (larger ACCENT shard with an orbit ring) | `spark_field.gd`, `MeshFactory.tilted_ring` | A premium reward | Kept |
| Colour-blind tilt of phase-B sparks | `spark_field.gd` `TILTED` | Phase B by shape (setting) | Kept |
| Collect pop (1 → 1.25 → 0 in 120 ms) | `spark_field.gd` | Collected | Kept |
| Magnet pull of sparks | `spark_field.gd` `apply_magnet` | Which sparks the magnet will collect (only those) | Kept |
| Shield pickup (hexagonal ring) | `entity_view.gd`, `view_kit.gd` | Protection power-up | Kept |
| Magnet pickup (striped capsule) | `entity_view.gd`, `view_kit.gd` | Attraction power-up | Kept |
| Mass plate (ballast tile + energy ring) | `entity_view.gd`, `view_kit.gd` | Weight you collect and carry | Kept |

### 13.3 Hazards

| Element | Where | Communicates | Kept / removed |
|---|---|---|---|
| Barrier shape (two per world, mixed along a row) | `hazard_shapes.gd`, `view_kit.gd` `barrier_mesh` | Solid: do not touch; which world you are in | Kept |
| Obstacle warning light (lamp, band, cracks, veins, inner glow) and warm rim | `hazard.gdshader`, `view_kit.gd` | Danger, the same in every world | Kept |
| Slider sled (warning strip on its front face) and its floor track | `hazard_shapes.gd` `sled`, `view_kit.gd` `track_mesh` | A moving hazard and its full range | Kept |
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
| Runway lamps outside the lanes (dashed, key-light colour) | `floor.gdshader` `edge_light` | The playable width and speed | Kept |
| Groove lips (brighten on the beat) | `floor.gdshader` `beat` | Lane edges; the music beat (off with reduce motion) | Kept |
| Panel seams | `floor.gdshader` | Speed | Kept |
| Deep Ocean caustics (albedo only) | `floor.gdshader` | The underwater world | Kept |
| Ribs every 7 u, one profile and material per world | `mesh_factory.gd` `rib`, `gameplay_view.gd` | Speed, depth and which world you are in | Kept |
| Monolith height pattern | `gameplay_view.gd` `RIB_HEIGHT_PATTERN` | Desert Reactor's slabs (fixed rule, not random) | Kept |
| Story silhouette | `mesh_factory.gd` `silhouette` | The world's story far away (e.g. the World 1 boss turbine) | Kept |
| Turbine rotation | `gameplay_view.gd` | The boss machine is running | Kept |
| Atmosphere motes (≤ 48, ≤ 20 %) | `ambient_motes.gd` `AmbientMotes.configure` | The world's air: dust in the key light, embers, bubbles, snow, sand, twinkling glitter, rising spores | Kept |
| Sky gradient | `sky.gdshader` | The world's light and mood | Kept |
| Flux sink | `sky.gdshader` | The direction of the run | Kept |
| Stars (sized, twinkle-free) | `sky.gdshader` | Night and space skies (per world, or a background cosmetic) | Kept |
| Skyline per world (city, spires, volcanoes, chimneys, reef, fungi, ice peaks, dunes, rocks, candy hills) | `sky.gdshader` `skyline` | Which world you are in, far away; depth beyond the shaft | Kept |
| Nebula, clouds, aurora, light rays | `sky.gdshader` | The world's air and light (space, sky, ice, water, sun) | Kept |
| Sun, moon or ringed planet | `sky.gdshader` `body` | Where the light comes from; the world's place | Kept |
| Depth fog | `gameplay_view.gd` | Depth | Kept |
| Key-light shadows (Medium and above, the mobile default; ribs and details do not cast) | `gameplay_view.gd` | Grounds hazards and the core | Kept |
| Surface relief per material (off on Low) | `structure.gdshader` | What the structure is made of (brushed metal, stone, ceramic crackle, ice and crystal facets, obsidian, lacquer) | Kept |
| Side details on the rib rhythm (conduits, pipes, panels, crystals, cables) | `mesh_factory.gd` `detail`, `gameplay_view.gd` | Which world you are in, and depth at the shaft walls | Kept |
| Light shafts (open-light worlds, Medium and above, ≤ 8 %) | `light_shaft.gdshader` | Where the light comes from; depth | Kept |
| Floor gloss per world | `floor.gdshader` | Ice, water and polished stone underfoot | Kept |
| Reflection probe (High and Ultra; environment layer only) | `gameplay_view.gd` | Polished surfaces reflect the shaft, never hazards or energy | Kept |

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
| Chromatic split | `post_fx.gdshader` | Fail impact (the only one; overdrive starts with a shockwave) | Kept |
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
| Shop / Collection: currency chips, preview stage, name, rarity, "what it changes", action, tabs, swatch grid, equipped check, packs, cosmetic-only note | `cosmetics_screen.gd`, `cosmetic_swatch.gd` | What an item is, what it changes and what it costs, before buying; a core skin plays its real style (`core_swatch.gdshader`) | Kept |
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
| Atmosphere above 8 % opacity (alphas 0.12-0.5) | Above the §7 cap; read as particle rain | `055562e` | `ambient_motes.gd` `AmbientMotes.MAX_ALPHA` |
| Bursts above their §9 budget on ultra (fail 35, perfect 37) | Over budget | `055562e` | `burst_pool.gd` `set_amount_scale` never scales above the budget |
| Live 3D core preview in the shop (SubViewport + CoreView) | Its colour-space conversion showed colours that differ from the item | `25f2423` | `cosmetics_screen.gd` `_build_preview` (flat swatch) |
| HUD visible under the result cards | Two layers saying the same thing | `25f2423` | `game_flow.gd` (the HUD steps away under the result card) |
| Level-up reveal over the fail card's PLAY AGAIN | Covered the main action | `26c2427` | `test_app_flow.gd::test_fail_card_stays_clear_and_music_follows_the_run` |
| Rib shadows | Thin ribs made noisy, wavering shadow lines that read as render artefacts | `53e1a0f` | `gameplay_view.gd` (ribs `SHADOW_CASTING_SETTING_OFF`) |
| Long trail aimed at the lens | A beam into the camera, not a speed cue | `53e1a0f` | `trail_ribbon.gd` `max_length` 1.6 u and the near-camera fade |

### 13.11 Open points found by this audit

These elements have a job, but the audit found a gap. The first seven were closed after the audit
(commits `3a49794` and the commit that adds `core_swatch.gdshader`), each with a test in
`tests/integration/test_view_detail_audit.gd`, `tests/unit/test_cosmetics_catalog.gd` or
`tests/integration/test_app_flow.gd`:

* ~~Core style 3 (void) never reads `color_a`~~: in PHASE / DASH / SURGE its rim and heart now take the form
  colour (`form_lock`), as does the prism style's spectrum.
* ~~Trail style 4 (rainbow) hides the form colour~~: it yields to the form colour outside HOP (`form_lock`).
* ~~§4 prisms without their ring~~: a tilted orbit ring spins round each prism (one MultiMesh, 240 triangles).
* ~~`glitter` and `spores` fall back to dust~~: Crystal Valley's glitter twinkles (alpha ramp over each
  mote's life), Cyber Garden's spores are larger and rise on a sideways drift; both ≤ 8 % opacity.
* ~~Chromatic split at overdrive start~~: removed; the fail is the only chromatic split (§9).
* ~~The shop's core-skin swatch draws every style the same~~: the swatch plays the skin's real style
  (`core_swatch.gdshader` over the shared `core_styles.gdshaderinc`, the run's own code).
* ~~`reward.wav`, `level_up.wav` and `unlock.wav` never play~~: each reveal names its cue (`level_up` for
  level-ups, `unlock` for worlds and cosmetics, `reward` otherwise) and `RevealQueue.show_next` plays it as the reveal opens.

* ~~The sky is screen-locked (`SCREEN_UV`)~~: the background is laid out from the eye direction in the
  camera's rest frame (identical at rest), so lean, shake and lane follow turn the view across it.

The round-5 review of 24 levels (2–3 per world, every new mechanic, captured at 15 %, 50 % and 85 %)
and the independent view review R-6 found and fixed:

* Passed gate arches and pulse-gate shutters crossed the camera's line to the core for over a metre of
  travel: they now sink into the floor as the core leaves them (`EntityView.arch_sink`).
* In PHASE / DASH / SURGE the core body mixed the form colour with the skin's second colour, so the
  warm-white dash core read grey-olive in Cloud Factory: outside HOP the second colour is a shade of the
  form colour.
* 8-bit banding rings in the core's floor light on glossy floors: debanding is on.
* The High-quality reflection probe mirrored hazard orange onto ice and crystal ribs: the probe captures
  only the environment layer.

None open from this audit.
