# FLUX DROP — Final Implementation Report

Generated from the repository state on branch `claude/sharp-clarke-gnn3y1` (2026-10-03).
Every status below is backed by a file, function or test in this repository, or by a recorded
command result. The requirement matrix (section 4) and the completion figure (section 40) are rendered
by `tools/report/completion.py` from `docs/requirements_status.json`, which was produced by
independent assessor agents and checked by independent skeptic agents allowed only to downgrade.

## 1. Executive Summary

FLUX DROP is an original one-tap mobile game built in Godot 4.7.2: one input whose meaning changes with
the core's form (hop / colour phase / dash / weight), 520 generated and proven-fair levels in 10 worlds
with boss and challenge set pieces, 8 modes, a daily challenge with a gentle streak, daily/weekly
missions, 82 achievements, a cosmetics-only economy (112 items, every category visible in game),
leaderboards with server-side replay verification, a versioned corruption-safe save, procedural audio
and haptics, quality presets with automatic downgrade, analytics/remote config/ads/IAP/notification
architecture with honest null providers, 13 UI screens on one design system in English and Turkish,
CI and documentation.

Verified results (final runs, 2026-10-03): **746 automated tests pass (0 failures)**;
**520/520 levels validate** (validated 520 levels in 394.8s: 0 failed, 0 with warnings, worst tap window 183 ms); regenerating all 520 levels reproduces
the committed data (generated 520 levels in 553.2s, failures=0 mismatches=0); a **signed Android debug APK** (64 MB, v2+v3
signatures verified, 520 level files packaged) and an **iOS Xcode project** export here; gdlint,
placeholder and licence scans are clean.

Not achievable in this environment (BLOCKED): compiling/signing the iOS app (no macOS/Xcode/Apple
account), release signing (no keystore/accounts), CodeRabbit (CLI download refused by the network
policy). Not done for lack of hardware or people: on-device performance/battery/thermal/haptics
measurement and human playtests (PARTIAL where a requirement depends on them).

<!-- COMPLETION:BEGIN -->
| Total requirements | 333 |
|---|---|
| IMPLEMENTED | 251 |
| PARTIAL | 76 |
| NOT_IMPLEMENTED | 2 |
| BLOCKED | 4 |
| **Completion = Implemented / Total × 100** | **75.4 %** |
<!-- COMPLETION:END -->

## 2. Project Overview

| Item | Value |
|---|---|
| Engine | Godot 4.7.2-stable (official), Mobile renderer, Compatibility fallback |
| Language | GDScript, fully static typed (untyped declarations are a project error) |
| Code | 188 `.gd` files, ~40,023 lines (26,074 in `game/src`), 66 test files |
| Data | 566 JSON files (520 levels, 10 worlds, curve, modes, economy, rewards, cosmetics, store, achievements, missions, daily, analytics schema, remote config, ads policy, audio bank, quality presets, haptics, i18n) |
| Assets | 11 shaders, 64 audio files (31 SFX + world/boss loops, intensity stems, stingers; 22 MB, procedurally synthesised), Outfit font (OFL), flat app icon |
| Platforms | Android (APK, arm64-v8a + armeabi-v7a), iOS (Xcode project, arm64, iOS 14+) |
| Docs | README, ARCHITECTURE, GAME_DESIGN, LEVEL_DESIGN, ART_DIRECTION, REPOSITORIES, REQUIREMENTS_CHECKLIST, CODERABBIT_REPORT, this report |

## 3. Requirements Summary

`docs/REQUIREMENTS_CHECKLIST.md` was written before development (commit `b9cbbd1`) and lists 333
requirements in 27 groups (A–Z plus AA, the anti-AI-slop art direction added mid-development). Counts
by status are in section 40; each requirement's status, location, files, functions, tests, runtime
verification and notes are in section 4.

## 4. Full Requirements Matrix

<!-- MATRIX:BEGIN -->
#### A. Process & originality

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-001 | Do not ask the user questions; take professional decisions autonomously. | **IMPLEMENTED** | docs | docs/CODERABBIT_REPORT.md, docs/ARCHITECTURE.md, game/assets/LICENSES.json | Claude, UTC |  | code inspection | Judged from repo only; the conversation is not in the repo, so the absence of questions cannot be proven. No question artifacts found. |
| REQ-002 | Complete the work in a single working session as far as possible. | **IMPLEMENTED** |  |  | Every, Claude, Session |  | code inspection | Delivered in one long autonomous session; release signing and the compiled iOS app remain BLOCKED (report section 38). Every non-merge commit after the legacy web project carries Claude-Session: session_01NCJ2vt5E5MLemEUyuKwnNQ; the merges are by the same author; all work is dated 2026-10-03 (git log). |
| REQ-003 | Create `docs/REQUIREMENTS_CHECKLIST.md` listing every requirement with an ID before development. | **IMPLEMENTED** | docs | docs/REQUIREMENTS_CHECKLIST.md |  |  | code inspection | The brief is not in the repo, so completeness against it cannot be checked; REQ-302..333 were added mid-development. |
| REQ-004 | Follow the mandated 20-step ordering (inspect → architecture → prototype → … → final report). | **PARTIAL** |  |  | VFX |  | code inspection | Modules were built in parallel (save/analytics/daily came before progression/UI) and CodeRabbit was replaced by substitute reviews; optimization/export, the final review (R-FINAL) and this report were done at the end as ordered. — evidence: git log order: checklist -> core+levels+difficulty (b091251) -> save (86431da) -> platform/analytics (933e677) -> daily (67d68b9) -> feel/VFX (3ebda43) -> economy -> cosmetics -> missions -> progression (412a3d1) -> UI (53e1a0f) -> reviews/fixes -> docs. |
| REQ-005 | The game is fully original and not a clone of any existing game. | **IMPLEMENTED** | game/src/gameplay/sim | game/src/gameplay/sim/flux_sim.gd | Original, FluxSim._apply_tap, SimConst, EntityType | test_form_gate_switches_tap_meaning | automated tests (suite 746 passed, 0 failed) | Originality is a design judgement; no formal IP/trademark search. Phase colour gates resemble a common genre mechanic. |
| REQ-006 | Do not copy names, characters, maps, UI, sounds, animations or distinctive mechanic combinations of Ketchapp/Voodoo games. | **IMPLEMENTED** | game/assets | game/assets/LICENSES.json, tools/audio/synth_bank.py, mesh_factory.gd | Assets, SVG, OFL, Outfit, Ketchapp, Voodoo |  | code inspection | Checked by inspection only; no external IP review. |
| REQ-007 | Use only abstracted, industry-level design principles from successful hyper-casual games. | **IMPLEMENTED** | mechanics.json | mechanics.json, docs/GAME_DESIGN.md | LevelGenerator, LevelValidator |  | level validator 520/520 | Judged by inspection; no competitor-specific content found. |
| REQ-008 | Use "FLUX DROP" as working name or produce a better original name. | **IMPLEMENTED** | game | game/project.godot, game/export_presets.cfg, en.json, tr.json | FLUX, DROP |  | Android debug export | Working name kept; no trademark search done. |

#### B. Core design pillars & core loop

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-009 | Extremely simple control structure. | **IMPLEMENTED** | game/src/app | game/src/app/game_flow.gd | Single, GameFlow._unhandled_input, Space, GameplaySession.request_tap, FluxSim.step |  | code inspection | One tap only; its meaning depends on the visible form (by design). |
| REQ-010 | Game is understandable within the first 5 seconds. | **PARTIAL** | hud.gd | hud.gd | Tutorial, L1, DifficultyModel._apply_tutorial, HUD, TUTORIAL, TAP |  | code inspection | No human playtest; '5 seconds to understand' is unmeasured. — evidence: Tutorial L1-5 (DifficultyModel._apply_tutorial: slower, forgiving first hit); HUD tap hint on stored solution taps (hud.gd TUTORIAL_HINT_LEAD); w01_l01 lasts 10.4 s with 2 taps; form hints 'TAP = ...'. |
| REQ-011 | Player has fun within the first 15 seconds. | **PARTIAL** |  |  | Overdrive | test_main_scene_boots_headless | automated tests (suite 746 passed, 0 failed) | Fun within 15 s not verified by any human playtest. — evidence: w01_l01 is 10.4 s; probe of all 520 stored solutions shows combo steps and Overdrive in every level; attract run plays behind the main menu (test_main_scene_boots_headless). |
| REQ-012 | Player wants to retry within 30 seconds ("one more try"). | **PARTIAL** |  |  | Fail, RESULT, FailOverlay.enter, TIP | test_restart_is_stable_and_fast | automated tests (suite 746 passed, 0 failed) | Wanting to retry within 30 s is a player outcome; not playtested. — evidence: Fail card after RESULT_DELAY 0.55 s with progress %, best and a reason tip (FailOverlay.enter, TIP_KEYS); restart without scene reload (test_restart_is_stable_and_fast). |
| REQ-013 | Short play sessions. | **IMPLEMENTED** | curve.json | curve.json | JSONs, LevelValidator |  | level validator 520/520 | Durations are design durations along the stored solution. |
| REQ-014 | Near-instant restart with no unnecessary loading. | **IMPLEMENTED** |  |  | GameFlow._restart, GameplaySession.restart, READY, GameplayView.reset_for_run | test_restart_is_stable_and_fast, test_app_flow.gd | automated tests (suite 746 passed, 0 failed) | Campaign restart timed headless only; endless/boss-rush restarts re-prepare via _start_run (untimed). Not measured on a device. |
| REQ-015 | PLAY AGAIN is reachable very quickly after failing. | **IMPLEMENTED** | game/src/app | game/src/app/game_flow.gd | Fail, GameFlow, RESULT, PLAY, AGAIN, FailOverlay.enter | test_fail_card_stays_clear_and_music_follows_the_run, test_app_flow.gd | automated tests (suite 746 passed, 0 failed) | Timed headless; not measured on a device. |
| REQ-016 | Physical and visual satisfaction. | **PARTIAL** | core_view.gd | core_view.gd, burst_pool.gd | Juice, CoreView, GameplayView.hit_stop, CameraRig.add_trauma, BurstPool |  | visual review of screenshots (Xvfb) | Feel never tried on a device or by players; only static screenshots reviewed. — evidence: Juice code: CoreView springs/squash/morph (core_view.gd), GameplayView.hit_stop/slow_motion/shockwave, CameraRig.add_trauma/fov_punch, BurstPool debris (src/vfx/burst_pool.gd); reviewed via llvmpipe screenshots. |
| REQ-017 | Level-based progression. | **IMPLEMENTED** | progression_service.gd | progression_service.gd | ProgressionService.is_level_unlocked | test_catalog_has_ten_worlds_and_520_levels, test_progression_ | automated tests (suite 746 passed, 0 failed) | Checked in code, shipped data and headless tests. |
| REQ-018 | Mechanics unlock gradually. | **IMPLEMENTED** |  |  | First, L1, L15, L17, L27, L40 | test_difficulty_structure_tiers_and_specials | automated tests (suite 746 passed, 0 failed) | Pulse gates now first appear in the W1 pulse chapter (L40), as designed. |
| REQ-019 | Combo system. | **IMPLEMENTED** |  |  | SimConst.combo_multiplier, FluxSim._combo_up | test_spark_collection_combo_and_multiplier, test_missed_spark_breaks_combo, test_sim_rules.gd | automated tests (suite 746 passed, 0 failed) | Checked in code, shipped data and headless tests. |
| REQ-020 | Collectible structure. | **IMPLEMENTED** | cosmetics.json | cosmetics.json | Spark, FluxSim._check_collect |  | code inspection | Checked in code, shipped data and headless tests. |
| REQ-021 | Skin / cosmetic progression. | **IMPLEMENTED** |  |  | CosmeticService, CosmeticCatalog, GameplayView.apply_cosmetics, UiTheme.apply_accent, ProfileEmblem | test_particle_effect_and_background_cosmetics_change_the_view, test_theme_cosmetic_recolours_the_ui_and_default_restores_it | automated tests (suite 746 passed, 0 failed) |  |
| REQ-022 | Missions. | **IMPLEMENTED** | mission_service.gd | mission_service.gd, missions.json | MissionService, EventBus | test_meta_missions.gd, test_meta_missions_schedule.gd | automated tests (suite 746 passed, 0 failed) | Checked in code, shipped data and headless tests. |
| REQ-023 | Daily content. | **IMPLEMENTED** | daily_challenge_service.gd | daily_challenge_service.gd, modes.json | DailyChallengeService, UTC, Daily | test_online_daily_level.gd, test_online_daily_streak.gd, test_daily_rewards_only_first_completion | automated tests (suite 746 passed, 0 failed) | Daily content is generated locally; no hosted daily leaderboard. |
| REQ-024 | High replayability. | **PARTIAL** | modes.json | modes.json | Replay, RunResult.compute_stars, Endless | test_endless_seed_is_weekly_and_deterministic | automated tests (suite 746 passed, 0 failed) | Replay systems exist and are tested, but 'high' replayability is unmeasured: no retention data or human playtests. — evidence: Replay drivers: 3 stars/perfect per level (RunResult.compute_stars), 8 modes incl. weekly-seeded Endless (data/modes/modes.json; test_endless_seed_is_weekly_and_deterministic), daily level, missions, 82 achievements, 112 cosmetics, local boards. |
| REQ-025 | Satisfying sound / haptics / particle feedback. | **PARTIAL** | synth_bank.py | synth_bank.py, patterns.json | AudioService, SoundBank, SFX, HapticsService, Input.vibrate_handheld, BurstPool | test_feel_audio, test_feel_haptics.gd | automated tests (suite 746 passed, 0 failed) | Haptics never run on a device; how satisfying audio/particles feel has not been judged by players. — evidence: AudioService/SoundBank: 31 SFX + 33 music files from synth_bank.py, combo pitch steps; HapticsService via Input.vibrate_handheld with patterns (data/haptics/patterns.json); BurstPool particles; tests test_feel_audio*.gd, test_feel_haptics.gd. |
| REQ-026 | Player controls a small, visually high-quality energy core. | **PARTIAL** | core_view.gd | core_view.gd, core.gd | CoreView |  | visual review of screenshots (Xvfb) | Control done; quality judged only on llvmpipe shots (orb reads as a plain glow disc, dash capsule looks muddy in w04). No device render. — evidence: CoreView (src/gameplay/view/core_view.gd): 4 silhouettes (orb/prism/comet/sphere-in-ring), core.gdshader, ink shell, halo, charge shards, 19 skins; seen in lead/worlds_final/*.png llvmpipe captures. |
| REQ-027 | The core advances automatically. | **IMPLEMENTED** |  |  | FluxSim.step, DT | test_runs_to_completion_without_input, test_sim_basic.gd | automated tests (suite 746 passed, 0 failed) | Checked in code, shipped data and headless tests. |
| REQ-028 | TAP changes the core's current movement behaviour. | **IMPLEMENTED** |  |  | FluxSim._apply_tap, HOP, PHASE, DASH, SURGE | test_hop_moves_between_lanes_smoothly, test_phase_gate_requires_matching_phase, test_dash_cooldown_denies_spam, test_surge_changes_speed_with_momentum | automated tests (suite 746 passed, 0 failed) | Checked in code, shipped data and headless tests. |
| REQ-029 | Pass obstacles with correct timing. | **IMPLEMENTED** |  |  | FluxSim._check_hazard, LevelGenerator._measure_window, LevelValidator | test_barrier_kills_and_hop_avoids | automated tests (suite 746 passed, 0 failed); level validator 520/520 | Checked in code, shipped data and headless tests. |
| REQ-030 | Collect energy objects. | **IMPLEMENTED** |  |  | Sparks, FluxSim._check_collect, Overdrive | test_spark_collection_combo_and_multiplier | automated tests (suite 746 passed, 0 failed) | Checked in code, shipped data and headless tests. |
| REQ-031 | Interact correctly with colour / energy types. | **IMPLEMENTED** |  |  | Phase, PHASE, FailReason, WRONG | test_phase_gate_requires_matching_phase | automated tests (suite 746 passed, 0 failed) | Checked in code, shipped data and headless tests. |
| REQ-032 | Build combos. | **IMPLEMENTED** |  |  | Combo, FluxSim._combo_up, RunResult.compute_grade, COMBO |  | code inspection | Checked in code, shipped data and headless tests. Combo grows from sparks, gate passes, shatters and near misses (FluxSim._combo_up); level combo_target feeds the grade (RunResult.compute_grade); probe: COMBO_STEP events in all 520 solution runs. |
| REQ-033 | Avoid collisions. | **IMPLEMENTED** |  |  | FluxSim._collide, Zen | test_barrier_kills_and_hop_avoids, test_shield_absorbs_one_hit | automated tests (suite 746 passed, 0 failed); level validator 520/520 | Checked in code, shipped data and headless tests. |
| REQ-034 | Pass through special gates. | **IMPLEMENTED** |  |  | Special, GATE | test_phase_gate_requires_matching_phase, test_form_gate_switches_tap_meaning, test_pulse_gate_open_closed_cycle | automated tests (suite 746 passed, 0 failed) | Checked in code, shipped data and headless tests. |
| REQ-035 | Maximise score. | **IMPLEMENTED** |  |  | Score, Overdrive, FluxSim._add_score, RunResult.compute_stars, LeaderboardService, LocalLeaderboardBackend |  | code inspection | Online boards need a hosted backend, which does not exist. Score with combo/Overdrive multipliers (FluxSim._add_score/_multiplier); per-level score_target for the 2nd star (RunResult.compute_stars); bests per level/mode and local boards (LeaderboardService, LocalLeaderboardBackend). |
| REQ-036 | Complete per-level objectives. | **IMPLEMENTED** |  |  | Objectives, DifficultyModel._choose_objective, FluxSim._complete, objective_met(), FailReason, OBJECTIVE | test_validator_detects_missing_objective | automated tests (suite 746 passed, 0 failed) | Boss 'survive' acts as reach_end. Collect-objective failure confirmed only by a scratch probe (status_probes/batch1v), no repo test. |
| REQ-037 | Perfect runs. | **IMPLEMENTED** |  |  | FluxSim.is_perfect, PERFECT, Perfect, Run | test_run_result_stars_and_grades, test_strict_rule_fails_on_missed_spark | automated tests (suite 746 passed, 0 failed) | Checked in code, shipped data and headless tests. |
| REQ-038 | The same input turns into very different behaviours as levels progress. | **IMPLEMENTED** |  |  | FluxSim._change_form, FORM, L1, L53, L157, L209 | test_form_gate_switches_tap_meaning, test_three_lane_ping_pong_direction | automated tests (suite 746 passed, 0 failed) | Checked in code, shipped data and headless tests. |
| REQ-039 | Simple to learn, hard to master; systems deepen gradually. | **PARTIAL** | curve.json | curve.json | Designed, DifficultyModel | test_speed_rises_on_average_but_not_randomly | automated tests (suite 746 passed, 0 failed) | Easy-to-learn / hard-to-master not validated by human playtests. — evidence: Designed deepening: curve.json tiers tighten min tap window 420->130 ms and speed 6.5->12 m/s; 13-level chapters go intro->mastery->combination->pressure (DifficultyModel); test_speed_rises_on_average_but_not_randomly. |
| REQ-040 | Level durations: beginner 5–15 s, mid 10–30 s, advanced 20–60 s, special challenges 60–120 s. | **IMPLEMENTED** | curve.json | curve.json | LevelValidator |  | level validator 520/520 |  |

#### C. Mechanic families (combined into a new system, not copied one by one)

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-041 | Timing. | **IMPLEMENTED** | curve.json | curve.json | Every, LevelGenerator._measure_window, LevelValidator |  | level validator 520/520 | Checked in code, shipped data and headless tests. |
| REQ-042 | Lane switching. | **IMPLEMENTED** |  |  | HOP, FluxSim._tap_hop | test_hop_moves_between_lanes_smoothly, test_three_lane_ping_pong_direction | automated tests (suite 746 passed, 0 failed) | Checked in code, shipped data and headless tests. |
| REQ-043 | Tapping. | **IMPLEMENTED** |  |  | Tap, GameFlow._unhandled_input, GameplaySession.request_tap, RunReplay, MIN |  | code inspection | Checked in code, shipped data and headless tests. Tap is the only input (GameFlow._unhandled_input -> GameplaySession.request_tap, gap RunReplay.MIN_TAP_GAP_TICKS); stored solutions use 7993 hop, 2124 phase, 1246 dash, 2764 surge taps (probe). |
| REQ-044 | Dodging. | **IMPLEMENTED** |  |  | FluxSim._check_hazard | test_barrier_kills_and_hop_avoids | automated tests (suite 746 passed, 0 failed) | Checked in code, shipped data and headless tests. |
| REQ-045 | Collecting. | **IMPLEMENTED** |  |  | FluxSim._check_collect | test_spark_collection_combo_and_multiplier, test_overdrive_after_charges | automated tests (suite 746 passed, 0 failed) | Checked in code, shipped data and headless tests. |
| REQ-046 | Stacking. | **PARTIAL** | mechanics.json | mechanics.json | Only, Overdrive, FluxSim._check_collect, MAX, CoreView._update_shards |  | code inspection | No object/physical stacking mechanic; stacking is reinterpreted as charge/multiplier accumulation. — evidence: Only abstract stacking: 8 sparks stack charges into Overdrive (FluxSim._check_collect, MAX_CHARGES; CoreView._update_shards shows them), combo multiplier stacks; mechanics.json tags 'overdrive' as stacking; MAX_SHIELDS=1. |
| REQ-047 | Colour matching. | **IMPLEMENTED** |  |  | PHASE, FluxSim._apply_tap | test_phase_gate_requires_matching_phase | automated tests (suite 746 passed, 0 failed) | Checked in code, shipped data and headless tests. |
| REQ-048 | Moving platforms / moving obstacles. | **IMPLEMENTED** |  |  | Sliders, SimLevel.slider_x, SimConst.ping_pong01 | test_slider_position_is_deterministic_polynomial, test_pulse_gate_open_closed_cycle | automated tests (suite 746 passed, 0 failed) | Moving obstacles only; no rideable moving platforms. |
| REQ-049 | Momentum. | **IMPLEMENTED** |  |  | SURGE, DEFAULT, FluxSim.step, W8 | test_surge_changes_speed_with_momentum | automated tests (suite 746 passed, 0 failed) | Momentum is felt mainly in SURGE form; other forms reach target speed almost instantly. |
| REQ-050 | Physics. | **PARTIAL** | burst_pool.gd | burst_pool.gd | Kinematic, SURGE, CoreView, CPUParticles3D |  | automated tests (suite 746 passed, 0 failed) | No physics-driven gameplay (rigid bodies, bounces, forces); 'physics' is approximated kinematically. — evidence: Kinematic deterministic sim only: acceleration (SURGE_ACCEL), overlap collision tests, chain shatter; physical feel is presentation (CoreView springs, CPUParticles3D debris with gravity in burst_pool.gd); no physics bodies in gameplay. |
| REQ-051 | Risk / reward. | **IMPLEMENTED** |  |  | Prisms, LevelGenerator._maybe_place_prism, LevelValidator._check_prisms |  | level validator 520/520 | Near misses now trigger for last-moment dodges (REQ-053). Prisms (+50) sit on the lane being left just before the hazard and need a later, riskier hop (LevelGenerator._maybe_place_prism), 286 in 75 levels; LevelValidator._check_prisms proves each reachable; near-miss bonus. |
| REQ-052 | Chain reactions. | **IMPLEMENTED** |  |  | FluxSim._shatter, CHAIN, W4 | test_dash_shatters_breakable_and_chains | automated tests (suite 746 passed, 0 failed) | Checked in code, shipped data and headless tests. |
| REQ-053 | Near miss. | **IMPLEMENTED** |  |  | FluxSim._check_hazard, FLAG, SimConst, NEAR, SIM | test_late_dodge_is_a_near_miss_early_dodge_is_not, test_sim_rules.gd | automated tests (suite 746 passed, 0 failed) | Rule fixed this round: before, a near miss was geometrically impossible for lane hops. |
| REQ-054 | Precision. | **IMPLEMENTED** | curve.json | curve.json | Min |  | visual review of screenshots (Xvfb) | Checked in code, shipped data and headless tests. |
| REQ-055 | Rhythm-like timing. | **IMPLEMENTED** |  |  | Pulse, DifficultyModel, LevelGenerator | test_pulse_gate_open_closed_cycle | automated tests (suite 746 passed, 0 failed) | Bug: pulse gates appear only from L222 (W1 'pulse' chapter has none). Not phase-locked to audio; bosses play boss_bpm music. |
| REQ-056 | Destructible objects. | **IMPLEMENTED** |  |  | DASH, FluxSim._check_hazard | test_dash_shatters_breakable_and_chains | automated tests (suite 746 passed, 0 failed) | Checked in code, shipped data and headless tests. |
| REQ-057 | Portals. | **IMPLEMENTED** |  |  | Portal, FluxSim, PORTAL | test_portal_teleports_and_current_pushes | automated tests (suite 746 passed, 0 failed); level validator 520/520; visual review of screenshots (Xvfb) | Checked in code, shipped data and headless tests. |
| REQ-058 | Gravity changes. | **PARTIAL** | mechanics.json | mechanics.json | Approximated, SURGE, LIGHT |  | code inspection | No real change of gravity direction or strength; it is a weight/speed toggle plus lateral pushes. — evidence: Approximated: SURGE heavy/light changes fall speed (SURGE_HEAVY_FACTOR 1.4 / LIGHT 0.72) and 'current' entities force lateral shifts (791 in 109 levels); mechanics.json tags surge/current as gravity_changes. |
| REQ-059 | Magnetic interaction. | **IMPLEMENTED** | gameplay_view.gd | gameplay_view.gd | Magnet, FluxSim._check_pickup, SparkField.apply_magnet, Overdrive |  | code inspection | No repo unit test; a scratch probe (status_probes/batch1v) confirmed a magnet makes a far-lane spark collectable. |
| REQ-060 | Teleport. | **IMPLEMENTED** |  |  | FluxSim._teleport | test_portal_teleports_and_current_pushes | automated tests (suite 746 passed, 0 failed) | Uses the same portal entity as REQ-057. |
| REQ-061 | Temporary power states. | **IMPLEMENTED** |  |  | Timed, FluxSim, Overdrive | test_shield_absorbs_one_hit, test_overdrive_after_charges, test_dash_cooldown_denies_spam | automated tests (suite 746 passed, 0 failed) | Checked in code, shipped data and headless tests. |
| REQ-062 | Reaction chains (cascading triggers). | **IMPLEMENTED** |  |  | Cascading, FluxSim._chain_from, CHAIN | test_dash_shatters_breakable_and_chains | automated tests (suite 746 passed, 0 failed) | Only breakables cascade; the W6 'reaction_chain' chapter has no breakables (misnamed). |
| REQ-063 | Families are fused into a new original system rather than copied individually. | **IMPLEMENTED** | mechanics.json | mechanics.json | One, FluxSim |  | code inspection | Originality of the fusion is a design judgement. |
| REQ-064 | A new main idea is introduced every 10–20 levels ("same game, new trick"). | **PARTIAL** |  |  | W1, L40, W6, L14 | test_new_main_idea_every_10_to_20_levels, test_pulse_chapters_place_pulse_gates | automated tests (suite 746 passed, 0 failed) | Late chapters (master_mix, endgame_mix, final_gauntlet...) combine earlier mechanics rather than adding a new one. — evidence: 40 chapter introductions every 13 levels (data/worlds/*.json 'intro'); pulse and reaction_chain chapters fixed this round (pulse gates from W1 L40; breakable clusters in W6 L14-25); test_new_main_idea_every_10_to_20_levels, test_pulse_chapters_place_pulse_gates. |

#### D. Level system

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-065 | Minimum 500 playable levels. | **IMPLEMENTED** | game/data/levels | game/data/levels/w01..w10, validate_levels.gd |  | test_level_pipeline.gd, test_catalog_has_ten_worlds_and_520_levels, test_every_level_file_exists_and_loads | automated tests (suite 746 passed, 0 failed); level validator 520/520 | 520 campaign levels (>500). Playability is shown by replaying stored solutions, not by human play. w01_l24 needs zero taps. |
| REQ-066 | Data-driven level system. | **IMPLEMENTED** | index.json | index.json, curve.json, mechanics.json | LevelRepository.load_level, SimLevel.from_dict, WorldCatalog.load_default, DifficultyModel, CURVE, LevelValidator |  | level validator 520/520 | Levels, worlds, the curve and the mechanics are all data. The only hard-coded level id is RunController.TUTORIAL_LAST_LEVEL = "w01_l05". |
| REQ-067 | Each level stored as separate data. | **IMPLEMENTED** | game/data/levels/wNN | game/data/levels/wNN/wNN_lMM.json | One, LevelRepository.level_path, LRU | test_every_level_file_exists_and_loads | automated tests (suite 746 passed, 0 failed) | Each level is its own JSON file, loaded on demand. |
| REQ-068 | Level data contains: ID, difficulty, mechanics, speed, spawn configuration, hazards, collectibles, objective, score target, perfect target, combo target, environment, music, visual theme, unlock requirements. | **IMPLEMENTED** |  |  | Scanned, Typed, LevelValidator._check_schema |  | level validator 520/520 | Hazards and collectibles are typed entries in one 'entities' array, not separate keys. Every other field is a named key. Scanned all 520 files: none is missing id, difficulty, mechanics, speed, spawn, entities, objective, score_target, perfect_target, combo_target, environment, music, visual_theme or unlock. Typed hazards and collectibles live in 'entities'; LevelValidator._check_schema enforces the schema. |
| REQ-069 | Level generation is deterministic. | **IMPLEMENTED** | generate_levels.gd | generate_levels.gd | LevelGenerator, DetRng, FluxSim, HEAD | test_generator_is_deterministic, test_committed_data_matches_generator | automated tests (suite 746 passed, 0 failed) | Regenerating from data reproduces the committed level JSON. |
| REQ-070 | Seed-supported generation. | **IMPLEMENTED** |  |  | DifficultyModel.build_spec, DetRng | test_seed_changes_level, test_online_daily_level.gd, test_seed_is_stable_hash_of_date, test_modes.gd, test_endless_seed_is_weekly_and_deterministic | automated tests (suite 746 passed, 0 failed) | Campaign, daily and endless content all come from explicit seeds. |
| REQ-071 | Every level is playable. | **IMPLEMENTED** | validate_levels.gd | validate_levels.gd | LevelValidator._check_solution, FluxSim, GameplaySession | test_every_level_file_exists_and_loads | automated tests (suite 746 passed, 0 failed); level validator 520/520 | Shown by automated simulation only; no human played the levels on a device. w01_l24 needs zero taps (trivial but playable). |
| REQ-072 | Every level is solvable. | **IMPLEMENTED** |  |  | The, COMPLETE, AutopilotSolver | test_validator_detects_impossible_level, test_autopilot_solver_solves_independently | automated tests (suite 746 passed, 0 failed); level validator 520/520 | Every level has a re-verified solution path. The independent solver was run on only 4 levels. |
| REQ-073 | Every level is fair (unfair levels forbidden; losses feel self-inflicted). | **PARTIAL** |  |  | LevelValidator._check_windows, LevelGenerator._reserve_reaction_room |  | level validator 520/520 | Measurable fairness is enforced. Whether losses feel self-inflicted was never tested with people. Endgame tiers allow 130-150 ms windows. — evidence: LevelValidator._check_windows, _check_forced_moves (dead_end), _check_prisms; LevelGenerator._reserve_reaction_room; 520 levels with 0 unfair_window errors, worst tap window 183 ms (lead). |
| REQ-074 | Every level is testable. | **IMPLEMENTED** | game/tools | game/tools/validate_levels.gd, game/tools/capture_level.gd | GameplaySession.step_ticks | test_level_pipeline.gd | automated tests (suite 746 passed, 0 failed); level validator 520/520; visual review of screenshots (Xvfb) | Any single level can be validated, solved, replayed and screenshotted headlessly. |
| REQ-075 | Every level is reproducible. | **IMPLEMENTED** |  |  | Seeded, FluxSim, RunReplay, ReplayVerifier | test_determinism_identical_inputs_identical_state, test_sim_rules.gd, test_online_verifier.gd | automated tests (suite 746 passed, 0 failed) | The same seed gives the same level, and the same taps give the same outcome. |
| REQ-076 | Adding a new level is as easy as adding new data. | **PARTIAL** | ci.yml | ci.yml, generate_levels.gd | Loading, LevelRepository.path_for, But, DifficultyModel |  | code inspection | A hand-made level fails CI's regen diff. Adding any level changes 'total', which retunes every level, so the whole campaign must be regenerated. — evidence: Loading needs no code change (LevelRepository.path_for; the count comes from data/worlds 'levels'). But ci.yml:83 runs generate_levels.gd --check, which diffs every file against generator output, and DifficultyModel line 74 uses t=(n-1)/(total-1). |

#### E. Difficulty structure

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-077 | Difficulty does not rise randomly; it follows a designed structure. | **IMPLEMENTED** | curve.json | curve.json | Designed, DifficultyModel | test_difficulty_structure_tiers_and_specials, test_speed_rises_on_average_but_not_randomly, test_pulse_chapters_place_pulse_gates | automated tests (suite 746 passed, 0 failed) | Tap density varies within a phase with the hazard mix (not separately bounded). |
| REQ-078 | Stages: Tutorial, Early Game, Core Learning, Mechanic Expansion, Combination Mechanics, Advanced Timing, Expert, Master, Challenge, Endgame. | **IMPLEMENTED** | curve.json | curve.json | DifficultyModel.tier_for | test_difficulty_structure_tiers_and_specials | automated tests (suite 746 passed, 0 failed) | All ten stages exist as data tiers, each with its own duration band and minimum tap window. They are stored on every level ('tier'). |
| REQ-079 | Every new mechanic is first taught safely. | **PARTIAL** |  |  | Introduction, L1, HUD, Hud |  | code inspection | Slider, current and portal introductions have no dedicated teaching hint. — evidence: Introduction phase: slower density (chapter_phases.introduction density_scale 0.75), tutorial forgiveness L1-3, form gates with HUD hints (Hud form hint), pulse chapter fixed this round. |
| REQ-080 | Each mechanic follows Introduction → Mastery → Combination → High Pressure. | **PARTIAL** | curve.json | curve.json | Every, DifficultyModel | test_difficulty_structure_tiers_and_specials | automated tests (suite 746 passed, 0 failed) | The combination phase raises density/waves but does not re-introduce older mechanics explicitly. — evidence: Every chapter runs introduction (3) -> mastery (4) -> combination (4) -> high pressure (2) levels (curve.json chapter_phases, DifficultyModel); test_difficulty_structure_tiers_and_specials. |
| REQ-081 | Mechanics are later combined with older ones across the whole game (e.g. single obstacle → colour → moving → colour+moving → gravity → gravity+colour+moving). | **IMPLEMENTED** |  |  | Entity, W1, W2, W3, W6, W9 |  | code inspection | The single -> colour -> moving -> colour+moving -> current/surge -> combined order is in the data. Pulse gates join only from W5 because of the key bug. Entity types per chapter in level data: W1 A barrier, C +slider; W2 A phase_gate, C barrier+form_gate+phase_gate+slider; W3 D current+phase_gate+slider+form_gate; W6 C breakable+phase_gate+pulse_gate+form_gate; W9 D and W10 C/D use 7 hazard types. |
| REQ-082 | First world is very easy; later worlds progressively more complex. | **IMPLEMENTED** |  |  | Level, W1, W2, W3, W4, W5 |  | code inspection | W1 is objectively slow and wide-windowed. That it feels very easy was not checked with players. Level data per world (computed here): avg speed 6.86 m/s -> 11.71; avg min tap window 0.73 s -> 0.155 s (both monotonic); taps/s 0.27 -> 1.27. W1 is hop-only with 2 lanes; phase arrives in W2, 3 lanes in W3, dash in W4, surge in W5, all four forms from W6. |
| REQ-083 | Player fully learns the base mechanic within the first 20–30 levels. | **PARTIAL** | curve.json | curve.json | Tutorial, L1, HUD._update_tap_hint, L14, L27 |  | code inspection | The structure supports learning hop by L20-30, but nobody checked that players actually learn it (no playtests). — evidence: Tutorial L1-5 (forgiving L1-3, HUD._update_tap_hint on solution ticks); L1-52 are hop-only with shield at L14 and slider at L27; tier minimum windows 420/340 ms (curve.json). |
| REQ-084 | The game as a whole is not excessively hard. | **PARTIAL** | curve.json | curve.json | Tier, Zen | test_zen_never_fails | automated tests (suite 746 passed, 0 failed) | Endgame asks for about 1.27 taps/s with 133-150 ms windows. Overall difficulty was never tested with players or on a device. — evidence: Tier minimum windows go from 420 to 130 ms (curve.json); world unlocks need about 60% of stars; Zen mode never fails (test_zen_never_fails); forgiving tutorial. |

#### F. Feedback / game feel

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-085 | Every successful input produces small but high-quality feedback. | **PARTIAL** |  |  | GameplayView._handle_event, TAP, PHASE, DASH, SURGE, CoreView.hop_motion |  | code inspection | Wired for every input type. The quality of sound, haptics and motion was never judged on a device. — evidence: GameplayView._handle_event: each TAP_HOP/PHASE/DASH/SURGE moves the core (CoreView.hop_motion/phase_motion/squash), adds a camera impulse or FOV punch, and emits feedback -> GameFlow._on_feedback -> AudioService + HapticsService. |
| REQ-086 | Anticipation. | **IMPLEMENTED** |  |  | CoreView.hop_motion, ANTICIPATION, morph(), GameFlow, READY, GameplaySession |  | code inspection | Anticipation is applied to player motion and at level start. CoreView.hop_motion: a 40 ms ANTICIPATION squash, then _pending_stretch is released in update_visuals; morph() uses a 60 ms pre-squash; GameFlow READY_FIRST 0.8 s beat (GameplaySession Phase.READY); CameraRig.start_reveal. |
| REQ-087 | Squash / stretch. | **IMPLEMENTED** |  |  | CoreView.hop_motion, CoreView.squash, morph() |  | code inspection | Squash and stretch on the core for every tap verb. CoreView.hop_motion (squash, then stretch along the hop), CoreView.squash(axis) on dash and surge, morph() shrink then pop; the spring scale (_integrate_spring) is clamped to 0.45-1.7. |
| REQ-088 | Scale punch. | **IMPLEMENTED** |  |  | CoreView.punch, GameplayView._handle_event, HUD._punch_score, TRANS, CompleteOverlay._play_sequence, RewardOverlay |  | code inspection | Scale punches on the core, the HUD and the result cards. CoreView.punch on spark, prism and pickup (GameplayView._handle_event); HUD._punch_score (1.06) and _punch_combo (1.18 then TRANS_BACK); CompleteOverlay._play_sequence star 1.25 pop; RewardOverlay cell pop 1.06. |
| REQ-089 | Rotation. | **IMPLEMENTED** |  |  | CoreView.update_visuals, CameraRig.follow, W1 |  | code inspection | Rotation on the core, the camera and the backdrop. CoreView.update_visuals spins the body per form (rate scales with speed, x0.3 under reduce_motion), wobbles the ring and orbits the charge shards (_update_shards); CameraRig.follow rolls the camera on impulse; the W1 turbine silhouette rotates. |
| REQ-090 | Elastic easing. | **IMPLEMENTED** |  |  | CoreView, SPRING, CameraRig, HUD, CompleteOverlay, TRANS |  | code inspection | Underdamped springs and back-easing tweens. CoreView SPRING_K 300 / SPRING_D 18 (critical damping is about 34.6, so it overshoots); CameraRig impulse spring 140 / 18 (critical about 23.7); HUD combo and CompleteOverlay stars use TRANS_BACK; UiToggle uses TRANS_BACK. |
| REQ-091 | Particles. | **IMPLEMENTED** | burst_pool.gd | burst_pool.gd | CPUParticles3D, GameplayView._setup_atmosphere |  | code inspection | Pooled, budgeted particle effects. On the Low preset the amounts are 40% and there are no ambient motes. |
| REQ-092 | Glow. | **IMPLEMENTED** | glow_sprite.gd | glow_sprite.gd, core.gd | CoreView.halo, HDR, Environment, GameplayView._apply_environment |  | code inspection | Only energy glows, per ART_DIRECTION. |
| REQ-093 | Bloom. | **IMPLEMENTED** |  |  | GameplayView._apply_environment, AgX, GameplayView.set_quality, GameFlow._apply_quality, Low | test_quality_flags_survive_world_changes | automated tests (suite 746 passed, 0 failed) | HDR bloom only above threshold 1.0 (only energy glows). |
| REQ-094 | Trails. | **IMPLEMENTED** | trail_ribbon.gd | trail_ribbon.gd, trail.gd | GameplayView._update_frame |  | code inspection | An energy trail ribbon that cosmetics can skin. |
| REQ-095 | Screen shake. | **IMPLEMENTED** |  |  | CameraRig.add_trauma, MAX, TRAUMA, FAIL, HIT, SHATTER |  | code inspection | Capped, trauma-based screen shake that respects accessibility settings. CameraRig.add_trauma (shake = trauma^2 * MAX_SHAKE 0.16 * shake_scale, TRAUMA_DECAY 2.4); used on FAIL 0.6, HIT_SHIELDED 0.35, SHATTER 0.12, ZEN_BUMP 0.15; shake_scale is 0.2 under reduce_motion. |
| REQ-096 | Impact flash. | **IMPLEMENTED** | post_fx.gd | post_fx.gd | GameplayView.edge_tint, FAILURE, FAIL, ACCENT, COMPLETE, EntityView.flash |  | code inspection | Impact and event flashes are present. The edge tint needs post_fx, which is off on Low. |
| REQ-097 | Hit stop. | **IMPLEMENTED** |  |  | GameplaySession._process, GameplayView.hit_stop, SHATTER, CHAIN, HIT, FAIL |  | code inspection | Hit stop pauses the simulation clock only; it never changes the tick-level outcome. GameplaySession._process returns early while hit_stop > 0 (ticks pause); GameplayView.hit_stop: SHATTER 30 ms, CHAIN 15 ms, HIT_SHIELDED 60 ms, FAIL 90 ms (halved under reduce_motion). |
| REQ-098 | Slow-motion micro effect. | **IMPLEMENTED** |  |  | GameplayView.slow_motion, NEAR, COMPLETE, GameplaySession |  | code inspection | A micro slow-motion effect. GameplayView.slow_motion(0.75, 0.08) on NEAR_MISS at combo >= 10 (skipped under reduce_motion); COMPLETE sets session.time_scale 0.4; GameplaySession scales _accum by time_scale. |
| REQ-099 | Combo burst. | **IMPLEMENTED** |  |  | COMBO, BurstPool, HUD._punch_combo, OVERDRIVE | test_feel_audio_service.gd, test_combo_shimmer_layer_only_at_high_combo | automated tests (suite 746 passed, 0 failed) | Combo bursts appear visually, in the HUD and in the audio. |
| REQ-100 | Camera impulse. | **IMPLEMENTED** |  |  | CameraRig.impulse, follow(), TAP, HOP, CURRENT, CameraRig.fov_punch |  | code inspection | Directional camera impulses and FOV kicks. CameraRig.impulse with spring return in follow(); TAP_HOP leans by HOP_LEAN 0.15 toward the hop, CURRENT pushes; CameraRig.fov_punch on TAP_DASH (4) and heavy TAP_SURGE (3). |
| REQ-101 | Dynamic lighting. | **IMPLEMENTED** |  |  | CoreView, OmniLight3D, DirectionalLight3D, GameplayView.apply_world, CoreView.set_light_enabled |  | code inspection | A dynamic core light. It is off on Low, which auto-detect picks for phones with fewer than 8 cores, and in battery saver. CoreView OmniLight3D (light_energy rises with combo) follows the core and lights nearby hazards; per-world DirectionalLight3D key (GameplayView.apply_world); CoreView.set_light_enabled from the quality flag dynamic_light. |
| REQ-102 | Controlled chromatic-like effect. | **IMPLEMENTED** | post_fx.gd | post_fx.gd | RGB, GameplayView, FAIL, OVERDRIVE |  | code inspection | A controlled chromatic split, reserved for fail and overdrive. Off on Low. |
| REQ-103 | Distortion where appropriate. | **IMPLEMENTED** | post_fx.gd | post_fx.gd | UV, GameplayView.shockwave, FORM, OVERDRIVE, COMPLETE |  | code inspection | Distortion is used only on state changes. Off on Low. |
| REQ-104 | No effect spam; feedback stays readable. | **PARTIAL** |  |  | Budgets, BurstPool, CameraRig, MAX | test_burst_of_events_is_throttled, test_global_floor_across_kinds, test_polyphony_limit_and_voice_stealing | automated tests (suite 746 passed, 0 failed) | Anti-spam limits are enforced. Readability was judged only from static Xvfb screenshots, never in motion, on a device, or with players. — evidence: Budgets in code: fixed BurstPool amounts and pool sizes, CameraRig MAX_SHAKE, chroma only on fail and overdrive; haptics throttling (test_burst_of_events_is_throttled, test_global_floor_across_kinds); audio polyphony cap (test_polyphony_limit_and_voice_stealing). |
| REQ-105 | Feedback chain TAP → movement → sound → haptic → visual impact → score feedback. | **PARTIAL** |  |  | Tap, GameplaySession.request_tap, FluxSim, TAP, GameplayView._handle_event, GameFlow._on_feedback | test_on_feedback_connects_to_gameplay_view_signal | automated tests (suite 746 passed, 0 failed) | Haptics were never felt on hardware. A plain tap has no visual-impact or score step: bursts and score punches fire later, on collect, gate or shatter events. — evidence: Tap -> GameplaySession.request_tap -> FluxSim TAP_* event -> GameplayView._handle_event (core motion, camera) -> feedback -> GameFlow._on_feedback -> audio.on_feedback + haptics.on_feedback; HUD._punch_score when the score rises; test_on_feedback_connects_to_gameplay_view_signal. |

#### G. Graphics & visual identity

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-106 | Very high graphical quality; premium mobile look. | **PARTIAL** | game/assets | game/assets/shaders | PBR, ViewKit, STRUCTURE, HDR, AgX, The |  | visual review of screenshots (Xvfb) | Clean and consistent, but not premium: primitive geometry, no textures, simple backdrops. Never seen on a phone. — evidence: A coherent stylised 3D look: 11 custom shaders (game/assets/shaders), PBR presets (ViewKit.STRUCTURE_PRESETS), HDR glow, AgX. The renders in lead/worlds_final and lead/ribs show clean but simple chamfered-box hazards and flat silhouettes. |
| REQ-107 | Stylized high-end 3D / 2.5D. | **PARTIAL** |  |  | Real, Node3D, Camera3D, DirectionalLight3D, MeshFactory |  | visual review of screenshots (Xvfb) | It is stylised 3D, but not 'high-end': low geometric detail and mostly primitive forms. — evidence: Real-time 3D (Node3D, Camera3D, DirectionalLight3D) with stylised procedural meshes from MeshFactory (chamfered boxes, rib profiles, silhouettes) and stylised shaders; see the lead/worlds_final renders. |
| REQ-108 | High-quality materials (PBR approach where needed). | **PARTIAL** | glass.gd | glass.gd | ViewKit, STRUCTURE, StandardMaterial3D, Renders |  | visual review of screenshots (Xvfb) | There is a PBR approach, but surfaces have no texture, normal or roughness maps. In the renders they read as plain matte colours, not high-quality materials. Never seen on a device. — evidence: ViewKit.STRUCTURE_PRESETS gives each StandardMaterial3D its roughness, metallic, specular and clearcoat (anodised, steel, stone, ice, lacquer, crystal...); glass.gdshader with fresnel; sky radiance for metals. Renders show flat single-colour hazards and ribs. |
| REQ-109 | Realistic but stylized lighting. | **IMPLEMENTED** |  |  | GameplayView.apply_world, DirectionalLight3D, OmniLight3D, AgX |  | visual review of screenshots (Xvfb) | Physically based lighting with a per-world style. There is no GI or SSAO; ambient light is a flat colour. Never checked on a device display. GameplayView.apply_world/_apply_environment: a per-world DirectionalLight3D key (colour, energy and angle from world art data), a flat ambient colour, the core OmniLight3D as a local light, sky radiance reflections, AgX tonemap; the result is visible in the lead/worlds_final renders. |
| REQ-110 | Quality shaders. | **IMPLEMENTED** | game/assets | game/assets/shaders, noise.gd |  |  | code inspection | Purpose-built shaders. GPU cost was never profiled on a mobile device. |
| REQ-111 | Volumetric-looking effects. | **PARTIAL** | glow_sprite.gd | glow_sprite.gd, ART_DIRECTION.md | Only, FOG |  | code inspection | No light shafts, volumetric fog or god rays. Glow halos and depth fog are the only stand-ins for volumetric-looking effects. — evidence: Only soft additive halos (glow_sprite.gdshader, ring pulses), the sky 'flux sink' glow and depth fog (FOG_MODE_DEPTH). ART_DIRECTION.md section 6 explicitly rules out volumetric fog. |
| REQ-112 | Emissive materials. | **IMPLEMENTED** | core.gd | core.gd, spark.gd, membrane.gd, floor.gd | HDR, ViewKit, Matter, ART |  | code inspection | Emissive energy materials. |
| REQ-113 | Dynamic shadows. | **PARTIAL** | presets.json | presets.json | GameplayView, DirectionalLight3D, CoreView, ON |  | visual review of screenshots (Xvfb) | Shadows exist, but are off by default on every phone: auto-detect caps mobile at Medium, which has no shadows. Only a manual High/Ultra choice enables them. Ribs and floor cast none. — evidence: GameplayView key DirectionalLight3D shadows (set_quality(shadows)); the core body casts a shadow (CoreView cast_shadow ON); visible in the lead renders. data/quality/presets.json: shadows true only on high/ultra; auto_detect.mobile picks at most 'medium'. |
| REQ-114 | Reflections where needed. | **PARTIAL** |  |  | Environment.reflected_light_source, SKY, GameplayView._apply_environment |  | code inspection | No screen-space, planar or probe reflections (e.g. on the floor or on ice and water worlds). Only a low-res sky radiance reflection exists. — evidence: Environment.reflected_light_source = SKY with radiance_size 32 (GameplayView._apply_environment) gives metals a sky reflection; glass and the core use fresnel terms only. |
| REQ-115 | Environment ambience. | **IMPLEMENTED** |  |  | GameplayView._setup_atmosphere |  | code inspection | Each world has its own visual and audio ambience. Ambient motes are off on Low. GameplayView._setup_atmosphere: per-world motes (embers, bubbles, snow, sand, stars, puffs, sprinkles, dust); floor caustics; the sky sink; depth fog; the turbine silhouette; per-world music loops (assets/audio/music/<world>.wav, plus _hi and _boss versions). |
| REQ-116 | Polished UI animations. | **PARTIAL** |  |  | UiScreen.transition_in, UiButton, CompleteOverlay._play_sequence, RewardOverlay, HUD, UiToggle |  | code inspection | The animations are implemented, but nobody saw them in motion (only static Xvfb screenshots, no device and no video). Their polish is unverified. — evidence: UiScreen.transition_in/out (24 px slide + fade, cubic); UiButton press 0.96 and release overshoot; CompleteOverlay._play_sequence (star pop + count-up); RewardOverlay pops; HUD punches; UiToggle TRANS_BACK; reduce_motion is respected. |
| REQ-117 | Premium typography. | **IMPLEMENTED** | game/assets | game/assets/fonts | Outfit, OFL, Turkish, UiFonts, UiTokens, H1 |  | visual review of screenshots (Xvfb) | One quality geometric sans family with a defined type scale. |
| REQ-118 | Depth and parallax. | **IMPLEMENTED** |  |  | GameplayView, SILHOUETTE, RIB, CameraRig |  | code inspection | Layered depth with parallax. GameplayView: far silhouette at SILHOUETTE_DISTANCE 150 with SILHOUETTE_PARALLAX 0.03; ribs every 7 m (RIB_SPACING); scrolling floor seams; depth fog 28-115 m; sky gradient; CameraRig lateral lerp (_lateral) adds parallax. |
| REQ-119 | Camera movement. | **IMPLEMENTED** |  |  | CameraRig.follow, LOOK, FOV |  | code inspection | A dynamic follow camera. CameraRig.follow: lateral follow, LOOK_AHEAD, start_reveal sweep (offset + FOV), spring impulses, fov_punch, trauma shake, impulse roll. |
| REQ-120 | Polished post-processing. | **IMPLEMENTED** | presets.json | presets.json, post_fx.gd | GameplayView._apply_environment, AgX, HDR, MSAA, FX |  | visual review of screenshots (Xvfb) | Event effects only on fail/overdrive/perfect; glow honours the quality preset. |
| REQ-121 | Vivid but controlled colour palette. | **IMPLEMENTED** | palette.gd | palette.gd | World, W4, Cloud, Factory |  | visual review of screenshots (Xvfb) | ART_DIRECTION's saturation <= 0.45 rule is exceeded numerically by very dark colours (e.g. Deep Ocean s 0.72 at v 0.21), and W4 exceeds the value cap. No test enforces the rule. |
| REQ-122 | Every world has its own visual identity. | **IMPLEMENTED** |  |  | MeshFactory.rib |  | visual review of screenshots (Xvfb) | Committed in d107839. Hazard blocks look the same in every world, by design. data/worlds/w01..w10 'art' blocks: each world has its own rib_profile (gate, facet, truss, arch, hex, lattice, icicle, monolith, ring, candy; MeshFactory.rib), silhouette, sky, fog, floor, key light, atmosphere and music; renders in lead/worlds_final and lead/ribs. |
| REQ-123 | All assets original; no copyrighted assets. | **IMPLEMENTED** | tools/audio | tools/audio/synth_bank.py, mesh_factory.gd | Audio, IconGlyph, The, Outfit |  | code inspection | Everything is original or procedural except the OFL Outfit font. Legacy web files (php/tsx) in the repo root are not game assets. |
| REQ-124 | Any open-source asset is license-checked. | **IMPLEMENTED** | game/assets | game/assets/LICENSES.json, tools/ci/license_check.py, game/assets/fonts/OFL.txt, .github/workflows/ci.yml |  |  | code inspection | The only open-source asset (Outfit, OFL-1.1) is recorded and license-checked. |
| REQ-125 | Procedural / original art wherever possible. | **IMPLEMENTED** | noise.gd | noise.gd, synth_bank.py | MeshFactory, IconGlyph, No, ViewKit, GradientTexture2D |  | code inspection | Procedural and original art throughout. |
| REQ-126 | Distinctive visual language recognisable from a single screenshot. | **PARTIAL** |  |  | ART, HDR, WARNING, Consistent |  | visual review of screenshots (Xvfb) | Consistent, but recognisability was never validated. A glowing orb in a lane of orange blocks is close to genre conventions. — evidence: ART_DIRECTION rules are applied in code: only energy glows (unshaded HDR core vs lit matter), WARNING-orange chamfered hazards, a ribbed shaft, a different core silhouette per form. Consistent across the 10 world renders (lead/worlds_final). |
| REQ-127 | Signature elements: core look, energy trail, level transition, combo explosion, world transitions, collectible animation, fail effect, perfect effect. | **IMPLEMENTED** | core_view.gd | core_view.gd, trail_ribbon.gd | Core, CameraRig.start_reveal, GameFlow._world_transition, GameplayView._on_frame_events |  | code inspection | Judged from code and screenshots; motion not reviewed on a device. |

#### H. Controls

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-128 | One touch; main control is TAP. | **IMPLEMENTED** |  |  | GameFlow._unhandled_input, InputEventScreenTouch, Space, GameplaySession.request_tap, FluxSim.step |  | code inspection | One-touch tap control. GameFlow._unhandled_input accepts only InputEventScreenTouch presses (mouse is emulated as touch) or Space, and calls GameplaySession.request_tap; FluxSim.step(tap) takes a single boolean per tick. |
| REQ-129 | Hold / swipe / drag only optionally in later sections, never complicating the start. | **IMPLEMENTED** | mechanics.json | mechanics.json | No, GameFlow._unhandled_input |  | code inspection | Tap-only for the whole game, so the start is never complicated. |
| REQ-130 | Large touch areas. | **IMPLEMENTED** |  |  | UiTokens, MIN, BUTTON, ICON, GameFlow._unhandled_input | test_volume_sliders_meet_touch_target | automated tests (suite 746 passed, 0 failed) | Not measured on a device. |
| REQ-131 | Reduced accidental touches. | **IMPLEMENTED** |  |  | UiToggle, CompleteOverlay._set_actions_live, UiScreen.transition_out | test_toggle_flips_once_per_physical_tap, test_result_actions_take_no_taps_during_the_sequence, test_leaving_overlay_releases_input_immediately | automated tests (suite 746 passed, 0 failed) | No device test. |
| REQ-132 | Minimum input latency. | **PARTIAL** |  |  | Hz, GameplaySession._next_tap |  | code inspection | No latency was measured on a device. The view interpolates between the previous and current tick, which adds up to one tick of display lag. — evidence: project.godot input_devices/buffering/agile_event_flushing=true; taps are queued in _unhandled_input and consumed on the next 60 Hz tick (GameplaySession._next_tap, at most 16.7 ms of quantisation); no input smoothing. |

#### I. Combo, grades, stars

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-133 | Combo raises score multiplier, visual intensity, particles, sound layering, haptic response and collectible bonus. | **IMPLEMENTED** |  |  | SimConst.combo_multiplier, FluxSim._add_score, CoreView, COMBO, AudioService.play_sfx | test_spark_collection_combo_and_multiplier | automated tests (suite 746 passed, 0 failed) | Collectible bonus = multiplier on spark score. Music stem (set_combo) only updates on combo steps, so it lags after a break. Feel not checked on a device. |
| REQ-134 | Combo system is not overly complex. | **IMPLEMENTED** | hud.gd | hud.gd | Combo, SimConst.combo_multiplier, FluxSim._combo_break, Overdrive, HUD |  | code inspection | Simplicity judged from code/design only; no player testing. |
| REQ-135 | Per-level performance grades Normal / Good / Great / Perfect. | **IMPLEMENTED** | complete_overlay.gd | complete_overlay.gd | RunResult, Grade, NORMAL, GOOD, GREAT, PERFECT | test_sim_rules.gd::test_run_result_stars_and_grades | automated tests (suite 746 passed, 0 failed) | Grade is per run on the result card; a best grade per level is not stored or shown in level select. |
| REQ-136 | Perfect is very hard but learnable. | **PARTIAL** |  |  | Perfect, FluxSim.is_perfect, LevelValidator._check_solution |  | level validator 520/520 | 'Very hard' is unmeasured: no human playtests or perfect-rate data; only achievability is proven. — evidence: Perfect = no damage + every spark (FluxSim.is_perfect). LevelValidator._check_solution errors unless each level's stored solution is perfect (520 validated, 0 failed per lead); levels are deterministic, so they are learnable. |
| REQ-137 | Perfect completion grants star, badge, bonus currency and cosmetic unlock progress. | **IMPLEMENTED** |  |  | Perfect, RunResult.compute_stars, RewardEngine.compute_level_reward, CosmeticService.check_auto_unlocks | test_first_perfect_gives_gems_and_badge_only_once, test_auto_unlock_by_perfects | automated tests (suite 746 passed, 0 failed) | Gems only on a level's first perfect; badge once per difficulty tier, not on every perfect run. |
| REQ-138 | 1–3 stars per level (1 = cleared, 2 = high score, 3 = perfect). | **IMPLEMENTED** |  |  | RunResult.compute_stars, LevelValidator._check_solution | test_run_result_stars_and_grades | automated tests (suite 746 passed, 0 failed); level validator 520/520 | Stars are additive: a perfect run under the score target would get 2 stars. |
| REQ-139 | Star totals unlock worlds, cosmetics and challenges. | **IMPLEMENTED** | cosmetics.json | cosmetics.json, modes.json | Worlds, ProgressionService.is_world_unlocked, Time, Attack, ModeCatalog.is_unlocked | test_star_total_unlocks_the_time_attack_challenge | automated tests (suite 746 passed, 0 failed) |  |

#### J. Economy, monetization & ethics

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-140 | No crypto, blockchain, Web3 or NFT. | **IMPLEMENTED** | player_profile.gd | player_profile.gd, analytics_service.gd | Search, Godot, Crypto, EconomyService, CURRENCIES |  | code inspection | The game has none. The unrelated legacy web site at the repo root (src/components/Hero.tsx, About.tsx) still mentions blockchain/Ethereum. |
| REQ-141 | Currencies: Coins (normal gameplay) and Gems (rare rewards). | **IMPLEMENTED** | economy.json | economy.json, reward_tables.json | EconomyService, CURRENCIES | test_economy_service.gd, test_rewards_level.gd | automated tests (suite 746 passed, 0 failed) |  |
| REQ-142 | No pay-to-win; progress possible with skill alone. | **IMPLEMENTED** | products.json | products.json | Store, FluxSim | test_bundled_products_are_cosmetic_only, test_product_validation_rejects_currency_and_consumables | automated tests (suite 746 passed, 0 failed) | Revive comes from an optional rewarded ad (not sold); revived runs are not ranked. |
| REQ-143 | Monetization architecture ready. | **IMPLEMENTED** | ads_policy.json | ads_policy.json, services.gd | AdProvider, NullAdProvider, AdsService, AdsPolicy, StoreProvider, NullStoreProvider | test_platform_ads.gd, test_platform_store.gd | automated tests (suite 746 passed, 0 failed) | Architecture only: no ad/IAP SDK or store accounts, so null providers report unavailable. |
| REQ-144 | Interstitials only at natural breakpoints. | **IMPLEMENTED** |  |  | AdsService.interstitial_block_reason, GameFlow | test_interstitial_only_at_natural_breakpoints | automated tests (suite 746 passed, 0 failed) | No ad SDK, so no interstitial is ever really shown. |
| REQ-145 | Rewarded ads are optional (revive, double reward, bonus chest). | **IMPLEMENTED** |  |  | AdsService.show_rewarded, GameFlow._revive, CompleteOverlay, Daily, GameFlow._open_bonus_chest, Presenters.bonus_chest_offered | test_bonus_chest_is_optional_and_once_a_day | automated tests (suite 746 passed, 0 failed) | No ad SDK linked: NullAdProvider hides every offer in this build. |
| REQ-146 | The player is never forced to watch ads. | **IMPLEMENTED** |  |  | Rewarded, GameFlow._revive, AdsService | test_policy_data_cannot_loosen_hard_rules, test_no_interstitial_after_any_purchase | automated tests (suite 746 passed, 0 failed) | Interstitials (allowed by REQ-144) would auto-show at level end once an SDK exists; none ships. |
| REQ-147 | Premium offers are cosmetic only (Cosmetic Pack, Theme Pack, Starter Cosmetic Bundle); no gameplay advantage sold. | **IMPLEMENTED** | products.json | products.json | StoreService | test_product_validation_rejects_currency_and_consumables, test_bundled_products_are_cosmetic_only | automated tests (suite 746 passed, 0 failed) | Cannot be bought in this build (null store provider). Theme-pack items (theme_*, bg_*) do not render in game (see REQ-153). |
| REQ-148 | Data-driven reward engine with types Coins, Gems, Skin, Trail, Badge, Stars, XP. | **PARTIAL** | reward_tables.json | reward_tables.json | RewardBundle, RewardEngine | test_rewards_grant.gd, test_rewards_tables.gd | automated tests (suite 746 passed, 0 failed) | 'stars' is never granted (grant() drops it, SPEC_KEYS exclude it); Skin and Trail are one generic cosmetic type. — evidence: RewardBundle types coins/gems/xp/stars/cosmetic/badge; RewardEngine reads data/rewards/reward_tables.json (compute_level_reward, compute, bundle_from_spec, grant); skins/trails granted as 'cosmetic' ids. test_rewards_grant.gd, test_rewards_tables.gd |
| REQ-149 | No fake reward animations; rewards bound to real state. | **IMPLEMENTED** |  |  | RewardEngine.grant | test_app_flow.gd::test_first_clear_records_progress_and_grants_real_rewards, test_daily_rewards_only_first_completion | automated tests (suite 746 passed, 0 failed) |  |
| REQ-150 | No dark patterns: fake close buttons, forced ads, misleading purchases, aggressive FOMO, deceptive countdowns, hidden fees, fake rewards, notification spam, deliberately frustrating losses, rigged matchmaking, pay-to-win. | **IMPLEMENTED** |  |  | Shop, CosmeticsScreen._update_detail | test_shop_shows_price_and_shortfall_before_purchase, test_shop_says_what_an_item_changes | automated tests (suite 746 passed, 0 failed) | No human UX audit. |
| REQ-151 | Retention only through healthy mechanics (short levels, mastery, perfect, leaderboard, collection, cosmetics, daily challenge, personal best, combo mastery, achievements, world progression). | **IMPLEMENTED** | curve.json | curve.json | Retention |  | code inspection | Leaderboards are local-only (no backend). |
| REQ-152 | No predatory monetization, fear-based retention, deceptive UX, forced engagement, fake urgency or abusive notifications. | **IMPLEMENTED** |  |  | No, DailyChallengeService.tier_after, PLAY, AGAIN | test_economy_, test_online_daily_streak, test_ui_regressions | automated tests (suite 746 passed, 0 failed) |  |

#### K. Cosmetics & progression

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-153 | Many cosmetics: core skins, trails, particles, backgrounds, themes, effects, badges, frames, avatars. | **IMPLEMENTED** | cosmetics.json | cosmetics.json | GameplayView, UiTheme.apply_accent, ProfileEmblem | test_cosmetics_ | automated tests (suite 746 passed, 0 failed) |  |
| REQ-154 | Cosmetics never alter gameplay. | **IMPLEMENTED** | gameplay_session.gd | gameplay_session.gd | FluxSim, SimLevel, GameplaySession, ReplayVerifier, GameplayView.apply_cosmetics |  | code inspection |  |
| REQ-155 | Skins (Fire, Ice, Plasma, Void, Crystal …) each have quality animation, not just a recolour. | **PARTIAL** | core.gd | core.gd, cosmetics.json | CoreView.apply_skin |  | code inspection | 9 of 19 skins reuse another skin's style with new colours/speed; animation quality not reviewed on a device. — evidence: assets/shaders/core.gdshader has 10 animated styles (plasma, fire, ice, void, crystal, electric, molten, aurora, candy, nebula), picked by the cosmetics.json 'style'; CoreView.apply_skin sets style, colours and anim_speed. |
| REQ-156 | XP, player level, stars, coins, gems, achievements, daily challenges and collection systems. | **IMPLEMENTED** |  |  | ProgressionService, XP, EconomyService, AchievementService, DailyChallengeService, MissionService | test_progression_xp.gd, test_meta_achievements.gd, test_online_daily_streak.gd | automated tests (suite 746 passed, 0 failed) |  |
| REQ-157 | Unlock tree / visible "next thing to unlock". | **IMPLEMENTED** |  |  | ProgressionService.next_unlock_hint, Presenters, CosmeticService.unlock_status | test_progression_hints.gd | automated tests (suite 746 passed, 0 failed) | The next unlock is visible, but there is no full unlock-tree screen. |

#### L. Worlds & special levels

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-158 | At least 10 worlds. | **IMPLEMENTED** | index.json | index.json | ProgressionService | test_progress_summary_covers_ten_worlds | automated tests (suite 746 passed, 0 failed); level validator 520/520 |  |
| REQ-159 | 40–60 levels per world. | **IMPLEMENTED** |  |  | Each |  | level validator 520/520 | Each world JSON has levels: 52; data/levels/w01..w10 hold 52 JSON files each (520 total); validate_levels: 520 validated, 0 failed (lead fact). |
| REQ-160 | Each world has unique lighting, materials, hazards, music, particles and boss/challenge mechanic. | **PARTIAL** |  |  | World, WorldTheme |  | code inspection | Lighting, materials, music, atmosphere and set pieces differ per world (data/worlds/*.json); hazard types themselves are shared across worlds. — evidence: World JSON art per world (key_light, ambient, rib_material, atmosphere particles: dust, glitter, embers, snow…, silhouette), own music + boss + hi stems (assets/audio/music), boss/challenge spec; read by WorldTheme. |
| REQ-161 | Special end-of-world levels that differ from normal levels (rotating machine, escape sequence, fast obstacle field, pattern recognition, chain-reaction puzzle, survival sequence). | **IMPLEMENTED** |  |  | Boss, L52, L26, LevelGenerator._pick_hazard, DifficultyModel._apply_special | test_boss_set_pieces_shape_their_levels, test_level_content.gd | automated tests (suite 746 passed, 0 failed) | The rotating machine is expressed by synchronised slider blades, not by rotating geometry. |
| REQ-162 | World data drives theme, background, hazards, palette, audio, environment, lighting, particles, mechanics. | **IMPLEMENTED** | tools/audio | tools/audio/synth_bank.py | World, WorldTheme, WorldTheme.bpm, DifficultyModel |  | code inspection | Runtime music files are mapped by world id in data/audio/sound_bank.json. |

#### M. Game modes

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-163 | CLASSIC mode playable at launch. | **IMPLEMENTED** | modes.json | modes.json | Main, PLAY, GameFlow._play_campaign, RunController.prepare | test_first_clear_records_progress_and_grants_real_rewards | automated tests (suite 746 passed, 0 failed) | Played only in headless/Xvfb runs; no human device playtest. |
| REQ-164 | Architecture supports ENDLESS. | **IMPLEMENTED** | modes.json | modes.json | EndlessStreamer, RunController.prepare | test_endless_stream_is_deterministic_and_ordered, test_endless_streams_and_records_best_distance | automated tests (suite 746 passed, 0 failed) |  |
| REQ-165 | Architecture supports TIME ATTACK. | **IMPLEMENTED** | modes.json | modes.json | FluxSim | test_time_limit_completes_the_run, test_time_attack_replay_verifies_on_rebuilt_course | automated tests (suite 746 passed, 0 failed) | The mode text 'Clear it as fast as you can' does not match the 60 s highest-score rule. |
| REQ-166 | Architecture supports DAILY CHALLENGE. | **IMPLEMENTED** | modes.json | modes.json | DailyChallengeService.level_for, RunController | test_daily_rewards_only_first_completion, test_online_daily_level.gd | automated tests (suite 746 passed, 0 failed) |  |
| REQ-167 | Architecture supports PERFECT RUN. | **IMPLEMENTED** | modes.json | modes.json | FluxSim | test_strict_rule_fails_on_missed_spark | automated tests (suite 746 passed, 0 failed) |  |
| REQ-168 | Architecture supports ZEN MODE. | **IMPLEMENTED** | modes.json | modes.json | FluxSim | test_zen_never_fails, test_modifiers_carry_mode_and_rules | automated tests (suite 746 passed, 0 failed) |  |
| REQ-169 | Architecture supports HARD MODE. | **IMPLEMENTED** | modes.json | modes.json | FluxSim | test_catalog_has_all_modes_and_validates, test_unlock_rules_are_honest_thresholds | automated tests (suite 746 passed, 0 failed) | No dedicated hard-mode run test beyond modifiers. |
| REQ-170 | Architecture supports BOSS RUSH. | **IMPLEMENTED** | modes.json | modes.json | RunController.boss_rush_queue, ReplayVerifier, ModeCatalog | test_boss_rush_needs_beaten_bosses | automated tests (suite 746 passed, 0 failed) | Only the gating is tested (no bosses -> no rush); a full rush run is not. |

#### N. Daily / weekly / achievements

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-171 | New deterministic daily challenge every day (server-side or controlled deterministic seed). | **IMPLEMENTED** |  |  | DailyChallengeService.seed_for, DetRng.hash_string, UTC | test_seed_is_stable_hash_of_date, test_same_date_gives_identical_level_json, test_daily_levels_pass_validator | automated tests (suite 746 passed, 0 failed); level validator 520/520 |  |
| REQ-172 | Daily result shows score, rank and reward. | **IMPLEMENTED** |  |  | Daily, GameFlow._daily_rank_text, CompleteOverlay, DailyChallengeService.rank_text_local | test_daily_result_card_shows_the_rank, test_daily_rank_uses_the_service_total | automated tests (suite 746 passed, 0 failed) | Rank is among the player's own daily scores (no hosted global board). |
| REQ-173 | Streak system with Daily 1/2/3 bonuses; missing a day is not punitive. | **IMPLEMENTED** | reward_tables.json | reward_tables.json | DailyChallengeService._advance_streak | test_missed_day_decays_tier_gently, test_several_missed_days_never_go_below_one | automated tests (suite 746 passed, 0 failed) | A missed day still costs one tier (gentle decay, never a reset). |
| REQ-174 | Daily missions (play 5 levels, get 3 perfects, collect 100 energy, reach x10 combo, finish without damage …). | **IMPLEMENTED** | missions.json | missions.json | MissionService | test_required_templates_present, test_meta_missions.gd | automated tests (suite 746 passed, 0 failed) |  |
| REQ-175 | Weekly missions with longer-term goals. | **IMPLEMENTED** |  |  | ISO | test_weekly_resets_on_monday, test_meta_missions_schedule.gd, test_meta_missions.gd | automated tests (suite 746 passed, 0 failed) |  |
| REQ-176 | At least 50 achievements (First Perfect, 100 Collectibles, 10 Combo, 50/100 Levels, No Miss, Perfect World, Fast Clear, High Combo, Daily Master, Boss Master …). | **IMPLEMENTED** | achievements.json | achievements.json |  | test_shipped_definitions_have_at_least_55_entries, test_required_examples_present | automated tests (suite 746 passed, 0 failed) |  |

#### O. Online, leaderboard, anti-cheat, offline

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-177 | Global leaderboard architecture with Daily / Weekly / All Time boards. | **PARTIAL** | game/server | game/server/README.md | LeaderboardService, LocalLeaderboardBackend, HttpLeaderboardBackend, HTTP | test_online_leaderboard_service.gd, test_online_leaderboard_backends.gd | automated tests (suite 746 passed, 0 failed) | No hosted server stores or ranks global scores; the HTTP backend is off (empty base_url), so boards are local-only. — evidence: LeaderboardService boards daily/weekly/alltime/level (board_ids_for), LocalLeaderboardBackend + HttpLeaderboardBackend, offline queue; HTTP contract in game/server/README.md; test_online_leaderboard_service.gd, test_online_leaderboard_backends.gd. |
| REQ-178 | Server validation against score manipulation; the client is not trusted. | **PARTIAL** | game/server | game/server/verify_replay.gd | ReplayVerifier, CLI | test_rejects_tampered_score, test_rejects_impossible_tap_rate, test_cli_campaign_valid_and_tampered | automated tests (suite 746 passed, 0 failed) | Verification logic only: no deployed server runs it, so no score is validated server-side in this build. — evidence: ReplayVerifier (src/server_shared) re-simulates the replay and ignores the claimed score; CLI game/server/verify_replay.gd with fail-safe exit codes; test_rejects_tampered_score, test_rejects_impossible_tap_rate, test_cli_campaign_valid_and_tampered. |
| REQ-179 | Server-backed checks for leaderboard scores, daily scores, reward claims and suspicious progression. | **PARTIAL** |  |  | ReplayVerifier.verify, IntegrityMonitor | test_online_reward_claims.gd | automated tests (suite 746 passed, 0 failed) | Not server-backed (no hosted backend); suspicious-progression checks are client-side only. — evidence: ReplayVerifier.verify covers leaderboard and daily scores (daily date window); verify_reward_claim rejects duplicate/unverified daily claims and impossible currency deltas (test_online_reward_claims.gd); IntegrityMonitor flags ledger anomalies. |
| REQ-180 | Core gameplay works without internet. | **IMPLEMENTED** |  |  | Gameplay, HttpLeaderboardBackend | test_boot_builds_every_service, test_first_clear_records_progress_and_grants_real_rewards | automated tests (suite 746 passed, 0 failed) | No airplane-mode test on a device. |
| REQ-181 | Internet features (leaderboard, cloud save, analytics sync, daily challenge, remote config) degrade gracefully offline. | **PARTIAL** |  |  | Leaderboard, HTTP | test_offline_queues_then_flushes_when_transport_recovers, test_http_sink_queues_offline_then_flushes, test_fetch_offline_keeps_cached_values | automated tests (suite 746 passed, 0 failed) | Cloud save does not exist, so its offline behaviour is missing. — evidence: Leaderboard queues offline and flushes on reconnect (test_offline_queues_then_flushes_when_transport_recovers); analytics HTTP sink queues (test_http_sink_queues_offline_then_flushes); remote config keeps its cache (test_fetch_offline_keeps_cached_values); daily is local. |
| REQ-182 | Cloud save architecture. | **NOT_IMPLEMENTED** | save_storage.gd | save_storage.gd | No, SaveStorage, FileSaveStorage, MemorySaveStorage |  | code inspection | Missing: cloud provider interface, sync/conflict merge, account binding and a backend. — evidence: No cloud-save code: no cloud provider, sync or merge in src (search for cloud/sync); only the generic SaveStorage interface (src/save/save_storage.gd) with FileSaveStorage and MemorySaveStorage. |

#### P. Save & settings

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-183 | Local save of progress, settings, unlocks, currency, completed levels, stars, achievements. | **IMPLEMENTED** | services.gd | services.gd | PlayerProfile.to_dict, SaveService, FileSaveStorage | test_round_trip_preserves_every_profile_field, test_settings_survive_save_roundtrip | automated tests (suite 746 passed, 0 failed) |  |
| REQ-184 | Corrupted save recovery. | **IMPLEMENTED** |  |  | SaveService, SHA | test_save_recovery.gd, test_file_storage_recovers_from_truncated_main_on_disk | automated tests (suite 746 passed, 0 failed) |  |
| REQ-185 | Versioned save structure with migrations. | **IMPLEMENTED** |  |  | Envelope, SaveMigrations | test_v0_to_v1_shape, test_unsupported_version_returns_empty, test_migrates_enveloped_v0_save, test_future_main_is_preserved_and_backup_used | automated tests (suite 746 passed, 0 failed) | Only one migration step (v0->v1) exists so far. |
| REQ-186 | Sound setting. | **IMPLEMENTED** | settings_screen.gd | settings_screen.gd | SettingsService, AudioService.play_sfx | test_settings_apply_live_to_buses, test_settings_survive_save_roundtrip | automated tests (suite 746 passed, 0 failed) |  |
| REQ-187 | Music setting. | **IMPLEMENTED** | settings_screen.gd | settings_screen.gd | AudioService | test_settings_apply_live_to_buses | automated tests (suite 746 passed, 0 failed) |  |
| REQ-188 | Haptics setting. | **IMPLEMENTED** | settings_screen.gd | settings_screen.gd | Vibration, HapticsService.play | test_opt_out_setting | automated tests (suite 746 passed, 0 failed) | Vibration itself not checked on a device. |
| REQ-189 | Notifications setting. | **IMPLEMENTED** | settings_screen.gd | settings_screen.gd | Privacy, AppServices._on_setting, NotificationService.refresh | test_opt_in_is_required, test_disabling_cancels_everything | automated tests (suite 746 passed, 0 failed) | The setting works, but with NullNotificationProvider no OS notification is delivered (no push plugin). |
| REQ-190 | Graphics quality setting. | **IMPLEMENTED** | presets.json | presets.json | Settings, Auto, Low, Medium, High, Ultra | test_manual_setting_selects_preset, test_presets_scale_up_monotonically, test_apply_to_viewport | automated tests (suite 746 passed, 0 failed) | Performance effect not measured on a device. |
| REQ-191 | Battery saver setting. | **IMPLEMENTED** | settings_screen.gd | settings_screen.gd | QualityService, FPS, HapticsService | test_battery_saver_caps_fps_and_preset, test_battery_saver_halves_amplitude | automated tests (suite 746 passed, 0 failed) | Battery savings not measured (no device). |
| REQ-192 | Language setting. | **IMPLEMENTED** |  |  | Language, Device, English, SettingsService, Localization._on_settings_changed | test_language_values, test_every_key_exists_in_both_languages | automated tests (suite 746 passed, 0 failed); visual review of screenshots (Xvfb) |  |
| REQ-193 | Restore purchases. | **PARTIAL** |  |  | Settings, Restore, GameFlow._restore_purchases, StoreService.restore_purchases | test_restore_with_scripted_provider, test_restore_with_null_provider_returns_error | automated tests (suite 746 passed, 0 failed) | Real restore BLOCKED: no IAP SDK or store accounts; the null provider always reports the store unavailable. — evidence: Settings 'Restore purchases' button -> GameFlow._restore_purchases -> StoreService.restore_purchases with a status line; test_restore_with_scripted_provider, test_restore_with_null_provider_returns_error. |

#### Q. Mobile platform

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-194 | Targets iOS and Android. | **PARTIAL** | game | game/export_presets.cfg, .github/workflows/ci.yml | Android, APK |  | Android debug export | iOS export BLOCKED (no macOS/Xcode/Apple account) and CI not observed running; Android release signing BLOCKED (no keystore). — evidence: game/export_presets.cfg has Android (com.fluxdrop.game) and iOS presets, portrait orientation; lead: signed debug APK exported and apksigner-verified; iOS export job defined in .github/workflows/ci.yml. |
| REQ-195 | Safe-area support. | **IMPLEMENTED** | safe_probe.gd | safe_probe.gd | SafeAreaContainer.current_insets, DisplayServer.get_display_safe_area, UiScreen.make_safe_root, Android, Dynamic, Island |  | code inspection | Not checked on a real device; no unit test covers it (probe only). |
| REQ-196 | Works correctly on different aspect ratios. | **IMPLEMENTED** |  |  | SafeAreaContainer, Xvfb |  | visual review of screenshots (Xvfb) | Desktop renders only; on 3:4 some grids leave empty side space; fixed vertical FOV slightly crops the near outer lane on 9:19.5. project.godot: 720x1280 base, canvas_items/expand stretch; full-rect screens + SafeAreaContainer. Xvfb captures at 540x960 (lead ui6), 444x960 (~9:19.5) and 768x1024 (3:4) in status_probes/batch3/{tall,tablet} keep layouts intact. |
| REQ-197 | Handles notch, Dynamic Island, punch-hole, tablet, small phone. | **PARTIAL** | safe_probe.gd | safe_probe.gd | Notch, Dynamic, Island, SafeAreaContainer |  | visual review of screenshots (Xvfb) | Notch, punch-hole, 16:9 and 4:3 tablet layouts tested with simulated devices (test_safe_area.gd); no physical device. — evidence: Notch, Dynamic Island and punch-hole are handled through SafeAreaContainer (simulated insets in safe_probe.gd); tablet 3:4 and tall 9:19.5 captures render correctly (status_probes/batch3). |
| REQ-198 | Touch targets are large enough. | **IMPLEMENTED** |  |  | Touch, UiTokens, MIN, Android | test_volume_sliders_meet_touch_target | automated tests (suite 746 passed, 0 failed); visual review of screenshots (Xvfb) | Not measured on a device. |

#### R. Performance

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-199 | FPS targets: high-end 60, mid-range stable 60 where possible, low-end fallback quality. | **PARTIAL** | presets.json | presets.json | QualityService.auto_detect, Mobile | test_feel_quality.gd, test_auto_detect_is_conservative | automated tests (suite 746 passed, 0 failed); visual review of screenshots (Xvfb) | Targets are configured only. No FPS was measured on any device class (no hardware); screenshots used llvmpipe. — evidence: data/quality/presets.json fps_cap 60 (ultra 120); QualityService.auto_detect/detect_for picks low on compat renderer or weak mobile; Mobile renderer (opengl3 fallback default); test_feel_quality.gd test_auto_detect_is_conservative. |
| REQ-200 | Object pooling. | **IMPLEMENTED** | node_pool.gd | node_pool.gd, burst_pool.gd | NodePool, GameplayView._pool, EntityViews, CPUParticles3D, AudioService | test_app_flow.gd, test_restart_is_stable_and_fast | automated tests (suite 746 passed, 0 failed) | Hazards, bursts, rings and SFX voices are pooled. Restarts reuse nodes with no scene reload. |
| REQ-201 | Batching. | **IMPLEMENTED** | spark_field.gd | spark_field.gd | MultiMesh, GameplayView._ribs, MultiMeshInstance3D, RIB, TrailRibbon, ImmediateMesh |  | code inspection | The most numerous objects are instanced. Hazards are pooled single MeshInstances that share meshes and materials. |
| REQ-202 | Texture atlas. | **NOT_IMPLEMENTED** | game | game/src | No, Textures, GradientTextures, ViewKit, BurstPool, IconGlyph |  | code inspection | No texture atlas exists, and no documented decision covers it. Few bitmap textures exist, so the benefit would be small. — evidence: No atlas anywhere: case-insensitive grep 'atlas' over game/src, data, assets finds nothing. Textures are runtime GradientTextures (ViewKit soft dot, BurstPool glow), icons are code-drawn (IconGlyph), and the only image is assets/icons/app_icon.svg. |
| REQ-203 | Shader optimization. | **PARTIAL** | game/assets | game/assets/shaders | ColorRect |  | code inspection | No GPU profiling, no per-preset shader variants and no device check. glass.gdshader still runs a 3x3 loop per fragment. — evidence: 11 short shaders in game/assets/shaders (<=72 lines); energy shaders are unshaded/blend_add with shadows disabled; post_fx ColorRect only while an effect is active; sky radiance pass is gradient only; post_fx is off on the low preset. |
| REQ-204 | Particle limits. | **IMPLEMENTED** | burst_pool.gd | burst_pool.gd | PRESETS, emit(), WorldTheme, GameplayView._apply_atmosphere_quality, Test | test_atmosphere_and_bursts_stay_within_budget | automated tests (suite 746 passed, 0 failed) | Each effect has a hard cap and a fixed pool size, and counts scale down on lower presets. |
| REQ-205 | Memory management. | **PARTIAL** |  |  | Pooled, NodePool, BurstPool, LevelRepository, LRU, CACHE | test_restart_is_stable_and_fast | automated tests (suite 746 passed, 0 failed) | No memory budget or profiling exists. The memory footprint was never measured on any device. — evidence: Pooled nodes (NodePool, BurstPool), restart without scene reload (test_restart_is_stable_and_fast), LevelRepository LRU (CACHE_SIZE 8), EndlessStreamer compaction, bounded ErrorReporter (MAX_REPORTS 20) and GameLog ring (200). |
| REQ-206 | Async loading. | **IMPLEMENTED** | async_loader.gd | async_loader.gd | AsyncLoader, ResourceLoader, SoundBank.prefetch_music, AudioService.prefetch_music, GameFlow._show_main | test_prefetched_music_comes_from_the_background_loader | automated tests (suite 746 passed, 0 failed) |  |
| REQ-207 | Scene streaming. | **PARTIAL** |  |  | GameplayView._spawn_entities, VIEW, EndlessStreamer.pump, RunController.pump | test_endless_streams_and_records_best_distance | automated tests (suite 746 passed, 0 failed) | Course content streams within a level (EndlessStreamer) and music loads in the background (AsyncLoader); there is no multi-scene world streaming (single persistent scene by design). — evidence: GameplayView._spawn_entities spawns pooled entities within VIEW_AHEAD 75 and releases them behind VIEW_BEHIND; EndlessStreamer.pump builds 1 slot per frame (RunController.pump) with compaction; test_endless_streams_and_records_best_distance. |
| REQ-208 | Lightweight UI. | **IMPLEMENTED** | ui_theme.gd | ui_theme.gd | Theme, StyleBoxFlat, IconGlyph, ScreenRouter._ensure_built |  | visual review of screenshots (Xvfb) | UI cost was not measured on a device. The main menu renders a live 3D attract run behind the UI. |
| REQ-209 | Caching. | **IMPLEMENTED** |  |  | LevelRepository, LRU, CACHE, SoundBank.stream_at, ViewKit, UiTheme |  | code inspection | LevelRepository LRU (_cache/_order, CACHE_SIZE 8); SoundBank.stream_at caches streams, preload_sfx warms them; ViewKit caches arch/membrane/track/chevron/form meshes and materials; UiTheme/UiFonts static caches; RemoteConfig.save_cache/load_cache. |
| REQ-210 | Draw-call control. | **PARTIAL** | probe_draw.gd | probe_draw.gd | Design, MultiMesh, VIEW, The |  | code inspection | There is no draw-call budget, test or tool in the repo, and nothing was measured on the Mobile renderer or a device. — evidence: Design: MultiMesh sparks/ribs, VIEW_AHEAD windowing, shared materials. The assessor's own probe (probe_draw.gd, xvfb + opengl3/llvmpipe) measured draw calls: w01_l10 avg 33/max 40, w05_l40 54/68, w10_l52 79/96. |
| REQ-211 | Avoid unnecessary allocations / GC pressure. | **PARTIAL** | gameplay_view.gd | gameplay_view.gd | FluxSim.step, FrameMonitor, GameplayView._update_frame, keys() |  | code inspection | keys() copies removed from the per-frame view loop; event arrays are still allocated per tick and nothing was profiled on a device. — evidence: FluxSim.step avoids allocation (packed arrays, reused flat events buffer); FrameMonitor packed ring; pooled nodes. GameplayView._update_frame still calls _active.keys() every frame (gameplay_view.gd ~443). |
| REQ-212 | Quality presets Low / Medium / High / Ultra. | **IMPLEMENTED** | presets.json | presets.json | QualityService, GameplayView.set_quality, FX | test_feel_quality.gd, test_quality_flags_survive_world_changes | automated tests (suite 746 passed, 0 failed) | Not run on a device. |
| REQ-213 | Automatic runtime quality reduction when needed. | **IMPLEMENTED** | services.gd | services.gd | FrameMonitor, QualityService.feed_frame, MSAA, GameFlow._apply_quality | test_auto_quality_step_reaches_the_viewport, test_feel_quality.gd | automated tests (suite 746 passed, 0 failed); visual review of screenshots (Xvfb) | Not run on a device. |

#### S. Audio & haptics

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-214 | Button sounds. | **IMPLEMENTED** | ui_button.gd | ui_button.gd, sound_bank.json | UiKit.play_feedback, UiKit.feedback_hook, AppServices.ui_feedback, AudioService.play_sfx |  | code inspection |  |
| REQ-215 | Tap sounds. | **IMPLEMENTED** |  |  | GameplayView._handle_event, TAP, GameFlow._on_feedback, AudioService.on_feedback, WAVs | test_feel_audio.gd, test_every_gameplay_feedback_kind_has_a_sound | automated tests (suite 746 passed, 0 failed) |  |
| REQ-216 | Collision sounds. | **IMPLEMENTED** | sound_bank.json | sound_bank.json | GameplayView._handle_event, FAIL, HIT, ZEN, SHATTER, CHAIN | test_every_gameplay_feedback_kind_has_a_sound | automated tests (suite 746 passed, 0 failed) |  |
| REQ-217 | Combo layers. | **IMPLEMENTED** |  |  | Combo, SoundBank, AudioService.set_combo, GameFlow._on_feedback | test_fail_card_stays_clear_and_music_follows_the_run | automated tests (suite 746 passed, 0 failed) |  |
| REQ-218 | Perfect sound. | **IMPLEMENTED** | sound_bank.json | sound_bank.json | GameplayView._handle_event, COMPLETE, AudioService | test_every_gameplay_feedback_kind_has_a_sound | automated tests (suite 746 passed, 0 failed) | The perfect SFX plays. The 'perfect_fanfare' stinger never plays (see REQ-221). |
| REQ-219 | Fail sound. | **IMPLEMENTED** | sound_bank.json | sound_bank.json | GameplayView._handle_event, FAIL, AudioService.on_feedback, SoundBank, REQUIRED | test_every_gameplay_feedback_kind_has_a_sound | automated tests (suite 746 passed, 0 failed) |  |
| REQ-220 | Reward sound. | **IMPLEMENTED** |  |  | GameFlow._build_ui, RewardOverlay.item_landed, CompleteOverlay.star_landed |  | code inspection | The bank's 'reward', 'level_up' and 'unlock' SFX are never triggered. With Reduce Motion on, RewardOverlay skips item_landed, so reveals are silent. GameFlow._build_ui: RewardOverlay.item_landed -> audio.play_sfx('coin') for every reveal (level-up, mission, achievement); CompleteOverlay.star_landed -> play_sfx('star'); in-run pickups emit 'pickup'. |
| REQ-221 | Level-complete music. | **IMPLEMENTED** | sound_bank.json | sound_bank.json | Level, GameFlow |  | automated tests (suite 746 passed, 0 failed) | The stinger names were wrong before this round. |
| REQ-222 | World music. | **IMPLEMENTED** | sound_bank.json | sound_bank.json | GameFlow._start_run, AudioService | test_feel_audio.gd, test_music_covers_every_world_and_matches_tempo | automated tests (suite 746 passed, 0 failed) |  |
| REQ-223 | Boss / challenge music. | **IMPLEMENTED** | sound_bank.json | sound_bank.json | World, GameFlow._play_level_music |  | code inspection |  |
| REQ-224 | Audio synchronised with gameplay. | **PARTIAL** | floor.gd | floor.gd | AudioService.beat, GameFlow, GameplayView.music_beat, LevelGenerator._timed_pulse |  | code inspection | Music playback is not phase-locked to the simulation clock; hazards are beat-timed by the level, not by the audio position. — evidence: AudioService.beat drives the floor lane-lip pulse (GameFlow -> GameplayView.music_beat -> floor.gdshader beat); intensity stem follows the live combo; pulse gates and sliders are timed in multiples of the level beat_seconds (LevelGenerator._timed_pulse). |
| REQ-225 | Haptics on tap, collect, perfect, hit, combo, level complete, reward — without spam. | **IMPLEMENTED** | patterns.json | patterns.json | HapticsService, GameFlow | test_feel_haptics.gd | automated tests (suite 746 passed, 0 failed) | Never felt on hardware. |

#### T. Tutorial, UI/UX, flow

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-226 | Tutorial ≤ 20 s (ideally 5–10 s), no long text, taught through gameplay. | **PARTIAL** | w01_l01.json | w01_l01.json | Hud._update_tap_hint, TAP, Hud._show_form_hint |  | code inspection | Tutorial levels last 6-14 s with hints on L1-5 (docs match); whether it teaches within 20 s was not confirmed by players. — evidence: w01_l01.json: duration 10.4 s, 2 solution taps, forgiving true, tutorial true; Hud._update_tap_hint pulses a TAP ring on solution ticks; one-line form hints (Hud._show_form_hint). |
| REQ-227 | UI is minimal, premium, clean, fast, responsive. | **PARTIAL** |  |  | UiKit, UiTokens, UiButton, UiScreen.transition_in |  | visual review of screenshots (Xvfb) | Minimal/clean is judged from llvmpipe screenshots only. Speed and responsiveness were not measured on a device, and no human reviewed the UI. — evidence: UiKit/UiTokens design system (flat theme, 64 px touch targets, token type scale); UiButton press tweens; UiScreen.transition_in; EN/TR screenshots in lead/ui6 and lead/ui_tr look clean and minimal. |
| REQ-228 | Main screen cleanly organises Play, Progress, Shop, Collection, Daily, Settings. | **IMPLEMENTED** | main_menu.gd | main_menu.gd | PLAY, Daily, Worlds, Modes, TABS, GameFlow._on_tab |  | visual review of screenshots (Xvfb) |  |
| REQ-229 | Gameplay HUD shows score, combo, objective, pause — minimal. | **IMPLEMENTED** | hud.gd | hud.gd |  |  | visual review of screenshots (Xvfb) | For reach-end levels the objective is shown by the progress bar, not a text label. |
| REQ-230 | Level start: camera reveal, environment animation, core spawn, small anticipation. | **IMPLEMENTED** |  |  | GameplayView.reset_for_run, CameraRig.start_reveal, FOV, CoreView.spawn_in, EntityView.appear, GameplaySession.begin |  | code inspection | Environment motion is ambient plus the course scaling in. There is no dedicated per-level intro sequence. GameplayView.reset_for_run(true) -> CameraRig.start_reveal(1.0) (height/FOV ease) + CoreView.spawn_in(); EntityView.appear scales course pieces in as they spawn; GameplaySession.begin(READY_FIRST 0.8 s) anticipation beat. |
| REQ-231 | Level end: slowdown, perfect explosion, stars, coins, reward, transition; premium level-complete screen. | **IMPLEMENTED** |  |  | Level, GameplayView, COMPLETE, CompleteOverlay, XP | test_result_actions_take_no_taps_during_the_sequence | automated tests (suite 746 passed, 0 failed) | Premium feel judged from captures, not on a device. |
| REQ-232 | State machine with BOOT, MAIN_MENU, WORLD_SELECT, LEVEL_SELECT, COUNTDOWN, PLAYING, PAUSED, FAILED, COMPLETE, REWARD, SHOP, COLLECTION, SETTINGS, DAILY, ENDLESS. | **IMPLEMENTED** |  |  | GameStateMachine, ENDLESS, GameFlow._start_run | test_state_machine.gd | automated tests (suite 746 passed, 0 failed) |  |
| REQ-233 | Accessibility considerations (readability, contrast, reduced motion/shake, colour-blind-safe cues). | **IMPLEMENTED** |  |  | Reduce, Motion, FOV, GameplayView.reduce_motion, CameraRig.shake_scale, Colour | test_reduce_motion_scales_camera_motion, test_colorblind_marks_phase_gates_by_shape | automated tests (suite 746 passed, 0 failed) | No device or user accessibility check. |

#### U. Code quality & architecture

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-234 | Modular, clean, typed, maintainable, scalable, testable code. | **IMPLEMENTED** | services.gd | services.gd | Constructor, RefCounted, QualityService._init, Services |  | automated tests (suite 746 passed, 0 failed) | Specific gaps are tracked separately: broad coordinators (REQ-235), inline literals (REQ-237) and untyped Dictionary containers (REQ-239). |
| REQ-235 | No God Objects. | **PARTIAL** | level_generator.gd | level_generator.gd, flux_sim.gd, progression_service.gd | Domain, Run, RunController, Presenters, ScreenRouter |  | code inspection | GameFlow (700 lines, 43 methods) wires every screen and handles runs, ads/revive, purchases, missions, boards and settings. AppServices has 39 fields (mostly services) plus autosave and wiring. — evidence: Domain modules are focused: largest are level_generator.gd 829, flux_sim.gd 682, progression_service.gd 693 lines. Run logic is in RunController, payloads in Presenters, navigation in ScreenRouter. |
| REQ-236 | Minimise circular dependencies. | **IMPLEMENTED** | services.gd | services.gd | GameplayView.feedback, UiKit.feedback_hook, Modules |  | code inspection |  |
| REQ-237 | Minimise magic numbers. | **PARTIAL** |  |  | Systems, QualityService, HapticsService, SoundBank, SimConst |  | code inspection | Presentation code still holds many inline tuning literals: gameplay_view.gd _handle_event/_setup_atmosphere, core_view.gd, and camera_rig.follow (6.0, 9.0, 0.35, 47.0, ...). — evidence: Systems use named consts and data: QualityService, HapticsService and SoundBank const blocks, SimConst, data/*.json tunables. |
| REQ-238 | Data-driven design. | **IMPLEMENTED** | game | game/data |  |  | level validator 520/520 |  |
| REQ-239 | Static typing wherever possible. | **PARTIAL** |  |  | Array |  | code inspection | Godot 4.7 supports typed Dictionary[K,V], but src uses it once vs ~590 plain Dictionary decls, including homogeneous maps (GameplayView._active, ScreenRouter._screens, LevelRepository._cache). — evidence: project.godot [debug] untyped_declaration=2 (error) and unsafe_* warnings=1; every var/param/return is typed; 247 typed Array[T] uses; gdlint in CI. |
| REQ-240 | Reusable components. | **IMPLEMENTED** |  |  | UiButton, UiToggle, UiSegmented, IconGlyph, UiKit, UiTokens |  | code inspection | src/ui/kit (UiButton, UiToggle, UiSegmented, IconGlyph, UiKit factory, UiTokens, UiTheme, UiFonts), src/ui/components (UiScreen, ScreenHeader, SafeAreaContainer, ToastView, CosmeticSwatch), NodePool, BurstPool, JsonIO, DetRng; FluxSim shared by game, generator, validator, solver and ReplayVerifier. |
| REQ-241 | Clear naming. | **IMPLEMENTED** |  |  | Descriptive, QualityService.feed_frame, FrameMonitor.is_struggling, RunController.prepare, ReplayVerifier, LevelValidator |  | level validator 520/520 | This is a subjective judgement from reading the code. Descriptive class/function names across src (e.g. QualityService.feed_frame, FrameMonitor.is_struggling, RunController.prepare/finish/advance_rush, ReplayVerifier, LevelValidator); consistent snake_case files, one class per file. |
| REQ-242 | Error handling. | **IMPLEMENTED** |  |  | SaveService, PlayerProfile.from_dict, ErrorReporter | test_save_recovery.gd, test_profile_hostile.gd, test_bank_survives_bad_data, test_broken_presets_fall_back_safely | automated tests (suite 746 passed, 0 failed) |  |
| REQ-243 | Logging. | **IMPLEMENTED** | game_log.gd | game_log.gd | GameLog, DEBUG, ERROR, ErrorReporter.build_report, GameLog.debug |  | code inspection |  |
| REQ-244 | Validation. | **IMPLEMENTED** | tools | tools/validate_levels.gd | LevelValidator, QualityService, HapticsService.validate_document, SettingsService, RemoteConfig, AnalyticsSchema |  | level validator 520/520 |  |
| REQ-245 | Difficulty tuning, reward values, daily challenge, event parameters and economy values changeable later (remote-config ready). | **PARTIAL** |  |  | RemoteConfig, RewardEngine.coin_scale, AppServices._apply_remote_tuning, RewardEngine.with_coin_scale, ReplayVerifier.apply_remote_tuning, URLs | test_remote_tuning.gd | automated tests (suite 746 passed, 0 failed) | difficulty.* keys are not applied live (validated levels must not change speed under the player); difficulty is tuned via curve.json + regeneration. — evidence: RemoteConfig (typed, clamped, cached) drives economy.coin_multiplier, economy.daily_reward_multiplier, events.weekend_coin_bonus (RewardEngine.coin_scale/daily_scale via AppServices._apply_remote_tuning; level, daily and score-mode coins via RewardEngine.with_coin_scale), mirrored on the server by ReplayVerifier.apply_remote_tuning; daily.enabled, ads.*, URLs; tests/integration/test_remote_tuning.gd (7 tests). |
| REQ-246 | Architecture is backend-ready even if a backend is not mandatory. | **IMPLEMENTED** | game/server | game/server/verify_replay.gd | LeaderboardBackend, HttpLeaderboardBackend, HttpAnalyticsSink, HttpTransport, NetworkMonitor, RemoteConfig.fetch | test_online_leaderboard_backends.gd, test_online_cli.gd | automated tests (suite 746 passed, 0 failed) | No hosted backend exists, and the requirement does not demand one. The HTTP paths were exercised only with test transports. |
| REQ-247 | Professional directory structure. | **PARTIAL** | server | server/, tools/ci, .github/workflows | Repo |  | automated tests (suite 746 passed, 0 failed) | The repo root still holds an unrelated legacy WordPress/Vite project (index.php, src/, package.json). Its deletion was denied, as README notes. — evidence: game/ is cleanly split: src/{core,gameplay,levels,systems/<module>,save,server_shared,app,ui/{kit,components,screens},vfx,art}, data/, assets/, tests/{unit,integration}, tools/, server/. Repo-level docs/, tools/ci, .github/workflows. |

#### V. Engine, repositories & dependencies

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-248 | Godot Engine is the main engine (mobile iOS + Android). | **IMPLEMENTED** | game | game/project.godot, export_presets.cfg, .github/workflows/ci.yml | Mobile, Android, APK |  | visual review of screenshots (Xvfb); Android debug export | The iOS export was never run here (no macOS/Xcode; BLOCKED), and release signing is BLOCKED (no keystore). |
| REQ-249 | Inspect referenced repos (README, architecture, examples, source, patterns, tests, license) before use. | **IMPLEMENTED** | docs | docs/REPOSITORIES.md |  |  | code inspection | Only the demo-projects clone is still on disk. For pixijs, phaser and zustand the evidence is the doc alone (inspected before first feature commit per git log). |
| REQ-250 | Include only genuinely useful approaches/libraries; no unnecessary dependencies. | **IMPLEMENTED** | tools/audio | tools/audio/requirements.txt | Only, Godot, PixiJS, Phaser, Zustand |  | code inspection |  |
| REQ-251 | Do not copy commercially license-incompatible code or assets. | **IMPLEMENTED** | tools/audio | tools/audio/synth_bank.py, LICENSES.json, tools/ci/license_check.py, placeholder_scan.py | Audio, MeshFactory, ViewKit, IconGlyph, Outfit, OFL |  | code inspection | Separately from copying: only a one-line 'Godot Engine - MIT License' ships (Presenters.licenses_text). The full Godot/third-party notice text is not shipped. |
| REQ-252 | Install dependencies only through official package methods. | **IMPLEMENTED** |  |  | Godot, PyPI, Outfit, JDK, No |  | code inspection | CI downloads Godot 4.7.2 from github.com/godotengine releases; gdtoolkit via pip; numpy via PyPI requirements; Outfit via npm @fontsource/outfit; adb/JDK via apt (lead/apt_adb.log). No vendored binaries in git. |
| REQ-253 | `docs/REPOSITORIES.md` lists each repo with reason, module, version, license and affected features. | **IMPLEMENTED** | docs | docs/REPOSITORIES.md | Presenters.licenses_text, Engine.get_license_text, Engine.get_copyright_info |  | code inspection |  |
| REQ-254 | PixiJS / Phaser / Zustand only for a real need; never solve the same problem with two frameworks. | **IMPLEMENTED** | docs | docs/REPOSITORIES.md | No, PixiJS, Phaser, Zustand, GDScript, NodePool |  | visual review of screenshots (Xvfb) | The root package.json (React/WordPress) belongs to the legacy web project, not the game. |

#### W. Analytics & error handling

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-255 | Event-tracking abstraction with session_started, level_started, level_completed, level_failed, perfect_completed, combo_reached, reward_claimed, shop_opened, purchase_started, purchase_completed, ad_started, ad_completed, daily_started, daily_completed. | **IMPLEMENTED** | events.json | events.json, services.gd, game_flow.gd, run_controller.gd | Tracked, StoreService, AdsService | test_bundled_schema_declares_required_events_without_pii, test_unknown_event_rejected | automated tests (suite 746 passed, 0 failed) | daily_started fires when the Daily screen opens, not when a daily run starts. Ad and purchase events never fire in practice (null providers). |
| REQ-256 | No unnecessary PII collected. | **IMPLEMENTED** |  |  | Analytics, PlayerProfile | test_forbidden_params_dropped, test_events_are_enriched_without_device_identifiers | automated tests (suite 746 passed, 0 failed) |  |
| REQ-257 | Global error handling capturing error log, scene/state, level ID, app version, platform. | **IMPLEMENTED** | probe_audio_err.gd | probe_audio_err.gd | ErrorReporter, CaptureLogger, OS.add_logger, enqueue(), The, GameFlow |  | visual review of screenshots (Xvfb) | No unit test covers the Logger capture path, and native crashes are not captured. context_provider is called inside the Logger callback, which may run off the main thread. |

#### X. Testing, validation, CI

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-258 | Unit tests. | **IMPLEMENTED** | game/tests | game/tests/unit, game/tests/run_tests.gd |  |  | automated tests (suite 746 passed, 0 failed) | 746 tests, 0 failed in the final full run (66 suites incl. integration). |
| REQ-259 | Integration tests. | **IMPLEMENTED** | game/tests | game/tests/integration |  | test_app_flow.gd, test_stream_verification.gd, test_ui_regressions.gd, test_view_regressions.gd, test_remote_tuning.gd | automated tests (suite 746 passed, 0 failed) | Uses the real AppServices graph with MemorySaveStorage and a fixed GameClock. |
| REQ-260 | Gameplay tests. | **IMPLEMENTED** |  |  | GameplaySession | test_sim_rules.gd, test_sim_basic.gd, test_modes.gd, test_app_flow.gd | automated tests (suite 746 passed, 0 failed) | run_tests.gd lists res://tests/gameplay, which does not exist; gameplay tests live in unit/ and integration/. |
| REQ-261 | Save tests. | **IMPLEMENTED** | migrations.gd | migrations.gd |  | test_save_service, test_garbage_main_falls_back_to_backup, test_migrates_enveloped_v0_save, test_file_storage_end_to_end_leaves_no_temp_files, test_profile_hostile.gd | automated tests (suite 746 passed, 0 failed) | Covers envelope, checksum, atomic write, backup, migration and future-version handling. |
| REQ-262 | Economy tests. | **IMPLEMENTED** | tables.gd | tables.gd |  | test_economy_service.gd, test_economy_integrity.gd, test_economy_config.gd, test_rewards_grant, test_replay_pays_small_but_nonzero_coins | automated tests (suite 746 passed, 0 failed) | Economy invariants (no negatives, caps, ledger) are unit-tested. |
| REQ-263 | Level validation tests. | **IMPLEMENTED** |  |  | LevelValidator | test_level_pipeline.gd, test_level_content.gd | automated tests (suite 746 passed, 0 failed); level validator 520/520 |  |
| REQ-264 | Level validator detects unreachable state, impossible level, spawn collision, invalid sequence, missing objective, missing asset, invalid mechanic, dead-end path, broken trigger at build/test time. | **IMPLEMENTED** | level_validator.gd | level_validator.gd, validate_levels.gd | LevelValidator.validate |  | level validator 520/520 | unreachable_state and dead_end (barrier d=22.0, tap 134) reproduced by scratch probes, not by dedicated tests (see REQ-263). |
| REQ-265 | CI pipeline: build, tests, lint/format, import/dependency validation, level validation, asset validation. | **PARTIAL** | .github/workflows | .github/workflows/ci.yml, run_tests.gd, validate_levels.gd | Android, APK |  | automated tests (suite 746 passed, 0 failed); level validator 520/520; Android debug export | Not observed running on GitHub; no gdformat --check step (gdlint only). The iOS export step now injects a team ID (IOS_TEAM_ID or a non-signing value). — evidence: .github/workflows/ci.yml: gdlint, placeholder/licence scans, JSON parse, --import failing on script/shader errors, run_tests.gd, validate_levels.gd, generate_levels --check, Android debug APK export, iOS export + xcodebuild simulator build. |
| REQ-266 | Manual test of at least 20 different levels. | **PARTIAL** | tools | tools/validate_levels.gd | Autopilot |  | level validator 520/520; visual review of screenshots (Xvfb) | No human manual play on a device; only 10 distinct levels visually reviewed (report section 32 claims 20+). — evidence: Autopilot runs through the real view were captured for 10 distinct levels (w01_l30 to w10_l20, scratch shots3/worlds_final); UI capture plays w01_l01/w01_l12; all 520 levels sim-validated by tools/validate_levels.gd. |
| REQ-267 | Automated level validation executed. | **IMPLEMENTED** | tools | tools/validate_levels.gd | LevelValidator, Validate | test_level_pipeline.gd | automated tests (suite 746 passed, 0 failed); level validator 520/520 | The CI step is defined but has not been observed running on GitHub. |
| REQ-268 | Save/load test. | **IMPLEMENTED** |  |  |  | test_save_persistence.gd, test_file_storage_end_to_end_leaves_no_temp_files, test_migrated_save_is_rewritten_and_legacy_kept_as_backup, test_save_service.gd, test_save_storage.gd | automated tests (suite 746 passed, 0 failed) | Exercised on Linux user:// only, not on a device file system. |
| REQ-269 | Scene transition test. | **IMPLEMENTED** |  |  |  | test_state_machine.gd, test_ui_regressions.gd, test_main_scene_boots_headless | automated tests (suite 746 passed, 0 failed) |  |
| REQ-270 | Device aspect test. | **IMPLEMENTED** |  |  | SafeAreaContainer | test_safe_area.gd | automated tests (suite 746 passed, 0 failed) | No physical device. |
| REQ-271 | Performance test. | **PARTIAL** | gameplay_view.gd | gameplay_view.gd | MultiMesh | test_app_flow.gd::test_restart_is_stable_and_fast, test_feel_quality.gd | automated tests (suite 746 passed, 0 failed) | No FPS, frame-time, memory or thermal measurement on any device or GPU (no hardware). — evidence: test_app_flow.gd::test_restart_is_stable_and_fast (100 restarts, node count stable, each under 50 ms headless); test_feel_quality.gd frame monitor and auto-downgrade tests; pooled nodes and MultiMesh in gameplay_view.gd. |
| REQ-272 | Low-quality mode test. | **IMPLEMENTED** |  |  | FX | test_quality_flags_survive_world_changes, test_feel_quality.gd, test_auto_quality_step_reaches_the_viewport | automated tests (suite 746 passed, 0 failed) |  |
| REQ-273 | Offline test. | **IMPLEMENTED** |  |  |  | test_online_leaderboard_service.gd::test_offline_queues_then_flushes_when_transport_recovers, test_fetch_prefers_remote_and_falls_back_offline, test_platform_remote_config.gd::test_fetch_offline_keeps_cached_values, test_platform_network.gd::test_http_transport_unreachable_host_is_offline_not_crash | automated tests (suite 746 passed, 0 failed) | Offline behaviour verified with scripted transports and no backend, not by toggling a real device network. |
| REQ-274 | Corrupted data test. | **IMPLEMENTED** |  |  |  | test_save_recovery.gd, test_profile_hostile.gd, test_platform_remote_config.gd::test_corrupt_or_tampered_cache_falls_back_to_defaults, test_meta_missions.gd::test_corrupted_state_recovers | automated tests (suite 746 passed, 0 failed) | Corruption handled by fallback to backup or a new profile without crashing. |
| REQ-275 | Restart test. | **IMPLEMENTED** |  |  | GameplaySession.restart, GameplayView.reset_for_run | test_app_flow.gd::test_restart_is_stable_and_fast | automated tests (suite 746 passed, 0 failed) | Headless timing; device restart latency not measured. |
| REQ-276 | Repeated play test. | **IMPLEMENTED** |  |  |  | test_app_flow.gd::test_daily_rewards_only_first_completion, test_restart_is_stable_and_fast, test_rewards_level.gd::test_replay_pays_small_but_nonzero_coins, test_new_stars_on_replay_add_star_bonus | automated tests (suite 746 passed, 0 failed) | Automated repeated play only (restarts run 30 ticks each); no long human sessions. |

#### Y. CodeRabbit continuous review

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-277 | Run `coderabbit review --agent` after every major milestone (core prototype, core gameplay, level system, progression, UI, save, economy, daily, mobile optimization, release build). | **BLOCKED** | docs | docs/CODERABBIT_REPORT.md | PATH, CONNECT |  | code inspection | Blocked by the environment network policy (no npm distribution either). Substitute: 8 module reviews plus integrated review R-INT round 1 (d107839). — evidence: docs/CODERABBIT_REPORT.md status table; re-checked by verifier: no coderabbit binary on PATH, curl https://cli.coderabbit.ai/install.sh -> 'CONNECT tunnel failed, response 403'. |
| REQ-278 | Analyse output for bugs, logic errors, races, performance, memory, security, architecture, abstractions, dead/duplicated code, validation, tests, error handling, maintainability. | **BLOCKED** | docs | docs/CODERABBIT_REPORT.md | No, CodeRabbit, Substitute, PLAT, URL, FEEL |  | automated tests (suite 746 passed, 0 failed) | Blocked with REQ-277; analysing substitute reviews is not an analysis of CodeRabbit output. — evidence: No CodeRabbit output exists. Substitute module reviews in docs/CODERABBIT_REPORT.md covered bugs, security (R-PLAT URL guard), performance (R-FEEL per-frame copies), validation and missing tests. |
| REQ-279 | Issue → task → fix → test → re-run → verify loop; Critical/Major first. | **PARTIAL** | docs | docs/CODERABBIT_REPORT.md | INT |  | automated tests (suite 746 passed, 0 failed) | No CodeRabbit re-run (blocked); Critical/Major-first ordering and per-issue task tracking are not documented. — evidence: docs/CODERABBIT_REPORT.md: each substitute finding reproduced by probe or failing test, fixed (ce24494, aa87d85, 22bc293, e8ef6f8, f3fab46, d88e85e, 908b4fe, 7e0e9df) and suites re-run; R-INT fixes in d107839. |
| REQ-280 | At most 2–3 review/fix rounds per milestone (no infinite loop). | **IMPLEMENTED** |  |  | INT |  | code inspection | Bound respected by the substitute reviews only; CodeRabbit itself never ran (REQ-277 BLOCKED). git log: one review/fix round per module (e.g. 86431da -> ce24494, 4a6029d -> aa87d85, 67d68b9 -> 908b4fe) plus integrated review R-INT round 1 (d107839); no repeated review loops. |
| REQ-281 | Do not proceed to release until the CodeRabbit result is clean. | **BLOCKED** | FINAL_IMPLEMENTATION_REPORT.md | FINAL_IMPLEMENTATION_REPORT.md | No, CodeRabbit, REQ, APK |  | Android debug export | Gate cannot be evaluated: no CodeRabbit result exists (CLI unreachable); substitute reviews show 0 open critical/major findings. — evidence: No CodeRabbit result can be produced (REQ-277). No release build or store upload was made, only a signed debug APK; FINAL_IMPLEMENTATION_REPORT.md section 39 states the product is not yet shippable. |
| REQ-282 | Use the existing CodeRabbit auth flow; check CLI installation status. | **BLOCKED** | docs | docs/CODERABBIT_REPORT.md |  |  | code inspection | Installation status was checked and documented; the auth flow is impossible without the CLI and an account. — evidence: docs/CODERABBIT_REPORT.md table: curl install 403, npm @coderabbitai/cli 404, squatted npm 'coderabbit' not installed, 'which coderabbit' empty; re-verified (no binary, 403). |
| REQ-283 | `docs/CODERABBIT_REPORT.md` updated per milestone with Date, Milestone, Commit, Scope, Critical, Major, Minor, Fixed, Remaining, Final status. | **PARTIAL** | docs | docs/CODERABBIT_REPORT.md | Date, Milestone, Commit, Scope, Critical, Major |  | code inspection | Written at integration time rather than updated after each milestone; no real CodeRabbit output (BLOCKED). — evidence: docs/CODERABBIT_REPORT.md: per-milestone table with Date, Milestone, Commit, Scope, Critical, Major, Minor, Fixed, Remaining, Final status; module and R-INT review logs. |

#### Z. Documentation, reporting, build & final audit

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-284 | `README.md` with setup, run, build, test, export, architecture, directories, dependencies, known issues. | **IMPLEMENTED** | README.md | README.md | Quick, Mobile, Architecture, Directories, Dependencies, Known |  | automated tests (suite 746 passed, 0 failed); level validator 520/520; visual review of screenshots (Xvfb); Android debug export | README claims CI exports and compiles the iOS Xcode project; with the committed preset that export fails (empty team ID, see REQ-295). |
| REQ-285 | `docs/ARCHITECTURE.md`. | **IMPLEMENTED** | docs | docs/ARCHITECTURE.md, game/src | AppServices, GameFlow, ScreenRouter, GameStateMachine |  | automated tests (suite 746 passed, 0 failed) | Up to date with the module structure as of d107839. |
| REQ-286 | `docs/GAME_DESIGN.md`. | **IMPLEMENTED** | docs | docs/GAME_DESIGN.md |  |  | code inspection | Design document only; claims in it are verified by other requirements. |
| REQ-287 | `docs/LEVEL_DESIGN.md`. | **IMPLEMENTED** | docs | docs/LEVEL_DESIGN.md, difficulty_model.gd, curve.json, level_generator.gd, level_validator.gd |  |  | level validator 520/520 | Matches the validator codes and tools in the repo. |
| REQ-288 | `docs/FINAL_IMPLEMENTATION_REPORT.md` with per-requirement status (IMPLEMENTED / PARTIAL / NOT_IMPLEMENTED / BLOCKED) and fields ID, Description, Status, Location, Files, Functions/Classes, Tests, Runtime Verification, Notes. | **IMPLEMENTED** | docs | docs/FINAL_IMPLEMENTATION_REPORT.md, tools/report/completion.py, docs/requirements_status.json | ID, Description, Status, Implementation, Location, Relevant |  | automated tests (suite 746 passed, 0 failed); visual review of screenshots (Xvfb) |  |
| REQ-289 | Final report contains all 40 mandated sections. | **IMPLEMENTED** | docs | docs/FINAL_IMPLEMENTATION_REPORT.md, tools/report/completion.py | ANTI, AI, SLOP, VISUAL, AUDIT |  | code inspection |  |
| REQ-290 | Completion % computed as Implemented / Total × 100; PARTIAL reported separately. | **IMPLEMENTED** | tools/report | tools/report/completion.py | TOTAL, NOT, IDs |  | code inspection |  |
| REQ-291 | No TODO / FIXME / TEMP / PLACEHOLDER / MOCK / FAKE DATA left in production code (or explicitly reported). | **IMPLEMENTED** | tools/ci | tools/ci/placeholder_scan.py, game/src | TODO, FIXME, TEMP, MOCK, FAKE |  | code inspection | MemorySaveStorage (src/save) is a real fallback storage that also carries test hooks (corrupt, fail_writes); null ad/IAP/push providers are disclosed. |
| REQ-292 | Demo assets replaced by real assets. | **IMPLEMENTED** | game | game/assets, tools/audio/synth_bank.py, game/assets/LICENSES.json, tools/ci/license_check.py | Asset, WAVs, Outfit, OFL, SVG |  | code inspection | No demo/template assets remain; the app icon predates the art rework (b091251) and was never revised (see REQ-305). |
| REQ-293 | Features requiring UI + logic + state + save + validation + test are not reported complete with UI only; unfinished features are not hidden. | **IMPLEMENTED** | docs | docs/requirements_status.json | Statuses | test_safe_area.gd | automated tests (suite 746 passed, 0 failed); Android debug export |  |
| REQ-294 | Android APK/AAB build path. | **IMPLEMENTED** | game | game/export_presets.cfg | Android, APK, MB, OK |  | Android debug export | APK path only: AAB (Play upload) not configured (use_gradle_build=false); the real release keystore is missing (BLOCKED, REQ-296). |
| REQ-295 | iOS Xcode/export pipeline structure. | **IMPLEMENTED** | export_presets.cfg | export_presets.cfg, .github/workflows/ci.yml | Xcode, Linux, FluxDrop.xcodeproj, MB, ID, IOS |  | Android debug export | Compiling/signing need macOS + Apple account (BLOCKED here); CI job not observed running. |
| REQ-296 | Signing data is not requested from the user; missing signing is reported as BLOCKED. | **IMPLEMENTED** | FINAL_IMPLEMENTATION_REPORT.md | FINAL_IMPLEMENTATION_REPORT.md, game/.gitignore, export_credentials.cfg | Known, Release, AAB, APK |  | Android debug export | The missing iOS team ID is reported only as 'no macOS', not as the reason the iOS export fails. |
| REQ-297 | Separate polish pass (animation, timing, easing, particles, sounds, haptics, menus, transitions, typography, spacing, icons, colours, accessibility, loading, restart speed, fail/reward/level-complete screens). | **PARTIAL** |  |  | Commits, UiTokens |  | visual review of screenshots (Xvfb) | Polish pass done on captures (finish membrane, title band, reveal over fail, icon, touch sizes); sounds, haptics and loading were not reviewed on a device. — evidence: Commits 25f2423 'UI polish from screen review', 96e004d UI fixes, 53e1a0f art rework; UiTokens motion timings; EN/TR screen captures reviewed (scratch lead/ui1-ui6, ui_tr). |
| REQ-298 | Self-evaluation questions (fun? understood in 10 s? replay? level 100 interesting? mechanics combine? premium? responsive? mobile-comfortable? performant? production code?) answered from real code/test evidence. | **PARTIAL** | GAME_DESIGN.md | GAME_DESIGN.md | Report, FPS |  | code inspection | Self-evaluation answered in the report from automated evidence; player-facing answers (fun, understood in 10 s, wish to replay) remain unverified without playtests. — evidence: Report audits give evidence for some questions: section 5 (responsive tap queue), 18 (mobile comfort), 19 (performance, no device FPS), 26 (code quality); GAME_DESIGN.md section 11 tutorial under 20 s. |
| REQ-299 | Final steps executed: git status, build, tests, level validator, dependency check, license check, dead-code check, placeholder check, CodeRabbit, critical fixes, final CodeRabbit, final report, completion %. | **PARTIAL** |  |  | Final, Android, MB, Xcode, FINAL |  | automated tests (suite 746 passed, 0 failed); level validator 520/520; Android debug export | CodeRabbit runs are BLOCKED (CLI unreachable); substitute reviews used. — evidence: Final steps run at the end on the final tree: git status, Android debug export (64 MB, v2+v3 verified), iOS Xcode project export, 746 tests, full level validation (520/520) and regeneration check (0 mismatches), licence check, placeholder scan, dead-code probe (20 unused functions removed), gdlint, and a final independent review of the last fix round (R-FINAL: 0 critical / 0 major / 5 minor, 4 fixed, 1 by design); results in report sections 29 and 32-35. |
| REQ-300 | All required documentation files verified to exist. | **IMPLEMENTED** | README.md | README.md, docs/ARCHITECTURE.md, GAME_DESIGN.md, LEVEL_DESIGN.md, ART_DIRECTION.md, REPOSITORIES.md | Verified |  | code inspection | Existence only; completeness of the final and CodeRabbit reports is covered by REQ-283/288/289. |
| REQ-301 | Final answer in the mandated format, generated from the real repository state. | **IMPLEMENTED** | tools/report | tools/report/completion.py | The, PROJECT, STATUS, COMPLETION, FINAL, REPORT |  | code inspection | Delivered in the session, not stored in the repository. |

#### AA. Art direction — "anti AI-slop" human-made quality (added mid-development, 2026-10-03)

| Requirement ID | Description | Status | Implementation Location | Relevant Files | Relevant Functions/Classes | Tests | Runtime Verification | Notes |
|---|---|---|---|---|---|---|---|---|
| REQ-302 | The game must not look AI-generated, "AI slop", a generic asset pack or auto-generated; it must look like a professional studio team polished it for months. | **PARTIAL** | docs | docs/ART_DIRECTION.md | Art, WARNING |  | visual review of screenshots (Xvfb) | Consistent and readable but not studio-grade: primitive geometry, flat materials, recoloured core skins; no human art-director review. Icon, result backdrop and title band were fixed. — evidence: Art rework 53e1a0f and docs/ART_DIRECTION.md; renders (scratch lead/worlds_a.png, worlds_b.png, ribs_b.png) show a coherent, restrained look: matte chamfered WARNING blocks, one glowing core, per-world ribs and silhouettes. |
| REQ-303 | Avoid every listed AI-slop trait: generic AI look, meaningless gradients, random neon combinations, excessive glow, bloom on everything, emissive everywhere, plastic materials, meaningless contrast, random detail, lens flare, constant particle rain, heavy volumetric fog, chromatic aberration everywhere, heavy motion blur, artificial reflections, repeating textures, generic sci-fi textures, stock-asset feel, mixed/disconnected styles, wrong proportions, inconsistent perspective, physically meaningless materials, stretching, bad normals, excessive noise, repeating decals/objects, generic icon sets, AI faces, meaningless ornament, asset-pack collisions. | **PARTIAL** | gameplay_view.gd | gameplay_view.gd, world_theme.gd | Code, Deep, Ocean |  | code inspection | Icon redone flat in the palette; remaining trait: 9 of 19 core skins are recolours of a shared style. — evidence: Code guards: glow_hdr_threshold 1.0 and glow_bloom 0, depth fog only, chroma split only on fail (gameplay_view.gd), atmosphere clamped to 24 (world_theme.gd), no raster textures, emission on energy, the shutter lamp and Deep Ocean floor caustics. |
| REQ-304 | One art direction governs everything: shared proportion, shape, material and lighting language, colour theory, visual hierarchy and animation language (documented). | **IMPLEMENTED** | docs | docs/ART_DIRECTION.md, palette.gd, mesh_factory.gd, ui_tokens.gd, view_kit.gd, world_theme.gd | VFX, WorldTheme.quiet | test_environment_colours_stay_quiet_in_every_world, test_collected_sparks_pop_then_vanish | automated tests (suite 746 passed, 0 failed) | Doc aligned with the shipped chamfer (hazards 16 %, structure 8 %) and the four impact shakes. Judged from software-rendered captures, not a phone. |
| REQ-305 | Every asset is checked against the art language before inclusion ("does this fit?"). | **PARTIAL** | docs | docs/ART_DIRECTION.md |  |  | visual review of screenshots (Xvfb) | Assets were reviewed by category in the anti-slop audit; no per-asset gate record exists. — evidence: docs/ART_DIRECTION.md section 12 asset-gate checklist; world and UI renders reviewed (scratch lead/worlds_final, ui6, ui_tr); review-driven fixes in 25f2423 and d107839 (distinct rib profiles per world). |
| REQ-306 | Deliberate geometric language: fixed proportions for gameplay objects, a consistent collectible silhouette, consistent obstacle corners, rule-based environment variation. | **IMPLEMENTED** | sim_const.gd | sim_const.gd, view_kit.gd, spark_field.gd | LANE, CORE, BLOCK, HAZARD, MeshFactory.shard, RIB |  | code inspection | Chamfer ratio in code (16 %) differs from the doc (8 %); ribs use 8 %. |
| REQ-307 | Silhouettes are distinguishable at a glance; gameplay objects separate clearly from the background. | **IMPLEMENTED** | core_view.gd | core_view.gd | WARNING |  | visual review of screenshots (Xvfb) | Verified on llvmpipe screenshots only; Desert Reactor posts/gate frame share the hazard hue, separation there rests on value contrast. |
| REQ-308 | A colour role system (PRIMARY, SECONDARY, ACCENT, WARNING, SUCCESS, FAILURE); gameplay colours stand out with low clutter; background colours never compete. | **IMPLEMENTED** | palette.gd | palette.gd, view_kit.gd | PRIMARY, SECONDARY, ACCENT, WARNING, SUCCESS, FAILURE | test_environment_colours_stay_quiet_in_every_world | automated tests (suite 746 passed, 0 failed) | The high-key world (Cloud Factory) is exempt from the value cap only, as the doc allows. |
| REQ-309 | Worlds differ but clearly belong to one brand / visual universe. | **IMPLEMENTED** |  |  | Palette |  | visual review of screenshots (Xvfb) | Judged from software-rendered screenshots. data/worlds/w01-w10 JSON: own sky, fog, floor, key light, rib_profile, rib_material, silhouette, atmosphere; shared Palette roles, core, hazards, floor and UI; 10 renders (scratch lead/worlds_a.png, worlds_b.png) read as one visual universe. |
| REQ-310 | Materials are authored deliberately (roughness, metallic, specular, normal, emission); no "make everything shiny"; stylised but physically consistent (metal, glass, stone, ceramic read as such). | **PARTIAL** | view_kit.gd | view_kit.gd, glass.gd | STRUCTURE, Deep, Ocean |  | code inspection | No normal maps (geometry chamfers instead); metal/stone/ceramic read weakly in llvmpipe captures and were not checked on the Mobile renderer or a device GPU. — evidence: view_kit.gd STRUCTURE_PRESETS (anodised, steel, stone, ceramic, coated, ice, sandstone, obsidian, lacquer, crystal: roughness, metallic, specular, clearcoat), hazard satin 0.55/0.0/0.5, glass.gdshader; matter emission only on the lamp and Deep Ocean caustics. |
| REQ-311 | No stretching, obvious tiling, low-res look, repetition, random noise, meaningless detail or inconsistent scale; textures only with purpose; prefer procedural/authored materials, trim-like systems, atlases, masks. | **IMPLEMENTED** | floor.gd | floor.gd | No, WAV, WOFF2, SVG, MeshFactory, Deep |  | code inspection | Repetition is limited to the intentional 7 u rib rhythm (MultiMesh); judged on software renders. |
| REQ-312 | Asset reuse is controlled through variant, scale, material, animation and composition — never copy-paste repetition. | **PARTIAL** | view_kit.gd | view_kit.gd, entity_view.gd | Hazard, MeshFactory.rib |  | code inspection | Cosmetics reuse by recolour: 9 of 19 core skins share a shader style with different colours. — evidence: Hazard variants come from one chamfered family via scale, material and animation (view_kit.gd block/slider/glass/shutter meshes; entity_view.gd shutter drop); ribs via MeshFactory.rib(profile) per world. |
| REQ-313 | Layered foreground / midground / background with controlled parallax and depth; never empty, never overpowering gameplay. | **IMPLEMENTED** | gameplay_view.gd | gameplay_view.gd | MultiMesh, RIB, SILHOUETTE, CPUParticles3D |  | code inspection | Balance judged on software renders only. |
| REQ-314 | Each world tells its own visual story minimally, without decoration for its own sake. | **IMPLEMENTED** | gameplay_view.gd | gameplay_view.gd | Each, World |  | code inspection | Story is told through one far silhouette and one line of copy per world. |
| REQ-315 | Grid-based, proportional, consistent spacing, intentional typography, strong hierarchy, responsive, readable; no generic rounded-rect/gradient buttons, random glow, oversized icons or generic glassmorphism; buttons are not clones; all screens share one design system. | **IMPLEMENTED** |  |  | UiTokens, UiButton, UiTheme |  | visual review of screenshots (Xvfb) | Responsiveness checked only in Xvfb captures, not on devices. src/ui/kit: UiTokens (8 px unit, 32 px margins, 16 px gutters, 4 px radius), UiButton roles (primary, secondary, tertiary, icon, destructive), flat UiTheme panels; all 13 src/ui/screens use the kit; EN/TR, 450x975 and 600x800 captures lay out correctly. |
| REQ-316 | A typography system (H1, H2, H3, Body, Caption, Score, Button, Reward) with few font families and deliberate weights and spacing. | **IMPLEMENTED** | ui_tokens.gd | ui_tokens.gd, ui_kit.gd, ui_fonts.gd | H1, H2, H3, BODY, CAPTION, SCORE |  | code inspection | Minor drift: doc button tracking +1.5, code TRACK_BUTTON 2. |
| REQ-317 | One icon design system (never mixing 3D, flat, outline, emoji or AI-rendered icons). | **IMPLEMENTED** | icon_glyph.gd | icon_glyph.gd, game/src | IconGlyph, HUD, UiKit.icon_button, Unicode |  | code inspection | The launcher app_icon.svg is a separate gradient illustration outside this system (see REQ-305). |
| REQ-318 | Every animation has a purpose (anticipation, follow-through, squash/stretch, overshoot, settle, acceleration/deceleration) with distinct characters per class (player, collectible, obstacle, button, reward, transition), not one recipe applied everywhere. | **IMPLEMENTED** | core_view.gd | core_view.gd, entity_view.gd, spark.gd, ui_button.gd, complete_overlay.gd, ui_screen.gd | TRANS |  | code inspection | The documented collectible pop (scale 1 to 1.25 to 0) is an instant hide plus a 6-mote burst; motion not reviewed on a device. |
| REQ-319 | VFX serve gameplay information, impact, reward, progression or atmosphere; no huge explosion for every event. | **IMPLEMENTED** | burst_pool.gd | burst_pool.gd, gameplay_view.gd | PRESETS |  | code inspection | Budgets and scaling are in code; visual weight not reviewed on a device. |
| REQ-320 | Camera movement is controlled and intentional, tied to gameplay/impact/reward/transition; no shake on every event. | **IMPLEMENTED** | camera_rig.gd | camera_rig.gd, gameplay_view.gd | MAX, SHATTER, CHAIN, HIT, ZEN, FAIL |  | code inspection | Doc says shake only on fail, shield and boss; code also shakes lightly on shatter/chain and zen bump. |
| REQ-321 | Conceptual lighting: a defined key light, fill/rim/ambient/reflection only as needed; not neon-lit everything; no eye-tiring constant brightness. | **IMPLEMENTED** | gameplay_view.gd | gameplay_view.gd, core_view.gd | DirectionalLight3D, AgX, OmniLight3D |  | code inspection | Brightness/eye fatigue not assessed on a device; Cloud Factory is a deliberately high-key near-white world. |
| REQ-322 | Visual priority: 1 Player, 2 Immediate hazard, 3 Objective, 4 Interaction, 5 Score/combo, 6 Environment, 7 Decoration; the background never competes with gameplay. | **PARTIAL** | ART_DIRECTION.md | ART_DIRECTION.md | Palette, ENERGY, WARNING, HUD, WorldTheme.quiet | test_environment_colours_stay_quiet_in_every_world | automated tests (suite 746 passed, 0 failed); visual review of screenshots (Xvfb) | Structure/rib colours are not hue-checked against the gameplay roles (Desert posts sit in the WARNING hue family, though desaturated); hierarchy not tested with players. — evidence: ART_DIRECTION.md section 2; Palette.ENERGY_CORE 2.4 (only strong bloom), WARNING satin hazards, quiet top-centre HUD score; environment colours (sky, fog, floor, lanes) clamped to S <= 0.45 / V <= 0.55 by WorldTheme.quiet (test_environment_colours_stay_quiet_in_every_world); renders show core above hazards above environment. |
| REQ-323 | Variation comes from geometry, silhouette, scale, spacing, movement, material response, animation and placement — not small recolours of the same object. | **PARTIAL** |  |  | Hazards |  | code inspection | Core skins are largely recolours (9/19 share a style). — evidence: Hazards differ by geometry and behaviour (slider track, shutter drop, glass fracture, phase membrane); worlds by rib profile (10), silhouette (10), material preset and atmosphere type (data/worlds/*.json). |
| REQ-324 | "Made by the same professional team?" check applied to environment, objects, UI, icons, VFX, particles, animations, materials, typography and sounds. | **PARTIAL** | tools/audio | tools/audio/synth_bank.py | Shared, Palette, UiTokens, UiFonts, IconGlyph, MeshFactory |  | visual review of screenshots (Xvfb) | Per-category consistency check recorded in the ANTI-AI-SLOP VISUAL AUDIT (10 PASS / 5 PARTIAL); sounds not reviewed on device speakers. — evidence: Shared systems give consistency: Palette, UiTokens/UiFonts, IconGlyph, one synth palette (tools/audio/synth_bank.py), MeshFactory chamfer family; screens and worlds reviewed in captures. |
| REQ-325 | Every detail answers "what is this communicating?"; otherwise it is removed. | **PARTIAL** | ART_DIRECTION.md | ART_DIRECTION.md | World |  | code inspection | Finish membrane behind results and the title band were removed; no per-detail audit of every element exists. — evidence: ART_DIRECTION.md section 2 item 7 rule; code comments justify details (ribs cast no shadows, functional shutter lamp, turbine = World 1 boss story, atmosphere capped with a reason). |
| REQ-326 | Visual quality never harms readability (no invisible obstacles, low contrast, input confusion, player confusion or unclear objectives). | **PARTIAL** | gameplay_view.gd | gameplay_view.gd | LevelValidator, WorldTheme.bright |  | level validator 520/520; visual review of screenshots (Xvfb) | No playtest or device check for player/input confusion or unclear objectives; readability judged from software-rendered screenshots only. — evidence: LevelValidator fairness (unfair_window minimum tap window, first-hazard reaction distance, spawn_collision); colour-blind option (gameplay_view.gd set_colorblind); WorldTheme.bright high-key adaptation; hazards visible in all 10 world renders. |
| REQ-327 | Nothing reads as a one-to-one copy of another game's mechanic, visual, UI, animation, level pattern, character or environment; the game has its own identity. | **IMPLEMENTED** | flux_sim.gd | flux_sim.gd, synth_bank.py, docs/REPOSITORIES.md | Form, MeshFactory, IconGlyph |  | code inspection | The lane-runner tunnel framing is a genre convention, not a copy; name/trademark clearance still pending (report section 38). |
| REQ-328 | Per-asset gate: consistent style, scale, perspective, material, lighting, topology, texture resolution, no repetition, no AI artefacts, no weird geometry, no ambiguity, acceptable mobile performance — fix on any failure. | **PARTIAL** | ART_DIRECTION.md | ART_DIRECTION.md |  |  | code inspection | Category-level checks only (anti-slop audit); mobile cost not measured on devices; core-skin recolours unresolved. — evidence: ART_DIRECTION.md section 12 checklist (style, scale, perspective, material, lighting, topology, repetition, artefacts, meaning, mobile cost); fixes after review (d107839 distinct rib profiles, 25f2423 UI defects). |
| REQ-329 | No raw AI output is placed in the game. | **IMPLEMENTED** | tools/audio | tools/audio/synth_bank.py, mesh_factory.gd, game/assets/LICENSES.json | No, WAVs, OFL, SVG |  | visual review of screenshots (Xvfb) | All code and procedural content was authored by AI agents and reviewed; judged as 'no unedited generative assets'. |
| REQ-330 | Procedural generation obeys art-direction rules (palette, proportions, spacing, shape family, material rules) — random ≠ quality. | **IMPLEMENTED** | curve.json | curve.json, gameplay_view.gd | LevelGenerator, SimConst, MeshFactory, RIB, RNG | test_generator_is_deterministic | automated tests (suite 746 passed, 0 failed) | World palettes are authored data and break the doc's S/V limits (REQ-308); generation does not check palettes. |
| REQ-331 | Final visual review of MAIN MENU, LEVEL SELECT, GAMEPLAY, PAUSE, FAIL, COMPLETE, REWARD, SHOP, COLLECTION, DAILY, SETTINGS and WORLD SELECT against the slop questions, fixing anything that feels like AI slop. | **IMPLEMENTED** | tools | tools/capture_ui.gd, docs/ART_DIRECTION.md | All, ANTI, AI, SLOP, VISUAL, AUDIT |  | visual review of screenshots (Xvfb) | Software-rendered captures, not a phone. |
| REQ-332 | FINAL_IMPLEMENTATION_REPORT contains an "ANTI-AI-SLOP VISUAL AUDIT" grading visual consistency, texture quality, material quality, lighting consistency, UI consistency, iconography, typography, animation consistency, VFX consistency, environment quality, asset reuse quality, procedural generation quality, originality, AI-artifact inspection and overall human-made appearance as PASS / PARTIAL / FAIL; FAILs are fixed before release. | **IMPLEMENTED** | docs | docs/FINAL_IMPLEMENTATION_REPORT.md | ANTI, AI, SLOP, VISUAL, AUDIT, PASS |  | code inspection |  |
| REQ-333 | Minimal but flawless: only commercial-release quality is accepted; the project is not reported COMPLETED unless this section is satisfied. | **PARTIAL** | ART_DIRECTION.md | ART_DIRECTION.md, FINAL_IMPLEMENTATION_REPORT.md | Art, COMPLETED |  | code inspection | Commercial-release visual quality is neither reached nor verified (see REQ-302/331); the final STATUS must not be COMPLETED. — evidence: Art rework and UI design system exist (53e1a0f, src/ui/kit, ART_DIRECTION.md); FINAL_IMPLEMENTATION_REPORT.md section 39 says 'not yet shippable'; no COMPLETED claim in the repo. |
<!-- MATRIX:END -->

## 5. Gameplay Audit

* Deterministic `FluxSim` (`game/src/gameplay/sim/flux_sim.gd`, SIM_VERSION 2): 4 forms, 12 entity
  types, combo, overdrive, near misses (closest approach over the whole hazard pass — fixed this round:
  before, a near miss was geometrically impossible for lane hops), chains, portals, currents, shields,
  magnets, strict (Perfect Run) and zen rules. Tests: `test_sim_rules.gd` (19, incl.
  `test_late_dodge_is_a_near_miss_early_dodge_is_not`), `test_sim_basic.gd`, `test_modes.gd`.
* `GameplaySession`: fixed 60 Hz stepping with interpolation, tap queue with the replay's 2-tick spacing,
  presentation-only hit-stop/slow motion, one optional revive (the view restores the core and removes
  the barrier that was hit), instant restart. `test_restart_is_stable_and_fast` (100 restarts, node
  count stable, < 50 ms each headless).
* Every campaign level's stored solution completes it in the real session; the attract mode plays it
  behind the menu.

## 6. Level System Audit

* 520 levels in `game/data/levels/wNN/wNN_lMM.json`, generated by `LevelGenerator` around a planned tap
  path with measured tap windows, validated by the independent `LevelValidator` (13 error codes, each
  exercised by a test — `test_level_pipeline.gd`, `test_level_content.gd`).
* Full validation: `validated 520 levels in 394.8s: 0 failed, 0 with warnings, worst tap window 183 ms`.
* Determinism: `generate_levels.gd --check`: `generated 520 levels in 553.2s, failures=0 mismatches=0`.
* Fixed this round: world data called the pulse-gate hazard `pulse`, so 20 chapters placed no pulse gates
  (now from W1 L40, guarded by `test_world_hazard_weights_name_real_hazards`); the Cyber Garden
  "reaction chain" chapter had no breakables; mid-world challenges were 30–60 s (now 60–120 s).
* Boss/challenge set pieces now shape generation (rotor, rhythm, pattern memory, colour cascade, chain
  smasher, escape, survival, fast field — `docs/LEVEL_DESIGN.md`; `test_boss_set_pieces_shape_their_levels`).
* Independent solver: `AutopilotSolver` solves sampled levels of every form without the stored solution.
* Endless/time-attack courses stream from the same generator (`EndlessStreamer`).

## 7. Difficulty Curve Audit

Ten tiers with duration bands and minimum tap windows from 420 ms (tutorial) to 130 ms (endgame);
speed 6.5→12 m/s, spacing 7.2→4.1 m; 13-level chapters (introduction / mastery / combination / high
pressure) give the sawtooth; a new mechanic every 13 levels (40 introductions); specials 60–120 s.
Tests: `test_level_pipeline.gd` (difficulty structure, new idea every 10–20 levels, speed trend).
Measured durations (s): tutorial 6–14, challenge levels 80–116, bosses 62–113,
worst required tap window 183 ms. Not playtested by humans (REQ-083/084 PARTIAL).

## 8. Progression Audit

`ProgressionService` (stars keep the max, best score/time, attempts, level and world unlocks: world N
needs world N-1's boss and the star threshold), XP curve with multi-level-ups and level-up rewards as
reveals, `StatsService` (32 lifetime stats), next-unlock hint on the main menu, progress summary on the
Progress screen. Tests: `test_progression_*.gd` (59), `test_stats_*.gd` (21),
`test_app_flow.gd` (first clear unlocks the next level).

## 9. Economy Audit

Coins and gems with a ledger (bounded), never negative, per-grant caps and balance caps,
`IntegrityMonitor` anomaly detection (no punishment), data-driven rewards (first clear, new stars,
replay floor, first-perfect gems and badge), optional rewarded-ad double of currency only. The UI
animates exactly the granted bundle (`test_app_flow.gd` asserts the balance moves by exactly the shown
bundles). No energy, no paid continues, no loot boxes. Tests: `test_economy_*.gd` (38),
`test_rewards_*.gd` (49).

## 10. Cosmetic Audit

112 items in 9 categories (core skins 19 with 10 animated shader styles, trails 12 with 8 styles, bursts
9, effects 9, skies 10, themes 8, frames 10, avatars 14, badges 21). Every category now changes
something visible (fixed this round — 81 items had no effect before): bursts recolour/resize neutral
spark, prism and near-miss bursts; effects set fail flash, perfect burst and shockwave strength; skies
replace the world sky; themes recolour the UI; avatar + frame + badge form the profile emblem on the
menu and Progress. The shop states each item's effect, price and any shortfall before purchase.
Tests: `test_cosmetics_*.gd` (72), `test_particle_effect_and_background_cosmetics_change_the_view`,
`test_theme_cosmetic_recolours_the_ui_and_default_restores_it`, `test_shop_says_what_an_item_changes`.
Remaining: 9 of the 19 core skins reuse one of the 10 shader styles with new colours/speed.

## 11. Daily/Weekly System Audit

`DailyChallengeService`: one level per UTC date from the date seed (same for everyone), weekday
difficulty, first-completion reward by streak tier 1–7 with gentle decay, clock-back protection, honest
reset countdown (localized units), rank among the player's own dailies on the result card and the Daily
screen, remote pause switch (`daily.enabled`, missions stay). Optional once-a-day bonus chest (rewarded
ad only when one can play). `MissionService`: 3 daily + 3 weekly missions, deterministic per period,
progress from stat baselines, explicit claim. Tests: `test_online_daily_*.gd`, `test_meta_missions*.gd`,
`test_daily_rewards_only_first_completion`, `test_remote_tuning.gd`, `test_bonus_chest_is_optional_and_once_a_day`.

## 12. Achievement Audit

82 achievements (progress 14, skill 19, combo 10, collection 13, daily 6, boss 5, mastery 8, secret 7),
each tied to a real stat with a reward; unlocked once, rewarded once, revealed after the run with the
bundle actually granted. Tests: `test_meta_achievements.gd`, `test_meta_achievement_data.gd`.

## 13. Mission Audit

15 daily and 13 weekly templates; daily-capped targets are scaled to what is reachable in the days
left; unclaimed missions expire without penalty; claiming shows the granted bundle. Tests:
`test_meta_missions.gd`, `test_meta_missions_schedule.gd`.

## 14. UI/UX Audit

One design system (`game/src/ui/kit`): 8 px grid tokens, Outfit type scale, one stroke icon system,
five button roles, toggles, segmented controls, safe-area container, screen router with calm transitions
and Android back. 13 screens: main menu (live attract run, profile emblem), worlds, levels, modes, daily,
progress (overview/achievements/leaderboard), shop, collection, settings, HUD, pause, fail, complete,
reward. Touch targets are 88 canvas px (about 48 pt on a 390 pt phone; primary buttons 96 px). All
screens re-captured after the last fixes (`tools/capture_ui.gd`, EN and TR) and reviewed. Fixed this
round: toggles flipping twice per tap, pressable invisible result buttons, missing shop prices, screens
left in the old language after a language change, daily rank, localized time units, endless fail
progress, HUD centring, leaderboard tab state, slider height, reveals over PLAY AGAIN, title band, result
backdrop. Regression tests: `test_ui_regressions.gd`.

## 15. Graphics Audit

One art direction (`docs/ART_DIRECTION.md`): colour roles, "only energy glows", chamfered shape family,
physically motivated material presets, AgX tonemapping with glow threshold 1.0, depth fog, per-world
environment data. Ten structure profiles and ten silhouettes. Quality presets drive glow and ambient
particles; atmosphere capped at 8 % opacity; environment colours clamped to the doc's caps
(`WorldTheme.quiet`, S ≤ 0.45 / V ≤ 0.55, tested for every world); Deep Ocean caustics painted into the
floor albedo (no emissive matter); collectibles pop 1 → 1.25 → 0 in 120 ms; Reduce Motion and
Colour-blind shape markers; ink veil between worlds; the floor's lane lips breathe with the music.
Rendered and reviewed for every world.
See the ANTI-AI-SLOP VISUAL AUDIT.

## 16. Audio Audit

Original procedural audio (`tools/audio/synth_bank.py`, deterministic): 31 SFX, 10 worlds × (base loop,
intensity stem, boss loop) + menu + two stingers. `AudioService`: pooled voices, combo pitch steps and
shimmer, intensity stem following the live combo (reset per run), boss loops for bosses and challenges
(every boss-rush boss), level-complete/perfect stingers (they never played before this round: wrong
names), beat signal driving the floor, background prefetch of the next world's music
(`AsyncLoader`). Tests: `test_feel_audio*.gd`, `test_async_music.gd`, app-flow audio checks. On-device
mix not verified.

## 17. Haptics Audit

`HapticsService`: per-event patterns, 40 ms global floor, per-kind rate limits, opt-out, battery saver
halves amplitude, gameplay feedback fan-out, reward haptics on star and reward landings. Tests:
`test_feel_haptics.gd`. Real vibration on hardware not verified.

## 18. Mobile Compatibility Audit

Portrait 720×1280 canvas with `expand` stretch, safe-area insets on every screen (`SafeAreaContainer`;
simulated notch, punch-hole, 16:9 and 4:3 tablet devices in `test_safe_area.gd`), immersive mode on
Android, back routed through the UI, one pointer source per control, pause on focus loss/app pause,
pending runs applied and saves flushed on pause/close. Not verified on physical devices.

## 19. Performance Audit

Fixed-step sim with bounded steps per frame; pooled entity nodes; sparks and ribs in single MultiMeshes;
pooled burst particles never above their budget; trail as one ImmediateMesh; no scene reload on restart;
endless streaming one slot per frame with compaction; no per-frame dictionary key copies in the view;
pulse-gate lamp materials written only on change; autosave held while a run is played. Quality presets
(render scale, MSAA, fps cap, post FX, glow, ambient particles, particle scale, trail, light, shadows)
with battery saver and automatic downgrade that now reaches the viewport. No on-device FPS measurement.

## 20. Memory Audit

No per-frame allocations in the hot sim path (packed arrays, flat event buffer); pooled nodes and
MultiMesh reuse; 100 restarts without node growth (`test_restart_is_stable_and_fast`); the test runner
reports engine leaks at exit. Device memory profiling was not possible.

## 21. Save/Load Audit

Versioned envelope with SHA-256 checksum, atomic temp+rename writes, backup rotation only from a valid
main file, migration from v0, newer-version files preserved, hostile/garbage input recovered to backup
or a new profile with a calm toast, size cap on reads, type-safe profile parsing
(`test_profile_hostile.gd`). Debounced saves plus flush on pause/focus loss/close. Tests:
`test_save_*.gd` (66).

## 22. Offline Audit

Offline-first: campaign, modes, daily (generated locally), missions, achievements and cosmetics need no
network. Leaderboard submissions are queued (bounded, deduplicated, persisted on change) and flushed at
boot, on reconnect and after any successful server answer; a 2xx without a verdict stays queued.
Analytics HTTP sink queues offline; remote config falls back to cache and accepts only a values
snapshot. Tests: `test_online_leaderboard_service.gd`, `test_platform_network.gd`,
`test_platform_remote_config.gd`.

## 23. Security Audit

Untrusted inputs (save files incl. typed profile flags, replays, remote config, server responses, crash
reports) are type-checked before use; URL guard refuses credentials and `?`/`#` host tricks (also for
remote-config URLs); display names stripped of control, bidi, invisible and line-separator marks; no
secrets in the repository; signing material ignored by git. Module reviews fixed 1 critical / 31 major;
the integrated review and an independent security reviewer found 3 more critical and 5 major
security/data issues, all fixed (`docs/CODERABBIT_REPORT.md`).

## 24. Anti-Cheat / Anti-Fraud Audit

The client is not trusted for ranked features: submissions carry replays; `ReplayVerifier` re-simulates
with shared mode rules and rejects score mismatches, impossible tap rates, sim-version mismatches, wrong
level kinds, stale/future dailies, incomplete runs and malformed fields; streamed courses rank only on
their seed's weekly board and are refused cheaply (unranked mode, unofficial seed, over-long run)
before the server rebuilds them. Reward claims are bounded by what the content pays (daily tier reward,
level reward ceiling, scaled like the live remote tuning) and need one verified run each; daily and
stream ids are never level rewards. `IntegrityMonitor` runs after load and every run; anomalies go to
analytics once per session and travel with submissions for review. No hosted backend runs the verifier
yet (REQ-177/178/179 PARTIAL).

## 25. Analytics Audit

Schema-whitelisted events (the 14 listed in the brief plus achievement, mission, quality, save,
error, tutorial, settings, world events), typed parameters, forbidden PII names dropped, session id
only (no device identifiers), opt-in consent (off by default), file sink + optional HTTP sink with an
offline queue, crash reports forwarded. Tests: `test_platform_analytics*.gd` (29).

## 26. Code Quality Audit

Full static typing, `class_name` per reusable class, constructor injection, data-driven tunables, doc
comments, `gdlint` clean on `src`, `tests`, `tools`, `server` (`Success: no problems found`). Known
debt: `GameFlow` is large (screen wiring + run flow), many plain `Dictionary` declarations where typed
dictionaries would fit, inline tuning literals in presentation code (REQ-235/237/239 PARTIAL).

## 27. Dependency Audit

Runtime: Godot only. Dev: gdtoolkit 4.5.0, numpy (audio tool), Python 3.11. Font from
`@fontsource/outfit` 5.3.0. Reference repositories inspected but not used are listed with reasons in
`docs/REPOSITORIES.md`.

## 28. Open Source License Audit

`game/assets/LICENSES.json` lists fonts (OFL-1.1 with `OFL.txt`), audio and icons (original);
`python3 tools/ci/license_check.py` → `0 problem(s), 3 manifest entries`. Settings → Licences shows the
asset licences, the Godot MIT licence text (`Engine.get_license_text()`) and the engine's third-party
components (`Engine.get_copyright_info()`).

## 29. Dead Code Audit

Probe: every `func` in `game/src` whose name appears nowhere else in `game/` (scripts, scenes, data,
shaders). The final probe found 20 never-called functions (`LevelSpec.form_list`, `ScreenRouter.has_screen`,
`UiButton.set_glyph_color`, `CosmeticsScreen._color`, `AudioService.current_beat`, `Localization.locales`,
`AnalyticsService.remove_sink`, `MemoryAnalyticsSink.with_name`, `SimConst.is_collectible`,
`RunResult.grade_name` + `GRADE_NAMES`, `EndlessStreamer.extend_to`, `CoreView.flash_pulse`,
`GameplayView.active_entity_count`, `NodePool.release_all`, `GameClock.clear_fixed`, `JsonIO.read_array`,
`DetRng.get_state`, `DetRng.combine`, `GameStateMachine.is_in`, `AsyncLoader.cached_count`); all were
removed. Kept on purpose: `ErrorReporter._log_message` (engine `Logger` callback) and the
`NodePool.active_count/free_count` diagnostics. Brought into use earlier this round: `AsyncLoader` (music
prefetch), the `ENDLESS` state (streamed runs), the music pulse (drives the floor). A tracked Python
bytecode file was removed from git and ignored. Import is clean and 746 tests pass after the
removals. The unrelated legacy web project at the repository root is not part of the game.

## 30. Placeholder Asset Audit

No placeholder assets: all audio is synthesised by the project tool, meshes are procedural, icons are
vector code, the font is a licensed release. `python3 tools/ci/placeholder_scan.py` → `0 hit(s)`.

## 31. Mock / Fake Data Audit

No fake players, fake prices, fake odds or fake rewards: leaderboards show only real local entries
offline; the store says "unavailable" with the null provider; rewards shown are the granted bundles;
test doubles live only under `game/tests` and are named `Memory…`, `Scripted…`, `Recording…`.

## 32. Testing Audit

`godot --headless --path game -s res://tests/run_tests.gd` → `746 tests, 0 failed`. Coverage: sim
rules and determinism, generator/validator (every code)/solver, set pieces, modes and streaming, every
system module, save corruption/recovery/migration, verifier (genuine, tampered, malformed, streamed,
pre-checks, reward-claim bounds), app flow end to end, UI and view regressions, remote tuning, state
machine, simulated devices, async loading. The runner fails tests that hit script errors. The brief's
manual-test list: all 520 levels are played by their stored solutions in the validator; 15 screens
and every world were reviewed in captures — no human played on a phone (REQ-266 PARTIAL).

## 33. Build Audit

Android: `godot --headless --path game --export-debug "Android" build/android/fluxdrop-debug.apk` →
64 MB APK, `apksigner verify`: v2 and v3 verified, 520 level files packaged. Release AAB/APK:
BLOCKED (no release keystore). iOS: `--export-debug "iOS"` with a team ID produced the Xcode project
(FluxDrop.xcodeproj, frameworks, 13 MB .pck) on Linux; compiling and signing need macOS (BLOCKED). CI
(`.github/workflows/ci.yml`, valid YAML) runs lint, scans, import, tests, validation, regeneration diff,
Android export and the iOS export + unsigned simulator build; it has not been observed running on GitHub.

## 34. Runtime Audit

The game boots headless and under Xvfb without script errors: main scene test, full UI captures (EN/TR)
and level captures for all worlds; the only runtime message under Xvfb is the missing audio device. The
global error reporter captures runtime errors with state, level, version and platform.

## 35. CodeRabbit Audit

See `docs/CODERABBIT_REPORT.md`. CodeRabbit: **BLOCKED** (CLI cannot be installed: host refused by the
network policy; npm 404). Substitute independent reviews: 8 module reviews (95 findings: 1 critical,
31 major, 63 minor — 89 fixed in module, 4 fixed at integration, 2 documented limits) and the
integrated review R-INT summarised below.

<!-- RINT:BEGIN -->
Integrated review R-INT (details and per-milestone table in `docs/CODERABBIT_REPORT.md`):

| Review | Found | Critical | Major | Minor | Open |
|---|---|---|---|---|---|
| Module reviews (8) | 95 | 1 | 31 | 63 | 0 (2 accepted, documented limits) |
| R-INT round 1 (app flow, gameplay core) | 22 | 4 | 11 | 7 | 0 |
| R-INT round 2 (UI, view + performance, security + data) | 32 | 7 | 17 | 8 | 0 |
| Independent security/data reviewer | 10 | 1 | 2 | 7 | 0 |
| R-STATUS (requirement assessment) | 23 | 0 | 6 | 17 | 0 |
| R-FINAL (final review of the last fix round) | 5 | 0 | 0 | 5 | 0 (4 fixed, 1 by design) |
| **Total** | **187** | **13** | **67** | **107** | **0** |

Every finding was reproduced before fixing; R-INT findings were adversarially verified by a second
agent; fixes carry regression tests. The final review (R-FINAL, the brief's "final CodeRabbit" step)
found no critical or major defect in the last fix round. No CodeRabbit run exists (BLOCKED).
<!-- RINT:END -->

## 36. Critical Issues

<!-- CRITICAL:BEGIN -->
**Open critical code issues: none.** All 13 critical findings from the reviews are fixed with tests.

Critical for a store release but outside this environment (BLOCKED / not done):
1. No release signing and no compiled iOS app (no keystore, no macOS/Xcode/Apple account).
2. No hosted backend: leaderboards are local-only, the replay verifier and reward-claim checks are
   not deployed (REQ-177/178/179).
3. CodeRabbit could not run (CLI unreachable); substitute reviews only.
4. No on-device validation (performance, battery, thermal, haptics, touch) and no human playtests.
<!-- CRITICAL:END -->

## 37. Major Issues

<!-- MAJOR:BEGIN -->
Open major gaps (PARTIAL requirements, not hidden):
1. Content/design: no physics, stacking or true gravity mechanics (reinterpreted as kinematic forms,
   charges and weight — REQ-046/050/058); "Stars" is not a grantable reward type (REQ-148); late
   chapters remix earlier mechanics (REQ-064); slider/current/portal have no dedicated teaching hint
   (REQ-079); live difficulty tuning is deliberately not remote (REQ-245).
2. Visual: flat materials without texture maps, primitive geometry, no reflections or volumetrics,
   shadows off by default on mobile, 9 of 19 core skins are recolours (REQ-106–114, 155, 302, 303,
   305, 310, 312, 322–328).
3. Platform: no cloud save (REQ-182), no texture atlas (REQ-202), no scene streaming beyond course and
   music streaming (REQ-207), no draw-call/memory budget tooling or profiling (REQ-205/210/271).
4. Code health: large `GameFlow`, few typed dictionaries, inline tuning literals (REQ-235/237/239).
5. Process: CI not yet observed running; CodeRabbit report written at integration, not per milestone
   (REQ-265/283).
<!-- MAJOR:END -->

## 38. Remaining Work

1. iOS build and signing on macOS with an Apple team; Android release keystore and Play Console upload.
2. Run CodeRabbit on each milestone range once the CLI is reachable; watch the first CI run.
3. Host the replay verifier and leaderboard/analytics/remote-config endpoints; set
   `leaderboard.base_url`, `analytics.endpoint`, `config.url`; add cloud save.
4. Integrate real ad, IAP and push SDKs behind the existing provider interfaces.
5. On-device profiling (FPS, memory, battery, thermal) on low/mid/high Android and iOS devices; tune
   presets; decide on mobile shadows.
6. Human playtests (first-time users, difficulty around levels 20–60 and 150–260) and a human art
   director's pass (materials, geometry richness, more distinct core-skin styles).
7. Trademark/name clearance for "FLUX DROP"; store listing assets.

## 39. Production Readiness

Gameplay, content, progression, economy, save, offline, UI and the anti-cheat client/verifier are
production-structured and tested. The product is **not yet shippable** to stores: release signing, the
iOS build, a hosted backend, SDK accounts, on-device validation, playtests and an art pass are missing.
A soft-launch Android build is close once a release keystore is configured and device testing is done.

**Self-evaluation (answered from evidence, not from players):**

| Question | Answer |
|---|---|
| Is it fun? | Unknown without players. The loop has quick retries, combo/overdrive and set pieces; not playtested. |
| Understood in 10 s? | Likely: tutorial levels of 6–14 s with tap hints on the stored solution; unverified by people. |
| Do players want to replay? | Systems for it exist (stars, perfects, dailies, weekly boards, missions); no retention data. |
| Is level 100 interesting? | It is a different mechanic mix (W2 combination phase) with its own tier; judged from data only. |
| Do mechanics combine? | Yes in data: form gates mix hop/phase/dash/weight; combination phases and bosses mix hazards. |
| Does it look premium? | Clean and consistent, not premium: see the anti-slop audit (5 PARTIAL). |
| Is it responsive? | Input is applied on the next 60 Hz tick; no device latency measurement. |
| Is it mobile-comfortable? | 48 pt targets, safe areas, one-thumb input; no device test. |
| Does it perform? | Budgets and presets exist; no device FPS data. |

## 40. Final Completion Percentage

Computed by `python3 tools/report/completion.py` from the matrix (not estimated):

<!-- SUMMARY:BEGIN -->
| Total requirements | 333 |
|---|---|
| IMPLEMENTED | 251 |
| PARTIAL | 76 |
| NOT_IMPLEMENTED | 2 |
| BLOCKED | 4 |
| **Completion = Implemented / Total × 100** | **75.4 %** |
<!-- SUMMARY:END -->

## ANTI-AI-SLOP VISUAL AUDIT

<!-- SLOP:BEGIN -->
Method: the 12 screens the brief names (main menu, world select, level select, gameplay HUD, pause,
fail, complete, reward, shop, collection, daily, settings — plus modes and progress) were captured with
`tools/capture_ui.gd` after the last fixes (English and Turkish, 540×960, Xvfb + llvmpipe) and every
world was rendered with `tools/capture_level.gd`. Each image was checked against `docs/ART_DIRECTION.md`
(colour roles, "only energy glows", chamfer family, ≤ 8 % atmosphere, one icon system, type scale,
calm motion). Grades are strict: PASS only when nothing in the category contradicts the art direction.

| # | Category | Grade | Evidence | Remaining gap |
|---|---|---|---|---|
| 1 | Visual consistency | PASS | One palette with fixed roles (`src/art/palette.gd`), one Theme (`UiTheme`), one icon system (`IconGlyph`), every screen on the same 8 px grid; final captures show no off-style screen | — |
| 2 | Texture quality | PASS | No bitmap textures to degrade: surfaces are procedural shaders and vertex colours; the only generated textures (soft mote, slider grabber) are analytic gradients | — |
| 3 | Material quality | PARTIAL | Physically motivated presets (matte structure, glass hazards, metal ribs) with AgX tonemapping | No texture/normal/roughness maps; metal and stone read as plain matte colours in software renders; not seen on a phone GPU |
| 4 | Lighting consistency | PASS | Per-world key light, ambient and depth fog from world data; one tonemapper; glow threshold 1.0 so only HDR energy blooms | — |
| 5 | UI consistency | PASS | Five button roles, cards, toggles, segments, toasts from one kit; consistent header/back pattern; result screens share one layout | — |
| 6 | Iconography | PASS | 2-unit stroke icons on a 24-unit grid for every glyph; app icon redrawn flat in the palette (no gradients, no halo) | — |
| 7 | Typography | PASS | Outfit (OFL) with a fixed scale (H1/H2/H3/Body/Caption/Score/Button/Reward), tracked caps only for captions and buttons | — |
| 8 | Animation consistency | PARTIAL | One motion language (24 px slide + fade, 0.96 press / 1.02 settle, back-eased stars, ease-out counts) in `UiTokens`/`UiButton`/`UiScreen` | Reviewed from code and stills only; never watched in motion on a device |
| 9 | VFX consistency | PASS | Pooled bursts with per-preset budgets (never exceeded), only energy is emissive, atmosphere capped at 8 % opacity, chromatic aberration only on fail/overdrive | — |
| 10 | Environment quality | PARTIAL | Ten worlds with distinct structure profiles, silhouettes, skies and atmospheres | Geometry is primitive (chamfered boxes, simple silhouettes); scenes read sparse next to commercial games |
| 11 | Asset reuse quality | PARTIAL | Hazards reuse one chamfer family on purpose (readability) | 9 of the 19 core skins reuse one of the 10 shader styles with new colours/speed |
| 12 | Procedural generation quality | PASS | Levels generated around a planned tap path and proven by an independent validator (520/520, worst window 183 ms); procedural meshes follow the chamfer and rib grammar | — |
| 13 | Originality | PASS | Original mechanic (one tap whose meaning follows the core's form), own names, own audio synthesiser, no third-party art | — |
| 14 | AI-artifact inspection | PASS | No AI-generated images, audio or fonts in the project; captures show no smeared text, warped glyphs, random neon pairs, meaningless gradients or glow-on-everything | — |
| 15 | Overall human-made appearance | PARTIAL | Restrained, consistent and readable | Simple geometry and flat materials; no human art director has reviewed it; not commercial-release grade yet |

Result: **10 PASS, 5 PARTIAL, 0 FAIL.** No category fails, so nothing was left unfixed at FAIL level.
The PARTIAL items are why the overall status is not COMPLETED (the brief forbids COMPLETED until the
art bar is met): materials, motion review on a device, environment richness, core-skin variety and a
human art pass remain.
<!-- SLOP:END -->
