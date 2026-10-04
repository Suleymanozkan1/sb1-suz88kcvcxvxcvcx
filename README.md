# FLUX DROP

**One tap. The core decides.** A portrait, one-input arcade game for iOS and Android built with
Godot 4.7.2. An energy core falls down a shaft; your single tap hops, switches colour, dashes or
changes weight depending on the core's current form. 10 worlds × 52 levels (520), eight modes, a daily
challenge, missions, achievements, cosmetics-only economy, leaderboards with server-side replay
verification, and an offline-first, corruption-safe save.

> The Godot project lives in [`game/`](game/). The repository root also contains an older, unrelated
> web project (PHP/React files such as `index.php`, `src/`, `package.json`); it is not part of the game,
> is not built by CI, and was left in place.

## Quick start

Requirements: Godot **4.7.2** (official build) on PATH as `godot`; Python 3.11 for the repo tools.

```bash
# run the game (desktop preview of the mobile build; click/space = tap)
godot --path game

# headless: import, tests, level validation
godot --headless --path game --import
godot --headless --path game -s res://tests/run_tests.gd                 # all suites
godot --headless --path game -s res://tests/run_tests.gd -- --filter=test_modes
godot --headless --path game -s res://tools/validate_levels.gd -- --report=/tmp/levels.json
godot --headless --path game -s res://tools/generate_levels.gd -- --check  # regenerate + diff

# lint and scans (pip install gdtoolkit==4.5.0)
(cd game && gdlint src tests tools server && gdformat --line-length=120 --check src tests tools server)
python3 tools/ci/placeholder_scan.py && python3 tools/ci/license_check.py
python3 tools/report/asset_gate.py --check   # every asset registered against the art direction

# screenshots (needs a display; use xvfb-run on Linux)
xvfb-run -a godot --path game --rendering-driver opengl3 --resolution 540x960 \
  -s res://tools/capture_ui.gd -- --out=/tmp/ui --progress
xvfb-run -a godot --path game --rendering-driver opengl3 --resolution 540x960 \
  -s res://tools/capture_level.gd -- --level=w03_l20 --at=2,6 --out=/tmp/shots

# regenerate the procedural audio bank (deterministic)
pip install -r tools/audio/requirements.txt && python3 tools/audio/synth_bank.py
```

## Mobile builds

`game/export_presets.cfg` defines **Android** (APK, arm64-v8a + armeabi-v7a, immersive, vibrate +
internet permissions) and **iOS** (Xcode project, arm64, iOS 14+). Data JSON is included explicitly.

* Android debug: install the 4.7.2 export templates, set the Android SDK, JDK and debug keystore in
  Editor Settings, then
  `godot --headless --path game --export-debug "Android" build/android/fluxdrop-debug.apk`.
  CI does this on every push (`.github/workflows/ci.yml`, job `android`).
* Android "unlock all" test build: the preset **Android (Unlock All)** exports the same game with the
  `unlock_all` feature tag under its own package (`com.fluxdrop.game.unlockall`, label "FLUX DROP Test"),
  so it installs beside the real game with its own save. Every level, world, mode and cosmetic is open;
  the profile keeps only real progress (`AppInfo.unlock_all_build`, `tests/unit/test_unlock_all_build.gd`).
  `godot --headless --path game --export-debug "Android (Unlock All)" build/android/fluxdrop-unlockall.apk`.
  Not for store release.
* Android release and store upload need a release keystore and Play Console account (not in the repo).
* iOS: the Xcode project exports on any OS once an App Store team ID is set
  (`--export-debug "iOS" build/ios/FluxDrop.ipa` with `application/export_project_only=true`; verified
  here on Linux: Xcode project, frameworks and a 13 MB .pck). Compiling, signing and device builds need
  macOS + Xcode, an Apple team ID and a provisioning profile; CI injects the team ID from the
  `IOS_TEAM_ID` secret and compiles an unsigned simulator build on macOS.

## Architecture in one paragraph

One deterministic simulation (`game/src/gameplay/sim/flux_sim.gd`, 60 Hz fixed tick) drives gameplay,
the level generator, the level validator, the autopilot, the server replay verifier and the tests.
A composition root (`game/src/core/services.gd`, autoload `Services`) builds every system with
constructor injection; systems talk through a typed `EventBus`. `GameFlow` (main scene) owns the
persistent session/view, a screen router and the app state machine; screens are dumb views fed by
`Presenters`. Details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Directories

```
game/                 Godot project (project.godot, export_presets.cfg)
  scenes/             main.tscn → src/app/game_flow.gd
  src/core/           composition root, event bus, state machine, clock, RNG, JSON IO, errors, pools
  src/gameplay/       sim/ (rules), session, modes/ (catalog, endless streamer), view/ (rendering)
  src/levels/         world catalog, difficulty model, generator, validator, autopilot, repository
  src/systems/        profile, settings, i18n, economy, rewards, stats, progression, cosmetics,
                      achievements, missions, daily, leaderboard, analytics, remote config, ads,
                      store, notifications, network, audio, haptics, quality
  src/save/           versioned, checksummed, atomic, backed-up persistence
  src/server_shared/  replay verifier (shared with server/)
  src/app/            GameFlow, RunController, Presenters
  src/ui/             design-system kit, components, 13 screens, router
  src/vfx/ src/art/   bursts, trail; palette roles, procedural meshes
  data/               all tunables and content as JSON (worlds, 520 levels, curve, modes, economy, …)
  assets/             fonts (OFL), shaders, generated audio, icons, LICENSES.json
  server/             verify_replay.gd CLI + README
  tests/              runner, unit/, integration/
  tools/              generate/validate levels, capture level/UI screenshots
tools/ci/             placeholder scan, licence check
tools/audio/          procedural audio synthesiser
tools/report/         requirement matrix + completion calculator
docs/                 design, architecture, art direction, requirements, reports
.github/workflows/    CI
```

## Dependencies

| Dependency | Version | Licence | Use |
|---|---|---|---|
| Godot Engine | 4.7.2-stable (official) | MIT | engine, export templates |
| Outfit font | @fontsource/outfit 5.3.0 | OFL-1.1 | UI typography |
| gdtoolkit (dev) | 4.5.0 | MIT | gdlint / gdformat |
| numpy (dev) | see tools/audio/requirements.txt | BSD-3 | audio synthesis tool |
| Python | 3.11 (dev) | PSF | CI scans, report tool |

No third-party runtime code is shipped. Reference repositories inspected (and why they were not used):
[docs/REPOSITORIES.md](docs/REPOSITORIES.md).

## Known issues and limits

* **iOS**: the Xcode project was exported here, but compiling and signing need macOS/Xcode and an Apple
  account, which this environment does not have (BLOCKED); the CI macOS job has not been observed running.
* **Release signing**: no release keystore / store accounts — only a signed *debug* APK was produced.
* **CodeRabbit**: the CLI could not be installed (network policy); substitute independent reviews are
  logged in [docs/CODERABBIT_REPORT.md](docs/CODERABBIT_REPORT.md).
* **Online services**: no hosted backend; leaderboards are local-only until `leaderboard.base_url` is
  configured, and cloud save (sync with a deterministic merge, `game/server/README.md`) stays off with an
  honest Settings label until `cloud_save.base_url` is configured. Ads, in-app purchases and push notifications use null providers that report
  "unavailable" honestly; real SDKs and accounts are needed.
* **Device testing**: no physical device was available — performance, battery, thermal and haptics were
  verified by code, headless tests and software-rendered screenshots, not on hardware.
* The repository root still contains an unrelated legacy web project (see note above).

## Documentation

| Doc | Contents |
|---|---|
| [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md) | forms, elements, scoring, worlds, modes, economy, ethics |
| [docs/LEVEL_DESIGN.md](docs/LEVEL_DESIGN.md) | difficulty model, generator, validator, solver, tools |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | modules, composition root, flow, persistence, anti-cheat, tests |
| [docs/ART_DIRECTION.md](docs/ART_DIRECTION.md) | the one art direction: colour roles, shapes, materials, motion, UI system |
| [docs/REQUIREMENTS_CHECKLIST.md](docs/REQUIREMENTS_CHECKLIST.md) | every requirement with an ID (written before development) |
| [docs/REPOSITORIES.md](docs/REPOSITORIES.md) | reference repositories inspected and what was (not) used |
| [docs/CODERABBIT_REPORT.md](docs/CODERABBIT_REPORT.md) | milestone reviews (CodeRabbit blocked → substitute reviews) |
| [docs/REVIEW_FINDINGS.md](docs/REVIEW_FINDINGS.md) | every critical and major review finding: issue → fix → test → verify |
| [docs/ASSET_GATE.md](docs/ASSET_GATE.md) | per-asset art gate (generated from `game/data/art/asset_gate.json`) |
| [docs/FINAL_IMPLEMENTATION_REPORT.md](docs/FINAL_IMPLEMENTATION_REPORT.md) | status of every requirement with evidence |
| [game/server/README.md](game/server/README.md) | server-side replay verification |

## Licences

Code: project code. Engine: Godot (MIT). Font: Outfit (SIL Open Font License 1.1,
`game/assets/fonts/OFL.txt`). Audio and icons are original, generated by the scripts in this repository
(`game/assets/LICENSES.json`). No third-party runtime libraries.
