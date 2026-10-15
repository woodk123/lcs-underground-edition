# Windows player and native builds

Download the **[Windows player ZIP](https://github.com/woodk123/lcs-underground-edition/releases/download/underground-preview-2026.10.15/LCS-Underground-Edition-2026.10.15-Windows-x64-Player.zip)** from the [15 October 2026 early preview](https://github.com/woodk123/lcs-underground-edition/releases/tag/underground-preview-2026.10.15), extract the whole folder and run `lcs_new_age.exe`. This is a work in progress. The player package includes the game, credits, licenses and app-local runtime DLLs; Python and Flutter are not required to play.

The **[matching source ZIP](https://github.com/woodk123/lcs-underground-edition/releases/download/underground-preview-2026.10.15/LCS-Underground-Edition-2026.10.15-Source.zip)** is a separate download on the same release. It contains the modified game source, generated serializers, dependency lockfile, build scripts and documentation. Each player package's `SOURCE_REFERENCE.md` identifies it. Keep the matching source available alongside the player package when redistributing under GPL v2.

Use the included `BUILD_INFO.json`, `FILES.sha256` and release notes for identity and verification scope. The split player package retains the original preview binaries; their corresponding game source matches commit `626adbef0a0f578d2ac049173185de3090036a8c`; the packaging revision is recorded separately. Repackaging does not add gameplay coverage. The native version has not received a complete graphical playthrough or a clean-machine launch check. Focused founder and offline browser checks passed; the complete legacy browser run remains incomplete.

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

From the repository or extracted source root, run the dependency/serialization/test workflow in [Building and development](BUILDING.md). Then:

```powershell
.\.tools\flutter\bin\flutter.bat doctor -v
Set-Location upstream
..\.tools\flutter\bin\flutter.bat build windows --release --no-pub
```

The executable is `upstream/build/windows/x64/runner/Release/lcs_new_age.exe`. The complete `Release` folder is the runtime unit; the EXE alone is insufficient. The runner uses the window title `Liberal Crime Squad: New Age — The Underground Edition`, with an initial 1280 × 720 window. Product metadata uses that game name and description; the executable filename remains compatible with the upstream build.

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

`package_windows.py` creates an intermediate combined package with native runtime files, app-local C++ DLLs, license/credits, component notices, documentation and SHA-256 hashes. Supply the combined web/source package created by `build_release.ps1`:

```powershell
python scripts/package_windows.py --root . --runtime-dir 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\14.44.35112\x64\Microsoft.VC143.CRT' --source-package 'release\<final-source-package>'
```

The default output is `release/LiberalCrimeSquad-NewAge-UndergroundEdition-Windows`; if that folder exists, a new timestamped sibling is created. Omitting `--source-package` is only suitable for local QA until the matching source has been supplied. For publication, use `package_preview.py` to split verified combined packages into player and source ZIPs; see [split preview downloads](BUILDING.md#split-preview-downloads). Publish the matching source on the same release as both player packages.

## Historical build evidence — 13 October 2026

Earlier city/crew, navigation and journal builds compiled in 30.6, 27.6 and 29.9 seconds, with 174, 225 and 352 tests respectively. These are historical snapshots, not the current preview's test counts. Browser evidence for those stages is in [UI friction acceptance](UI_FRICTION_ACCEPTANCE.md) and [Gangsters journal acceptance](GANGSTERS_JOURNAL_ACCEPTANCE.md). A historical `dumpbin /DEPENDENTS` inspection matched the EXE's Flutter, plugin and three Visual C++ runtime dependencies to the bundled deployment files; Windows system DLLs are supplied by the supported OS.

An earlier native title window was inspected. Further native computer control was stopped by the user and was not resumed. Compilation and browser results do not establish native graphical or clean-machine launch coverage.

For native QA, the game database respects an `APPDATA` override. However, `shared_preferences_windows` uses `SHGetKnownFolderPath` for its application-support path, independently of that environment variable. An `APPDATA` override alone therefore does not guarantee that legacy preferences/migration data are isolated. Do not launch a test that could migrate legacy saves until preference isolation is also established. Never delete an existing user's game data for QA.
