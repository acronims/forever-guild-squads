# Guild Squads — Arquitectura

English → [ARCHITECTURE.md](../en/ARCHITECTURE.md)

Objetivo: cliente WoW Forever 1.60.1 (`## Interface: 16001`). Sin librerías embebidas. Las referencias a ficheros apuntan al árbol actual.

## 1. Mapa de módulos (orden de carga del TOC)

Lua puro (`Core/`, sin API de WoW, con tests unitarios fuera del juego):

| Fichero | Responsabilidad |
|---|---|
| `Locales/enUS.lua`, `Locales/esES.lua` | Tablas de textos (las mismas claves en los dos). |
| `Core/Serialize.lua` | Serializador determinista con tipos, escapado para el transporte, hash; `ns.apiFn`, que resuelve la API en el momento de la llamada. |
| `Core/Permissions.lua` | Decisiones de rango sobre una función `roster(name)` inyectada: `isGM` (rango 0), `isOfficer` (`settings.officerRanks`), `canEditSettings`, `canCreateSquad`, `canManageSquad`. |
| `Core/Chunk.lua` | Parte un payload escapado en mensajes de ≤255 bytes y los vuelve a montar. |
| `Core/Queue.lua` | Cola de envío con cubo de fichas (por defecto 1 msg/s, ráfaga 4, máx. 2000 elementos) que se retiene mientras las comunicaciones están bloqueadas. |
| `Core/Model.lua` | Registros, saneado contra el esquema, merge por última escritura (LWW), validación de autoridad, partición de la base de datos por guild + migraciones, `registerKind` para tipos de extensión. |
| `Core/Match.lua` | Puntuación de «Encaje» con motivos explicables; filtros del Buscador. |
| `Core/Logo.lua` | Datos del escudo (índices de icono / color / borde). |
| `Core/Call.lua` | Payload de «Llamar al squad» y reglas de enfriamiento/antispam. |
| `Core/Content.lua` | Catálogo de contenido PvE (mazmorras/bandas, rangos de nivel, alias). |
| `Core/Roster.lua` | Rosters de banda 10/20/40: registros `roster`, `rsvp`, `attendance`, `witness`, plantillas semanales, plan de invitación, exportación a Discord. |
| `Core/Progress.lua` | Rankings: esquema de MetricEvent, regla de testigos, deduplicación diaria, pesos, tope por wipe, ids de wipe (`W<n>`), temporadas. |
| `Core/Races.lua` | Carreras del Salón de la fama (Top 100/10/3) a partir de observaciones replicadas; anulaciones del GM; tipo `vconfirm`. |
| `Core/Catalog.lua` | El catálogo del GM: tipos `achdef` (activado/desactivado, tamaño del Top, nombre, carreras/insignias propias) y `achgrant` (insignias otorgadas); tamaño efectivo, desactivado/legado, planes de cambio en bloque. |
| `Core/Celebrate.lua` | Celebraciones: qué se anuncia (ajustes del GM), un solo anunciante por evento mediante un claim, límite de frecuencia. |
| `Core/Diag.lua` | Modelo del diagnóstico, guardado en `GuildSquadsDB.diag`. |

Pegamento con WoW e interfaz:

| Fichero | Responsabilidad |
|---|---|
| `Comm.lua` | Transporte: serializar → escapar → trocear → encolar → `C_ChatInfo.SendAddonMessage`, prefijo `GSquads`; retención en bloqueo. |
| `Sync.lua` | Replicación de registros (`D`, `H`), confianza en reenvíos, paginación del hello, despachador de tags. |
| `UI/Widgets.lua` | Kit de componentes; cada plantilla/atlas de Retail se prueba bajo `pcall` con alternativa simple. |
| `UI/Main.lua` | Ventana principal y pestañas; las pantallas se registran en `ns.UI.panels`. |
| `GuildSquads.lua` | Arranque: SavedVariables, caché del roster de la guild, selección de guild, acciones locales, temporizadores, comandos `/gsq`. |
| `Progress.lua` | Pegamento de los rankings: `PLAYER_LEVEL_UP`, `ENCOUNTER_END`, resultados PvP/HK, replicación de eventos (`E`), resúmenes de wipe (`SQ`/`SR`). |
| `Hall.lua` | Pegamento del Salón de la fama: detección, observaciones (`RO`/`RP`), claims de celebración (`CL`), lector de profesiones. |
| `Raids.lua` | Pegamento de los rosters de banda: escrituras firmadas, RSVP, invitar en un clic (APIs protegidas, solo con clic del usuario). |
| `Diag.lua` | Pegamento del diagnóstico (`/gsq diag`). |
| `UI/Panels.lua` | Mi squad · Squads · Buscador · Mi perfil · Ajustes (GM) · Crear squad. |
| `UI/Ranking.lua` | Pestaña Ranking (5 categorías + General, selector Wipe/Temporada) y franja de logros. |
| `UI/Raids.lua` | Pestaña Bandas (vista de lista + vista de roster). |
| `UI/Hall.lua` | Pestaña Salón de la fama. |
| `UI/Catalog.lua` | Ajustes > Logros (solo el GM): lista del catálogo, acciones en bloque, asistente «Nuevo logro», insignias otorgadas. |
| `UI/Minimap.lua` | Botón propio del minimapa (sin LibDBIcon). |

## 2. Modelo de datos

Registro (`Core/Model.lua`): `{ k = tipo, id = cadena, a = autor, ts = número, sq = número, d = datos }`. El merge es por última escritura sobre la versión `(ts, sq, autor)` (`vkey` en `Sync.lua`), con reglas de desempate propias de cada tipo.

Tipos base (`KINDS` en `Sync.lua`): `settings`, `squad`, `profile`, `reject`, `boss`, `annul`.
Tipos de extensión vía `M.registerKind`: `roster`, `rsvp`, `attendance`, `witness` (`Core/Roster.lua`), `vconfirm` (`Core/Races.lua`), `achdef` / `achgrant` (`Core/Catalog.lua`, orden 12/13; solo el GM). Un cliente que no conoce un tipo lo rechaza (`Model.validShape` -> `kind`, se cuenta en `Sync.stats.bad`) y sigue sincronizando el resto; las respuestas al hello solo llevan un tipo de extensión a un par cuyo hello trae hashes de ese tipo.

No son registros: los MetricEvents (tag `E`, `Core/Progress.lua`) y las observaciones de carreras (`RO`/`RP`, `Core/Races.lua`). Las puntuaciones y los resultados de las carreras se calculan en local a partir de ellos y nunca se transmiten (salvo los resúmenes de wipe de GM/oficiales, más abajo).

La membresía necesita los dos lados: el capitán incluye al jugador en el registro del squad **y** el perfil del jugador apunta al squad.

## 3. Protocolo de sincronización

- Prefijo `GSquads` (`Comm.PREFIX`), canal GUILD, WHISPER para respuestas dirigidas.
- Tags de mensaje (despachador en `Sync.lua`):

| Tag | Significado |
|---|---|
| `D` | Registros (deltas en vivo y respuestas al hello). |
| `H` | Hello con hashes de estado por cubos y por tipo. |
| `C` | Llamada al squad (susurro). |
| `E` | MetricEvents (en vivo, y lotes de puesta al día por susurro). |
| `RO` / `RP` | Observaciones de carreras: en vivo (solo el autor) / páginas de puesta al día. |
| `SQ` / `SR` | Petición / respuesta de resumen de wipe (la respuesta solo se acepta de GM/oficial). |
| `CL` | Claim de celebración (anuncia el nombre más bajo entre los claims). |

- **Hello**: cuando carga el roster, `Sync.Hello` se lanza tras 3–10 s; las respuestas llevan solo los registros que difieren, hasta 60 por respuesta (`MAX_REPLY`), paginadas con un cursor por solicitante sobre claves `"%03d|id"` (orden numérico del tipo). Un cliente recién llegado repite el hello hasta 6 rondas más mientras siga aprendiendo (`MAX_ROUNDS`).
- **Antientropía**: un hello cada 600–1200 s, con jitter (`GuildSquads.lua`).
- **Troceado**: partes de ≤255 bytes; los mensajes a medio recibir se recogen cada 30 s de tráfico.
- **Throttle**: cubo de fichas de ~1 msg/s, ráfaga 4; los registros propios recientes, los eventos, las observaciones en vivo y los claims salen como «urgentes», por delante del atraso de respuestas.
- **Retenciones**: no se envía nada durante encuentros, partidas PvP ni `C_ChatInfo.InChatMessagingLockdown()`.
- Los registros con más de 300 s en el futuro se rechazan (se reintentan más tarde); los que llegan antes de que cargue el roster de la guild esperan en una lista de pendientes (`MAX_PENDING` 5000).

```mermaid
flowchart LR
  A[Acción local] --> V{Model.validate + Permissions}
  V -->|ok| S[(GuildSquadsDB.guilds[key])]
  S --> Ser[Serializar + escapar] --> Ch[Trocear ≤255 B] --> Q[Cola 1 msg/s, ráfaga 4]
  Q -->|sin bloqueo| W[(Canal de addon GUILD 'GSquads')]
  W --> R[CHAT_MSG_ADDON] --> As[Reensamblar] --> T{tag}
  T -->|D/H| Sy[Sync: confianza en vivo/reenvío] --> V
  T -->|E/SQ/SR| P[Pegamento de Progress]
  T -->|RO/RP/CL| H[Pegamento de Hall]
```

## 4. Modelo de confianza

- Cada cliente vuelve a validar cada registro contra su propio roster de la guild; nada se da por bueno solo por haber llegado.
- Autoridad (`Core/Permissions.lua`): solo el rango 0 (GM) escribe `settings`; solo el dueño escribe un `profile`; solo el capitán o el GM gestionan un squad; oficiales = GM + los rangos de `settings.officerRanks`.
- Reenvío (cabecera de `Sync.lua`): un registro solo se acepta en vivo si el remitente es su autor; las copias reenviadas, solo de GM/oficiales. La misma regla vale para observaciones y resúmenes de wipe. Sin GM ni oficial conectado, los clientes solo reciben lo que publican los propios autores.
- Rosters de banda (`Core/Roster.lua`): el `roster` lo escribe su dueño (mientras sea RL/oficial), el GM, o los oficiales si el GM lo permite (`offEdit`); el `rsvp`, solo el jugador; la `attendance`, el RL/GM tras cerrar, hasta 7 días (`FIX_DAYS`); asistencia final = registro oficial + nombres informados por ≥2 testigos.
- «Firmado» aquí significa registros con autor validados por rango, no firmas criptográficas: un GM/oficial con un cliente modificado puede seguir falsificando reenvíos (ver [README, Limitaciones conocidas](../../README.es.md#limitaciones-conocidas)).

## 5. Persistencia

- SavedVariables `GuildSquadsDB` (por cuenta); los datos se separan por guild en `GuildSquadsDB.guilds[guildKey]` (`M.guildDB`), así que los alts de otras guilds nunca los tocan. Diagnóstico en `GuildSquadsDB.diag`.
- La base de datos lleva versión de esquema; al cargar se limpian los números no finitos guardados.
- Un cambio de guild sin `/reload` guarda la partición vieja y carga la nueva.

## 6. Temporizadores y rendimiento

- `ns.After` / ticker: `C_Timer.After` / `C_Timer.NewTicker` si existen; si no, una alternativa con `OnUpdate` (`GuildSquads.lua`); la cola la bombea un ticker de 0,2 s (`Comm.lua`).
- Las ráfagas de eventos (`UPDATE_FACTION`, `SKILL_LINES_CHANGED`, `PLAYER_PVP_KILLS_CHANGED`) se agrupan en una sola muestra (~2 s).
- Una resincronización completa de una guild grande tarda minutos por diseño (throttle); S8 mide msgs/s con 500 miembros / 100 squads.

## 7. Pruebas

- `tests/run.js`: carga `Core/*.lua` y el pegamento en **fengari** (VM de Lua 5.3 en JS) con los mocks de `tests/harness.lua` y ejecuta todos los `tests/*_spec.lua`.
- `tests/gates.js` (rompe el build ante cualquier fallo): sintaxis Lua 5.1 (luaparse) de cada `.lua`; cada global llamada o referenciada frente a la lista de la API 1.60.1 incluida en `tests/tools/`, salvo que esté protegida (solo protege una referencia desnuda: `if X then`, `X and X()`, `if not X then return end`, `ns.apiFn("X")`; `if X() then` / `X() or 0` no protegen); comprobaciones del TOC (Interface 16001, SavedVariables, ficheros con mayúsculas exactas, todos los `.lua` del addon listados); paridad de claves enUS/esES. Un autotest en `tests/tools/` demuestra que la barrera rechaza llamadas sin proteger dentro de condiciones.
- `tests/sim/` (`run.js`, `sim.js`, `scenarios.js`, `client.lua`, `fakewow.lua`): simulador multi-cliente, escenarios S1–S10: S1 convergencia del ciclo de vida del squad · S2 ajustes del GM con 30 clientes, ajustes falsificados ignorados · S3 puesta al día de un cliente nuevo · S4 muerte de jefe con las comunicaciones bloqueadas · S5 un mensaje de celebración por evento · S6 cambio de wipe con desfase de reloj de ±200 s · S7 RSVP/cierre/firma del roster de banda · S8 carga con 500 miembros/100 squads · S9 1 h de caos con 5 % de pérdida y /reload · S10 catálogo del GM con 30 clientes (un cliente que no conoce un tipo de registro lo ignora sin error). La CI los ejecuta todos salvo S10 con la semilla 7303. Resultados: [SIMULATOR-RESULTS.md](SIMULATOR-RESULTS.md).
- Los tests unitarios incluyen una carga en frío con una API 16001 falsa y estricta y `GuildSquadsDB = nil`.
