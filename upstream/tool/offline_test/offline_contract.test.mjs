import assert from 'node:assert/strict';
import test from 'node:test';
import { runInNewContext } from 'node:vm';
import { inspectPrecache, parseOfflineManifest } from './offline_contract.mjs';

const resources = { 'index.html': '123', 'main.dart.js': 'abc', 'assets/portrait 01.webp': 'def' };
const worker = (map = resources, version = '1234abcd') =>
  `const RESOURCES = ${JSON.stringify(map)};\nconst VERSION = '${version}';\nthrow new Error('Do not execute worker source');`;

function scenario(scope = 'http://127.0.0.1:18879/lcs-new-age/') {
  const manifest = parseOfflineManifest(worker());
  const name = `lcs-new-age-${manifest.version}`;
  const entries = new Map(Object.keys(manifest.resources).map(path => [new URL(path, scope).href, new Response(path)]));
  const manifestUrl = new URL('__lcs-manifest__', scope).href;
  entries.set(manifestUrl, new Response(JSON.stringify(manifest.resources)));
  const caches = new Map([[name, entries]]), opened = [];
  const storage = {
    keys: async () => [...caches.keys()],
    open: async name => {
      opened.push(name);
      assert.ok(caches.has(name), 'Inspection must not create missing caches.');
      return { match: async url => caches.get(name).get(url)?.clone() };
    },
  };
  return { expected: { ...manifest, scope }, name, entries, caches, opened, storage, manifestUrl };
}

test('reads injected constants as JSON without executing the worker', () => {
  assert.deepEqual(parseOfflineManifest(worker()), { version: '1234abcd', resources });
  assert.deepEqual(parseOfflineManifest(worker().replaceAll('\n', '\r\n')), { version: '1234abcd', resources });
});

test('unfilled, malformed and incomplete injected manifests fail preflight', () => {
  for (const source of [
    'const RESOURCES = null; // build: manifest\nconst VERSION = \'dev\'; // build: version',
    'const RESOURCES = {broken};\nconst VERSION = \'1234abcd\';',
    worker(resources, 'dev'), worker({}), worker([]), worker(null),
    worker({ 'index.html': '123' }), worker({ ...resources, 'main.dart.js': 123 }),
    worker({ ...resources, 'main.dart.js': 'not-a-checksum' }),
  ]) assert.throws(() => parseOfflineManifest(source), /RESOURCES|VERSION/);
});

test('complete current cache is verified at root and hosted base paths, including encoded asset names', async () => {
  for (const scope of ['http://127.0.0.1:18879/', 'http://127.0.0.1:18879/project%20name/']) {
    const fixture = scenario(scope);
    fixture.entries.set(new URL('runtime-extra.bin', scope).href, new Response('Allowed runtime entry'));
    const result = await inspectPrecache(fixture.expected, fixture.storage);
    assert.equal(result.name, fixture.name);
    assert.equal(result.scope, scope);
    assert.equal(result.count, Object.keys(resources).length);
    assert.deepEqual(fixture.opened, [fixture.name]);
  }
});

test('a complete stale-version cache cannot satisfy the current worker contract', async () => {
  const fixture = scenario();
  fixture.caches.set('lcs-new-age-deadbeef', fixture.entries);
  fixture.caches.delete(fixture.name);
  await assert.rejects(inspectPrecache(fixture.expected, fixture.storage), /Current precache is missing: lcs-new-age-1234abcd/);
  assert.deepEqual(fixture.opened, []);
});

test('many entries and main.dart.js in other caches cannot hide a missing current resource', async () => {
  const fixture = scenario();
  fixture.entries.delete(new URL('assets/portrait 01.webp', fixture.expected.scope).href);
  const unrelated = new Map(Array.from({ length: 20 }, (_, index) => [`http://other.test/asset-${index}`, new Response('old')]));
  unrelated.set('http://other.test/main.dart.js', new Response('old game'));
  fixture.caches.set('unrelated-cache', unrelated);
  const oldAggregate = [...fixture.caches.values()].flatMap(cache => [...cache.keys()]);
  assert.ok(oldAggregate.length >= 20 && oldAggregate.some(url => url.endsWith('main.dart.js')));
  await assert.rejects(inspectPrecache(fixture.expected, fixture.storage), /portrait%2001\.webp \(missing\)/);
  assert.deepEqual(fixture.opened, [fixture.name]);
});

test('resource entries must match each exact scoped URL', async () => {
  const fixture = scenario();
  for (const path of Object.keys(resources)) {
    fixture.entries.delete(new URL(path, fixture.expected.scope).href);
    fixture.entries.set(new URL(path, 'http://127.0.0.1:18879/').href, new Response('Wrong scope'));
  }
  await assert.rejects(inspectPrecache(fixture.expected, fixture.storage), /lcs-new-age\/main\.dart\.js \(missing\)/);
});

test('stored manifest must contain exactly the injected paths and checksum values', async () => {
  for (const map of [
    { ...resources, 'main.dart.js': '999' },
    { 'index.html': '123', 'main.dart.js': 'abc' },
    { ...resources, 'extra.bin': '123' },
    null, [],
  ]) {
    const fixture = scenario();
    fixture.entries.set(fixture.manifestUrl, new Response(JSON.stringify(map)));
    await assert.rejects(inspectPrecache(fixture.expected, fixture.storage), /manifest differs from injected RESOURCES/);
  }
  const fixture = scenario();
  fixture.entries.set(fixture.manifestUrl, new Response('not JSON'));
  await assert.rejects(inspectPrecache(fixture.expected, fixture.storage), /unreadable manifest/);
  fixture.entries.delete(fixture.manifestUrl);
  await assert.rejects(inspectPrecache(fixture.expected, fixture.storage), /no successful scoped manifest/);
});

test('non-OK cached responses cannot establish a complete precache', async () => {
  const fixture = scenario();
  fixture.entries.set(new URL('main.dart.js', fixture.expected.scope).href, new Response('failed', { status: 503 }));
  await assert.rejects(inspectPrecache(fixture.expected, fixture.storage), /main\.dart\.js \(HTTP 503\)/);
  fixture.entries.set(fixture.manifestUrl, new Response('failed', { status: 503 }));
  await assert.rejects(inspectPrecache(fixture.expected, fixture.storage), /no successful scoped manifest/);
});

test('manifest URLs cannot escape or alias the worker scope', async () => {
  for (const path of ['../private.txt', './main.dart.js', 'https://other.test/main.dart.js', 'main.dart.js?query=1']) {
    const fixture = scenario();
    fixture.expected.resources = { ...resources, [path]: '123' };
    await assert.rejects(inspectPrecache(fixture.expected, fixture.storage), /not a relative URL within the worker scope/);
    assert.deepEqual(fixture.opened, []);
  }
});

test('cache inspection runs with only browser globals after serialization', async () => {
  const fixture = scenario();
  const inBrowser = runInNewContext(`(${inspectPrecache.toString()})`, { caches: fixture.storage, URL });
  const result = await inBrowser(fixture.expected);
  assert.equal(result.name, fixture.name);
  assert.equal(result.count, Object.keys(resources).length);
});
