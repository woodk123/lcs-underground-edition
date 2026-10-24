import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { runInNewContext } from 'node:vm';

const source = await readFile(new URL('../../web/sw.js', import.meta.url), 'utf8');
const scope = 'http://127.0.0.1:18879/game/';
const resources = { 'index.html': '1', 'assets/flags.xml': '2' };
const manifestUrl = new URL('__lcs-manifest__', scope).href;

function worker({ fetchResource, previous, putFailure } = {}) {
  const listeners = new Map(), entries = new Map(), calls = [], delays = [], errors = [];
  const cache = {
    match: async url => entries.get(url)?.clone(),
    put: async (url, response) => {
      if (putFailure && url !== manifestUrl) throw putFailure;
      // Consume the real Response, as CacheStorage does before resolving put.
      entries.set(url, new Response(await response.arrayBuffer(), {
        status: response.status, headers: response.headers,
      }));
    },
  };
  const previousEntries = new Map(Object.entries(previous ?? {}).map(([path, hash]) =>
    [new URL(path, scope).href, new Response(`old ${hash}`)]));
  previousEntries.set(manifestUrl, new Response(JSON.stringify(previous ?? {})));
  runInNewContext(source.replace('const RESOURCES = null; // build: manifest',
    `const RESOURCES = ${JSON.stringify(resources)};`), {
    self: { registration: { scope }, addEventListener: (name, listener) => listeners.set(name, listener) },
    caches: {
      keys: async () => previous ? ['lcs-new-age-old'] : [],
      open: async name => name === 'lcs-new-age-old'
        ? { match: async url => previousEntries.get(url)?.clone() } : cache,
    },
    fetch: async (url, options) => {
      calls.push({ url, cache: options.cache });
      return fetchResource ? fetchResource(url) : new Response('new content');
    },
    setTimeout: (callback, delay) => { delays.push(delay); queueMicrotask(callback); },
    console: { error: (...args) => errors.push(args), warn: (...args) => errors.push(args) },
    URL, Response,
  });
  return { entries, calls, delays, errors, install() {
    let completion;
    listeners.get('install')({ waitUntil: promise => { completion = promise; } });
    return completion;
  } };
}

test('precache recovers two rejected transfers and writes its manifest only after every resource succeeds', async () => {
  let failures = 2;
  const scenario = worker({ fetchResource: url => {
    if (url.endsWith('/flags.xml') && failures-- > 0) throw new TypeError('Failed to fetch');
    return new Response(url.endsWith('/flags.xml') ? '<flags/>' : 'title');
  } });
  await scenario.install();
  assert.equal(scenario.calls.filter(call => call.url.endsWith('/flags.xml')).length, 3);
  assert.ok(scenario.calls.every(call => call.cache === 'reload'));
  assert.deepEqual(scenario.delays, [200, 400]);
  assert.deepEqual(scenario.errors, []);
  assert.deepEqual([...scenario.entries.keys()].sort(), [...Object.keys(resources).map(path => new URL(path, scope).href), manifestUrl].sort());
  assert.equal([...scenario.entries.keys()].at(-1), manifestUrl);
  assert.equal(await scenario.entries.get(new URL('assets/flags.xml', scope).href).text(), '<flags/>');
  assert.deepEqual(await scenario.entries.get(manifestUrl).json(), resources);
});

test('permanent transfer failures stop after three attempts and never mark a partial cache complete', async () => {
  const scenario = worker({ fetchResource: url => {
    if (url.endsWith('/flags.xml')) throw new TypeError('Connection timed out');
    return new Response('title');
  } });
  await assert.rejects(scenario.install(), /Precache failed for 1 resource/);
  assert.equal(scenario.calls.filter(call => call.url.endsWith('/flags.xml')).length, 3);
  assert.deepEqual(scenario.delays, [200, 400]);
  assert.equal(scenario.entries.has(manifestUrl), false);
  assert.match(JSON.stringify(scenario.errors), /assets\/flags.xml.*Connection timed out/);
});

test('a rejected response body is retried before cache storage sees the successful transfer', async () => {
  let failures = 2;
  const scenario = worker({ fetchResource: url => {
    if (url.endsWith('/flags.xml') && failures-- > 0) {
      return new Response(new ReadableStream({ start(controller) {
        controller.error(new TypeError('Connection timed out during body transfer'));
      } }));
    }
    return new Response('<complete/>');
  } });
  await scenario.install();
  assert.equal(scenario.calls.filter(call => call.url.endsWith('/flags.xml')).length, 3);
  assert.deepEqual(scenario.delays, [200, 400]);
  assert.deepEqual(scenario.errors, []);
  assert.equal(await scenario.entries.get(new URL('assets/flags.xml', scope).href).text(), '<complete/>');
  assert.deepEqual(await scenario.entries.get(manifestUrl).json(), resources);
});

test('HTTP errors are reported once without retrying a missing resource', async () => {
  const scenario = worker({ fetchResource: url => new Response('missing', { status: url.endsWith('/flags.xml') ? 404 : 200 }) });
  await assert.rejects(scenario.install(), /Precache failed for 1 resource/);
  assert.equal(scenario.calls.length, 2);
  assert.deepEqual(scenario.delays, []);
  assert.equal(scenario.entries.has(manifestUrl), false);
  assert.match(JSON.stringify(scenario.errors), /HTTP 404/);
});

test('cache storage errors do not cause another network transfer or a success manifest', async () => {
  const scenario = worker({ putFailure: new Error('Quota exceeded') });
  await assert.rejects(scenario.install(), /Precache failed for 2 resource/);
  assert.equal(scenario.calls.length, 2);
  assert.deepEqual(scenario.delays, []);
  assert.equal(scenario.entries.has(manifestUrl), false);
});

test('unchanged previous resources are reused while changed resources can recover from a rejected fetch', async () => {
  let failures = 1;
  const scenario = worker({ previous: { 'index.html': '1', 'assets/flags.xml': 'old' }, fetchResource: () => {
    if (failures-- > 0) throw new TypeError('Failed to fetch');
    return new Response('<new-flags/>');
  } });
  await scenario.install();
  assert.equal(scenario.calls.length, 2);
  assert.ok(scenario.calls.every(call => call.url === new URL('assets/flags.xml', scope).href));
  assert.equal(await scenario.entries.get(new URL('index.html', scope).href).text(), 'old 1');
  assert.equal(await scenario.entries.get(new URL('assets/flags.xml', scope).href).text(), '<new-flags/>');
  assert.deepEqual(await scenario.entries.get(manifestUrl).json(), resources);
});
