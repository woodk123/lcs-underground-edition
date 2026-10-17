// Dedicated, fresh-profile acceptance. Never opens or edits a player campaign.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromiumLaunchOptions } from './browser_support.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const args = process.argv.slice(2);
const value = (flag, fallback) => args.includes(flag) ? args[args.indexOf(flag) + 1] : fallback;
const expectedHash = value('--expected-hash', '');
assert.match(expectedHash, /^[a-f0-9]{64}$/i);
const url = new URL(value('--url', 'http://127.0.0.1:18882/')).href;
assert.equal(url, 'http://127.0.0.1:18882/');
const output = resolve(root, value('--out', 'reports/personnel-directory-qa/browser'));
await mkdir(output, { recursive: true });
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const decode = save => typeof save.saveData === 'string' ? JSON.parse(save.saveData) : save.saveData;
const original = JSON.parse(await readFile(resolve(root, 'upstream/test/saves/felix_1_0.json'), 'utf8'));
const fixture = decode(original);
const template = structuredClone(fixture.lcs.pool[0]);
const hospital = fixture.sites.find(site => site.type === 'universityHospital');
assert.ok(hospital);
const chaz = fixture.lcs.pool[0];
Object.assign(chaz, { name: 'Chaz Reasoner', properName: 'Chaz Reasoner',
  locationId: `Site${hospital.id}`, squadId: null, medicalBills: 1360, _blood: .2 });
for (const squad of fixture.lcs.squads) squad.members = squad.members.filter(id => id !== chaz.id);
const custody = fixture.sites.find(site => site.type === 'policeStation');
for (const [name, patch] of [
  ['Casey Custody', { locationId: `Site${custody.id}` }],
  ['Sam Sleeper', { sleeperAgent: true }], ['Holly Hiding', { hidingDaysLeft: 4 }],
  ['Dora Departed', { alive: false }], ['Harriet Hostage', { align: 'conservative' }],
  ...Array.from({ length: 24 }, (_, i) => [`Zed ${String(i).padStart(2, '0')}`, {}]),
]) {
  const person = { ...structuredClone(template), id: fixture.nextCreatureId++, name,
    properName: name, squadId: null, sleeperAgent: false, hidingDaysLeft: 0,
    vacationDaysLeft: 0, medicalBills: 0, ...patch };
  fixture.lcs.pool.push(person);
}
original.saveData = typeof original.saveData === 'string' ? JSON.stringify(fixture) : fixture;
const fixturePath = resolve(output, 'synthetic-personnel.json');
await writeFile(fixturePath, JSON.stringify(original));
const report = { status: 'running', url, expectedHash, scope: 'Prepared mixed-status bundled campaign; fresh Edge context; no player data and no day advancement.',
  checks: [], screenshots: [], pageErrors: [], consoleErrors: [], failedRequests: [] };
const response = await fetch(new URL('main.dart.js', url));
assert.ok(response.ok);
report.mainJsSha256 = hash(Buffer.from(await response.arrayBuffer()));
assert.equal(report.mainJsSha256, expectedHash.toLowerCase());
const browser = await chromium.launch(chromiumLaunchOptions({ args }));
const context = await browser.newContext({ viewport: { width: 1440, height: 1100 }, acceptDownloads: true });
const page = await context.newPage();
page.on('pageerror', error => report.pageErrors.push(String(error)));
page.on('console', message => { if (message.type() === 'error') report.consoleErrors.push(message.text()); });
page.on('requestfailed', request => report.failedRequests.push(request.url()));
async function uiText() {
  const host = page.locator('flt-semantics-host');
  return await host.count() ? host.evaluate(node => [node.innerText,
    ...[...node.querySelectorAll('[aria-label]')].map(item => item.getAttribute('aria-label'))].filter(Boolean).join('\n')) : '';
}
async function wait(pattern) {
  for (let i = 0; i < 200; i++) {
    if (pattern.test(await uiText())) return;
    await page.waitForTimeout(100);
  }
  throw new Error(`Missing ${pattern}: ${await uiText()}`);
}
async function click(name) {
  await page.getByRole('button', { name }).first().click();
  await page.mouse.move(2, 2);
  await page.waitForTimeout(200);
  if (String(name).includes('Back to directory')) await top();
}
async function top() {
  await page.mouse.move(page.viewportSize().width * .76, page.viewportSize().height * .55);
  await page.mouse.wheel(0, -10000); await page.waitForTimeout(200);
}
async function capture(name) {
  await page.screenshot({ path: resolve(output, `${name}.png`), fullPage: true });
  await writeFile(resolve(output, `${name}.txt`), await uiText());
  report.screenshots.push(`${name}.png`);
}
async function exportGame(name) {
  await click(/^Save & exit/); await wait(/Start a New Game/);
  await click(/^Load & Manage Saves/); await click(/^A(?:\s|$)/);
  await wait(/Manage .*Saved Game/);
  const downloading = page.waitForEvent('download');
  await click(/Export Save File/);
  const path = resolve(output, `${name}.json`);
  await (await downloading).saveAs(path);
  const state = decode(JSON.parse(await readFile(path, 'utf8')));
  await click(/^L Load Game/); await wait(/Save & exit/);
  return state;
}
async function search(text) {
  await top();
  const input = page.getByRole('textbox', { name: /Find anyone/ });
  await input.fill(text); await page.waitForTimeout(250);
}
async function row(name, screenshot) {
  const target = page.getByRole('button', { name: new RegExp(`^Open dossier for ${name}\\.`) });
  for (let i = 0; i < 18; i++) {
    const box = await target.boundingBox().catch(() => null);
    if (box && box.y > 75 && box.y + box.height < page.viewportSize().height - 70) break;
    await page.mouse.move(page.viewportSize().width * .76, page.viewportSize().height * .55);
    await page.mouse.wheel(0, 180); await page.waitForTimeout(150);
  }
  if (screenshot) await capture(screenshot);
  await target.click(); await page.mouse.move(2, 2); await page.waitForTimeout(300);
}
try {
  await page.goto(url, { waitUntil: 'networkidle' }); await wait(/Start a New Game/);
  const choosing = page.waitForEvent('filechooser'); await click(/^Import a Save/);
  await (await choosing).setFiles(fixturePath); await wait(/Save imported/);
  await page.keyboard.press('Enter'); await wait(/Start a New Game/);
  await click(/^Load & Manage Saves/); await click(/^A(?:\s|$)/); await wait(/Manage .*Saved Game/);
  await click(/^L Load Game/); await wait(/Save & exit/);
  const before = await exportGame('before-inspection');
  report.checks.push('Mixed-status fixture imports; no time advancement');
  await click(/^Clipboard(?:\s|$)/); await wait(/Personnel directory/);
  assert.match(await uiText(), /Hospital \(1\)/);
  await wait(/Chaz Reasoner/); await wait(/Hospitalized/);
  assert.match(await uiText(), /1,360/);
  await capture('01-desktop-all-personnel');
  report.checks.push('One click Clipboard lists hospitalized Chaz with bill and location');
  for (const name of ['Hospital', 'Custody', 'Sleepers', 'Away', 'Hostages', 'Dead', 'Active', 'All']) {
    await click(new RegExp(`^${name} \\(`));
    await wait(new RegExp(`people.*${name === 'All' ? 'All personnel' : name}`));
  }
  report.checks.push('Every visible counted category opens without Classic view');
  await click(/^Active \(/); await search('chaz'); await wait(/Chaz Reasoner/);
  assert.match(await uiText(), /1 of \d+ people.*All personnel/);
  await click(/^Hospital \(/); await row('Chaz Reasoner');
  await wait(/Back to directory/); await capture('02-chaz-native-profile');
  await click(/^Back to directory$/); await wait(/people.*Hospital/);
  await page.getByRole('textbox', { name: /Find anyone/ }).click();
  await page.waitForTimeout(100);
  assert.equal(await page.locator('input,textarea').evaluateAll(nodes => nodes.map(node => node.value).find(value => value === 'chaz') ?? ''), 'chaz');
  report.checks.push('Search finds patient across Active; native profile closes retaining Hospital and search');
  await search('Zed 23'); await row('Zed 23'); await wait(/Back to directory/);
  await click(/^Back to directory$/); await search('Chaz'); await row('Chaz Reasoner');
  await wait(/Back to directory/); await click(/^Back to directory$/);
  report.checks.push('Search selects original person beyond page 19 then correctly resolves earlier person');
  await search('No matching name'); await wait(/No matching people/);
  await click(/^Clear search$/); await wait(/All personnel/);
  await click(/^Hospital \(/); await capture('03-hospital-filter');
  report.checks.push('Empty search explains recovery; clear restores roster');
  await page.setViewportSize({ width: 800, height: 600 });
  await click(/^Reading size$/); await page.getByRole('menuitem', { name: '150%', exact: true }).click(); await wait(/Personnel directory/);
  await capture('04-800x600-at150-directory');
  await row('Chaz Reasoner', '05-800x600-at150-patient'); await wait(/Back to directory/);
  await click(/^Back to directory$/); await wait(/people.*Hospital/);
  report.checks.push('800x600 at 150 percent retains readable controls and patient profile navigation');
  await page.setViewportSize({ width: 1440, height: 1100 });
  await click(/^Back to organisation$/);
  const after = await exportGame('after-inspection');
  assert.deepEqual(after, before, 'Entire exported campaign must remain identical.');
  report.campaignSha256 = hash(JSON.stringify(before));
  report.checks.push('Entire campaign exports match before/after all browsing');
  assert.deepEqual(report.pageErrors, []); assert.deepEqual(report.consoleErrors, []); assert.deepEqual(report.failedRequests, []);
  report.checks.push('Exact-build Edge run has no page/console/network failures');
  report.status = 'passed';
} catch (error) {
  report.status = 'failed'; report.error = String(error.stack ?? error);
  await capture('failure').catch(() => {}); throw error;
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  await context.close(); await browser.close();
}
console.log(JSON.stringify({ status: report.status, checks: report.checks.length, screenshots: report.screenshots.length }));
