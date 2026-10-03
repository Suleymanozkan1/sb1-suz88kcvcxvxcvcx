# FLUX DROP — server-side verification

**There is no hosted backend.** This folder contains the *authoritative
verification logic* a leaderboard / reward backend would run, packaged as a
headless Godot command-line tool. The shipped game has an empty
`leaderboard.base_url` (remote config), so `HttpLeaderboardBackend` is
disabled: leaderboards show the player's own bests (local, offline-first), and
nothing is sent anywhere. Building and operating an HTTP service (accounts,
storage, rate limiting, abuse handling) is out of scope of this repository.

## Why a replay, not a score

The client is never trusted. FLUX DROP's simulation (`src/gameplay/sim/`) is
deterministic: fixed 60 Hz ticks, integer-seeded xorshift RNG, no
transcendental math in gameplay rules. A run is fully described by the level
and the ticks on which the player tapped (`RunReplay`). A backend therefore
ignores the claimed score and re-simulates the replay on *its own copy* of the
level:

- campaign levels (`wNN_lMM`) come from `data/levels/` (`LevelRepository`);
- daily levels (`daily_YYYY-MM-DD`) are regenerated from the date with
  `DailyChallengeService.level_for()` — the same deterministic generator +
  validator pipeline the client uses, independent of any player data.

## Running the verifier

```sh
godot --headless --path game -s res://server/verify_replay.gd -- \
    --submission=/path/to/submission.json [--now=<unix seconds>]
```

- `--submission` — the JSON body the client POSTed (format below).
- `--now` — the server's current time (UTC unix seconds). Used for the daily
  date window; defaults to the system clock. Pass it explicitly from the
  backend so every worker agrees on "today".

Output: one JSON object, printed as the last line of stdout (Godot prints its
version banner first, so read the last line).

```json
{"details": [], "level_id": "w03_l10", "reasons": [], "score": 4115,
 "server_date": "2026-10-03", "valid": true}
```

`score` is the **authoritative** score (from simulation) — store this, never
the claimed one. Exit codes: `0` valid, `2` invalid (see `reasons`), `1`
error (bad arguments, unreadable submission, unknown level). Warnings go to
stderr. A typical backend worker spawns the tool per submission (or keeps a
pool of Godot processes) and maps exit `0` → accept, `2` → reject (HTTP 422),
`1` → retryable server error (HTTP 500).

## HTTP contract used by the client (`HttpLeaderboardBackend`)

`POST {base_url}/v1/scores`

```json
{
  "board": "daily:2026-10-03",
  "score": 4115,
  "replay": {"level_id": "daily_2026-10-03", "seed": 123456789, "mode": "daily",
             "sim_version": 1, "taps": [75, 180, 362], "end_tick": 1490},
  "level_id": "daily_2026-10-03",
  "mode": "daily",
  "app_version": "1.0.0",
  "install_id": "<32 hex chars, random per install, not PII>",
  "sim_version": 1
}
```

Responses: `2xx {"accepted": true|false, "rank": n, "score": authoritative,
"reasons": [...]}`; `400/403/404/409/410/422` = rejected (the client drops the
submission); `429`, `5xx` or no answer = transient (the client keeps it in a
bounded offline queue — 50 entries, deduplicated by board+score+level — and
retries later).

`GET {base_url}/v1/boards/{board}?limit=n&install_id=<id>` (board id
URL-encoded) → `{"entries": [{"rank", "name", "score"}], "player": {"rank",
"name", "score"}}`. Names are display names chosen by the backend; the client
truncates them and never invents entries.

Board ids: `daily:<YYYY-MM-DD>`, `weekly:<YYYY-Www>:<mode>`,
`alltime:<mode>`, `level:<level_id>` (classic only). Revived runs and zen runs
are never submitted.

## What `ReplayVerifier.verify()` checks

| Reason code | Rule |
|---|---|
| `missing_replay`, `invalid_level` | submission has a replay; level data exists and simulates |
| `sim_version_mismatch` | client sim version equals the server's `RunReplay.SIM_VERSION` |
| `invalid_structure` | `RunReplay.validate_structure()` (monotonic ticks, ≥ 2 ticks apart), end tick present, no tap at/after the end |
| `level_mismatch`, `seed_mismatch` | submission, replay and authoritative level agree on id and seed |
| `mode_mismatch`, `unknown_mode`, `unranked_mode` | mode is known, ranked (zen is not) and consistent with the level kind |
| `future_daily`, `stale_daily` | daily date is today or yesterday on the **server** clock (`daily_accept_days_back`) |
| `board_mismatch` | the board matches mode/level/date (weekly: current or previous ISO week) |
| `tap_rate` | at most 12 taps in any 60-tick (1 s) window (`max_taps_per_second`) |
| `run_not_finished`, `end_tick_mismatch` | the re-simulated run ends exactly at the replay's `end_tick` |
| `not_completed` | classic / daily / perfect_run / hard / boss_rush runs must complete |
| `invalid_score`, `score_mismatch` | the claimed score equals the recomputed score |

Mode rules (shields, zen, speed scale, time limit, ranked, completion) live in
`data/daily/daily.json` → `modes`; the game must start runs with exactly these
modifiers so client and server simulate identically.

## Reward claims (`ReplayVerifier.verify_reward_claim`)

For a backend that also grants server-side rewards: a claim
`{"type": "daily"|"level", "date_key", "level_id", "tier", "first_clear",
"deltas": {"coins", "gems", "xp"}}` is checked against the install's history
`{"verified_completions": [...], "daily_claims": {date: tier}, "level_claims":
[...]}`. Rejected: duplicate daily claims, levels (or dailies) never verified
as completed, duplicate first-clear claims, negative / non-integer / unknown /
above-cap currency deltas (`verifier.reward_caps`), stale or future dailies.
Daily tiers are recomputed from the claim history with the same gentle streak
rule as the client (`DailyChallengeService.tier_after`); a higher claimed tier
is clamped (`allowed_tier`) rather than rejected, so honest players who
played offline are never punished.

Detections are for the backend only. The client never punishes a player for
a rejected submission; it simply is not ranked.
