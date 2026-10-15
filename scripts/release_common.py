"""Shared release archive, source-reference and integrity helpers."""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import stat
import zipfile
from pathlib import Path, PurePosixPath


WEB_SCRIPTS = ("launch.ps1", "common.ps1", "serve.py", "stop.ps1")


CACHE_NAMES = {
    ".git", ".dart_tool", "build", ".idea", ".vscode", "ephemeral",
    "node_modules", "__pycache__", ".pytest_cache", ".DS_Store", "Thumbs.db",
    ".flutter-plugins", ".flutter-plugins-dependencies",
}


HASH_RE = re.compile(r"[0-9a-f]{64}")


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return stream_digest(stream)


def stream_digest(stream) -> str:
    checksum = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b""):
        checksum.update(block)
    return checksum.hexdigest()


def safe_relative(name: str) -> str:
    """Accept unambiguous portable relative paths, including on Windows."""
    path = PurePosixPath(name)
    if (not name or not path.parts or "\\" in name or ":" in name or "\x00" in name
            or path.is_absolute() or path.as_posix() != name
            or any(part in {".", ".."} or part.endswith((".", " "))
                   for part in path.parts)):
        raise ValueError(f"Unsafe relative path: {name!r}")
    return name


def file_hashes(directory: Path) -> dict[str, str]:
    entries = {}
    folded = set()
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"Symbolic links are not allowed in packages: {path}")
        if path.is_dir():
            continue
        if not path.is_file():
            raise ValueError(f"Non-regular package file: {path}")
        relative = safe_relative(path.relative_to(directory).as_posix())
        if relative.casefold() in folded:
            raise ValueError(f"Case-ambiguous package path: {relative}")
        folded.add(relative.casefold())
        entries[relative] = digest(path)
    return entries


def manifest_hashes(directory: Path) -> dict[str, str]:
    entries = {}
    folded = set()
    for line in (directory / "FILES.sha256").read_text(encoding="utf-8-sig").splitlines():
        if len(line) < 67 or line[64:66] != "  " or not HASH_RE.fullmatch(line[:64]):
            raise ValueError(f"Malformed manifest line in {directory}: {line!r}")
        checksum, relative = line[:64], safe_relative(line[66:])
        if relative == "FILES.sha256" or relative.casefold() in folded:
            raise ValueError(f"Unsafe or duplicated manifest entry: {relative}")
        entries[relative] = checksum
        folded.add(relative.casefold())
    if not entries:
        raise ValueError(f"Empty manifest: {directory}")
    actual = file_hashes(directory)
    if set(actual) != set(entries) | {"FILES.sha256"}:
        missing = sorted(set(entries) - set(actual))
        extra = sorted(set(actual) - set(entries) - {"FILES.sha256"})
        raise ValueError(f"Manifest inventory differs in {directory}: missing={missing}, extra={extra}")
    for relative, expected in entries.items():
        if actual[relative] != expected:
            raise ValueError(f"File hash mismatch: {directory / relative}")
    return entries


def verify_package(directory: Path) -> dict:
    """Verify a package and its adjacent ZIP/sidecar; works after clean extraction.

    This deliberately has no source-layout assumptions, so it verifies both
    player packages and the separate corresponding source archive.
    """
    directory = Path(directory).resolve(strict=True)
    entries = manifest_hashes(directory)
    archive = directory.with_name(directory.name + ".zip")
    sidecar = archive.with_name(archive.name + ".sha256")
    line = sidecar.read_text(encoding="utf-8-sig").strip()
    if (len(line) < 67 or line[64:66] != "  " or not HASH_RE.fullmatch(line[:64])
            or line[66:] != archive.name):
        raise ValueError(f"Invalid archive SHA-256 sidecar: {sidecar}")
    expected_archive_hash = line[:64]
    if digest(archive) != expected_archive_hash:
        raise ValueError(f"Archive SHA-256 does not match its sidecar: {archive}")
    expected_files = {**entries, "FILES.sha256": digest(directory / "FILES.sha256")}
    with zipfile.ZipFile(archive) as bundle:
        members = bundle.infolist()
        names = [entry.filename for entry in members]
        if len(names) != len(set(name.casefold() for name in names)):
            raise ValueError(f"Duplicate or case-ambiguous ZIP entries: {archive}")
        for entry in members:
            safe_relative(entry.filename)
            if stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError(f"ZIP contains a symbolic link: {entry.filename}")
        if set(names) != {f"{directory.name}/{name}" for name in expected_files}:
            raise ValueError(f"ZIP and directory inventories differ: {archive}")
        # Reading each member to EOF validates its CRC and its complete contents,
        # including a substituted ZIP whose own sidecar was regenerated.
        for relative, expected in expected_files.items():
            with bundle.open(f"{directory.name}/{relative}") as stream:
                if stream_digest(stream) != expected:
                    raise ValueError(f"ZIP file hash mismatch: {relative}")
    return {
        "status": "passed", "package": str(directory), "archive": str(archive),
        "archive_sha256": expected_archive_hash, "archive_bytes": archive.stat().st_size,
        "verified_file_hashes": len(entries), "zip_crc_and_inventory": "passed",
        "zip_file_hashes": "passed",
    }


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def filtered_source_hashes(directory: Path) -> dict[str, str]:
    """Inventory an extracted source tree without generated build/cache state."""
    entries = {}
    for current, directories, files in os.walk(directory):
        directories[:] = [name for name in directories if name not in CACHE_NAMES]
        for name in [*directories, *files]:
            if (Path(current) / name).is_symlink():
                raise ValueError(f"Symbolic links are not allowed in source: {Path(current) / name}")
        for name in files:
            if name in CACHE_NAMES or name.endswith((".log", ".pyc", ".pyo")):
                continue
            path = Path(current) / name
            relative = safe_relative(path.relative_to(directory).as_posix())
            entries[relative] = digest(path)
    return entries


def cache_ignore(directory: str, names: list[str]) -> set[str]:
    return {name for name in names if name in CACHE_NAMES or name.endswith((".log", ".pyc", ".pyo"))}


def copy_file(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def require_files(directory: Path, names: tuple[str, ...]) -> None:
    for name in names:
        if not (directory / name).is_file():
            raise ValueError(f"Required runtime/distribution file is missing: {directory / name}")


def runtime_hashes(package: Path, target: str) -> dict[str, str]:
    if target == "web":
        require_files(package, ("web/index.html", "web/main.dart.js", "web/flutter_bootstrap.js", "web/sw.js"))
        return {f"web/{name}": value for name, value in file_hashes(package / "web").items()}
    require_files(package, (
        "lcs_new_age.exe", "flutter_windows.dll", "msvcp140.dll", "vcruntime140.dll",
        "vcruntime140_1.dll", "data/app.so", "data/icudtl.dat", "data/flutter_assets/NOTICES.Z",
    ))
    result = {f"data/{name}": value for name, value in file_hashes(package / "data").items()}
    for path in package.iterdir():
        if path.is_file() and (path.suffix.lower() in {".exe", ".dll"} or path.name == "native_assets.json"):
            result[path.name] = digest(path)
    return result


def archive_package(directory: Path) -> dict:
    entries = file_hashes(directory)
    (directory / "FILES.sha256").write_text(
        "".join(f"{value}  {name}\n" for name, value in sorted(entries.items())), encoding="utf-8",
    )
    archive = directory.with_name(directory.name + ".zip")
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        for path in sorted(directory.rglob("*")):
            if path.is_file():
                # Fixed timestamps/permissions avoid host-specific ZIP metadata.
                entry = zipfile.ZipInfo(f"{directory.name}/{path.relative_to(directory).as_posix()}")
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = (stat.S_IFREG | 0o644) << 16
                with path.open("rb") as source, bundle.open(entry, "w", force_zip64=True) as output:
                    shutil.copyfileobj(source, output, length=1024 * 1024)
    archive.with_name(archive.name + ".sha256").write_text(
        f"{digest(archive)}  {archive.name}\n", encoding="utf-8",
    )
    return verify_package(directory)


def source_reference(source_archive: str, source_sha256: str, source_url: str, identity: dict) -> str:
    return (
        "# Corresponding source\n\n"
        f"The complete matching modified source is a separate download: [{source_archive}]({source_url}).\n\n"
        f"SHA-256: `{source_sha256}`\n\n"
        f"Runtime source commit: `{identity['runtime_source_commit']}`. "
        f"Distribution scripts and documentation commit: `{identity['packaging_commit']}`.\n\n"
        "The source ZIP contains the modified game under `upstream/`, including artwork, generated "
        "serialization and locked dependencies, plus build scripts, documentation, license and credits. "
        "See its `docs/BUILDING.md` for rebuilding and `SOURCE_INFO.md` for provenance. "
        "The original upstream repository alone is not the matching modified source.\n\n"
        "When redistributing the binaries, provide the corresponding source under the included GPL v2 terms; "
        "keep the matching source download available alongside the player download.\n"
    )
