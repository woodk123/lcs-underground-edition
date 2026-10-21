// MCP stdout belongs exclusively to the protocol. Diagnostics go to evidence.
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { DevelopmentSession, ROOT } from './session.mjs';

export const dependencyRequire = createRequire(resolve(ROOT, 'upstream/tool/dev_mcp/package.json'));
const { McpServer } = dependencyRequire('@modelcontextprotocol/server');
const { z } = dependencyRequire('zod');

const revision = z.number().int().nonnegative();
const timeoutMs = z.number().int().min(0).max(30000).default(10000);
const annotations = readOnlyHint => ({ readOnlyHint, destructiveHint: false, idempotentHint: readOnlyHint, openWorldHint: false });

export function createDevelopmentServer(session = new DevelopmentSession()) {
  const server = new McpServer({ name: 'lcs-development', version: '1.0.0' }, {
    instructions: 'Development/testing only. Start an isolated session from a prepared LCS_DEVTOOLS build. Observe before choosing source action IDs; pass the observed revision. Never retry a failed/timed-out mutation blindly. Inspect is read-only. Imported fixtures are prepared conditions, not earned outcomes. Capture evidence for bugs. This interface tests gameplay; use browser/UI tests for layout/focus. Close the session when finished.',
  });
  function tool(name, description, schema, readOnly, operation) {
    server.registerTool(name, { description, inputSchema: schema, annotations: annotations(readOnly) }, async params => {
      try {
        const result = await operation(params);
        return { content: [{ type: 'text', text: JSON.stringify(result) }], structuredContent: result };
      } catch (error) {
        const result = { error: { code: error.code ?? 'session_error', message: error.message },
          ...(error.observation ? { observation: error.observation } : {}),
          ...(session.output ? { evidenceDirectory: session.output } : {}) };
        return { content: [{ type: 'text', text: JSON.stringify(result) }], structuredContent: result, isError: true };
      }
    });
  }
  tool('lcs_start', 'Start an owned loopback server and fresh disposable browser. Default build: python scripts/prepare_dev_mcp.py. Verifies the actual loaded JavaScript hash and bridge; never attaches player profiles. Optional fixture imports a copied save through the real UI.', z.object({
    webRoot: z.string().default('.local/dev-mcp/web'), expectedHash: z.string().regex(/^[a-fA-F0-9]{64}$/).optional(),
    output: z.string().optional(), fixture: z.string().optional(), browser: z.enum(['msedge', 'chrome']).default('msedge'),
    browserExecutable: z.string().optional(), headed: z.boolean().default(false),
    width: z.number().int().min(390).max(3840).default(1440), height: z.number().int().min(400).max(2160).default(1000),
  }).strict(), false, params => session.start(params));
  tool('lcs_observe', 'Read the current source reader, input status, exact current actions and revision without consuming input or RNG.', z.object({}).strict(), true, () => session.observe());
  tool('lcs_inspect', 'Read campaign summary, a person or complete campaign data without making game rolls. Full campaign scope can be large; prefer summary/person while playing.', z.object({
    scope: z.enum(['summary', 'person', 'campaign']).default('summary'), personId: z.number().int().optional(),
  }).strict(), true, params => session.inspect(params));
  tool('lcs_act', 'Execute one currently authored source action using its exact ID and observed revision. Rejects stale/disabled/blocked actions. Returns the next input-ready observation and records a trace.', z.object({
    revision, actionId: z.string().min(1).max(200),
  }).strict(), false, params => session.command('act', params));
  tool('lcs_input_text', 'Submit a source text reader using the observed revision, native text replay and Enter/Escape. Escape preserves the original source cancellation meaning.', z.object({
    revision, text: z.string().max(10000), submit: z.enum(['Enter', 'Escape']).default('Enter'),
  }).strict(), false, params => session.command('input_text', params));
  tool('lcs_wait', 'Wait up to 30 seconds for an input-ready reader, optionally with a changed revision or exact screen. Timeout returns the last observation; never acknowledges a decision.', z.object({
    afterRevision: revision.optional(), screen: z.string().optional(), timeoutMs,
  }).strict(), true, params => session.wait(params));
  tool('lcs_capture', 'Save screenshot, build identity, observation and inspection JSON beside the action trace. Returns absolute evidence paths. Full campaign inclusion is explicit.', z.object({
    name: z.string().regex(/^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/).default('capture'), includeCampaign: z.boolean().default(false),
  }).strict(), true, params => session.capture(params));
  tool('lcs_close', 'Close this MCP session browser/server and finalize evidence. Does not stop other servers or browsers.', z.object({}).strict(), false, () => session.close());
  return server;
}

export function attachDisconnectCleanup(streams, session, serving) {
  let closing;
  const close = () => closing ??= Promise.resolve().then(() => session.shutdown())
    .finally(() => serving.close());
  // Pipe close/error can happen without stdin end when a host exits abruptly.
  for (const event of ['end', 'close', 'error']) streams.stdin.once(event, () => { void close().catch(error => process.stderr.write(`${error.message}\n`)); });
  streams.stdout.once('error', () => { void close().catch(error => process.stderr.write(`${error.message}\n`)); });
  return close;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const session = new DevelopmentSession();
  const { serveStdio } = dependencyRequire('@modelcontextprotocol/server/stdio');
  const serving = serveStdio(() => createDevelopmentServer(session));
  const close = attachDisconnectCleanup(process, session, serving);
  for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, async () => { await close(); process.exit(0); });
}
