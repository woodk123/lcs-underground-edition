// Actual pointer/keyboard acceptance for equipment preparation and the movement plan.
// Prepared people/stock/orders are declared; no RNG calls, time advances or outcomes are supplied.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, isAbsolute, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertQaUrl, chromiumLaunchOptions, createQaPage, observeMainScript, waitForSemantics, waitForUiSettled } from './browser_support.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const option = (flag, fallback) => {
  const index = args.indexOf(flag);
  if (index < 0) return fallback;
  assert.ok(args[index + 1] && !args[index + 1].startsWith('--'), `${flag} requires a value.`);
  return args[index + 1];
};
if (args.includes('--help')) {
  console.log('Usage: node scripts/planning_equipment_browser_review.mjs --expected-hash SHA256 [--url URL] [--out FRESH_IGNORED_DIRECTORY]\n'
    + 'Requires a development bridge build. Runs desktop and 1024x720/150% equipment and Daily plan journeys in fresh profiles. '
    + '--prepare-only writes the declared fixture without fetching or launching anything.');
  process.exit(0);
}
const prepareOnly = args.includes('--prepare-only');
const expectedHash = option('--expected-hash', '').toLowerCase();
if (!prepareOnly) assert.match(expectedHash, /^[a-f0-9]{64}$/, 'Require the exact compiled main.dart.js SHA-256.');
const url = assertQaUrl(option('--url', undefined));
const output = resolve(root, option('--out', `reports/planning-equipment-${Date.now()}`));
assert.ok(['.local', 'reports'].some(parent => {
  const child = relative(resolve(root, parent), output);
  return child && !isAbsolute(child) && child !== '..' && !child.startsWith('../') && !child.startsWith('..\\');
}), 'Keep fresh evidence beneath ignored .local/ or reports/.');
await mkdir(dirname(output), { recursive: true });
await mkdir(output);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const decode = envelope => typeof envelope.saveData === 'string' ? JSON.parse(envelope.saveData) : envelope.saveData;
const sourceFixture = resolve(root, 'upstream/test/saves/felix_1_0.json');
const originalBytes = await readFile(sourceFixture);
const envelope = JSON.parse(originalBytes);
const prepared = decode(envelope);
const sites = prepared.cities.flatMap(city => city.districts.flatMap(district => district.sites));
const home = sites.find(site => site.id === prepared.lcs.pool[0].baseId);
const hospital = sites.find(site => site.type === 'universityHospital');
const park = sites.find(site => site.type === 'publicPark' && site.cityId === home.cityId);
assert.ok(home && hospital && park, 'Use existing source-authored locations.');
const template = structuredClone(prepared.lcs.pool[0]);
for (const person of prepared.lcs.pool) {
  person.wantedForCrimes = Object.fromEntries(Object.keys(person.wantedForCrimes).map(key => [key, 0]));
  person.heat = 0;
  person.activity = { type: 'none' };
}
const equipmentActor = prepared.lcs.pool[1];
equipmentActor.equippedWeapon = { typeName: 'WEAPON_9MM_HANDGUN', stackSize: 1, ammo: 0, loadedAmmoId: 'AMMO_9MM' };
equipmentActor.spareAmmo = { typeName: 'AMMO_9MM', stackSize: 12 };
prepared.lcs.pool[0].activity = { type: 'donations' };
equipmentActor.activity = { type: 'sellArt' };
prepared.lcs.pool[2].activity = { type: 'study', skill: 'science' };
prepared.lcs.pool[3].activity = { type: 'recruiting' };
const addPerson = (name, patch = {}) => {
  const person = { ...structuredClone(template), id: prepared.nextCreatureId++, name, properName: name,
    hireId: template.id, squadId: null, carId: null, preferredCarId: null, isDriver: false, preferredDriver: false,
    sleeperAgent: false, hidingDaysLeft: 0, vacationDaysLeft: 0, clinicMonthsLeft: 0, medicalBills: 0,
    heat: 0, activity: { type: 'none' }, ...patch };
  person.wantedForCrimes = Object.fromEntries(Object.keys(person.wantedForCrimes).map(key => [key, 0]));
  prepared.lcs.pool.push(person);
  return person;
};
const orderActor = addPerson('Mara Planner');
const hospitalPerson = addPerson('Chaz Patient', { locationId: `Site${hospital.id}`, medicalBills: 1360, _blood: .5,
  activity: { type: 'clinic' } });
const hidingPerson = addPerson('Holly Hiding', { hidingDaysLeft: 4 });
const sleeper = addPerson('Sam Sleeper', { sleeperAgent: true, workLocationId: `Site${home.id}`,
  activity: { type: 'sleeperLiberal' } });
const queuedSquad = { id: prepared.nextSquadId++, name: 'Prepared park team', members: [],
  activity: { type: 'visit', idString: `Site${park.id}` }, loot: [] };
for (const name of ['Quinn Scout', 'Rowan Scout']) {
  const person = addPerson(name, { squadId: queuedSquad.id });
  queuedSquad.members.push(person.id);
}
prepared.lcs.squads.push(queuedSquad);
for (let index = 1; index <= 10; index++) addPerson(`Zed Planner ${String(index).padStart(2, '0')}`,
  { activity: index % 2 ? { type: 'donations' } : { type: 'none' } });
const prospect = { ...structuredClone(template), id: prepared.nextCreatureId++, name: 'Casey Prospect', properName: 'Casey Prospect',
  hireId: null, squadId: null, activity: { type: 'none' }, equippedWeapon: null, spareAmmo: null };
prepared.recruitmentSessions = [{ recruit: prospect, recruiter: prepared.lcs.pool[3].id, rawEagerness: 4 }];
prepared.datingSessions = [];
const clothingIds = ['CLOTHING_CATSUIT', 'CLOTHING_BLACKDRESS', 'CLOTHING_LEATHER', 'CLOTHING_BLACKBLOC',
  'CLOTHING_BLACKROBE', 'CLOTHING_BLACKSUIT', 'CLOTHING_BLACKSUIT_AGENT', 'CLOTHING_BLACKCLOTHES',
  'CLOTHING_BONDAGEGEAR', 'CLOTHING_BUNKERGEAR', 'CLOTHING_CHEAPDRESS', 'CLOTHING_CHEAPSUIT',
  'CLOTHING_CLOWNSUIT', 'CLOTHING_DEATHSQUADUNIFORM', 'CLOTHING_DONKEYSUIT', 'CLOTHING_ELEPHANTSUIT',
  'CLOTHING_LABCOAT', 'CLOTHING_KIMONO', 'CLOTHING_TIE_DYE'];
const clothingXml = await readFile(resolve(root, 'upstream/assets/xml/clothing.xml'), 'utf8');
for (const id of clothingIds) assert.ok(clothingXml.includes(`idname="${id}"`), `Declared source outfit ${id} exists.`);
home.loot = [
  { typeName: 'WEAPON_AK102', stackSize: 1, ammo: 0, loadedAmmoId: null },
  ...clothingIds.map(typeName => ({ typeName, stackSize: 1, bloody: false, damaged: false })),
  { typeName: 'AMMO_556', stackSize: 120 }, { typeName: 'AMMO_68', stackSize: 20 },
  { typeName: 'LOOT_COMPUTER', stackSize: 1 },
];
assert.ok(home.loot.length > 18, 'Exercise actual source inventory pages.');
assert.equal(new Set(prepared.lcs.pool.map(person => person.id)).size, prepared.lcs.pool.length);
for (const squad of prepared.lcs.squads) for (const id of squad.members)
  assert.equal(prepared.lcs.pool.find(person => person.id === id)?.squadId, squad.id);
envelope.saveData = typeof envelope.saveData === 'string' ? JSON.stringify(prepared) : prepared;
const fixturePath = resolve(output, 'prepared-mixed-campaign.json');
await writeFile(fixturePath, JSON.stringify(envelope));
const report = {
  status: prepareOnly ? 'prepared' : 'running', url, expectedHash: expectedHash || null,
  scope: 'Prepared mixed Felix campaign; fresh desktop and 1024x720/150% browser profiles. Actual pointer/keyboard '
    + 'equipment and Orders actions; read-only bridge observations identify current source actions/revisions and compare complete campaign state. '
    + 'No day advances. RNG purity is covered separately by native seeded regressions; this browser has no RNG inspection API.',
  prepared: { fixture: relative(output, fixturePath), source: relative(root, sourceFixture), sourceSha256: hash(originalBytes),
    changes: ['Original crew charges/heat cleared; personal donations/art/science/recruiting/idle orders supplied.',
      'Second original member supplied an empty 9mm handgun and12 compatible spare rounds;23 base stock entries supplied, including an empty AK-102,19 outfits and ammunition.',
      'Living Liberal unsquadded idle/working, hospital, hiding and sleeper people cloned; separate two-person park visit explicitly queued.',
      'Ten additional rows supplied for filtering/scrolling; one ready recruitment follow-up supplied for the original recruiter. No earned recruitment, stock or visit is claimed.'],
    actors: { equipment: { id: equipmentActor.id, name: equipmentActor.name }, order: { id: orderActor.id, name: orderActor.name },
      hospital: { id: hospitalPerson.id, name: hospitalPerson.name }, hiding: { id: hidingPerson.id, name: hidingPerson.name },
      sleeper: { id: sleeper.id, name: sleeper.name }, queuedSquad: { id: queuedSquad.id, name: queuedSquad.name, destination: park.name },
      recruiter: { id: prepared.lcs.pool[3].id, name: prepared.lcs.pool[3].name }, prospect: { id: prospect.id, name: prospect.name } },
    people: prepared.lcs.pool.length, stockTypes: home.loot.map(item => item.typeName) },
  checks: [], errors: [], screenshots: [], sourceActions: [], snapshots: [], layouts: [], focusChecks: [], sourceNormalizations: [],
  pageErrors: [], consoleErrors: [], failedRequests: [], workerErrors: [], loadedMainJsHashes: [],
};
await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
if (prepareOnly) { console.log(JSON.stringify({ status: report.status, output, fixturePath, people: prepared.lcs.pool.length })); process.exit(0); }

const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
let browser, context, page, verifyLoaded, layout = '', captureIndex = 0;
const escape = text => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const person = (campaign, id) => campaign.lcs.pool.find(entry => entry.id === id);
const site = (campaign, id) => campaign.cities.flatMap(city => city.districts.flatMap(district => district.sites)).find(entry => entry.id === id);
const stock = campaign => site(campaign, home.id).loot;
const button = (name, scope = page) => scope.getByRole('button', { name }).first();
async function text() {
  return page.evaluate(() => {
    const host = document.querySelector('flt-semantics-host');
    return host ? [host.innerText, ...[...host.querySelectorAll('[aria-label]')].map(node => node.getAttribute('aria-label')),
      ...[...host.querySelectorAll('input,textarea')].map(node => node.value)].filter(Boolean).join('\n') : '';
  });
}
async function bridge(method, params = {}) {
  const raw = await page.evaluate(async ({ method, params }) => {
    if (!globalThis.lcsDev?.request) throw Error('Use a build prepared with LCS_DEVTOOLS=true.');
    let timer;
    try { return await Promise.race([globalThis.lcsDev.request(JSON.stringify({ method, params })),
      new Promise((_, reject) => { timer = setTimeout(() => reject(Error('Read-only bridge timed out.')), 5000); })]);
    } finally { clearTimeout(timer); }
  }, { method, params });
  const envelope = JSON.parse(raw);
  assert.ok(envelope.ok, `Read-only bridge ${method}: ${JSON.stringify(envelope.error)}`);
  return envelope.result;
}
async function snapshot(name) {
  const observation = await bridge('observe');
  const campaign = (await bridge('inspect', { scope: 'campaign' })).campaign;
  const currentContext = await bridge('inspect', { scope: 'context' });
  const filename = `${layout}-snapshot-${report.snapshots.length + 1}-${name}.json`;
  await writeFile(resolve(output, filename), JSON.stringify({ observation, campaign, context: currentContext }, null, 2));
  report.snapshots.push({ name, layout, file: filename, revision: observation.revision, blockedReason: observation.blockedReason });
  return { observation, campaign, context: currentContext };
}
function sameSource(before, after, name) {
  // Modal/draft blocking is presentation state; retain it in evidence, but compare
  // every original pending reader/action field independently of that reason.
  const fields = ['build', 'revision', 'screen', 'text', 'report', 'reportContext', 'awaitingInput', 'textInput', 'navigation', 'actions'];
  for (const key of fields) assert.deepEqual(after.observation[key], before.observation[key], `${name}: source ${key} unchanged.`);
  assert.deepEqual(after.campaign, before.campaign, `${name}: complete campaign unchanged.`);
  assert.deepEqual(after.context, before.context, `${name}: original actor/context unchanged.`);
}
function check(name) { report.checks.push({ name, layout, status: 'passed' }); console.log(`PASS ${layout}: ${name}`); }
async function wait(pattern) { await waitForSemantics(page, pattern); }
async function reveal(control, scope = page) {
  let lastError;
  for (let attempt = 0; attempt < 32; attempt++) {
    const viewport = page.viewportSize();
    const area = scope === page ? { x: 0, y: 0, ...viewport } : await scope.boundingBox();
    assert.ok(area, 'Keep the current reader mounted while scrolling.');
    const box = await control.count() ? await control.boundingBox() : null;
    if (box && box.height > 4 && box.y >= area.y && box.y + box.height <= area.y + area.height) {
      try { await control.click({ trial: true, timeout: 300 }); return control; }
      catch (error) { lastError = String(error); }
    }
    await page.mouse.move(area.x + area.width * .76, area.y + area.height * .58);
    await page.mouse.wheel(0, box && box.y < area.y ? -230 : 230);
    await waitForUiSettled(page);
  }
  throw Error(`Cannot reach the current reader's control: ${lastError ?? await control.count() + ' semantic nodes'}`);
}
async function click(name, scope = page) {
  const control = button(name, scope);
  await reveal(control, scope); await control.click();
  await page.mouse.move(2, 2); await waitForUiSettled(page);
}
async function chooseFilter(name, scope = page) {
  const control = scope.getByRole('checkbox', { name }).first();
  await reveal(control, scope); await control.click();
  await page.mouse.move(2, 2); await waitForUiSettled(page);
  assert.ok(await control.isChecked(), 'The actual ChoiceChip must retain the selected filter.');
}
async function capture(name) {
  const filename = `${layout}-${++captureIndex}-${name}`;
  await page.screenshot({ path: resolve(output, `${filename}.png`), fullPage: true });
  await writeFile(resolve(output, `${filename}.txt`), await text());
  report.screenshots.push(`${filename}.png`);
}
async function exportGame(name) {
  await click(/^Save & exit/); await wait(/Start a New Game/);
  await click(/^Load & Manage Saves/); await click(/^A(?:\s|$)/); await wait(/Manage .*Saved Game/);
  const downloading = page.waitForEvent('download'); await click(/Export Save File/);
  const filename = `${layout}-${name}.json`;
  await (await downloading).saveAs(resolve(output, filename));
  const saved = decode(JSON.parse(await readFile(resolve(output, filename), 'utf8')));
  await click(/^L Load Game/); await wait(/Save & exit/);
  return saved;
}
async function sourceChoice(name, predicate, control, { keyboard = false } = {}) {
  const observed = await bridge('observe');
  assert.ok(observed.awaitingInput, `${name}: the original reader must await input.`);
  const choices = observed.actions.filter(action => action.enabled && predicate(action));
  assert.equal(choices.length, 1, `${name}: use one exact current source action.`);
  const choice = choices[0];
  await reveal(control);
  const current = await bridge('observe');
  assert.equal(current.revision, observed.revision, `${name}: source revision still current before input.`);
  assert.deepEqual(current.actions.find(action => action.id === choice.id), choice, `${name}: source identity still current.`);
  const keyboardKey = keyboard === true ? 'Enter' : keyboard;
  report.sourceActions.push({ layout, name, revision: observed.revision, action: choice, input: keyboardKey ? `keyboard ${keyboardKey}` : 'pointer' });
  if (keyboardKey) await page.keyboard.press(keyboardKey); else await control.click();
  await page.mouse.move(2, 2);
  const deadline = Date.now() + 20000;
  let next;
  do {
    next = await bridge('observe');
    if (next.revision !== observed.revision && next.awaitingInput) break;
    await page.waitForTimeout(60);
  } while (Date.now() < deadline);
  assert.ok(next.revision !== observed.revision && next.awaitingInput, `${name}: reach the next original input reader.`);
  await waitForUiSettled(page);
  return choice;
}

async function query(input, value, scope = page) {
  await reveal(input, scope); await input.click(); await waitForUiSettled(page);
  await page.keyboard.press('Control+A');
  if (value) await page.keyboard.type(value); else await page.keyboard.press('Backspace');
  await waitForUiSettled(page);
  assert.equal(await input.inputValue(), value, 'The actual focused text field must receive the query.');
}
async function keyboardFocus(control, name) {
  for (let attempt = 0; attempt < 45; attempt++) {
    if (await control.count() && await control.evaluate(node => node === document.activeElement || node.contains(document.activeElement))) {
      report.focusChecks.push({ layout, name, tabs: attempt,
        activeElement: await page.evaluate(() => ({ tag: document.activeElement?.tagName,
          label: document.activeElement?.getAttribute('aria-label'), text: document.activeElement?.textContent })) });
      return;
    }
    await page.keyboard.press('Tab'); await waitForUiSettled(page);
  }
  throw Error(`Keyboard traversal did not focus ${name}.`);
}
async function inventoryAction(typeName) {
  const observed = await bridge('observe');
  const actions = observed.actions.filter(action => action.entityType === 'equipment-stock'
    && action.entityCategory === typeName && action.enabled);
  assert.equal(actions.length, 1, `The current original inventory page must contain ${typeName}.`);
  return actions[0];
}
async function equipmentBack(name = 'equipment source Back') {
  await sourceChoice(name, action => action.key === 'Enter', button(/^(?:Enter\s+)?Done$/));
  await wait(/Save & exit/);
}
async function openEquipment() {
  const action = await headquartersEquipmentAction();
  await sourceChoice('open original equipment reader', choice => choice.id === action.id, button(/^Equipment(?:$|\s)/));
  await wait(/Increase ammo allocation/);
}
async function headquartersEquipmentAction() {
  const observed = await bridge('observe');
  assert.equal(observed.screen, 'headquarters', 'Use the equipment command only in the actual HQ reader.');
  const actions = observed.actions.filter(action => action.enabled && /Equip Squad/.test(action.label));
  assert.equal(actions.length, 1, 'Observe the current original HQ equipment command.');
  return actions[0];
}
async function selectedEquipmentPerson(name) {
  await click(`Select equipment for ${name}`);
  assert.ok(await button(`Select equipment for ${name}`).evaluate(node =>
    node.getAttribute('aria-selected') === 'true' || !!node.closest('[aria-selected="true"], [aria-current="true"]')),
  'The local equipment card must visibly identify the actual selected person.');
}
async function applyItem(typeName) {
  const action = await inventoryAction(typeName);
  await sourceChoice(`equip ${typeName}`, choice => choice.id === action.id,
    button(new RegExp(`^Equip ${escape(action.entityLabel)}, shortcut `)));
  return action;
}
async function recipient(phase) {
  await sourceChoice(`${phase} recipient ${equipmentActor.name}`,
    action => action.entityType === 'equipment-recipient' && action.entityId === String(equipmentActor.id)
      && action.entityCategory === phase,
    button(new RegExp(`^\\d+ ${escape(equipmentActor.name)}(?:$|\\s)`)));
}
function expectedGift(campaign, action, kind) {
  const expected = structuredClone(campaign), inventory = stock(expected);
  const index = Number(action.entityId), item = inventory[index];
  assert.equal(item.typeName, action.entityCategory, 'Original absolute stock index identifies the supplied item.');
  assert.equal(item.stackSize, 1, 'This finite fixture gives one unique weapon/outfit.');
  const actor = person(expected, equipmentActor.id);
  inventory.splice(index, 1);
  if (kind === 'weapon') {
    if (actor.equippedWeapon) inventory.push(actor.equippedWeapon);
    if (actor.spareAmmo) inventory.push(actor.spareAmmo);
    actor.equippedWeapon = item; actor.spareAmmo = null;
  } else {
    if (actor.equippedClothing && actor.equippedClothing.typeName !== 'CLOTHING_NONE') inventory.push(actor.equippedClothing);
    actor.equippedClothing = item;
  }
  assert.equal(new Set(inventory.map(entry => entry.typeName)).size, inventory.length,
    'Fixture avoids stock merging so the original exact gift delta is unambiguous.');
  return expected;
}
async function equipmentJourney() {
  // The original reader sorts/consolidates stock. Let that authored setup finish
  // before the one canonical campaign baseline used for inspection comparisons.
  await openEquipment();
  await snapshot('original-stock-normalization');
  await equipmentBack('normalization Back');
  const canonical = await exportGame('canonical-before-equipment');
  report.layouts.at(-1).canonicalBaseline = `${layout}-canonical-before-equipment.json`;
  await openEquipment();
  const beforeInspection = await snapshot('equipment-before-inspection');
  assert.deepEqual(beforeInspection.campaign, canonical);
  await selectedEquipmentPerson(equipmentActor.name);
  await click(/^Preparation details/); await wait(/0 loaded · 12 compatible spare rounds/);
  await capture('preparation-details');
  await click(/^Preparation details/);
  await selectedEquipmentPerson(prepared.lcs.pool[0].name);
  await selectedEquipmentPerson(equipmentActor.name);
  await chooseFilter('Weapons');
  await query(page.getByRole('textbox', { name: 'Filter this page', exact: true }), 'ak');
  const rifle = await inventoryAction('WEAPON_AK102');
  await click(new RegExp(`^Preview ${escape(rifle.entityLabel)}(?:$|\\s)`));
  await wait(new RegExp(`Compare equipment for ${escape(equipmentActor.name)}`));
  assert.match(await text(), /Current[\s\S]*Selected item/);
  await click(/^Equipment details/); await wait(/Damage and hit chances/); await capture('weapon-comparison-details');
  await click(/^Equipment details/);
  await query(page.getByRole('textbox', { name: 'Filter this page', exact: true }), '');
  for (const filter of ['Outfits', 'Ammo', 'Other', 'All']) await chooseFilter(new RegExp(`^${filter}$`));
  const afterInspection = await snapshot('equipment-after-inspection');
  sameSource(beforeInspection, afterInspection, 'Equipment selection, filtering, comparison and details');
  check('equipment inspection preserves full campaign, source reader/actions/revision and original actor');
  await sourceChoice('original inventory next page', action => /\bNext$/.test(action.label), button('Next page'));
  await wait(/Page 2 of 2/);
  const pageTwo = await snapshot('inventory-source-page-two');
  const pageTwoStock = pageTwo.observation.actions.filter(action => action.entityType === 'equipment-stock');
  assert.ok(pageTwoStock.length && pageTwoStock.every(action => Number(action.entityId) >= 18),
    'Source page two keeps the original absolute item indices.');
  await chooseFilter('Ammo');
  const ammo = await inventoryAction('AMMO_556'); await click(new RegExp(`^Preview ${escape(ammo.entityLabel)}(?:$|\\s)`));
  const filteredPageTwo = await snapshot('inventory-filtered-page-two');
  sameSource(pageTwo, filteredPageTwo, 'Filtering and preview on original page two');
  await capture('inventory-page-two-ammo-preview');
  await chooseFilter('All');
  await sourceChoice('original inventory previous page', action => /\bPrevious$/.test(action.label), button('Previous page'));
  await wait(/Page 1 of 2/);
  assert.deepEqual((await snapshot('inventory-paging-return')).campaign, canonical);
  check('original inventory paging retains absolute indices; local filters keep current action identities and campaign');
  await equipmentBack();
  assert.deepEqual(await exportGame('after-equipment-inspection'), canonical);
  await openEquipment();
  await selectedEquipmentPerson(equipmentActor.name);
  await applyItem('WEAPON_AK102');
  const cancel = button(/^Cancel$/);
  await reveal(cancel); await keyboardFocus(cancel, 'original equipment recipient Cancel');
  await capture('recipient-cancel-focused');
  await sourceChoice('cancel original equipment recipient', action => action.key === 'Enter' && /Cancel/.test(action.label),
    cancel, { keyboard: true });
  assert.deepEqual((await snapshot('after-recipient-cancel')).campaign, canonical);
  check('original recipient cancellation through keyboard leaves every campaign field unchanged');
  const beforeWeapon = await snapshot('before-weapon');
  const weaponAction = await applyItem('WEAPON_AK102'); await recipient('giveItem');
  const afterWeapon = await snapshot('after-weapon');
  assert.deepEqual(afterWeapon.campaign, expectedGift(beforeWeapon.campaign, weaponAction, 'weapon'),
    'Only the intended person receives this exact weapon; their previous weapon/ammo return to the source stock.');
  check('original stock letter and recipient equip the chosen weapon for only the intended person');
  const beforeOutfit = await snapshot('before-outfit');
  const outfit = await inventoryAction('CLOTHING_CATSUIT');
  await click(new RegExp(`^Preview ${escape(outfit.entityLabel)}(?:$|\\s)`)); await capture('outfit-comparison');
  const outfitAction = await applyItem('CLOTHING_CATSUIT'); await recipient('giveItem');
  const afterOutfit = await snapshot('after-outfit');
  assert.deepEqual(afterOutfit.campaign, expectedGift(beforeOutfit.campaign, outfitAction, 'outfit'),
    'Only the intended outfit and exact stock entries change.');
  check('original outfit action replaces only the intended person’s outfit and returns the old one to stock');
  const beforeAmmo = await snapshot('before-ammo');
  await sourceChoice('increase original ammunition allocation', action => action.key === 'Up', button(/^Increase ammo allocation$/));
  await recipient('increaseAmmo');
  const afterAmmo = await snapshot('after-ammo-increase');
  const expectedAmmo = structuredClone(beforeAmmo.campaign);
  const reserve = stock(expectedAmmo).find(item => item.typeName === 'AMMO_556');
  assert.ok(reserve.stackSize >= 30); reserve.stackSize -= 30;
  person(expectedAmmo, equipmentActor.id).spareAmmo = { typeName: 'AMMO_556', stackSize: 30 };
  assert.deepEqual(afterAmmo.campaign, expectedAmmo, 'Allocate exactly one original30-round magazine; no loaded rounds or other fields change.');
  await click(/^Preparation details/); await wait(/0 loaded · 30 compatible spare rounds/); await capture('allocated-ammo-readiness');
  await click(/^Preparation details/);
  await sourceChoice('decrease original ammunition allocation', action => action.key === 'Down', button(/^Decrease ammo allocation$/));
  await recipient('decreaseAmmo');
  const afterAmmoReturn = await snapshot('after-ammo-return');
  assert.deepEqual(afterAmmoReturn.campaign, beforeAmmo.campaign, 'Returning the same magazine restores the complete prior campaign.');
  check('original increase/decrease allocation updates compatible spare rounds and exactly restores campaign on return');
  await equipmentBack();
  const equippedSave = await exportGame('equipped-campaign');
  assert.deepEqual(equippedSave, afterAmmoReturn.campaign, 'Native export retains the exact equipment result.');
  await openEquipment();
  assert.equal((await bridge('observe')).actions.filter(action => action.entityType === 'equipment-stock'
    && action.entityCategory === 'WEAPON_AK102').length, 0, 'No stale stock action for the equipped rifle.');
  await selectedEquipmentPerson(equipmentActor.name); await capture('equipment-revisited');
  await equipmentBack();
  // Reentering the original reader sorts newly returned stock. This fixture has
  // one weapon and unique outfit/ammo/loot types, so its exact original class /
  // type-id order is unambiguous; preserve every item payload and other field.
  const sortedExpected = structuredClone(equippedSave), returnedStock = stock(sortedExpected);
  const rank = { WEAPON: 0, CLOTHING: 1, AMMO: 2, LOOT: 3 };
  assert.equal(returnedStock.filter(item => item.typeName.startsWith('WEAPON_')).length, 1);
  assert.equal(new Set(returnedStock.map(item => item.typeName)).size, returnedStock.length);
  for (const item of returnedStock) assert.ok(item.typeName.split('_')[0] in rank);
  returnedStock.sort((a, b) => rank[a.typeName.split('_')[0]] - rank[b.typeName.split('_')[0]]
    || (a.typeName < b.typeName ? -1 : a.typeName > b.typeName ? 1 : 0));
  assert.deepEqual(await exportGame('after-equipment-revisit'), sortedExpected,
    'Original stock sorting is the only change on equipment reentry; all complete item payloads and other campaign fields remain exact.');
  report.sourceNormalizations.push({ layout, kind: 'original equipment reentry stock sort', siteId: home.id,
    before: `${layout}-equipped-campaign.json`, after: `${layout}-after-equipment-revisit.json` });
  check('Back/revisit and native save round trip retain the final equipment without stale stock actions');
}
const boardLocator = () => page.getByRole('dialog').filter({
  has: page.getByRole('button', { name: /^Close daily plan(?:$|\s)/ }),
});
async function openBoard() {
  await click(/^Daily plan$/);
  const board = boardLocator(); await board.waitFor({ state: 'visible' });
  await button('Close daily plan', board).click({ trial: true });
  return board;
}
async function boardQuery(board, value) {
  await query(board.getByRole('textbox', { name: 'Search daily plan', exact: true }), value, board);
}
async function boardSelect(board, name, { details = false } = {}) {
  await click(`Select daily plan for ${name}`, board);
  await wait(new RegExp(`Selected: ${escape(name)}`));
  if (details) await click(`Show daily plan details for ${name}`, board);
}
async function closeBoard(board, { keyboard = false } = {}) {
  if (keyboard) {
    await keyboardFocus(button('Close daily plan', board), 'Daily plan Close');
    await capture('daily-plan-close-focused');
    await page.keyboard.press('Enter');
  } else await click('Close daily plan', board);
  await board.waitFor({ state: 'hidden' }); await waitForUiSettled(page);
}
async function dailyPlanJourney() {
  let initial = await snapshot('before-daily-plan');
  let board = await openBoard();
  await keyboardFocus(button('Close daily plan', board), 'Daily plan modal isolation outside search');
  for (const key of ['w', 'p', 'd']) {
    await page.keyboard.press(key); await waitForUiSettled(page);
    assert.ok(await board.isVisible(), `Bare ${key} must remain inside the board modal.`);
  }
  sameSource(initial, await snapshot('board-bare-key-isolation'), 'Bare W/P/D inside the Daily plan modal');
  await capture('daily-plan-modal-key-isolation');
  await page.keyboard.press('Escape'); await board.waitFor({ state: 'hidden' }); await waitForUiSettled(page);
  sameSource(initial, await snapshot('board-escape-dismissal'), 'Escape dismisses only the board');
  // Do not click the background to repair focus. Exercise the next original
  // equipment/Back keys, then baseline its new reader identity separately.
  const equipmentCommand = await headquartersEquipmentAction();
  await sourceChoice('original keyboard equipment after modal Escape', action => action.id === equipmentCommand.id,
    button(/^Equipment(?:$|\s)/), { keyboard: equipmentCommand.key });
  await sourceChoice('original keyboard Back after modal Escape', action => action.key === 'Enter', button(/^(?:Enter\s+)?Done$/), { keyboard: true });
  await wait(/Save & exit/);
  const continued = await snapshot('source-keyboard-continued-after-modal');
  assert.deepEqual(continued.campaign, initial.campaign, 'Original keyboard continuation after modal dismissal preserves the complete campaign.');
  initial = continued;
  check('modal-focused bare W/P/D cannot reach gameplay; Escape restores original equipment/Back keyboard continuation');
  board = await openBoard();
  for (const [label, count] of [['All', 21], ['Needs order', 7], ['Assigned', 12], ['Unavailable', 2]]) {
    assert.equal(await board.getByRole('checkbox', { name: `${label} (${count})`, exact: true }).count(), 1,
      'Movement-wide counts include the explicitly prepared people outside the active squad.');
  }
  await capture('daily-plan-movement-overview');
  await chooseFilter(/^Needs order \(/, board);
  await wait(/Available active crew currently Laying Low/);
  await boardQuery(board, 'Zed Planner');
  const lastName = 'Zed Planner 10';
  await boardSelect(board, lastName, { details: true });
  await wait(/Personal order: Laying Low/);
  const anchor = button(`Select daily plan for ${lastName}`, board);
  await reveal(anchor, board);
  const beforeBounds = await anchor.boundingBox();
  await capture('daily-plan-filtered-scroll');
  await closeBoard(board, { keyboard: true });
  sameSource(initial, await snapshot('daily-plan-closed'), 'Daily plan inspection and keyboard Close');
  board = await openBoard();
  await wait(new RegExp(`Selected: ${lastName}`));
  assert.ok(await board.getByRole('checkbox', { name: /^Needs order \(/ }).isChecked(), 'Reopening retains the selected Needs order filter.');
  assert.equal(await button(`Hide daily plan details for ${lastName}`, board).count(), 1);
  const afterBounds = await button(`Select daily plan for ${lastName}`, board).boundingBox();
  assert.ok(beforeBounds && afterBounds && Math.abs(beforeBounds.y - afterBounds.y) <= 4,
    'Reopening the unchanged board retains the actual list scroll anchor.');
  // Flutter synchronizes the recreated semantic input with its retained editor
  // value only when editing is active; inspect scroll/selection before focusing.
  const retainedSearch = board.getByRole('textbox', { name: 'Search daily plan', exact: true });
  await reveal(retainedSearch, board); await retainedSearch.click(); await waitForUiSettled(page);
  assert.ok(await retainedSearch.evaluate(node => node === document.activeElement || node.contains(document.activeElement)),
    'The actual reopened search input must own editing focus.');
  assert.equal(await retainedSearch.inputValue(), 'Zed Planner');
  check('Daily plan retains search, Needs order filter, selected person, expanded detail and list scroll after keyboard Close/reopen');
  await chooseFilter(/^Unavailable \(/, board); await boardQuery(board, hospitalPerson.name);
  await boardSelect(board, hospitalPerson.name, { details: true });
  await wait(/Hospitalized/); await wait(new RegExp(escape(hospital.name)));
  assert.equal(await button(`Orders for ${hospitalPerson.name}`, board).isEnabled(), false);
  await capture('daily-plan-unavailable-hospital');
  await chooseFilter(/^All \(/, board); await boardQuery(board, sleeper.name);
  await boardSelect(board, sleeper.name, { details: true });
  await wait(/sleeper standing order/); await capture('daily-plan-sleeper-standing-order');
  await boardQuery(board, prospect.name);
  await boardSelect(board, prepared.lcs.pool[3].name, { details: true });
  await wait(new RegExp(escape(prospect.name))); await wait(/Ready for a join offer/); await wait(/free recruitment slots/);
  await capture('daily-plan-pending-recruitment');
  await boardQuery(board, 'Quinn Scout');
  await boardSelect(board, 'Quinn Scout', { details: true });
  await wait(/Queued squad visit/); await wait(new RegExp(escape(park.name)));
  await wait(/Personal order: Laying Low/);
  assert.equal(await button('Orders for Quinn Scout', board).isEnabled(), false);
  await capture('daily-plan-queued-squad-override');
  await closeBoard(board);
  sameSource(initial, await snapshot('after-mixed-board-inspection'), 'Mixed jobs, availability, queued visits and recruitment inspection');
  assert.deepEqual(await exportGame('after-daily-plan-inspection'), initial.campaign);
  check('Mixed movement facts and stored recruitment details preserve complete campaign, pending input and original actor');

  // View squad is an original source selection, not a read-only preview. Pin
  // its exact active-squad delta, then restore it before later comparisons.
  board = await openBoard();
  await click(`View ${queuedSquad.name} squad`, board); await board.waitFor({ state: 'hidden' });
  await wait(/Visit queued/);
  const selectedSquad = await snapshot('queued-squad-view');
  const selectedExpected = structuredClone(initial.campaign); selectedExpected.activeSquadId = queuedSquad.id;
  assert.deepEqual(selectedSquad.campaign, selectedExpected, 'View squad changes only the original active squad selection.');
  await capture('queued-squad-source-view');
  await click(new RegExp(`^Select squad ${escape(prepared.lcs.squads[0].name)}(?:$|\\s)`));
  await wait(/Save & exit/);
  assert.deepEqual((await snapshot('restored-equipment-squad')).campaign, initial.campaign,
    'Restoring the active squad preserves the queued departure and every other field.');
  check('View squad follows the original queued team and returns without canceling departure');

  board = await openBoard(); await chooseFilter(/^All \(/, board); await boardQuery(board, hospitalPerson.name);
  await boardSelect(board, hospitalPerson.name);
  await click(`Profile for ${hospitalPerson.name}`, board); await board.waitFor({ state: 'hidden' });
  await wait(/Back to directory/); await wait(new RegExp(escape(hospitalPerson.name)));
  await capture('board-native-hospital-profile');
  await click(/^Back to directory/); await wait(/Personnel directory/);
  await click(/^Organisation(?:$|\s)/); await wait(/Save & exit/);
  assert.deepEqual((await snapshot('after-native-profile')).campaign, initial.campaign);
  check('Profile opens the original intended person and Back returns without changing campaign');

  board = await openBoard(); await chooseFilter(/^Needs order \(/, board); await boardQuery(board, orderActor.name);
  await boardSelect(board, orderActor.name);
  await click(`Orders for ${orderActor.name}`, board); await board.waitFor({ state: 'hidden' });
  await click(/^Business(?:$|\s)/); await wait(/Prepare Solicit Donations/);
  const orderFrame = await snapshot('clicked-actor-orders');
  assert.ok(orderFrame.observation.actions.some(action => action.entityType === 'activity'
    && action.entityId === 'donations' && action.entityCategory === String(orderActor.id)),
  'The original Orders reader must be for the person selected on the board.');
  await click(/^Prepare Solicit Donations(?:$|\s)/);
  await wait(/Prepared · awaiting confirmation/);
  const draft = await snapshot('daily-plan-local-draft');
  sameSource(orderFrame, draft, 'Preparing a daily order is a local draft');
  await capture('daily-plan-order-draft');
  await click(/^Cancel prepared order$/);
  sameSource(orderFrame, await snapshot('daily-plan-cancelled-draft'), 'Cancel retains the current actor and all existing assignments');
  check('Orders routes the clicked outside-squad actor; preparing and Cancel preserve full campaign and source actions');
  await click(/^Prepare Solicit Donations(?:$|\s)/); await wait(/Prepared · awaiting confirmation/);
  const beforeConfirm = await snapshot('before-daily-plan-confirm');
  await sourceChoice('confirm clicked actor donations', action => action.entityType === 'activity'
    && action.entityId === 'donations' && action.entityCategory === String(orderActor.id), button('Confirm order'));
  const confirmed = await snapshot('after-daily-plan-confirm');
  const confirmedExpected = structuredClone(beforeConfirm.campaign);
  person(confirmedExpected, orderActor.id).activity = { type: 'donations' };
  assert.deepEqual(confirmed.campaign, confirmedExpected,
    'Only the clicked person’s original activity changes; all other jobs, queued departure, people, stock, funds and date stay exact.');
  await capture('daily-plan-confirmed-actor');
  await click(/^Return to planning; keep assigned orders$/);
  await wait(/Save & exit/);
  assert.deepEqual(await exportGame('final-planned-equipped-campaign'), confirmedExpected);
  board = await openBoard(); await chooseFilter(/^Assigned \(/, board); await boardQuery(board, orderActor.name);
  await boardSelect(board, orderActor.name, { details: true });
  await wait(/Personal order: Soliciting Donations/);
  await capture('daily-plan-refreshed-after-confirmation');
  await closeBoard(board);
  assert.deepEqual((await snapshot('final-after-revisit')).campaign, confirmedExpected);
  check('Confirm changes only the intended person; native save and refreshed board retain equipment, other jobs and queued visit');
}

try {
  const response = await fetch(new URL('main.dart.js', url));
  assert.ok(response.ok); report.mainJsSha256 = hash(Buffer.from(await response.arrayBuffer()));
  assert.equal(report.mainJsSha256, expectedHash);
  browser = await chromium.launch(chromiumLaunchOptions({ args }));
  for (const configuration of [
    { name: 'desktop', viewport: { width: 1440, height: 1000 }, reading: '100%' },
    { name: 'large', viewport: { width: 1024, height: 720 }, reading: '150%' },
  ]) {
    layout = configuration.name; report.layouts.push(configuration);
    ({ context, page } = await createQaPage(browser, { previousContext: context, report,
      errorContext: () => ({ layout }), timeout: 12000 }));
    await page.setViewportSize(configuration.viewport);
    verifyLoaded = observeMainScript(page, report);
    context.on('console', message => {
      if (!message.page() && message.type() === 'error') report.workerErrors.push({ layout, error: message.text(), location: message.location() });
    });
    await page.goto(url, { waitUntil: 'domcontentloaded' }); await wait(/Start a New Game/);
    await button(/Start a New Game/).click({ trial: true });
    const choosing = page.waitForEvent('filechooser'); await click(/^Import a Save/); await (await choosing).setFiles(fixturePath);
    await wait(/Save imported/); await page.keyboard.press('Enter'); await wait(/Start a New Game/);
    await click(/^Load & Manage Saves/); await click(/^A(?:\s|$)/); await click(/^L Load Game/); await wait(/Save & exit/);
    const initial = await snapshot('initial-import');
    report.layouts.at(-1).bridgeBuild = initial.observation.build;
    await click(/^Reading size/); await page.getByRole('menuitem', { name: configuration.reading, exact: true }).click();
    await waitForUiSettled(page);
    await equipmentJourney();
    await dailyPlanJourney();
    await verifyLoaded(expectedHash);
    await context.close(); context = null;
  }
  assert.equal(report.loadedMainJsHashes.length, 2);
  for (const actual of report.loadedMainJsHashes) assert.equal(actual, expectedHash);
  assert.deepEqual(report.pageErrors, []); assert.deepEqual(report.consoleErrors, []);
  assert.deepEqual(report.failedRequests, []); assert.deepEqual(report.workerErrors, []);
  report.status = 'passed';
} catch (error) {
  report.status = 'failed'; report.failure = error.stack ?? String(error); process.exitCode = 1;
  report.errors.push({ layout, error: report.failure });
  if (page && !page.isClosed()) {
    await capture('FAILURE').catch(error => { report.captureError = String(error); });
    await writeFile(resolve(output, `${layout}-failure-semantics.html`), await page.locator('flt-semantics-host').innerHTML())
      .catch(error => { report.domCaptureError = String(error); });
    report.failureControls = await page.locator('flt-semantics[role]').evaluateAll(nodes => nodes.map(node => ({
      role: node.getAttribute('role'), label: node.getAttribute('aria-label'), text: node.textContent,
      selected: node.getAttribute('aria-selected'), checked: node.getAttribute('aria-checked'),
      bounds: node.getBoundingClientRect().toJSON(),
    }))).catch(error => [{ error: String(error) }]);
    await snapshot('failure').catch(error => { report.observationError = String(error); });
    await verifyLoaded?.(expectedHash).catch(error => { report.loadedScriptError = String(error); });
  }
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  await browser?.close();
  console.log(JSON.stringify({ status: report.status, output, checks: report.checks.length, loadedMainJsHashes: report.loadedMainJsHashes }));
}
