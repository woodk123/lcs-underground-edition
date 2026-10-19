// Compare the Discord interface feedback in isolated, disposable campaigns.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertQaUrl, chromiumLaunchOptions, observeMainScript } from './browser_support.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const args = process.argv.slice(2);
const arg = (flag, fallback) => args.includes(flag) ? args[args.indexOf(flag) + 1] : fallback;
const url = assertQaUrl(arg('--url', undefined));
const output = resolve(root, arg('--out', 'reports/discord-feedback/after'));
const baseline = args.includes('--before');
const large = args.includes('--large');
await mkdir(output, { recursive: true });
const envelope = JSON.parse(await readFile(resolve(root, 'upstream/test/saves/felix_1_0.json'), 'utf8'));
const state = typeof envelope.saveData === 'string' ? JSON.parse(envelope.saveData) : envelope.saveData;
for (const person of state.lcs.pool) {
  person.wantedForCrimes = Object.fromEntries(Object.keys(person.wantedForCrimes).map(key => [key, 0]));
  person.heat = 0;
  person.activity = { type: 'none' };
}
for (const name of ['Casey Rivers', 'Robin Vale']) {
  const recruit = structuredClone(state.lcs.pool.at(-1));
  Object.assign(recruit, { id: state.nextCreatureId++, name, properName: name, squadId: null, hireId: null });
  state.recruitmentSessions.push({ recruit, recruiter: state.lcs.pool[0].id, rawEagerness: 3 });
}
envelope.saveData = typeof envelope.saveData === 'string' ? JSON.stringify(state) : state;
const fixture = resolve(output, 'prepared-campaign.json');
await writeFile(fixture, JSON.stringify(envelope));
const report = {
  status: 'running', url, baseline, large,
  prepared: 'Bundled Felix campaign with heat, crimes and personal orders cleared and two explicitly supplied follow-up prospects. Screenshots are prepared UI scenarios, not earned recruitment outcomes.',
  mainJsSha256: arg('--expected-hash', ''), checks: [], screenshots: [],
  pageErrors: [], consoleErrors: [], failedRequests: [], externalFontRequests: [],
};
const browser = await chromium.launch(chromiumLaunchOptions({ args }));
const context = await browser.newContext({ viewport: large ? { width: 800, height: 600 } : { width: 1440, height: 1000 }, acceptDownloads: true });
const page = await context.newPage();
page.setDefaultTimeout(12000);
const verify = observeMainScript(page, report);
page.on('pageerror', error => report.pageErrors.push(String(error)));
page.on('console', msg => { if (msg.type() === 'error') report.consoleErrors.push(msg.text()); });
page.on('requestfailed', req => report.failedRequests.push(req.url()));
page.on('request', req => { if (/fonts\.gstatic\.com|fonts\.googleapis\.com/.test(req.url())) report.externalFontRequests.push(req.url()); });
async function text() {
  return page.locator('flt-semantics-host').evaluate(host => [host.innerText, ...[...host.querySelectorAll('[aria-label]')].map(n => n.getAttribute('aria-label'))].join('\n'));
}
async function wait(pattern) {
  await page.waitForFunction(source => {
    const host = document.querySelector('flt-semantics-host');
    return host && new RegExp(source, 'i').test([host.innerText, ...[...host.querySelectorAll('[aria-label]')].map(n => n.getAttribute('aria-label'))].join('\n'));
  }, pattern.source, { timeout: 30000 });
}
async function click(name) {
  await page.getByRole('button', { name }).first().click();
  await page.mouse.move(2, 2);
  await page.waitForTimeout(250);
}
async function capture(name) {
  await page.waitForTimeout(250);
  await page.screenshot({ path: resolve(output, `${name}.png`), fullPage: true });
  await writeFile(resolve(output, `${name}.txt`), await text());
  report.screenshots.push(`${name}.png`);
  report.checks.push(name);
  console.log(`PASS ${name}`);
}
async function exportGame(name) {
  await click(/^Save & exit/); await wait(/Start a New Game/);
  await click(/^Load & Manage Saves/); await click(/^A(?:\s|$)/);
  const downloading = page.waitForEvent('download');
  await click(/Export Save File/);
  const path = resolve(output, `${name}.json`);
  await (await downloading).saveAs(path);
  const save = JSON.parse(await readFile(path, 'utf8'));
  await click(/^L Load Game/); await wait(/Save & exit/);
  return typeof save.saveData === 'string' ? JSON.parse(save.saveData) : save.saveData;
}
try {
  await page.goto(url, { waitUntil: 'networkidle' }); await wait(/Start a New Game/);
  const choosing = page.waitForEvent('filechooser'); await click(/^Import a Save/);
  await (await choosing).setFiles(fixture); await wait(/Save imported/);
  await page.keyboard.press('Enter'); await wait(/Start a New Game/);
  await click(/^Load & Manage Saves/); await click(/^A(?:\s|$)/); await click(/^L Load Game/);
  await wait(/Save & exit/);
  if (large) {
    await click(/^Reading size/); await page.getByRole('menuitem', { name: '150%', exact: true }).click();
  }
  const before = await exportGame('before-inspection');
  await capture('organisation');
  await click(/^Inspect Felix Kobayashi(?:$|\s)/);
  await capture('character-summary');
  await click(/^Full dossier/); await capture('character-overview');
  await click(/^Skills$/); await capture('character-skills');
  await page.keyboard.press('Escape');
  await page.keyboard.press('Escape');
  const after = await exportGame('after-inspection');
  assert.deepEqual(after, before, 'Character inspection must preserve the complete campaign.');
  report.checks.push('inspection preserves complete campaign');
  await page.keyboard.press('F1'); await capture('keyboard-guide');
  await page.keyboard.press('Escape');
  await page.keyboard.press('f'); await wait(/Select a destination/);
  await capture('visit-keyboard');
  await page.keyboard.press('Escape'); await wait(/Save & exit/);
  await click(/^City maps(?:$|[.\s])/);
  await click(/^Shopping(?:$|[.\s])/);
  await click(/Marx.s Department Store/);
  await capture('visit-destination');
  if (baseline) {
    await click(/^Prepare visit$/); await capture('visit-confirmation');
  } else {
    await click(/^Queue visit/); await wait(/Visit queued/);
    await capture('visit-queued');
    const queued = await exportGame('queued-visit');
    assert.equal(queued.date, before.date, 'Queuing a visit never advances the day.');
    assert.equal(queued.lcs.squads.find(s => s.id === before.lcs.squads[0].id).activity.type, 'visit');
    report.checks.push('single action queues original visit without advancing time');
    await click(/^Organisation(?:$|[.\s])/);
    await click(/Cancel departure/i);
    await capture('visit-cancelled');
    assert.deepEqual(await exportGame('cancelled-visit'), before,
      'Cancelling a queued departure restores the original complete campaign.');
    report.checks.push('cancel queued departure preserves original campaign');
  }
  await verify(report.mainJsSha256);
  if (!baseline) assert.deepEqual(report.externalFontRequests.filter(url => /\/roboto\//i.test(url)), [],
    'Use the bundled default Roboto font without an external download.');
  assert.deepEqual(report.pageErrors, []); assert.deepEqual(report.consoleErrors, []); assert.deepEqual(report.failedRequests, []);
  report.status = 'passed';
} catch (error) {
  report.status = 'failed'; report.error = String(error);
  report.lastText = await text().catch(() => '');
  await page.screenshot({ path: resolve(output, 'FAILED.png') });
  throw error;
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  await browser.close();
}
