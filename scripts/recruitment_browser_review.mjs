// Isolated compiled-release recruitment regression; synthetic imported save only.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertQaUrl, chromiumLaunchOptions, observeMainScript } from './browser_support.mjs';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const args = process.argv.slice(2);
const arg = (key, fallback) => args.includes(key) ? args[args.indexOf(key) + 1] : fallback;
const url = assertQaUrl(arg('--url', undefined));
const expected = arg('--expected-hash', '');
assert.match(expected, /^[a-f0-9]{64}$/i);
const output = resolve(root, arg('--out', 'reports/recruitment-qa/browser'));
const relativeOutput = relative(resolve(root, 'reports'), output);
assert.ok(relativeOutput && !relativeOutput.startsWith('..'), 'Evidence must remain under reports/.');
await mkdir(output, { recursive: true });
const envelope = JSON.parse(await readFile(resolve(root, 'upstream/test/saves/felix_1_0.json'), 'utf8'));
const state = typeof envelope.saveData === 'string' ? JSON.parse(envelope.saveData) : envelope.saveData;
for (const person of state.lcs.pool) {
  person.wantedForCrimes = Object.fromEntries(Object.keys(person.wantedForCrimes).map(k => [k, 0]));
  person.heat = 0; person.activity = { type: 'none' };
}
state.lcs.pool[0].activity = { type: 'recruiting' };
state.recruitmentSessions = []; state.datingSessions = [];
envelope.saveData = typeof envelope.saveData === 'string' ? JSON.stringify(state) : state;
const fixture = resolve(output, 'prepared-recruiting.json');
await writeFile(fixture, JSON.stringify(envelope));
const report = { status: 'running', url, expectedHash: expected, fixture,
  prepared: 'Bundled Felix save copy, all charges and heat cleared, all orders idle except founder recruiting; no outcome or profession injected.',
  checks: [], screenshots: [], pageErrors: [], consoleErrors: [], failedRequests: [], loadedMainJsHashes: [] };
const res = await fetch(new URL('main.dart.js', url)); assert.ok(res.ok);
report.actualHash = createHash('sha256').update(Buffer.from(await res.arrayBuffer())).digest('hex');
assert.equal(report.actualHash, expected.toLowerCase());
const browser = await chromium.launch(chromiumLaunchOptions({ args }));
let page, context, verifyLoadedScript;
async function text() {
  if (!await page.locator('flt-semantics-host').count()) return '';
  return page.locator('flt-semantics-host').evaluate(host => [host.innerText,
    ...[...host.querySelectorAll('[aria-label]')].map(n => n.getAttribute('aria-label'))].join('\n'));
}
async function wait(pattern) {
  for (let i = 0; i < 200; i++) { if (pattern.test(await text())) return; await page.waitForTimeout(100); }
  throw Error(`Missing ${pattern}: ${await text()}`);
}
const button = name => page.getByRole('button', { name }).first();
async function click(name) { await button(name).click(); await page.mouse.move(2, 2); await page.waitForTimeout(200); }
async function capture(name) {
  await page.screenshot({ path: resolve(output, `${name}.png`), fullPage: true });
  await writeFile(resolve(output, `${name}.txt`), await text()); report.screenshots.push(`${name}.png`);
}
function check(name) { report.checks.push(name); console.log(`PASS ${name}`); }
async function start(width) {
  if (verifyLoadedScript) await verifyLoadedScript(expected.toLowerCase());
  await context?.close();
  context = await browser.newContext({ viewport: { width, height: width === 1024 ? 720 : 1440 } });
  page = await context.newPage(); page.setDefaultTimeout(12000);
  verifyLoadedScript = observeMainScript(page, report);
  page.on('pageerror', e => report.pageErrors.push(String(e)));
  page.on('console', m => { if (m.type() === 'error') report.consoleErrors.push(m.text()); });
  page.on('requestfailed', r => report.failedRequests.push(r.url()));
  await page.goto(url, { waitUntil: 'networkidle' }); await wait(/Start a New Game/);
  const chooser = page.waitForEvent('filechooser'); await click(/^Import a Save/); await (await chooser).setFiles(fixture);
  await wait(/Save imported/); await page.keyboard.press('Enter'); await wait(/Start a New Game/);
  await click(/^Load & Manage Saves/); await click(/^A(?:\s|$)/); await click(/^L Load Game/); await wait(/Save & exit/);
  if (width === 1024) {
    await click(/^Reading size/); await page.getByRole('menuitem', { name: '150%', exact: true }).click();
  }
  await click(/^(?:Wait a day|Carry out your plans)/);
  for (let i = 0; i < 100; i++) {
    if (/What type of person/.test(await text())) return;
    if (await button(/^Continue$/).count()) await click(/^Continue$/); else await page.waitForTimeout(100);
  }
  throw Error(`No profession reader: ${await text()}`);
}
try {
  for (const width of [2560, 1024]) {
    await start(width); await capture(`professions-${width}`);
    assert.match(await text(), /Meeting difficulty/i);
    assert.match(await text(), /Page 1 of/);
    assert.match(await text(), /Skip recruitment today/);
    const info = page.getByRole('button', { name: /Base attribute ranges:/ }).first();
    await info.click(); await wait(/These are generation ranges/);
    await page.waitForTimeout(700); // Let the dialog's fade transition finish before visual QA.
    await capture(`profession-stats-${width}`);
    await click(/^Close$/); check(`profession stat help at ${width}`);
    const first = await button(/^A /).textContent();
    assert.ok(first, 'Profession A must exist.'); check(`profession choices visible at ${width}`);
    await page.keyboard.press('PageDown'); await page.waitForTimeout(250); await capture(`page-two-${width}`);
    assert.notEqual(await button(/^A /).textContent(), first);
    await page.keyboard.press('PageUp'); await page.waitForTimeout(250);
    assert.equal(await button(/^A /).textContent(), first); check(`profession pagination at ${width}`);
    if (width === 1024) {
      await page.keyboard.press('Escape'); await page.waitForTimeout(250); await capture(`cancel-${width}`);
      assert.doesNotMatch(await text(), /What type of person|asks around for/); check('profession cancellation');
    } else {
      await click(/^A /); await wait(/asks around for/); await capture('asking-around');
      if (await button(/^Continue$/).count()) await click(/^Continue$/); else await page.keyboard.press('Enter');
      await wait(/People to meet/); await capture('candidate-selection');
      assert.ok(await page.getByRole('button', { name: /Meet / }).count()); check('actual daily recruitment creates candidate controls');
    }
  }
  await verifyLoadedScript(expected.toLowerCase());
  assert.ok(report.loadedMainJsHashes.length >= 2, 'Capture the actual loaded JavaScript in both contexts.');
  for (const hash of report.loadedMainJsHashes) assert.equal(hash, expected.toLowerCase());
  assert.deepEqual(report.pageErrors, []); assert.deepEqual(report.consoleErrors, []);
  report.status = 'passed';
} catch (error) {
  report.status = 'failed'; report.failure = String(error); if (page) await capture('failure'); process.exitCode = 1;
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2)); await browser.close();
  console.log(JSON.stringify(report, null, 2));
}


