// Isolated browser acceptance for journal reports and the original profile reader.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const url = process.argv[2] || 'http://127.0.0.1:8766/';
const output = resolve(root, 'reports/journal-screen-audit/browser');
await mkdir(output, { recursive: true });
const fixture = JSON.parse(await readFile(resolve(root, 'upstream/test/saves/felix_1_0.json'), 'utf8'));
const original = typeof fixture.saveData === 'string' ? JSON.parse(fixture.saveData) : fixture.saveData;
const served = await fetch(new URL('main.dart.js', url));
const report = {
  url, status: 'running', checks: [], errors: [],
  mainJsSha256: createHash('sha256').update(Buffer.from(await served.arrayBuffer())).digest('hex'),
};
const browser = await chromium.launch({ channel: 'msedge', headless: true });
let context, page;
async function text() {
  return page.locator('flt-semantics-host').evaluate(host =>
    [host.innerText, ...[...host.querySelectorAll('[aria-label]')].map(n => n.getAttribute('aria-label'))].join('\n'));
}
async function wait(pattern) {
  const until = Date.now() + 20000;
  while (Date.now() < until) {
    if (await page.locator('flt-semantics-host').count() && pattern.test(await text())) return;
    await page.waitForTimeout(100);
  }
  throw new Error(`Missing ${pattern}: ${await text()}`);
}
async function click(pattern) {
  await page.getByRole('button', { name: pattern }).first().click();
  await page.waitForTimeout(250);
}
async function shot(name) {
  await page.mouse.move(2, 2);
  await page.screenshot({ path: resolve(output, name + '.png'), fullPage: true });
  await writeFile(resolve(output, name + '.txt'), await text());
}
async function loadScenario(activity) {
  if (context) await context.close();
  context = await browser.newContext({ viewport: { width: 1600, height: 1000 } });
  page = await context.newPage();
  page.on('pageerror', error => report.errors.push(error.message));
  const file = structuredClone(fixture), data = structuredClone(original);
  for (const person of data.lcs.pool) person.activity = { type: 'none' };
  data.lcs.pool[0].activity = { type: activity };
  if (activity === 'clinic') data.lcs.pool[0]._blood = 0.2;
  data.lcs.squads[0].activity = { type: 'none' };
  const path = resolve(output, activity + '-fixture.json');
  file.saveData = data;
  await writeFile(path, JSON.stringify(file));
  await page.goto(url, { waitUntil: 'networkidle' });
  await wait(/Start a new movement|Start a New Game/);
  const chooser = page.waitForEvent('filechooser');
  await click('Import a Save');
  await (await chooser).setFiles(path);
  await wait(/Save imported/);
  await page.keyboard.press('Enter');
  await wait(/Start a new movement|Start a New Game/);
  await click('Load & Manage Saves');
  await click(/^A(?:\s|$)/);
  await wait(/Manage .*Saved Game/);
  await click(/^L Load Game/);
  await wait(/Organisation/);
  await page.getByRole('button', { name: 'Save & exit', exact: true }).waitFor();
}
try {
  await loadScenario('stealCars');
  await page.keyboard.press('1');
  await page.waitForTimeout(200);
  await page.keyboard.press('1');
  await wait(/Continue the Struggle/);
  await page.keyboard.press('ArrowDown');
  await wait(/Skills & training/);
  await shot('personnel-skills');
  report.checks.push('Original numbered personnel reader renders native dossier and skill page.');
  await click(/Continue the Struggle/);
  await click(/Carry out (?:your )?plans|Run day|Wait a day/i);
  await wait(/What type of car/);
  await shot('vehicle-list');
  await page.keyboard.press('a');
  await wait(/looks around for an accessible vehicle/);
  assert.match(await text(), /Vehicle report/);
  assert.doesNotMatch(await text(), /Transp:|Top Skills:|=== ACTIVISM ===/);
  await shot('vehicle-report');
  await click(/^Continue/);
  await wait(/Vehicle report/);
  await shot('vehicle-found');
  await click(/^Continue/);
  await wait(/Approach the driver/);
  await shot('vehicle-decision');
  report.checks.push('Real next-day car-theft list, two acknowledgements and subsequent decision render in journal.');

  await loadScenario('clinic');
  await click(/Carry out (?:your )?plans|Run day|Wait a day/i);
  await wait(/Hospital admission/);
  assert.doesNotMatch(await text(), /Transp:|Top Skills:|=== ACTIVISM ===/);
  await shot('hospital-admission');
  await page.setViewportSize({ width: 800, height: 600 });
  await page.waitForTimeout(300);
  await shot('hospital-admission-small');
  report.checks.push('Actual clinic activity produces a clean admission report at large and small sizes.');
  assert.deepEqual(report.errors, []);
  report.status = 'passed';
} catch (error) {
  report.status = 'failed';
  report.failure = error.stack;
  if (page) await shot('failure').catch(() => {});
  process.exitCode = 1;
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  await browser.close();
  console.log(JSON.stringify(report, null, 2));
}
