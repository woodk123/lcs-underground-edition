import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { EventEmitter } from 'node:events';
import test from 'node:test';
import { attachDisconnectCleanup, createDevelopmentServer, dependencyRequire } from './server.mjs';
import { ROOT } from './session.mjs';

const { createMcpHandler } = dependencyRequire('@modelcontextprotocol/server');
const { Client, StreamableHTTPClientTransport } = dependencyRequire('@modelcontextprotocol/client');
const { StdioClientTransport } = dependencyRequire('@modelcontextprotocol/client/stdio');

test('real MCP transport discovers schemas, applies defaults, routes commands and reports stale failures', async t => {
  const calls = [];
  const session = {
    start: async params => { calls.push(['start', params]); return { observation: { revision: 3 } }; },
    observe: async () => ({ revision: 3, actions: [] }), inspect: async params => { calls.push(['inspect', params]); return { funds: 25 }; },
    command: async (method, params) => { calls.push([method, params]); const error = Error('Observe again.'); error.code = 'stale_revision'; error.observation = { revision: 4 }; throw error; },
    wait: async () => ({ revision: 4 }), capture: async () => ({ screenshot: '/capture.png' }), close: async () => ({ status: 'closed' }),
    continueReports: async params => { calls.push(['continue_reports', params]); return { completedReports: 2, stopReason: 'decision' }; },
  };
  const handler = createMcpHandler(() => createDevelopmentServer(session));
  const transport = new StreamableHTTPClientTransport(new URL('http://test.local/mcp'), { fetch: (url, init) => handler.fetch(new Request(url, init)) });
  const client = new Client({ name: 'lcs-contract-test', version: '1.0.0' }, { versionNegotiation: { mode: 'auto' } });
  await client.connect(transport); t.after(() => client.close());
  const tools = await client.listTools();
  assert.equal(tools.tools.length, 9);
  assert.equal(tools.tools.find(tool => tool.name === 'lcs_inspect').annotations.readOnlyHint, true);
  assert.equal(tools.tools.find(tool => tool.name === 'lcs_act').annotations.readOnlyHint, false);
  assert.equal((await client.callTool({ name: 'lcs_start', arguments: {} })).structuredContent.observation.revision, 3);
  assert.equal(calls[0][1].webRoot, '.local/dev-mcp/web');
  assert.equal((await client.callTool({ name: 'lcs_inspect', arguments: {} })).structuredContent.funds, 25);
  assert.equal(calls.at(-1)[1].scope, 'summary');
  assert.equal((await client.callTool({ name: 'lcs_inspect', arguments: { scope: 'context' } })).isError, undefined);
  assert.equal((await client.callTool({ name: 'lcs_continue_reports', arguments: { revision: 3, actionId: '3:0' } })).structuredContent.completedReports, 2);
  assert.equal(calls.at(-1)[1].maxReports, 20);
  const stale = await client.callTool({ name: 'lcs_act', arguments: { revision: 3, actionId: '3:0' } });
  assert.ok(stale.isError);
  assert.equal(stale.structuredContent.error.code, 'stale_revision');
  assert.equal(stale.structuredContent.observation.revision, 4);
  const count = calls.length;
  assert.ok((await client.callTool({ name: 'lcs_act', arguments: { revision: -1, actionId: '3:0' } })).isError);
  assert.ok((await client.callTool({ name: 'lcs_capture', arguments: { name: '../escape' } })).isError);
  assert.ok((await client.callTool({ name: 'lcs_continue_reports', arguments: { revision: 3, actionId: '3:0', maxReports: 101 } })).isError);
  assert.equal(calls.length, count, 'Invalid schemas cannot reach a mutation.');
});

test('shipped stdio executable initializes with clean protocol output and shuts down without a session', async t => {
  const transport = new StdioClientTransport({ command: process.execPath, args: [resolve(ROOT, 'scripts/dev_mcp/server.mjs')], stderr: 'pipe' });
  let stderr = '';
  transport.stderr?.on('data', bytes => { stderr += bytes; });
  const client = new Client({ name: 'lcs-stdio-test', version: '1.0.0' }, { versionNegotiation: { mode: 'auto' } });
  await client.connect(transport); t.after(() => client.close());
  assert.equal((await client.listTools()).tools.length, 9);
  const result = await client.callTool({ name: 'lcs_observe', arguments: {} });
  assert.ok(result.isError);
  assert.match(result.structuredContent.error.message, /Start a development session/);
  assert.deepEqual((await client.callTool({ name: 'lcs_close', arguments: {} })).structuredContent.cleanupErrors, []);
  assert.equal(stderr, '');
});

test('abrupt host pipe close releases an active session exactly once', async () => {
  const streams = { stdin: new EventEmitter(), stdout: new EventEmitter() };
  let sessions = 0, transports = 0;
  const closed = attachDisconnectCleanup(streams, { shutdown: async () => { sessions++; } }, { close: async () => { transports++; } });
  streams.stdin.emit('close'); streams.stdin.emit('end'); streams.stdout.emit('error', Error('EPIPE'));
  await closed();
  assert.equal(sessions, 1); assert.equal(transports, 1);
});
