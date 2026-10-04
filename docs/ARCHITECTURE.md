# FLUX DROP — Architecture

Godot 4.7.2, GDScript with full static typing (untyped declarations are a project error), Mobile
renderer with the Compatibility renderer as fallback, portrait 720×1280 canvas (`canvas_items` /
`expand` stretch, safe-area aware). The Godot project is `game/`; the repository root holds docs, CI
and repo-level tools. (The repository also still contains an unrelated legacy web project at its root;
it is not part of the game and is not built.)

```
game/
  project.godot, export_presets.cfg (Android, iOS)
  scenes/main.tscn          → src/app/game_flow.gd (app root)
  src/core/                 services (composition root autoload), event bus, state machine, clock,
                            deterministic RNG, JSON IO, logging, error reporter, node pool, async loader
  src/gameplay/sim/         FluxSim — the deterministic rules (shared by everything below)
  src/gameplay/             GameplaySession (fixed-step driver, input queue, replay, hit-stop, revive)
  src/gameplay/modes/       ModeCatalog (8 modes, data-driven), EndlessStreamer
  src/gameplay/view/        GameplayView, CoreView, EntityView, SparkField, CameraRig, ViewKit, WorldTheme
  src/vfx/ src/art/         burst pool, trail ribbon; palette roles, procedural mesh factory
  src/levels/               WorldCatalog, DifficultyModel, LevelSpec, LevelGenerator, LevelValidator,
                            AutopilotSolver, LevelRepository
  src/systems/              profile, settings, localization, economy, rewards, stats, progression,
                            cosmetics, achievements, missions, daily, leaderboard, analytics,
                            remote_config, ads, store, notifications, network, audio, haptics, quality
  src/save/                 SaveService (versioned envelope, checksum, atomic writes, backup, migrations)
  src/server_shared/        ReplayVerifier (also used by game/server/verify_replay.gd)
  src/app/                  GameFlow (composition root), RunController, Presenters, RevealQueue,
                            MetaActions, MenuNavigator, ViewSync
  src/ui/                   kit (tokens, fonts, theme, buttons, icons, toggles, segmented), components,
                            screens (13), ScreenRouter
  data/                     worlds, levels (520 JSON), difficulty curve, mechanics, modes, economy,
                            rewards, cosmetics, store products, achievements, missions, daily,
                            analytics schema, remote-config defaults, ads policy, audio bank,
                            quality presets, haptic patterns, i18n (en, tr)
  assets/                   fonts (Outfit, OFL), shaders, synthesised audio, icons, LICENSES.json
  server/                   verify_replay.gd CLI + README (server-side anti-cheat entry point)
  tests/                    dependency-free runner, unit/ and integration/ suites
  tools/                    generate_levels, validate_levels, capture_level, capture_ui
tools/ci/                   placeholder_scan.py, license_check.py
tools/audio/                synth_bank.py (procedural, deterministic SFX + music)
.github/workflows/ci.yml    lint, scans, import, tests, level validation + regen diff, Android, iOS
```

## 1. Principles

* **One deterministic simulation.** `FluxSim` is a `RefCounted` with no nodes, engine time or
  transcendental math in its rules. Gameplay, generator, validator, autopilot, server verifier and tests
  all step the same code, so a level proven solvable is solvable in the game and a replay re-simulates
  identically on a server.
* **Data-driven.** Tunables live in JSON under `game/data/`, validated at load; bad data degrades to
  safe defaults with a log line, never a crash.
* **Constructor injection, no service locator in modules.** Systems are `RefCounted` classes that get
  their collaborators in `_init`. Only the app layer (GameFlow, RunController, Presenters) touches the
  `Services` autoload, which makes every system testable with in-memory doubles.
* **Facts on an event bus.** `EventBus` carries typed domain facts (`run_completed`, `currency_changed`,
  `achievement_unlocked`, …). Producers don't know consumers; the save cadence, analytics and stats
  subscribe.
* **Dumb views.** Screens receive a payload dictionary and emit intent signals. `Presenters` build
  payloads from real state; nothing on screen is invented.

## 2. Runtime composition

`AppServices` (`src/core/services.gd`, autoload `Services`) boots once:

```
EventBus, GameClock, ErrorReporter (OS logger) ─┐
WorldCatalog, LevelRepository, DifficultyModel, ModeCatalog
SaveService(FileSaveStorage) → PlayerProfile (backup/migration/recovery)
SettingsService → Localization (en/tr + parts)
EconomyService, IntegrityMonitor, ProgressionService, StatsService(+bus)
CosmeticCatalog → CosmeticService → RewardEngine(grant_xp, grant_cosmetic)
AchievementService, MissionService (reward_engine.grant_spec), DailyChallengeService (grant_table)
RemoteConfig(cache) → HttpTransport + NetworkMonitor → AnalyticsService(+file/http sinks)
LeaderboardService(local + optional http), AdsService(NullAdProvider), StoreService(NullStoreProvider),
NotificationService(NullNotificationProvider), HapticsService, AudioService(node), QualityService
```

Saves are debounced (any persisted fact marks the save dirty; flush every 1.5 s, held while a run is
being played so a save never hitches gameplay) and forced on application pause, focus loss and close.
Remote economy tuning (coin/daily multipliers, weekend event bonus) is applied to the `RewardEngine` at
boot, on every config snapshot and at each run start. `IntegrityMonitor.check()` runs after load and
after every run. Tests and tools build their own isolated graph
(`auto_boot = false`, `boot(MemorySaveStorage, fixed GameClock)`); the autoload only boots for the real
game.

## 3. App flow

`GameFlow` (main scene) owns the persistent `GameplaySession` + `GameplayView` (restart = `sim.reset()`
+ pooled entity recycle, no scene reload; 100 restarts are leak-tested), the `ScreenRouter` (one base
screen + a stack of overlays, only the top overlay visible, Android back/Escape routed to the top
screen) and the `GameStateMachine` (BOOT, MAIN_MENU, WORLD_SELECT, LEVEL_SELECT, MODES, COUNTDOWN,
PLAYING, PAUSED, FAILED, COMPLETE, REWARD, SHOP, COLLECTION, SETTINGS, DAILY, PROGRESS, ENDLESS;
illegal transitions are rejected and logged; streamed courses enter through ENDLESS). A pending
failed run (revive still on offer) is applied when the app is backgrounded or closed. Changing language
marks every built screen stale; each is rebuilt in the new language on its next show. Entering a
different world passes through a short ink veil.

The main menu shows a live attract run (the next level played by its stored solution) behind the UI.
`RunController.prepare(mode, level)` turns a request into level data + sim modifiers (campaign, daily,
endless stream, boss rush); `finish(result)` applies the result: progression, stats, exact reward
bundles, mode bests, leaderboard submission (ranked modes only, never revived runs), analytics, and
collects reveals (level-ups with their reward, world unlocks, achievements with the bundle actually
granted, cosmetic unlocks) which GameFlow shows after the result sequence.

GameFlow is the composition root, not a god object: it builds the screens and wires every intent, owns
the state machine and runs the run lifecycle (attract, start, present, restart, pause/resume, revive,
result cards), and hands everything else to focused collaborators in `src/app/`:

* `RunController` (RefCounted): run preparation and bookkeeping, including the failed run held back
  while a revive is on offer (`conclude` / `commit_pending`, applied exactly once).
* `RevealQueue` (Node child): queued reveals shown one at a time on the reward overlay with their own
  cue; returns the state machine to the state the first one covered; celebrates only on a cleared
  result and otherwise waits for the menu, never over a fail card or a revive ad.
* `MetaActions` (Node child, awaits ads/store): mission claims, the daily bonus chest, the result
  card's double reward, leaderboards, shop/collection purchases and equips, restoring purchases.
* `MenuNavigator` (RefCounted): moves between the menu screens with their payloads and states, turns
  mode and level picks into `campaign_requested` / `run_requested`, and returns Settings to the menu
  or the pause card.
* `ViewSync` (Node child): keeps the view in step with settings, worn cosmetics and the quality preset,
  pulses the track on the music's beat and lifts the ink veil between worlds.

Node children are used where a coroutine or tween must end with the app root.

## 4. Gameplay layers

* `GameplaySession` accumulates frame time into 60 Hz ticks (lockstep option for tests/capture),
  queues taps (minimum 2 ticks apart, the replay's validity rule), records the replay, applies
  presentation-only time scaling (hit-stop, slow motion) and supports one optional revive.
* `GameplayView` renders the session with interpolation: chamfered hazards from a node pool, sparks in
  one MultiMesh, ribs in one MultiMesh, procedural world silhouettes, trail ribbon, pooled bursts,
  camera spring rig, post effects driven by budgets. It emits `feedback(kind, strength, pitch_step)`
  which GameFlow fans out to audio and haptics.
* Quality presets (Low/Medium/High/Ultra + battery saver + automatic downgrade from a frame monitor)
  set render scale, MSAA and fps cap (re-applied on every automatic step), post FX, glow, ambient
  particles, particle scale, trail length, dynamic light and shadows. Reduce Motion scales camera
  shake, lean and FOV kicks; Colour-blind adds shape markers to phase gates and phase-B sparks.
* Cosmetics: skins and trails drive the core shader and ribbon; particle, effect and background items
  drive burst colours/sizes, fail/perfect colours, shockwave strength and the sky; UI themes recolour
  the shared Theme; avatar, frame and badge form the `ProfileEmblem`.
* `AsyncLoader` (threaded `ResourceLoader`) prefetches the next world's music loops from the menu and
  the level select; `SoundBank` takes the prefetched stream instead of loading on the main thread.

## 5. Persistence and integrity

`SaveService` writes an envelope `{format, version, saved_at, checksum, payload}` where the checksum is
SHA-256 over canonical JSON + salt; writes are atomic (temp + rename) and rotate a backup only when the
main file is valid. Loading tries main → backup → new profile, migrates old versions, never overwrites a
newer-version file (it is set aside), and `PlayerProfile.from_dict` sanitises every field type.
`IntegrityMonitor` detects ledger/balance anomalies for analytics without punishing the player.

## 6. Online and anti-cheat

Leaderboard submissions carry the replay. `ReplayVerifier` (shared with `game/server/verify_replay.gd`)
re-simulates with the mode's sim modifiers from `ModeCatalog` (single source of truth for client and
server), rebuilds daily levels from the date and streamed courses from their seed, and rejects score
mismatches, impossible tap rates, sim-version mismatches, wrong level kinds for the mode, stale dailies
and incomplete runs. The server CLI refuses unranked modes, unofficial weekly seeds and over-long
streams before rebuilding a course. Reward claims are bounded by the real daily-tier or level reward
(scaled like the client's remote tuning) and need one verified run each. Offline submissions are queued
(bounded, persisted) and flushed at boot, on reconnect and after any successful server answer; a 2xx
without an explicit verdict is retried, never counted as accepted. Submissions carry the
IntegrityMonitor codes for review. No hosted backend ships with this build; the HTTP backend is enabled
by a remote-config URL (host-checked: no credentials or ?/# tricks before the path).

## 7. Error handling and observability

`ErrorReporter` installs an engine `Logger` that captures script and engine errors with app context
(state, level, version), persists reports, and forwards them to analytics on next launch. Analytics is
schema-whitelisted, opt-in, enriched only with non-identifying context (session id, app version,
platform) and drops forbidden parameters. Remote config is typed, clamped and cached.

## 8. Testing and CI

`game/tests/run_tests.gd` discovers `test_*.gd` under `tests/unit` and `tests/integration`, awaits
async tests and fails a test whose body hits a script error. 730+ tests cover the sim rules and
determinism, level pipeline (generator determinism, validator detection, solver), every system module,
save corruption/recovery/migration, economy invariants, the replay verifier (genuine, tampered,
streamed), the app flow end to end (boot, first clear, failed run, daily once-only rewards, endless,
boss-rush gating, 100 restarts without node leaks, main scene boot). CI (`.github/workflows/ci.yml`)
runs gdlint, placeholder/licence scans, JSON checks, import, tests, full level validation and
regeneration diff, then Android debug and iOS project exports.
