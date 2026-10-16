// Real mission, treatment and custody journeys in disposable browser contexts.
// Prepared conditions are recorded separately from decisions exercised in play.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertQaUrl, chromiumLaunchOptions } from './browser_support.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const args = process.argv.slice(2);
const arg = (name, fallback) => args.includes(name) ? args[args.indexOf(name) + 1] : fallback;
const only = arg('--only', 'all');
assert.ok(['all', 'operation', 'conversation', 'paid-care', 'unpaid-care', 'custody'].includes(only),
  'Unknown --only scenario.');
const url = assertQaUrl(arg('--url', undefined));
const expected = arg('--expected-hash', '');
assert.match(expected, /^[a-f0-9]{64}$/i, 'Pass the exact rebuilt main.dart.js SHA-256.');
const output = resolve(root, arg('--out', `reports/mission-browser-${Date.now()}`));
assert.ok(relative(resolve(root, 'reports'), output) &&
  !relative(resolve(root, 'reports'), output).startsWith('..'), 'Keep evidence under ignored reports/.');
await mkdir(output, { recursive: true });
const decode = save => typeof save.saveData === 'string' ? JSON.parse(save.saveData) : save.saveData;
const original = JSON.parse(await readFile(resolve(root, 'upstream/test/saves/felix_1_0.json'), 'utf8'));
const seed = decode(original);
for (const person of seed.lcs.pool) {
  person.wantedForCrimes = Object.fromEntries(Object.keys(person.wantedForCrimes).map(k => [k, 0]));
  person.heat = 0;
  person.activity = { type: 'none' };
}
const report = { status: 'running', url, expectedHash: expected, prepared: [], checks: [],
  scenarios: {}, screenshots: [], decisions: [], pageErrors: [], consoleErrors: [], failedRequests: [] };
const response = await fetch(new URL('main.dart.js', url));
assert.ok(response.ok);
report.mainJsSha256 = createHash('sha256').update(Buffer.from(await response.arrayBuffer())).digest('hex');
assert.equal(report.mainJsSha256, expected.toLowerCase(), 'QA server must serve this exact compiled build.');
const browser = await chromium.launch(chromiumLaunchOptions({ args }));
let context, page, normalizedEnvelope, normalizedState;
let scenario = '';
const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
async function uiText() {
  if (!await page.locator('flt-semantics-host').count()) return '';
  return page.locator('flt-semantics-host').evaluate(host => [host.innerText,
    ...[...host.querySelectorAll('[aria-label]')].map(n => n.getAttribute('aria-label')),
    ...[...host.querySelectorAll('input,textarea')].map(n => n.value),
  ].filter(Boolean).join('\n'));
}
async function wait(pattern) {
  const deadline = Date.now() + 20000;
  while (Date.now() < deadline) {
    if (pattern.test(await uiText())) return;
    await page.waitForTimeout(80);
  }
  throw Error(`Missing ${pattern}: ${await uiText()}`);
}
const button = name => page.getByRole('button', { name }).first();
async function available(name) { return await button(name).count() > 0 && await button(name).isEnabled(); }
async function click(name) {
  await button(name).click();
  await page.mouse.move(2, 2);
  await page.waitForTimeout(130);
}
function check(name) { report.checks.push(`${scenario}: ${name}`); console.log(`PASS ${scenario}: ${name}`); }
async function capture(name) {
  const filename = `${scenario}-${name}.png`;
  await page.mouse.move(2, 2);
  await page.waitForTimeout(250);
  await page.screenshot({ path: resolve(output, filename), fullPage: true });
  report.screenshots.push(filename);
  await writeFile(resolve(output, `${scenario}-${name}.txt`), await uiText());
}
async function fresh() {
  await context?.close();
  context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, acceptDownloads: true });
  page = await context.newPage();
  page.setDefaultTimeout(8000);
  page.on('pageerror', e => report.pageErrors.push({ scenario, error: String(e) }));
  page.on('console', m => { if (m.type() === 'error') report.consoleErrors.push({ scenario, error: m.text() }); });
  page.on('requestfailed', r => report.failedRequests.push({ scenario, url: r.url() }));
  await page.goto(url, { waitUntil: 'networkidle' });
  await wait(/Start a New Game/);
}
async function fixture(name, state, changes, envelope = normalizedEnvelope ?? original) {
  const save = structuredClone(envelope);
  save.saveData = typeof save.saveData === 'string' ? JSON.stringify(state) : state;
  const path = resolve(output, `prepared-${name}.json`);
  await writeFile(path, JSON.stringify(save));
  report.prepared.push({ name, path: `prepared-${name}.json`, changes });
  return path;
}
async function importLoad(path) {
  const choosing = page.waitForEvent('filechooser');
  await click(/^Import a Save/);
  await (await choosing).setFiles(path);
  await wait(/Save imported/);
  await page.keyboard.press('Enter');
  await wait(/Start a New Game/);
  await click(/^Load & Manage Saves/);
  await click(/^A(?:\s|$)/);
  await click(/^L Load Game/);
  await wait(/Save & exit/);
}
async function exportGame(name) {
  assert.ok(await available(/^Save & exit/), 'Save only at the current headquarters reader.');
  await click(/^Save & exit/);
  await wait(/Start a New Game/);
  await click(/^Load & Manage Saves/);
  await click(/^A(?:\s|$)/);
  const downloading = page.waitForEvent('download');
  await click(/Export Save File/);
  const path = resolve(output, `${scenario}-${name}.json`);
  await (await downloading).saveAs(path);
  const envelope = JSON.parse(await readFile(path, 'utf8'));
  await click(/^L Load Game/);
  await wait(/Save & exit/);
  return { path, envelope, state: decode(envelope) };
}
async function roundTrip(name) {
  const saved = await exportGame(name);
  // The first export already reloads through the original save menu. Reload
  // the browser too, then transfer to a completely new storage context.
  await page.reload({ waitUntil: 'networkidle' });
  await wait(/Continue Game|Continue Previous|Continue Last|Continue Saved|Continue/);
  await click(/^Continue/);
  await wait(/Save & exit/);
  const reloaded = await exportGame(`${name}-reloaded`);
  assert.deepEqual(reloaded.state, saved.state, 'Browser reload must preserve the complete campaign.');
  await fresh();
  await importLoad(saved.path);
  const restored = await exportGame(`${name}-reimported`);
  assert.deepEqual(restored.state, saved.state,
    'Fresh-context transfer must retain condition, portraits, equipment, squads, orders, money and progress exactly.');
  check('save, browser reload and fresh-context reimport preserve the complete campaign exactly');
  return saved.state;
}
async function recordDecision() {
  report.decisions.push({ scenario, text: await uiText(), buttons: await page.getByRole('button')
    .evaluateAll(ns => ns.map(n => ({ label: n.getAttribute('aria-label') ?? n.textContent,
      disabled: n.getAttribute('aria-disabled') === 'true' }))) });
}
async function reports() {
  for (let i = 0; i < 100; i++) {
    if (!await available(/^Continue$/)) return;
    await recordDecision();
    await click(/^Continue$/);
  }
  throw Error('Too many consecutive reports.');
}
async function visit(district, site) {
  await click(/^Orders(?:$|\s)/);
  await click(/^Operations(?:$|\s)/);
  await click('Visit a location');
  await click(new RegExp(`^${escape(district)}\\.`));
  await click(new RegExp(`^${escape(site)}\\.`));
  await click('Confirm order');
  await click(/^(?:Wait a day|Carry out your plans)/);
  await reports();
}
async function waitEncounter(control) {
  for (let turn = 0; turn < 120; turn++) {
    await reports();
    if (await available(control)) return;
    assert.ok(await available(/^S Wait \/ stall$/), `Need tactical reader: ${await uiText()}`);
    await click(/^S Wait \/ stall$/);
  }
  throw Error(`No encounter offering ${control} in 120 actual wait turns.`);
}
async function exitBuilding() {
  for (let step = 0; step < 100; step++) {
    await reports();
    if (await available(/^Save & exit/)) return;
    if (await available('Move up')) await click('Move up');
    else if (await available(/^V (?:Flee|Sneak away)$/)) {
      await click(/^V (?:Flee|Sneak away)$/);
      await click('Move up');
    } else if (await available(/^D.*(?:lose|escape)/)) await click(/^D.*(?:lose|escape)/);
    else if (await available(/^Y Yes$/)) await click(/^Y Yes$/);
    else if (await available(/^D Break off the meetings/)) await click(/^D Break off the meetings/);
    else throw Error(`Unexpected exit reader: ${await uiText()}`);
  }
  throw Error('Operation did not return to headquarters.');
}
async function day({ pay = false, defense = false } = {}) {
  await click(/^(?:Wait a day|Carry out your plans)/);
  const bills = [];
  for (let prompt = 0; prompt < 400; prompt++) {
    if (await available(/^Save & exit/)) return bills;
    if (await available(/^Pay \$\d+$/) || await available(/^Leave with \$/)) {
      await recordDecision();
      await capture(`bill-${report.decisions.length}`);
      const payButton = button(/^Pay \$\d+$/);
      const amount = Number((await payButton.innerText()).match(/\$(\d+)/)[1]);
      bills.push({ amount, paid: pay });
      if (pay) { assert.ok(await payButton.isEnabled()); await click(/^Pay \$\d+$/); }
      else { assert.equal(await payButton.isEnabled(), false); await click(/^Leave with \$/); }
    } else if (defense && await available(/^Court-appointed attorney$/)) {
      await recordDecision();
      await capture('court-defense');
      assert.equal(await button(/^Hire elite attorney/).isEnabled(), false);
      await page.keyboard.press('z');
      await page.waitForTimeout(150);
      assert.ok(await available(/^Plead guilty$/), 'Invalid input must retain the same defense choices.');
      await click(/^Plead guilty$/);
      check('court defense retains choices on invalid input and rejects unaffordable elite counsel');
    } else if (await available(/^Continue$/)) { await recordDecision(); await click(/^Continue$/); }
    else if (await available(/^D Break off the meetings/)) await click(/^D Break off the meetings/);
    else if (await available(/Read newspaper|Read the paper|Done reading/)) await click(/Read newspaper|Read the paper|Done reading/);
    // Scene generation and animated monthly results can paint a frame before
    // the next original reader is ready. Wait; never invent an acknowledgement.
    else await page.waitForTimeout(100);
  }
  throw Error(`Daily turn did not resolve: ${await uiText()}`);
}

try {
  scenario = 'operation';
  await fresh();
  const initial = await fixture('operation', seed,
    ['Copy of bundled Felix fixture; old wanted crimes/heat cleared; personal orders set to none. No skills, equipment, funds, date or outcomes altered.']);
  await importLoad(initial);
  const baseline = await exportGame('baseline');
  normalizedEnvelope = baseline.envelope;
  normalizedState = baseline.state;
  if (['all', 'operation'].includes(only)) {
    await visit('Downtown Seattle', 'Police Station');
    await click('Move down'); await reports();
    await click('Move down'); await reports();
    await click('Move down'); await reports();
    check('entered a building, opened its entrance and moved inside');
    await waitEncounter(/^V (?:Flee|Sneak away)$/);
    await capture('encounter-visible');
    const beforeInspect = await uiText();
    await click(`Inspect ${baseline.state.lcs.pool[0].name} dossier`);
    await wait(/Full dossier/);
    await capture('field-inspector');
    await click('Close crew inspection');
    assert.equal(await uiText(), beforeInspect, 'Read-only field inspection must retain the operation.');
    check('field portrait opens and closes a dossier without advancing the reader');
    await click(/^V (?:Flee|Sneak away)$/);
    assert.ok(await available('Move up'));
    assert.ok(await available(/Cancel escape$/));
    await page.keyboard.press('z'); await page.waitForTimeout(150);
    assert.ok(await available('Move up'));
    await capture('retreat-directions');
    await click(/Cancel escape$/);
    await click(/^F Fight$/);
    await reports();
    check('combat dispatched through the current source control');
    if (!await available(/^V (?:Flee|Sneak away)$/)) await waitEncounter(/^V (?:Flee|Sneak away)$/);
    await click(/^V (?:Flee|Sneak away)$/);
    await click('Move up');
    await reports();
    await exitBuilding();
    const after = await exportGame('returned');
    const originalAmmo = baseline.state.lcs.pool.reduce((n, p) => n + (p.equippedWeapon?.ammo ?? 0), 0);
    const remainingAmmo = after.state.lcs.pool.reduce((n, p) => n + (p.equippedWeapon?.ammo ?? 0), 0);
    assert.ok(remainingAmmo < originalAmmo, 'Actual combat consumes ammunition.');
    assert.ok(after.state.date > baseline.state.date, 'The completed operation advances campaign time.');
    assert.ok(after.state.lcs.pool.filter(p => p.squadId != null).every(p => p.locationId === `Site${p.baseId}`));
    check('retreat resolves the operation, returns survivors to HQ and retains spent ammunition');
    report.scenarios.operation = { date: after.state.date, originalAmmo, remainingAmmo,
      people: after.state.lcs.pool.map(p => ({ id: p.id, alive: p.alive, blood: p._blood, location: p.locationId })) };
    await capture('returned-to-headquarters');
    let recovered = await roundTrip('complete');
    const wounded = recovered.lcs.pool.filter(p => p.alive && p._blood < 1);
    report.scenarios.operation.actualWoundedIds = wounded.map(p => p.id);
    if (wounded.length) {
      await visit('University District', 'University Hospital');
      await capture('actual-wounds-hospital-menu');
      await click(/^Admit injured squad members$/);
      await reports();
      recovered = (await exportGame('actual-admission')).state;
      const patients = recovered.lcs.pool.filter(p => p.locationId === 'Site12');
      assert.ok(patients.length > 0, 'Actual combat injuries must reach the real admission handler.');
      const bills = [];
      let healingDays = 0;
      while (recovered.lcs.pool.some(p => p.alive && p.locationId === 'Site12') && healingDays < 62) {
        bills.push(...await day());
        recovered = (await exportGame(`actual-care-${++healingDays}`)).state;
      }
      for (const admitted of patients) {
        const returned = recovered.lcs.pool.find(p => p.id === admitted.id);
        assert.ok(returned, 'Retain each admitted crew identity.');
        if (returned.alive) {
          assert.equal(returned.locationId, `Site${returned.baseId}`);
          assert.equal(returned.squadId, null);
          assert.ok(returned._blood >= admitted._blood);
          assert.deepEqual(returned.equippedWeapon, admitted.equippedWeapon);
          assert.deepEqual(returned.spareAmmo, admitted.spareAmmo);
          assert.equal(returned.portraitId, admitted.portraitId);
        }
      }
      report.scenarios.operation.actualRecovery = { healingDays, bills, patientIds: patients.map(p => p.id) };
      check('actually sustained mission injuries receive hospital care and return through original discharge decisions');
      await roundTrip('actual-recovery-complete');
    }
  }
  if (['all', 'conversation'].includes(only)) {
    scenario = 'conversation';
    const state = structuredClone(normalizedState);
    for (const p of state.lcs.pool) { p.equippedWeapon = null; p.spareAmmo = null; }
    await fresh();
    await importLoad(await fixture('conversation', state,
      ['Separate unarmed copy of normalized baseline; all weapons/reserve ammunition removed before play so the conversation is not interrupted by visible firearms. No skill or opinion changes.']));
    await visit('Industrial District', 'Chilton St. Housing Projects');
    await click('Move down'); await reports();
    await click('Move down'); await reports();
    await waitEncounter(/^T Talk$/);
    await click(/^T Talk$/);
    for (let step = 0; step < 8; step++) {
      await reports();
      if (await available(/^A Strike up a conversation/)) break;
      const candidates = page.getByRole('button', { name: /^(?:[1-6]|[A-Z]) / });
      let selected = false;
      for (const candidate of await candidates.all()) {
        if (await candidate.isEnabled()) { await candidate.click(); await page.waitForTimeout(150); selected = true; break; }
      }
      assert.ok(selected, `No current conversation participant: ${await uiText()}`);
    }
    assert.ok(await available(/^A Strike up a conversation/));
    await page.keyboard.press('z'); await page.waitForTimeout(150);
    assert.ok(await available(/^A Strike up a conversation/));
    await capture('conversation-retry');
    await click(/^A Strike up a conversation/);
    // Follow real conversation acknowledgements; if persuasion reaches the
    // issue reader, use its own explicit cancellation choice.
    for (let step = 0; step < 50; step++) {
      if (await available(/^S Wait \/ stall$/)) break;
      if (await available(/^Continue$/)) { await recordDecision(); await click(/^Continue$/); }
      else if (await available(/On second thought|Never mind|Nevermind|Nothing|Forget it|Cancel|Goodbye/i))
        await click(/On second thought|Never mind|Nevermind|Nothing|Forget it|Cancel|Goodbye/i);
      else {
        const choices = page.getByRole('button', { name: /^[A-Z] / });
        const choice = await choices.all();
        let selected = false;
        for (const item of choice) if (await item.isEnabled()) { await item.click(); selected = true; break; }
        assert.ok(selected, `Unhandled conversation reader: ${await uiText()}`);
      }
    }
    check('met a real building occupant and exercised political conversation; invalid input keeps choices');
    await exitBuilding();
    await roundTrip('complete');
  }
  for (const pay of [true, false]) if (['all', pay ? 'paid-care' : 'unpaid-care'].includes(only)) {
    scenario = pay ? 'paid-care' : 'unpaid-care';
    const state = structuredClone(normalizedState);
    const patient = state.lcs.pool[1];
    patient._blood = 0.94;
    patient.body.leftArm.shot = true;
    patient.body.leftArm.bleedingStacks = 1;
    state.ledger._funds = pay ? 5000 : 7;
    await fresh();
    await importLoad(await fixture(scenario, state,
      [`Prepared ${patient.name} with 94% blood and one bleeding arm wound at headquarters; starting funds $${state.ledger._funds}. Admission, stabilization, daily healing, bill and discharge are produced through the original browser handlers.`]));
    const before = (await exportGame('baseline')).state;
    await visit('University District', 'University Hospital');
    assert.match(await uiText(), /Visit in progress/);
    assert.doesNotMatch(await uiText(), /Visit queued · advance the day to travel/);
    await capture('hospital-menu');
    await page.setViewportSize({ width: 800, height: 600 });
    await click(/^Reading size/); await page.getByRole('menuitem', { name: '150%', exact: true }).click();
    await capture('hospital-menu-800x600-at150');
    await click(/^Admit injured squad members$/);
    await reports();
    let current = (await exportGame('admitted')).state;
    let person = current.lcs.pool.find(p => p.id === patient.id);
    assert.equal(person.locationId, 'Site12'); assert.equal(person.squadId, null);
    assert.deepEqual(person.equippedWeapon, patient.equippedWeapon);
    assert.deepEqual(person.spareAmmo, patient.spareAmmo);
    assert.equal(person.portraitId, patient.portraitId);
    assert.ok(person._blood > patient._blood, 'Actual hospital care restores blood.');
    assert.equal(person.body.leftArm.bleedingStacks, 0, 'Hospital care stabilizes prepared bleeding.');
    check('hospital admission removes only the injured member from their squad and preserves equipment/portrait');
    const bills = [];
    for (let elapsed = 0; elapsed < 8 && person.locationId === 'Site12'; elapsed++) {
      bills.push(...await day({ pay }));
      current = (await exportGame(`care-day-${elapsed + 1}`)).state;
      person = current.lcs.pool.find(p => p.id === patient.id);
    }
    assert.equal(bills.length, 1); assert.ok(bills[0].amount > 0);
    assert.equal(person.locationId, `Site${patient.baseId}`); assert.equal(person.squadId, null);
    assert.equal(person._blood, 1); assert.equal(person.daysHospitalized, 0);
    assert.equal(person.medicalBills, pay ? 0 : bills[0].amount);
    assert.equal(current.ledger._funds, before.ledger._funds - (pay ? bills[0].amount : 0));
    assert.deepEqual(person.equippedWeapon, patient.equippedWeapon);
    assert.deepEqual(person.spareAmmo, patient.spareAmmo);
    report.scenarios[scenario] = { patientId: patient.id, bills, funds: current.ledger._funds };
    check('daily care, bill availability, money/debt and squadless return are correct');
    await roundTrip('complete');
  }
  if (['all', 'custody'].includes(only)) {
    scenario = 'custody';
    const state = structuredClone(normalizedState);
    state.date = '2023-01-31T00:00:00.000';
    const defendant = state.lcs.pool[1], detainee = state.lcs.pool[2], prisoner = state.lcs.pool[3];
    for (const p of [defendant, detainee, prisoner]) {
      p.squadId = null; p.equippedWeapon = null; p.spareAmmo = null;
      state.lcs.squads[0].members = state.lcs.squads[0].members.filter(id => id !== p.id);
      p.equippedClothing = { ...p.equippedClothing, typeName: 'CLOTHING_PRISONER', bloody: false, damaged: false };
    }
    defendant.locationId = 'Site6'; defendant.wantedForCrimes.theft = 2;
    detainee.locationId = 'Site5'; detainee.wantedForCrimes.loitering = 1; detainee.heat = 0;
    prisoner.locationId = 'Site26'; prisoner.sentence = 1; prisoner.pastConvictions.theft = 1;
    await fresh();
    await importLoad(await fixture('custody', state,
      ['Separate January 31 custody fixture: one defendant awaiting trial with two theft charges, one police detainee with a loitering charge, one prisoner with one month remaining. Their weapons/ammo and squad membership are already removed. Starting arrests and incarceration were prepared, not earned in browser play. The next actual daily/monthly turn must transfer the detainee, conduct the trial, and release the prisoner.']));
    const before = (await exportGame('baseline')).state;
    await page.setViewportSize({ width: 800, height: 600 });
    await click(/^Reading size/); await page.getByRole('menuitem', { name: '150%', exact: true }).click();
    await day({ defense: true });
    const after = (await exportGame('resolved')).state;
    assert.equal(after.date.slice(0, 10), '2023-02-01');
    const tried = after.lcs.pool.find(p => p.id === defendant.id);
    const transferred = after.lcs.pool.find(p => p.id === detainee.id);
    const released = after.lcs.pool.find(p => p.id === prisoner.id);
    assert.equal(transferred.locationId, 'Site6', 'Monthly system transfers police detainee to courthouse.');
    assert.equal(transferred.equippedClothing.typeName, 'CLOTHING_PRISONER');
    assert.equal(released.locationId, `Site${released.baseId}`); assert.equal(released.sentence, 0);
    assert.equal(released.squadId, null); assert.equal(released.equippedClothing.typeName, 'CLOTHING_CLOTHES');
    assert.ok(Object.values(tried.wantedForCrimes).every(n => n === 0));
    assert.equal(tried.pastConvictions.theft, before.lcs.pool.find(p => p.id === defendant.id).pastConvictions.theft + 2,
      'The actual guilty plea must be retained in the conviction history.');
    assert.ok(tried.sentence > 0 && tried.locationId === 'Site26' || tried.locationId === `Site${tried.baseId}`,
      'A resolved guilty plea must leave an actual sentence or a return to base.');
    for (const prior of before.lcs.pool) {
      const current = after.lcs.pool.find(p => p.id === prior.id);
      assert.equal(current.portraitId, prior.portraitId);
      if ([defendant.id, detainee.id, prisoner.id].includes(prior.id)) {
        assert.equal(current.equippedWeapon, null); assert.equal(current.spareAmmo, null); assert.equal(current.squadId, null);
      }
    }
    check('actual month transition transfers custody, resolves trial and releases a sentence without restoring confiscated equipment');
    report.scenarios.custody = { defendant: { id: tried.id, sentence: tried.sentence, location: tried.locationId },
      detainee: { id: transferred.id, location: transferred.locationId }, prisoner: { id: released.id, location: released.locationId } };
    await roundTrip('complete');
  }
  assert.deepEqual(report.pageErrors, []);
  assert.deepEqual(report.consoleErrors, []);
  assert.deepEqual(report.failedRequests, []);
  report.status = 'passed';
} catch (error) {
  report.status = 'failed'; report.error = error.stack ?? String(error); process.exitCode = 1;
  if (page) {
    await page.screenshot({ path: resolve(output, 'FAILURE.png'), fullPage: true }).catch(() => {});
    await writeFile(resolve(output, 'FAILURE.txt'), await uiText().catch(() => '')).catch(() => {});
    await writeFile(resolve(output, 'FAILURE.html'),
      await page.locator('flt-semantics-host').innerHTML().catch(() => '')).catch(() => {});
  }
} finally {
  await context?.close(); await browser.close();
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ status: report.status, output, checks: report.checks.length, error: report.error }));
}
