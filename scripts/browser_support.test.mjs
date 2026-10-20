import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { EventEmitter } from 'node:events';
import test from 'node:test';
import { runInNewContext } from 'node:vm';
import { QA_URL, assertQaUrl, chromiumLaunchOptions, observeMainScript,
  waitForSemantics, waitForUiSettled } from './browser_support.mjs';

test('reader waits reject stale/missing readers and observe labels and editable values', async () => {
  let host = null, disposed = false;
  const document = { querySelector: () => host };
  const page = {
    async waitForFunction(predicate, argument, options) {
      assert.equal(options.polling, 'raf');
      const matches = () => runInNewContext(`(${predicate})(${JSON.stringify(argument)})`, { document });
      assert.equal(matches(), false, 'A missing or stale reader must not satisfy the wait.');
      host = { innerText: 'New reader', querySelectorAll: selector => selector === '[aria-label]'
        ? [{ getAttribute: () => 'Confirm assignment' }] : [{ value: 'Typed founder' }] };
      assert.equal(matches(), true);
      return { dispose: async () => { disposed = true; } };
    },
  };
  await waitForSemantics(page, /confirm assignment.*typed founder/is);
  assert.ok(disposed);
  host.innerText = 'Old reader';
  await waitForSemantics(page, 'New reader\nConfirm assignment\nTyped founder');
});

test('layout waits restart observation when semantics change between rendered frames', async () => {
  const snapshots = ['old', 'old', 'new', 'new', 'new', 'new'];
  let frames = 0;
  const page = { evaluate: callback => runInNewContext(`(${callback})()`, {
    document: { querySelector: () => ({ outerHTML: snapshots[Math.min(frames++ , snapshots.length - 1)] }) },
    requestAnimationFrame: callback => setImmediate(callback), cancelAnimationFrame: clearImmediate,
    setTimeout, clearTimeout,
  }) };
  await waitForUiSettled(page);
  assert.ok(frames >= snapshots.length, 'Changing layout must restart the stable-frame count.');
});

test('a reader that never appears fails its bounded layout wait', async () => {
  const page = { evaluate: callback => runInNewContext(`(${callback})()`, {
    document: { querySelector: () => null },
    requestAnimationFrame: () => 1, cancelAnimationFrame: () => {},
    setTimeout: callback => setImmediate(callback), clearTimeout: clearImmediate,
  }) };
  await assert.rejects(waitForUiSettled(page), /did not settle/);
});

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
