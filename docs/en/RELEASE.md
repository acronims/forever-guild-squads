# Releasing a Guild Squads version

Español → [RELEASE.md](../es/RELEASE.md)

Versions are released by pushing a `vX.Y.Z` tag. A GitHub Actions workflow packages the addon with the [BigWigs packager](https://github.com/BigWigsMods/packager) and uploads it to CurseForge, Wago and GitHub Releases. WoWInterface is not used (it has no Forever game type).

Only maintainers with admin rights on the repository can configure the secrets and approve a release.

## Repository pieces

- **`.github/workflows/release.yml`**: triggered by every tag starting with `v`. The `release` job uses the GitHub environment `environment: release` (the publishing secrets live there and the environment can require approval before running) and only runs when the repository variable `RELEASE_ENABLED` is exactly `true`; otherwise the job ends as *skipped* and nothing is published. It checks out the full history (`fetch-depth: 0`) and runs the BigWigs packager pinned by SHA. It needs `contents: write` to create the GitHub release.
- **`.github/workflows/package-dryrun.yml`**: on every pull request (or by hand from *Actions*) it runs the packager with `-d` (no upload) and keeps the zip as the `GuildSquads-zip` artifact.
- **`.pkgmeta`**: the zip holds the `GuildSquads/` folder; the release changelog is `CHANGELOG.md` (markdown); `tests/`, `docs/`, `.github/`, `node_modules/`, `.luacheckrc`, `.gitignore`, `README.md`, `README.es.md`, `CURSEFORGE.md`, `SECURITY.md` and `CONTRIBUTING.md` stay out of the zip.
- **`GuildSquads.toc`**: `## Version: @project-version@`. The packager replaces that value with the tag name when packaging; that is why an addon installed straight from git shows `@project-version@`. Project IDs go in `## X-Curse-Project-ID:` and `## X-Wago-ID:`.
- **`CURSEFORGE.md`**: the public description for CurseForge and Wago.

## Setup (once)

1. **Projects** on CurseForge (World of Warcraft, game version Forever 1.60.1) and on Wago. Description: `CURSEFORGE.md`. MIT license.
2. **IDs in the TOC**: put the real IDs in `## X-Curse-Project-ID:` and `## X-Wago-ID:` (without a leading `#`). Without `X-Curse-Project-ID` the packager skips CurseForge without any error.
3. **Secrets** in the `release` environment (GitHub > *Settings > Environments > release*):
   - `CF_API_TOKEN`: CurseForge upload token (generated in the CurseForge author settings).
   - `WAGO_API_TOKEN`: Wago API token.
   - No GitHub token is needed: the workflow passes the automatic `GITHUB_TOKEN` as `GITHUB_API_TOKEN`.
   Tokens are only stored as secrets; never in code, issues or commits.
4. **Enable publishing**: repository variable `RELEASE_ENABLED` = `true` (*Settings > Secrets and variables > Actions > Variables*). To go back to safe mode, delete it or set it to `false`.

## Releasing a version

1. Check that `main` is green in CI and that `CHANGELOG.md` has the version section (`## X.Y.Z — YYYY-MM-DD`, ES and EN).
2. Review the test zip: *Actions > Package dry run > Run workflow* and download the `GuildSquads-zip` artifact. It must contain the `GuildSquads/` folder with the TOC (`## Interface: 16001`), the `.lua` files, `Bindings.xml`, `LICENSE` and `CHANGELOG.md`, and must not contain `tests/`, `docs/`, `.github/`, `README.md` or `README.es.md`. Try it in the client: it loads without errors and `/gsq` opens the window.
3. Create and push an annotated tag:
   ```
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin vX.Y.Z
   ```
   The packager decides the release type from the tag name: a tag with a `-beta` suffix is published as a beta; a plain `vX.Y.Z`, as a release.
4. If the `release` environment requires approval, approve it on the workflow run.

## Checking the release

A green job is not enough: the packager finishes fine even when it skips an upload.

1. **Run log** (*Actions > Release*): there must be a successful upload to CurseForge and another to Wago, and the GitHub release must exist. A warning that it cannot find the CurseForge game version means it picked another one: check the project.
   - Job *skipped*: `RELEASE_ENABLED` is not `true`.
   - No CurseForge upload: `X-Curse-Project-ID` is missing from the TOC or the `CF_API_TOKEN` secret is missing.
   - No GitHub release: check the workflow permissions.
2. **CurseForge and Wago**: the file shows up with the right type (on CurseForge it may stay *Under Review* for a while).
3. **Download the published zip** and repeat the review from step 2 of *Releasing a version*: the TOC must show `## Version: vX.Y.Z`, not `@project-version@`.
