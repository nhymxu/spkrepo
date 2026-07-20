# Adding a new app package

How to turn "an app that runs as a binary" into a DSM7 x86_64 `.spk` that
gets built, released, and published into `data/packages.json`, following
the pattern established by `packages/forgejo/` and `packages/gitea/`
(two worked examples -- read either `README.md` and `build.sh` alongside
this guide; they're nearly identical since Forgejo is a Gitea fork).

This guide only covers the *build-one-app* side. The catalog-*serving*
side (root static site, `future-deployments/`) doesn't change per app.

## 1. Decide binary sourcing strategy

- **Prebuilt (preferred when available):** the app publishes official
  `linux-amd64` binaries on its own releases -- `build.sh` just
  downloads and repackages. Simplest, no toolchain needed in CI.
- **Build from source:** clone at a tag and compile natively on the
  `ubuntu-latest` (x86_64) runner -- no cross-compilation. Only do this
  if the app has no prebuilt binary, or you need custom build flags.
  See `packages/forgejo/build.sh` for a working Go+Node example.

## 2. Pick minimal vs. production-grade scripts

Two tracks, pick based on whether the app needs persistent user data in
a NAS shared folder:

- **Minimal** (an app with no meaningful persistent state, or that's
  fine storing everything under its own package var dir): a single
  hand-written `scripts/start-stop-status` using `$SYNOPKG_PKGDEST`/
  `$SYNOPKG_PKGVAR` directly, `conf/privilege` omitted (runs as root).
  Faster to write, fewer moving parts.
- **Production-grade** (an app that should store data in a
  user-chosen shared folder, run as a non-root dedicated account, etc.):
  follow `packages/forgejo/src/` as the reference --
  vendor spksrc's generic lifecycle scripts (see step 4) rather than
  hand-rolling the DSM7 privilege/resource mechanics, since those
  aren't fully documented publicly and are easy to get subtly wrong.

## 3. Scaffold `packages/<app>/`

Minimal track:

```
packages/<app>/
  build.sh
  src/
    scripts/
      start-stop-status
  README.md
```

Production-grade track (see `packages/forgejo/` or `packages/gitea/` for
a complete example) reuses the **already-vendored** generic scripts at
`packages/_shared/spksrc-service/` -- don't re-vendor them per package:

```
packages/_shared/spksrc-service/    # shared by every package, create once
  functions            # vendored verbatim from spksrc
  installer.dsm7        # vendored verbatim from spksrc
  start-stop-status     # vendored verbatim from spksrc
  preinst/postinst/preuninst/postuninst/preupgrade/postupgrade  # generic wrappers, app-agnostic
  NOTICE.md               # BSD-3 attribution

packages/<app>/
  build.sh
  src/
    scripts/
      service-setup          # the only script that's actually app-specific
    conf/
      privilege
      resource
    wizard/
      install_uifile
      upgrade_uifile
    conf.ini (or equivalent config template, if needed)
  README.md
```

`build.sh` copies everything from `packages/_shared/spksrc-service/`
plus this app's own `service-setup` into the same staged `scripts/`
directory at build time (see step 4) -- they must end up as siblings
there, not in the source tree.

## 4. Write `build.sh`

Args: `--version X.Y.Z` (required), `--os-min-ver` (default
`7.0-40000`, i.e. DSM7), `--out DIR`. Steps:

1. Fetch or build the binary for linux/amd64.
2. `tar czf package.tgz` containing the binary (+ any required static
   assets, + a pre-seeded config template under `var/` if using the
   production-grade track) -- this becomes `$SYNOPKG_PKGDEST` on the NAS.
3. Minimal track: copy `src/scripts/` in, `chmod +x scripts/*`.
   Production-grade track: copy every file from
   `packages/_shared/spksrc-service/` plus this app's own
   `src/scripts/service-setup` into the staged `scripts/` dir
   (`chmod +x` all the lifecycle scripts), and also copy
   `src/conf/` and `src/wizard/` in as top-level
   `.spk` entries.
4. Generate `INFO` via heredoc (no template engine) with at least:
   `package`, `version`, `arch="x86_64"`, `os_min_ver`, `displayname`,
   `description`, `maintainer`, `maintainer_url`, `startable="yes"`, and
   `install_dep_packages="..."` for any other DSM package this one
   needs at runtime (e.g. Forgejo needs `git>=2`, since Git-based apps
   need the `git` binary on `PATH`  -- check this for your app too).
5. `tar cf $OUT/<app>-<version>-x86_64.spk -C staging INFO package.tgz scripts [conf wizard]`
   -- the outer `.spk` container is a **plain, uncompressed** tar.

## 5. Minimal track: `src/scripts/start-stop-status`

- Use the DSM-provided `$SYNOPKG_PKGDEST` (install dir) and
  `$SYNOPKG_PKGVAR` (persistent data dir, survives upgrades) env vars --
  never hardcode `/var/packages/...` paths.
- pidfile-based start/stop/status.
- Point the app's config/data paths at `$SYNOPKG_PKGVAR` so state
  survives package upgrades.

## 5b. Production-grade track: vendor spksrc's generic lifecycle scripts

DSM7's dedicated-service-account + shared-folder-grant mechanism
(`conf/privilege`/`conf/resource`) isn't documented well enough to
safely hand-roll from scratch. Instead:

- If `packages/_shared/spksrc-service/` doesn't exist yet, vendor
  `mk/spksrc.service/{functions,installer.dsm7,start-stop-status}` from
  `SynoCommunity/spksrc` **verbatim** (3-clause BSD, attribution
  required -- add a `NOTICE.md`), plus write generic `preinst`/
  `postinst`/`preuninst`/`postuninst`/`preupgrade`/`postupgrade` wrapper
  scripts that source `installer.dsm7` and call the matching function.
  If it already exists (it does, as of `packages/forgejo/` and
  `packages/gitea/`), just reuse it -- don't vendor a second copy.
- Write an app-specific `scripts/service-setup` (`SERVICE_COMMAND`,
  `SVC_BACKGROUND=y`, port, any extra `PATH` entries the app needs,
  `service_postinst()` for config templating).
- `conf/privilege`: `{"defaults": {"run-as": "package"}}` (per
  [Synology's developer guide](https://help.synology.com/developer-guide/privilege/privilege_config.html)).
- `conf/resource`: `{"data-share": {"shares": [{"name": "...", "permission": {"rw": ["..."]}}]}}`
  (per the [resource acquisition docs](https://help.synology.com/developer-guide/resource_acquisition/resources.html))
  -- the exact wizard-name binding syntax is a best-effort
  reconstruction; verify on a real NAS.
- `wizard/install_uifile` + `upgrade_uifile`: ask for a shared-folder
  name if the app needs persistent user data.

See `packages/forgejo/README.md` and `packages/forgejo/src/`
for a complete worked example of this track.

## 6. Wire up CI: reuse the shared workflow, don't copy it

`.github/workflows/build-package.yml` is a **reusable** workflow
(`workflow_call`, inputs `package` and `version`) that does the whole
build → release → publish → commit pipeline generically: checkout →
setup Go/Node/corepack → run `packages/<package>/build.sh --version
<version>` → `gh release create <package>-v<version> <spk> --title ...
--notes ...` → compute the deterministic asset download URL →
`python3 tools/spk_to_payload.py <spk> --link <url> --write-index
data/packages.json` → commit and push. The push auto-triggers the root
`deploy-static-site.yml` (it watches `data/**`) -- no separate deploy
step needed.

Adding a new app only needs a **thin dispatcher** workflow, not a copy
of the pipeline -- see `.github/workflows/build-forgejo.yml` /
`build-gitea.yml`:

```yaml
name: Build <App> package
on:
  workflow_dispatch:
    inputs:
      version:
        required: true
jobs:
  build:
    uses: ./.github/workflows/build-package.yml
    with:
      package: <app>
      version: ${{ inputs.version }}
    permissions:
      contents: write
```

Only touch `build-package.yml` itself if the *generic* pipeline logic
needs to change for every app at once (e.g. bumping the Go/Node
version). If a new app needs an extra toolchain step, add it there
guarded to be a no-op for apps that don't need it (like
`corepack enable`, harmless for packages that don't use pnpm).

## 7. Link it from the root README

Add `<app>` to the `packages/` bullet list in the root `README.md`,
pointing at `packages/<app>/README.md`.

## 8. Verify before triggering the real workflow

- `bash -n` on the new scripts.
- Dry-run the packaging logic with a stub binary (skip the real
  fetch/build) piped through `tools/spk_to_payload.py --write-index
  /tmp/check.json` then `tools/render_static_catalog.py`, and confirm
  the rendered `{"packages": [...]}` looks right for `arch=x86_64`.
- Confirm the upstream tag/release naming (`git ls-remote` or the app's
  releases API) matches what `--version` will produce.
- A full real fetch/compile can only be verified for real on an x86_64
  Linux host -- trust the actual GitHub Actions run for that part.

## Known simplifications to default to

Call out in the package's own README which of these you didn't apply:

- No package icon (Package Center shows a generic icon).
- x86_64 only, one manual `workflow_dispatch` build per version (no
  auto-update watcher for new upstream releases).
- **Minimal track only:** runs as root (no dedicated `conf/privilege`
  user), no bundled DSM install wizard (rely on the app's own first-run
  setup if it has one).
- **Production-grade track:** the `conf/resource` wizard-binding syntax
  and whether a pre-seeded config file actually suppresses the app's own
  first-run setup are both best-effort until confirmed on a real DSM7
  NAS -- say so explicitly rather than presenting them as verified.
