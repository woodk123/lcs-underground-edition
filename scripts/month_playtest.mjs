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
const output = resolve(root, `reports/browser/month-playtest-${stamp}`);
const profile = resolve(root, `.local/browser-profiles/month-playtest-${stamp}`);
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
  scope: '31 consecutive days of actual browser gameplay, varied orders, public operation, monthly rollover, daily exported/reloaded saves and weekly chapter review; isolated player profile.',
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
const monthNames=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
function visibleDate(content) {
 const matches=[...content.matchAll(/\b(\d{1,2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{4})\s*[·]/g)];
 if(!matches.length)return null;
 const m=matches.at(-1);return new Date(Date.UTC(+m[3],monthNames.indexOf(m[2]),+m[1])).toISOString().slice(0,10);
}
async function ready(){const save=page.getByRole('button',{name:'Save & exit',exact:true});return await save.count()===1&&await save.isEnabled();}
async function settleDay(expected){
 const until=Date.now()+30000;let seen=new Set();
 while(Date.now()<until){
  const content=await text();
  if(content.includes('Campaign update')) {
   const heading=page.getByText('Campaign update',{exact:true});
   if(await heading.count())await inside(heading.first(),'Current announcement heading');
   assert.doesNotMatch(content,/Homeless Camp, SEA, Jan \d+, 2023/,'Required announcement must not show stale HQ transcript.');
  }
  if(/Legislative Agenda \d+/.test(content)) {
   const labels=await page.locator('[aria-label]').evaluateAll(nodes=>nodes.map(n=>n.getAttribute('aria-label')));
   assert.ok(!labels.some(label=>/^President: \d+ (Yea|Nay)/.test(label)),'House/Senate numbers must not move under the President label.');
  }
  if(await ready()&&visibleDate(content)===expected)return;
  if(content.includes('Squad & orders')) {
   await capture(`field-${expected}`);await click(/View full map/);await wait(/Explored areas/);await capture(`floor-${expected}`);await click('Back to operation');await click(/^Move up/);continue;
  }
  const continuing=page.getByRole('button',{name:/^Continue$/});
  if(await continuing.count()&&await continuing.first().isEnabled()){
   const signature=content.slice(-1500);
   if(!seen.has(signature)){await capture(`event-${expected}-${seen.size}`);seen.add(signature);}
   await continuing.first().click();await page.waitForTimeout(200);continue;
  }
  const labels=await page.getByRole('button').evaluateAll(nodes=>nodes.map(n=>n.getAttribute('aria-label')||n.innerText));
  await writeFile(resolve(output,'current-prompt.txt'),content+'\nBUTTONS\n'+JSON.stringify(labels));
  await page.waitForTimeout(150);
 }
 throw Error(`Day stalled before ${expected}. ${await text()}`);
}
async function assign(name,activity,group='Business'){
 await selectCrew(name);await click('Orders','left');await click(group,'left');
 const action=await button(new RegExp('^Prepare '+escape(activity)+'(?:$|\\s)'),'any');
 assert.ok(await action.isEnabled(),`${name}: ${activity} must be enabled`);
 await action.click();await click('Confirm order','left');
 if(activity.includes('Practice')){await capture('practice-skill-choice');await click(/Science/);}
 await top('Organisation');
 report.checks.push({name:`assign ${name}: ${activity}`,status:'passed'});
}
async function planPark(){
 await ordersFor('Felix Kobayashi');
 let parks=page.getByRole('button',{name:/Park\. site(?:\.|\s|$)/});
 if(!(await parks.count())){await click(/University.*\. district(?:\.|\s|$)/);parks=page.getByRole('button',{name:/Park\. site(?:\.|\s|$)/});}
 await parks.first().click();await click('Visit with selected squad');await click('Confirm visit');await top('Organisation');await capture('public-operation-queued');
}
try {
 report.mainJsSha256=await servedHash();assert.equal(report.mainJsSha256,expectedHash);
 await launch();await wait(/Start a New Game/);
 const chooser=page.waitForEvent('filechooser');await click('Import a Save');await(await chooser).setFiles(fixture);
 await wait(/Save imported/);await press('Enter');await wait(/Start a New Game/);await click('Load & Manage Saves');await click(/^A(?:\s|$)/);await click(/^L Load Game/);await journal();
 const baseline=await exportSave('day-00-baseline');report.daily=[];report.startDate=baseline.date;await capture('day-00-headquarters');
 await assign('Felix Kobayashi','Solicit Donations');
 await assign('Eugene Kaltenbrunner','Make and Sell Art');
 await assign('Wendell McAllister','Perform Live Music');
 await assign('Nickie Somner','Make and Sell Clothing');
 await assign('Yann Zedner','Solicit Donations');
 let prior=baseline;
 for(let day=1;day<=31;day++){
  if(day===8)await planPark();
  if(day===9){await assign('Felix Kobayashi','Solicit Donations');await assign('Eugene Kaltenbrunner','Perform Live Music');}
  if(day===16)await assign('Wendell McAllister','Community Service','Activism');
  if(day===23)await assign('Nickie Somner','Solicit Donations');
  const expected=new Date(new Date(baseline.date+'Z').getTime()+day*86400000).toISOString().slice(0,10);
  await click(/Carry out (?:your )?plans|Run day|Wait a day/i,'footer');await settleDay(expected);await journal();
  const saved=await exportSave(`day-${String(day).padStart(2,'0')}`);
  assert.equal(saved.date.slice(0,10),expected,'Every day must advance exactly once.');
  for(const person of baseline.lcs.pool.filter(p=>p.alive)){
   const current=saved.lcs.pool.find(p=>p.id===person.id);assert.ok(current,`Lost person ${person.id}`);
   assert.equal(current.daysSinceJoined,person.daysSinceJoined+day,`Roster age for ${person.name}`);
   assert.ok(Number.isFinite(current._blood)&&current._blood>=0,'Valid health bounds');
  }
  assert.ok(Number.isFinite(saved.ledger._funds));
  const expectedFunds=baseline.ledger._funds+(saved.ledger.totalIncome-baseline.ledger.totalIncome)-(saved.ledger.totalExpense-baseline.ledger.totalExpense);
  assert.equal(saved.ledger._funds,expectedFunds,'Every daily balance must reconcile with recorded income/expenses.');
  report.daily.push({day,date:saved.date,funds:saved.ledger._funds,totalIncome:saved.ledger.totalIncome,totalExpense:saved.ledger.totalExpense,news:saved.newsArchive?.length,people:saved.lcs.pool.map(p=>({id:p.id,name:p.name,alive:p.alive,activity:p.activity,income:p.income}))});
  console.log(`DAY ${day} ${expected} funds=${saved.ledger._funds}`);
  if(day%7===0||day===31){
   await capture(`day-${day}-headquarters`);
   for(const section of ['Ledger','Justice','Agenda','Newspaper','Reports']){await top(section);await capture(`day-${day}-${section.toLowerCase()}`);await top('Organisation');}
   if(day===14){await page.reload({waitUntil:'networkidle'});await wait(/Continue (?:your campaign|Last Game|as )/);await click(/Continue (?:your campaign|Last Game|as )/);await journal();assert.equal(visibleDate(await text()),expected);}
  }
  prior=saved;
 }
 assert.equal(prior.date.slice(0,10),'2023-02-04');assert.ok(prior.ledger.totalIncome>baseline.ledger.totalIncome);
 report.endDate=prior.date;report.daysPlayed=31;report.finalFunds=prior.ledger._funds;report.saveReloadCycles=report.exports.length;report.fullBrowserRefreshOnDay=14;report.dailyAccountingReconciles=true;
 assert.equal(report.daily.length,31);assert.deepEqual(report.pageErrors,[]);assert.deepEqual(report.consoleErrors,[]);assert.deepEqual(report.failedRequests,[]);report.status='passed';
} catch(error){
 report.status='failed';report.error=error.stack??String(error);process.exitCode=1;
 if(page){await page.screenshot({path:resolve(output,'FAILURE.png')});await writeFile(resolve(output,'FAILURE.txt'),await text());await writeFile(resolve(output,'FAILURE.html'),await page.locator('flt-semantics-host').innerHTML());}
} finally {
 if(context)await context.close();report.completed=new Date().toISOString();await writeFile(resolve(output,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,output,days:report.daily?.length,error:report.error}));
}
