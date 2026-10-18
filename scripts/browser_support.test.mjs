import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { EventEmitter } from 'node:events';
import test from 'node:test';
import { QA_URL, assertQaUrl, chromiumLaunchOptions, observeMainScript } from './browser_support.mjs';

test('browser journeys accept only the isolated QA origin and root page', () => {
  assert.equal(assertQaUrl(), QA_URL);
  assert.equal(assertQaUrl('http://127.0.0.1:18879/'), QA_URL);
  for (const url of [
    'http://127.0.0.1:8765/', 'http://127.0.0.1:18880/',
    'http://localhost:18879/', 'https://127.0.0.1:18879/',
    'http://127.0.0.1:18879/player/', 'http://127.0.0.1:18879/?player=1',
    'http://player:password@127.0.0.1:18879/',
  ]) assert.throws(() => assertQaUrl(url), /isolated QA server/);
});

test('an explicit installed executable is used without profile or download options', () => {
  assert.deepEqual(chromiumLaunchOptions({ channel: 'chrome', args: ['--browser-executable', process.execPath] }),
    { channel: 'chrome', executablePath: process.execPath, headless: true });
});

test('a missing explicit browser executable fails before a browser is launched', () => {
  assert.throws(() => chromiumLaunchOptions({ args: ['--browser-executable'] }), /requires a path/);
  assert.throws(() => chromiumLaunchOptions({ args: ['--browser-executable', '--url'] }), /requires a path/);
  assert.throws(() => chromiumLaunchOptions({ args: ['--browser-executable', 'no-such-browser-qa.exe'] }), /not found/);
});

test('unsupported browser channels are rejected', () => {
  assert.throws(() => chromiumLaunchOptions({ channel: 'firefox', args: [] }), /installed Microsoft Edge or Chrome/);
});

test('an acceptance runner may select a different dedicated origin while player origins remain forbidden', () => {
  const previous = process.env.LCS_ACCEPTANCE_QA_URL;
  try {
    process.env.LCS_ACCEPTANCE_QA_URL = 'http://127.0.0.1:18889/';
    assert.equal(assertQaUrl('http://127.0.0.1:18889/'), 'http://127.0.0.1:18889/');
    assert.throws(() => assertQaUrl(QA_URL), /isolated QA server/);
    for (const url of ['http://127.0.0.1:8765/', 'http://localhost:18889/',
      'http://127.0.0.1:18889/player/', 'http://127.0.0.1:18889/?player=1',
      'http://player:password@127.0.0.1:18889/']) {
      process.env.LCS_ACCEPTANCE_QA_URL = url;
      assert.throws(() => assertQaUrl(url), /isolated QA server/);
    }
  } finally {
    if (previous === undefined) delete process.env.LCS_ACCEPTANCE_QA_URL;
    else process.env.LCS_ACCEPTANCE_QA_URL = previous;
  }
});

test('acceptance identifies the actual loaded script rather than only a prefetched hash', async () => {
  const page = new EventEmitter(), report = {};
  const verify = observeMainScript(page, report);
  const body = Buffer.from('requested compiled game');
  const expected = createHash('sha256').update(body).digest('hex');
  page.emit('response', { url: () => `${QA_URL}assets/ignored.bin`, body: async () => Buffer.from('asset') });
  page.emit('response', { url: () => `${QA_URL}main.dart.js`, body: async () => body });
  await verify(expected);
  assert.deepEqual(report.loadedMainJsHashes, [expected]);
  await assert.rejects(verify('0'.repeat(64)), /different compiled build/);
});

test('a missing or unreadable browser-loaded script cannot pass acceptance', async () => {
  const page = new EventEmitter(), verify = observeMainScript(page, {});
  await assert.rejects(verify('0'.repeat(64)), /must have loaded/);
  page.emit('response', { url: () => `${QA_URL}main.dart.js`, body: async () => { throw Error('disconnected'); } });
  await assert.rejects(verify('0'.repeat(64)), /actual browser-loaded/);
});
