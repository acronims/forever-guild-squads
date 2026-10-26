# Simulador multi-cliente — resultados

Simulador: `tests/sim/` (Node + fengari). Cada cliente es el addon completo (todo el TOC) en su propio estado fengari, con su API WoW falsa, SavedVariables, reloj (con desfase) y timers. Bus GUILD/WHISPER con `CHAT_MSG_ADDON` y remitente `Nombre-Reino`, latencia 50–800 ms (en orden por par), throttle por prefijo (ráfaga 10, 1 msg/s; por encima devuelve 3), pérdida opcional, bloqueo en encuentro/BG, login/logout//reload con SavedVariables. PRNG con semilla (mulberry32).

Ejecutar: `NODE_PATH=… node tests/sim/run.js [S1 … S10] [--seed N] [--s5seeds N] [--s8min N] [--s9seeds N] [--s9min N]`. La CI ejecuta todos salvo S10, con la semilla 7303 (S9 también con 8303 y 9303).

## Resultados (semilla 7303)

| Escenario | Resultado | Cifras |
|---|---|---|
| S1 10 clientes, squads/solicitudes/aceptar/expulsar al azar | PASS | 50 acciones efectivas; mismo hash del modelo en los 10 |
| S2 el GM cambia ajustes con 30 clientes; un miembro falsifica | PASS | los 30 aplican los ajustes en 2 s; 0 clientes aceptan la falsificación (firmada por él y suplantando al GM) |
| S3a cliente nuevo, 200 registros, oficial conectado | PASS | converge en 210 s simulados (≤ 450 s exigidos) |
| S3b sin GM ni oficiales (semilla 7304) | PASS | recibe solo los perfiles de los 3 autores conectados + el suyo (comportamiento documentado) |
| S4 banda de 10, 2 squads, jefe con comunicación bloqueada | PASS | 0 mensajes durante el encuentro; misma puntuación y Top en los 10 |
| S5 celebraciones, 20 clientes | PASS | 20 semillas (7303–7322): 60 eventos → 60 mensajes, exactamente 1 por evento |
| S6 cambio de wipe con desfase de reloj ±200 s | PASS | mismo resumen canónico de ambos wipes en los 10; puntuación en vivo del wipe cerrado igual en todos (`liveScoreVariants` = 1; en el wipe abierto, 2) |
| S7 roster de banda: publicar, 15 RSVP, invitar, cerrar sin RL, firma posterior | PASS | 4 invitados en el primer clic (grupo), misma asistencia firmada en todos |
| S8 carga: 500 miembros, 100 squads, 20 clientes, 15 min | PASS | ver *Métricas S8* |
| S9 caos 60 min, pérdida 5 %, /reload aleatorios | PASS | 263 acciones, 15 /reload, 776 mensajes perdidos; convergencia final |
| S10 catálogo del GM con 30 clientes | PASS | ver *S10* |

Errores de Lua capturados (pcall de eventos/timers, `Sync.stats.errors`, `Comm.stats.handlerErrors`, `ns.debug` con `archivo:línea`): **0** en todos los escenarios.

## Métricas S8 (15 min con 20 clientes; en la CI, 3 min)

| Métrica | Valor | Límite |
|---|---|---|
| Media de mensajes/s del cliente más cargado (oficial) | 0,763 | ≤ 1,05 (la cola de Comm drena a 1/s) |
| Pico en 1 s | 4 | ≤ 10 (ráfaga del throttle) |
| Envíos rechazados por el throttle | 0 | 0 |
| Cola máxima | 379 | 500 |

La cola es el atraso de un oficial respondiendo hellos cuando 20 clientes entran en 60 s; drena a 1 msg/s. Lo propio (registros, eventos, observaciones en vivo, claims) va delante, así que el atraso solo retrasa la puesta al día de los demás.

## S10 — catálogo del GM

30 clientes (GM, 2 oficiales, 27 miembros). 5 de ellos no conocen los tipos de registro del catálogo (`achdef`, `achgrant`): comprueba que un cliente que no conoce un tipo de registro lo ignora sin error y sigue sincronizando el resto. No va en la CI: necesita `GSQ_COMPAT_REF` (y `GIT_DIR` si hace falta) apuntando a un ref de git con ese cliente. Semilla 7303. Comando: `NODE_PATH=… node tests/sim/run.js S10 --seed 7303`.

| Comprobación | Resultado |
|---|---|
| El GM desactiva 60 carreras (un bloque = 60 registros `achdef`) y crea 5 logros propios | 60 aplicados, 0 rechazados; 5 creados |
| Partes de mensaje del bloque (estimación que ve el GM en la confirmación) | 40 (3 registros por mensaje) |
| Los 25 clientes que conocen esos tipos tienen el mismo catálogo (65 registros, 60 desactivados) | **45 s** simulados (medido en pasos de 5 s): 40 s del bloque a 1 msg/s + los 5 propios |
| `achdef` falsificado por un miembro (firmado por él y suplantando al GM) y `achgrant` falsificado | aceptado por **0** clientes; la copia que suplanta al GM se rechaza como reenvío (`relayRefused`) |
| Clientes que no conocen esos tipos | reciben e ignoran los tipos desconocidos sin error (`sync bad=` 68 en cada uno), no guardan nada del catálogo, aplican los ajustes del GM y el resto del modelo converge en los 30 en 5 s |
| Errores de Lua capturados | **0** |

## Límites del simulador

API falsa permisiva (sin UI real, sin medición de texto), reloj y throttle modelados (no los del cliente), roster compartido instantáneo, `GetServerTime` con desfase artificial (en el juego lo da el servidor). Pasar en el simulador no equivale a estar probado en el juego.
