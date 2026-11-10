# SPEC v2.0.1 — Miembros sin perfil en el Buscador

Petición de BRO (10-nov-2026, 12:58): «En el buscador no se ve a nadie que no haya rellenado el perfil. Quizá
podríamos mostrarlos con un estado "perfil no rellenado" (o un texto mejor). Es una forma de ver quién tiene el
addon puesto aunque no rellene el perfil. Y que se les puedan enviar invitaciones, pero que les obliguen a rellenar
el perfil para unirse.»

Base: `feat/2.0` @ be11d89 (la 2.0.0 publicada es 9415c4f). Rama: `feat/2.0.1-noprofile`. Sin publicar.

## Spec — Guild Squads 2.0.1: «Sin perfil todavía» en el Buscador e invitación con perfil obligatorio

**Objetivo**
Que el capitán vea en el Buscador a todo miembro de la guild que tiene Guild Squads aunque no haya rellenado su
perfil, marcado como «Sin perfil todavía», y pueda invitarlo a su squad; el invitado solo entra en el squad
después de guardar un perfil completo (rol y al menos un objetivo).

**Contexto**

- Hallazgo al leer el código (y comprobado con el simulador, 3 clientes que nunca abren Mi perfil): desde la 1.0
  el cliente publica solo un registro `profile` al entrar (`A.RefreshProfile(true)` con `A.MyProfile()` por
  defecto: `role = "DAMAGER"`, `avail = "00000000"`, `goals = {}`). Así que hoy esos miembros **sí** están en
  `state.profiles`, pero el Buscador los pinta como **«Daño» sin objetivos**, iguales que un perfil rellenado. Con
  el filtro de nivel que viene puesto (tu nivel ±3), a muchos ni se les ve. Eso explica lo que ve BRO: no hay
  forma de distinguir «no ha rellenado nada».
- «Perfil rellenado» ya tiene una definición en el addon: el «!» de la pestaña Mi perfil
  (`A.ProfileIncomplete`): rol principal **y** al menos un objetivo. Esta spec usa esa misma regla, sacada a una
  función pura `M.profileComplete(d)`, para todo.
- `presence` (`Core/P2P.lua`, `X.applyPresence`): registro firmado `{ver, day}` que cada cliente publica una vez al
  día; es lo que cuenta el «Guild Squads: X/Y miembros (N días)». `state.presence` solo guarda presencias
  verificadas (las que llegan por un relevo sin firma verificada esperan en la lista de pendientes, como los
  perfiles).
- Invitación de squad (`Core/Model.lua`): el capitán pone el nombre en `members`/`bench` del registro `squad`
  (firmado por él); la pertenencia efectiva necesita además que el **perfil del invitado, firmado por el
  invitado**, apunte al squad (`M.isMember`). Aceptar = `A.RequestJoin(id)`, que escribe `profile.squad = id`. El
  modelo no exige nada al perfil para listar a alguien, así que invitar a quien no tiene perfil ya funciona en la
  red; lo que falta es la puerta en el lado del invitado.
- Identidad (CONTRIBUTING «WoW Forever names», SPEC-v2.0-identidad): toda identidad es «Nombre Apellido»; un nombre
  de los datos que no sea exactamente la identidad canónica se descarta.

**Alcance**

1. **Quién sale como «Sin perfil todavía»** (modo Jugadores del Buscador), con las mismas exclusiones que hoy (no
   soy yo, no está en un squad, está en la lista de la guild):
   - a) un miembro con perfil **verificado** (`state.profiles`) que no está completo (`M.profileComplete` falso:
     sin rol o sin objetivos), o
   - b) un miembro **sin** perfil verificado ni pendiente pero con **presence verificada** de los últimos
     `adoptDays` días (la misma ventana del contador X/Y).
   - Solo cuenta lo firmado por el propio miembro y verificado: `state.profiles` / `state.presence`, nunca la lista
     de pendientes. El nombre tiene que ser su identidad canónica (`ns.id(name) == name`) y estar en la lista de la
     guild (`ns.roster(name)`). Una presence sin verificar, de alguien fuera de la guild o con un nombre no
     canónico («ann oak», «Ann-Reino») no saca a nadie.
   - Los perfiles que llegan sin verificar siguen como hoy (gris, «sin verificar»), sin cambios.
2. **Cómo se pinta** la tarjeta: nombre en el color de su clase y nivel como siempre, seguido de
   `(Sin perfil todavía)` / `(No profile yet)` en gris (`|cff888888`); sin iconos de rol, sin chips de objetivos y
   sin la insignia de encaje (no hay datos para puntuar). Distinguible del «sin verificar», que pone todo el
   nombre en gris. Tooltip: título «Sin perfil todavía» / «No profile yet» y texto «Tiene Guild Squads pero no ha
   rellenado su perfil. Puedes invitarle a tu squad: para unirse tendrá que rellenarlo.» / «Has Guild Squads but
   has not filled in a profile. You can invite them to your squad: to join they will have to fill it in.».
   Orden: perfiles completos verificados, después los «sin verificar» y al final los «sin perfil»; dentro de cada
   grupo, primero los conectados y después por nombre.
3. **Filtros.** Rol, objetivos y horario dependen del perfil: con cualquiera de ellos activo, los «sin perfil» **se
   ocultan**. Justificación: el filtro dice «busco un tanque» o «que juegue por la tarde»; de alguien sin perfil no
   se sabe, y enseñarlo sería decir que encaja. Clase, nivel y «conectado» salen de la lista de la guild, no del
   perfil: **sí se aplican**, igual que a los demás (filtrar por clase a alguien cuya clase sabemos es verdad, y el
   filtro de nivel viene puesto por defecto: si no se aplicara, al abrir el Buscador saldrían todos los sin perfil
   de cualquier nivel). El pie «N de M jugadores» los cuenta en M.
4. **Invitar.** Clic derecho «Invitar al squad» y el botón principal funcionan con ellos igual que con cualquiera
   (`A.AddMember`, sin cambios en el modelo).
5. **Unirse con perfil obligatorio** (lado del invitado, que es quien firma la aceptación):
   - `A.RequestJoin(id)` (aceptar una invitación y también pedir unirse, son la misma acción) comprueba primero
     `M.profileComplete` del perfil propio guardado. Si no lo está: no escribe nada, devuelve
     `false, "profileIncomplete"`, recuerda el squad (solo en la sesión) y abre Mi perfil con el aviso «Rellena tu
     rol y al menos un objetivo y pulsa Guardar para unirte a «X».». El error dice «para unirte a un squad
     necesitas un perfil con rol y al menos un objetivo».
   - Al **Guardar** (o «Guardar y salir») un perfil completo con un squad recordado que sigue existiendo y me sigue
     listando o está abierto, ese mismo guardado lleva `squad = id` y `reqAt`: **un solo registro**, y la
     aceptación se completa entonces (mensaje «Te has unido a «X».» / «Solicitud enviada»). Si el perfil guardado
     sigue incompleto, se guarda el perfil y la unión sigue esperando.
   - Nada que llegue por la red puede escribir la aceptación: el único camino que pone `squad` en mi perfil son
     mis acciones (`A.RequestJoin`, `A.CreateSquad`, guardar Mi perfil con un squad recordado por una acción mía).
     Un registro `squad` que me lista, aunque llegue mil veces, solo crea la invitación.
6. **Locales ES/EN completos** y **CHANGELOG 2.0.1 ES/EN**. `ns.VERSION` / `.toc` a 2.0.1.

**Fuera de alcance**

- **Protocolo**: sigue `PROTO 3`, sin campos ni tipos de registro nuevos, sin cambios en firmas ni en
  `Core/Model.lua` de validación. No hace falta: «sin perfil» se deduce de registros que ya viajan (profile y
  presence) y la puerta va en el cliente que firma la aceptación. Un 2.0.0 y un 2.0.1 ven el mismo modelo.
- **Que los demás clientes rechacen a un miembro con perfil incompleto** (validar en el modelo): no. Un 2.0.0
  seguiría contándolo y el modelo divergiría entre versiones (los escenarios de convergencia exigen el mismo
  modelo en todos). Lo que se garantiza es que un 2.0.1 nunca firma una aceptación sin perfil completo; quien
  modifique su cliente para saltársela solo consigue lo que ya podía hacer en la 2.0.0 (entrar con un perfil
  vacío), y siempre con su propia firma.
- Cambiar el perfil automático (`role = "DAMAGER"` por defecto) que se publica al entrar: cambiaría lo que ven los
  2.0.0. La 2.0.1 simplemente no lo cuenta como rellenado.
- Crear squad (el capitán no pasa por la puerta), la pestaña Squads y la lista de miembros de la guild.
- Miembros con la 1.x: no tienen presence de la 2.0 y siguen sin salir (otra red, ver 2.0.0).

**Criterios de aceptación** (test en `tests/noprofile_spec.lua` salvo que diga otra cosa)

- [ ] AC1 `M.profileComplete`: `nil`, `{}`, `{role="DAMAGER", goals={}}` (el perfil automático) y `{goals={"raid"}}`
  son incompletos; `{role="TANK", goals={"raid"}}` es completo. `A.ProfileIncomplete()` da lo mismo que
  `not M.profileComplete` del perfil propio (el «!» no cambia de regla).
- [ ] AC2 Buscador (cliente completo): un miembro de la guild con el perfil automático verificado sale una vez,
  con «(Sin perfil todavía)» en su tarjeta, sin rol ni chips ni insignia de encaje, tooltip `L.NO_PROFILE_TIP`; uno
  con presence verificada y sin perfil, igual; uno con perfil completo sale como siempre (sin la marca).
- [ ] AC3 Seguridad: no sale como «sin perfil» (ni de ninguna otra forma) quien solo tiene una presence pendiente
  (llegada por relevo sin firma verificada), una presence de hace más de `adoptDays`, una presence de alguien que
  no está en la lista de la guild, ni una entrada de `state.presence` con un nombre no canónico de un miembro
  («mb9 apmb9», «Mb9 Apmb9-Reino»).
- [ ] AC4 Filtros: con rol, objetivo u horario activos los «sin perfil» no salen; con clase, nivel o conectado se
  aplican como a los demás (sale el que cumple, no el que no). El total del pie los cuenta.
- [ ] AC5 Orden: completos, después «sin verificar», después «sin perfil».
- [ ] AC6 Invitar: `A.AddMember(miSquad, "Sin Perfil")` desde el Buscador funciona y `M.invites` del invitado lo
  lista (el modelo no exige perfil para invitar).
- [ ] AC7 Puerta: con el perfil propio incompleto, `A.RequestJoin(id)` devuelve `false, "profileIncomplete"`, no
  escribe ningún registro (la secuencia `db.seq` no se mueve), no me hace miembro, abre Mi perfil y muestra el
  aviso con el nombre del squad.
- [ ] AC8 Al guardar en Mi perfil un perfil completo, se escribe **un** registro de perfil con el rol, los objetivos
  y `squad = id`: soy miembro (`M.isMember`), la invitación desaparece y el aviso se borra. Guardar un perfil aún
  incompleto no une (`M.isMember` falso) y la unión sigue recordada. «Guardar y salir» hace lo mismo.
- [ ] AC9 La red no fuerza: aplicar desde otro cliente un registro `squad` del capitán que me lista (y repetirlo),
  con mi perfil incompleto, no escribe nada mío ni me hace miembro; un perfil «mío» firmado por otro se sigue
  rechazando (sin cambios).
- [ ] AC10 Con perfil completo, `A.RequestJoin` hace lo de la 2.0.0 (une al invitado o envía la solicitud), sin
  pasar por Mi perfil.
- [ ] AC11 Locales: todas las claves nuevas en enUS y esES (`tests/locales_spec.lua`, incluido `ERR_profileIncomplete`).
- [ ] AC12 Protocolo intacto: `PROTO` sigue 3 y los esquemas de `M.SCHEMA` y de `presence` no cambian (test que
  compara la forma serializada con la de la 2.0.0).
- [ ] AC13 Suite completa verde (`node tests/run.js`), gates (`node tests/gates.js`),
  `npx -y wow-secret-lint@1.10.2 .` limpio, escenarios S2, S11, S20 y S21 PASS, y CI de la rama en verde.
- [ ] AC14 CHANGELOG 2.0.1 ES/EN, versión 2.0.1 en `.toc` y `ns.VERSION`.

**Aislamiento**
Worktree `wt/c-201`, rama `feat/2.0.1-noprofile` desde be11d89. No se toca `feat/2.0` ni `main`; nada se publica
(sin tag, sin release, sin CurseForge).

**Revisor**
Anton (y BRO para el texto y el aspecto en el juego: es un objetivo abierto, solo sube a verificado con su
captura).

**Riesgos / suposiciones**

- Suposición: la regla «rol y al menos un objetivo» es lo que BRO entiende por «perfil rellenado». Un jugador que
  de verdad quiere no marcar objetivos saldrá como «sin perfil» y no podrá unirse sin marcar uno. Es la misma regla
  del «!» que ya ve.
- Un 2.0.0 sigue pudiendo aceptar sin perfil (no tiene la puerta) y sigue viendo a los sin perfil como «Daño».
- El aviso de unión se recuerda solo durante la sesión: tras `/reload` la invitación sigue en Mi squad y se vuelve
  a pulsar Aceptar.
- Sin medir en el juego: el ancho del texto «(Sin perfil todavía)» junto a un nombre largo (se corta a la vista
  como el resto, `oneLine`).
