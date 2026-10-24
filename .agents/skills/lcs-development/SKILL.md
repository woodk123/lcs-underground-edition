---
name: lcs-development
description: Develop and maintain the LCS Underground Edition repository, selecting focused checks, preparing traceable development builds, and investigating original gameplay readers. Use for this repository's Flutter game, build tools, tests, assets, and development documentation.
---

# LCS development

Work from the repository containing `upstream/`, `scripts/toolchain.json` and `AGENTS.md`. Read the applicable `AGENTS.md` first; it owns repository policy. Keep commands relative to that root so the workflow works in another checkout or worktree.

## Find the relevant boundary

Use the maintained guides rather than copying their commands or test lists into this skill:

| Work | Read when needed |
|---|---|
| Setup, dependencies, serializers or local builds | [Building](../../../docs/BUILDING.md), using the pinned `scripts/toolchain.json` SDK. |
| Choosing regressions or reviewing an interaction | [Focused checks](../../../docs/TESTING.md#choose-focused-checks) and [development lessons](../../../docs/DEVELOPMENT_LESSONS.md). |
| UI extraction, source actions or awaited readers | [Architecture](../../../docs/ARCHITECTURE.md), then [input ownership](../../../docs/INPUT_OWNERSHIP.md) or [Classic keyboard contract](../../../docs/CLASSIC_KEYBOARD.md) for input work. |
| Exploratory engine play or a stuck reader | [Development MCP](../../../docs/DEV_MCP.md). |
| Runtime artwork, masters, manifests or portraits | [Assets](../../../docs/ASSETS.md) and, for faces, [portrait library](../../../docs/PORTRAIT_LIBRARY.md). |
| Version/save handling, a commit, push or release | [Versioning](../../../docs/VERSIONING.md), including its commit/push checklist. |

Inspect Git status before edits. Identify existing changes and task-owned paths. When delegating, agree file ownership and coordinate shared SDKs, generated output and QA ports; a parallel report does not establish an integrated build.

If local setup is uncertain, run `python scripts/developer_doctor.py` first. The building guide describes its optional browser, MCP and tooling checks. A passing prerequisite inventory does not establish current serializers, passing code checks or an accepted build.

## Choose the working loop

For a known defect, reproduce the actual failing boundary and start with its existing focused regression. Keep the original reader and exact observed action/revision authoritative; presentation state and source input have different owners. Check the source calculation before changing explanatory text.

For internal tools or documentation, run the relevant tooling tests or verify the documented commands and references. Use the [local documentation check](../../../docs/TESTING.md#documentation-and-skill-checks) after guide or skill edits; it needs no Flutter build. A Flutter player build is useful only when the affected behavior needs it. Keep generated evidence under ignored `.local/` or `reports/` and distinguish a current run from historical evidence.

For UI or routing work, define the complete interaction before editing: retained selection/scroll, cancellation, revisiting, focus and relevant compact/enlarged layouts. Once source settles, use the shared acceptance journey for changes spanning creation, orders, navigation or saves. Preserve its new founder's continuation and separately declared prepared scenarios. Follow the testing guide for supplemental journeys outside that coverage.

## Investigate through the development MCP

Prepare the cached development build with `python scripts/prepare_dev_mcp.py`, then start a disposable session as described in its guide. Observe the current reader, choose one of its current action IDs and send its observed revision. After an action fails or times out, observe again before deciding what to do: the action may already have been accepted.

For final development acceptance, pin `lcs_start.expectedHash` to preparation's `main_js_sha256`. Record the startup result's original `compiledSource`, current `checkedSource` and loaded `mainJsSha256` together; a verified cache hit can retain an older compiled commit.

Use inspection and captures to explain the defect; save the action trace and actual loaded-build identity. Keep each attempt in a new ignored output directory, retaining the initial failure's diagnostics beside any successful retry. Use the native export flow for a restorable checkpoint rather than synthesizing a save from inspection. Close the owned session when finished. Turn a discovered defect into an ordinary regression and, where relevant, a browser journey; structured engine control cannot verify pointer bounds, focus or layout.

## Leave a reviewable result

Review the integrated diff and run checks matched to the final change. State what changed, the checks actually run, the source/build identity when applicable, and remaining limits. Review player impact before a commit or push: internal maintenance retains the game version; a completed player-visible batch follows the version policy. Versioning or preparing a build does not authorize publication or deployment.
