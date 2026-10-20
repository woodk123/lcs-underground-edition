// Keyboard-only task sequences in the actual graphical and Classic readers.
// Fixture import/export and changing display preferences are explicit setup.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertQaUrl, chromiumLaunchOptions, observeMainScript } from './browser_support.mjs';

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
  scope: 'Unmodified bundled Felix save in disposable profiles. Original LCS L/M/Escape/W/X menu meanings and source-first labels, optional modified journal-tab and Save exit shortcuts, modal isolation, and the identical immediate A/A/B/1 assignment and source Back keys in graphical desktop, graphical compact 800x600/150%, and Classic. Pointer task previews retain separate draft cancellation and day-advance protection. Import/export and preference changes are setup. No day advances, outcomes or skill values are supplied.',
  checks: [], screenshots: [], sequences: [], pageErrors: [], consoleErrors: [], failedRequests: [],
};
const expected = value('--expected-hash', null);
assert.match(expected ?? '', /^[a-f0-9]{64}$/i, 'An exact compiled build hash is required.');
report.mainJsSha256 = digest(Buffer.from(await (await fetch(new URL('main.dart.js', url))).arrayBuffer()));
assert.equal(report.mainJsSha256, expected.toLowerCase());
const browser = await chromium.launch(chromiumLaunchOptions({ args }));

async function runScenario({ name, viewport, compact, classic }) {
  const context = await browser.newContext({ viewport, acceptDownloads: true });
  const page = await context.newPage();
  const verifyLoaded = observeMainScript(page, report);
  page.on('pageerror', error => report.pageErrors.push(String(error)));
  page.on('console', message => { if (message.type() === 'error') report.consoleErrors.push(message.text()); });
  page.on('requestfailed', request => report.failedRequests.push(request.url()));
  const text = () => page.locator('flt-semantics-host').evaluate(host => [host.innerText,
    ...[...host.querySelectorAll('[aria-label]')].map(node => node.getAttribute('aria-label')),
  ].filter(Boolean).join('\n'));
  async function wait(pattern) {
    const deadline = Date.now() + 20000;
    while (Date.now() < deadline) {
      if (await page.locator('flt-semantics-host').count() && pattern.test(await text())) return;
      await page.waitForTimeout(100);
    }
    throw new Error(`Missing ${pattern}: ${await text()}`);
  }
  async function click(pattern, locator = page) {
    await locator.getByRole('button', { name: pattern }).first().click();
    await page.mouse.move(1, 1);
    await page.waitForTimeout(200);
  }
  async function key(key) {
    await page.keyboard.press(key);
    await page.waitForTimeout(220);
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
    await page.goto(url, { waitUntil: 'networkidle' });
    await wait(/Start a New Game/);
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
      await page.reload({ waitUntil: 'networkidle' });
      await wait(/Start a New Game/);
      await click(/^Interface preferences/);
      assert.equal(await page.getByRole('checkbox', { name: 'Compact', exact: true }).getAttribute('aria-checked'), 'true');
      assert.equal(await page.getByRole('switch', { name: /^Show explanations/ }).getAttribute('aria-checked'), 'false');
      await key('Escape');
      report.checks.push(`${name}: display preferences survive reload`);
    }
    await verifyLoaded(expected.toLowerCase());
    return { before, after };
  } finally {
    await context.close();
  }
}

try {
  const desktop = await runScenario({ name: 'graphical-desktop', viewport: { width: 1440, height: 1000 }, compact: false, classic: false });
  const compact = await runScenario({ name: 'graphical-compact', viewport: { width: 800, height: 600 }, compact: true, classic: false });
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
