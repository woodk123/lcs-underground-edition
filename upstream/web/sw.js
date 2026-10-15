'use strict';

const RESOURCES = null; // build: manifest
const VERSION = 'dev'; // build: version

const CACHE_PREFIX = 'lcs-new-age-';
const CACHE_NAME = CACHE_PREFIX + VERSION;
const MANIFEST_KEY = '__lcs-manifest__';
const LEGACY_CACHES =
    ['flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest'];

function resourceUrl(path) {
  return new URL(path, self.registration.scope).toString();
}

async function stripRedirect(response) {
  if (!response.redirected) {
    return response;
  }
  return new Response(await response.blob(), {
    status: response.status,
    statusText: response.statusText,
    headers: response.headers,
  });
}

async function previousCache() {
  const names = await caches.keys();
  const name =
      names.find((n) => n.startsWith(CACHE_PREFIX) && n !== CACHE_NAME);
  if (!name) {
    return { cache: null, manifest: {} };
  }
  const cache = await caches.open(name);
  const stored = await cache.match(resourceUrl(MANIFEST_KEY));
  if (!stored) {
    return { cache, manifest: {} };
  }
  try {
    return { cache, manifest: await stored.json() };
  } catch (e) {
    return { cache, manifest: {} };
  }
}

self.addEventListener('install', (event) => {
  if (RESOURCES === null) {
    return;
  }
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    const previous = await previousCache();
    const failures = [];
    await Promise.all(Object.keys(RESOURCES).map(async (path) => {
      const url = resourceUrl(path);
      try {
        if (previous.cache && previous.manifest[path] === RESOURCES[path]) {
          const reused = await previous.cache.match(url);
          if (reused) {
            await cache.put(url, reused);
            return;
          }
        }
        const response = await fetch(url, { cache: 'reload' });
        if (!response.ok) {
          throw new Error('HTTP ' + response.status);
        }
        await cache.put(url, await stripRedirect(response));
      } catch (e) {
        failures.push(path + ' — ' + e.message);
      }
    }));
    if (failures.length > 0) {
      console.error(
        'LCS service worker: precache failed, offline play unavailable. ' +
        'Failed resources:', failures);
      throw new Error('Precache failed for ' + failures.length + ' resource(s)');
    }
    await cache.put(resourceUrl(MANIFEST_KEY), new Response(
        JSON.stringify(RESOURCES),
        { headers: { 'Content-Type': 'application/json' } }));
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    if (RESOURCES !== null) {
      const names = await caches.keys();
      await Promise.all(names.map(async (name) => {
        const outdated =
            (name.startsWith(CACHE_PREFIX) && name !== CACHE_NAME) ||
            LEGACY_CACHES.includes(name);
        if (outdated) {
          await caches.delete(name);
        }
      }));
    }
    await self.clients.claim();
  })());
});

self.addEventListener('message', (event) => {
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
  }
});

async function cachePut(cache, key, response) {
  try {
    await cache.put(key, await stripRedirect(response));
  } catch (e) {
    console.warn('LCS service worker: failed to cache ' + key, e);
  }
}

function cacheKey(request) {
  const url = new URL(request.url);
  url.search = '';
  const path = url.toString().substring(self.registration.scope.length);
  if (Object.hasOwn(RESOURCES, path)) {
    return url.toString();
  }
  return request.url;
}

async function respond(request) {
  const cache = await caches.open(CACHE_NAME);
  if (request.mode === 'navigate') {
    const key = resourceUrl('index.html');
    try {
      const response = await fetch(request);
      if (response.status === 200) {
        await cachePut(cache, key, response.clone());
      }
      return response;
    } catch (e) {
      const cached = await cache.match(key);
      if (cached) {
        return cached;
      }
      throw e;
    }
  }
  const key = cacheKey(request);
  const cached = await cache.match(key);
  if (cached) {
    return cached;
  }
  const response = await fetch(request);
  if (response.status === 200) {
    await cachePut(cache, key, response.clone());
  }
  return response;
}

self.addEventListener('fetch', (event) => {
  if (RESOURCES === null) {
    return;
  }
  if (event.request.method !== 'GET') {
    return;
  }
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) {
    return;
  }
  if (!url.href.startsWith(self.registration.scope)) {
    return;
  }
  event.respondWith(respond(event.request));
});
