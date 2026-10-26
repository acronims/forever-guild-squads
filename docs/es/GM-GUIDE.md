# Guild Squads — Guía del GM, oficiales y RL

English → [GM-GUIDE.md](../en/GM-GUIDE.md)

Para el maestro de la guild (GM, rango 0), los oficiales y los líderes de banda (RL). Lo básico del jugador está en [PLAYER-GUIDE.md](PLAYER-GUIDE.md).

## Quién puede qué

| Quién | Puede |
|---|---|
| **GM** (rango 0) | Cambiar todos los Ajustes y compartirlos; editar cualquier squad; anular y revertir puestos del Salón de la fama; **adaptar el catálogo de logros y carreras y otorgar insignias** (Ajustes > Logros, solo él); marcar el jefe final; cerrar temporadas; editar cualquier roster de banda. |
| **Oficiales** (los rangos que marque el GM) | Aprobar squads nuevos, disolver un squad, restablecer un nombre o escudo ofensivo; liderar bandas; editar rosters ajenos si el GM lo permite. **Reenvían datos** a los que acaban de conectar. |
| **RL** (lista del GM) | Crear, publicar, invitar y cerrar sus bandas. |
| Capitán | Su squad: invitar, aceptar, suplentes, expulsar, ceder la capitanía. |

Los Ajustes los ve toda la guild en solo lectura. Cada cliente comprueba contra el roster de la guild quién firmó cada cambio: un ajuste que no viene del GM se ignora.

## Primeros pasos del GM

1. Instala el addon y abre `/gsq` > **Ajustes**.
2. Repasa las 9 secciones (abajo; **Logros** solo la ves tú). Cambia lo que quieras y pulsa **Guardar y compartir**. Si sales de la pestaña sin guardar, avisa.
3. Pide a tus oficiales que lo instalen: sin GM ni oficial conectado, los jugadores que acaban de entrar solo reciben lo que publican en vivo los autores (ver *Problemas*).
4. Anuncia el addon en la guild. La bienvenida del addon ya les guía (perfil → squad → ranking).

## Ajustes, sección a sección

**Squads.** Rango mínimo para crear squads (por nombre de rango), *Los oficiales deben aprobar los squads nuevos*, suplentes 0–2, qué rangos son oficiales, días hasta "Inactivo" (7/14/30/nunca), máximo de squads (sin límite/10/20/50).

**Competición.** Activar o no, peso de cada categoría (0–3; con 0 la categoría no suma), tope por categoría y wipe (50/100/150/200), objetivo semanal de la guild. El reinicio del wipe (miércoles 09:00 hora del reino) se ve pero no se cambia.

**Temporada.** Nombre, inicio y fin (YYYY-MM-DD HH:MM hora del reino; fin vacío = abierta). **Nueva temporada** cierra la actual ahora y abre otra (pide confirmación). Debajo, las temporadas anteriores. Por defecto: "Temporada 1" desde el 4-nov-2026 09:00.

**Integrac.** Usar Overlord (si está instalado; solo se leen sus capturas, 2 puntos cada una) y si se muestra el aviso que lo recomienda.

**Moderación.** Palabras prohibidas (una por línea, hasta 50). Lista de squads con *Disolver* y *Restablecer nombre/escudo* (GM y oficiales, con confirmación; restablecer deja `Squad <código>` y el escudo por defecto). **Datos**: Exportar, Importar y Sincronizar.

**Celebrac.** *Anunciar en el chat de la guild* — **desactivado por defecto**. *Qué se anuncia*: **Puesto 1**, **Top 3** o **Cualquiera** (cualquier entrada en un Top). *Anunciar también los logros de squad*. Anuncia el protagonista si tiene el addon; si no, el de mayor rango conectado. Anuncia un solo cliente por evento, máximo 1 mensaje cada 10 s, sin enlaces, nunca durante un encuentro. El mensaje del chat de la guild sale en el idioma del cliente que anuncia (inglés o español), así que en una guild mixta el idioma puede cambiar de un anuncio a otro. El aviso dentro del addon sale siempre, en el idioma de cada jugador.

**Contenido.** Catálogo de jefes que se aprende solo (cada jefe se guarda la primera vez que muere con el addon). Marca el **jefe final** de cada mazmorra o banda: sin eso no se abren las carreras de "completar".

**Bandas.** Lista de RL (un personaje de la guild por línea), *Los oficiales pueden editar rosters de otros*, y la tabla de clases útiles (`clave:CLASE+CLASE:tamaño mín.`) que alimenta los avisos de composición. Vacía = valores por defecto. GM y oficiales siempre pueden liderar.

**Logros** (solo la ve el GM). Aquí decides qué reconocimientos usa tu guild. **Cada cambio se comparte al momento** (no hace falta *Guardar y compartir*) y cada cliente vuelve a comprobar que lo firmó el GM: un oficial no puede tocarlo.
- **Grupo** (Nivel, Clase, Raza, Mazmorras, Bandas, PvP, Profesiones, Reputación, Squad, Personaje) y una fila por logro o carrera: casilla (activo), nombre, estado (*abierta n/N*, *cerrada*, *pendiente de datos* o *insignia*), **Top N** y **Renombrar**.
- **Desactivar** oculta el logro o la carrera en el Salón, el Ranking y Mis logros, y no se celebra. **No borra nada**: sigue contando a escondidas y, si lo reactivas, vuelve con todo su historial. Lo que alguien ya había conseguido sale en **Legado** (apagado, con la etiqueta *legacy*): en el Salón, botón *Legado (n)*; en Mis logros y en la tira de Mi squad, al final.
- **Activar todo / Desactivar todo** cambia el grupo elegido; **Global** cambia todo el catálogo. Antes te dice cuántos registros son y cuánto tardan en llegar a todos (1 mensaje por segundo: un "desactivar todo" global puede tardar un par de minutos).
- **Top N**: solo en carreras **abiertas**, de 1 al máximo de su familia (100 en las de nivel general, 10 en el resto, 3 en "contenido completo") y nunca por debajo de las entradas que ya tiene. Una carrera cerrada no se toca (el botón lo explica).
- **Renombrar**: hasta 32 caracteres, sin colores ni enlaces. El identificador interno no cambia; vacío = nombre por defecto.
- **Nuevo logro** (máximo 50): 1) qué mide — nivel (opcional: de una clase o raza), un jefe del catálogo en grupo (≥2 testigos), victorias de squad en BG (en general o en un mapa), habilidad de una profesión, reputación Exaltado, o una **insignia que otorgas tú**; 2) cuál; 3) umbral y tamaño del Top; 4) nombre. Se calcula con los mismos datos y testigos que los de serie. Lo que mide no se puede cambiar una vez creado (sí el nombre, el tamaño y activarlo o no).
- **Otorgar**: elige insignia, personaje (o squad, si es de squad) y **motivo obligatorio**. Sale en el tooltip como *Otorgado por el GM: motivo*. **Nunca mete a nadie en un Top** (los Tops van por quién llegó antes). *Retirar* lo quita y queda en el historial.
- Compatibilidad: un cliente que no conoce un tipo de registro lo ignora sin error (sigue viendo el catálogo de serie).

## Moderar el Salón de la fama

- Clic derecho en un puesto: **Anular** con motivo (solo GM). El siguiente sube y queda historial. *Revertir* lo devuelve a su sitio.
- Los datos que llegan tarde o con saltos raros quedan *no verificados*: solo los confirma un GM u oficial conectado al reenviarlos.
- Un Top lleno se congela; una carrera cerrada no se reabre.

## Bandas: flujo del RL

1. **Bandas > Nueva banda.** Pon nombre ("Banda A martes"), banda (Barrow Deeps 10, Hyjal Summit 20, Onyxia's Lair 40 o personalizada de 10/20/40), fecha y hora del reino (`YYYY-MM-DD HH:MM` + Enter) y plantilla tanques/sanadores/daño como mín-máx (`2-2/2-3/5-6` + Enter). Marca *Cada semana* si se repite.
2. **Monta el roster** con "+" en el panel de squads y jugadores (filtra por rol, conectados, nombre o clase; un número = nivel mínimo). Un squad entra entero en el primer grupo con sitio; si no cabe, entran los titulares que quepan y te avisa; sus suplentes van a huecos libres o a la lista de suplentes (máx. 10). Nadie sale dos veces.
3. Mira la **barra de composición** y los avisos ("faltan 1 T", "sobran 1 D", "sin quitar maldiciones"). **Guardar**.
4. **Publicar**: los apuntados ya pueden responder Sí / Tal vez / No / Suplente. Cualquiera de la guild puede responder como voluntario. Ves el recuento y los comentarios.
5. A la hora: **Invitar confirmados**. Una tanda por clic, solo fuera de combate (5 en grupo; luego convierte a banda si el cliente lo permite y coloca los subgrupos si eres líder o ayudante). Cuando acepten, **vuelve a pulsar**.
6. **Cerrar** al acabar: guarda la asistencia (quién estuvo en la banda desde 30 min antes hasta 3 h después). Si no la cierras, se cierra sola 3 h después **si tu cliente (o el del GM) está conectado**.
7. **Semana sig.** copia la banda a +7 días a la misma hora del reino. **Exportar** da el texto para Discord. **Cancelar banda** avisa a todos los apuntados.

El % de asistencia de cada jugador cuenta las 8 últimas bandas con asistencia registrada en las que estaba apuntado o presente.

## Comandos útiles para el GM

| Comando | Para qué |
|---|---|
| `/gsq` · `/gsq help` | Ventana · lista de comandos. |
| `/gsq sync` | Pide lo que falta (1 por minuto). Al conectar como GM, tu cliente ayuda a los demás a ponerse al día. |
| `/gsq export` / `/gsq import` | Copia de seguridad en texto. Al importar, cada registro se vuelve a validar; los que no te corresponde aplicar se rechazan y se cuentan. |
| `/gsq diag` | Informe de diagnóstico: qué APIs tiene el cliente (`raid apis … rosters=`), contadores de eventos y de envío (`comm`), rechazos de sincronización (`sync bad= relayRefused= future= quarantine=`), errores del chat de la guild (`hall … chatErr=`) y la vía de lectura de profesiones (`prof path= n=`). Detalle línea a línea en la [guía del jugador](PLAYER-GUIDE.md#qué-trae-gsq-diag). |
| `/gsq ui` | Imprime qué plantillas y atlas tiene el cliente y cuáles usan la alternativa. |
| `/gsq minimap` | Vuelve a mostrar el botón del minimapa. |
| `/gsq debug` | Contadores de envío/recepción en el chat y registro detallado (para depurar). |

## Problemas

**No sincroniza nada sin GM u oficial conectado.** Es así por diseño: un dato se acepta en vivo de su autor y solo lo reenvían GM u oficiales. Si queréis que los nuevos se pongan al día rápido, que haya un oficial con el addon conectado en las horas punta.

**Los datos parecen perderse al reiniciar.** Se ha visto que el cliente de Forever a veces no relee las SavedVariables. Haz `/gsq export` después de cambiar ajustes o cerrar bandas y guarda el texto; los demás los recuperan de cualquier GM/oficial conectado.

**El chat de la guild no anuncia nada.** Celebraciones desactivadas por defecto: Ajustes > Celebrac. Si el cliente bloquea el mensaje, el error aparece en `/gsq diag` (`hall ... chatErr=`).

**Las carreras de "completar" no se abren.** Falta marcar el jefe final en Ajustes > Contenido.

**Invitar confirmados no monta la banda.** `/gsq diag` dice qué APIs de grupo/banda existen. Si no se puede convertir a banda o mover subgrupos, el addon lo salta y avisa; hazlo a mano.

**Dos squads con el mismo nombre a la vez.** Cada cliente se queda con el que vio primero; renombra o restablece uno desde Moderación.

**Un jugador sigue viendo un logro que desactivé.** Aún no le ha llegado el cambio (los cambios en bloque van a 1 mensaje por segundo). `/gsq diag` muestra `catalog achdef= custom= grants= off=`: compara los números con los tuyos.

## Preguntas frecuentes

**¿Puedo delegar los ajustes en un oficial?** No: solo el rango 0 firma ajustes (y el catálogo de logros). Los oficiales moderan (aprobar, disolver, restablecer) y reenvían datos.

**¿Qué pasa al empezar una temporada nueva a mitad de wipe?** Ese wipe queda en la temporada anterior.

**¿Cuánto tarda en ponerse al día una guild grande?** Minutos (500 perfiles), a propósito, para respetar el límite de mensajes del cliente.

**¿Se puede usar para repartir botín o cobrar?** No. No guarda nada de economía: gratis, MIT, sin anuncios, sin donaciones y sin oro de por medio.
