# PROGRESS v1.2 — toda la sincronización en P2P (rama `feat/v1.2-p2p`)

Spec: `docs/SPEC-v1.2-p2p.md` (aprobado 7-nov; D1 = quórum 3, D2 = los oficiales contestan siempre mientras quede algún
cliente viejo, D3 = tráfico total ≤ 1.1 + 20 %). Base: 636e545 (punta de `feat/v1.1-sync-p2p`). El spec nombra la rama
`feat/v1.2-p2p-all`; la tarea programada pide `feat/v1.2-p2p` y es la que se usa.

## Cómo se prueba
```
export NODE_PATH=/workspace/group/research/wowforever/wt/node/node_modules
node tests/run.js            # unidad + smoke
node tests/gates.js          # sintaxis / API / TOC / locales
node tests/sim/run.js <S..> --seed 7303     # en segundo plano, timeout ≤ 20 min
```
Línea base (7-nov, 636e545, sin tocar nada): `RESULT: 266 passed, 0 failed`, `GATES: OK`.

## Estado por criterio
Estados: no ejecutado · corriendo · reportado hecho · verificado (gate de evidencia).
| AC | Estado | Test | Evidencia / notas |
|---|---|---|---|
| AC0 referencia S8g (1.1 y 1.0.1) | verificado | sim `S8g` seed 7303 | 1.1 (636e545): partes **5762** (top Of2 718 = 12,5 %; Of1+Of2+Gm = 37 %), cola máx. 285, meanAll 0,159 msg/s, recién llegado t95 240 s / t100 250 s (220 registros), converge 15 s, 0 errores, PASS (1028 s). 1.0.1: partes 3299 (top Of1 588 = 17,8 %), cola máx. 235, meanAll 0,091, t95 260 s / t100 270 s, converge 15 s, PASS (687 s). Tope D3 para AC5: 5762 × 1,2 = **6914** partes. Ojo AC2: en la 1.1 ningún cliente pasa ya del 15 % (12,5 %); el reparto se mide por el peso conjunto de oficiales. Logs `wt/ac0/s8g-110.log`, `s8g-101.log` (+ `.json`). Contenedor borrado. |
| AC1 convergencia S11 + S15 (squads incluidos, ≤3 sesiones) | verificado (S11/S15); batería pendiente | sim `S11`, `S15`; unidad `p2p_spec` | Rojo sobre 1.1: S11 squads 5/10; S15 autorales 45/50 (presence ajenas). Verde tras el cambio (7-nov 11:47): **S11 PASS** (autorales 50/50, squads 10/10, 17,9 s) y **S15 PASS** (25,6 s), seed 7303, logs `/tmp/gsq/s11.log`, `s15.log`. Código: `M.P2P_AUTH` (autoridad relevada por un miembro → `p2p`, no `relay`), `X.QUORUM_AUTH = 3`, `X.quorumFor`, `X.protoOf`, hello `p2 = 2`, `ReplyFor`/`ForwardsFor`/`suppressed` aceptan autoridad para solicitantes `p2 ≥ 2`, `p2pOff` solo para solicitantes < 2. Unidad 266/266 (4 tests de la regla 1.1 «relay» pasados a «pending» + quórum 3). |
| AC2 reparto (≤15 % por cliente, oficial ≤30 % de hellos) | no ejecutado | sim `S8g` + `tools/tally.js` | — |
| AC3 latencia quórum (95 % ≤3 min, 100 % ≤10 min, 5 semillas) | no ejecutado | sim `S8g` | — |
| AC4 envenenamiento (S16, tope 200 por reenviador) | verificado (S16 + unidad); batería pendiente | sim `S16`; unidad `p2p_spec` (2 tests v1.2) | Rojo sobre 1a25844: S16 FAIL (inundación 2000 pendientes y el legítimo expulsado; desmentido de autoridad = `shape`; diag sin reenviadores). Verde (7-nov 11:57): **S16 PASS** 40 s — 1 y 2 cómplices nunca verifican `settings` ni el squad ajeno; 5000 falsos → 200 pendientes de Mb2, el legítimo sobrevive; GM y Mb1 se conectan → falsos fuera en todos; diag `relayers=Mb2-Realm:2,Mb3-Realm:2`. Código: `X.MAX_PEND_RELAYER = 200` (`cap`), `applyRepudiate` acepta tipos de autoridad, `getStored/setStored` (settings no es tabla con clave), `enforce` compara también con `via` (`settingsOf` rellena valores por defecto y mueve el hash). Unidad 268/268. |
| AC5 tráfico total (≤1.1 + 20 %, cola ≤500, S8 PASS) | no ejecutado | sim `S8g`, `S8` | — |
| AC6 compatibilidad (S17: 2×1.0.1 + 2×1.1 entre 8) | no ejecutado | sim `S17` | — |
| AC7 batería + CHANGELOG ES/EN | no ejecutado | `run.js`, `gates.js`, sim S1–S14 | — |

## Bitácora
- 7-nov: worktree `wt/v1.2` creado desde 636e545; spec copiado; línea base en verde.
- 7-nov 11:4x: escenario `S8g` (commit «test(sim): escenario S8g…»): 200 miembros, 40 clientes, 15 min de ediciones y un
  recién llegado vacío. Mide partes totales y por cliente, cola máxima, msg/s medios, t95/t100 del recién llegado y tiempo
  hasta converger. AC0 lanzado detached (no en Gilfoyle: no tiene node y es producción; el Mac mini sí). Copias congeladas:
  `wt/ac0/ref-110` (git archive 636e545) y `wt/ref-101`.
- 7-nov 11:4x: AC0 acabado (cifras arriba). S11 ampliado con 2 squads (Mb1, Mb4) y S15 nuevo (= S11 con el GM conectado todo el rato); los dos en rojo sobre la 1.1.
- 7-nov 11:47: AC1 en verde (S11, S15, unidad 266/266, gates OK). Batería S1–S12 + S14 corriendo para ver regresiones.
- Riesgo anotado para AC6: un 1.1 compara `payload.p2 == 1`; con el hello `p2 = 2` de la 1.2 un **miembro** 1.1 lo trata
  como 1.0 (solo sus propios registros). Los oficiales 1.1 siguen sirviéndolo. Se mide en S17; si falla, la salida es
  mandar `p2 = 1` y el nivel 1.2 en un campo aparte (desvío del spec, lo decidiría Anton por delegación).
- 7-nov 11:57: AC4 en verde (S16 + 2 tests de unidad).
- Siguiente: batería S1–S12 + S14 sobre el código de AC4; luego AC2/AC3/AC5 (muestra por cubos con `nonce`, `MAX_SAMPLE = 30`, oficiales con `p = 8/online`). Las S8g van detached en el Mac mini.
