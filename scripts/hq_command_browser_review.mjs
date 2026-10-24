// Original HQ readers reached from contextual controls in disposable campaigns.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertQaUrl, chromiumLaunchOptions, observeMainScript, waitForSemantics, waitForUiSettled } from './browser_support.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const value = (flag, fallback) => args.includes(flag) ? args[args.indexOf(flag) + 1] : fallback;
const url = assertQaUrl(value('--url', 'http://127.0.0.1:18879/'));
const output = resolve(root, value('--out', `.local/reports/hq-commands-${Date.now()}`));
await mkdir(output, { recursive: true });
const expectedHash = value('--expected-hash', null);
assert.ok(expectedHash, 'Supply the exact compiled JavaScript hash.');
const hash = createHash('sha256').update(Buffer.from(await (await fetch(new URL('main.dart.js', url))).arrayBuffer())).digest('hex');
assert.equal(hash, expectedHash.toLowerCase());
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const decode = save => typeof save.saveData === 'string' ? JSON.parse(save.saveData) : save.saveData;
const original = JSON.parse(await readFile(resolve(root, 'upstream/test/saves/felix_1_0.json'), 'utf8'));
const fixture = decode(original);
const sleeper = structuredClone(fixture.lcs.pool[0]);
Object.assign(sleeper, { id: fixture.nextCreatureId++, name: 'Prepared sleeper', squadId: null,
  sleeperAgent: true, activity: { type: 'none' } });
fixture.lcs.pool.push(sleeper);
original.saveData = typeof original.saveData === 'string' ? JSON.stringify(fixture) : fixture;
const fixturePath = resolve(output, 'prepared-sleeper-fixture.json');
await writeFile(fixturePath, JSON.stringify(original));
const report = { status: 'running', mainJsSha256: hash, checks: [], screenshots: [], pageErrors: [],
  scope: 'Bundled Felix campaign plus one explicitly prepared sleeper. No day advances. Contextual pointer entry, original keyboard choices/cancellation, whole-campaign exports, retained People search, and desktop/enlarged bounds.' };
const browser = await chromium.launch(chromiumLaunchOptions({ args }));
try {
  for (const layout of [{ width: 1440, height: 1000, reading: '100%' }, { width: 1024, height: 720, reading: '150%' }]) {
    const name = `${layout.width}-${layout.reading}`;
    const context = await browser.newContext({ viewport: { width: layout.width, height: layout.height }, acceptDownloads: true });
    const page = await context.newPage();
    const verifyLoaded = observeMainScript(page, report);
    page.on('pageerror', error => report.pageErrors.push(String(error)));
    const wait = pattern => waitForSemantics(page, pattern);
    const key = async input => { await page.keyboard.press(input); await waitForUiSettled(page); };
    const click = async pattern => {
      await page.mouse.move(1, 1);
      await page.getByRole('button', { name: pattern }).first().click();
      await page.mouse.move(1, 1);
      await waitForUiSettled(page);
    };
    const capture = async label => {
      await waitForUiSettled(page);
      const file = `${name}-${label}.png`;
      await page.screenshot({ path: resolve(output, file), fullPage: true });
      report.screenshots.push(file);
    };
    const visible = async pattern => {
      const box = await page.getByRole('button', { name: pattern }).first().boundingBox();
      assert.ok(box && box.x >= 0 && box.y >= 0 && box.x + box.width <= layout.width + 1
        && box.y + box.height <= layout.height + 1, `Visible contextual command: ${pattern}`);
    };
    const exportGame = async label => {
      await click(/^Save & exit/);
      await wait(/Start a New Game/);
      await click(/^Load & Manage Saves/);
      await click(/^A(?:\s|$)/);
      const downloading = page.waitForEvent('download');
      await click(/Export Save File/);
      const path = resolve(output, `${name}-${label}.json`);
      await (await downloading).saveAs(path);
      const data = decode(JSON.parse(await readFile(path, 'utf8')));
      await click(/^L Load Game/);
      await wait(/Save & exit/);
      return data;
    };
    try {
      await page.goto(url, { waitUntil: 'domcontentloaded' });
      await wait(/Start a New Game/);
      const choosing = page.waitForEvent('filechooser');
      await click(/^Import a Save/);
      await (await choosing).setFiles(fixturePath);
      await wait(/Save imported/);
      await key('Enter');
      await click(/^Load & Manage Saves/);
      await click(/^A(?:\s|$)/);
      await click(/^L Load Game/);
      await wait(/Save & exit/);
      await click(/^Reading size/);
      await page.getByRole('menuitem', { name: layout.reading, exact: true }).click();
      const before = await exportGame('before');
      await visible(/^Reorder$/);
      await capture('roster');
      await click(/^Reorder$/);
      await wait(/Choose squad member to move/);
      await key('Escape');
      await click(/^Reorder$/);
      await key('1');
      await wait(/Choose squad member to replace/);
      await capture('reorder-target');
      await key('Escape');
      assert.deepEqual(await exportGame('after-reorder-cancel'), before);
      await click(/^People(?:\.|$)/);
      const search = page.getByRole('textbox', { name: /Find anyone/ });
      await search.click();
      await waitForUiSettled(page);
      await key('Control+A');
      await page.keyboard.type(before.lcs.pool[0].name);
      await page.waitForFunction(value => [...document.querySelectorAll('input,textarea')]
        .some(node => node === document.activeElement && node.value === value), before.lcs.pool[0].name);
      await waitForUiSettled(page);
      await visible(/^Bulk crew orders$/);
      await capture('people');
      await click(/^Bulk crew orders$/);
      await wait(/Assign Tasks in Bulk/);
      await visible(/^Community Service$/);
      await visible(new RegExp(`^${before.lcs.pool[0].name}\\b`));
      await click(/^Details$/);
      await wait(/How|Community Service/);
      await key('Escape');
      await capture('crew-picker');
      await key('Escape');
      await key('Escape');
      await click(/^People(?:\.|$)/);
      const retainedSearch = page.getByRole('textbox', { name: /Find anyone/ });
      await retainedSearch.click();
      await waitForUiSettled(page);
      assert.ok(await retainedSearch.evaluate(node => node === document.activeElement
        || node.contains(document.activeElement)), 'Read the active native search editor.');
      assert.equal(await retainedSearch.inputValue(), before.lcs.pool[0].name);
      await click(/^Bulk crew orders$/);
      await key('8');
      await click(new RegExp(`^${before.lcs.pool[0].name}\\b`));
      const expected = structuredClone(before);
      expected.lcs.pool[0].activity = { type: 'stealCars' };
      assert.deepEqual(await exportGame('after-crew-order'), expected);
      await click(/^Network(?:\.|$)/);
      await visible(/^Bulk sleeper orders$/);
      await capture('network');
      await click(/^Bulk sleeper orders$/);
      await wait(/Activate Sleeper Agents in Bulk/);
      await visible(/^Lay Low$/);
      await visible(/^Prepared sleeper\b/);
      await capture('sleeper-picker');
      await key('Escape');
      await key('Escape');
      await click(/^Network(?:\.|$)/);
      await click(/^Bulk sleeper orders$/);
      await key('2');
      await click(/^Prepared sleeper\b/);
      expected.lcs.pool.find(person => person.id === sleeper.id).activity = { type: 'sleeperLiberal' };
      assert.deepEqual(await exportGame('after-sleeper-order'), expected);
      await key('Alt+o');
      await wait(/Campaign options/);
      await click(/^Change movement slogan$/);
      await wait(/What is your new slogan/);
      await page.getByRole('textbox').first().fill('A prepared browser slogan');
      await key('Enter');
      expected.lcs.slogan = 'A prepared browser slogan';
      assert.deepEqual(await exportGame('after-slogan'), expected);
      await verifyLoaded(hash);
      report.checks.push({ layout, result: 'passed', campaignPreservation: true });
    } catch (error) {
      await capture('failure').catch(() => {});
      throw error;
    } finally { await context.close(); }
  }
  assert.deepEqual(report.pageErrors, []);
  report.status = 'passed';
} catch (error) {
  report.status = 'failed';
  report.error = String(error.stack ?? error);
  throw error;
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  await browser.close();
  console.log(`${report.status}: ${resolve(output, 'report.json')}`);
}
