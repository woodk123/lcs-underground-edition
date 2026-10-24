// Screen-by-screen acceptance against an isolated compiled QA player.
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
const arg = (key, fallback) => args.includes(key) ? args[args.indexOf(key) + 1] : fallback;
const url = assertQaUrl(arg('--url', undefined));
const output = resolve(root, arg('--out', 'reports/screens-browser'));
await mkdir(output, { recursive: true });
const expected = arg('--expected-hash', '');
assert.match(expected, /^[a-f0-9]{64}$/i);
const actual = createHash('sha256').update(Buffer.from(await (await fetch(new URL('main.dart.js', url))).arrayBuffer())).digest('hex');
assert.equal(actual, expected);
const envelope = JSON.parse(await readFile(resolve(root, 'upstream/test/saves/felix_1_0.json'), 'utf8'));
const state = typeof envelope.saveData === 'string' ? JSON.parse(envelope.saveData) : envelope.saveData;
for (const person of state.lcs.pool) {
  person.wantedForCrimes = Object.fromEntries(Object.keys(person.wantedForCrimes).map(key => [key, 0]));
  person.heat = 0;
  person.activity = { type: 'none' };
}
state.newsArchive = Array.from({ length: 25 }, (_, i) => ({
  type: 'majorEvent', headline: `Prepared screen review report ${i + 1}`,
  body: `Full archived article ${i + 1}.\n\n${'This is declared QA archive text for navigation and reading checks. '.repeat(20)}`,
  byline: 'QA archive fixture', publicationName: 'The Times', publicationAlignment: 'moderate',
  _date: '2023-01-03T00:00:00.000', effects: { freeSpeech: 2.5, lcsLiked: -0.25 }, unread: true,
}));
state.lcs.vehiclePool = [{ id: state.nextVehicleId++, typeName: 'JEEP', color: 'Red', year: 2020, heat: 0, locationId: state.lcs.pool[0].baseId }];
envelope.saveData = typeof envelope.saveData === 'string' ? JSON.stringify(state) : state;
const fixture = resolve(output, 'prepared-peaceful-campaign.json');
await writeFile(fixture, JSON.stringify(envelope));
const report = { status: 'running', expectedHash: expected, prepared: 'Copy of bundled Felix campaign with charges, heat and individual orders cleared, one parked Jeep and twenty-five explicitly prepared archive articles. Player storage is never used.', screens: [], failures: [], pageErrors: [], consoleErrors: [] };
const browser = await chromium.launch(chromiumLaunchOptions({ args }));
const large = args.includes('--large');
const context = await browser.newContext({ viewport: large ? { width: 1024, height: 720 } : { width: 1440, height: 1000 }, acceptDownloads: true });
const page = await context.newPage();
const verifyLoadedScript = observeMainScript(page, report);
page.setDefaultTimeout(7000);
page.on('pageerror', error => report.pageErrors.push(String(error)));
page.on('console', message => { if (message.type() === 'error') report.consoleErrors.push(message.text()); });
async function text() {
  return page.locator('flt-semantics-host').evaluate(host => [host.innerText, ...[...host.querySelectorAll('[aria-label]')].map(node => node.getAttribute('aria-label'))].join('\n'));
}
async function wait(pattern) {
  await page.waitForFunction(source => {
    const host = document.querySelector('flt-semantics-host');
    return host && new RegExp(source, 'i').test([host.innerText, ...[...host.querySelectorAll('[aria-label]')].map(n => n.getAttribute('aria-label'))].join('\n'));
  }, pattern.source, { timeout: 25000 });
}
const topTabs = ['Organisation', 'People', 'Network', 'Bases', 'Ledger', 'Justice', 'Agenda', 'Newspaper', 'Reports', 'City maps', 'Options'];
async function revealTopTab(name) {
  if (!large || !topTabs.some(label => name instanceof RegExp ? name.test(label) : name === label)) return;
  const viewport = page.viewportSize();
  const guide = page.getByRole('button', { name: /^Field guide(?:$|\s)/ }).first();
  const guideBounds = await guide.count() ? await guide.boundingBox() : null;
  const stripRight = guideBounds?.x ?? viewport.width - 120;
  const target = page.getByRole('button', { name }).first();
  async function visible() {
    if (!await target.count()) return false;
    const bounds = await target.boundingBox();
    return bounds && bounds.y >= 0 && bounds.y < 100 && bounds.x >= 0 && bounds.x + bounds.width <= stripRight + 1;
  }
  if (await visible()) return;
  // Traverse real controls so Flutter brings focused tabs into view. Horizontal
  // wheel gestures at the strip's edge can invoke native browser history.
  for (let step = 0; step < 120; step++) {
    if (await visible()) return;
    await page.keyboard.press('Tab');
    await page.waitForTimeout(60);
  }
  if (await visible()) return;
  assert.fail(`The top tab ${String(name)} must be reachable through its horizontal strip.`);
}
async function click(name) {
  await revealTopTab(name);
  const control = page.getByRole('button', { name })
    .or(page.getByRole('checkbox', { name })).first();
  await control.click();
  await page.mouse.move(2, 2);
  await page.waitForTimeout(250);
}
async function screen(id) {
  if (large && !await page.getByRole('dialog').count() && !await page.getByRole('alertdialog').count()) {
    const reading = page.getByRole('button', { name: /^Reading size/ }).first();
    if (await reading.count()) {
      await reading.click();
      await page.getByRole('menuitem', { name: '150%', exact: true }).click();
    }
  }
  await page.waitForTimeout(250);
  const controls = await page.getByRole('button').evaluateAll(nodes => nodes.map(node => ({ name: node.getAttribute('aria-label') || node.innerText, disabled: node.getAttribute('aria-disabled') === 'true' })));
  const body = await text();
  assert.doesNotMatch(body, /A RenderFlex overflowed|Unhandled exception|Error: Unexpected/i);
  await page.screenshot({ path: resolve(output, `${id}.png`), fullPage: true });
  await writeFile(resolve(output, `${id}.txt`), body);
  report.screens.push({ id, viewport: page.viewportSize(), controls, screenshot: `${id}.png` });
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  console.log(`PASS ${id}`);
}
async function visibleModal(role, closeName) {
  const dialog = page.getByRole(role).filter({ has: page.getByRole('button', { name: closeName, exact: true }) }).last();
  await dialog.waitFor({ state: 'visible' });
  const close = dialog.getByRole('button', { name: closeName, exact: true }).last();
  await close.waitFor({ state: 'visible' });
  assert.ok(await close.isEnabled(), `${closeName} must be enabled in the current modal.`);
  return { dialog, close };
}
async function hq() {
  await page.reload({ waitUntil: 'domcontentloaded' });
  await wait(/Start a New Game/);
  const resume = page.getByRole('button', { name: /^Continue as/ });
  if (await resume.count() && await resume.isEnabled()) {
    await click(/^Continue as/);
  } else {
    await click(/^Load & Manage Saves/); await click(/^A(?:\s|$)/);
    await click(/^L Load Game/);
  }
  await wait(/Save & exit/);
}
async function journey(id, action) {
  try { await action(); }
  catch (error) {
    report.failures.push({ id, error: String(error), text: await text().catch(() => '') });
    await page.screenshot({ path: resolve(output, `${id}-FAILED.png`), fullPage: true });
    console.log(`FAIL ${id}: ${error}`);
  }
}
try {
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await wait(/Start a New Game/);
  await screen('title-no-saves');
  await journey('title-options', async () => {
    await click(/^Gameplay Options/); await screen('options');
    await click(/^I.*Interface Options/); await screen('interface-options');
    await click(/^B.*Back to Options/);
    await click(/^C.*Content and Tone/); await screen('content-tone-options');
    await click(/^B.*Back to Options/); await click(/^B.*Back to Title/);
  });
  await page.reload({ waitUntil: 'domcontentloaded' }); await wait(/Start a New Game/);
  await journey('changelog', async () => { await click(/^View Changelog/); await screen('changelog'); });
  await page.reload({ waitUntil: 'domcontentloaded' }); await wait(/Start a New Game/);
  const choosing = page.waitForEvent('filechooser'); await click(/^Import a Save/);
  await (await choosing).setFiles(fixture); await wait(/Save imported/); await page.keyboard.press('Enter'); await wait(/Start a New Game/);
  await screen('title-with-save');
  await click(/^Load & Manage Saves/); await screen('save-list');
  await click(/^A(?:\s|$)/); await screen('save-actions');
  await click(/^D.*Delete Save/); await screen('save-delete-confirmation');
  await click(/^N.*No/);
  await hq(); await screen('headquarters');
  for (const tab of ['Organisation', 'People', 'Network', 'Bases', 'Ledger', 'Justice', 'Agenda', 'Newspaper', 'Reports', 'City maps', 'Options']) {
    await journey(`tab-${tab}`, async () => {
      await hq(); await click(new RegExp(`^${tab}(?:$|[.\\s])`)); await screen(`tab-${tab.toLowerCase().replaceAll(' ', '-')}`);
    });
  }
  for (const rail of ['All people', 'Vehicles', 'Equipment', 'Orders', 'Assign to squads']) {
    await journey(`rail-${rail}`, async () => {
      await hq(); await click(new RegExp(`^${rail}(?:$|[.\\s])`)); await screen(`rail-${rail.toLowerCase().replaceAll(' ', '-')}`);
    });
  }
  await journey('people-scopes', async () => {
    await hq(); await click(/^People(?:$|[.\s])/);
    await click(/^Leadership$/); await screen('people-leadership');
    await click(/^Captives$/); await screen('people-captives');
    await click(/^All people$/); await screen('people-directory');
  });
  await journey('media-production', async () => {
    await hq(); await click(/^Newspaper(?:$|\s)/);
    await click(/^Production$/); await wait(/Liberal Guardian production/);
    await screen('newspaper-production');
    await click(/^Archive$/);
  });
  await journey('agenda-pages', async () => {
    await hq(); await click(/^Agenda(?:$|\s)/);
    for (let i = 1; i <= 5; i++) {
      await screen(`agenda-page-${i}`);
      await click(/^Next page$/);
    }
    await click(/^Disband and Wait/); await screen('disband-confirmation');
    await page.keyboard.press('Escape');
  });
  await journey('ledger-guide', async () => {
    await hq(); await click(/^Ledger(?:$|\s)/);
    await click(/^Money & ledger guide/);
    const guide = await visibleModal('dialog', 'Close decision guide');
    await screen('ledger-guide');
    await page.keyboard.press('Escape');
    await guide.dialog.waitFor({ state: 'hidden' });
  });
  await journey('archive-article-pages', async () => {
    await hq(); await click(/^Newspaper(?:$|\s)/);
    await click(/^Archive$/);
    await screen('newspaper-populated');
    await click(/^(?:Unread\. )?Prepared screen review report 25/); await screen('newspaper-full-article');
    await click(/^Continue$|^Back to reports$/);
    const next = page.getByRole('button', { name: /Next/ }).first();
    assert.ok(await next.count(), 'Prepared archive must expose another page');
    await next.click(); await screen('newspaper-next-page');
    await click(/^Public opinion guide/);
    const guide = await visibleModal('dialog', 'Close decision guide');
    await screen('public-opinion-guide');
    await page.keyboard.press('Escape');
    await guide.dialog.waitFor({ state: 'hidden' });
  });
  await journey('dossier-all-pages', async () => {
    await hq(); await click(/^Inspect Felix Kobayashi(?:$|\s)/); await screen('crew-inspector');
    await click(/^Full dossier/);
    const dossier = await visibleModal('dialog', 'Close dossier');
    for (const name of ['Overview', 'Skills', 'Campaign record']) {
      await click(new RegExp(`^${name}$`)); await screen(`dossier-${name.toLowerCase().replaceAll(' ', '-')}`);
    }
    await dossier.close.click();
    await dossier.dialog.waitFor({ state: 'hidden' });
  });
  await journey('people-sort', async () => {
    await hq(); await click(/^People(?:$|[.\s])/);
    await click(/^Sort & reorder crew/);
    await click(/^T Sort Liberals/); await screen('people-sort');
    await page.keyboard.press('Escape');
    await click(/^Z Reorder Liberals/); await screen('people-reorder');
    await page.keyboard.press('Escape');
  });
  for (const category of ['Business', 'Personnel', 'Activism', 'Operations']) {
    await journey(`orders-${category}`, async () => {
      await hq(); await click(/^Orders(?:$|\s)/); await click(new RegExp(`^${category}(?:$|\\s)`));
      await screen(`orders-${category.toLowerCase()}`);
      const choices = await page.getByRole('button', { name: /^Prepare / }).allTextContents();
      report.screens.at(-1).availablePreparations = choices;
    });
  }
  await journey('headquarters-command-menu', async () => {
    await hq(); await click(/^HQ commands/); await screen('headquarters-command-menu');
    await page.keyboard.press('Escape');
  });
  await journey('field-guide', async () => {
    await hq(); await click(/^Field guide/);
    const guide = await visibleModal('alertdialog', 'Back to the game');
    await screen('field-guide');
    await guide.close.click();
    await guide.dialog.waitFor({ state: 'hidden' });
  });
  await journey('classic-view', async () => {
    await hq(); await click(/^Switch readable \/ classic view/); await screen('classic-headquarters');
    await click(/^Switch readable \/ classic view/);
  });
  await journey('save-delete-and-empty', async () => {
    await hq(); await click(/^Save & exit/); await wait(/Start a New Game/);
    await click(/^Load & Manage Saves/); await click(/^A(?:\s|$)/);
    await click(/^D.*Delete Save/); await click(/^Y.*Yes/);
    await screen('save-empty-after-deletion');
  });
  await journey('invalid-import', async () => {
    await page.reload({ waitUntil: 'domcontentloaded' }); await wait(/Start a New Game/);
    const invalid = resolve(output, 'deliberately-invalid.json');
    await writeFile(invalid, '{ invalid campaign JSON');
    const chooser = page.waitForEvent('filechooser'); await click(/^Import a Save/);
    await (await chooser).setFiles(invalid);
    await page.waitForTimeout(500); await screen('invalid-import-error');
    await page.keyboard.press('Enter');
  });
  await verifyLoadedScript(expected.toLowerCase());
  report.status = report.failures.length || report.pageErrors.length || report.consoleErrors.length ? 'failed' : 'passed';
} catch (error) {
  report.status = 'failed';
  report.failures.push({ id: 'startup', error: String(error) });
  console.log(`FAIL startup: ${error}`);
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  await browser.close();
}
console.log(JSON.stringify({ status: report.status, screens: report.screens.length, failures: report.failures.length, output }));
if (report.status !== 'passed') process.exitCode = 1;
