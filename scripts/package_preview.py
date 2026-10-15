"""Split verified combined preview packages into two players and matching source.

The existing compiled games and corresponding upstream source are inputs, never
rebuilt or edited here. Every input and output is checked against its manifest,
ZIP inventory, ZIP CRCs, and SHA-256 sidecar before distribution.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import zipfile
from pathlib import Path, PurePosixPath
from urllib.parse import quote


DEFAULT_RELEASE_ID = "2026.10.15"
DEFAULT_RELEASE_TAG = "underground-preview-2026.10.15"
DEFAULT_REPOSITORY = "woodk123/lcs-underground-edition"
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

    This deliberately has no source-layout assumptions, so it verifies both the
    old combined packages and the new standalone players/source archive.
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


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def snapshot_id(entries: dict[str, str]) -> str:
    payload = "".join(f"{value}  {name}\n" for name, value in sorted(entries.items()))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


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


def packaging_commit(root: Path) -> str:
    if (root / ".git").exists():
        value = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "HEAD"], check=True, capture_output=True, text=True,
        ).stdout.strip()
    else:
        metadata = read_json(root / "BUILD_INFO.json")
        value = next((metadata.get(key) for key in ("packaging_commit", "source_commit", "runtime_source_commit")
                      if metadata.get(key)), "")
    if not re.fullmatch(r"[0-9a-f]{40}", value):
        raise ValueError("Source checkout/archive has no full packaging commit identity")
    return value


def validate_source_pair(root: Path, web_package: Path, windows_package: Path) -> dict:
    """Prove both compiled packages have the same complete, unchanged source."""
    web_info = read_json(web_package / "BUILD_INFO.json")
    windows_info = read_json(windows_package / "BUILD_INFO.json")
    source_commit = web_info.get("source_commit")
    if not re.fullmatch(r"[0-9a-f]{40}", source_commit or ""):
        raise ValueError("Original web package has no full source_commit identity")
    if windows_info.get("source_commit") != source_commit:
        raise ValueError("Windows and web runtime source commits differ")
    web_source = file_hashes(web_package / "source")
    windows_source = file_hashes(windows_package / "source")
    if not web_source or web_source != windows_source:
        raise ValueError("Windows and web corresponding source snapshots differ")
    upstream = file_hashes(web_package / "source/upstream")
    for required in ("lib/main.dart", "pubspec.yaml", "pubspec.lock"):
        if required not in upstream:
            raise ValueError(f"Corresponding source is missing: upstream/{required}")
    # Include generated serializers and other untracked rebuild prerequisites.
    for relative, expected in upstream.items():
        current = root / "upstream" / relative
        if not current.is_file() or digest(current) != expected:
            raise ValueError(f"Current runtime source differs from the compiled preview: upstream/{relative}")
    checked = 0
    if (root / ".git").exists():
        tracked = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z", "--", "upstream"],
            check=True, capture_output=True,
        ).stdout.decode("utf-8").split("\0")
        for name in filter(None, tracked):
            relative = safe_relative(name.removeprefix("upstream/"))
            if any(part in CACHE_NAMES for part in PurePosixPath(relative).parts):
                continue
            if relative not in upstream:
                raise ValueError(f"Tracked runtime source is absent from the preview: {name}")
            checked += 1
        current_verification = "All packaged upstream bytes and tracked current upstream inventory checked."
    else:
        if filtered_source_hashes(root / "upstream") != upstream:
            raise ValueError("Extracted current source inventory differs from the compiled preview")
        current_verification = "Complete extracted upstream source inventory checked without Git; build/cache state excluded."
    for relative, expected in windows_info.get("source_files_sha256", {}).items():
        safe_relative(relative)
        if upstream.get(relative) != expected:
            raise ValueError(f"Windows recorded source hash mismatch: {relative}")
    return {
        "runtime_source_commit": source_commit,
        "compiled_source_commit": web_info.get("compiled_source_commit", source_commit),
        "matching_source_files": len(web_source), "unchanged_upstream_files": len(upstream),
        "verified_tracked_upstream_files": checked, "upstream_snapshot_sha256": snapshot_id(upstream),
        "current_source_verification": current_verification,
    }


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


def load_runtime_verification(root: Path, web_info: dict, windows_info: dict, web_hash: str) -> dict:
    original = root / ".local/github-release-assets/verification.json"
    if original.is_file():
        value = read_json(original)
        if (value.get("source_commit") != web_info["source_commit"]
                or value.get("compiled_main_js_sha256") != web_hash):
            raise ValueError("Existing runtime verification does not describe these compiled packages")
        value.pop("archive_integrity", None)
        return value
    # New previews may have only the checked build reports. Preserve that scope
    # verbatim instead of inventing gameplay/launch claims from packaging checks.
    return {
        "source_commit": web_info["source_commit"], "compiled_main_js_sha256": web_hash,
        "original_build_status": web_info.get("status"),
        "original_manual_qa": web_info.get("manual_qa"),
        "original_native_visual_qa": windows_info.get("native_visual_qa"),
    }


def package_preview(
    root: Path, web_package: Path, windows_package: Path, output: Path,
    release_id: str = DEFAULT_RELEASE_ID, release_tag: str = DEFAULT_RELEASE_TAG,
    repository: str = DEFAULT_REPOSITORY,
) -> dict:
    root = Path(root).resolve(strict=True)
    web_package = Path(web_package).resolve(strict=True)
    windows_package = Path(windows_package).resolve(strict=True)
    output = Path(output).resolve()
    for value in (release_id, release_tag):
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", value):
            raise ValueError(f"Invalid release identifier: {value!r}")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError(f"Invalid GitHub repository: {repository!r}")
    if output.exists():
        raise ValueError(f"Output already exists; choose a new directory: {output}")
    for protected in (web_package, windows_package, root / "upstream", root / "scripts", root / "docs"):
        if output == protected or output.is_relative_to(protected):
            raise ValueError(f"Output must be outside package/source input directories: {output}")
    original_web = verify_package(web_package)
    original_windows = verify_package(windows_package)
    identity = validate_source_pair(root, web_package, windows_package)
    identity["packaging_commit"] = packaging_commit(root)
    payloads = {"web": runtime_hashes(web_package, "web"), "windows-x64": runtime_hashes(windows_package, "windows-x64")}
    require_files(root, tuple(f"scripts/{name}" for name in WEB_SCRIPTS) + ("README.md", "LICENSE", "AUTHORS.md", "Play.cmd", ".gitignore"))
    licenses = windows_package / "licenses"
    if not licenses.is_dir() or not file_hashes(licenses):
        raise ValueError("Bundled component licenses are missing from the Windows package")
    web_info = read_json(web_package / "BUILD_INFO.json")
    windows_info = read_json(windows_package / "BUILD_INFO.json")
    runtime_verification = load_runtime_verification(root, web_info, windows_info, payloads["web"]["web/main.dart.js"])
    prefix = f"LCS-Underground-Edition-{release_id}"
    source = output / f"{prefix}-Source"
    output.mkdir(parents=True, exist_ok=False)
    source.mkdir()
    # Preserve the complete original game source/provenance; refresh only the
    # distribution documentation and tooling outside upstream/.
    for entry in sorted((web_package / "source").iterdir()):
        if entry.name in {"scripts", "docs", "README.md", "LICENSE", "AUTHORS.md", "Play.cmd", ".gitignore"}:
            continue
        if entry.name == "upstream-changes.patch" and entry.stat().st_size == 0:
            continue
        if entry.is_dir():
            shutil.copytree(entry, source / entry.name)
        else:
            copy_file(entry, source / entry.name)
    for name in ("scripts", "docs"):
        shutil.copytree(root / name, source / name, ignore=cache_ignore)
    for name in ("README.md", "LICENSE", "AUTHORS.md", "Play.cmd", ".gitignore"):
        copy_file(root / name, source / name)
    evidence = source / "build-evidence"
    evidence.mkdir(exist_ok=True)
    for package in (web_package, windows_package):
        if not (package / "build-evidence").is_dir():
            continue
        for relative, checksum in file_hashes(package / "build-evidence").items():
            destination = evidence / relative
            if destination.exists():
                if digest(destination) == checksum:
                    continue
                destination = evidence / "windows" / relative
            copy_file(package / "build-evidence" / relative, destination)
    write_json(evidence / "original-web-build-info.json", web_info)
    write_json(evidence / "original-windows-build-info.json", windows_info)
    write_json(evidence / "runtime-verification.json", runtime_verification)
    write_json(source / "BUILD_INFO.json", {
        "target": "corresponding-source", "release_tag": release_tag, "repository": repository,
        **identity, "runtime_source_directory": "upstream",
        "verification_scope": "Original runtime verification is retained in build-evidence/runtime-verification.json. Packaging checks do not add gameplay coverage.",
    })
    (source / "SOURCE_INFO.md").write_text(
        "# Matching source for The Underground Edition preview\n\n"
        f"This is the complete modified source corresponding to the `{release_tag}` player downloads.\n\n"
        f"Runtime source snapshot: `{identity['runtime_source_commit']}`. "
        f"Original compiled-source revision recorded by the build: `{identity['compiled_source_commit']}`. "
        f"Updated distribution scripts/documentation: `{identity['packaging_commit']}`.\n\n"
        "`upstream/` is byte-for-byte identical to the corresponding source in both original combined "
        "preview packages and the current game source. It includes generated serializers, dependency lockfile "
        "and runtime artwork. The distribution scripts and documentation were refreshed without rebuilding "
        "either compiled game. Root artwork folders retain the original provenance/reference material.\n\n"
        "Read `docs/BUILDING.md` to rebuild. Build evidence appears once under `build-evidence/`; "
        "`runtime-verification.json` preserves the original checks and their limits. Packaging verification "
        "does not establish additional native playthrough or clean-machine launch coverage.\n\n"
        "The Underground Edition is by Kevin Wood, based on New Age by Ashley S. Fox and the original "
        "Liberal Crime Squad by Tarn Adams. See `LICENSE` and `AUTHORS.md`.\n",
        encoding="utf-8",
    )
    if file_hashes(source / "upstream") != file_hashes(web_package / "source/upstream"):
        raise ValueError("Copied corresponding source differs from the original snapshot")
    source_result = archive_package(source)
    source_archive = Path(source_result["archive"]).name
    source_sha256 = source_result["archive_sha256"]
    source_url = f"https://github.com/{repository}/releases/download/{quote(release_tag, safe='')}/{quote(source_archive, safe='')}"
    results = [source_result]
    unchanged = {}
    for target, original, suffix in (("windows-x64", windows_package, "Windows-x64-Player"), ("web", web_package, "Web-Player")):
        player = output / f"{prefix}-{suffix}"
        player.mkdir()
        for relative in payloads[target]:
            copy_file(original / relative, player / relative)
        shutil.copytree(licenses, player / "licenses")
        for name in ("LICENSE", "AUTHORS.md"):
            copy_file(root / name, player / name)
        if target == "web":
            copy_file(root / "Play.cmd", player / "Play.cmd")
            for name in WEB_SCRIPTS:
                copy_file(root / "scripts" / name, player / "scripts" / name)
            instructions = (
                "Extract the complete folder, then double-click **Play.cmd** on Windows. Python 3 is required; "
                "Flutter is not. On other systems run `python3 scripts/serve.py --directory web --port 8765`, "
                "then open http://127.0.0.1:8765 in your browser.\n\n"
                "Keep using the same browser and address to retain saves. Export important campaigns before "
                "clearing browser data. Close the managed Windows server with "
                "`powershell -ExecutionPolicy Bypass -File scripts/stop.ps1`.\n"
            )
        else:
            instructions = (
                "Extract the complete folder, then double-click **lcs_new_age.exe**. Keep `data/` and every DLL "
                "beside the executable. This build targets Windows 10/11 x64; Python and Flutter are not required.\n\n"
                "Saves are stored under `%APPDATA%\\LCS New Age\\lcs_new_age\\lcs_new_age.db`. "
                "Export/Import in the game transfers campaigns between browser and Windows editions.\n"
            )
        (player / "README.md").write_text(
            f"# LCS: New Age — The Underground Edition — {suffix}\n\n{instructions}\n"
            "Early preview by Kevin Wood. See `SOURCE_REFERENCE.md` for the separate matching source download "
            "and its SHA-256, `LICENSE` and `AUTHORS.md` for game license/credits, and `licenses/` for bundled "
            "component notices. Runtime verification and rebuilding details are in the source download.\n",
            encoding="utf-8",
        )
        (player / "SOURCE_REFERENCE.md").write_text(
            source_reference(source_archive, source_sha256, source_url, identity), encoding="utf-8",
        )
        write_json(player / "BUILD_INFO.json", {
            "target": target, "release_tag": release_tag, "repository": repository, **identity,
            "source_archive": source_archive, "source_archive_sha256": source_sha256,
            "source_download_url": source_url, "runtime_payload_sha256": snapshot_id(payloads[target]),
            "runtime_payload_files": len(payloads[target]), "runtime_payload_unchanged": True,
            "verification_scope": "Runtime checks are unchanged; see build-evidence/runtime-verification.json in the matching source ZIP.",
        })
        copied = runtime_hashes(player, target)
        if copied != payloads[target]:
            raise ValueError(f"Copied runtime differs from original {target} package")
        unchanged[target] = {
            "status": "passed", "files": len(copied), "payload_sha256": snapshot_id(copied),
            "original_archive_bytes": (original_web if target == "web" else original_windows)["archive_bytes"],
        }
        result = archive_package(player)
        unchanged[target]["player_archive_bytes"] = result["archive_bytes"]
        unchanged[target]["size_fraction_of_original"] = round(result["archive_bytes"] / unchanged[target]["original_archive_bytes"], 6)
        results.append(result)
    verification = {
        **runtime_verification, "status": "passed", "release_tag": release_tag, "repository": repository,
        **identity, "archive_integrity": [
            {"archive": Path(item["archive"]).name, "sha256": item["archive_sha256"],
             "bytes": item["archive_bytes"], "verified_files": item["verified_file_hashes"],
             "status": item["status"], "zip_crc_and_inventory": item["zip_crc_and_inventory"],
             "zip_file_hashes": item["zip_file_hashes"]} for item in results
        ],
        "unchanged_payload_checks": unchanged,
        "corresponding_source_checks": "Both original packages and copied upstream source match byte-for-byte; current tracked/runtime source is unchanged.",
        "packaging_verification_scope": "Archive, manifest, payload and source checks only. Original runtime QA fields and limitations above are unchanged.",
    }
    write_json(output / "verification.json", verification)
    return verification


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--web-package", type=Path, required=True)
    parser.add_argument("--windows-package", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--release-id", default=DEFAULT_RELEASE_ID)
    parser.add_argument("--release-tag", default=DEFAULT_RELEASE_TAG)
    parser.add_argument("--repository", default=DEFAULT_REPOSITORY)
    args = parser.parse_args()
    result = package_preview(**vars(args))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
