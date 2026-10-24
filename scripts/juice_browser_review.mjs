// Dedicated, fresh-profile acceptance. Never opens or edits a player campaign.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromiumLaunchOptions, observeMainScript } from './browser_support.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const args = process.argv.slice(2);
const value = (flag, fallback) => args.includes(flag) ? args[args.indexOf(flag) + 1] : fallback;
const expectedHash = value('--expected-hash', '');
assert.match(expectedHash, /^[a-f0-9]{64}$/i);
const url = new URL(value('--url', 'http://127.0.0.1:18883/')).href;
assert.equal(url, 'http://127.0.0.1:18883/');
const output = resolve(root, value('--out', 'reports/juice-status-qa/browser'));
await mkdir(output, { recursive: true });
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const decode = save => typeof save.saveData === 'string' ? JSON.parse(save.saveData) : save.saveData;
const original = JSON.parse(await readFile(resolve(root, 'upstream/test/saves/felix_1_0.json'), 'utf8'));
const fixture = decode(original);
const template = structuredClone(fixture.lcs.pool[0]);
const hospital = fixture.sites.find(site => site.type === 'universityHospital');
const chaz = fixture.lcs.pool[0];
Object.assign(chaz, { name: 'Chaz Reasoner', properName: 'Chaz Reasoner', juice: 160,
  locationId: `Site${hospital.id}`, squadId: null, medicalBills: 1360, _blood: .2 });
for (const squad of fixture.lcs.squads) squad.members = squad.members.filter(id => id !== chaz.id);
const active = fixture.lcs.pool[1];
Object.assign(active, { name: 'Artie Activist', properName: 'Artie Activist', juice: 160 });
for (const [name, juice] of [['Elite Example',1000],['Urban Example',200],['Socialist Example',50],['Civilian Example',0],['Unstable Example',-10]]) {
  const person = { ...structuredClone(template), id: fixture.nextCreatureId++, name,
    properName: name, juice, squadId: null, sleeperAgent: false, hidingDaysLeft: 0,
    vacationDaysLeft: 0, medicalBills: 0 };
  fixture.lcs.pool.push(person);
}
original.saveData = typeof original.saveData === 'string' ? JSON.stringify(fixture) : fixture;
const fixturePath = resolve(output, 'synthetic-juice.json');
await writeFile(fixturePath, JSON.stringify(original));
const report = { status: 'running', url, expectedHash, scope: 'Prepared Juice milestone campaign; fresh Edge context; no player data and no day advancement.',
  checks: [], screenshots: [], pageErrors: [], consoleErrors: [], failedRequests: [] };
const response = await fetch(new URL('main.dart.js', url));
assert.ok(response.ok);
report.mainJsSha256 = hash(Buffer.from(await response.arrayBuffer()));
assert.equal(report.mainJsSha256, expectedHash.toLowerCase());
const browser = await chromium.launch(chromiumLaunchOptions({ args }));
const context = await browser.newContext({ viewport: { width: 1440, height: 1100 }, acceptDownloads: true });
const page = await context.newPage();
const verifyLoadedScript = observeMainScript(page, report);
page.on('pageerror', error => report.pageErrors.push(String(error)));
page.on('console', message => { if (message.type() === 'error') report.consoleErrors.push(message.text()); });
page.on('requestfailed', request => report.failedRequests.push(request.url()));
async function uiText() {
  const host = page.locator('flt-semantics-host');
  return await host.count() ? host.evaluate(node => [node.innerText,
    ...[...node.querySelectorAll('[aria-label]')].map(item => item.getAttribute('aria-label'))].filter(Boolean).join('\n')) : '';
}
async function wait(pattern) {
  for (let i = 0; i < 200; i++) {
    if (pattern.test(await uiText())) return;
    await page.waitForTimeout(100);
  }
  throw new Error(`Missing ${pattern}: ${await uiText()}`);
}
async function click(name) {
  await page.getByRole('button', { name }).first().click();
  await page.mouse.move(2, 2);
  await page.waitForTimeout(200);
  if (String(name).includes('Back to directory')) await top();
}
async function top() {
  await page.mouse.move(page.viewportSize().width * .76, page.viewportSize().height * .55);
  await page.mouse.wheel(0, -10000); await page.waitForTimeout(200);
}
async function capture(name) {
  await page.waitForTimeout(350);
  await page.screenshot({ path: resolve(output, `${name}.png`), fullPage: true });
  await writeFile(resolve(output, `${name}.txt`), await uiText());
  report.screenshots.push(`${name}.png`);
}
async function exportGame(name) {
  await click(/^Save & exit/); await wait(/Start a New Game/);
  await click(/^Load & Manage Saves/); await click(/^A(?:\s|$)/);
  await wait(/Manage .*Saved Game/);
  const downloading = page.waitForEvent('download');
  await click(/Export Save File/);
  const path = resolve(output, `${name}.json`);
  await (await downloading).saveAs(path);
  const state = decode(JSON.parse(await readFile(path, 'utf8')));
  await click(/^L Load Game/); await wait(/Save & exit/);
  return state;
}
async function search(text) {
  await top();
  const input = page.getByRole('textbox', { name: /Find anyone/ });
  await input.fill(text); await page.waitForTimeout(250);
}
async function row(name, screenshot) {
  const target = page.getByRole('button', { name: new RegExp(`^Open dossier for ${name}\\.`) });
  for (let i = 0; i < 18; i++) {
    const box = await target.boundingBox().catch(() => null);
    if (box && box.y > 75 && box.y + box.height < page.viewportSize().height - 70) break;
    await page.mouse.move(page.viewportSize().width * .76, page.viewportSize().height * .55);
    await page.mouse.wheel(0, 180); await page.waitForTimeout(150);
  }
  if (screenshot) await capture(screenshot);
  await target.click(); await page.mouse.move(2, 2); await page.waitForTimeout(300);
}
async function openHelp(locator = page) {
  await locator.getByRole('button', { name: /Juice 160/ }).first().click();
  await page.getByRole('alertdialog').waitFor();
  await wait(/Juice.*experience.*standing/);
}
async function closeHelp() {
  await page.getByRole('alertdialog').getByRole('button', { name: /^Close$/ }).click();
  await page.waitForTimeout(180);
}
async function helpTextGeometry(prefix, fullSize) {
  return page.getByRole('alertdialog').evaluate((dialog, { prefix, fullSize }) => {
    const bounds = node => {
      const box = node.getBoundingClientRect();
      return { left: box.left, top: box.top, right: box.right, bottom: box.bottom, width: box.width, height: box.height };
    };
    const describe = node => ({ tag: node.tagName, id: node.id, role: node.getAttribute('role'),
      text: node.textContent?.trim(), ariaLabel: node.getAttribute('aria-label'), rect: bounds(node) });
    const nodes = [...dialog.querySelectorAll('*')];
    const matches = nodes.filter(node => [node.textContent?.trim(), node.getAttribute('aria-label')]
      .some(text => text?.startsWith(prefix)));
    // Flutter's semantic node describes the painted paragraph. Its stretched,
    // single-line DOM span can have a different height from the painted text.
    const target = matches.find(node => node.tagName === 'FLT-SEMANTICS' && bounds(node).height > 0);
    const close = nodes.find(node => node.getAttribute('role') === 'button'
      && [node.textContent?.trim(), node.getAttribute('aria-label')].includes('Close'));
    const visibleClip = { left: 0, top: 0, right: innerWidth, bottom: innerHeight };
    const clips = [], unsupportedClips = [];
    for (let node = target?.parentElement; node; node = node.parentElement) {
      const style = getComputedStyle(node), rect = bounds(node);
      const clipX = /hidden|clip|auto|scroll/.test(style.overflowX);
      const clipY = /hidden|clip|auto|scroll/.test(style.overflowY);
      if (clipX || clipY) {
        clips.push({ id: node.id, rect, overflowX: style.overflowX, overflowY: style.overflowY, scrollTop: node.scrollTop });
        if (clipX) { visibleClip.left = Math.max(visibleClip.left, rect.left); visibleClip.right = Math.min(visibleClip.right, rect.right); }
        if (clipY) { visibleClip.top = Math.max(visibleClip.top, rect.top); visibleClip.bottom = Math.min(visibleClip.bottom, rect.bottom); }
      }
      if (style.clip !== 'auto' || style.clipPath !== 'none') unsupportedClips.push({ id: node.id, clip: style.clip, clipPath: style.clipPath });
    }
    const surface = dialog.getRootNode();
    const hit = (node, x, y) => {
      const top = (surface.elementsFromPoint?.(x, y) ?? document.elementsFromPoint(x, y))[0];
      return { x, y, ownsTarget: Boolean(top && (top === node || node.contains(top))), top: top ? describe(top) : null };
    };
    const closeRect = close ? bounds(close) : null;
    const closeHit = closeRect ? hit(close, closeRect.left + closeRect.width / 2, closeRect.top + closeRect.height / 2) : null;
    const closeVisible = Boolean(closeRect && closeRect.width > 0 && closeRect.height > 0 && closeRect.left >= 0
      && closeRect.top >= 0 && closeRect.right <= innerWidth && closeRect.bottom <= innerHeight && closeHit.ownsTarget);
    if (closeRect) visibleClip.bottom = Math.min(visibleClip.bottom, closeRect.top);
    const rect = target ? bounds(target) : null;
    const hits = rect ? [[rect.left + 2, rect.top + 2], [rect.left + rect.width / 2, rect.top + rect.height / 2], [rect.right - 2, rect.bottom - 2]]
      .map(([x, y]) => hit(target, x, y)) : [];
    const fullyVisible = Boolean(rect && rect.width > 0 && rect.height > 0 && !unsupportedClips.length && closeVisible
      && (!fullSize || (rect.width >= fullSize.width - .5 && rect.height >= fullSize.height - .5))
      && rect.left >= visibleClip.left - .5 && rect.top >= visibleClip.top - .5
      && rect.right <= visibleClip.right + .5 && rect.bottom <= visibleClip.bottom + .5 && hits.every(point => point.ownsTarget));
    return { prefix, fullSize, viewport: { width: innerWidth, height: innerHeight }, dialog: bounds(dialog),
      candidates: matches.map(describe), target: target ? describe(target) : null,
      clips, unsupportedClips, visibleClip, hits, close: close ? describe(close) : null, closeHit, closeVisible, fullyVisible };
  }, { prefix, fullSize });
}
try {
  await page.goto(url, { waitUntil: 'domcontentloaded' }); await wait(/Start a New Game/);
  const choosing = page.waitForEvent('filechooser'); await click(/^Import a Save/);
  await (await choosing).setFiles(fixturePath); await wait(/Save imported/);
  await page.keyboard.press('Enter'); await wait(/Start a New Game/);
  await click(/^Load & Manage Saves/); await click(/^A(?:\s|$)/); await wait(/Manage .*Saved Game/);
  await click(/^L Load Game/); await wait(/Save & exit/);
  const before = await exportGame('before-inspection');
  await wait(/Juice 160/); await capture('01-hq-juice-visible');
  report.checks.push('Selected HQ identity and crew show numeric Juice');
  await click(/^Inspect Artie Activist(?:\s|$)/); await wait(/Full dossier/);
  await openHelp(); await wait(/40 more Juice.*Urban Commando at 200/);
  await wait(/30%/); await wait(/Wisdom is unaffected/);
  await wait(/personal recruitment capacity/); await capture('02-juice-help');
  const helpText = await uiText();
  assert.match(helpText, /Community Service.*10/); assert.match(helpText, /Disobedience.*50/);
  assert.match(helpText, /Hacking.*200/); assert.match(helpText, /does not instantly add trained skill levels/);
  await closeHelp(); report.checks.push('Portrait inspection exposes clickable Juice help explaining exact current bonus, next rank, caps, capacity and separate skill XP');
  await wait(/40 to Urban Commando \(200\)/);
  await capture('03-nonmodal-inspector-juice');
  await click(/^Full dossier/); await page.getByRole('dialog').last().waitFor();
  await wait(/40 to Urban Commando \(200\)/); await wait(/30%/);
  await capture('04-dossier-current-next');
  await openHelp(page.getByRole('dialog')); await wait(/40 more Juice/); await closeHelp();
  await page.getByRole('dialog').getByRole('button', { name: 'Close dossier', exact: true }).last().click();
  await click(/^Close crew inspection/);
  report.checks.push('Inspector and full dossier show current Juice, rank benefits and next milestone; nested help closes safely');
  await click(/^People(?:$|[.\s])/); await wait(/Personnel directory/); await wait(/Juice 160/);
  await page.getByText('Sort: Name', { exact: true }).click();
  await page.getByRole('menuitem', { name: 'Sort: Juice', exact: true }).click();
  await wait(/Sort: Juice/); await capture('05-directory-juice-sort');
  const labels = await page.getByRole('button', { name: /^Open dossier for/ }).allTextContents();
  const semantics = await page.getByRole('button', { name: /^Open dossier for/ }).evaluateAll(nodes => nodes.map(node => node.getAttribute('aria-label') ?? node.textContent));
  assert.match(semantics[0] ?? labels[0], /Elite Example/);
  assert.match(semantics[0] ?? labels[0], /1000/);
  report.checks.push('Directory rows expose Juice and sort strongest first');
  await search('Chaz'); await row('Chaz Reasoner'); await wait(/Back to directory/);
  await wait(/Juice 160/); await wait(/40 to Urban Commando \(200\)/);
  await capture('06-hospital-native-profile-juice');
  await click(/^Back to directory$/); await click(/^Organisation(?:$|\s)/);
  await page.setViewportSize({ width: 1024, height: 720 });
  await click(/^Reading size$/); await page.getByRole('menuitem', { name: '150%', exact: true }).click();
  await click(/^Inspect Artie Activist(?:\s|$)/); await wait(/Full dossier/);
  await openHelp(); await wait(/40 more Juice/); await capture('07-1024x720-at150-help');
  // Preserve the full offscreen text size before scrolling: Flutter can trim a
  // partially clipped semantic rectangle while retaining its complete label.
  const initialEarning = await helpTextGeometry('Earning Juice');
  const initialCaps = await helpTextGeometry('Successful actions can award Juice');
  report.enlargedHelpGeometry = { initialEarning, initialCaps, earning: [] };
  await writeFile(resolve(output, 'enlarged-help-geometry.json'), JSON.stringify(report.enlargedHelpGeometry, null, 2));
  assert.ok(initialEarning.target?.rect && initialCaps.target?.rect, 'Help must expose its complete earning and cap paragraphs.');
  let earning;
  for (let step = 0; step < 12; step++) {
    earning = await helpTextGeometry('Earning Juice', initialEarning.target.rect);
    report.enlargedHelpGeometry.earning.push(earning);
    if (earning.fullyVisible) break;
    await page.mouse.move(400, 330); await page.mouse.wheel(0, 250); await page.waitForTimeout(120);
  }
  earning = await helpTextGeometry('Earning Juice', initialEarning.target.rect);
  report.enlargedHelpGeometry.earning.push(earning);
  await writeFile(resolve(output, 'enlarged-help-geometry.json'), JSON.stringify(report.enlargedHelpGeometry, null, 2));
  assert.ok(earning.fullyVisible, 'Earning guidance must scroll fully inside the actual unclipped help viewport with Close visible.');
  await capture('08-1024x720-at150-earning');
  await page.mouse.move(400, 330); await page.mouse.wheel(0, 650); await page.waitForTimeout(200);
  const caps = report.enlargedHelpGeometry.caps = await helpTextGeometry('Successful actions can award Juice', initialCaps.target.rect);
  await writeFile(resolve(output, 'enlarged-help-geometry.json'), JSON.stringify(report.enlargedHelpGeometry, null, 2));
  await writeFile(resolve(output, 'enlarged-help-semantics.html'), await page.getByRole('alertdialog').innerHTML());
  assert.ok(caps.fullyVisible, 'The complete activity cap paragraph must fit the actual unclipped help viewport with Close visible.');
  assert.match(caps.target.text || caps.target.ariaLabel, /Community Service.*10.*Disobedience.*50.*Hacking.*200.*Outcomes and risks vary\./);
  await capture('09-1024x720-at150-caps');
  await closeHelp(); await wait(/Juice 160/);
  report.checks.push('1024x720 at 150 percent help reads, scrolls and dismisses without losing underlying game');
  await page.setViewportSize({ width: 1440, height: 1100 });
  await click(/^Close crew inspection/);
  const after = await exportGame('after-inspection');
  assert.deepEqual(after, before, 'Entire exported campaign must remain identical.');
  report.campaignSha256 = hash(JSON.stringify(before));
  report.checks.push('Entire campaign exports match before and after all Juice browsing');
  await verifyLoadedScript(expectedHash.toLowerCase());
  assert.deepEqual(report.pageErrors, []); assert.deepEqual(report.consoleErrors, []); assert.deepEqual(report.failedRequests, []);
  report.checks.push('Exact-build Edge run has no page, console or network failures');
  report.status = 'passed';
} catch (error) {
  report.status = 'failed'; report.error = String(error.stack ?? error);
  await capture('failure').catch(() => {}); throw error;
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  await context.close(); await browser.close();
}
console.log(JSON.stringify({ status: report.status, checks: report.checks.length, screenshots: report.screenshots.length }));



