// Real street arrest and Free Clinic care, driven only through the browser UI.
// Wounds are declared fixture conditions; the arrest is earned during play.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertQaUrl, chromiumLaunchOptions, observeMainScript } from './browser_support.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const args = process.argv.slice(2);
const arg = (flag, fallback) => args.includes(flag) ? args[args.indexOf(flag) + 1] : fallback;
const url = assertQaUrl(arg('--url', undefined));
const expected = arg('--expected-hash', '');
assert.match(expected, /^[a-f0-9]{64}$/i, 'Provide the compiled QA main.dart.js SHA-256.');
const only = arg('--only', 'all');
assert.ok(['all', 'street', 'clinic'].includes(only));
const baselineRun = args.includes('--baseline');
const output = resolve(root, arg('--out', `reports/street-clinic-${Date.now()}`));
const relativeOutput = relative(resolve(root, 'reports'), output);
assert.ok(relativeOutput && !relativeOutput.startsWith('..'), 'Keep evidence under reports/.');
await mkdir(output, { recursive: true });
const decode = env => typeof env.saveData === 'string' ? JSON.parse(env.saveData) : env.saveData;
const sourceEnvelope = JSON.parse(await readFile(resolve(root, 'upstream/test/saves/felix_1_0.json'), 'utf8'));
const seed = decode(sourceEnvelope);
for (const person of seed.lcs.pool) {
  person.wantedForCrimes = Object.fromEntries(Object.keys(person.wantedForCrimes).map(key => [key, 0]));
  person.heat = 0;
  person.activity = { type: 'none' };
}
const report = { status: 'running', url, baselineRun, expectedHash: expected, prepared: [], checks: [],
  issues: [], outcomes: {}, decisions: [], screenshots: [], pageErrors: [], consoleErrors: [], failedRequests: [] };
const response = await fetch(new URL('main.dart.js', url));
assert.ok(response.ok);
report.mainJsSha256 = createHash('sha256').update(Buffer.from(await response.arrayBuffer())).digest('hex');
assert.equal(report.mainJsSha256, expected.toLowerCase());
const browser = await chromium.launch(chromiumLaunchOptions({ args }));
let context, page, verifyLoadedScript, scene = 'setup', normalized;
const decodeText = async () => {
  if (!await page.locator('flt-semantics-host').count()) return '';
  return page.locator('flt-semantics-host').evaluate(host => [host.innerText,
    ...[...host.querySelectorAll('[aria-label]')].map(n => n.getAttribute('aria-label')),
  ].filter(Boolean).join('\n'));
};
const button = name => page.getByRole('button', { name }).first();
async function available(name) { return await button(name).count() > 0 && await button(name).isEnabled(); }
async function wait(pattern) {
  const deadline = Date.now() + 20000;
  while (Date.now() < deadline) {
    if (pattern.test(await decodeText())) return;
    await page.waitForTimeout(80);
  }
  throw Error(`Missing ${pattern}: ${await decodeText()}`);
}
async function click(name) {
  await button(name).click();
  await page.mouse.move(2, 2);
  await page.waitForTimeout(160);
}
async function capture(name) {
  await page.mouse.move(2, 2); await page.waitForTimeout(250);
  const file = `${scene}-${name}`;
  await page.screenshot({ path: resolve(output, `${file}.png`), fullPage: true });
  await writeFile(resolve(output, `${file}.txt`), await decodeText());
  report.screenshots.push(`${file}.png`);
}
function check(name) { report.checks.push(`${scene}: ${name}`); console.log(`PASS ${scene}: ${name}`); }
function issue(name) {
  report.issues.push(`${scene}: ${name}`);
  if (!baselineRun) throw Error(name);
  console.log(`REPRODUCED ${scene}: ${name}`);
}
async function fresh() {
  if (verifyLoadedScript) await verifyLoadedScript(expected.toLowerCase());
  await context?.close();
  context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, acceptDownloads: true });
  page = await context.newPage(); page.setDefaultTimeout(9000);
  verifyLoadedScript = observeMainScript(page, report);
  page.on('pageerror', e => report.pageErrors.push(String(e)));
  page.on('console', m => { if (m.type() === 'error') report.consoleErrors.push(m.text()); });
  page.on('requestfailed', r => report.failedRequests.push(r.url()));
  await page.goto(url, { waitUntil: 'networkidle' });
  await wait(/Start a New Game/);
}
async function prepared(name, state, details, envelope = normalized?.envelope ?? sourceEnvelope) {
  const env = structuredClone(envelope);
  env.saveData = typeof env.saveData === 'string' ? JSON.stringify(state) : state;
  const path = resolve(output, `prepared-${name}.json`);
  await writeFile(path, JSON.stringify(env));
  report.prepared.push({ scenario: name, changes: details, path });
  return path;
}
async function importLoad(path) {
  const choosing = page.waitForEvent('filechooser');
  await click(/^Import a Save/); await (await choosing).setFiles(path);
  await wait(/Save imported/); await page.keyboard.press('Enter');
  await wait(/Start a New Game/); await click(/^Load & Manage Saves/);
  await click(/^A(?:\s|$)/); await click(/^L Load Game/); await wait(/Save & exit/);
}
async function snapshot(name) {
  assert.ok(await available(/^Save & exit/));
  await click(/^Save & exit/); await wait(/Start a New Game/);
  await click(/^Load & Manage Saves/); await click(/^A(?:\s|$)/);
  const downloading = page.waitForEvent('download'); await click(/Export Save File/);
  const path = resolve(output, `${scene}-${name}.json`); await (await downloading).saveAs(path);
  const envelope = JSON.parse(await readFile(path, 'utf8'));
  await click(/^L Load Game/); await wait(/Save & exit/);
  return { state: decode(envelope), envelope, path };
}
async function decision() {
  const text = await decodeText();
  report.decisions.push({ scene, text, buttons: await page.getByRole('button')
    .evaluateAll(nodes => nodes.map(n => ({ label: n.getAttribute('aria-label') ?? n.textContent,
      disabled: n.getAttribute('aria-disabled') === 'true' }))) });
  return text;
}
async function enlarged() {
  await page.setViewportSize({ width: 1024, height: 720 });
  await click(/^Reading size/); await page.getByRole('menuitem', { name: '150%', exact: true }).click();
  await page.waitForTimeout(250);
}
async function settle({ street = false } = {}) {
  let surrendered = false;
  for (let step = 0; step < 500; step++) {
    if (await available(/^Save & exit/)) return surrendered;
    if (street && await available(/Give up/)) {
      const before = await decision();
      assert.match(before, /Yann Zedner/);
      await capture('pursuit-before-inspection');
      await click(/^Inspect Yann Zedner$/);
      if (await page.getByRole('dialog').count()) {
        await page.getByRole('dialog').getByRole('button', { name: 'Close dossier', exact: true }).last().click();
        await page.waitForTimeout(150);
        assert.ok(await available(/Give up/));
        check('pursuit dossier opens and closes without consuming a game decision');
      } else issue('Pursuit Inspect control does not display a dossier.');
      await enlarged();
      await page.keyboard.press('z'); await page.waitForTimeout(150);
      assert.ok(await available(/Give up/), 'Retry must retain the source surrender choice.');
      const bounds = await button(/Give up/).boundingBox();
      assert.ok(bounds && bounds.y >= 0 && bounds.y + bounds.height <= page.viewportSize().height);
      await capture('pursuit-1024x720-at150');
      await click(/Give up/); surrendered = true;
      check('actual police pursuit accepts its current surrender control at enlarged text');
    } else if (await available(/^Continue$/)) {
      const text = await decision();
      if (street && /As you exit the site/.test(text)) issue('Street arrest incorrectly claims the character exited a site.');
      await click(/^Continue$/);
    } else await page.waitForTimeout(100);
  }
  throw Error(`Unresolved daily decision: ${await decodeText()}`);
}
async function day(options) {
  await click(/^(?:Wait a day|Carry out your plans)/);
  return settle(options);
}

try {
  await fresh();
  await importLoad(await prepared('baseline', seed,
    'Bundled Felix campaign copy with wanted charges/heat cleared and all personal orders idle. No skills, funds, equipment, dates or RNG altered.'));
  normalized = await snapshot('normalized');
  if (['all', 'street'].includes(only)) {
    scene = 'street';
    const original = normalized.state;
    // Remove clothes with the actual equipment handler, preserving the weapon.
    await click(/^Equipment(?:$|\s)/); await click(/Strip a Squad member/);
    await click(/^5 Yann Zedner(?:$|\s)/); await click(/^Enter Done$/);
    const stripped = (await snapshot('stripped-through-ui')).state;
    const actor = stripped.lcs.pool.find(p => p.id === 4);
    assert.equal(actor.equippedClothing, null);
    assert.deepEqual(actor.equippedWeapon, original.lcs.pool.find(p => p.id === 4).equippedWeapon);
    assert.deepEqual(actor.spareAmmo, original.lcs.pool.find(p => p.id === 4).spareAmmo);
    assert.ok(Object.values(actor.wantedForCrimes).every(n => n === 0));
    check('actual strip action removes only clothing before any arrest or charge exists');
    await click(/^Select crew Yann Zedner/); await click(/^Orders(?:$|\s)/);
    await click(/^Business(?:$|\s)/); await click(/^Prepare Solicit Donations/); await click('Confirm order');
    let prior = (await snapshot('ordered')).state;
    let current, arrestDay;
    for (let elapsed = 1; elapsed <= 20; elapsed++) {
      const surrendered = await day({ street: true });
      current = (await snapshot(`day-${elapsed}`)).state;
      if (surrendered) { arrestDay = elapsed; break; }
      prior = current;
    }
    assert.ok(arrestDay, 'A real street arrest must occur during the natural daily checks.');
    const detainee = current.lcs.pool.find(p => p.id === actor.id);
    assert.ok(report.decisions.some(d => /accosted by police while soliciting donations/.test(d.text)));
    assert.ok(report.decisions.some(d => /You stop and are arrested/.test(d.text)));
    assert.ok(detainee.wantedForCrimes.disturbingThePeace > 0);
    assert.equal(detainee.wantedForCrimes.resistingArrest, 0);
    assert.equal(detainee.squadId, null); assert.equal(detainee.carId, null);
    assert.equal(detainee.equippedWeapon, null); assert.equal(detainee.spareAmmo, null);
    assert.equal(detainee.activity.type, 'none'); assert.equal(detainee.alive, true);
    const police = current.cities.flatMap(c => c.districts.flatMap(d => d.sites))
      .find(s => s.type === 'policeStation' && `Site${s.id}` === detainee.locationId);
    assert.ok(police, 'The engine must place the arrested person in police custody.');
    assert.deepEqual(current.lcs.squads.map(s => s.id), original.lcs.squads.map(s => s.id));
    assert.deepEqual(current.lcs.squads[0].members, original.lcs.squads[0].members.filter(id => id !== actor.id));
    assert.equal(current.ledger._funds, prior.ledger._funds, 'The interrupted street order earns no money on arrest day.');
    const founder = current.lcs.pool.find(p => p.id === 0);
    assert.equal(founder.locationId, `Site${founder.baseId}`); assert.equal(founder.squadId, original.lcs.pool[0].squadId);
    check('street arrest adds its charge, confiscates weapons/ammo, clears orders, and preserves the founder and original squad');
    await capture('returned-to-headquarters');
    report.outcomes.street = { arrestDay, detaineeId: actor.id, locationId: detainee.locationId,
      crimes: detainee.wantedForCrimes, funds: current.ledger._funds, startingWeapon: actor.equippedWeapon,
      startingSpareAmmo: actor.spareAmmo, finalWeapon: detainee.equippedWeapon, finalSpareAmmo: detainee.spareAmmo };
  }
  if (['all', 'clinic'].includes(only)) {
    scene = 'clinic';
    const state = structuredClone(normalized.state), patient = state.lcs.pool[1];
    patient._blood = .80; patient.body.leftArm.shot = true; patient.body.leftArm.bleedingStacks = 1;
    await fresh();
    await importLoad(await prepared('clinic', state,
      'One prepared patient at 80% blood with a bleeding arm wound. No money, skill, date or healing outcomes altered. Admission and all treatment occur through the Free Clinic UI.'));
    await click(/^Orders(?:$|\s)/); await click(/^Operations(?:$|\s)/); await click('Visit a location');
    await click(/^University District\./); await click(/^Free Clinic\./); await click('Confirm order');
    await click(/^(?:Wait a day|Carry out your plans)/);
    for (let step = 0; step < 100 && !await available(/^Admit injured squad members$/); step++) {
      if (await available(/^Continue$/)) { await decision(); await click(/^Continue$/); }
      else await page.waitForTimeout(100);
    }
    await enlarged(); await capture('admission-menu');
    await click(/^Admit injured squad members$/); await settle();
    let current = (await snapshot('admitted')).state;
    let person = current.lcs.pool.find(p => p.id === patient.id);
    const clinicId = person.locationId;
    const clinic = current.cities.flatMap(c => c.districts.flatMap(d => d.sites))
      .find(s => `Site${s.id}` === clinicId && s.type === 'clinic');
    assert.ok(clinic); assert.equal(person.squadId, null);
    assert.ok(person._blood > patient._blood);
    assert.equal(person.medicalBills, 0);
    check('actual Free Clinic admission begins treatment and preserves money');
    await day(); current = (await snapshot('second-treatment-day')).state;
    person = current.lcs.pool.find(p => p.id === patient.id);
    if (person.locationId !== clinicId || person.daysHospitalized < 2)
      issue('Still-injured Free Clinic patient is returned to base instead of remaining in care.');
    else check('clinic patient remains admitted across the next daily turn');
    if (!baselineRun || person.locationId === clinicId) {
      let days = 2;
      while (person.locationId === clinicId && days < 20) {
        await day(); current = (await snapshot(`treatment-day-${++days}`)).state;
        person = current.lcs.pool.find(p => p.id === patient.id);
      }
      assert.equal(person.locationId, `Site${person.baseId}`); assert.equal(person._blood, 1);
      assert.equal(person.squadId, null); assert.equal(person.daysHospitalized, 0);
      assert.equal(person.medicalBills, 0); assert.equal(current.ledger._funds, state.ledger._funds);
      assert.deepEqual(person.equippedWeapon, patient.equippedWeapon);
      assert.deepEqual(person.spareAmmo, patient.spareAmmo);
      assert.equal(person.portraitId, patient.portraitId);
      assert.equal(person.body.leftArm.bleedingStacks, 0);
      check('free care heals and discharges to headquarters without fees or lost equipment');
      report.outcomes.clinic = { patientId: person.id, days, funds: current.ledger._funds,
        medicalBills: person.medicalBills, finalLocation: person.locationId, blood: person._blood };
      await capture('discharged-to-headquarters');
    }
  }
  await verifyLoadedScript(expected.toLowerCase());
  assert.deepEqual(report.pageErrors, []); assert.deepEqual(report.consoleErrors, []); assert.deepEqual(report.failedRequests, []);
  report.status = report.issues.length ? 'baseline-issues-reproduced' : 'passed';
} catch (error) {
  report.status = 'failed'; report.error = error.stack ?? String(error); process.exitCode = 1;
  if (page) {
    await page.screenshot({ path: resolve(output, 'FAILURE.png'), fullPage: true }).catch(() => {});
    await writeFile(resolve(output, 'FAILURE.txt'), await decodeText().catch(() => '')).catch(() => {});
  }
} finally {
  await context?.close(); await browser.close();
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ status: report.status, output, checks: report.checks.length, issues: report.issues, error: report.error }));
}
