import { createServer } from 'node:http';
import { readFileSync, existsSync, statSync, writeFileSync } from 'node:fs';
import { extname, join, resolve } from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';
import { PNG } from 'pngjs';
import { waitForSemantics, waitForUiSettled } from '../../../scripts/browser_support.mjs';
import { inspectPrecache, parseOfflineManifest } from './offline_contract.mjs';

const TIMEOUT = 120_000;
const FAILURE_SCREENSHOT =
  fileURLToPath(new URL('offline-test-failure.png', import.meta.url));
const buildDir = resolve(process.argv[2] ?? join('..', '..', 'build', 'web'));
const BASE_PATH = process.argv[3] ?? '/lcs-new-age/';
if (!BASE_PATH.startsWith('/') || !BASE_PATH.endsWith('/')) {
  console.error(`Base path must start and end with /: ${BASE_PATH}`);
  process.exit(1);
}

const MIME = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.xml': 'application/xml',
  '.svg': 'image/svg+xml',
  '.css': 'text/css',
  '.md': 'text/markdown',
  '.txt': 'text/plain',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
};

function handleRequest(req, res) {
  const url = new URL(req.url, 'http://localhost');
  if (!url.pathname.startsWith(BASE_PATH)) {
    res.writeHead(404).end();
    return;
  }
  let rel = decodeURIComponent(url.pathname.slice(BASE_PATH.length));
  if (rel === 'index.html') {
    res.writeHead(308, { Location: BASE_PATH }).end();
    return;
  }
  if (rel === '') rel = 'index.html';
  const filePath = resolve(join(buildDir, rel));
  if (!filePath.startsWith(buildDir) || !existsSync(filePath) || !statSync(filePath).isFile()) {
    res.writeHead(404).end();
    return;
  }
  res.writeHead(200, { 'Content-Type': MIME[extname(filePath)] ?? 'application/octet-stream' });
  res.end(readFileSync(filePath));
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function waitForTitle(page, phase) {
  await waitForSemantics(page, /Start a New Game/, { timeout: TIMEOUT });
  const start = page.getByRole('button', { name: /^Start a New Game\b/ }).first();
  await start.waitFor({ state: 'visible', timeout: TIMEOUT });
  assert(await start.isEnabled(), `Source title's Start a New Game is disabled ${phase}.`);
  await waitForUiSettled(page);
}

async function main() {
  assert(existsSync(join(buildDir, 'index.html')), `No index.html in ${buildDir}`);
  const sw = readFileSync(join(buildDir, 'sw.js'), 'utf8');
  assert(!sw.includes('// build: manifest'),
    'sw.js still contains the unfilled manifest placeholder. ' +
    'Run tool/inject_service_worker.dart before this test.');
  const manifest = parseOfflineManifest(sw);

  const server = createServer(handleRequest);
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const origin = `http://127.0.0.1:${server.address().port}`;

  const browser = await chromium.launch({channel: process.env.LCS_BROWSER_CHANNEL || undefined,
    args: ['--force-renderer-accessibility']});
  const pageErrors = [];
  const failedRequests = [];
  let page;
  try {
    page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
    page.on('pageerror', (e) => pageErrors.push(String(e)));
    page.on('requestfailed', (r) =>
      failedRequests.push(`${r.method()} ${r.url()} — ${r.failure()?.errorText}`));

    console.log('Loading app online...');
    await page.goto(origin + BASE_PATH, { waitUntil: 'load', timeout: TIMEOUT });
    await page.waitForSelector('flutter-view, flt-glass-pane', { state: 'attached', timeout: TIMEOUT });
    await waitForTitle(page, 'online');
    console.log('Source title ready online.');

    console.log('Waiting for service worker activation (precache complete)...');
    const scope = origin + BASE_PATH;
    await page.waitForFunction(async ({ scope, script }) => {
      const reg = await navigator.serviceWorker.getRegistration(scope);
      return reg?.scope === scope && reg.active?.state === 'activated' && reg.active.scriptURL === script
        && navigator.serviceWorker.controller?.state === 'activated' && navigator.serviceWorker.controller.scriptURL === script;
    }, { scope, script: new URL('sw.js', scope).href }, { timeout: TIMEOUT });

    const cached = await page.evaluate(inspectPrecache, { ...manifest, scope });
    console.log(`Current cache ${cached.name}: complete manifest and ${cached.count} scoped resource responses verified.`);

    console.log('Stopping web server; reloading with no network available...');
    server.closeAllConnections();
    await new Promise((r) => server.close(r));
    await page.context().setOffline(true);
    pageErrors.length = 0;
    failedRequests.length = 0;

    await page.reload({ waitUntil: 'load', timeout: TIMEOUT });
    await page.waitForSelector('flutter-view, flt-glass-pane', { state: 'attached', timeout: TIMEOUT });
    await waitForTitle(page, 'offline after server shutdown');

    const shot = PNG.sync.read(await page.screenshot());
    let litPixels = 0;
    for (let i = 0; i < shot.data.length; i += 4) {
      if (shot.data[i] + shot.data[i + 1] + shot.data[i + 2] > 90) litPixels++;
    }
    assert(litPixels > 5000,
      `App booted offline but rendered almost nothing (${litPixels} lit pixels)`);

    console.log(`PASS: source title boots offline (${cached.name}, ${cached.count} cached resources, ${litPixels} lit pixels rendered)`);
  } catch (e) {
    console.error(`FAIL: ${e.message}`);
    for (const err of pageErrors) console.error(`  page error: ${err}`);
    for (const req of failedRequests) console.error(`  failed request: ${req}`);
    if (page) {
      try {
        writeFileSync(FAILURE_SCREENSHOT, await page.screenshot());
        console.error(`  screenshot saved to ${FAILURE_SCREENSHOT}`);
      } catch {
        // page may be unusable; screenshot is best-effort
      }
    }
    process.exitCode = 1;
  } finally {
    await browser.close();
    server.closeAllConnections();
    server.close();
  }
}

await main();
