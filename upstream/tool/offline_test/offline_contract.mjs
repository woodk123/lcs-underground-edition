// Pure offline acceptance checks; importing this module never launches a browser.
export function parseOfflineManifest(worker) {
  const resourcesMatch = /^const RESOURCES = (.+);\r?$/m.exec(worker);
  const versionMatch = /^const VERSION = '([^'\r\n]+)';\r?$/m.exec(worker);
  if (!resourcesMatch || !versionMatch || !/^[0-9a-f]{1,8}$/.test(versionMatch[1])) {
    throw new Error('sw.js has no injected RESOURCES/VERSION. Run tool/inject_service_worker.dart.');
  }
  let resources;
  try { resources = JSON.parse(resourcesMatch[1]); }
  catch { throw new Error('Injected sw.js RESOURCES is not valid JSON.'); }
  if (!resources || typeof resources !== 'object' || Array.isArray(resources)
    || !Object.keys(resources).length || !Object.hasOwn(resources, 'index.html') || !Object.hasOwn(resources, 'main.dart.js')
    || Object.entries(resources).some(([path, crc]) => !path || typeof crc !== 'string' || !/^[0-9a-f]{1,8}$/.test(crc))) {
    throw new Error('Injected sw.js RESOURCES must contain the complete resource/checksum map, including index.html and main.dart.js.');
  }
  return { version: versionMatch[1], resources };
}

export async function waitForPrecacheActivation(page, { scope, script, timeout }) {
  const registration = await page.evaluateHandle(scope => navigator.serviceWorker.getRegistration(scope), scope);
  try {
    // Playwright polls the immediate return value; an async predicate is a truthy Promise.
    await page.waitForFunction(({ registration, scope, script }) => Boolean(
      registration?.scope === scope && registration.active?.state === 'activated' && registration.active.scriptURL === script
      && navigator.serviceWorker.controller?.state === 'activated' && navigator.serviceWorker.controller.scriptURL === script
    ), { registration, scope, script }, { timeout });
  } finally {
    await registration.dispose();
  }
}

// Self-contained for page.evaluate: only browser globals and supplied data.
// A second argument permits dependency-free CacheStorage fixtures in Node.
export async function inspectPrecache({ version, resources, scope }, storage = globalThis.caches) {
  const base = new URL(scope);
  if (base.href !== scope || !base.pathname.endsWith('/') || base.search || base.hash) {
    throw new Error(`Invalid service worker scope: ${scope}`);
  }
  const paths = Object.keys(resources);
  const urls = paths.map(path => {
    const url = new URL(path, scope);
    if (url.origin !== base.origin || !url.href.startsWith(scope) || url.search || url.hash
      || decodeURIComponent(url.pathname.slice(base.pathname.length)) !== path) {
      throw new Error(`Resource is not a relative URL within the worker scope: ${path}`);
    }
    return url.href;
  });
  const name = `lcs-new-age-${version}`;
  const names = await storage.keys();
  if (!names.includes(name)) throw new Error(`Current precache is missing: ${name}. Found: ${names.join(', ')}`);
  const cache = await storage.open(name);
  const manifest = await cache.match(new URL('__lcs-manifest__', scope).href);
  if (!manifest?.ok) throw new Error(`Current precache ${name} has no successful scoped manifest response.`);
  let stored;
  try { stored = await manifest.json(); }
  catch { throw new Error(`Current precache ${name} has an unreadable manifest.`); }
  if (!stored || typeof stored !== 'object' || Array.isArray(stored)
    || Object.keys(stored).length !== paths.length || paths.some(path => !Object.hasOwn(stored, path) || stored[path] !== resources[path])) {
    throw new Error(`Current precache ${name} manifest differs from injected RESOURCES.`);
  }
  const missing = (await Promise.all(urls.map(async url => {
    const response = await cache.match(url);
    return response?.ok ? null : `${url} (${response ? `HTTP ${response.status}` : 'missing'})`;
  }))).filter(Boolean);
  if (missing.length) throw new Error(`Current precache ${name} has ${missing.length} missing/failed resource(s): ${missing.join(', ')}`);
  return { name, names, scope, count: paths.length };
}
