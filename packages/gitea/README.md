# packages/gitea

Builds a DSM7 x86_64 `.spk` for [Gitea](https://github.com/go-gitea/gitea)
(self-hosted Git service) from source, following the same build recipe as
the real, maintained [`SynoCommunity/spksrc`](https://github.com/SynoCommunity/spksrc)
`spk/gitea/` package. Same shape as `packages/forgejo/` (Forgejo is a
Gitea fork) -- see that package's `README.md` for a more detailed
explanation of the DSM7 packaging mechanics (privilege model, shared
folder wizard, etc.), which apply identically here.

## Build locally

Requires Go >= 1.26.4 and Node >= 22.18 (1.27.1's `go.mod` and
`package.json` `engines`; CI uses Go 1.26 / Node 24), plus `make` and gcc (CGO is enabled for
sqlite), on an x86_64 Linux host (no cross-compilation). Gitea's
frontend build pins a specific `pnpm` version via its own
`package.json` `"packageManager"` field -- run `corepack enable` once
so `pnpm` resolves and installs that exact version automatically:

```bash
corepack enable
packages/gitea/build.sh --version 1.27.1
```

Add `--rev N` (default `1`) to bump the *package* revision without
changing the upstream version -- e.g. a packaging-only fix rebuilds the
same `--version` with `--rev 2`, producing `1.27.1-2`. The upstream
fetch always uses the bare `--version` regardless of `--rev`.

Fetches Gitea's release source archive
(`https://github.com/go-gitea/gitea/archive/v<version>.tar.gz`), builds
with `CGO_ENABLED=1 TAGS="bindata sqlite sqlite_unlock_notify" make build`
(Gitea's own Makefile already defaults its binary name to `gitea`, no
rename needed), with `LDFLAGS` embedding `CustomPath`/`CustomConf`/
`AppWorkPath`/`PIDFile` under `/var/packages/gitea/var` directly into the
binary. Packages the binary (`bin/gitea`) plus a pre-seeded
`var/conf.ini` into
`packages/gitea/dist/gitea-<version>-<rev>-x86_64.spk`.

Those `LDFLAGS` are the only thing pointing Gitea at the pre-seeded
`conf.ini` -- `service-setup` passes neither `--config` nor
`GITEA_WORK_DIR`/`GITEA_CUSTOM` -- and the Go linker drops a `-X` naming
a symbol it cannot resolve *without failing the build*. Two guards keep
that from shipping silently:

- The module path is read from the unpacked `go.mod` rather than
  hardcoded, so a module rename (Gitea did exactly this in 1.27, see
  below) is picked up automatically.
- After the build, every `-X` target is looked up in the binary's symbol
  table via `go tool nm`; a moved or renamed variable fails the build
  instead of producing a package that ignores its own `conf.ini` and
  re-runs the first-run web installer.

`--os-min-ver` (default `7.0-40000`, i.e. DSM7) and `--out` (default
`packages/gitea/dist`) are optional overrides. The final `.spk`'s
`INFO` `version=` and filename both use `<version>-<rev>`
(`gitea-1.27.1-1-x86_64.spk` with the default `--rev 1`), which the
catalog's natural-sort version comparator (`tools/dsm_catalog.py`)
already orders correctly against both bare and revved versions.

## What's different from packages/forgejo/

- Source: a plain GitHub release archive, not a vendored-deps tarball --
  needs `pnpm` (via corepack) at build time, where Forgejo's tarball
  already includes vendored frontend deps.
- Build tags: `bindata sqlite sqlite_unlock_notify` (no `timetzdata`).
- Go module path: `gitea.dev/...` as of 1.27 (it was
  `code.gitea.io/gitea/...` up to and including 1.26; Forgejo's is
  `forgejo.org/...`). `build.sh` reads it from `go.mod`, so it handles
  either. Upstream spksrc still pins 1.26.2 and hardcodes the old path,
  which is why its recipe cannot be copied verbatim for 1.27.
- `PIDFile` is declared in package `cmd` (`cmd/web.go`), not
  `modules/setting` -- in Gitea *and* Forgejo. spksrc's Makefile targets
  `setting.PIDFile`, which resolves to nothing; this package targets
  `<module>/cmd.PIDFile`. Cosmetic either way, since `service-setup`
  passes `--pid` explicitly.
- `SERVICE_PORT = 8418` (Forgejo's is `8620`) -- deliberately different
  so both could be installed on the same NAS without a port clash.
- Everything else -- `conf/privilege`, `conf/resource`, wizard shape,
  `conf.ini` template, DSM7 lifecycle scripts -- is identical in
  structure, and the actual lifecycle script *files*
  (`functions`/`installer.dsm7`/`start-stop-status`/`preinst`/`postinst`/
  etc.) are the exact same shared files from
  `packages/_shared/spksrc-service/`, not per-package copies.

## CI: build, release, publish

`.github/workflows/build-gitea.yml` (`workflow_dispatch`, inputs
`version` and `rev`, the latter defaulting to `1`) calls the shared
reusable workflow
`.github/workflows/build-package.yml` with `package: gitea` -- same
build → release → `tools/spk_to_payload.py --write-index
data/packages.json` → commit pipeline documented in
`packages/forgejo/README.md`.

## Known simplifications and open risks

Same as `packages/forgejo/README.md`'s list, read for Gitea:

- `conf/resource` binds the share via DSM's `{{wizard_shared_folder_name}}`
  placeholder with `permission.rw` naming `sc-gitea` literally; not yet
  verified on a real DSM7 NAS.
- Whether the pre-seeded `conf.ini` alone suppresses Gitea's own
  first-run web installer is unverified -- please test an actual install
  and report back.
- `LOG_FILE`/`PID_FILE` in `service-setup` are our own explicit choices,
  consistent with the paths the build embeds via ldflags.
- x86_64 only; one manual build per version, no auto-update watcher for
  new upstream Gitea releases.
