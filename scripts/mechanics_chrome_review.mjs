// Source-derived mechanics review. Real hover, order browsing and save exports only.
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
const output = resolve(root, `reports/browser/skill-hover-${stamp}`);
const profile = resolve(root, `.local/browser-profiles/chrome-final-${stamp}`);
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
  scope: 'Targeted isolated Chrome review of source-derived skill hover descriptions and visible activity formulas. Imports the unchanged five-person campaign, exercises real pointer hover and compares full campaign exports before and after browsing. This report does not extend the prior packaged-release acceptance to this runtime.',
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
try {
 report.mainJsSha256=await servedHash();assert.equal(report.mainJsSha256,expectedHash);
 await launch();await wait(/Start a New Game/);
 const chooser=page.waitForEvent('filechooser');await click('Import a Save');await(await chooser).setFiles(fixture);
 await wait(/Save imported/);await press('Enter');await wait(/Start a New Game/);
 await click('Load & Manage Saves');await click(/^A(?:\s|$)/);await wait(/Manage .*Saved Game/);await click(/^L Load Game/);await journal();
 const baseline=await exportSave('01-before-hover');
 await click('Toggle crew and skills');
 await page.waitForTimeout(250);
 await writeFile(resolve(output,'skill-semantics.html'),await page.locator('flt-semantics-host').innerHTML());
 const skill=page.getByText(/^Effectively use guns in combat/).first();
 await skill.waitFor();const bounds=await skill.boundingBox();assert.ok(bounds);
 await page.mouse.move(bounds.x+bounds.width/2,bounds.y+bounds.height/2);await page.waitForTimeout(650);
 const help=page.getByText(/Useful for: attacking with guns that require Firearms/);
 assert.ok(await help.count(),'Real hover tooltip must expose Firearms use.');
 assert.match(await text(), /Physical attack baseline: d20/);
 await page.screenshot({path:resolve(output,'01-journal-firearms-hover.png')});
 await writeFile(resolve(output,'01-journal-firearms-hover.txt'),await text());
 report.screenshots.push('01-journal-firearms-hover.png');
 report.checks.push({name:'journal-skill-hover',status:'passed'});
 await page.mouse.move(2,2);await page.waitForTimeout(300);
 await click('Toggle crew and skills');await click('Inspect Felix Kobayashi','left');
 await click('Full dossier');await click('Skills');
 await page.waitForTimeout(250);
 await writeFile(resolve(output,'dossier-skill-semantics.html'),await page.locator('flt-semantics-host').innerHTML());
 const fullSkill=page.getByRole('progressbar',{name:/Useful for: attacking with guns that require Firearms/}).first();await fullSkill.waitFor();const db=await fullSkill.boundingBox();await page.mouse.move(db.x+db.width/2,db.y+db.height/2);await page.waitForTimeout(650);
 assert.ok(await page.getByText(/Useful for: attacking with guns that require Firearms/).count());
 await page.screenshot({path:resolve(output,'02-dossier-firearms-hover.png')});
 report.screenshots.push('02-dossier-firearms-hover.png');
 report.checks.push({name:'dossier-skill-hover',status:'passed'});
 await press('Escape');await press('Escape');
 await ordersFor('Felix Kobayashi');await prepareDonations();
 assert.match(await text(), /Calculation: Daily income/);
 assert.match(await text(), /\$2\/day estimated \(2d6 = 7\)/);
 await page.mouse.move(2,2);await page.waitForTimeout(250);
 await page.screenshot({path:resolve(output,'03-activity-calculation.png')});
 await writeFile(resolve(output,'03-activity-calculation.txt'),await text());
 report.screenshots.push('03-activity-calculation.png');
 report.checks.push({name:'activity-formula-and-current-income-visible',status:'passed'});
 const calc=page.getByText(/^Daily income = round/).first();const cb=await calc.boundingBox();assert.ok(cb);
 await page.mouse.move(cb.x+cb.width/2,cb.y+cb.height/2);await page.waitForTimeout(650);
 await page.screenshot({path:resolve(output,'04-activity-formula-hover.png')});
 report.screenshots.push('04-activity-formula-hover.png');
 assert.ok(await page.getByText(/^Daily income = round/).count()>1,'Hover must add a rendered calculation tooltip.');
 report.checks.push({name:'activity-formula-hover',status:'passed'});
 await page.mouse.move(2,2);await page.waitForTimeout(250);
 await cancelPrepared();await top('Organisation');
 await top('Options');await click('150%');await top('Organisation');
 for(const [width,height] of [[1280,720],[800,600]]) {
  await page.setViewportSize({width,height});await page.waitForTimeout(300);await journal();
  await click('Toggle crew and skills');await page.waitForTimeout(180);
  const expanded=page.getByText(/^Effectively use guns in combat/).first();await expanded.waitFor();const eb=await expanded.boundingBox();assert.ok(eb);
  await page.mouse.move(eb.x+eb.width/2,eb.y+eb.height/2);await page.waitForTimeout(650);
  const tooltip=page.getByText(/Useful for: attacking with guns that require Firearms/).last();await inside(tooltip,'150% skill tooltip');
  const image=`05-skill-hover-150-${width}x${height}.png`;await page.screenshot({path:resolve(output,image)});report.screenshots.push(image);
  report.checks.push({name:`skill-hover-150-${width}x${height}`,status:'passed'});
  await page.mouse.move(2,2);await page.waitForTimeout(250);await click('Toggle crew and skills');
  await ordersFor('Felix Kobayashi');await prepareDonations();
  await inside(await button('Confirm order','left'),'150% confirm');await inside(await button('Cancel prepared order','left'),'150% cancellation');
  const filename=`06-activity-result-150-${width}x${height}.png`;await page.mouse.move(2,2);await page.waitForTimeout(250);await page.screenshot({path:resolve(output,filename)});report.screenshots.push(filename);
  report.checks.push({name:`activity-result-150-${width}x${height}`,status:'passed'});
  const currentCalc=page.getByText(/^Daily income = round/).first();const pb=await currentCalc.boundingBox();assert.ok(pb);
  await page.mouse.move(pb.x+pb.width/2,pb.y+pb.height/2);await page.waitForTimeout(650);
  const calculationTooltip=page.getByText(/^Daily income = round/).last();
  await writeFile(resolve(output,`activity-tooltip-semantics-${width}.html`),await page.locator('flt-semantics-host').innerHTML());
  await inside(calculationTooltip.locator('..'),'150% calculation tooltip');
  const detailImage=`07-activity-formula-150-${width}x${height}.png`;await page.screenshot({path:resolve(output,detailImage)});report.screenshots.push(detailImage);
  report.checks.push({name:`activity-formula-150-${width}x${height}`,status:'passed'});
  await page.mouse.move(2,2);await page.waitForTimeout(250);
  await cancelPrepared();await top('Organisation');
 }
 await page.setViewportSize({width:1280,height:720});await top('Options');await click('100%');await top('Organisation');
 const after=await exportSave('02-after-hover');assert.deepEqual(after,baseline);
 report.campaignDataUnchanged=true;
 report.campaignDataSha256=hash(Buffer.from(JSON.stringify(after)));
 report.exportEnvelopeNote='Export timestamps differ; the complete parsed campaign data is deeply equal.';
 report.checks.push({name:'hover-does-not-change-campaign',status:'passed'});
 assert.deepEqual(report.pageErrors,[]);assert.deepEqual(report.consoleErrors,[]);report.status='passed';
} catch(error) {report.status='failed';report.error=error.stack??String(error);if(page)await page.screenshot({path:resolve(output,'FAILURE.png')});process.exitCode=1;}
finally {if(context)await context.close();report.completed=new Date().toISOString();await writeFile(resolve(output,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,output,checks:report.checks,error:report.error}));}
