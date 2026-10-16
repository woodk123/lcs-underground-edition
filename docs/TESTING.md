# Testing

Run commands from the repository root unless noted otherwise. Install the [pinned toolchain](BUILDING.md) and generate dependencies/serialization with the build script first.

## Automated regressions

```powershell
Set-Location upstream
..\.tools\flutter\bin\flutter.bat test --no-pub
..\.tools\flutter\bin\flutter.bat analyze --no-pub
```

The suite covers the original engine, command routing, order confirmation/cancellation, saves and migrations, equipment, politics, campaign endings, portraits and responsive UI. Save files under `upstream/test/saves/` are regression fixtures, not disposable player saves.

Release tooling uses Python's standard library:

```powershell
python -m unittest discover -s scripts -p 'test_*.py' -v
python scripts/verify_assets.py
```

The tests exercise archive integrity/tampering, complete source snapshots, local and nightly packaging, release-size accounting and limits, unchanged-input detection and safe publication. Flutter regressions also decode every runtime WebP, check atlas dimensions and native alpha fidelity, and exercise conservative web renderer pruning. No live GitHub release is modified by these tests.

## Browser regressions

The supported browser helpers use isolated contexts and test fixtures. They never operate a player's browser profile. Their Node dependencies are in `upstream/tool/offline_test/`:

```powershell
npm install --prefix upstream/tool/offline_test
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/launch.ps1 -Port 18879 -NoBrowser
node scripts/browser_review.mjs --url http://127.0.0.1:18879/
```

`browser_review.mjs` checks dossier skill hierarchy, portrait-age repair, mechanics disclosure at normal and enlarged text, and exact exported-save equality after inspection and cancelled drafts. Screenshots and JSON results are written under ignored `reports/`.

Founder creation uses an installed Chrome and an exact compiled-build hash:

```powershell
$expected = (Get-FileHash upstream/build/web/main.dart.js -Algorithm SHA256).Hash.ToLowerInvariant()
node scripts/creation_browser_review.mjs --url http://127.0.0.1:18879/ --expected-hash $expected
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/stop.ps1 -Port 18879
```

The first helper uses installed Microsoft Edge. The creation helper exercises visible portrait rerolls without changing name/settings text, answer-bonus tooltips and click-through at normal and 150% text, manual and random backgrounds, public-name entry and playable headquarters at normal size and 800×600 with 150% text. Use only the isolated QA port when stopping a test server.

## Release checks

Each build report records automated command exit codes and source identity. Generated reports and old test counts are not a substitute for a current run. Review the build log and release-specific metadata for what actually ran.

```powershell
python scripts/verify_package.py 'release/<build>/<extracted-package-folder>'
```

Keep its ZIP and `.zip.sha256` beside the extracted folder. Verification checks the manifest, file inventory, paths, archive SHA-256 and each ZIP member's contents/CRC.

Before describing a release as manually accepted, test its extracted launcher, campaign creation, load/save/export/import, assignments, day advancement and any changed gameplay path. Browser offline claims need cache activation plus a save/reload with networking disabled; server-stopped claims need the test server actually stopped. Native GUI and clean-machine launch checks are separate from compilation and browser results.

Historical reports are retained in Git history, old release artifacts and local ignored evidence. Published previews keep their original verification scope; later source or packaging changes do not retroactively certify them.
