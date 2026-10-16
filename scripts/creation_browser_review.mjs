// Real new-campaign UI review in an isolated headless Chrome profile.
// Does not operate a human browser profile or stop the user's game server.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const args = process.argv.slice(2);
const expectedHash = args[args.indexOf('--expected-hash') + 1];
assert.ok(args.includes('--expected-hash'));
assert.match(expectedHash, /^[a-f0-9]{64}$/);
const url = args.includes('--url') ? args[args.indexOf('--url') + 1] : 'http://127.0.0.1:18879/';
const stamp = new Date().toISOString().replaceAll(':', '-').replaceAll('.', '-');
const output = resolve(root, `reports/browser/creation-${stamp}`);
const profile = resolve(root, `.local/browser-profiles/creation-${stamp}`);
await mkdir(output, { recursive: true });
await mkdir(profile, { recursive: true });
const report = { status: 'running', started: new Date().toISOString(), expectedHash, url,
  scope: 'Real original new-game settings, identity, ten background questions, briefing, public-name entry and playable HQ. Normal and150%/800x600 manual/fate journeys in an isolated profile.',
  checks: [], screenshots: [], pageErrors: [], consoleErrors: [], failedRequests: [] };
let context, page;
async function text() {
  return page.locator('flt-semantics-host').evaluate(host => [host.innerText,
    ...[...host.querySelectorAll('[aria-label]')].map(n => n.getAttribute('aria-label')),
    ...[...host.querySelectorAll('input,textarea')].map(n => n.value),
  ].filter(Boolean).join('\n'));
}
async function wait(pattern) {
  const until = Date.now() + 15000;
  while (Date.now() < until) {
    if (await page.locator('flt-semantics-host').count() && pattern.test(await text())) return;
    await page.waitForTimeout(100);
  }
  throw new Error(`Missing ${pattern}: ${await text()}`);
}
async function click(pattern) {
  const target = page.getByRole('button', { name: pattern }).first();
  for (let attempt = 0; attempt < 18; attempt++) {
    const box = await target.count() ? await target.boundingBox() : null, viewport = page.viewportSize();
    if (box && box.height > 5 && box.y >= 0 && box.y + Math.min(box.height / 2, 35) < viewport.height - 4) {
      await target.click({ position: { x: Math.min(20, box.width / 2), y: Math.min(25, box.height / 2) } });
      await page.waitForTimeout(200); return;
    }
    if (!box || box.height <= 5 || box.y > viewport.height - 80) {
      await page.mouse.move(viewport.width * .3, viewport.height * .5);
      await page.mouse.wheel(0, 240); await page.waitForTimeout(180);
    } else {
      await target.scrollIntoViewIfNeeded(); await page.waitForTimeout(120);
    }
  }
  throw new Error(`Cannot reach ${pattern}`);
}
async function capture(name) {
  await page.mouse.move(2, 2); await page.waitForTimeout(220);
  assert.equal(await page.getByRole('dialog').count(), 0);
  assert.doesNotMatch(await text(), /AVAILABLE CHOICES/);
  const bytes = await page.screenshot({ path: resolve(output, `${name}.png`), fullPage: true });
  assert.deepEqual({width:bytes.readUInt32BE(16),height:bytes.readUInt32BE(20)}, page.viewportSize());
  await writeFile(resolve(output, `${name}.txt`), await text());
  report.screenshots.push(`${name}.png`);
  report.checks.push({ name, status: 'passed', viewport: page.viewportSize() });
  console.log(`PASS ${name}`);
}
async function rerollPortrait(prefix) {
  const preview = page.getByRole('img', { name: 'Founder portrait preview', exact: true });
  await preview.waitFor();
  await page.waitForTimeout(300);
  const beforeText = await text();
  const before = createHash('sha256').update(await preview.screenshot()).digest('hex');
  await click(/^Reroll portrait$/);
  await page.mouse.move(2, 2);
  await page.waitForTimeout(350);
  const after = createHash('sha256').update(await preview.screenshot()).digest('hex');
  assert.notEqual(after, before, 'Reroll must visibly change the portrait');
  assert.equal(await text(), beforeText, 'Reroll must leave names and settings unchanged');
  report.checks.push({ name: `${prefix}-portrait-reroll`, status: 'passed' });
}
async function bonusHelp(prefix, scale) {
  const before = await text();
  const answer = page.getByRole('button', { name: /^A(?:\s|$)/ }).first();
  await answer.scrollIntoViewIfNeeded();
  const box = await answer.boundingBox();
  assert.ok(box);
  const y = box.y + box.height - 12 - 8.4 * scale;
  let previousX = box.x + 40;
  let lastPoint;
  for (const [name, message] of [
    ['law', /courtroom defense, legal arguments/],
    ['agility', /Speed and coordination/],
  ]) {
    let popup;
    for (let x = previousX; x < Math.min(box.x + box.width - 12, box.x + 380 * scale); x += 12) {
      await page.mouse.move(x, y);
      await page.waitForTimeout(450);
      const candidates = page.getByText(message);
      for (const candidate of await candidates.all()) {
        // Sidebar rows expose the same help in their accessibility labels.
        // The actual popup is a multiline box, not a single sidebar stat row.
        const bounds = await candidate.boundingBox({ timeout: 500 }).catch(() => null);
        if (bounds && bounds.width > 200 && bounds.height > 60
            && await candidate.isVisible()) {
          // A popup adds/removes semantics nodes during its fade. Keep its
          // exact text instead of a positional locator that can shift mid-frame.
          popup = page.getByText(await candidate.innerText(), { exact: true }).last();
          previousX = x + 12;
          lastPoint = { x, y };
          break;
        }
      }
      if (popup) break;
    }
    assert.ok(popup, `No ${name} tooltip over the answer bonus`);
    await page.waitForTimeout(250);
    const bounds = await popup.boundingBox();
    const viewport = page.viewportSize();
    assert.ok(bounds && bounds.x >= 0 && bounds.y >= 0
      && bounds.x + bounds.width <= viewport.width && bounds.y + bounds.height <= viewport.height);
    const image = `${prefix}-bonus-${name}.png`;
    await page.screenshot({ path: resolve(output, image), fullPage: true });
    report.screenshots.push(image);
    report.checks.push({ name: `${prefix}-bonus-${name}`, status: 'passed', bounds, target: lastPoint });
    console.log(`PASS ${prefix}-bonus-${name}`);
  }
  await page.mouse.move(2, 2);
  await page.waitForTimeout(350);
  assert.equal(await text(), before, 'Inspecting bonuses must not select an answer or change founder facts');
  await page.mouse.move(lastPoint.x, lastPoint.y);
  await page.waitForTimeout(450);
  return lastPoint;
}
async function founderFlow({ fate, prefix, name }) {
  await click(/^Start a New Game/); await wait(/Campaign dossier/);
  await capture(`${prefix}-01-settings`);
  await click(/^Continue to founder/); await wait(/The founder/);
  assert.match(await text(), /Given name/);
  assert.doesNotMatch(await text(), /Founder dossier/);
  await rerollPortrait(prefix);
  if (fate) {
    await click(/^Tragic origin/); await wait(/Let Fate Decide/);
  }
  await capture(`${prefix}-02-identity`);
  await click(/^Begin background/);
  for (let step = 1; step <= 10; step++) {
    await wait(new RegExp(`${step}\\s*/\\s*10`));
    assert.match(await text(), /Founder dossier/);
    if (step === 1 || step === 10) await capture(`${prefix}-03-background-${step}`);
    if (fate) {
      assert.equal(await page.getByRole('button', { name: /^A(?:\s|$)/ }).count(), 0);
      await click(/^Continue/);
    } else {
      assert.equal(await page.getByRole('button', { name: /^[A-E](?:\s|$)/ }).count(), 5);
      if (step === 4) {
        await bonusHelp('normal', 1);
        await click(/^Reading size/);
        await page.getByRole('menuitem', { name: '150%', exact: true }).click();
        await page.setViewportSize({ width: 800, height: 600 });
        await page.waitForTimeout(250);
        const bonus = await bonusHelp('large', 1.5);
        await page.mouse.click(bonus.x, bonus.y);
        await wait(/5\s*\/\s*10/);
        await click(/^Reading size/);
        await page.getByRole('menuitem', { name: '100%', exact: true }).click();
        await page.setViewportSize({ width: 1280, height: 720 });
        await page.waitForTimeout(200);
        continue;
      }
      await click(/^A(?:\s|$)/);
    }
  }
  await wait(/A new Conservative era/); await capture(`${prefix}-04-briefing`);
  await click(/^Continue/); await wait(/Sign the founding record/);
  const field = page.getByRole('textbox').first(); await field.waitFor();
  assert.ok(await field.inputValue());
  await field.fill(name);
  await capture(`${prefix}-05-public-name`);
  const begin = page.getByRole('button', {name:/^Begin campaign/});
  const bounds = await begin.boundingBox();
  assert.ok(bounds && bounds.y >= 0 && bounds.y + bounds.height <= page.viewportSize().height);
  await begin.click(); await wait(/Save & exit/);
  assert.match(await text(), new RegExp(name));
  await capture(`${prefix}-06-playable-organisation`);
  await click(/^Save & exit/); await wait(/Start a New Game/);
}
try {
  const response = await fetch(new URL('main.dart.js', url));
  report.mainJsSha256 = createHash('sha256').update(Buffer.from(await response.arrayBuffer())).digest('hex');
  assert.equal(report.mainJsSha256, expectedHash);
  context = await chromium.launchPersistentContext(profile, {
    channel:'chrome', headless:true, viewport:{width:1280,height:720},
  });
  report.browserVersion = context.browser().version();
  page = await context.newPage();
  page.on('pageerror', error => report.pageErrors.push(error.stack ?? error.message));
  page.on('console', message => {if(message.type()==='error') report.consoleErrors.push(message.text());});
  page.on('requestfailed', request => report.failedRequests.push({url:request.url(),failure:request.failure()?.errorText}));
  await page.goto(url, {waitUntil:'networkidle'}); await wait(/Start a New Game/);
  if(!args.includes('--large-only'))await founderFlow({fate:false,prefix:'manual',name:'Journal Founder Review'});
  await click(/^Start a New Game/); await wait(/Campaign dossier/);
  await click(/^Reading size/);
  await writeFile(resolve(output,'reading-menu.html'),await page.locator('flt-semantics-host').innerHTML());
  await page.getByRole('menuitem',{name:'150%',exact:true}).click();await page.waitForTimeout(200);
  await page.setViewportSize({width:800,height:600});await page.waitForTimeout(250);
  await capture('large-01-settings');
  await click(/^Continue to founder/);await wait(/The founder/);
  await rerollPortrait('large');
  await click(/^Tragic origin/);await wait(/Let Fate Decide/);
  await capture('large-02-identity');await click(/^Begin background/);
  for(let step=1;step<=10;step++) {
    await wait(new RegExp(`${step}\\s*/\\s*10`));
    if(step===1||step===10)await capture(`large-03-fate-${step}`);
    assert.equal(await page.getByRole('button',{name:/^[A-E](?:\s|$)/}).count(),0);
    await click(/^Continue/);
  }
  await wait(/A new Conservative era/);await capture('large-04-briefing');
  await click(/^Continue/);await wait(/Sign the founding record/);
  await page.getByRole('textbox').first().fill('Large Founder Review');
  await capture('large-05-public-name');
  await page.getByRole('button',{name:/^Begin campaign/}).click();await wait(/Save & exit/);
  assert.match(await text(),/Large Founder Review/);await capture('large-06-playable-organisation');
  assert.deepEqual(report.pageErrors,[]);assert.deepEqual(report.consoleErrors,[]);assert.deepEqual(report.failedRequests,[]);
  report.status='passed';
} catch(error) {
  report.status='failed';report.error=error.stack??String(error);process.exitCode=1;
  if(page){await page.screenshot({path:resolve(output,'FAILURE.png')});await writeFile(resolve(output,'FAILURE.txt'),await text());}
} finally {
  if(context)await context.close();report.completed=new Date().toISOString();
  await writeFile(resolve(output,'report.json'),JSON.stringify(report,null,2));
  console.log(JSON.stringify({status:report.status,output,checks:report.checks.length,error:report.error}));
}
