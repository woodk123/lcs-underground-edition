# Windows builds

The native game targets **Windows 10/11 x64**. Extract the complete Windows Player ZIP and run `lcs_new_age.exe`; keep `data/` and all DLLs beside it. Python, Flutter and Visual Studio are not required to play.

The matching Source ZIP is a separate download on the same release. Each player includes `SOURCE_REFERENCE.md` with its source URL and checksum, plus `LICENSE`, `AUTHORS.md` and component notices. Keep matching source available when redistributing.

## Build locally

Install Visual Studio 2022 Build Tools with **Desktop development with C++**, MSVC v143 and a Windows SDK. Install the pinned Flutter SDK as described in [BUILDING.md](BUILDING.md), then run from the repository/source root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build_release.ps1 -Windows
```

This runs the shared tests/analysis, builds web and Windows, then creates **Windows Player + Web Player + Source** ZIPs and SHA-256 sidecars. Source includes generated serializers and the dependency lockfile; build tools and caches are excluded. The packager locates app-local Visual C++ runtime DLLs through `vswhere.exe` and includes the required `msvcp140.dll`, `vcruntime140.dll` and `vcruntime140_1.dll`.

Do not mix DLLs or data folders from different builds. `BUILD_INFO.json`, `FILES.sha256` and the ZIP sidecars identify the package. See [TESTING.md](TESTING.md) for verification commands and coverage limits.

## Saves

Native saves are stored per Windows user under `%APPDATA%\LCS New Age\lcs_new_age\lcs_new_age.db`. Browser saves belong to their browser profile and origin. Use the game's export/import controls to transfer campaigns.

For automated tests, use isolated data. An `APPDATA` override alone does not isolate all Windows preferences: `shared_preferences_windows` can use the Windows known-folder API separately. Do not run native QA against a player's existing profile.

The standard executable supports an explicit local profile:

```powershell
.\lcs_new_age.exe --data-directory="D:\LCS-QA\campaign-one"
```

Use an absolute directory. Both `lcs_new_age.db` and `preferences.json` stay inside
it, including scores, settings and the last-used campaign. The default profile
is neither read nor migrated when this option is present. Launching without the
option retains the normal Windows save and preference locations.
