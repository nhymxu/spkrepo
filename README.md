# Synology packages repository

DSM 7 only, x86_64. Tested on DSM 7.2.

## Packages

- `packages/` holds `.spk` build pipelines for specific apps.
  - [`packages/forgejo/`](packages/forgejo/README.md)
  - [`packages/gitea/`](packages/gitea/README.md)
- Generic DSM7 packaging scripts: [`packages/_shared/spksrc-service/`](packages/_shared/spksrc-service/NOTICE.md)
- Each app's CI dispatches into the shared workflow `.github/workflows/build-package.yml`.

## Static site deployment

Renders the catalog as a single static JSON file. No runtime code.

- **DSM7 only** — responds with `{"packages": [...]}`, no legacy DSM5/6 formats.
- **No per-request filtering** — arch/firmware filtering happens at build time. Suits a single-arch fleet.
- **No write API / no runtime storage** — `data/packages.json` is the source of truth, committed to git.

### Publish a package version

```bash
python3 tools/spk_to_payload.py package.spk \
  --link https://github.com/you/repo/releases/download/v1/package.spk \
  --thumbnail https://you.github.io/repo/icons/package-72.png \
  --thumbnail-retina https://you.github.io/repo/icons/package-256.png \
  --write-index data/packages.json
git add data/packages.json
git commit -m "feat: publish package v1"
```

`--extract-icons DIR` extracts `.spk` icons to local files before you have URLs for them.

### Render locally

```bash
python3 tools/render_static_catalog.py --arch x86_64 --build 64570 --out dist/index.json
python3 tools/render_static_page.py --arch x86_64 --build 64570 --out dist/index.html
```

Python 3.9+ stdlib only. `dist/` is regenerated on each deploy — don't commit it.

### Deploy: GitHub Pages

`.github/workflows/deploy-static-site.yml` builds and deploys `dist` via GitHub Pages.

- Set `SPK_ARCH` / `SPK_BUILD` under Settings → Secrets and variables → Actions → Variables.
- Enable Pages with source "GitHub Actions" under Settings → Pages.
- Point DSM Package Source Location at `https://<user>.github.io/<repo>/index.json`.
- Browsers get `index.html` at the bare URL, DSM gets JSON at `index.json`.
- Icons are copied from `packages/<app>/` to `dist/icons/` and served from Pages, not Release assets.

### Deploy: Cloudflare Pages

Connect the repo with build command:

```bash
python3 tools/render_static_catalog.py --arch <arch> --build <build> --out dist/index.json \
  && python3 tools/render_static_page.py --arch <arch> --build <build> --out dist/index.html
```

Output directory: `dist`.

### Add to DSM

Package Center → Settings → Package Sources → Add. Points Location at the deployed `index.json` URL.

## Metadata tooling

`tools/spk_to_payload.py` reads `.spk`/`INFO` fields (`package`, `version`, `arch`, `os_min_ver`, etc.) and computes MD5 + size of the `.spk` file itself. `link`/`thumbnail`/`thumbnail_retina` are supplied via CLI flags.

Self-contained (stdlib only) — can be copied into other projects. Output modes: `--post` (HTTP POST) or `--write-index` (local JSON file).

## Credits

[`SynoCommunity/spksrc`](https://github.com/SynoCommunity/spksrc) — the reference this repo's build recipes are modeled on. `packages/_shared/spksrc-service/` vendors `functions`, `installer.dsm7`, and `start-stop-status` verbatim from spksrc's `mk/spksrc.service/` (3-clause BSD, © 2011 Sebastien Erard — full license in `NOTICE.md`).
