// Actual vehicle theft and car pursuits in disposable browser contexts.
// Character/equipment preparation is declared; gameplay RNG and outcomes are untouched.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertQaUrl, chromiumLaunchOptions, createQaPage } from './browser_support.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const args = process.argv.slice(2);
const arg = (flag, fallback) => args.includes(flag) ? args[args.indexOf(flag) + 1] : fallback;
const url = assertQaUrl(arg('--url', undefined));
const expected = arg('--expected-hash', '');
assert.match(expected, /^[a-f0-9]{64}$/i, 'Provide the exact compiled QA main.dart.js SHA-256.');
const only = arg('--only', 'all');
assert.ok(['all', 'remaining', 'escape', 'fight', 'surrender', 'bailout', 'fight-to-end'].includes(only));
const baselineRun = args.includes('--baseline');
const maxAttempts = 40;
const output = resolve(root, arg('--out', `reports/car-chase-20261016/browser-${Date.now()}`));
const relativeOutput = relative(resolve(root, 'reports'), output);
assert.ok(relativeOutput && !relativeOutput.startsWith('..'), 'Keep evidence under reports/.');
await mkdir(output, { recursive: true });
const decode = env => typeof env.saveData === 'string' ? JSON.parse(env.saveData) : env.saveData;
const envelope = JSON.parse(await readFile(resolve(root, 'upstream/test/saves/felix_1_0.json'), 'utf8'));
const experienced = decode(JSON.parse(await readFile(resolve(root, 'upstream/test/saves/EQ_1_1.json'), 'utf8')));
const seed = decode(envelope);
for (const person of seed.lcs.pool) {
  person.wantedForCrimes = Object.fromEntries(Object.keys(person.wantedForCrimes).map(key => [key, 0]));
  person.heat = 0; person.activity = { type: 'none' };
}
const actor = structuredClone(experienced.lcs.pool.find(person => person.id === 9));
assert.equal(actor.name, 'Teachlocks');
actor.hireId = 0; actor.baseId = 20; actor.locationId = 'Site20'; actor.squadId = 0;
actor.carId = null; actor.preferredCarId = null; actor.isDriver = false; actor.preferredDriver = false;
actor.activity = { type: 'none' }; actor.heat = 0;
actor.wantedForCrimes = Object.fromEntries(Object.keys(actor.wantedForCrimes).map(key => [key, 0]));
actor.equippedWeapon = structuredClone(seed.lcs.pool[0].equippedWeapon);
actor.spareAmmo = structuredClone(seed.lcs.pool[0].spareAmmo);
assert.equal(actor.equippedWeapon.ammo, 30); assert.equal(actor.spareAmmo.stackSize, 8);
seed.lcs.pool.push(actor); seed.lcs.squads[0].members.push(actor.id);
seed.nextCreatureId = Math.max(seed.nextCreatureId, actor.id + 1);
const preparedEnvelope = structuredClone(envelope);
preparedEnvelope.saveData = typeof envelope.saveData === 'string' ? JSON.stringify(seed) : seed;
const seedPath = resolve(output, 'prepared-start.json');
await writeFile(seedPath, JSON.stringify(preparedEnvelope));
const report = {
  status: 'running', url, baselineRun, maxAttempts, expectedHash: expected,
  prepared: [{ path: seedPath, description: 'Bundled Felix campaign with all orders idle and old wanted crimes/heat cleared. '
    + 'Added the whole original Teachlocks ID 9 from EQ_1_1: remapped to HQ20, founder hireId0 and squad0; '
    + 'cleared car preferences/orders/charges/heat. Original attributes, skills, body, blood and juice preserved. '
    + 'Supplied a clone of the founder AK47 (30 loaded rounds) and spare ammunition stack8. '
    + 'No supplied vehicle, selected RNG, forced pursuit, healing, balance or outcome.' }],
  checks: [], issues: [], attempts: [], outcomes: {}, decisions: [], chosenControls: [], screenshots: [],
  pageErrors: [], consoleErrors: [], failedRequests: [],
};
const response = await fetch(new URL('main.dart.js', url));
assert.ok(response.ok);
report.mainJsSha256 = createHash('sha256').update(Buffer.from(await response.arrayBuffer())).digest('hex');
assert.equal(report.mainJsSha256, expected.toLowerCase(), 'QA must serve this exact compiled build.');
const browser = await chromium.launch(chromiumLaunchOptions({ args }));
let context, page, scene = 'setup', attemptNumber = 0, normalized;
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
  while (Date.now() < deadline) {
    if (pattern.test(await text())) return;
    await page.waitForTimeout(80);
  }
  throw Error(`Missing ${pattern}: ${await text()}`);
}
async function click(name) {
  // Parallel browser reviews can leave the authored control briefly disabled
  // while the preceding engine confirmation finishes. Wait for its reader.
  const deadline = Date.now() + 12000;
  while (!await available(name) && Date.now() < deadline) await page.waitForTimeout(80);
  assert.ok(await available(name), `Need current enabled control ${name}: ${await text()}`);
  report.chosenControls.push({ scene, attempt: attemptNumber,
    label: await button(name).getAttribute('aria-label') ?? await button(name).innerText() });
  await button(name).click(); await page.mouse.move(2, 2); await page.waitForTimeout(140);
}
async function decision(kind = 'reader') {
  const current = await text();
  report.decisions.push({ scene, attempt: attemptNumber, kind, text: current,
    buttons: await page.getByRole('button').evaluateAll(nodes => nodes.map(node => ({
      label: node.getAttribute('aria-label') ?? node.textContent,
      disabled: node.getAttribute('aria-disabled') === 'true',
    }))) });
  return current;
}
async function capture(name) {
  await page.mouse.move(2, 2); await page.waitForTimeout(200);
  const file = `${scene}-${attemptNumber}-${name}`;
  await page.screenshot({ path: resolve(output, `${file}.png`), fullPage: true });
  await writeFile(resolve(output, `${file}.txt`), await text());
  report.screenshots.push(`${file}.png`);
}
function check(message) { report.checks.push(`${scene}: ${message}`); console.log(`PASS ${scene}: ${message}`); }
function issue(message) {
  report.issues.push(`${scene}: ${message}`);
  if (!baselineRun) throw Error(message);
  console.log(`REPRODUCED ${scene}: ${message}`);
}
async function fresh() {
  ({ context, page } = await createQaPage(browser, {
    previousContext: context, report, errorContext: () => ({ scene }), timeout: 9000,
  }));
  await page.goto(url, { waitUntil: 'networkidle' }); await wait(/Start a New Game/);
}
async function importLoad(path) {
  const choosing = page.waitForEvent('filechooser'); await click(/^Import a Save/);
  await (await choosing).setFiles(path);
  await wait(/Save imported/); await page.keyboard.press('Enter');
  await wait(/Start a New Game/); await click(/^Load & Manage Saves/);
  await click(/^A(?:\s|$)/); await click(/^L Load Game/); await wait(/Save & exit/);
}
async function snapshot(name) {
  await click(/^Save & exit/); await wait(/Start a New Game/);
  await click(/^Load & Manage Saves/); await click(/^A(?:\s|$)/);
  const downloading = page.waitForEvent('download'); await click(/Export Save File/);
  const path = resolve(output, `${scene}-${attemptNumber}-${name}.json`);
  await (await downloading).saveAs(path);
  const env = JSON.parse(await readFile(path, 'utf8'));
  await click(/^L Load Game/); await wait(/Save & exit/);
  return { state: decode(env), envelope: env, path };
}
async function enlarged() {
  await page.setViewportSize({ width: 800, height: 600 });
  await click(/^Reading size/);
  await page.getByRole('menuitem', { name: '150%', exact: true }).click();
  await page.waitForTimeout(200);
}
const pullOver = /^(?:P[-\s]*)?Pull over and surrender$/i;
const bailOut = /^(?:B[-\s]*)?Bail out and run$/i;
const fight = /^(?:F[-\s]*)?Fight$/i;
const drive = /^(?:D[-\s]*)?Drive hard to escape$/i;
const loseOnFoot = /^(?:D[-\s]*)?(?:Try to lose them|Try to lose them)$/i;
const footSurrender = /^(?:G[-\s]*)?Give up(?: and surrender)?$/i;
const carActive = async () => await available(pullOver) || await available(bailOut);

async function orderTheft() {
  await click(/^Select crew Teachlocks(?:\s|$)/);
  await click(/^Orders(?:\s|$)/); await click(/^Personnel(?:\s|$)/);
  await click(/^Prepare Steal a Car(?:\s|$)/); await click('Confirm order');
}
async function reportContinue() {
  await decision('report'); await click(/^Continue$/);
}

// The actor can be noticed before successfully starting a car. Such attempts
// are recorded and resolved as on-foot arrests, then discarded, not counted
// as one of the requested car outcomes.
async function reachCarReader() {
  await click(/^(?:Wait a day|Carry out your plans)/);
  for (let step = 0; step < 180; step++) {
    if (await available(/^Continue$/)) await reportContinue();
    else if (await carActive()) { await decision('car-entry'); return 'car'; }
    else if (await available(footSurrender)) {
      await decision('pre-car-foot-pursuit'); await capture('pre-car-foot-pursuit');
      await click(footSurrender); await settleReports(); return 'pre-car-arrest';
    } else if (await available(/^Save & exit/)) return 'no-chase';
    else if (await available(/^[A-Z](?:\s+-|\s)\s*Sportscar(?:\s|$)/)) {
      await decision('vehicle-choice'); await click(/^[A-Z](?:\s+-|\s)\s*Sportscar(?:\s|$)/);
    } else if (await available(/Approach the driver's side door/)) {
      await decision('approach'); await click(/Approach the driver's side door/);
    } else if (await available(/Break the window/)) {
      await decision('break-window'); await click(/Break the window/);
    } else if (await available(/Hotwire the car/)) {
      await decision('hotwire'); await click(/Hotwire the car/);
    } else await page.waitForTimeout(80);
  }
  throw Error(`Theft has no recognized current reader: ${await text()}`);
}
async function settleReports() {
  for (let step = 0; step < 200; step++) {
    if (await available(/^Save & exit/)) return;
    if (await available(/^Continue$/)) await reportContinue();
    else await page.waitForTimeout(80);
  }
  throw Error(`Daily operation did not return to headquarters: ${await text()}`);
}
async function inspectAndEnlarge() {
  await capture('car-entry');
  if (!/Car pursuit/.test(await text())) issue('Car pursuit uses the generic fallback instead of a contextual journal page.');
  if (await available(/^Inspect Teachlocks$/)) {
    const before = await text(); await click(/^Inspect Teachlocks$/);
    if (await page.getByRole('dialog').count()) {
      await page.keyboard.press('p'); await page.keyboard.press('d'); await page.waitForTimeout(160);
      assert.ok(await page.getByRole('dialog').count(), 'Dossier must block underlying keyboard actions.');
      await page.getByRole('dialog').getByRole('button', { name: 'Close dossier', exact: true }).last().click();
      await page.waitForTimeout(160);
      assert.equal(await text(), before, 'Closing the read-only dossier preserves the current car decision.');
      check('car dossier opens, blocks pursuit keys and closes without consuming a decision');
    } else issue('Car pursuit Inspect control does not open a dossier.');
  } else issue('Car pursuit has no working read-only crew dossier control.');
  await enlarged(); await decision('enlarged-car-reader');
  const bounds = await button(pullOver).boundingBox();
  (report.enlargedSurrenderBounds ??= []).push({ scene, attempt: attemptNumber, bounds,
    viewport: page.viewportSize() });
  if (!bounds || bounds.y < 0 || bounds.y + bounds.height > 600)
    issue('Car surrender control is not reachable at 800x600 with 150 percent reading size.');
  await capture('car-800x600-at150');
  await page.waitForTimeout(500);
}
async function finishCar(mode) {
  let carTurns = 0, fightingTurns = 0, footFallback = false, surrendered = false;
  let sawShot = false, sawEscape = false, ammoAfterCombat;
  let bailoutSelected = false, footCombatTurns = 0, footEscapeTurns = 0;
  let lastCondition;
  function observeCondition(current) {
    const health = current.match(/Health:\s*([^\n]+)/);
    const weapon = current.match(/Weapon:\s*([^\n]+)/);
    if (health || weapon) lastCondition = { health: health?.[1], weapon: weapon?.[1] };
  }
  const terminalReports = [];
  for (let step = 0; step < 700; step++) {
    if (await available(/^Save & exit/)) return { carTurns, fightingTurns, footFallback, surrendered, sawShot, sawEscape,
      ammoAfterCombat, bailoutSelected, footCombatTurns, footEscapeTurns, terminalReports, lastCondition };
    if (await available(/^Continue$/)) {
      const current = await decision('pursuit-report');
      sawShot ||= /open fire on the/.test(current);
      sawEscape ||= /looks like you've lost them|A Liberal outcome|can't keep up|couldn't keep up/.test(current);
      if (/lost them|Liberal outcome|arrested|dies|dead|killed|crash|bleed|squashed|crushed|seized|handcuffed|runs.*off the road|gives up|pulls over/.test(current))
        terminalReports.push(current);
      await click(/^Continue$/);
    } else if (await carActive()) {
      const current = await decision('car-decision');
      observeCondition(current);
      if (fightingTurns > 0 && ammoAfterCombat === undefined) {
        const ammunition = current.match(/Weapon:\s*[^\n]*?\b(\d+)\/(\d+)\b/);
        assert.ok(ammunition, `The current source crew card must expose ammunition: ${current}`);
        ammoAfterCombat = { loaded: Number(ammunition[1]), spare: Number(ammunition[2]) };
        assert.ok(ammoAfterCombat.loaded < 30, 'The actual car combat must spend loaded ammunition before surrender.');
        await capture('after-combat-ammunition');
        check('current source crew card shows ammunition consumed by the actual car fight');
      }
      if (mode === 'bailout' && !bailoutSelected && !baselineRun) {
        await capture('before-bailout'); await click(bailOut); bailoutSelected = true;
      } else if (baselineRun || mode === 'surrender' || (mode === 'fight' && fightingTurns > 0)) {
        assert.ok(await available(pullOver)); await click(pullOver); surrendered = true;
        if (baselineRun && await carActive()) {
          issue('Current surrender click is rejected while the classic car animation is running.');
          await capture('animation-rejected-surrender'); return { baselineStopped: true };
        }
      } else if (['fight', 'fight-to-end'].includes(mode) && await available(fight)) {
        await click(fight); fightingTurns++; carTurns++;
      } else if (mode !== 'fight-to-end' && await available(drive)) { await click(drive); carTurns++; }
      else {
        // Obstacle controls have their own authored meanings; F can mean slow
        // down, so never infer a combat action from its key.
        const obstacle = /^(?:D[-\s]*)?(?:Swerve(?: around| into an alley| into traffic)|Run the light)$/i;
        if (mode === 'fight-to-end' && await available(/^(?:F[-\s]*)?Slow down$/i))
          await click(/^(?:F[-\s]*)?Slow down$/i);
        else if (await available(obstacle)) await click(obstacle);
        else if (await available(/^(?:F[-\s]*)?Slow down$/i)) await click(/^(?:F[-\s]*)?Slow down$/i);
        else throw Error(`No authored obstacle choice: ${await text()}`);
        carTurns++;
      }
    } else if (await available(footSurrender) || await available(loseOnFoot)) {
      footFallback = true; observeCondition(await decision('actual-on-foot-transition')); await capture('on-foot-transition');
      if (mode === 'fight-to-end') {
        assert.ok(await available(fight), 'Continue actual combat after a forced transition to foot.');
        await click(fight); footCombatTurns++;
      } else if (['escape', 'bailout'].includes(mode) && await available(loseOnFoot)) {
        await click(loseOnFoot); footEscapeTurns++;
      }
      else { await click(footSurrender); surrendered = true; }
    } else if (await available(/Reflect on your Conservative (?:driving|ineptitude)/i)) {
      const current = await decision('source-defeat-reflection');
      footFallback ||= /On-foot pursuit/.test(current);
      await capture('source-defeat-reflection');
      await click(/Reflect on your Conservative (?:driving|ineptitude)/i);
    } else await page.waitForTimeout(100);
  }
  throw Error(`Car pursuit failed to resolve: ${await text()}`);
}

function verifyFounder(state, before) {
  const founder = state.lcs.pool.find(person => person.id === 0);
  const original = before.lcs.pool.find(person => person.id === 0);
  assert.equal(founder.alive, true); assert.equal(founder.locationId, `Site${founder.baseId}`);
  assert.equal(founder.squadId, original.squadId);
  assert.deepEqual(founder.equippedWeapon, original.equippedWeapon);
  assert.deepEqual(founder.spareAmmo, original.spareAmmo);
}
async function runScenario(mode) {
  scene = mode;
  for (attemptNumber = 1; attemptNumber <= maxAttempts; attemptNumber++) {
    console.log(`ATTEMPT ${scene} ${attemptNumber}: actual theft from a fresh isolated campaign`);
    await fresh(); await importLoad(normalized.path); await orderTheft();
    const ordered = (await snapshot('ordered')).state;
    const initialActor = ordered.lcs.pool.find(person => person.id === actor.id);
    assert.equal(initialActor.activity.type, 'stealCars');
    assert.equal(ordered.lcs.vehiclePool.length, 0);
    const entry = await reachCarReader();
    console.log(`ATTEMPT ${scene} ${attemptNumber}: ${entry}`);
    if (entry !== 'car') {
      const result = (await snapshot(entry)).state;
      report.attempts.push({ scene, attempt: attemptNumber, result: entry, date: result.date,
        acquiredCars: result.lcs.vehiclePool, locationId: result.lcs.pool.find(person => person.id === actor.id).locationId });
      continue;
    }
    await inspectAndEnlarge();
    const result = await finishCar(mode);
    if (result.baselineStopped) return;
    const final = (await snapshot('resolved')).state;
    const person = final.lcs.pool.find(candidate => candidate.id === actor.id);
    verifyFounder(final, ordered);
    if (!['bailout', 'fight-to-end'].includes(mode))
      assert.equal(person.alive, true, 'This completed scenario must retain the actor.');
    assert.ok(final.nextVehicleId > ordered.nextVehicleId, 'The original theft/pursuit handlers created actual vehicles.');
    const localDecisions = report.decisions.filter(record => record.scene === scene && record.attempt === attemptNumber);
    const selected = report.chosenControls.filter(record => record.scene === scene && record.attempt === attemptNumber);
    if (mode === 'fight-to-end') {
      assert.ok(selected.every(record => !pullOver.test(record.label) && !footSurrender.test(record.label)
        && !bailOut.test(record.label) && !drive.test(record.label)),
      'The recorded terminal-combat journey must never select surrender, voluntary bailout or driving escape.');
    }
    assert.ok(localDecisions.some(record => /hotwires the car|found the keys/.test(record.text)),
      'The car must have been started through actual theft gameplay.');
    assert.ok(localDecisions.some(record => /by car|pull away from the site/.test(record.text)));
    check('successful UI theft starts a real car pursuit without forced RNG or a supplied vehicle');
    if (baselineRun) {
      report.attempts.push({ scene, attempt: attemptNumber, result: 'baseline-car-captured' });
      report.outcomes[scene] = { ...result, personId: person.id, locationId: person.locationId };
      return;
    }
    if (mode === 'escape' && result.footFallback) {
      report.attempts.push({ scene, attempt: attemptNumber, result: 'car-lost-continued-on-foot', details: result });
      continue; // Recorded honestly; try another natural car escape.
    }
    if (!person) {
      assert.ok(['bailout', 'fight-to-end'].includes(mode));
      assert.equal(result.surrendered, false);
      assert.ok(localDecisions.some(record => record.kind === 'source-defeat-reflection'),
        'A removed actor requires the actual terminal defeat reader.');
      assert.equal(final.stats.martyrs, ordered.stats.martyrs + 1,
        'The original engine must record the actor death once before removing an unrecovered body.');
      assert.equal(final.lcs.vehiclePool.length, 0);
      assert.deepEqual(final.lcs.squads[0].members, ordered.lcs.squads[0].members.filter(id => id !== actor.id));
      assert.deepEqual(final.lcs.squads.map(squad => squad.id), ordered.lcs.squads.map(squad => squad.id));
      if (mode === 'bailout') assert.ok(result.bailoutSelected && result.footFallback && result.footEscapeTurns > 0);
      else assert.ok(result.fightingTurns > 0 && result.sawShot && !result.bailoutSelected);
      report.outcomes[scene] = { attempt: attemptNumber, ...result, personId: actor.id,
        terminal: 'death', alive: false, bodyRecovered: false, removedFromPool: true,
        date: final.date, cars: final.lcs.vehiclePool, funds: final.ledger._funds,
        martyrsBefore: ordered.stats.martyrs, martyrsAfter: final.stats.martyrs,
        loadedAmmoBefore: initialActor.equippedWeapon?.ammo, finalCondition: 'Unrecovered body removed by original engine' };
      await capture('resolved-headquarters-after-unrecovered-death');
      check('actual terminal combat defeat removes the unrecovered body and abandoned car, records one martyr and restores the original squad');
      check('save/export/reload retains the real defeat outcome while the founder and other crew remain at HQ');
      return;
    }
    const police = final.cities.flatMap(city => city.districts.flatMap(district => district.sites))
      .find(site => site.type === 'policeStation' && `Site${site.id}` === person.locationId);
    const terminal = !person.alive ? 'death' : police ? 'custody'
      : person.locationId === `Site${person.baseId}` ? 'headquarters' : 'other';
    if (['bailout', 'fight-to-end'].includes(mode)) {
      assert.equal(result.surrendered, false, 'These scenarios never select voluntary surrender.');
      assert.notEqual(terminal, 'other', 'The original pursuit must resolve into HQ, custody or death.');
      if (mode === 'bailout') {
        assert.equal(result.bailoutSelected, true);
        assert.equal(result.footFallback, true, 'Bailout must actually enter the on-foot pursuit reader.');
        assert.ok(result.footEscapeTurns > 0);
        assert.equal(final.lcs.vehiclePool.length, 0, 'Bailing out abandons the actual stolen car.');
        check('current Bail out action abandons the stolen car and enters a real on-foot pursuit');
      } else {
        assert.equal(result.bailoutSelected, false);
        assert.ok(result.fightingTurns > 0 && result.sawShot);
        check('repeated original Fight controls resolve the pursuit without voluntary surrender, bailout or driving escape');
      }
      if (terminal === 'headquarters') {
        assert.equal(person.squadId, initialActor.squadId);
        if (mode === 'bailout') {
          assert.equal(person.equippedWeapon.typeName, initialActor.equippedWeapon.typeName);
          assert.equal(person.equippedWeapon.ammo, initialActor.equippedWeapon.ammo);
          assert.deepEqual(person.spareAmmo, initialActor.spareAmmo);
        }
      } else if (terminal === 'custody') {
        assert.equal(person.squadId, null);
        assert.ok(person.carId == null || person.carId === -1,
          'An automatic on-foot arrest can retain the original -1 no-car sentinel.');
        assert.equal(person.equippedWeapon, null); assert.equal(person.spareAmmo, null);
        assert.equal(person.activity.type, 'none');
      } else {
        // A retained corpse can remain at its original location. The original
        // engine distinguishes it from an unrecovered body removed from pool.
        assert.ok(person.locationId == null || person.locationId === `Site${person.baseId}`);
        assert.equal(final.stats.martyrs, ordered.stats.martyrs + 1);
        assert.equal(person.squadId, null, 'A dead driver must not retain a dangling temporary pursuit squad.');
        assert.ok(!final.lcs.vehiclePool.some(car => car.id === person.carId),
          'The historical corpse car reference must not identify a live vehicle.');
      }
      if (result.footFallback || !person.alive) assert.equal(final.lcs.vehiclePool.length, 0);
      check(`original ${mode} consequences resolve to ${terminal} with saved condition, equipment and squad state`);
    } else if (mode === 'escape') {
      assert.ok(result.carTurns > 0 && result.sawEscape);
      assert.equal(result.surrendered, false);
      assert.equal(person.locationId, `Site${person.baseId}`); assert.equal(person.squadId, initialActor.squadId);
      assert.ok(final.lcs.vehiclePool.some(car => car.id === person.preferredCarId && car.heat > 0),
        'The actual stolen vehicle remains owned after escaping.');
      assert.ok(person.wantedForCrimes.resistingArrest > 0);
      assert.deepEqual(person.equippedWeapon, initialActor.equippedWeapon);
      assert.deepEqual(person.spareAmmo, initialActor.spareAmmo);
      check('actual driving escape retains the stolen car and equipment, returns to HQ and records resisting arrest');
    } else if (result.surrendered) {
      assert.equal(result.surrendered, true);
      assert.equal(person.squadId, null); assert.equal(person.carId, null);
      assert.equal(person.equippedWeapon, null); assert.equal(person.spareAmmo, null);
      assert.equal(person.activity.type, 'none'); assert.equal(final.lcs.vehiclePool.length, 0);
      assert.ok(police, 'Surrender places the driver in original police custody.');
      assert.deepEqual(final.lcs.squads[0].members, ordered.lcs.squads[0].members.filter(id => id !== person.id));
      if (mode === 'fight') {
        assert.ok(result.fightingTurns > 0 && result.sawShot, 'Root Fight must produce the original shooting report.');
        assert.ok(person.wantedForCrimes.resistingArrest > 0);
        check('actual car combat fires on a pursuing vehicle before surrender and custody confiscation');
      } else {
        assert.equal(person.wantedForCrimes.resistingArrest, initialActor.wantedForCrimes.resistingArrest);
        check('immediate pull-over preserves surrender rules, confiscates the car and equipment and clears the order');
      }
    } else {
      assert.equal(mode, 'fight');
      assert.ok(result.fightingTurns > 0 && result.sawShot);
      assert.equal(person.locationId, `Site${person.baseId}`);
      assert.equal(person.squadId, initialActor.squadId);
      assert.ok(person.equippedWeapon.ammo < initialActor.equippedWeapon.ammo);
      assert.ok(final.lcs.vehiclePool.some(car => car.id === person.preferredCarId));
      check('actual car combat resolves the pursuit and returns the armed driver and car to HQ with spent ammunition');
    }
    assert.deepEqual(person.portraitId, initialActor.portraitId);
    assert.deepEqual(final.lcs.squads.map(squad => squad.id), ordered.lcs.squads.map(squad => squad.id));
    report.outcomes[scene] = { attempt: attemptNumber, ...result, personId: person.id,
      terminal, alive: person.alive, date: final.date, locationId: person.locationId, blood: person._blood,
      cars: final.lcs.vehiclePool, crimes: person.wantedForCrimes, funds: final.ledger._funds,
      body: person.body, squadId: person.squadId, carId: person.carId,
      weapon: person.equippedWeapon, spareAmmo: person.spareAmmo, activity: person.activity,
      bodyRetainedInPool: !person.alive || undefined,
      corpseStatus: !person.alive ? 'Retained corpse at original base or no location' : undefined,
      loadedAmmoBefore: initialActor.equippedWeapon?.ammo, loadedAmmoAfter: person.equippedWeapon?.ammo ?? null };
    await capture('resolved-headquarters');
    check('save/export/reload observes the resulting custody or HQ state and preserves the founder and squad');
    return;
  }
  throw Error(`No completed ${mode} car outcome in ${maxAttempts} ordinary theft attempts; see recorded attempts.`);
}

try {
  await fresh(); await importLoad(seedPath); normalized = await snapshot('normalized');
  const normalizedActor = normalized.state.lcs.pool.find(person => person.id === actor.id);
  assert.deepEqual(normalizedActor.rawSkill, actor.rawSkill);
  assert.deepEqual(normalizedActor.rawAttributes, actor.rawAttributes);
  assert.equal(normalizedActor.juice, actor.juice);
  check('fixture normalization preserves the experienced driver original skills and attributes');
  const modes = only === 'all' ? ['escape', 'fight', 'surrender', 'bailout', 'fight-to-end']
    : only === 'remaining' ? ['bailout', 'fight-to-end'] : [only];
  for (const mode of modes) await runScenario(mode);
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
