// Original siege responses in isolated campaigns on the QA origin only.
// Siege conditions, equipment and drill geometry are declared preparations.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertQaUrl, chromiumLaunchOptions, createQaPage, observeMainScript } from './browser_support.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const args = process.argv.slice(2);
const arg = (name, fallback) => args.includes(name) ? args[args.indexOf(name) + 1] : fallback;
const url = assertQaUrl(arg('--url', undefined));
const expected = arg('--expected-hash', '');
assert.match(expected, /^[a-f0-9]{64}$/i, 'Provide the exact rebuilt main.dart.js SHA-256.');
const only = arg('--only', 'all');
assert.ok(['all', 'defense', 'escape', 'surrender', 'assault-escape'].includes(only));
const baselineRun = args.includes('--baseline');
const output = resolve(root, arg('--out', `reports/siege-chase-20261016/siege-${Date.now()}`));
const rel = relative(resolve(root, 'reports'), output);
assert.ok(rel && !rel.startsWith('..'), 'Keep evidence under reports/.');
await mkdir(output, { recursive: true });
const decode = envelope => typeof envelope.saveData === 'string' ? JSON.parse(envelope.saveData) : envelope.saveData;
const original = JSON.parse(await readFile(resolve(root, 'upstream/test/saves/felix_1_0.json'), 'utf8'));
const experienced = decode(JSON.parse(await readFile(resolve(root, 'upstream/test/saves/EQ_1_1.json'), 'utf8')));
const seed = decode(original);
for (const person of seed.lcs.pool) {
  person.wantedForCrimes = Object.fromEntries(Object.keys(person.wantedForCrimes).map(key => [key, 0]));
  person.heat = 0; person.activity = { type: 'none' };
}
const report = { status: 'running', url, expectedHash: expected, baselineRun, prepared: [], checks: [],
  issues: [], decisions: [], screenshots: [], outcomes: {}, pageErrors: [], consoleErrors: [], failedRequests: [] };
const main = await fetch(new URL('main.dart.js', url));
assert.ok(main.ok);
report.mainJsSha256 = createHash('sha256').update(Buffer.from(await main.arrayBuffer())).digest('hex');
assert.equal(report.mainJsSha256, expected.toLowerCase());
const browser = await chromium.launch(chromiumLaunchOptions({ args }));
let context, page, verifyLoadedScript, scene = 'setup', normalized, serial = 0;
const button = name => page.getByRole('button', { name }).first();
async function available(name) { return await button(name).count() > 0 && await button(name).isEnabled(); }
async function text() {
  if (!await page.locator('flt-semantics-host').count()) return '';
  return page.locator('flt-semantics-host').evaluate(host => [host.innerText,
    ...[...host.querySelectorAll('[aria-label]')].map(node => node.getAttribute('aria-label')),
  ].filter(Boolean).join('\n'));
}
async function wait(pattern) {
  const deadline = Date.now() + 20000;
  while (Date.now() < deadline) { if (pattern.test(await text())) return; await page.waitForTimeout(80); }
  throw Error(`Missing ${pattern}: ${await text()}`);
}
async function click(name) {
  const deadline = Date.now() + 12000;
  while (!await available(name) && Date.now() < deadline) await page.waitForTimeout(80);
  assert.ok(await available(name), `Need enabled current control ${name}: ${await text()}`);
  await button(name).click(); await page.mouse.move(2, 2); await page.waitForTimeout(150);
}
function check(message) { report.checks.push(`${scene}: ${message}`); console.log(`PASS ${scene}: ${message}`); }
function issue(message) {
  report.issues.push(`${scene}: ${message}`);
  if (!baselineRun) throw Error(message);
  console.log(`REPRODUCED ${scene}: ${message}`);
}
async function decision(kind) {
  const current = await text();
  report.decisions.push({ scene, kind, text: current, buttons: await page.getByRole('button')
    .evaluateAll(nodes => nodes.map(node => ({ label: node.getAttribute('aria-label') ?? node.textContent,
      disabled: node.getAttribute('aria-disabled') === 'true' }))) });
  return current;
}
async function capture(name) {
  await page.mouse.move(2, 2); await page.waitForTimeout(200);
  const file = `${scene}-${name}`;
  await page.screenshot({ path: resolve(output, `${file}.png`), fullPage: true });
  await writeFile(resolve(output, `${file}.txt`), await text()); report.screenshots.push(`${file}.png`);
}
async function fresh() {
  if (verifyLoadedScript) await verifyLoadedScript(expected.toLowerCase());
  ({ context, page } = await createQaPage(browser, {
    previousContext: context, report, errorContext: () => ({ scene }), timeout: 10000,
  }));
  verifyLoadedScript = observeMainScript(page, report);
  await page.goto(url, { waitUntil: 'networkidle' }); await wait(/Start a New Game/);
}
async function prepared(name, state, description, envelope = normalized?.envelope ?? original) {
  const env = structuredClone(envelope);
  env.saveData = typeof env.saveData === 'string' ? JSON.stringify(state) : state;
  const path = resolve(output, `prepared-${name}.json`);
  await writeFile(path, JSON.stringify(env)); report.prepared.push({ scene: name, path, description }); return path;
}
async function importLoad(path) {
  const choosing = page.waitForEvent('filechooser'); await click(/^Import a Save/);
  await (await choosing).setFiles(path); await wait(/Save imported/); await page.keyboard.press('Enter');
  await wait(/Start a New Game/); await click(/^Load & Manage Saves/);
  await click(/^A(?:\s|$)/); await click(/^L Load Game/); await wait(/Save & exit/);
}
async function snapshot(name) {
  await click(/^Save & exit/); await wait(/Start a New Game/);
  await click(/^Load & Manage Saves/); await click(/^A(?:\s|$)/);
  const downloading = page.waitForEvent('download'); await click(/Export Save File/);
  const path = resolve(output, `${scene}-${++serial}-${name}.json`); await (await downloading).saveAs(path);
  const envelope = JSON.parse(await readFile(path, 'utf8'));
  await click(/^L Load Game/); await wait(/Save & exit/);
  return { state: decode(envelope), envelope, path };
}
const allSites = state => state.cities.flatMap(city => city.districts.flatMap(district => district.sites));
const person = (state, id) => state.lcs.pool.find(candidate => candidate.id === id);
function fixture(mode) {
  const state = structuredClone(normalized.state);
  const targetId = mode === 'defense' ? 20 : 21, remoteId = targetId === 20 ? 21 : 20;
  const target = allSites(state).find(site => site.id === targetId);
  const recruits = mode === 'escape' ? [944, 1119, 2480, 4338] : [9, 1955, 1975];
  const locals = mode === 'escape' ? recruits : [0, 2, 3, ...recruits];
  const remoteIds = mode === 'escape' ? [0, 2, 3, 4] : [4];
  for (const id of recruits) state.lcs.pool.push(structuredClone(experienced.lcs.pool.find(p => p.id === id)));
  state.nextCreatureId = Math.max(state.nextCreatureId, ...recruits.map(id => id + 1));
  for (const id of locals) {
    const p = person(state, id);
    p.hireId = id === 0 ? null : 0; p.baseId = targetId; p.locationId = `Site${targetId}`; p.squadId = 0;
    p.activity = { type: 'none' }; p.heat = 0;
    p.carId = null; p.preferredCarId = null; p.isDriver = false; p.preferredDriver = false;
    p.wantedForCrimes = Object.fromEntries(Object.keys(p.wantedForCrimes).map(key => [key, key === 'theft' ? 1 : 0]));
    p.equippedWeapon = structuredClone(normalized.state.lcs.pool[0].equippedWeapon);
    p.spareAmmo = structuredClone(normalized.state.lcs.pool[0].spareAmmo);
    // Standard source SWAT equipment, at its authored full armor values.
    p.equippedClothing = { stackSize: 1, typeName: 'CLOTHING_SWATARMOR', bloody: false, damaged: false,
      _quality: 1, armorId: 'ARMOR_SWAT', bodyArmor: 160, headArmor: 80, _limbArmor: {} };
    delete p.equippedArmor;
  }
  const patient = person(state, 1);
  patient.locationId = 'Site12'; patient.baseId = targetId; patient.squadId = null;
  patient._blood = .8; patient.body.leftArm.shot = true; patient.body.leftArm.bleedingStacks = 1;
  patient.daysHospitalized = 2;
  for (const id of remoteIds) {
    const p = person(state, id); p.locationId = `Site${remoteId}`; p.baseId = remoteId; p.squadId = 1;
  }
  const remote = person(state, 4);
  remote._blood = .9; remote.body.rightArm.shot = true; remote.body.rightArm.bleedingStacks = 1;
  state.lcs.squads = [{ ...state.lcs.squads[0], name: 'Local defenders', members: locals, activity: { type: 'none' } },
    { id: 1, name: 'Off-site crew', members: remoteIds, activity: { type: 'none' }, loot: [] }];
  state.nextSquadId = Math.max(state.nextSquadId, 2);
  state.activeSquadId = 0; state.activeSafehouseId = targetId;
  target.controller = 'lcs'; target.rent = targetId === 21 ? 100 : 0;
  target.siege.activeSiegeType = 'police'; target.siege.underAttack = mode !== 'escape';
  target.siege.escalationState = 'police'; target.siege.timeUntilCops = -1;
  target.compound.fortified = targetId === 21; target.compound.boobyTraps = targetId === 21;
  target.compound.rations = targetId === 21 ? 1000 : 0;
  target.loot = [structuredClone(normalized.state.lcs.pool[0].equippedWeapon)];
  state.lcs.vehiclePool = [
    { id: 0, typeName: 'SPORTSCAR', color: 'Blue', year: 2024, heat: 0, locationId: targetId },
    { id: 1, typeName: 'VAN', color: 'White', year: 2022, heat: 0, locationId: targetId },
    { id: 2, typeName: 'SPORTSCAR', color: 'Red', year: 2023, heat: 0, locationId: remoteId },
  ];
  state.nextVehicleId = 3;
  if (mode === 'assault-escape') {
    for (const id of locals) {
      person(state, id).preferredCarId = 0; person(state, id).preferredDriver = id === 9;
      person(state, id).carId = 0; person(state, id).isDriver = id === 9;
    }
    // Explicit open-floor drill like the existing engine evacuation fixture.
    // The original map generator, enemy units, traps and movement still run.
    target.changes = [];
    for (let x = 0; x < 70; x++) for (let y = 0; y < 23; y++) {
      target.changes.push({ x, y, z: 0, flag: 8192 });
      if (y === 0) target.changes.push({ x, y, z: 0, flag: 1 });
    }
  }
  return { state, targetId, remoteId, locals };
}
const giveUp = /^(?:G[-\s]*)?Give Up$/i;
const fightEscape = /^(?:F[-\s]*)?Fight\s*(?:\/|or)\s*Escape$/i;
const footFight = /^(?:F[-\s]*)?Fight$/i;
const lose = /^(?:D[-\s]*)?(?:Try to lose them|Dash away)$/i;
async function headquartersAction(name) {
  if (await available(name)) return click(name);
  if (!baselineRun) throw Error(`Siege response is hidden: ${name}: ${await text()}`);
  await click(/^HQ commands/);
  const menu = page.getByRole('menuitem', { name }).first();
  await menu.click(); await page.waitForTimeout(180);
}
async function inspectAndEnlarge(actorName) {
  await capture('headquarters'); const current = await decision('headquarters-siege');
  if (!await available(fightEscape) || !await available(giveUp)) issue('Main siege response controls are hidden in the headquarters journal.');
  if (!baselineRun) {
    assert.match(current, /siege|attack/i); assert.match(current, /Local defenders/); assert.match(current, /Off-site crew/);
    const inspect = `Dossier: ${actorName}`;
    if (await available(inspect)) {
      await click(inspect); await page.keyboard.press('g'); await page.keyboard.press('f');
      await page.waitForTimeout(150); await capture('dossier-keyboard-isolation');
      assert.ok(!await available(/^Continue$/), 'Inspecting cannot enter the surrender or fight reader.');
      if (await available(/^Close crew inspection$/)) await click(/^Close crew inspection$/);
      else if (await available(/^Close inspection$/)) await click(/^Close inspection$/);
      else if (await available(/^Close dossier$/)) await click(/^Close dossier$/);
      else await page.keyboard.press('Escape');
      await wait(/Safehouse under (?:attack|siege)/);
      check('siege inspection blocks battle and surrender keys');
    }
    await page.setViewportSize({ width: 1024, height: 720 }); await click(/^Reading size/);
    await page.getByRole('menuitem', { name: '150%', exact: true }).click(); await page.waitForTimeout(200);
    for (const name of [fightEscape, giveUp]) {
      const bounds = await button(name).boundingBox();
      assert.ok(bounds && bounds.y >= 0 && bounds.y + bounds.height <= page.viewportSize().height, `${name} is reachable at enlarged size.`);
    }
    await capture('headquarters-1024x720-at150'); check('current siege status and responses are reachable at 1024x720 with150% text');
  }
}
async function resolveOperation(mode) {
  let fighting = 0, running = 0, tacticalSteps = 0, carSteps = 0, sawPursuit = false, sawTactical = false;
  let stalled = 0;
  for (let step = 0; step < 1200; step++) {
    if (await available(/^Save & exit/) && !await available(fightEscape)) return { fighting, running, tacticalSteps, carSteps, sawPursuit, sawTactical };
    if (await available(/^Continue$/)) { await decision('report'); await click(/^Continue$/); }
    else if (await available(/^(?:C[-\s]*)?(?:Press C to Continue Liberally\.?|Continue Liberally\.?|Reflect.*)$/i)) {
      await decision('source-completion'); await click(/^(?:C[-\s]*)?(?:Press C to Continue Liberally\.?|Continue Liberally\.?|Reflect.*)$/i);
    } else if (/Car pursuit/.test(await text())) {
      await decision('car-evacuation');
      if (await available(/^Drive hard to escape$/)) await click(/^Drive hard to escape$/);
      else if (await available(/^Slow down$/)) await click(/^Slow down$/);
      else throw Error(`No current car evacuation control: ${await text()}`);
      carSteps++;
    } else if (await available(lose) || (/On-foot pursuit/.test(await text()) && await available(footFight))) {
      sawPursuit = true; await decision('pursuit');
      if (mode === 'defense') { assert.ok(await available(footFight)); await click(footFight); fighting++; }
      else if (await available(lose)) { await click(lose); running++; }
      else throw Error(`Escape needs its current source run control: ${await text()}`);
    } else if (await available('Move up')) {
      sawTactical = true; await decision('tactical-drill'); await click('Move up'); tacticalSteps++;
    } else if (await available(/^V (?:Flee|Sneak away)$/)) {
      sawTactical = true; await decision('tactical-escape-direction');
      await click(/^V (?:Flee|Sneak away)$/); await click('Move up'); tacticalSteps++;
    } else if (await available(/^C (?:Reflect|Continue)/)) { await decision('completion'); await click(/^C (?:Reflect|Continue)/); }
    else {
      if (++stalled >= 40) {
        await decision('unrecognized-reader'); await capture('unrecognized-reader');
        throw Error(`No recognized current siege control: ${await text()}`);
      }
      await page.waitForTimeout(80);
      continue;
    }
    stalled = 0;
  }
  throw Error(`Siege did not resolve: ${await text()}`);
}
function outsidersUnchanged(before, after, locals) {
  for (const p of before.lcs.pool.filter(p => !locals.includes(p.id)))
    assert.deepEqual(person(after, p.id), p, `Siege must preserve outside person ${p.id}.`);
  assert.deepEqual(after.lcs.squads.find(squad => squad.id === 1), before.lcs.squads.find(squad => squad.id === 1));
  assert.deepEqual(after.lcs.vehiclePool.find(car => car.id === 2), before.lcs.vehiclePool.find(car => car.id === 2));
  assert.equal(after.ledger._funds, before.ledger._funds);
}
async function followRecovery(initial, locals, mode) {
  let current = initial, days = 0;
  let interruptedBySiege;
  const inCare = state => [1, ...locals].some(id => {
    const p = person(state, id); return p?.alive && p.locationId === 'Site12';
  });
  while (days < 62 && (inCare(current) ||
      (mode !== 'surrender' && locals.some(id => person(current, id)?.hidingDaysLeft > 0)))) {
    if (!await available(/^(?:Wait a day|Carry out your plans)/)) {
      const sieges = allSites(current).filter(site => site.siege.underAttack);
      if (sieges.length) {
        interruptedBySiege = sieges.map(site => ({ id: site.id, type: site.siege.activeSiegeType }));
        await decision('recovery-interrupted-by-new-siege'); await capture('recovery-interrupted-by-new-siege');
        break;
      }
    }
    await click(/^(?:Wait a day|Carry out your plans)/);
    for (let step = 0; step < 200; step++) {
      if (await available(/^Save & exit/)) break;
      if (await available(/^Continue$/)) { await decision('daily-recovery'); await click(/^Continue$/); }
      else if (await available(/^Leave with \$/)) { await decision('discharge-bill'); await click(/^Leave with \$/); }
      else if (await available(/Read newspaper|Read the paper|Done reading/)) await click(/Read newspaper|Read the paper|Done reading/);
      else await page.waitForTimeout(80);
    }
    current = (await snapshot(`recovery-day-${++days}`)).state;
  }
  const patient = person(current, 1);
  assert.equal(patient.locationId, 'Site20'); assert.equal(patient.baseId, 20);
  assert.equal(patient.squadId, null); assert.equal(patient._blood, 1);
  assert.equal(patient.portraitId, person(initial, 1).portraitId);
  assert.deepEqual(patient.equippedWeapon, person(initial, 1).equippedWeapon);
  assert.deepEqual(patient.spareAmmo, person(initial, 1).spareAmmo);
  if (mode !== 'surrender') {
    for (const id of locals) {
      const p = person(current, id);
      if (p?.alive) {
        assert.equal(p.hidingDaysLeft, 0); assert.equal(p.baseId, 20);
        if (interruptedBySiege && p.locationId === 'Site12') assert.ok(p.daysHospitalized > 0);
        else assert.equal(p.locationId, 'Site20');
      }
    }
  }
  check(mode === 'surrender'
    ? 'continued treatment discharges the original hospitalpatient to a valid fallback after headquarters surrender'
    : interruptedBySiege
      ? 'hiding ends and the original patient is discharged; a new siege explicitly interrupts further battle-injury care'
      : 'continued days return hiding survivors and discharge hospitalpatients to a valid fallback headquarters');
  return { days, interruptedBySiege, patient: { id: 1, locationId: patient.locationId, baseId: patient.baseId,
    blood: patient._blood, medicalBills: patient.medicalBills, portraitId: patient.portraitId },
    crew: locals.map(id => { const p = person(current, id); return p && { id, alive: p.alive, hidingDaysLeft: p.hidingDaysLeft,
      locationId: p.locationId, baseId: p.baseId, blood: p._blood, daysHospitalized: p.daysHospitalized,
      medicalBills: p.medicalBills }; }) };
}
async function runScenario(mode) {
  scene = mode; const setup = fixture(mode); await fresh();
  await importLoad(await prepared(mode, setup.state,
    `Prepared police siege at site${setup.targetId}, ${mode === 'escape' ? 'before' : 'during'} attack; `
    + (mode === 'escape' ? 'Four original fast EQ characters (Catsuit, Helen Tillsley, The Blade, Irving Ashmore), while the original Felix crew stays off-site. ' : 'Six local defenders including original EQ Teachlocks/Dubya/Hope. ')
    + 'All original character skills/attributes/body/juice unchanged. '
    + 'Supplied standard AK rifles/ammo and full source SWAT armor, warehouse fortifications/traps/rations, local stored weapon/two vehicles and one off-site vehicle. '
    + 'One declared bleeding hospitalpatient and one separate bleeding off-site squad observer. All local wanted theft counts1; funds unchanged. '
    + (mode === 'assault-escape' ? 'Declared actual occupancy of car0 with Teachlocks driving and open-floor evacuation drill geometry; actual enemy generation, traps, combat and exits remain active.' : 'No prepared result, map override or RNG selection.')));
  const before = (await snapshot('before-response')).state;
  await inspectAndEnlarge(person(before, setup.locals[0]).name);
  await headquartersAction(mode === 'surrender' ? giveUp : fightEscape);
  const actions = await resolveOperation(mode); const after = (await snapshot('resolved')).state;
  const site = allSites(after).find(site => site.id === setup.targetId);
  assert.equal(site.siege.activeSiegeType, 'none'); outsidersUnchanged(before, after, setup.locals);
  check('response resolves the siege and preserves hospital/off-site people, squad, vehicle and funds');
  const localAfter = setup.locals.map(id => person(after, id)).filter(Boolean);
  if (mode === 'surrender') {
    assert.equal(site.controller, 'unaligned'); assert.equal(site.loot.length, 0);
    assert.ok(!after.lcs.vehiclePool.some(car => [0, 1].includes(car.id)));
    for (const p of localAfter) {
      assert.equal(p.locationId, 'Site5'); assert.equal(p.squadId, null);
      assert.equal(p.equippedWeapon, null); assert.equal(p.spareAmmo, null); assert.equal(p.activity.type, 'none');
    }
    check('police surrender captures local wanted defenders, confiscates stored gear/cars and releases the rented base');
  } else if (mode === 'defense') {
    assert.ok(actions.fighting > 0 && actions.sawPursuit);
    assert.equal(site.controller, 'lcs'); assert.equal(site.siege.escalationState, 'nationalGuard');
    assert.ok(site.heat >= before.cities.flatMap(c => c.districts.flatMap(d => d.sites)).find(s => s.id === setup.targetId).heat + 1000);
    assert.ok(localAfter.some(p => p.alive && p.locationId === `Site${setup.targetId}`));
    check('actual defense breaks the siege, retains headquarters and records escalation and combat consequences');
  } else {
    assert.ok(actions.running > 0 || actions.tacticalSteps > 0);
    assert.equal(site.controller, 'unaligned'); assert.equal(site.loot.length, 0);
    assert.ok(localAfter.some(p => p.alive && p.hidingDaysLeft > 0 && p.locationId == null && p.baseId === 20));
    assert.ok(!after.lcs.vehiclePool.some(car => car.id === 1));
    if (mode === 'assault-escape') {
      assert.ok(actions.sawTactical);
      const evacuated = after.lcs.vehiclePool.find(car => car.id === 0);
      assert.ok(evacuated, 'The driven evacuation vehicle survives; the parked van is abandoned.');
      assert.equal(evacuated.locationId, 20);
    }
    check('escape abandons the rented headquarters and unrescued inventory while survivors split up into hiding');
  }
  report.outcomes[mode] = { ...actions, site: { id: site.id, controller: site.controller, siege: site.siege, loot: site.loot },
    vehicles: after.lcs.vehiclePool, funds: after.ledger._funds,
    people: setup.locals.map(id => { const p = person(after, id); return p ? { id, alive: p.alive, blood: p._blood,
      body: p.body, location: p.locationId, baseId: p.baseId, hidingDays: p.hidingDaysLeft, squadId: p.squadId,
      weapon: p.equippedWeapon, spareAmmo: p.spareAmmo, crimes: p.wantedForCrimes } : { id, removed: true }; }) };
  await capture('resolved');
  if (!baselineRun && mode !== 'defense') report.outcomes[mode].recovery = await followRecovery(after, setup.locals, mode);
}
try {
  await fresh(); await importLoad(await prepared('normalization', seed,
    'Bundled Felix copy with idle orders and old wanted crimes/heat cleared. No siege or results yet.'));
  normalized = await snapshot('normalized');
  for (const mode of only === 'all' ? ['surrender', 'escape', 'defense', 'assault-escape'] : [only]) await runScenario(mode);
  await verifyLoadedScript(expected.toLowerCase());
  assert.deepEqual(report.pageErrors, []); assert.deepEqual(report.consoleErrors, []); assert.deepEqual(report.failedRequests, []);
  report.status = report.issues.length ? 'baseline-issues-reproduced' : 'passed';
} catch (error) {
  report.status = 'failed'; report.error = error.stack ?? String(error); process.exitCode = 1;
  if (page) {
    await page.screenshot({ path: resolve(output, 'FAILURE.png'), fullPage: true }).catch(() => {});
    await writeFile(resolve(output, 'FAILURE.txt'), await text().catch(() => '')).catch(() => {});
  }
} finally {
  await context?.close(); await browser.close();
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ status: report.status, output, checks: report.checks.length, issues: report.issues, error: report.error }));
}
