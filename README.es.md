# Guild Squads

[![CI](https://github.com/acronims/forever-guild-squads/actions/workflows/ci.yml/badge.svg)](https://github.com/acronims/forever-guild-squads/actions/workflows/ci.yml)

**English → [README.md](README.md)**

Addon para **World of Warcraft: Forever** (cliente 1.60.1, `## Interface: 16001`). Versión **1.0.1**. Licencia MIT. Autor: Raul Illana.

## Qué es
Squads de 5 dentro de la guild, con el GM al mando:

- **Squads de 5** (capitán + titulares + suplentes configurables 0–2), con nombre, escudo, lema y etiquetas. Para entrar hacen falta los dos lados: el capitán te incluye **y** tu perfil apunta al squad.
- **Perfiles** de miembro (rol, horario, objetivos) y **Buscador** interno de la guild con sugerencias explicadas.
- **Rankings** por **wipe** (semanal, reinicio el miércoles 09:00 hora del reino) y por **temporada**; categorías PvE (Leveo, Mazmorras, Bandas) y PvP (campos de batalla, PvP de mundo).
- **Salón de la fama** (carreras Top N de la guild) y **logros** fechados de squad y de jugador ([ACHIEVEMENTS.md](docs/es/ACHIEVEMENTS.md)).
- **El GM adapta el catálogo** (**Ajustes > Logros**): activar o desactivar cada logro o carrera (uno a uno, por grupo o todos), cambiar el tamaño de un Top abierto y su nombre visible, crear hasta 50 logros propios sobre lo que el addon ya mide y otorgar insignias a mano con motivo. Lo desactivado sigue contando y lo ya conseguido queda en **Legado**.
- **Bandas**: rosters de 10/20/40, RSVP (Sí/Tal vez/No/Suplente), "Invitar confirmados", asistencia.
- **Celebraciones** opcionales en el chat de guild (desactivadas por defecto).
- **Diagnóstico** copiable con `/gsq diag`.
- **Inglés y español** en todo: la interfaz, los logros y carreras de serie, los estados y las celebraciones siguen el idioma del cliente. Los anuncios en el chat de la guild salen en el idioma del cliente que anuncia.

## Diagramas
Diagramas (PNG; HTML interactivo e índice en [docs/es/diagrams](docs/es/diagrams/README.md)): [arquitectura](docs/es/diagrams/png/01-architecture.png) · [ciclo del squad](docs/es/diagrams/png/02-squad-lifecycle.png) · [sync](docs/es/diagrams/png/03-sync.png) · [ajustes GM](docs/es/diagrams/png/04-gm-settings.png) · [puntuación](docs/es/diagrams/png/05-scoring.png) · [wipe/temporada](docs/es/diagrams/png/06-wipe-season.png) · [bandas](docs/es/diagrams/png/07-raids.png) · [Salón de la fama](docs/es/diagrams/png/08-hall-of-fame.png).

## Instalación
1. Descarga el zip de la release (CurseForge, Wago o GitHub Releases).
2. Descomprímelo en `Interface\AddOns\GuildSquads` dentro de la carpeta del cliente Forever (debe quedar `Interface\AddOns\GuildSquads\GuildSquads.toc`).
3. Entra con un personaje que esté en una guild.

## Primeros pasos
1. `/gsq` abre la ventana; la bienvenida te guía (perfil → squad → ranking).
2. **Mi perfil**: rellena rol y objetivo principal y guarda. La pestaña lleva un **"!"** mientras esté incompleto. Si sales con cambios sin guardar te ofrece **Guardar y salir**.
3. Crea un squad o busca uno en **Squads** / **Buscador**.
4. GM: abre **Ajustes**, revisa las secciones y pulsa **Guardar y compartir** ([GM-GUIDE.md](docs/es/GM-GUIDE.md)).
5. GM: en **Ajustes > Logros** decide qué logros y carreras usa tu guild (casilla, **Activar/Desactivar todo**, tamaño del Top, nombre), crea los tuyos con **Nuevo logro** y otorga insignias en **Otorgar**. Cada cambio se comparte al momento (sin "Guardar").

## Comandos
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

## Ajustes del GM
Solo el GM (rango 0) escribe los ajustes; el resto los ve en solo lectura. Secciones: **Squads** (rango mínimo para crear, aprobación por oficiales, suplentes 0–2, rangos de oficial, días hasta inactivo, máximo de squads), **Compet.** (activar, peso 0–3 y tope por categoría, objetivo semanal), **Temporada**, **Integrac.** (Overlord), **Moderación** (palabras prohibidas, disolver/restablecer squads, exportar/importar/sync), **Celebrac.**, **Contenido** (jefe final de cada mazmorra/banda), **Bandas** (lista de RL, permisos, clases útiles) y **Logros** (solo la ve el GM: catálogo de logros y carreras, logros propios, insignias otorgadas). Detalle: [GM-GUIDE.md](docs/es/GM-GUIDE.md).

## Cómo se puntúa
5 categorías: **Leveo**, **Mazmorras**, **Bandas**, **PvP** y **PvP de mundo**. Tope por defecto **100 por categoría y wipe** (máx. 500), configurable por el GM (50/100/150/200) con pesos 0–3; la **General** es la suma ponderada. Jefes y campos de batalla necesitan **2 miembros del squad** que lo informen en 180 s. La puntuación se calcula en cada cliente a partir de eventos; no se transmite. Detalle: [diagrama de puntuación](docs/es/diagrams/png/05-scoring.png) y [guía del jugador](docs/es/PLAYER-GUIDE.md#cómo-se-puntúa-en-pocas-palabras).

## Privacidad y reglas de Blizzard
- Se sincroniza **solo** por el canal de addon de la **GUILD** (prefijo `GSquads`) y por susurro de addon entre miembros de la guild: ajustes, squads, perfiles, eventos de progreso (niveles, jefes, campos de batalla, PvP de mundo), observaciones del Salón de la fama, catálogo de logros del GM y rosters/RSVP/asistencia de bandas.
- Nada sale de la guild. Sin servidores externos, sin telemetría, sin librerías embebidas.
- **Sin oro ni economía, sin anuncios, sin venta de nada.** El addon no automatiza el juego: invitar a banda requiere un clic por tanda y fuera de combate; no envía nada durante un encuentro ni en partidas PvP. Pensado para cumplir la política de addons de Blizzard.
- Datos locales en `GuildSquadsDB` (SavedVariables), separados por guild.

## Preguntas frecuentes
- **¿Necesita el addon toda la guild?** No, pero solo quien lo tiene puede estar en un squad y puntuar. Los niveles de quien no lo tiene se ven en el roster y cuentan para las carreras de nivel.
- **¿Puedo estar en dos squads?** No, uno por personaje. Tus alts pueden estar en otros, y un alt en otra guild guarda sus datos aparte.
- **¿Por qué veo una puntuación distinta a la de un compañero?** Cada cliente calcula el ranking con los eventos que tiene; en cuanto os llegan los mismos datos, coincide.
- **¿Puede un oficial cambiar los ajustes o el catálogo de logros?** No: solo el GM (rango 0). Los oficiales moderan squads y reenvían datos.
- **¿Cuesta algo?** No. Gratis, MIT, sin anuncios ni donaciones.

## Problemas
- `/gsq diag` → Ctrl+A, Ctrl+C y pégalo en la incidencia.
- Fichero de datos: `WTF\Account\<CUENTA>\SavedVariables\GuildSquads.lua` (en la carpeta del cliente Forever).
- Sin GM ni oficial conectado, un cliente recién entrado solo recibe lo que publican en vivo sus autores. Más en [PLAYER-GUIDE.md](docs/es/PLAYER-GUIDE.md).

## Limitaciones conocidas
- Sin firmas criptográficas: un GM u oficial con un cliente modificado puede falsificar reenvíos.
- Sin GM ni oficial conectado, cada uno solo recibe lo que publican en vivo sus autores.
- Una resincronización completa de una guild grande tarda minutos (throttle, por diseño).
- Los IDs de encuentros/instancias de Forever no se conocen: las instancias se reconocen por nombre y aprenden el ID al verlo.
- El cliente 1.60.1 no ofrece `UnitPVPRank`: ahí los logros y carreras de rango PvP no se muestran.
- Tampoco hay API de Legacy Points en 1.60.1: esas carreras quedan como «pendiente de datos».
- Las bandas de Forever abren el 9-dic-2026: hasta entonces la categoría Bandas muestra el aviso «Las bandas abren el 9-dic».
- Se ha visto que el cliente de Forever a veces no relee las SavedVariables al entrar: haz `/gsq export` de vez en cuando y guarda el texto (con `/gsq import` lo recuperas).
- Sin chat de squad.

## Estado
**1.0.1.** La lógica (`Core/`), el transporte y el flujo completo se prueban fuera del juego con tests unitarios y un simulador multi-cliente ([SIMULATOR-RESULTS.md](docs/es/SIMULATOR-RESULTS.md)). Arquitectura: [ARCHITECTURE.md](docs/es/ARCHITECTURE.md). Cambios: [CHANGELOG.md](CHANGELOG.md).

## Documentación
[docs/es/INDEX.md](docs/es/INDEX.md) · Jugador: [PLAYER-GUIDE.md](docs/es/PLAYER-GUIDE.md) · GM/oficiales/RL: [GM-GUIDE.md](docs/es/GM-GUIDE.md) · Logros: [ACHIEVEMENTS.md](docs/es/ACHIEVEMENTS.md) · Arquitectura: [ARCHITECTURE.md](docs/es/ARCHITECTURE.md) · Simulador: [SIMULATOR-RESULTS.md](docs/es/SIMULATOR-RESULTS.md) · Publicar: [RELEASE.md](docs/es/RELEASE.md) · Diagramas: [docs/es/diagrams](docs/es/diagrams/README.md) · Contribuir: [CONTRIBUTING.md](CONTRIBUTING.md) (en inglés) · Seguridad: [SECURITY.md](SECURITY.md) (en inglés)

Cada documento existe también en inglés en [docs/en/](docs/en/INDEX.md), con el mismo nombre de fichero.

## Licencia
MIT — ver [LICENSE](LICENSE).
