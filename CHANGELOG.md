# Changelog

## 1.0.0 — 2026-10-27

### ES

Primera versión pública de Guild Squads para World of Warcraft: Forever (cliente 1.60.1, interfaz 16001).

**Squads**
- Squads de 5 dentro de la guild: capitán, titulares y de 0 a 2 suplentes (lo decide el GM). Nombre, escudo (icono, color y borde), lema y hasta 3 etiquetas de objetivo.
- Para entrar hacen falta los dos lados: el capitán te incluye y tu perfil apunta al squad. Un squad por personaje.
- El capitán invita, acepta o rechaza solicitudes (el rechazo se sincroniza), pasa gente a suplentes, expulsa, cede la capitanía o disuelve. Aviso al capitán cuando llega una solicitud.
- *Llamar al squad* (una vez cada 5 min) e *Invitar al grupo*, solo con clic y fuera de combate. "Visto por última vez" y squads inactivos atenuados al final de la lista.

**Buscador y perfil**
- Mi perfil: clase, nivel y raza detectados; rol principal y secundario, horario (entre semana / fin de semana, 4 franjas) y objetivos. Marca "!" mientras el perfil esté incompleto y aviso de cambios sin guardar.
- Buscador con dos listas (squads con plaza y jugadores sin squad), filtros por rol, clase, nivel, horas en común, objetivo y conectados, y una puntuación de encaje que explica por qué te lo sugiere.
- Admite los apellidos de personaje de WoW Forever en el roster de la guild.

**Ranking y temporadas**
- Ranking de squads en 5 categorías más la General: Subir de nivel, Mazmorras, Bandas, PvP (campos de batalla) y PvP de mundo (muertes con honor fuera de instancias). Integración opcional con Overlord (solo lectura de capturas).
- Puntos por **wipe** (reinicio semanal el miércoles 09:00 hora del reino) con tope por categoría y reparto entre los miembros activos; **temporadas** con nombre y fechas que fija el GM.
- Jefes y campos de batalla cuentan con al menos 2 miembros del squad como testigos. La puntuación se calcula en cada cliente; nunca se envían totales.
- Panel "Este wipe" en Mi squad, botón "¿Cómo se puntúa?" y exportación del ranking para Discord.

**Salón de la fama y logros**
- Carreras Top N de la guild: Top 100 a cada hito de nivel, Top 10 por clase y por raza, primeras muertes de cada jefe, mazmorras y bandas completas, contenido PvE completo (Top 3), muertes con honor, campos de batalla, profesiones, reputaciones Exaltado y más. Cada puesto muestra la hora del reino y cómo se confirmó.
- Logros fechados de squad, de personaje y de guild, con progreso visible y cuadrícula "Mis logros".
- El GM puede anular un puesto con motivo y revertirlo; el historial se conserva.
- Celebraciones: aviso dentro del addon siempre; anuncio en el chat de la guild opcional y desactivado por defecto.

**Bandas**
- Pestaña Bandas para RL, oficiales y GM: rosters de 10, 20 y 40 en grupos G1–G8, añadiendo squads enteros o jugadores sueltos, con barra de composición y avisos.
- RSVP en un clic (Sí, Tal vez, No, Suplente) con comentario corto y recordatorio una hora antes.
- "Invitar confirmados" por tandas, un clic por tanda y fuera de combate. Asistencia registrada y % de las 8 últimas bandas.
- Copia a la semana siguiente, rosters semanales y exportación como texto para Discord.

**Ajustes del GM**
- Ajustes visibles para toda la guild en solo lectura; solo el GM (rango 0) los cambia y los comparte. Secciones: Squads, Competición, Temporada, Integraciones, Moderación, Celebraciones, Contenido, Bandas y Logros.
- Los oficiales pueden aprobar squads nuevos, disolver un squad o restablecer un nombre o escudo ofensivo.

**Catálogo del GM (Ajustes > Logros)**
- Activar o desactivar cada logro o carrera, uno a uno, por grupo o todos a la vez. Lo desactivado sigue contando sin mostrarse; lo ya conseguido aparece en **Legado**.
- Cambiar el tamaño de un Top abierto y su nombre visible.
- Hasta 50 logros propios con un asistente de 4 pasos (nivel, jefe, victorias de squad en BG, profesión, reputación o insignia otorgada).
- Otorgar insignias a mano con motivo obligatorio; una insignia otorgada nunca mete a nadie en un Top.

**Diagnóstico**
- `/gsq diag`: informe copiable con las APIs del cliente, contadores de eventos, estado de la sincronización, roster, catálogo y lectura de profesiones; también se guarda en SavedVariables.
- `/gsq sync`, `/gsq export` / `/gsq import`, `/gsq ui` y `/gsq debug`.
- Sincronización solo por el canal de addon de la guild, con comprobación de autoridad en cada cliente; nada se envía durante encuentros ni partidas PvP. Idiomas: español e inglés.

### EN

First public release of Guild Squads for World of Warcraft: Forever (client 1.60.1, interface 16001).

**Squads**
- Guild-only squads of 5: captain, starters and a bench of 0 to 2 (set by the GM). Name, crest (icon, colour and border), motto and up to 3 goal tags.
- Joining needs both sides: the captain lists you and your profile points to the squad. One squad per character.
- The captain invites, accepts or rejects requests (rejections are synced), moves players to the bench, kicks, hands over the captaincy or disbands. The captain is notified of new requests.
- *Call the squad* (once every 5 min) and *Invite to group*, on click only and out of combat. "Last seen" and inactive squads dimmed at the end of the list.

**Finder and profile**
- My profile: class, level and race detected; main and secondary role, play hours (weekday / weekend, 4 slots) and goals. A "!" mark while the profile is incomplete and an unsaved-changes prompt.
- Finder with two lists (squads with room and players without a squad), filters by role, class, level, shared hours, goal and online, and a fit score that explains each suggestion.
- Supports WoW Forever character surnames in the guild roster.

**Ranking and seasons**
- Squad ranking in 5 categories plus Overall: Leveling, Dungeons, Raids, PvP (battlegrounds) and World PvP (honorable kills outside instances). Optional Overlord integration (read-only captures).
- Points per **wipe** (weekly reset, Wednesday 09:00 realm time) with a cap per category and sharing among active members; **seasons** named and dated by the GM.
- Bosses and battlegrounds count with at least 2 squad members as witnesses. Scores are computed on each client; totals are never sent.
- "This wipe" panel in My squad, a "How is it scored?" button and ranking export for Discord.

**Hall of Fame and achievements**
- Guild Top N races: Top 100 to each level milestone, Top 10 per class and per race, first kills of every boss, full dungeon and raid clears, full PvE content (Top 3), honorable kills, battlegrounds, professions, Exalted reputations and more. Each entry shows the realm time and how it was confirmed.
- Dated squad, character and guild achievements, with visible progress and a "My achievements" grid.
- The GM can annul an entry with a reason and revert it; the history is kept.
- Celebrations: an in-addon notice always; guild chat announcements optional and off by default.

**Raids**
- Raids tab for raid leaders, officers and the GM: 10, 20 and 40-player rosters in groups G1–G8, adding whole squads or single players, with a composition bar and warnings.
- One-click RSVP (Yes, Maybe, No, Bench) with a short comment and a reminder one hour before.
- "Invite confirmed" in batches, one click per batch and out of combat. Attendance recorded and shown as a % of the last 8 raids.
- Copy to next week, weekly rosters and text export for Discord.

**GM settings**
- Settings visible to the whole guild read-only; only the GM (rank 0) changes and shares them. Sections: Squads, Competition, Season, Integrations, Moderation, Celebrate, Content, Raids and Achievements.
- Officers can approve new squads, disband a squad or reset an offensive name or crest.

**GM catalog (Settings > Achievements)**
- Enable or disable every achievement or race, one by one, per group or all at once. Disabled entries keep counting while hidden; what was already earned shows under **Legacy**.
- Change the size and the visible name of an open Top.
- Up to 50 custom achievements with a 4-step wizard (level, boss, squad battleground wins, profession, reputation or granted badge).
- Grant badges by hand with a mandatory reason; a granted badge never puts anyone in a Top.

**Diagnostics**
- `/gsq diag`: copyable report with the client APIs, event counters, sync state, roster, catalog and profession reading; also saved in SavedVariables.
- `/gsq sync`, `/gsq export` / `/gsq import`, `/gsq ui` and `/gsq debug`.
- Sync only over the guild addon channel, with authority checks on every client; nothing is sent during encounters or PvP matches. Languages: English and Spanish.
