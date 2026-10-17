// Isolated browser regression checks for dossiers, orders, contextual travel
// and portrait migration. Synthetic fixture edits never touch player saves.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertQaUrl, chromiumLaunchOptions } from './browser_support.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const args = process.argv.slice(2);
const value = (flag, fallback) => args.includes(flag) ? args[args.indexOf(flag) + 1] : fallback;
const url = assertQaUrl(value('--url', 'http://127.0.0.1:18879/'));
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
const expectedHash = value('--expected-hash', null);
if (expectedHash) assert.equal(report.mainJsSha256, expectedHash.toLowerCase(),
  'QA server must serve the requested compiled build.');
const browser = await chromium.launch(chromiumLaunchOptions({ args }));
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
  report.checks.push('campaign-save-identical-and-corrected-portrait-persists');

  await click(/^Reading size/);
  await page.getByRole('menuitem', { name: '100%', exact: true }).click();
  await page.setViewportSize({ width: 1440, height: 1000 });
  const crew = before.lcs.pool.filter(person => person.squadId === actor.squadId && person.alive !== false);
  assert.ok(crew.length >= 2);
  await click(/^Orders(?:$|\s)/);
  await click(/^Personnel(?:$|\s)/);
  await click('Teaching Classes');
  await click(/^Show location index/);
  await click(/^Prepare Teach Liberal Arts(?:$|\s)/);
  await click(new RegExp(`^Select crew ${escape(crew[1].name)}(?:$|\\s)`));
  assert.equal(await page.getByRole('button', { name: 'Confirm order', exact: true }).count(), 0);
  assert.equal(await page.getByRole('button', { name: 'Teaching Classes', exact: true }).count(), 1);
  assert.ok(await page.getByRole('button', { name: /^Show city plan/ }).count(), 'Keep the open location index when switching actors.');
  await capture('07-member-switch-keeps-category-and-map');
  for (const member of crew.slice(0, 2)) {
    await click(new RegExp(`^Select crew ${escape(member.name)}(?:$|\\s)`));
    await click(/^Prepare Teach Liberal Arts(?:$|\s)/);
    await click('Confirm order');
    await wait(/Prepare Teach Liberal Arts/);
    assert.equal(await page.getByRole('button', { name: 'Confirm order', exact: true }).count(), 0);
  }
  await capture('08-confirm-keeps-assignment-category-open');
  const assigned = await exportGame('after-repeated-assignments');
  const expected = structuredClone(before);
  for (const member of crew.slice(0, 2)) {
    expected.lcs.pool.find(person => person.id === member.id).activity = { type: 'teachLiberalArts' };
  }
  assert.deepEqual(assigned, expected, 'Only the two explicitly confirmed members may change.');
  report.checks.push('repeated-assignments-change-only-confirmed-members');

  await click(/^Orders(?:$|\s)/);
  await click(/^Operations(?:$|\s)/);
  await click('Visit a location');
  const cities = before.cities;
  const home = cities.flatMap(city => city.districts.flatMap(district => district.sites))
    .find(site => `Site${site.id}` === crew[0].locationId || site.id === crew[0].locationId);
  assert.ok(home, 'Locate the synthetic crew’s current site.');
  const homeCity = cities.find(city => city.id === home.cityId);
  const localDistrict = homeCity.districts.find(district => district.area === homeCity.area && district.sites.some(site => site.type === 'publicPark'));
  const park = localDistrict.sites.find(site => site.type === 'publicPark');
  const otherCities = page.getByRole('button', { name: /^Other cities/ });
  assert.match(await otherCities.innerText(), new RegExp(`\\(\\$${crew.length * 100}\\)`));
  await capture('09-intercity-option-shows-price');
  await click(new RegExp(`^${escape(localDistrict.name)}\\.`));
  await click(new RegExp(`^${escape(park.name)}\\.`));
  assert.ok(await page.getByRole('button', { name: 'Confirm order', exact: true }).isEnabled());
  assert.doesNotMatch(await uiText(), /Travel cost:|Current intercity fee:|Travel to another area needs a car|Needs: an open site/);
  await capture('10-nearby-trip-without-generic-travel-lecture');
  await click(/^Order mechanics(?:$|\s)/);
  await wait(/Travel to another area needs a car/);
  await click('Close', page.getByRole('alertdialog'));
  await page.keyboard.press('Escape');
  const afterTravel = await exportGame('after-travel-inspection');
  assert.deepEqual(afterTravel, assigned, 'Travel inspection and cancellation must not queue or charge anything.');
  report.checks.push('travel-details-and-cancel-preserve-campaign');

  await click(new RegExp(`^Select crew ${escape(crew[0].name)}(?:$|\\s)`));
  await click(/^Clipboard(?:$|\s)/);
  await wait(/Personnel directory/);
  assert.equal((await uiText()).split('\n').filter(line => line.trim() === 'Personnel directory').length, 1);
  await capture('11-clipboard-as-ruled-journal-page');
  await click(new RegExp('^Open dossier for ' + escape(crew[0].name) + '[.]'));
  await wait(/Campaign record/);
  assert.doesNotMatch(await uiText(), /Profile of a Liberal|SKILL\s+NOW\s+MAX/);
  await capture('12-clipboard-native-personnel-dossier');
  await click(/^Skills$/);
  await wait(/Skills & training/);
  await capture('13-clipboard-aligned-skill-values');
  await click(new RegExp(`^Select crew ${escape(crew[1].name)}(?:$|\\s)`));
  await wait(/Skills & training/);
  assert.equal(await page.getByRole('img', { name: new RegExp(`^${escape(crew[1].name)} portrait\\.`) }).count(), 2,
    'The left identity and open dossier must both follow the selected person.');
  await capture('17-profile-member-switch-keeps-skills-tab');
  await click(/^Back to directory/);
  await wait(/Personnel directory/);
  await click(/^Weapons(?:$|\s)/);
  await wait(/Increase ammo allocation/);
  assert.equal((await uiText()).split('\n').filter(line => line.trim() === 'Equipment').length, 1);
  assert.doesNotMatch(await uiText(), /Crew & choices|Equip the Squad|Cursors -/);
  await click(new RegExp(`^Select crew ${escape(crew[1].name)}(?:$|\\s)`));
  const selectedEquipment = page.getByRole('button', { name: new RegExp(`^2 ${escape(crew[1].name)}(?:$|\\s)`) });
  assert.ok(await selectedEquipment.evaluate(node => !!node.closest('[aria-current="true"], [aria-selected="true"]')),
    'Equipment marks the selected person without invoking Unequip weapon.');
  await capture('18-equipment-follows-local-selection');
  await page.setViewportSize({ width: 2200, height: 1200 });
  await capture('14-equipment-as-journal-ledger');
  await click(/^Reading size/);
  await page.getByRole('menuitem', { name: '150%', exact: true }).click();
  await page.setViewportSize({ width: 800, height: 600 });
  await capture('15-equipment-800x600-at150');
  await click(/^Clipboard(?:$|\s)/);
  await wait(/Personnel directory/);
  await click(new RegExp('^Open dossier for ' + escape(crew[0].name) + '[.]'));
  await wait(/Campaign record/);
  await capture('16-clipboard-dossier-800x600-at150');
  await click(/^Back to directory/);
  await click(/^Reading size/);
  await page.getByRole('menuitem', { name: '100%', exact: true }).click();
  await page.setViewportSize({ width: 1440, height: 1000 });
  const afterManagement = await exportGame('after-management-inspection');
  assert.deepEqual(afterManagement, assigned, 'Clipboard dossiers and equipment inspection preserve the saved campaign.');
  report.checks.push('journal-management-inspection-preserves-campaign');
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
