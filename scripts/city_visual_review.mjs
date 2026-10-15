// Acceptance of space, explanation and direct navigation using an unchanged shipped campaign.
// Browser accessibility and rendered pixels only; no Dart internals, synthetic campaign or test hooks.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';

const root = process.cwd();
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const args = process.argv.slice(2);
const argument = (flag, fallback) => args.includes(flag) ? args[args.indexOf(flag) + 1] : fallback;
const url = argument('--url', args[0]?.startsWith('http') ? args[0] : 'http://127.0.0.1:8765/');
const stamp = new Date().toISOString().replaceAll(':', '-');
const output = resolve(root, argument('--out', `reports/city-review-${stamp}`));
await mkdir(output, { recursive: true });
const context = await chromium.launchPersistentContext(resolve(root, `.local/browser-profiles/city-review-${stamp}`), {
  channel: 'msedge', headless: true, viewport: { width: 1600, height: 1000 },
  recordVideo: { dir: resolve(output, 'video'), size: { width: 1600, height: 1000 } },
});
const page = await context.newPage();
const report = { status: 'running', url, screenshots: [], checks: [], pageErrors: [], consoleErrors: [] };
page.on('pageerror', error => report.pageErrors.push(String(error)));
page.on('console', message => { if (message.type() === 'error') report.consoleErrors.push(message.text()); });
async function text() {
  return page.locator('flt-semantics-host').evaluate(host => [host.innerText,
    ...[...host.querySelectorAll('[aria-label]')].map(node => node.getAttribute('aria-label')),
    ...[...host.querySelectorAll('[aria-valuetext]')].map(node => node.getAttribute('aria-valuetext')),
    ...[...host.querySelectorAll('input,textarea')].map(node => node.value)].filter(Boolean).join('\n'));
}
async function wait(pattern) {
  await page.locator('flt-semantics-host').waitFor({ state: 'attached' });
  for (let i = 0; i < 120; i++) {
    if (pattern.test(await text())) return;
    await page.waitForTimeout(100);
  }
  throw new Error(`Missing UI ${pattern}: ${await text()}`);
}
async function click(name) {
  await page.getByRole('button', { name, exact: typeof name === 'string' }).first().click();
  await page.waitForTimeout(180);
}
async function shot(name, details = {}) {
  await page.waitForTimeout(180);
  await page.screenshot({ path: resolve(output, `${name}.png`) });
  await writeFile(resolve(output, `${name}.txt`), await text());
  report.screenshots.push(`${name}.png`);
  report.checks.push({ name, status: name === 'FAILURE' ? 'failed' : 'passed', viewport: page.viewportSize(), ...details });
  console.log(`${name === 'FAILURE' ? 'FAIL' : 'PASS'} ${name}`);
}
async function state() {
  const value = await page.locator('flt-semantics-host').evaluate(host => [...host.querySelectorAll('[aria-label]')]
    .map(node => node.getAttribute('aria-label')).filter(Boolean).join('\n')
    .match(/(?:LIBERAL CRIME SQUAD|LCS)\n\d{1,2} (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d{4}\n\$[\d,]+/)?.[0] ?? '');
  const date = value.match(/\b\d{1,2} (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d{4}\b/)?.[0] ?? value.match(/(?:January|February|March|April|May|June|July|August|September|October|November|December) \d{1,2}, \d{4}/)?.[0];
  const funds = value.match(/\$([\d,]+)/)?.[1];
  assert.ok(date && funds, 'Date and funds must remain visible, including narrow layouts.');
  return { date, funds };
}
async function inside(control, contextName) {
  const box = await control.boundingBox();
  const viewport = page.viewportSize();
  assert.ok(box && box.x >= 0 && box.y >= 0 && box.x + box.width <= viewport.width + 1 && box.y + box.height <= viewport.height + 1,
    `${contextName} must be fully inside ${viewport.width}x${viewport.height}. Got ${JSON.stringify(box)}`);
  return box;
}
const areaButtons = () => page.getByRole('button', { name: /^Open (?!dossier)/ });
const siteButtons = () => page.getByRole('button', { name: /^Inspect (?!.*alongside the city)/ });
try {
  const js = await fetch(new URL('main.dart.js', url));
  assert.ok(js.ok);
  report.mainJsSha256 = createHash('sha256').update(Buffer.from(await js.arrayBuffer())).digest('hex');
  report.browserVersion = context.browser().version();
  await page.goto(url, { waitUntil: 'networkidle' });
  await wait(/Start a new movement/);
  const choose = page.waitForEvent('filechooser');
  await click('Import a Save');
  await (await choose).setFiles(resolve(root, 'upstream/test/saves/felix_1_0.json'));
  await wait(/Save imported/);
  await page.keyboard.press('Enter');
  await wait(/Start a new movement/);
  await click('Load & Manage Saves');
  await click(/^A(?:\s|$)/);
  await click(/^L Load Game/);
  await wait(/DAILY BRIEFING/);
  const initial = await state();
  report.initialCampaign = initial;
  const portraits = page.getByRole('button', { name: /^Inspect / });
  assert.equal(await portraits.count(), 5, 'The unchanged imported campaign contains five active crew, each with a direct inspector.');
  const crewNames = await portraits.allTextContents();
  report.crewNames = crewNames;
  for (const [width, height] of [[1600, 1000], [1280, 720], [800, 700]]) {
    await page.setViewportSize({ width, height });
    await page.waitForTimeout(220);
    assert.deepEqual(await state(), initial);
    if (width >= 1280) {
      const bounds = [];
      for (const portrait of await portraits.all()) bounds.push(await inside(portrait, 'All five HQ crew portraits'));
      report.hqRosterBounds ??= [];
      report.hqRosterBounds.push({ viewport: { width, height }, bounds });
    }
    await shot(`01-hq-five-crew-${width}x${height}`);
    await portraits.first().click();
    await page.getByRole('button', { name: 'Close crew inspection', exact: true }).waitFor();
    assert.equal(await page.getByRole('dialog').count(), 0, 'Everyday inspection must not open a blocking dialog.');
    await inside(page.getByRole('button', { name: 'Close crew inspection', exact: true }), 'Inspector close control');
    assert.equal(await page.getByRole('button', { name: 'Daily assignments', exact: true }).first().isEnabled(), true,
      'The primary assignment control must remain enabled during inspection.');
    await shot(`02-hq-inline-inspector-${width}x${height}`, { modal: false });
    await click('Daily assignments'); // No dismissal or Escape before primary navigation, including the narrow HQ quick action.
    await wait(/Assign Tasks to Liberals/);
    assert.deepEqual(await state(), initial);
    assert.equal(await page.getByRole('button', { name: 'Close crew inspection', exact: true }).count(), 0,
      'Changing section should clear the local inspector without an extra close click.');
    await shot(`03-inspector-to-assignments-${width}x${height}`, { clicks: 1 });
    await page.getByRole('button', { name: /^A / }).first().click();
    await wait(/Choose a group of tasks|Current assignment|Done closes|Choose an activity|Legal Fundraising/);
    await shot(`04-assignment-explained-${width}x${height}`);
    const nestedState = await state();
    const media = page.getByRole('button', { name: width < 900 ? 'Media' : 'Media & impact', exact: true }).first();
    assert.equal(await media.isEnabled(), true, 'Ordinary nested task screens must allow direct section navigation.');
    await media.click();
    await wait(/Media Overview/);
    assert.deepEqual(await state(), nestedState);
    await shot(`05-nested-assignment-direct-media-${width}x${height}`, { clicks: 1, campaignPreserved: true });
    await click('Headquarters');
    await wait(/DAILY BRIEFING/);
  }
  await page.setViewportSize({ width: 1600, height: 1000 });
  await click('Operations');
  await wait(/Open a district directly/);
  for (const [width, height] of [[1600, 1000], [1280, 720], [800, 700]]) {
    await page.setViewportSize({ width, height });
    await page.waitForTimeout(220);
    const buildings = page.getByRole('button', { name: /^(?:Open|Inspect) (?!.*alongside the city)/ });
    assert.ok(await buildings.count() > 0, 'The fitted map must show real destination objects.');
    for (const building of await buildings.all()) await inside(building, 'Every exposed city object');
    assert.deepEqual(await state(), initial);
    await shot(`06-city-full-space-${width}x${height}`);
  }
  await page.setViewportSize({ width: 1280, height: 720 });
  const district = areaButtons().first();
  await district.waitFor();
  const districtLabel = await district.innerText();
  await district.click();
  await page.waitForTimeout(250);
  assert.equal(await page.getByRole('button', { name: 'Enter district', exact: true }).count(), 0,
    'Opening a district must not require a redundant confirmation.');
  assert.ok(await siteButtons().count() > 0, 'One district activation must reveal its real sites.');
  assert.deepEqual(await state(), initial);
  await shot('07-district-single-click', { district: districtLabel, clicks: 1, campaignPreserved: true });
  await siteButtons().first().click();
  await page.getByRole('button', { name: 'Close inspection', exact: true }).waitFor();
  const order = page.getByRole('button', { name: /^(?:Queue squad visit|Keep visit queued|Choose destination)$/ }).first();
  await inside(order, 'Explicit building order');
  assert.match(await text(), /Queue a visit for the selected squad\. The visit starts when you advance the day\./,
    'Building inspection must explain that queueing an order defers its execution until the day advances.');
  await shot('08-building-inspector-1280x720');
  assert.deepEqual(await state(), initial);
  await page.setViewportSize({ width: 800, height: 700 });
  await page.waitForTimeout(250);
  await inside(order, 'Narrow explicit building order');
  await shot('09-building-inspector-800x700');
  await click('Close inspection');
  const cityCrew = page.getByRole('button', { name: /Inspect .* alongside the city/ }).first();
  await cityCrew.click();
  await page.getByRole('button', { name: 'Close crew inspection', exact: true }).waitFor();
  assert.equal(await page.getByRole('dialog').count(), 0);
  await inside(page.getByRole('button', { name: 'Close crew inspection', exact: true }), 'Narrow crew inspector close');
  await shot('10-city-crew-nonmodal-800x700');
  // Switching view remains available with the inspector open; no blocking overlay.
  await click('Locations list');
  assert.match(await text(), /Close crew inspection/);
  await shot('11-city-list-with-inspector-800x700', { mapControlsRemainUsable: true });
  await click('City streets');
  await click('Close crew inspection');
  await click('Media');
  await wait(/Media Overview/);
  assert.deepEqual(await state(), initial);
  await shot('12-operations-direct-media-preserved');
  await click('Headquarters');
  await wait(/DAILY BRIEFING/);
  assert.deepEqual(await state(), initial);
  await shot('13-returned-campaign-preserved');
  assert.deepEqual(report.pageErrors, []);
  assert.deepEqual(report.consoleErrors, []);
  report.status = 'passed';
} catch (error) {
  report.status = 'failed'; report.error = error.stack ?? String(error); process.exitCode = 1;
  try { await shot('FAILURE'); } catch {}
} finally {
  await context.close();
  report.video = await page.video()?.path();
  report.completed = new Date().toISOString();
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ output, ...report }, null, 2));
}
