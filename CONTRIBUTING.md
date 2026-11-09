# Contributing to Guild Squads

ES: guía breve para contribuir. La documentación está en inglés y en español (`docs/en/` y `docs/es/`, con los mismos documentos y los mismos nombres; [README.es.md](README.es.md)); el código y los tests, en inglés. Puedes abrir incidencias y PR en español o en inglés. EN below.

## Dev setup
Node 22 (same as CI). The tests need the Lua VM (fengari) and the Lua 5.1 parser (luaparse). Install them outside the tree, the same way CI does, and point `NODE_PATH` at them:

```
npm i --no-save --prefix /tmp/gsq-node fengari@0.1.4 luaparse@0.3.1
export NODE_PATH=/tmp/gsq-node/node_modules
```

Any prefix works as long as `NODE_PATH` points at its `node_modules` (for example `--prefix .node` and `NODE_PATH=$PWD/.node/node_modules`). Do not commit `node_modules/` or `.node/`.

## Run the checks
| What | Command |
|---|---|
| Unit tests (every `tests/*_spec.lua`, run in fengari) | `node tests/run.js` |
| Static gates (fail the build): Lua 5.1 syntax, calls/globals vs the vendored 1.60.1 API list in `tests/tools/` unless guarded, TOC, enUS/esES key parity, unit name APIs and the 1.x identity helpers outside the identity code (2.0) | `node tests/gates.js` |
| Docs links (relative links and anchors resolve; `docs/en` and `docs/es` hold the same files) | `node tests/tools/check-links.js` |
| Multi-client simulator (a WoW Forever realm by default; `--realm` = the 1.2.x world) | `node tests/sim/run.js [S1 … S22] [--seed N] [--s5seeds N] [--s8min N] [--s9seeds N] [--s9min N] [--realm]` |

CI (`.github/workflows/ci.yml`) runs the unit tests, the gates and a gates self-test on every push and pull request, and the simulator in parallel jobs with seed 7303 (S9 also with 8303 and 9303). Scenarios and current numbers: [docs/en/SIMULATOR-RESULTS.md](docs/en/SIMULATOR-RESULTS.md).

## Rules for code
- `Core/` is pure Lua: no WoW API. WoW glue lives in the top-level `*.lua`, UI in `UI/`. See [docs/en/ARCHITECTURE.md](docs/en/ARCHITECTURE.md).
- The client is Lua 5.1 (WoW): the syntax gate must pass.
- Resolve client APIs through `ns.apiFn(...)` and guard with `pcall` when they may be missing on interface 16001.
- No embedded libraries, no economy data, nothing that sends during encounters or PvP matches, no automation without a user click.
- New files must be added to `GuildSquads.toc` (exact case, backslashes).

## Locales
Every key in `Locales/enUS.lua` must exist in `Locales/esES.lua` and vice versa; the locale parity check in the gates and the unit tests fails otherwise. Add both strings in the same commit. Every text the player sees (including default achievement and race names, statuses and guild-chat messages) goes through `L`; replicated ids never do.

## Docs
Docs live in `docs/en/` and `docs/es/` with the same file names; diagrams in `docs/<lang>/diagrams/` (sources in `src/*.json`). A doc change goes into both languages in the same PR, and each doc links to its pair at the top.

## Branches, PRs, CI
- Branch from `main` (`feat/…`, `fix/…`, `docs/…`); never push straight to `main`.
- Describe the change and how to verify it (acceptance criteria you can check) in the pull request.
- Open a PR; CI must be green. Add a `CHANGELOG.md` entry (ES + EN) for user-visible changes, and tests for behaviour changes.
- Review before merge; the author does not approve their own PR.

## Release
Maintainers only, step by step in [docs/en/RELEASE.md](docs/en/RELEASE.md): annotated `vX.Y.Z` tag → `release.yml` (BigWigs packager) → CurseForge / Wago / GitHub Releases. Check the zip from the **Package dry run** workflow first.

## License
By contributing you agree your work is released under the MIT license ([LICENSE](LICENSE)).

## WoW Forever names

In WoW Forever every character has a name **and a surname**, and the full name is unique in the whole region
(Blizzard: *"a full name that is unique within a region"*; research in `agents/research-surnames.md` of the dev
workspace). Since 2.0 (`docs/SPEC-v2.0-identidad.md`) that full name is the **identity** of a character:

- **One function for every name**: `ns.id(a, b)` (sender, roster name, typed name, saved 1.x name; `(a, b)` = what
  `UnitName` gives). The pure part is `Core/Identity.lua` (`I.id(a, b, ctx)`). In mode **forever** the identity is
  `Name Surname`, without the realm (`Kas Pitas`); in mode **realm** it is `Name-Realm`, the 1.2.x key. Never build,
  cut or compare names anywhere else: authors, trust keys, signatures, certificates, indexes and `WHISPER` targets all
  carry the identity. `ns.idFromUnit(unit)`, `ns.me()`, `ns.isSelf(x)`, `ns.roster(x)` (entry with `realm`, `raw`,
  `surname`), `ns.rosterIndex()`, `ns.whisperTarget(id)` and `ns.displayName(id)` / `ns.shortName(id)` wrap it.
- **The mode**: `forever` when `RegionalUniqueNamesEnabled()` is true (read at `ADDON_LOADED` and again at
  `PLAYER_LOGIN`, which wins; frozen for the session), `realm` otherwise. `/gsq diag` prints
  `id mode=forever me=Kas Pitas surname=yes`. Tests force it by setting `ns.ID_MODE` before loading the files.
- **What the client gives** (forever): `GetGuildRosterInfo` and `GetRaidRosterInfo` give `Name Surname-Realm` (the
  realm goes to `r.realm`, never into the identity); `UnitName` / `UnitNameUnmodified` give `(Name, Surname)` (the
  2nd value is the surname, not the realm); `UnitFullName` gives `("Name Surname", "")` or `("Name", "Surname")`; the
  sender of `CHAT_MSG_ADDON` comes as `Name Surname` from any realm. A bare `Name` (sender or unit whose surname is
  not cached yet) resolves through the roster only when one member has that first name; with two `Kas` it is `nil`
  and the message is dropped. A typed name is matched without case (ASCII only; the roster spelling wins) and
  `Kas-Pitas` (the chat link separator) means `Kas Pitas` when that member exists. `ns.id` never raises, is
  idempotent and splits with plain `string.find` (never `%s` / `%w`).
- **`WHISPER` target = the identity**, `Kas Pitas`, never `-Realm` (also towards a connected realm: the server
  refuses `Kas`, `Kas-Realm` and `Kas Pitas-Realm` with «No hay ningún jugador con el nombre …»). Only members in the
  roster that are online (or were heard lately) are whispered; anyone else gets the message over `GUILD` in a `W`
  envelope with the recipient identity. A server «not found» for a name whispered in the last 5 s is hidden
  (`Comm.SystemFilter`).
- **Only `Core/Identity.lua` and `GuildSquads.lua` call `UnitName`, `UnitNameUnmodified` or `UnitFullName`**; any
  other call needs the `-- id-ok` mark (the gate checks it). Overlord keeps the bare first name (`-- id-ok`).
- **The 1.x helpers are gone**: `ns.fullName`, `ns.charKey` and `M.charName` no longer exist. Ask `ns.id` (the 1.2.2
  realm key is `ns.Identity.realmKey`); the gate fails on any reference to them outside `Core/Identity.lua`.
- **The simulator is a WoW Forever realm by default** (`tests/sim/sim.js`, `forever`; `GSQ_SIM_FOREVER=0` gives the
  1.2.x world back): roster and raid roster `Name Surname-Realm`, `UnitName` `(Name, Surname)`, `UnitFullName` in
  both forms (alternating per client), senders `Name Surname`, and a server that delivers a whisper only to the
  exact `Name Surname` of an online client (anything else gets the `CHAT_MSG_SYSTEM` error). A member handle with a
  space gives the surname (`sim.addMember('Kas Pitas', 5)`); `sim.idOf(handle)` is its identity, `sim.whisperLog`
  every whisper and where it went. S20 (with a self-test of that server), S21 (two `Kas` on one realm) and S22
  (connected realms) cover it, and `tests/sim/run.js` fails when any «No hay ningún jugador» line reaches the chat
  of a client of this build (`SYSSHOWN total=`). The older builds that S14 and S17 mix in (1.0.1, 1.1) whisper
  `Name Surname-Realm` in WoW Forever and show that line themselves: it is printed apart (`old=`) and does not fail.
