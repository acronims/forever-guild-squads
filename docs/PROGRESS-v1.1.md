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
| AC9 | **parcial: S8 en rojo** | `tests/run.js`, `gates.js`, `check-links.js`, `gates-selftest.js`, `wow-secret-lint`, sim S1–S9 | unidad `RESULT: 266 passed, 0 failed`; `GATES: OK`; enlaces 0 rotos; secret lint 0 errores. Simulador (seed 7303): S1, S2, S3, S4, S5 (5 semillas), S6, S7, S9 (15 min) PASS; **S8 (3 min) FAIL**: `send queue never above X = 500 -> 553` (repetido: 547). La 1.0.1 con la misma semilla: maxQueue 379, meanAll 0,218 msg/s; la 1.1: maxQueue 547-553, meanAll 0,264 (+21 %). CHANGELOG ES/EN y línea `p2p pend= verified= repudiated= blocked=` en `/gsq diag` (smoke «v1.1: /gsq diag…») hechos. |

## Tests existentes cuya expectativa cambia por el spec (no se debilitan: se cambia lo que el spec cambia)
- `tests/sync_spec.lua:32-41`: un perfil reenviado por un no oficial pasa de `relay` a `pending` (y se comprueba que no se guarda).
- `tests/catalog_spec.lua:242`: `presence` y `repudiate` van detrás de `achdef`/`achgrant` en `M.EXT_ORDER` (las posiciones antiguas no cambian).
- `tests/sim/scenarios.js` S3(b): sin oficiales el recién llegado recibe ahora los 200 perfiles (antes, solo los de los 3 autores conectados).

## Carga en el canal (AC8): cambios hechos al medir
- Primera medida (S1, con el GM conectado): 1124 partes frente a 312 de la 1.0.1. Causas: los miembros reenviaban registros
  ajenos aunque hubiera un oficial, la `presence` alargaba las rondas de hello y los tipos nuevos engordaban el hello.
- Arreglo (commit 74fb618): mientras un GM/oficial con el addon está conectado (oído en los últimos 15 min) los miembros
  responden como en la 1.0 (solo lo suyo); `presence` no cuenta para alargar las rondas; hash vacío compacto para
  `presence`/`repudiate`. S1 queda en 478 partes (la 1.0.1, 312) y S4 (sin oficiales) en 450 (1.0.1: 353).
- Lo que queda de más es sobre todo la `presence` (un registro nuevo por miembro que los oficiales reenvían en cada
  hello). Probé empaquetar más registros pequeños por mensaje y lo revertí: rompía 3 tests de paginación y estimación.

- S8 por emisor (herramienta `wt/tools/tally.js`, 3 min): en la 1.1 los oficiales mandan 1894 perfiles y 310 presence;
  en la 1.0.1, 1562 perfiles en total. Los miembros mandan solo lo suyo (el corte por oficial conectado funciona), así
  que el exceso viene de las respuestas de los oficiales. Probé enviar las presence de 10 en 10: no cambió la cola
  (547), descartado.

## Qué falta / siguiente paso
1. Resultado de S13 (AC8) y de la regresión del simulador S1–S9 (AC9).
2. ~~Medir el tamaño de SavedVariables con 200 miembros~~ hecho (script de medida con el simulador, cliente Mb1, 200 miembros):
   200 perfiles + 20 squads = 63 KB; + 200 presence = 89 KB; + 2000 pendientes (el máximo) = 663 KB. Los pendientes pesan
   ~290 bytes cada uno; en una guild normal hay pocos (caducan a los 7 días), pero el peor caso son ~0,6 MB.
3. Revisión QA a ciegas y prueba de BRO en el juego (AC7 con BugSack).

## 7-nov 09:xx — bucle de la cola de S8: 3 arreglos fallidos → ESCALADO a BRO (regla: máx. 3)
| # | Commit | Cambio | S8 (cola ≤500) | S2 (convergencia) |
|---|---|---|---|---|
| 1 | e54fbc1 | (estado de partida) | FAIL 547-553 | PASS |
| 2 | a321d40 | los oficiales no reenvían presence ajenas; tope de 6 para los miembros | PASS 397 | **FAIL** (baseline no converge) |
| 3 | c2c7aa3 | tope de 6 presence ajenas por respuesta para TODOS (también los oficiales) | **FAIL 549** | PASS |
- Causa de que el 2 rompiera S2: la condición `onlyAuthor == nil or nPres >= MAX` hacía que nadie reenviara presence ajenas (en P2P `onlyAuthor` también es nil).
- Suposición que sospecho falsa: «el tope por respuesta basta». S8 indica que lo que llena la cola es que los OFICIALES reenvíen presence ajenas en cada hello, aunque sean pocas por respuesta.
- Propuesta (4.º intento, solo con el OK de BRO): los oficiales no reenvían presence ajenas (`isOfficerMe()`), los miembros en P2P sí, con el tope de 6. Alternativas: aceptar ~550 en el umbral de S8, o que presence no se reenvíe nunca (el contador va más lento).
- AC8 (S13, 40 clientes): en este entorno no acaba ni con `--s13min 15` (timeout de 25 min) ni con `--s13min 5` (timeout de 26 min; probado con a321d40). Hay que medirlo en otra máquina o con menos clientes (p. ej., 20 y su versión 1.0.1 de referencia). Mientras tanto, la referencia de carga es S8 (20 clientes).
