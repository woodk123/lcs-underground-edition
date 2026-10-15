// Browser-only acceptance for the Gangsters-style organisation journal.
// Uses real controls, accessibility and exported saves; no Dart test hooks.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { cp, mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const args = process.argv.slice(2);
const argument = (flag, fallback) => args.includes(flag) ? args[args.indexOf(flag) + 1] : fallback;
const url = argument('--url', 'http://127.0.0.1:18876/');
const stamp = new Date().toISOString().replaceAll(':', '-').replaceAll('.', '-');
const output = resolve(root, argument('--out', `reports/browser/journal-${stamp}`));
const fixture = resolve(root, argument('--fixture', 'upstream/test/saves/felix_1_0.json'));
const packageRoot = args.includes('--package-root') ? resolve(argument('--package-root')) : null;
const layoutOnly = args.includes('--layout-only');
const articleOnly = args.includes('--article-only');
const newGameOnly = args.includes('--newgame-only');
const preview = args.includes('--preview') || layoutOnly || articleOnly || newGameOnly;
const skipKeyboard = args.includes('--skip-keyboard');
assert.ok(!skipKeyboard || preview, 'Final acceptance cannot skip keyboard verification.');
const continueKnownLedger = args.includes('--continue-known-ledger');
assert.ok(!continueKnownLedger || preview, 'Final acceptance cannot bypass the known Ledger navigation defect.');
const stopServer = args.includes('--stop-server');
assert.ok(preview || stopServer, 'Final acceptance requires --stop-server to verify actual server-stopped offline play.');
const profile = resolve(root, `.local/browser-profiles/journal-${stamp}`);
await mkdir(output, { recursive: true });
await mkdir(profile, { recursive: true });
const report = {
  status: 'running', started: new Date().toISOString(), url, profile, fixture,
  scope: preview ? 'Explicit preliminary browser review; not final release acceptance.' : 'Full browser acceptance.',
  checks: [], screenshots: [], pageErrors: [], consoleErrors: [], failedRequests: [], skipped: [],
};
if (skipKeyboard) report.skipped.push('Explicit preliminary --skip-keyboard: the reported native Tab focus defect remains pending; final acceptance must run without this flag.');
const response = await fetch(new URL('main.dart.js', url));
assert.ok(response.ok, 'The server must serve the compiled application.');
report.mainJsSha256 = createHash('sha256').update(Buffer.from(await response.arrayBuffer())).digest('hex');
if (packageRoot) {
  const health = await (await fetch(new URL('__lcs_launcher_health', url))).json();
  assert.equal(health.application, 'lcs-modern-local');
  assert.equal(resolve(health.directory).toLowerCase(), resolve(packageRoot, 'web').toLowerCase());
  const packagedMain = await readFile(resolve(packageRoot, 'web/main.dart.js'));
  assert.equal(createHash('sha256').update(packagedMain).digest('hex'), report.mainJsSha256);
  report.package = JSON.parse(await readFile(resolve(packageRoot, 'BUILD_INFO.json'), 'utf8'));
}
let context = await chromium.launchPersistentContext(profile, {
  channel: 'msedge', headless: true, viewport: { width: 1600, height: 1000 },
  recordVideo: { dir: resolve(output, 'video'), size: { width: 1600, height: 1000 } },
});
const extraContexts = [];
class OriginalArchiveFixtureEnding extends Error {}
let page;
let shotNumber = 0;
report.browserVersion = context.browser().version();
const escape = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const sourceGame = contents => typeof contents.saveData === 'string' ? JSON.parse(contents.saveData) : contents.saveData;
const fixtureGame = sourceGame(JSON.parse(await readFile(fixture, 'utf8')));
const crew = fixtureGame.lcs.pool.filter(p => p.alive && p.align === 'liberal' && !p.sleeperAgent);
assert.equal(crew.length, 5, 'The primary unchanged fixture must contain five original crew.');
report.originalCrew = crew.map(p => ({ id: p.id, name: p.name }));

function attach(target) {
  target.on('pageerror', error => report.pageErrors.push(error.stack ?? error.message));
  target.on('console', message => { if (message.type() === 'error') report.consoleErrors.push(message.text()); });
  target.on('requestfailed', request => report.failedRequests.push({ url: request.url(), failure: request.failure()?.errorText }));
}
async function text() {
  return page.locator('flt-semantics-host').evaluate(host => [
    host.innerText,
    ...[...host.querySelectorAll('[aria-label]')].map(node => node.getAttribute('aria-label')),
    ...[...host.querySelectorAll('[aria-valuetext]')].map(node => node.getAttribute('aria-valuetext')),
    ...[...host.querySelectorAll('input,textarea')].map(node => node.value),
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
  const accessibleName = typeof name === 'string' ? new RegExp(`^${escape(name)}(?:$|\\s)`) : name;
  const candidates = page.getByRole('button', { name: accessibleName });
  const size = page.viewportSize();
  const until = Date.now() + 3500;
  while (Date.now() < until) {
    for (const item of await candidates.all()) {
      const bounds = await item.boundingBox();
      if (!bounds) continue;
      const middle = bounds.x + bounds.width / 2;
      if (scope === 'top' && bounds.y > 110) continue;
      if (scope === 'left' && (middle > size.width * .53 || bounds.y < 85)) continue;
      if (scope === 'right' && (middle < size.width * .46 || bounds.y < 85)) continue;
      if (scope === 'footer' && bounds.y < size.height - 110) continue;
      return item;
    }
    // Flutter restores the underlying route's semantics after menu/dialog
    // reverse animations. Wait for that actual role without repeating actions.
    await page.waitForTimeout(65);
  }
  throw new Error(`No accessible ${scope} button ${name}. Available: ${JSON.stringify(await page.getByRole('button').allTextContents())}`);
}
async function click(name, scope = 'any') {
  const item = await button(name, scope);
  await item.scrollIntoViewIfNeeded();
  try {
    await item.click({ timeout: 4000 });
  } catch (error) {
    if (!String(error).includes('intercepts pointer events')) throw error;
    // Flutter can overlap its accessibility proxy rectangles even when the
    // painted controls are distinct. Test the real pointer route, retaining
    // all subsequent visible-state and exported-save assertions.
    const bounds = await item.boundingBox();
    assert.ok(bounds && await item.isEnabled(), `Visible enabled control required: ${name}`);
    const position = { x: bounds.x + bounds.width / 2, y: bounds.y + bounds.height / 2 };
    (report.pointerProxyFallbacks ??= []).push({ name: String(name), position });
    await page.mouse.click(position.x, position.y);
  }
  await page.waitForTimeout(200);
  return item;
}
async function top(name) { return click(new RegExp(`^${escape(name)}(?:$|\\s)`), 'top'); }
async function press(key) { await page.keyboard.press(key); await page.waitForTimeout(180); }
async function tabTo(pattern) {
  const target = typeof pattern === 'string' ? new RegExp(escape(pattern)) : pattern;
  for (let step = 0; step < 90; step++) {
    const focused = await page.evaluate(() => ({
      label: document.activeElement?.getAttribute('aria-label') ?? document.activeElement?.textContent?.trim() ?? '',
      role: document.activeElement?.getAttribute('role') ?? document.activeElement?.tagName ?? '',
    }));
    if (target.test(focused.label)) {
      report.keyboard ??= [];
      report.keyboard.push({ target: String(pattern), tabSteps: step, focused });
      return focused;
    }
    await page.keyboard.press('Tab'); await page.waitForTimeout(65);
  }
  throw new Error(`Keyboard Tab did not reach ${pattern}.`);
}
async function inside(item, label) {
  const bounds = await item.boundingBox();
  const size = page.viewportSize();
  assert.ok(bounds && bounds.x >= -1 && bounds.y >= -1 && bounds.x + bounds.width <= size.width + 1 && bounds.y + bounds.height <= size.height + 1,
    `${label} must fit ${size.width}x${size.height}: ${JSON.stringify(bounds)}`);
  return bounds;
}
async function state() {
  const content = await text();
  const match = content.match(/(\d{1,2} (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d{4})\s*[·•]\s*\$([\d,]+)/);
  assert.ok(match, 'The journal must visibly retain date and funds together.');
  return { date: match[1], funds: Number(match[2].replaceAll(',', '')) };
}
async function shot(name, details = {}) {
  await page.mouse.move(2, 2);
  await page.waitForTimeout(180);
  const base = `${String(++shotNumber).padStart(2, '0')}-${name}`;
  const pixels = await page.screenshot({ path: resolve(output, `${base}.png`), fullPage: true });
  const raster = { width: pixels.readUInt32BE(16), height: pixels.readUInt32BE(20) };
  await writeFile(resolve(output, `${base}.txt`), await text());
  report.screenshots.push(`${base}.png`);
  const metrics = await page.evaluate(() => {
    const width = innerWidth, height = innerHeight;
    const describe = node => {
      const bounds = node.getBoundingClientRect();
      const style = getComputedStyle(node);
      return {
        tag: node.tagName.toLowerCase(), id: node.id, parent: node.parentElement?.tagName.toLowerCase(), parentId: node.parentElement?.id,
        label: node.getAttribute('aria-label')?.slice(0, 100),
        rect: { x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height, right: bounds.right, bottom: bounds.bottom },
        client: { width: node.clientWidth, height: node.clientHeight },
        scroll: { width: node.scrollWidth, height: node.scrollHeight },
        css: { display: style.display, position: style.position, overflowX: style.overflowX, overflowY: style.overflowY, margin: style.margin, padding: style.padding, width: style.width, height: style.height, transform: style.transform },
      };
    };
    const all = [];
    function walk(parent) {
      for (const child of parent.children ?? []) {
        all.push(child); walk(child);
        if (child.shadowRoot) walk(child.shadowRoot);
      }
    }
    walk(document.documentElement);
    return {
      viewport: { width, height }, documentElement: describe(document.documentElement), body: describe(document.body),
      flutterHosts: all.filter(node => /^(FLUTTER-VIEW|FLT-GLASS-PANE|FLT-SCENE-HOST|FLT-TEXT-EDITING-HOST|FLT-SEMANTICS-HOST|FLT-SEMANTICS-PLACEHOLDER|FLT-ANNOUNCEMENT-HOST)$/.test(node.tagName)).map(describe),
      outsideViewport: all.filter(node => {
        const r = node.getBoundingClientRect();
        return (r.width > 0 || r.height > 0) && (r.right > width + .5 || r.bottom > height + .5 || r.left < -.5 || r.top < -.5);
      }).slice(0, 45).map(describe),
      semanticsScrollExtents: all.filter(node => node.tagName.startsWith('FLT-SEMANTICS') && (node.scrollWidth > node.clientWidth + .5 || node.scrollHeight > node.clientHeight + .5)).slice(0, 55).map(describe),
    };
  });
  await writeFile(resolve(output, `${base}-layout.json`), JSON.stringify(metrics, null, 2));
  report.checks.push({ name, status: name === 'FAILURE' ? 'failed' : 'passed', viewport: page.viewportSize(), raster, ...details });
  if (!layoutOnly && name !== 'FAILURE') assert.deepEqual(raster, page.viewportSize(), 'Full-page capture must equal the actual viewport; hidden semantic overflow must not add blank borders.');
  console.log(`${name === 'FAILURE' ? 'FAIL' : 'PASS'} ${name}`);
}
async function journal() {
  const save = await button('Save & exit', 'footer');
  await save.waitFor();
  const until = Date.now() + 12000;
  while (!(await save.isEnabled()) && Date.now() < until) await page.waitForTimeout(100);
  assert.ok(await save.isEnabled(), 'The ordinary journal must be ready for its actual source input.');
  for (const name of ['Organisation', 'Ledger', 'Justice', 'Agenda', 'Newspaper', 'Reports', 'City maps', 'Options']) {
    await inside(await button(new RegExp(`^${escape(name)}(?:$|\\s)`), 'top'), `${name} section tab`);
  }
  assert.equal(await page.getByRole('dialog').count(), 0, 'The organisation journal must not begin under a modal.');
  assert.doesNotMatch(await text(), /AVAILABLE CHOICES/, 'The journal must not reproduce the detached terminal choice panel.');
}
async function importAndLoad(path, { settleOriginalHospitalBill = false } = {}) {
  await wait(/Start a new movement|Start a New Game/);
  const chooser = page.waitForEvent('filechooser');
  await click('Import a Save');
  await (await chooser).setFiles(path);
  await wait(/Save imported/);
  await press('Enter');
  await wait(/Start a new movement|Start a New Game/);
  await click('Load & Manage Saves');
  await click(/^A(?:\s|$)/);
  await wait(/Manage .*Saved Game/);
  await click(/^L Load Game/);
  if (settleOriginalHospitalBill) {
    for (let step = 0; step < 4; step++) {
      const gate = await wait(/Pay the bill|Just leave|Save & exit|You were in a coma when the country was on the verge of collapse/);
      if (/You were in a coma when the country was on the verge of collapse/.test(gate)) {
        throw new OriginalArchiveFixtureEnding('The unchanged Moe archive fixture reached its original random hospital constitutional-amendment defeat during load.');
      }
      const saves = page.getByRole('button', { name: 'Save & exit', exact: true });
      if (await saves.count() && await saves.first().isEnabled()) break;
      const leave = page.getByRole('button', { name: /^(?:B )?Just leave(?:$|[.\s])/ });
      await leave.first().waitFor();
      report.originalLoadDecisions ??= [];
      report.originalLoadDecisions.push({ fixture: path, visibleChoice: 'Just leave', scope: 'Known Moe fixture original hospital-bill gate; isolated archive test campaign only.' });
      await leave.first().click(); await page.waitForTimeout(250);
    }
  }
  await journal();
}
async function exportSave(label, resume = true) {
  await click('Save & exit', 'footer');
  await wait(/Continue (?:your campaign|Last Game|as )/);
  await click('Load & Manage Saves');
  await click(/^A(?:\s|$)/);
  await wait(/Manage .*Saved Game/);
  const downloading = page.waitForEvent('download');
  await click(/Export Save File/);
  const download = await downloading;
  const path = resolve(output, `${label}.json`);
  await download.saveAs(path);
  const bytes = await readFile(path);
  const contents = JSON.parse(bytes.toString('utf8'));
  const game = sourceGame(contents);
  assert.ok(game.lcs && game.date && game.ledger, 'An export must contain the actual campaign.');
  report.exports ??= [];
  report.exports.push({ label, file: `${label}.json`, bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') });
  if (resume) {
    await click(/^L Load Game/);
    await journal();
  }
  return game;
}
async function selectCrew(name) {
  await click(new RegExp(`Select crew ${escape(name)}(?:$|\\s)`), 'left');
  await inside(await button(`Inspect ${name}`, 'left'), 'Selected actor portrait');
}
async function ordersFor(name) {
  await selectCrew(name);
  await click('Orders', 'left');
  await click('Business', 'left');
  await (await button(/Prepare Solicit Donations(?:$|\s)/, 'right')).waitFor();
}
async function prepareDonations() {
  await click(/Prepare Solicit Donations(?:$|\s)/, 'right');
  await inside(await button('Confirm order', 'left'), 'Inline order confirmation');
  const content = await text();
  assert.match(content, /Persuasion|Street Smarts|Charisma|Heart/, 'The job card must explain actual fundraising factors.');
  assert.match(content, /advance the day|next day|daily/i, 'The job card must explain execution timing.');
}
async function cancelPrepared() {
  await click('Cancel prepared order', 'left');
  await page.waitForTimeout(150);
}
async function drag(source, target) {
  const from = await source.boundingBox();
  const to = await target.boundingBox();
  assert.ok(from && to, 'Drag endpoints must come from actual visible UI objects.');
  await page.mouse.move(from.x + Math.min(24, from.width / 2), from.y + from.height / 2);
  await page.mouse.down();
  await page.mouse.move(from.x + 35, from.y + from.height / 2 + 4, { steps: 4 });
  await page.mouse.move(to.x + to.width / 2, to.y + to.height / 2, { steps: 24 });
  await page.waitForTimeout(180);
  await page.mouse.up();
  await page.waitForTimeout(500);
}
async function preparePublicVisit() {
  await top('Organisation');
  await click(/Select squad QA Field Team(?:$|\s)/);
  await ordersFor(crew.at(-1).name);
  await click('Operations', 'left');
  await click('Visit a location');
  let parks = page.getByRole('button', { name: /Park\. site(?:\.|\s|$)/ });
  if (!(await parks.count())) {
    await click(/University.*\. district(?:\.|\s|$)/);
    await page.waitForTimeout(200);
    parks = page.getByRole('button', { name: /Park\. site(?:\.|\s|$)/ });
  }
  assert.ok(await parks.count(), 'The actual known University district must expose a public park.');
  const park = parks.first();
  const sourceLabel = await park.getAttribute('aria-label') ?? await park.innerText();
  await park.click(); await page.waitForTimeout(180);
  await inside(await button('Confirm order', 'left'), 'Shared squad visit job card confirmation');
  return sourceLabel;
}
async function archiveJourney() {
  const savedPage = page;
  // This unchanged 2036 source fixture has only hospitalized/inactive members.
  // Loading it can automatically run the original month-end constitutional
  // vote and end the campaign before its archive becomes reachable. Retry only
  // that exact original ending, without editing the fixture or engine state.
  for (let attempt = 1; attempt <= 5; attempt++) {
    const newsContext = await context.browser().newContext({ viewport: { width: 1280, height: 720 } });
    extraContexts.push(newsContext);
    try {
      page = await newsContext.newPage(); attach(page);
      await page.goto(url, { waitUntil: 'networkidle' });
      await importAndLoad(resolve(root, 'upstream/test/saves/moe_1_5.json'), { settleOriginalHospitalBill: true });
      await top('Newspaper'); await wait(/Press archive|Media Overview/);
      await click(/GM FOOD FAIRE/);
      await page.getByRole('heading', { name: 'GM FOOD FAIRE', exact: true }).waitFor();
      await wait(/Cable News/);
      await wait(/Savannah, GA/);
      report.articleBodyAccessible = /Savannah, GA/.test(await text());
      await shot('original-news-article-in-journal');
      await click(/^(?:Continue|Back to archive|Back to newspaper)(?:$|\s)/i);
      await wait(/Press archive|Media Overview/);
      await shot('article-pointer-return-to-archive');
      report.articleReturnVerified = true;
      report.articleFixtureLoadAttempt = attempt;
      return;
    } catch (error) {
      if (!(error instanceof OriginalArchiveFixtureEnding)) throw error;
      report.originalArchiveLoadOutcomes ??= [];
      report.originalArchiveLoadOutcomes.push({ attempt, outcome: error.message });
      await shot(`original-hospital-defeat-${attempt}`);
      await click(/^Continue(?:$|\s)/i);
      await wait(/They don't bring folks like you back anymore/);
      await click(/^Continue(?:$|\s)/i);
      await wait(/The world is fading with you/);
      await click(/^Continue(?:$|\s)/i);
      await wait(/The Liberal ELITE/);
      await shot(`original-completed-score-${attempt}`);
      await click(/^Continue(?:$|\s)/i);
      await wait(/Start a new movement|Start a New Game/);
      await shot(`original-loss-returned-title-${attempt}`);
      report.originalNaturalEndingVerified = true;
      if (attempt === 5) throw error;
    } finally {
      await newsContext.close();
      page = savedPage;
    }
  }
}

async function newCampaignJourney() {
    // The redesigned title must also create a new original-engine campaign.
    const newContext = await context.browser().newContext({ viewport: { width: 1280, height: 720 } });
    extraContexts.push(newContext);
    const retainedPage = page;
    page = await newContext.newPage(); attach(page);
    await page.goto(url, { waitUntil: 'networkidle' });
    await wait(/Start a new movement|Start a New Game/);
    await click(/^(?:Start a new movement|Start a New Game)(?:$|\s|·)/i);
    await wait(/Starting Political Climate/); await press('Enter');
    await wait(/toggle choice or fate/); await press('d'); await press('Enter');
    const nameInput = page.locator('input:not([disabled]):not([readonly])');
    for (let step = 0; step < 30 && !(await nameInput.count()); step++) await press('Enter');
    assert.equal(await nameInput.count(), 1, 'Original founder creation must reach its actual editable name prompt.');
    await wait(/What is your name to the people/);
    await nameInput.fill('Journal QA Founder'); await click('Confirm text');
    await journal();
    assert.match(await text(), /Journal QA Founder/);
    const newCampaignState = await state();
    report.newCampaign = { founder: 'Journal QA Founder', ...newCampaignState };
    await shot('new-original-campaign-created');
    await click('Save & exit', 'footer'); await wait(/Continue (?:your campaign|Last Game|as )/);
    await click(/^Continue (?:your campaign|Last Game|as )/i); await journal();
    assert.match(await text(), /Journal QA Founder/);
    assert.deepEqual(await state(), newCampaignState, 'Saving and continuing a new campaign must not advance time or alter funds.');
    await shot('new-campaign-saved-and-continued');
    await newContext.close(); page = retainedPage;

}

try {
  review: {
  if (newGameOnly) {
    await newCampaignJourney();
    report.skipped.push('Explicit --newgame-only diagnostic: organisation, existing campaigns, persistence and upgrade phases were not run.');
    report.status = 'preview-passed';
    break review;
  }
  if (articleOnly) {
    await archiveJourney();
    report.skipped.push('Explicit --article-only diagnostic: organisation, gameplay, persistence and upgrade phases were not run.');
    report.status = 'preview-passed';
    break review;
  }
  page = await context.newPage(); attach(page);
  await page.goto(url, { waitUntil: 'networkidle' });
  await wait(/Start a new movement|Start a New Game/);
  await shot('title-journal');
  await importAndLoad(fixture);
  const initial = await state();
  assert.deepEqual(initial, { date: '4 Jan 2023', funds: 7 });
  report.initialCampaign = initial;
  await writeFile(resolve(output, 'initial-semantics.html'), await page.locator('flt-semantics-host').innerHTML());
  for (const [width, height] of [[1600, 1000], [1280, 720], [800, 700]]) {
    await page.setViewportSize({ width, height });
    await page.waitForTimeout(300);
    await journal();
    const rosterBounds = [];
    for (const member of crew) rosterBounds.push(await inside(layoutOnly ? await button(new RegExp(`^Dossier: ${escape(member.name)}(?:$|\\s)`), 'left') : await button(`Select crew ${member.name}`, 'left'), `Crew row ${member.name}`));
    assert.deepEqual(await state(), initial);
    await shot(`organisation-five-crew-${width}x${height}`, { rosterBounds, reference: '00904_lieutenants.png' });
    if (layoutOnly) continue;
    const squad = await button(/Select squad The Liberal Crime Squad(?:$|\s)/);
    assert.ok((await squad.boundingBox()).x < 90, 'Squad selection belongs in the vertical left-edge rail.');
    await squad.click(); await page.waitForTimeout(250);
    assert.doesNotMatch(await text(), /Available crew|Assemble the squad|Drag crew between these pages/, 'Selecting an active squad must not enter assembly.');
    await shot(`direct-squad-tab-${width}x${height}`, { clicks: 1, opensAssembly: false });
    await click(`Inspect ${crew[0].name}`, 'left');
    assert.equal(await page.getByRole('dialog').count(), 0, 'Crew inspection must remain a nonblocking facing-page inspector.');
    await inside(await button('Close crew inspection'), 'Inline inspector close');
    await shot(`nonmodal-inspection-${width}x${height}`);
    await top('Newspaper'); await top('Organisation');
    assert.equal(await page.getByRole('button', { name: 'Close crew inspection', exact: true }).count(), 0, 'Main section switching clears inspection without a dismissal click.');
    assert.deepEqual(await state(), initial);
    await ordersFor(crew[0].name);
    await prepareDonations();
    await shot(`prepared-order-${width}x${height}`, { reference: '00909_lieutenants.png', actor: crew[0].name });
    assert.deepEqual(await state(), initial);
    await cancelPrepared();
    await top('Organisation');
  }
  if (layoutOnly) {
    report.skipped.push('Explicit --layout-only review: save-effect, allocation, full gameplay, offline and upgrade checks remain pending.');
    report.status = 'preview-passed';
  } else {
    // Exercise the actual reading control at a constrained desktop size. The
    // mechanics must have rendered space, rather than merely exist in ARIA.
    await top('Options');
    await click(/^150%$/);
    await top('Organisation');
    await page.setViewportSize({ width: 800, height: 600 });
    await ordersFor(crew[0].name); await prepareDonations();
    const timing = page.getByText('Runs when you advance the day.', { exact: true }).first();
    await timing.waitFor();
    const timingBounds = await inside(timing, '150% order timing');
    const timingClip = await timing.evaluate(node => {
      const rect = node.getBoundingClientRect();
      let left = Math.max(0, rect.left), top = Math.max(0, rect.top);
      let right = Math.min(innerWidth, rect.right), bottom = Math.min(innerHeight, rect.bottom);
      const clippingAncestors = [];
      for (let parent = node.parentElement; parent; parent = parent.parentElement) {
        const style = getComputedStyle(parent);
        if (!/hidden|clip|scroll|auto/.test(`${style.overflowX} ${style.overflowY}`)) continue;
        const bounds = parent.getBoundingClientRect();
        clippingAncestors.push({ tag: parent.tagName, width: bounds.width, height: bounds.height });
        left = Math.max(left, bounds.left); right = Math.min(right, bounds.right);
        top = Math.max(top, bounds.top); bottom = Math.min(bottom, bounds.bottom);
      }
      return { width: Math.max(0, right - left), height: Math.max(0, bottom - top), clippingAncestors };
    });
    assert.ok(timingClip.width > 20 && timingClip.height > 10, `150% mechanics timing must render within a usable pane: ${JSON.stringify(timingClip)}`);
    await inside(await button('Confirm order', 'left'), '150% confirmation');
    await shot('prepared-order-800x600-reading150', { timingBounds, timingClip, readingScale: 1.5 });
    assert.deepEqual(await state(), initial);
    await cancelPrepared();
    await top('Options'); await click(/^100%$/); await top('Organisation');
    await page.setViewportSize({ width: 1600, height: 1000 });
    const baseline = await exportSave('01-initial-canonical-save');
    // Browse every group, prepare/cancel, and export: exact real gameplay state must be unchanged.
    await ordersFor(crew[0].name);
    for (const group of ['Personnel', 'Activism', 'Business']) await click(group, 'left');
    await prepareDonations();
    await cancelPrepared();
    await top('Organisation');
    const previewed = await exportSave('02-cancelled-preview-save');
    assert.deepEqual(previewed, baseline, 'Order categories and cancelled previews must not change any serialized campaign state.');
    await shot('preview-and-cancel-save-identical', { proof: '01-initial-canonical-save.json vs02-cancelled-preview-save.json' });

    const transferName = crew.at(-1).name;
    await click('Crew pool', 'left');
    await wait(/Available crew/);
    await click(`Remove ${transferName} from this squad`, 'left');
    await wait(/Crew · 4\/6/);
    await click(new RegExp(`Inspect pool member ${escape(transferName)}(?:$|\\s)`), 'right');
    await shot('pool-person-inspected-inline', { reference: '00902_lieutenants.png', selected: transferName });
    assert.equal(await page.getByRole('dialog').count(), 0);
    await click(/^Add to this squad$/, 'right');
    await wait(/Crew · 5\/6/);
    await shot('pool-add-source-action');
    await click(`Remove ${transferName} from this squad`, 'left');
    await wait(/Crew · 4\/6/);
    await drag(await button(new RegExp(`Inspect pool member ${escape(transferName)}(?:$|\\s)`), 'right'), await button(`Select crew ${crew[0].name}`, 'left'));
    await wait(/Crew · 5\/6/);
    await shot('pool-drag-to-squad');
    await drag(await button(`Select crew ${transferName}`, 'left'), await button(/Sort:/, 'right'));
    await wait(/Crew · 4\/6/);
    await shot('squad-drag-to-pool');
    await click(new RegExp(`Inspect pool member ${escape(transferName)}(?:$|\\s)`), 'right');
    await click(/^Add to this squad$/, 'right');
    await wait(/Crew · 5\/6/);
    await click('Done', 'left');
    await top('Organisation');
    const restored = await exportSave('03-pool-roundtrip-save');
    assert.deepEqual(restored, baseline, 'Click/drag transfer round trips must preserve all serialized campaign state.');
    await shot('pool-roundtrip-export-verified');

    // Create a second real squad through the original explicit assembly and name prompt.
    await click('Assemble a new squad');
    await wait(/Available crew/);
    await click(new RegExp(`Inspect pool member ${escape(transferName)}(?:$|\\s)`), 'right');
    await click(/^Add to this squad$/, 'right');
    await wait(/Crew · 1\/6/);
    await click('Done', 'left');
    await wait(/What shall we designate/);
    const input = page.locator('input:not([disabled]):not([readonly])');
    assert.equal(await input.count(), 1);
    await input.fill('QA Field Team');
    await click('Confirm text');
    await journal();
    for (const name of ['QA Field Team', 'The Liberal Crime Squad', 'QA Field Team', 'The Liberal Crime Squad']) {
      await click(new RegExp(`Select squad ${escape(name)}(?:$|\\s)`));
      await page.waitForTimeout(220);
      assert.doesNotMatch(await text(), /Available crew|Drag crew between these pages/, 'A squad-tab click must select, without reopening assembly.');
    }
    await shot('two-real-squads-direct-selection');
    const beforeCommit = await exportSave('03b-two-squads-before-order');

    // A draft for A must not accidentally become B's confirmed order.
    await ordersFor(crew[0].name);
    await prepareDonations();
    if (skipKeyboard) await selectCrew(crew[1].name);
    else {
      await tabTo(`Select crew ${crew[1].name}`);
      await press('Space');
    }
    await inside(await button(`Inspect ${crew[1].name}`, 'left'), 'Keyboard-selected actor portrait');
    const confirms = page.getByRole('button', { name: 'Confirm order', exact: true });
    assert.ok(!(await confirms.count()) || !(await confirms.first().isEnabled()), 'Changing actor must clear the previous actor\'s draft.');
    await click('Business', 'left');
    await prepareDonations();
    await shot('prepared-order-after-actor-switch', { actor: crew[1].name });
    if (skipKeyboard) await click('Confirm order', 'left');
    else {
      await tabTo(/^Confirm order(?:$|\s)/);
      await press('Enter');
    }
    await page.waitForTimeout(400);
    await top('Organisation');
    const committed = await exportSave('04-confirmed-personal-order');
    for (const actor of committed.lcs.pool) {
      assert.equal(actor.activity.type, actor.id === crew[1].id ? 'donations' : 'none', 'Only the explicitly confirmed actor receives this activity.');
    }
    assert.equal(committed.date, baseline.date);
    assert.deepEqual(committed.ledger, baseline.ledger);
    assert.equal(committed.lcs.squads.length, 2);
    const expectedCommit = structuredClone(beforeCommit);
    expectedCommit.lcs.pool.find(p => p.id === crew[1].id).activity = committed.lcs.pool.find(p => p.id === crew[1].id).activity;
    assert.deepEqual(committed, expectedCommit, 'Confirm changes exactly the named actor\'s activity and nothing else in the serialized campaign.');
    await shot('confirmed-order-exact-actor-save-proof');
    await ordersFor(crew[1].name);
    assert.match(await text(), /Soliciting Donations/, 'Reentry must retain the real confirmed assignment.');
    await click(/Prepare Perform Live Music(?:$|\s)/, 'right');
    await inside(await button('Confirm order', 'left'), 'Reentered draft confirmation');
    await cancelPrepared(); await top('Organisation');
    const cancelledReplacement = await exportSave('04b-reentry-replacement-cancelled');
    assert.deepEqual(cancelledReplacement, committed, 'Cancelling a replacement draft must retain the previously confirmed activity.');
    await shot('reentered-replacement-cancel-preserved');

    // All eight tabs and uncommon original commands remain accessible in the journal.
    for (const section of ['Ledger', 'Justice', 'Agenda', 'Newspaper', 'Reports', 'Options', 'Organisation']) {
      await top(section);
      try { await journal(); }
      catch (error) {
        if (!continueKnownLedger || section !== 'Ledger' || !/Funding Report/.test(await text())) throw error;
        report.knownDefects ??= [];
        report.knownDefects.push({ section, failure: String(error), workaround: 'Explicit original Continue, exploratory preview only.' });
        report.skipped.push('Known Ledger navigation defect: preview used explicit Continue; final acceptance must pass without --continue-known-ledger.');
        await shot('ledger-known-navigation-defect', { status: 'known-failed' });
        await click('Continue');
        await journal();
      }
      assert.deepEqual(await state(), initial);
      await shot(`section-${section.toLowerCase()}`);
    }
    await click(/More headquarters commands/);
    assert.match(await text(), /Sleeper Agents|Change the Slogan|Next Location|Reorder|Set Vehicles/, 'Original HQ commands must remain reachable in the modern journal.');
    await shot('original-headquarters-commands');
    await press('Escape');

    // Choose a real public site through the shared squad order controls.
    await click(/Select squad QA Field Team(?:$|\s)/);
    const parkLabel = await preparePublicVisit();
    await shot('visit-target-prepared', { selectedSourceLabel: parkLabel, reference: '00913_lieutenants.png' });
    await top('Organisation');
    const targetPreview = await exportSave('05-unconfirmed-target-save');
    assert.ok(targetPreview.lcs.squads.every(s => s.activity.type === 'none'), 'A selected but unconfirmed target must not queue a visit.');
    await preparePublicVisit();
    await click('Confirm order', 'left');
    await top('Organisation');
    const queued = await exportSave('06-confirmed-squad-visit');
    const field = queued.lcs.squads.find(s => s.name === 'QA Field Team');
    assert.equal(field.activity.type, 'visit');
    assert.ok(field.activity.idString, 'A confirmed visit must retain the exact source site ID.');
    assert.equal(queued.date, baseline.date);
    assert.deepEqual(queued.ledger, baseline.ledger);
    const expectedVisit = structuredClone(targetPreview);
    expectedVisit.lcs.squads.find(s => s.name === 'QA Field Team').activity = field.activity;
    assert.deepEqual(queued, expectedVisit, 'Confirm Visit changes exactly this squad\'s source order.');
    await top('Newspaper'); await top('Organisation');
    const retained = await exportSave('07-queued-visit-after-section-switch');
    assert.deepEqual(retained.lcs.squads.find(s => s.name === 'QA Field Team').activity, field.activity, 'Section changes must preserve the queued target.');
    await shot('queued-visit-preserved-by-navigation');

    await click(/Carry out (?:your )?plans|Run day|Wait a day/i, 'footer');
    let arrival = false;
    for (let step = 0; step < 25; step++) {
      const content = await text();
      if (/has arrived at/.test(content)) { arrival = true; break; }
      assert.doesNotMatch(content, /TACTICAL VIEW/, 'The actual arrival message must precede tactical entry.');
      await press('Enter');
    }
    assert.ok(arrival, 'The confirmed real visit must reach its original arrival event.');
    await shot('actual-squad-arrival');
    await press('Enter'); await wait(/TACTICAL VIEW/);
    await shot('actual-tactical-operation');
    await click(/View full map/); await wait(/Explored areas/);
    await shot('actual-full-map');
    await click('Back to operation'); await wait(/TACTICAL VIEW/);
    await shot('full-map-pointer-return');
    await click(/^Move up(?:$|\s)/);
    for (let step = 0; step < 20; step++) {
      const saves = page.getByRole('button', { name: 'Save & exit', exact: true });
      if ((await saves.count()) && await saves.first().isEnabled() && !(await text()).includes('TACTICAL VIEW')) break;
      await press('Enter');
    }
    await journal();
    assert.notDeepEqual(await state(), initial, 'Running the actual operation advances campaign state.');
    await shot('operation-returned-to-journal');
    const afterOperation = await exportSave('08-after-real-operation');
    report.operationResult = { before: initial, after: await state(), sourceTarget: field.activity.idString };

    // Full browser-process restart of only this newly created isolated QA profile.
    await click('Save & exit', 'footer'); await wait(/Continue (?:your campaign|Last Game|as )/);
    await context.close();
    context = await chromium.launchPersistentContext(profile, { channel: 'msedge', headless: true, viewport: { width: 1280, height: 720 } });
    page = await context.newPage(); attach(page);
    await page.goto(url, { waitUntil: 'networkidle' });
    await click(/^Continue (?:your campaign|Last Game|as )/i); await journal();
    const restarted = await exportSave('09-after-browser-process-restart');
    assert.deepEqual(restarted, afterOperation);
    await shot('browser-process-restart-preserved');
    report.restartVerified = true;

    // Real supplied archive, isolated from the five-crew acceptance campaign.
    await archiveJourney();

    await newCampaignJourney();

    if (preview) report.skipped.push('Explicit --preview: packaged-runtime/cache-upgrade verification awaits a packaged18876 build.');
    else {
      assert.ok(packageRoot, 'Final acceptance requires --package-root and the actual packaged18876 server.');
      const previousReportPath = resolve(root, 'reports/browser/smoke-2026-10-13T23-36-30-298Z/report.json');
      const previousReport = JSON.parse(await readFile(previousReportPath, 'utf8'));
      assert.equal(previousReport.status, 'passed'); assert.equal(previousReport.url, url);
      const previousProfile = resolve(root, '.local/browser-profiles/2026-10-13T23-36-30-298Z');
      const upgradedProfile = resolve(root, `.local/browser-profiles/journal-upgrade-${stamp}`);
      assert.ok(previousProfile.startsWith(resolve(root, '.local/browser-profiles') + sep));
      await cp(previousProfile, upgradedProfile, { recursive: true, errorOnExist: true, force: false });
      const upgradeDirectory = resolve(output, 'upgrade');
      await mkdir(upgradeDirectory, { recursive: true });
      const upgradeContext = await chromium.launchPersistentContext(upgradedProfile, { channel: 'msedge', headless: true, viewport: { width: 1280, height: 720 } });
      extraContexts.push(upgradeContext);
      const upgradeErrorsStart = report.pageErrors.length;
      const upgradeConsoleStart = report.consoleErrors.length;
      const originalPage = page;
      page = await upgradeContext.newPage(); attach(page);
      await page.goto(url, { waitUntil: 'domcontentloaded' });
      await page.waitForFunction(async expected => {
        for (const name of await caches.keys()) {
          const cached = await (await caches.open(name)).match(new URL('main.dart.js', location.href).href);
          if (!cached) continue;
          const hash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', await cached.arrayBuffer()))].map(v => v.toString(16).padStart(2, '0')).join('');
          if (hash === expected && navigator.serviceWorker.controller) return true;
        }
        return false;
      }, report.mainJsSha256, { timeout: 60000 });
      await page.reload({ waitUntil: 'networkidle' });
      await wait(/Continue (?:your campaign|Last Game|as )/, 30000);
      await click(/^Continue (?:your campaign|Last Game|as )/i); await journal();
      assert.deepEqual(await state(), { date: '4 Jan 2023', funds: previousReport.offlineResult.savedFunds });
      assert.match(await text(), /QA Founder/);
      await shot('prior-real-qa-profile-upgraded-to-journal');
      const upgradeCache = await page.evaluate(async expected => {
        const names = await caches.keys();
        for (const name of names) {
          const cache = await caches.open(name);
          const cached = await cache.match(new URL('main.dart.js', location.href).href);
          if (!cached) continue;
          const hash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', await cached.arrayBuffer()))].map(v => v.toString(16).padStart(2, '0')).join('');
          if (hash === expected) return { names, cachedMainSha256: hash, count: (await cache.keys()).length };
        }
        return { names, cachedMainSha256: null };
      }, report.mainJsSha256);
      assert.equal(upgradeCache.cachedMainSha256, report.mainJsSha256);
      const upgradeState = await state();
      await cp(resolve(output, report.screenshots.at(-1)), resolve(upgradeDirectory, 'campaign-preserved.png'));
      const upgradedGame = await exportSave('upgrade/upgraded-campaign');
      assert.equal(upgradedGame.lcs.pool.find(p => p.name === 'QA Founder')?.activity.type, 'none');
      const upgradeReport = {
        status: 'passed', url, profile: upgradedProfile, expectedHash: report.mainJsSha256,
        previousMainHash: previousReport.mainJsSha256, cache: upgradeCache,
        preservedCampaign: { founder: 'QA Founder', ...upgradeState, activity: 'none' },
        pageErrors: report.pageErrors.slice(upgradeErrorsStart), consoleErrors: report.consoleErrors.slice(upgradeConsoleStart),
        screenshots: ['campaign-preserved.png'], completed: new Date().toISOString(),
      };
      assert.deepEqual(upgradeReport.pageErrors, []); assert.deepEqual(upgradeReport.consoleErrors, []);
      await writeFile(resolve(upgradeDirectory, 'report.json'), JSON.stringify(upgradeReport, null, 2));
      report.upgradeVerified = { previousMainHash: previousReport.mainJsSha256, currentMainHash: report.mainJsSha256, copiedProfile: upgradedProfile, preserved: upgradeState, cache: upgradeCache };
      await upgradeContext.close(); page = originalPage;
    }
    // Actual cached runtime, not a mocked offline state.
    await click('Save & exit', 'footer'); await wait(/Continue (?:your campaign|Last Game|as )/);
    await page.waitForFunction(async expected => {
      if (!navigator.serviceWorker.controller) return false;
      for (const name of await caches.keys()) {
        const cached = await (await caches.open(name)).match(new URL('main.dart.js', location.href).href);
        if (!cached) continue;
        const hash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', await cached.arrayBuffer()))].map(v => v.toString(16).padStart(2, '0')).join('');
        if (hash === expected) return true;
      }
      return false;
    }, report.mainJsSha256, { timeout: 60000 });
    report.offlineCache = await page.evaluate(async expected => {
      const names = await caches.keys();
      for (const name of names) {
        const cache = await caches.open(name);
        const response = await cache.match(new URL('main.dart.js', location.href).href);
        if (!response) continue;
        const hash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', await response.arrayBuffer()))].map(v => v.toString(16).padStart(2, '0')).join('');
        if (hash === expected) return { names, count: (await cache.keys()).length, hasMain: true, cachedMainSha256: hash };
      }
      return { names, count: 0, hasMain: false, cachedMainSha256: null };
    }, report.mainJsSha256);
    assert.ok(report.offlineCache.hasMain && report.offlineCache.count > 20);
    if (stopServer) {
      const address = new URL(url);
      assert.ok(packageRoot && ['localhost', '127.0.0.1'].includes(address.hostname) && address.port !== '8765', 'Only the exact isolated packaged server may be stopped.');
      const health = await (await fetch(new URL('__lcs_launcher_health', url))).json();
      assert.equal(health.application, 'lcs-modern-local');
      assert.equal(resolve(health.directory).toLowerCase(), resolve(packageRoot, 'web').toLowerCase());
      report.managedServer = health;
      report.serverStopOutput = execFileSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', resolve(packageRoot, 'scripts/stop.ps1'), '-Port', address.port], { encoding: 'utf8', windowsHide: true });
      const stillServing = await fetch(new URL('__lcs_launcher_health', url), { signal: AbortSignal.timeout(2000) }).then(r => r.ok, () => false);
      assert.equal(stillServing, false, 'The packaged launcher must actually stop its own recorded server before offline acceptance.');
      report.managedServerStopped = true;
    }
    await context.setOffline(true);
    await page.reload({ waitUntil: 'domcontentloaded' });
    await wait(/Continue (?:your campaign|Last Game|as )/);
    await click(/^Continue (?:your campaign|Last Game|as )/i); await journal();
    await click(/Select squad The Liberal Crime Squad(?:$|\s)/);
    await ordersFor(crew[1].name); await prepareDonations(); await cancelPrepared();
    await top('Organisation');
    await shot('offline-journal-playable');
    const offlineBefore = await state();
    await click(/Carry out (?:your )?plans|Run day|Wait a day/i, 'footer');
    let offlineAdvanced = false;
    for (let step = 0; step < 40; step++) {
      const saves = page.getByRole('button', { name: 'Save & exit', exact: true });
      if (await saves.count() && await saves.first().isEnabled()) {
        const current = await state();
        if (current.date !== offlineBefore.date) { offlineAdvanced = true; break; }
      }
      await press('Enter');
    }
    assert.ok(offlineAdvanced, 'The real cached game must execute a campaign day offline.');
    const offlineAfter = await state();
    await shot('offline-campaign-day-executed', { before: offlineBefore, after: offlineAfter });
    await click('Save & exit', 'footer'); await wait(/Continue (?:your campaign|Last Game|as )/);
    await page.reload({ waitUntil: 'domcontentloaded' });
    await wait(/Continue (?:your campaign|Last Game|as )/);
    await click(/^Continue (?:your campaign|Last Game|as )/i); await journal();
    assert.deepEqual(await state(), offlineAfter, 'Offline saving and reload must preserve the executed day.');
    await shot('offline-day-saved-and-reloaded');
    if (!stopServer) await context.setOffline(false);
    report.offlineVerified = { before: offlineBefore, after: offlineAfter, savedAndReloaded: true };
    report.offlineResult = { restoredDate: offlineBefore.date, savedDate: offlineAfter.date, savedFunds: offlineAfter.funds, cacheEntries: report.offlineCache.count };


    assert.deepEqual(report.pageErrors, [], 'The new runtime must not raise browser page errors.');
    assert.deepEqual(report.consoleErrors, [], 'The new runtime must not emit browser console errors.');
    assert.deepEqual(report.failedRequests, [], 'The fully cached runtime must not fail resource requests, including during offline use.');
    report.status = report.knownDefects?.length ? 'preview-complete-with-known-defects' : preview ? 'preview-passed' : 'passed';
  }
  }
} catch (error) {
  report.status = 'failed'; report.error = error.stack ?? String(error); process.exitCode = 1;
  try { await shot('FAILURE'); } catch {}
  try {
    await writeFile(resolve(output, 'FAILURE-semantics.html'), await page.locator('flt-semantics-host').innerHTML());
    await writeFile(resolve(output, 'FAILURE-buttons.json'), JSON.stringify(await page.getByRole('button').evaluateAll(nodes => nodes.map(node => ({ label: node.getAttribute('aria-label'), text: node.innerText, role: node.getAttribute('role'), pointerEvents: getComputedStyle(node).pointerEvents }))), null, 2));
  } catch {}
  console.error(report.error);
} finally {
  for (const extra of extraContexts.reverse()) {
    try { await extra.close(); } catch {}
  }
  await context.close();
  report.completed = new Date().toISOString();
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ output, status: report.status, checks: report.checks.length, skipped: report.skipped, mainJsSha256: report.mainJsSha256 }, null, 2));
}
