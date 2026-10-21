import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { EventEmitter } from 'node:events';
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import test from 'node:test';
import { DevelopmentSession, evidenceDirectory, serveBuild } from './session.mjs';

async function fixture(t) {
  const root = await mkdtemp(resolve(tmpdir(), 'lcs-dev-mcp-test-'));
  t.after(async () => { await t.session?.close(); await rm(root, { recursive: true, force: true }); });
  await mkdir(resolve(root, 'web'));
  await writeFile(resolve(root, 'web/index.html'), '<html>Test build</html>');
  await writeFile(resolve(root, 'web/main.dart.js'), 'test compiled bytes');
  return root;
}

function fakeBrowser() {
  let current = 0, roll = 17;
  const page = new EventEmitter();
  const observation = () => ({ bridgeVersion: 1, build: { source: 'test' }, revision: current,
    screen: 'headquarters', awaitingInput: true, blockedReason: null,
    actions: [{ id: `${current}:0`, key: 'D', label: 'Advance day', enabled: true }] });
  page.setDefaultTimeout = () => {};
  page.waitForFunction = async () => {};
  page.goto = async url => page.emit('response', { url: () => `${url}main.dart.js`, body: async () => Buffer.from('test compiled bytes') });
  page.screenshot = async ({ path }) => writeFile(path, 'test screenshot');
  page.evaluate = async (_, { request }) => {
    let result;
    if (request.method === 'observe') result = observation();
    else if (request.method === 'inspect') result = { date: current, funds: 100, roll };
    else if (request.params.revision !== current || request.params.actionId !== `${current}:0`) {
      return JSON.stringify({ ok: false, error: { code: 'stale_revision', message: 'Observe again.' }, observation: observation() });
    } else { current++; roll++; result = { accepted: true }; }
    return JSON.stringify({ ok: true, result });
  };
  const context = { newPage: async () => page, close: async () => { context.closed = true; } };
  const browser = { newContext: async options => { browser.options = options; return context; }, close: async () => { browser.closed = true; } };
  return { browser, context, observation };
}

test('owned static server serves exact bytes and rejects writes, directories and escaping symlinks', async t => {
  const root = await fixture(t), server = await serveBuild(resolve(root, 'web'));
  t.after(server.close);
  assert.equal(await (await fetch(server.url)).text(), '<html>Test build</html>');
  assert.equal((await fetch(`${server.url}main.dart.js?fresh=1`)).headers.get('content-type'), 'text/javascript');
  assert.equal((await fetch(server.url, { method: 'POST' })).status, 405);
  assert.equal((await fetch(`${server.url}missing/`)).status, 404);
  await writeFile(resolve(root, 'private.txt'), 'not served');
  // Windows directory junctions do not require developer-mode symlink privileges.
  await symlink(root, resolve(root, 'web/escape'), 'junction');
  assert.equal((await fetch(`${server.url}escape/private.txt`)).status, 404);
  assert.equal((await (await fetch(`${server.url}__lcs_launcher_health`)).json()).application, 'lcs-dev-mcp');
});

test('evidence paths reject traversal, existing output and symlink escape before writing', async t => {
  const root = await fixture(t);
  await assert.rejects(evidenceDirectory(root, '../outside'), /reports/);
  await assert.rejects(evidenceDirectory(root, 'upstream/capture'), /reports/);
  await evidenceDirectory(root, 'reports/nested/run');
  await assert.rejects(evidenceDirectory(root, 'reports/nested/run'), /EEXIST/);
  await symlink(tmpdir(), resolve(root, 'reports/escape'), 'junction');
  await assert.rejects(evidenceDirectory(root, 'reports/escape/not-created'), /escapes/);
  await symlink(resolve(root, 'web'), resolve(root, 'reports/tracked'), 'junction');
  await assert.rejects(evidenceDirectory(root, 'reports/tracked/not-created'), /symlink/);
});

test('session identifies actual loaded build, preserves inspection, serializes mutations and retains stale evidence', async t => {
  const root = await fixture(t), fake = fakeBrowser();
  const session = new DevelopmentSession({ root, launchBrowser: async () => fake.browser });
  t.session = session;
  const started = await session.start({ webRoot: 'web', output: 'reports/session' });
  assert.equal(started.mainJsSha256, createHash('sha256').update('test compiled bytes').digest('hex'));
  assert.equal(fake.browser.options.serviceWorkers, 'block');
  const before = await session.inspect({ scope: 'campaign' });
  assert.deepEqual(await session.observe(), started.observation);
  assert.deepEqual(await session.inspect({ scope: 'campaign' }), before);
  const command = { revision: 0, actionId: '0:0' };
  const results = await Promise.allSettled([session.command('act', command), session.command('act', command)]);
  assert.equal(results[0].status, 'fulfilled');
  assert.equal(results[0].value.observation.revision, 1);
  assert.equal(results[1].status, 'rejected');
  assert.equal(results[1].reason.code, 'stale_revision');
  const trace = (await readFile(resolve(started.evidenceDirectory, 'trace.jsonl'), 'utf8')).trim().split('\n').map(JSON.parse);
  assert.equal(trace.filter(event => event.operation === 'act' && !event.error).length, 1);
  assert.equal(trace.at(-1).error.code, 'stale_revision');
  const capture = await session.capture({ name: 'after', includeCampaign: true });
  assert.equal(JSON.parse(await readFile(capture.snapshot, 'utf8')).observation.revision, 1);
  await assert.rejects(session.capture({ name: '../escape' }), /path characters/);
  await assert.rejects(session.wait({ afterRevision: 1, timeoutMs: 0 }), error => error.code === 'wait_timeout' && error.observation.revision === 1);
  await session.close();
  assert.ok(fake.browser.closed && fake.context.closed);
  await session.shutdown();
  assert.equal(JSON.parse(await readFile(resolve(started.evidenceDirectory, 'session.json'), 'utf8')).status, 'closed');
});

test('wrong expected build fails before browser launch and startup failure closes owned server', async t => {
  const root = await fixture(t); let launches = 0;
  const session = new DevelopmentSession({ root, launchBrowser: async () => { launches++; throw Error('Browser unavailable'); } });
  await assert.rejects(session.start({ webRoot: 'web', expectedHash: '0'.repeat(64) }), /does not match/);
  assert.equal(launches, 0);
  await assert.rejects(session.start({ webRoot: 'web', output: 'reports/failure' }), /Browser unavailable/);
  assert.equal(session.server, undefined);
  assert.equal(JSON.parse(await readFile(resolve(root, 'reports/failure/session.json'), 'utf8')).status, 'failed');
});

test('cached default build must pass current-source validation before browser launch', async t => {
  const root = await fixture(t); let launches = 0, checks = 0;
  await mkdir(resolve(root, '.local/dev-mcp/web'), { recursive: true });
  await writeFile(resolve(root, '.local/dev-mcp/web/index.html'), '<html>Old build</html>');
  await writeFile(resolve(root, '.local/dev-mcp/web/main.dart.js'), 'old compiled bytes');
  const session = new DevelopmentSession({ root,
    launchBrowser: async () => { launches++; throw Error('Should not launch'); },
    validatePrepared: async () => { checks++; throw Error('Source changed. Run prepare_dev_mcp.py.'); },
  });
  await assert.rejects(session.start({}), /Source changed/);
  assert.equal(checks, 1); assert.equal(launches, 0);
});

test('a root path alias cannot bypass cached default source validation', async t => {
  const root = await fixture(t); let launches = 0, checks = 0;
  await mkdir(resolve(root, '.local/dev-mcp/web'), { recursive: true });
  await writeFile(resolve(root, '.local/dev-mcp/web/index.html'), '<html>Old build</html>');
  await writeFile(resolve(root, '.local/dev-mcp/web/main.dart.js'), 'old compiled bytes');
  const alias = resolve(root, 'root-alias');
  await symlink(root, alias, 'junction');
  const session = new DevelopmentSession({ root: alias,
    launchBrowser: async () => { launches++; throw Error('Should not launch'); },
    validatePrepared: async () => { checks++; throw Error('Source changed. Run prepare_dev_mcp.py.'); },
  });
  await assert.rejects(session.start({}), /Source changed/);
  assert.equal(checks, 1); assert.equal(launches, 0);
});
