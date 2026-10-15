"""Package an existing Windows release build with app-local VC runtime files."""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import zipfile
from datetime import datetime, timezone
from pathlib import Path


def digest(path: Path) -> str:
    checksum = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(block)
    return checksum.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--runtime-dir", type=Path, required=True)
    parser.add_argument("--source-package", type=Path)
    args = parser.parse_args()
    root = args.root.resolve(strict=True)
    runtime = args.runtime_dir.resolve(strict=True)
    build = root / "upstream/build/windows/x64/runner/Release"
    required_build = (
        "lcs_new_age.exe", "flutter_windows.dll", "data/app.so", "data/icudtl.dat",
        "data/flutter_assets/NOTICES.Z",
    )
    runtime_files = ("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll")
    for name in required_build:
        if not (build / name).is_file():
            parser.error(f"Missing Windows build artifact: {build / name}")
    for name in runtime_files:
        if not (runtime / name).is_file():
            parser.error(f"Missing app-local C++ runtime file: {runtime / name}")
    source_package = None
    if args.source_package is not None:
        source_package = args.source_package.resolve(strict=True)
        if not (source_package / "source/upstream/lib/main.dart").is_file():
            parser.error("The companion package must contain source/upstream/lib/main.dart")

    now = datetime.now(timezone.utc)
    release_root = root / "release"
    release_root.mkdir(exist_ok=True)
    destination = release_root / "LiberalCrimeSquad-NewAge-UndergroundEdition-Windows"
    if destination.exists():
        destination = release_root / f"LiberalCrimeSquad-NewAge-UndergroundEdition-Windows-{now:%Y%m%d-%H%M%S}"
    shutil.copytree(build, destination)
    for name in runtime_files:
        shutil.copy2(runtime / name, destination / name)
    for name in ("LICENSE", "AUTHORS.md"):
        shutil.copy2(root / "upstream" / name, destination / name)
    shutil.copy2(root / "README.md", destination / "PROJECT_README.md")
    shutil.copytree(root / "docs", destination / "docs")
    native_log = root / "reports/final-windows-build.log"
    if native_log.is_file():
        evidence = destination / "build-evidence"
        evidence.mkdir()
        shutil.copy2(native_log, evidence / "windows-build.log")
    if source_package is not None and (source_package / "reports").is_dir():
        shutil.copytree(source_package / "reports", destination / "reports")
    if source_package is not None and (source_package / "assets").is_dir():
        shutil.copytree(source_package / "assets", destination / "assets")
    licenses = destination / "licenses"
    licenses.mkdir()
    shutil.copy2(root / "upstream/fonts/modern/roboto_license.txt", licenses / "Roboto-LICENSE.txt")
    journal_license = root / "upstream/fonts/journal/OFL.txt"
    if journal_license.is_file():
        shutil.copy2(journal_license, licenses / "LibreBaskerville-OFL.txt")
    flutter_license = root / ".tools/flutter/LICENSE"
    if flutter_license.is_file():
        shutil.copy2(flutter_license, licenses / "Flutter-LICENSE.txt")

    readme = """# Liberal Crime Squad: New Age — The Underground Edition — Windows

Extract the whole folder, then double-click **lcs_new_age.exe**.
Keep the `data` folder and every DLL beside the executable. You do not need
Python, a browser, Flutter, Visual Studio, an API key, or an internet connection
to play this native build.

This package targets Windows 10/11 x64. The Visual C++ runtime DLLs are included
beside the game. The build was compiled on Windows 11; consult the included
verification documentation for the exact launch and gameplay checks completed.

Saves are stored per Windows user under
`%APPDATA%\\LCS New Age\\lcs_new_age\\lcs_new_age.db`.
Use Save & Exit at headquarters. Export important campaigns through the game's
save interface. Browser campaigns live in browser storage; transfer one through
Export/Import rather than copying browser files into the native save folder.

The full New Age engine and modern presentation are included. Keyboard commands
and classic specialist views remain available. F1 opens the field guide.

See `SOURCE_REFERENCE.md` for the corresponding modified source, `LICENSE` and
`AUTHORS.md` for the original game license/credits, and `licenses/` plus
`data/flutter_assets/NOTICES.Z` for bundled component notices. Build and native
verification details are in `docs/WINDOWS_BUILD.md`.
"""
    (destination / "README.md").write_text(readme, encoding="utf-8")
    companion = source_package.name if source_package else "the companion web/source release"
    source_reference = (
        "# Corresponding source\n\n"
        f"The corresponding modified source is supplied in **{companion}**, "
        "under `source/upstream/`, together with the dependency lockfile, "
        "generated serialization, local assets, build scripts and documentation. "
        "Keep that source package with this Windows folder when redistributing.\n\n"
        "Base upstream: https://github.com/ashley-s-fox/lcs-new-age\n\n"
        "Base revision: `a1a2112dabf4a8d1a25e36a7a747ef99c9318b87`. "
        "The upstream link alone is not the modified corresponding source. "
        "The GPL v2 license is included as `LICENSE`.\n"
    )
    (destination / "SOURCE_REFERENCE.md").write_text(source_reference, encoding="utf-8")
    if source_package is not None:
        shutil.copytree(source_package / "source", destination / "source")
        (destination / "SOURCE_REFERENCE.md").write_text(
            "# Corresponding source\n\n"
            "The complete corresponding modified source is included in this package under `source/upstream/`, "
            "with build scripts, locked dependencies, generated serialization and artwork. "
            f"The matching web/source package is `{companion}`.\n\n"
            "Base upstream: https://github.com/ashley-s-fox/lcs-new-age\n\n"
            "Base revision: `a1a2112dabf4a8d1a25e36a7a747ef99c9318b87`. See LICENSE and AUTHORS.md.\n",
            encoding="utf-8",
        )
    source_files = {
        path.relative_to(root / "upstream").as_posix(): digest(path)
        for directory in ("lib", "windows")
        for path in sorted((root / "upstream" / directory).rglob("*"))
        if path.is_file() and "ephemeral" not in path.parts
    }
    info = {
        "target": "windows-x64",
        "packaged_utc": now.isoformat(),
        "executable": "lcs_new_age.exe",
        "flutter_version": "3.47.7",
        "build_command": "flutter build windows --release --no-pub",
        "source_package": source_package.name if source_package else None,
        "source_commit": json.loads((source_package / "BUILD_INFO.json").read_text(encoding="utf-8"))["source_commit"] if source_package else None,
        "native_visual_qa": "Earlier title window inspected; final native playthrough unverified after user stopped computer control. See docs/WINDOWS_BUILD.md.",
        "app_local_vc_runtime": list(runtime_files),
        "runtime_source": str(runtime),
        "source_files_sha256": source_files,
    }
    (destination / "BUILD_INFO.json").write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8")
    hashes = [
        f"{digest(path)}  {path.relative_to(destination).as_posix()}"
        for path in sorted(destination.rglob("*")) if path.is_file()
    ]
    (destination / "FILES.sha256").write_text("\n".join(hashes) + "\n", encoding="utf-8")
    archive = destination.with_suffix(".zip")
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        for path in sorted(destination.rglob("*")):
            if path.is_file():
                bundle.write(path, f"{destination.name}/{path.relative_to(destination).as_posix()}")
    archive.with_suffix(".zip.sha256").write_text(f"{digest(archive)}  {archive.name}\n", encoding="utf-8")
    print(f"Windows package: {destination}")
    print(f"Launch: {destination / 'lcs_new_age.exe'}")
    print(f"Archive: {archive}")
    if source_package is None:
        print("Corresponding source reference needs the final companion release name before distribution.")


if __name__ == "__main__":
    main()
