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
| AC0 referencia S8g (1.1 y 1.0.1) | no ejecutado | sim `S8g` | — |
| AC1 convergencia S11 + S15 (squads incluidos, ≤3 sesiones) | no ejecutado | sim `S11`, `S15` | — |
| AC2 reparto (≤15 % por cliente, oficial ≤30 % de hellos) | no ejecutado | sim `S8g` + `tools/tally.js` | — |
| AC3 latencia quórum (95 % ≤3 min, 100 % ≤10 min, 5 semillas) | no ejecutado | sim `S8g` | — |
| AC4 envenenamiento (S16, tope 200 por reenviador) | no ejecutado | sim `S16` + unidad | — |
| AC5 tráfico total (≤1.1 + 20 %, cola ≤500, S8 PASS) | no ejecutado | sim `S8g`, `S8` | — |
| AC6 compatibilidad (S17: 2×1.0.1 + 2×1.1 entre 8) | no ejecutado | sim `S17` | — |
| AC7 batería + CHANGELOG ES/EN | no ejecutado | `run.js`, `gates.js`, sim S1–S14 | — |

## Bitácora
- 7-nov: worktree `wt/v1.2` creado desde 636e545; spec copiado; línea base en verde.
