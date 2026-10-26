# Publicar una versión de Guild Squads

Las versiones se publican empujando un tag `vX.Y.Z`. Un workflow de GitHub Actions empaqueta el addon con el [BigWigs packager](https://github.com/BigWigsMods/packager) y lo sube a CurseForge, Wago y GitHub Releases. WoWInterface no se usa (no tiene el tipo de juego Forever).

Solo los mantenedores con permisos de administración del repositorio pueden configurar los secretos y aprobar la publicación.

## Piezas del repositorio

- **`.github/workflows/release.yml`**: se lanza con cada tag que empieza por `v`. El job `release` usa el entorno de GitHub `environment: release` (los secretos de publicación viven ahí y el entorno puede exigir aprobación antes de correr) y solo se ejecuta si la variable del repositorio `RELEASE_ENABLED` vale exactamente `true`; si no, el job sale como *skipped* y no se publica nada. Hace checkout con todo el historial (`fetch-depth: 0`) y ejecuta el BigWigs packager fijado por SHA. Necesita `contents: write` para crear la release de GitHub.
- **`.github/workflows/package-dryrun.yml`**: en cada pull request (o a mano desde *Actions*) ejecuta el packager con `-d` (sin subir nada) y deja el zip como artefacto `GuildSquads-zip`.
- **`.pkgmeta`**: el zip contiene la carpeta `GuildSquads/`; el changelog de la release es `CHANGELOG.md` (markdown); quedan fuera del zip `tests/`, `docs/`, `.github/`, `node_modules/`, `.luacheckrc`, `.gitignore`, `README.md`, `CURSEFORGE.md`, `SECURITY.md` y `CONTRIBUTING.md`.
- **`GuildSquads.toc`**: `## Version: @project-version@`. El packager sustituye ese valor por el nombre del tag al empaquetar; por eso un addon instalado directamente desde git muestra `@project-version@`. Los IDs de proyecto van en `## X-Curse-Project-ID:` y `## X-Wago-ID:`.
- **`CURSEFORGE.md`**: la descripción pública para CurseForge y Wago.

## Configuración (una vez)

1. **Proyectos** en CurseForge (World of Warcraft, versión de juego Forever 1.60.1) y en Wago. Descripción: `CURSEFORGE.md`. Licencia MIT.
2. **IDs en el TOC**: pon los IDs reales en `## X-Curse-Project-ID:` y `## X-Wago-ID:` (sin `#` delante). Sin `X-Curse-Project-ID` el packager se salta CurseForge sin dar error.
3. **Secretos** en el entorno `release` (GitHub > *Settings > Environments > release*):
   - `CF_API_TOKEN`: token de subida de CurseForge (se genera en la configuración de autor de CurseForge).
   - `WAGO_API_TOKEN`: token de API de Wago.
   - El token de GitHub no hace falta: el workflow pasa el `GITHUB_TOKEN` automático como `GITHUB_API_TOKEN`.
   Los tokens solo se guardan como secretos; nunca en el código, en incidencias ni en commits.
4. **Activar la publicación**: variable del repositorio `RELEASE_ENABLED` = `true` (*Settings > Secrets and variables > Actions > Variables*). Para volver a modo seguro, bórrala o ponla a `false`.

## Publicar una versión

1. Comprueba que `main` está en verde en la CI y que `CHANGELOG.md` tiene la sección de la versión (`## X.Y.Z — AAAA-MM-DD`, ES y EN).
2. Revisa el zip de prueba: *Actions > Package dry run > Run workflow* y descarga el artefacto `GuildSquads-zip`. Dentro debe estar la carpeta `GuildSquads/` con el TOC (`## Interface: 16001`), los `.lua`, `Bindings.xml`, `LICENSE` y `CHANGELOG.md`, y no deben estar `tests/`, `docs/` ni `.github/`. Pruébalo en el cliente: carga sin errores y `/gsq` abre la ventana.
3. Crea y empuja un tag anotado:
   ```
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin vX.Y.Z
   ```
   El tipo de release lo decide el packager por el nombre del tag: un tag con sufijo `-beta` se publica como beta; un `vX.Y.Z` sin sufijo, como release.
4. Si el entorno `release` exige aprobación, apruébala en la ejecución del workflow.

## Comprobar la publicación

Que el job termine en verde no basta: el packager acaba bien aunque se salte una subida.

1. **Log de la ejecución** (*Actions > Release*): debe haber una subida correcta a CurseForge y otra a Wago, y la release de GitHub creada. Un aviso de que no encuentra la versión de juego de CurseForge significa que eligió otra: revisa el proyecto.
   - Job *skipped*: `RELEASE_ENABLED` no es `true`.
   - Sin subida a CurseForge: falta `X-Curse-Project-ID` en el TOC o el secreto `CF_API_TOKEN`.
   - Sin release de GitHub: revisa los permisos del workflow.
2. **CurseForge y Wago**: el fichero aparece con el tipo correcto (en CurseForge puede salir *Under Review* un tiempo).
3. **Descarga el zip publicado** y repite la revisión del paso 2 de *Publicar una versión*: el TOC debe mostrar `## Version: vX.Y.Z`, no `@project-version@`.
