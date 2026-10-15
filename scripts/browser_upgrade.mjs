// Validate an actual prior QA browser profile across a packaged app update.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const args = process.argv.slice(2);
const argument = (flag, fallback) => args.includes(flag) ? args[args.indexOf(flag) + 1] : fallback;
const url = argument('--url', 'http://127.0.0.1:18876/');
const packageRoot = resolve(argument('--package-root', ''));
const profile = resolve(argument('--profile', ''));
assert.ok(profile.toLowerCase().startsWith((resolve(root, '.local/browser-profiles') + sep).toLowerCase()), 'Only this project\'s isolated QA profiles may be used.');
const packageInfo = JSON.parse(await readFile(resolve(packageRoot, 'BUILD_INFO.json'), 'utf8'));
assert.equal(packageInfo.project, 'LiberalCrimeSquad2026');
const health = await (await fetch(new URL('__lcs_launcher_health', url))).json();
assert.equal(health.application, 'lcs-modern-local');
assert.equal(resolve(health.directory).toLowerCase(), resolve(packageRoot, 'web').toLowerCase());
const main = await readFile(resolve(packageRoot, 'web/main.dart.js'));
const expectedHash = createHash('sha256').update(main).digest('hex');
const worker = await readFile(resolve(packageRoot, 'web/sw.js'), 'utf8');
const workerVersion = worker.match(/const VERSION = '([^']+)'/)?.[1];
assert.ok(workerVersion);
const stamp = new Date().toISOString().replaceAll(':', '-').replaceAll('.', '-');
const output = resolve(root, argument('--out', `reports/browser/upgrade-${stamp}`));
await mkdir(output, { recursive: true });
const report = { status: 'running', url, package: packageInfo.package_name, profile, expectedHash, workerVersion, pageErrors: [], consoleErrors: [], screenshots: [] };
const context = await chromium.launchPersistentContext(profile, { channel: 'msedge', headless: true, viewport: { width: 1440, height: 1000 } });
const page = await context.newPage();
page.on('pageerror', error => report.pageErrors.push(error.message));
page.on('console', message => { if (message.type() === 'error') report.consoleErrors.push(message.text()); });
const text = () => page.locator('flt-semantics-host').evaluate(host => [host.innerText, ...[...host.querySelectorAll('[aria-label]')].map(node => node.getAttribute('aria-label')), ...[...host.querySelectorAll('textarea,input')].map(node => node.value)].filter(Boolean).join('\n'));
async function shot(name) { await page.waitForTimeout(180); await page.screenshot({ path: resolve(output, `${name}.png`), fullPage: true }); await writeFile(resolve(output, `${name}.txt`), await text()); report.screenshots.push(`${name}.png`); }
try {
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(async ({ expectedHash, workerVersion }) => {
    const cacheName = `lcs-new-age-${workerVersion}`;
    if (!(await caches.keys()).includes(cacheName)) return false;
    const response = await (await caches.open(cacheName)).match(new URL('main.dart.js', location.href).href);
    if (!response) return false;
    const hash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', await response.arrayBuffer()))].map(byte => byte.toString(16).padStart(2, '0')).join('');
    return hash === expectedHash && !!navigator.serviceWorker.controller;
  }, { expectedHash, workerVersion }, { timeout: 60000 });
  await page.reload({ waitUntil: 'networkidle' });
  await page.getByRole('button', { name: 'Continue your campaign', exact: true }).waitFor();
  await shot('01-upgraded-title');
  report.cache = await page.evaluate(async () => {
    const names = await caches.keys();
    const response = await (await caches.open(names.find(name => name.startsWith('lcs-new-age-')))).match(new URL('main.dart.js', location.href).href);
    return { names, cachedMainSha256: [...new Uint8Array(await crypto.subtle.digest('SHA-256', await response.arrayBuffer()))].map(byte => byte.toString(16).padStart(2, '0')).join('') };
  });
  assert.equal(report.cache.cachedMainSha256, expectedHash);
  await page.getByRole('button', { name: 'Continue your campaign', exact: true }).click();
  await page.getByRole('button', { name: 'Save & exit', exact: true }).first().waitFor();
  const restored = await text();
  assert.match(restored, /QA Founder/);
  assert.match(restored, /4 Jan 2023|January 4, 2023/);
  assert.match(restored, /\$1004\b/);
  assert.match(restored, /Laying Low/);
  await shot('02-upgraded-campaign-preserved');
  report.preservedCampaign = { founder: 'QA Founder', date: 'January 4, 2023', funds: 1004, activity: 'Laying Low' };
  await page.getByRole('button', { name: /^Inspect QA Founder(?: |$)/ }).click();
  await page.getByRole('button', { name: 'Close crew inspection', exact: true }).waitFor();
  assert.equal(await page.getByRole('dialog').count(), 0, 'Upgraded campaign inspection must be nonmodal.');
  await shot('02b-upgraded-nonmodal-inspector');
  await page.getByRole('button', { name: 'Media & impact', exact: true }).click();
  assert.equal(await page.getByRole('button', { name: 'Close crew inspection', exact: true }).count(), 0,
    'Direct section switching must clear inspection without a dismissal click.');
  report.nonblockingNavigation = 'Opened crew inspection, then switched directly to Media without closing it.';
  const article = page.getByRole('button', { name: /^A .*KILLER FOOD/ });
  await article.waitFor();
  await shot('03-upgraded-original-archive');
  await article.click();
  await page.getByRole('heading', { name: 'KILLER FOOD', exact: true }).waitFor();
  await shot('04-upgraded-original-article');
  await page.mouse.move(850, 550);
  await page.mouse.wheel(0, 650);
  await page.waitForTimeout(180);
  const articleText = await text();
  assert.match(articleText, /12\.8%/);
  assert.match(articleText, /Genetics: \+12\.8% Exact recorded change:/);
  assert.doesNotMatch(articleText, /Genetics: \+12\.803436977924854/);
  await page.mouse.move(20, 20); // Keep the optional exact-value tooltip out of the primary card capture.
  await shot('05-upgraded-article-rounded-impact');
  report.originalArticle = { headline: 'KILLER FOOD', roundedImpact: '+12.8%', exactValueRetainedInAccessibleMetadata: true, syntheticData: false };
  await page.getByRole('button', { name: 'Continue', exact: true }).click();
  await page.getByRole('button', { name: /^A .*KILLER FOOD/ }).waitFor();
  await shot('06-upgraded-article-pointer-return');
  report.originalArticle.pointerReturnToArchive = true;
  report.originalProfileBaseline = 'reports/browser/smoke-2026-10-13T21-06-05-742Z/report.json';
  assert.deepEqual(report.pageErrors, []);
  assert.deepEqual(report.consoleErrors, []);
  report.status = 'passed';
} catch (error) {
  report.status = 'failed'; report.failure = error.stack ?? String(error); process.exitCode = 1;
  try { await shot('FAILURE'); } catch { /* Original error remains authoritative. */ }
  console.error(report.failure);
} finally {
  await context.close();
  report.serverStopOutput = execFileSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', resolve(packageRoot, 'scripts/stop.ps1'), '-Port', new URL(url).port], { encoding: 'utf8', windowsHide: true });
  report.completed = new Date().toISOString();
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  console.log(`Upgrade QA ${report.status}: ${output}`);
}
