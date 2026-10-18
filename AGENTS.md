# Working in this repository

The Flutter game lives in `upstream/`; fork documentation and build tools live at the repository root. Follow [building](docs/BUILDING.md), [testing](docs/TESTING.md) and [architecture](docs/ARCHITECTURE.md) for the existing workflows. Keep generated reports and review captures in ignored `.local/` or `reports/` directories.

## Development practice

Follow [development lessons](docs/DEVELOPMENT_LESSONS.md) for the working loop and checks matched to the change.

- Inspect Git status before editing, preserve concurrent work, and stage only an explicit task-owned path allowlist when committing.
- Keep the original gameplay reader and source-authored action identities/revisions authoritative. Inspection, help and cosmetic animation must preserve campaign state, pending input and gameplay RNG.
- For UI/routing changes, check the affected journey with retained scroll/selection state, cancellation, revisiting screens and keyboard focus. Include compact/enlarged layouts where affected; an isolated widget pass does not cover the whole interaction.
- Iterate with focused checks, then verify the integrated result appropriate to the change. Use the pinned SDK, fully restart after engine changes, and identify the exact build served during isolated browser QA. Keep historical test/timing reports distinct from current verification.

## Versioning and changelog decisions

Apply [the versioning policy](docs/VERSIONING.md) whenever changing player-visible behavior or preparing a release.

- For a player-visible fix or feature, add a concise entry under **Unreleased** in `upstream/assets/changelog.md`. Describe what changes for the player. Internal refactoring, tests, documentation and build maintenance without a player-visible effect do not require an entry or a version bump.
- Do not bump the version for every task, commit, push or nightly. Accumulate changes until a named preview or release is being prepared. A request to commit and push alone is not a release request.
- When preparing a release, choose the bump autonomously from the whole unreleased batch: **patch** for fixes, small interface improvements, wording and modest balance changes; **minor** for a substantial feature, new system or significant interface improvement. Use the highest applicable level and explain the choice in the final report. Routine patch/minor decisions do not need confirmation.
- A **major** bump requires explicit direction from the user. Continue authorized implementation and checks while leaving that release decision pending.
- For the first numbered Underground release, finalize the initial `0.1.0` development baseline instead of immediately bumping it again. This exception applies only while the changelog has no dated Underground release section.
- Keep `gameVersion` in `upstream/lib/utils/game_version.dart` and `version` in `upstream/pubspec.yaml` synchronized. When releasing, move Unreleased notes into a dated version section and leave an empty Unreleased section above it.
- Keep `upstreamVersion`, `saveCompatibilityVersion`, the release version and source build ID separate. Never change save compatibility merely to advertise a release. Save-format changes require an explicit migration/compatibility design and save regression checks.
- Preserve the inherited New Age changelog. Keep the source revision visible for bug reports and use the appropriate Development, Preview, Nightly or Release channel.

Run checks appropriate to the changed behavior before committing. Changes to version/save handling must include the version, save migration/recovery and title layout checks described in the policy.
