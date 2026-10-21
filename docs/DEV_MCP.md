# Development MCP

The development MCP lets an assistant inspect a running game, choose its current source actions and collect reproducible bug evidence. It is useful for investigating stuck readers, checking campaign consequences and exploring paths that do not yet have a browser helper. It shares the original game handlers; it contains no alternative gameplay rules.

## Setup

Install the pinned Flutter SDK described in [Building](BUILDING.md), Python 3.11 or later, Node.js 20 or later and Microsoft Edge or Chrome. From the repository root:

```powershell
python scripts/prepare_dev_mcp.py --configure-codex
```

This installs locked Node dependencies, verifies the Flutter pin, generates serializers and compiles a development web player under `.local/dev-mcp/web`. It records source and payload hashes in `.local/dev-mcp/build.json`. Subsequent runs reuse that build only when the source identity and every built file still match. Run it after editing game code; use `--rebuild` to force compilation. Close active MCP sessions before rebuilding.

The default `lcs_start` also checks freshness against the current checkout and refuses stale or modified builds. `python scripts/prepare_dev_mcp.py --check` performs that check without rebuilding. Custom historical artifacts are permitted with an explicit `webRoot`; their result reports that source freshness was not checked, and `expectedHash` can pin the intended artifact.

`--configure-codex` adds this server to the machine-local `.codex/config.toml`, which is ignored by Git. It retains unrelated configuration and refuses to overwrite a conflicting server entry. Reconnect MCP servers or open a new chat to load the connection. Project MCP configuration is supported for trusted projects; see the [official Codex MCP documentation](https://developers.openai.com/codex/mcp). No model API key or hosted service is required.

Other MCP clients can launch the same stdio server with an absolute Node executable and the absolute path to `scripts/dev_mcp/server.mjs`; set its working directory to this repository. The server starts promptly without building or launching a browser. A game session starts only when `lcs_start` is called.

## Working loop

1. Run the preparation command against settled source.
2. Call `lcs_start` with default arguments. It serves the prepared build on an owned loopback port and opens a fresh disposable browser context. It checks the JavaScript actually loaded by the browser against its SHA-256 and verifies the bridge handshake. The result includes the build identity, first observation and evidence directory.
3. Read the current observation. Use `lcs_inspect` with `scope: "summary"` or `scope: "person", personId: ...` to investigate consequences. Request `scope: "campaign"` only when complete saved fields are needed.
4. Choose an enabled action from `observation.actions`. Call `lcs_act` with its `actionId` and the observation's `revision`. The result supplies the next decision, so ordinary play does not need an extra observation call after every action. Use `lcs_input_text` when a source reader requests text.
5. On an unexpected result, call `lcs_capture` with a meaningful name. Preserve the returned paths in the fix report, add a focused regression, then run the existing checks appropriate to the change.
6. Call `lcs_close` to finalize the session and close its owned resources.

Always inspect a rejected or timed-out action before retrying. A timeout can follow an accepted command; it does not mean that command never happened. Required reports, encounters and confirmations remain individual decisions. `lcs_wait` observes progress without answering them.

The MCP can start with a supplied save using `lcs_start({fixture: "path/to/campaign.json"})`. The copy is imported through the original UI into disposable storage. Record that starting condition honestly. Prepared injuries, money or contacts are not outcomes earned during play.

## Tools

| Tool | Purpose |
|---|---|
| `lcs_start` | Own a loopback server and disposable browser; verify the loaded build; optionally import a fixture. |
| `lcs_observe` | Read reader text, pending text entry, input status, blocking reason, current actions and revision. |
| `lcs_inspect` | Read campaign summary, one person or complete saved campaign fields. |
| `lcs_act` | Execute one observed action, rejecting stale, replaced, disabled or blocked choices. |
| `lcs_input_text` | Replay text through the existing source reader and submit with Enter or Escape. |
| `lcs_wait` | Wait at most 30 seconds for an input-ready reader, optionally a changed revision or exact screen. |
| `lcs_capture` | Write a screenshot, observation and inspection beside build metadata and the action trace. |
| `lcs_close` | Close only this session's browser/server and retain its report. |

For a custom build, pass `webRoot` and optionally `expectedHash` to `lcs_start`. The supplied build must have `LCS_DEVTOOLS=true`; ordinary distributed players do not expose the bridge. `headed: true` shows the owned browser for observation. `browser` chooses `msedge` or `chrome`; `browserExecutable` can identify an installed Chromium executable. No player browser profile is reused.

## Evidence and boundaries

Session evidence is retained under ignored `reports/` or `.local/`. It includes the loaded JavaScript hash, bridge build identity, requests, results, elapsed times, rejected actions and browser errors. Named captures provide screenshots and structured state for bug reports. Keep failures as well as successes. Old captures describe their recorded build, not the current checkout.

The bridge reads without making gameplay rolls, advancing time or answering pending input. Actions retain their original object identity and revision. Modal inspection, presentation drafts and busy input boundaries prevent underlying commands. Text entry uses the same editor replay as the visible game. There are no arbitrary JavaScript, raw key, money-setting or state-editing tools.

Complete campaign inspection contains saved fields, not every tactical runtime value or an RNG checkpoint. Action traces help explain and reproduce a path, but do not promise identical stochastic outcomes after reloading. Use deterministic engine tests for exact rule regressions and explicit fixtures for rare branches.

Structured gameplay control does not certify graphical layout, keyboard focus, scrolling, pointer navigation or native Windows behavior. Continue using the [shared acceptance journey](TESTING.md#shared-acceptance-journey) and affected browser checks. Existing fixed tests remain faster and more repeatable for known assertions; the MCP helps investigate new questions and produces evidence for turning them into regressions.

## Verification

```powershell
python -m unittest discover -s scripts -p test_prepare_dev_mcp.py -v
npm test --prefix upstream/tool/dev_mcp
node scripts/dev_mcp/smoke.mjs
Push-Location upstream
..\.tools\flutter\bin\flutter.bat test --no-pub test/development_bridge_test.dart
..\.tools\flutter\bin\flutter.bat test --no-pub --dart-define=LCS_DEVTOOLS=true test/development_bridge_test.dart
Pop-Location
```

The MCP package tests exercise the real stdio protocol in addition to session contracts. The Dart bridge regressions cover read-only state/RNG, current-action identity, stale readers and input boundaries. Run both default-disabled and explicitly enabled configurations: the enabled run exercises actual shell/modal/text integration. CI requires the enabled run on Linux and Windows as well as the normal regression shards. Use the pinned SDK and fully restart after engine changes.

The smoke journey talks to the shipped stdio executable and the compiled player. It creates a fresh founder through all ten original background decisions, submits the public name, verifies inspection purity, rejects a stale action, advances an actual day and checks save/continue. It records the original first-load lazy NPC normalization separately, then requires complete campaign equality on the next save/continue. No starting campaign or earned outcome is supplied. Its `smoke.json` retains call timings, checks and build identity; these are measurements of that run, not a general speedup claim.
