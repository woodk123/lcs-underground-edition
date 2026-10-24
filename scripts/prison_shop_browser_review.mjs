// Supplemental acceptance: prepared prisoners and print-shop premises, ordinary UI input.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, isAbsolute, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertQaUrl, chromiumLaunchOptions, observeMainScript, waitForSemantics, waitForUiSettled } from './browser_support.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const option = (flag, fallback) => {
  const index = args.indexOf(flag);
  if (index < 0) return fallback;
  assert.ok(args[index + 1] && !args[index + 1].startsWith('--'), `${flag} requires a value.`);
  return args[index + 1];
};
if (args.includes('--help')) {
  console.log('Usage: node scripts/prison_shop_browser_review.mjs --expected-hash SHA256 [--url http://127.0.0.1:18889/] [--out FRESH_IGNORED_DIRECTORY] [--prepare-only]\nRequires a current LCS_DEVTOOLS=true build. Uses observe/inspect only; original UI controls perform every game action.');
  process.exit(0);
}
const prepareOnly = args.includes('--prepare-only');
const expectedHash = option('--expected-hash', '').toLowerCase();
if (!prepareOnly) assert.match(expectedHash, /^[a-f0-9]{64}$/, 'Supply the exact compiled JavaScript hash.');
const url = assertQaUrl(option('--url', 'http://127.0.0.1:18889/'), 'http://127.0.0.1:18889/');
const output = resolve(root, option('--out', `reports/prison-shop-${Date.now()}`));
assert.ok(['.local', 'reports'].some(parent => {
  const child = relative(resolve(root, parent), output);
  return child && !isAbsolute(child) && child !== '..' && !child.startsWith('../') && !child.startsWith('..\\');
}), 'Keep fresh evidence beneath ignored .local/ or reports/.');
await mkdir(dirname(output), { recursive: true });
await mkdir(output);
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const decode = envelope => typeof envelope.saveData === 'string' ? JSON.parse(envelope.saveData) : envelope.saveData;
const sitesOf = campaign => campaign.cities.flatMap(city => city.districts.flatMap(district => district.sites));
const personOf = (campaign, id) => campaign.lcs.pool.find(person => person.id === id);
const siteOf = (campaign, id) => sitesOf(campaign).find(site => site.id === id);
const sourceFixture = resolve(root, 'upstream/test/saves/felix_1_0.json');
const originalBytes = await readFile(sourceFixture);
const envelope = JSON.parse(originalBytes), prepared = decode(envelope);
const originalHome = siteOf(prepared, prepared.lcs.pool[0].baseId);
const home = sitesOf(prepared).find(site => site.type === 'warehouse' && site.cityId === originalHome.cityId);
const prison = sitesOf(prepared).find(site => site.type === 'prison' && site.cityId === home.cityId);
assert.ok(home && prison, 'Use existing source-authored warehouse/prison locations.');
Object.assign(home, { controller: 'lcs', closed: 0, _businessFront: false, frontBusiness: null, name: 'Prepared Print Warehouse' });
home.siege.activeSiegeType = 'none';
for (const person of prepared.lcs.pool) {
  Object.assign(person, { baseId: home.id, locationId: `Site${home.id}`, activity: { type: 'none' }, heat: 0 });
  person.wantedForCrimes = Object.fromEntries(Object.keys(person.wantedForCrimes).map(key => [key, 0]));
}
const addPerson = (name, patch) => {
  const person = { ...structuredClone(prepared.lcs.pool[0]), id: prepared.nextCreatureId++, name, properName: name,
    hireId: prepared.lcs.pool[0].id, squadId: null, carId: null, preferredCarId: null, isDriver: false,
    preferredDriver: false, sleeperAgent: false, hidingDaysLeft: 0, vacationDaysLeft: 0, ...patch };
  prepared.lcs.pool.push(person); return person;
};
const worker = addPerson('Prepared Print Worker', {});
const prisoner = addPerson('Prepared Prisoner', { locationId: `Site${prison.id}`, sentence: 12, deathPenalty: false,
  prisonActivity: { order: 'keepHeadDown', contacts: 1, documentProgress: 1, documentCompleted: false,
    pendingDocument: false, pendingDocumentCityId: null, lastResolvedMonth: null, lastReport: 'Prepared prison progress; no earned outcome claimed.' } });
prepared.ledger._funds = 20000;
prepared.politics.laws.prisons = 'moderate';
envelope.saveData = typeof envelope.saveData === 'string' ? JSON.stringify(prepared) : prepared;
const fixturePath = resolve(output, 'prepared-prison-shop.json');
await writeFile(fixturePath, JSON.stringify(envelope));
const report = { status: prepareOnly ? 'prepared' : 'running', url, expectedHash: expectedHash || null,
  scope: 'Explicitly prepared Felix fixture: owned warehouse, $20,000, ordinary outside worker and sentenced prisoner with one contact/evidence month. No day/month advances or earned results are claimed. Original source pointer/keyboard choices, cancellation, reader return, bounds/focus, whole-campaign comparisons and native save export/import at desktop and enlarged layouts. Bridge is observe/inspect only; seeded subsystem regressions establish RNG and monthly outcomes.',
  prepared: { source: relative(root, sourceFixture), sourceSha256: sha256(originalBytes), fixture: relative(output, fixturePath),
    home: { id: home.id, name: home.name }, prison: { id: prison.id, name: prison.name }, worker: { id: worker.id, name: worker.name },
    prisoner: { id: prisoner.id, name: prisoner.name }, setupCost: 4500 },
  checks: [], sourceActions: [], snapshots: [], screenshots: [], geometry: [], focusChecks: [], pageErrors: [], consoleErrors: [], failedRequests: [], loadedMainJsHashes: [] };
await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
if (prepareOnly) { console.log(JSON.stringify({ status: 'prepared', output, fixturePath })); process.exit(0); }
assert.equal(sha256(Buffer.from(await (await fetch(new URL('main.dart.js', url))).arrayBuffer())), expectedHash);
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const browser = await chromium.launch(chromiumLaunchOptions({ args }));
let page, context, layout;
const escaped = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const button = pattern => page.getByRole('button', { name: pattern }).first();
const wait = pattern => waitForSemantics(page, pattern);
async function bridge(method, params = {}) {
  assert.ok(['observe', 'inspect'].includes(method), 'The browser bridge is read-only.');
  const raw = await page.evaluate(async ({ method, params }) => {
    if (!globalThis.lcsDev?.request) throw Error('Use a build prepared with LCS_DEVTOOLS=true.');
    return await globalThis.lcsDev.request(JSON.stringify({ method, params }));
  }, { method, params });
  const answer = JSON.parse(raw);
  assert.ok(answer.ok, `Read-only ${method}: ${JSON.stringify(answer.error)}`);
  return answer.result;
}
const campaign = async () => (await bridge('inspect', { scope: 'campaign' })).campaign;
async function snapshot(name) {
  const data = { observation: await bridge('observe'), campaign: await campaign() };
  const file = `${layout}-${report.snapshots.length + 1}-${name}.json`;
  await writeFile(resolve(output, file), JSON.stringify(data, null, 2));
  report.snapshots.push({ layout, name, file }); return data;
}
async function capture(name) {
  const file = `${layout}-${report.screenshots.length + 1}-${name}.png`;
  await page.screenshot({ path: resolve(output, file), fullPage: true }); report.screenshots.push(file);
}
async function reveal(control) {
  for (let attempt = 0; attempt < 35; attempt++) {
    const viewport = page.viewportSize();
    const geometry = await control.count() ? await control.evaluate(node => {
      const box = node.getBoundingClientRect();
      let left = 0, top = 0, right = innerWidth, bottom = innerHeight;
      for (let parent = node.parentElement; parent; parent = parent.parentElement) {
        const style = getComputedStyle(parent);
        if (!/(hidden|auto|scroll)/.test(`${style.overflowX} ${style.overflowY}`)) continue;
        const clip = parent.getBoundingClientRect();
        left = Math.max(left, clip.left); top = Math.max(top, clip.top);
        right = Math.min(right, clip.right); bottom = Math.min(bottom, clip.bottom);
      }
      return { x: box.x, y: box.y, width: box.width, height: box.height, left, top, right, bottom };
    }) : null;
    if (geometry && geometry.height > 4 && geometry.x >= geometry.left - .02 && geometry.y >= geometry.top
      && geometry.x + geometry.width <= geometry.right + .02 && geometry.y + geometry.height <= geometry.bottom) {
      await control.click({ trial: true, timeout: 1000 });
      report.geometry.push({ layout, ...geometry }); return;
    }
    const area = geometry && geometry.bottom - geometry.top > 8 ? geometry
      : { left: viewport.width * .25, right: viewport.width - 20, top: 140, bottom: viewport.height - 65 };
    await page.mouse.move((area.left + area.right) / 2, (area.top + area.bottom) / 2);
    await page.mouse.wheel(0, geometry && geometry.y < area.top ? -180 : 180);
    await page.mouse.move(2, 2); await waitForUiSettled(page);
  }
  throw Error('Current control could not be exposed within its actual clipped viewport.');
}
async function click(pattern) {
  const control = button(pattern); await reveal(control);
  assert.ok(await control.isEnabled(), `Enabled UI control: ${pattern}`);
  await control.click(); await page.mouse.move(2, 2); await waitForUiSettled(page);
}
async function key(input) { await page.keyboard.press(input); await waitForUiSettled(page); }
async function focus(control, name) {
  await reveal(control);
  for (let tabs = 0; tabs < 55; tabs++) {
    const state = await control.evaluate(node => ({
      focused: node === document.activeElement || node.contains(document.activeElement),
      target: node.outerHTML.slice(0, 1500),
      active: document.activeElement?.outerHTML.slice(0, 1500),
      hasFocus: document.hasFocus(),
    }));
    (report.focusTrace ??= []).push({ layout, name, tabs, ...state });
    if (state.focused) {
      report.focusChecks.push({ layout, name, tabs }); return;
    }
    await key('Tab');
  }
  throw Error(`Tab traversal could not focus ${name}.`);
}
async function sourceChoice(name, predicate, pattern, { keyboard = false } = {}) {
  const before = await bridge('observe');
  assert.ok(before.awaitingInput && !before.textInput, `${name}: source choice is ready.`);
  const choices = before.actions.filter(action => action.kind === 'source_action' && action.enabled && predicate(action));
  assert.equal(choices.length, 1, `${name}: one current source action.`);
  const action = choices[0], control = button(pattern);
  await reveal(control); assert.ok(await control.isEnabled(), `${name}: pointer control enabled.`);
  if (keyboard) await focus(control, name);
  const current = await bridge('observe');
  assert.equal(current.revision, before.revision, `${name}: revision retained before input.`);
  assert.deepEqual(current.actions.find(choice => choice.id === action.id), action);
  report.sourceActions.push({ layout, name, revision: before.revision, action, input: keyboard ? 'Tab then Enter' : 'pointer' });
  if (keyboard) await key('Enter'); else { await control.click(); await page.mouse.move(2, 2); }
  await page.waitForFunction(async revision => {
    const answer = JSON.parse(await globalThis.lcsDev.request(JSON.stringify({ method: 'observe', params: {} })));
    return answer.ok && answer.result.revision !== revision && answer.result.awaitingInput;
  }, before.revision, { timeout: 20000 });
  await waitForUiSettled(page);
}
const back = async name => sourceChoice(name, action => action.key === 'Enter', /^(?:Enter\s+)?Back$/);
async function importSave(path) {
  const choosing = page.waitForEvent('filechooser'); await click(/^Import a Save/);
  await (await choosing).setFiles(path); await wait(/Save imported/); await key('Enter');
  await click(/^Load & Manage Saves/); await click(/^A(?:\s|$)/); await click(/^L Load Game/); await wait(/Save & exit/);
}
async function exportAndReload(name) {
  await click(/^Save & exit/); await wait(/Start a New Game/);
  await click(/^Load & Manage Saves/); await click(/^A(?:\s|$)/);
  const downloading = page.waitForEvent('download'); await click(/Export Save File/);
  const path = resolve(output, `${layout}-${name}.json`); await (await downloading).saveAs(path);
  const saved = decode(JSON.parse(await readFile(path, 'utf8')));
  // Return to the title using the original reader's Back before native import.
  await key('Escape'); await key('Escape'); await wait(/Start a New Game/);
  await importSave(path); return saved;
}
try {
  for (const size of [{ width: 1440, height: 1000, reading: '100%' }, { width: 1024, height: 720, reading: '150%' }]) {
    layout = `${size.width}-${size.reading}`;
    context = await browser.newContext({ viewport: { width: size.width, height: size.height }, acceptDownloads: true });
    page = await context.newPage(); page.setDefaultTimeout(20000);
    const verifyLoaded = observeMainScript(page, report);
    page.on('pageerror', error => report.pageErrors.push({ layout, error: String(error) }));
    page.on('console', message => { if (message.type() === 'error') report.consoleErrors.push({ layout, error: message.text() }); });
    page.on('requestfailed', request => report.failedRequests.push({ layout, url: request.url(), error: request.failure() }));
    await page.goto(url, { waitUntil: 'domcontentloaded' }); await wait(/Start a New Game/); await importSave(fixturePath);
    await click(/^Reading size/); await page.getByRole('menuitem', { name: size.reading, exact: true }).click(); await waitForUiSettled(page);
    const initial = await campaign();
    await click(/^Justice(?:\.|$)/); await wait(/Manage prison orders/);
    await sourceChoice('Justice prison management', action => action.key === 'u', /Manage prison orders/);
    await sourceChoice('select sentenced prisoner', action => action.entityType === 'prisoner-person' && action.entityId === `${prisoner.id}`, /Prepared Prisoner/);
    const inspecting = await snapshot('prison-inspect');
    assert.deepEqual(inspecting.campaign, initial, 'Browsing Justice/prison management changes no campaign data.');
    await capture('prison-orders');
    await back('prison detail cancellation'); await sourceChoice('revisit prisoner', action => action.entityType === 'prisoner-person' && action.entityId === `${prisoner.id}`, /Prepared Prisoner/);
    assert.deepEqual(await campaign(), initial, 'Back and revisit preserve whole campaign.');
    await sourceChoice('Study Law through keyboard focus', action => action.entityType === 'prison-order' && action.entityId === 'studyLaw', /Study Law/, { keyboard: true });
    const ordered = await snapshot('prison-law-order');
    const expectedOrder = structuredClone(initial); personOf(expectedOrder, prisoner.id).prisonActivity.order = 'studyLaw';
    assert.deepEqual(ordered.campaign, expectedOrder, 'Only the prisoner standing order changed.');
    await back('prison order back'); await sourceChoice('revisit selected order', action => action.entityType === 'prisoner-person' && action.entityId === `${prisoner.id}`, /Prepared Prisoner/);
    await wait(/Current order: Study Law/); await back('return prisoner roster');
    await click(/^Bases(?:\.|$)/); await wait(/Manage print shop/);
    const baseChoice = page.getByText(/^Prepared Print Warehouse(?:,|$)/).first();
    await reveal(baseChoice); await baseChoice.click(); await waitForUiSettled(page);
    await click(/^Manage print shop$/); await wait(/Set up print shop/);
    const beforeSetup = await snapshot('shop-before-setup');
    await sourceChoice('prepare print shop setup', action => action.entityType === 'front-business-setup', /Set up print shop/);
    await wait(/Total setup: \$4500/); await capture('shop-setup-confirmation');
    await sourceChoice('cancel setup', action => action.key === 'Enter', /^(?:Enter\s+)?(?:Cancel|Back)$/);
    assert.deepEqual(await campaign(), beforeSetup.campaign, 'Setup cancellation spends no funds and creates no shop.');
    await sourceChoice('prepare setup again', action => action.entityType === 'front-business-setup', /Set up print shop/);
    await sourceChoice('pay setup once', action => action.entityType === 'front-business-confirm', /Pay for setup/);
    const equipped = await snapshot('shop-equipped');
    assert.equal(equipped.campaign.ledger._funds, beforeSetup.campaign.ledger._funds - 4500);
    assert.ok(siteOf(equipped.campaign, home.id).frontBusiness); await capture('shop-operating-controls');
    await sourceChoice('open shop name draft', action => action.entityType === 'front-business-name', /Name this business/);
    const textbox = page.getByRole('textbox').first(); await textbox.fill('Cancelled shop name');
    await click(/^Cancel edits$/);
    assert.deepEqual(await campaign(), equipped.campaign, 'Name cancellation preserves the complete campaign.');
    await sourceChoice('open staff picker', action => action.entityType === 'front-business-staffing', /Manage staff/);
    await sourceChoice('assign prepared worker', action => action.entityType === 'front-business-staff' && action.entityId === `${worker.id}`, /Prepared Print Worker/);
    await back('return shop management');
    const staffed = await snapshot('shop-staffed');
    assert.deepEqual(personOf(staffed.campaign, worker.id).activity, { type: 'workPrintShop', idString: `Site${home.id}` });
    assert.deepEqual(siteOf(staffed.campaign, home.id).frontBusiness.staffIds, [worker.id]);
    await sourceChoice('choose movement printing', action => action.entityType === 'front-business-mode' && action.entityId === 'movement', /Movement printing: Free Speech/);
    const movement = await snapshot('shop-movement');
    assert.equal(siteOf(movement.campaign, home.id).frontBusiness.mode, 'movement');
    await capture('shop-movement');
    await sourceChoice('close shop and release staff', action => action.entityType === 'front-business-mode' && action.entityId === 'closed', /Temporarily close and release staff/);
    const closed = await snapshot('shop-closed');
    assert.equal(siteOf(closed.campaign, home.id).frontBusiness.mode, 'closed');
    assert.deepEqual(siteOf(closed.campaign, home.id).frontBusiness.staffIds, []);
    assert.equal(personOf(closed.campaign, worker.id).activity.type, 'none');
    await sourceChoice('reopen commercial shop', action => action.entityType === 'front-business-mode' && action.entityId === 'commercial', /Commercial work/);
    await sourceChoice('reopen staffing', action => action.entityType === 'front-business-staffing', /Manage staff/);
    await sourceChoice('restore worker for persistence', action => action.entityType === 'front-business-staff' && action.entityId === `${worker.id}`, /Prepared Print Worker/);
    await back('staffing back for persistence');
    const beforeSave = await snapshot('before-native-export');
    const saved = await exportAndReload('native-export');
    const loaded = await snapshot('after-native-import');
    assert.deepEqual(personOf(saved, prisoner.id).prisonActivity, personOf(beforeSave.campaign, prisoner.id).prisonActivity);
    assert.deepEqual(siteOf(saved, home.id).frontBusiness, siteOf(beforeSave.campaign, home.id).frontBusiness);
    assert.deepEqual(personOf(loaded.campaign, prisoner.id).prisonActivity, personOf(saved, prisoner.id).prisonActivity);
    assert.deepEqual(siteOf(loaded.campaign, home.id).frontBusiness, siteOf(saved, home.id).frontBusiness);
    assert.deepEqual(personOf(loaded.campaign, worker.id).activity, personOf(saved, worker.id).activity);
    assert.equal(loaded.campaign.date, initial.date, 'No day or month was advanced.');
    await click(/^Justice(?:\.|$)/); await sourceChoice('persisted prison management', action => action.key === 'u', /Manage prison orders/);
    await sourceChoice('persisted prisoner', action => action.entityType === 'prisoner-person' && action.entityId === `${prisoner.id}`, /Prepared Prisoner/);
    await wait(/Current order: Study Law/); await capture('persisted-prison-order');
    await verifyLoaded(expectedHash); report.checks.push({ layout: size, status: 'passed', noTimeAdvance: true, nativeSaveRoundTrip: true });
    await context.close(); context = null;
  }
  assert.deepEqual(report.pageErrors, []); report.status = 'passed';
} catch (error) {
  report.status = 'failed'; report.error = String(error.stack ?? error);
  if (page) { await capture('failure').catch(() => {}); await snapshot('failure').catch(() => {}); }
  throw error;
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  await context?.close().catch(() => {}); await browser.close(); console.log(`${report.status}: ${resolve(output, 'report.json')}`);
}
