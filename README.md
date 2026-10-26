# Guild Squads

[![CI](https://github.com/acronims/forever-guild-squads/actions/workflows/ci.yml/badge.svg)](https://github.com/acronims/forever-guild-squads/actions/workflows/ci.yml)

Addon para **World of Warcraft: Forever** (cliente 1.60.1, `## Interface: 16001`). Versión **1.0.0**. Licencia MIT. Autor: Raul Illana.
*English below — [jump to English](#english).*

---

## Español

### Qué es
Squads de 5 dentro de la guild, con el GM al mando:

- **Squads de 5** (capitán + titulares + suplentes configurables 0–2), con nombre, escudo, lema y etiquetas. Para entrar hacen falta los dos lados: el capitán te incluye **y** tu perfil apunta al squad.
- **Perfiles** de miembro (rol, horario, objetivos) y **Buscador** interno de la guild con sugerencias explicadas.
- **Rankings** por **wipe** (semanal, reinicio el miércoles 09:00 hora del reino) y por **temporada**; categorías PvE (Leveo, Mazmorras, Bandas) y PvP (campos de batalla, PvP de mundo).
- **Salón de la fama** (carreras Top N de la guild) y **logros** fechados de squad y de jugador ([LOGROS.md](docs/LOGROS.md)).
- **El GM adapta el catálogo** (**Ajustes > Logros**): activar o desactivar cada logro o carrera (uno a uno, por grupo o todos), cambiar el tamaño de un Top abierto y su nombre visible, crear hasta 50 logros propios sobre lo que el addon ya mide y otorgar insignias a mano con motivo. Lo desactivado sigue contando y lo ya conseguido queda en **Legado**.
- **Bandas**: rosters de 10/20/40, RSVP (Sí/Tal vez/No/Suplente), "Invitar confirmados", asistencia.
- **Celebraciones** opcionales en el chat de guild (desactivadas por defecto).
- **Diagnóstico** copiable con `/gsq diag`.

### Diagramas
Diagramas (PNG): [arquitectura](docs/diagrams/png/01-arquitectura.png) · [ciclo del squad](docs/diagrams/png/02-ciclo-squad.png) · [sync](docs/diagrams/png/03-sync.png) · [ajustes GM](docs/diagrams/png/04-ajustes-gm.png) · [puntuación](docs/diagrams/png/05-puntuacion.png) · [wipe/temporada](docs/diagrams/png/06-wipe-temporada.png) · [bandas](docs/diagrams/png/07-bandas.png) · [Salón de la fama](docs/diagrams/png/08-salon-de-la-fama.png).

### Instalación
1. Descarga el zip de la release (CurseForge, Wago o GitHub Releases).
2. Descomprímelo en `Interface\AddOns\GuildSquads` dentro de la carpeta del cliente Forever (debe quedar `Interface\AddOns\GuildSquads\GuildSquads.toc`).
3. Entra con un personaje que esté en una guild.

### Primeros pasos
1. `/gsq` abre la ventana; la bienvenida te guía (perfil → squad → ranking).
2. **Mi perfil**: rellena rol y objetivo principal y guarda. La pestaña lleva un **"!"** mientras esté incompleto. Si sales con cambios sin guardar te ofrece **Guardar y salir**.
3. Crea un squad o busca uno en **Squads** / **Buscador**.
4. GM: abre **Ajustes**, revisa las secciones y pulsa **Guardar y compartir** ([GUIA-GM.md](docs/GUIA-GM.md)).
5. GM: en **Ajustes > Logros** decide qué logros y carreras usa tu guild (casilla, **Activar/Desactivar todo**, tamaño del Top, nombre), crea los tuyos con **Nuevo logro** y otorga insignias en **Otorgar**. Cada cambio se comparte al momento (sin "Guardar").

### Comandos
| Comando | Qué hace |
|---|---|
| `/gsq` (o `/gsq toggle`) | Abre/cierra la ventana (también hay atajo de teclado "Guild Squads: abrir") |
| `/gsq help` | Lista de comandos |
| `/gsq sync` | Pide a la guild los datos que te faltan (1 vez por minuto) |
| `/gsq diag` | Informe de diagnóstico copiable |
| `/gsq export` / `/gsq import` | Copia de seguridad en texto |
| `/gsq minimap` | Vuelve a mostrar el botón del minimapa |
| `/gsq welcome` (`bienvenida`) · `/gsq news` (`novedades`) | Guía de bienvenida · novedades |
| `/gsq ui` | Qué plantillas/atlas tiene este cliente (informe de alternativas) |
| `/gsq debug` | Contadores + log detallado |

### Ajustes del GM
Solo el GM (rango 0) escribe los ajustes; el resto los ve en solo lectura. Secciones: **Squads** (rango mínimo para crear, aprobación por oficiales, suplentes 0–2, rangos de oficial, días hasta inactivo, máximo de squads), **Compet.** (activar, peso 0–3 y tope por categoría, objetivo semanal), **Temporada**, **Integrac.** (Overlord), **Moderación** (palabras prohibidas, disolver/restablecer squads, exportar/importar/sync), **Celebrac.**, **Contenido** (jefe final de cada mazmorra/banda), **Bandas** (lista de RL, permisos, clases útiles) y **Logros** (solo la ve el GM: catálogo de logros y carreras, logros propios, insignias otorgadas). Detalle: [GUIA-GM.md](docs/GUIA-GM.md).

### Cómo se puntúa
5 categorías: **Leveo**, **Mazmorras**, **Bandas**, **PvP** y **PvP de mundo**. Tope por defecto **100 por categoría y wipe** (máx. 500), configurable por el GM (50/100/150/200) con pesos 0–3; la **General** es la suma ponderada. Jefes y campos de batalla necesitan **2 miembros del squad** que lo informen en 180 s. La puntuación se calcula en cada cliente a partir de eventos; no se transmite. Detalle: [diagrama de puntuación](docs/diagrams/png/05-puntuacion.png) y [guía del jugador](docs/GUIA-JUGADOR.md#cómo-se-puntúa-en-pocas-palabras).

### Privacidad y reglas de Blizzard
- Se sincroniza **solo** por el canal de addon de la **GUILD** (prefijo `GSquads`) y por susurro de addon entre miembros de la guild: ajustes, squads, perfiles, eventos de progreso (niveles, jefes, campos de batalla, PvP de mundo), observaciones del Salón de la fama, catálogo de logros del GM y rosters/RSVP/asistencia de bandas.
- Nada sale de la guild. Sin servidores externos, sin telemetría, sin librerías embebidas.
- **Sin oro ni economía, sin anuncios, sin venta de nada.** El addon no automatiza el juego: invitar a banda requiere un clic por tanda y fuera de combate; no envía nada durante un encuentro ni en partidas PvP. Pensado para cumplir la política de addons de Blizzard.
- Datos locales en `GuildSquadsDB` (SavedVariables), separados por guild.

### Preguntas frecuentes
- **¿Necesita el addon toda la guild?** No, pero solo quien lo tiene puede estar en un squad y puntuar. Los niveles de quien no lo tiene se ven en el roster y cuentan para las carreras de nivel.
- **¿Puedo estar en dos squads?** No, uno por personaje. Tus alts pueden estar en otros, y un alt en otra guild guarda sus datos aparte.
- **¿Por qué veo una puntuación distinta a la de un compañero?** Cada cliente calcula el ranking con los eventos que tiene; en cuanto os llegan los mismos datos, coincide.
- **¿Puede un oficial cambiar los ajustes o el catálogo de logros?** No: solo el GM (rango 0). Los oficiales moderan squads y reenvían datos.
- **¿Cuesta algo?** No. Gratis, MIT, sin anuncios ni donaciones.

### Problemas
- `/gsq diag` → Ctrl+A, Ctrl+C y pégalo en la incidencia.
- Fichero de datos: `WTF\Account\<CUENTA>\SavedVariables\GuildSquads.lua` (en la carpeta del cliente Forever).
- Sin GM ni oficial conectado, un cliente recién entrado solo recibe lo que publican en vivo sus autores. Más en [GUIA-JUGADOR.md](docs/GUIA-JUGADOR.md).

### Limitaciones conocidas
- Sin firmas criptográficas: un GM u oficial con un cliente modificado puede falsificar reenvíos.
- Sin GM ni oficial conectado, cada uno solo recibe lo que publican en vivo sus autores.
- Una resincronización completa de una guild grande tarda minutos (throttle, por diseño).
- Los IDs de encuentros/instancias de Forever no se conocen: las instancias se reconocen por nombre y aprenden el ID al verlo.
- El cliente 1.60.1 no ofrece `UnitPVPRank`: ahí los logros y carreras de rango PvP no se muestran.
- Tampoco hay API de Legacy Points en 1.60.1: esas carreras quedan como «pendiente de datos».
- Las bandas de Forever abren el 9-dic-2026: hasta entonces la categoría Bandas muestra el aviso «Las bandas abren el 9-dic».
- Se ha visto que el cliente de Forever a veces no relee las SavedVariables al entrar: haz `/gsq export` de vez en cuando y guarda el texto (con `/gsq import` lo recuperas).
- Sin chat de squad.

### Estado
**1.0.0.** La lógica (`Core/`), el transporte y el flujo completo se prueban fuera del juego con tests unitarios y un simulador multi-cliente ([SIM-RESULTADOS.md](docs/SIM-RESULTADOS.md)). Arquitectura: [ARCHITECTURE.md](docs/ARCHITECTURE.md). Cambios: [CHANGELOG.md](CHANGELOG.md).

### Documentación
[docs/INDEX.md](docs/INDEX.md) · Jugador: [GUIA-JUGADOR.md](docs/GUIA-JUGADOR.md) · GM/oficiales/RL: [GUIA-GM.md](docs/GUIA-GM.md) · Logros: [LOGROS.md](docs/LOGROS.md) · Contribuir: [CONTRIBUTING.md](CONTRIBUTING.md) · Seguridad: [SECURITY.md](SECURITY.md) · Publicar: [RELEASE.md](docs/RELEASE.md)

---

## English

### What it is
Guild-only squads of 5, with the guild master in control:

- **Squads of 5** (captain + starters + bench 0–2), with a name, crest, motto and tags. Joining needs both sides: the captain lists you **and** your profile points to the squad.
- Member **profiles** (role, play hours, goals) and an in-guild **Finder** with explained suggestions.
- **Rankings** per **wipe** (weekly, reset Wednesday 09:00 realm time) and per **season**; PvE categories (leveling, dungeons, raids) and PvP categories (battlegrounds, world PvP).
- **Hall of Fame** (guild Top N races) and dated squad/player **achievements** ([LOGROS.md](docs/LOGROS.md), ES).
- **The GM tailors the catalog** (**Settings > Achievements**): enable or disable each achievement or race (one by one, per group or all at once), change the size and visible name of an open Top, create up to 50 custom achievements on what the addon already measures, and grant badges by hand with a reason. Disabled entries keep counting and what was already earned stays under **Legacy**.
- **Raids**: rosters of 10/20/40, RSVP (Yes/Maybe/No/Bench), "Invite confirmed", attendance.
- Optional **celebrations** in guild chat (off by default).
- Copyable **diagnostics** with `/gsq diag`.

### Diagrams
Diagrams (PNG, labels in Spanish): [architecture](docs/diagrams/png/01-arquitectura.png) · [squad lifecycle](docs/diagrams/png/02-ciclo-squad.png) · [sync](docs/diagrams/png/03-sync.png) · [GM settings](docs/diagrams/png/04-ajustes-gm.png) · [scoring](docs/diagrams/png/05-puntuacion.png) · [wipe/season](docs/diagrams/png/06-wipe-temporada.png) · [raids](docs/diagrams/png/07-bandas.png) · [Hall of fame](docs/diagrams/png/08-salon-de-la-fama.png).

### Install
1. Download the release zip (CurseForge, Wago or GitHub Releases).
2. Unzip into `Interface\AddOns\GuildSquads` inside the Forever client folder (you should end up with `Interface\AddOns\GuildSquads\GuildSquads.toc`).
3. Log in with a character that is in a guild.

### First steps
1. `/gsq` opens the window; the welcome guide walks you through profile → squad → ranking.
2. **My profile**: set role and main goal and save. The tab shows a **"!"** while the profile is incomplete. Leaving with unsaved changes offers **Save and exit**.
3. Create a squad or find one in **Squads** / **Finder**.
4. GM: open **Settings**, go through the sections and press **Save and share** ([GM-GUIDE.md](docs/GM-GUIDE.md)).
5. GM: in **Settings > Achievements** choose which achievements and races your guild uses (checkbox, **Enable/Disable all**, Top size, name), create your own with **New achievement** and grant badges under **Grant**. Every change is shared at once (no "Save").

### Commands
| Command | What it does |
|---|---|
| `/gsq` (or `/gsq toggle`) | Open/close the window (there is also a "Guild Squads: open" key binding) |
| `/gsq help` | Command list |
| `/gsq sync` | Ask the guild for missing data (once per minute) |
| `/gsq diag` | Copyable diagnostics report |
| `/gsq export` / `/gsq import` | Text backup |
| `/gsq minimap` | Show the minimap button again |
| `/gsq welcome` · `/gsq news` | Welcome guide · what's new |
| `/gsq ui` | Which templates/atlases this client has (fallback report) |
| `/gsq debug` | Counters + verbose log |

### GM settings
Only the GM (rank 0) writes settings; everyone else sees them read-only. Sections: **Squads**, **Compet.** (on/off, weight 0–3 and cap per category, weekly goal), **Season**, **Integr.** (Overlord), **Moderation**, **Celebrate**, **Content** (final boss per dungeon/raid), **Raids** (RL list, permissions, useful classes) and **Achiev.** (GM only: catalog of achievements and races, custom achievements, granted badges). Details: [GM-GUIDE.md](docs/GM-GUIDE.md).

### How scoring works
5 categories: **Leveling**, **Dungeons**, **Raids**, **PvP**, **World PvP**. Default cap **100 per category and wipe** (max 500), GM-configurable (50/100/150/200) with weights 0–3; **Overall** is the weighted sum. Bosses and battlegrounds need **2 squad members** reporting within 180 s. Scores are computed locally from events, never transmitted. Details: [PLAYER-GUIDE.md](docs/PLAYER-GUIDE.md#how-scoring-works-in-plain-words).

### Privacy and Blizzard rules
- Synced **only** over the **GUILD** addon channel (prefix `GSquads`) and addon whispers between guild members: settings, squads, profiles, progress events (levels, bosses, battlegrounds, world PvP), Hall of Fame observations, the GM's achievement catalog, raid rosters/RSVP/attendance.
- Nothing leaves the guild. No external servers, no telemetry, no embedded libraries.
- **No gold or economy data, no ads, nothing for sale.** No game automation: raid invites need one click per batch, out of combat; nothing is sent during encounters or PvP matches. Designed to comply with Blizzard's addon policy.
- Local data in `GuildSquadsDB` (SavedVariables), kept per guild.

### FAQ
- **Does the whole guild need the addon?** No, but only players with it can join a squad and score. Levels of members without it are seen in the guild roster and count for the level races.
- **Can I be in two squads?** No, one per character. Your alts can be in others, and an alt in another guild keeps its data apart.
- **Why does my score differ from a guildmate's?** Each client computes the ranking from the events it has; once you both have the same data, it matches.
- **Can an officer change the settings or the achievement catalog?** No: only the GM (rank 0). Officers moderate squads and relay data.
- **Does it cost anything?** No. Free, MIT, no ads, no donations.

### Troubleshooting
- `/gsq diag` → Ctrl+A, Ctrl+C and paste it in the issue.
- Data file: `WTF\Account\<ACCOUNT>\SavedVariables\GuildSquads.lua` (in the Forever client folder).
- With no GM or officer online, a freshly logged-in client only receives what authors publish live. See [PLAYER-GUIDE.md](docs/PLAYER-GUIDE.md).

### Known limitations
- No cryptographic signatures: a GM/officer running a modified client can still forge relays.
- With no GM or officer online, each player only receives what authors publish live.
- A full resync of a large guild takes minutes by design (throttle).
- Forever encounter/instance IDs are unknown: instances match by name and learn the ID when seen.
- The 1.60.1 client has no `UnitPVPRank`: PvP rank achievements and races are not shown there.
- There is no Legacy Points API in 1.60.1 either: those races stay as "pending data".
- Forever raids open on 9-Dec-2026: until then the Raids category shows the "Raids open on 9-Dec" notice.
- The Forever client has been seen not reading SavedVariables back on login: run `/gsq export` now and then and keep the text (`/gsq import` restores it).
- No squad chat.

### Status
**1.0.0.** Logic (`Core/`), transport and the full flow are tested outside the game with unit tests and a multi-client simulator ([SIM-RESULTADOS.md](docs/SIM-RESULTADOS.md), ES). Architecture: [ARCHITECTURE.md](docs/ARCHITECTURE.md). Changes: [CHANGELOG.md](CHANGELOG.md).

### Docs
[docs/INDEX.md](docs/INDEX.md) · Players: [PLAYER-GUIDE.md](docs/PLAYER-GUIDE.md) · GM/officers/RL: [GM-GUIDE.md](docs/GM-GUIDE.md) · Achievements: [LOGROS.md](docs/LOGROS.md) (ES) · Contributing: [CONTRIBUTING.md](CONTRIBUTING.md) · Security: [SECURITY.md](SECURITY.md) · Release: [RELEASE.md](docs/RELEASE.md)

## License
MIT — see [LICENSE](LICENSE).
