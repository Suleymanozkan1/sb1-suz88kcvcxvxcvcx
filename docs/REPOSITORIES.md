# Referenced Repositories

All five repositories named in the brief were inspected on **2026-10-03** (shallow clones through
the session git proxy; README, LICENSE, directory layout, tests setup and relevant source were read).
Only the Godot engine is a runtime dependency. Nothing was copied from any repository: no code and
no assets. Patterns that inspired our own GDScript implementations are listed per repository.

| Repo | Inspected revision | Version | License | Used as | Runtime dependency? |
|---|---|---|---|---|---|
| [godotengine/godot](https://github.com/godotengine/godot) | tag `4.7.2-stable` = `ed1daf0bf001b61586d9930840f2f1394092c079` (2026-08-16) | **4.7.2-stable** (official binary `4.7.2.stable.official.ed1daf0bf`) | MIT | Game engine, export templates | **Yes** (engine) |
| [godotengine/godot-demo-projects](https://github.com/godotengine/godot-demo-projects) | `3e08537616661a5883831628decab4c526260289` (2026-09-29), tag `4.7-6ad6167` | 4.7 demos | MIT (some demo assets carry their own licenses) | API usage reference only | No |
| [pixijs/pixijs](https://github.com/pixijs/pixijs) | `5b41ee37fd36c61e089113345a8f12cf1c3323cf` (2026-10-01) | v8.22.0 | MIT | Pattern inspiration (object pool, prioritised ticker) | No |
| [phaserjs/phaser](https://github.com/phaserjs/phaser) | `02d8931b626d9764c133cbb3fbf99966c03c757c` (2026-08-21) | v4.2.1 | MIT | Pattern inspiration (scene lifecycle / state machine) | No |
| [pmndrs/zustand](https://github.com/pmndrs/zustand) | `d7a5583cffd80af515f7dfb69583c95cbdc9e2ce` (2026-09-29) | v5.0.15 | MIT | Pattern inspiration (single store, versioned persist + migrate) | No |

## 1. godotengine/godot — engine (USED)

- **Why:** mandated main engine; MIT licensed; exports to Android (APK/AAB) and iOS (Xcode project).
- **Where:** the whole `game/` project (`game/project.godot`, `config/features=["4.7","Mobile"]`).
- **Version:** 4.7.2-stable official Linux build for headless tooling/tests; matching 4.7.2 export
  templates for Android/iOS/Web.
- **License obligations:** ship the Godot MIT notice and the third-party notices from `COPYRIGHT.txt`.
  `game/src/ui/screens/settings_screen.gd` has a "Licenses" view that prints `Engine.get_license_text()`
  and `Engine.get_copyright_info()`, so these notices ship inside the game.
- **API facts verified in the 4.7.2 source (and the features they drive):**

| API | Evidence in engine source | Used by |
|---|---|---|
| `Logger` + `OS.add_logger()` | `core/core_bind.h:125`, `core/core_bind.cpp:716` | `game/src/core/error_reporter.gd` (global error capture) |
| `Input.vibrate_handheld(duration_ms, amplitude)` | `core/input/input.h:433` | `game/src/systems/haptics_service.gd` |
| `DisplayServer.get_display_safe_area()` | `servers/display/display_server.h:310` (Android/iOS only) | `game/src/ui/components/safe_area_container.gd` |
| `AudioStreamWAV` QOA import (default `compress/mode=2`); `save_to_wav` PCM only | `editor/import/resource_importer_wav.cpp:89`, `scene/resources/audio_stream_wav.cpp:532` | Generated WAVs are saved as 16-bit PCM and compressed to QOA on import |
| `rendering/rendering_device/fallback_to_opengl3` (default true) | `main/main.cpp:2398` | `game/project.godot`: low-end devices fall back to the Compatibility renderer |
| `ResourceLoader.load_threaded_request()` | `core/core_bind.h:73` | `game/src/core/async_loader.gd` |
| `MultiMeshInstance3D` | `scene/3d/multimesh_instance_3d.h` | Spark and ring rendering (draw-call batching) |
| Compatibility glow (simplified, SCREEN blend) | `drivers/gles3/effects/glow.cpp` | Glow works on both renderers. Quality presets account for this. |
| No particle trails in Compatibility | `drivers/gles3/storage/particles_storage.cpp:301` | We use our own ribbon-mesh trail (`game/src/vfx/trail_ribbon.gd`), not GPU particle trails |

## 2. godotengine/godot-demo-projects — reference only (NOT a dependency)

- **Why inspected:** idiomatic 4.7 API usage for mobile input, particles, glow, logging and threaded
  loading.
- **Demos consulted:**

| Demo | Technique |
|---|---|
| `mobile/multitouch_cubes`, `mobile/multitouch_view` | `InputEventScreenTouch` per-finger handling. Our input handler accepts only touch-down of new fingers. |
| `3d/particles`, `2d/particles` | GPU/CPU particles. We use `CPUParticles3D` bursts so behaviour matches across renderers. |
| `2d/glow`, `3d/tonemap_color_correction` | `WorldEnvironment` glow/tonemap. The HUD sits on its own CanvasLayer. |
| `3d/graphics_settings` | Runtime quality toggles. Our presets live in `game/src/systems/quality_service.gd`. |
| `misc/custom_logging` | `Logger` subclass + `OS.add_logger`, made thread-safe. |
| `loading/load_threaded` | `load_threaded_request` / `load_threaded_get`. |
| `2d/finite_state_machine` | FSM pattern. Ours is a table-driven state machine with validated transitions. |
| `misc/os_test` | `get_display_safe_area()` and `vibrate_handheld` usage. |
| `gui/multiple_resolutions` | `canvas_items` + `expand` stretch strategy for many aspect ratios. |

- **License:** MIT. Some demo assets (e.g. a smoke texture in `3d/particles/kenney/`, paintings in
  `loading/load_threaded`, a model in `3d/graphics_settings/polyhaven`) have no license file next to
  them, so **no asset was copied**.

## 3. pixijs/pixijs — inspiration only (NOT used)

- 2D WebGL/WebGPU renderer for browsers (TypeScript, npm `pixi.js`). Jest-based tests.
- **Not a dependency:** it is a JS/TS library that cannot run inside Godot's GDScript runtime or in
  native iOS/Android exports. Godot already provides rendering, the main loop and particles.
- **Pattern borrowed:** `Pool<T>` (`src/utils/pool/Pool.ts`: prepopulate / get→init / return→reset)
  became `game/src/core/node_pool.gd` (prewarm / acquire / release, with a reset hook) for obstacle
  and VFX nodes.

## 4. phaserjs/phaser — inspiration only (NOT used)

- HTML5 2D game framework (JS, Vitest tests). Scene lifecycle in `src/scene/const.js` and
  `SceneManager.js` (init → preload → create → update; pause/sleep/shutdown).
- **Not a dependency:** it is a browser framework with its own renderer and loop, and would duplicate
  Godot entirely.
- **Pattern borrowed:** an explicit lifecycle state machine with enter/exit and transition events
  became `game/src/core/game_state_machine.gd`, with a validated transition table.

## 5. pmndrs/zustand — inspiration only (NOT used)

- Minimal JS state store (`src/vanilla.ts`) with a `persist` middleware (version + migrate).
- **Not a dependency:** it is an npm/React package and GDScript cannot import it. Godot signals cover
  subscriptions.
- **Pattern borrowed:** a versioned persisted state with an explicit `migrate()` step became
  `game/src/save/save_service.gd` + `game/src/save/save_migrations.gd`.

## Development tools (not shipped)

| Tool | Version | License | Installed via | Purpose |
|---|---|---|---|---|
| Godot Engine (headless) | 4.7.2-stable | MIT | Official GitHub release binary | Import, tests, tools, export |
| gdtoolkit (`gdlint`, `gdformat`) | 4.5.0 | MIT | `pip install gdtoolkit==4.5.0` (PyPI) | GDScript lint and format in CI |
| Python 3 + NumPy | 3.11 / see `tools/requirements.txt` | PSF / BSD-3 | PyPI | Offline audio synthesis (`tools/audio/synth_bank.py`), report scripts |

## Fonts

| Asset | Source | License |
|---|---|---|
| Outfit (variable/static weights) | npm `@fontsource/outfit` (official Fontsource package) | SIL Open Font License 1.1, with the license text shipped in `game/assets/fonts/OFL.txt` |
