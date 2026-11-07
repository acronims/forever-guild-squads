# PROGRESS v1.1 — sincronización P2P (rama `feat/v1.1-sync-p2p`)

Spec: `docs/SPEC-v1.1-sync-p2p.md` (anexo A = lista de tipos autorales / de autoridad, confirmada contra el código).

## Cómo se prueba
```
npm i --no-save --prefix /workspace/group/research/wowforever/wt/node fengari@0.1.4 luaparse@0.3.1
export NODE_PATH=/workspace/group/research/wowforever/wt/node/node_modules
node tests/run.js            # unidad + smoke (cliente falso)
node tests/gates.js          # sintaxis / API / TOC / locales
node tests/sim/run.js S11 S12 S14 --seed 7303          # AC1, AC2+AC4, AC7
node tests/sim/run.js S13 --seed 7303 --s13min 15      # AC8 (4 corridas de 40 clientes, lento)
```
S13 y S14 comparan con la v1.0.1 (`GSQ_REF`, por defecto `406029a`, leído con `git show`).

Línea base antes de tocar nada (7-nov, commit db23705): `RESULT: 255 passed, 0 failed`, `GATES: OK`,
simulador S1 S2 S3 S4 S5(5 semillas) S6 S7 = 7/7 PASS.

## Estado por criterio
| AC | Estado | Test | Salida |
|---|---|---|---|
| Anexo A | hecho | `tests/p2p_spec.lua` «the closed list of authorial kinds» | pasa |
| AC1 | verificado | sim `S11` | 50/50 registros autorales (perfiles + presence) en los 5 clientes, máx. 2 conectados, ≤3 sesiones; 26/50 verificados. Con el código 1.0.1 (`GSQ_ROOT=ref-101`): 13/50 (rojo) |
| AC2 | verificado | `p2p_spec` «AC2…» + sim `S12` | unverified en todos, 20 min después sigue sin verificar |
| AC3 | verificado | `p2p_spec` «AC3…» | pasa |
| AC4 | verificado | `p2p_spec` «AC4…» (2 tests) + sim `S12` | el falso desaparece de los 5 clientes; diag `relayers=Mb2-Realm:1,Mb3-Realm:1` |
| AC5 | verificado | `p2p_spec` «AC5…» | pasa (settings, squad, reject req, annul, roster, attendance, perfil con xferTo → `relay`) |
| AC5b | verificado | `p2p_spec` «AC5b…» | pasa |
| AC6 | verificado | `p2p_spec` «AC6…» + smoke «v1.1: /gsq diag…» | pasa |
| AC7 | verificado (simulador) | sim `S14` (2 clientes 1.0.1 entre 8) | 0 errores Lua, los viejos descartan presence/repudiate (`bad` 48 y 46) y siguen sincronizando lo suyo. **Falta** la prueba real con BugSack en el juego (BRO). |
| AC8 | ver abajo | sim `S13` | pendiente de resultado |
| AC9 | ver abajo | `tests/run.js`, `gates.js`, sim S1–S9 | `RESULT: 266 passed, 0 failed`, `GATES: OK`; sim pendiente |

## Tests existentes cuya expectativa cambia por el spec (no se debilitan: se cambia lo que el spec cambia)
- `tests/sync_spec.lua:32-41`: un perfil reenviado por un no oficial pasa de `relay` a `pending` (y se comprueba que no se guarda).
- `tests/catalog_spec.lua:242`: `presence` y `repudiate` van detrás de `achdef`/`achgrant` en `M.EXT_ORDER` (las posiciones antiguas no cambian).
- `tests/sim/scenarios.js` S3(b): sin oficiales el recién llegado recibe ahora los 200 perfiles (antes, solo los de los 3 autores conectados).

## Qué falta / siguiente paso
1. Resultado de S13 (AC8) y de la regresión del simulador S1–S9 (AC9).
2. Medir el tamaño de SavedVariables con 200 miembros (riesgo del spec).
3. Revisión QA a ciegas y prueba de BRO en el juego (AC7 con BugSack).
