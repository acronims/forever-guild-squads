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
- [ ] **AC3 — latencia y aviso (rehecho por BRO el 7-nov a las 19:04: «¿puede hacerse de forma asíncrona y avisar por chat al usuario de que ya está sync?»):** la sincronización sigue en segundo plano, sin bloquear la interfaz. En S8g, el recién llegado tiene el 95 % en ≤240 s (no peor que la 1.1) y el 100 % en ≤600 s (p95 de 5 semillas). **Aviso:** cuando el cliente queda sincronizado (una ronda de hello sin diferencias, o 60 s sin registros nuevos después de la última ronda), escribe **una sola vez por sesión** una línea local en el chat (`DEFAULT_CHAT_FRAME:AddMessage`, que no se envía a nadie): «Guild Squads: sincronizado (N registros, M pendientes de verificar)», en ES y EN. Hay test de unidad para el disparo único y para el texto, y el simulador comprueba que salta en S8g.
- [ ] **AC4 — envenenamiento:** en S16, 1 y luego 2 miembros maliciosos inventan un `settings` del GM y un `squad` ajeno. Con 1 malicioso nunca llega a verificado. Con `QUORUM_AUTH - 1` cómplices, tampoco. Cuando el GM se conecta, el desmentido lo borra de todos los clientes y los reenviadores aparecen en `diag`. Además, el tope de 200 pendientes por reenviador aguanta una inundación de 5.000 registros falsos sin expulsar los pendientes legítimos. (Con QUORUM_AUTH = 2: 1 malicioso nunca verifica; 2 cómplices sí pueden, hasta que el autor o un oficial lo desmienten. S16 se ajusta a eso y sigue comprobando el desmentido.)
- [ ] **AC5 — tráfico total:** en S8g, los partes totales de la 1.2 son como mucho los de la 1.1 más el margen de **D3**. La cola de ningún cliente pasa de 500 y nunca se choca con el bloqueo de combate. S8 (20 clientes, umbral 500) sigue en PASS.
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
- **Cambio de BRO (7-nov, 19:04):** D1 pasa a **2 reenviadores** (opción B, aceptando el riesgo de los alts). AC3 pasa a sincronización asíncrona con aviso (ver AC3).
- **Decidido (11:14):** D1 = 3 reenviadores (sustituido a las 19:04 por 2); D2 = mientras quede algún cliente viejo; D3 = +20 % como máximo.
- **D1 — Quórum para squads, ajustes y anulaciones:** *3 reenviadores* (recomendado, aguanta a un jugador con 2 alts) o *2*, como los perfiles (converge antes y es más fácil de falsear).
- **D2 — Hasta cuándo responden siempre los oficiales a 1.0.1/1.1:** *mientras quede algún cliente viejo* (recomendado) o *nunca desde la 1.2* (los clientes viejos se quedan sin sincronizar lo ajeno).
- **D3 — Margen de tráfico total frente a la 1.1:** *+0 %* (el reparto no puede costar más), *+20 %* (recomendado) o *+50 %* (converge más rápido).

## Anexo F: firmas (decisión de BRO del 8-nov a las 00:46: «2. firmas»; «1. acepto, probamos» = AC5 se acepta con 4481 partes)
**AC5:** se acepta tal como está (S8 1 min: 4481 partes frente a 2593 de la 1.1). Siguen siendo duros: cola ≤500 y 0 rechazos del throttle. No hay más intentos de tráfico.
**Objetivo:** H2/H3 y cualquier dato falso de alts o de clientes modificados deja de ser posible sin la clave del autor. Sin cuentas oficiales como raíz de confianza; como mucho, la de dev de BRO.
**Diseño:**
- **ed25519 con ccryptolib** (MIT, vendorizada con su aviso y los parches del SPIKE). La firma es **determinista según RFC 8032** (nonce = H(prefijo ‖ msg)); se cambia el nonce aleatorio de ccryptolib, porque WoW no tiene RNG criptográfico. Verificación **estricta**: se rechazan S ≥ L y los puntos de orden pequeño (lo de la maleabilidad del SPIKE).
- **Clave por personaje:** se genera una vez y se guarda en SavedVariables. La semilla es el sha512 de una mezcla de entropía: `debugprofilestop()` en N eventos de input o de frame, GetTime, GetServerTime, la posición del cursor, el GUID y math.random. Va con un test que compruebe que la semilla no se repite entre 1000 arranques simulados con relojes distintos. Se documenta el riesgo (entropía limitada).
- **Aprender claves (sin oficiales):** (1) **directamente de su dueño**, porque WoW garantiza el remitente de los mensajes de addon: TOFU, y la primera clave oída del dueño queda fijada; (2) reenviada por otros, solo si la firma la **clave de dev de BRO**, fijada en el código (el cliente de dev firma automáticamente las claves que oye directamente de sus dueños); o (3) reenviada con quórum 2, como «pendiente-débil», que se convierte en fija cuando se oye del dueño o del dev. Si una clave fija cambia, se rechaza y se avisa en `/gsq diag`; la rotación solo la puede hacer la clave vieja firmando la nueva, o el dev.
- **Firma por lote:** el autor firma un manifiesto (sha512 de cada registro suyo y seq) y lo vuelve a firmar cuando cambia. El receptor hace 1 verificación por manifiesto y comprueba cada registro con su hash. Las verificaciones van **en cola, repartidas en frames** (≤1 por frame, con pausa en combate y en encuentros) y con caché de las ya verificadas.
- **Reglas:** un registro authorial sin firma válida de su autor no se aplica nunca. Un `repudiate` solo vale si lo firma el autor o el dev; ya no hay quórum para borrar (H3 cerrado). Un perfil con `d.squad=A` solo cuenta si el roster de A, firmado por su capitán, incluye al autor (H2 cerrado). Squads y ajustes los firma su dueño (capitán o GM); el quórum queda solo para las claves.
- **Clave de dev:** BRO la genera fuera del juego (script node en tools/dev-key.js; la privada no va al repo y se guarda en .secrets). La pública se fija en Core/Trust.lua. El cliente de dev se reconoce porque tiene la privada importada con `/gsq dev import`, que solo se guarda en sus SavedVariables.
### ⚡ Cambio de BRO del 8-nov a las 01:02: «sin claves de dev, elimina mi parte». MANDA SOBRE EL ANEXO F
- **No hay clave de dev** ni notario, ni `/gsq dev import`, ni tools/dev-key.js. No hay ninguna raíz de confianza central.
- Aprender claves: (1) **directamente de su dueño** (TOFU, **fuerte**); (2) reenviada con quórum 2 → **débil**. Lo que firma una clave débil se muestra como «sin verificar» y nunca puede **borrar** ni **sustituir** datos firmados por una clave fuerte. Tampoco puede aplicar un `repudiate`, ni cambios de roster de squad o de ajustes: esos solo se aplican con una clave fuerte.
- **Conflicto:** cuando se oye al dueño en persona con una clave distinta de la débil, gana la del dueño. La débil y todo lo que firmó se descartan, y los reenviadores que la trajeron cuentan como sospechosos en `diag` (el tope de 200 por reenviador sigue).
- Rotación: solo con la clave vieja firmando la nueva. Si se pierde la clave (por ejemplo, se borran las SavedVariables), los demás tienen que hacer `/gsq trust reset <nombre>` a mano, y lo deja escrito en la guía del GM.
- AF5 se adapta: sin dev. AF6 (revisión de seguridad) incluye el ataque de «clave débil falsa para un jugador que el recién llegado no ha visto nunca» y comprueba que no puede borrar ni sustituir nada fuerte.

**Criterios de aceptación:**
- **AF1:** vectores RFC 8032 (los §7.1 TEST 1-3), firma y verificación interoperables con node `crypto` y rechazo de firmas maleables. Unidad en Fengari y en Lua 5.1.
- **AF2:** S16 rehecho: 2, 3 y 5 cómplices (alts) no consiguen aplicar un perfil, squad, ajuste ni repudiate falso de nadie. El legítimo llega.
- **AF3:** S11 y S15 convergen con las firmas: autorales 50/50 y squads 10/10, con ≤3 sesiones.
- **AF4:** coste: en S8 de 1 min no hay ninguna verificación que bloquee más de 1 por tick simulado. Partes ≤ 4481 × 1,25. Cola ≤500 y 0 throttle.
- **AF5:** cambio de clave: una clave fija que cambia sin la firma de la vieja se rechaza y sale en diag; con la firma de la vieja, se acepta.
- **AF6:** revisión de seguridad a ciegas centrada en las firmas: nonce, entropía, TOFU, clave de dev y repeticiones (replay, con el seq por autor). Ningún hallazgo alto o medio abierto.

### ⚡ Anexo G: certificación cruzada de claves (GO de BRO, 8-nov 03:15, «dale, investígalo»). Sustituye a «débil con quórum 2 de reenviadores»
- **Datos:** se siguen reenviando, porque van firmados por su autor (el reenviador solo hace de cartero). Un dato solo se aplica con el manifiesto verificado de su autor.
- **Certificado (attestation):** cada cliente publica UNA lista firmada con su clave: `{n, [hash12(nombre‖clave)] de las claves que ha oído EN PERSONA en los últimos 30 días}`. Se vuelve a firmar solo si cambia y viaja como los manifiestos (1 por emisor y destino cada 600 s o cuando cambia n).
- **Verificar la clave de un desconocido Z:** «certificada» si hay ≥2 certificados de emisores distintos con clave **fuerte para mí** (oídos en persona por mí) que incluyen hash12(Z‖K) **y ningún** certificado de un emisor fuerte con otra clave para Z. Si hay conflicto, queda **«disputada»**: se ve como sin verificar, no aplica nada nuevo y sale en diag. Si llega Z en persona, gana siempre su clave (Anexo F, BRO 03:09).
- **Opcional, solo si el tráfico lo permite:** un segundo salto. Un certificado de un emisor que es «certificado» para mí cuenta como 0,5. Se mide antes de decidir; por defecto está apagado.
- Lo certificado vale como fuerte para aplicar datos (perfiles y squads). Un `repudiate` sigue exigiendo la firma del propio autor.
- **Primero se investiga (Bitácora + docs/DESIGN-certificados.md, 1 página):** el tamaño del certificado con 200 miembros (hash12 → ~2,4 KB → partes), el coste en S8 de 1 min frente al tope AF4 (5601), cuántos verificados salen en S11 y S15, y el ataque de 2 alts conocidos en persona (S16b). Si el tráfico se pasa del tope: certificado delta (solo los cambios) o un filtro de Bloom de 1 KB, y se documenta la tasa de falsos positivos.
- **AF7:** S11 y S15: autorales 50/50 y squads 10/10 verificados con ≤3 sesiones. S16b: 2 alts conocidos certifican una clave falsa de Z; con 1 certificado honesto en contra queda disputada y no se aplica nada; cuando Z llega en persona, se aplica lo suyo y se descarta lo falso. S8 de 1 min: partes ≤5601.
