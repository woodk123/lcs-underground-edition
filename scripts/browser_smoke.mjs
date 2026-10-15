// Real browser-only acceptance scenario. No Dart/engine internals or test hooks.
// Center-content commands are checked as visible controls in the workspace,
// independently of the sidebar navigation and classic compatibility screens.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const { PNG } = require('pngjs');
const args = process.argv.slice(2);
const argument = (flag, fallback) => args.includes(flag) ? args[args.indexOf(flag) + 1] : fallback;
const url = argument('--url', 'http://127.0.0.1:8765/');
const stamp = new Date().toISOString().replaceAll(':', '-').replaceAll('.', '-');
const output = resolve(root, argument('--out', `reports/browser/smoke-${stamp}`));
await mkdir(output, { recursive: true });
const report = { started: new Date().toISOString(), url, browser: 'Microsoft Edge', channel: 'msedge', viewport: { width: 1440, height: 1000 }, checks: [], skipped: [], screenshots: [], pageErrors: [], consoleErrors: [], failedRequests: [], status: 'running' };
const mainJs = await fetch(new URL('main.dart.js', url));
assert.ok(mainJs.ok, 'The supplied server must serve a compiled game.');
report.mainJsSha256 = createHash('sha256').update(Buffer.from(await mainJs.arrayBuffer())).digest('hex');
const profile = resolve(root, '.local/browser-profiles', stamp);
await mkdir(profile, { recursive: true });
let context = await chromium.launchPersistentContext(profile, { channel: 'msedge', headless: true, viewport: report.viewport });
let browser = context.browser();
assert.ok(browser, 'A real isolated browser process is required.');
report.browserVersion = browser.version();
let page;
let checkpointNumber = 0;

function attach(target) {
  target.on('pageerror', error => report.pageErrors.push(error.stack ?? error.message));
  target.on('console', message => { if (message.type() === 'error') report.consoleErrors.push(message.text()); });
  target.on('requestfailed', request => report.failedRequests.push({ url: request.url(), failure: request.failure()?.errorText }));
}

// Flutter exposes some text in aria-labels and SelectableText in disabled textareas.
// These are DOM accessibility values, not a read of application state.
async function uiText() {
  return page.locator('flt-semantics-host').evaluate(host => {
    const text = [host.innerText];
    for (const node of host.querySelectorAll('[aria-label]')) text.push(node.getAttribute('aria-label'));
    for (const node of host.querySelectorAll('[aria-valuetext]')) text.push(node.getAttribute('aria-valuetext'));
    for (const node of host.querySelectorAll('input, textarea')) text.push(node.value);
    return text.filter(Boolean).join('\n');
  });
}

async function waitText(pattern, timeout = 12000) {
  const deadline = Date.now() + timeout;
  let text = '';
  while (Date.now() < deadline) {
    if (await page.locator('flt-semantics-host').count()) {
      text = await uiText();
      if (pattern.test(text)) return text;
    }
    await page.waitForTimeout(100);
  }
  throw new Error(`UI did not show ${pattern} within ${timeout}ms.\n${text}`);
}

async function checkpoint(name, detail = {}) {
  await page.waitForTimeout(120);
  const prefix = `${String(++checkpointNumber).padStart(2, '0')}-${name}`;
  const text = await uiText();
  await page.screenshot({ path: resolve(output, `${prefix}.png`), fullPage: true });
  await writeFile(resolve(output, `${prefix}.txt`), text);
  report.screenshots.push(`${prefix}.png`);
  report.checks.push({ name, status: 'passed', ...detail });
  console.log(`PASS ${name}`);
  return text;
}

async function click(name) {
  await page.getByRole('button', { name, exact: typeof name === 'string' }).first().click();
  await page.waitForTimeout(120);
}

async function centerClick(name) {
  assert.doesNotMatch(await uiText(), /AVAILABLE CHOICES/, 'Modern content must not use the old right-hand choice panel.');
  const button = page.getByRole('button', { name, exact: typeof name === 'string' }).first();
  await button.scrollIntoViewIfNeeded();
  const box = await button.boundingBox();
  const viewport = page.viewportSize();
  assert.ok(box && box.x >= (viewport.width < 900 ? 0 : 180) && box.x + box.width <= viewport.width + 1,
    `The ${name} command must be a directly clickable center-content control.`);
  report.centerActions ??= [];
  report.centerActions.push({ name: String(name), bounds: box, accessibleLabel: await button.getAttribute('aria-label') });
  await button.click();
  await page.waitForTimeout(150);
}

async function press(key) {
  await page.keyboard.press(key);
  await page.waitForTimeout(120);
}

async function headquarters() {
  await waitText(/DAILY BRIEFING/);
  await page.getByRole('button', { name: 'Save & exit', exact: true }).first().waitFor();
  await page.getByRole('button', { name: 'Daily assignments', exact: true }).first().waitFor({ state: 'visible' });
}

async function visibleCampaignState() {
  const header = await page.locator('flt-semantics-host').evaluate(host => [...host.querySelectorAll('[aria-label]')]
    .map(node => node.getAttribute('aria-label')).filter(Boolean).join('\n')
    .match(/(?:LIBERAL CRIME SQUAD|LCS)\n\d{1,2} (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d{4}\n\$[\d,]+/)?.[0] ?? '');
  const text = await uiText();
  const state = { date: dateIn(header), funds: fundsIn(header), order: text.match(/Current order: ([^\n]+)/)?.[1] ?? null };
  assert.ok(state.date && Number.isFinite(state.funds), 'Campaign inspection requires an actual visible date and funds.');
  return state;
}

async function inspectDossier(buttonName, phase, expectedBlood = null) {
  const before = await visibleCampaignState();
  await click(buttonName);
  await page.getByRole('button', { name: 'Close crew inspection', exact: true }).first().waitFor();
  assert.equal(await page.getByRole('dialog').count(), 0, 'Everyday crew inspection must remain alongside the current workspace.');
  await checkpoint(`crew-inspector-${phase}-nonmodal`);
  const duringInspection = await visibleCampaignState();
  assert.deepEqual({ date: duringInspection.date, funds: duringInspection.funds }, { date: before.date, funds: before.funds },
    'Opening inline inspection must preserve the visible date and funds. The same order is checked again after its local inspector closes.');
  await click('Full dossier');
  await page.getByRole('button', { name: /^Close dossier/ }).first().waitFor();
  let dossier = await checkpoint(`crew-dossier-${phase}-overview`);
  assert.match(dossier, /QA Founder/);
  assert.match(dossier, /Current orders|Personal assignment/);
  const blood = dossier.match(/Blood\s+(\d+)\s*\/\s*(\d+)/);
  if (expectedBlood) {
    assert.ok(blood, 'The actual dossier must expose its factual blood record.');
    assert.deepEqual(blood.slice(1), expectedBlood, 'Dossier blood must match the visible HQ record.');
  }
  await click('Skills');
  await checkpoint(`crew-dossier-${phase}-skills`);
  await click('Campaign record');
  await checkpoint(`crew-dossier-${phase}-record`);
  await click('Close dossier');
  await click('Close crew inspection');
  await page.waitForTimeout(180);
  assert.deepEqual(await visibleCampaignState(), before, 'Inspecting a dossier must not advance time, cash or the current squad order.');
  report.dossiers ??= [];
  report.dossiers.push({ phase, before, after: await visibleCampaignState(), observedBlood: blood?.slice(1) ?? null });
}

async function inspectPlace(name, phase) {
  const before = await visibleCampaignState();
  await centerClick(new RegExp(`^Inspect ${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?:$| )`));
  await page.getByRole('button', { name: 'Close inspection', exact: true }).waitFor();
  const after = await visibleCampaignState();
  assert.deepEqual(after, before, 'Building inspection must not dispatch an order, advance the day or spend funds.');
  if (phase) await checkpoint(`building-inspected-${phase}`, { name, before, after });
  return page.getByRole('button', { name: /^(?:Enter district|Open city|Queue squad visit|Keep visit queued|Choose destination)$/ }).first();
}

function placeName(label) {
  return label.replace(/^(?:Inspect|Open) /, '').split(/\n| Current location| Order unavailable/)[0].trim();
}

async function choosePlace(name, phase) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const area = page.getByRole('button', { name: new RegExp(`^Open ${escaped}(?:$| )`) }).first();
  if (await area.count()) {
    const before = await visibleCampaignState();
    await centerClick(new RegExp(`^Open ${escaped}(?:$| )`));
    assert.deepEqual(await visibleCampaignState(), before, 'Opening a district must preserve orders, cash and time.');
    assert.equal(await page.getByRole('button', { name: 'Enter district', exact: true }).count(), 0, 'District navigation must not require a second confirmation.');
    if (phase) await checkpoint(`area-opened-${phase}`, { name, before, after: await visibleCampaignState(), clicks: 1 });
    return true;
  }
  const order = await inspectPlace(name, phase);
  if (!(await order.isEnabled())) return false;
  await centerClick(await order.innerText());
  return true;
}

function rasterDifference(first, second) {
  assert.equal(first.width, second.width); assert.equal(first.height, second.height);
  let changedPixels = 0;
  for (let i = 0; i < first.data.length; i += 4) {
    if (Math.abs(first.data[i] - second.data[i]) + Math.abs(first.data[i + 1] - second.data[i + 1]) + Math.abs(first.data[i + 2] - second.data[i + 2]) > 12) changedPixels++;
  }
  return changedPixels;
}

async function inspectCityAnimation() {
  const before = await visibleCampaignState();
  const fit = page.getByRole('button', { name: /^Fit city/ }).first();
  await fit.scrollIntoViewIfNeeded();
  for (let i = 0; i < 5 && (await fit.boundingBox()).y > 380; i++) {
    await page.mouse.move(1360, 570); await page.mouse.wheel(0, 260); await page.waitForTimeout(120);
  }
  await fit.click(); await page.mouse.move(20, 20); await page.waitForTimeout(650);
  await observeFrames('city-streets');
  const box = await fit.boundingBox();
  const clip = { x: 245, y: Math.ceil(box.y + box.height + 8), width: Math.floor(box.x + box.width + 10 - 245), height: Math.min(500, Math.floor(page.viewportSize().height - box.y - box.height - 50)) };
  assert.ok(clip.width > 250 && clip.height > 240, 'The actual street scene must be visible for animation inspection.');
  const animationDir = resolve(output, 'city-animation'); await mkdir(animationDir, { recursive: true });
  const frames = [];
  const videoFrames = [];
  const sampleTimes = [];
  for (let i = 0; i < 24; i++) {
    const bytes = await page.screenshot({ path: resolve(animationDir, `frame-${String(i).padStart(2, '0')}.png`), clip });
    frames.push(PNG.sync.read(bytes));
    videoFrames.push(await page.screenshot({ type: 'jpeg', quality: 88, clip }));
    sampleTimes.push(Date.now()); await page.waitForTimeout(85);
  }
  const uniqueFrames = new Set(frames.map(frame => createHash('sha256').update(frame.data).digest('hex'))).size;
  const changedPixels = Math.max(...frames.slice(1).map(frame => rasterDifference(frames[0], frame)));
  assert.ok(uniqueFrames >= 8 && changedPixels > 10, 'All eight generated pedestrian frames must be observable in the rendered street scene.');
  await page.emulateMedia({ reducedMotion: 'reduce' }); await page.mouse.move(20, 20); await page.waitForTimeout(700);
  const reducedA = PNG.sync.read(await page.screenshot({ path: resolve(animationDir, 'reduced-motion-a.png'), clip }));
  await page.waitForTimeout(237);
  const reducedB = PNG.sync.read(await page.screenshot({ path: resolve(animationDir, 'reduced-motion-b.png'), clip }));
  const reducedChanges = rasterDifference(reducedA, reducedB);
  assert.equal(reducedChanges, 0, 'Reduced-motion preference must stop the decorative pedestrian animation.');
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  assert.deepEqual(await visibleCampaignState(), before, 'Decorative sprite playback and reduced-motion changes must not affect the campaign.');
  const resources = await page.evaluate(() => performance.getEntriesByType('resource').map(entry => entry.name));
  assert.ok(resources.some(name => name.includes('building_sprites_v2.png')) && resources.some(name => name.includes('pedestrian_walk_v2.png')), 'The actual generated building and walking atlases must load in the browser.');
  const ffmpeg = resolve(process.env.LOCALAPPDATA, 'ms-playwright/ffmpeg-1013/ffmpeg-win64.exe');
  const sampledFps = (sampleTimes.length - 1) * 1000 / (sampleTimes.at(-1) - sampleTimes[0]);
  execFileSync(ffmpeg, ['-y', '-f', 'image2pipe', '-c:v', 'mjpeg', '-r', sampledFps.toFixed(4), '-i', 'pipe:0', '-vf', 'pad=ceil(iw/2)*2:ceil(ih/2)*2', '-c:v', 'libvpx-vp9', '-pix_fmt', 'yuv420p', '-an', 'city-animation.webm'], { cwd: animationDir, windowsHide: true, input: Buffer.concat(videoFrames), stdio: 'pipe' });
  report.cityAnimation = { clip, screenshots: frames.length, sampleTimes, uniqueRasterFrames: uniqueFrames, maximumChangedPixels: changedPixels, reducedMotionChangedPixels: reducedChanges, generatedEightFrameSheet: 'assets/modern/pedestrian_walk_v2.png', video: 'city-animation/city-animation.webm', sampledFps, videoMethod: 'Actual browser JPEG captures encoded at their measured average sample rate; timestamps and PNG evidence retained.' };
  await checkpoint('city-animation-verified', report.cityAnimation);
}

function dateIn(text) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const compact = text.match(/\b(\d{1,2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{4})\b/);
  const full = text.match(/\b(January|February|March|April|May|June|July|August|September|October|November|December) (\d{1,2}), (\d{4})\b/);
  if (compact) return `${compact[3]}-${String(months.indexOf(compact[2]) + 1).padStart(2, '0')}-${compact[1].padStart(2, '0')}`;
  if (full) return `${full[3]}-${String(months.indexOf(full[1].slice(0, 3)) + 1).padStart(2, '0')}-${full[2].padStart(2, '0')}`;
  return undefined;
}

function fundsIn(text) {
  return Number(text.match(/\$([\d,]+)/)?.[1]?.replaceAll(',', ''));
}

async function returnToHeadquarters() {
  for (let i = 0; i < 8; i++) {
    if ((await uiText()).includes('DAILY BRIEFING')) return headquarters();
    await press('Escape');
  }
  throw new Error('Could not return to headquarters using the original cancel/back input.');
}

async function settleTactical(name) {
  // Movement can yield an ordinary narrative/encounter message before the next map frame.
  for (let i = 0; i < 15; i++) {
    await page.waitForTimeout(250);
    const text = await uiText();
    if (text.includes('TACTICAL VIEW') && await page.getByRole('button', { name: /^Move up/ }).count()) return;
    const proceed = page.getByRole('button', { name: /^Continue(?: →)?$/ });
    if (await proceed.count() && await proceed.isEnabled()) {
      if (i < 4) await checkpoint(`${name}-message-${i + 1}`);
      await click(/^Continue(?: →)?$/);
    }
  }
  throw new Error(`The ${name} command did not settle at a tactical input state.\n${await uiText()}`);
}

async function inspectActualArticle(phase) {
  const rows = page.getByRole('button', { name: /^[A-Q] (?:- )?[^\[\]]/ });
  if (!(await rows.count())) {
    report.newsArticle ??= { status: 'not_available', reason: 'The actual campaign news archive had no selectable story in the inspected state.', phases: [] };
    report.newsArticle.phases?.push(phase);
    return;
  }
  const article = rows.first();
  const label = await article.innerText();
  await centerClick(label);
  const text = await checkpoint(`news-article-${phase}`, { selectedArchiveLabel: label });
  assert.doesNotMatch(text, /AVAILABLE CHOICES|Press a Letter to read a news article/);
  await page.mouse.move(800, 520);
  await page.mouse.wheel(0, 520);
  await checkpoint(`news-article-${phase}-scrolled`);
  report.newsArticle = { status: 'opened_actual_archive_story', phase, selectedArchiveLabel: label, visibleSemanticTextLength: text.length };
  await click(/^Continue(?: →)?$/);
  await waitText(/Media Overview/);
}

async function observeFrames(state) {
  await page.bringToFront();
  const observation = await page.evaluate(() => new Promise(resolve => {
    const intervals = [];
    let previous;
    let finished = false;
    const finish = timedOut => {
      if (finished) return;
      finished = true;
      const sorted = [...intervals].sort((a, b) => a - b);
      const percentile = q => sorted.length ? sorted[Math.floor((sorted.length - 1) * q)] : null;
      resolve({ samples: intervals.length, timedOut, visibility: document.visibilityState, p50_ms: percentile(.5), p95_ms: percentile(.95), max_ms: sorted.at(-1) ?? null,
        jsHeap: performance.memory ? { used_bytes: performance.memory.usedJSHeapSize, total_bytes: performance.memory.totalJSHeapSize, limit_bytes: performance.memory.jsHeapSizeLimit } : null });
    };
    const timer = setTimeout(() => finish(true), 8000);
    const frame = time => {
      if (finished) return;
      if (previous !== undefined) intervals.push(time - previous);
      previous = time;
      if (intervals.length >= 120) { clearTimeout(timer); finish(false); } else requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  }));
  report.performanceObservations ??= [];
  report.performanceObservations.push({ state, scope: 'Warm headless Edge frame-delivery and JS heap observation; not a physical GPU or large-campaign benchmark.', ...observation });
  console.log(`OBSERVED ${state}: ${observation.samples} frames, p50=${observation.p50_ms}, p95=${observation.p95_ms}, max=${observation.max_ms}ms`);
}

try {
  page = await context.newPage();
  attach(page);
  await page.goto(url, { waitUntil: 'networkidle' });
  await waitText(/Start a new movement/);
  await checkpoint('title-1440');
  async function tabTo(label) {
    for (let i = 0; i < 16; i++) {
      await press('Tab');
      const focused = await page.evaluate(() => document.activeElement?.getAttribute('aria-label') ?? document.activeElement?.textContent?.trim());
      if (focused === label) return;
    }
    throw new Error(`Keyboard Tab traversal did not focus ${label}.`);
  }
  if (args.includes('--skip-keyboard')) {
    report.skipped.push('Tab/Enter activation (explicit exploratory flag; not a final acceptance run)');
    await click('Start a new movement');
  } else {
    await tabTo('Field guide');
    await press('Enter');
    await waitText(/A small movement\. A long game\./);
    await checkpoint('keyboard-tab-enter-guide');
    await press('Escape');
    await waitText(/Start a new movement/);
    await tabTo('Start a new movement');
    await checkpoint('keyboard-new-game-focused');
    await press('Enter');
  }
  await waitText(/Starting Political Climate/);
  await checkpoint('difficulty-choices');
  await press('Enter');
  await waitText(/toggle choice or fate/);
  await press('d'); // The original game's random-origin option; no engine hooks.
  await checkpoint('founder-random-origin');
  await press('Enter');

  const entry = page.locator('input:not([disabled]):not([readonly])');
  let originMessages = 0;
  while (!(await entry.count()) && originMessages < 30) {
    await press('Enter');
    originMessages++;
  }
  assert.equal(await entry.count(), 1, 'The name prompt must expose exactly one real editable input.');
  await waitText(/What is your name to the people/);
  await checkpoint('founder-name-prompt', { originMessages });
  await entry.fill('QA Founder');
  await click('Confirm text');
  await headquarters();
  let text = await checkpoint('headquarters-created');
  assert.match(text, /QA Founder/);
  const startDate = dateIn(text);
  const startFunds = fundsIn(text);
  assert.ok(startDate && Number.isFinite(startFunds), 'HQ must expose a real campaign date and funds.');
  const founderBlood = text.match(/(\d+)\/(\d+) blood/)?.slice(1) ?? null;
  await page.getByRole('button', { name: /^Inspect QA Founder(?: |$)/ }).scrollIntoViewIfNeeded();
  await checkpoint('hq-crew-portrait');
  await inspectDossier(/^Inspect QA Founder(?: |$)/, 'headquarters', founderBlood);
  for (const [width, height] of [[1280, 720], [1600, 900], [1920, 1080]]) {
    await page.setViewportSize({ width, height });
    await checkpoint(`headquarters-${width}x${height}`);
    assert.equal(dateIn(await uiText()), startDate, 'Resizing must not advance the campaign.');
  }
  await page.setViewportSize(report.viewport);
  await observeFrames('headquarters');

  await click('Daily assignments');
  await page.getByRole('button', { name: /^A QA Founder(?: |$)/ }).waitFor();
  await checkpoint('direct-people-table');
  await inspectDossier(/^Inspect QA Founder dossier/, 'assignment-row', founderBlood);
  await centerClick(/^A QA Founder(?: |$)/);
  await checkpoint('direct-activity-categories');
  await centerClick(/^B Legal Fundraising(?: |$)/);
  await waitText(/Solicit Donations/);
  await checkpoint('legal-fundraising-options');
  await centerClick(/^1 Solicit Donations(?: |$)/);
  text = await checkpoint('direct-fundraising-selected');
  assert.match(text, /Runs when you advance the day|advance the day/i, 'Selected activities must explain when they resolve.');
  assert.match(text, /Persuasion|Street Smarts|Charisma|Heart/, 'Fundraising must expose source-backed skill or attribute factors.');
  const nestedState = await visibleCampaignState();
  await click('Media & impact');
  await waitText(/Media Overview/);
  assert.deepEqual(await visibleCampaignState(), nestedState, 'Direct navigation from a nested assignment must preserve cash, time and current squad orders.');
  await checkpoint('nested-assignment-direct-to-media', { clicks: 1, before: nestedState, after: await visibleCampaignState() });
  await click('Daily assignments');
  await page.getByRole('button', { name: /^A QA Founder(?: |$)/ }).waitFor();
  await centerClick(/^A QA Founder(?: |$)/);
  await waitText(/Soliciting Donations/);
  await checkpoint('assignment-preserved-after-direct-navigation');
  await centerClick(/^(?:Enter )?Done(?: |$)/);
  await press('Escape');
  await headquarters();
  text = await checkpoint('fundraising-assigned');
  assert.match(text, /Soliciting Donations/);
  assert.equal(dateIn(text), startDate, 'Assigning an activity must not advance time.');

  await click('Wait a day');
  const dailyMessages = [];
  for (let i = 0; i < 25; i++) {
    await page.waitForTimeout(180);
    text = await uiText();
    const waitButton = page.getByRole('button', { name: 'Wait a day', exact: true });
    if (text.includes('DAILY BRIEFING') && await waitButton.count() && await waitButton.isEnabled()) break;
    dailyMessages.push(text);
    if (i < 5) await checkpoint(`daily-result-${i + 1}`);
    await press('Enter');
  }
  await headquarters();
  text = await checkpoint('day-completed', { startDate, startFunds, dailyMessageCount: dailyMessages.length });
  const advancedDate = dateIn(text);
  const advancedFunds = fundsIn(text);
  assert.notEqual(advancedDate, startDate, 'Executing daily assignments must advance the campaign date.');
  assert.ok(advancedFunds >= startFunds, 'Soliciting donations must not reduce funds.');
  report.dailyResult = { startDate, advancedDate, startFunds, advancedFunds, messages: dailyMessages };

  await click('People & squads');
  await waitText(/Review your Liberals and Assemble Squads/);
  await checkpoint('squad-review');
  await click(/^1 Active Liberals/);
  await waitText(/QA Founder/);
  await checkpoint('people-and-squads');
  await returnToHeadquarters();
  assert.equal(dateIn(await uiText()), advancedDate, 'Roster navigation must not advance time.');
  await click('Liberal Agenda');
  await checkpoint('liberal-agenda');
  await returnToHeadquarters();
  await click('Media & impact');
  await checkpoint('media-and-impact');
  await inspectActualArticle('first-review');
  await returnToHeadquarters();

  await click('Operations');
  await waitText(/Open a district directly\. Inspect a building/);
  await checkpoint('operation-districts');
  assert.match(await uiText(), /City streets/);
  assert.match(await uiText(), /Illustrated street plan/);
  await checkpoint('city-building-streets');
  await inspectDossier(/Inspect QA Founder alongside the city/, 'city-crew', founderBlood);
  await page.setViewportSize({ width: 1280, height: 720 });
  await checkpoint('city-streets-1280x720');
  await inspectDossier(/Inspect QA Founder alongside the city/, 'city-crew-1280x720', founderBlood);
  await page.setViewportSize(report.viewport);
  let disabledInspection = false;
  for (const building of await page.getByRole('button', { name: /^Inspect (?!QA Founder(?: |$))/ }).all()) {
    const label = await building.innerText();
    if (/Order unavailable/.test(label)) {
      const name = label.replace(/^Inspect /, '').split(/\n| Current location| Order unavailable/)[0].trim();
      const order = await inspectPlace(name, 'unavailable-order');
      assert.equal(await order.isEnabled(), false);
      assert.match(await uiText(), /unavailable under the conditions|Need Car|Closed Down|Under Siege/);
      disabledInspection = true; break;
    }
  }
  report.disabledBuildingInspection = { status: disabledInspection ? 'verified_actual_unavailable_order' : 'not_present_in_this_actual_starting_city', scope: 'No disabled building was fabricated; widget fixtures cover unavailable orders when the fresh campaign exposes none.' };
  const firstBuilding = page.getByRole('button', { name: /^(?:Open|Inspect) (?!QA Founder)/ }).first();
  const firstName = placeName(await firstBuilding.innerText());
  const initialBuildingBox = await firstBuilding.boundingBox();
  await click('Zoom in');
  const zoomedBuildingBox = await firstBuilding.boundingBox();
  assert.ok(zoomedBuildingBox && initialBuildingBox && zoomedBuildingBox.width > initialBuildingBox.width * 1.15, 'City zoom must enlarge the actual generated building object.');
  await checkpoint('city-building-zoomed');
  await click(/^Fit city/);
  await inspectCityAnimation();
  await centerClick('Locations list');
  text = await checkpoint('city-planning-list');
  assert.doesNotMatch(text, /Illustrated street plan/);
  await centerClick('City streets');
  assert.match(await uiText(), /Illustrated street plan/);
  const district = page.getByRole('button', { name: /^Open (?!dossier|QA Founder)/ });
  let districtChosen = false;
  for (const option of await district.all()) {
    const name = placeName(await option.innerText());
    if (await choosePlace(name, 'district')) { districtChosen = true; break; }
  }
  assert.ok(districtChosen, 'At least one local district must be accessible.');
  await page.waitForTimeout(150);
  await checkpoint('operation-sites');
  const sites = page.getByRole('button', { name: /^Inspect (?!QA Founder(?: |$))/ }).filter({ hasNotText: /Homeless Camp|Different City/ });
  let selectedSite;
  for (const option of await sites.all()) {
    const name = placeName(await option.innerText());
    if (await choosePlace(name, 'site')) { selectedSite = name; break; }
  }
  assert.ok(selectedSite, 'At least one non-home local site must be selectable.');
  await headquarters();
  text = await checkpoint('operation-queued', { selectedSite });
  assert.match(text, /Next day ·/);
  assert.match(text, /\b[1-9]\d* visits? queued\b/);
  assert.match(text, /Visiting/);
  assert.equal(dateIn(text), advancedDate, 'Planning a visit must not execute it or advance time.');
  const queuedState = await visibleCampaignState();
  await click('Operations');
  await waitText(/Open a district directly/);
  await click('Media & impact');
  await waitText(/Media Overview/);
  await click('Headquarters');
  await headquarters();
  text = await checkpoint('queued-visit-preserved-by-direct-navigation', { selectedSite, before: queuedState, after: await visibleCampaignState() });
  assert.deepEqual(await visibleCampaignState(), queuedState, 'Leaving Operations through direct navigation must preserve time, funds and current order.');
  assert.match(text, /\b[1-9]\d* visits? queued\b/);
  assert.ok(text.includes(selectedSite), 'The exact queued destination must remain visible after leaving Operations.');
  await click(/Cancel Departure/);
  await headquarters();
  text = await checkpoint('operation-cancelled');
  assert.match(text, /No visits queued/);
  assert.doesNotMatch(text, /\b[1-9]\d* visits? queued\b/);

  await click('Save & exit');
  await waitText(/Continue your campaign/);
  await checkpoint('saved-to-title');
  await click('Load & Manage Saves');
  await waitText(/Liberal Save Game Management System/);
  await checkpoint('save-management-list');
  await click(/^A(?:\s|$)/);
  await waitText(/Manage .*Saved Game/);
  await checkpoint('save-management-actions');
  const downloadPending = page.waitForEvent('download');
  await click(/Export Save File/);
  const download = await downloadPending;
  const exportedSave = resolve(output, 'exported-campaign.json');
  await download.saveAs(exportedSave);
  const exportedBytes = await readFile(exportedSave);
  assert.ok(exportedBytes.length > 1000, 'An actual campaign must be exported rather than an empty file.');
  report.exportedSave = { filename: download.suggestedFilename(), bytes: exportedBytes.length, sha256: createHash('sha256').update(exportedBytes).digest('hex') };
  await checkpoint('save-exported');
  await press('Escape');
  await press('Escape');
  await waitText(/Continue your campaign/);
  // Close the entire isolated browser, then reopen its own fresh test profile.
  await context.close();
  context = await chromium.launchPersistentContext(profile, { channel: 'msedge', headless: true, viewport: report.viewport });
  browser = context.browser();
  assert.ok(browser);
  page = await context.newPage();
  attach(page);
  await page.goto(url, { waitUntil: 'networkidle' });
  await waitText(/Continue your campaign/);
  await checkpoint('browser-page-reopened');
  await click('Continue your campaign');
  await headquarters();
  text = await checkpoint('campaign-restored');
  assert.match(text, /QA Founder/);
  assert.match(text, /Soliciting Donations/);
  assert.equal(dateIn(text), advancedDate, 'Reload must preserve the advanced campaign date.');
  assert.equal(fundsIn(text), advancedFunds, 'Reload must preserve campaign funds.');
  report.browserProcessRestartVerified = true;

  const originalPage = page;
  const importContext = await browser.newContext({ viewport: report.viewport });
  try {
    page = await importContext.newPage();
    attach(page);
    await page.goto(url, { waitUntil: 'networkidle' });
    await waitText(/Start a new movement/);
    assert.doesNotMatch(await uiText(), /Continue your campaign/, 'Import must start in an empty isolated browser context.');
    const chooseFile = page.waitForEvent('filechooser');
    await click('Import a Save');
    await (await chooseFile).setFiles(exportedSave);
    await waitText(/Save imported successfully|Save imported/);
    await checkpoint('save-import-success');
    await press('Enter');
    await waitText(/Start a new movement/);
    if (await page.getByRole('button', { name: 'Continue your campaign', exact: true }).count()) {
      await click('Continue your campaign');
    } else {
      // A newly imported profile may have no "last played" preference until it is loaded.
      await click('Load & Manage Saves');
      await waitText(/Liberal Save Game Management System/);
      await click(/^A(?:\s|$)/);
      await waitText(/Manage .*Saved Game/);
      await click(/^L Load Game/);
    }
    await headquarters();
    text = await checkpoint('imported-campaign-restored');
    assert.match(text, /QA Founder/);
    assert.match(text, /Soliciting Donations/);
    assert.equal(dateIn(text), advancedDate);
    assert.equal(fundsIn(text), advancedFunds);

    await click('Save & exit');
    await waitText(/Continue your campaign/);
    const chooseCorrupt = page.waitForEvent('filechooser');
    await click('Import a Save');
    await (await chooseCorrupt).setFiles({ name: 'truncated-campaign.json', mimeType: 'application/json', buffer: Buffer.from('{"saveData":') });
    await waitText(/Error importing|Unable to import|could not be imported|Invalid save/i);
    await checkpoint('truncated-import-rejected');
    await press('Enter');
    await waitText(/Continue your campaign/);
    await click('Continue your campaign');
    await headquarters();
    text = await checkpoint('valid-campaign-preserved-after-invalid-import');
    assert.match(text, /QA Founder/);
    assert.equal(dateIn(text), advancedDate);
    assert.equal(fundsIn(text), advancedFunds);
  } finally {
    await importContext.close();
    page = originalPage;
  }

  await page.setViewportSize({ width: 800, height: 600 });
  await checkpoint('headquarters-800x600');
  await click('Reading size');
  await page.getByRole('menuitem', { name: '125%', exact: true }).click();
  await checkpoint('headquarters-800x600-larger-text');
  await click(/^(Field guide|Guide)$/);
  await waitText(/A small movement/);
  await checkpoint('field-guide-800x600');
  await press('Escape');
  await page.setViewportSize({ width: 1440, height: 1000 });
  await checkpoint('headquarters-restored-size');

  // Execute an ordinary public visit through the same engine commands a player uses.
  // A park or cafe avoids deliberately triggering a hostile operation for this smoke.
  await click('Operations');
  await waitText(/Open a district directly\. Inspect a building/);
  const districts = (await page.getByRole('button', { name: /^Open (?!dossier|QA Founder)/ }).allTextContents()).map(placeName);
  const preferred = [...districts].sort((a, b) => Number(/University/.test(b)) - Number(/University/.test(a)));
  let safeSite;
  for (const districtName of preferred) {
    if (/Different City/.test(districtName)) continue;
    if (!(await choosePlace(districtName, 'public-district'))) continue;
    const destinations = page.getByRole('button', { name: /^Inspect .*\b(?:Park|Cafe|Café)\b/ });
    for (const destination of await destinations.all()) {
      const name = (await destination.innerText()).replace(/^Inspect /, '').split(/\n| Current location| Order unavailable/)[0].trim();
      if (await choosePlace(name, 'public-site')) {
        safeSite = name;
        break;
      }
    }
    if (safeSite) break;
    await press('Escape');
  }
  assert.ok(safeSite, 'A public park or cafe must be available for the tactical smoke.');
  await headquarters();
  await checkpoint('public-operation-queued', { safeSite });
  await click('Carry out your plans');
  let arrived = false;
  for (let i = 0; i < 15; i++) {
    await page.waitForTimeout(180);
    text = await uiText();
    if (/has arrived at/.test(text)) { arrived = true; break; }
    assert.doesNotMatch(text, /TACTICAL VIEW/, 'The arrival message must be shown before tactical entry.');
    if (i < 4) await checkpoint(`operation-departure-message-${i + 1}`);
    await press('Enter');
  }
  assert.ok(arrived, 'The original operation arrival message must be reachable.');
  text = await checkpoint('public-site-arrival-message');
  assert.doesNotMatch(text, /DAILY BRIEFING/, 'An asynchronous arrival message must not be hidden by the HQ presentation.');
  await press('Enter');
  await waitText(/TACTICAL VIEW/);
  await checkpoint('tactical-site-entered');
  for (const [width, height] of [[1280, 720], [1600, 900], [1920, 1080]]) {
    await page.setViewportSize({ width, height });
    await checkpoint(`tactical-${width}x${height}`);
    const directions = await Promise.all((await page.getByRole('button', { name: /^Move down/ }).all()).map(button => button.boundingBox()));
    assert.ok(directions.some(direction => direction && direction.y >= 0 && direction.y + direction.height <= height),
      `The tactical pointer movement controls must remain visible at ${width}x${height}.`);
  }
  await page.setViewportSize(report.viewport);
  await observeFrames('tactical');

  await centerClick(/View full map/);
  text = await checkpoint('tactical-full-map-pointer');
  assert.doesNotMatch(text, /TACTICAL VIEW/, 'The full-map subview must not retain main tactical controls.');
  assert.match(text, /Explored areas/);
  assert.match(text, /Zoom to inspect rooms/);
  const mapSquad = page.getByText(/^Squad, column \d+, row \d+$/).first();
  const fitBounds = await mapSquad.boundingBox();
  assert.ok(fitBounds, 'The graphical full map must expose the actual visible squad tile.');
  await click(/^Zoom in/);
  const zoomBounds = await mapSquad.boundingBox();
  assert.ok(zoomBounds && zoomBounds.width > fitBounds.width * 1.2, 'Zoom in must visibly enlarge the rendered map tile.');
  await checkpoint('graphical-full-map-zoomed', { fitBounds, zoomBounds });
  await click('Fit floor');
  const resetBounds = await mapSquad.boundingBox();
  assert.ok(resetBounds && Math.abs(resetBounds.width - fitBounds.width) < 1, 'Fit floor must restore the rendered map scale.');
  await checkpoint('graphical-full-map-fitted', { resetBounds });
  await click('Back to operation');
  await waitText(/TACTICAL VIEW/);
  await centerClick(/Equip squad/);
  text = await checkpoint('tactical-equipment-pointer');
  assert.doesNotMatch(text, /TACTICAL VIEW/, 'Equipment must show its own readable decision screen.');
  await centerClick(/Increase ammo allocation/);
  await page.waitForTimeout(180);
  if (/Choose a Liberal squad member to receive ammo/.test(await uiText())) {
    await centerClick(/^1 .*QA Founder/);
  }
  text = await checkpoint('direct-equipment-ammo-action');
  assert.match(text, /Equip the Squad|Equipment/);
  assert.doesNotMatch(text, /TACTICAL VIEW/);
  for (let i = 0; i < 5 && !(await uiText()).includes('TACTICAL VIEW'); i++) await press('Escape');
  await waitText(/TACTICAL VIEW/);

  const squadCell = async () => {
    const label = (await uiText()).match(/^Squad, column \d+, row \d+$/m)?.[0];
    assert.ok(label, 'The rendered tactical map must expose the visible squad tile.');
    const [, column, row] = label.match(/column (\d+), row (\d+)/);
    return { column: Number(column), row: Number(row), label };
  };
  const entrance = await squadCell();
  const adjacentTile = page.getByRole('button', { name: new RegExp(`, column ${entrance.column}, row ${entrance.row + 1}$`) });
  const tileLabel = await adjacentTile.innerText();
  await adjacentTile.scrollIntoViewIfNeeded();
  await adjacentTile.click();
  await settleTactical('move-down');
  await checkpoint('tactical-adjacent-tile-activated', { tileLabel });
  let moved = await squadCell();
  if (moved.label === entrance.label) {
    // The original rules spend the first movement opening the public entrance door.
    await checkpoint('tactical-door-opened');
    await click(/^Move down/);
    await settleTactical('enter-door');
    moved = await squadCell();
  }
  assert.notDeepEqual(moved, entrance, 'A real pointer movement command must move the squad tile.');
  await checkpoint('tactical-pointer-moved', { from: entrance, to: moved });
  await press('ArrowUp');
  await settleTactical('return-to-entrance');
  assert.deepEqual(await squadCell(), entrance, 'Arrow input must return the squad to its entrance tile.');
  await checkpoint('tactical-keyboard-returned');
  await click('Move up'); // The tile above the entrance is the original map exit.
  for (let i = 0; i < 15; i++) {
    await page.waitForTimeout(150);
    text = await uiText();
    if (text.includes('DAILY BRIEFING')) break;
    if (i < 4) await checkpoint(`site-exit-result-${i + 1}`);
    await press('Enter');
  }
  await headquarters();
  text = await checkpoint('tactical-operation-returned');
  assert.match(text, /QA Founder/);
  assert.doesNotMatch(text, /\b[1-9]\d* visits? queued\b/);
  assert.notEqual(dateIn(text), advancedDate, 'Executing the queued operation must complete its campaign day.');
  report.tacticalResult = { safeSite, entrance, moved, returnedDate: dateIn(text), returnedFunds: fundsIn(text) };

  await click('Save & exit');
  await waitText(/Continue your campaign/);
  await page.waitForFunction(async () => {
    const registration = await navigator.serviceWorker.getRegistration();
    return !!(registration?.active && navigator.serviceWorker.controller);
  }, undefined, { timeout: 60000 });
  report.offlineCache = await page.evaluate(async () => {
    const names = await caches.keys();
    const cachedUrls = (await Promise.all(names.map(async name => (await (await caches.open(name)).keys()).map(request => request.url)))).flat();
    return { names, count: cachedUrls.length, hasMain: cachedUrls.some(url => url.endsWith('/main.dart.js')) };
  });
  assert.ok(report.offlineCache.hasMain && report.offlineCache.count > 20, 'The real offline worker must precache the application.');
  if (args.includes('--stop-server')) {
    const address = new URL(url);
    assert.ok(['localhost', '127.0.0.1'].includes(address.hostname) && address.port !== '8765', 'Only an isolated loopback test server may be stopped.');
    const health = await (await fetch(new URL('__lcs_launcher_health', url))).json();
    assert.equal(health.application, 'lcs-modern-local');
    const suppliedPackage = argument('--package-root', null);
    assert.ok(suppliedPackage, '--stop-server requires the exact extracted --package-root.');
    const packageRoot = resolve(suppliedPackage);
    assert.equal(resolve(health.directory).toLowerCase(), resolve(packageRoot, 'web').toLowerCase(), 'The managed server must serve the exact extracted package.');
    const packageInfo = JSON.parse(await readFile(resolve(packageRoot, 'BUILD_INFO.json'), 'utf8'));
    assert.ok(['LiberalCrimeSquad-NewAge-UndergroundEdition', 'LiberalCrimeSquad2026'].includes(packageInfo.project));
    const packagedMain = await readFile(resolve(packageRoot, 'web/main.dart.js'));
    assert.equal(createHash('sha256').update(packagedMain).digest('hex'), report.mainJsSha256, 'The browser must be testing the extracted package binary.');
    report.managedServer = health;
    report.package = { root: packageRoot, name: packageInfo.package_name, sourceSnapshot: packageInfo.source_snapshot };
    report.serverStopOutput = execFileSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', resolve(packageRoot, 'scripts/stop.ps1'), '-Port', address.port], { encoding: 'utf8', windowsHide: true });
    await page.waitForTimeout(150);
    const stillServing = await fetch(new URL('__lcs_launcher_health', url), { signal: AbortSignal.timeout(2000) }).then(response => response.ok, () => false);
    assert.equal(stillServing, false, 'The isolated packaged server must actually stop; launch its own Play.cmd so its PID is recorded in that package.');
    report.managedServerStopped = true;
    try {
      const contracts = JSON.parse((await readFile(resolve(root, '.local/reports/launcher-contracts.json'), 'utf8')).replace(/^\uFEFF/, ''));
      report.launcherContracts = contracts;
      await writeFile(resolve(output, 'launcher-contracts.json'), JSON.stringify(contracts, null, 2));
    } catch { report.launcherContracts = { status: 'not_loaded', note: 'See the repository launcher contract evidence separately.' }; }
  }
  await context.setOffline(true);
  report.offlinePhaseStarted = new Date().toISOString();
  await page.reload({ waitUntil: 'load' });
  await waitText(/Continue your campaign/);
  await checkpoint('offline-title-reload');
  await click('Continue your campaign');
  await headquarters();
  text = await checkpoint('offline-campaign-restored');
  assert.equal(dateIn(text), report.tacticalResult.returnedDate);
  assert.equal(fundsIn(text), report.tacticalResult.returnedFunds);
  await click('Wait a day');
  for (let i = 0; i < 25; i++) {
    await page.waitForTimeout(180);
    text = await uiText();
    if (text.includes('DAILY BRIEFING') && dateIn(text) !== report.tacticalResult.returnedDate) break;
    if (i < 4) await checkpoint(`offline-daily-message-${i + 1}`);
    await press('Enter');
  }
  await headquarters();
  const offlineDate = dateIn(await uiText());
  const offlineFunds = fundsIn(await uiText());
  assert.notEqual(offlineDate, report.tacticalResult.returnedDate);
  await click('Save & exit');
  await waitText(/Continue your campaign/);
  await page.reload({ waitUntil: 'load' });
  await waitText(/Continue your campaign/);
  await click('Continue your campaign');
  await headquarters();
  text = await checkpoint('offline-play-save-reload');
  assert.match(text, /QA Founder/);
  assert.equal(dateIn(text), offlineDate);
  assert.equal(fundsIn(text), offlineFunds);
  report.offlineResult = { restoredDate: report.tacticalResult.returnedDate, savedDate: offlineDate, savedFunds: offlineFunds, cacheEntries: report.offlineCache.count };
  if (report.newsArticle?.status !== 'opened_actual_archive_story') {
    await click('Media & impact');
    await checkpoint('offline-media-review');
    await inspectActualArticle('offline-review');
    await returnToHeadquarters();
  }

  assert.deepEqual(report.pageErrors, [], 'Browser must not report uncaught page errors.');
  assert.deepEqual(report.consoleErrors, [], 'Browser console must not report rendering/runtime errors.');
  report.status = 'passed';
} catch (error) {
  report.status = 'failed';
  report.failure = error.stack ?? String(error);
  try {
    await page.screenshot({ path: resolve(output, 'FAILURE.png'), fullPage: true });
    await writeFile(resolve(output, 'FAILURE.txt'), await uiText());
  } catch { /* Preserve the original failure if the page itself is unavailable. */ }
  try { report.failureButtons = await page.getByRole('button').evaluateAll(nodes => nodes.map(node => ({ text: node.textContent, label: node.getAttribute('aria-label'), role: node.getAttribute('role') }))); } catch { /* Optional diagnosis only. */ }
  console.error(report.failure);
  process.exitCode = 1;
} finally {
  report.completed = new Date().toISOString();
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  await context.close();
  await browser.close();
  console.log(`Browser QA ${report.status}: ${output}`);
}
