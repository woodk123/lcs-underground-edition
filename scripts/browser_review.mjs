// Isolated browser regression checks for dossiers, order details and portrait
// migration. Synthetic fixture edits never touch player saves.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const args = process.argv.slice(2);
const value = (flag, fallback) => args.includes(flag) ? args[args.indexOf(flag) + 1] : fallback;
const url = value('--url', 'http://127.0.0.1:18879/');
const output = resolve(root, value('--out', `reports/browser-review-${new Date().toISOString().replaceAll(':', '-')}`));
await mkdir(output, { recursive: true });
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const decode = save => typeof save.saveData === 'string' ? JSON.parse(save.saveData) : save.saveData;
const original = JSON.parse(await readFile(resolve(root, 'upstream/test/saves/felix_1_0.json'), 'utf8'));
const fixture = decode(original);
const actor = fixture.lcs.pool[0];
actor.birthDate = `${Number(fixture.date.slice(0, 4)) - 22}-01-01T00:00:00.000`;
actor.portraitId = 13; // Deliberately mismatched visual-age-68 illustration.
actor.portraitAssignedAge = 22;
actor.rawSkill.art = 12;
actor.rawSkillXP.art = 25;
actor.rawAttributes.heart = 14;
original.saveData = typeof original.saveData === 'string' ? JSON.stringify(fixture) : fixture;
const fixturePath = resolve(output, 'synthetic-age22.json');
await writeFile(fixturePath, JSON.stringify(original));
const report = {
  status: 'running', url,
  scope: 'Synthetic copy of the bundled Felix campaign: first actor is 22, Art 12, Heart 14, with a deliberately mismatched saved older portrait. Isolated browser context only.',
  checks: [], screenshots: [], pageErrors: [], consoleErrors: [], failedRequests: [],
};
const response = await fetch(new URL('main.dart.js', url));
assert.ok(response.ok);
report.mainJsSha256 = hash(Buffer.from(await response.arrayBuffer()));
const browser = await chromium.launch({ channel: 'msedge', headless: true });
const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, acceptDownloads: true });
const page = await context.newPage();
page.on('pageerror', error => report.pageErrors.push(String(error)));
page.on('console', message => { if (message.type() === 'error') report.consoleErrors.push(message.text()); });
page.on('requestfailed', request => report.failedRequests.push(request.url()));
const escape = text => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
async function uiText() {
  return page.locator('flt-semantics-host').evaluate(host => [host.innerText,
    ...[...host.querySelectorAll('[aria-label]')].map(node => node.getAttribute('aria-label')),
    ...[...host.querySelectorAll('input,textarea')].map(node => node.value),
  ].filter(Boolean).join('\n'));
}
async function wait(pattern) {
  const deadline = Date.now() + 20000;
  while (Date.now() < deadline) {
    if (await page.locator('flt-semantics-host').count() && pattern.test(await uiText())) return;
    await page.waitForTimeout(100);
  }
  throw new Error(`Missing ${pattern}: ${await uiText()}`);
}
async function click(name, locator = page) {
  const item = locator.getByRole('button', { name }).first();
  await item.click();
  await page.mouse.move(2, 2);
  await page.waitForTimeout(220);
}
async function capture(name) {
  await page.mouse.move(2, 2);
  await page.waitForTimeout(200);
  await page.screenshot({ path: resolve(output, `${name}.png`), fullPage: true });
  report.screenshots.push(`${name}.png`);
  report.checks.push(name);
  console.log(`PASS ${name}`);
}
async function exportGame(name) {
  await click(/^Save & exit/);
  await wait(/Start a New Game/);
  await click(/^Load & Manage Saves/);
  await click(/^A(?:\s|$)/);
  await wait(/Manage .*Saved Game/);
  const downloading = page.waitForEvent('download');
  await click(/Export Save File/);
  const download = await downloading;
  const path = resolve(output, `${name}.json`);
  await download.saveAs(path);
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
  await (await choosing).setFiles(fixturePath);
  await wait(/Save imported/);
  await page.keyboard.press('Enter');
  await wait(/Start a New Game/);
  await click(/^Load & Manage Saves/);
  await click(/^A(?:\s|$)/);
  await wait(/Manage .*Saved Game/);
  await click(/^L Load Game/);
  await wait(/Save & exit/);
  const before = await exportGame('before-ui-review');
  const repaired = before.lcs.pool.find(person => person.id === actor.id);
  assert.equal(repaired.portraitAssignedAge, 22);
  assert.ok(repaired.portraitId < 250 && Math.floor(repaired.portraitId % 16 / 4) === 0,
    'The repaired ordinary adult face must use the 20–30 painted age row.');
  report.portrait = { characterAge: 22, priorId: 13, priorVisualAge: 68, correctedId: repaired.portraitId, correctedVisualAge: 25 };
  await click(new RegExp(`^Inspect ${escape(actor.name)}(?:$|\\s)`));
  await click(/^Full dossier/);
  let dossier = page.getByRole('dialog');
  await dossier.waitFor();
  assert.equal(await dossier.getByText('Age 22', { exact: true }).count(), 1);
  await capture('01-age22-corrected-portrait');
  await click(/^Skills(?:$|\s)/, dossier);
  await writeFile(resolve(output, 'skill-semantics.html'), await dossier.innerHTML());
  const heading = dossier.getByText('Art: level 12', { exact: true });
  await heading.waitFor();
  assert.ok(await heading.boundingBox(), 'Name and skill value must be exposed together as primary information.');
  assert.equal(await dossier.getByText('Skill levels and progress from the current campaign.', { exact: true }).count(), 0);
  report.skillHeading = { label: 'Art: level 12', bounds: await heading.boundingBox(), note: 'Exact label/value spacing is covered by dossier widget tests at normal and enlarged text.' };
  await capture('02-skill-values-next-to-names');
  await dossier.getByRole('button', { name: 'Close dossier', exact: true }).last().click();
  await click(/^Orders(?:$|\s)/);
  await click(/^Business(?:$|\s)/);
  await click(/^Prepare Solicit Donations(?:$|\s)/);
  assert.doesNotMatch(await uiText(), /Calculation: Daily income/);
  assert.match(await uiText(), /Estimated \$\d+\/day/);
  await capture('03-order-brief-without-formulas');
  await click(/^Order mechanics(?:$|\s)/);
  let details = page.getByRole('alertdialog');
  await details.waitFor();
  await wait(/Calculation: Daily income/);
  await capture('04-order-mechanics-on-request');
  await click('Close', details);
  assert.doesNotMatch(await uiText(), /Calculation: Daily income/);
  assert.ok(await page.getByRole('button', { name: 'Confirm order', exact: true }).isEnabled());
  await page.keyboard.press('Escape'); // Cancel the draft, not an engine action.
  await click(/^Reading size/);
  await page.getByRole('menuitem', { name: '150%', exact: true }).click();
  await page.setViewportSize({ width: 800, height: 600 });
  await click(/^Prepare Solicit Donations(?:$|\s)/);
  await capture('05-order-brief-800x600-at150');
  await click(/^Order mechanics(?:$|\s)/);
  details = page.getByRole('alertdialog');
  await details.waitFor();
  await wait(/Calculation: Daily income/);
  const close = await details.getByRole('button', { name: 'Close', exact: true }).boundingBox();
  assert.ok(close && close.y >= 0 && close.y + close.height <= 600);
  await capture('06-mechanics-800x600-at150');
  await page.keyboard.press('Escape');
  assert.ok(await page.getByRole('button', { name: 'Confirm order', exact: true }).isEnabled());
  await page.keyboard.press('Escape');
  const after = await exportGame('after-ui-review');
  assert.deepEqual(after, before, 'Dossiers, mechanics disclosures and cancelled drafts must preserve the exported campaign exactly.');
  assert.deepEqual(report.pageErrors, []);
  assert.deepEqual(report.consoleErrors, []);
  assert.deepEqual(report.failedRequests, []);
  report.checks.push('campaign-save-identical-and-corrected-portrait-persists');
  report.status = 'passed';
} catch (error) {
  report.status = 'failed'; report.error = error.stack ?? String(error); process.exitCode = 1;
  await page.screenshot({ path: resolve(output, 'FAILURE.png'), fullPage: true });
  await writeFile(resolve(output, 'FAILURE.txt'), await uiText());
} finally {
  await context.close(); await browser.close();
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ status: report.status, output, checks: report.checks.length, error: report.error }));
}
