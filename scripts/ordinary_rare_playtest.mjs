import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..');
const require=createRequire(resolve(root,'upstream/tool/offline_test/package.json'));
const {chromium}=require('playwright');
const output=resolve(root,'reports/longevity-combat-20261015');
const url='http://127.0.0.1:8767/';
const only=process.argv.slice(2);
const previous=only.length?await readFile(resolve(output,'rare-browser-report.json'),'utf8').then(JSON.parse).catch(()=>null):null;
const report={origin:url,started:new Date().toISOString(),browser:'external installed Chrome, visible window, isolated contexts',scenarios:[],errors:[]};
if(previous)report.scenarios=previous.scenarios.filter(s=>!only.includes(s.label)).map(s=>({...s,runtimeSha256:s.runtimeSha256||previous.runtimeSha256}));
const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:false});
let context,page,current;
const text=async()=>await page.locator('body').innerText();
async function wait(re){for(let i=0;i<200;i++){const t=await text();if(re.test(t))return t;await page.waitForTimeout(75);}throw Error('Missing '+re+' '+await text());}
async function click(name){await page.mouse.move(2,2);await page.waitForTimeout(140);await page.getByRole('button',{name,exact:typeof name==='string'}).first().click({timeout:4000});await page.waitForTimeout(90);}
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
async function scenario(label,path,run){if(only.length&&!only.includes(label))return;current={label,path,runtimeSha256:report.runtimeSha256,captures:[],events:[],checks:[]};report.scenarios.push(current);try{await load(path);await run();current.status='passed';}catch(e){current.status='failed';current.error=String(e);if(page)await capture(label+'-failure');}finally{if(context)await context.close();await writeFile(resolve(output,'rare-browser-report.json'),JSON.stringify(report,null,2));console.log(label+': '+current.status+(current.error||''));}}
async function exported(label){
 await click('Save & exit');await wait(/Load & Manage Saves/);await click(/^Load & Manage Saves/);await click(/^A(?:\s|$)/);
 const download=page.waitForEvent('download',{timeout:10000});await click(/^E Export Save File/);const dl=await download;const path=resolve(output,label+'.json');await dl.saveAs(path);
 const raw=JSON.parse(await readFile(path,'utf8'));const game=typeof raw.saveData==='string'?JSON.parse(raw.saveData):raw.saveData;await click(/^L Load Game/);await wait(/Save & exit/);return {path,game};
}
const servedRuntime=await fetch(new URL('main.dart.js',url));assert.ok(servedRuntime.ok);report.runtimeSha256=createHash('sha256').update(Buffer.from(await servedRuntime.arrayBuffer())).digest('hex');report.servingDirectory=(await(await fetch(new URL('__lcs_launcher_health',url))).json()).directory;
async function acknowledge(){
 if(/\(Yes or No\)|Yes or No/.test(await text())){await page.keyboard.press('y');await page.waitForTimeout(80);return;}
 for(const name of [/Continue Liberally/,/^(?:Enter )?Continue.*$/, /^Back to the game$/])if(await enabled(name)){await click(name);return;}
 await page.keyboard.press('Enter');await page.waitForTimeout(65);
}
async function drive({fight=false,tactical=false,limit=1000,terminal}={}){
 let carFought=false;
 for(let i=0;i<limit;i++){
  const t=await text();if(terminal&&terminal.test(t))return;if(await ready())return;current.events.push(t);
  if(tactical&&t.includes('Squad & orders')){
   if(await enabled(/^F Fight/))await click(/^F Fight/);else if(await enabled(/^Move up/))await click(/^Move up/);else await acknowledge();
  } else if(await enabled(/^D.*(?:rive hard|Swerve|Run the light)/)){if(!carFought&&await enabled(/^F Fight/)){await click(/^F Fight/);carFought=true;}else await click(/^D/);}
  else if(await enabled(/^F Fight/))await click(fight?/^F Fight/:/^D Try to lose/);
  else await acknowledge();
  if(i%100===0)console.log(current.label+' frames '+i);
 }throw Error('Prompt limit: '+await text());
}


async function resolveOrdinary(rounds){
 let fought=0;
 for(let i=0;i<180;i++){
  const t=await text();current.events.push(t);if(i%25===0){await capture(current.label+'-progress');console.log(current.label+' '+i+' '+t.slice(-450));}if(await ready()||/Start a New Game/.test(t))return;
  if(await enabled(/^F Fight/)){await capture(current.label+'-decision-'+fought);await click(fought++<rounds?/^F Fight/:/^D Try to lose/);}
  else if(await enabled(/^A Use a court-appointed/))await click(/^A Use a court-appointed/);
  else if(await enabled(/Reflect on your Conservative/))await click(/Reflect on your Conservative/);
  else await acknowledge();
 }
 throw Error('Ordinary encounter did not finish: '+await text());
}
for(const [label,rounds] of [['ordinary-combat',2],['ordinary-retreat',0]])await scenario(label,resolve(output,'saves/ordinary-police-sweep.json'),async()=>{
 await capture(label+'-start');await page.keyboard.press('f');await page.waitForTimeout(150);await resolveOrdinary(rounds);await capture(label+'-finished');
 if(await ready()){const saved=await exported(label+'-outcome');current.outcome={date:saved.game.date,crew:saved.game.lcs.pool.map(p=>({id:p.id,name:p.name,alive:p.alive,blood:p._blood,location:p.locationId})),stats:saved.game.stats};}
 else {assert.match(await text(),/View High Scores/);current.outcome={ended:true};}
 assert.ok(current.events.some(t=>/Police Officer/.test(t)));if(rounds)assert.ok(current.events.some(t=>/shoots at|stabs|swings at/.test(t)));current.checks.push('Ordinary saved attributes/skills, real encounter through retreat, defeat or victory; no stat inflation');
});
for(const type of ['cia','angryRuralMob','corporateMercs','ccs','medicalDebtCollectors'])await scenario('surrender-'+type,resolve(output,'saves/rare-'+type+'.json'),async()=>{
 await capture(type+'-start');await page.keyboard.press('g');await page.waitForTimeout(100);await drive();await capture(type+'-resolved');const {game}=await exported(type+'-outcome');
 const source=JSON.parse(await readFile(current.path,'utf8'));const before=typeof source.saveData==='string'?JSON.parse(source.saveData):source.saveData;const site=game.cities.flatMap(c=>c.districts.flatMap(d=>d.sites)).find(s=>s.id===21);assert.equal(site.siege.activeSiegeType,'none');
 for(const id of [2,3,4])assert.equal(game.lcs.pool.find(p=>p.id===id).alive,true);
 if(type==='medicalDebtCollectors'){assert.ok(game.lcs.pool.every(p=>p.alive));assert.equal(game.ledger._funds,0);assert.ok(game.lcs.pool.slice(0,2).every(p=>p.medicalBills===0));assert.equal(game.ledger.totalExpense-before.ledger.totalExpense,100);}
 else{assert.equal(game.lcs.pool.find(p=>p.id===0).alive,false);assert.equal(game.lcs.pool.find(p=>p.id===1).alive,false);assert.equal(game.stats.martyrs-before.stats.martyrs,2);}
 if(type==='ccs')assert.equal(site.controller,'ccs');current.checks.push('Original '+type+' surrender outcome; outside crew preserved, exact accounting and reload');
});
for(const escalation of ['nationalGuard','tanks','bombers'])await scenario('siege-'+escalation,resolve(output,'saves/police-'+escalation+'.json'),async()=>{
 await capture(escalation+'-start');await click(/Wait out the siege/);await drive();await capture(escalation+'-day');await page.keyboard.press('g');await page.waitForTimeout(120);await drive();await capture(escalation+'-surrender');const {game}=await exported(escalation+'-outcome');const site=game.cities.flatMap(c=>c.districts.flatMap(d=>d.sites)).find(s=>s.id===21);assert.equal(site.siege.activeSiegeType,'none');current.checks.push('Prepared '+escalation+' escalation; real day hazards, then surrender and save/reload');
});
report.completed=new Date().toISOString();await writeFile(resolve(output,'rare-browser-report.json'),JSON.stringify(report,null,2));await browser.close();if(report.scenarios.some(s=>s.status==='failed')||report.errors.length)process.exitCode=1;
