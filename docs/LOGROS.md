# Guild Squads — Catálogo de logros y carreras ("Tops")

Qué reconoce el addon, cómo se confirma y cómo lo adapta el GM. Uso desde el juego: [GUIA-JUGADOR.md](GUIA-JUGADOR.md) (jugadores) y [GUIA-GM.md](GUIA-GM.md), sección *Logros* (GM).

## 1. Tres tipos de reconocimiento

| Tipo | Qué es | Cuánto dura | Ejemplo |
|---|---|---|---|
| **Carrera (Top N)** | Lista **ordenada por quién llegó antes**. Cuando se llena, se cierra para siempre. | Permanente: Salón de la fama | "Top 100 primeros en llegar al 60" |
| **Logro** | Insignia que se desbloquea al cumplir una condición, con fecha y progreso visible. | Permanente | "Squad al 60", "Ruta Forever" |
| **Ranking** | Puntos por categoría que se reinician en cada wipe y se suman por temporada. | Wipe / temporada | Ranking de Mazmorras |

Todo se cuenta **dentro de la guild**. Tamaños: **Top 100** en las carreras generales de nivel, **Top 3** en "contenido PvE completo" y **Top 10** en todo lo demás (el GM puede reducirlos, ver §8).

## 2. Carreras de nivel (por personaje)

| Id | Carrera | Tamaño | Hitos |
|---|---|---|---|
| `lvl.all.<H>` | Primeros personajes de la guild en llegar al nivel H | **Top 100** | H = 10, 20, 30, 40, 50, 60 |
| `lvl.class.<CLASE>.<H>` | Primeros de cada **clase** en llegar al nivel H | Top 10 | 9 clases × 6 hitos |
| `lvl.race.<RAZA>.<H>` | Primeros de cada **raza** en llegar al nivel H | Top 10 | razas de Forever × 6 hitos |

- Clases y razas se leen de `UnitClass`/`UnitRace` y del roster de la guild (`classFile`); una raza que no está en la lista conocida necesita al menos 2 informantes distintos para abrir su carrera.
- **Detección:** el propio jugador (`PLAYER_LEVEL_UP`) **y** cualquier miembro con el addon que vea en el roster de la guild que un compañero sube de nivel (`GUILD_ROSTER_UPDATE`). Así cuentan **también los personajes sin addon**, con la hora en que se vio el cambio.
- **Hora que vale:** *exacta* si la informa el propio jugador y la confirma el roster; *aprox.* si la ven ≥ 2 observadores del roster con 10 minutos de margen (o un GM/oficial). Empate exacto: orden alfabético del nombre completo.
- **No es retroactivo:** solo cuenta lo que ocurre con al menos un miembro de la guild usando el addon.

## 3. Carreras PvE

En mazmorras compite el **grupo** que mata al jefe; se apuntan los participantes y su squad. En bandas compite el **grupo de banda**.

| Id | Carrera | Tamaño | Condición |
|---|---|---|---|
| `dng.<MAZMORRA>` | Primeros grupos en **completar** cada mazmorra | Top 10 | matar al jefe final |
| `dng.<MAZMORRA>.<JEFE>` | Primeros en matar a **cada jefe** de mazmorra | Top 10 | `ENCOUNTER_END` con éxito |
| `dng.all` | Primeros **squads** en completar **las 9 mazmorras nuevas** de Forever | Top 10 | las 9 completadas con ≥ 3 miembros del mismo squad |
| `raid.<BANDA>` | Primeros grupos en completar cada banda | Top 10 | jefe final |
| `raid.<BANDA>.<JEFE>` | Primeros en matar a cada jefe de banda | Top 10 | `ENCOUNTER_END` con éxito |
| `raid.all` | Primeros en completar **todas las bandas abiertas** | Top 10 | Barrow Deeps, Hyjal Summit y Onyxia's Lair |
| `full.10` | **Contenido PvE completo de 10**: todas las mazmorras + las bandas de 10 | **Top 3** | alianza de squads, ver abajo |
| `full.20` | **Contenido PvE completo de 20**: todas las mazmorras + las bandas de 20 | **Top 3** | alianza de squads |

- **Testigos:** cada muerte de jefe necesita **≥ 2 informes** de clientes con el addon presentes, con 180 s de margen. Con un solo informe la muerte queda *pendiente* 24 h por si llega otro.
- **Mazmorras:** se acredita a **un solo squad**, el que tenga ≥ 3 miembros en el grupo. Si ninguno llega a 3, la entrada es *grupo mixto*: entra en el Top y no da logro de squad.
- **Alianza de squads** (`raid.all`, `full.*`): en cada muerte se anotan los squads presentes con ≥ 3 miembros. Se acredita a cada squad presente en **≥ 70 %** de las muertes necesarias; la entrada se comparte ("Dragones + Escarcha") y ocupa **una sola posición**. Los jugadores sin squad que participaron salen como *apoyo* en el tooltip. Una "pasada" de banda son las muertes de esa banda en los 7 días anteriores al jefe final.
- **Jefes y jefe final:** el catálogo (`Core/Content.lua`) **aprende** los jefes la primera vez que mueren con el addon (nombre, encounterID e instancia) y lo replica. El GM marca el **jefe final** en Ajustes > Contenido. Sin jefe final, las carreras de "completar" quedan *pendiente de datos*; las de cada jefe funcionan desde el primer día.

## 4. Carreras PvP

| Id | Carrera | Tamaño | Condición |
|---|---|---|---|
| `pvp.rank.<R>.s<TEMPORADA>` | Primeros en llegar al **rango PvP** R en la temporada | Top 10 | R = 5, 10, 12, 14; no disponible en el cliente 1.60.1 (se oculta solo) |
| `pvp.rank.class.<CLASE>.14.s<TEMPORADA>` | Primeros de cada clase en llegar al rango 14 en la temporada | Top 10 | ídem |
| `pvp.hk.<N>` | Primeros en llegar a N muertes con honor, contadas desde que instalan el addon | Top 10 | N = 100, 1.000, 5.000 |
| `pvp.bg.<N>` | Primeros **squads** en ganar N campos de batalla juntos | Top 10 | N = 10, 50, 100; ≥ 2 miembros del squad en la BG |
| `pvp.bgmap.<MAPA>` | Primeros squads en ganar en cada campo de batalla | Top 10 | por mapa (el nombre se lee del juego) |
| `wpvp.caps.<N>` | Primeros en llegar a N capturas con Overlord | Top 10 | N = 10, 100 (solo con Overlord activo) |

- Las carreras de **rango PvP** son **por temporada**; las demás, permanentes.
- El rango se lee con `UnitPVPRank`/`GetPVPRankInfo`. Si el cliente no tiene `UnitPVPRank` (caso de WoW Forever 1.60.1), los logros y carreras de rango no se muestran y `/gsq diag` dice `pvpRank=unsupported`.

## 5. Otras carreras

| Id | Carrera | Tamaño | Fuente |
|---|---|---|---|
| `prof.<PROFESIÓN>.<N>` | Primeros en llegar a N en cada profesión | Top 10 | `GetProfessions`/`GetProfessionInfo`, `C_SkillInfo`. N = 150, 225, 300 |
| `rep.<FACCIÓN>.exalted` | Primeros en llegar a Exaltado con cada facción | Top 10 | `C_Reputation` o `GetFactionInfo` |
| `legacy.<N>` | Primeros en conseguir N puntos de Legado (Legacy Points) | Top 10 | N = 100, 500, 1.000. El cliente 1.60.1 no tiene API para ellos: la carrera se muestra como «pendiente de datos» |
| `squad.full60` | Primeros **squads** con los 5 titulares al 60 | Top 10 | roster de la guild |

Si la API no existe en el cliente, la carrera queda *pendiente de datos*, sin error.

## 6. Logros (insignias con fecha y progreso)

### De squad
| Id | Logro | Condición | Progreso visible |
|---|---|---|---|
| `first60` | Primer 60 del squad | algún miembro llega al 60 | nivel máximo / 60 |
| `squad60` | Squad al 60 | los 5 titulares al 60 | n / 5 |
| `firstDungeon` | Primera mazmorra juntos | ≥ 2 miembros (jefe con testigos) | — |
| `forever` | Ruta Forever | las 9 mazmorras nuevas juntos | n / 9 |
| `boss10` / `boss50` / `boss100` | 10/50/100 jefes juntos | jefes con testigos | n / objetivo |
| `firstRaid` | Primer jefe de banda | ≥ 3 miembros en un jefe de banda | — |
| `sotw` / `sots` | Squad del wipe / de la temporada | primero en la General al cerrar | — |
| `firstBg` | Primera BG ganada juntos | ≥ 2 miembros | — |
| `hk100` | 100 HK del squad | suma del squad | n / 100 |
| `conq` | Conquistadores | 10 capturas con Overlord | n / 10 |
| `allRoles` | Equipo completo | 1 tanque, 1 sanador y 3 DPS por rol principal | — |
| `allClasses` | Arcoíris | 5 clases distintas entre los titulares | n / 5 |
| `wipeTopAll` | Sin fisuras | llegar al tope en las 5 categorías de un wipe | n / 5 |
| `wipes4` | Constancia | top 3 de la General 4 wipes seguidos | n / 4 |
| `hallOfFame` | Leyenda | el squad aparece en una carrera de Top 10 o menos | — |

### De personaje
| Id | Logro | Condición |
|---|---|---|
| `guildFirst60` | Primero de la guild al 60 | el primer 60 de la guild |
| `lvl<H>` | Nivel H (10…60) | llegar al nivel H con el addon instalado |
| `top100.<H>` | Entre los 100 primeros al nivel H | puesto en `lvl.all.<H>` |
| `top10class` | Top 10 de tu clase | puesto en cualquier `lvl.class.*` |
| `top10race` | Top 10 de tu raza | puesto en cualquier `lvl.race.*` |
| `first1` | ¡Primero! | puesto 1 en cualquier carrera |
| `dungeonsAll` | Explorador de Forever | las 9 mazmorras nuevas completadas (con cualquier grupo) |
| `raider` | Raider | un jefe de cada banda abierta |
| `pvpRank<R>` | Rango R | llegar al rango PvP R; no disponible en el cliente 1.60.1 (se oculta solo) |

### De guild
| Id | Logro | Condición |
|---|---|---|
| `allAboard` | Toda la guild a bordo | ≥ 80 % de los miembros activos (últimos 14 días) con el addon |

En Ajustes y en el Salón se ve "Guild Squads instalado: X/Y miembros".

## 7. Reglas comunes

1. **Orden de la carrera:** por hora del servidor (`GetServerTime`). Empate exacto: orden alfabético del nombre completo. Una entrada inválida (personaje fuera de la guild, hora incoherente) se descarta y el siguiente sube.
2. **Testigos:** jefes y BG necesitan ≥ 2 informes. Los niveles, el propio cliente + el roster, o ≥ 2 observadores del roster. Los contadores (HK, profesión, reputación) los informa el propio jugador y llevan la marca *informado por el jugador*; el primer dato es la línea base.
3. **No verificado:** un dato que llega tarde o con un salto raro se ve con «?» y no entra en el Top hasta que lo confirma un GM u oficial (registro `vconfirm`).
4. **Carrera cerrada = inmutable.** Un Top lleno se congela. Solo el GM puede **anular** una entrada, con motivo obligatorio; lo anulado queda en el historial y se puede revertir.
5. **Personajes que dejan la guild:** su entrada se queda en el Salón con la etiqueta *exmiembro*.
6. **Nada de oro ni de economía** en ninguna condición. Nada de DPS ni daño.
7. **Privacidad:** solo se ve dentro de la guild. *Exportar Top* copia el Top elegido como texto para Discord.

### Datos y sincronización
Las observaciones (`RO` en vivo, solo del autor; `RP` páginas de puesta al día, solo de GM u oficiales) se replican por el canal de addon de la guild; los Tops y los logros se **calculan en local** en cada cliente. Las carreras cerradas se compactan en una sola fila y no se reenvían si el hash coincide.

### Celebraciones
Aviso dentro del addon **siempre** (más grande si eres el 1). Mensaje en el chat de la guild **solo si el GM lo activa** en Ajustes > Celebrac. (desactivado por defecto): qué se anuncia (puesto 1 / Top 3 / cualquier entrada) y si se anuncian los logros de squad. Anuncia **un solo cliente** por evento: el del protagonista si tiene el addon; si no, el de mayor rango conectado (desempate por nombre). Máximo 1 mensaje cada 10 s, sin enlaces, nunca durante un encuentro.

## 8. El GM y el catálogo (Ajustes > Logros)

El GM adapta este catálogo a su guild sin tocar código (uso paso a paso: [GUIA-GM.md](GUIA-GM.md), sección *Logros*). Las reglas de §7 se mantienen: lo cerrado es inmutable, cada cliente vuelve a validar todo contra su propio roster y los resultados se calculan en local.

**Registros** (tipos de extensión, `M.registerKind`, orden 12 y 13; los firma **solo el GM**, rango 0, igual que `settings`):

| Registro | id | Campos | Para qué |
|---|---|---|---|
| `achdef` | id del logro o de la carrera (`lvl.all.60`, `hallOfFame`, `gm.<slug>`…) | `on`, `size` (solo carreras), `name` (≤ 32, sin colores ni enlaces), `sts` (cuándo se fijó el tamaño); los propios añaden `custom`, `metric`, `param`, `thr`, `scope` | activar/desactivar, tamaño del Top, nombre visible, logros propios |
| `achgrant` | `ach .. "|" .. who` | `ach`, `who` (personaje o id de squad), `reason` (obligatorio), `on` | otorgar una insignia a mano; `on = false` la retira y queda en el historial |

Un registro por logro: cada cambio viaja solo y se resuelve por última escritura (LWW) por id. Un cambio en bloque son N registros normales, 3 por mensaje, en la cola de 1 msg/s.

**Activar / desactivar.** Lo desactivado **sigue contando**: no se ve en el Salón, el Ranking ni Mis logros y no se celebra, pero sus observaciones se guardan y, al reactivarlo, vuelve con su historial. Lo ya conseguido se ve en **Legado** (apagado, etiqueta *legacy*).

**Tamaño del Top.** Solo carreras abiertas; de 1 al máximo de su familia (100 `lvl.all.*`, 3 `full.*`, 10 el resto) y nunca por debajo de las entradas que ya tiene. El cliente del GM rechaza el cambio sobre una carrera cerrada. Cada cliente aplica una regla determinista: un Top congelado conserva sus filas; una carrera que ya estaba llena con su tamaño de siempre cuando el GM la cambió conserva ese tamaño; si no, el tamaño nuevo, con el suelo de las entradas que tenía en ese momento (`sts`).

**Logros propios (`gm.<slug>`, máximo 50).** Carreras Top N con las mismas observaciones y testigos que las de serie:

| `metric` | `param` | `thr` | Ámbito |
|---|---|---|---|
| `level` | vacío, `class:<CLASE>` o `race:<RAZA>` | hito 10…60 | personaje |
| `boss` | id del jefe del catálogo aprendido (`<instancia>.<jefe>`) | — | grupo (≥ 2 testigos) |
| `bg` | vacío o mapa | N victorias de squad | squad (≥ 2 del squad en la BG) |
| `prof` | profesión | habilidad ≥ N (los informes llegan al cruzar 150, 225 y 300) | personaje |
| `rep` | facción | 8 = Exaltado (es lo único que se observa) | personaje |
| `manual` | — | — | insignia (personaje o squad), solo por `achgrant` |

Sin la API en el cliente (profesiones, reputación) la carrera queda *pendiente de datos*, como las de serie. Lo que mide un logro propio no cambia una vez creado.

**Otorgar a mano.** Solo insignias (los logros de §6 y los propios `manual`); **nunca** crea una entrada en un Top. En el tooltip: «Otorgado por el GM: <motivo>».

**Compatibilidad.** Un cliente que no conoce un tipo de registro lo ignora sin error (`Model.validShape` → `kind`, cuenta en `sync bad=`) y sigue sincronizando lo demás. `/gsq diag` muestra `catalog achdef=<n> custom=<n> grants=<n> off=<n>`.
