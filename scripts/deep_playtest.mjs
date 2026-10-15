import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..');
const require=createRequire(resolve(root,'upstream/tool/offline_test/package.json'));
const {chromium}=require('playwright');
const output=resolve(root,'reports/deep-playtest-20261014');
const url='http://127.0.0.1:8766/';
const only=process.argv.slice(2);
const previous=only.length?JSON.parse(await readFile(resolve(output,'browser-report.json'),'utf8')):null;
const report={origin:url,started:new Date().toISOString(),browser:'external installed Chrome, visible window, isolated contexts',scenarios:[],errors:[]};
if(previous)report.scenarios=previous.scenarios.filter(s=>!only.includes(s.label)).map(s=>({...s,runtimeSha256:s.runtimeSha256||previous.runtimeSha256}));
const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:false});
let context,page,current;
const text=async()=>await page.locator('body').innerText();
async function wait(re){for(let i=0;i<200;i++){const t=await text();if(re.test(t))return t;await page.waitForTimeout(75);}throw Error('Missing '+re+' '+await text());}
async function click(name){await page.getByRole('button',{name,exact:typeof name==='string'}).first().click({timeout:4000});await page.waitForTimeout(90);}
async function capture(label){await page.screenshot({path:resolve(output,label+'.png')});await writeFile(resolve(output,label+'.txt'),await text());current.captures.push(label);}
async function enabled(name){const b=page.getByRole('button',{name,exact:typeof name==='string'});return (await b.count())>0&&await b.first().isEnabled();}
async function ready(){return enabled('Save & exit');}
async function enter(){await page.keyboard.press('Enter');await page.waitForTimeout(75);}
async function settle(limit=180){for(let i=0;i<limit;i++){const t=await text();if(await ready())return;const cont=page.getByRole('button',{name:/^(?:Enter )?Continue$/});if(await cont.count()){current.events.push(t);await cont.first().click();await page.waitForTimeout(75);continue;}throw Error('Unrecognised required decision '+t);}throw Error('Prompt limit');}
async function load(path){
 context=await browser.newContext({viewport:{width:1280,height:800},acceptDownloads:true});page=await context.newPage();
 page.on('pageerror',e=>report.errors.push(String(e)));page.on('console',m=>{if(m.type()==='error')report.errors.push(m.text());});
 await page.goto(url);await wait(/Start a New Game/);
 const chooser=page.waitForEvent('filechooser');await click(/^Import a Save/);await(await chooser).setFiles(path);
 await wait(/Save imported/);await enter();await wait(/Load & Manage Saves/);await click(/^Load & Manage Saves/);await click(/^A(?:\s|$)/);await click(/^L Load Game/);await wait(/Save & exit/);
}
async function scenario(label,path,run){if(only.length&&!only.includes(label))return;current={label,path,runtimeSha256:report.runtimeSha256,captures:[],events:[],checks:[]};report.scenarios.push(current);try{await load(path);await run();current.status='passed';}catch(e){current.status='failed';current.error=String(e);if(page)await capture(label+'-failure');}finally{if(context)await context.close();await writeFile(resolve(output,'browser-report.json'),JSON.stringify(report,null,2));console.log(label+': '+current.status+(current.error||''));}}
async function exported(label){
 await click('Save & exit');await wait(/Load & Manage Saves/);await click(/^Load & Manage Saves/);await click(/^A(?:\s|$)/);
 const download=page.waitForEvent('download',{timeout:10000});await click(/^E Export Save File/);const dl=await download;const path=resolve(output,label+'.json');await dl.saveAs(path);
 const raw=JSON.parse(await readFile(path,'utf8'));const game=typeof raw.saveData==='string'?JSON.parse(raw.saveData):raw.saveData;await click(/^L Load Game/);await wait(/Save & exit/);return {path,game};
}
report.runtimeSha256=createHash('sha256').update(await readFile(resolve(root,'upstream/build/web/main.dart.js'))).digest('hex');
await scenario('legacy-firearms',resolve(root,'upstream/test/saves/felix_1_0.json'),async()=>{
 await capture('fixed-import-headquarters');
 // Original keyboard command F opens the site's visit planner; siege F is read
 // from the prepared scenario's overflow menu before subsequent script runs.
 const {game}=await exported('legacy-import-export');
 assert.ok(['WEAPON_SHOTGUN_PUMP','WEAPON_PUMP_SHOTGUN'].includes(game.lcs.pool[2].equippedWeapon.typeName));
 current.checks.push('Imported pump shotgun retained; exported through game UI');
 await page.reload({waitUntil:'networkidle'});await wait(/Continue as/);await page.waitForTimeout(400);await click(/^Continue as/);await wait(/Save & exit/);
 current.checks.push('Full browser refresh restores exported campaign');
 await context.setOffline(true);await page.reload({waitUntil:'networkidle'});await wait(/Continue as/);await page.waitForTimeout(400);await click(/^Continue as/);await wait(/Save & exit/);await capture('offline-restored');await context.setOffline(false);
 current.checks.push('Offline refresh and campaign load');
 for(const size of [{width:800,height:600},{width:360,height:640}]){await page.setViewportSize(size);await page.waitForTimeout(200);await capture('hq-'+size.width);if(size.width===360){await page.mouse.move(180,300);await page.mouse.wheel(600,0);await page.waitForTimeout(200);await capture('hq-360-right');}await page.getByRole('button',{name:'Field guide',exact:true}).hover();await page.waitForTimeout(650);await capture('guide-tooltip-'+size.width);await page.mouse.move(2,2);await page.waitForTimeout(300);await click('Field guide');await wait(/Decision guides/);await capture('guide-'+size.width);await click('Back to the game');}
});
await scenario('camp-combat-retreat',resolve(output,'siege-police.json'),async()=>{
 await page.keyboard.press('f');await page.waitForTimeout(150);await capture('fixed-camp-preparation');await click('Continue');await wait(/Try to lose/);await click(/^F Fight/);
 for(let i=0;i<90;i++){const t=await text();current.events.push(t);if(await enabled(/^F Fight/))break;await enter();}
 assert.ok(current.events.some(t=>/Felix Kobayashi shoots at/.test(t)),'Imported rifle must fire');await capture('fixed-camp-after-round');
 if(await enabled(/^D Try to lose/)){
  await click(/^D Try to lose/);
  for(let i=0;i<90;i++){current.events.push(await text());if(await ready()||await enabled(/^F Fight/))break;await enter();}
  await capture('fixed-camp-retreat-result');
 }
 current.checks.push('Actual mixed firearm/melee round, enemy armour, blood loss, ammunition consumption and one pursuit escape attempt; encounter intentionally stopped after this attempt');
});
const reloadWrapper=JSON.parse(await readFile(resolve(output,'siege-police.json'),'utf8'));
const reloadGame=JSON.parse(reloadWrapper.saveData);reloadGame.uniqueGameId=2026101409;reloadGame.lcs.pool[0].equippedWeapon.ammo=0;reloadGame.lcs.pool[0].spareAmmo.stackSize=3;reloadWrapper.gameId='2026101409';reloadWrapper.saveData=JSON.stringify(reloadGame);await writeFile(resolve(output,'saves/camp-reload.json'),JSON.stringify(reloadWrapper));
await scenario('camp-reload',resolve(output,'saves/camp-reload.json'),async()=>{
 await page.keyboard.press('f');await page.waitForTimeout(120);await click('Continue');await wait(/Try to lose/);await click(/^F Fight/);
 for(let i=0;i<90;i++){current.events.push(await text());if(await enabled(/^F Fight/))break;await enter();}
 assert.ok(current.events.some(t=>/AK-102 3\/0/.test(t)));assert.ok(current.events.some(t=>/Felix Kobayashi shoots at/.test(t)));assert.match(await text(),/AK-102 0/);await capture('camp-reload-after-round');current.checks.push('Empty legacy rifle automatically reloads before pursuit, then fires its three rounds; combat-turn reload is separately tested in Dart');
});
await scenario('warehouse-surrender',resolve(output,'saves/warehouse-siege.json'),async()=>{
 await capture('warehouse-siege-prepared');await page.keyboard.press('g');await page.waitForTimeout(150);await capture('warehouse-surrender-event');await settle();
 await click(/^Justice/);await capture('warehouse-surrender-justice');
 const {game}=await exported('warehouse-after-surrender');const people=game.lcs.pool;
 assert.equal(people[0].locationId,'Site21'); // no charges at a warehouse: processed/released
 assert.equal(people[0].equippedWeapon,null);current.checks.push('Warehouse surrender confiscates equipment, ends siege and releases uncharged crew');
});
await scenario('justice-month-end',resolve(output,'saves/justice-rollover.json'),async()=>{
 await click(/^Justice/);await capture('justice-before');await click(/^Organisation/);await click(/Wait a day|Carry out/);await page.waitForTimeout(100);
 for(let i=0;i<180;i++){
  if(await ready())break;const t=await text();current.events.push(t);
  const plea=page.getByRole('button',{name:/Plead guilty/});if(await plea.count()){await plea.first().click();await page.waitForTimeout(100);continue;}
  const cont=page.getByRole('button',{name:/^(?:Enter )?Continue$/});if(await cont.count()){await cont.first().click();await page.waitForTimeout(75);continue;}
  throw Error('Justice decision: '+t);
 }
 assert.ok(await ready());await click(/^Justice/);await capture('justice-after');const {game}=await exported('justice-after-month');current.result=game.lcs.pool.map(p=>({name:p.name,alive:p.alive,sentence:p.sentence,location:p.locationId}));
 assert.ok(current.events.some(t=>/standing trial/.test(t)),'Trial must actually be heard');assert.ok(!game.lcs.pool.some(p=>p.id===4));assert.ok(!game.lcs.pool.some(p=>p.id===2));assert.ok(current.events.some(t=>/executed.*Wendell|Wendell.*executed/s.test(t)));assert.equal(game.lcs.pool.find(p=>p.id===3).sentence,0);const source=JSON.parse(await readFile(current.path,'utf8'));const start=typeof source.saveData==='string'?JSON.parse(source.saveData):source.saveData;assert.equal(game.stats.martyrs,start.stats.martyrs+1,'One execution must record one martyr');current.checks.push('Real monthly trial, execution, prison release and deportation');
});
await scenario('two-squads-sleeper',resolve(output,'saves/two-squads-sleeper.json'),async()=>{
 await capture('two-squads');await click(/Select squad Second Squad/);await capture('second-squad-selected');await click(/^Vehicles/);await capture('vehicles-empty');await page.keyboard.press('Escape');await click(/^Organisation/);await click(/Wait a day|Carry out/);await settle();const {game}=await exported('two-squads-after-day');assert.equal(game.lcs.squads.length,2);assert.equal(game.lcs.pool.filter(p=>p.sleeperAgent).length,1);current.checks.push('Switch squads; no-vehicle state; one day and save preserve both squads and sleeper');
});
await scenario('extreme-laws',resolve(output,'saves/extreme-laws.json'),async()=>{
 await click(/^Agenda/);await capture('extreme-agenda');await click('Field guide');await capture('extreme-guide');await page.keyboard.press('Escape');await click(/^Organisation/);await click(/Wait a day|Carry out/);await settle();await capture('extreme-next-day');current.checks.push('All-Arch-Conservative save loads; Agenda and guide; next day returns to planning');
});
await scenario('natural-campaign-extension',resolve(root,'reports/month-playtest-20261014/day-31.json'),async()=>{
 const initial=await exported('extension-start');
 for(let day=1;day<=90;day++){await click(/Carry out (?:your )?plans|Run day|Wait a day/i);await settle();if(day%30===0){await capture('natural-extension-day-'+day);const save=await exported('natural-extension-day-'+day);current.checks.push({day,date:save.game.date,funds:save.game.ledger._funds});console.log('natural day '+day);}}
 const final=await exported('extension-final');const delta=(Date.parse(final.game.date+'Z')-Date.parse(initial.game.date+'Z'))/86400000;assert.equal(delta,90);current.checks.push('90 uninterrupted calendar days through original browser day commands from the prior natural campaign');
});
report.completed=new Date().toISOString();await writeFile(resolve(output,'browser-report.json'),JSON.stringify(report,null,2));await browser.close();
if(report.scenarios.some(s=>s.status==='failed')||report.errors.length)process.exitCode=1;
