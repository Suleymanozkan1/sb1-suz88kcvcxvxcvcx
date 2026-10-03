# CodeRabbit Report — FLUX DROP

## Status: CodeRabbit CLI **BLOCKED** → substitute reviews performed

The brief asks for `coderabbit review --agent` after every milestone. In this build environment the
CodeRabbit CLI cannot be installed or run:

| Check (2026-10-03) | Result |
|---|---|
| `curl https://cli.coderabbit.ai/install.sh` | `CONNECT tunnel failed, response 403` (outbound host refused by the environment's network policy) |
| npm `@coderabbitai/cli` | `404 Not Found` (no npm distribution) |
| npm `coderabbit` | name-squatted security holding package (not the CLI) — not installed |
| `which coderabbit` | not installed |
| Account/API authentication | not possible without the CLI and a CodeRabbit account |

Because no CodeRabbit run was possible, **no CodeRabbit result is claimed anywhere in this
repository.** Instead every milestone's code went through an independent, adversarial review by
separate reviewer agents that had not written the code, followed by fixes and regression tests. These
are logged below with the same information a CodeRabbit run would provide (scope, findings, severity,
fix, verification). To run real CodeRabbit later: install the CLI on a machine with access to
`cli.coderabbit.ai`, authenticate, and run `coderabbit review --agent` on each milestone range below.

## Milestones and review coverage

| # | Milestone | Commits | Review performed |
|---|---|---|---|
| M1 | Core prototype (sim, session, view) | `b091251` | Integrated review R-INT (area gameplay-core, view-perf) |
| M2 | Core gameplay (forms, elements, combo, juice) | `b091251`, `53e1a0f` | R-INT (gameplay-core, view-perf) + visual review of 10 worlds |
| M3 | Level system (generator, validator, 520 levels) | `b091251`, `53e1a0f` | R-INT (gameplay-core) + full validation of 520 levels in CI form |
| M4 | Progression system | `4a6029d`→`e8ef6f8` (review fix), merge `9f765fd` | Module review R-PROG |
| M5 | UI/UX | `53e1a0f`, `9a769df`, `25f2423` | R-INT (ui-screens, app-flow) + screen-by-screen visual review (EN + TR) |
| M6 | Save system | `86431da`→`ce24494`, merge `4a862b6` | Module review R-SAVE |
| M7 | Economy & cosmetics | `4a6029d`→`aa87d85`, `b23f3bf`→`d88e85e` | Module reviews R-ECON, R-COS |
| M8 | Daily / missions / achievements / leaderboard | `67d68b9`→`908b4fe`, `89098dd`→`7e0e9df` | Module reviews R-ONLINE, R-META |
| M9 | Optimization & platform services | `3ebda43`→`22bc293`, `933e677`→`f3fab46` | Module reviews R-FEEL, R-PLAT + R-INT (view-perf) |
| M10 | Release build | `export_presets.cfg`, CI, Android debug APK | R-INT (security-data) + export verification (signed debug APK, all 520 levels packaged) |

## Module reviews (one independent reviewer per module, fixes committed on `review/<module>`)

Each reviewer read the module against its spec, reproduced every defect with a headless probe or a
failing test **before** fixing it (mutation check: new tests fail on the original code), fixed it, and
ran the module suite and the full suite.

| Review | Fix commit | Findings | Severity | Fixed | Highlights |
|---|---|---|---|---|---|
| R-SAVE | `ce24494` | 10 | 2 major, 8 minor | 8 (+2 accepted limits documented) | bare un-enveloped "v0" JSON bypassed the checksum (99 999 999 coins loaded) → removed; ±2^53 clamp; quadratic migration; size cap on reads; control chars in names |
| R-ECON | `aa87d85` | 10 | 1 major, 9 minor | 10 | `{coins: 0, gems: 5}` priced items as free; replay reward floor; hostile numeric strings; Turkish ad copy implied "short"; streak copy pushed a return |
| R-FEEL | `22bc293` | 10 | 3 major, 7 minor | 10 | nested mixer data crashed every `play_sfx`; quality auto-detect crash on bad data; playback before entering the tree; battery-saver ranges; per-frame dictionary copies |
| R-PROG | `e8ef6f8` | 14 | 3 major, 11 minor | 12 (+2 out of module, fixed at integration) | type-unsafe reads aborted progress recording; XP clamp could lower a player's level; int64 overflow; INF times |
| R-PLAT | `f3fab46` | 14 | 6 major, 8 minor | 14 | consent withdrawal re-sent queued events; "anonymous" copy overstated privacy; forbidden PII names matched only whole tokens; URL guard allowed local HTTP in release; double grant on restore during purchase |
| R-COS | `d88e85e` | 11 | 4 major, 7 minor | 11 | validator returned zero errors on malformed config; signed hex colours accepted; badge ids not matching achievements; level-gated items unreachable on the XP curve |
| R-ONLINE | `908b4fe` | 17 | 1 critical, 8 major, 8 minor | 15 (+2 out of module, fixed at integration) | **critical:** a replay with `"seed": null` crashed the verifier CLI which then exited 0 = "valid" → every field type-checked, exit code defaults to error; clock-back daily reward farming; non-canonical date keys; queue eviction; control/bidi chars in names |
| R-META | `7e0e9df` | 9 | 4 major, 5 minor | 9 | weekly missions that could not be finished in the remaining days (fake goal) → capped targets; float reward amounts after save round-trip; tampered stored reward specs |
| **Total** | | **95** | **1 critical, 31 major, 63 minor** | **89 fixed in-module, 4 fixed at integration, 2 documented limits** | |

Items the module reviewers could not fix in their module and that were fixed during integration
(`25f2423`): queued taps on consecutive ticks were rejected by the server (min 2-tick spacing now
enforced in `GameplaySession`); endless runs were ranked but the server could not rebuild endless
courses (now rebuilt from the seed — end-to-end test `test_stream_verification.gd`); hostile field
types in `PlayerProfile.from_dict` (hardened + `test_profile_hostile.gd`); the test runner did not fail
tests that hit script errors (now detected through an engine `Logger`).

## Integrated review R-INT (all milestones, five areas, adversarially verified)

See the section appended below after the run (findings, verification verdicts and fixes).
