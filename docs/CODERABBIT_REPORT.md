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
| M11 | Round 5: mass & gravity mechanics, cloud save, music lock, visual quality, performance budgets, refactors | `83c86ef` → `f0f3391` | Independent review R-6 (three areas) + 24-level visual review |
| M12 | Early-pacing pass after player feedback, iOS device build in CI | `f7cfff3`, `914c96f` | Independent review R-7 |

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

## Round 5 review R-6 (three independent reviewers, 2026-10-04)

Round 5 (`4d3eb5f..f0f3391`) added the mass & gravity family, cloud save, music locked to the run, the
visual-quality work, performance budgets and the GameFlow / typed-dictionary / named-constant refactors.
Three reviewers that had not written the code reviewed the round's diff by area, reproduced each defect
with a headless script or a render under Xvfb, and changed nothing; the fixes and regression tests were
written afterwards (each regression test fails on the old code).

| Area | Found | Critical | Major | Minor | Fixed | Fix commit | Notes |
|---|---|---|---|---|---|---|---|
| Sim and levels | 2 | 0 | 1 | 1 | 2 | `6cc5fc8` | A dash through a stack-crash glass row kept the plates, so a later launch planned for a lighter core could not clear its wall (w10_l33, w10_l50); 22 World 10 levels regenerated |
| App and systems | 9 | 3 | 3 | 3 | 9 | `a6ba2be` | All in the new cloud save: fresh install wiping a linked wallet, clock-based last-writer-wins wallet, merges counted as earnings, dirty flag lost on pause, in-flight changes marked synced, bonus stars merged by max, quadratic de-duplication, future daily day adopted, uploads larger than downloads; replaced by a three-way wallet merge (`WalletMerge`) |
| View, shaders, tools | 14 | 0 | 6 | 8 | 12 | `69f3f09` | Low/Medium never got the light glass, per-frame sky re-bake, reflection probe mirroring hazards, pooled views keeping shader values, swatch ignoring fades; 2 accepted (below) |
| **Total** | **25** | **3** | **10** | **12** | **23** | | **0 open; 2 accepted, documented** |

Accepted, documented: (1) the reflection probe's re-captures do not appear in the engine's draw-call
counter, so the High/Ultra draw-call budgets cannot see them (their cost shows in frame time and video
memory; `docs/ARCHITECTURE.md` §9); (2) a tool or test booting the app with analytics consent off clears
that machine's local analytics log — the designed consent behaviour, it only touches developer machines.
The 24-level visual review found four more issues, all fixed: passed gate arches and pulse-gate shutters
hiding the core (`9b64e2d`, `69f3f09`), the muddy dash core in high-key worlds, floor-light banding and the
probe mirroring hazard colour onto ribs. Verification after the fixes: full suite 885 tests, 0 failed;
520/520 levels validate (worst tap window 150 ms); regeneration reproduces all 520 files.

## Pacing review R-7 (one independent reviewer, 2026-10-04)

The first player report on the APK said the game stayed too simple for too long. The pacing pass
(`914c96f`: front-loaded curve, 10/8 m lead-in and tail, three-level tutorial, sliders at L14, all 520
levels regenerated) and the CI change that builds the iOS device app with Xcode 26 (`f7cfff3`) were
reviewed by a reviewer that had not written them. The reviewer reproduced every finding with headless
probes, changed nothing, and found 0 critical, 2 major and 7 minor issues; all nine are fixed in `a0be5ae`.

| # | Severity | Finding | Fix | Regression test |
|---|---|---|---|---|
| R7-1 | major | The 10 m lead-in made 14 World 5 (surge) levels demand a tap 0.53–0.58 s after GO (w05_l16: 0.17–0.40 s), although a tap during READY only starts the run; nothing limited how soon the first decision may be due. | Validator rule: no tap may be due before `FIRST_DECISION_S` (1.0 s) after GO; the generator refuses such windows (the row moves further away or the slot goes calm). | `unit/test_level_pacing.gd::test_the_first_decision_leaves_time_to_read`; all 520 levels validate under the rule |
| R7-2 | major | Endless, Time Attack and Zen are built from campaign specs, so the curve change retuned them silently (Zen, "slower, no score pressure", went from 0.36 to 0.68 taps/s; Endless 0.24 → 0.66). | Streams pin `change_prob` and `density` per mode in `modes.json` (Zen 0.4/0.6 → about 0.43 taps/s; Endless and Time Attack keep the busier pace on purpose). | `unit/test_level_pacing.gd::test_streamed_modes_keep_their_pace` |
| R7-3 | minor | `RunController.TUTORIAL_LAST_LEVEL` still named w01_l05, no longer a tutorial level. | `w01_l03`. | `test_the_tutorial_is_short` checks it is the last tutorial level |
| R7-4 | minor | Docs claimed "a lane change every 1.2–1.8 s" from level 4 (chapter averages, not per level), the shield at L27 and prisms from L4 (data: L28, L5). | Docs give averages and per-level ranges; the shield is now in L27 (R7-6). | — |
| R7-5 | minor | REQ-078/079/080 evidence still described the old tiers and phases. | Updated. | — |
| R7-6 | minor | w01_l27 showed "New: a shield absorbs one hit" without a shield. | A chapter that introduces a pickup places it at the first pickup spot of each introduction level. | `test_every_introduction_level_shows_its_idea` |
| R7-7 | minor | The pacing tests were too weak (a 0.25 taps/s floor, nothing on the lead-in, a tutorial check the generator guarantees anyway). | Floors 0.3 / 0.6 / 0.75 taps/s, first row within 2.8 s, tutorial slower and shorter than level 4, sliders in every L14–25 level. | `unit/test_level_pacing.gd` (7 tests) |
| R7-8 | minor | The CI step could pick a beta or release-candidate Xcode (`sort -V` puts `26.1_beta_2` after `26.1`). | Betas and release candidates are filtered out. | CI job |
| R7-9 | minor | Every course changed but `SIM_VERSION` and `GENERATOR_VERSION` did not, so a run from an older build would be rejected as a score mismatch instead of an old version. | `SIM_VERSION` 4, `GENERATOR_VERSION` 2. | Existing replay-version tests |

Verification after the fixes: 520 levels regenerated (0 failures) and validated (0 failed, 0 warnings),
full suite 893 tests, 0 failed.

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
| M11 Round 5 | 2026-10-04 | `6cc5fc8`, `69f3f09`, `a6ba2be` | R-6 sim/levels, app/systems (cloud save), view/shaders/tools | 3 | 10 | 12 | 23 | 0 (2 accepted, documented) | reviewed, fixed |
| M12 Pacing pass | 2026-10-04 | `a0be5ae` | R-7 pacing, modes, CI | 0 | 2 | 7 | 9 | 0 | reviewed, fixed |
| **Total** | | | | **16** | **79** | **126** | **216 of 221** | **0 open** | |

Every critical and major finding above, row by row (issue → fix → commit → regression test → verification → status, critical first): `docs/REVIEW_FINDINGS.md`.

The per-milestone counts assign every module, integrated, round-5 and pacing finding (95 + 92 + 25 + 9 = 221) to the milestone
whose code it concerns; each finding is counted once. The five findings not fixed are R-SAVE's two
accepted, documented limits, R-FINAL's Time Attack unlock note (by design, see above) and R-6's two accepted,
documented items (probe draw calls outside the counter; consent clearing a developer's local analytics log). Real CodeRabbit runs
remain BLOCKED; nothing here is a CodeRabbit result.
