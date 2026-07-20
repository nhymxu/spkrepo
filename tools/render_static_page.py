#!/usr/bin/env python3
"""Build-time renderer for the human-facing info page served alongside
index.json. GitHub Pages (and most static hosts) prefer index.html over
index.json at the bare directory path, so once this file exists browsers
requesting the repo root get this page while index.json keeps serving the
same DSM7 catalog for Package Center. See tools/render_static_catalog.py
for the JSON renderer this reuses filtering logic from.

Usage:
    python3 tools/render_static_page.py --arch x86_64 --build 64570 --out dist/index.html
"""

import argparse
import html
import json
import sys
from pathlib import Path

from dsm_catalog import build_catalog_response

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DATA = ROOT / "data" / "packages.json"

PAGE_TEMPLATE = """<!doctype html>
<html lang="en" style="color-scheme: light;">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<title>{title}</title>
<style>
  body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
         max-width: 720px; margin: 2rem auto; padding: 0 1rem; color: #1b1f23; background: #ffffff; }}
  h1 {{ font-size: 1.5rem; }}
  h2.section {{ font-size: 1.1rem; margin-top: 2rem; }}
  code {{ background: #f0f0f0; padding: 0.1rem 0.35rem; border-radius: 3px; }}
  .guide {{ border: 1px solid #d0d7de; border-radius: 6px; padding: 1rem 1.25rem; background: #f6f8fa; }}
  .guide ol {{ margin: 0; padding-left: 1.25rem; }}
  .guide li {{ margin: 0.5rem 0; }}
  .pkg {{ border: 1px solid #d0d7de; border-radius: 6px; padding: 1rem; margin: 1rem 0; }}
  .pkg h2 {{ margin: 0 0 0.25rem; font-size: 1.1rem; }}
  .pkg .meta {{ color: #57606a; font-size: 0.85rem; margin-bottom: 0.5rem; }}
  .empty {{ color: #57606a; }}
  footer {{ margin-top: 2rem; color: #57606a; font-size: 0.85rem; }}
</style>
</head>
<body>
<h1>{title}</h1>
<p>Synology DSM 7 package repository.</p>
<h2 class="section">Quick guide: add this source to Package Center</h2>
<div class="guide">
<ol>
  <li>Open <strong>Package Center</strong> on your NAS.</li>
  <li>Go to <strong>Settings</strong> &rarr; <strong>Package Sources</strong> &rarr; <strong>Add</strong>.</li>
  <li><strong>Name:</strong> anything you like.</li>
  <li><strong>Location:</strong> <code>{index_url}</code> &mdash; use this exact URL,
      not the page you are viewing now.</li>
  <li>Click <strong>Save</strong>, then find the packages under the
      <strong>Community</strong> tab of Package Center.</li>
</ol>
</div>
{packages_html}
<footer>Machine-readable catalog: <a href="index.json">index.json</a></footer>
</body>
</html>
"""

PACKAGE_TEMPLATE = """<div class="pkg">
  <h2>{dname} <small>{version}</small></h2>
  <div class="meta">{package} &middot; {size}</div>
  <p>{desc}</p>
</div>
"""


def _format_size(num_bytes: int) -> str:
    size = float(num_bytes)
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024:
            return f"{size:.0f}{unit}" if unit == "B" else f"{size:.1f}{unit}"
        size /= 1024
    return f"{size:.1f}TB"


def render_page(catalog_response: dict, index_url: str) -> str:
    packages = catalog_response["packages"]
    if packages:
        packages_html = "\n".join(
            PACKAGE_TEMPLATE.format(
                dname=html.escape(pkg["dname"]),
                version=html.escape(pkg["version"]),
                package=html.escape(pkg["package"]),
                size=_format_size(pkg["size"]) if pkg.get("size") else "size unknown",
                desc=html.escape(pkg["desc"]),
            )
            for pkg in packages
        )
    else:
        packages_html = '<p class="empty">No packages published yet.</p>'

    return PAGE_TEMPLATE.format(
        title="Synology Package Repository",
        index_url=html.escape(index_url),
        packages_html=packages_html,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--arch", required=True, help="must match what your fleet reports (noarch if arch-agnostic)")
    parser.add_argument("--build", required=True, type=int, help="DSM7 firmware build number")
    parser.add_argument("--out", default="dist/index.html", help="output path (default: dist/index.html)")
    parser.add_argument("--data", default=str(DEFAULT_DATA), help="source index (default: data/packages.json)")
    parser.add_argument("--index-url", default="index.json", help="link/path shown to the JSON catalog (default: index.json)")
    args = parser.parse_args()

    catalog = json.loads(Path(args.data).read_text(encoding="utf-8"))
    result = build_catalog_response(catalog, args.arch, args.build)

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(render_page(result, args.index_url), encoding="utf-8")
    print(f"wrote {out_path} ({len(result['packages'])} package(s) listed)", file=sys.stderr)


if __name__ == "__main__":
    main()
