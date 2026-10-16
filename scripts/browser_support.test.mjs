import assert from 'node:assert/strict';
import test from 'node:test';
import { QA_URL, assertQaUrl, chromiumLaunchOptions } from './browser_support.mjs';

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
