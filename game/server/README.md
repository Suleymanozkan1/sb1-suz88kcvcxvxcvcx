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
  validator pipeline the client uses, independent of any player data. Only
  the canonical date spelling is accepted (`2026-11-05`, never `2026-11-+5`),
  so each day has exactly one daily level and one daily board.

The server must run the same game build (code + `data/`) as the clients it
verifies: a different generator, validator or `data/daily/daily.json` would
regenerate a different daily, and `sim_version` only guards the simulation.

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
error (bad arguments, unreadable submission, unknown level, malformed
verdict). Warnings go to stderr. A typical backend worker spawns the tool per
submission (or keeps a pool of Godot processes) and maps exit `0` → accept,
`2` → reject (HTTP 422), `1` → server error (HTTP 500; the client retries it
for up to 14 days without letting it block its other queued scores).

The exit code is fail-safe: it starts at `1` and becomes `0` only after a
well-formed verdict with `"valid": true` and no reasons was printed, so an
unexpected script error can never be read as "valid". Accept a score only
when the exit code is `0` **and** the last stdout line parses to
`"valid": true`. A daily submission outside the server's date window is
refused (`stale_daily` / `future_daily`, exit `2`) before its level is
regenerated, so old or future dates cannot be used to make the server do the
expensive generation work.

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
retries later; daily / weekly entries outside the accepted window and
entries older than 14 days are dropped before retrying).

`GET {base_url}/v1/boards/{board}?limit=n&install_id=<id>` (board id
URL-encoded) → `{"entries": [{"rank", "name", "score"}], "player": {"rank",
"name", "score"}}`. Names are display names chosen by the backend; the client
treats them as untrusted (control characters and invisible direction marks
removed, length capped at `leaderboard.name_max_length`) and never invents
entries. The install id in the query string identifies the player's own row;
it is a random per-install value, but a backend should still keep it out of
access logs.

Board ids: `daily:<YYYY-MM-DD>`, `weekly:<YYYY-Www>:<mode>`,
`alltime:<mode>`, `level:<level_id>` (classic only). Revived runs and zen runs
are never submitted. Streamed courses (endless, time attack) are submitted to
the weekly board of the week whose official seed built them, and nowhere else.

Before a streamed course is rebuilt (seconds of CPU), the CLI refuses it
cheaply (`ReplayVerifier.stream_precheck_reason`) when the mode is unranked,
the seed is not the official seed of the current or previous week, or the
end tick exceeds the mode's time limit.

## What `ReplayVerifier.verify()` checks

| Reason code | Rule |
|---|---|
| `missing_replay`, `invalid_level` | submission has a replay; level data exists and simulates |
| `sim_version_mismatch` | client sim version equals the server's `RunReplay.SIM_VERSION` |
| `invalid_structure` | every replay field has the right JSON type and range (string level id / mode, 32-bit seed, whole-number ticks within `max_replay_ticks`) — checked first, nothing malformed is simulated; then `RunReplay.validate_structure()` (monotonic ticks, ≥ 2 ticks apart), end tick present, no tap at/after the end |
| `level_mismatch`, `seed_mismatch` | submission, replay and authoritative level agree on id and seed |
| `mode_mismatch`, `unknown_mode`, `unranked_mode` | mode is known, ranked (zen is not) and consistent with the level kind: daily levels only in daily mode, and the level's `kind` is in the mode's `level_kinds` when the mode lists them (e.g. endless boards only take endless levels) |
| `future_daily`, `stale_daily` | daily date is today or yesterday on the **server** clock (`daily_accept_days_back`) |
| `board_mismatch` | when the submission names a board, it matches mode/level/date (weekly: current or previous ISO week; level boards only for modes with `level_board`) |
| `tap_rate` | at most 12 taps in any 60-tick (1 s) window (`max_taps_per_second`) |
| `run_not_finished`, `end_tick_mismatch` | the re-simulated run ends exactly at the replay's `end_tick` |
| `not_completed` | classic / daily / perfect_run / hard / boss_rush runs must complete |
| `invalid_score`, `score_mismatch` | the claimed score is a non-negative whole number equal to the recomputed score |

Mode rules (shields, zen, speed scale, time limit, ranked, completion, level
kinds) live in `data/daily/daily.json` → `modes`; the game must start runs
with exactly these modifiers so client and server simulate identically.

Known limit: a replay proves that a run is *possible*, not that a person
played it. Campaign levels ship their generator solution (`solution.taps`), so
replaying it is always accepted; the tap-rate rule only stops inhuman input.
Backends that need more should rank campaign boards by additional signals
(account age, play history) rather than trust a single replay.

## Reward claims (`ReplayVerifier.verify_reward_claim`)

For a backend that also grants server-side rewards: a claim
`{"type": "daily"|"level", "date_key", "level_id", "tier", "first_clear",
"deltas": {"coins", "gems", "xp"}}` is checked against the install's history
`{"verified_completions": [...], "daily_claims": {date: tier}, "level_claims":
[...]}`. Rejected: duplicate daily claims, levels (or dailies) never verified
as completed, duplicate first-clear claims, negative / non-integer / unknown /
above-cap currency deltas (`verifier.reward_caps`), stale or future dailies,
daily or streamed ids claimed as level rewards. Both history lists hold one
entry per verified run / accepted claim, and each level claim needs its own
verified run. Deltas are bounded by what the content really pays: a daily by
the streak-table reward of the allowed tier, a level by its tier and kind
(`RewardEngine.level_reward_ceiling`: first-clear or replay coins, every star
new, the first perfect, full XP), coins and gems at most doubled by the
optional ad.
Daily tiers are recomputed from the claim history with the same gentle streak
rule as the client (`DailyChallengeService.tier_after`); a higher claimed tier
is clamped (`allowed_tier`) rather than rejected, so honest players who
played offline are never punished.

Detections are for the backend only. The client never punishes a player for
a rejected submission; it simply is not ranked.
