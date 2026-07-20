"""Shape the static package catalog into the JSON DSM Package Center expects.

Standalone port of the same DSM7 filtering rules used elsewhere in this
repo (kept independent by design -- this project has no runtime dependency
on any other folder here):
- arch matching is a direct string match (or "noarch")
- firmware compatibility is a plain build-number range check
- DSM7-only: always returns {"packages": [...]} (no "keyrings", no bare-list
  DSM5 fallback -- this deployment target intentionally doesn't support
  pre-DSM7 clients, see README).
"""

import re
from typing import Any

Catalog = dict[str, list[dict[str, Any]]]

_VERSION_SPLIT_RE = re.compile(r"(\d+)")


def _version_parts(version: str) -> list[Any]:
    parts = [part for part in _VERSION_SPLIT_RE.split(version) if part != ""]
    return [int(part) if part.isdigit() else part for part in parts]


def _compare_versions(a: str, b: str) -> int:
    """Natural-sort comparison so "1.10.0-2" > "1.9.0-1"."""
    parts_a = _version_parts(a)
    parts_b = _version_parts(b)
    for pa, pb in zip(parts_a, parts_b):
        if isinstance(pa, int) and isinstance(pb, int):
            if pa != pb:
                return pa - pb
        else:
            sa, sb = str(pa), str(pb)
            if sa != sb:
                return -1 if sa < sb else 1
    return len(parts_a) - len(parts_b)


def _entry_matches(entry: dict[str, Any], arch: str, build: int) -> bool:
    archs = entry["archs"]
    if arch not in archs and "noarch" not in archs:
        return False
    os_min_build = entry.get("os_min_build")
    if os_min_build is not None and build < os_min_build:
        return False
    os_max_build = entry.get("os_max_build")
    if os_max_build is not None and build > os_max_build:
        return False
    return True


def _pick_latest(entries: list[dict[str, Any]]) -> dict[str, Any]:
    latest = entries[0]
    for entry in entries[1:]:
        if _compare_versions(entry["version"], latest["version"]) > 0:
            latest = entry
    return latest


def _build_package_dict(entry: dict[str, Any]) -> dict[str, Any]:
    has_install_wizard = entry.get("install_wizard", False)
    has_upgrade_wizard = entry.get("upgrade_wizard", False)
    result: dict[str, Any] = {
        "package": entry["package"],
        "version": entry["version"],
        "dname": entry["displayname"],
        "desc": entry["description"],
        "link": entry["link"],
        "thumbnail": entry["thumbnail"],
        "qinst": not has_install_wizard,
        "qupgrade": not has_upgrade_wizard,
        "qstart": entry["startable"] and not has_install_wizard,
        "snapshot": [],
    }

    if entry["deppkgs"]:
        result["deppkgs"] = entry["deppkgs"]
    if entry["conflictpkgs"]:
        result["conflictpkgs"] = entry["conflictpkgs"]

    if entry["thumbnail_retina"]:
        result["thumbnail_retina"] = entry["thumbnail_retina"]

    for key in ("changelog", "distributor", "distributor_url", "maintainer", "maintainer_url", "md5"):
        value = entry.get(key)
        if value:
            result[key] = value
    if entry.get("size"):
        result["size"] = entry["size"]

    if not entry["startable"]:
        result["startable"] = "no"

    return result


def build_catalog_response(catalog: Catalog, arch: str, build: int) -> dict[str, list[dict[str, Any]]]:
    packages: list[dict[str, Any]] = []
    for entries in catalog.values():
        matching = [entry for entry in entries if _entry_matches(entry, arch, build)]
        if matching:
            packages.append(_build_package_dict(_pick_latest(matching)))
    return {"packages": packages}
