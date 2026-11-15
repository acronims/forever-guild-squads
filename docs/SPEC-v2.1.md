# SPEC v2.1 — Datos locales en la identidad nueva, compatibilidad con la 2.0.0 y lo que quedó de la 2.0.1

Orden de BRO (15-nov-2026, 17:05): «tira millas a 2.1». Decisión de BRO (15-nov, 17:06): **la 2.0.1 no se publica
sola**; sale dentro de la 2.1. La 2.1.0 incluye todo `release/2.0.1` (carreras por raza, «Sin perfil todavía» y los
arreglos de su revisión a ciegas) y lo de esta spec.

Base: `release/2.0.1` @ 9cd7a59 (verde: unidad 477/477, gates, matriz del simulador; `wt/agents/gsq-201-fix.md`).
Rama: `feat/2.1`, worktree `wt/c-21`. Sin push, sin tag, sin CurseForge.

## Spec — Guild Squads 2.1.0

**Objetivo**
Que lo que un jugador ya tenía guardado antes de la 2.0 (Salón de la fama, logros, historial de wipes, anulaciones
del GM) siga siendo suyo con la identidad «Nombre Apellido», que la 2.1 conviva sin romper nada con quien sigue en la
2.0.0, y cerrar los avisos pequeños que dejaron las revisiones D (2.0) y la de la 2.0.1.

**Contexto (fuentes del backlog)**

- `STATE.md` (Anton): «Límites conocidos para la 2.1: snap/ach/lvKnown/closed sin remapear y los bajos de la revisión
  D (CHANGELOG)».
- `CHANGELOG.md`, 2.0.0, «Límites conocidos», 1.ª viñeta: «las instantáneas de los miembros de cada wipe, los logros ya
  ganados, los niveles conocidos, las carreras cerradas y los ids de anulaciones y confirmaciones que incluyen un
  nombre … se quedan desfasados». Lo mismo en `wt/agents/g20-b.md` («Límites y pendientes») y `g20-integ.md`
  («Límites y lo que queda»). Por lectura de código (`Core/Model.lua` step1, 9cd7a59): la migración remapea
  `progress.events`, `progress.hkState`, `progress.pending`, `races.obs`, `races.pend`, `races.hkBase` y `races.sent`,
  pero **no** `progress.snap`, `progress.ach`, `progress.lvKnown`, `races.ach`, `races.closed`, `races.rcache`,
  `races.rseen` ni `races.hello`; y `fixOwn` no toca `annul` ni `vconfirm`. Consecuencias deducidas (se prueban en
  AC1-AC4): los wipes cerrados pierden a los miembros (`P.memberAt` busca «Kas Pitas» en una instantánea con
  «Kas-Reino»), los logros ya ganados se vuelven a dar como nuevos con el nombre nuevo, las filas de carreras cerradas
  siguen con el nombre viejo y una anulación del GM sobre una entrada de personaje deja de anular.
- Revisión D (`wt/agents/g20-d.md` §3, bajos) y `g20-fix.md`: A1, M1, B2, B4, B8 y B10 arreglados en la 2.0.0; B1, B3,
  B5, B6, B7, B9 y B11 quedaron como «límites conocidos» del CHANGELOG 2.0.0.
- Revisión de la 2.0.1 (`wt/agents/review-2.0.1.md`): H1, H2, H3, H5, H6 y H8 (UI.Open doble y 2.º argumento)
  arreglados (`gsq-201-fix.md`). Quedan los 🟡 **H4** (razas de PNJ con un solo informante), **H7** (cubos del Salón en
  guilds mixtas), **H8** (tope de 30 opciones del desplegable de razas del GM) y los «Huecos de tests» 2, 3, 5, 6 y 7
  (desplegable de razas, reintento de `H.RaceTable`, escenario mixto de versiones, AC12 que solo vigila 2 esquemas,
  nada pintado en esES).
- `wt/agents/hotfix-121.md` («Pendiente / decisiones», última viñeta): restos «Nombre Apellido-Reino» en las
  SavedVariables (claves, manifiestos, certificados) que inflan `keys strong=` y entran en el certificado propio
  (`C.own` recorre `tdb.keys`).
- `NOCHE-backlog.md`: todo lo de la cola está hecho o descartado; lo único abierto, R11 (resúmenes de wipe
  replicables por oficial), cambia el protocolo y quedó descartado el 21-oct («no merece la pena»). No entra.
- Decisión de BRO: compatibilidad a probar **2.0.0 ↔ 2.1** (la 2.0.1 nunca llegó a los jugadores).

**Alcance** (por prioridad: primero lo que puede romper datos o la sincronización, después lo que se ve en el juego,
por último la limpieza)

*A. Datos y sincronización*
1. Remapear a «Nombre Apellido» los datos locales por nombre que la migración de la 2.0 dejó: `progress.snap`,
   `progress.ach`, `progress.lvKnown`, `races.ach`, `races.rcache`, `races.rseen`, `races.hello`.
2. Las filas de las carreras cerradas (`races.closed`): nombres remapeados en local y también al importar una fila de
   un compañero (los 2.0.0 la siguen sirviendo con el nombre viejo), para que todos los 2.1 tengan el mismo texto.
3. Una pasada única para quien ya migró con la 2.0.0 (marca nueva en la partición), que aplica 1, 2 y 4.
4. Anulaciones (`annul`) y confirmaciones (`vconfirm`) propias con un nombre viejo dentro: se vuelven a firmar con
   el nombre y el id nuevos.
5. Restos «Nombre Apellido-Reino» de la 1.2.0 (hotfix-121): ni en `keys strong=` ni en el certificado propio.
6. H4: una raza que solo da la tabla del cliente (posible raza de PNJ) no abre carrera con un solo informante.
7. Escenario del simulador 2.0.0 ↔ 2.1 (hueco 5 y H7) y un test que fije el formato del cable (hueco 6).

*B. Lo que se ve en el juego*
8. Tarjeta «(Sin perfil todavía)», su tooltip y el aviso de unirse pintados en esES (hueco 7).
9. H8: el desplegable de razas del GM no pierde razas sin avisar (hueco 2).
10. B3: los nombres tecleados casan sin mayúsculas también con tildes y eñes («KÁS PÍTAS» → «Kás Pítas»).

*C. Limpieza*
11. Test del reintento de `H.RaceTable` (hueco 3).
12. B7: un personaje de WoW Forever sin guild no recalcula su clave en cada fotograma.
13. CHANGELOG: una sola sección **2.1.0** en ES y EN que recoge también lo de la 2.0.1 (sin sección 2.0.1 suelta);
    guías si cambia algo que describen.

**Fuera de alcance**

- El Hall retroactivo (aparcado por BRO).
- Cualquier cambio del protocolo: sigue PROTO 3, mismos tipos de mensaje, mismos esquemas firmados. Si algún punto lo
  exigiera, se para y se escala (ver Riesgos).
- B1 (exigir el remitente completo en susurros): sin medir en el juego cómo llega el remitente; endurecerlo a ciegas
  puede cortar todos los susurros. B11 (`InviteUnit`/`UnitInRaid` a otro reino) y la longitud de «(Sin perfil
  todavía)» con nombres largos: solo se pueden medir en el juego.
- Recordar la unión pendiente tras `/reload` (exigiría guardar algo nuevo en las SavedVariables; no lo ha pedido nadie).
- B5, B6 y B9 (simulador, gate estático y una forma absurda de nombre): sin efecto para los jugadores.
- R11 del backlog nocturno (cambia el protocolo).
- La raza de los miembros sin addon (la lista de la guild no la trae).
- Publicar, etiquetar, empujar o tocar `release/2.0.1`.

**Criterios de aceptación** (cada uno con un commit rojo con el test y otro verde con el arreglo, salvo los marcados
«solo test», que vigilan algo que ya funciona y no pueden tener rojo honesto)

A. Datos y sincronización
- [ ] **AC1** `migration_spec`: tras migrar el fixture 1.2.2, `progress.snap`, `progress.ach.char`, `races.ach.char`,
  `progress.lvKnown`, `races.rcache`, `races.rseen` y `races.hello` no tienen ninguna clave ni nombre con «-» que tenga
  identidad; «Kas-Realm» pasa a «Kas Pitas», un nombre ambiguo o sin identidad se quita. Los ids de squad
  («Kas-Realm:1795001009») no se tocan (son opacos). `P.memberAt` sobre la instantánea migrada da `true` para «Kas
  Pitas» en su squad del wipe cerrado. `P.mergeAchievements` con los logros recalculados bajo el nombre nuevo no
  devuelve ninguno como nuevo (no se vuelven a anunciar).
- [ ] **AC2** `migration_spec`: una fila de `races.closed` con «Kas-Realm» en `key`, `chars` y `sup` queda con «Kas
  Pitas» tras migrar; `R.importClosed` de un texto con nombres viejos guarda el mismo texto que un cliente que migró
  (mismo `R.packClosed`, mismo hash de cubo). Un nombre sin identidad se queda como está (no se quitan filas: el Top
  cerrado no cambia de tamaño).
- [ ] **AC3** `migration_spec` + fixture nuevo `tests/fixtures/sv-2.0.0.lua` (el 1.2.2 migrado por el código del tag
  v2.0.0, generado por `tests/tools/make-sv-200.js`): al cargar con la 2.1, una sola vez (marca `g.idv21`), quedan
  remapeados los datos de AC1, AC2 y AC4; dos pasadas dan los mismos bytes; el modo dry de `/gsq diag` cuenta y no
  escribe; en modo realm no hace nada.
- [ ] **AC4** `migration_spec`: una anulación propia del GM sobre una entrada de personaje («lvl.all.10|Kas-Realm»)
  sale con `d.key = "Kas Pitas"`, `id = "lvl.all.10|Kas Pitas"`, `sq` mayor y en espera de firma; una sobre una
  carrera de squad no cambia (el id de squad es opaco). Un `vconfirm` propio de una observación remapeada sale con el
  id nuevo de la observación. Después, `R.place` con esa anulación deja fuera a «Kas Pitas».
- [ ] **AC5** (solo test si ya pasa) `peers_spec`/`canon_spec`: con «Ann Oak-Realm» y «Kas Pitas-Realm» en
  `trust.keys` (strong), `sig.man` y `cert.crt` de una partición ya migrada, tras cargarla `keys strong=` del diag no
  los cuenta y `C.own` no los certifica, en modo forever y en modo realm.
- [ ] **AC6** `race_races_spec`: con `ctx.raceOk` de la tabla del cliente que incluye «Naga_», un solo informe propio
  de un miembro cuyo perfil firmado no es Naga_ no abre `lvl.race.NAGA_.10`; Skyborne (raza de un perfil firmado de
  la guild o la raza propia) sí la abre con un informante; las 17 de `R.RACE_OK` siguen igual.
- [ ] **AC7** Simulador `S25` (nuevo, `tests/sim/scenarios_b.js`): Gm y Mb1 con el código del tag v2.0.0, Mb2 y Mb3
  con la 2.1, WoW Forever, firmas reales. 0 errores de Lua; perfiles, squads y ajustes del GM llegan en los dos
  sentidos; un 2.0.0 que acepta con el perfil vacío entra en el squad visto desde los 2.1; las carreras comunes del
  Salón cuadran; con una carrera de Skyborne cerrada solo en los 2.1 (H7), se mide el tráfico extra de Salón por
  hello y no hay ninguna carrera distinta fuera de esa. Y `proto3_spec`: `M.PROTO == 3` y la huella de **todos** los
  esquemas (`M.SCHEMA`, `R.SCHEMA` y los tipos de mensaje) es la de la 2.0.0 (constante calculada sobre v2.0.0).

B. Lo que se ve en el juego
- [ ] **AC8** (solo test) `noprofile_spec` en esES: la tarjeta lleva «(Sin perfil todavía)», el tooltip «Tiene Guild
  Squads pero no ha rellenado su perfil», y el aviso de Mi perfil «Rellena tu rol principal y al menos un objetivo…»
  con el nombre del squad y el enlace «Cancelar»; ninguna cadena sale en inglés ni como clave.
- [ ] **AC9** `catalog_ui_spec`: con una guild de 12 razas propias (Skyborne ×2 incluidas) más las 17 de
  `R.RACE_OK`, el desplegable de razas del logro de nivel ofrece todas, sin repetir y con las de la guild primero.
- [ ] **AC10** `identity_spec`: `ns.id` de un nombre tecleado casa sin mayúsculas con letras latinas con tilde, diéresis
  o eñe (Á/á … Ñ/ñ, Ü/ü, Ç/ç): «KÁS PÍTAS» y «kás pítas» → «Kás Pítas», «ÑANDÚ ÉBANO» → «Ñandú Ébano». Sigue: un nombre
  que llega dentro de los datos tiene que ser exactamente la identidad (`ns.isCanon`: «kás pítas» es alias), y dos
  miembros que solo difieren en mayúsculas dan nil (ambiguo), nunca otro.

C. Limpieza
- [ ] **AC11** (solo test) `race_races_spec`: `H.RaceTable` con la API vacía al arrancar se vuelve a leer cuando
  responde (a los 10 s o al aparecer) y entonces abre la carrera de Skyborne.
- [ ] **AC12** `periphery_spec`: un personaje de WoW Forever sin guild llama a la generación de clave como mucho una vez
  por segundo en el `OnUpdate` (hoy, en cada fotograma).
- [ ] **AC13** Suite y CHANGELOG: `node tests/run.js` completo en verde, `node tests/gates.js` OK, `wow-secret-lint`
  0/0, matriz de `gsq-razas-rel-ci.sh` (S1 S3 S4 S5, S2 S6, S7, S8, S9 ×3, S19, S19 --realm, S16d S20-S24) más S25 en
  verde, en un contenedor aparte. `CHANGELOG.md` con una sola sección «2.1.0 — sin publicar» ES/EN que incluye la
  2.0.1; `node tests/tools/check-links.js` 0 rotos.

**Aislamiento**
Rama `feat/2.1` en `wt/c-21` desde 9cd7a59. No se toca `release/2.0.1` ni ninguna otra rama. Las simulaciones largas
y la suite completa corren en un contenedor `node:22-slim` aparte (Portainer), que se borra al terminar.

**Revisor**
Anton (o un revisor a ciegas que él lance). El constructor (gsq-21) no juzga su propio trabajo: lo que entrega es
`reportado`.

**Riesgos / suposiciones**

1. **SavedVariables (AC3, riesgo principal).** Campo nuevo `g.idv21` en la partición de la guild. No cambia el formato
   de nada que ya existe. Migración probada con un fixture real de la 2.0.0 (AC3: una vez, idempotente, dry). Si un
   jugador vuelve a la 2.0.0, la marca se ignora y los datos remapeados siguen siendo válidos para la 2.0.0 (usan la
   identidad que ella misma usa).
2. **Protocolo.** Ningún cambio: AC7 lo vigila con la huella de esquemas. AC4 vuelve a firmar registros propios con
   el esquema de siempre (una versión nueva, `sq` + 1), como ya hace la migración de la 2.0. Si algún punto exigiera
   PROTO 4, se para y se escala a BRO.
3. **Carreras cerradas (AC2).** Su texto viaja sin firma entre compañeros y su hash decide los cubos. Con la 2.0.0 en la
   guild, sus filas viejas no cuadran con las remapeadas: solo tráfico (el 2.0.0 nunca sustituye una carrera cerrada
   que ya tiene), igual que H7, hasta que actualice. AC7 lo mide. Suposición: dos 2.1 con el mismo roster remapean
   igual; un miembro que ya no está deja su nombre viejo tal cual en los dos.
4. **AC4.** Solo el GM (o el oficial) que escribió la anulación puede volver a firmarla; hasta que entre con la 2.1,
   la anulación sigue sin efecto en todos. Las versiones viejas que sigan circulando no apuntan a nada.
5. **AC10.** Solo afecta a nombres tecleados: la regla de identidad de los datos (A1) no cambia. Cubre las letras
   latinas de 2 bytes de UTF-8 (U+00C0-U+00DE ↔ U+00E0-U+00FE); otras escrituras siguen como antes.
6. Sin cliente: nada de esto se ha probado en el juego. Lo que depende del juego (B1, B11, Skyborne real) sigue en
   «Límites conocidos».
