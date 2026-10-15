import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..');
const require=createRequire(resolve(root,'upstream/tool/offline_test/package.json'));
const {chromium}=require('playwright');
const output=resolve(root,'reports/campaign-systems-20261015');
const url='http://127.0.0.1:8766/';
const only=process.argv.slice(2);
const previous=only.length?await readFile(resolve(output,'browser-report.json'),'utf8').then(JSON.parse).catch(()=>null):null;
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
async function scenario(label,path,run){if(only.length&&!only.includes(label))return;current={label,path,runtimeSha256:report.runtimeSha256,captures:[],events:[],checks:[]};report.scenarios.push(current);try{await load(path);await run();current.status='passed';}catch(e){current.status='failed';current.error=String(e);if(page)await capture(label+'-failure');}finally{if(context)await context.close();await writeFile(resolve(output,'browser-report.json'),JSON.stringify(report,null,2));console.log(label+': '+current.status+(current.error||''));}}
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
for(const [label,fight] of [['warehouse-defence',true],['warehouse-breakout',false]])await scenario(label,resolve(output,'saves/'+label+'.json'),async()=>{
 await page.keyboard.press('f');await page.waitForTimeout(120);await capture(label+'-preparation');await drive({fight});await capture(label+'-completed');const {game}=await exported(label+'-outcome');const s=game.cities.flatMap(c=>c.districts.flatMap(d=>d.sites)).find(s=>s.id===21);assert.equal(s.siege.activeSiegeType,'none');assert.ok(game.lcs.pool.every(p=>p.alive));if(fight){assert.equal(s.siege.escalationState,'nationalGuard');assert.ok(s.heat>=1000);}else assert.ok(game.lcs.pool.every(p=>p.baseId===20));current.checks.push('Completed '+(fight?'defence with escalation':'pursuit escape and relocation')+'; exported and reloaded');
});
await scenario('vehicle-evacuation',resolve(output,'saves/warehouse-vehicle-evacuation.json'),async()=>{
 await page.keyboard.press('f');await page.waitForTimeout(120);await capture('evacuation-preparation');await drive({tactical:true});await capture('evacuation-completed');const {game}=await exported('evacuation-outcome');assert.ok(current.events.some(t=>/rive hard to escape|Bail out and run/.test(t)));assert.ok(game.lcs.pool.some(p=>p.alive));assert.equal(game.lcs.vehiclePool.length,2,'Escaped cars must survive cleanup');assert.ok(current.events.some(t=>/You open fire/.test(t)),'Actual vehicle gunfire');current.checks.push('Prepared open-floor tactical evacuation, vehicle pursuit and completed escape');
});
await scenario('large-organisation',resolve(output,'saves/large-organisation.json'),async()=>{
 await capture('three-squads');await click(/Select squad Second Team/);await capture('second-team');await click(/Select squad Third Team/);await capture('third-team');await click(/^Vehicles/);await capture('shared-vehicle');await page.keyboard.press('Escape');await click(/^Organisation/);await click(/Wait a day|Carry out/);
 for(let i=0;i<700;i++){
  if(await ready())break;const t=await text();current.events.push(t);
  if(/Squad & orders/.test(t)&&await enabled(/^Move up/)){await click(/^Move up/);continue;}
  const join=/^C.*(?:recruit|join|Ask)/i;if(await enabled(join)){await click(join);continue;}
  if(await enabled(/^A.*regular member/)){await click(/^A.*regular member/);continue;}
  await acknowledge();
 }assert.ok(await ready());await capture('large-after-day');await click(/Wait a day|Carry out/);await drive();await capture('large-after-month');const {game}=await exported('large-outcome');assert.ok(game.lcs.squads.length>=3);assert.ok(game.lcs.pool.length>=15,'Ready candidate joins');assert.equal(game.date.slice(0,10),'2023-02-01');assert.ok(game.ledger.totalIncome>0,'Sleeper embezzlement produces recorded income');assert.equal(game.lcs.pool.filter(p=>p.sleeperAgent).length,2);assert.ok(current.events.some(t=>/couldn't use/.test(t)));current.checks.push('Three squads, fourteen crew, two sleepers, vehicle conflicts and daily save');
});
await scenario('presidential-election',resolve(output,'saves/presidential-election.json'),async()=>{
 await click(/Wait a day|Carry out/);await drive();assert.ok(current.events.some(t=>/Presidential General Election|Presidential Election/.test(t)));await capture('election-completed');const {game}=await exported('election-outcome');assert.equal(game.date.slice(0,10),'2024-11-01');current.checks.push('Presidential, congressional and ballot processing; post-election save');
});
await scenario('victory',resolve(output,'saves/victory.json'),async()=>{
 await click(/Wait a day|Carry out/);
 for(let i=0;i<180;i++){
  const t=await text();current.events.push(t);if(/Start a New Game/.test(t))break;
  if(/The Triumph of the Liberal Agenda|View the high score list/.test(t))await capture('victory-agenda');
  if(await enabled(/^(?:L )?View the high score list/)){await click(/^(?:L )?View the high score list/);continue;}
  if(await enabled(/^(?:Space |Enter )?(?:Back|Return)/)){await click(/^(?:Space |Enter )?(?:Back|Return)/);continue;}
  await acknowledge();
 }assert.ok(current.events.some(t=>/The Triumph of the Liberal Agenda|View the high score list/.test(t)));await wait(/Start a New Game/);await capture('victory-title');assert.equal(await enabled(/^Continue/),false);await click(/^View High Scores/);await capture('victory-high-scores');current.checks.push('Prepared victory, final agenda, persisted score and return to title');
});
for(const [target,expected] of [['Fire Station',/^\d+ Fireman\b/m],['Prison',/^\d+ (?:Re-)?Educator\b/m],['Drug House',/^\d+ Mutant\b/im],['Corporate HQ',/^\d+ (?:Corporate|Mercenary|Security Guard|CEO|Office Worker|Secretary)/m]])await scenario('regime-'+target,resolve(output,'saves/regime-'+target+'.json'),async()=>{
 await click(/Wait a day|Carry out/);await drive({terminal:/Squad & orders/});await capture('regime-'+target+'-operation');
 const visits=new Map();const attempts=new Map();let seen=false;let moves=0;
 for(let i=0;i<1200;i++){
  const t=await text();current.events.push(t);
  if(expected.test(t)){seen=true;await capture('regime-'+target+'-encounter');break;}
  if(/Squad & orders/.test(t)&&await enabled(/^F Fight/)){await click(/^F Fight/);continue;}
  if(/Squad & orders/.test(t)&&await enabled(/^Move down/)){
   const cells=[...t.matchAll(/^(.+), column (\d+), row (\d+)$/gm)].map(m=>({kind:m[1],x:+m[2],y:+m[3]}));const here=cells.find(c=>c.kind==='Squad');
   let direction='down';
   if(here){visits.set(here.x+','+here.y,(visits.get(here.x+','+here.y)||0)+1);const options=[['down',0,1],['right',1,0],['left',-1,0],['up',0,-1]].map(([d,dx,dy])=>({d,c:cells.find(c=>c.x===here.x+dx&&c.y===here.y+dy)})).filter(o=>o.c&&!/Wall|Unknown|Exit/.test(o.c.kind));const cost=o=>(visits.get(o.c.x+','+o.c.y)||0)+(attempts.get(o.c.x+','+o.c.y)||0)*.4;options.sort((a,b)=>cost(a)-cost(b));if(options.length){direction=options[0].d;const key=options[0].c.x+','+options[0].c.y;attempts.set(key,(attempts.get(key)||0)+1);}}
   await click(new RegExp('^Move '+direction));moves++;
  }else await acknowledge();
  if(moves>=160)break;
 }
 assert.ok(seen,'Must encounter '+expected+' under actual regime rules');await capture('regime-'+target+'-encounters');current.checks.push('Actual site visit and generated '+expected+' encounter under compound extreme laws');
});
await scenario('death-squads',resolve(output,'saves/death-squad-siege.json'),async()=>{
 await page.keyboard.press('f');await page.waitForTimeout(120);await drive({fight:true});assert.ok(current.events.some(t=>/DethSquad Officer/.test(t)));await capture('death-squad-defence');current.checks.push('Real Death Squad siege combat through completed defence');
});
await scenario('natural-extension',resolve(root,'reports/deep-playtest-20261014/extension-final.json'),async()=>{
 const before=await exported('natural-start');
 for(let day=1;day<=180;day++){await click(/Carry out (?:your )?plans|Run day|Wait a day/i);await drive();if(day%30===0){await capture('natural-day-'+day);const saved=await exported('natural-day-'+day);current.checks.push({day,date:saved.game.date,funds:saved.game.ledger._funds});console.log('Natural campaign day '+day);}}
 const after=await exported('natural-final');assert.equal((Date.parse(after.game.date+'Z')-Date.parse(before.game.date+'Z'))/86400000,180);assert.equal(after.game.ledger._funds,before.game.ledger._funds+after.game.ledger.totalIncome-before.game.ledger.totalIncome-after.game.ledger.totalExpense+before.game.ledger.totalExpense);current.checks.push('180 additional consecutive calendar days; balance reconciles');
});
await scenario('final-browser-reliability',resolve(output,'natural-final.json'),async()=>{
 const before=await exported('reliability-before');await page.waitForLoadState('networkidle');await page.evaluate(()=>navigator.serviceWorker.ready.then(r=>r.active?.state));
 await page.reload({waitUntil:'networkidle'});await wait(/Continue as/);await page.waitForTimeout(400);await click(/^Continue as/);await wait(/Save & exit/);await capture('final-refreshed-build');
 await page.waitForFunction(()=>navigator.serviceWorker.controller?.state==='activated');
 current.workerState=await page.evaluate(async()=>{const r=await navigator.serviceWorker.getRegistration();return {controller:navigator.serviceWorker.controller?.scriptURL,active:r?.active?.state,installing:r?.installing?.state,waiting:r?.waiting?.state,cacheKeys:await caches.keys(),cachedIndex:!!await caches.match(new URL('index.html',location.href).href),storage:await navigator.storage.estimate()};});await writeFile(resolve(output,'worker-debug.json'),JSON.stringify(current.workerState,null,2));
 await context.setOffline(true);await page.reload({waitUntil:'networkidle'});await wait(/Continue as/);await page.waitForTimeout(400);await click(/^Continue as/);await wait(/Save & exit/);await capture('final-offline-campaign');await context.setOffline(false);
 const after=await exported('reliability-after');assert.equal(after.game.date,before.game.date);assert.equal(after.game.ledger._funds,before.game.ledger._funds);assert.deepEqual(after.game.lcs.pool.map(p=>({id:p.id,alive:p.alive,portraitId:p.portraitId})),before.game.lcs.pool.map(p=>({id:p.id,alive:p.alive,portraitId:p.portraitId})));current.checks.push('Final runtime: export/reload, refresh, activated service worker, warm-cache offline refresh, crew/portrait/funds/date persistence');
});
report.completed=new Date().toISOString();await writeFile(resolve(output,'browser-report.json'),JSON.stringify(report,null,2));await browser.close();if(report.scenarios.some(s=>s.status==='failed')||report.errors.length)process.exitCode=1;
