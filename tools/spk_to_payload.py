#!/usr/bin/env python3
"""Turn a locally-built .spk into the JSON payload this repo's write API
expects, and optionally POST it directly.

Intentionally a single self-contained file (stdlib only, no imports from
the rest of this repo): it's meant to be copied into whatever *other*
project actually builds the .spk (e.g. its CI pipeline), which won't have
this repo checked out. Duplicates a small amount of parsing logic that
also lives in repo_server/spk_reader.py for that reason.

Usage:
    python3 spk_to_payload.py package.spk --link https://cdn.example.com/package.spk
    python3 spk_to_payload.py package.spk --link https://... \\
        --post http://repo-host:8000 --token "$API_TOKEN"
"""

import argparse
import hashlib
import json
import re
import sys
import tarfile
import urllib.request
from pathlib import Path

_INFO_LINE_RE = re.compile(r'^(\w+)="((?:[^"\\]|\\.)*)"$')


def _unescape(value: str) -> str:
    return value.replace('\\"', '"').replace("\\\\", "\\")


def parse_info_text(text: str) -> dict:
    fields = {}
    for line in text.splitlines():
        match = _INFO_LINE_RE.match(line.strip())
        if match:
            fields[match.group(1)] = _unescape(match.group(2))
    return fields


def parse_os_build(value: str | None) -> int | None:
    if not value or "-" not in value:
        return None
    try:
        return int(value.rsplit("-", 1)[1])
    except ValueError:
        return None


def read_info(spk_path: Path) -> dict:
    with tarfile.open(spk_path, mode="r:") as tar:
        info_member = tar.extractfile("INFO")
        if info_member is None:
            raise KeyError("INFO member missing from spk archive")
        return parse_info_text(info_member.read().decode("utf-8", errors="replace"))


def extract_icons(spk_path: Path, out_dir: Path) -> list[Path]:
    members = {"72": "PACKAGE_ICON.PNG", "256": "PACKAGE_ICON_256.PNG"}
    written = []
    out_dir.mkdir(parents=True, exist_ok=True)
    with tarfile.open(spk_path, mode="r:") as tar:
        for size, name in members.items():
            try:
                member = tar.extractfile(name)
            except KeyError:
                member = None
            if member is None:
                continue
            dest = out_dir / f"{spk_path.stem}_{size}.png"
            dest.write_bytes(member.read())
            written.append(dest)
    return written


def has_wizard_file(spk_path: Path, filename: str) -> bool:
    with tarfile.open(spk_path, mode="r:") as tar:
        try:
            tar.getmember(f"WIZARD_UIFILES/{filename}")
            return True
        except KeyError:
            return False


def fingerprint(path: Path, chunk_size: int = 1024 * 1024) -> tuple[str, int]:
    md5 = hashlib.md5()
    size = 0
    with open(path, "rb") as f:
        while chunk := f.read(chunk_size):
            md5.update(chunk)
            size += len(chunk)
    return md5.hexdigest(), size


def build_payload(spk_path: Path, link: str, thumbnail: str | None, thumbnail_retina: str | None) -> dict:
    info = read_info(spk_path)
    md5, size = fingerprint(spk_path)
    payload = {
        "package": info.get("package"),
        "version": info.get("version"),
        "archs": info.get("arch", "").split() or ["noarch"],
        "os_min_build": parse_os_build(info.get("os_min_ver") or info.get("firmware")),
        "os_max_build": parse_os_build(info.get("os_max_ver")),
        "displayname": info.get("displayname") or info.get("package"),
        "description": info.get("description", ""),
        "maintainer": info.get("maintainer", ""),
        "maintainer_url": info.get("maintainer_url", ""),
        "distributor": info.get("distributor", ""),
        "distributor_url": info.get("distributor_url", ""),
        "changelog": info.get("changelog", ""),
        "deppkgs": info.get("install_dep_packages", ""),
        "conflictpkgs": info.get("install_conflict_packages", ""),
        "startable": info.get("startable") != "no" and info.get("ctl_stop") != "no",
        "install_wizard": has_wizard_file(spk_path, "install_uifile"),
        "upgrade_wizard": has_wizard_file(spk_path, "upgrade_uifile"),
        "link": link,
        "md5": md5,
        "size": size,
        "thumbnail": [thumbnail] if thumbnail else [],
        "thumbnail_retina": [thumbnail_retina, thumbnail_retina] if thumbnail_retina else [],
    }
    if not payload["package"] or not payload["version"]:
        raise ValueError(f"{spk_path}: INFO is missing 'package' or 'version'")
    return payload


def post_payload(base_url: str, token: str, payload: dict) -> None:
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        base_url.rstrip("/") + "/api/packages",
        data=body,
        method="POST",
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(req) as resp:
        print(resp.read().decode("utf-8"))


def write_index(index_path: Path, payload: dict) -> None:
    """Upsert this payload into a local static index file (e.g.
    data/packages.json), in place of POSTing to a running
    server. Index shape: {package: [version_entry, ...]}."""
    index = {}
    if index_path.exists():
        index = json.loads(index_path.read_text(encoding="utf-8"))
    versions = index.setdefault(payload["package"], [])
    versions[:] = [v for v in versions if v["version"] != payload["version"]]
    versions.append(payload)
    index_path.parent.mkdir(parents=True, exist_ok=True)
    index_path.write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("spk_path", type=Path)
    parser.add_argument("--link", required=True, help="URL DSM will download the .spk from (GitHub Release/S3/etc.)")
    parser.add_argument("--thumbnail", help="URL of a 72x72 icon")
    parser.add_argument("--thumbnail-retina", help="URL of a 256x256 icon")
    parser.add_argument("--extract-icons", type=Path, help="dump embedded icons to this directory instead of/alongside posting")
    parser.add_argument("--post", metavar="BASE_URL", help="POST the payload to this repo server instead of printing it")
    parser.add_argument("--token", help="API token, required with --post")
    parser.add_argument(
        "--write-index",
        metavar="PATH",
        type=Path,
        help="upsert the payload into a local static index file instead of/alongside POSTing "
        "(e.g. data/packages.json -- commit and redeploy afterwards)",
    )
    args = parser.parse_args()

    if args.extract_icons:
        written = extract_icons(args.spk_path, args.extract_icons)
        for path in written:
            print(f"wrote {path}", file=sys.stderr)

    payload = build_payload(args.spk_path, args.link, args.thumbnail, args.thumbnail_retina)

    if args.write_index:
        write_index(args.write_index, payload)
        print(f"wrote {args.write_index}", file=sys.stderr)

    if args.post:
        if not args.token:
            parser.error("--post requires --token")
        post_payload(args.post, args.token, payload)
    elif not args.write_index:
        print(json.dumps(payload, indent=2))


if __name__ == "__main__":
    main()
