// Journal field and visit review through original source controls.
// This script never stops a server and never uses an existing human profile.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const url = 'http://127.0.0.1:8765/';
const args = process.argv.slice(2);
assert.ok(args.includes('--expected-hash'), 'Provide --expected-hash for the compiled runtime under review.');
const expectedHash = args[args.indexOf('--expected-hash') + 1];
assert.match(expectedHash, /^[a-f0-9]{64}$/, 'Supply the exact approved compiled runtime SHA256.');
const stamp = new Date().toISOString().replaceAll(':', '-').replaceAll('.', '-');
const output = resolve(root, `reports/browser/operations-${stamp}`);
const profile = resolve(root, `.local/browser-profiles/operations-${stamp}`);
const fixture = resolve(root, 'upstream/test/saves/felix_1_0.json');
assert.ok(profile.startsWith(resolve(root, '.local/browser-profiles') + sep));
await mkdir(output, { recursive: true });
await mkdir(profile, { recursive: true });
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const originalFixtureHash = hash(await readFile(fixture));
const sourceGame = contents => typeof contents.saveData === 'string' ? JSON.parse(contents.saveData) : contents.saveData;
const original = sourceGame(JSON.parse(await readFile(fixture, 'utf8')));
const crew = original.lcs.pool.filter(p => p.alive && p.align === 'liberal' && !p.sleeperAgent);
assert.equal(crew.length, 5);
const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const report = {
  status: 'running', started: new Date().toISOString(), url, profile, fixture,
  scope: 'Real isolated Chrome audit of journal style: title/changelog, save management, headquarters, main chapters, dossier, planning, arrival, field operation, equipment and full floor. Includes actual mission return and small-window150% captures; gameplay uses original controls.',
  expectedHash, originalFixtureHash, originalCrew: crew.map(p => ({ id: p.id, name: p.name })),
  checks: [], screenshots: [], exports: [], keyboard: [], findings: [], pageErrors: [], consoleErrors: [], failedRequests: [],
};
let context, page;
let offlinePhase = false;
async function servedHash() {
  const response = await fetch(new URL('main.dart.js', url));
  assert.ok(response.ok);
  return hash(Buffer.from(await response.arrayBuffer()));
}
function attach(target) {
  target.on('pageerror', error => report.pageErrors.push(error.stack ?? error.message));
  target.on('console', message => { if (message.type() === 'error') report.consoleErrors.push(message.text()); });
  target.on('requestfailed', request => report.failedRequests.push({ url: request.url(), failure: request.failure()?.errorText, offlinePhase }));
}
async function launch() {
  context = await chromium.launchPersistentContext(profile, {
    channel: 'chrome', headless: true, viewport: { width: 1280, height: 720 },
  });
  report.browserVersion = context.browser().version();
  page = await context.newPage(); attach(page);
  await page.goto(url, { waitUntil: 'networkidle' });
}
async function text() {
  return page.locator('flt-semantics-host').evaluate(host => [host.innerText,
    ...[...host.querySelectorAll('[aria-label]')].map(n => n.getAttribute('aria-label')),
    ...[...host.querySelectorAll('[aria-valuetext]')].map(n => n.getAttribute('aria-valuetext')),
    ...[...host.querySelectorAll('input,textarea')].map(n => n.value),
  ].filter(Boolean).join('\n'));
}
async function wait(pattern, timeout = 15000) {
  const until = Date.now() + timeout;
  let actual = '';
  while (Date.now() < until) {
    if (await page.locator('flt-semantics-host').count()) {
      actual = await text();
      if (pattern.test(actual)) return actual;
    }
    await page.waitForTimeout(100);
  }
  throw new Error(`Missing visible UI ${pattern}.\n${actual}`);
}
async function button(name, scope = 'any') {
  const pattern = typeof name === 'string' ? new RegExp(`^${escape(name)}(?:$|\\s)`) : name;
  const until = Date.now() + 3500;
  while (Date.now() < until) {
    for (const item of await page.getByRole('button', { name: pattern }).all()) {
      const bounds = await item.boundingBox();
      if (!bounds) continue;
      const size = page.viewportSize(), middle = bounds.x + bounds.width / 2;
      if (scope === 'top' && bounds.y > 110) continue;
      if (scope === 'left' && (middle > size.width * .53 || bounds.y < 110)) continue;
      if (scope === 'right' && (middle < size.width * .46 || bounds.y < 110)) continue;
      if (scope === 'footer' && bounds.y < size.height - 110) continue;
      return item;
    }
    await page.waitForTimeout(65);
  }
  throw new Error(`No accessible ${scope} button ${name}.`);
}
async function click(name, scope = 'any') {
  const item = await button(name, scope);
  await item.scrollIntoViewIfNeeded(); await item.click(); await page.waitForTimeout(200);
}
async function top(name) { await click(name, 'top'); }
async function press(key) { await page.keyboard.press(key); await page.waitForTimeout(180); }
async function inside(item, label) {
  const bounds = await item.boundingBox(), size = page.viewportSize();
  assert.ok(bounds && bounds.x >= -1 && bounds.y >= -1 && bounds.x + bounds.width <= size.width + 1 && bounds.y + bounds.height <= size.height + 1,
    `${label} must fit ${size.width}x${size.height}: ${JSON.stringify(bounds)}`);
  return bounds;
}
async function journal() {
  const save = await button('Save & exit', 'footer');
  const until = Date.now() + 12000;
  while (!(await save.isEnabled()) && Date.now() < until) await page.waitForTimeout(100);
  assert.ok(await save.isEnabled(), 'Normal journal must be ready for source input.');
  for (const name of ['Organisation', 'Ledger', 'Justice', 'Agenda', 'Newspaper', 'Reports', 'City maps', 'Options']) {
    await inside(await button(name, 'top'), `${name} tab`);
  }
  assert.equal(await page.getByRole('dialog').count(), 0);
  assert.doesNotMatch(await text(), /AVAILABLE CHOICES/);
}
async function exportSave(label) {
  await click('Save & exit', 'footer'); await wait(/Continue (?:your campaign|Last Game|as )/);
  await click('Load & Manage Saves'); await click(/^A(?:\s|$)/); await wait(/Manage .*Saved Game/);
  const downloading = page.waitForEvent('download'); await click(/Export Save File/);
  const path = resolve(output, `${label}.json`); await (await downloading).saveAs(path);
  const bytes = await readFile(path), actual = sourceGame(JSON.parse(bytes.toString('utf8')));
  assert.ok(actual.lcs && actual.date && actual.ledger);
  report.exports.push({ file: `${label}.json`, bytes: bytes.length, sha256: hash(bytes) });
  await click(/^L Load Game/); await journal();
  return actual;
}
async function selectCrew(name) {
  await click(`Select crew ${name}`, 'left'); await inside(await button(`Inspect ${name}`, 'left'), 'Selected crew portrait');
}
async function ordersFor(name) {
  await selectCrew(name); await click('Orders', 'left'); await click('Business', 'left');
  await button(/Prepare Solicit Donations(?:$|\s)/, 'right');
}
async function prepareDonations({ requireTiming = true } = {}) {
  await click(/Prepare Solicit Donations(?:$|\s)/, 'right');
  await inside(await button('Confirm order', 'left'), 'Inline order confirmation');
  const content = await text();
  assert.match(content, /Persuasion|Street Smarts|Charisma|Heart/);
  const timingExplained = /advance the day|next day|daily/i.test(content);
  if (requireTiming) assert.ok(timingExplained, 'The job card must expose execution timing.');
  return timingExplained;
}
async function cancelPrepared() { await click('Cancel prepared order', 'left'); }

async function capture(name) {
 await page.mouse.move(2,2);await page.waitForTimeout(200);
 await page.screenshot({path:resolve(output,name+'.png')});
 await writeFile(resolve(output,name+'.txt'),await text());
 assert.doesNotMatch(await text(),/AVAILABLE CHOICES/);
 report.screenshots.push(name+'.png');report.checks.push({name,status:'passed'});console.log('PASS '+name);
}
try {
 report.mainJsSha256=await servedHash();assert.equal(report.mainJsSha256,expectedHash);
 await launch();await wait(/Start a New Game/);await capture('01-title');
 await click(/^View Changelog/);await wait(/Campaign changelog/);await capture('02-changelog');
 await click(/^Close changelog/);
 const chooser=page.waitForEvent('filechooser');await click('Import a Save');await(await chooser).setFiles(fixture);
 await wait(/Save imported/);await press('Enter');await wait(/Start a New Game/);
 await click('Load & Manage Saves');await capture('03-save-management');
 await click(/^A(?:\s|$)/);await click(/^L Load Game/);await journal();await capture('04-headquarters');
 await click('Inspect Felix Kobayashi','left');await capture('05-inline-dossier');await click('Full dossier');await capture('06-full-dossier');await press('Escape');await press('Escape');
 for(const section of ['Ledger','Agenda','Newspaper','Reports','Options']) {
  await top(section);await capture('chapter-'+section.toLowerCase());await top('Organisation');
 }
 const beforeInspection = await exportSave('visit-inspection-baseline');
 await ordersFor('Felix Kobayashi');
 let parks=page.getByRole('button',{name:/Park\. site(?:\.|\s|$)/});
 if(!(await parks.count())){await click(/University.*\. district(?:\.|\s|$)/);parks=page.getByRole('button',{name:/Park\. site(?:\.|\s|$)/});}
 assert.ok(await parks.count());await parks.first().click();await page.waitForTimeout(200);await capture('07-city-plan');
 await click(/^Reading size/);await page.getByRole('menuitem',{name:'150%',exact:true}).click();await page.setViewportSize({width:800,height:600});await page.waitForTimeout(300);
 await inside(await button('Visit with selected squad'), 'Selected-building visit action');await capture('07a-visit-800-150');
 await click(/^Reading size/);await page.getByRole('menuitem',{name:'100%',exact:true}).click();await page.setViewportSize({width:1280,height:720});await page.waitForTimeout(200);
 await click('Visit with selected squad');await capture('07b-prepared-visit');
 await click('Cancel prepared visit');await journal();await capture('07c-cancelled-visit');
 const afterCancellation = await exportSave('visit-inspection-cancelled');
 assert.deepEqual(afterCancellation,beforeInspection,'Inspecting and cancelling a prepared visit must preserve all parsed campaign data.');
 report.checks.push({name:'full-campaign-inspection-and-cancel-unchanged',status:'passed'});
 await ordersFor('Felix Kobayashi');
 parks=page.getByRole('button',{name:/Park\. site(?:\.|\s|$)/});
 if(!(await parks.count())){await click(/University.*\. district(?:\.|\s|$)/);parks=page.getByRole('button',{name:/Park\. site(?:\.|\s|$)/});}
 await parks.first().click();await click('Visit with selected squad');await click('Confirm visit');
 assert.match(await text(), /Visit queued|Queued visit|advance the day|next day/i);await capture('07d-queued-visit');await top('Organisation');await click(/Carry out (?:your )?plans|Run day|Wait a day/i,'footer');
 for(let step=0;step<30;step++) {
  if(/has arrived at/.test(await text()))break;
  await press('Enter');
 }
 await wait(/has arrived at/);await capture('08-arrival');await click(/^Continue$/);await wait(/Squad & orders/);await capture('09-field-operation');
 await click(/View full map/);await wait(/Explored areas/);await capture('10-full-floor');
 await click('Back to operation');await wait(/Squad & orders/);
 await click(/Equip squad/);await capture('11-field-equipment');await press('Escape');await wait(/Squad & orders/);
 await click(/^Reading size/);await page.getByRole('menuitem',{name:'150%',exact:true}).click();await page.waitForTimeout(180);
 await page.setViewportSize({width:800,height:600});await page.waitForTimeout(300);await capture('12-field-800-150');
 await inside(await button(/^Move up/),'Pinned field movement');
 await click(/View full map/);await wait(/Explored areas/);await capture('13-floor-800-150');
 await click('Back to operation');await wait(/Squad & orders/);
 await click(/^Reading size/);await page.getByRole('menuitem',{name:'100%',exact:true}).click();await page.setViewportSize({width:1280,height:720});await page.waitForTimeout(200);
 await click(/^Move up/);
 for(let step=0;step<30;step++) {
  if(!(await text()).includes('Squad & orders')&&await page.getByRole('button',{name:'Save & exit',exact:true}).count())break;
  await press('Enter');
 }
 await journal();await capture('14-returned-to-headquarters');
 assert.deepEqual(report.pageErrors,[]);assert.deepEqual(report.consoleErrors,[]);assert.deepEqual(report.failedRequests,[]);report.status='passed';
} catch(error) {
 report.status='failed';report.error=error.stack??String(error);process.exitCode=1;
 if(page){await page.screenshot({path:resolve(output,'FAILURE.png')});await writeFile(resolve(output,'FAILURE.txt'),await text());await writeFile(resolve(output,'FAILURE.html'),await page.locator('flt-semantics-host').innerHTML());}
} finally {
 if(context)await context.close();report.completed=new Date().toISOString();await writeFile(resolve(output,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,output,checks:report.checks.length,error:report.error}));
}
