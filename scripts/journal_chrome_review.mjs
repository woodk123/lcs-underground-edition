// Secondary-browser compatibility review. Real UI and save exports only.
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
const expectedHash = args.includes('--expected-hash')
  ? args[args.indexOf('--expected-hash') + 1]
  : 'dbc3f95b0ac5cd4e68764def55281363787f0cb0960be77dac31e188b6bf4296';
assert.match(expectedHash, /^[a-f0-9]{64}$/, 'Supply the exact approved compiled runtime SHA256.');
const stamp = new Date().toISOString().replaceAll(':', '-').replaceAll('.', '-');
const output = resolve(root, `reports/browser/chrome-final-${stamp}`);
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
  scope: 'Secondary installed-Chrome compatibility on the frozen compiled runtime. Real unchanged-fixture import, journal interaction, original order mutation, persistence and browser-isolated offline cache; not a replacement for packaged-server acceptance.',
  expectedHash, originalFixtureHash, originalCrew: crew.map(p => ({ id: p.id, name: p.name })),
  checks: [], screenshots: [], exports: [], keyboard: [], findings: [], pageErrors: [], consoleErrors: [], failedRequests: [],
};
let context, page;
let shotNumber = 0;
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
async function tabTo(pattern) {
  const target = typeof pattern === 'string' ? new RegExp(escape(pattern)) : pattern;
  for (let step = 0; step < 90; step++) {
    const focused = await page.evaluate(() => ({
      label: document.activeElement?.getAttribute('aria-label') ?? document.activeElement?.textContent?.trim() ?? '',
      role: document.activeElement?.getAttribute('role') ?? document.activeElement?.tagName ?? '',
    }));
    if (target.test(focused.label)) { report.keyboard.push({ target: String(pattern), tabSteps: step, focused }); return; }
    await page.keyboard.press('Tab'); await page.waitForTimeout(65);
  }
  throw new Error(`Keyboard Tab did not reach ${pattern}.`);
}
async function inside(item, label) {
  const bounds = await item.boundingBox(), size = page.viewportSize();
  assert.ok(bounds && bounds.x >= -1 && bounds.y >= -1 && bounds.x + bounds.width <= size.width + 1 && bounds.y + bounds.height <= size.height + 1,
    `${label} must fit ${size.width}x${size.height}: ${JSON.stringify(bounds)}`);
  return bounds;
}
async function state() {
  const match = (await text()).match(/(\d{1,2} (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d{4})\s*[·•]\s*\$([\d,]+)/);
  assert.ok(match, 'Campaign date and funds must remain visible together.');
  return { date: match[1], funds: Number(match[2].replaceAll(',', '')) };
}
async function shot(name, details = {}) {
  await page.mouse.move(2, 2); await page.waitForTimeout(180);
  const base = `${String(++shotNumber).padStart(2, '0')}-${name}`;
  const pixels = await page.screenshot({ path: resolve(output, `${base}.png`), fullPage: true });
  const raster = { width: pixels.readUInt32BE(16), height: pixels.readUInt32BE(20) };
  await writeFile(resolve(output, `${base}.txt`), await text());
  report.screenshots.push(`${base}.png`);
  report.checks.push({ name, status: name === 'FAILURE' ? 'failed' : 'passed', viewport: page.viewportSize(), raster, ...details });
  if (name !== 'FAILURE') assert.deepEqual(raster, page.viewportSize(), 'No hidden document overflow or blank capture borders.');
  const outcome = name === 'FAILURE' ? 'FAIL' : String(details.status ?? '').startsWith('failed') ? 'FINDING' : 'PASS';
  console.log(`${outcome} ${name}`);
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
async function cacheState() {
  return page.evaluate(async expected => {
    const names = await caches.keys();
    for (const name of names) {
      const cache = await caches.open(name), cached = await cache.match(new URL('main.dart.js', location.href).href);
      if (!cached) continue;
      const digest = [...new Uint8Array(await crypto.subtle.digest('SHA-256', await cached.arrayBuffer()))].map(v => v.toString(16).padStart(2, '0')).join('');
      if (digest === expected) return { names, cachedMainSha256: digest, entries: (await cache.keys()).length, controlled: Boolean(navigator.serviceWorker.controller) };
    }
    return { names, cachedMainSha256: null };
  }, expectedHash);
}

try {
  report.mainJsSha256 = await servedHash(); assert.equal(report.mainJsSha256, expectedHash);
  assert.equal(hash(await readFile(resolve(root, 'upstream/build/web/main.dart.js'))), expectedHash);
  await launch(); await wait(/Start a new movement|Start a New Game/); await shot('chrome-title');
  const chooser = page.waitForEvent('filechooser'); await click('Import a Save'); await (await chooser).setFiles(fixture);
  await wait(/Save imported/); await press('Enter'); await wait(/Start a new movement|Start a New Game/);
  await click('Load & Manage Saves'); await click(/^A(?:\s|$)/); await wait(/Manage .*Saved Game/);
  await click(/^L Load Game/); await journal();
  const initial = await state(); assert.deepEqual(initial, { date: '4 Jan 2023', funds: 7 });
  report.initialCampaign = initial;
  const baseline = await exportSave('01-baseline');

  for (const [width, height] of [[1280, 720], [800, 600], [1600, 1000]]) {
    await page.setViewportSize({ width, height }); await page.waitForTimeout(300); await journal();
    const rosterBounds = [];
    for (const member of crew) rosterBounds.push(await inside(await button(`Select crew ${member.name}`, 'left'), `Crew row ${member.name}`));
    await shot(`chrome-organisation-${width}x${height}`, { rosterBounds });
    const squad = await button(/Select squad The Liberal Crime Squad(?:$|\s)/);
    assert.ok((await squad.boundingBox()).x < 90);
    await squad.click(); await page.waitForTimeout(250);
    assert.doesNotMatch(await text(), /Available crew|Assemble the squad|Drag crew between these pages/);
    await selectCrew(crew[0].name); await click(`Inspect ${crew[0].name}`, 'left');
    assert.equal(await page.getByRole('dialog').count(), 0);
    await inside(await button('Close crew inspection'), 'Nonmodal inspection close');
    await shot(`chrome-inline-dossier-${width}x${height}`);
    await top('Newspaper'); await top('Organisation');
    assert.equal(await page.getByRole('button', { name: 'Close crew inspection', exact: true }).count(), 0);
    await ordersFor(crew[0].name); await prepareDonations();
    await shot(`chrome-prepared-order-${width}x${height}`);
    await cancelPrepared(); await top('Organisation'); assert.deepEqual(await state(), initial);
  }
  await page.setViewportSize({ width: 1280, height: 720 });
  await ordersFor(crew[0].name);
  for (const group of ['Personnel', 'Activism', 'Business']) await click(group, 'left');
  await prepareDonations(); await cancelPrepared(); await top('Organisation');
  const cancelled = await exportSave('02-cancelled-preview');
  assert.deepEqual(cancelled, baseline, 'Category browsing and cancellation must preserve complete serialized state.');
  await shot('chrome-preview-cancel-save-identical');

  await ordersFor(crew[0].name); await prepareDonations();
  await tabTo(`Select crew ${crew[1].name}`); await press('Space');
  await inside(await button(`Inspect ${crew[1].name}`, 'left'), 'Native Tab/Space-selected actor');
  const confirms = page.getByRole('button', { name: 'Confirm order', exact: true });
  assert.ok(!(await confirms.count()) || !(await confirms.first().isEnabled()));
  await click('Business', 'left'); await prepareDonations();
  await shot('chrome-keyboard-selected-actor-prepared');
  await tabTo(/^Confirm order(?:$|\s)/); await press('Enter');
  await top('Organisation');
  const committed = await exportSave('03-confirmed-personal-order');
  const expectedCommit = structuredClone(baseline);
  expectedCommit.lcs.pool.find(p => p.id === crew[1].id).activity = committed.lcs.pool.find(p => p.id === crew[1].id).activity;
  assert.equal(committed.lcs.pool.find(p => p.id === crew[1].id).activity.type, 'donations');
  assert.deepEqual(committed, expectedCommit, 'Confirm must change exactly the selected original actor activity.');
  await shot('chrome-confirm-exact-actor-save-proof');

  for (const section of ['Ledger', 'Agenda']) {
    await top(section); await journal();
    const content = await text();
    assert.doesNotMatch(content, /\$null|AVAILABLE CHOICES/);
    assert.match(content, section === 'Ledger' ? /Financial ledger|Funding Report|Income|Expenses|Balance/i : /Liberal Agenda|Agenda|Public Opinion/);
    await shot(`chrome-${section.toLowerCase()}-readable`);
    await click(section === 'Ledger' ? 'Back to organisation' : /^Back(?:$|\s)/);
    await journal(); await button(`Select crew ${crew[0].name}`, 'left');
    await shot(`chrome-${section.toLowerCase()}-source-back`);
    await top(section); await journal();
    await top('Organisation'); await journal();
    assert.deepEqual(await state(), initial);
    await shot(`chrome-${section.toLowerCase()}-one-click-return`);
  }
  await top('Options'); await click('150%'); await top('Organisation');
  for (const [width, height] of [[1280, 720], [800, 600]]) {
    await page.setViewportSize({ width, height }); await page.waitForTimeout(300); await journal();
    await ordersFor(crew[0].name);
    const timingExplained = await prepareDonations({ requireTiming: false });
    await inside(await button('Cancel prepared order', 'left'), '150% cancellation');
    if (!timingExplained) report.findings.push({
      severity: 'readability', viewport: { width, height }, readingPercent: 150,
      issue: 'Prepared job card retains activity, status and Confirm/Cancel, but no execution-timing or mechanics disclosure appears in this compact layout.',
      runtime: expectedHash,
    });
    await shot(`chrome-reading-150-${width}x${height}`, { timingExplained, status: timingExplained ? 'passed' : 'failed-readability' });
    await cancelPrepared(); await top('Organisation');
  }
  await top('Options'); await click('100%'); await top('Organisation');
  await page.setViewportSize({ width: 1280, height: 720 });
  assert.deepEqual(await exportSave('04-readonly-navigation'), committed);

  await click('Save & exit', 'footer'); await wait(/Continue (?:your campaign|Last Game|as )/);
  await context.close(); context = null;
  await launch(); await wait(/Continue (?:your campaign|Last Game|as )/);
  await click(/^Continue (?:your campaign|Last Game|as )/i); await journal();
  assert.deepEqual(await exportSave('05-browser-process-restart'), committed);
  report.restartVerified = true; await shot('chrome-browser-restart-continue');
  await click('Save & exit', 'footer'); await wait(/Continue (?:your campaign|Last Game|as )/);
  const cacheDeadline = Date.now() + 45000;
  do { report.cache = await cacheState(); if (report.cache.controlled && report.cache.cachedMainSha256 === expectedHash) break; await page.waitForTimeout(200); } while (Date.now() < cacheDeadline);
  assert.equal(report.cache.cachedMainSha256, expectedHash); assert.ok(report.cache.controlled && report.cache.entries > 20);
  offlinePhase = true; await context.setOffline(true);
  await page.reload({ waitUntil: 'domcontentloaded' }); await wait(/Continue (?:your campaign|Last Game|as )/);
  await click(/^Continue (?:your campaign|Last Game|as )/i); await journal();
  await ordersFor(crew[1].name); await prepareDonations(); await cancelPrepared(); await top('Organisation');
  assert.deepEqual(await state(), initial); await shot('chrome-offline-cached-continue-and-orders');
  assert.deepEqual(await exportSave('06-offline-unchanged-order'), committed);
  await context.setOffline(false); offlinePhase = false;
  report.offlineVerified = 'Chrome browser networking disabled only; server 8765 deliberately left running. Real cached reload, Continue, order preview/cancel and exact exported save verified.';
  report.finalServedHash = await servedHash(); assert.equal(report.finalServedHash, expectedHash);
  report.finalFixtureHash = hash(await readFile(fixture)); assert.equal(report.finalFixtureHash, originalFixtureHash);
  assert.deepEqual(report.pageErrors, []); assert.deepEqual(report.consoleErrors, []); assert.deepEqual(report.failedRequests, []);
  report.status = report.findings.length ? 'completed-with-findings' : 'passed';
  if (report.findings.length) process.exitCode = 1;
} catch (error) {
  report.status = 'failed'; report.error = error.stack ?? String(error); process.exitCode = 1;
  try { await shot('FAILURE'); } catch {}
  try { await writeFile(resolve(output, 'FAILURE-semantics.html'), await page.locator('flt-semantics-host').innerHTML()); } catch {}
  console.error(report.error);
} finally {
  try { if (context) await context.close(); } catch {}
  report.completed = new Date().toISOString();
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  const summary = [
    `Chrome compatibility review: **${report.status}**. Installed Chrome ${report.browserVersion ?? 'unavailable'}, headless, with a new isolated profile.`,
    `Runtime SHA256: \`${expectedHash}\`. Served, local and cache equality are asserted by the script. Fixture bytes and server 8765 are preserved.`,
    `${report.checks.length} captured checkpoints; ${report.exports.length} real campaign exports; ${report.pageErrors.length} page errors; ${report.consoleErrors.length} console errors; ${report.failedRequests.length} failed requests.`,
    'The review uses actual file import, crew/squad controls, native Tab/Space/Enter, group/task prepare/cancel/Confirm, canonical save equality, Ledger/Agenda source Back and section tabs, 150% reading, isolated browser restart/Continue, and browser-isolated offline cache. It does not stop the server or replace packaged-server acceptance.',
    report.findings.length ? report.findings.map(item => `Finding: ${item.issue} (${item.viewport.width}×${item.viewport.height}, ${item.readingPercent}% reading).`).join('\n\n') : 'No readability finding was recorded.',
    report.error ? `Failure: \`${report.error.split('\n')[0]}\`` : '',
    '[Machine-readable report and screenshot index](report.json). Actual exported campaigns are retained alongside this report.',
  ].filter(Boolean).join('\n\n');
  await writeFile(resolve(output, 'review.md'), `${summary}\n`);
  console.log(JSON.stringify({ output, status: report.status, checks: report.checks.length, mainJsSha256: report.mainJsSha256 }, null, 2));
}
