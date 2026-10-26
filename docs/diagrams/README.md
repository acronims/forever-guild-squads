# Diagramas de Guild Squads

HTML autónomos (SVG en línea, tema claro/oscuro, exportación) generados con archify a partir de `src/*.json`. PNG en `png/`. Índice visual: `index.html`.

| Diagrama | Descripción |
|---|---|
| [01-arquitectura](01-arquitectura.html) | Módulos del cliente (Core puro, glue WoW, UI), SavedVariables, canal GUILD/WHISPER, otros clientes, Overlord opcional, diagnóstico y lo que nunca ocurre. |
| [02-ciclo-squad](02-ciclo-squad.html) | Estados del squad y de la membresía: crear, aprobar, solicitud/invitación, miembro, transferir, expulsar/salir, disolver, squad inactivo y rechazos sincronizados. |
| [03-sync](03-sync.html) | Secuencia de sincronización: hello con hashes, respuesta con jitter, merge LWW + autoridad, refresco de UI, bloqueo en encuentro, export/import. |
| [04-ajustes-gm](04-ajustes-gm.html) | El GM guarda los ajustes: registro versionado, difusión, validación de rango 0 en cada cliente y aplicación (p. ej., squads desactivados ocultan pestañas). |
| [05-puntuacion](05-puntuacion.html) | Flujo de puntos: eventos → MetricEvent → réplica → membresía por wipe y testigos → normalización y tope → wipe → temporada. |
| [06-wipe-temporada](06-wipe-temporada.html) | Wipe semanal (miércoles 09:00, hora del reino) abierto → cerrado → archivado; temporada del GM y "Nueva temporada"; logros del wipe y de la temporada. |
| [07-bandas](07-bandas.html) | Bandas 10/20/40: crear roster, composición, squads enteros G1–G8, cobertura y avisos, RSVP firmado, publicar → invitar, cerrar + asistencia firmada (≤ 7 días), copia semanal y export. No incluye calendario del juego, botín ni arrastrar y soltar. |
| [08-salon-de-la-fama](08-salon-de-la-fama.html) | Salón de la fama: observaciones → ventana en vivo / no verificado «?» → testigos → carreras Top N (Confirmar y Anular del GM/oficial) → Mis logros → claim de anunciante → chat de la guild. |

## Regenerar

- HTML: `node <archify>/bin/archify.mjs deliver <tipo> src/<n>.json <n>.html --quality showcase`, donde `<tipo>` es el `diagram_type` del JSON (p. ej. `workflow` para 02 y 07, `dataflow` para 08).
- PNG: con un navegador sin cabeza a 1400×900, abrir `<n>.html?theme=light` y hacer una captura de página completa en `png/<n>.png`.
