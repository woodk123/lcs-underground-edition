// Keyboard-only task sequences in the actual graphical and Classic readers.
// Fixture import/export and changing display preferences are explicit setup.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertQaUrl, chromiumLaunchOptions, observeMainScript, waitForSemantics, waitForUiSettled } from './browser_support.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const args = process.argv.slice(2);
const value = (flag, fallback) => args.includes(flag) ? args[args.indexOf(flag) + 1] : fallback;
const url = assertQaUrl(value('--url', 'http://127.0.0.1:18879/'));
const output = resolve(root, value('--out', `reports/keyboard-interface-${new Date().toISOString().replaceAll(':', '-')}`));
await mkdir(output, { recursive: true });
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const decode = save => typeof save.saveData === 'string' ? JSON.parse(save.saveData) : save.saveData;
const report = {
  status: 'running', url,
  scope: 'Unmodified bundled Felix save in disposable profiles. Original LCS L/M/Escape/W/X menu meanings and source-first labels, optional modified journal-tab and Save exit shortcuts, modal isolation, and the identical immediate A/A/B/1 assignment and source Back keys in graphical desktop, graphical compact 1024x720/150%, and Classic. Pointer task previews retain separate draft cancellation and day-advance protection. Import/export and preference changes are setup. No day advances, outcomes or skill values are supplied.',
  checks: [], screenshots: [], sequences: [], startups: [], failures: [], pageErrors: [], consoleErrors: [], failedRequests: [],
};
const expected = value('--expected-hash', null);
assert.match(expected ?? '', /^[a-f0-9]{64}$/i, 'An exact compiled build hash is required.');
report.mainJsSha256 = digest(Buffer.from(await (await fetch(new URL('main.dart.js', url))).arrayBuffer()));
assert.equal(report.mainJsSha256, expected.toLowerCase());
const browser = await chromium.launch(chromiumLaunchOptions({ args }));

function trackStartupRequests(context) {
  const startedAt = Date.now(), requests = [], pending = new Map(), workerErrors = [];
  context.on('request', request => {
    const entry = { url: request.url(), method: request.method(), resourceType: request.resourceType(),
      serviceWorker: request.serviceWorker()?.url() ?? null, startedMs: Date.now() - startedAt };
    requests.push(entry); pending.set(request, entry);
  });
  context.on('response', response => {
    const entry = pending.get(response.request());
    if (entry) Object.assign(entry, { responseMs: Date.now() - startedAt, status: response.status(),
      fromServiceWorker: response.fromServiceWorker(), contentLength: Number(response.headers()['content-length'] ?? 0) });
  });
  function finish(request, error) {
    const entry = pending.get(request);
    if (entry) Object.assign(entry, { finishedMs: Date.now() - startedAt, timing: request.timing(),
      ...(error ? { error } : {}) });
    pending.delete(request);
  }
  context.on('requestfinished', request => finish(request));
  context.on('requestfailed', request => finish(request, request.failure()?.errorText ?? 'Unknown request failure'));
  context.on('console', message => {
    if (!message.page() && ['error', 'warning'].includes(message.type()))
      workerErrors.push({ elapsedMs: Date.now() - startedAt, type: message.type(), text: message.text(), location: message.location() });
  });
  return { startedAt, requests, workerErrors,
    pendingAtFailure: () => [...pending.values()].map(entry => ({ ...entry, pendingForMs: Date.now() - startedAt - entry.startedMs })) };
}

async function runScenario({ name, viewport, compact, classic }) {
  const context = await browser.newContext({ viewport, acceptDownloads: true });
  const network = trackStartupRequests(context);
  const startup = { scenario: name, createdAt: new Date(network.startedAt).toISOString(), titleDeadlineMs: 20000 };
  report.startups.push(startup);
  const page = await context.newPage();
  const operations = [];
  const verifyLoaded = observeMainScript(page, report);
  page.on('pageerror', error => report.pageErrors.push(String(error)));
  page.on('console', message => { if (message.type() === 'error') report.consoleErrors.push(message.text()); });
  page.on('requestfailed', request => report.failedRequests.push(request.url()));
  const text = () => page.locator('flt-semantics-host').evaluate(host => [host.innerText,
    ...[...host.querySelectorAll('[aria-label]')].map(node => node.getAttribute('aria-label')),
  ].filter(Boolean).join('\n'));
  async function wait(pattern) {
    operations.push({ operation: 'wait', target: String(pattern) });
    await waitForSemantics(page, pattern);
  }
  async function click(pattern, locator = page) {
    operations.push({ operation: 'click', target: String(pattern) });
    await locator.getByRole('button', { name: pattern }).first().click();
    await page.mouse.move(1, 1);
    await waitForUiSettled(page);
  }
  async function key(key) {
    operations.push({ operation: 'key', target: key });
    await page.keyboard.press(key);
    await waitForUiSettled(page);
  }
  async function capture(label) {
    const path = `${name}-${label}.png`;
    await page.screenshot({ path: resolve(output, path), fullPage: true });
    report.screenshots.push(path);
  }
  async function exportGame(label, { keyboardExit = false, originalExit = false } = {}) {
    if (originalExit) await key('x');
    else if (keyboardExit) await key('Alt+x');
    else await click(/^Save & exit/);
    await wait(/Start a New Game/);
    await click(/^Load & Manage Saves/);
    await click(/^A(?:\s|$)/);
    await wait(/Manage .*Saved Game/);
    const downloading = page.waitForEvent('download');
    await click(/Export Save File/);
    const path = resolve(output, `${name}-${label}.json`);
    await (await downloading).saveAs(path);
    const data = decode(JSON.parse(await readFile(path, 'utf8')));
    await click(/^L Load Game/);
    await wait(/Save & exit/);
    return data;
  }
  try {
    startup.navigationStartedAt = new Date().toISOString();
    await page.goto(url, { waitUntil: 'domcontentloaded' });
    startup.domContentLoadedAt = new Date().toISOString();
    await wait(/Start a New Game/);
    startup.titleReadyAt = new Date().toISOString();
    const choosing = page.waitForEvent('filechooser');
    await click(/^Import a Save/);
    await (await choosing).setFiles(resolve(root, 'upstream/test/saves/felix_1_0.json'));
    await wait(/Save imported/);
    await key('Enter');
    await click(/^Load & Manage Saves/);
    await click(/^A(?:\s|$)/);
    await click(/^L Load Game/);
    await wait(/Save & exit/);
    const before = await exportGame('before');

    if (compact) {
      await click(/^Reading size/);
      await page.getByRole('menuitem', { name: '150%' }).click();
      await click(/^Interface preferences/);
      await page.getByRole('alertdialog').getByRole('checkbox', { name: 'Compact', exact: true }).click();
      await page.getByRole('switch', { name: /^Show explanations/ }).click();
      // Keys that would advance time or open readers must stay inside the dialog.
      for (const command of ['l', 'm', 'r', 'x', 'w', 'a', 'f', 'Alt+7', 'Alt+x', 'Alt+w']) await key(command);
      await key('Escape');
      assert.deepEqual(await exportGame('after-preferences'), before);
      report.checks.push(`${name}: preferences and modal shortcuts preserve campaign`);
    }

    if (!classic) {
      await capture('original-controls-headquarters');
      await key('l');
      await wait(/The Liberal Agenda/);
      await capture('original-controls-agenda');
      // Original Agenda W is Back, not an HQ day command. Original HQ X
      // must still save and exit after that reader has returned.
      await key('w');
      await key('m');
      await wait(/Press archive/);
      await key('Escape');
      assert.deepEqual(await exportGame('after-original-keys', { originalExit: true }), before,
        'Original L opens Agenda, W returns without a day advance, M/Escape opens and closes Media, and HQ X saves unchanged state.');
      report.checks.push(`${name}: original L/M/Escape/W/X keys retain source menu meanings and campaign state`);
      for (const [command, heading] of [
        ['Alt+7', /The Liberal Agenda/],
        ['Alt+o', /Journal options/],
        ['Alt+2', /Personnel directory/],
        ['Alt+7', /The Liberal Agenda/],
      ]) {
        await key(command);
        await wait(heading);
        assert.equal(page.url(), url, 'Journal shortcuts stay inside the game.');
      }
      await capture('header-shortcuts-agenda');
      assert.deepEqual(await exportGame('after-header-shortcuts', { keyboardExit: true }), before,
        'Header navigation and keyboard Save & exit preserve the complete campaign.');
      await key('Alt+1');
      report.checks.push(`${name}: modified header shortcuts and Save exit follow source routes`);
    }

    if (classic) {
      await click(/^Switch readable \/ classic view/);
    }
    const opening = ['a', 'a', 'b', '1'];
    for (const command of opening) await key(command);
    if (!classic) {
      await wait(/Choose a task/);
      assert.equal(await page.getByRole('button', { name: 'Confirm order', exact: true }).count(), 0,
        'The original task key applies immediately without creating a journal draft.');
    }
    await capture('keyboard-assigned-task');
    // Task 1 applies immediately and leaves the original actor reader open.
    // Each original Back key returns to the same person list; A reopens it.
    const backAliasProbe = ['Escape', 'a', 'Enter', 'a', 'Space', 'Space'];
    for (const command of backAliasProbe) await key(command);
    if (classic) await click(/^Switch readable \/ classic view/);
    const after = await exportGame('after-original-assignment');
    const expectedCampaign = structuredClone(before);
    expectedCampaign.lcs.pool[0].activity = { type: 'donations' };
    assert.deepEqual(after, expectedCampaign,
      'The original A/A/B/1 keys immediately assign only the selected first actor; Back aliases preserve that choice.');
    report.sequences.push({
      name, viewport, readingScale: compact ? 1.5 : 1,
      assignment: opening, assignmentKeypresses: opening.length,
      assignmentEffect: 'Category B applies its original default; task 1 immediately assigns donations and retains the actor reader.',
      backAliasProbe,
      mouseInputsDuringTaskSequence: 0,
    });
    report.checks.push(`${name}: original keyboard assignment is immediate and original Back aliases preserve menu flow`);
    if (!classic) {
      // Reopen the same source actor/category and restore task 1 before the
      // separate pointer-only preview. Raw category B can change its default.
      for (const command of opening) await key(command);
      await wait(/Choose a task/);
      await click(/^Prepare .*Make and Sell Art/);
      await wait(/Prepared, awaiting confirmation|Prepared · awaiting confirmation/);
      assert.equal(await page.getByRole('button', { name: 'Confirm order', exact: true }).count(), 1);
      await key('Alt+w');
      assert.equal(await page.getByRole('button', { name: 'Confirm order', exact: true }).count(), 1,
        'The global day shortcut must not dismiss or commit a pointer-prepared order.');
      await capture('pointer-prepared-order');
      await key('Escape');
      assert.equal(await page.getByRole('button', { name: 'Confirm order', exact: true }).count(), 0);
      for (const command of ['Escape', 'Space']) await key(command);
      assert.deepEqual(await exportGame('after-pointer-draft'), after,
        'Pointer preview, blocked day advance and cancellation preserve the complete assigned campaign.');
      report.sequences.at(-1).pointerDraftProbe = {
        reentry: opening, prepare: 'Pointer: Make and Sell Art',
        blockedCommand: 'Alt+w', cancel: 'Escape', sourceBack: ['Escape', 'Space'],
      };
      report.checks.push(`${name}: pointer draft cancellation and day-advance guard preserve the complete campaign`);
    }
    if (compact) {
      await page.reload({ waitUntil: 'domcontentloaded' });
      await wait(/Start a New Game/);
      await click(/^Interface preferences/);
      assert.equal(await page.getByRole('checkbox', { name: 'Compact', exact: true }).getAttribute('aria-checked'), 'true');
      assert.equal(await page.getByRole('switch', { name: /^Show explanations/ }).getAttribute('aria-checked'), 'false');
      await key('Escape');
      report.checks.push(`${name}: display preferences survive reload`);
    }
    await verifyLoaded(expected.toLowerCase());
    return { before, after };
  } catch (error) {
    const failure = { scenario: name, error: String(error.stack ?? error), operations: operations.slice(-20),
      network: { capturedAt: new Date().toISOString(), pendingBeforeCapture: network.pendingAtFailure(),
        requests: network.requests, workerErrors: network.workerErrors } };
    try {
      failure.screenshot = `${name}-failure.png`;
      await page.screenshot({ path: resolve(output, failure.screenshot), fullPage: true, timeout: 10000 });
      report.screenshots.push(failure.screenshot);
    } catch (captureError) { failure.screenshotError = String(captureError); }
    try {
      const evidence = await page.evaluate(async () => {
        const host = document.querySelector('flt-semantics-host');
        const describe = node => node ? {
          tag: node.tagName, role: node.getAttribute('role'), label: node.getAttribute('aria-label'),
          text: node.textContent, value: node.value,
        } : null;
        let bridge = { available: false };
        if (globalThis.lcsDev?.request) {
          let timer;
          try { bridge = { available: true, result: JSON.parse(await Promise.race([
            globalThis.lcsDev.request(JSON.stringify({ method: 'observe', params: {} })),
            new Promise((_, reject) => { timer = setTimeout(() => reject(Error('Read-only observe timed out')), 1500); }),
          ])) }; } catch (error) { bridge = { available: true, error: String(error) }; } finally { clearTimeout(timer); }
        }
        const registrations = await navigator.serviceWorker.getRegistrations().catch(() => []);
        return {
          url: location.href,
          capturedAt: new Date().toISOString(), bridge, fonts: document.fonts.status,
          resources: performance.getEntriesByType('resource').map(entry => entry.toJSON()),
          navigation: performance.getEntriesByType('navigation').map(entry => entry.toJSON()),
          serviceWorker: { controller: navigator.serviceWorker.controller && {
            scriptURL: navigator.serviceWorker.controller.scriptURL, state: navigator.serviceWorker.controller.state },
          registrations: registrations.map(registration => ({ scope: registration.scope,
            active: registration.active?.state, installing: registration.installing?.state, waiting: registration.waiting?.state })) },
          semantics: host ? [host.innerText,
            ...[...host.querySelectorAll('[aria-label]')].map(node => node.getAttribute('aria-label')),
            ...[...host.querySelectorAll('input,textarea')].map(node => node.value),
          ].filter(Boolean).join('\n') : null,
          activeElement: describe(document.activeElement),
          controls: host ? [...host.querySelectorAll('[role="button"],input,textarea')].map(node => {
            const bounds = node.getBoundingClientRect();
            return { ...describe(node), bounds: bounds.toJSON(),
              coveringElement: describe(document.elementFromPoint(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2)) };
          }) : [],
        };
      });
      failure.semantics = `${name}-failure.json`;
      await writeFile(resolve(output, failure.semantics), JSON.stringify(evidence, null, 2));
    } catch (captureError) { failure.semanticsError = String(captureError); }
    report.failures.push(failure);
    throw error;
  } finally {
    startup.pendingBeforeClose = network.pendingAtFailure().length;
    startup.requestsObserved = network.requests.length;
    await context.close();
    startup.closedAt = new Date().toISOString();
  }
}

try {
  const desktop = await runScenario({ name: 'graphical-desktop', viewport: { width: 1440, height: 1000 }, compact: false, classic: false });
  const compact = await runScenario({ name: 'graphical-compact', viewport: { width: 1024, height: 720 }, compact: true, classic: false });
  const classic = await runScenario({ name: 'classic-reference', viewport: { width: 1440, height: 1000 }, compact: false, classic: true });
  assert.deepEqual(desktop.before, classic.before, 'Graphical and Classic start from the same complete campaign.');
  assert.deepEqual(compact.before, classic.before, 'Compact graphical and Classic start from the same complete campaign.');
  assert.deepEqual(desktop.after, classic.after, 'Graphical and Classic produce the same complete campaign from identical original keys.');
  assert.deepEqual(compact.after, classic.after, 'Compact graphical and Classic produce the same complete campaign from identical original keys.');
  report.checks.push('Original A/A/B/1 assignment and Back-key journey produce identical complete campaigns in Classic and both graphical layouts.');
  assert.deepEqual(report.pageErrors, []);
  assert.deepEqual(report.consoleErrors, []);
  assert.deepEqual(report.failedRequests, []);
  report.status = 'passed';
} catch (error) {
  report.status = 'failed';
  report.error = String(error.stack ?? error);
  throw error;
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  await browser.close();
}
