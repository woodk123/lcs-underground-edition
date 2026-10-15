# Building and development

These instructions use Windows PowerShell, Git and Python 3.12 or later. Run commands from the repository root, containing `upstream/`, `scripts/` and `docs/`. The separate [preview source ZIP](https://github.com/woodk123/lcs-underground-edition/releases/download/underground-preview-2026.10.15/LCS-Underground-Edition-2026.10.15-Source.zip) uses the same layout: open its extracted top-level folder. Player ZIPs contain the game and runtime; download the source ZIP to build or modify it.

## Install Flutter

The project pins Flutter **3.47.7 stable**, revision `abaf9c523780a608bd46686fd5e53740a07077f8`, in [scripts/toolchain.json](../scripts/toolchain.json).

If `.tools/flutter` is absent:

```powershell
New-Item -ItemType Directory -Force .tools
git clone --depth 1 --branch 3.47.7 https://github.com/flutter/flutter.git .tools/flutter
git -C .tools/flutter rev-parse HEAD
```

The revision must match the pin above. The build script checks it before using the SDK. Initial setup and dependency downloads need internet access.

## Build and play

From the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build_release.ps1
```

The script resolves dependencies, generates save serialization code, runs tests and analysis, builds the web game and adds its offline manifest. It creates a uniquely named combined web/source folder and ZIP under `release/`, with credits, license, checksums and build logs. This is an intermediate package; the public preview uses separate player and source downloads as described below. Existing packages are preserved.

Double-click **Play.cmd** at the repository root to play the built game, or extract a release ZIP and use its launcher. The source checkout launcher serves `upstream/build/web` at **http://127.0.0.1:8765/**. A packaged build needs Python 3, but no Flutter SDK or API key.

Use the same browser profile and address for existing browser saves. `localhost:8765` and `127.0.0.1:8765` have separate storage. Export important saves before clearing browser data. Do not open `index.html` directly.

To stop the launcher's local server:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/stop.ps1
```

For a native Windows build, see [Windows build instructions](WINDOWS_BUILD.md).

## Split preview downloads

The [15 October 2026 preview](https://github.com/woodk123/lcs-underground-edition/releases/tag/underground-preview-2026.10.15) has three assets: a Windows player ZIP, a browser player ZIP and one matching source ZIP. The player packages omit duplicate source, reference artwork and development reports. Runtime artwork, fonts and component notices remain included.

To repackage the existing verified combined packages without rebuilding the game:

```powershell
python scripts/package_preview.py --root . --web-package 'release\<combined-web-package>' --windows-package 'release\<combined-windows-package>' --output 'release\<split-preview-output>'
```

The script writes the three ZIPs and verification metadata. Use a fresh output directory and publish all three on the same GitHub release. `SOURCE_REFERENCE.md` in each player package identifies its matching source download. Keep that source available alongside the player packages when redistributing under GPL v2. GitHub's automatic repository-source downloads are not a substitute for the prepared source asset, which also includes generated Dart serializers and the dependency lockfile.

The repackaged preview keeps the original binaries; their corresponding game source matches the tree at commit `626adbef0a0f578d2ac049173185de3090036a8c`. `BUILD_INFO.json` records the original build, matching game source and packaging identities separately; repackaging adds no new gameplay test coverage. The preview's focused founder and offline browser checks passed; the complete legacy browser run remains incomplete, and the native build has not had a complete graphical playthrough or clean-machine launch check.

## Nightly builds on GitHub

The **Nightly Windows and web** Actions workflow checks the default branch daily at **03:23 UTC** (03:23 UK winter time / 04:23 UK summer time). It can also be started from GitHub's **Actions → Nightly Windows and web → Run workflow** button. Feature-branch manual runs are skipped.

It compares the Git identities of `upstream/` (including runtime assets, dependencies and tests), `scripts/`, `.github/` and `Play.cmd` with the last successfully published nightly. Unchanged inputs skip SDK installation and builds. Documentation-only changes outside those paths do not trigger a rebuild. Failed builds or uploads are retried on the next run because they do not advance the published input fingerprint.

Changed inputs run the pinned Flutter toolchain, serialization generation, tests, analysis, web/offline build and Windows x64 build on a GitHub-hosted Windows runner. The workflow packages Windows and web player ZIPs, matching source (including generated serializers), and SHA-256 sidecars. Windows packages include app-local Visual C++ runtime DLLs. No personal SDK path or extra release secret is required; the workflow uses GitHub's built-in token with repository contents write permission.

Downloads appear in a prerelease titled **Nightly**, with a unique `nightly-<run-id>-<attempt>` tag. All six assets are uploaded to a draft and checked before publication. Only after publication succeeds does the workflow retire earlier releases carrying its nightly tag and metadata marker. The existing `underground-preview-*` releases are never selected for replacement or cleanup, and the nightly is never marked as GitHub's latest stable release. Failed uploads may leave a draft, which a later successful run cleans up. The most recent successful nightly stays available if checks or uploads fail.

Build logs are retained as Actions artifacts for seven days. Automated builds do not certify manual gameplay, browser offline acceptance or clean-machine native launch. Export important campaigns before trying a nightly. Scheduled runs can be delayed by GitHub; public-repository schedules may be disabled after 60 days without activity.

## Development

After dependencies and serialization have been generated:

```powershell
Set-Location upstream
..\.tools\flutter\bin\flutter.bat run -d chrome
```

The Flutter project lives in `upstream/`; the repository root holds the launcher, build scripts, artwork sources and documentation. The game is based on original New Age revision `a1a2112dabf4a8d1a25e36a7a747ef99c9318b87`.

Perform a full application restart after changing engine code. Hot reload cannot reliably reset the original sequential game loop.

## Verification

The release script checks native command exit codes. Focused analysis is strict; full-project legacy warnings and infos are logged separately, while errors fail the build. Automated success alone does not establish manual gameplay or usability coverage.

See [gameplay fidelity](GAMEPLAY_FIDELITY.md), the [month playtest](MONTH_PLAYTEST.md), [browser QA](BROWSER_QA.md) and the [release checklist](RELEASE_CHECKLIST.md) for recorded checks and their limits. Locally generated reports and release packages are excluded from Git.

To rerun browser acceptance against an already served build, install the Playwright dependencies and matching FFmpeg component (`npx playwright install ffmpeg`) in `upstream/tool/offline_test`, then run from the repository root:

```powershell
node scripts/journal_browser_review.mjs --url http://127.0.0.1:18876/ --package-root <absolute-package-directory>
```

This uses an isolated headless Edge context and writes dated evidence under `reports/browser/`. See [BROWSER_QA.md](BROWSER_QA.md) for supported arguments and verification boundaries.
