# Versioning

The Underground Edition has its own player-facing version, starting at **0.1.0**. This establishes a development baseline for the existing fork; it does not announce a new published release or renumber the earlier date-tagged preview. Versions below 1.0 reflect the current work in progress.

## Identifiers and their sources

| Identifier | Source | Purpose |
|---|---|---|
| Underground release version | `gameVersion` in `upstream/lib/utils/game_version.dart` | Helps players identify releases and judge the scale of an update. Mirror it in `upstream/pubspec.yaml`; a regression check prevents drift. |
| Release channel | Compile-time `LCS_CHANNEL`, default `Development` | Distinguishes local development, named previews, nightly candidates and releases. |
| New Age base version | `upstreamVersion` in the same Dart file | Records the upstream version on which the fork is based, currently 1.5.6. |
| Save compatibility version | `saveCompatibilityVersion` in the same Dart file | Writes the existing save header, rejects newer unsupported saves and preserves historical migration gates. It remains 1.5.6. |
| Source build ID | Compile-time `LCS_BUILD`, default `development` | Records the eight-character Git revision supplied by the builders for precise bug reports and matching source. |

The title footer shows the Underground release and channel first, then the New Age base and source build ID. A build ID is useful diagnostic information; it does not replace a release version. The package version describes this fork, so it must not be copied into save headers.

## Choosing a bump

Choose from the complete batch of changes since the last numbered release, not the number of commits or lines changed. Agents may choose patch and minor bumps without asking. These game-release conventions apply during 0.x development too.

| Change in the batch | Bump | Example |
|---|---|---|
| Fixes, small UI improvements, wording corrections, modest balance changes | Patch | 0.1.0 → 0.1.1 |
| Substantial feature, new gameplay system, significant interface improvement | Minor; reset patch | 0.1.1 → 0.2.0 |
| Major milestone or deliberate breaking change | Major; explicit user direction | 0.8.3 → 1.0.0 |
| Internal refactoring, tests, documentation or build maintenance with no player-visible effect | None | Keep the current version |

A substantial new People or Bases chapter is a minor change; fixing a clipped button or an incorrect crafting cost is a patch. A mixed batch containing a substantial feature receives one minor bump. A save incompatibility must be called out and designed explicitly even during 0.x; the release number alone cannot enforce save compatibility.

## During normal development

1. Add concise player-facing notes under **Unreleased** in `upstream/assets/changelog.md`. Group related work and explain its effect, without implementation details or claims of testing that did not happen.
2. Keep the release version unchanged until a named preview or release is prepared. Ordinary commits, pushes and automatic nightlies do not consume version numbers.
3. In the completion report, mention an appropriate future bump when it helps explain the change. Do not treat every minor polish change as a new feature release.

Unreleased notes appear in the in-game changelog of development/nightly builds. Preserve the original entries below **New Age history**. `docs/ORIGINAL_CODE_CHANGES.md` remains the broader description of how this fork differs from New Age.

## Preparing a named release

1. Review the unreleased batch and choose the highest applicable bump. For the first numbered Underground preview/release, finalize the existing 0.1.0 baseline. No bump is necessary to repackage identical release source.
2. Update `gameVersion` and the package version together. Move the batch into a `## Underground Edition X.Y.Z — YYYY-MM-DD` section using the actual release date, leaving an empty Unreleased section above it. Mention any save consequences clearly.
3. Run version and save regressions, title layout checks and the regular release checks. Commit the release source before packaging, as required by the builders.
4. Use a unique tag for each published preview/release. Existing date-based preview/nightly tag conventions remain valid; the embedded game version is independent of the tag. Keep players and matching source together.
5. Report the version selected and why. Preparing a version or committing/pushing does not itself publish a release.

`scripts/build_release.ps1` selects **Nightly** with `-Nightly`, **Preview** with `-Tag`, and **Development** otherwise. `-Channel Release` labels an explicitly prepared release, including one built with `-Tag`. CI players are **Nightly** candidates so that identical checked artifacts can be reused by nightly publication. Their source commit still identifies the exact build. The standalone Linux builder defaults to Development; use `--channel Preview` or `--channel Release` to match a manually prepared package. Direct Flutter builds may supply `--dart-define=LCS_CHANNEL=Preview` and `--dart-define=LCS_BUILD=<revision>`.

## Save compatibility

Keep compatibility independent of release numbering and upstream credits. Changing Underground 0.1.0 to 0.2.0 must neither write 0.2.0 into old-format saves nor reject existing 1.5.6 campaigns. The save format and its current New Age migration comparisons are unchanged by this policy. Keeping the compatibility label is not a promise that upstream New Age understands every fork-specific field.

Before changing the compatibility identifier, decide how existing campaigns migrate and how older builds will reject unsupported data. Add meaningful round-trip/import/recovery coverage and document the consequences. Adding an optional field does not automatically require a compatibility bump; assess the actual reader and migration behavior.

For version/save changes, run these from `upstream/` with the pinned SDK:

```powershell
..\.tools\flutter\bin\flutter.bat test --no-pub test/game_version_test.dart test/save_load_test.dart test/save_round_trip_test.dart test/save_recovery_test.dart test/journal_title_test.dart
```

The version check also reads the real package manifest to catch version drift. Title tests cover narrow windows and enlarged reading sizes. Follow [Testing](TESTING.md) for analysis and the full release suite.
