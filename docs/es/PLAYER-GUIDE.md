# Guild Squads — Guía del jugador

English → [PLAYER-GUIDE.md](../en/PLAYER-GUIDE.md)

Addon de WoW Forever (interfaz 16001) para formar squads de 5 dentro de tu guild, competir por semanas, entrar en el Salón de la fama y apuntarte a bandas. Todo se queda dentro de la guild. Si algo falla, `/gsq diag` y manda el informe (ver *Problemas*).

Guía del GM, los oficiales y los líderes de banda: [GM-GUIDE.md](GM-GUIDE.md).

## Primeros pasos

1. Instala el zip en `Interface\AddOns\GuildSquads` y entra con un personaje que esté en una guild.
2. Escribe `/gsq` (o pulsa el botón del minimapa). La primera vez sale la bienvenida con 4 pasos; puedes volver a verla con `/gsq bienvenida`.
3. **Mi perfil**: elige rol principal y secundario, tus horas de juego (entre semana / fin de semana, 4 franjas) y qué quieres hacer (subir nivel, mazmorras, farmear, PvP de mundo, campos de batalla, bandas). Guarda. Clase, nivel y raza se detectan solos.
4. **Squads** o **Buscador**: pide entrar en un squad con plaza, o crea el tuyo con **Crear squad**.
5. Juega con tu squad: el **Ranking** suma solo.

## Las pestañas

**Mi squad.** Tu squad: miembros con rol y clase, "visto por última vez", logros del squad (con fecha o con su progreso en gris) y el panel **Este wipe** (puntos de cada categoría, tope y posición en la guild). Botones: *Llamar al squad* (avisa a los conectados de dónde estás; una vez cada 5 min, no en instancias PvP) e *Invitar al grupo* (solo con clic y fuera de combate). El capitán ve también las **solicitudes** (aceptar ✔ o rechazar) y puede pasar a alguien a suplente, expulsar o ceder la capitanía.

**Squads.** Todos los squads de la guild con su escudo, lema, etiquetas y plazas. Los inactivos (nadie conectado en N días) salen atenuados y al final. Desde aquí pides entrar.

**Buscador.** Dos listas: *Squads con plaza* y *Jugadores sin squad*. Filtra por rol, clase, nivel, horas en común, objetivo y conectados. Cada sugerencia dice por qué encaja.

**Mi perfil.** Tus datos y **Mis logros** (cuadrícula con fecha o progreso). Una insignia otorgada por el GM dice *Otorgado por el GM: motivo* en el tooltip; un logro que el GM desactivó y ya tenías queda al final, en *Legado*. Mientras tu perfil no se haya guardado nunca o le falte el rol o el objetivo principal, la pestaña lleva una marca **"!"**; desaparece al completarlo. Si sales con cambios sin guardar, te avisa con tres opciones: **Guardar y salir** (guarda y cambia de pestaña; si el guardado se rechaza, te quedas), **Descartar** o **Seguir editando**.

**Crear squad.** Dos pasos: nombre, lema y etiquetas (máx. 3); después el escudo (icono, color y borde) con vista previa. Si el GM exige aprobación, un oficial tiene que aprobarlo.

**Ranking.** Clasificación de squads por categoría (Leveo, Mazmorras, Bandas, PvP, PvP de mundo y General). Arriba eliges *Wipe* (el actual y los 8 anteriores) o *Temporada*. Tu squad va fijo arriba. Pasa el ratón por un squad para ver el desglose. *¿Cómo se puntúa?* lo explica en el juego. *Exportar ranking* copia el top 10 para Discord.

**Bandas.** Las bandas publicadas por los RL. Filtros *Próximas*, *Mis bandas* y *Pasadas*. En cada tarjeta respondes en un clic: **Sí**, **Tal vez**, **No** o **Suplente**, con un comentario corto (60 caracteres) para el RL. Una hora antes sale un recordatorio dentro del addon. Si no hay ninguna banda publicada, la pestaña no aparece.

**Salón de la fama.** Carreras de la guild: Top 100 a cada nivel, Top 10 por clase y por raza, primeras muertes de cada jefe, mazmorras y bandas completas, contenido PvE completo (Top 3), rango PvP por temporada (no disponible en el cliente 1.60.1: se oculta solo), muertes con honor, campos de batalla, profesiones, reputaciones exaltadas y las carreras propias que cree el GM. Cada puesto lleva la hora del reino y cómo se confirmó: *exacta*, *aprox.*, *testigos* o *informado por el jugador*. *Exportar Top* lo copia para Discord. Las carreras que el GM desactivó y ya tenían puestos están en *Legado (n)*. Catálogo completo: [ACHIEVEMENTS.md](ACHIEVEMENTS.md).

**Ajustes.** Los ves todos, pero solo el GM los cambia ("Solo el GM puede cambiar esto"). En *Moderación > Datos* tienes Exportar, Importar y Sincronizar.

## Comandos

| Comando | Qué hace |
|---|---|
| `/gsq` | Abre o cierra la ventana (también hay atajo de teclado "Guild Squads: abrir"). |
| `/gsq help` | Lista los comandos. |
| `/gsq sync` | Pide a la guild los datos que te faltan. Una vez por minuto. |
| `/gsq export` | Copia de seguridad en texto: Ctrl+A, Ctrl+C y guárdala. |
| `/gsq import` | Pega una copia y pulsa Importar. Dice cuántos registros aplicó y cuántos rechazó. |
| `/gsq diag` | Informe de diagnóstico para copiar (también se guarda en SavedVariables). |
| `/gsq minimap` | Vuelve a mostrar el botón del minimapa. |
| `/gsq novedades` · `/gsq bienvenida` | Novedades · guía de bienvenida (también `/gsq news` · `/gsq welcome`). |

## Cómo se puntúa, en pocas palabras

- **Wipe** = la semana de competición. Empieza el miércoles a las 09:00 hora del reino (UE, con horario de verano). Cada categoría tiene un **tope por wipe** (100 por defecto; el GM lo cambia), así que jugar más horas no basta.
- **Temporada** = un periodo con nombre que pone el GM (por defecto "Temporada 1" desde el 4-nov-2026). Los puntos de la temporada son la suma de sus wipes, cada uno ya con su tope.
- **Leveo**: cada nivel que sube un miembro mientras está en el squad.
- **Mazmorras y bandas**: cada jefe muerto; más miembros del squad presentes = más puntos. El mismo jefe cuenta una vez al día por squad. El primer squad de la guild en matar un jefe de banda se lleva un extra.
- **PvP**: campos de batalla con compañeros de squad (ganar vale 10, perder 3). **PvP de mundo**: 1 punto por cada 5 muertes con honor fuera de instancias. Si usas el addon Overlord, sus capturas pueden puntuar (lo decide el GM).
- **Reparto**: los puntos se dividen entre los miembros activos (mínimo 3), así un squad grande no gana por ser grande.
- **Testigos**: un jefe o un campo de batalla solo cuenta si lo informan **al menos 2 miembros del squad con el addon** en 3 minutos. Si juegas con gente sin addon, no puntúa.
- **Si cambias de squad**: te llevas tus puntos del wipe en curso; los wipes cerrados se quedan con el squad anterior.
- Nadie envía totales: cada cliente calcula el ranking con los mismos eventos. Por eso dos personas pueden ver un número distinto durante unos minutos hasta que les llegan los mismos datos.

## Salón de la fama: cómo se confirma

- **Nivel**: *exacta* si tú lo informas y el roster de la guild lo confirma; *aprox.* si lo ven 2 jugadores con el addon en 10 minutos (o un GM/oficial).
- **Jefes y campos de batalla**: 2 informes en 3 minutos; con uno solo queda "pendiente" 24 h.
- **Contadores** (muertes con honor, profesiones, reputación): los informa el propio jugador. El primer dato es tu *línea base* y no puntúa; cuenta lo que avances desde ahí.
- Un dato que llega tarde o con un salto raro queda *no verificado* y no entra en el Top hasta que lo confirma un GM u oficial.
- El GM puede anular un puesto con motivo (y revertirlo). El siguiente sube.

## Problemas frecuentes

**Al volver a entrar no tengo mis datos.** Se ha visto que el cliente de Forever guarda las SavedVariables al salir pero a veces no las vuelve a leer. Qué hacer: haz `/gsq export` de vez en cuando y guarda el texto; si pierdes datos, `/gsq import`. Además, al conectar, lo recuperas de la guild si hay un GM u oficial conectado (`/gsq sync`).

**No me llega nada / no veo los squads de otros.** Los datos de otros solo te llegan en vivo de su autor o reenviados por el **GM o un oficial**. Sin GM ni oficial conectados, solo recibes lo que publican en ese momento los propios autores. Espera a que entre uno y haz `/gsq sync`. En guilds grandes, ponerse al día tarda unos minutos (a propósito, para no saturar el canal).

**No se anuncia nada en el chat de la guild.** Las celebraciones en el chat de la guild están **desactivadas por defecto**; las activa el GM en Ajustes > Celebrac. (*Anunciar en el chat de la guild*, *Qué se anuncia*: Puesto 1 / Top 3 / Cualquiera, y *Anunciar también los logros de squad*). El aviso dentro del addon sale siempre. El mensaje del chat va en el idioma del cliente que lo anuncia, que puede no ser el tuyo.

**Mis profesiones no salen en el Salón de la fama.** Mira la línea `prof path=… n=…` de `/gsq diag`: si dice `none` o `empty` con `n=0`, el cliente no le da al addon tus profesiones; mándanos el informe.

**Mi jefe no puntuó.** ¿Había otro miembro del squad con el addon en el grupo? ¿Ya lo matasteis hoy? ¿La competición está activa y la categoría tiene peso > 0? Durante el combate el addon no envía nada: se envía al terminar.

**No puedo entrar en el squad.** Hace falta que el capitán te acepte **y** que tu perfil apunte a ese squad. Un personaje solo puede estar en un squad.

**El botón está gris.** Pasa el ratón: el tooltip dice por qué (no eres capitán, el squad está lleno, primero elige una tarjeta...).

**Informe para el desarrollador.** `/gsq diag`, Ctrl+A, Ctrl+C y pégalo en la incidencia. O manda el fichero `WTF\Account\<CUENTA>\SavedVariables\GuildSquads.lua` (en la carpeta del cliente de Forever).


## Qué trae `/gsq diag`

Abre una ventana con el informe para copiar (Ctrl+A, Ctrl+C); la misma copia queda en SavedVariables. Además de la versión, contadores de eventos y APIs del cliente, añade estas líneas:

- `events=<N> wipe=<wipe> v=<versión>` (Progress): eventos de puntuación guardados y wipe en curso.
- `hall obs=<N> closed=<N> chatErr=<error> pvpRank=ok|unsupported`: observaciones del Salón de la fama, carreras cerradas, el último error al anunciar en el chat de la guild y si el cliente da el rango PvP.
- `prof path=<vía> n=<N>`: qué API del cliente leyó tus profesiones (`GetProfessions`, `C_SkillInfo`, `empty` o `none`) y cuántas encontró.
- `raid apis <API>=yes|no … rosters=<N>`: qué APIs de grupo y banda existen en el cliente y cuántos rosters de banda hay.
- `comm sent= recv= failed= pending=`: mensajes de addon enviados, recibidos, fallidos y en cola.
- `sync bad= relayRefused= future= errors= quarantine= guild=`: registros rechazados (mal formados, reenvío no autorizado, fecha futura), en cuarentena, y la guild cargada.
- `[roster] me=<clave> found=yes|no entries=<N> surnames=<N>`: si tu personaje aparece en el roster de la guild (se admiten los apellidos de personaje).
- `catalog achdef=<N> custom=<N> grants=<N> off=<N>`: el catálogo de logros del GM (entradas, logros propios, insignias otorgadas, desactivados).

## Preguntas frecuentes

**¿Sale algo fuera de la guild?** No. Solo el canal de addon de la guild y susurros de addon a miembros de la guild. Sin peticiones a internet.

**¿Necesito el addon para salir en el Salón de la fama?** Los niveles de miembros sin addon se ven por el roster de la guild (desde que alguien con addon lo observa, no hacia atrás). Jefes, PvP y contadores necesitan el addon.

**¿Puedo estar en dos squads?** No, uno por personaje. Tus alts pueden estar en otros.

**¿Y mis alts en otra guild?** Los datos se guardan por guild; un alt en otra guild no toca los de la principal.

**¿Cuesta algo?** No. Gratis, MIT, sin anuncios, sin donaciones y sin oro de por medio.
