#!/usr/bin/env python3
"""Build-time renderer for pure static hosts (GitHub Pages, Cloudflare Pages
without Functions, S3, ...) -- there's no request handler there, so instead
of filtering per request, this runs the dsm_catalog filtering once against
one target arch/build pair and writes a single JSON file. That file gets
served byte-for-byte to every request regardless of the `?build=&arch=`
query string DSM appends -- static hosts ignore query strings for routing.

Self-contained: this project owns its own data/packages.json and
dsm_catalog.py, independent of anything in future-deployments/. Same repo,
unrelated runtime.

Usage:
    python3 tools/render_static_catalog.py --arch x86_64 --build 64570 --out dist/index.json
"""

import argparse
import json
import sys
from pathlib import Path

from dsm_catalog import build_catalog_response

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DATA = ROOT / "data" / "packages.json"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--arch", required=True, help="must match what your fleet reports (noarch if arch-agnostic)")
    parser.add_argument("--build", required=True, type=int, help="DSM7 firmware build number")
    parser.add_argument("--out", default="dist/index.json", help="output path (default: dist/index.json)")
    parser.add_argument("--data", default=str(DEFAULT_DATA), help="source index (default: data/packages.json)")
    args = parser.parse_args()

    catalog = json.loads(Path(args.data).read_text(encoding="utf-8"))
    result = build_catalog_response(catalog, args.arch, args.build)

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result), encoding="utf-8")
    print(
        f"wrote {out_path} ({len(result['packages'])} package(s), arch={args.arch} build={args.build})",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
