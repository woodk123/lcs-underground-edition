// Exact-build, isolated browser acceptance. Never reads or modifies player saves.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromiumLaunchOptions, observeMainScript } from './browser_support.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const args = process.argv.slice(2);
const value = (flag, fallback) => args.includes(flag) ? args[args.indexOf(flag) + 1] : fallback;
const expectedHash = value('--expected-hash', '');
assert.match(expectedHash, /^[a-f0-9]{64}$/i, '--expected-hash requires the exact compiled main.dart.js SHA-256.');
const qaOrigin = 'http://127.0.0.1:18881/';
const url = new URL(value('--url', qaOrigin)).href;
assert.equal(url, qaOrigin, `Injury browser reviews require the dedicated QA server at ${qaOrigin}`);
const output = resolve(root, value('--out', 'reports/injury-status-qa/browser'));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const decode = save => typeof save.saveData === 'string' ? JSON.parse(save.saveData) : save.saveData;
const original = JSON.parse(await readFile(resolve(root, 'upstream/test/saves/felix_1_0.json'), 'utf8'));
const fixture = decode(original);
const actor = fixture.lcs.pool[0];
Object.assign(actor, {
  name: 'Chaz Reasoner', properName: 'Chaz Reasoner',
  birthDate: `${Number(fixture.date.slice(0, 4)) - 22}-01-01T00:00:00.000`,
  portraitId: 209, portraitVariant: 0, portraitAssignedAge: 22,
  _blood: .2, permanentHealthDamage: 1, activity: { type: 'clinic' },
});
for (const part of ['head', 'torso', 'leftArm', 'rightArm', 'leftLeg', 'rightLeg']) {
  Object.assign(actor.body[part], { shot: false, cut: false, bruised: false, burned: false,
    torn: false, nastyOff: false, cleanOff: false, bleedingStacks: 0, relativeHealth: 1 });
}
for (const key of Object.keys(actor.body).filter(key => /^(missing|punctured)/.test(key))) actor.body[key] = false;
Object.assign(actor.body, { neck: 'healthy', upperSpine: 'healthy', lowerSpine: 'healthy',
  teeth: 32, maxTeeth: 32, ribs: 10, maxRibs: 10, puncturedRightLung: true });
Object.assign(actor.body.torso, { shot: true, relativeHealth: .74 });
Object.assign(actor.body.leftLeg, { bruised: true, relativeHealth: .97 });
Object.assign(actor.body.rightLeg, { bruised: true, relativeHealth: .94 });
original.saveData = typeof original.saveData === 'string' ? JSON.stringify(fixture) : fixture;
await mkdir(output, { recursive: true });
const fixturePath = resolve(output, 'synthetic-chaz-injuries.json');
await writeFile(fixturePath, JSON.stringify(original));
const report = {
  status: 'running', url, expectedHash: expectedHash.toLowerCase(),
  scope: 'Prepared copy of bundled Felix campaign, imported into a fresh browser context. No time advancement or player-save access.',
  prepared: { actorId: actor.id, name: actor.name, age: 22, portraitId: 209, portraitVisualAge: 25,
    torso: 'Shot, 74% tissue', leftLeg: 'Bruised, 97% tissue', rightLeg: 'Bruised, 94% tissue',
    rightLung: 'Collapsed', bloodFraction: .2, permanentHealthDamage: 1,
    personalOrder: 'clinic (Going to the Hospital)', activeBleeding: false },
  checks: [], screenshots: [], productionFindings: [], pageErrors: [], consoleErrors: [], failedRequests: [],
};
const response = await fetch(new URL('main.dart.js', url));
assert.ok(response.ok, 'QA build must be available.');
report.mainJsSha256 = hash(Buffer.from(await response.arrayBuffer()));
assert.equal(report.mainJsSha256, report.expectedHash, 'QA server must serve the exact requested build.');
const browser = await chromium.launch(chromiumLaunchOptions({ args }));
const context = await browser.newContext({ viewport: { width: 1440, height: 1100 }, acceptDownloads: true });
const page = await context.newPage();
const verifyLoadedScript = observeMainScript(page, report);
page.on('pageerror', error => report.pageErrors.push(String(error)));
page.on('console', message => { if (message.type() === 'error') report.consoleErrors.push(message.text()); });
page.on('requestfailed', request => report.failedRequests.push(request.url()));
async function uiText() {
  const host = page.locator('flt-semantics-host');
  return await host.count() ? host.evaluate(node => [node.innerText,
    ...[...node.querySelectorAll('[aria-label]')].map(item => item.getAttribute('aria-label')),
  ].filter(Boolean).join('\n')) : '';
}
async function wait(pattern) {
  const deadline = Date.now() + 20000;
  while (Date.now() < deadline) {
    if (pattern.test(await uiText())) return;
    await page.waitForTimeout(100);
  }
  throw new Error(`Missing ${pattern}: ${await uiText()}`);
}
async function click(name, locator = page) {
  await locator.getByRole('button', { name }).first().click();
  await page.mouse.move(2, 2);
  await page.waitForTimeout(200);
}
async function show(locator) {
  for (let i = 0; i < 24; i++) {
    const box = await locator.boundingBox();
    const height = page.viewportSize().height;
    if (box && box.y >= 80 && box.y + box.height < height - 85) return box;
    await page.mouse.move(page.viewportSize().width / 2, height / 2);
    const delta = !box ? 240 : box.y < 80 ? box.y - 100 : box.y + box.height - (height - 100);
    await page.mouse.wheel(0, Math.max(-420, Math.min(420, delta)));
    await page.waitForTimeout(120);
  }
  throw new Error(`Could not reveal ${await locator.textContent()}`);
}
async function capture(name) {
  await page.waitForTimeout(250);
  await page.screenshot({ path: resolve(output, `${name}.png`), fullPage: true });
  await writeFile(resolve(output, `${name}.txt`), await uiText());
  report.screenshots.push(`${name}.png`);
  console.log(`CAPTURE ${name}`);
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
  const campaign = decode(JSON.parse(await readFile(path, 'utf8')));
  await click(/^L Load Game/);
  await wait(/Save & exit/);
  return campaign;
}
async function openDossier() {
  await click(/^Inspect Chaz Reasoner(?:$|\s)/);
  await click(/^Full dossier/);
  await page.getByRole('dialog').waitFor();
  await wait(/FIELD MEDICAL RECORD/);
}
async function inspectRecovery(name) {
  const help = page.getByRole('dialog').getByText('How daily recovery works', { exact: true });
  await show(help);
  await help.click();
  await wait(/no medic assignment or Lay Low order is required/);
  await wait(/Medical support at/);
  await wait(/Current medical recovery ceiling:/);
  await capture(name);
  await show(page.getByRole('dialog').getByText(/^Care is automatic:/));
  await capture(`${name}-details`);
  await show(help);
  await help.click();
  report.checks.push('Daily recovery rate and automatic care explanation open and close');
}
async function closeDossier() {
  await page.getByRole('dialog').getByRole('button', { name: 'Close dossier', exact: true }).last().click();
  await page.waitForTimeout(180);
}
const inspect = name => page.getByRole('dialog').getByRole('button', { name: new RegExp(`^Inspect ${name}:`) }).first();
const row = name => page.getByRole('dialog').getByRole('button', { name: new RegExp(`^${name} ·`) }).first();
async function detail(name, expected) {
  await page.getByRole('dialog').getByText(name, { exact: true }).first().waitFor({ state: 'attached' });
  await wait(expected);
}
async function pinRow(name, expected) {
  const target = row(name);
  await show(target);
  await target.click();
  await page.mouse.move(2, 2);
  await detail(name, expected);
  await show(page.getByRole('dialog').getByText(name, { exact: true }).first());
  report.checks.push(`Pinned ${name}: ${expected}`);
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
  const before = await exportGame('before-inspection');
  const prepared = before.lcs.pool.find(person => person.id === actor.id);
  assert.equal(prepared.name, 'Chaz Reasoner');
  assert.equal(prepared._blood, .2);
  assert.equal(prepared.activity.type, 'clinic');
  assert.equal(prepared.birthDate, actor.birthDate);
  assert.equal(prepared.portraitId, 209);
  assert.equal(prepared.portraitAssignedAge, 22);
  assert.equal(prepared.permanentHealthDamage, 1);
  assert.equal(prepared.body.puncturedRightLung, true);
  assert.equal(prepared.body.torso.relativeHealth, .74);
  assert.equal(prepared.body.leftLeg.relativeHealth, .97);
  assert.equal(prepared.body.rightLeg.relativeHealth, .94);
  assert.equal(prepared.body.leftLeg.bruised && prepared.body.rightLeg.bruised && prepared.body.torso.shot, true);
  assert.equal(before.date, fixture.date, 'Import and load must not advance campaign time.');
  report.checks.push('Prepared conditions survive real import and normalization');
  await openDossier();
  await inspectRecovery('00-desktop-daily-recovery');
  assert.match(await uiText(), /Age 22: No age attribute modifiers/);
  await show(inspect('Right lung'));
  await inspect('Right lung').hover();
  await detail('Right lung', /Adds 2 to the injury modifier/);
  await inspect('Right lung').click();
  await page.mouse.move(2, 2);
  await wait(/Collapsed lung/);
  await capture('01-desktop-right-lung-pinned');
  report.checks.push('Right lung marker previews and pins without losing its torso injury');

  // Tight region semantics must agree with the anatomical mouse target.
  const leg = inspect('Left Leg');
  await show(leg);
  await leg.hover();
  await detail('Left Leg', /97% tissue health/);
  await capture('02-desktop-left-leg-hover');
  await leg.click();
  await page.mouse.move(2, 2);
  await detail('Left Leg', /Further hits can more easily sever/);
  report.checks.push('Left Leg anatomical zone previews, switches and pins');
  await pinRow('Torso', /74% tissue health/);
  await capture('03-desktop-torso-gameplay');
  await pinRow('Right Leg', /94% tissue health/);
  await capture('04-desktop-right-leg-gameplay');
  await pinRow('Right lung', /no fixed recovery date/);
  const condition = await page.getByRole('dialog').getByText('Condition', { exact: true }).boundingBox();
  await page.mouse.move(950, 450);
  await page.mouse.wheel(0, condition.y - 105);
  await page.mouse.move(2, 2);
  await capture('05-desktop-medical-plate');
  assert.doesNotMatch(await uiText(), /(?:26|6|3)% (?:combat|accuracy|movement)/i);
  await closeDossier();
  await click(/^Reading size/);
  await page.getByRole('menuitem', { name: '150%', exact: true }).click();
  await page.setViewportSize({ width: 1024, height: 720 });
  await openDossier();
  await inspectRecovery('06-1024x720-at150-daily-recovery');
  await show(inspect('Left Leg'));
  await capture('06-1024x720-at150-body');
  await pinRow('Right lung', /Adds 2 to the injury modifier/);
  await capture('07-1024x720-at150-lung-detail');
  await pinRow('Left Leg', /97% tissue health/);
  await capture('08-1024x720-at150-leg-detail');
  const close = await page.getByRole('dialog').getByRole('button', { name: 'Close dossier', exact: true }).last().boundingBox();
  assert.ok(close && close.y >= 0 && close.y + close.height <= page.viewportSize().height, 'Dossier dismissal remains visible at enlarged reading size.');
  await closeDossier();
  await click(/^Reading size/);
  await page.getByRole('menuitem', { name: '100%', exact: true }).click();
  await page.setViewportSize({ width: 1440, height: 1100 });
  const after = await exportGame('after-inspection');
  assert.deepEqual(after, before, 'The complete normalized campaign must remain identical after all inspection.');
  report.beforeCampaignSha256 = hash(JSON.stringify(before));
  report.afterCampaignSha256 = hash(JSON.stringify(after));
  report.checks.push('Whole normalized campaign identical; no time or gameplay changes');
  await verifyLoadedScript(report.expectedHash);
  assert.deepEqual(report.productionFindings, []);
  assert.deepEqual(report.pageErrors, []);
  assert.deepEqual(report.consoleErrors, []);
  assert.deepEqual(report.failedRequests, []);
  report.status = 'passed';
} catch (error) {
  report.status = 'failed'; report.error = error.stack ?? String(error); process.exitCode = 1;
  await page.screenshot({ path: resolve(output, 'FAILURE.png'), fullPage: true });
  await writeFile(resolve(output, 'FAILURE.txt'), await uiText());
  await writeFile(resolve(output, 'FAILURE.html'), await page.locator('flt-semantics-host').innerHTML());
} finally {
  await context.close(); await browser.close();
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ status: report.status, output, checks: report.checks.length, error: report.error }));
}
