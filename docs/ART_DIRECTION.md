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
* **Glow/bloom:** HDR threshold ≥ 1.0. Only energy exceeds it. Tonemapper: AgX (Mobile) / ACES
  (Compatibility).
* No lens flares, no volumetric fog, no motion blur. Fog is distance-only, for depth.
* **Light shafts:** in worlds with open light (Crystal Valley, Deep Ocean, Cyber Garden, Desert Reactor)
  four faint beams of the key light colour lean through the far shaft at 6 % opacity (within the 8 %
  atmosphere cap), Medium and above; they are the volumetric look without volumetric fog.

## 7. Environment layering

* **Foreground:** floor panels and lane grooves (orientation and speed read).
* **Midground:** ribs every 7 u (rhythm, speed and depth via parallax), and one kind of wall detail
  between them per world (`art.detail`: conduits, pipes, panels, crystals or sagging cables), outside
  the rib pillars so the lanes stay clear.
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
