# Building and development

For Windows/web release packaging, use Windows PowerShell, Git and Python 3.12+. Linux desktop builds use the Linux instructions below. Commands run from the repository root, containing `upstream/` and `scripts/`. A prepared Source ZIP has the same layout and can be rebuilt without a `.git` folder; its `BUILD_INFO.json` records the source identity.

## Toolchain

The exact Flutter version and revision are pinned in [scripts/toolchain.json](../scripts/toolchain.json). Install that SDK into `.tools/flutter`:

```powershell
$pin = Get-Content scripts/toolchain.json -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Force .tools
git clone -c core.longpaths=true --depth 1 --branch $pin.flutter_version $pin.flutter_repository .tools/flutter
```

The build script verifies the pin. Initial setup and dependency downloads need internet access.

## Build and play

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build_release.ps1
```

This resolves dependencies, generates save serializers, runs Flutter tests and analysis, builds the web game, injects the offline manifest and creates **Web Player + Source** ZIPs with checksum sidecars under a new `release/` directory. Player packages contain the game/runtime, licenses and source-download references; source, tools and build evidence are provided once in the matching Source ZIP.

Before creating the offline manifest, the injector removes renderer files proven unused by the current JavaScript/CanvasKit build. Both standard and Chromium CanvasKit variants remain available. A build with Wasm or an unknown renderer retains its renderer files.

Each release writes `size-report.json` beside the ZIPs and `release-sizes.json` in its build evidence. These account for compressed and extracted sizes by artwork, portraits, renderer, code and other data. Player size limits are in `scripts/release_sizes.py`; exceeding either download or extracted-size limits fails packaging. Source archives are reported separately without a player-size limit. Review the artwork and report before deliberately raising a budget.

Double-click **Play.cmd** in the checkout or extracted browser player. It serves `upstream/build/web` in a checkout, or `web/` in a player package, at **http://127.0.0.1:8765/**. Playing requires Python 3 but no Flutter SDK.

Use the same browser profile and address for existing saves. Export important saves before clearing browser data. Do not open `index.html` directly.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/stop.ps1
```

For Windows players, add `-Windows` to the build command; see [Windows setup](WINDOWS_BUILD.md). The same packager produces separate players and corresponding source for local builds and CI.

To prepare a named preview with both players and matching source:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build_release.ps1 -Windows -Tag underground-preview-2026.10.16
```

Commit source changes first: release builds require a clean Git checkout, including untracked source files, and packaging checks that HEAD still matches the build report. Ignored build outputs and reports are allowed. Rebuilding an extracted Source ZIP still uses its recorded source identity.

An explicit `-Tag` prepares absolute Source ZIP links for that tag in `woodk123/lcs-underground-edition`; it does not publish or upload anything. The Python packager's `--tag` behaves the same and accepts `--repository owner/repo` for another fork. Untagged local builds retain relative source links. Keep the players and their matching Source ZIP together on the named release, and use a fresh tag/output directory for each preview. `-Tag` cannot be combined with `-Nightly`.

## Development mode

After the build has resolved dependencies and generated serializers:

```powershell
Set-Location upstream
..\.tools\flutter\bin\flutter.bat run -d chrome
```

Restart the application fully after changing engine code. See [architecture](ARCHITECTURE.md), [testing](TESTING.md) and [assets](ASSETS.md).

## Linux desktop

The Linux x64 CI target is **Ubuntu 22.04**. Build on Linux with the same pinned Flutter SDK as Windows. On Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y git curl unzip xz-utils zip clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev python3
version=$(python3 -c 'import json; print(json.load(open("scripts/toolchain.json"))["flutter_version"])')
repository=$(python3 -c 'import json; print(json.load(open("scripts/toolchain.json"))["flutter_repository"])')
git clone --depth 1 --branch "$version" "$repository" .tools/flutter
.tools/flutter/bin/flutter config --no-analytics --enable-linux-desktop
python3 scripts/build_linux.py
```

The builder verifies the SDK version/revision and source identity, generates serializers, runs tests and both analysis passes, then builds the native release. Start with a clean Git checkout or an extracted Source ZIP. Its output directory `.local/linux` must not already exist; move any previous output aside before rebuilding. The checked bundle is at `.local/linux/bundle/`, with logs and a hashed build report under `.local/linux/evidence/`.

Run `./lcs_new_age` from the bundle folder on a graphical Linux desktop. Keep the whole folder, including `lib/` and `data/`. Ubuntu runtime dependencies are `libgtk-3-0 libblkid1 liblzma5`; Flutter and Python are not needed to play. Linux players are x64 builds requiring Ubuntu 22.04 or a compatible system with GTK 3; other distributions and ARM64 are not covered by this workflow.

[Linux desktop build](../.github/workflows/linux.yml) can also be run manually in Actions. It uploads the bundle and build evidence as a seven-day Actions artifact. These intermediate files are used by the nightly packager. For manual release packaging on Windows, download that artifact into `.local/linux` and add `-LinuxBundle "$PWD/.local/linux"` to `scripts/build_release.ps1`; it must match the exact source commit and SDK. The final Linux Player ZIP records executable permissions; if an extractor drops them, run `chmod +x lcs_new_age` after extracting.

## Checks on pushes and pull requests

[Project checks](../.github/workflows/checks.yml) runs on every push and pull request, and can also be started manually. It tests the release tools, verifies assets, generates serializers, runs Flutter tests and performs focused/full-project analysis with the pinned SDK. A separate Ubuntu 22.04 job runs the same checks and compiles the Linux x64 release. Focused analysis is strict; full-project errors fail while legacy warnings and infos remain visible.

Checks use read-only repository access and do not publish downloads. A newer push cancels an older checks run for the same branch or pull request. Requiring these checks before merging is a separate branch-protection setting.

## Nightly builds on GitHub

[The workflow](../.github/workflows/nightly.yml) runs at **03:23 UTC daily** and can be started manually with **Run workflow** from [GitHub Actions](https://github.com/woodk123/lcs-underground-edition/actions/workflows/nightly.yml). It runs only on the default branch. It skips a build when game/build inputs match the last successfully published Nightly; documentation-only commits do not trigger a rebuild.

CI first checks for changed inputs, then builds and checks Linux on Ubuntu 22.04. Once that passes, Windows CI downloads the checked bundle and runs `scripts/build_release.ps1 -Nightly -LinuxBundle "$PWD/.local/linux"`. Flutter tests, analysis, Linux, web and Windows builds, source packaging and archive integrity must pass before publication. A failed Linux job prevents publication and leaves the previous nightly available.

Each [Nightly](https://github.com/woodk123/lcs-underground-edition/releases?q=nightly-) has separate Windows Player, Linux Player, Web Player and Source ZIPs, each with a SHA-256 sidecar. All players reference the same corresponding Source ZIP, which includes Linux build evidence. The publisher uploads and verifies a complete new draft before publishing it and retiring older managed nightlies. The early preview and manually created releases are kept separate. CI logs remain Actions artifacts for seven days.

Nightlies have automated coverage; they are not certification of every gameplay path or a clean-machine native launch. See [release checks](TESTING.md#release-checks). When redistributing players, keep their exact matching source available under the included GPL v2 terms.
