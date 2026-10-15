# Building and development

These instructions use Windows PowerShell, Git and Python 3.12 or later. Run commands from the repository root, containing `upstream/`, `scripts/` and `docs/`. In a packaged release, use its `source/` folder instead.

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

The script resolves dependencies, generates save serialization code, runs tests and analysis, builds the web game and adds its offline manifest. It creates a uniquely named folder and ZIP under `release/`, including source, credits, license, checksums and build logs. Existing packages are preserved.

Double-click **Play.cmd** at the repository root to play the built game, or extract a release ZIP and use its launcher. The source checkout launcher serves `upstream/build/web` at **http://127.0.0.1:8765/**. A packaged build needs Python 3, but no Flutter SDK or API key.

Use the same browser profile and address for existing browser saves. `localhost:8765` and `127.0.0.1:8765` have separate storage. Export important saves before clearing browser data. Do not open `index.html` directly.

To stop the launcher's local server:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/stop.ps1
```

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
