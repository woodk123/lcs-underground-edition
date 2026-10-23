# Development MCP

The development MCP lets an assistant inspect a running game, choose its current source actions and collect reproducible bug evidence. It is useful for investigating stuck readers, checking campaign consequences and exploring paths that do not yet have a browser helper. It shares the original game handlers; it contains no alternative gameplay rules.

## Setup

Install the pinned Flutter SDK described in [Building](BUILDING.md), Python 3.11 or later, Node.js 20 or later and Microsoft Edge or Chrome. From the repository root:

```powershell
python scripts/prepare_dev_mcp.py --configure-codex
```

This verifies the Flutter pin, checks the current Node version and locked package inventory, repairs affected Node tool directories with development dependencies included, generates serializers and compiles a development web player under `.local/dev-mcp/web`. Node must meet the committed packages' engine requirements. It records source and payload hashes in `.local/dev-mcp/build.json`. Subsequent runs reuse that build only when the game inputs (including ignored generated `.g.dart` serializers), toolchain pin, preparation recipe and every built file still match. Run it after editing game code or the preparation scripts; use `--rebuild` to force compilation. Close active MCP sessions before rebuilding.

On Windows, package resolution can stop at plugin link creation when symlink privilege is unavailable. Follow the [project-local plugin junction setup](WINDOWS_BUILD.md#plugin-junction-setup-without-developer-mode), then retry preparation. It uses the generated plugin metadata and preserves existing matching links without changing machine settings.

The default `lcs_start` also checks freshness against the current checkout and refuses stale or modified builds. `python scripts/prepare_dev_mcp.py --check` performs that check without rebuilding. Custom historical artifacts are permitted with an explicit `webRoot`; their result reports that source freshness was not checked, and `expectedHash` can pin the intended artifact.

`--configure-codex` adds this server to the machine-local `.codex/config.toml`, which is ignored by Git. It retains unrelated configuration and refuses to overwrite a conflicting server entry. Reconnect MCP servers or open a new chat to load the connection. Project MCP configuration is supported for trusted projects; see the [official Codex MCP documentation](https://developers.openai.com/codex/mcp). No model API key or hosted service is required.

Other MCP clients can launch the same stdio server with an absolute Node executable and the absolute path to `scripts/dev_mcp/server.mjs`; set its working directory to this repository. The server starts promptly without building or launching a browser. A game session starts only when `lcs_start` is called.

## Working loop

1. Run the preparation command against settled source.
2. Call `lcs_start` with default arguments. It serves the prepared build on an owned loopback port and opens a fresh disposable browser context. It checks the JavaScript actually loaded by the browser against its SHA-256 and verifies the bridge handshake. The result includes the build identity, first observation and evidence directory.
3. Read the current observation. Use `lcs_inspect` with `scope: "summary"` or `scope: "person", personId: ...` to investigate consequences. `scope: "context"` gives named locations, pending recruitment, vehicles and the existing encounter without a full campaign dump. These are debugging fields, including hidden locations; they do not predict recruitment success. Request `scope: "campaign"` only when complete saved fields are needed.
4. Choose an enabled action from `observation.actions`. Call `lcs_act` with its `actionId` and the observation's `revision`. The result supplies the next decision, so ordinary play does not need an extra observation call after every action. Use `lcs_input_text` when a source reader requests text.
5. On an unexpected result, call `lcs_capture` with a meaningful name. Preserve the returned paths in the fix report, add a focused regression, then run the existing checks appropriate to the change.
6. Call `lcs_close` to finalize the session and close its owned resources.

Always inspect a rejected or timed-out action before retrying. A timeout can follow an accepted command; it does not mean that command never happened. `lcs_wait` observes progress without answering it. Encounters and confirmations remain individual decisions.

During a tactical reader, `observation.map` supplies the same read-only snapshot as the graphical map: coordinates, an ASCII grid and legend, known cells with terrain and interaction hints, and adjacent source movement actions linked by their current IDs. `#` is a known wall, `+` a door, `@` the squad and `?` unexplored terrain. Unknown cells expose no flags, enemies, loot or lock state. Remembered cells are distinguished from those in view. `full_map` uses the full already-explored floor; other tactical readers use the graphical viewport. Movement terrain describes the known target; it does not predict an encounter or bypass the source handler. Nested prompts retain the displayed squad position and expose no movement action unless the original reader does.

`observation.reportContext` includes readable authored article headlines/bodies and legislative proposals/outcomes. Pending proposals remain marked pending; no votes are rolled or outcomes predicted by inspection. A child acknowledgement takes precedence over retained parent metadata.

For a chain of reports, call `lcs_continue_reports` with the sole observed acknowledgement's `actionId` and `revision`. It continues at most `maxReports` (default 20, maximum 100) within `timeoutMs` (default 10000, maximum 30000), retaining a screenshot and structured snapshot before each acknowledgement plus the ordinary action trace. Each returned report includes its screen, kind, title and readable text; older/plain readers fall back to their console text. It stops before any source choice, multiple-action reader, text entry or blocked input. The result includes `completedReports`, `stopReason`, evidence paths and the final observation. Limits do not select a default action. Stale capabilities and errors stop execution and return completed progress; a timed-out action may already have taken effect.

For **Export Save File**, pass `expectDownload: true` to `lcs_act`. It installs the native download waiter before dispatch and returns `downloads` containing absolute retained paths, byte counts, original suggested filenames and SHA-256 hashes. The bytes come directly from the browser download and survive `lcs_close`; the MCP does not synthesize a save from inspection. Repeated filenames get separate files. All native downloads are retained automatically; `lcs_observe` and `lcs_close` also return the session's completed downloads and download errors. If retaining an export fails after acceptance, inspect the result and evidence before retrying. An `accepted: true` error result confirms dispatch succeeded; its absence does not prove dispatch failed.

To check a checkpoint, close the session and pass the retained export path as `fixture` to a fresh `lcs_start`. This uses the real file picker and save loader in a new disposable context. Record any original load-time repairs separately when comparing state.

The MCP can start with a supplied save using `lcs_start({fixture: "path/to/campaign.json"})`. The copy is imported through the original UI into disposable storage. Record that starting condition honestly. Prepared injuries, money or contacts are not outcomes earned during play.

## Tools

| Tool | Purpose |
|---|---|
| `lcs_start` | Own a loopback server and disposable browser; verify the loaded build; optionally import a fixture. |
| `lcs_observe` | Read reader text, pending text entry, input status, blocking reason, current actions and revision. |
| `lcs_inspect` | Read summary, compact play context, one person or complete saved campaign fields. |
| `lcs_act` | Execute one observed action; optionally await its native download with `expectDownload`. |
| `lcs_continue_reports` | Continue only sole source acknowledgements within count/time limits, retaining every report and stopping at decisions. |
| `lcs_input_text` | Replay text through the existing source reader and submit with Enter or Escape. |
| `lcs_wait` | Wait at most 30 seconds for an input-ready reader, optionally a changed revision or exact screen. |
| `lcs_capture` | Write a screenshot, observation and inspection beside build metadata and the action trace. |
| `lcs_close` | Close only this session's browser/server and retain its report. |

For a custom build, pass `webRoot` and optionally `expectedHash` to `lcs_start`. The supplied build must have `LCS_DEVTOOLS=true`; ordinary distributed players do not expose the bridge. `headed: true` shows the owned browser for observation. `browser` chooses `msedge` or `chrome`; `browserExecutable` can identify an installed Chromium executable. No player browser profile is reused.

## Evidence and boundaries

Session evidence is retained under ignored `reports/` or `.local/`. It includes the loaded JavaScript hash, bridge build identity, requests, results, elapsed times, rejected actions and browser errors. Named captures provide screenshots and structured state for bug reports. Keep failures as well as successes. Old captures describe their recorded build, not the current checkout.

Use `lcs_close` to let pending native exports finish before closing the disposable context. If the MCP host disconnects, cleanup closes its owned browser and loopback server first so a stalled download cannot hold them open; interrupted exports remain recorded as download errors in `session.json` and the trace.

The bridge reads without making gameplay rolls, advancing time or answering pending input. Actions retain their original object identity and revision. Modal inspection, presentation drafts and busy input boundaries prevent underlying commands. Text entry uses the same editor replay as the visible game. There are no arbitrary JavaScript, raw key, money-setting or state-editing tools.

Menus can also publish a source navigation context without painting a Back action. The bridge exposes its exact Back key as a `source_navigation` action, retaining the navigation object and revision. Replaced navigation, text readers and explicitly disabled Back actions cannot be bypassed through it.

An authored acknowledgement exposes only its scoped Continue capability. Generic reports can retain their parent menu's painted choices internally; those obsolete labels are excluded until the original report reader finishes.

Complete campaign inspection contains saved fields, not every tactical runtime value or an RNG checkpoint. Action traces help explain and reproduce a path, but do not promise identical stochastic outcomes after reloading. Use deterministic engine tests for exact rule regressions and explicit fixtures for rare branches.

Structured gameplay control does not certify graphical layout, keyboard focus, scrolling, pointer navigation or native Windows behavior. Continue using the [shared acceptance journey](TESTING.md#shared-acceptance-journey) and affected browser checks. Existing fixed tests remain faster and more repeatable for known assertions; the MCP helps investigate new questions and produces evidence for turning them into regressions.

## Verification

```powershell
python -m unittest discover -s scripts -p 'test_prepare_dev_mcp*.py' -v
npm test --prefix upstream/tool/dev_mcp
node scripts/dev_mcp/smoke.mjs
Push-Location upstream
..\.tools\flutter\bin\flutter.bat test --no-pub test/development_bridge_test.dart
..\.tools\flutter\bin\flutter.bat test --no-pub --dart-define=LCS_DEVTOOLS=true test/development_bridge_test.dart
Pop-Location
```

The MCP package tests exercise the real stdio protocol in addition to session contracts. The Dart bridge regressions cover read-only state/RNG, current-action identity, stale readers and input boundaries. Run both default-disabled and explicitly enabled configurations: the enabled run exercises actual shell/modal/text integration. CI requires the enabled run on Linux and Windows as well as the normal regression shards. Use the pinned SDK and fully restart after engine changes.

The smoke journey talks to the shipped stdio executable and the compiled player. It creates a fresh founder through all ten original background decisions, continues the political briefing through the bounded helper and requires it to stop at text entry, then submits the public name. It verifies inspection purity, rejects a stale action, advances an actual day (using bounded continuation if reports occur) and checks save/continue. It records the original first-load lazy NPC normalization separately, then requires complete campaign equality on the next save/continue. It exports the original save, verifies retained bytes/hash after closing the browser, and imports that file in a fresh session with complete campaign equality. No starting campaign or earned outcome is supplied to the initial journey. Its `smoke.json` retains call timings, checks and build identity; these are measurements of that run, not a general speedup claim.
