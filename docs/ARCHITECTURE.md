# Guild Squads — Architecture

Target: WoW Forever client 1.60.1 (`## Interface: 16001`). No embedded libraries. File references point to the current tree.

## 1. Module map (TOC load order)

Pure Lua (`Core/`, no WoW API, unit-tested outside the game):

| File | Responsibility |
|---|---|
| `Locales/enUS.lua`, `Locales/esES.lua` | String tables (same keys in both). |
| `Core/Serialize.lua` | Deterministic type-tagged serializer, transport escaping, hash; `ns.apiFn` call-time API resolver. |
| `Core/Permissions.lua` | Rank decisions over an injected `roster(name)` function: `isGM` (rank 0), `isOfficer` (`settings.officerRanks`), `canEditSettings`, `canCreateSquad`, `canManageSquad`. |
| `Core/Chunk.lua` | Splits an escaped payload into ≤255-byte messages and reassembles them. |
| `Core/Queue.lua` | Token-bucket send queue (default 1 msg/s, burst 4, max 2000 items) that holds while comms are locked. |
| `Core/Model.lua` | Records, schema sanitising, last-writer-wins merge, authority validation, per-guild DB partition + migrations, `registerKind` for extension kinds. |
| `Core/Match.lua` | "Encaje" fit score with explainable reasons; finder filters. |
| `Core/Logo.lua` | Logo data (icon / colour / border indices). |
| `Core/Call.lua` | "Llamar al squad" payload and cooldown/anti-spam rules. |
| `Core/Content.lua` | PvE content catalog (dungeons/raids, level ranges, aliases). |
| `Core/Roster.lua` | Raid rosters 10/20/40: `roster`, `rsvp`, `attendance`, `witness` records, weekly templates, invite plan, Discord export. |
| `Core/Progress.lua` | Rankings: MetricEvent schema, witness rule, daily dedupe, weights, cap per wipe, wipe ids (`W<n>`), seasons. |
| `Core/Races.lua` | "Salón de la fama" races (Top 100/10/3) from replicated observations; GM annulments; `vconfirm` kind. |
| `Core/Catalog.lua` | The GM's catalog: `achdef` (on/off, Top size, name, custom races/badges) and `achgrant` (granted badges) kinds; effective size, off/legacy, bulk plans. |
| `Core/Celebrate.lua` | Celebrations: what is announced (GM settings), single announcer per event via a claim, rate limit. |
| `Core/Diag.lua` | Diagnostics model stored in `GuildSquadsDB.diag`. |

WoW glue and UI:

| File | Responsibility |
|---|---|
| `Comm.lua` | Transport: serialize → escape → chunk → queue → `C_ChatInfo.SendAddonMessage`, prefix `GSquads`; lockdown holds. |
| `Sync.lua` | Record replication (`D`, `H`), relay trust, hello pagination, tag dispatcher. |
| `UI/Widgets.lua` | Component kit; every Retail template/atlas tried under `pcall` with plain fallbacks. |
| `UI/Main.lua` | Main window and tabs; screens register in `ns.UI.panels`. |
| `GuildSquads.lua` | Bootstrap: SavedVariables, guild roster cache, guild selection, local actions, timers, slash commands. |
| `Progress.lua` | Rankings glue: `PLAYER_LEVEL_UP`, `ENCOUNTER_END`, PvP results/HK, event replication (`E`), wipe summaries (`SQ`/`SR`). |
| `Hall.lua` | Hall of Fame glue: detection, observations (`RO`/`RP`), celebration claims (`CL`), professions reader. |
| `Raids.lua` | Raid roster glue: signed writes, RSVP, one-click invite (guarded APIs, user click only). |
| `Diag.lua` | Diagnostics glue (`/gsq diag`). |
| `UI/Panels.lua` | Mi squad · Squads · Buscador · Mi perfil · Ajustes (GM) · Crear squad. |
| `UI/Ranking.lua` | Ranking tab (5 categories + General, Wipe/Temporada selector) and achievements strip. |
| `UI/Raids.lua` | Bandas tab (list + roster views). |
| `UI/Hall.lua` | Salón de la fama tab. |
| `UI/Catalog.lua` | Ajustes > Logros / Settings > Achievements (GM only): catalog list, bulk, "Nuevo logro" wizard, grants. |
| `UI/Minimap.lua` | Own minimap button (no LibDBIcon). |

## 2. Data model

Record (`Core/Model.lua`): `{ k = kind, id = string, a = author, ts = number, sq = number, d = data }`. Merge is last-writer-wins on the version `(ts, sq, author)` (`Sync.lua` `vkey`), with kind-specific tie rules.

Core kinds (`Sync.lua` `KINDS`): `settings`, `squad`, `profile`, `reject`, `boss`, `annul`.
Extension kinds via `M.registerKind`: `roster`, `rsvp`, `attendance`, `witness` (`Core/Roster.lua`), `vconfirm` (`Core/Races.lua`), `achdef` / `achgrant` (`Core/Catalog.lua`, order 12/13; GM only). A client that does not know a kind refuses it (`Model.validShape` -> `kind`, counted in `Sync.stats.bad`) and keeps syncing the rest; hello replies only carry an extension kind to a peer whose hello has hashes for it.

Not records: MetricEvents (tag `E`, `Core/Progress.lua`) and race observations (`RO`/`RP`, `Core/Races.lua`). Scores and race results are computed locally from them, never transmitted (except GM/officer wipe summaries, below).

Membership needs both sides: the captain lists the player in the squad record **and** the player's profile points to the squad.

## 3. Sync protocol

- Prefix `GSquads` (`Comm.PREFIX`), GUILD channel, WHISPER for directed replies.
- Message tags (dispatcher `Sync.lua`):

| Tag | Meaning |
|---|---|
| `D` | Records (live deltas and hello replies). |
| `H` | Hello with bucketed state hashes per kind. |
| `C` | Squad call (whisper). |
| `E` | MetricEvents (live, and catch-up batches by whisper). |
| `RO` / `RP` | Race observations: live (author only) / catch-up pages. |
| `SQ` / `SR` | Wipe summary request / reply (reply accepted only from GM/officer). |
| `CL` | Celebration claim (lowest name among claims announces). |

- **Hello**: after the roster loads, `Sync.Hello` fires after 3–10 s; replies carry only differing records, up to 60 per reply (`MAX_REPLY`), paginated with a per-requester cursor over keys `"%03d|id"` (numeric kind order). A fresh client re-hellos up to 6 extra rounds while it keeps learning (`MAX_ROUNDS`).
- **Anti-entropy**: one hello every 600–1200 s, jittered (`GuildSquads.lua`).
- **Chunking**: ≤255-byte parts; half-received messages are garbage-collected every 30 s of traffic.
- **Throttle**: token bucket ~1 msg/s, burst 4; own fresh records, events, live observations and claims are sent "urgent" ahead of the reply backlog.
- **Holds**: nothing is sent during encounters, PvP matches or `C_ChatInfo.InChatMessagingLockdown()`.
- Records > 300 s in the future are refused (retried later); records arriving before the guild roster loads wait in a pending list (`MAX_PENDING` 5000).

```mermaid
flowchart LR
  A[Local action] --> V{Model.validate + Permissions}
  V -->|ok| S[(GuildSquadsDB.guilds[key])]
  S --> Ser[Serialize + escape] --> Ch[Chunk ≤255 B] --> Q[Queue 1 msg/s, burst 4]
  Q -->|not locked| W[(GUILD addon channel 'GSquads')]
  W --> R[CHAT_MSG_ADDON] --> As[Reassemble] --> T{tag}
  T -->|D/H| Sy[Sync: trust check live/relay] --> V
  T -->|E/SQ/SR| P[Progress glue]
  T -->|RO/RP/CL| H[Hall glue]
```

## 4. Trust model

- Every client re-validates every record against its own guild roster; nothing is trusted because it arrived.
- Authority (`Core/Permissions.lua`): only rank 0 (GM) writes `settings`; only the owner writes a `profile`; only the captain or GM manages a squad; officers = GM + ranks in `settings.officerRanks`.
- Relay (`Sync.lua` header): a record is accepted live only when the sender is its author; relayed copies only from GM/officers. Same rule for observations and wipe summaries. Without a GM/officer online, clients only get what authors publish themselves.
- Raid rosters (`Core/Roster.lua`): `roster` written by its owner (while RL/officer), the GM, or officers if the GM allows (`offEdit`); `rsvp` only by the player; `attendance` by RL/GM after close, up to 7 days (`FIX_DAYS`); final attendance = official record + names reported by ≥2 witnesses.
- "Signed" here means authored records validated by rank, not cryptographic signatures: a GM/officer with a modified client can still forge relays (README, "Known limitations").

## 5. Persistence

- SavedVariables `GuildSquadsDB` (per account); data partitioned per guild in `GuildSquadsDB.guilds[guildKey]` (`M.guildDB`), so alts in other guilds never touch it. Diagnostics in `GuildSquadsDB.diag`.
- The DB carries a schema version; on load, stored non-finite numbers are scrubbed.
- Guild change without `/reload` saves the old partition and loads the new one.

## 6. Timers and performance

- `ns.After` / ticker: `C_Timer.After` / `C_Timer.NewTicker` when present, else an `OnUpdate` fallback (`GuildSquads.lua`); queue pumped by a 0.2 s ticker (`Comm.lua`).
- Event bursts (`UPDATE_FACTION`, `SKILL_LINES_CHANGED`, `PLAYER_PVP_KILLS_CHANGED`) are debounced into one sample (~2 s).
- Full resync of large guilds takes minutes by design (throttle); S8 measures msgs/s for 500 members / 100 squads.

## 7. Testing

- `tests/run.js`: loads `Core/*.lua` and the glue into **fengari** (Lua 5.3 VM in JS) with `tests/harness.lua` mocks and runs every `tests/*_spec.lua`.
- `tests/gates.js` (fails the build on any failure): Lua 5.1 syntax (luaparse) of every `.lua`; every called/referenced global vs the vendored 1.60.1 API list in `tests/tools/` unless guarded (only a bare reference guards: `if X then`, `X and X()`, `if not X then return end`, `ns.apiFn("X")`; `if X() then` / `X() or 0` do not); TOC checks (Interface 16001, SavedVariables, case-exact files, every addon `.lua` listed); enUS/esES key parity. A self-test in `tests/tools/` proves the gate rejects unguarded calls inside conditions.
- `tests/sim/` (`run.js`, `sim.js`, `scenarios.js`, `client.lua`, `fakewow.lua`): multi-client simulator, scenarios S1–S10: S1 squad lifecycle convergence · S2 GM settings with 30 clients, forged settings ignored · S3 fresh client catch-up · S4 boss kill under comms lock · S5 one celebration message per event · S6 wipe change with ±200 s clock skew · S7 raid roster RSVP/close/signature · S8 load 500 members/100 squads · S9 1 h chaos with 5 % loss and /reloads · S10 GM catalog with 30 clients (a client that does not know a record kind ignores it without error). CI runs all of them except S10 with seed 7303. Results: `docs/SIM-RESULTADOS.md`.
- The unit tests include a cold load with a strict fake 16001 API and `GuildSquadsDB = nil`.
