# Changelog

## 2.0.0 — 2026-11-09 — Cada personaje es «Nombre Apellido» / Every character is «Name Surname»

### ES

- **⚠️ Tiene que actualizar toda la guild.** La 2.0 habla el protocolo 3 y firma con etiquetas nuevas. No recibe nada de la 1.x (1.0.x, 1.1 y 1.2.x) y la 1.x no recibe nada de la 2.0. No hay errores: cada una ignora a la otra. Hasta que actualicen todos, la guild queda partida en dos redes.
- **Cada personaje es «Nombre Apellido».** En WoW Forever el nombre completo con apellido es único en la región. La 2.0 lo usa para todo: autor de tus datos, clave de firma, certificados y destino de los susurros, siempre sin «-Reino», también con reinos conectados. **Arreglado: dos personajes del mismo reino con el mismo nombre de pila** («Kas Pitas» y «Kas Mora») ya son dos personas distintas, cada una con su perfil, su clave y su squad. La 1.2.2 los ignoraba a los dos.
- **Tus datos pasan solos a la identidad nueva.** Al entrar con la 2.0, tu perfil, tu squad y el resto de lo tuyo se firman otra vez como «Nombre Apellido», con una clave nueva; la vieja se borra. Lo de tus alts no se pierde: espera hasta que entras con cada alt. Las claves y los certificados de los demás se vuelven a aprender en persona.
- **Lo que otros firmaron con la 1.x se borra de tu cliente:** perfiles, squads, ajustes del GM y el resto de registros. Vuelve cuando su autor actualiza a la 2.0 y lo firma otra vez. Hasta entonces verás menos perfiles y squads.
- **Aviso de versión vieja**, solo para ti y una vez por sesión: «Guild Squads: N miembros usan una versión anterior a la 2.0 y no se sincronizan contigo hasta que actualicen». En el otro sentido, la 1.2.2 ya avisa: «Hay una versión nueva de Guild Squads (2.0) en tu guild: actualiza.».
- **Arreglado: las invitaciones de raid.** «Invitar confirmados», «Invitar al grupo» del menú de miembro y la invitación del squad van a «Nombre Apellido». Antes iban a «Nombre-Reino», que WoW Forever no encuentra. En «Invitar confirmados», a quien no sale en la lista de la guild no se le invita, y el addon te dice cuántos se han quedado fuera.
- **Arreglado: los kills en grupo ya cuentan.** En grupo (no en banda), el addon leía el apellido de tus compañeros como si fuera el reino («Kas-Pitas»), así que los presentes en un jefe o un campo de batalla no casaban con nadie: no les contaban las carreras del Salón de la fama ni la presencia en el squad. Ahora salen como «Kas Pitas» y cuentan.
- **Nombres tecleados:** `/gsq trust reset <Nombre Apellido>`, invitar a tu squad por nombre, la lista de RL y la concesión de insignias aceptan el nombre con apellido. No distinguen mayúsculas (solo en letras sin tilde) y también aceptan «Nombre-Apellido», como en los enlaces del chat. El nombre de pila solo basta si en la guild hay un único personaje con ese nombre; si hay dos «Kas», el addon te pide el apellido. Si no coincide nadie, te dice «Nadie Nunca no está en la guild».
- **En la interfaz** cada personaje sale como «Nombre Apellido», nunca con «-Reino»: listas y banquillo, capitán, menús, tooltips, convocatorias, Salón de la fama, catálogo, celdas de banda y exportación a Discord. Si un nombre largo no cabe, se corta solo a la vista; el nombre no se acorta.
- `/gsq diag`: líneas nuevas `id mode=forever me=Nombre Apellido surname=yes` y `proto v=3 old=N` (los miembros oídos con la 1.x).
- Fuera de WoW Forever (si el cliente no tiene `RegionalUniqueNamesEnabled` o devuelve false), la 2.0 sigue con los nombres «Nombre-Reino» de la 1.2.2, con el protocolo 3.
- **Arreglado (revisión de seguridad): un nombre escrito de otra forma ya no se cuela como otro miembro.** «ann oak», «Ann-Reino», «Ann» o «Ann Oak-X» apuntan a Ann Oak en la lista de la guild, pero no son su identidad. Dos cómplices podían certificar una clave para una de esas formas y colar un perfil o un squad que salía como si fuera del GM (pasaba ya en la 1.2.x). Ahora todo nombre que llega dentro de los datos tiene que ser exactamente «Nombre Apellido»: el autor y los nombres de cada registro, las claves, los manifiestos, los certificados, el destinatario de los mensajes que van por la guild y lo que hay guardado. Si no lo es, se descarta (nunca se corrige) y `/gsq diag` lo cuenta en la línea `id` (`alias=N`, con el primero).
- **Arreglado: la sesión ya no se queda sin migrar** si el cliente da el modo de WoW Forever tarde (falso al cargar el addon y verdadero al entrar) y la lista de la guild llega entre medias. La lista se lee con el modo definitivo y la migración corre entonces.
- Un nombre tecleado raro («Kas Pitas -Reino») da la misma identidad que bien escrito. Rechazar a alguien que no está en la guild ya no guarda nada. «Susurrar» nunca abre `/w` con «-Reino». Las observaciones de jefes guardan entero el «nombre>squad» de los nombres largos.
- **Límites conocidos:**
  - Algunos datos locales antiguos que llevan nombres dentro no pasan a la identidad nueva: las instantáneas de los miembros de cada wipe, los logros ya ganados, los niveles conocidos, las carreras cerradas y los ids de anulaciones y confirmaciones que incluyen un nombre. Si llevan nombres de la 1.x, se quedan desfasados, sin errores.
  - Sin medir todavía en el juego: invitar o susurrar a «Nombre Apellido» de otro reino conectado. Si el servidor no lo encuentra, el aviso se oculta y el mensaje va por el canal de la guild. Tampoco está medido por nosotros el formato del remitente (lo midieron otros addons): si llega sin apellido y hay dos personajes con ese nombre de pila, el mensaje se descarta y `/gsq diag` lo cuenta en `peers notInRoster=`.
  - Si un susurro del addon llegara con el remitente sin apellido («Ann») y en la guild hay un solo «Ann», el addon lo toma por ella. Los addons que lo midieron ven siempre «Nombre Apellido»; lo confirmará la prueba en el juego.
  - Sin medir: `UnitInRaid` con «Nombre Apellido» de otro reino. Si solo aceptara el nombre de pila, «Invitar confirmados» volvería a invitar a quien ya está en el grupo.
  - Las letras con tilde no se comparan sin mayúsculas: «KÁS PÍTAS» tecleado no casa con «Kás Pítas». Escribe el nombre como sale en la guild. Nunca se susurra a la forma mal escrita.
  - Si ningún miembro de la lista de la guild trae apellido, no se sincroniza nada (`/gsq diag`: `entries=0`) y la migración quita de los datos locales los nombres que no puede resolver.
  - Caso raro de la migración: si un alt tuyo ya no está en la guild y otro personaje es el único de su reino con ese nombre de pila, los registros del alt quedan a nombre del otro en espera y no se envían nunca.
  - Un personaje de WoW Forever sin guild no crea su clave y lo vuelve a comprobar en cada fotograma (coste pequeño, sin medir).
  - Para desarrollo: la regla IDENTITY de `tests/gates.js` no ve una evasión a propósito (`_G["Unit".."Name"]`, un alias local de `ns`); la lista de la guild arma «Nombre Apellido» por su cuenta, sin `ns.id` (solo difiere con formas absurdas como «Kas-R Pitas-X»); S17v2 no exige `old=2` a Mb1, que recarga y después solo oye a un cliente viejo.

### EN

- **⚠️ The whole guild has to update.** 2.0 speaks protocol 3 and signs with new tags. It receives nothing from 1.x (1.0.x, 1.1 and 1.2.x), and 1.x receives nothing from 2.0. There are no errors: each one ignores the other. Until everyone updates, the guild is split into two networks.
- **Every character is «Name Surname».** In WoW Forever the full name with the surname is unique in the region. 2.0 uses it for everything: author of your data, signing key, certificates and whisper target, always without "-Realm", also on connected realms. **Fixed: two characters of the same realm with the same first name** ("Kas Pitas" and "Kas Mora") are now two different people, each with their own profile, key and squad. 1.2.2 ignored both.
- **Your data moves to the new identity by itself.** When you log in with 2.0, your profile, your squad and the rest of your records are signed again as «Name Surname», with a new key; the old one is deleted. Your alts' data is not lost: it waits until you log in with each alt. Other players' keys and certificates are learned again in person.
- **What others signed with 1.x is removed from your client:** profiles, squads, the GM's settings and every other record. It comes back when its author updates to 2.0 and signs it again. Until then you will see fewer profiles and squads.
- **Old-version notice**, only for you and once per session: "Guild Squads: N members use a version older than 2.0 and do not sync with you until they update". The other way round, 1.2.2 already warns: "There is a new version of Guild Squads (2.0) in your guild: please update.".
- **Fixed: raid invites.** "Invite confirmed", "Invite to group" in the member menu and the squad invite go to «Name Surname». They used to go to "Name-Realm", which WoW Forever does not find. With "Invite confirmed", someone missing from the guild roster is not invited, and the addon tells you how many were left out.
- **Fixed: group kills count now.** In a party (not a raid), the addon read your mates' surname as if it were the realm ("Kas-Pitas"), so the players present at a boss or a battleground matched nobody: the Hall of Fame races and the squad presence did not count for them. They now come out as "Kas Pitas" and count.
- **Typed names:** `/gsq trust reset <Name Surname>`, inviting to your squad by name, the RL list and badge grants take the name with the surname. They ignore case (only for letters without accents) and also take "Name-Surname", as in chat links. The first name alone is enough only when a single guild character has it; with two "Kas", the addon asks for the surname. When nobody matches, it says "Nobody Never is not in the guild".
- **In the interface** every character shows as «Name Surname», never with "-Realm": lists and bench, captain, menus, tooltips, squad calls, Hall of Fame, catalog, raid cells and the Discord export. A long name that does not fit is cut only on screen; the name itself is never shortened.
- `/gsq diag`: new lines `id mode=forever me=Name Surname surname=yes` and `proto v=3 old=N` (the members heard on 1.x).
- Outside WoW Forever (a client without `RegionalUniqueNamesEnabled`, or where it returns false), 2.0 keeps the 1.2.2 "Name-Realm" names, with protocol 3.
- **Fixed (security review): a name spelled another way no longer passes for another member.** "ann oak", "Ann-Realm", "Ann" or "Ann Oak-X" point to Ann Oak in the guild roster, but they are not her identity. Two accomplices could certify a key for one of those spellings and slip in a profile or a squad that showed as the GM's (this already happened in 1.2.x). Now every name that arrives inside the data has to be exactly «Name Surname»: the author and the names of each record, keys, manifests, certificates, the recipient of the messages that go over the guild channel and what is saved. Otherwise it is dropped (never corrected) and `/gsq diag` counts it on the `id` line (`alias=N`, with the first one).
- **Fixed: the session no longer stays unmigrated** when the client gives the WoW Forever mode late (false when the addon loads, true at login) and the guild roster arrives in between. The roster is read with the final mode and the migration runs then.
- An oddly typed name ("Kas Pitas -Realm") gives the same identity as a well typed one. Rejecting someone who is not in the guild no longer stores anything. "Whisper" never opens `/w` with "-Realm". Boss observations keep the "name>squad" of long names whole.
- **Known limits:**
  - Some old local data with names inside does not move to the new identity: the member snapshots of each wipe, achievements already earned, known levels, closed races and the ids of annulments and confirmations that include a name. If they hold 1.x names, they stay out of date, without errors.
  - Not measured in the game yet: inviting or whispering «Name Surname» on another connected realm. If the server does not find them, the notice is hidden and the message goes over the guild channel. We have not measured the sender format ourselves either (other addons did): if it arrives without the surname and two characters share that first name, the message is dropped and `/gsq diag` counts it in `peers notInRoster=`.
  - If an addon whisper arrived with the sender without a surname ("Ann") and the guild has a single "Ann", the addon takes it as her. The addons that measured it always see «Name Surname»; the test in the game will confirm it.
  - Not measured: `UnitInRaid` with «Name Surname» of another realm. If it only took the first name, "Invite confirmed" would invite again someone already in the group.
  - Letters with accents are not compared without case: "KÁS PÍTAS" typed does not match "Kás Pítas". Type the name as the guild shows it. Nothing is ever whispered to the misspelled form.
  - If no member of the guild roster carries a surname, nothing syncs (`/gsq diag`: `entries=0`) and the migration removes from the local data the names it cannot resolve.
  - A rare migration case: if an alt of yours is no longer in the guild and another character is the only one of its realm with that first name, the alt's records end up waiting under the other one and are never sent.
  - A WoW Forever character without a guild does not make its key and checks again on every frame (small cost, not measured).
  - For development: the IDENTITY rule of `tests/gates.js` does not see a deliberate evasion (`_G["Unit".."Name"]`, a local alias of `ns`); the guild roster builds «Name Surname» by itself, without `ns.id` (it only differs on absurd forms like "Kas-R Pitas-X"); S17v2 does not require `old=2` from Mb1, which reloads and then only hears one old client.

## 1.2.2 — 2026-11-09 — Susurros al nombre con apellido / Whispers to the name with the surname

### ES

- **Arreglado: el chat se llenaba de «No hay ningún jugador con el nombre Kas CAMWOWEU4Realm6PvP.»** En WoW Forever un susurro solo llega al **nombre completo con apellido** («Kas Pitas»; probado por BRO en el juego). La 1.2.1 susurraba a «Kas-Reino», sin apellido, y el servidor no lo encontraba nunca: ni certificados, ni copias, ni registros por susurro. Ahora el destino sale del roster: «Nombre Apellido» en tu reino y «Nombre Apellido-Reino» en otro. La identidad (autor, firmas, certificados) sigue siendo «Nombre-Reino», sin apellido: los datos firmados no cambian.
- **Los avisos del servidor por nuestros susurros ya no salen en el chat.** Si el servidor no encuentra a alguien a quien el addon acaba de susurrar, la línea se oculta, se prueba una vez la otra forma del nombre (con o sin reino) y, si tampoco va, el addon deja de susurrarle 10 minutos y le manda lo suyo por el canal de la guild con su nombre dentro (solo él lo procesa). A quien no está en el roster nunca se le susurra; a quien está desconectado no se le manda nada.
- **Salón de la fama: fuera la pestaña «Otros».** Las carreras de «Puntos de Legado» no funcionan así en WoW Forever y salen del catálogo; «Squad con los 5 titulares al 60» y las carreras de profesión y reputación pasan a la pestaña «Nivel». Los datos guardados de esas carreras se quedan como estaban, pero no puntúan ni se muestran: no se pierde nada más.
- Al cargar se borran las claves, manifiestos y certificados que la 1.2.0 guardó con apellido («Nombre Apellido-Reino»): ya no casaban con nadie e inflaban `keys strong=` del diag.
- El botón «Susurrar» abre `/w Nombre Apellido`, la única forma que encuentra WoW Forever.
- Aviso nuevo, solo para ti y una vez por sesión: «Hay una versión nueva de Guild Squads (2.0) en tu guild: actualiza.», cuando alguien de la guild ya usa la 2.0.
- **Límite conocido: dos personajes del mismo reino con el mismo nombre de pila** (p. ej. «Kas Pitas» y «Kas Mora») comparten la clave interna «Kas-Reino». La 1.2.2 los detecta, no mezcla sus datos y los ignora a los dos (`/gsq diag`: `[roster] … ambiguous=`). **La 2.0** pasará la identidad a «Nombre Apellido», que es única en la región, con un protocolo nuevo.
- `/gsq diag`: línea nueva `whisper` con los avisos ocultados (`notFound=`), quién va con la otra forma del nombre (`alt=`), quién está marcado (`marked=`), los mensajes por la guild con destinatario (`routed=`), los descartados por desconexión (`dropped=`) y las claves de la 1.2.0 borradas (`swept=`).

### EN

- **Fixed: the chat filled with "No hay ningún jugador con el nombre Kas CAMWOWEU4Realm6PvP."** In WoW Forever a whisper only reaches the **full name with the surname** ("Kas Pitas"; tested by BRO in the game). 1.2.1 whispered "Kas-Realm", without the surname, and the server never found it: no certificates, copies or records by whisper. The target now comes from the roster: "Name Surname" on your realm and "Name Surname-Realm" on another one. The identity (author, signatures, certificates) stays "Name-Realm", without the surname: signed data does not change.
- **The server's notices about our whispers no longer reach the chat.** When the server does not find someone the addon just whispered, the line is hidden, the other form of the name (with or without the realm) is tried once and, if that fails too, the addon stops whispering him for 10 minutes and sends his messages over the guild channel with his name inside (only he handles them). Nobody missing from the roster is ever whispered; nothing is sent to someone offline.
- **Hall of fame: the "Others" tab is gone.** "Legacy points" races do not work that way in WoW Forever and leave the catalog; "Squad with the 5 starters at 60" and the profession and reputation races move to the "Level" tab. Saved data of those races stays as it was but is neither scored nor shown: nothing else is lost.
- At load, the keys, manifests and certificates that 1.2.0 saved with the surname ("Name Surname-Realm") are dropped: they never matched anyone and inflated the diag's `keys strong=`.
- The "Whisper" button opens `/w Name Surname`, the only form WoW Forever finds.
- New notice, only for you and once per session: "There is a new version of Guild Squads (2.0) in your guild: please update.", when someone in the guild already runs 2.0.
- **Known limit: two characters of the same realm with the same first name** (e.g. "Kas Pitas" and "Kas Mora") share the internal key "Kas-Realm". 1.2.2 detects them, never mixes their data and ignores both (`/gsq diag`: `[roster] … ambiguous=`). **2.0** will make the identity "Name Surname", unique in the region, with a new protocol.
- `/gsq diag`: new `whisper` line with the hidden notices (`notFound=`), who gets the other form of the name (`alt=`), who is marked (`marked=`), the guild-channel messages with a recipient (`routed=`), the ones dropped because the target is offline (`dropped=`) and the 1.2.0 keys dropped (`swept=`).

## 1.2.1 — 2026-11-09 — Sincroniza con pocos jugadores en la 1.2 / Syncs with few players on 1.2

### ES

- **Arreglado: los susurros del addon iban a «Nombre Apellido-Reino» y se perdían** («No hay ningún jugador con el nombre …» una y otra vez en el chat). En WoW Forever el roster da los nombres con apellido, y con reinos conectados el remitente también; esos nombres se usaban tal cual como clave del autor y como destino de los susurros. Así nunca se casaban la clave, los manifiestos y los certificados con su autor (`sig verified=0`, `cert held=0`), y todo lo que va por susurro (petición y envío de certificados, copias sin verificar, registros de otros) no llegaba. Ahora todo nombre de personaje es «Nombre-Reino», sin apellido.
- **Arreglado: con pocos jugadores en la 1.2 dentro de una guild grande no se sincronizaba casi nada.** Cada nodo decidía si contestar a un hello con la cuenta de **miembros de la guild conectados** (8 / conectados) y, con más de 8 conectados, mandaba solo 2 de 8 partes de lo que te falta. En una guild de 317 con ~60 conectados y 3 en la 1.2, cada uno contestaba ~1 de cada 8 hellos y con una cuarta parte de la diferencia: ni perfiles, ni manifiestos, ni firmas verificadas (`/gsq diag`: `sample=0`, `sig verified=0`). Ahora cuenta **los jugadores con la 1.2** que ha oído en los últimos 20 minutos y siguen conectados (más tú): con 3, todos contestan siempre y con todo lo que falta. Lo mismo para las páginas del Salón de la fama. En el simulador (S19: 300 miembros, 60 conectados, 3 en la 1.2 y 5 en la 1.1), los 3 tienen lo mismo y todo verificado a los 30 s del último login; con la 1.2.0, nada a los 10 min. Igual con reinos conectados (personaje y guild en reinos distintos).
- `/gsq diag`: línea nueva `peers` con los jugadores 1.2 que cuentan (`n=`), los remitentes oídos (`heard=`), cuántos de ellos no aparecen en tu roster (`notInRoster=`, con el primer nombre: si no es 0, hay un desajuste de nombres de reino), los hellos oídos y contestados, y los susurros descartados (`badChannel=`).

### EN

- **Fixed: the addon's whispers went to "Name Surname-Realm" and were lost** ("No player named …" over and over in chat). In WoW Forever the roster gives names with the surname, and so does the sender on connected realms; those names were used as they came, as the author's key and as whisper targets. So keys, manifests and certificates never matched their author (`sig verified=0`, `cert held=0`), and everything that travels by whisper (certificate asks and answers, unverified copies, other people's records) never arrived. Every character name is now "Name-Realm", without the surname.
- **Fixed: with few players on 1.2 in a big guild almost nothing synced.** Each node decided whether to answer a hello from the number of **guild members online** (8 / online) and, with more than 8 online, sent only 2 of 8 parts of what you were missing. In a 317-member guild with ~60 online and 3 on 1.2, each one answered ~1 hello in 8 and with a quarter of the difference: no profiles, no manifests, no verified signatures (`/gsq diag`: `sample=0`, `sig verified=0`). Now it counts **the players on 1.2** it heard in the last 20 minutes who are still online (plus you): with 3, all of them always answer, with everything you lack. The same for the Hall of Fame pages. In the simulator (S19: 300 members, 60 online, 3 on 1.2 and 5 on 1.1), the 3 hold the same data, all verified, 30 s after the last login; with 1.2.0, nothing after 10 min. The same with connected realms (character and guild on different realms).
- `/gsq diag`: new `peers` line with the 1.2 players counted (`n=`), the senders heard (`heard=`), how many of them are not in your roster (`notInRoster=`, with the first name: anything but 0 means a realm-name mismatch), the hellos heard and answered, and the dropped whispers (`badChannel=`).

## 1.2.0 — 2026-11-08 — Todo en P2P, sin repetidor central / Everything P2P, no central relay

La 1.1.0 no llegó a publicarse. De ella, la 1.2 conserva el reenvío P2P, el contador real y el desmentido del autor; el quórum de 2, los capitanes como nodo, el reenvío de oficiales y la lista negra los sustituyen las firmas (abajo). / 1.1.0 was never published. 1.2 keeps its P2P relay, real counter and author denials; the quorum of 2, captains as nodes, officer relays and the blacklist are replaced by signatures (below).

### ES

Cada jugador con el addon es un nodo: perfiles, squads, ajustes, anulaciones, rosters y el resto de registros pasan de cliente a cliente, con la carga repartida entre todos. Ningún jugador, tampoco los oficiales, hace de repetidor central.

- **⚠️ Tiene que actualizar toda la guild.** La 1.2 habla el protocolo 2: no recibe nada de la 1.0.x ni de la 1.1 y ellas no reciben nada de la 1.2 (sin errores, cada uno ignora al otro). Junto al aviso de sincronizado (o 30 s después de oír al primero, si es más tarde), el chat te dice una vez, solo en local, cuántos miembros has oído con una versión vieja: «Guild Squads: N miembros de la hermandad usan una versión antigua y no se sincronizan hasta que actualicen».
- **Aviso de sincronizado**: ponerse al día va en segundo plano, sin bloquear nada, y cuando ya casi no llega nada nuevo (una ronda de hello con ≤ 2 registros, o 60 s sin registros tras la última ronda) el chat dice una vez «Guild Squads: sincronizado (N registros, M pendientes de verificar)»; si siguen goteando, lo dice igualmente al acabar la espera, y como mucho 8 minutos después del primer hello. En una guild de 200 con 40 conectados, el recién llegado tiene el 95 % en unos 4 minutos (medido en el simulador antes de las firmas; con firmas, lo verificado tarda más porque se comprueba una firma por frame).
- **Respuestas repartidas**: cada hello lo contestan unos 8 jugadores (también los oficiales, que ya no contestan siempre), cada uno con una muestra al azar de lo que te falta; lo que ya ha circulado no se repite.
- **Firmas Ed25519 en todos los registros**: cada personaje tiene su clave y firma lo suyo (un manifiesto con el hash de cada registro). Cualquier miembro reenvía cualquier cosa, pero una copia solo se aplica con la firma verificada de su autor; si no, queda **sin verificar**: no cuenta para nada y, si es un perfil, sale en gris en el buscador con un tooltip que dice qué falta. Ya no hay quórum de reenviadores ni sello de oficial. **Arreglado: con dos personajes ya no se puede hacer pasar por verificado un perfil, squad o ajuste falso (H2; la excepción con alts está en los límites conocidos), ni borrar datos de otro con desmentidos falsos (H3)**: un desmentido exige la firma del propio autor.
- **Claves**: la clave se aprende del dueño en persona (WoW garantiza el remitente) y esa **siempre gana**; una clave reenviada nunca sustituye a una oída en persona. La de alguien a quien nunca has oído vale si la certifican 2 jugadores que sí has oído en persona (cada uno da fe de las claves que oyó en persona en los últimos 30 días) y ninguno da otra; así certificada vale para su perfil y los squads que capitanea, pero ajustes, rosters, asistencias y desmentidos piden la clave oída en persona; si hay conflicto, queda **disputada** y no se aplica nada nuevo suyo hasta que lo oyes. Verificar va en cola, una por frame y en pausa en combate.
- **Comandos nuevos**: `/gsq trust newkey` (borra tu clave y crea otra; pide confirmación) y `/gsq trust reset <nombre>` (olvida la clave de un miembro). `/gsq diag`: líneas `keys`, `sig` y `cert`.
- Límites conocidos (README): dos alts oídos en persona pueden certificar una clave falsa de alguien a quien nunca has oído, hasta que lo oyes; un solo alt puede dejarla disputada; WoW no tiene azar criptográfico (la semilla mezcla tiempos de frames e input); la clave privada va en claro en las SavedVariables. La lista negra de la 1.1 (3 desmentidos = 7 días) ya no hace nada con firmas: solo queda en `/gsq diag`.
- Nadie puede dejarte más de 200 registros pendientes a la vez. Límites por remitente: un hello cada 20 s, 20 manifiestos aparcados y 4 rotaciones de clave en cola. Las colas de manifiestos y certificados por verificar tienen un tope total, no por remitente.
- Seguridad: arreglos menores en el rastro de reenvío y en la comprobación del registro de reenviadores. Lo que queda bajo inundación de clientes modificados (turnos de la cola de verificación, desmentidos de copias sin firma, respuestas grandes de puesta al día como mucho cada 25 s y 20 por hora por nombre, reenvío de certificados) está en los límites del README.
- `/gsq diag`: la línea `comm` cuenta los mensajes de versión vieja descartados (`badProto=`).
- **Manifiesto con tope**: cada jugador firma **hasta 180 de sus registros más recientes** (sus datos antes que presencia y desmentidos, y como mucho ~13 KB); los más viejos (p. ej. asistencias antiguas de un GM) solo se aplican oídos al propio autor, y reenviados por otros quedan «sin verificar». Así el manifiesto cabe siempre en un mensaje que los demás pueden recibir.
- Un recién llegado con un solo jugador conectado ve todos los perfiles en cuanto le llegan; los que no puede verificar todavía salen en gris y pasan a verificados en cuanto coinciden las firmas (al oír al autor o a 2 jugadores que certifiquen su clave).
- **Límites conocidos, para la 1.2.1**: manifiestos por páginas firmadas (hoy, tope de 180 registros por autor); la cola de la puesta al día (el 95 % llega en ≤ 4 min, los últimos registros pueden tardar más porque una ronda vacía corta el catch-up).

### EN

Every player with the addon is a node: profiles, squads, settings, annulments, rosters and every other record travel from client to client, with the load shared by everyone. No player, officers included, acts as a central relay.

- **⚠️ The whole guild has to update.** 1.2 speaks protocol 2: it receives nothing from 1.0.x or 1.1 and they receive nothing from 1.2 (no errors, each ignores the other). Together with the synced notice (or 30 s after hearing the first one, if later), chat tells you once, locally, how many guildmates it heard on an old version: "Guild Squads: N guild members use an old version and cannot sync until they update".
- **Synced notice**: catching up runs in the background without blocking anything, and once almost nothing new arrives (a hello round with ≤ 2 records, or 60 s without records after the last round) chat says once "Guild Squads: synced (N records, M pending verification)"; if records keep trickling in, it says so anyway when the wait ends, and at most 8 minutes after the first hello. In a 200-member guild with 40 online, a newcomer has 95 % of it in about 4 minutes (measured in the simulator before signatures; with signatures, the verified part takes longer, since one signature is checked per frame).
- **Shared replies**: each hello is answered by about 8 players (officers too, who no longer always answer), each with a random sample of what you are missing; what has already gone round is not repeated.
- **Ed25519 signatures on every record**: each character has its own key and signs its own records (a manifest with the hash of each one). Any member relays anything, but a copy is applied only with its author's verified signature; otherwise it stays **unverified**: it counts for nothing and, if it is a profile, it shows grey in the finder with a tooltip saying what is missing. There is no relayer quorum and no officer seal any more. **Fixed: two characters can no longer make a forged profile, squad or setting look verified (H2; the exception with alts is in the known limits), nor delete someone's data with forged denials (H3)**: a denial needs the author's own signature.
- **Keys**: a key is learned from its owner in person (WoW guarantees the sender) and that one **always wins**; a relayed key never replaces one heard in person. The key of someone you never heard counts when 2 players you did hear in person certify it (each vouches for the keys it heard in person in the last 30 days) and none lists another; a key certified this way covers their profile and the squads they captain, while settings, rosters, attendance and denials need the key heard in person; on a conflict it is **disputed** and nothing new from it applies until you hear them. Verifies are queued, one per frame, paused in combat.
- **New commands**: `/gsq trust newkey` (delete your key and make a new one; asks first) and `/gsq trust reset <name>` (forget a member's key). `/gsq diag`: `keys`, `sig` and `cert` lines.
- Known limits (README): two alts heard in person can certify a fake key for someone you never heard, until you hear them; a single alt can keep it disputed; WoW has no cryptographic RNG (the seed mixes frame and input timings); the private key is stored in plain text in SavedVariables. The 1.1 blacklist (3 denials = 7 days) does nothing with signatures: it only shows in `/gsq diag`.
- Nobody can leave more than 200 pending records on your client at once. Per-sender limits: one hello per 20 s, 20 parked manifests and 4 queued key rotations. The queues of manifests and certificates to verify have a total cap, not a per-sender one.
- Security: minor fixes to the relay trail and the relayer ledger check. What remains under a flood from modified clients (verify-queue turns, denials of unsigned copies, large catch-up answers at most every 25 s and 20 per hour per name, certificate re-sends) is in the README limits.
- `/gsq diag`: the `comm` line counts the dropped old-version messages (`badProto=`).
- **Capped manifest**: each player signs **up to 180 of their most recent records** (their data before presence and denials, and at most ~13 KB); older ones (e.g. a GM's old attendance) only apply when heard from the author in person, and relayed by others they stay "unverified". The manifest therefore always fits in a message the others can receive.
- A newcomer with a single player online sees every profile as soon as it arrives; the ones it cannot verify yet are grey and turn verified as soon as the signatures match (when it hears the author, or 2 players certify their key).
- **Known limits, for 1.2.1**: signed manifest pages (today, a cap of 180 records per author); the catch-up tail (95 % arrives in ≤ 4 min, the last records can take longer because an empty round ends the catch-up).

## 1.1.0 — no publicada, incluida en la 1.2.0 / never published, included in 1.2.0 — Sincronización P2P sin oficiales / P2P sync without officers

### ES

Guild Squads converge entre todos los que lo tienen instalado aunque no haya GM ni oficiales conectados con el addon, y el contador de instalados cuenta a quien lo tiene aunque no esté conectado.

- **Reenvío P2P de los registros autorales** (perfil, RSVP, testigo, `presence`, el rechazo de una invitación por el propio invitado): cualquier miembro con la 1.1 los reenvía al responder a un hello. Los registros de autoridad (ajustes, squads, anulaciones, jefes, catálogo, rosters, asistencia, confirmaciones, rechazos de solicitudes del capitán y perfiles con traspaso `xferTo`) siguen como antes: solo en directo o reenviados por el GM o un oficial.
- **Quórum de 2**: una versión reenviada por un miembro queda **sin verificar** (gris en el buscador, con «Llegado por X; se confirmará cuando Y se conecte») y no cuenta para nada hasta que llega la misma versión de un segundo reenviador distinto, del capitán de su squad o del propio autor. Dos versiones distintas con la misma firma: no se aplica ninguna hasta que llega el autor.
- **Capitanes como nodo de su squad**: un reenvío del capitán vigente vale como verificado para los perfiles que apuntan a su squad, los RSVP y testigos de los eventos de su squad y los rechazos de invitación a su squad. Un excapitán (tras `xferTo`) deja de serlo.
- **El autor manda y puede desmentir**: su versión en directo gana a cualquier reenvío. Si alguien hace circular una versión con tu nombre que no escribiste, tu cliente la desmiente solo (`repudiate`), desaparece de todos los clientes y se apunta a quien la trajo; con 3 desmentidos un reenviador deja de contar para el quórum durante 7 días.
- **Contador real**: «Guild Squads: X/Y miembros (30 días)» cuenta a quien publicó su `presence` (una vez al día, se guarda y se reenvía) en los últimos 30 días (`adoptDays`). El tooltip dice quién lo tiene y con qué versión; los oficiales ven «El GM no lo tiene instalado» si el rango 0 no lo tiene.
- `/gsq diag`: línea `p2p pend= verified= repudiated= blocked=` con los reenviadores desmentidos.
- **Compatibilidad**: los clientes 1.0.x siguen sincronizando lo suyo sin errores; rechazan los reenvíos de quien no es oficial e ignoran `presence` y `repudiate` como tipo desconocido. **Actualiza a la 1.1 para sincronizar sin oficiales.**

### EN

Guild Squads converges among everyone who has it installed even when no GM or officer with the addon is online, and the installed counter counts players who have it while they are offline.

- **P2P relay of authorial records** (profile, RSVP, witness, `presence`, an invitation declined by the invited player): any 1.1 member relays them in its hello replies. Authority records (settings, squads, annulments, bosses, catalog, rosters, attendance, confirmations, captain rejections of a request and profiles carrying an `xferTo` transfer) are unchanged: live, or relayed by the GM or an officer.
- **Quorum of 2**: a version relayed by a member stays **unverified** (grey in the finder, "Arrived via X; it will be confirmed when Y logs in") and counts for nothing until the same version arrives from a second distinct relayer, the captain of its squad or the author. Two different versions with the same signature: none applies until the author.
- **Captains as nodes of their squad**: a relay from the current captain counts as verified for the profiles pointing at the squad, the RSVPs and witnesses of the squad's events and the declined invitations to the squad. A former captain (after `xferTo`) no longer is one.
- **The author rules and can deny**: the author's live version beats any relay. If someone circulates a version with your name that you did not write, your client denies it on its own (`repudiate`); it disappears from every client and the relayers are counted; with 3 denials a relayer stops counting for the quorum for 7 days.
- **Real counter**: "Guild Squads: X/Y members (30 days)" counts those who published their `presence` (once a day, saved and relayed) in the last 30 days (`adoptDays`). The tooltip lists who has it and which version; officers see "The GM does not have it installed" when rank 0 lacks it.
- `/gsq diag`: line `p2p pend= verified= repudiated= blocked=` with the denied relayers.
- **Compatibility**: 1.0.x clients keep syncing their own records without errors; they refuse relays from non-officers and ignore `presence` and `repudiate` as unknown kinds. **Update to 1.1 to sync without officers.**

## 1.0.1 — 2026-10-26 — Preparing the repository release

### ES

Versión de preparación del repositorio: documentación, textos y traducciones. Sin cambios de lógica.

- **Documentación bilingüe por carpetas**: `docs/en/` y `docs/es/` con los mismos documentos y los mismos nombres (INDEX, PLAYER-GUIDE, GM-GUIDE, ACHIEVEMENTS, ARCHITECTURE, SIMULATOR-RESULTS, RELEASE); cada uno enlaza arriba con su par. Nuevas traducciones: el catálogo de logros, los resultados del simulador y la publicación al inglés, y la arquitectura al español.
- **Diagramas en los dos idiomas**: los 8 diagramas (HTML y PNG) en `docs/en/diagrams/` y `docs/es/diagrams/`, con índice en cada idioma; los ingleses se regeneran desde las fuentes traducidas.
- **README en inglés** (`README.md`) con enlace a **`README.es.md`** en español.
- **Contenido del juego traducido entero (EN/ES)**: logros y carreras de serie, celebraciones y estados. Los nombres de raza de las carreras y del asistente de logros propios salen traducidos (antes, el token crudo: «Nightelf», «Scourge»), igual que «Top N» y los minutos. Los anuncios en el chat de la guild salen en el idioma del cliente que anuncia.
- Correcciones de texto: «Hall of Fame» unificado en inglés, «Every open raid», «Overall» en la descripción de Constancia, «Color» en inglés, títulos de los tests en inglés.
- Comprobación de enlaces de la documentación en la CI (`tests/tools/check-links.js`), el zip no lleva `README.es.md` y las plantillas de incidencias enlazan a la guía del jugador.

### EN

Repository preparation release: docs, texts and translations. No logic changes.

- **Bilingual docs by folder**: `docs/en/` and `docs/es/` hold the same documents under the same names (INDEX, PLAYER-GUIDE, GM-GUIDE, ACHIEVEMENTS, ARCHITECTURE, SIMULATOR-RESULTS, RELEASE); each links to its pair at the top. New translations: the achievements catalog, the simulator results and the release process into English, and the architecture into Spanish.
- **Diagrams in both languages**: the 8 diagrams (HTML and PNG) in `docs/en/diagrams/` and `docs/es/diagrams/`, with an index per language; the English ones are regenerated from translated sources.
- **English README** (`README.md`) linking to **`README.es.md`** in Spanish.
- **In-game content fully translated (EN/ES)**: default achievements, races, celebrations, statuses. Race names in race titles and in the custom achievement wizard are now translated (they showed the raw token, e.g. "Nightelf", "Scourge"), as are "Top N" and minutes. Guild-chat announcements use the language of the announcing client.
- Text fixes: "Hall of Fame" unified in English, "Every open raid", "Overall" in the Consistency description, "Color" in English, test titles in English.
- Docs link check in CI (`tests/tools/check-links.js`), `README.es.md` kept out of the zip, and the issue templates link to the player guide.

## 1.0.0 — 2026-10-26

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
