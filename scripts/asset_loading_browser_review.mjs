// Startup timeout regression through actual import, headquarters and save UI.
// Only declared page-owned asset requests are faulted; service workers remain enabled.
// Page-only cache bypass models startup before worker control; it does not test
// worker-cached responses or establish the cause of an operating-system timeout.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, isAbsolute, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertQaUrl, chromiumLaunchOptions, observeMainScript, waitForSemantics } from './browser_support.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
if (args.includes('--help')) {
  console.log('Usage: node scripts/asset_loading_browser_review.mjs --expected-hash SHA256 [--fault-count 1|2|all] [--url URL] [--out FRESH_IGNORED_DIRECTORY]\n'
    + 'Fault fixture: bypass the service worker only for page requests, modeling startup before worker control. '
    + 'Worker registration and precaching remain enabled. Abort the first one/two page flags.xml requests, '
    + 'then require the enabled title within 20 seconds and an unchanged Felix save round trip. '
    + 'This does not intercept worker-cached responses or prove the original OS timeout trigger.');
  process.exit(0);
}
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const arg = (flag, fallback) => {
  const index = args.indexOf(flag);
  if (index < 0) return fallback;
  assert.ok(args[index + 1] && !args[index + 1].startsWith('--'), `${flag} requires a value.`);
  return args[index + 1];
};
const url = assertQaUrl(arg('--url', undefined));
const expected = arg('--expected-hash', '').toLowerCase();
assert.match(expected, /^[a-f0-9]{64}$/, 'Require the exact compiled main.dart.js SHA-256.');
const selection = arg('--fault-count', 'all');
assert.ok(['all', '1', '2'].includes(selection), '--fault-count must be 1, 2 or all.');
const counts = selection === 'all' ? [1, 2] : [Number(selection)];
const output = resolve(root, arg('--out', `reports/asset-loading-${Date.now()}`));
assert.ok(['.local', 'reports'].some(parent => {
  const child = relative(resolve(root, parent), output);
  return child && !isAbsolute(child) && child !== '..' && !child.startsWith('../') && !child.startsWith('..\\');
}), 'Keep fresh evidence beneath ignored .local/ or reports/.');
await mkdir(dirname(output), { recursive: true });
await mkdir(output); // Refuse an existing attempt rather than overwriting its diagnostics.
const assetUrl = new URL('assets/assets/xml/flags.xml', url).href;
const fixture = resolve(root, 'upstream/test/saves/felix_1_0.json');
const fixtureBytes = await readFile(fixture);
const report = {
  status: 'running', started: new Date().toISOString(), url, expectedHash: expected,
  scope: 'Fresh profiles with page-only service-worker cache bypass to model startup before worker control; '
    + 'worker registration and precaching remain enabled and unmodified. The first one or two page-owned flags.xml GETs '
    + 'are aborted as timedout. This does not intercept worker-cached responses or prove the original OS timeout trigger. '
    + 'Actual title within 20 seconds, unmodified bundled Felix import, '
    + 'headquarters, save/exit/export and complete campaign equality after reload/save/exit/export. No gameplay turns.',
  fixture: { path: relative(root, fixture), sha256: createHash('sha256').update(fixtureBytes).digest('hex'), changes: [] },
  assetUrl, scenarios: [], loadedMainJsHashes: [],
};
await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
let browser;
const decode = envelope => typeof envelope.saveData === 'string' ? JSON.parse(envelope.saveData) : envelope.saveData;
try {
  const response = await fetch(new URL('main.dart.js', url));
  assert.ok(response.ok, `main.dart.js HTTP ${response.status}`);
  report.prefetchedMainJsSha256 = createHash('sha256').update(Buffer.from(await response.arrayBuffer())).digest('hex');
  assert.equal(report.prefetchedMainJsSha256, expected);
  browser = await chromium.launch(chromiumLaunchOptions({ args }));
  for (const faultCount of counts) {
    const scenario = { faultCount, status: 'running', checks: [], injected: [], requests: [], pageErrors: [],
      consoleErrors: [], failedRequests: [], workerConsole: [], loadedMainJsHashes: [], screenshots: [],
      fixture: { pageServiceWorkerCacheBypass: true, workerRegistrationAndPrecache: 'allowed, unmodified' } };
    report.scenarios.push(scenario);
    const directory = resolve(output, `timeouts-${faultCount}`);
    await mkdir(directory);
    const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, acceptDownloads: true,
      serviceWorkers: 'allow' });
    const page = await context.newPage();
    page.setDefaultTimeout(10000);
    const verifyLoaded = observeMainScript(page, scenario);
    const startedAt = Date.now(), pending = new Map(), injectedRequests = new Set();
    const elapsed = () => Date.now() - startedAt;
    const check = name => { scenario.checks.push(name); console.log(`PASS ${faultCount} timeout(s): ${name}`); };
    const button = name => page.getByRole('button', { name }).first();
    const wait = pattern => waitForSemantics(page, pattern, { timeout: 20000 });
    const text = () => page.evaluate(() => {
      const host = document.querySelector('flt-semantics-host');
      return host ? [host.innerText, ...[...host.querySelectorAll('[aria-label]')].map(n => n.getAttribute('aria-label')),
        ...[...host.querySelectorAll('input,textarea')].map(n => n.value)].filter(Boolean).join('\n') : '';
    });
    async function click(name) {
      const control = button(name);
      // Trial waits for this reader's visible, enabled control before sending input.
      await control.click({ trial: true });
      await control.click();
      await page.mouse.move(2, 2);
    }
    async function capture(name) {
      await page.screenshot({ path: resolve(directory, `${name}.png`), fullPage: true });
      await writeFile(resolve(directory, `${name}.txt`), await text());
      scenario.screenshots.push(`${name}.png`);
    }
    context.on('request', request => {
      const entry = { url: request.url(), method: request.method(), resourceType: request.resourceType(),
        serviceWorker: request.serviceWorker()?.url() ?? null, startedMs: elapsed() };
      scenario.requests.push(entry); pending.set(request, entry);
    });
    context.on('response', response => {
      const entry = pending.get(response.request());
      if (entry) Object.assign(entry, { status: response.status(), responseMs: elapsed(), fromServiceWorker: response.fromServiceWorker() });
    });
    function finish(request, error) {
      const entry = pending.get(request);
      if (entry) Object.assign(entry, { finishedMs: elapsed(), timing: request.timing(), ...(error ? { error } : {}) });
      pending.delete(request);
    }
    context.on('requestfinished', request => finish(request));
    context.on('requestfailed', request => {
      const failure = { url: request.url(), errorText: request.failure()?.errorText ?? null,
        serviceWorker: request.serviceWorker()?.url() ?? null, injected: injectedRequests.has(request), elapsedMs: elapsed() };
      scenario.failedRequests.push(failure); finish(request, failure.errorText);
    });
    page.on('pageerror', error => scenario.pageErrors.push({
      error: String(error), name: error.name, stack: error.stack ?? null, elapsedMs: elapsed(),
    }));
    context.on('console', message => {
      if (message.page() === page && message.type() === 'error') {
        scenario.consoleErrors.push({ text: message.text(), location: message.location(), elapsedMs: elapsed() });
      } else if (!message.page() && ['error', 'warning'].includes(message.type())) {
        scenario.workerConsole.push({ type: message.type(), text: message.text(), location: message.location(), elapsedMs: elapsed() });
      }
    });
    const cdp = await context.newCDPSession(page);
    await cdp.send('Network.enable');
    await cdp.send('Network.setBypassServiceWorker', { bypass: true });
    await page.route(assetUrl, async route => {
      const request = route.request();
      // Do not inject into the worker's separate install/precache traffic.
      if (request.method() !== 'GET' || request.serviceWorker() || request.frame() !== page.mainFrame()) return route.continue();
      if (scenario.injected.length >= faultCount) return route.continue();
      injectedRequests.add(request);
      scenario.injected.push({ url: request.url(), elapsedMs: elapsed(), owner: 'page-main-frame', error: 'timedout' });
      await route.abort('timedout');
    });
    async function diagnostic() {
      scenario.pendingAtCapture = [...pending.values()].map(entry => ({ ...entry, pendingForMs: elapsed() - entry.startedMs }));
      scenario.browserState = await page.evaluate(async () => {
        let bridge = null, timer;
        try {
          if (globalThis.lcsDev?.request) bridge = JSON.parse(await Promise.race([
            globalThis.lcsDev.request(JSON.stringify({ method: 'observe', params: {} })),
            new Promise((_, reject) => { timer = setTimeout(() => reject(Error('Read-only observe timed out.')), 1000); }),
          ]));
        } catch (error) { bridge = { error: String(error) }; } finally { clearTimeout(timer); }
        const registrations = await navigator.serviceWorker.getRegistrations();
        return { bridge, controller: navigator.serviceWorker.controller?.scriptURL ?? null,
          registrations: registrations.map(r => ({ scope: r.scope, installing: r.installing?.state ?? null,
            waiting: r.waiting?.state ?? null, active: r.active?.state ?? null })) };
      });
    }
    async function saveAndExport(name) {
      await click(/^Save & exit/); await wait(/Start a New Game/);
      await click(/^Load & Manage Saves/); await click(/^A(?:\s|$)/);
      await wait(/Manage .*Saved Game/);
      const downloading = page.waitForEvent('download');
      await click(/Export Save File/);
      const path = resolve(directory, `${name}.json`);
      await (await downloading).saveAs(path);
      return decode(JSON.parse(await readFile(path, 'utf8')));
    }
    try {
      await page.goto(url, { waitUntil: 'domcontentloaded' });
      // One deadline covers both title semantics and its actual enabled control.
      const remaining = Math.max(1, startedAt + 20000 - Date.now());
      await button(/Start a New Game/).click({ trial: true, timeout: remaining });
      scenario.titleReadyMs = elapsed();
      assert.ok(scenario.titleReadyMs <= 20000, 'The actual enabled title must arrive within the unchanged 20-second deadline.');
      check('actual enabled title within 20 seconds');
      assert.equal(scenario.injected.length, faultCount, 'Exercise every declared foreground timeout.');
      const successes = scenario.requests.filter(r => r.url === assetUrl && !r.serviceWorker && r.status === 200);
      assert.ok(successes.length, 'The page must receive flags.xml successfully after the injected failures.');
      assert.ok(successes.every(r => r.fromServiceWorker === false), 'The declared cold-start page fixture must use network responses.');
      check('declared page faults followed by a successful asset response');
      await capture('title');
      const choosing = page.waitForEvent('filechooser');
      await click(/^Import a Save/); await (await choosing).setFiles(fixture);
      await wait(/Save imported/); await page.keyboard.press('Enter'); await wait(/Start a New Game/);
      await click(/^Load & Manage Saves/); await click(/^A(?:\s|$)/); await click(/^L Load Game/);
      await wait(/Save & exit/); await button(/^Save & exit/).click({ trial: true });
      check('unmodified Felix imported and playable headquarters reached');
      await capture('headquarters');
      const before = await saveAndExport('first-save');
      await click(/^L Load Game/); await wait(/Save & exit/);
      const after = await saveAndExport('second-save');
      assert.deepEqual(after, before, 'No-turn save/reload/save must preserve the complete normalized campaign.');
      check('save/exit/export and reload preserve complete campaign');
      await capture('saved-game');
      scenario.status = 'passed';
    } catch (error) {
      scenario.status = 'failed'; scenario.failure = String(error); process.exitCode = 1;
      await capture('failure').catch(error => { scenario.captureError = String(error); });
    } finally {
      let diagnosticTimer;
      try {
        await Promise.race([diagnostic(), new Promise((_, reject) => {
          diagnosticTimer = setTimeout(() => reject(Error('Read-only diagnostic exceeded 1600ms.')), 1600);
        })]);
      } catch (error) {
        scenario.status = 'failed'; scenario.diagnosticError = String(error); process.exitCode = 1;
      } finally { clearTimeout(diagnosticTimer); }
      await verifyLoaded(expected).catch(error => { scenario.status = 'failed'; scenario.loadedScriptError = String(error); process.exitCode = 1; });
      report.loadedMainJsHashes.push(...scenario.loadedMainJsHashes);
      // Run after diagnostics/hash verification so errors arriving late in the
      // journey are checked before writing the final pre-close report.
      try {
        scenario.expectedConsoleErrors = scenario.consoleErrors.filter(error => injectedRequests.size > 0
          && error.location.url === assetUrl && error.text === 'Failed to load resource: net::ERR_TIMED_OUT');
        assert.deepEqual(scenario.consoleErrors.filter(error => !scenario.expectedConsoleErrors.includes(error)), []);
        assert.ok(scenario.expectedConsoleErrors.length <= injectedRequests.size, 'Do not exempt more console errors than injected requests.');
        assert.deepEqual(scenario.pageErrors, []);
        assert.deepEqual(scenario.workerConsole.filter(message => message.type === 'error'), [], 'No unexpected worker errors.');
        assert.deepEqual(scenario.failedRequests.filter(failure => !failure.injected), [], 'No unrelated page or worker request failures.');
        assert.equal(scenario.failedRequests.filter(failure => failure.injected && failure.errorText === 'net::ERR_TIMED_OUT').length, faultCount);
        check('only exact declared timeout errors observed');
      } catch (error) {
        scenario.status = 'failed'; scenario.errorGateFailure = String(error); process.exitCode = 1;
      }
      await writeFile(resolve(directory, 'report.json'), JSON.stringify(scenario, null, 2));
      await context.close();
      await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
    }
    console.log(`${scenario.status.toUpperCase()} ${faultCount} timeout(s): ${scenario.failure ?? scenario.errorGateFailure
      ?? scenario.diagnosticError ?? scenario.loadedScriptError ?? scenario.titleReadyMs + 'ms title'}`);
  }
  report.status = report.scenarios.every(scenario => scenario.status === 'passed') ? 'passed' : 'failed';
} catch (error) {
  report.status = 'failed'; report.failure = String(error); process.exitCode = 1;
} finally {
  await browser?.close();
  report.finished = new Date().toISOString();
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ status: report.status, output, loadedMainJsHashes: report.loadedMainJsHashes }));
}
