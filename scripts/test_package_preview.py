"""Fast integration checks for release preservation and distributable integrity."""
from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

import package_preview as packaging


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def put(root: Path, name: str, value: str | bytes) -> None:
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(value.encode("utf-8") if isinstance(value, str) else value)


def seal(package: Path) -> None:
    """Independently generate a legacy manifest/ZIP fixture."""
    files = sorted(path for path in package.rglob("*") if path.is_file() and path.name != "FILES.sha256")
    put(package, "FILES.sha256", "".join(f"{sha(path)}  {path.relative_to(package).as_posix()}\n" for path in files))
    archive = package.with_name(package.name + ".zip")
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_STORED) as bundle:
        for path in sorted(package.rglob("*")):
            if path.is_file():
                bundle.write(path, f"{package.name}/{path.relative_to(package).as_posix()}")
    put(archive.parent, archive.name + ".sha256", f"{sha(archive)}  {archive.name}\n")


class PreviewPackageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "checkout"
        self.root.mkdir()
        for name, content in {
            "upstream/lib/main.dart": "void main() {}\n",
            "upstream/lib/model.g.dart": "// Generated serializer retained for rebuilds.\n",
            "upstream/pubspec.yaml": "name: lcs_new_age\n",
            "upstream/pubspec.lock": "packages: {}\n",
            "upstream/assets/portrait.png": b"painted-runtime-portrait",
            "upstream/windows/runner/main.cpp": "int main() {}\n",
            "README.md": "# Current project instructions\n",
            "LICENSE": "GPL version 2\n",
            "AUTHORS.md": "Tarn Adams, Ashley S. Fox, Kevin Wood\n",
            "Play.cmd": "powershell -File scripts\\launch.ps1\n",
            ".gitignore": ".local/\n",
            "docs/BUILDING.md": "Current separate source build instructions.\n",
            "scripts/package_preview.py": "# Current distribution tooling\n",
            **{f"scripts/{name}": f"# Current {name}\n" for name in packaging.WEB_SCRIPTS},
        }.items():
            put(self.root, name, content)
        subprocess.run(["git", "init", "--quiet", str(self.root)], check=True, capture_output=True)
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True, capture_output=True)
        subprocess.run([
            "git", "-C", str(self.root), "-c", "user.name=Release Test", "-c", "user.email=test@example.invalid",
            "commit", "--quiet", "-m", "Synthetic compiled source",
        ], check=True, capture_output=True)
        self.web = self.base / "legacy-web"
        self.windows = self.base / "legacy-windows"
        self.output = self.base / "split"
        self.commit = "a" * 40
        for package in (self.web, self.windows):
            source = package / "source"
            source.mkdir(parents=True)
            shutil.copytree(self.root / "upstream", source / "upstream")
            shutil.copytree(self.root / "scripts", source / "scripts")
            shutil.copytree(self.root / "docs", source / "docs")
            put(source, "assets/provenance/prompt.txt", "Original artwork provenance.\n")
            put(source, "upstream-changes.patch", "")
            put(source, "docs/obsolete.txt", "Old distribution instructions.\n")
            put(package, "LICENSE", "GPL version 2\n")
            put(package, "AUTHORS.md", "Original credits.\n")
            put(package, "build-evidence/windows-build.log", "Windows compilation passed; no graphical playthrough.\n")
            put(package, "assets/reference.png", b"Unneeded duplicate reference picture")
        for name, content in {
            "web/index.html": "<html>Compiled game</html>", "web/main.dart.js": b"compiled-javascript",
            "web/flutter_bootstrap.js": "// bootstrap", "web/sw.js": "// offline worker",
            "web/assets/portrait.png": b"painted-runtime-portrait",
            "BUILD_INFO.json": json.dumps({"source_commit": self.commit, "status": "checks_passed", "manual_qa": "Limited original coverage."}),
        }.items():
            put(self.web, name, content)
        for name, content in {
            "lcs_new_age.exe": b"EXE-CONTENTS", "flutter_windows.dll": b"flutter-runtime",
            "plugin.dll": b"plugin-must-be-preserved", "msvcp140.dll": b"vc-runtime",
            "vcruntime140.dll": b"vc-runtime-1", "vcruntime140_1.dll": b"vc-runtime-2",
            "native_assets.json": "{}", "data/app.so": b"compiled-native-application",
            "data/icudtl.dat": b"icu-data", "data/flutter_assets/NOTICES.Z": b"component-notices",
            "data/flutter_assets/portrait.png": b"painted-runtime-portrait",
            "licenses/Flutter-LICENSE.txt": "Flutter license\n",
            "BUILD_INFO.json": json.dumps({"source_commit": self.commit, "native_visual_qa": "Not performed."}),
        }.items():
            put(self.windows, name, content)
        self.qa = {
            "source_commit": self.commit, "compiled_main_js_sha256": sha(self.web / "web/main.dart.js"),
            "automated_tests_passed": 564, "native_graphical_playthrough": "not performed",
            "offline_save_reload": {"scope": "Browser networking disabled, server remains running."},
            "archive_integrity": [{"archive": "obsolete.zip", "sha256": "obsolete"}],
        }
        put(self.root, ".local/github-release-assets/verification.json", json.dumps(self.qa))
        seal(self.web)
        seal(self.windows)

    def package(self) -> dict:
        return packaging.package_preview(self.root, self.web, self.windows, self.output)

    def test_split_archives_preserve_payload_source_and_original_qa_after_extraction(self) -> None:
        before = {p: packaging.file_hashes(p) for p in (self.web, self.windows)}
        # Current docs/scripts replace legacy copies, and caches are excluded.
        put(self.root, "scripts/__pycache__/junk.pyc", b"cache-not-source")
        report = self.package()
        self.assertEqual(report["automated_tests_passed"], 564)
        self.assertEqual(report["native_graphical_playthrough"], "not performed")
        self.assertEqual(report["offline_save_reload"], self.qa["offline_save_reload"])
        self.assertEqual(len(report["archive_integrity"]), 3)
        self.assertNotIn("obsolete.zip", json.dumps(report))
        self.assertTrue(all(packaging.file_hashes(p) == original for p, original in before.items()))
        prefix = "LCS-Underground-Edition-2026.10.15"
        source = self.output / f"{prefix}-Source"
        self.assertEqual(packaging.file_hashes(source / "upstream"), packaging.file_hashes(self.web / "source/upstream"))
        self.assertTrue((source / "upstream/lib/model.g.dart").is_file())
        self.assertTrue((source / "upstream/pubspec.lock").is_file())
        self.assertTrue((source / "assets/provenance/prompt.txt").is_file())
        self.assertFalse((source / "docs/obsolete.txt").exists())
        self.assertFalse((source / "scripts/__pycache__").exists())
        self.assertFalse((source / "upstream-changes.patch").exists())
        self.assertEqual(len(list(source.rglob("windows-build.log"))), 1)
        source_archive = source.with_name(source.name + ".zip")
        for suffix in ("Windows-x64-Player", "Web-Player"):
            player = self.output / f"{prefix}-{suffix}"
            for excluded in ("source", "assets", "docs", "build-evidence", "reports", "PROJECT_README.md"):
                self.assertFalse((player / excluded).exists(), (suffix, excluded))
            reference = (player / "SOURCE_REFERENCE.md").read_text(encoding="utf-8")
            self.assertIn(source_archive.name, reference)
            self.assertIn(sha(source_archive), reference)
            if suffix == "Web-Player":
                self.assertEqual({p.name for p in (player / "scripts").iterdir()}, set(packaging.WEB_SCRIPTS))
            else:
                self.assertEqual(sha(player / "plugin.dll"), sha(self.windows / "plugin.dll"))
                self.assertEqual(sha(player / "native_assets.json"), sha(self.windows / "native_assets.json"))
        clean = self.base / "fresh-extraction"
        clean.mkdir()
        for archive in self.output.glob("*.zip"):
            with zipfile.ZipFile(archive) as bundle:
                self.assertIsNone(bundle.testzip())
                bundle.extractall(clean)
            shutil.copy2(archive, clean / archive.name)
            sidecar = archive.with_name(archive.name + ".sha256")
            shutil.copy2(sidecar, clean / sidecar.name)
            checked = packaging.verify_package(clean / archive.name.removesuffix(".zip"))
            self.assertEqual(checked["status"], "passed")

    def test_manifest_rejects_unsafe_paths_before_copying(self) -> None:
        manifest = self.web / "FILES.sha256"
        original = manifest.read_text(encoding="utf-8")
        for path in ("../outside", "/absolute", "C:/absolute", "folder\\..\\outside", "./normal", "."):
            with self.subTest(path=path):
                manifest.write_text(original + f"{'0' * 64}  {path}\n", encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "Unsafe relative path"):
                    self.package()
                self.assertFalse(self.output.exists())

    def test_runtime_tamper_and_missing_required_runtime_are_rejected(self) -> None:
        executable = self.windows / "lcs_new_age.exe"
        executable.write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "File hash mismatch"):
            self.package()
        executable.unlink()
        seal(self.windows)
        with self.assertRaisesRegex(ValueError, "Required runtime/distribution file is missing"):
            self.package()
        self.assertFalse(self.output.exists())

    def test_mismatched_corresponding_source_and_new_game_edits_are_rejected(self) -> None:
        target = self.windows / "source/upstream/lib/main.dart"
        target.write_bytes(b"different source")
        seal(self.windows)
        with self.assertRaisesRegex(ValueError, "corresponding source snapshots differ"):
            self.package()
        shutil.copy2(self.web / "source/upstream/lib/main.dart", target)
        seal(self.windows)
        put(self.root, "upstream/lib/main.dart", "new gameplay after compilation")
        with self.assertRaisesRegex(ValueError, "Current runtime source differs"):
            self.package()
        self.assertFalse(self.output.exists())

    def test_zip_member_hash_checked_even_when_zip_and_sidecar_are_replaced(self) -> None:
        archive = self.web.with_name(self.web.name + ".zip")
        with zipfile.ZipFile(archive) as bundle:
            contents = {name: bundle.read(name) for name in bundle.namelist()}
        contents[f"{self.web.name}/web/main.dart.js"] = b"other runtime with valid CRC"
        with zipfile.ZipFile(archive, "w") as bundle:
            for name, content in contents.items():
                bundle.writestr(name, content)
        put(archive.parent, archive.name + ".sha256", f"{sha(archive)}  {archive.name}\n")
        with self.assertRaisesRegex(ValueError, "ZIP file hash mismatch"):
            self.package()
        self.assertFalse(self.output.exists())

    def test_existing_output_is_never_overwritten(self) -> None:
        self.output.mkdir()
        put(self.output, "keep.txt", "Do not replace")
        with self.assertRaisesRegex(ValueError, "Output already exists"):
            self.package()
        self.assertEqual((self.output / "keep.txt").read_text(), "Do not replace")

    def test_extracted_source_without_git_uses_metadata_and_checks_complete_source_inventory(self) -> None:
        extracted = self.base / "extracted-source"
        shutil.copytree(self.root, extracted, ignore=shutil.ignore_patterns(".git"))
        commit = "b" * 40
        put(extracted, "BUILD_INFO.json", json.dumps({"packaging_commit": commit}))
        put(extracted, "upstream/.dart_tool/ignored-cache", b"generated cache")
        result = packaging.package_preview(extracted, self.web, self.windows, self.output)
        self.assertEqual(result["packaging_commit"], commit)
        self.assertIn("without Git", result["current_source_verification"])
        put(extracted, "upstream/lib/unrecorded_gameplay.dart", "unrecorded source")
        with self.assertRaisesRegex(ValueError, "Extracted current source inventory differs"):
            packaging.package_preview(extracted, self.web, self.windows, self.base / "must-not-exist")
        self.assertFalse((self.base / "must-not-exist").exists())


if __name__ == "__main__":
    unittest.main()
