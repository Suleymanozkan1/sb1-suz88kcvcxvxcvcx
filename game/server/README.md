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
Live economy tuning: call `verifier.apply_remote_tuning(values)` with the
remote-config values snapshot the backend serves (`economy.coin_multiplier`,
`economy.daily_reward_multiplier`, `events.weekend_coin_bonus`) before
checking claims, so the bounds scale coins exactly like the client. The client
applies the weekend bonus by its own clock when a run starts, so the server
allows the bonus on every day while one is configured (a Sunday run claimed on
Monday, or in another time zone, is never refused for it).
Daily tiers are recomputed from the claim history with the same gentle streak
rule as the client (`DailyChallengeService.tier_after`); a higher claimed tier
is clamped (`allowed_tier`) rather than rejected, so honest players who
played offline are never punished.

Detections are for the backend only. The client never punishes a player for
a rejected submission; it simply is not ranked.


Reward claims bound currencies only. Bonus stars, skins and trails (achievement
rewards, see `RewardEngine`) are not claimable: a claim whose `deltas` names
`stars`, `skin`, `trail` or anything else outside `verifier.reward_caps` is
rejected as `unknown_currency`.

## Cloud save (`HttpCloudSaveProvider`, `CloudSaveService`)

Like leaderboards, the cloud save is **off in the shipped build**: remote config
`cloud_save.base_url` is empty, so the game uses `NullCloudSaveProvider`,
nothing is sent anywhere, and Settings says "Cloud save isn't available in this
build". The URL is validated like every remote URL (HTTPS, one plain host, no
credentials). The client, protocol and merge are complete and tested; the
local save stays the source of truth and works offline.

### Endpoints

`GET {base_url}/v1/saves/{install_id}` (install id URI-encoded) →
`200 {"blob": "<save envelope>", "revision": "<token>"}`, or `404` when no
cloud copy exists yet.

`PUT {base_url}/v1/saves/{install_id}`

```json
{"blob": "{\"checksum\":\"…\",\"format\":\"fluxdrop-save\",\"payload\":{…},\"saved_at\":1790000000,\"version\":1}",
 "base_revision": "r41", "app_version": "1.0.0"}
```

→ `200 {"revision": "<new token>"}` when stored, or
`409 {"blob": "<current envelope>", "revision": "<current token>"}` when
`base_revision` is not the current revision.

Both: `429`, `5xx` or no answer = transient (the client keeps `cloud.dirty`
in the profile and syncs again at the next trigger: boot, network back online,
app pause, or "Sync now"); any other `4xx` = final. A `2xx` (or `409`) whose
body does not have exactly this shape is never applied and is retried later:
`blob` must be a string, `revision` a token of 1–128 characters from
`[A-Za-z0-9._:-]` (`CloudSaveProvider.valid_revision`). Responses larger than
the client transport's 1 MiB body limit (`HttpTransport.MAX_BODY_BYTES`) never
arrive, so the client never uploads a blob whose `GET` answer (the blob
JSON-escaped inside `{"blob", "revision"}`, `HttpCloudSaveProvider.download_bytes`)
would exceed it: such a push is refused before anything is sent and the sync
ends with status `error` / `too_large`, the changes staying dirty. A backend
should refuse larger blobs too (`413`) and must refuse anything above
`SaveService.MAX_SAVE_CHARS`.

The uploaded payload is `ProfileMerge.travelling`: it never carries the
device-local `settings`, `cosmetics_equipped` or `pending_submissions` (queued
leaderboard / analytics submissions belong to the device that queued them;
another device would send them twice) nor the client's `cloud.*` bookkeeping
flags. Those fields hold their defaults in the stored envelope.

### Revisions and conflicts

The server keeps one `(blob, revision)` pair per save slot and treats a PUT as
a compare-and-swap: it is stored only when `base_revision` equals the current
revision (`""` when the slot is empty), and the server then issues a new,
never reused revision (a counter or random token). Otherwise it answers `409`
with its current copy and changes nothing. The client merges that copy with
`ProfileMerge` (union / maximum of progress, earliest unlock times, missions
claimed on either side stay claimed, the three-way wallet merge below) and
PUTs once more with the returned revision; a second conflict waits for the
next sync. The client never overwrites a cloud copy it could not read: a copy
with a bad checksum or from a newer save version (`SaveService.decode` refuses
both) leaves both sides untouched.

The slot key is the random per-install id (not PII; keep it out of access
logs). Linking installs to one player (platform sign-in) is outside this
repository; a backend that links installs serves the linked account's save for
each linked install id, which is how a second device sees the first device's
progress. Store the blob verbatim: the client relies on its `sync.pushes` flag
(below) coming back unchanged.

### Wallet merge (coins, gems, bonus stars)

The wallet is never taken whole from one side (device clocks cannot be
trusted, and either choice loses the other device's spends or earnings). Each
client keeps a **base** in its own save (`cloud.base`, `cloud.base_ledger`):
the wallet and ledger entries of the last state it and the cloud shared,
recorded when the server accepts its PUT and whenever it merges a cloud copy.
The exact rule (`WalletMerge`), per currency and for bonus stars:

- **With a base:** `merged = max(0, remote + (local - base) - repeated)`. Every
  spend and every earning since the base, on either device, applies exactly
  once. `repeated` is what this device's new ledger entries (those not in the
  base) did for an event that happens once per account and that the cloud copy
  already holds: the same item bought (`cosmetic:<id>`), the same achievement,
  mission, player-level or world reward (`achievement:<id>`, `mission:<id>`,
  `level_up:<n>`, `world_complete:<n>`, with their `:duplicate` / `:ad_double`
  parts), or the daily streak reward or bonus chest of the same UTC day. The
  copy holds such an event when its ledger has an entry with the same source
  and currency (same day for the daily ones) or, for achievements, items,
  missions and player levels, when its state shows it. A purchase made on both
  devices is charged once and the item is owned once; the second charge is
  refunded. Purchases of different items made offline on both devices are both
  paid; when together they cost more than the wallet held, the wallet stops at
  0. Bonus stars are not in the ledger: stars of the same achievement unlocked
  on both devices before either synced count twice (three achievements pay
  stars, a handful in total).
- **Without a base** (the device never synced): only what it holds beyond the
  economy's starting balance counts as earned there:
  `merged = remote + max(0, local - starting - repeated)`, stars
  `remote + local`. A fresh or pristine install never replaces or reduces the
  account's wallet: the fresh install whose first boot found `404` and
  uploaded its starting balance, then is linked to an account and served the
  account's (older) copy, keeps the account's wallet.
- **A push whose answer was lost:** before each PUT the client stores the copy
  it sends as `cloud.pending` with a sequence number and counts it in the
  travelling flag `sync.pushes` (`{device id: last sequence}`, merged by
  maximum on every client). A cloud copy whose `sync.pushes` shows that
  sequence contains the push (also when another device merged it since), so
  the pending copy is the base and nothing is counted twice.
- **Saves synced before bases existed** (a `cloud.revision` without a base)
  rebuild the base from their ledger: the entries dated after `cloud.synced_at`
  are their changes.

The merged ledger is the cloud copy's entries plus this device's new,
non-repeated ones, ordered by time with the balances recomputed; when the
newest balance still differs from the merged wallet (a refund, a clamp, the
starting balance) one `cloud_sync` entry records the difference, so the newest
entry always matches the wallet. A merge is not earning: lifetime stats merge
by maximum (`coins_earned` included) and no coin is reported as earned twice.

Days: a cloud copy's daily `last_day` beyond the device's today plus the daily
late grace, or a `bonus_chest_day` beyond today, comes from a clock running
ahead and is never adopted (it would block every daily on every device).

### What the server must check

- **The envelope, with the client's own rules.** Run `SaveService.decode(blob)`
  on every PUT (format `fluxdrop-save`, SHA-256 checksum over the canonical
  payload, a version no newer than the server build's
  `SaveService.CURRENT_VERSION`, the size cap) and answer `422` when it fails,
  then sanitise the payload with `PlayerProfile.from_dict` before reading any
  field. Run the same game build as the clients, as for replays.
- **Never trust currencies blindly.** The checksum detects damage and casual
  edits only; its salt ships with the game, so anyone can produce a valid
  envelope with any balance. The server must cross-check `coins` and `gems`
  (and the `ledger` that explains them) against what it has verified for this
  install / account: the starting balance, accepted reward claims
  (`ReplayVerifier.verify_reward_claim` with `apply_remote_tuning` applied to
  the live remote-config values, see "Reward claims" above) and verified store
  purchases. A save holding more than that is refused (`422`) or stored with
  its currencies clamped and the install flagged for review — never used as
  evidence for a reward or a rank. A merged copy's balances are the sum of
  each linked install's verified changes since the copy it built on (see
  "Wallet merge"); `cloud_sync` ledger entries record merge adjustments (a
  clamp at 0, the starting balance, history beyond the ledger limit), not
  earnings.
- **Progress is the player's own.** Levels, stars, achievements and bonus
  stars in a cloud copy only restore the player's own progress; leaderboard
  ranks still come exclusively from verified replays (`ReplayVerifier.verify`).
- **Rate-limit PUTs** per install (a healthy client pushes at most once per
  trigger) and keep only the newest copy per slot.
