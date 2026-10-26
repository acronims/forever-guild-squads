# Contributing to Guild Squads

ES: guía breve para contribuir. Parte de la documentación está en español; el código y los tests, en inglés. Puedes abrir incidencias y PR en español o en inglés. EN below.

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
| Static gates (fail the build): Lua 5.1 syntax, calls/globals vs the vendored 1.60.1 API list in `tests/tools/` unless guarded, TOC, enUS/esES key parity | `node tests/gates.js` |
| Multi-client simulator | `node tests/sim/run.js [S1 … S10] [--seed N] [--s5seeds N] [--s8min N] [--s9seeds N] [--s9min N]` |

CI (`.github/workflows/ci.yml`) runs the unit tests, the gates and a gates self-test on every push and pull request, and the simulator in parallel jobs with seed 7303 (S9 also with 8303 and 9303). Scenarios and current numbers: [docs/SIM-RESULTADOS.md](docs/SIM-RESULTADOS.md).

## Rules for code
- `Core/` is pure Lua: no WoW API. WoW glue lives in the top-level `*.lua`, UI in `UI/`. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- The client is Lua 5.1 (WoW): the syntax gate must pass.
- Resolve client APIs through `ns.apiFn(...)` and guard with `pcall` when they may be missing on interface 16001.
- No embedded libraries, no economy data, nothing that sends during encounters or PvP matches, no automation without a user click.
- New files must be added to `GuildSquads.toc` (exact case, backslashes).

## Locales
Every key in `Locales/enUS.lua` must exist in `Locales/esES.lua` and vice versa; the locale parity check in the gates and the unit tests fails otherwise. Add both strings in the same commit.

## Branches, PRs, CI
- Branch from `main` (`feat/…`, `fix/…`, `docs/…`); never push straight to `main`.
- Describe the change and how to verify it (acceptance criteria you can check) in the pull request.
- Open a PR; CI must be green. Add a `CHANGELOG.md` entry (ES + EN) for user-visible changes, and tests for behaviour changes.
- Review before merge; the author does not approve their own PR.

## Release
Maintainers only, step by step in [docs/RELEASE.md](docs/RELEASE.md): annotated `vX.Y.Z` tag → `release.yml` (BigWigs packager) → CurseForge / Wago / GitHub Releases. Check the zip from the **Package dry run** workflow first.

## License
By contributing you agree your work is released under the MIT license ([LICENSE](LICENSE)).
