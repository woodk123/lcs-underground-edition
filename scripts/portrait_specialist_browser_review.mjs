// Specialist portrait and painted appearance acceptance through isolated ordinary UI save imports.
// Uses an isolated browser context, ordinary game controls and portable exports.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const { PNG } = require('pngjs');
const args = process.argv.slice(2);
const arg = (name, fallback) => args.includes(name) ? args[args.indexOf(name) + 1] : fallback;
const url = arg('--url', 'http://127.0.0.1:8765/');
const output = resolve(root, arg('--out', `reports/portrait-specialist-browser-${new Date().toISOString().replaceAll(':', '-')}`));
await mkdir(output, { recursive: true });
const report = { status: 'running', url, started: new Date().toISOString(), pageErrors: [], consoleErrors: [], failedRequests: [], atlasResponses: [], screenshots: [], checks: [] };
const main = await fetch(new URL('main.dart.js', url));
assert.ok(main.ok);
report.mainJsSha256 = createHash('sha256').update(Buffer.from(await main.arrayBuffer())).digest('hex');
const browser = await chromium.launch({ channel: 'msedge', headless: true });
let context = await browser.newContext({ viewport: { width: 1600, height: 1000 }, acceptDownloads: true });
let page = await context.newPage();
function attachListeners() {
page.on('pageerror', error => report.pageErrors.push(error.message));
page.on('console', message => { if (message.type() === 'error') report.consoleErrors.push(message.text()); });
page.on('requestfailed', request => report.failedRequests.push({ url: request.url(), failure: request.failure()?.errorText }));
page.on('response', response => {
  if (!/portraits_v2\/(?:batch_\d+|appearance_overlays)\.png/.test(response.url())) return;
  let fromPage = false;
  try { fromPage = response.request().frame() === page.mainFrame(); } catch {}
  report.atlasResponses.push({ url: response.url(), status: response.status(), fromPage });
});
}
attachListeners();

async function text() {
  return page.locator('flt-semantics-host').evaluate(host => [host.innerText, ...[...host.querySelectorAll('[aria-label]')].map(node => node.getAttribute('aria-label'))].filter(Boolean).join('\n'));
}
async function wait(pattern) {
  const deadline = Date.now() + 20000;
  let actual = '';
  while (Date.now() < deadline) {
    if (await page.locator('flt-semantics-host').count()) {
      actual = await text();
      if (pattern.test(actual)) return;
    }
    await page.waitForTimeout(100);
  }
  throw new Error(`Missing ${pattern}: ${actual}`);
}
async function click(name) {
  const button = page.getByRole('button', { name }).first();
  await button.waitFor();
  await button.click();
  await page.waitForTimeout(250);
}
async function shot(name) {
  await page.mouse.move(2, 2);
  await page.screenshot({ path: resolve(output, `${name}.png`), fullPage: true });
  await writeFile(resolve(output, `${name}.txt`), await text());
  report.screenshots.push(`${name}.png`);
}
async function journal() {
  await page.getByRole('button', { name: 'Save & exit', exact: true }).waitFor();
  await wait(/Organisation/);
}
async function exportSave(name) {
  await click('Save & exit');
  await wait(/Continue (?:your campaign|Last Game|as )/);
  await click('Load & Manage Saves');
  await click(/^A(?:\s|$)/);
  await wait(/Manage .*Saved Game/);
  const pending = page.waitForEvent('download');
  await click(/Export Save File/);
  const download = await pending;
  const path = resolve(output, `${name}.json`);
  await download.saveAs(path);
  const save = JSON.parse(await readFile(path, 'utf8'));
  return typeof save.saveData === 'string' ? JSON.parse(save.saveData) : save.saveData;
}
function mean(png, box) {
  const sum = [0, 0, 0];
  let count = 0;
  for (let y = Math.ceil(box.y); y < box.y + box.height; y++) {
    for (let x = Math.ceil(box.x); x < box.x + box.width; x++) {
      const offset = (y * png.width + x) * 4;
      for (let channel = 0; channel < 3; channel++) sum[channel] += png.data[offset + channel];
      count++;
    }
  }
  return sum.map(value => value / count);
}

const rawFixture = JSON.parse(await readFile(resolve(root, 'upstream/test/saves/felix_1_0.json'), 'utf8'));
const original = typeof rawFixture.saveData === 'string' ? JSON.parse(rawFixture.saveData) : rawFixture.saveData;
const clone = value => JSON.parse(JSON.stringify(value));
const year = Number(original.date.slice(0, 4));
const rosterCases = [
  ['subcultures', [['Punk','PUNK',30,250,253],['Goth','GOTH',30,254,257],['Emo','EMO',25,258,261],['Biker','BIKER',45,262,265],['Nun','NUN',40,266,281]]],
  ['specialists', [['Priest','PRIEST',45,266,281],['Televangelist','TELEVANGELIST',55,266,281],['Mutant','MUTANT',38,282,297],['Child','WORKER_FACTORY_CHILD',7,298,313],['Teen','TEENAGER',16,314,329]]],
  ['bodies-and-elderly', [['Dog','GUARDDOG',5,330,345,'canine'],['Tank','TANK',40,346,347,'tank'],['Monster','GENETIC',30,348,349,'monster'],['Gorilla','GENETIC',30,350,351,'purpleGorilla'],['Elder','RETIREE',88,362,377]]],
];
function buildFixture(specs, appearance) {
  const file = clone(rawFixture), data = clone(original);
  const people = specs.map((spec, index) => {
    const [name,type,age,minId,maxId,body] = spec;
    const person = clone(original.lcs.pool[index]);
    person.name = person.properName = name;
    person.typeId = `CREATURE_${type}`;
    person.birthDate = `${year-age}-01-01T00:00:00.000`;
    person.gender = person.genderAssignedAtBirth = type==='NUN' ? 'female' : 'male';
    delete person.portraitId; delete person.portraitVariant; delete person.portraitAssignedAge;
    delete person.equippedArmor;
    person.equippedClothing = null;
    if (body) {
      person.body.type = body; person.body.typeName = name;
      if (body==='tank') {
        for(const part of ['turretRear','turretFront','frontArmor','rearArmor','leftSide','rightSide','leftTrack','rightTrack']) {
          person.body[part]={...clone(person.body.torso),name:part};
        }
      }
    }
    if (appearance && index===0) {
      person.portraitId = 1; person.portraitAssignedAge = 40; person.portraitVariant=100;
      appearance(person);
    }
    return person;
  });
  data.lcs.pool = people;
  file.saveData = data;
  return file;
}
async function importAndLoad(path) {
  await page.goto(url, { waitUntil: 'networkidle' });
  await wait(/Start a new movement|Start a New Game/);
  const chooser = page.waitForEvent('filechooser');
  await click('Import a Save');
  await (await chooser).setFiles(path);
  await wait(/Save imported/); await page.keyboard.press('Enter');
  await wait(/Start a new movement|Start a New Game/);
  await click('Load & Manage Saves'); await click(/^A(?:\s|$)/);
  await wait(/Manage .*Saved Game/); await click(/^L Load Game/);
  await journal(); await page.waitForTimeout(800);
}
async function freshContext() {
  await context.close();
  context = await browser.newContext({ viewport: { width: 1600, height: 1000 }, acceptDownloads: true });
  page = await context.newPage(); attachListeners();
}
async function capturePerson(name, label) {
  const escaped=name.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
  await click(new RegExp(`^Select crew ${escaped}(?:$|\\s)`));
  await click(new RegExp(`^Inspect ${escaped}(?:$|\\s)`));
  await click('Full dossier');
  await page.waitForTimeout(500);
  const images = page.getByRole('img', { name:new RegExp(`^${escaped} portrait\\.`) });
  let box;
  for (let i=0;i<await images.count();i++) {
    const candidate = await images.nth(i).boundingBox();
    if (candidate?.width>=80 && (!box||candidate.width>box.width)) box=candidate;
  }
  assert.ok(box,`Dossier must contain a large accessible painted portrait for ${name}`);
  await page.mouse.move(2,2);
  const pixels=PNG.sync.read(await page.screenshot({clip:box,path:resolve(output,`${label}-portrait.png`)}));
  const semantics=await text();
  await shot(label);
  await click('Close dossier');
  return {pixels,semantics,box};
}
const centerBox = png => ({x:png.width*.35,y:png.height*.3,width:png.width*.3,height:png.height*.25});
function pixelDifference(left,right,region) {
  let difference=0,count=0;
  const box=region??{x:0,y:0,width:left.width,height:left.height};
  for(let y=Math.ceil(box.y);y<box.y+box.height;y++)for(let x=Math.ceil(box.x);x<box.x+box.width;x++) {
    const at=(y*left.width+x)*4;
    for(let c=0;c<3;c++) {difference+=Math.abs(left.data[at+c]-right.data[at+c]);count++;}
  }
  return difference/count;
}
try {
  report.rosters=[];
  for (const [label,specs] of rosterCases) {
    await freshContext();
    const fixturePath=resolve(output,`fixture-${label}.json`);
    await writeFile(fixturePath,JSON.stringify(buildFixture(specs)));
    await importAndLoad(fixturePath);
    const captures=[];
    for(const spec of specs) captures.push(await capturePerson(spec[0],`${label}-${spec[0].toLowerCase()}`));
    const saved=await exportSave(`export-${label}`);
    const members=[];
    for(let i=0;i<specs.length;i++) {
      const spec=specs[i], person=saved.lcs.pool.find(p=>p.name===spec[0]);
      assert.ok(person,`Export includes ${spec[0]}`);
      assert.ok(person.portraitId>=spec[3]&&person.portraitId<=spec[4],`${spec[0]} has category-correct saved portrait: ${person.portraitId}`);
      assert.ok(Number.isInteger(person.portraitVariant)); assert.equal(person.portraitAssignedAge,spec[2]);
      const batch=16+Math.floor((person.portraitId-250)/16),cell=(person.portraitId-250)%16;
      const asset=`assets/modern/portraits_v2/batch_${batch}.png`;
      assert.ok(report.atlasResponses.some(r=>r.url.endsWith(asset)&&r.status===200&&r.fromPage),`App requested ${asset}`);
      const atlas=PNG.sync.read(await readFile(resolve(root,'upstream',asset)));
      const expected=mean(atlas,{x:(cell%4+.35)*atlas.width/4,y:(Math.floor(cell/4)+.3)*atlas.height/4,width:atlas.width/4*.3,height:atlas.height/4*.25});
      const actual=mean(captures[i].pixels,centerBox(captures[i].pixels));
      const delta=actual.map((v,c)=>Math.abs(v-expected[c]));
      assert.ok(Math.max(...delta)<24,`${spec[0]} rendered correct atlas-cell central artwork: RGB difference ${delta}`);
      members.push({name:person.name,portraitId:person.portraitId,asset,cell,centralRgbDifference:delta});
    }
    await click(/^L Load Game/); await journal();
    const reloadedCapture=await capturePerson(specs[0][0],`${label}-reloaded-first`);
    assert.ok(pixelDifference(reloadedCapture.pixels,captures[0].pixels)<.05,`${label} rendered identity stays visually identical after save/reload`);
    const again=await exportSave(`export-${label}-reloaded`);
    assert.deepEqual(again.lcs.pool.map(p=>[p.id,p.portraitId,p.portraitVariant,p.portraitAssignedAge]),saved.lcs.pool.map(p=>[p.id,p.portraitId,p.portraitVariant,p.portraitAssignedAge]));
    report.rosters.push({label,members});
  }
  report.checks.push('Fifteen real dossier portraits use category-correct saved IDs, request the correct atlases, match source artwork and retain full identity through UI save/reload.');
  const appearanceCases=[
    ['baseline',p=>{}],
    ['left-eye',p=>{p.body.missingLeftEye=true;}],
    ['right-eye',p=>{p.body.missingRightEye=true;}],
    ['wounds',p=>{p.body.head.cut=true;p.body.missingNose=true;}],
    ['medical',p=>{p.equippedClothing={stackSize:1,typeName:'CLOTHING_LABCOAT',bloody:false,damaged:false};}],
    ['armor',p=>{p.equippedClothing={stackSize:1,typeName:'CLOTHING_SWATARMOR',bloody:false,damaged:false};}],
    ['aged',p=>{p.birthDate=`${year-70}-01-01T00:00:00.000`;}],
  ];
  const appearanceSpecs=[['Appearance Reference','LAWYER',40,1,1],...rosterCases[0][1].slice(1)];
  const appearanceCaptures={}; report.appearances=[];
  for(const [label,mutation] of appearanceCases) {
    await freshContext();
    const path=resolve(output,`fixture-appearance-${label}.json`);
    await writeFile(path,JSON.stringify(buildFixture(appearanceSpecs,mutation)));
    await importAndLoad(path);
    const capture=await capturePerson('Appearance Reference',`appearance-${label}`);
    appearanceCaptures[label]=capture;
    const saved=await exportSave(`export-appearance-${label}`),person=saved.lcs.pool[0];
    assert.equal(person.portraitId,1);assert.equal(person.portraitVariant,100);assert.equal(person.portraitAssignedAge,40);
    const diff=label==='baseline'?0:pixelDifference(capture.pixels,appearanceCaptures.baseline.pixels);
    let agingPixels;
    if(label==='aged') {
      let changed=0,peakChannel=0,outsideForehead=0;
      const a=capture.pixels,b=appearanceCaptures.baseline.pixels;
      for(let y=0;y<a.height;y++)for(let x=0;x<a.width;x++) {
        const at=(y*a.width+x)*4;
        const delta=Math.max(...[0,1,2].map(c=>Math.abs(a.data[at+c]-b.data[at+c])));
        if(delta>0) {
          changed++; peakChannel=Math.max(peakChannel,delta);
          if(x<a.width*.35||x>a.width*.65||y<a.height*.15||y>a.height*.35)outsideForehead++;
        }
      }
      agingPixels={changed,peakChannel,outsideForehead};
      assert.ok(changed>=60&&peakChannel>=5,'Subtle ageing lines must change at least60 forehead pixels with measurable contrast');
      assert.equal(outsideForehead,0,'Ageing must preserve identity outside the forehead lines');
    } else if(label!=='baseline')assert.ok(diff>.25,`${label} visibly changes portrait pixels (difference ${diff})`);
    if(label==='left-eye')assert.match(capture.semantics,/Left eye missing/);
    if(label==='right-eye')assert.match(capture.semantics,/Right eye missing/);
    if(label==='wounds')assert.match(capture.semantics,/Nose missing/);
    if(label==='aged')assert.match(capture.semantics,/Aged since this portrait was assigned/);
    report.appearances.push({label,portraitId:person.portraitId,meanAbsolutePixelDifference:diff,agingPixels});
  }
  assert.ok(pixelDifference(appearanceCaptures['left-eye'].pixels,appearanceCaptures['right-eye'].pixels)>.15,'Left and right eye dressings visibly differ');
  assert.ok(report.atlasResponses.some(r=>r.url.endsWith('appearance_overlays.png')&&r.status===200&&r.fromPage),'Application loads painted appearance atlas successfully');
  report.checks.push('Missing left/right eyes, head/nose wounds, medical clothing and armor visibly alter rendered portraits; ageing adds subtle measurable forehead lines while saved facial ID, cosmetic variant and assignment age stay fixed.');
  assert.deepEqual(report.pageErrors,[]);assert.deepEqual(report.consoleErrors,[]);assert.deepEqual(report.failedRequests,[]);
  report.status='passed';

} catch (error) {
  report.status = 'failed';
  report.error = error.stack ?? String(error);
  process.exitCode = 1;
  try { await shot('FAILURE'); } catch {}
  console.error(report.error);
} finally {
  report.completed = new Date().toISOString();
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  await context.close();
  await browser.close();
  console.log(JSON.stringify({ output, status: report.status, checks: report.checks, mainJsSha256: report.mainJsSha256 }, null, 2));
}

