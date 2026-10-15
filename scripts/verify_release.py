"""Verify a complete release directory, its file manifest and its ZIP archive."""
from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from pathlib import Path

from audit_fidelity import sha as fidelity_sha


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    package = args.package.resolve(strict=True)
    archive = package.with_suffix(".zip")
    expected_archive_hash = archive.with_suffix(".zip.sha256").read_text().split()[0]
    if digest(archive) != expected_archive_hash:
        raise ValueError("Archive SHA-256 does not match its sidecar")

    entries = {}
    for line in (package / "FILES.sha256").read_text(encoding="utf-8").splitlines():
        expected, relative = line.split("  ", 1)
        target = (package / relative).resolve(strict=True)
        if not target.is_relative_to(package) or relative in entries:
            raise ValueError(f"Unsafe or duplicated manifest entry: {relative}")
        if digest(target) != expected:
            raise ValueError(f"File hash mismatch: {relative}")
        entries[relative] = expected
    actual = {
        path.relative_to(package).as_posix()
        for path in package.rglob("*") if path.is_file()
    }
    if actual != set(entries) | {"FILES.sha256"}:
        raise ValueError("Release files and manifest inventory differ")
    if not (package / "source/upstream/lib/main.dart").is_file():
        raise ValueError("Corresponding modified source is missing")
    for name in ("LICENSE", "AUTHORS.md", "docs/FIDELITY_AUDIT.json"):
        if not (package / name).is_file():
            raise ValueError(f"Required release document is missing: {name}")
    audit = json.loads((package / "docs/FIDELITY_AUDIT.json").read_text())
    if audit.get("status") != "passed" or audit.get("failures"):
        raise ValueError("Packaged fidelity audit did not pass")
    audit_script = package / "source/scripts/audit_fidelity.py"
    if digest(audit_script) != audit["audit_script_sha256"]:
        raise ValueError("Packaged audit script differs from the recorded reviewer gate")
    audited_files = 0
    for entry in [*audit["files"], *audit["additions"]]:
        relative = entry["path"]
        source_root = package / "source/upstream"
        target = (source_root / relative).resolve(strict=True)
        if not target.is_relative_to(source_root):
            raise ValueError(f"Unsafe fidelity entry: {relative}")
        expected = entry.get("current_sha256", entry.get("sha256"))
        if fidelity_sha(target.read_bytes(), relative) != expected:
            raise ValueError(f"Corresponding source differs from reviewed snapshot: {relative}")
        audited_files += 1

    with zipfile.ZipFile(archive) as bundle:
        members = bundle.namelist()
        if len(members) != len(set(members)):
            raise ValueError("Duplicate ZIP entries")
        if set(members) != {f"{package.name}/{name}" for name in actual}:
            raise ValueError("ZIP and directory inventories differ")
        bad_file = bundle.testzip()
        if bad_file:
            raise ValueError(f"ZIP CRC failure: {bad_file}")
    result = {
        "status": "passed",
        "package": str(package),
        "archive": str(archive),
        "archive_sha256": expected_archive_hash,
        "verified_file_hashes": len(entries),
        "zip_crc_and_inventory": "passed",
        "corresponding_source_and_fidelity": "passed",
        "verified_audited_source_and_asset_files": audited_files,
    }
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
