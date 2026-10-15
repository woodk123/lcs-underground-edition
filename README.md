# Liberal Crime Squad 2026

A playable modernization of [Liberal Crime Squad: New Age](https://github.com/ashley-s-fox/lcs-new-age), with an organisation interface closely following **Gangsters: Organized Crime (1998)**. Its eight illustrated tabs, squad portrait tabs, open paper journal, brass binding, crew pool and pinned job cards follow the original manual and screens. The complete Dart gameplay engine and authored campaign content remain in place. Flutter preserves those rules without the risks of rewriting the game in another engine.

Select a squad from the left portrait tabs and a person directly from its roster. Open Orders, browse a group and prepare a task on the facing page; the job card explains the real skills, cost, restrictions, risks and timing before Confirm. Cancel leaves the existing assignment intact. The crew pool supports arrows and drag between the facing pages, with real skill ratings. Select a known building in the Business map or City maps, choose **Visit with selected squad**, then **Confirm visit**. The destination card names the squad and explains next-day travel; inspection alone changes no assignment. Cancelling a prepared visit preserves an already queued destination. Advancing time uses the original daily engine and its siege/attack restrictions.

The period paper, leather, portraits, chapter illustrations and activity paintings are original ChatGPT-generated assets with recorded prompts and crop metadata in `assets/gangsters-journal/atlas_metadata.json`. All labels and interactions are rendered live. Field operations, full-floor maps, equipment and specialist decisions use the same journal, with pinned movement, visible command scrolling and readable crew details. Earlier city/tactical artwork and the complete character dossiers remain available; map geometry is illustrative. The expanded adult portrait library contains 250 painted faces across six broad backgrounds, with saved identities, age and profession preferences, and duplicate avoidance among known crew and contacts. Source artwork, prompts and crop metadata are in `assets/portraits-v2/`; see [PORTRAIT_LIBRARY.md](docs/PORTRAIT_LIBRARY.md).

[GANGSTERS_MANUAL_AUDIT.md](docs/GANGSTERS_MANUAL_AUDIT.md) records the complete 104-page research and separates original Gangsters mechanics from LCS rules. [GANGSTERS_JOURNAL_ACCEPTANCE.md](docs/GANGSTERS_JOURNAL_ACCEPTANCE.md) records the earlier packaged journal build, browser interaction/save/offline evidence and verification boundaries. Later live updates and their exact runtime checks are recorded in [GAMEPLAY_FIDELITY.md](docs/GAMEPLAY_FIDELITY.md) and `release/DELIVERY.json.current_live_update`. `release/DELIVERY.json` identifies the accepted archives. The matching Windows build is additional; native graphical playthrough remains outside the verified browser scope after the user stopped native UI control.

The code is based on upstream revision `a1a2112dabf4a8d1a25e36a7a747ef99c9318b87`. Original authors and the GPL v2 license are in `upstream/AUTHORS.md` and `upstream/LICENSE` in the checkout, or `AUTHORS.md` and `LICENSE` beside this README in a release package. Releases include both credits and the corresponding modified source.

## Play locally

Extract the complete release archive and double-click **Play.cmd**. It starts a hidden local Python server and opens **http://127.0.0.1:8765/** in your default browser, preserving the original local game address. No Flutter SDK or API key is needed to play the built game. The launcher requires Python 3; it discovers `python.exe` when the development machine's Python path is unavailable.

Keep using the same browser profile and `127.0.0.1:8765` address: browser saves belong to that origin. **`localhost:8765` has separate browser storage**, as does a different port, private browsing or another browser. Export an important save through the game's save interface before clearing browser data. Do not open `index.html` directly with a `file://` URL.

The service worker caches the built game and local CanvasKit files after its initial successful load. The verified package reloaded, played another day, saved and reloaded again with its server stopped and browser networking disabled. Browser storage availability and retention still depend on the browser/profile. The local server can serve an extracted package without an internet connection.

In a source checkout, Play.cmd serves `upstream/build/web`. Build it first using the release command below. To stop the hidden server:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/stop.ps1
```

## Build from source

In an extracted release, open its `source/` directory before following development or test commands. In the original checkout, stay at the checkout root. These commands run from the directory containing `upstream/`, `scripts/` and `docs/`.

Use Windows PowerShell, Git and Python 3.12 or later. The local Flutter SDK is pinned to **3.47.7 stable**, revision `abaf9c523780a608bd46686fd5e53740a07077f8`, in `scripts/toolchain.json`. SDK tools and build outputs stay outside source control.

If `.tools/flutter` is absent, install that exact SDK in the checkout:

```powershell
New-Item -ItemType Directory -Force .tools
git clone --depth 1 --branch 3.47.7 https://github.com/flutter/flutter.git .tools/flutter
git -C .tools/flutter rev-parse HEAD
```

The revision must match the pin above. The release script verifies both Flutter version and revision before using it. Dependency downloads require internet access during setup/build. From the checkout root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build_release.ps1
```

The script resolves dependencies, regenerates JSON serialization, runs tests, analyzes the changed modern UI/main/console files strictly, records full-project analysis separately, builds release web files, injects the upstream offline manifest and packages the result. Full-project warnings/infos stay visible in their own log; errors fail the build. Every native tool's exit code is checked. It does not claim manual campaign, usability or offline-save QA has passed.

Output is a uniquely named directory and ZIP under `release/`, with SHA-256 checksums, build logs, documentation, license/credits and a `source/` snapshot. Existing packages are preserved. The source snapshot contains the modified engine/presentation, dependency lockfile, generated serialization, local assets and build scripts. Development SDKs, caches and build products are excluded.

For development after dependencies and serialization are generated:

```powershell
Set-Location upstream
..\.tools\flutter\bin\flutter.bat run -d chrome
```

The upstream engine runs a sequential curses-style game loop; perform a full application restart when changing engine code. Hot reload alone cannot reliably reset that loop.

## Verification and scope

[Original code changes and bug fixes](docs/ORIGINAL_CODE_CHANGES.md) gives a short summary of the modernization and the separate corrections.

The latest [month playtest](docs/MONTH_PLAYTEST.md) covers 31 consecutive browser days, daily save/reload, a real field operation and monthly reports. It documents the corrected unaffordable crafting cloth-loss bug, six crafting regressions, corrected announcement/vote feedback, an independent engine month and 436 passing tests.

[DELIVERY_PLAN.md](docs/DELIVERY_PLAN.md) explains the scope and workflows adapted from RacingDynasty. [RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md) records the eight completed acceptance contracts and coverage limits. The current frozen build and its exact test/analysis counts are recorded in `release/DELIVERY.json`; original campaign/end-state fixtures and the source-fidelity audit complement actual browser scenarios. Native full GUI verification, exhaustive specialist branches and hardware benchmarking are not claimed.

[GANGSTERS_JOURNAL_ACCEPTANCE.md](docs/GANGSTERS_JOURNAL_ACCEPTANCE.md) and [BROWSER_QA.md](docs/BROWSER_QA.md) record exact runtime identities and screenshots: real building inspection/orders, city zoom/fit/list, HQ/task/city dossiers, animation PNG/WebM evidence, reduced motion, founder creation, assignments, navigation, browser restart/export/import/recovery, a real public operation, adjacent movement, full-map zoom/fit and server-stopped offline saves. The upgrade preserves an existing QA campaign and reads its original news story on the new build. Each refreshed archive's BUILD_INFO, file manifest, SHA-256 sidecar and integrity report identify the delivered artifact.

To rerun browser acceptance against an already served build, install the Playwright test dependencies and its matching FFmpeg component (`npx playwright install ffmpeg`) in `upstream/tool/offline_test`, then run:

```powershell
node scripts/journal_browser_review.mjs --url http://127.0.0.1:18876/ --package-root <absolute-package-directory>
```

The script uses an isolated headless Edge context and writes dated screenshots/reports under `reports/browser/`, including the exact served JavaScript hash. It uses real browser input rather than game-state hooks. See the QA document for supported arguments and the limits of each completed run.
