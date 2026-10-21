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

function fakeBrowser({ frames, download } = {}) {
  let current = 0, roll = 17;
  const page = new EventEmitter();
  const observation = () => ({ bridgeVersion: 1, build: { source: 'test' }, revision: current,
    screen: 'headquarters', awaitingInput: true, blockedReason: null,
    actions: [{ id: `${current}:0`, key: 'D', label: 'Advance day', enabled: true }],
    ...frames?.[Math.min(current, frames.length - 1)] });
  page.setDefaultTimeout = () => {};
  page.waitForFunction = async () => {};
  page.goto = async url => page.emit('response', { url: () => `${url}main.dart.js`, body: async () => Buffer.from('test compiled bytes') });
  page.screenshot = async ({ path }) => writeFile(path, 'test screenshot');
  page.waitForEvent = event => new Promise(resolve => page.once(event, resolve));
  page.evaluate = async (_, { request }) => {
    let result;
    if (request.method === 'observe') result = observation();
    else if (request.method === 'inspect') result = { date: current, funds: 100, roll };
    else if (request.params.revision !== current || request.params.actionId !== `${current}:0`) {
      return JSON.stringify({ ok: false, error: { code: 'stale_revision', message: 'Observe again.' }, observation: observation() });
    } else { current++; roll++; result = { accepted: true }; if (download) page.emit('download', download); }
    return JSON.stringify({ ok: true, result });
  };
  const context = { newPage: async () => page, close: async () => { context.closed = true; } };
  const browser = { newContext: async options => { browser.options = options; return context; }, close: async () => { browser.closed = true; } };
  return { browser, context, observation, invalidate: () => current++ };
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
  assert.deepEqual(await session.observe(), { ...started.observation, downloads: [], downloadErrors: [] });
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

test('native downloads retain exact bytes, hashes and safe unique paths after close', async t => {
  const root = await fixture(t), bytes = Buffer.from('{"original":"export bytes"}\n');
  const fake = fakeBrowser({ download: {
    suggestedFilename: () => '../../campaign.json',
    saveAs: async path => { await new Promise(resolve => setTimeout(resolve, 15)); await writeFile(path, bytes); },
  } });
  const session = t.session = new DevelopmentSession({ root, launchBrowser: async () => fake.browser });
  await session.start({ webRoot: 'web', output: 'reports/download' });
  const first = await session.command('act', { revision: 0, actionId: '0:0', expectDownload: true });
  const second = await session.command('act', { revision: 1, actionId: '1:0', expectDownload: true });
  assert.equal(first.downloads.length, 1);
  assert.equal(first.downloads[0].bytes, bytes.length);
  assert.equal(first.downloads[0].sha256, createHash('sha256').update(bytes).digest('hex'));
  assert.notEqual(first.downloads[0].path, second.downloads[0].path);
  assert.ok(first.downloads[0].path.startsWith(resolve(root, 'reports/download/downloads')));
  assert.equal((await session.observe()).downloads.length, 2);
  const closed = await session.close();
  assert.equal(closed.downloads.length, 2);
  assert.deepEqual(await readFile(first.downloads[0].path), bytes);
});

test('download failure is reported after accepted action without a retry', async t => {
  const root = await fixture(t);
  const fake = fakeBrowser({ download: { suggestedFilename: () => 'failed.json', saveAs: async () => { throw Error('download cancelled'); } } });
  const session = t.session = new DevelopmentSession({ root, launchBrowser: async () => fake.browser });
  await session.start({ webRoot: 'web', output: 'reports/download-failure' });
  await assert.rejects(session.command('act', { revision: 0, actionId: '0:0', expectDownload: true }), error => error.code === 'download_failed');
  assert.equal((await session.observe()).revision, 1);
  assert.match((await session.observe()).downloadErrors[0].message, /cancelled/);
  await session.close();
  assert.equal(JSON.parse(await readFile(resolve(root, 'reports/download-failure/session.json'))).hasErrors, true);
});

const ack = current => ({ actions: [{ id: `${current}:0`, kind: 'acknowledgement', enabled: true, label: 'Continue' }], report: `Report ${current}` });

test('report helper retains every acknowledgement and stops before a real choice', async t => {
  const root = await fixture(t), fake = fakeBrowser({ frames: [ack(0), ack(1), { report: null }] });
  const session = t.session = new DevelopmentSession({ root, launchBrowser: async () => fake.browser });
  await session.start({ webRoot: 'web', output: 'reports/reports' });
  const result = await session.continueReports({ revision: 0, actionId: '0:0' });
  assert.equal(result.completedReports, 2);
  assert.equal(result.stopReason, 'decision');
  assert.equal(result.observation.revision, 2);
  for (const [index, report] of result.reports.entries()) {
    const snapshot = JSON.parse(await readFile(report.snapshot));
    assert.equal(snapshot.observation.report, `Report ${index}`);
    assert.equal(await readFile(report.screenshot, 'utf8'), 'test screenshot');
  }
});

test('report helper respects count/time limits, blocked/text readers and source Enter choices', async t => {
  const variants = [
    { frames: [ack(0), ack(1)], params: { maxReports: 1 }, reason: 'limit', count: 1 },
    { frames: [{ ...ack(0), textInput: { value: '' } }], reason: 'text_input', count: 0 },
    { frames: [{ ...ack(0), blockedReason: 'modal' }], reason: 'blocked', count: 0 },
    { frames: [{ actions: [{ id: '0:0', enabled: true, kind: 'source_action', key: 'Enter', label: 'Continue' }] }], reason: 'decision', count: 0 },
    { frames: [{ actions: [...ack(0).actions, { id: 'real-choice', enabled: false, kind: 'source_action' }] }], reason: 'decision', count: 0 },
    { frames: [ack(0)], params: { timeoutMs: 1 }, delayCapture: true, reason: 'timeout', count: 0 },
  ];
  for (const [index, variant] of variants.entries()) {
    const root = await fixture(t), fake = fakeBrowser({ frames: variant.frames });
    const session = new DevelopmentSession({ root, launchBrowser: async () => fake.browser });
    t.after(() => session.close());
    await session.start({ webRoot: 'web', output: `reports/limits-${index}` });
    if (variant.delayCapture) session._capture = async () => { await new Promise(resolve => setTimeout(resolve, 10)); return {}; };
    const result = await session.continueReports({ revision: 0, actionId: '0:0', ...variant.params });
    assert.equal(result.stopReason, variant.reason);
    assert.equal(result.completedReports, variant.count);
    assert.equal(result.observation.revision, variant.count);
    await session.close();
  }
});

test('report batches return readable article, legislation and buffer fallback text', async t => {
  const root = await fixture(t);
  const fake = fakeBrowser({ frames: [
    { ...ack(0), screen: 'article', report: '', text: 'Bitmap headline glyphs', reportContext: { kind: 'article', title: 'The actual headline', text: 'The actual headline\nComplete article body.' } },
    { ...ack(1), screen: 'generic', report: '', reportContext: { kind: 'legislation', title: 'Legislation 2023', text: 'Flag Burning: decision pending.' } },
    { ...ack(2), screen: 'generic', report: '   ', text: 'Original report buffer fallback.' },
    { report: null },
  ] });
  const session = t.session = new DevelopmentSession({ root, launchBrowser: async () => fake.browser });
  await session.start({ webRoot: 'web', output: 'reports/readable-batches' });
  const result = await session.continueReports({ revision: 0, actionId: '0:0' });
  assert.equal(result.stopReason, 'decision');
  assert.equal(result.completedReports, 3);
  assert.deepEqual(result.reports.map(report => [report.screen, report.kind, report.title, report.report]), [
    ['article', 'article', 'The actual headline', 'The actual headline\nComplete article body.'],
    ['generic', 'legislation', 'Legislation 2023', 'Flag Burning: decision pending.'],
    ['generic', 'source_report', null, 'Original report buffer fallback.'],
  ]);
  const retained = JSON.parse(await readFile(result.reports[0].snapshot, 'utf8'));
  assert.equal(retained.observation.reportContext.text, result.reports[0].report);
});

test('report helper rejects stale capabilities before and during continuation without retry', async t => {
  const root = await fixture(t), fake = fakeBrowser({ frames: [ack(0), ack(1)] });
  const session = t.session = new DevelopmentSession({ root, launchBrowser: async () => fake.browser });
  await session.start({ webRoot: 'web', output: 'reports/stale-report' });
  await assert.rejects(session.continueReports({ revision: 9, actionId: '0:0' }), error => error.code === 'stale_action');
  const capture = session._capture.bind(session);
  session._capture = async params => { const result = await capture(params); fake.invalidate(); return result; };
  await assert.rejects(session.continueReports({ revision: 0, actionId: '0:0' }), error => error.code === 'stale_revision' && error.progress.completedReports === 0);
  assert.equal((await session.observe()).revision, 1, 'Only the simulated source replacement occurred.');
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
