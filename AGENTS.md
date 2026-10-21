# Working in this repository

The Flutter game lives in `upstream/`; fork documentation and build tools live at the repository root. Follow [building](docs/BUILDING.md), [testing](docs/TESTING.md) and [architecture](docs/ARCHITECTURE.md) for the existing workflows. Keep generated reports and review captures in ignored `.local/` or `reports/` directories.

## Development practice

Follow [development lessons](docs/DEVELOPMENT_LESSONS.md) for the working loop and checks matched to the change.

- Inspect Git status before editing, preserve concurrent work, and stage only an explicit task-owned path allowlist when committing.
- Keep the original gameplay reader and source-authored action identities/revisions authoritative. Inspection, help and cosmetic animation must preserve campaign state, pending input and gameplay RNG.
- For UI/routing changes, check the affected journey with retained scroll/selection state, cancellation, revisiting screens and keyboard focus. Include compact/enlarged layouts where affected; an isolated widget pass does not cover the whole interaction.
- Iterate with focused checks, then verify the integrated result appropriate to the change. Use the pinned SDK, fully restart after engine changes, and identify the exact build served during isolated browser QA. Keep historical test/timing reports distinct from current verification.
- For changes spanning creation, orders, navigation or saves, use the [shared acceptance journey](docs/TESTING.md#shared-acceptance-journey): `python scripts/shared_acceptance.py`. Preserve its fresh-campaign continuation and explicitly prepared branch coverage when extending it.
- For interactive engine debugging and exploratory playthroughs, use the [development MCP](docs/DEV_MCP.md). Prepare a current build with `python scripts/prepare_dev_mcp.py`; its cache verifies source and compiled artifacts. Start a disposable session, choose current action IDs with their observed revision, and retain captures/traces for defects. Use ordinary regression/browser checks for the resulting fix; MCP source actions alone do not establish UI layout, focus or pointer behavior.

## Versioning and changelog decisions

Apply [the versioning policy](docs/VERSIONING.md) whenever changing player-visible behavior or preparing a release.

- For a player-visible fix or feature, add a concise entry under **Unreleased** in `upstream/assets/changelog.md`. Describe what changes for the player. Internal refactoring, tests, documentation and build maintenance without a player-visible effect do not require an entry or a version bump.
- Version completed player-visible changes before committing or pushing them, including ordinary development pushes and nightlies. Choose the bump from the impact of the coherent change batch, not the number of tasks or commits. Internal-only work and repackaging an already versioned batch do not need another bump. A version bump does not itself authorize publishing a tagged release or deploying the hosted game.
- Choose the bump autonomously from the whole unversioned batch: **patch** for fixes, small interface improvements, wording and modest balance changes; **minor** for a substantial feature, new system, significant interface improvement or substantial expansion of visual content. Use the highest applicable level and explain the choice in the final report. Routine patch/minor decisions do not need confirmation.
- A **major** bump requires explicit direction from the user. Continue authorized implementation and checks while leaving that release decision pending.
- Keep `gameVersion` in `upstream/lib/utils/game_version.dart` and `version` in `upstream/pubspec.yaml` synchronized. When bumping, move the completed Unreleased batch into a dated version section and leave an empty Unreleased section above it. A dated section identifies versioned source; it does not claim that a public release has been published.
- Keep `upstreamVersion`, `saveCompatibilityVersion`, the release version and source build ID separate. Never change save compatibility merely to advertise a release. Save-format changes require an explicit migration/compatibility design and save regression checks.
- Preserve the inherited New Age changelog. Keep the source revision visible for bug reports and use the appropriate Development, Preview, Nightly or Release channel.

Run checks appropriate to the changed behavior before committing. Changes to version/save handling must include the version, save migration/recovery and title layout checks described in the policy.

## Commit and push checklist

Follow [the commit/push versioning checklist](docs/VERSIONING.md#before-committing-or-pushing) for every requested commit or push, including documentation-only work.

- Review player impact before committing: version completed player-visible changes even for an ordinary push or nightly, while retaining the version for internal-only work or an already versioned batch. Review named preview/release publication separately.
- Confirm the changelog and any required version changes are complete, run the applicable checks, and stage only the task-owned path allowlist. Choose routine patch/minor release bumps without asking again.
- In the completion report, state the commit and push status, the release version, and why it changed or stayed unchanged.
- When a nightly or release is requested, verify publication for the intended commit before reporting it as published. If reporting the hosted game as updated, verify its build metadata matches that commit. A dispatched workflow alone is not a completed build or deployment.
