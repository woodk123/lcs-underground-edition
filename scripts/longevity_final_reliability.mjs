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
const previous=only.length?await readFile(resolve(output,'reliability-browser-report.json'),'utf8').then(JSON.parse).catch(()=>null):null;
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
async function scenario(label,path,run){if(only.length&&!only.includes(label))return;current={label,path,runtimeSha256:report.runtimeSha256,captures:[],events:[],checks:[]};report.scenarios.push(current);try{await load(path);await run();current.status='passed';}catch(e){current.status='failed';current.error=String(e);if(page)await capture(label+'-failure');}finally{if(context)await context.close();await writeFile(resolve(output,'reliability-browser-report.json'),JSON.stringify(report,null,2));console.log(label+': '+current.status+(current.error||''));}}
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


await scenario('final-browser-reliability',resolve(output,'natural-final.json'),async()=>{
 const before=await exported('reliability-before');await page.waitForLoadState('networkidle');await page.evaluate(()=>navigator.serviceWorker.ready.then(r=>r.active?.state));
 await page.reload({waitUntil:'networkidle'});await wait(/Continue as/);await page.waitForTimeout(400);await click(/^Continue as/);await wait(/Save & exit/);await capture('final-refreshed-build');
 await page.waitForFunction(()=>navigator.serviceWorker.controller?.state==='activated');
 current.workerState=await page.evaluate(async()=>{const r=await navigator.serviceWorker.getRegistration();return {controller:navigator.serviceWorker.controller?.scriptURL,active:r?.active?.state,installing:r?.installing?.state,waiting:r?.waiting?.state,cacheKeys:await caches.keys(),cachedIndex:!!await caches.match(new URL('index.html',location.href).href),storage:await navigator.storage.estimate()};});await writeFile(resolve(output,'worker-debug.json'),JSON.stringify(current.workerState,null,2));
 await context.setOffline(true);await page.reload({waitUntil:'networkidle'});await wait(/Continue as/);await page.waitForTimeout(400);await click(/^Continue as/);await wait(/Save & exit/);await capture('final-offline-campaign');await context.setOffline(false);
 const after=await exported('reliability-after');assert.equal(after.game.date,before.game.date);assert.equal(after.game.ledger._funds,before.game.ledger._funds);assert.deepEqual(after.game.lcs.pool.map(p=>({id:p.id,alive:p.alive,portraitId:p.portraitId})),before.game.lcs.pool.map(p=>({id:p.id,alive:p.alive,portraitId:p.portraitId})));current.checks.push('Final runtime: export/reload, refresh, activated service worker, warm-cache offline refresh, crew/portrait/funds/date persistence');
});
report.completed=new Date().toISOString();await writeFile(resolve(output,'reliability-browser-report.json'),JSON.stringify(report,null,2));await browser.close();if(report.scenarios.some(s=>s.status==='failed')||report.errors.length)process.exitCode=1;
