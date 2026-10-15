// Visual review through ordinary UI in an isolated browser context.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
const root = resolve(import.meta.dirname, '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const url = process.argv[2] ?? 'http://127.0.0.1:8766/';
const out = resolve(root, 'reports/district-map-review');
await mkdir(out, { recursive: true });
const browser = await chromium.launch({ channel: 'msedge', headless: true });
const context = await browser.newContext({ viewport: { width: 1600, height: 1000 } });
const page = await context.newPage();
const report = { errors: [], atlasLoaded: false, siteAtlases: [], screenshots: [] };
page.on('pageerror', e => report.errors.push(e.message));
page.on('response', r => {
  if (r.url().endsWith('district_atlas_v1.png') && r.ok()) report.atlasLoaded = true;
  const siteAtlas = r.url().match(/site_atlas_([123])_v1\.png$/)?.[1];
  if (siteAtlas && r.ok() && !report.siteAtlases.includes(siteAtlas)) {
    report.siteAtlases.push(siteAtlas);
  }
});
async function text() {
  return page.locator('flt-semantics-host').evaluate(h => [h.innerText,
    ...[...h.querySelectorAll('[aria-label]')].map(n => n.getAttribute('aria-label'))].join('\n'));
}
async function wait(pattern) {
  for (let i = 0; i < 150; i++) {
    if (await page.locator('flt-semantics-host').count() && pattern.test(await text())) return;
    await page.waitForTimeout(100);
  }
  throw Error(`Missing ${pattern}: ${await text()}`);
}
async function click(name) {
  const accessibleName = typeof name === 'string'
    ? new RegExp(`^${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?:$|\\s)`)
    : name;
  await page.getByRole('button', { name: accessibleName }).first().click();
  await page.waitForTimeout(200);
}
async function shot(name) {
  await page.mouse.move(1, 1);
  await page.waitForTimeout(350);
  await page.screenshot({ path: resolve(out, `${name}.png`) });
  await writeFile(resolve(out, `${name}.txt`), await text());
  report.screenshots.push(`${name}.png`);
}
try {
  await page.goto(url, { waitUntil: 'networkidle' });
  await wait(/Start a new movement|Start a New Game/);
  await page.waitForTimeout(1200);
  const chooser = page.waitForEvent('filechooser');
  chooser.catch(() => {});
  await click('Import a Save');
  await shot('import-dialog');
  await (await chooser).setFiles(resolve(root, 'upstream/test/saves/felix_1_0.json'));
  await wait(/Save imported/);
  await page.keyboard.press('Enter');
  await click('Load & Manage Saves');
  await click(/^A(?:\s|$)/);
  await click(/^L Load Game/);
  await wait(/Save & exit/);
  await click('City maps');
  await wait(/\. district/);
  for (const [width, height] of [[1600, 1000], [1280, 720], [800, 700]]) {
    await page.setViewportSize({ width, height });
    await shot(`districts-${width}x${height}`);
  }
  await page.setViewportSize({ width: 1600, height: 1000 });
  await click(/University.*\. district/);
  await wait(/\. site/);
  await shot('university-sites');
  await click('Zoom in');
  await shot('zoomed-sites');
  await click('Fit all locations');
  await click('Show location index');
  await shot('location-index');
  await click('Organisation');
  await shot('organisation-map-1600x1000');
  await page.setViewportSize({ width: 1280, height: 720 });
  await shot('organisation-map-1280x720');
  assert.ok(report.atlasLoaded, 'The generated atlas must load in the actual application.');
  assert.deepEqual(report.siteAtlases.sort(), ['1', '2', '3'],
    'Real University sites must load all three building artwork sheets.');
  assert.deepEqual(report.errors, []);
  report.status = 'passed';
} catch (error) {
  report.status = 'failed';
  report.failure = String(error);
  await shot('failure');
  process.exitCode = 1;
} finally {
  await writeFile(resolve(out, 'report.json'), JSON.stringify(report, null, 2));
  await browser.close();
  console.log(JSON.stringify(report, null, 2));
}
