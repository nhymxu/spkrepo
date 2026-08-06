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

Requires Go >= 1.26, Node >= 20, `make`, gcc (CGO is enabled for
sqlite), on an x86_64 Linux host (no cross-compilation):

```bash
packages/forgejo/build.sh --version 15.0.4
```

Add `--rev N` (default `1`) to bump the *package* revision without
changing the upstream version -- e.g. a packaging-only fix (a
`conf/resource`/`service-setup` change, no new Forgejo release) rebuilds
the same `--version` with `--rev 2`, producing `15.0.4-2`. The upstream
fetch always uses the bare `--version` regardless of `--rev`.

Fetches Forgejo's own vendored-deps source tarball
(`forgejo-src-<version>.tar.gz` from its Codeberg release, not a git
clone), builds with
`CGO_ENABLED=1 TAGS="bindata timetzdata sqlite sqlite_unlock_notify" make build`
(binary is **not** renamed -- Forgejo forked from Gitea and keeps the
binary named `gitea`), with `LDFLAGS` embedding `CustomPath`/`CustomConf`/
`AppWorkPath`/`PIDFile` under `/var/packages/forgejo/var` directly into
the binary. Packages the binary (`bin/gitea`) plus a pre-seeded
`var/conf.ini` into
`packages/forgejo/dist/forgejo-<version>-<rev>-x86_64.spk`.

`--os-min-ver` (default `7.0-40000`, i.e. DSM7) and `--out` (default
`packages/forgejo/dist`) are optional overrides. The final `.spk`'s
`INFO` `version=` and filename both use `<version>-<rev>`
(`forgejo-15.0.4-1-x86_64.spk` with the default `--rev 1`), which the
catalog's natural-sort version comparator (`tools/dsm_catalog.py`)
already orders correctly against both bare and revved versions.

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
- **`conf/privilege`** -- `run-as: package` under a dedicated service
  account `sc-forgejo` (username kept identical to SynoCommunity's package
  so its existing data, owned `sc-forgejo:*`, stays accessible without a
  re-chown) in group `nhymxu-pkg` (shared by every package in this repo).
- **`conf/resource`** -- declares/creates a shared folder (named via the
  install wizard) and grants the package's account read-write access.
- **`wizard/install_uifile`, `upgrade_uifile`** -- installer asks for a
  shared-folder name (`wizard_shared_folder_name`) to store repos in;
  upgrade wizard reminds about manual `conf.ini` review.
- **`conf.ini`** -- pre-seeded template (repo root, domain/IP, LFS path)
  so Forgejo skips its own interactive web installer.

## CI: build, release, publish

`.github/workflows/build-forgejo.yml` (`workflow_dispatch`, inputs
`version` and `rev`, the latter defaulting to `1`) is a thin dispatcher
that calls the shared reusable workflow
`.github/workflows/build-package.yml` with `package: forgejo` --
`packages/gitea/` uses the same reusable workflow with `package: gitea`,
so adding a third package only needs a new one-line dispatcher, not a
new copy of the whole pipeline. The reusable workflow:

1. Runs `packages/<package>/build.sh --version <version> --rev <rev>`.
2. `gh release create <package>-v<version>-<rev>` and uploads the `.spk`
   as a release asset.
3. `python3 tools/spk_to_payload.py <spk> --link <release-asset-url>
   --write-index data/packages.json` (the shared tool at the repo root --
   intentionally reused here, since it's built to be called by any
   project that produces a `.spk`).
4. Commits and pushes `data/packages.json` -- auto-triggers the root
   `deploy-static-site.yml` Pages redeploy.

## Expected behaviour worth knowing

**The first-run web installer appears on first start. That is intended, not
a packaging bug.** `INSTALL_LOCK` defaults to `false`
(`modules/setting/setting.go`, `Key("INSTALL_LOCK").MustBool(false)`) and
`cmd/web.go` serves the installer whenever it is unset. spksrc's own
`spk/forgejo/src/conf.ini` omits the key too -- ours is byte-identical to
theirs -- so the seeded `conf.ini` is there to *pre-fill* the installer's
defaults (repository root, domain, port), not to bypass it. Completing the
wizard writes `INSTALL_LOCK = true` and it stops appearing. Gitea behaves
identically; see `packages/gitea/README.md`.

## Settled by real installs

- **`conf/resource` share binding** matches SynoCommunity's proven syntax:
  the `data-share` name uses DSM's `{{wizard_shared_folder_name}}` template
  placeholder (not shell `${...}`, which DSM passes through literally -- the
  cause of the "Unable to create a shared folder named
  ${wizard_shared_folder_name}" install error), and `permission.rw` lists
  the package account by literal name (`sc-forgejo`). `service-setup` derives
  `SHARE_PATH` (`/var/packages/<pkg>/shares/<name>`) so the `@share_path@`
  seed in `conf.ini` resolves.
- **Package Center icon** comes from base64 `package_icon`/`package_icon_256`
  in `INFO`; without them an installed package shows the default Synology
  icon.

Both were found and fixed by installing on a real DSM7 NAS. They apply
unchanged to every package in this repo -- the lifecycle scripts are the
same files from `packages/_shared/spksrc-service/` and the icon embedding
is the same shared helper.

## Known simplifications and open risks

- `LOG_FILE`/`PID_FILE` defaults in `service-setup` are our own explicit
  choices (consistent with the paths spksrc's build embeds via ldflags)
  -- the real package's `service-setup.sh` excerpt we found didn't show
  where it defines these, so this isn't a byte-for-byte copy of that
  part.
- SynoCommunity ships its own `forgejo` package. DSM identifies a package
  by `INFO`'s `package=` name, so on a NAS that already has theirs
  installed, Package Center treats this one as the same package. The
  service account name is deliberately kept as `sc-forgejo` for that
  reason (existing repository data stays accessible), but the overlap
  itself is untested.
- x86_64 only; one manual build per version, no auto-update watcher for
  new upstream Forgejo releases.
