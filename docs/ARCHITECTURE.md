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
  src/app/                  GameFlow, RunController, Presenters
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

Saves are debounced (any persisted fact marks the save dirty; flush every 1.5 s) and forced on
application pause, focus loss and close. Tests and tools build their own isolated graph
(`auto_boot = false`, `boot(MemorySaveStorage, fixed GameClock)`); the autoload only boots for the real
game.

## 3. App flow

`GameFlow` (main scene) owns the persistent `GameplaySession` + `GameplayView` (restart = `sim.reset()`
+ pooled entity recycle, no scene reload; 100 restarts are leak-tested), the `ScreenRouter` (one base
screen + a stack of overlays, only the top overlay visible, Android back/Escape routed to the top
screen) and the `GameStateMachine` (BOOT, MAIN_MENU, WORLD_SELECT, LEVEL_SELECT, MODES, COUNTDOWN,
PLAYING, PAUSED, FAILED, COMPLETE, REWARD, SHOP, COLLECTION, SETTINGS, DAILY, PROGRESS, ENDLESS;
illegal transitions are rejected and logged).

The main menu shows a live attract run (the next level played by its stored solution) behind the UI.
`RunController.prepare(mode, level)` turns a request into level data + sim modifiers (campaign, daily,
endless stream, boss rush); `finish(result)` applies the result: progression, stats, exact reward
bundles, mode bests, leaderboard submission (ranked modes only, never revived runs), analytics, and
collects reveals (level-ups with their reward, world unlocks, achievements with the bundle actually
granted, cosmetic unlocks) which GameFlow shows after the result sequence.

## 4. Gameplay layers

* `GameplaySession` accumulates frame time into 60 Hz ticks (lockstep option for tests/capture),
  queues taps (minimum 2 ticks apart, the replay's validity rule), records the replay, applies
  presentation-only time scaling (hit-stop, slow motion) and supports one optional revive.
* `GameplayView` renders the session with interpolation: chamfered hazards from a node pool, sparks in
  one MultiMesh, ribs in one MultiMesh, procedural world silhouettes, trail ribbon, pooled bursts,
  camera spring rig, post effects driven by budgets. It emits `feedback(kind, strength, pitch_step)`
  which GameFlow fans out to audio and haptics.
* Quality presets (Low/Medium/High/Ultra + battery saver + automatic downgrade from a frame monitor)
  set render scale, MSAA, post FX, particle scale, trail length, dynamic light and shadows.

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
and incomplete runs. Offline submissions are queued (bounded) and flushed on reconnect. No hosted
backend ships with this build; the HTTP backend is enabled by a remote-config URL.

## 7. Error handling and observability

`ErrorReporter` installs an engine `Logger` that captures script and engine errors with app context
(state, level, version), persists reports, and forwards them to analytics on next launch. Analytics is
schema-whitelisted, opt-in, enriched only with non-identifying context (session id, app version,
platform) and drops forbidden parameters. Remote config is typed, clamped and cached.

## 8. Testing and CI

`game/tests/run_tests.gd` discovers `test_*.gd` under `tests/unit` and `tests/integration`, awaits
async tests and fails a test whose body hits a script error. 680+ tests cover the sim rules and
determinism, level pipeline (generator determinism, validator detection, solver), every system module,
save corruption/recovery/migration, economy invariants, the replay verifier (genuine, tampered,
streamed), the app flow end to end (boot, first clear, failed run, daily once-only rewards, endless,
boss-rush gating, 100 restarts without node leaks, main scene boot). CI (`.github/workflows/ci.yml`)
runs gdlint, placeholder/licence scans, JSON checks, import, tests, full level validation and
regeneration diff, then Android debug and iOS project exports.
