# FLUX DROP — Requirements Checklist

Created **before development started** (2026-10-03) from the one-shot master brief.
Every requirement in the brief has a stable ID. The status of each ID (REQ-001 … REQ-333) is reported, with code
evidence, in [`FINAL_IMPLEMENTATION_REPORT.md`](FINAL_IMPLEMENTATION_REPORT.md).
`tools/report/completion.py` cross-checks that every ID below appears exactly once in the
final report matrix and computes the completion percentage from it.

Format: `| ID | Area | Requirement |`

## A. Process & originality

| ID | Area | Requirement |
|---|---|---|
| REQ-001 | Process | Do not ask the user questions; take professional decisions autonomously. |
| REQ-002 | Process | Complete the work in a single working session as far as possible. |
| REQ-003 | Process | Create `docs/REQUIREMENTS_CHECKLIST.md` listing every requirement with an ID before development. |
| REQ-004 | Process | Follow the mandated 20-step ordering (inspect → architecture → prototype → … → final report). |
| REQ-005 | Originality | The game is fully original and not a clone of any existing game. |
| REQ-006 | Originality | Do not copy names, characters, maps, UI, sounds, animations or distinctive mechanic combinations of Ketchapp/Voodoo games. |
| REQ-007 | Originality | Use only abstracted, industry-level design principles from successful hyper-casual games. |
| REQ-008 | Originality | Use "FLUX DROP" as working name or produce a better original name. |

## B. Core design pillars & core loop

| ID | Area | Requirement |
|---|---|---|
| REQ-009 | Pillars | Extremely simple control structure. |
| REQ-010 | Pillars | Game is understandable within the first 5 seconds. |
| REQ-011 | Pillars | Player has fun within the first 15 seconds. |
| REQ-012 | Pillars | Player wants to retry within 30 seconds ("one more try"). |
| REQ-013 | Pillars | Short play sessions. |
| REQ-014 | Pillars | Near-instant restart with no unnecessary loading. |
| REQ-015 | Pillars | PLAY AGAIN is reachable very quickly after failing. |
| REQ-016 | Pillars | Physical and visual satisfaction. |
| REQ-017 | Pillars | Level-based progression. |
| REQ-018 | Pillars | Mechanics unlock gradually. |
| REQ-019 | Pillars | Combo system. |
| REQ-020 | Pillars | Collectible structure. |
| REQ-021 | Pillars | Skin / cosmetic progression. |
| REQ-022 | Pillars | Missions. |
| REQ-023 | Pillars | Daily content. |
| REQ-024 | Pillars | High replayability. |
| REQ-025 | Pillars | Satisfying sound / haptics / particle feedback. |
| REQ-026 | Core loop | Player controls a small, visually high-quality energy core. |
| REQ-027 | Core loop | The core advances automatically. |
| REQ-028 | Core loop | TAP changes the core's current movement behaviour. |
| REQ-029 | Objectives | Pass obstacles with correct timing. |
| REQ-030 | Objectives | Collect energy objects. |
| REQ-031 | Objectives | Interact correctly with colour / energy types. |
| REQ-032 | Objectives | Build combos. |
| REQ-033 | Objectives | Avoid collisions. |
| REQ-034 | Objectives | Pass through special gates. |
| REQ-035 | Objectives | Maximise score. |
| REQ-036 | Objectives | Complete per-level objectives. |
| REQ-037 | Objectives | Perfect runs. |
| REQ-038 | Core loop | The same input turns into very different behaviours as levels progress. |
| REQ-039 | Core loop | Simple to learn, hard to master; systems deepen gradually. |
| REQ-040 | Durations | Level durations: beginner 5–15 s, mid 10–30 s, advanced 20–60 s, special challenges 60–120 s. |

## C. Mechanic families (combined into a new system, not copied one by one)

| ID | Area | Requirement |
|---|---|---|
| REQ-041 | Mechanics | Timing. |
| REQ-042 | Mechanics | Lane switching. |
| REQ-043 | Mechanics | Tapping. |
| REQ-044 | Mechanics | Dodging. |
| REQ-045 | Mechanics | Collecting. |
| REQ-046 | Mechanics | Stacking. |
| REQ-047 | Mechanics | Colour matching. |
| REQ-048 | Mechanics | Moving platforms / moving obstacles. |
| REQ-049 | Mechanics | Momentum. |
| REQ-050 | Mechanics | Physics. |
| REQ-051 | Mechanics | Risk / reward. |
| REQ-052 | Mechanics | Chain reactions. |
| REQ-053 | Mechanics | Near miss. |
| REQ-054 | Mechanics | Precision. |
| REQ-055 | Mechanics | Rhythm-like timing. |
| REQ-056 | Mechanics | Destructible objects. |
| REQ-057 | Mechanics | Portals. |
| REQ-058 | Mechanics | Gravity changes. |
| REQ-059 | Mechanics | Magnetic interaction. |
| REQ-060 | Mechanics | Teleport. |
| REQ-061 | Mechanics | Temporary power states. |
| REQ-062 | Mechanics | Reaction chains (cascading triggers). |
| REQ-063 | Mechanics | Families are fused into a new original system rather than copied individually. |
| REQ-064 | Mechanics | A new main idea is introduced every 10–20 levels ("same game, new trick"). |

## D. Level system

| ID | Area | Requirement |
|---|---|---|
| REQ-065 | Levels | Minimum 500 playable levels. |
| REQ-066 | Levels | Data-driven level system. |
| REQ-067 | Levels | Each level stored as separate data. |
| REQ-068 | Levels | Level data contains: ID, difficulty, mechanics, speed, spawn configuration, hazards, collectibles, objective, score target, perfect target, combo target, environment, music, visual theme, unlock requirements. |
| REQ-069 | Levels | Level generation is deterministic. |
| REQ-070 | Levels | Seed-supported generation. |
| REQ-071 | Levels | Every level is playable. |
| REQ-072 | Levels | Every level is solvable. |
| REQ-073 | Levels | Every level is fair (unfair levels forbidden; losses feel self-inflicted). |
| REQ-074 | Levels | Every level is testable. |
| REQ-075 | Levels | Every level is reproducible. |
| REQ-076 | Levels | Adding a new level is as easy as adding new data. |

## E. Difficulty structure

| ID | Area | Requirement |
|---|---|---|
| REQ-077 | Difficulty | Difficulty does not rise randomly; it follows a designed structure. |
| REQ-078 | Difficulty | Stages: Tutorial, Early Game, Core Learning, Mechanic Expansion, Combination Mechanics, Advanced Timing, Expert, Master, Challenge, Endgame. |
| REQ-079 | Difficulty | Every new mechanic is first taught safely. |
| REQ-080 | Difficulty | Each mechanic follows Introduction → Mastery → Combination → High Pressure. |
| REQ-081 | Difficulty | Mechanics are later combined with older ones across the whole game (e.g. single obstacle → colour → moving → colour+moving → gravity → gravity+colour+moving). |
| REQ-082 | Difficulty | First world is very easy; later worlds progressively more complex. |
| REQ-083 | Difficulty | Player fully learns the base mechanic within the first 20–30 levels. |
| REQ-084 | Difficulty | The game as a whole is not excessively hard. |

## F. Feedback / game feel

| ID | Area | Requirement |
|---|---|---|
| REQ-085 | Feedback | Every successful input produces small but high-quality feedback. |
| REQ-086 | Feedback | Anticipation. |
| REQ-087 | Feedback | Squash / stretch. |
| REQ-088 | Feedback | Scale punch. |
| REQ-089 | Feedback | Rotation. |
| REQ-090 | Feedback | Elastic easing. |
| REQ-091 | Feedback | Particles. |
| REQ-092 | Feedback | Glow. |
| REQ-093 | Feedback | Bloom. |
| REQ-094 | Feedback | Trails. |
| REQ-095 | Feedback | Screen shake. |
| REQ-096 | Feedback | Impact flash. |
| REQ-097 | Feedback | Hit stop. |
| REQ-098 | Feedback | Slow-motion micro effect. |
| REQ-099 | Feedback | Combo burst. |
| REQ-100 | Feedback | Camera impulse. |
| REQ-101 | Feedback | Dynamic lighting. |
| REQ-102 | Feedback | Controlled chromatic-like effect. |
| REQ-103 | Feedback | Distortion where appropriate. |
| REQ-104 | Feedback | No effect spam; feedback stays readable. |
| REQ-105 | Feedback | Feedback chain TAP → movement → sound → haptic → visual impact → score feedback. |

## G. Graphics & visual identity

| ID | Area | Requirement |
|---|---|---|
| REQ-106 | Graphics | Very high graphical quality; premium mobile look. |
| REQ-107 | Graphics | Stylized high-end 3D / 2.5D. |
| REQ-108 | Graphics | High-quality materials (PBR approach where needed). |
| REQ-109 | Graphics | Realistic but stylized lighting. |
| REQ-110 | Graphics | Quality shaders. |
| REQ-111 | Graphics | Volumetric-looking effects. |
| REQ-112 | Graphics | Emissive materials. |
| REQ-113 | Graphics | Dynamic shadows. |
| REQ-114 | Graphics | Reflections where needed. |
| REQ-115 | Graphics | Environment ambience. |
| REQ-116 | Graphics | Polished UI animations. |
| REQ-117 | Graphics | Premium typography. |
| REQ-118 | Graphics | Depth and parallax. |
| REQ-119 | Graphics | Camera movement. |
| REQ-120 | Graphics | Polished post-processing. |
| REQ-121 | Graphics | Vivid but controlled colour palette. |
| REQ-122 | Graphics | Every world has its own visual identity. |
| REQ-123 | Assets | All assets original; no copyrighted assets. |
| REQ-124 | Assets | Any open-source asset is license-checked. |
| REQ-125 | Assets | Procedural / original art wherever possible. |
| REQ-126 | Identity | Distinctive visual language recognisable from a single screenshot. |
| REQ-127 | Identity | Signature elements: core look, energy trail, level transition, combo explosion, world transitions, collectible animation, fail effect, perfect effect. |

## H. Controls

| ID | Area | Requirement |
|---|---|---|
| REQ-128 | Controls | One touch; main control is TAP. |
| REQ-129 | Controls | Hold / swipe / drag only optionally in later sections, never complicating the start. |
| REQ-130 | Controls | Large touch areas. |
| REQ-131 | Controls | Reduced accidental touches. |
| REQ-132 | Controls | Minimum input latency. |

## I. Combo, grades, stars

| ID | Area | Requirement |
|---|---|---|
| REQ-133 | Combo | Combo raises score multiplier, visual intensity, particles, sound layering, haptic response and collectible bonus. |
| REQ-134 | Combo | Combo system is not overly complex. |
| REQ-135 | Grades | Per-level performance grades Normal / Good / Great / Perfect. |
| REQ-136 | Grades | Perfect is very hard but learnable. |
| REQ-137 | Grades | Perfect completion grants star, badge, bonus currency and cosmetic unlock progress. |
| REQ-138 | Stars | 1–3 stars per level (1 = cleared, 2 = high score, 3 = perfect). |
| REQ-139 | Stars | Star totals unlock worlds, cosmetics and challenges. |

## J. Economy, monetization & ethics

| ID | Area | Requirement |
|---|---|---|
| REQ-140 | Economy | No crypto, blockchain, Web3 or NFT. |
| REQ-141 | Economy | Currencies: Coins (normal gameplay) and Gems (rare rewards). |
| REQ-142 | Economy | No pay-to-win; progress possible with skill alone. |
| REQ-143 | Monetization | Monetization architecture ready. |
| REQ-144 | Monetization | Interstitials only at natural breakpoints. |
| REQ-145 | Monetization | Rewarded ads are optional (revive, double reward, bonus chest). |
| REQ-146 | Monetization | The player is never forced to watch ads. |
| REQ-147 | Monetization | Premium offers are cosmetic only (Cosmetic Pack, Theme Pack, Starter Cosmetic Bundle); no gameplay advantage sold. |
| REQ-148 | Rewards | Data-driven reward engine with types Coins, Gems, Skin, Trail, Badge, Stars, XP. |
| REQ-149 | Rewards | No fake reward animations; rewards bound to real state. |
| REQ-150 | Ethics | No dark patterns: fake close buttons, forced ads, misleading purchases, aggressive FOMO, deceptive countdowns, hidden fees, fake rewards, notification spam, deliberately frustrating losses, rigged matchmaking, pay-to-win. |
| REQ-151 | Ethics | Retention only through healthy mechanics (short levels, mastery, perfect, leaderboard, collection, cosmetics, daily challenge, personal best, combo mastery, achievements, world progression). |
| REQ-152 | Ethics | No predatory monetization, fear-based retention, deceptive UX, forced engagement, fake urgency or abusive notifications. |

## K. Cosmetics & progression

| ID | Area | Requirement |
|---|---|---|
| REQ-153 | Cosmetics | Many cosmetics: core skins, trails, particles, backgrounds, themes, effects, badges, frames, avatars. |
| REQ-154 | Cosmetics | Cosmetics never alter gameplay. |
| REQ-155 | Cosmetics | Skins (Fire, Ice, Plasma, Void, Crystal …) each have quality animation, not just a recolour. |
| REQ-156 | Progression | XP, player level, stars, coins, gems, achievements, daily challenges and collection systems. |
| REQ-157 | Progression | Unlock tree / visible "next thing to unlock". |

## L. Worlds & special levels

| ID | Area | Requirement |
|---|---|---|
| REQ-158 | Worlds | At least 10 worlds. |
| REQ-159 | Worlds | 40–60 levels per world. |
| REQ-160 | Worlds | Each world has unique lighting, materials, hazards, music, particles and boss/challenge mechanic. |
| REQ-161 | Worlds | Special end-of-world levels that differ from normal levels (rotating machine, escape sequence, fast obstacle field, pattern recognition, chain-reaction puzzle, survival sequence). |
| REQ-162 | Worlds | World data drives theme, background, hazards, palette, audio, environment, lighting, particles, mechanics. |

## M. Game modes

| ID | Area | Requirement |
|---|---|---|
| REQ-163 | Modes | CLASSIC mode playable at launch. |
| REQ-164 | Modes | Architecture supports ENDLESS. |
| REQ-165 | Modes | Architecture supports TIME ATTACK. |
| REQ-166 | Modes | Architecture supports DAILY CHALLENGE. |
| REQ-167 | Modes | Architecture supports PERFECT RUN. |
| REQ-168 | Modes | Architecture supports ZEN MODE. |
| REQ-169 | Modes | Architecture supports HARD MODE. |
| REQ-170 | Modes | Architecture supports BOSS RUSH. |

## N. Daily / weekly / achievements

| ID | Area | Requirement |
|---|---|---|
| REQ-171 | Daily | New deterministic daily challenge every day (server-side or controlled deterministic seed). |
| REQ-172 | Daily | Daily result shows score, rank and reward. |
| REQ-173 | Daily | Streak system with Daily 1/2/3 bonuses; missing a day is not punitive. |
| REQ-174 | Missions | Daily missions (play 5 levels, get 3 perfects, collect 100 energy, reach x10 combo, finish without damage …). |
| REQ-175 | Missions | Weekly missions with longer-term goals. |
| REQ-176 | Achievements | At least 50 achievements (First Perfect, 100 Collectibles, 10 Combo, 50/100 Levels, No Miss, Perfect World, Fast Clear, High Combo, Daily Master, Boss Master …). |

## O. Online, leaderboard, anti-cheat, offline

| ID | Area | Requirement |
|---|---|---|
| REQ-177 | Leaderboard | Global leaderboard architecture with Daily / Weekly / All Time boards. |
| REQ-178 | Anti-cheat | Server validation against score manipulation; the client is not trusted. |
| REQ-179 | Anti-cheat | Server-backed checks for leaderboard scores, daily scores, reward claims and suspicious progression. |
| REQ-180 | Offline | Core gameplay works without internet. |
| REQ-181 | Online | Internet features (leaderboard, cloud save, analytics sync, daily challenge, remote config) degrade gracefully offline. |
| REQ-182 | Online | Cloud save architecture. |

## P. Save & settings

| ID | Area | Requirement |
|---|---|---|
| REQ-183 | Save | Local save of progress, settings, unlocks, currency, completed levels, stars, achievements. |
| REQ-184 | Save | Corrupted save recovery. |
| REQ-185 | Save | Versioned save structure with migrations. |
| REQ-186 | Settings | Sound setting. |
| REQ-187 | Settings | Music setting. |
| REQ-188 | Settings | Haptics setting. |
| REQ-189 | Settings | Notifications setting. |
| REQ-190 | Settings | Graphics quality setting. |
| REQ-191 | Settings | Battery saver setting. |
| REQ-192 | Settings | Language setting. |
| REQ-193 | Settings | Restore purchases. |

## Q. Mobile platform

| ID | Area | Requirement |
|---|---|---|
| REQ-194 | Mobile | Targets iOS and Android. |
| REQ-195 | Mobile | Safe-area support. |
| REQ-196 | Mobile | Works correctly on different aspect ratios. |
| REQ-197 | Mobile | Handles notch, Dynamic Island, punch-hole, tablet, small phone. |
| REQ-198 | Mobile | Touch targets are large enough. |

## R. Performance

| ID | Area | Requirement |
|---|---|---|
| REQ-199 | Performance | FPS targets: high-end 60, mid-range stable 60 where possible, low-end fallback quality. |
| REQ-200 | Performance | Object pooling. |
| REQ-201 | Performance | Batching. |
| REQ-202 | Performance | Texture atlas. |
| REQ-203 | Performance | Shader optimization. |
| REQ-204 | Performance | Particle limits. |
| REQ-205 | Performance | Memory management. |
| REQ-206 | Performance | Async loading. |
| REQ-207 | Performance | Scene streaming. |
| REQ-208 | Performance | Lightweight UI. |
| REQ-209 | Performance | Caching. |
| REQ-210 | Performance | Draw-call control. |
| REQ-211 | Performance | Avoid unnecessary allocations / GC pressure. |
| REQ-212 | Performance | Quality presets Low / Medium / High / Ultra. |
| REQ-213 | Performance | Automatic runtime quality reduction when needed. |

## S. Audio & haptics

| ID | Area | Requirement |
|---|---|---|
| REQ-214 | Audio | Button sounds. |
| REQ-215 | Audio | Tap sounds. |
| REQ-216 | Audio | Collision sounds. |
| REQ-217 | Audio | Combo layers. |
| REQ-218 | Audio | Perfect sound. |
| REQ-219 | Audio | Fail sound. |
| REQ-220 | Audio | Reward sound. |
| REQ-221 | Audio | Level-complete music. |
| REQ-222 | Audio | World music. |
| REQ-223 | Audio | Boss / challenge music. |
| REQ-224 | Audio | Audio synchronised with gameplay. |
| REQ-225 | Haptics | Haptics on tap, collect, perfect, hit, combo, level complete, reward — without spam. |

## T. Tutorial, UI/UX, flow

| ID | Area | Requirement |
|---|---|---|
| REQ-226 | Tutorial | Tutorial ≤ 20 s (ideally 5–10 s), no long text, taught through gameplay. |
| REQ-227 | UI | UI is minimal, premium, clean, fast, responsive. |
| REQ-228 | UI | Main screen cleanly organises Play, Progress, Shop, Collection, Daily, Settings. |
| REQ-229 | UI | Gameplay HUD shows score, combo, objective, pause — minimal. |
| REQ-230 | Flow | Level start: camera reveal, environment animation, core spawn, small anticipation. |
| REQ-231 | Flow | Level end: slowdown, perfect explosion, stars, coins, reward, transition; premium level-complete screen. |
| REQ-232 | Flow | State machine with BOOT, MAIN_MENU, WORLD_SELECT, LEVEL_SELECT, COUNTDOWN, PLAYING, PAUSED, FAILED, COMPLETE, REWARD, SHOP, COLLECTION, SETTINGS, DAILY, ENDLESS. |
| REQ-233 | UI | Accessibility considerations (readability, contrast, reduced motion/shake, colour-blind-safe cues). |

## U. Code quality & architecture

| ID | Area | Requirement |
|---|---|---|
| REQ-234 | Code | Modular, clean, typed, maintainable, scalable, testable code. |
| REQ-235 | Code | No God Objects. |
| REQ-236 | Code | Minimise circular dependencies. |
| REQ-237 | Code | Minimise magic numbers. |
| REQ-238 | Code | Data-driven design. |
| REQ-239 | Code | Static typing wherever possible. |
| REQ-240 | Code | Reusable components. |
| REQ-241 | Code | Clear naming. |
| REQ-242 | Code | Error handling. |
| REQ-243 | Code | Logging. |
| REQ-244 | Code | Validation. |
| REQ-245 | Config | Difficulty tuning, reward values, daily challenge, event parameters and economy values changeable later (remote-config ready). |
| REQ-246 | Backend | Architecture is backend-ready even if a backend is not mandatory. |
| REQ-247 | Structure | Professional directory structure. |

## V. Engine, repositories & dependencies

| ID | Area | Requirement |
|---|---|---|
| REQ-248 | Engine | Godot Engine is the main engine (mobile iOS + Android). |
| REQ-249 | Repos | Inspect referenced repos (README, architecture, examples, source, patterns, tests, license) before use. |
| REQ-250 | Repos | Include only genuinely useful approaches/libraries; no unnecessary dependencies. |
| REQ-251 | Repos | Do not copy commercially license-incompatible code or assets. |
| REQ-252 | Repos | Install dependencies only through official package methods. |
| REQ-253 | Repos | `docs/REPOSITORIES.md` lists each repo with reason, module, version, license and affected features. |
| REQ-254 | Repos | PixiJS / Phaser / Zustand only for a real need; never solve the same problem with two frameworks. |

## W. Analytics & error handling

| ID | Area | Requirement |
|---|---|---|
| REQ-255 | Analytics | Event-tracking abstraction with session_started, level_started, level_completed, level_failed, perfect_completed, combo_reached, reward_claimed, shop_opened, purchase_started, purchase_completed, ad_started, ad_completed, daily_started, daily_completed. |
| REQ-256 | Analytics | No unnecessary PII collected. |
| REQ-257 | Errors | Global error handling capturing error log, scene/state, level ID, app version, platform. |

## X. Testing, validation, CI

| ID | Area | Requirement |
|---|---|---|
| REQ-258 | Tests | Unit tests. |
| REQ-259 | Tests | Integration tests. |
| REQ-260 | Tests | Gameplay tests. |
| REQ-261 | Tests | Save tests. |
| REQ-262 | Tests | Economy tests. |
| REQ-263 | Tests | Level validation tests. |
| REQ-264 | Validator | Level validator detects unreachable state, impossible level, spawn collision, invalid sequence, missing objective, missing asset, invalid mechanic, dead-end path, broken trigger at build/test time. |
| REQ-265 | CI | CI pipeline: build, tests, lint/format, import/dependency validation, level validation, asset validation. |
| REQ-266 | QA | Manual test of at least 20 different levels. |
| REQ-267 | QA | Automated level validation executed. |
| REQ-268 | QA | Save/load test. |
| REQ-269 | QA | Scene transition test. |
| REQ-270 | QA | Device aspect test. |
| REQ-271 | QA | Performance test. |
| REQ-272 | QA | Low-quality mode test. |
| REQ-273 | QA | Offline test. |
| REQ-274 | QA | Corrupted data test. |
| REQ-275 | QA | Restart test. |
| REQ-276 | QA | Repeated play test. |

## Y. CodeRabbit continuous review

| ID | Area | Requirement |
|---|---|---|
| REQ-277 | CodeRabbit | Run `coderabbit review --agent` after every major milestone (core prototype, core gameplay, level system, progression, UI, save, economy, daily, mobile optimization, release build). |
| REQ-278 | CodeRabbit | Analyse output for bugs, logic errors, races, performance, memory, security, architecture, abstractions, dead/duplicated code, validation, tests, error handling, maintainability. |
| REQ-279 | CodeRabbit | Issue → task → fix → test → re-run → verify loop; Critical/Major first. |
| REQ-280 | CodeRabbit | At most 2–3 review/fix rounds per milestone (no infinite loop). |
| REQ-281 | CodeRabbit | Do not proceed to release until the CodeRabbit result is clean. |
| REQ-282 | CodeRabbit | Use the existing CodeRabbit auth flow; check CLI installation status. |
| REQ-283 | CodeRabbit | `docs/CODERABBIT_REPORT.md` updated per milestone with Date, Milestone, Commit, Scope, Critical, Major, Minor, Fixed, Remaining, Final status. |

## Z. Documentation, reporting, build & final audit

| ID | Area | Requirement |
|---|---|---|
| REQ-284 | Docs | `README.md` with setup, run, build, test, export, architecture, directories, dependencies, known issues. |
| REQ-285 | Docs | `docs/ARCHITECTURE.md`. |
| REQ-286 | Docs | `docs/GAME_DESIGN.md`. |
| REQ-287 | Docs | `docs/LEVEL_DESIGN.md`. |
| REQ-288 | Report | `docs/FINAL_IMPLEMENTATION_REPORT.md` with per-requirement status (IMPLEMENTED / PARTIAL / NOT_IMPLEMENTED / BLOCKED) and fields ID, Description, Status, Location, Files, Functions/Classes, Tests, Runtime Verification, Notes. |
| REQ-289 | Report | Final report contains all 40 mandated sections. |
| REQ-290 | Report | Completion % computed as Implemented / Total × 100; PARTIAL reported separately. |
| REQ-291 | Hygiene | No TODO / FIXME / TEMP / PLACEHOLDER / MOCK / FAKE DATA left in production code (or explicitly reported). |
| REQ-292 | Hygiene | Demo assets replaced by real assets. |
| REQ-293 | Honesty | Features requiring UI + logic + state + save + validation + test are not reported complete with UI only; unfinished features are not hidden. |
| REQ-294 | Build | Android APK/AAB build path. |
| REQ-295 | Build | iOS Xcode/export pipeline structure. |
| REQ-296 | Build | Signing data is not requested from the user; missing signing is reported as BLOCKED. |
| REQ-297 | Polish | Separate polish pass (animation, timing, easing, particles, sounds, haptics, menus, transitions, typography, spacing, icons, colours, accessibility, loading, restart speed, fail/reward/level-complete screens). |
| REQ-298 | Audit | Self-evaluation questions (fun? understood in 10 s? replay? level 100 interesting? mechanics combine? premium? responsive? mobile-comfortable? performant? production code?) answered from real code/test evidence. |
| REQ-299 | Audit | Final steps executed: git status, build, tests, level validator, dependency check, license check, dead-code check, placeholder check, CodeRabbit, critical fixes, final CodeRabbit, final report, completion %. |
| REQ-300 | Audit | All required documentation files verified to exist. |
| REQ-301 | Audit | Final answer in the mandated format, generated from the real repository state. |

## AA. Art direction — "anti AI-slop" human-made quality (added mid-development, 2026-10-03)

Added from the user's follow-up instruction, before the UI and art polish work. The project may not be
reported **COMPLETED** unless this section is satisfied. The governing rules live in
[`ART_DIRECTION.md`](ART_DIRECTION.md).

| ID | Area | Requirement |
|---|---|---|
| REQ-302 | Art direction | The game must not look AI-generated, "AI slop", a generic asset pack or auto-generated; it must look like a professional studio team polished it for months. |
| REQ-303 | Art direction | Avoid every listed AI-slop trait: generic AI look, meaningless gradients, random neon combinations, excessive glow, bloom on everything, emissive everywhere, plastic materials, meaningless contrast, random detail, lens flare, constant particle rain, heavy volumetric fog, chromatic aberration everywhere, heavy motion blur, artificial reflections, repeating textures, generic sci-fi textures, stock-asset feel, mixed/disconnected styles, wrong proportions, inconsistent perspective, physically meaningless materials, stretching, bad normals, excessive noise, repeating decals/objects, generic icon sets, AI faces, meaningless ornament, asset-pack collisions. |
| REQ-304 | Art direction | One art direction governs everything: shared proportion, shape, material and lighting language, colour theory, visual hierarchy and animation language (documented). |
| REQ-305 | Art direction | Every asset is checked against the art language before inclusion ("does this fit?"). |
| REQ-306 | Shape language | Deliberate geometric language: fixed proportions for gameplay objects, a consistent collectible silhouette, consistent obstacle corners, rule-based environment variation. |
| REQ-307 | Readability | Silhouettes are distinguishable at a glance; gameplay objects separate clearly from the background. |
| REQ-308 | Colour | A colour role system (PRIMARY, SECONDARY, ACCENT, WARNING, SUCCESS, FAILURE); gameplay colours stand out with low clutter; background colours never compete. |
| REQ-309 | Colour | Worlds differ but clearly belong to one brand / visual universe. |
| REQ-310 | Materials | Materials are authored deliberately (roughness, metallic, specular, normal, emission); no "make everything shiny"; stylised but physically consistent (metal, glass, stone, ceramic read as such). |
| REQ-311 | Textures | No stretching, obvious tiling, low-res look, repetition, random noise, meaningless detail or inconsistent scale; textures only with purpose; prefer procedural/authored materials, trim-like systems, atlases, masks. |
| REQ-312 | Reuse | Asset reuse is controlled through variant, scale, material, animation and composition — never copy-paste repetition. |
| REQ-313 | Environment | Layered foreground / midground / background with controlled parallax and depth; never empty, never overpowering gameplay. |
| REQ-314 | Environment | Each world tells its own visual story minimally, without decoration for its own sake. |
| REQ-315 | UI | Grid-based, proportional, consistent spacing, intentional typography, strong hierarchy, responsive, readable; no generic rounded-rect/gradient buttons, random glow, oversized icons or generic glassmorphism; buttons are not clones; all screens share one design system. |
| REQ-316 | Typography | A typography system (H1, H2, H3, Body, Caption, Score, Button, Reward) with few font families and deliberate weights and spacing. |
| REQ-317 | Icons | One icon design system (never mixing 3D, flat, outline, emoji or AI-rendered icons). |
| REQ-318 | Animation | Every animation has a purpose (anticipation, follow-through, squash/stretch, overshoot, settle, acceleration/deceleration) with distinct characters per class (player, collectible, obstacle, button, reward, transition), not one recipe applied everywhere. |
| REQ-319 | VFX | VFX serve gameplay information, impact, reward, progression or atmosphere; no huge explosion for every event. |
| REQ-320 | Camera | Camera movement is controlled and intentional, tied to gameplay/impact/reward/transition; no shake on every event. |
| REQ-321 | Lighting | Conceptual lighting: a defined key light, fill/rim/ambient/reflection only as needed; not neon-lit everything; no eye-tiring constant brightness. |
| REQ-322 | Hierarchy | Visual priority: 1 Player, 2 Immediate hazard, 3 Objective, 4 Interaction, 5 Score/combo, 6 Environment, 7 Decoration; the background never competes with gameplay. |
| REQ-323 | Variation | Variation comes from geometry, silhouette, scale, spacing, movement, material response, animation and placement — not small recolours of the same object. |
| REQ-324 | Consistency | "Made by the same professional team?" check applied to environment, objects, UI, icons, VFX, particles, animations, materials, typography and sounds. |
| REQ-325 | Detail | Every detail answers "what is this communicating?"; otherwise it is removed. |
| REQ-326 | Readability | Visual quality never harms readability (no invisible obstacles, low contrast, input confusion, player confusion or unclear objectives). |
| REQ-327 | Originality | Nothing reads as a one-to-one copy of another game's mechanic, visual, UI, animation, level pattern, character or environment; the game has its own identity. |
| REQ-328 | Asset gate | Per-asset gate: consistent style, scale, perspective, material, lighting, topology, texture resolution, no repetition, no AI artefacts, no weird geometry, no ambiguity, acceptable mobile performance — fix on any failure. |
| REQ-329 | Asset gate | No raw AI output is placed in the game. |
| REQ-330 | Procedural | Procedural generation obeys art-direction rules (palette, proportions, spacing, shape family, material rules) — random ≠ quality. |
| REQ-331 | Review | Final visual review of MAIN MENU, LEVEL SELECT, GAMEPLAY, PAUSE, FAIL, COMPLETE, REWARD, SHOP, COLLECTION, DAILY, SETTINGS and WORLD SELECT against the slop questions, fixing anything that feels like AI slop. |
| REQ-332 | Report | FINAL_IMPLEMENTATION_REPORT contains an "ANTI-AI-SLOP VISUAL AUDIT" grading visual consistency, texture quality, material quality, lighting consistency, UI consistency, iconography, typography, animation consistency, VFX consistency, environment quality, asset reuse quality, procedural generation quality, originality, AI-artifact inspection and overall human-made appearance as PASS / PARTIAL / FAIL; FAILs are fixed before release. |
| REQ-333 | Quality bar | Minimal but flawless: only commercial-release quality is accepted; the project is not reported COMPLETED unless this section is satisfied. |
