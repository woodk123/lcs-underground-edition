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

### Quality 90 size measurements (17 October 2026)

Build `94ef3a09529fa35c0ba8e755c4f526a96987af3f` regenerated all 42 runtime images from their original PNG masters at WebP quality 90. Image dimensions, portrait cells and alpha pixels are unchanged. The shared encoder and regenerated manifests make subsequent builds use the same policy; see [artwork regeneration](ASSETS.md).

Actual player sizes, compared with the `underground-preview-2026.10.16` packages:

| Player | Previous ZIP bytes | Quality 90 ZIP bytes | Download reduction | Quality 90 extracted bytes |
|---|---:|---:|---:|---:|
| Browser | 34,540,400 | 22,453,164 | 12,087,236 bytes (35.0%) | 38,081,854 |
| Windows x64 | 42,700,237 | 30,645,529 | 12,054,708 bytes (28.2%) | 54,732,218 |

The artwork payload itself fell from 26,405,232 to 14,322,460 bytes (45.8%). The package comparison includes other code changes since the preview, so the ZIP differences are whole-build measurements rather than an isolated compression benchmark. Quality 90 was selected after comparing qualities 90, 85 and 80: representative faces, icons, buildings and textures remained close to the existing art, with more visible smoothing at the lower qualities. Visual review covered representative samples, not every image in every gameplay view.

The local artifacts are under `release/local-20261017-090800-94ef3a09/`, including player ZIPs, matching source, checksum sidecars and `size-report.json`. Build evidence is under `.local/reports/build-20261017-090455/`. These directories are ignored by Git and are not hosted download links. Validation passed all 736 Flutter tests, both focused and full analysis, asset verification, ZIP integrity and checksum checks, and byte comparisons of all 42 packaged images against the regenerated files. Manual gameplay and clean-machine launch checks remain pending.

### Running and packaging players

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

Development does not require a clean checkout or release packaging. After installing the pinned SDK above, verify it and generate dependencies/serializers from the repository root:

```powershell
. ./scripts/common.ps1
$flutter = Get-LcsFlutter
Push-Location upstream
try {
    & $flutter --suppress-analytics pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
    ..\.tools\flutter\bin\dart.bat run build_runner build
    if ($LASTEXITCODE -ne 0) { throw 'Serializer generation failed.' }
} finally {
    Pop-Location
}
```

Regenerate serializers after changing saved model fields or JSON annotations. Then start the development game:

```powershell
Set-Location upstream
..\.tools\flutter\bin\flutter.bat run -d chrome
```

Restart the application fully after changing engine code. See [architecture](ARCHITECTURE.md), [testing](TESTING.md) and [assets](ASSETS.md).

## Keeping the checkout tidy

Write build logs, browser reports and review images under the ignored `.local/` or `reports/` directories. Release packages belong under ignored `release/`; SDKs and dependency/build caches are generated local files. Historical root-level diagnostic logs have been moved to `reports/legacy-root-logs/` where present. Test counts and outcomes in those logs describe their original run; use a current run to assess current source.

Keep source artwork, prompts, manifests, license notices and `upstream/test/saves/` fixtures. They support regeneration, attribution and regression coverage even when the player does not load them directly. Validate runtime asset removal with `python scripts/verify_assets.py` and check code, XML catalogues and tests for references before deleting a candidate. See [Artwork and assets](ASSETS.md) for the authoritative source/runtime copies.

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

[Project checks](../.github/workflows/checks.yml) runs on every push and pull request, and can also be started manually. It calls the shared [checked-player pipeline](../.github/workflows/ci.yml). Two test shards on each of Windows 2022 and Ubuntu 22.04 run alongside independent Linux and Windows/web release builds. Every test file runs once per operating system; shard 0 also runs release-tool tests, asset verification and focused/full-project analysis. Focused analysis is strict; full-project errors fail while legacy warnings and infos remain visible.

The shared setup caches the pinned Flutter SDK and Dart package downloads separately for each operating system. SDK keys include the toolchain file; package keys also include `pubspec.lock`. Cached SDKs still have their version and revision verified. Only trusted build workers save shared caches. No compiled player or passed-test status is taken from a cache.

Generator tooling has a separate exact-key cache for `.dart_tool/build/entrypoint`, `.dart_tool/pub/bin/build_runner` and `.dart_tool/build_resolvers`. Its key includes the OS/architecture, pinned toolchain, dependency lockfile, package manifest and builder configuration. Successful default-branch build workers populate it after running serialization. Project `.g.dart` files, the build asset graph and generated intermediate outputs are excluded: workers still regenerate serializers and `build_runner` still checks compiled-tool dependencies for freshness. Cache misses run the same full generator command.

Both test shards also emit Flutter JSON timing reports. The reviewed `scripts/ci_test_weights.json` profile balances per-file loading/execution costs separately for Linux and Windows, reserving time for shard 0's tooling, asset and analysis checks. Test inventory always comes from the current source tree: new files get a median cost estimate, removed files disappear, and every current file belongs to exactly one shard per OS. With no profile, workers use the original deterministic round-robin split. Timing weights change only through a reviewed commit, not during a CI run. To update them from the four successful shard artifacts, run `python scripts/ci_shards.py --reports .local/check-timings --output scripts/ci_test_weights.json` after downloading `checks-*` artifacts into that directory.

Each worker retains its logs and a machine-readable report with source commit, toolchain, Actions run identity, step results and timings. Reports also record exact shard coverage or runtime file hashes. A final verification job requires all four shards and both builds to pass and match before the workflow succeeds. Build artifacts and reports remain available for seven days.

Checks use read-only repository access and do not publish downloads. A newer push cancels an older checks run for the same branch or pull request. Requiring these checks before merging is a separate branch-protection setting.

## Nightly builds on GitHub

[The workflow](../.github/workflows/nightly.yml) runs at **03:23 UTC daily** and can be started manually with **Run workflow** from [GitHub Actions](https://github.com/woodk123/lcs-underground-edition/actions/workflows/nightly.yml). It runs only on the default branch. It skips a build when game/build inputs match the last successfully published Nightly; documentation-only commits do not trigger a rebuild.

After checking for changed inputs, the nightly looks for a successful **push** run of Project checks from the same repository, default branch and exact commit. If that push is still running, it polls every ten seconds for up to twenty minutes rather than starting duplicate work. A successful run is reusable only while all six required artifacts remain available. PR runs, different commits, missing/expired artifacts and failed runs do not provide reusable checks. Without usable evidence, the nightly runs the shared pipeline itself, with Linux and Windows/web builds in parallel.

The publication job downloads artifacts from the selected Actions run, verifies all shard inventories, check results, commit/toolchain/run identities and runtime file hashes, then packages the players and matching source. Generated serializers travel with the build artifacts; every check and build must record identical generated-source hashes. Publication restores those exact files into its fresh checkout. Original CI evidence is included in the Source ZIP. The packager rechecks that evidence against the actual payloads before archiving. It also retains the existing source-cleanliness, runtime-completeness, size-budget, archive-integrity and checksum gates. No Flutter SDK installation or compilation is needed in the publication job. A failed check or build prevents publication and leaves the previous nightly available.

Publication validates the same-commit upstream evidence for tooling and asset checks instead of rerunning those checks a third time. Artifact validation, package verification, size budgets, source matching and SHA-256 verification still run at the publication boundary.

The local `scripts/build_release.ps1` and standalone Linux builder retain their complete self-contained checks; CI reuse does not create a local skip-tests switch. Cache misses remain supported and produce the same checks and players. Warm-run speed depends on runner availability and test-shard balance; use worker reports rather than assuming fixed savings.

Each [Nightly](https://github.com/woodk123/lcs-underground-edition/releases?q=nightly-) has separate Windows Player, Linux Player, Web Player and Source ZIPs, each with a SHA-256 sidecar. All players reference the same corresponding Source ZIP, which includes Linux build evidence. The publisher uploads and verifies a complete new draft before publishing it and retiring older managed nightlies. The early preview and manually created releases are kept separate. CI logs remain Actions artifacts for seven days.

Nightlies have automated coverage; they are not certification of every gameplay path or a clean-machine native launch. See [release checks](TESTING.md#release-checks). When redistributing players, keep their exact matching source available under the included GPL v2 terms.

## Hosted nightly on GitHub Pages

**[Play latest nightly](https://woodk123.github.io/lcs-underground-edition/)** serves the latest successfully published managed Nightly. [The Pages workflow](../.github/workflows/pages.yml) runs after successful nightly workflow completion and can also be started manually to redeploy the current Nightly without rebuilding the game. It runs only from the default branch, selects the newest published Nightly (excluding drafts and previews), and verifies the web/source downloads against their SHA-256 sidecars and package metadata.

Pages uses the exact compiled JavaScript and assets from the downloaded Web Player. Preparation changes the hosted copy's HTML base path to `/lcs-underground-edition/`, adds source/credits links and refreshes the corresponding service worker manifest hashes. The downloadable ZIP stays unchanged. The matching Source ZIP and license notices are hosted alongside the game so that retiring an old Nightly release cannot remove the deployed game's corresponding source. Source downloads are excluded from the offline precache.

Before deployment, the browser smoke test checks online startup at the project path, service worker precaching and offline reload. Preparation, smoke test or deployment failure leaves the previously deployed site available. Deployments are serialized, and a successful nightly run that skipped unchanged inputs can safely redeploy the same published version. GitHub repository Settings → Pages must use **GitHub Actions** as its publishing source.

Saves use IndexedDB in each player's browser profile. Deploying at the same site address retains those saves; the service worker updates runtime caches without deleting IndexedDB. Browser profiles/devices have separate saves; profiles shared by multiple people share their save list. Export/import transfers campaigns between devices or the downloaded player. Clearing site data can remove saves. Keeping the address stable does not replace save-format compatibility testing for future game changes.
