# packages/gitea

Builds a DSM7 x86_64 `.spk` for [Gitea](https://github.com/go-gitea/gitea)
(self-hosted Git service) from source, following the same build recipe as
the real, maintained [`SynoCommunity/spksrc`](https://github.com/SynoCommunity/spksrc)
`spk/gitea/` package. Same shape as `packages/forgejo/` (Forgejo is a
Gitea fork) -- see that package's `README.md` for a more detailed
explanation of the DSM7 packaging mechanics (privilege model, shared
folder wizard, etc.), which apply identically here.

## Build locally

Requires Go >= 1.24, Node >= 22, `make`, gcc (CGO is enabled for
sqlite), on an x86_64 Linux host (no cross-compilation). Gitea's
frontend build pins a specific `pnpm` version via its own
`package.json` `"packageManager"` field -- run `corepack enable` once
so `pnpm` resolves and installs that exact version automatically:

```bash
corepack enable
packages/gitea/build.sh --version 1.26.2
```

Fetches Gitea's release source archive
(`https://github.com/go-gitea/gitea/archive/v<version>.tar.gz`), builds
with `CGO_ENABLED=1 TAGS="bindata sqlite sqlite_unlock_notify" make build`
(Gitea's own Makefile already defaults its binary name to `gitea`, no
rename needed), with `LDFLAGS` embedding `CustomPath`/`CustomConf`/
`AppWorkPath`/`PIDFile` under `/var/packages/gitea/var` directly into the
binary. Packages the binary (`bin/gitea`) plus a pre-seeded
`var/conf.ini` into `packages/gitea/dist/gitea-<version>-x86_64.spk`.

`--os-min-ver` (default `7.0-40000`, i.e. DSM7) and `--out` (default
`packages/gitea/dist`) are optional overrides.

## What's different from packages/forgejo/

- Source: a plain GitHub release archive, not a vendored-deps tarball --
  needs `pnpm` (via corepack) at build time, where Forgejo's tarball
  already includes vendored frontend deps.
- Build tags: `bindata sqlite sqlite_unlock_notify` (no `timetzdata`).
- Go module path: `code.gitea.io/gitea/...` (Forgejo's is
  `forgejo.org/...`).
- `SERVICE_PORT = 8418` (Forgejo's is `8620`) -- deliberately different
  so both could be installed on the same NAS without a port clash.
- Everything else -- `conf/privilege`, `conf/resource`, wizard shape,
  `conf.ini` template, DSM7 lifecycle scripts -- is identical in
  structure, and the actual lifecycle script *files*
  (`functions`/`installer.dsm7`/`start-stop-status`/`preinst`/`postinst`/
  etc.) are the exact same shared files from
  `packages/_shared/spksrc-service/`, not per-package copies.

## CI: build, release, publish

`.github/workflows/build-gitea.yml` (`workflow_dispatch`, input
`version`) calls the shared reusable workflow
`.github/workflows/build-package.yml` with `package: gitea` -- same
build → release → `tools/spk_to_payload.py --write-index
data/packages.json` → commit pipeline documented in
`packages/forgejo/README.md`.

## Known simplifications and open risks

Same as `packages/forgejo/README.md`'s list -- not yet verified on a
real DSM7 NAS (`conf/resource` wizard-binding syntax, whether the
pre-seeded `conf.ini` fully suppresses Gitea's own first-run web
installer), no package icon, x86_64 only, one manual build per version.
