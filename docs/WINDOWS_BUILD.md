# GitHub early preview — 15 October 2026

Download the Windows ZIP from the [early preview release](https://github.com/woodk123/lcs-underground-edition/releases/tag/underground-preview-2026.10.15), extract the whole folder and run `lcs_new_age.exe`. This is a work in progress. The package includes the modified source, credits and app-local runtime DLLs; Python and Flutter are not required to play.

For this release, use the included `BUILD_INFO.json`, `FILES.sha256` and GitHub release notes for build identity and verification scope. The native version has not received a complete graphical playthrough or a clean-machine launch check. The dated results below describe earlier local builds.

# Historical Gangsters journal Windows build

The final journal source compiled in 29.9 seconds and is packaged alongside the corresponding accepted web/source release. It passes 352 tests and clean focused/full analysis. Current build identity, test count and native archive are in `release/DELIVERY.json`; current browser evidence is in [GANGSTERS_JOURNAL_ACCEPTANCE.md](GANGSTERS_JOURNAL_ACCEPTANCE.md). Native graphical playthrough remains outside the verified scope after the user's stop instruction. No native UI automation resumed. The package includes its app-local Visual C++ runtime, fonts and license notices.

## Historical previous UI build — 1aa0be78



The current navigation/space/explanations source compiles successfully for Windows in 27.6 seconds; `reports/final-windows-build.log` records the final build. The matching source passes 225 tests and clean focused/full analysis. The native layout/playthrough remains outside the verified scope after the user's stop instruction; no native UI automation resumed. See `UI_FRICTION_ACCEPTANCE.md` for current browser acceptance. Native archives include the matching corresponding source and app-local runtime dependencies.

The following earlier build notes remain useful setup/history, rather than the identity of the current delivery.

# Native Windows build

## Play

In the Windows release folder, double-click `lcs_new_age.exe`. Keep its `data` directory and all DLL files beside it. This native build does not require Python, a browser, Flutter, Visual Studio, an API key or an internet connection to play. It targets Windows 10/11 x64; compilation was performed on Windows 11.

The packager includes the app-local Visual C++ runtime (`msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`) from the installed Visual Studio redistributable directory. This is Flutter's documented ZIP deployment layout, alongside every DLL and `data/` from the release build. See [Flutter Windows packaging](https://docs.flutter.dev/platform-integration/windows/building#building-your-own-zip-file-for-windows).

Saves are stored under `%APPDATA%\LCS New Age\lcs_new_age\lcs_new_age.db`. Browser saves are separate; use the existing export/import interface to transfer a campaign. Preferences are stored by `shared_preferences_windows` through the Windows roaming application-support directory.

## Rebuild

The tested toolchain on 13 October 2026 was:

- Flutter 3.47.7 stable, framework revision `abaf9c523780a608bd46686fd5e53740a07077f8`.
- Dart 3.13.5.
- Visual Studio Build Tools 2022 17.14.28, MSVC v143 x64 tools.
- Windows SDK 10.0.26100.0.

From the repository root, run the normal dependency/serialization/test workflow documented in `README.md`. Then:

```powershell
.\.tools\flutter\bin\flutter.bat doctor -v
Set-Location upstream
..\.tools\flutter\bin\flutter.bat build windows --release --no-pub
```

The executable is `upstream/build/windows/x64/runner/Release/lcs_new_age.exe`. The complete `Release` folder is the runtime unit; the EXE alone is insufficient. The final runner source uses the window title `Liberal Crime Squad: New Age — The Underground Edition`, with an initial 1280 × 720 window. Product metadata uses that game name and the description `Liberal Crime Squad: New Age — The Underground Edition`; the executable filename remains compatible with the upstream build.

The Windows/C++ doctor checks passed. PATH and Android license warnings did not affect the native build. No Visual Studio installation or OS configuration change was needed.

### Plugin junction fallback

The first build stopped because this machine could not create symbolic links without Developer Mode. Flutter's `createPluginSymlinks()` skips existing links when building with `--no-pub`. Creating directory junctions in ignored platform `flutter/ephemeral/.plugin_symlinks` directories let the normal build proceed. This changes only local build caches; it does not modify Flutter source or Windows settings.

If this same permission issue occurs, run the following from the checkout root after dependencies are resolved, then retry the native build:

```powershell
$taskPlugins = Get-Content -LiteralPath upstream\.flutter-plugins-dependencies -Raw | ConvertFrom-Json
foreach ($taskPlatform in @('windows', 'linux')) {
    $taskLinkRoot = Join-Path (Get-Location).Path ('upstream\' + $taskPlatform + '\flutter\ephemeral\.plugin_symlinks')
    New-Item -ItemType Directory -Path $taskLinkRoot -Force | Out-Null
    foreach ($taskPlugin in $taskPlugins.plugins.$taskPlatform) {
        $taskLink = Join-Path $taskLinkRoot $taskPlugin.name
        $taskTarget = [System.IO.Path]::GetFullPath($taskPlugin.path)
        if (!(Test-Path -LiteralPath $taskTarget -PathType Container)) {
            throw ('Missing plugin target ' + $taskTarget)
        }
        if (!(Test-Path -LiteralPath $taskLink)) {
            New-Item -ItemType Junction -Path $taskLink -Target $taskTarget | Out-Null
        }
    }
}
```

Running dependency refresh with forced plugin regeneration can remove these cache junctions. Recreate them when needed. Do not copy `.plugin_symlinks`, the Pub cache or the Flutter SDK into a distribution.

## Package

The repeatable packager preserves existing releases, includes all native runtime files, app-local C++ DLLs, license/credits, documentation, Roboto/Flutter notices and SHA-256 hashes. A companion source/web release contains the corresponding modified source. Supply that package directory once final source packaging is complete:

```powershell
python scripts/package_windows.py --root . --runtime-dir 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\14.44.35112\x64\Microsoft.VC143.CRT' --source-package 'release\<final-source-package>'
```

Omitting `--source-package` permits a local package for QA, but its corresponding-source reference must be finalized before distribution. The default output is `release/LiberalCrimeSquad-NewAge-UndergroundEdition-Windows`; if that folder exists, a new timestamped sibling is created rather than overwriting it.

## Verification status

The final frozen city/crew extension source compiled successfully on 13 October 2026 in 30.6 seconds; the log is `reports/final-windows-build.log` and is copied into release build evidence. This includes selectable generated buildings and inspectors, portraits/dossiers, the eight-frame animation, responsive city layout, graphical floor map, complete articles and staged text entry. Runtime files and required deployment DLLs are checked by the packaging script. A `dumpbin /DEPENDENTS` inspection confirms the EXE's Flutter, plugin and three Visual C++ runtime dependencies match the bundled deployment set; Windows system DLLs are supplied by the supported OS. Shared game/UI logic is covered by 174 Flutter tests and the compiled browser acceptance run.

An earlier native title window was inspected. Further native computer control was stopped by the user and was not resumed. The final native package has not received a complete graphical playthrough or clean-machine launch check. These are recorded limits, not claims established by compilation or the browser results.

For native QA, the game database respects an `APPDATA` override. However, `shared_preferences_windows` uses `SHGetKnownFolderPath` for its application-support path, independently of that environment variable. An `APPDATA` override alone therefore does not guarantee that legacy preferences/migration data are isolated. Do not launch a test that could migrate legacy saves until preference isolation is also established. Never delete an existing user's game data for QA.
