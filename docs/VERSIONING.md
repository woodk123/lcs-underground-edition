# Versioning

The Underground Edition has its own player-facing version, starting at **0.1.0**, the first numbered release prepared on 18 October 2026. It finalizes the fork's initial development baseline; the earlier date-tagged previews retain their original identities. Versions below 1.0 reflect the current work in progress.

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

Choose from the complete coherent batch of player-visible changes not yet assigned a version, not the number of commits or lines changed. Apply the decision before committing or pushing completed work, including ordinary development pushes and nightlies; do not wait for a named release. Agents may choose patch and minor bumps without asking. These conventions apply during 0.x development too.

| Change in the batch | Bump | Example |
|---|---|---|
| Fixes, small UI improvements, wording corrections, modest balance changes | Patch | 0.1.0 → 0.1.1 |
| Substantial feature, new gameplay system, significant interface improvement or substantial expansion of visual content | Minor; reset patch | 0.1.1 → 0.2.0 |
| Major milestone or deliberate breaking change | Major; explicit user direction | 0.8.3 → 1.0.0 |
| Internal refactoring, tests, documentation or build maintenance with no player-visible effect | None | Keep the current version |

A substantial new People or Bases chapter, a redesigned Orders workspace or completing a large equipment artwork catalogue is a minor change; fixing a clipped button, a single missing sprite or an incorrect crafting cost is a patch. A mixed batch containing a substantial change receives one minor bump. A save incompatibility must be called out and designed explicitly even during 0.x; the release number alone cannot enforce save compatibility.

Version 0.2.0 assigns the accumulated changes after 0.1.0 a new player-facing identity: complete equipment artwork, the Orders workspace and display preferences, Classic keyboard flow, and related fixes. This is a minor bump because the batch substantially expands the interface and visual content, even though the underlying gameplay rules and save compatibility remain separate.

## During normal development

1. Add concise player-facing notes under **Unreleased** in `upstream/assets/changelog.md`. Group related work and explain its effect, without implementation details or claims of testing that did not happen.
2. Before committing or pushing a completed player-visible batch, choose its patch/minor bump, synchronize both version fields, move its notes into a dated version section and leave an empty Unreleased section above it. Apply this to artwork and presentation changes as well as gameplay rules. Internal-only work, additional commits for the same already versioned batch, rebuilds and repackaging do not consume another version number.
3. A dated version section records the source change batch, not proof of a published download. Preserve Development/Nightly channels until an actual preview/release is prepared. A commit/push request or version bump does not by itself authorize a tagged public release or hosted deployment.

The in-game changelog includes Unreleased notes and dated version sections. Preserve the original entries below **New Age history**. `docs/ORIGINAL_CODE_CHANGES.md` remains the broader description of how this fork differs from New Age.

## Before committing or pushing

Versioning is a required review step for every requested commit or push, even when the correct decision is to leave the version unchanged.

1. **Review impact and the requested outcome.** A completed player-visible batch needs a patch/minor bump even for an ordinary commit/push or nightly. Internal-only work or an already versioned batch keeps the current version. Decide separately whether publication was requested; a commit/push request alone does not authorize a tagged public release.
2. **Check the player-facing notes.** Fixes and features need an Unreleased entry. Internal tests, documentation and build maintenance without a player-visible effect need neither a changelog entry nor a bump.
3. **Apply any required version changes before committing.** Choose patch/minor bumps autonomously; major bumps still require explicit direction. Synchronize both version fields, date the versioned notes and run the version/save/title checks. Keep save compatibility separate. Named release preparation additionally needs the regular release checks.
4. **Verify and commit the intended work.** Run checks appropriate to the changes, inspect the staged diff and use an explicit task-owned path allowlist. Preserve unrelated work. Verify the remote commit after pushing.
5. **Report the version decision.** State the commit, push status, current game version and the impact-based reason for changing or retaining it. For example: “Pushed `<commit>`; version is 0.2.0 for the expanded interface and complete equipment artwork.” Do not report an unchanged version solely because the build is a nightly or ordinary push.

If publication was requested, also report its actual outcome and URL. Verify that the published nightly/release references the intended commit; do not call a queued or running workflow published. Before saying the browser game is updated, check its hosted `BUILD_INFO.json` against that commit. Report failures or pending deployment honestly.

## Preparing a named release

1. Review any completed Unreleased work and apply the highest applicable bump if it is not already versioned. Use the current version when publishing an already versioned source batch; publishing or repackaging alone does not require another bump. The initial 0.1.0 baseline was finalized on 18 October 2026.
2. Ensure `gameVersion` and the package version agree. Record newly versioned work in a `## Underground Edition X.Y.Z — YYYY-MM-DD` section dated when the batch was versioned, leaving an empty Unreleased section above it. Preserve that date when publishing later; release metadata records the publication date separately. Mention any save consequences clearly.
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
