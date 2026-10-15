// Isolated real-browser recruitment introductions; ordinary save imports/UI.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';
const root = resolve(import.meta.dirname, '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const url = 'http://127.0.0.1:8765/';
const out = resolve(root, 'reports/recruitment-card-browser');
await mkdir(out, { recursive: true });
const report = { status: 'running', checks: [], errors: [], screenshots: [] };
report.mainJsSha256 = createHash('sha256').update(Buffer.from(await (await fetch(new URL('main.dart.js', url))).arrayBuffer())).digest('hex');
const browser = await chromium.launch({ channel: 'msedge', headless: true });
const context = await browser.newContext({ viewport: { width: 1600, height: 1000 }, acceptDownloads: true });
const page = await context.newPage();
page.on('pageerror', e => report.errors.push(e.message));
page.on('console', m => { if (m.type() === 'error') report.errors.push(m.text()); });
page.on('requestfailed', r => report.errors.push(r.url()));
async function text() {
  if (!await page.locator('flt-semantics-host').count()) return '';
  return page.locator('flt-semantics-host').evaluate(h => [h.innerText, ...[...h.querySelectorAll('[aria-label]')].map(n => n.getAttribute('aria-label'))].filter(Boolean).join('\n'));
}
async function wait(pattern) {
  for (let i = 0; i < 180; i++) { if (pattern.test(await text())) return; await page.waitForTimeout(100); }
  throw Error(`Missing ${pattern}: ${await text()}`);
}
async function click(name) {
  const b = page.getByRole('button', { name }).first();
  await b.scrollIntoViewIfNeeded(); await b.click(); await page.waitForTimeout(180);
}
async function shot(name) {
  await page.mouse.move(1, 1); await page.waitForTimeout(250);
  await page.screenshot({ path: resolve(out, `${name}.png`) });
  await writeFile(resolve(out, `${name}.txt`), await text()); report.screenshots.push(`${name}.png`);
}
async function advanceUntil(pattern) {
  for (let i = 0; i < 60; i++) {
    const current = await text();
    if (pattern.test(current)) return;
    if (/What type of person will .*try to meet and recruit/.test(current)) {
      await click(/^A\s/); continue;
    }
    const next = page.getByRole('button', { name: /^Continue$/ });
    if (await next.count() && await next.first().isEnabled()) await next.first().click();
    else await page.keyboard.press('Enter');
    await page.waitForTimeout(180);
  }
  throw Error(`Reader stalled before ${pattern}: ${await text()}`);
}
try {
  const file = JSON.parse(await readFile(resolve(root, 'upstream/test/saves/felix_1_0.json'), 'utf8'));
  const data = typeof file.saveData === 'string' ? JSON.parse(file.saveData) : file.saveData;
  const recruiter = data.lcs.pool[0];
  recruiter.activity = { type: 'recruiting', idString: 'CREATURE_LAWYER' };
  recruiter.rawSkill.streetSmarts = 100;
  const prospect = structuredClone(data.lcs.pool[1]);
  Object.assign(prospect, { id: 10001, name: 'Morgan Rivers', properName: 'Morgan Rivers', alreadyNamed: true,
    typeId: 'CREATURE_LAWYER', birthDate: '1988-01-01T00:00:00.000',
    hireId: null, squadId: null, portraitId: 25, portraitAssignedAge: 35, portraitVariant: 0,
    equippedWeapon: null, equippedClothing: null, activity: { type: 'none' } });
  for (const key of Object.keys(prospect.rawSkill)) prospect.rawSkill[key] = 0;
  Object.assign(prospect.rawSkill, { law: 7, business: 4, persuasion: 3 });
  data.recruitmentSessions = [{ recruit: prospect, recruiter: recruiter.id, rawEagerness: 2 }];
  data.nextCreatureId = Math.max(data.nextCreatureId, 10002);
  file.saveData = data;
  const path = resolve(out, 'fixture.json'); await writeFile(path, JSON.stringify(file));
  await page.goto(url, { waitUntil: 'networkidle' });
  await wait(/Start a new movement|Start a New Game/);
  const choosing = page.waitForEvent('filechooser'); choosing.catch(() => {}); await click('Import a Save');
  await (await choosing).setFiles(path);
  await wait(/Save imported/); await page.keyboard.press('Enter');
  await click('Load & Manage Saves'); await click(/^A(?:\s|$)/);
  await wait(/Manage .*Saved Game/); await click(/^L Load Game/);
  await wait(/Organisation/);
  await click(/Carry out (?:your )?plans|Run day|Wait a day/i);
  await advanceUntil(/MEET A PROSPECT/);
  const candidateText = await text();
  assert.match(candidateText, /Strongest skills/);
  assert.ok(await page.getByRole('img', { name: /portrait/ }).count());
  assert.ok(await page.getByRole('button', { name: /^[A-J] · Meet / }).count() > 1);
  await shot('01-candidate-cards');
  report.checks.push('Real recruiting activity introduces multiple actual candidates as portrait cards with measured skills and original reader shortcuts.');
  const callItADay = page.getByRole('button', { name: /Call it a day/i });
  assert.ok(await callItADay.count(), 'Original leave choice remains available');
  await callItADay.first().click();
  await advanceUntil(/RECRUITMENT MEETING/);
  assert.match(await text(), /Morgan Rivers/);
  assert.match(await text(), /Law 7/);
  assert.match(await text(), /Business 4/);
  assert.match(await text(), /Persuasion 3/);
  await shot('02-follow-up-card');
  await click('Inspect Morgan Rivers');
  await wait(/Close dossier/); await shot('03-prospect-dossier');
  await click('Close dossier');
  assert.match(await text(), /RECRUITMENT MEETING/);
  assert.match(await text(), /Morgan Rivers/);
  await page.setViewportSize({ width: 800, height: 700 });
  await shot('04-narrow-meeting');
  await page.setViewportSize({ width: 1600, height: 1000 });
  await click(/Break off the meetings/);
  report.checks.push('Follow-up card shows exact skills; inspecting and closing the prospect dossier leaves the meeting available; original break-off command works.');
  assert.deepEqual(report.errors, []);
  report.status = 'passed';
} catch (e) {
  report.status = 'failed'; report.error = e.stack ?? String(e); process.exitCode = 1;
  await shot('FAILURE').catch(() => {});
  console.error(report.error);
} finally {
  await writeFile(resolve(out, 'report.json'), JSON.stringify(report, null, 2));
  await browser.close(); console.log(JSON.stringify({ output: out, ...report }, null, 2));
}
