# Multi-client simulator — results

Español → [SIMULATOR-RESULTS.md](../es/SIMULATOR-RESULTS.md)

Simulator: `tests/sim/` (Node + fengari). Every client is the full addon (the whole TOC) in its own fengari state, with its own fake WoW API, SavedVariables, clock (with skew) and timers. GUILD/WHISPER bus with `CHAT_MSG_ADDON` and `Name-Realm` senders, 50–800 ms latency (in order per pair), per-prefix throttle (burst 10, 1 msg/s; above that it returns 3), optional loss, lock during encounters/BGs, login/logout//reload with SavedVariables. Seeded PRNG (mulberry32).

Run: `NODE_PATH=… node tests/sim/run.js [S1 … S10] [--seed N] [--s5seeds N] [--s8min N] [--s9seeds N] [--s9min N]`. CI runs all of them except S10, with seed 7303 (S9 also with 8303 and 9303).

## Results (seed 7303)

| Scenario | Result | Figures |
|---|---|---|
| S1 10 clients, random squads/requests/accepts/kicks | PASS | 50 effective actions; same model hash on all 10 |
| S2 the GM changes settings with 30 clients; a member forges them | PASS | all 30 apply the settings within 2 s; 0 clients accept the forgery (signed as himself or impersonating the GM) |
| S3a fresh client, 200 records, officer online | PASS | converges in 210 simulated s (≤ 450 s required) |
| S3b no GM and no officers (seed 7304) | PASS | receives only the profiles of the 3 online authors + its own (documented behaviour) |
| S4 10-player raid, 2 squads, boss with comms locked | PASS | 0 messages during the encounter; same score and Top on all 10 |
| S5 celebrations, 20 clients | PASS | 20 seeds (7303–7322): 60 events → 60 messages, exactly 1 per event |
| S6 wipe change with ±200 s clock skew | PASS | same canonical summary of both wipes on all 10; live score of the closed wipe identical everywhere (`liveScoreVariants` = 1; on the open wipe, 2) |
| S7 raid roster: publish, 15 RSVPs, invite, close without the RL, later signature | PASS | 4 invited on the first click (party), same signed attendance everywhere |
| S8 load: 500 members, 100 squads, 20 clients, 15 min | PASS | see *S8 metrics* |
| S9 60 min chaos, 5 % loss, random /reloads | PASS | 263 actions, 15 /reloads, 776 lost messages; final convergence |
| S10 GM catalog with 30 clients | PASS | see *S10* |

Captured Lua errors (pcall around events/timers, `Sync.stats.errors`, `Comm.stats.handlerErrors`, `ns.debug` with `file:line`): **0** in every scenario.

## S8 metrics (15 min with 20 clients; 3 min in CI)

| Metric | Value | Limit |
|---|---|---|
| Mean messages/s of the busiest client (an officer) | 0.763 | ≤ 1.05 (the Comm queue drains at 1/s) |
| Peak in 1 s | 4 | ≤ 10 (throttle burst) |
| Sends refused by the throttle | 0 | 0 |
| Max queue | 379 | 500 |

The queue is the backlog of an officer answering hellos while 20 clients log in within 60 s; it drains at 1 msg/s. Own traffic (records, events, live observations, claims) goes first, so the backlog only delays the others' catch-up.

## S10 — GM catalog

30 clients (GM, 2 officers, 27 members). 5 of them do not know the catalog record kinds (`achdef`, `achgrant`): it checks that a client that does not know a record kind ignores it without error and keeps syncing the rest. Not in CI: it needs `GSQ_COMPAT_REF` (and `GIT_DIR` if needed) pointing to a git ref with such a client. Seed 7303. Command: `NODE_PATH=… node tests/sim/run.js S10 --seed 7303`.

| Check | Result |
|---|---|
| The GM disables 60 races (one bulk = 60 `achdef` records) and creates 5 custom achievements | 60 applied, 0 refused; 5 created |
| Message parts of the bulk (estimate shown to the GM in the confirmation) | 40 (3 records per message) |
| The 25 clients that know those kinds hold the same catalog (65 records, 60 disabled) | **45 s** simulated (measured in 5 s steps): 40 s for the bulk at 1 msg/s + the 5 custom ones |
| `achdef` forged by a member (signed as himself or impersonating the GM) and forged `achgrant` | accepted by **0** clients; the copy impersonating the GM is refused as a relay (`relayRefused`) |
| Clients that do not know those kinds | receive and ignore the unknown kinds without error (`sync bad=` 68 on each), store nothing from the catalog, apply the GM's settings, and the rest of the model converges on all 30 within 5 s |
| Captured Lua errors | **0** |

## Simulator limits

Permissive fake API (no real UI, no text measuring), modelled clock and throttle (not the client's), instantly shared roster, `GetServerTime` with artificial skew (in game the server provides it). Passing in the simulator is not the same as being tested in game.
