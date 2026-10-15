# Building and development

Use Windows PowerShell, Git and Python 3.12+. Commands run from the repository root, containing `upstream/` and `scripts/`. A prepared Source ZIP has the same layout and can be rebuilt without a `.git` folder; its `BUILD_INFO.json` records the source identity.

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

## Development mode

After the build has resolved dependencies and generated serializers:

```powershell
Set-Location upstream
..\.tools\flutter\bin\flutter.bat run -d chrome
```

Restart the application fully after changing engine code. See [architecture](ARCHITECTURE.md), [testing](TESTING.md) and [assets](ASSETS.md).

## Checks on pushes and pull requests

[Project checks](../.github/workflows/checks.yml) runs on every push and pull request, and can also be started manually. It tests the release tools, verifies assets, generates serializers, runs Flutter tests and performs focused/full-project analysis with the pinned SDK. Focused analysis is strict; full-project errors fail while legacy warnings and infos remain visible.

Checks use read-only repository access and do not publish downloads. A newer push cancels an older checks run for the same branch or pull request. Requiring these checks before merging is a separate branch-protection setting.

## Nightly builds on GitHub

[The workflow](../.github/workflows/nightly.yml) runs at **03:23 UTC daily** and can be started manually with **Run workflow** from [GitHub Actions](https://github.com/woodk123/lcs-underground-edition/actions/workflows/nightly.yml). It runs only on the default branch. It skips a build when game/build inputs match the last successfully published Nightly; documentation-only commits do not trigger a rebuild.

CI runs the release-tool tests, verifies asset provenance, installs the pinned SDK and runs `scripts/build_release.ps1 -Nightly`. Flutter tests, analysis, web and Windows builds, source packaging and archive integrity must pass before publication.

Each [Nightly](https://github.com/woodk123/lcs-underground-edition/releases?q=nightly-) has separate Windows Player, Web Player and Source ZIPs. The publisher uploads and verifies a complete new draft before publishing it and retiring older managed nightlies. The early preview and manually created releases are kept separate. CI logs remain Actions artifacts for seven days.

Nightlies have automated coverage; they are not certification of every gameplay path or a clean-machine native launch. See [release checks](TESTING.md#release-checks). When redistributing players, keep their exact matching source available under the included GPL v2 terms.
