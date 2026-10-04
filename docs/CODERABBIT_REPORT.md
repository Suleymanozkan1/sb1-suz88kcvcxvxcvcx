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

After integration, five independent finder agents reviewed the whole game by area (gameplay core,
app flow, UI screens, gameplay view + performance, security + data). Every finding needed a concrete
reproduction (headless probe or test). A second, skeptical verifier per area then tried to refute each
finding on the current code; confirmed findings were fixed with regression tests. A separate, independent
security/data reviewer ran in parallel. Finally a requirement-by-requirement assessment (10 agents:
5 assessors + 5 downgrade-only verifiers over all 333 requirement IDs) surfaced more defects (R-STATUS).

| Review | Date | Scope | Found | Critical | Major | Minor | Verified | Fix commit | Open after fix |
|---|---|---|---|---|---|---|---|---|---|
| R-INT round 1 (app flow, gameplay core) | 2026-10-03 | M1–M5, M8 | 22 | 4 | 11 | 7 | fixed first; verifier then confirmed 3 residual defects (app-flow-01 minor, app-flow-03 major, gameplay-core-4 minor) | `d107839`, residuals `055562e` | 0 |
| R-INT round 2 (UI screens) | 2026-10-03 | M5 | 12 | 3 | 7 | 2 | 12 / 12 confirmed | `055562e` | 0 |
| R-INT round 2 (view + performance) | 2026-10-03 | M1, M2, M9 | 12 | 2 | 7 | 3 | 12 / 12 confirmed | `055562e` | 0 |
| R-INT round 2 (security + data) | 2026-10-03 | M6, M8, M10 | 8 | 2 | 3 | 3 | 6 confirmed, 2 refuted (one later reproduced by the independent reviewer and fixed) | `055562e` | 0 |
| Independent security/data review | 2026-10-03 | M6–M8, M10 | 10 | 1 | 2 | 7 | reproduced with probes (p1–p9) | `055562e` | 0 |
| R-STATUS (requirement assessment) | 2026-10-03 | all | 23 | 0 | 6 | 17 | each reproduced before fixing | `26c2427` and the following commit | 0 |
| R-FINAL (final review of the last fix round, the "final CodeRabbit" step) | 2026-10-03 | M4, M5, M7, M8 | 5 | 0 | 0 | 5 | each traced through the code paths; one measured with a layout probe | final commit | 0 (4 fixed, 1 by design) |
| **R-INT total** | | | **92** | **12** | **36** | **44** | | | **0** |

Several findings overlap across reviewers (the stream-rebuild cost, the week-boundary board, the
reward-claim bounds); they are counted once per reviewer above, so unique defects are slightly fewer.

Highlights:

* **Critical (all fixed):** settings toggles flipped twice per tap (analytics opt-out impossible);
  invisible "Double it (optional ad)" and navigation buttons pressable during the result sequence (an
  accidental ad); the shop never showed a price; after a rewarded revive the core stayed invisible and
  the barrier it hit stayed drawn; leftward currents drawn over the wrong lanes; reward claims at 100×
  the real level reward accepted by the verifier; a stale end tick accepted; the revive double-apply of
  a run (round 1).
* **Major (all fixed):** language change left screens in the old language; daily rank always "—";
  endless fail showed "0% of the way"; HUD score off-centre; glow/ambient particles ignored by quality;
  automatic downgrade never reached render scale/MSAA/fps cap; Reduce Motion did not reduce camera
  motion; Colour-blind did nothing; magnet visual pulled sparks the sim never collects; repeat level
  reward claims unlimited; daily claims not bounded by the allowed tier; IntegrityMonitor never ran;
  offline score queue never retried in a later online session; world data named the pulse-gate hazard
  "pulse" so 20 chapters placed no pulse gates; 81 sold cosmetics had no in-game effect; level-up
  reveals covered PLAY AGAIN; the near-miss rule could never trigger for lane hops; mid-world
  challenges were 30–60 s instead of 60–120 s; the iOS export failed without a team ID.
* **Minor (all fixed):** localized duration units, slider touch targets, leaderboard tab state,
  turbine roll leaking into other worlds, bounded silhouette approach, atmosphere opacity above 8 %,
  per-frame material writes and key copies, stream pops behind the core, fail-open "accepted" on a 2xx,
  URL guard bypass with `?@host`, remote config wiped by an error body, unsanitized profile flags,
  invisible marks in names, completion stingers never played, combo music stem never reset,
  boss-rush music, beat sync, reward haptics, ENDLESS state unused, AsyncLoader unused, remote keys
  unread, licence text, app icon gradients, finish membrane behind the results.

R-FINAL (independent reviewer, read-only, over every uncommitted code change of the last round —
near miss, set pieces, remote tuning, stream pre-check, ENDLESS state, music prefetch, star unlock,
bonus chest, daily rank, touch targets, palette clamp, caustics, collect pop, dead-code removal): no
critical or major defect; the removed functions have no remaining callers and replay determinism holds.
Five minor findings: (1) the paused-daily sentence on the Play button made it 796–968 px wide on a
720 px canvas → short `daily.paused` label, `test_locked_daily_button_fits_the_screen`; (2) the
server's claim scales were never set and the weekend bonus depends on the client's run-start day →
`ReplayVerifier.apply_remote_tuning` (allows the bonus on every day while configured, junk values fall
back, clamped like the client), documented in `game/server/README.md`,
`test_server_tuning_allows_the_weekend_bonus_on_any_day`; (3) score-mode coins ignored the live
multiplier and weekend bonus → `RewardEngine.with_coin_scale` in `RunController._finish_scored`,
`test_score_mode_coins_follow_the_live_multiplier`; (4) a level-up from the bonus chest's XP was only
revealed after the next run → `GameFlow._open_bonus_chest` collects it, `test_bonus_chest_level_up_is_revealed_with_it`;
(5) Time Attack moved from "20 levels" to "60 stars" → by design, no change: the game has not shipped
(no saves exist with the old rule) and stars never decrease, so an unlock is never taken back. Note
kept as a limit: a prefetched music loop that is never played stays loaded for the session (at most
one world's loops per world visited).

Verification: after the fixes the full suite (now 740+ tests including `test_ui_regressions.gd`,
`test_view_regressions.gd`, `test_remote_tuning.gd`, `test_state_machine.gd`, `test_safe_area.gd`,
`test_async_music.gd` and the new cases in the online, platform, profile, level-pipeline, sim and
app-flow suites) passes, gdlint is clean and all 520 regenerated levels validate.

## Milestone review log (per milestone)

| Milestone | Date | Commit(s) | Scope | Critical | Major | Minor | Fixed | Remaining | Final status |
|---|---|---|---|---|---|---|---|---|---|
| M1 Core prototype | 2026-10-03 | `b091251` → `d107839`, `055562e` | sim, session (R-INT gameplay core) | 1 | 4 | 5 | 10 | 0 | reviewed, fixed |
| M2 Core gameplay | 2026-10-03 | `53e1a0f` → `055562e` | view, forms, juice (R-INT view) | 2 | 7 | 3 | 12 | 0 | reviewed, fixed |
| M3 Level system | 2026-10-03 | `b091251` → `26c2427` + follow-up | pulse chapters, challenge length, near miss (R-STATUS) | 0 | 3 | 0 | 3 | 0 | reviewed, fixed |
| M4 Progression | 2026-10-03 | `4a6029d` → `e8ef6f8`, final commit | R-PROG, R-FINAL | 0 | 3 | 12 | 14 (2 at integration) | 0 (1 by design) | reviewed, fixed |
| M5 UI/UX | 2026-10-03 | `d107839`, `055562e`, `26c2427`, final commit | R-INT app flow + UI screens, R-STATUS, R-FINAL | 6 | 15 | 12 | 33 | 0 | reviewed, fixed |
| M6 Save system | 2026-10-03 | `86431da` → `ce24494`, `055562e` | R-SAVE, profile flags | 0 | 2 | 9 | 9 | 0 (2 accepted, documented limits) | reviewed, fixed |
| M7 Economy & cosmetics | 2026-10-03 | `aa87d85`, `d88e85e`, `26c2427`, final commit | R-ECON, R-COS, R-STATUS, R-FINAL | 0 | 6 | 18 | 24 | 0 | reviewed, fixed |
| M8 Daily / missions / achievements / leaderboard | 2026-10-03 | `908b4fe`, `7e0e9df`, `055562e`, final commit | R-ONLINE, R-META, R-INT security, independent security, R-FINAL | 4 | 17 | 22 | 43 (2 at integration) | 0 | reviewed, fixed |
| M9 Optimization & platform | 2026-10-03 | `22bc293`, `f3fab46`, `055562e`, follow-up | R-FEEL, R-PLAT, audio/loading/allocations | 0 | 9 | 24 | 33 | 0 | reviewed, fixed |
| M10 Release build | 2026-10-03 | export presets, CI, follow-up | iOS team ID, licence notices, docs | 0 | 1 | 2 | 3 | 0 | Android debug APK + iOS Xcode project exported; signing BLOCKED |
| **Total** | | | | **13** | **67** | **107** | **184 of 187** | **0 open** | |

Every critical and major finding above, row by row (issue → fix → commit → regression test → verification → status, critical first): `docs/REVIEW_FINDINGS.md`.

The per-milestone counts assign every module and integrated finding (95 + 92 = 187) to the milestone
whose code it concerns; each finding is counted once. The three findings not fixed are R-SAVE's two
accepted, documented limits and R-FINAL's Time Attack unlock note (by design, see above). Real CodeRabbit runs
remain BLOCKED; nothing here is a CodeRabbit result.
