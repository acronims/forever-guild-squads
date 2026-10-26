# Diagramas de Guild Squads

English → [diagrams/README.md](../../en/diagrams/README.md)

HTML autónomos (SVG en línea, tema claro/oscuro, exportación) generados con archify a partir de `src/*.json`. PNG en `png/`. Índice visual: [index.html](index.html). Los controles del visor (tema, exportar, leyenda) los pone el generador y salen en inglés.

| Diagrama | PNG | Descripción |
|---|---|---|
| [01-architecture](01-architecture.html) | [png](png/01-architecture.png) | Módulos del cliente (Core puro, pegamento WoW, UI), SavedVariables, canal GUILD/WHISPER, otros clientes, Overlord opcional, diagnóstico y lo que nunca ocurre. |
| [02-squad-lifecycle](02-squad-lifecycle.html) | [png](png/02-squad-lifecycle.png) | Estados del squad y de la membresía: crear, aprobar, solicitud/invitación, miembro, transferir, expulsar/salir, disolver, squad inactivo y rechazos sincronizados. |
| [03-sync](03-sync.html) | [png](png/03-sync.png) | Secuencia de sincronización: hello con hashes, respuesta con jitter, merge LWW + autoridad, refresco de UI, bloqueo en encuentro, export/import. |
| [04-gm-settings](04-gm-settings.html) | [png](png/04-gm-settings.png) | El GM guarda los ajustes: registro versionado, difusión, validación de rango 0 en cada cliente y aplicación (p. ej., squads desactivados ocultan pestañas). |
| [05-scoring](05-scoring.html) | [png](png/05-scoring.png) | Flujo de puntos: eventos → MetricEvent → réplica → membresía por wipe y testigos → normalización y tope → wipe → temporada. |
| [06-wipe-season](06-wipe-season.html) | [png](png/06-wipe-season.png) | Wipe semanal (miércoles 09:00, hora del reino) abierto → cerrado → archivado; temporada del GM y «Nueva temporada»; logros del wipe y de la temporada. |
| [07-raids](07-raids.html) | [png](png/07-raids.png) | Bandas 10/20/40: crear roster, composición, squads enteros G1–G8, cobertura y avisos, RSVP firmado, publicar → invitar, cerrar + asistencia firmada (≤ 7 días), copia semanal y export. No incluye calendario del juego, botín ni arrastrar y soltar. |
| [08-hall-of-fame](08-hall-of-fame.html) | [png](png/08-hall-of-fame.png) | Salón de la fama: observaciones → ventana en vivo / no verificado «?» → testigos → carreras Top N (Confirmar y Anular del GM/oficial) → Mis logros → claim de anunciante → chat de la guild. |

## Regenerar

- HTML: `node <archify>/bin/archify.mjs deliver <tipo> src/<n>.json <n>.html --quality showcase`, donde `<tipo>` es el `diagram_type` del JSON (`architecture` para 01, `workflow` para 02, 06 y 07, `sequence` para 03 y 04, `dataflow` para 05 y 08).
- PNG: con un navegador sin cabeza a 1400×900, abrir `<n>.html?theme=light` y hacer una captura de página completa en `png/<n>.png`.
- Un cambio en un diagrama va en los dos idiomas: `docs/es/diagrams/src/` y `docs/en/diagrams/src/` tienen los mismos ids de nodo; solo cambian los textos.
