# SPEC v1.2 — Toda la sincronización en P2P: cada instalado es un nodo (BORRADOR)

**Estado:** aprobado (7-nov, 11:14: BRO delega las decisiones en Anton; D1-D3 decididas al final). Base: rama `feat/v1.1-sync-p2p` (636e545).
**Pedido (BRO, 7-nov):** «que toda la comunicación funcione así, rollo nodos P2P entre los que lo tenemos instalado». «Cierra 1.1 y tira con 1.2».

## Objetivo
Que **todo** (perfiles, squads, avisos y el resto de registros) se propague de cliente a cliente entre los que tienen el addon, con la carga repartida: ningún jugador, tampoco los oficiales, hace de repetidor central. Los oficiales son un nodo más, con un sello de confianza que verifica al momento lo que reenvían.

## Contexto (código 1.1, leído en el worktree sin tocarlo)
- `Sync.lua` `onHello`: responde solo una fracción `p = 8/online`, pero **los oficiales responden siempre** y con `MAX_REPLY = 60` paginado por cursor. En S8 eso hizo que las colas de los oficiales pasaran de 500 (PROGRESS, bucle de 4 intentos).
- `Core/Model.lua:540` `M.P2P_KINDS` / `M.isP2P`: solo los registros autorales van en P2P (quórum 2, `Core/P2P.lua` `X.QUORUM = 2`). Los de autoridad (`squad`, `settings`, `annul`, `boss`, `roster`, `attendance`, `vconfirm`, `achdef`, `achgrant`, `profile` con `xferTo`, `reject req`) los reenvía solo el GM o un oficial (`M.provenance`, regla R06-1).
- `suppressed()` ya no vuelve a enviar lo que se ha oído con quórum desde el hello, pero solo para los autorales y solo si el solicitante es 1.1.
- Con un oficial conectado (`Sync.TrustedOnline`, 15 min) los miembros vuelven al modo 1.0 (`p2pOff`): el P2P solo funciona cuando no hay oficiales.

## Alcance
1. **Protocolo `p2 = 2`.** Lo anuncia el hello de la 1.2. Todo lo nuevo solo se hace con solicitantes `p2 >= 2`.
2. **Reparto de respuestas.** Cada hello lo contestan unos **8 nodos** (`p = 8/online`, **también los oficiales**). Cada nodo manda una **muestra al azar** del diff, con un tope de `MAX_SAMPLE = 30` registros por respuesta. La muestra va por cubos: el solicitante manda un `nonce` y cada nodo elige 2 de 8 cubos `hash(id, nonce) mod 8`. Así cada registro lo envían de media 2 nodos distintos y llega con quórum en una sola ronda. Desaparece `p2pOff`.
3. **Supresión general.** `suppressed()` se aplica a todos los tipos: no se envía una versión que ya se ha oído desde el hello con quórum, con sello de oficial o del propio autor.
4. **Registros de autoridad en P2P** (squads, ajustes, anulaciones, roster, catálogo…): cualquier miembro puede reenviarlos. Quedan **pendientes** hasta tener un quórum de `QUORUM_AUTH` reenviadores distintos (**D1**), el sello de un oficial o el autor en directo. Mientras no se verifican se muestran en gris y no cuentan para nada. Su validación (`validateSquad`, `R.canEdit`…) no cambia: el quórum solo decide si la copia es auténtica, no si el autor tenía permiso.
5. **Sello de oficial.** Lo que reenvía un GM u oficial se verifica al momento, como en la 1.1, pero ya no tiene que contestar siempre.
6. **Desmentido para todos los tipos.** `repudiate` también vale para los de autoridad (lo emite el autor, por ejemplo el GM, cuando se conecta). La lista negra local queda igual (3 desmentidos = 7 días sin voto) y se añade un **tope de 200 pendientes por reenviador**, para que uno solo no pueda echar a los demás de `MAX_PEND`.
7. **Avisos** (mensajes `C` / `E` y las convocatorias): pasan por la misma vía, con quórum y supresión, si se pueden guardar como registro. Si no, se quedan como están (ver Riesgos).
8. `/gsq diag`: `p2 proto= sample= suppressed= auth-pend= seals=`.

## Fuera de alcance
Firmas criptográficas. Cambiar quién tiene autoridad. Opciones nuevas para el GM. Detectar alts (ver Riesgos). Cambiar `HallGlue` y las carreras (`RO`/`RP`/`CL`), que tienen su propio protocolo.

## Criterios de aceptación (simulador `tests/sim`, `--seed 7303`, comparado con la 1.1 mediante `GSQ_REF=636e545`)
- [ ] **AC0 (referencia):** medir **S8g**, una guild de 200 con 40 clientes y 15 minutos (el S13 de la 1.1), con la 1.1 y con la 1.0.1, **en Gilfoyle o detached**: S13 no acaba aquí en 25 minutos. Se anotan los partes totales, la cola máxima por cliente, la media de mensajes por segundo y el tiempo hasta converger. Sin esta referencia no se puede evaluar AC5.
- [ ] **AC1 — convergencia sin oficiales y con ellos:** con S11 (5 clientes escalonados, sin oficiales) y una variante S15 con el GM conectado, el 100 % de los registros, **también los squads**, llegan a todos en 3 sesiones solapadas o menos. En la 1.1, los squads de S11 no convergen sin oficial (rojo esperado).
- [ ] **AC2 — reparto:** en S8g, ningún cliente envía más del 15 % de los partes totales. En la 1.1, los oficiales concentran la mayoría (`tools/tally.js`). Un oficial no responde a más del 30 % de los hellos.
- [ ] **AC3 — latencia hasta tener quórum:** en S8g, un recién llegado tiene verificado el 95 % de lo que le falta en 3 minutos o menos y el 100 % en 10 minutos o menos (p50 y p95 de 5 semillas).
- [ ] **AC4 — envenenamiento:** en S16, 1 y luego 2 miembros maliciosos inventan un `settings` del GM y un `squad` ajeno. Con 1 malicioso nunca llega a verificado. Con `QUORUM_AUTH - 1` cómplices, tampoco. Cuando el GM se conecta, el desmentido lo borra de todos los clientes y los reenviadores aparecen en `diag`. Además, el tope de 200 pendientes por reenviador aguanta una inundación de 5.000 registros falsos sin expulsar los pendientes legítimos.
- [ ] **AC5 — tráfico total (rehecho el 7-nov a las 13:0x; decide Anton por delegación de BRO):** en S8g, los **bytes enviados** (y los registros) de la 1.2 son como mucho los de la 1.1 + 20 % (D3). Además, todo esto es obligatorio: **0 rechazos del throttle**, pico 1 s ≤10 mensajes por cliente, cola ≤500 por cliente y S8 en PASS. El número de mensajes se anota, pero no decide: lo que cuesta en WoW son los bytes y los rechazos por ráfaga, y ambos siguen siendo duros. Motivo: la 1.2 recibe +18 % de registros (dentro de D3) y da 1,9× en mensajes solo porque los lotes son más pequeños.
- [ ] **AC6 — compatibilidad:** S14 ampliado (S17), con 2 clientes 1.0.1 y 2 clientes 1.1 entre 8 de la 1.2: 0 errores de Lua. Los 1.0.1 y los 1.1 siguen recibiendo lo suyo y lo que reenvía un oficial. Los registros de autoridad que reenvía un miembro **nunca** se envían a un solicitante con `p2 < 2`, porque ahí lo rechazaría como `relay`.
- [ ] **AC7:** la batería sigue en verde (unidad, `gates.js`, simulador de S1 a S14). CHANGELOG ES/EN.

## Compatibilidad
- **1.0.1** (no manda `p2`): solo acepta reenvíos de oficiales. Mientras haya solicitantes 1.0.1, los oficiales les **siguen contestando siempre**, como en la 1.1. Es el modo heredado, y lo que dure lo decide **D2**.
- **1.1** (`p2 = 1`): acepta los autorales con quórum y rechaza los de autoridad de un miembro. Se le contesta como en la 1.1. Nunca le llegan los de autoridad de un miembro ni los cubos de la 1.2.
- **1.2 ↔ 1.2:** todo lo de arriba. Los campos nuevos (`nonce`, `p2 = 2`) los ignoran las versiones viejas sin dar error (comprobado en S14 para `presence`/`repudiate`).

## Riesgos / suposiciones
- **Latencia hasta tener quórum:** con muestras al azar, dos nodos pueden no coincidir en un registro, y entonces hace falta otra ronda. Los cubos con `nonce` lo resuelven sobre el papel, pero hay que medirlo (AC3). Con menos de 3 instalados conectados, lo de autoridad se queda en gris hasta que llegue un oficial o el autor.
- **Tráfico total:** 8 nodos × 30 registros ≈ 240 registros por hello, frente a los 60 de cada oficial que manda la 1.1. Sin la supresión, el total sube. El tope y la supresión son los mandos, y AC5 es el freno. Lo de la 1.1 (4 intentos para que S8 pasara) indica que esto **es lo más probable que falle**.
- **Envenenamiento:** la amenaza real son los **alts del mismo jugador**, que cuentan como reenviadores distintos y no se pueden distinguir. Con quórum 2, un jugador con 2 personajes puede crear un squad o un ajuste falso que se ve como verificado hasta que el autor o un oficial lo desmienten. Por eso propongo `QUORUM_AUTH = 3` (D1) y que el sello de oficial pueda tumbar una versión verificada por quórum.
- **Tamaño de SavedVariables:** los pendientes de autoridad suman a los ~0,6 MB del peor caso de la 1.1, así que hay que medir con 200 miembros.
- **Suposición:** que «avisos» son los mensajes `C`/`E` y las convocatorias. Si BRO se refiere a otra cosa, el punto 7 del alcance cambia.
- **Entorno:** los escenarios de 40 clientes no acaban en el contenedor de Anton. Hay que correrlos detached en Gilfoyle (y montarlo es parte de la estimación).

## Aislamiento / revisor
Rama `feat/v1.2-p2p-all` desde la 1.1 cerrada, en su propio worktree. Commits **sin atribución**. Beta solo con el GO de BRO. El revisor es un QA a ciegas distinto del constructor, más Anton. La prueba en el juego la hace BRO con 3-4 jugadores, con y sin el GM.

## Estimación
**~30 h** (±8): 2 h para cerrar el spec, 4 h para la referencia S8g en Gilfoyle, 10 h de código (cubos, supresión, autoridad en P2P, desmentido y topes), 6 h de escenarios S15-S17 y ajustes, 5 h del bucle de carga (el riesgo principal), 3 h de QA y documentación. Son unos 4 días de trabajo, sin contar la beta.

## Decisiones (tomadas por Anton por delegación de BRO, 7-nov 11:14)
- **Decidido:** D1 = 3 reenviadores; D2 = mientras quede algún cliente viejo; D3 = +20 % como máximo.
- **D1 — Quórum para squads, ajustes y anulaciones:** *3 reenviadores* (recomendado, aguanta a un jugador con 2 alts) o *2*, como los perfiles (converge antes y es más fácil de falsear).
- **D2 — Hasta cuándo responden siempre los oficiales a 1.0.1/1.1:** *mientras quede algún cliente viejo* (recomendado) o *nunca desde la 1.2* (los clientes viejos se quedan sin sincronizar lo ajeno).
- **D3 — Margen de tráfico total frente a la 1.1:** *+0 %* (el reparto no puede costar más), *+20 %* (recomendado) o *+50 %* (converge más rápido).
