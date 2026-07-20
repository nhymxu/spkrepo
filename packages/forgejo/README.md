# packages/forgejo

Builds a DSM7 x86_64 `.spk` for [Forgejo](https://codeberg.org/forgejo/forgejo)
(self-hosted Git service) from source, following the same build recipe as
the real, maintained [`SynoCommunity/spksrc`](https://github.com/SynoCommunity/spksrc)
`spk/forgejo/` package -- git dependency, source tarball, embedded config
paths, dedicated service account, shared-folder wizard. This is a
package-*building* concern, separate from the catalog-*serving*
deployments at the repo root and under `future-deployments/` -- it
produces the `.spk` and metadata those deployments then serve.

## Build locally

Requires Go >= 1.24, Node >= 20, `make`, gcc (CGO is enabled for
sqlite), on an x86_64 Linux host (no cross-compilation):

```bash
packages/forgejo/build.sh --version 15.0.4
```

Fetches Forgejo's own vendored-deps source tarball
(`forgejo-src-<version>.tar.gz` from its Codeberg release, not a git
clone), builds with
`CGO_ENABLED=1 TAGS="bindata timetzdata sqlite sqlite_unlock_notify" make build`
(binary is **not** renamed -- Forgejo forked from Gitea and keeps the
binary named `gitea`), with `LDFLAGS` embedding `CustomPath`/`CustomConf`/
`AppWorkPath`/`PIDFile` under `/var/packages/forgejo/var` directly into
the binary. Packages the binary (`bin/gitea`) plus a pre-seeded
`var/conf.ini` into `packages/forgejo/dist/forgejo-<version>-x86_64.spk`.

`--os-min-ver` (default `7.0-40000`, i.e. DSM7) and `--out` (default
`packages/forgejo/dist`) are optional overrides.

## Package structure

`build.sh` assembles the final `.spk`'s `scripts/` directory from two
sources -- **not** all forgejo-specific:

- **`packages/_shared/spksrc-service/`** (shared across every package
  under `packages/`, not just this one): `functions`, `installer.dsm7`,
  `start-stop-status` -- vendored verbatim from spksrc's generic,
  package-agnostic `mk/spksrc.service/` (3-clause BSD, see that
  directory's `NOTICE.md`); plus `preinst`, `postinst`, `preuninst`,
  `postuninst`, `preupgrade`, `postupgrade` -- generic wrappers (this
  repo's own, but app-agnostic: each just sources `installer.dsm7` and
  calls the matching function). Together these implement the whole DSM7
  package lifecycle (`var` folder migration on install/upgrade, daemon
  start/stop/status) with zero forgejo-specific content. Any new
  package under `packages/<app>/` reuses these same files rather than
  copying them. `build.sh` copies all of them, plus this package's own
  `service-setup`, into the same staged `scripts/` directory in the
  final `.spk` -- they must end up as siblings there since
  `installer.dsm7`/`start-stop-status` look each other and
  `service-setup` up via `$(dirname "$0")` at runtime.
- **`packages/forgejo/src/scripts/service-setup`** -- the one
  genuinely forgejo-specific script: `SERVICE_COMMAND`
  (`gitea web --port 8620 --pid ...`), `PATH` including
  `/var/packages/git/target/bin` (Forgejo needs `git` on `PATH` for
  every repo operation), `service_postinst()` substituting
  `@share_path@`/`@ip_address@`/`@service_port@` into `conf.ini`.
- **`conf/privilege`** -- `{"defaults": {"run-as": "package"}}`, so DSM
  runs this package under its own dedicated service account instead of
  root.
- **`conf/resource`** -- declares/creates a shared folder (named via the
  install wizard) and grants the package's account read-write access.
- **`wizard/install_uifile`, `upgrade_uifile`** -- installer asks for a
  shared-folder name (`wizard_shared_folder_name`) to store repos in;
  upgrade wizard reminds about manual `conf.ini` review.
- **`conf.ini`** -- pre-seeded template (repo root, domain/IP, LFS path)
  so Forgejo skips its own interactive web installer.

## CI: build, release, publish

`.github/workflows/build-forgejo.yml` (`workflow_dispatch`, input
`version`) is a thin dispatcher that calls the shared reusable workflow
`.github/workflows/build-package.yml` with `package: forgejo` --
`packages/gitea/` uses the same reusable workflow with `package: gitea`,
so adding a third package only needs a new one-line dispatcher, not a
new copy of the whole pipeline. The reusable workflow:

1. Runs `packages/<package>/build.sh --version <version>`.
2. `gh release create <package>-v<version>` and uploads the `.spk` as a
   release asset.
3. `python3 tools/spk_to_payload.py <spk> --link <release-asset-url>
   --write-index data/packages.json` (the shared tool at the repo root --
   intentionally reused here, since it's built to be called by any
   project that produces a `.spk`).
4. Commits and pushes `data/packages.json` -- auto-triggers the root
   `deploy-static-site.yml` Pages redeploy.

## Known simplifications and open risks

- **Not yet verified on a real DSM7 NAS.** Two things in particular are
  best-effort reconstructions rather than confirmed-correct: the exact
  `conf/resource` syntax for binding the wizard's chosen share name to
  the `data-share` declaration, and whether the pre-seeded `conf.ini`
  alone (without an explicit `INSTALL_LOCK` setting) fully suppresses
  Forgejo's own first-run web installer. Please test an actual install
  and report back if either needs adjusting.
- `LOG_FILE`/`PID_FILE` defaults in `service-setup` are our own explicit
  choices (consistent with the paths spksrc's build embeds via ldflags)
  -- the real package's `service-setup.sh` excerpt we found didn't show
  where it defines these, so this isn't a byte-for-byte copy of that
  part.
- x86_64 only; one manual build per version, no auto-update watcher for
  new upstream Forgejo releases.
