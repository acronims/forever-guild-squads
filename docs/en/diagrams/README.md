# Guild Squads diagrams

Español → [diagrams/README.md](../../es/diagrams/README.md)

Standalone HTML files (inline SVG, light/dark theme, export) built with archify from `src/*.json`. PNGs in `png/`. Visual index: [index.html](index.html).

| Diagram | PNG | Description |
|---|---|---|
| [01-architecture](01-architecture.html) | [png](png/01-architecture.png) | Client modules (pure Core, WoW glue, UI), SavedVariables, GUILD/WHISPER channel, other clients, optional Overlord, diagnostics and what never happens. |
| [02-squad-lifecycle](02-squad-lifecycle.html) | [png](png/02-squad-lifecycle.png) | Squad and membership states: create, approve, request/invitation, member, transfer, kick/leave, disband, inactive squad and synced rejections. |
| [03-sync](03-sync.html) | [png](png/03-sync.png) | Sync sequence: hello with hashes, jittered reply, LWW merge + authority, UI refresh, encounter lock, export/import. |
| [04-gm-settings](04-gm-settings.html) | [png](png/04-gm-settings.png) | The GM saves the settings: versioned record, broadcast, rank 0 validation on every client and application (e.g. disabled squads hide tabs). |
| [05-scoring](05-scoring.html) | [png](png/05-scoring.png) | Points flow: events → MetricEvent → replication → per-wipe membership and witnesses → normalisation and cap → wipe → season. |
| [06-wipe-season](06-wipe-season.html) | [png](png/06-wipe-season.png) | Weekly wipe (Wednesday 09:00 realm time) open → closed → archived; the GM's season and "New season"; wipe and season achievements. |
| [07-raids](07-raids.html) | [png](png/07-raids.png) | Raids 10/20/40: create roster, composition, whole squads G1–G8, coverage and warnings, signed RSVP, publish → invite, close + signed attendance (≤ 7 days), weekly copy and export. Out of scope: in-game calendar, loot, drag and drop. |
| [08-hall-of-fame](08-hall-of-fame.html) | [png](png/08-hall-of-fame.png) | Hall of Fame: observations → live window / unverified "?" → witnesses → Top N races (GM/officer Confirm and Annul) → My achievements → announcer claim → guild chat. |

## Regenerating

- HTML: `node <archify>/bin/archify.mjs deliver <type> src/<n>.json <n>.html --quality showcase`, where `<type>` is the JSON's `diagram_type` (`architecture` for 01, `workflow` for 02, 06 and 07, `sequence` for 03 and 04, `dataflow` for 05 and 08).
- PNG: with a headless browser at 1400×900, open `<n>.html?theme=light` and take a full-page screenshot into `png/<n>.png`.
- A diagram change goes into both languages: `docs/en/diagrams/src/` and `docs/es/diagrams/src/` share the same node ids; only the texts differ.
