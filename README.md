# Synology packages repository

Support only DSM 7 x86_64

Tested on DSM 7.2

## Static site deployment

Renders the catalog to a single static JSON file for hosts with no
request-time code at all (GitHub Pages, Cloudflare Pages without Pages
Functions, S3, ...).

- **DSM7 clients only.** Always responds with `{"packages": [...]}` --
  no `keyrings` list, no bare-list fallback for DSM5/6.
- **No per-request filtering.** A static host serves the same file
  regardless of the `?build=&arch=` query string DSM appends, so arch/
  firmware-build filtering happens once at build time instead of per
  request. This only makes sense for a single-arch fleet where every
  published package is already valid for the DSM7 builds you run.
- **No write API / no runtime storage.** The index is
  `data/packages.json`, committed to git. Updating a package means
  editing that file and redeploying.

### Publish a package version

```bash
python3 tools/spk_to_payload.py package.spk \
  --link https://github.com/you/repo/releases/download/v1/package.spk \
  --thumbnail https://github.com/you/repo/releases/download/v1/icon72.png \
  --thumbnail-retina https://github.com/you/repo/releases/download/v1/icon256.png \
  --write-index data/packages.json
git add data/packages.json
git commit -m "feat: publish package v1"
```

`--extract-icons DIR` dumps the `.spk`'s embedded
`PACKAGE_ICON(.PNG|_256.PNG)` to local files if you need to upload those
somewhere too before you have URLs for them.

### Render it locally

```bash
python3 tools/render_static_catalog.py --arch x86_64 --build 64570 --out dist/index.json
```

No dependencies beyond Python 3 stdlib (3.9+, uses `dict`/`list` generics).
`--arch` must match what your fleet reports (`noarch` if none of your
packages are arch-specific). `--build` is a DSM7 firmware build number
(check yours under DSM's Control Panel -> Info Center, or `cat
/etc/VERSION` on the NAS) -- pick one high enough to clear every
package's `os_min_build`, unless a package sets an `os_max_build` cap you
need to respect. Commit nothing from `dist/` -- it's regenerated on every
deploy.

### Deploy: GitHub Pages

`.github/workflows/deploy-static-site.yml` builds and publishes `dist`
via GitHub's official Pages Actions on every push that touches the
catalog source or renderer. Set repo variables `SPK_ARCH`/`SPK_BUILD`
under Settings -> Secrets and variables -> Actions -> Variables, and
enable Pages with source "GitHub Actions" under Settings -> Pages. DSM's
Package Source "Location" then points at the deployed
`https://<user>.github.io/<repo>/` (or `.../index.json` if Pages doesn't
serve it at the bare path).

### Deploy: Cloudflare Pages

Connect the repo in the dashboard with build command
`python3 tools/render_static_catalog.py --arch <arch> --build <build> --out dist/index.json`
and output directory `dist`.

### Adding the repository to DSM

Package Center → Settings → Package Sources → Add:
- **Name:** anything
- **Location:** the deployed URL from whichever host above you used

## Metadata source of truth

`tools/spk_to_payload.py` reads the same `.spk`/`INFO` fields
already writes when building a package: `package`, `version`, `arch`,
`os_min_ver`/`os_max_ver` (or legacy `firmware`), `displayname`,
`description`, `maintainer(_url)`, `distributor(_url)`, `changelog`,
`install_dep_packages`, `install_conflict_packages`, `startable`/`ctl_stop`.
It also computes the `.spk` file's own MD5 + size (not the `checksum`
field inside `INFO`, which is `package.tgz`'s checksum, not the outer
archive's). `link`/`thumbnail`/`thumbnail_retina` are supplied explicitly
via CLI flags since nothing here has a local file to derive them from.

This script is intentionally a single self-contained file (stdlib only)
so it can be copied straight into whatever *other* project builds your
`.spk` -- it doesn't need this repo checked out. `--post`/`--token` (POST
to a running server's write API) and `--write-index PATH` (upsert into a
local static index file) are independent output modes -- use whichever
matches the deployment you picked.
