# SPEC v2.0 — Identidad de personaje «Nombre Apellido» (PROTO 3)

**Estado:** borrador para GO de BRO (9-nov 03:33: «SACA LA 2.0 YA, PUESTOS»). Autor: Anton (subagente spec-20), 9-nov 03:33-03:55 CET.
**Base:** la 1.2.2 cerrada. Hoy es `fix/1.2.2` @ `5e4a845`, con cambios sin commitear en `wt/a-122` (Comm.lua, Core/Model.lua, GuildSquads.lua, tests/sim/*, tests/whisper_spec.lua). **Todas las líneas `fichero:línea` de esta SPEC son de `5e4a845`**: al rebasar sobre la 1.2.2 final hay que volver a sacar los números con el grep del §3.
**Cobertura de esta SPEC:** leídos enteros `agents/research-surnames.md`, `agents/hotfix-121.md`, `spec-driven-development.md` y `docs/SPEC-v1.2-p2p.md` (con los anexos F y G). El commit 3e16bc2 (la red de la 1.2.2) lo he leído en diff. Del código, por grep: los 37 `.lua` del addon (240 resultados del grep principal y unos 60 del secundario). Trozos leídos de verdad: GuildSquads.lua:25-180 y :230-275, Core/Model.lua:12-40, :275-290, :519-532 y :780-880, Comm.lua:395-460, Raids.lua:200-240, tests/sim/fakewow.lua:55-150 y tests/sim/sim.js:265-330. No hay ningún fichero `.lua` leído entero. `hotfix-122.md` no existe todavía.

---

## 1. Objetivo, contexto, alcance y fuera de alcance

**Objetivo.** En WoW Forever la identidad de un personaje dentro del addon pasa a ser **«Nombre Apellido»**: sin reino y única en la región. Esa identidad se usa como autor, clave de confianza, firma, certificado, índice y destino de WHISPER. Así, dos «Kas» con distinto apellido dejan de ser el mismo personaje y ningún susurro sale con «-Reino».

**Contexto.**
- `research-surnames.md`: la identidad es «Nombre Apellido», sin reino y única en la región (Blizzard: *"a full name that is unique within a region"*). `RegionalUniqueNamesEnabled()` es el interruptor. `UnitName(u)` devuelve `(nombre, apellido)`. El `sender` de CHAT_MSG_ADDON y WHISPER llega como «Nombre Apellido», sin reino; lo midieron 3 addons de terceros, nosotros no. El destino de WHISPER es «Nombre Apellido», sin «-Reino». El roster da «Nombre Apellido-Reino».
- La 1.2.1 (366b2a9) le quitó el apellido a la clave («Nombre-Reino»). La 1.2.2 (3e16bc2) **dejó la identidad como estaba** y construye el destino aparte: `ns.whisperTarget`, `Comm.SystemFilter` y el sobre GUILD «W». La identidad «Nombre-Reino» **no es única**: «Kas Pitas-R» y «Kas Mora-R» dan los dos «Kas-R». Esta SPEC cambia lo que se firma, así que necesita protocolo nuevo.
- Hay fallos de la 1.2.x que en Forever se dan siempre: Hall.lua:176 y Progress.lua:221 construyen `name.."-"..realm` con el 2.º valor de `UnitName("partyN")`, que es el **apellido** («Kas-Pitas»). Los testigos de grupo nunca casan con los squads. Además, `InviteUnit` recibe «Nombre-Reino» (Core/Roster.lua:798 → Raids.lua:218), igual que los susurros rotos de la 1.2.1.

**Alcance.**
1. El modo de identidad y **una sola función `ns.id`** para cada entrada (§2).
2. Que pasen por `ns.id` todos los sitios del inventario (§3).
3. PROTO 3, etiquetas de firma nuevas y topes de longitud (§4).
4. La migración idempotente de SavedVariables (§5).
5. El destino de WHISPER en modo Forever, conservando la red de la 1.2.2 (§6).
6. Los nombres con apellido en la UI (§7).
7. El WoW falso en modo Forever, los escenarios S20-S23 y una regla nueva en `gates.js` (§8).
8. CHANGELOG ES/EN 2.0, CONTRIBUTING «WoW Forever names» y la guía del GM (`/gsq trust reset` con apellido).

**Fuera de alcance.**
- Ponerse en contacto con clientes 1.x. Son dos redes separadas; la única opción es D2.
- Cambiar quién tiene autoridad, los quórums, AF/AG o el formato de los registros (solo cambian los nombres que llevan dentro).
- La clave de partición de la guild (`M.guildKey`, Core/Model.lua:847: «Guild-Reino») y las ids de squad ya creadas (`me..":"..ts`, GuildSquads.lua:446, que son opacas y no se analizan).
- Overlord: `GetMaxCapturesForDedupName` sigue recibiendo el nombre de pila (Hall.lua:381, Progress.lua:361), porque la clave la decide Overlord.
- Rusificar nombres (`Enum.NamePartType`).
- Publicar. El tag y CurseForge van con el GO de BRO, después de su prueba en el juego.

---

## 2. Modelo de identidad

### 2.1 El modo
- `ns.ID_MODE = "forever"` si `type(RegionalUniqueNamesEnabled) == "function"` y `pcall` devuelve `true`. Si no, `"realm"`.
- Se evalúa en `ADDON_LOADED` y otra vez en `PLAYER_LOGIN`; manda el de `PLAYER_LOGIN`. Después se congela durante la sesión. Mientras sea `nil`, `ns.me()` devuelve nil y no se escribe nada (ya pasa así antes de que el roster esté listo).
- En los tests se fuerza con `ns.ID_MODE` antes de cargar. `/gsq diag` añade la línea `id mode=forever me=Kas Pitas surname=yes`.

### 2.2 La forma canónica
| Modo | Identidad | Ejemplo |
|---|---|---|
| forever | `Nombre .. " " .. Apellido`, sin reino, con mayúsculas como las da el servidor | `Kas Pitas` |
| realm | `Nombre .. "-" .. Reino` (lo mismo que `ns.fullName` en la 1.2.2) | `Kas-CAMWOWEU4Realm6PvP` |

### 2.3 Una función para todas las entradas: `ns.id(a, b)` → identidad o nil
Todo pasa por aquí. La parte pura vive en `Core/Identity.lua` (`I.id(a, b, ctx)`; `ctx = { mode, myRealm, index }`, sin globales). `ns.id` es un envoltorio con el modo, el reino propio y el índice del roster.

| Entrada (quién llama) | Llamada | forever → | realm → |
|---|---|---|---|
| `sender` de CHAT_MSG_ADDON/WHISPER | `ns.id(sender)` | `"Kas Pitas"` → `Kas Pitas`; `"Kas Pitas-R"` → `Kas Pitas`; `"Kas"` (sin apellido, contra lo medido) → índice del roster por nombre de pila: si es único, `Kas Pitas`; si hay 2, **nil** (se descarta y cuenta en `peers notInRoster=`) | como la 1.2.2 |
| Roster: `GetGuildRosterInfo` / `GetRaidRosterInfo` | `ns.id(name)` | `"Kas Pitas-CAMWOWEU4Realm6PvP"` → `Kas Pitas` (el reino va aparte a `r.realm`) | como la 1.2.2 |
| Unidad: `UnitNameUnmodified`/`UnitName(u)` | `ns.idFromUnit(u)` = `ns.id(UnitNameUnmodified(u))` | `("Kas","Pitas")` → `Kas Pitas`; `("Kas Pitas","")` → `Kas Pitas`; `("Kas", nil)` (apellido aún sin caché, TRP3 #1482) → índice del roster o nil | `("Kas", nil)` → `Kas-MiReino`; `("Kas","Otro")` → `Kas-Otro` |
| Nombre tecleado (invitar, rlList, `/gsq trust reset`) | `ns.id(texto)` | quita espacios sobrantes; búsqueda en el roster sin distinguir mayúsculas (`kas pitas` → `Kas Pitas`); `"Kas-Pitas"` (separador de enlace, `C_NameUtil.ReplaceSurname…`) → `Kas Pitas` si existe en el roster; sin coincidencia → nil y error «no está en la hermandad» | como la 1.2.2 |
| Datos guardados de la 1.x | `ns.id(viejo)`, solo en la migración (§5) | `"Kas-R"` (sin espacio y con un reino conocido) → índice por (nombre de pila, reino): si es único, `Kas Pitas`; si no, nil. `"Kas Pitas-R"` (restos de la 1.2.0) → `Kas Pitas` | sin cambio |

Reglas:
- (a) No es string, está vacío o `issecretvalue` → nil.
- (b) Es idempotente: `ns.id(ns.id(x)) == ns.id(x)`.
- (c) Nunca lanza un error.
- (d) Las separaciones se hacen con `string.find(…, 1, true)`, nunca con `%s` ni `%w`, que dependen del locale y de UTF-8.
- (e) La comparación sin mayúsculas solo vale para ASCII (`string.lower`). Para los nombres con tildes manda el roster exacto.
- (f) En modo forever, para distinguir «X-Y» como reino o como apellido, Y cuenta como reino si es `myRealm` o aparece como reino en el roster; si no, es un apellido.

### 2.4 La API que exporta A (contrato congelado para B y C)
- `ns.ID_MODE`, `ns.id(a, b)`, `ns.idFromUnit(unit)`
- `ns.me()`: `ns.idFromUnit("player")`, cacheado en cuanto deja de ser nil.
- `ns.isSelf(x)`: `ns.id(x) == ns.me()`.
- `ns.roster(x)`: `rosterCache[ns.id(x)]`. La entrada añade `r.realm` y `r.raw`.
- `ns.rosterIndex()`: `{ byFirst = {lower(nombre)={ids}}, byFirstRealm = {lower(nombre).."-"..reino={ids}}, byLower = {lower(id)=id}, realms = {reino=true} }`.
- `ns.whisperTarget(id, alt)`: ver §6.
- `ns.displayName(id)` y `ns.shortName(id)`: en forever los dos devuelven `id`; en realm, como la 1.2.2.
- Alias **temporales** `ns.fullName = ns.id` y `ns.charKey = function(n) return ns.id(n), surnameOf(n) end`, para que B y C se puedan fusionar en cualquier orden. Al final de C, `git grep -nE 'ns\.(fullName|charKey)\(' -- '*.lua' ':!tests/*'` = 0, y las definiciones de los alias se borran.
- `M.charName` y `M.whisperTarget` (Core/Model.lua:796 y :819) se quedan como envoltorios de `Core/Identity.lua` para el modo realm.

---

## 3. Inventario (fichero:línea @5e4a845) y cambio de cada sitio

Grep que lo genera (volver a pasarlo tras rebasar):
`git grep -nE 'UnitName|UnitFullName|GetGuildRosterInfo|GetRaidRosterInfo|fullName|charKey|charName|shortName|displayName|myRealm|whisperTarget|ns\.me\(|isSelf|IsSelf|"-" *\.\.|\[\^-\]|%-\(\.[*+]\)|sender|InviteUnit|UnitInRaid' -- '*.lua' ':!tests/*' ':!Core/Ed25519.lua' ':!Locales/*'`

Leyenda: **T** = tarea dueña (§10). «→ id» = pasar por `ns.id`/`ns.idFromUnit`. Los cientos de comparaciones `x == ns.me()` / `x ~= ns.me()` (GuildSquads.lua, Sync.lua, Hall.lua, Progress.lua y UI/*) **no cambian**: comparan identidades que ya vienen canónicas. Se listan por fichero al final de la tabla.

| # | Sitio | Hoy | Cambio | T |
|---|---|---|---|---|
| 1 | GuildSquads.lua:31-35 `myRealm()` | `GetNormalizedRealmName()` | se queda; solo lo usan el modo realm y el diag | A |
| 2 | GuildSquads.lua:42-47 `ns.fullName` | espacio → `M.charName` («Nombre-Reino») | alias de `ns.id` (§2.4) | A |
| 3 | GuildSquads.lua:49-51 `ns.me` | `ns.fullName(UnitName("player"))` (solo el 1.er valor) | `ns.idFromUnit("player")` cacheado | A |
| 4 | GuildSquads.lua:54 `ns.isSelf` | por fullName | `ns.id(x) == ns.me()` | A |
| 5 | GuildSquads.lua:58-61 `ns.charKey` | `M.charName` → (clave, apellido) | alias temporal | A |
| 6 | GuildSquads.lua:63 `ns.shortName` | quita «-…» | forever: `id`; realm: igual | A |
| 7 | GuildSquads.lua:69-74 `ns.whisperTarget` | roster → `M.whisperTarget(key, surname, myRealm, alt)` | §6: forever = `id`, sin variante alternativa | A |
| 8 | GuildSquads.lua:113-115 `ns.roster` | `rosterCache[fullName]` | `rosterCache[ns.id(x)]` | A |
| 9 | GuildSquads.lua:119-123 `ns.displayName` | pila + `r.surname` | forever: `id` | A |
| 10 | GuildSquads.lua:137-151 `ns.RosterDiag` | `key:match("%-(.*)$")` para contar reinos | forever: reinos desde `r.realm`; añade `mode=` | A |
| 11 | GuildSquads.lua:173 `M.guildDB(…, inGuild)` | `rosterCache[ns.fullName(n)]` | `ns.roster(n) ~= nil` | A |
| 12 | GuildSquads.lua:177-178 `M.sweepSurnames(g)` | barre los restos de la 1.2.0 | se sustituye por `M.migrateIdentity` (§5) | B |
| 13 | GuildSquads.lua:241-256 escaneo del roster | `ns.charKey(name)` → `cache[key] = {…, surname}` | `id = ns.id(name)`; guarda `realm`, `raw` y `surname`; construye `rosterIndex` | A |
| 14 | GuildSquads.lua:446 id de squad | `me .. ":" .. serverTime()` | sin cambio (opaca); las nuevas llevan «Kas Pitas:ts» | — |
| 15 | GuildSquads.lua:469, 478, 506, 512, 532 retroalimentación | `ns.shortName(name)` | sin cambio de código (shortName ya da `id`); test de los textos | C |
| 16 | GuildSquads.lua:494, 527 nombre tecleado (invitar o rechazar) | `ns.charKey(name)` | `ns.id(name)`; nil → error `notInGuild` | C |
| 17 | GuildSquads.lua:608-614 convocatoria recibida | `ns.fullName(sender)` | `ns.id(sender)` | C |
| 18 | GuildSquads.lua:690-760 `ownKeys[ns.me()]` | clave propia por «Nombre-Reino» | por `id`; la vieja se borra en la migración (§5) | B |
| 19 | GuildSquads.lua:840 análisis de `/gsq trust <sub> <who>` | `^%S+%s+(%S+)%s*(%S*)`: **corta «Kas Pitas» en «Kas»** | `who` = el resto de la línea (`^%S+%s+%S+%s+(.-)%s*$`) | C |
| 20 | GuildSquads.lua:848 `/gsq trust reset` | `ns.fullName(who)` | `ns.id(who)` | C |
| 21 | GuildSquads.lua:865 import | `sender = ns.me()` | sin cambio | — |
| 22 | Core/Model.lua:12 `M.PROTO = 2` | | `3` | B |
| 23 | Core/Model.lua:21-35 SCHEMA: `captain` 48, `members`/`bench` L…48, `xferFrom` 48 | 48 bytes | **64** (12+1+12 caracteres de 2 bytes = 49) | B |
| 24 | Core/Roster.lua:375-380 (`main`, `bench`, `owner`, `name`, `names` 48); Core/Progress.lua:33-35 (`who`, `pres` 48); Core/Races.lua:77-81 (`who`, `by`, `pres` 48, `key` 48); Core/Catalog.lua:33 (`who` 48) | 48 | 64 en los campos que llevan nombre de personaje (`key` de Races no es un nombre: sin cambio) | B |
| 25 | Core/Model.lua:519-523 `validShape` `#rec.a > 64` | 64 | sin cambio (cabe) | — |
| 26 | Core/Model.lua:791-813 `M.charName` | separa el apellido y añade «-Reino» | envoltorio de `I.id` en modo realm (§2.4) | A |
| 27 | Core/Model.lua:816-830 `M.whisperTarget` | `full .. "-" .. realm` si es de otro reino | solo para el modo realm | A |
| 28 | Core/Model.lua:832-846 `M.sweepSurnames` | | lo absorbe `M.migrateIdentity` | B |
| 29 | Comm.lua:12 `Comm.PROTO = 2` | | `3` | B |
| 30 | Comm.lua:160 `keyOf` | `ns.fullName` | `ns.id` | B |
| 31 | Comm.lua:173-177 `variant` y :203-221 `Comm.Failed` | main → alt → marcado | forever: no hay alt; el primer fallo marca (§6) | B |
| 32 | Comm.lua:223-249 `bareLower` / `Comm.MatchNotFound` | exacto, luego pila + reino, luego pila | forever: exacto (sin mayúsculas), y luego el mismo `id` quitando «-…». **Nunca solo por el nombre de pila** | B |
| 33 | Comm.lua:287-294 `Comm.ForMe(to)` | adivina por nombre de pila y reino | forever: `ns.id(to) == ns.me()` exacto | B |
| 34 | Comm.lua:304-330 `Comm.Send` WHISPER | `ns.whisperTarget(key, v=="alt")` | igual, con la variante de §6 | B |
| 35 | Comm.lua:390-397 `ChannelOk` | `ns.roster(sender)` | sin cambio de código (ns.roster ya usa ns.id) | — |
| 36 | Comm.lua:417 `ns.isSelf(sender)` | | sin cambio de código | — |
| 37 | Comm.lua:424-431 control de PROTO, `oldPeers[sender]` | clave = sender crudo | `oldPeers[ns.id(sender) or sender]`; §4.3 | B |
| 38 | Comm.lua:435-442 sobre «W» | `Comm.ForMe(payload.to)` | `to` = identidad (§6) | B |
| 39 | Sync.lua:63 / :1166 `heard[fullName(sender)]` | | `ns.id(sender)`; nil → no se apunta | B |
| 40 | Sync.lua:86-93 `PeerDiag` (notInRoster) | | sin cambio de código | — |
| 41 | Sync.lua:1036, :1104 `from = ns.fullName(sender)` | | `ns.id(sender)`; nil → se descarta y se cuenta (`bad`) | B |
| 42 | Sync.lua:1043 `hearOwner(from, payload.pk)` (TOFU) | | se fija la clave a la identidad nueva | B |
| 43 | Sync.lua:281, :547, :557, :627 (autor == from, emisor del certificado `c.i == from`) | | sin cambio de código (las dos partes ya son id) | — |
| 44 | Core/Sig.lua:21-22 `G.TAG="GSQ-MAN1"`, `G.STMT_TAG="GSQ-MAN2"` | | `GSQ-MAN3` / `GSQ-MAN4` (§4.2) | B |
| 45 | Core/Cert.lua:21 `C.TAG="GSQ-CRT1"` (y :52 `hash(name‖pk)`, :62 `statement` con `c.i`) | | `GSQ-CRT2`; `name` = id | B |
| 46 | Core/Trust.lua:29 `T.ROT_TAG="GSQ-ROT1"` (:267 `rotationMsg(name, pk)`) | | `GSQ-ROT2` | B |
| 47 | Hall.lua:163-170 testigos del raid `GetRaidRosterInfo` → `ns.charKey(name)` | | `ns.id(name)` | C |
| 48 | **Hall.lua:171-176** grupo `UnitName("party"..i)` → `name.."-"..realm` | en Forever da «Kas-Pitas» | `ns.idFromUnit("party"..i)` (se queda la guarda `issecretvalue`) | C |
| 49 | Hall.lua:381 y **Progress.lua:361** `UnitName("player")` → Overlord | | sin cambio (fuera de alcance); marca `-- id-ok` para el gate | C |
| 50 | Hall.lua:415, :453, :574 `from = ns.fullName(sender)` | | `ns.id(sender)` | C |
| 51 | Hall.lua:529, :633 `ns.shortName(…)` (lista de versiones, entrada) | | sin cambio de código (da `id`) | C |
| 52 | Progress.lua:209-213 testigos del raid → `ns.charKey(name)` | | `ns.id(name)` | C |
| 53 | **Progress.lua:215-221** grupo `name.."-"..realm` | en Forever da «Kas-Pitas» | `ns.idFromUnit("party"..i)` | C |
| 54 | Progress.lua:355 `ns.me() .. ":" .. src` (estado local del contador) | | sin cambio (la migración re-clavea `hkState`, §5) | B |
| 55 | Progress.lua:387, :463, :521, :540, :570 `ns.fullName(sender)` | | `ns.id(sender)` | C |
| 56 | Raids.lua:203 `short(n)` (`^([^-]+)`) | | forever: devuelve `n` tal cual | C |
| 57 | **Raids.lua:216-218** `api.invite(n)` ← Core/Roster.lua:798 `call(api.invite, n)` con n = clave | `InviteUnit("Kas-Reino")`, que en Forever falla como el susurro | `inviteFn(ns.whisperTarget(n))`; nil → no se invita y cuenta como `noTarget` | C |
| 58 | Raids.lua:225-227 `api.inGroup(n)` | `UnitInRaid(short(n))` | primero `UnitInRaid(n)` con el id y después `short(n)` | C |
| 59 | Raids.lua:236-237 roster del raid → `ns.charKey(name)` | | `ns.id(name)` | C |
| 60 | Raids.lua:13 `me()` | | sin cambio | — |
| 61 | Core/Roster.lua:846 `short` en la exportación a Discord | `^([^-]+)` | forever: el id «Nombre Apellido» (es como se llama en el juego) | C |
| 62 | Diag.lua:151 `ns.isSelf(sender)` | | sin cambio de código | — |
| 63 | Core/Diag.lua:18, :25 lista de APIs sondeadas | | añadir `RegionalUniqueNamesEnabled`, `UnitNameUnmodified` y `UnitFullName` | C |
| 64 | UI/Panels.lua:24-25, 29, 33, 110, 134, 139-143, 199, 335, 505, 708, 723, 1579 `ns.shortName`/`ns.displayName` | | sin cambio de código (ya da `id`). Comprobar anchos (§7) | C |
| 65 | UI/Panels.lua:1332 `rlList` tecleado `(ns.charKey or ns.fullName)(n)` | | `ns.id(n)` | C |
| 66 | UI/Catalog.lua:214-216 nombre tecleado `(ns.charKey or ns.fullName)(…)` | | `ns.id(…)` | C |
| 67 | UI/Catalog.lua:230, :319; UI/Hall.lua:128, :131, :163, :294; UI/Raids.lua:28 `short` | | sin cambio de código; test de que se ven distintos (§7) | C |
| 68 | UI/Main.lua:344 `me = ns.me() or "?"` | | sin cambio | — |
| 69 | UI/Ranking.lua:122 `M.displayName(state, sid)` | es el nombre del **squad**, no del personaje | sin cambio | — |
| 70 | tests/gates.js | | regla nueva (§8, AC9) | C |

Comparaciones con `ns.me()` que no cambian (§3, comparan ids): GuildSquads.lua:128, 149, 313, 328, 359, 389, 398, 411, 418, 421, 425, 443, 476, 518, 552, 592, 626, 636, 650, 705-706, 739, 755. Sync.lua:73, 104, 195, 220, 343, 402, 415, 460, 505, 914, 1029, 1043, 1068, 1072, 1181. Hall.lua:120, 134, 142, 163, 197, 225, 333, 342, 376-377, 472, 474, 504, 517, 533, 550, 554, 558, 560, 590, 639, 738, 745, 756, 765, 777. Progress.lua:150, 202, 246, 293, 332-333, 343, 365, 421, 440, 458, 465, 468. UI/Panels.lua:87, 137, 197, 253, 277, 316, 328, 337, 345, 406, 423, 579-590, 623, 636, 665, 727, 839, 853, 889, 1014, 1029, 1066-1067, 1464, 1629. UI/Raids.lua:45, 92, 484. UI/Hall.lua:17, 344. UI/Catalog.lua:17. UI/Ranking.lua:205, 209. UI/Main.lua:316.

---

## 4. Protocolo: PROTO 3

### 4.1 Por qué hace falta
Lo firmado lleva el nombre: el autor del registro `rec.a` dentro de `G.recHash` (Core/Sig.lua:41-42); el autor del manifiesto `m.a` (Sig.lua:54-58, :99); el emisor del certificado `c.i` y cada entrada `hash12(nombre‖clave)` (Cert.lua:52-62); la rotación `ROT_TAG|nombre|pk` (Trust.lua:267); y las ids y los campos con nombres (perfil id = autor, `captain`, `members`, `rejectId(sid, name, kind)`, `xferTo "sid>Capitán"`, listas `main`/`bench`/`names`/`pres`, `who`/`by`). Un 1.2.x que lea «Kas Pitas» lo pasa por su `M.charName` y lo convierte en «Kas-Reino», así que no verifica nada y mezcla identidades. Por eso hacen falta dos redes separadas.

### 4.2 Qué se firma ahora
- **Formato:** el mismo que en la 1.2.2. Solo cambia el valor de los nombres, que pasa a ser la identidad de §2. Los topes de nombre de personaje pasan de 48 a 64 bytes (§3 #23-24).
- **Etiquetas de dominio nuevas:** `G.TAG = "GSQ-MAN3"`, `G.STMT_TAG = "GSQ-MAN4"`, `C.TAG = "GSQ-CRT2"` y `T.ROT_TAG = "GSQ-ROT2"`. Así una firma de la 1.x **nunca** verifica en la 2.0, aunque coincidan el nombre y la clave (por ejemplo en modo realm). `GSQ-SEED1` (la entropía de la semilla) no cambia.
- `Comm.PROTO = 3` y `M.PROTO = 3`. El `p2 = 2` del hello (Core/P2P.lua:21 `X.PROTO`) se queda como está: es el nivel de la función P2P, no la versión del cable.
- La clave propia es **nueva** para la identidad nueva: `ownKeys[id]` se genera con `T.ensureOwn`, que ya existe. Razón: «claves viejas fuera», y no queda ninguna clave asociada a dos identidades.

### 4.3 Rechazo de la 1.x y avisos
- **La 2.0 al recibir `v = 2` (o 1):** lo descarta (como hoy, Comm.lua:424) y lo apunta en `oldPeers[ns.id(sender)]`. Una vez por sesión escribe en el chat local `L.OLD_PEERS` con texto nuevo: «Guild Squads: %d miembros usan una versión anterior a la 2.0 y no se sincronizan contigo hasta que actualicen». `/gsq diag`: `proto v=3 old=N`.
- **La 1.x al recibir `v = 3`:** lo descarta (`data.v ~= 2`, cuenta `badProto`) sin errores de Lua. No se avisa al usuario, salvo con **D2**.
- **D2 (decisión de BRO):** si la 1.2.2 todavía no se ha publicado, se le añade `v > Comm.PROTO` → una línea local por sesión: «Hay una versión nueva de Guild Squads (2.0) en tu hermandad: actualiza para seguir sincronizando». Son unas 8 líneas más un test, unos 20 minutos.
- En un hello de la 2.0 no se acepta nada que venga de un 1.x, y viceversa (lo verifica AC6).

---

## 5. Migración de SavedVariables (`M.migrateIdentity`, sustituye a `M.sweepSurnames`)

Solo hay migración en modo **forever**; en modo realm no se hace nada. Va en dos pasos con marca. Cada paso es idempotente aunque se pierda la marca: solo toca nombres en forma vieja, es decir, con «-» en modo forever. También se ejecuta en modo `dry` para `/gsq diag`.

**Paso 1, partición de guild** (`g.idv ~= 2`; se ejecuta en `selectGuild` cuando el roster ya está listo, porque lo necesita para remapear):
1. Fuera todo lo que va por nombre viejo y por clave: `g.trust` (`keys`, `pend`, `contested`, `suspects`, `alerts`), `g.sig.man`, `g.cert.crt`, las rotaciones pendientes y `prevOwnKeys`. Todo eso se vuelve a aprender en persona con PROTO 3.
2. Registros firmados de **otros** (`rec.a` no es de esta cuenta, es decir, no está en las claves de `GuildSquadsDB.ownKeys`): **se descartan** (recomendado, **D1**). Vuelven cuando su autor actualiza a la 2.0 y vuelve a firmar.
3. Registros de **personajes de esta cuenta** (`rec.a` ∈ `ownKeys`, que incluye los alts): se remapea `a` con `ns.id(a)`, como en los datos guardados de §2.3. Si da nil (es ambiguo o no está en el roster), se descartan. Se marcan `rec.resign = true` (local: nunca se envía ni se reenvía mientras lo tenga).
4. Nombres de otros dentro de datos locales sin firmar: eventos de Progress (`who`, `pres`), observaciones de Races (`who`, `by`, `pres`), Hall (`hkBase`, `pend`) y `hkState` (`<id>:src`). Se remapean si `ns.id` es inequívoco con el roster; si no, se quitan de la lista (o se borra la entrada si el nombre es la clave).
5. `g.idv = 2`, `g.idMigratedAt = ts` y el contador `swept=` del diag.

**Paso 2, personaje** (`GuildSquadsDB.idv[ns.me()] ~= 2`; se ejecuta en cada login, después del paso 1):
1. `ownKeys[viejo]` → se borra. Se genera `ownKeys[ns.me()]`.
2. Mis registros con `resign` o con `a` vieja: se pone `a = ns.me()`. Las ids que son mi nombre (perfil y presencia) se re-clavean con mi id. Los nombres de dentro (`captain`, `members`, `bench`, `rejectId`, `xferTo`, listas de rosters y asistencia) se remapean con la regla del paso 1.4; si un miembro es ambiguo, sale de la lista. Se sube `sq` (y `ts = now`) para que mi versión gane a cualquier copia. Se quita `resign`. Se firma un manifiesto nuevo `n = 1` con la clave nueva y se publica en el hello siguiente.
3. `GuildSquadsDB.idv[ns.me()] = 2`.

**Idempotencia (AC5):** ejecutar los dos pasos 2 veces seguidas deja `S.encode(GuildSquadsDB)` idéntico byte a byte a ejecutarlos 1 vez. Si se ejecutan sin las marcas, el resultado es el mismo.

---

## 6. Destino de WHISPER y red de seguridad de la 1.2.2

- **Forever:** `ns.whisperTarget(id)` = `id` («Kas Pitas»), **sin «-Reino» nunca**, también hacia reinos conectados. No hay variante alternativa (`alt` → nil). Solo se susurra a quien está en el roster **y** online o se ha oído hace ≤ `HEARD_FRESH` s (regla de la 1.2.2, Comm.lua:179-184). Fuera del roster → sobre GUILD «W» con `to = id`.
- **Se mantiene de la 1.2.2:**
  - `Comm.SystemFilter`: oculta `ERR_CHAT_PLAYER_NOT_FOUND_S` de un nombre susurrado en los últimos 5 s.
  - `TargetOffline (12)` cuenta como no encontrado.
  - Un fallo marca al destinatario 10 min, y mientras tanto sus mensajes van por GUILD «W» con destinatario.
  - Después del marcado se manda un susurro de sonda.
  - En el diag, `whisper notFound= marked= routed= dropped= notForMe=`.
- **Cambia en forever:** al no haber variante, el primer «no encontrado» marca directamente. `MatchNotFound` es exacto (sin mayúsculas) o «id sin -…», y nunca solo por el nombre de pila. `ForMe` es `ns.id(to) == ns.me()` exacto, sin adivinar el reino.
- **Realm:** el comportamiento de la 1.2.2 entero (main/alt con o sin sufijo).
- `InviteUnit` usa el mismo destino que el susurro (§3 #57).

---

## 7. UI: lo que se muestra con apellido

En modo forever, **cada vez que aparece un personaje se muestra «Nombre Apellido»** (`ns.displayName(id)` = `shortName(id)` = `id`):
- listas de miembros y banquillo, capitán, sugerencias y peticiones o invitaciones (UI/Panels.lua);
- tooltips y menús de miembro, con los diálogos de confirmar capitán, banquillo y expulsión (Panels.lua:134-143);
- mensajes de retroalimentación y convocatorias (GuildSquads.lua:469-614);
- el Salón: entradas, `chars`, `sup`, historial y la lista de versiones (UI/Hall.lua:128-294, Hall.lua:529);
- el catálogo, con la concesión y la retirada (UI/Catalog.lua:216-319);
- las celdas del raid (UI/Raids.lua:28) y la exportación a Discord (Core/Roster.lua:846);
- los tooltips de «sin verificar» y «disputada» (Panels.lua:24-25);
- `/gsq diag` (`me=Kas Pitas`).

Nunca se muestra «-Reino» (en Forever el reino no es identidad). Si no cabe en la celda, se trunca visualmente con el ancho del FontString, sin acortar el texto: nada de «Kas P.», que vuelve a colisionar. Los textos nuevos o cambiados van en esES y enUS (OLD_PEERS, error «no está en la hermandad» con nombre completo, ayuda de `/gsq trust reset <Nombre Apellido>`).

---

## 8. Criterios de aceptación (cada uno con su prueba; semilla `--seed 7303` salvo que se diga otra)

- [ ] **AC1 — `ns.id` (unidad, `tests/identity_spec.lua`, nuevo):** tabla de ≥ 35 casos en los dos modos. Incluye: «Kas Pitas-CAMWOWEU4Realm6PvP» → «Kas Pitas»; `("Kas","Pitas")` y `("Kas Pitas","")` → «Kas Pitas»; `("Kas",nil)` con un Kas en el roster → «Kas Pitas» y con dos → nil; «kas pitas» y «Kas-Pitas» tecleados → «Kas Pitas»; «Kas-RealmA» guardado → por el índice; un nombre cirílico de 49 bytes vuelve igual; secretos y valores que no son string → nil; idempotencia en todos los casos; modo realm igual que la 1.2.2 (los casos del `surnames_spec` de la 1.2.1 pasados al modo realm). **Rojo en 5e4a845** (no existe `ns.id`) y verde en 2.0.
- [ ] **AC2 — WoW falso en modo Forever (S20, nuevo):** `Sim({forever:true})`:
  - roster «N A-R»; `UnitName`/`UnitNameUnmodified("player"|"partyN")` → `(N, A)`; `UnitFullName` en las dos formas (alternando por cliente); `RegionalUniqueNamesEnabled()` → true; sender «N A» sin reino desde cualquier reino.
  - El servidor falso entrega un WHISPER **solo** a «N A» exacto de un cliente online; cualquier otra cosa da la línea «No hay ningún jugador con el nombre X.».
  - **Autoprueba del falso** (para que el verde no sea vacío): un susurro a «N», otro a «N-R» y otro a «N A-R» no se entregan y dan 3 errores; uno a «N A» sí se entrega.
  - 5 clientes 2.0 convergen en ≤ 600 s: 100 % de registros verificados en todos y certificados de los otros 4.
  - `badWhisper = 0`, susurros con «-» = 0 y `SIM_SYSSHOWN = 0`.
- [ ] **AC3 — dos «Kas» (S21, nuevo, y unidad):** en el mismo reino, «Kas Pitas-R» y «Kas Mora-R», los dos con la 2.0, más 3 clientes. Al final:
  - 2 perfiles y 2 claves distintas en todos los clientes (`trust.keys` tiene «Kas Pitas» y «Kas Mora»);
  - Kas Pitas crea un squad y Kas Mora no figura como capitán ni como miembro;
  - el registro de entregas del simulador muestra que **ningún** susurro para Kas Pitas llega a Kas Mora;
  - la UI de los dos muestra «Kas Pitas» y «Kas Mora» (texto de la lista, en unidad).
  - El mismo escenario con la 1.2.2 (`GSQ_REF`) sale **rojo**: las dos claves chocan en «Kas-R».
- [ ] **AC4 — reinos conectados (S22, nuevo):** guild en RealmB, miembros en RealmA y RealmB, con un «Mb2» en cada reino y distinto apellido. Converge en ≤ 600 s, susurros con «-» = 0, `peerCount` correcto en cada uno y el diag muestra `realms=RealmA:n,RealmB:m`. S19 [connected realms] sigue en verde.
- [ ] **AC5 — migración desde la 1.2.2 (`tests/migration_spec.lua` y S23):**
  - Fixture `tests/fixtures/sv-1.2.2.lua`, generado con `tests/tools/make-sv-122.js` ejecutando la 1.2.2 en el simulador y guardado en el repo. Contiene 2 personajes de la misma cuenta, uno de ellos un alt; registros propios y ajenos; dos «Kas» en el mismo reino; y restos «N A-R» de la 1.2.0.
  - Tras cargar la 2.0:
    - (a) 0 claves con «-» en trust, sig y cert;
    - (b) mis registros con `a = «Kas Pitas»` y un manifiesto `n = 1` que **verifica un cliente nuevo**;
    - (c) los registros del alt se quedan en `resign` hasta que el alt entra, y entonces se re-firman;
    - (d) los dos «Kas» ambiguos se descartan y uno inequívoco se remapea;
    - (e) las firmas ajenas se descartan (con D1 = descartar);
    - (f) idempotencia byte a byte (§5);
    - (g) 0 errores de Lua.
  - S23: 3 clientes que arrancan con la fixture se verifican entre ellos en ≤ 600 s.
- [ ] **AC6 — PROTO 3 (`tests/proto3_spec.lua` y S17v2 mixto):**
  - Unidad: `Comm.PROTO == 3`. Un mensaje `v = 2` se descarta, cuenta en `oldPeers` por id y saca `OLD_PEERS` una sola vez. Un manifiesto, un certificado o una rotación firmados con las etiquetas de la 1.2.2 (mismo nombre y misma clave) **no verifican**.
  - Simulador, con 4 de la 2.0 y 2 de la 1.2.2 (`GSQ_REF=<sha 1.2.2>`): 0 errores de Lua en los 6; ningún registro de autor 1.2.2 en el estado de un 2.0, ni al revés; los 2.0 ven `old=2`.
- [ ] **AC7 — batería en modo forever (el valor por defecto del simulador pasa a `forever:true`):** S19 (las 2 variantes), S2, S8 (`--s8min 1`, partes ≤ 5601, cola ≤ 500 y 0 throttle), S11 y S15 (verificados ≥ 26/50 y ≥ 38/50, 0 claves falsas), S16 y S16b en **PASS**. S1-S7 y S9 ×3 también siguen en verde (matriz de la CI).
- [ ] **AC8 — 0 líneas «No hay ningún jugador»:** `tests/sim/run.js` imprime al final `SYSSHOWN total=0` sumando todos los escenarios ejecutados. Si no es 0, el run falla.
- [ ] **AC9 — gate:** `tests/gates.js` falla si aparece `UnitName(`, `UnitNameUnmodified(` o `UnitFullName(` fuera de `Core/Identity.lua` y `GuildSquads.lua` (identidad) sin la marca `-- id-ok`. `gates-selftest.js` comprueba que detecta un `UnitName("party1")` metido en Hall.lua. Al final, `git grep -nE 'ns\.(fullName|charKey)\(|charName\(' -- '*.lua' ':!tests/*'` da 0 resultados.
- [ ] **AC10 — periferia (`tests/periphery_spec.lua`):**
  - `UnitName("party1")` → `("Kas","Pitas")` da «Kas Pitas» en los testigos de Hall y de Progress. **Rojo en 5e4a845**, que da «Kas-Pitas».
  - El `InviteUnit` falso recibe «Kas Pitas», nunca un nombre con «-».
  - `/gsq trust reset Kas Pitas` olvida a «Kas Pitas».
  - El `rlList` tecleado y la concesión del catálogo usan «Kas Pitas».
- [ ] **AC11 — UI:** en unidad, todos los textos de §7 muestran «Kas Pitas» y «Kas Mora» distintos. `ui_layout_spec` con un nombre de 25 caracteres no se desborda. **Señal externa:** captura de BRO del panel de squad y del Salón con un nombre con apellido (es un objetivo abierto).
- [ ] **AC12 — CI y documentación:**
  - CI en verde en la rama de integración con los jobs actuales, más el grupo nuevo `S20 S21 S22 S23 --seed 7303`.
  - `wow-secret-lint@1.10.2` con 0/0, `check-links` OK y `gates-selftest` OK.
  - CHANGELOG `## 2.0.0` en ES y EN (rompe con la 1.x), CONTRIBUTING «WoW Forever names» reescrito y guía del GM actualizada.
  - Commits **sin atribución**: `git log --format=%B feat/2.0 | grep -ciE 'co-authored|claude'` = 0.
- [ ] **AC13 — en el juego (BRO, antes de publicar):**
  - `/dump RegionalUniqueNamesEnabled(), UnitNameUnmodified("player")`.
  - Con 2 personajes con la 2.0 (de dos reinos, si se puede), `/gsq diag` en los dos: `id mode=forever me=<Nombre Apellido>`, `whisper notFound=0`, los dos verificados en ≤ 10 min y 0 líneas «No hay ningún jugador» en el chat.

---

## 9. Riesgos y suposiciones
1. **El formato del sender lo midieron otros, no nosotros** (y contradice nuestra nota de la 1.2.1). Mitigación: `ns.id` resuelve un sender sin apellido por el roster si es inequívoco, y `peers notInRoster=` lo enseña. AC13 lo confirma.
2. **El susurro «Nombre Apellido» hacia otro reino conectado** es un indicio fuerte, sin medir. La red de la 1.2.2 (ocultar el error y mandar por GUILD «W») hace que no se pierda nada ni salga spam.
3. **`RegionalUniqueNamesEnabled()`**: si da false o no existe a la hora de evaluarlo, la 2.0 trabaja en modo realm, que es la 1.2.2 con PROTO 3. Se ve en `diag mode=`. Por eso el modo se reevalúa en PLAYER_LOGIN.
4. **Apellido aún sin caché para una unidad** (TRP3 #1482): `ns.idFromUnit` da nil o tira del roster. Quien llama lo salta y no hay ningún error.
5. **Transición en dos redes:** hasta que la guild actualiza, los de la 2.0 no ven lo de los de la 1.x y viceversa. Con D1 = descartar, un 2.0 ve menos perfiles y squads hasta que sus autores actualizan. El aviso OLD_PEERS lo explica.
6. **Límites de longitud del apellido** sin documentar: el tope de 64 bytes cubre 12+1+12 caracteres de 2 bytes. Se prueba con 49 bytes.
7. **Mayúsculas y minúsculas en UTF-8:** `string.lower` solo vale para ASCII. Un nombre tecleado con tildes en otra caja no casa, y el error es claro. El roster manda.
8. **Base movediza:** la 1.2.2 tiene cambios sin commitear justo en Comm.lua, Model.lua, GuildSquads.lua y sim.js. **Si los agentes arrancan antes del commit final de la 1.2.2, habrá conflictos seguros.** Regla: A, B y C salen del commit final de la 1.2.2.
9. **La refactorización del simulador** (hoy los clientes van por nombre de pila: `this.clients[name]` y `roster.find(m => m.name === first)` en sim.js:282-313) es el cambio más grande y puede desestabilizar todos los escenarios. Mitigación: A deja `forever:false` en verde **antes** de cambiar el valor por defecto.
10. **`InviteUnit("Nombre Apellido")` hacia otro reino**: sin medir (se comprueba en AC13 si BRO invita).
11. **Migración de los alts de la cuenta**: es lo más delicado de B y tiene su propio caso en AC5(c).
12. **Tiempo de CI y del contenedor:** S11, S15, S16 y S16b no están en la matriz, y los largos van detached (en Gilfoyle o con `nohup`). No se espera nada en bloqueo.

---

## 10. Reparto en tareas paralelas (agentes nuevos, worktrees distintos, commits sin atribución)

**Rama de integración:** `feat/2.0` desde el commit final de la 1.2.2. Cada tarea tiene rama y worktree propios: `wt/b-20a`, `wt/b-20b` y `wt/b-20c`. **Orden de fusión: A → B → C**, con rebase de cada una sobre la anterior. Después, la CI completa y D.

### A — Núcleo de identidad, WoW falso en modo Forever y tests (`feat/2.0-id`)
- **Ficheros:** `Core/Identity.lua` (nuevo, puro), `GuildSquads.toc` (+1 línea), GuildSquads.lua:25-151 y :233-262, Core/Model.lua:791-830, `tests/identity_spec.lua` (nuevo), `tests/surnames_spec.lua` (pasado a modo realm), `tests/sim/fakewow.lua`, `tests/sim/sim.js` (los clientes pasan a ir por identidad completa y se añaden `forever`, `UnitFullName` en 2 formas, `GetRaidRosterInfo` con «N A-R» y el registro de entregas), `tests/sim/scenarios.js` (S20, S21, S22 y la autoprueba del falso), `tests/sim/run.js` (`SYSSHOWN total`), `.github/workflows/ci.yml` (grupo S20-S23) y CONTRIBUTING.
- **Entrega primero, en ≤ 1 h, y la sube:** el commit «contrato», con `Core/Identity.lua`, los envoltorios `ns.*` y los alias de §2.4, más `identity_spec` en verde. B y C rebasan sobre ese commit en cuanto existe.
- **Criterios:** AC1, AC2, AC3, AC4 y el cambio de valor por defecto de AC7.

### B — PROTO 3, firmas y migración (`feat/2.0-proto`)
- **Ficheros:** Comm.lua (§3 #29-38), Core/Sig.lua:21-22, Core/Cert.lua:21, Core/Trust.lua:29, Core/Model.lua:12 y :21-35 (topes), :832-846 → `M.migrateIdentity`, Core/Roster.lua:375-380, Core/Progress.lua:33-35, Core/Races.lua:77-81, Core/Catalog.lua:33 (topes), Sync.lua:63, :1036, :1104 y :1166, GuildSquads.lua:168-200 (llamada a la migración) y :686-760 (ownKeys), Locales (solo el bloque OLD_PEERS y proto), `tests/proto3_spec.lua`, `tests/migration_spec.lua`, `tests/fixtures/sv-1.2.2.lua`, `tests/tools/make-sv-122.js`, `tests/whisper_spec.lua` (pasado a forever), los specs de sig, cert y keys_wire (etiquetas) y `tests/sim/scenarios_b.js` (S23 y S17v2; A lo engancha en `scenarios.js` con 1 línea).
- **Usa de A:** `ns.id`, `ns.me`, `ns.rosterIndex` y `ns.whisperTarget` (el contrato).
- **Criterios:** AC5 y AC6, y en AC7 la parte de las firmas (S16, S16b, S11 y S15).

### C — UI y sitios periféricos (`feat/2.0-ui`)
- **Ficheros:** Hall.lua (§3 #47-51), Progress.lua (#52-55), Raids.lua (#56-59), Diag.lua, Core/Diag.lua:18 y :25, Core/Roster.lua:846, UI/Panels.lua:1332 (y la comprobación de anchos), UI/Catalog.lua:214, GuildSquads.lua:440-532, :600-616 y :836-850, Locales (bloque UI 2.0), `tests/gates.js` y `tests/tools/gates-selftest.js`, `tests/periphery_spec.lua` (nuevo) y los specs de UI para los dos Kas. Al final borra los alias `ns.fullName` y `ns.charKey`.
- **Usa de A:** el contrato.
- **Criterios:** AC9, AC10 y AC11.
- **Conflictos esperables:** GuildSquads.lua se lo reparten A (25-262), B (168-200 y 686-760) y C (440-850) por rangos disjuntos; el tramo 168-200 es de B y A no lo toca. En Locales cada uno usa su propio bloque.

### D — Revisor a ciegas (agente nuevo, nunca un fork, después de la fusión)
- **Recibe:** esta SPEC, el diff `1.2.2..feat/2.0` y los ids de la CI. **No recibe** los `resultado:` de A, B ni C.
- **Ejecuta:** unidad completa, gates y su autoprueba, la matriz y S11, S15, S16, S16b y S20-S23 (los largos, detached).
- **Audita con grep:** §3, que no quede ningún «-» en los destinos y que el gate tenga marcas falsas.
- **Revisión de seguridad:**
  - ¿Se puede asociar una clave a la identidad nueva de otro durante la migración o con un sobre «W» trucado?
  - ¿Pueden chocar «Kas-Pitas» (forma de enlace) y «Kas-Reino»?
  - ¿Hay replay entre las etiquetas 1.x y 2.0?
- **Entrega:** un veredicto PASS o FAIL por AC, con localizador (`fichero:línea`, run o log) y `leídos k/N enteros`. Máximo 3 bucles de arreglo; cada arreglo lo recomprueba otro agente distinto del que lo hace.

**Prueba en el juego (BRO):** AC13, después de D y antes del tag `v2.0.0`.

---

## Estimación honesta (horas de reloj, con A, B y C en paralelo)
| Fase | Horas |
|---|---|
| Cerrar la 1.2.2 (requisito; ya está en marcha) | 0,5-1 |
| A, B y C en paralelo (A: 5 h, por el simulador; B: 5 h, por la migración y la fixture; C: 3,5 h) | 5-6 |
| Integración A → B → C y CI completa (S9 ×3 15 min, S8) más S11, S15, S16 y S16b detached | 2 |
| D a ciegas | 1,5-2 |
| Bucle de arreglos (≤ 3) y CI otra vez | 1-2 |
| **Total hasta la prueba de BRO en el juego** | **≈ 10-13 h** (lo más probable, 11 h). Empezando a las 04:00, hacia las 15:00 de hoy (9-nov). Publicar tras su prueba: +0,5 h |

Lo que más puede alargarlo: la refactorización del simulador (A) y la migración de los alts (B), +2-3 h si fallan las primeras pasadas. Con D1 = (b) en lugar de descartar, +2 h.

## Decisiones para BRO
- **D1 — Datos firmados de otros que vienen de la 1.x:** (a) **descartarlos** en la migración; vuelven cuando sus autores actualizan (recomendado: es limpio y rápido). (b) Conservarlos en gris («pendiente de que X actualice») hasta que llegue su versión 2.0 (+2 h, y más casos que probar).
- **D2 — Aviso en la 1.2.2** (si aún no está publicada): «hay una versión nueva, actualiza» cuando oiga PROTO 3 (+20 min; recomendado sí).
- **D3 — Medición de 5 minutos en el juego** (`/dump`, sender y susurro entre reinos; `research-surnames.md` §Recomendación 5) durante el desarrollo. No bloquea el código, pero sí la publicación.
- Decidido por Anton, sin preguntar: la clave propia es nueva para la identidad nueva; el formato de los registros no cambia; la partición de guild «Guild-Reino» se queda igual.

## ⚡ Decisiones de BRO (9-nov 03:49: «OK 1 y 2, pero no puedo hacer la 3 hasta mañana por la noche. No obstante, dale caña y sácalo ASAP»)
- **D1 = descartar** las firmas ajenas de la 1.x.
- **D2 = sí**: va en la 1.2.2 (el aviso «actualiza a la 2.0» al oír PROTO 3).
- **D3 = no hay prueba previa de BRO en el juego:** la 2.0 se publica cuando todos los criterios de aceptación, la CI y el revisor a ciegas (D) estén en verde. Sin bajar ningún criterio para ir más rápido: si algo sale rojo, se arregla.
