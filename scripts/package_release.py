"""Package a freshly checked web build with corresponding source and attribution."""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import zipfile
from datetime import datetime, timezone
from pathlib import Path


def digest(path: Path) -> str:
    checksum = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(block)
    return checksum.hexdigest()


def source_ignore(directory: str, names: list[str]) -> set[str]:
    excluded = {
        ".git", ".dart_tool", "build", ".idea", ".vscode", "ephemeral",
        "node_modules", ".flutter-plugins", ".flutter-plugins-dependencies",
        ".DS_Store", "Thumbs.db", "__pycache__",
    }
    return {name for name in names if name in excluded or name.endswith(".log")}


def artwork_ignore(directory: str, names: list[str]) -> set[str]:
    # Preserve provenance prompts without distributing rejected raster trials.
    if Path(directory).name == "explorations":
        return {name for name in names if not name.endswith(".txt")}
    return set()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--qa-report", type=Path)
    args = parser.parse_args()
    root = args.root.resolve(strict=True)
    report = args.report.resolve(strict=True)
    build = root / "upstream/build/web"
    required = ("index.html", "main.dart.js", "flutter_bootstrap.js", "sw.js")
    for name in required:
        if not (build / name).is_file():
            parser.error(f"Missing required built file: {build / name}")
    if "const RESOURCES = null; // build: manifest" in (build / "sw.js").read_text(encoding="utf-8"):
        parser.error("Offline manifest was not injected. Run the complete release script.")
    info = json.loads((report / "build-info.json").read_text(encoding="utf-8-sig"))
    if info.get("status") not in {
        "automated_checks_passed_manual_qa_pending",
        "automated_checks_and_packaging_passed_manual_qa_pending",
    }:
        parser.error("Packaging requires the current release script's passing build report.")
    steps = info.get("steps", [])
    required_steps = ["01-dependencies", "02-serialization", "03-tests", "04-focused-analysis", "05-full-analysis", "06-web-release", "07-offline-manifest"]
    if [step.get("name") for step in steps[:7]] != required_steps or any(step.get("exit_code") != 0 for step in steps):
        parser.error("Release report must contain all seven successful build/check steps.")

    qa_directory = None
    if args.qa_report is not None:
        qa_path = args.qa_report.resolve(strict=True)
        qa = json.loads(qa_path.read_text(encoding="utf-8"))
        if (qa.get("status") != "passed" or qa.get("skipped")
                or qa.get("pageErrors") or qa.get("consoleErrors") or qa.get("failedRequests")
                or qa.get("mainJsSha256") != digest(build / "main.dart.js")
                or not qa.get("managedServerStopped")):
            parser.error("Final QA must pass without skips/errors for this exact JavaScript hash, including server-stopped offline use.")
        qa_directory = qa_path.parent
        upgrade = json.loads((qa_directory / "upgrade/report.json").read_text(encoding="utf-8"))
        if (upgrade.get("status") != "passed" or upgrade.get("pageErrors")
                or upgrade.get("consoleErrors")
                or upgrade.get("cache", {}).get("cachedMainSha256") != digest(build / "main.dart.js")):
            parser.error("Final QA must also verify a save-preserving update to this exact cached JavaScript hash.")

    now = datetime.now(timezone.utc)
    name = f"LiberalCrimeSquad-NewAge-UndergroundEdition-{now:%Y%m%d-%H%M%S}-{digest(build / 'main.dart.js')[:8]}"
    release_root = root / "release"
    release_root.mkdir(exist_ok=True)
    destination = release_root / name
    destination.mkdir(exist_ok=False)
    shutil.copytree(build, destination / "web", ignore=shutil.ignore_patterns("*.map", "*.symbols", ".last_build_id"))
    shutil.copytree(root / "scripts", destination / "scripts", ignore=source_ignore)
    shutil.copytree(root / "docs", destination / "docs", ignore=source_ignore)
    for asset_folder in ("assets/concepts", "assets/art-city-v2", "assets/gangsters-journal"):
        if (root / asset_folder).is_dir():
            shutil.copytree(root / asset_folder, destination / asset_folder,
                            ignore=artwork_ignore)
    shutil.copytree(report, destination / "build-evidence", ignore=shutil.ignore_patterns("08-package.log"))
    native_log = root / "reports/final-windows-build.log"
    if native_log.is_file():
        shutil.copy2(native_log, destination / "build-evidence/windows-build.log")
    launcher_report = root / ".local/reports/launcher-contracts.json"
    if launcher_report.is_file():
        shutil.copy2(launcher_report, destination / "build-evidence/launcher-contracts.json")
    if qa_directory is not None:
        shutil.copytree(qa_directory, destination / "reports/browser" / qa_directory.name)
    for filename in ("Play.cmd", "README.md"):
        shutil.copy2(root / filename, destination / filename)
    for filename in ("LICENSE", "AUTHORS.md"):
        shutil.copy2(root / "upstream" / filename, destination / filename)

    source = destination / "source"
    source.mkdir()
    shutil.copytree(root / "upstream", source / "upstream", ignore=source_ignore)
    shutil.copytree(root / "scripts", source / "scripts", ignore=source_ignore)
    shutil.copytree(root / "docs", source / "docs", ignore=source_ignore)
    if qa_directory is not None:
        shutil.copytree(qa_directory, source / "reports/browser" / qa_directory.name)
    for asset_folder in ("assets/concepts", "assets/art-city-v2", "assets/gangsters-journal"):
        if (root / asset_folder).is_dir():
            shutil.copytree(root / asset_folder, source / asset_folder,
                            ignore=artwork_ignore)
    for filename in ("Play.cmd", "README.md", ".gitignore"):
        shutil.copy2(root / filename, source / filename)
    git_diff = subprocess.run(
        ["git", "-C", str(root / "upstream"), "diff", "--binary", "HEAD"],
        check=True, capture_output=True,
    )
    (source / "upstream-changes.patch").write_bytes(git_diff.stdout)
    pin = json.loads((root / "scripts/toolchain.json").read_text(encoding="utf-8"))
    attribution = (
        "# Liberal Crime Squad: New Age — The Underground Edition — Source and attribution\n\n"
        "Liberal Crime Squad was created by Tarn Adams. Liberal Crime Squad: New Age "
        "was created by Ashley S. Fox; see AUTHORS.md for the complete upstream credits.\n\n"
        f"Upstream: {pin['upstream_repository']}\n\n"
        f"Base revision: `{pin['upstream_base_revision']}`\n\n"
        "This package contains a modernized Flutter presentation over the retained Dart game. "
        "Classic tactical and specialist console views remain available. It is not a new Godot port.\n\n"
        "The corresponding modified game source, generated serialization, dependency lockfile, "
        "build scripts and documentation are included under `source/`. "
        "The original GPL v2 license is included as LICENSE. Flutter/Dart SDK downloads "
        "are development prerequisites and are not bundled. Rebuild instructions are in README.md.\n\n"
        "Generated artwork provenance is recorded in the included documentation/asset manifests. "
        "Build-evidence logs document automated checks; release usability and offline-save checks "
        "must be assessed separately in docs/RELEASE_CHECKLIST.md.\n"
    )
    (destination / "SOURCE_ATTRIBUTION.md").write_text(attribution, encoding="utf-8")
    info["package_name"] = name
    info["packaged_utc"] = now.isoformat()
    info["source_snapshot"] = "source/upstream"
    if qa_directory is not None:
        info["status"] = "automated_checks_and_packaged_browser_acceptance_passed"
        info["manual_qa"] = "Selected browser screenshots inspected; exact scenarios and remaining coverage limits are documented in docs/RELEASE_CHECKLIST.md. Native graphical playthrough is not certified."
        info["browser_qa"] = {
            "report": f"reports/browser/{qa_directory.name}/report.json",
            "main_js_sha256": digest(build / "main.dart.js"),
            "server_stopped_offline": True,
            "save_preserving_update": True,
            "passed_checkpoints": len(qa["checks"]),
        }
    (destination / "BUILD_INFO.json").write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8")
    hashes = [
        f"{digest(path)}  {path.relative_to(destination).as_posix()}"
        for path in sorted(destination.rglob("*")) if path.is_file()
    ]
    (destination / "FILES.sha256").write_text("\n".join(hashes) + "\n", encoding="utf-8")
    archive = release_root / f"{name}.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        for path in sorted(destination.rglob("*")):
            if path.is_file():
                bundle.write(path, f"{name}/{path.relative_to(destination).as_posix()}")
    sidecar = archive.with_suffix(".zip.sha256")
    sidecar.write_text(f"{digest(archive)}  {archive.name}\n", encoding="utf-8")
    print(f"Package: {destination}")
    print(f"Archive: {archive}")
    print(f"SHA-256: {sidecar.read_text().strip()}")


if __name__ == "__main__":
    main()
