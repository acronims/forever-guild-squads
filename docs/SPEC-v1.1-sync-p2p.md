# SPEC v1.1 — Sincronización P2P sin depender del GM, capitanes como nodos de su squad y contador de instalados real

**Estado:** aprobada por BRO (7-nov 05:38, «prepara la 1.1 con esto»), con los capitanes como nodos. Versión 1.1.0.
**Pedido por BRO (7-nov 05:10):** «el GM de mi guild no lo ha instalado… cada jugador instalado haga de nodo de actualización… no sale el número correcto de gente que lo tiene… debería funcionar para quien lo instale con los valores por defecto sin depender de que una persona lo active, lo configure o lo maneje». Opciones elegidas: **1 + 2 + contador** (BRO 05:34, «vamos palante con el spec»). **BRO 05:38:** «en CurseForge tenemos ya la 1.0.1. Prepara la 1.1 con esto. Los capitanes de squad podrían ser nodos de autoridad de sus grupos, ¡sí!». Base: `acronims/forever-guild-squads` v1.0.1 (406029a).

## Objetivo
Que Guild Squads converja entre todos los que lo tengan instalado **aunque no haya GM ni oficiales conectados con el addon**, sin abrir la puerta a que un miembro se invente registros a nombre de otro. Y que el contador «Guild Squads instalado: X/Y» cuente a quien lo tiene aunque no esté conectado.

## Contexto (código actual, 1.0.1)
- `Core/Model.lua:540` `M.provenance`: un registro reenviado (`sender ≠ autor`) **solo se acepta si quien lo reenvía es GM u oficial** (rango 0 o `officerRanks`, por defecto `{1}`). Lo hicimos así en la v0.6.1 (auditoría R06-1) porque el hash de 24 bits era falsificable.
- `Sync.lua:224-230` / `Sync.ReplyFor`: quien no es oficial solo responde a un hello con **sus propios** registros (`onlyAuthor`).
- Consecuencia: sin GM ni oficial conectados con el addon, cada cliente solo tiene lo que cada autor publica mientras coinciden conectados. En la guild de BRO el GM no lo tiene, así que no converge.
- Contador: `UI/Panels.lua:1393` y `UI/Hall.lua:295` usan `Sync.HeardAgo` (`Sync.lua:282-297`): son los jugadores que te han enviado un mensaje del addon **en esta sesión**. Ni se guarda en disco ni cuenta a los desconectados.
- Los ajustes por defecto ya funcionan sin GM (`M.defaultSettings`: squads activados, sin aprobación, `minCreateRank = 9`).

## Alcance
1. **Dos clases de registros:**
   - **Autorales** (solo describen al autor o una decisión suya de jugador): `profile`, `rsvp`, `witness`, `presence` (nuevo), y las solicitudes y salidas de squad de un jugador (`reject` cuando lo emite el propio interesado). Hay que confirmar la lista exacta contra `M.apply` y los `applyFn` de las extensiones; la lista va cerrada en el código (`M.P2P_KINDS`), no se deduce.
   - **De autoridad**: `settings`, `annul`, `boss`, `vconfirm`, `achdef`, `achgrant`, `roster`, `attendance`, y las operaciones de squad que requieren capitán u oficial. **No cambian**: el reenvío sigue siendo solo de GM/oficial (o del autor en directo).
2. **Reenvío P2P de los registros autorales** (opción 1): cualquier miembro de la guild con el addon puede reenviarlos. Cada cliente responde a los hellos también con registros autorales de otros (paginado y con los mismos límites de `MAX_REPLY`).
3. **Quórum de 2** (opción 2): un registro autoral reenviado (`sender ≠ autor`) queda primero como **pendiente**. Se aplica cuando llega **la misma versión** (`vkey`: ts.sq.a + hash del contenido) desde **2 reenviadores distintos, ninguno de ellos el autor**. Si llega del propio autor, se aplica en el momento. Los pendientes caducan a los 7 días, con un máximo de 2000 en memoria y en disco.
   - *Arranque en frío:* en una guild con 2 instalados, el quórum nunca se cumple para los registros del ausente. Solución: con un solo reenviador se muestra igual, marcado como «sin verificar» (gris, tooltip «Llegado por <relayer>; se confirmará cuando <autor> se conecte»), y **no cuenta** para rankings, Tops ni celebraciones hasta que haya quórum o lo confirme el autor.
3b. **Capitanes como nodo de autoridad de su squad** (BRO 05:38): un registro reenviado por **el capitán vigente del squad al que pertenece el registro** se acepta como verificado sin quórum. Aplica a los perfiles que apuntan a su squad (`profile.d.squad == sid`), los RSVP, la asistencia y los testigos de los eventos de su squad, y los `reject` de su squad. El capitán vigente es el `captain` del registro `squad` que ya tiene el receptor, sin `disbanded` y tras aplicar `xferTo`. El capitán **no** gana autoridad sobre registros de otros squads ni de autoridad de guild (settings, annul, boss, catálogo). Si el receptor aún no conoce el squad, el reenvío del capitán cuenta como 1 reenviador normal para el quórum.
4. **El autor manda y puede desmentir:**
   - La versión del autor en directo siempre gana a cualquier reenvío (ya pasa por `ts` y versión; hay que asegurarlo con un test).
   - Nuevo registro `repudiate {id, vkey}`: solo lo acepta quien lo recibe del propio autor en directo, o reenviado con quórum de 2. Borra esa versión en todos los clientes y apunta los reenviadores que la trajeron (`Sync.stats.repudiated[relayer]++`). Un cliente que reciba un registro autoral con la firma de contenido de otro jugador, y que no coincida con el que tiene el autor cuando se conecta, emite el desmentido automáticamente (sin UI).
   - Lista negra local: un reenviador con 3 o más desmentidos deja de contar para el quórum en ese cliente durante 7 días (se ve en `/gsq diag`).
5. **Contador real de instalados:** nuevo registro autoral `presence {a, ver, day}`, que cada cliente publica al entrar y como máximo una vez al día. Se reenvía en P2P (con quórum como los demás), se guarda en SavedVariables y lo podan los clientes cuando el jugador sale de la guild o pasan 60 días.
   - Contador = miembros del roster con `presence` en los últimos **30 días** (configurable: `adoptDays`, por defecto 30). El texto pasa a ser «Guild Squads: X/Y miembros (30 días)», con un tooltip que lista quién lo tiene y su versión.
   - Una línea «El GM no lo tiene instalado» (solo la ven los oficiales) si el rango 0 no tiene `presence`.
6. **Compatibilidad:** los clientes 0.10.x rechazarán los reenvíos de quien no es oficial («relay») y no conocen `presence` ni `repudiate`, que ignorarán como tipo desconocido sin errores. La 0.11 converge entre clientes 0.11. Aviso en el changelog y en la UI: «Actualiza para sincronizar sin oficiales».

## Fuera de alcance
- Firmas criptográficas (opción 4).
- Cambiar quién puede tomar decisiones de autoridad.
- Tocar el protocolo de los registros de autoridad.
- Nuevas opciones de configuración para el GM, salvo `adoptDays`.

## Criterios de aceptación (cada uno con su test en `tests/`, en el simulador cuando haga falta)
- [ ] AC1: en una guild simulada **sin GM ni oficiales con el addon**, con 5 clientes 0.11 que se conectan escalonados (nunca más de 2 a la vez), los registros autorales de todos llegan a todos en ≤3 sesiones solapadas. Simulador: `sim-out`, con convergencia del 100 % de los registros autorales.
- [ ] AC2: un registro autoral falso (autor X, inventado por Y) llega a los demás como «sin verificar» y **no** puntúa. Con un solo reenviador malicioso, nunca pasa a verificado.
- [ ] AC3: dos reenviadores distintos con la misma versión → se aplica como verificado. Dos versiones distintas → ninguna se aplica hasta que llegue el autor.
- [ ] AC4: cuando el autor se conecta, su versión gana; si había una falsa, se emite el `repudiate` y la falsa desaparece de todos los clientes de la simulación; el reenviador sale en `/gsq diag`.
- [ ] AC5: los registros de autoridad reenviados por quien no es oficial siguen rechazados («relay»). Es un test de regresión de R06-1.
- [ ] AC5b: el capitán de A reenvía el perfil de un miembro de A → verificado al momento. El capitán de A reenvía un perfil o un RSVP de B → cuenta solo como 1 reenviador (no verificado). Un excapitán (tras `xferTo`) deja de ser nodo.
- [ ] AC6: el contador cuenta a un instalado que no está conectado (presence de hace 3 días) y no cuenta a quien lleva 31 días sin presence. El tooltip lista quién lo tiene, y la línea del GM sale cuando el rango 0 no lo tiene.
- [ ] AC7: un cliente 0.10 en la misma guild no da ningún error de Lua (BugSack limpio) y sigue sincronizando lo suyo.
- [ ] AC8: carga en el canal: con 40 clientes en el simulador, los mensajes por minuto de un cliente no superan en más de un 30 % a los de la v0.10 (con el mismo `MAX_REPLY` y la misma cola), y nunca chocan con el bloqueo de combate y encuentro.
- [ ] AC9: la batería actual de tests sigue en verde. CHANGELOG ES/EN y `/gsq diag` con `p2p pend= verified= repudiated= blocked=`.

## Aislamiento
- Rama `feat/v1.1-sync-p2p` en `acronims/forever-guild-squads` (desde la v1.0.1), en un worktree propio y sin tocar `main` hasta el OK.
- Commits **sin atribución** (regla de BRO).
- Release beta en CurseForge **solo con el GO de BRO**.

## Revisor
Un agente QA distinto del que lo construye (juez a ciegas) y Anton. La prueba en el juego la hace BRO con 2-3 jugadores de su guild.

## Riesgos / suposiciones
- **Ventana de suplantación:** con un solo reenviador, un registro falso se ve como «sin verificar» hasta que el autor se conecta. Lo aceptamos porque no puntúa.
- **Guilds diminutas:** sin quórum posible, casi todo lo de los ausentes queda «sin verificar». Es lo correcto, pero hay que explicarlo en el tooltip.
- **Tamaño de SavedVariables:** los pendientes y las presences suman. Hay que medirlo en el simulador con 200 miembros.
- **Suposición que puede ser falsa:** que los tipos autorales nunca dependen de la autoridad de otro. Si alguno lo hace (por ejemplo, una solicitud de squad cuya validez depende del capitán), ese tipo se queda en autoridad. Hay que revisarlo antes de codificar.
- **Versiones mezcladas:** mientras la guild no actualice, la 0.10 sigue como hasta ahora.

## Estimación
Unos 2 días: spec cerrada, código, tests y simulador, más una ronda de QA. Después, la beta y la prueba de BRO en el juego.
