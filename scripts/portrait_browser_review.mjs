// Focused browser acceptance of actual portrait atlas rendering and save identity.
// Uses an isolated browser context, ordinary game controls and portable exports.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const { PNG } = require('pngjs');
const args = process.argv.slice(2);
const arg = (name, fallback) => args.includes(name) ? args[args.indexOf(name) + 1] : fallback;
const url = arg('--url', 'http://127.0.0.1:8765/');
const output = resolve(root, arg('--out', `reports/portrait-browser-${new Date().toISOString().replaceAll(':', '-')}`));
await mkdir(output, { recursive: true });
const report = { status: 'running', url, started: new Date().toISOString(), pageErrors: [], consoleErrors: [], failedRequests: [], atlasResponses: [], screenshots: [], checks: [] };
const main = await fetch(new URL('main.dart.js', url));
assert.ok(main.ok);
report.mainJsSha256 = createHash('sha256').update(Buffer.from(await main.arrayBuffer())).digest('hex');
const browser = await chromium.launch({ channel: 'msedge', headless: true });
const context = await browser.newContext({ viewport: { width: 1600, height: 1000 }, acceptDownloads: true });
const page = await context.newPage();
page.on('pageerror', error => report.pageErrors.push(error.message));
page.on('console', message => { if (message.type() === 'error') report.consoleErrors.push(message.text()); });
page.on('requestfailed', request => report.failedRequests.push({ url: request.url(), failure: request.failure()?.errorText }));
page.on('response', response => {
  if (!/portraits_v2\/batch_\d+\.png/.test(response.url())) return;
  let fromPage = false;
  try { fromPage = response.request().frame() === page.mainFrame(); } catch {}
  report.atlasResponses.push({ url: response.url(), status: response.status(), fromPage });
});

async function text() {
  return page.locator('flt-semantics-host').evaluate(host => [host.innerText, ...[...host.querySelectorAll('[aria-label]')].map(node => node.getAttribute('aria-label'))].filter(Boolean).join('\n'));
}
async function wait(pattern) {
  const deadline = Date.now() + 20000;
  let actual = '';
  while (Date.now() < deadline) {
    if (await page.locator('flt-semantics-host').count()) {
      actual = await text();
      if (pattern.test(actual)) return;
    }
    await page.waitForTimeout(100);
  }
  throw new Error(`Missing ${pattern}: ${actual}`);
}
async function click(name) {
  const button = page.getByRole('button', { name }).first();
  await button.waitFor();
  await button.click();
  await page.waitForTimeout(250);
}
async function shot(name) {
  await page.mouse.move(2, 2);
  await page.screenshot({ path: resolve(output, `${name}.png`), fullPage: true });
  await writeFile(resolve(output, `${name}.txt`), await text());
  report.screenshots.push(`${name}.png`);
}
async function journal() {
  await page.getByRole('button', { name: 'Save & exit', exact: true }).waitFor();
  await wait(/Organisation/);
}
async function exportSave(name) {
  await click('Save & exit');
  await wait(/Continue (?:your campaign|Last Game|as )/);
  await click('Load & Manage Saves');
  await click(/^A(?:\s|$)/);
  await wait(/Manage .*Saved Game/);
  const pending = page.waitForEvent('download');
  await click(/Export Save File/);
  const download = await pending;
  const path = resolve(output, `${name}.json`);
  await download.saveAs(path);
  const save = JSON.parse(await readFile(path, 'utf8'));
  return typeof save.saveData === 'string' ? JSON.parse(save.saveData) : save.saveData;
}
function mean(png, box) {
  const sum = [0, 0, 0];
  let count = 0;
  for (let y = Math.ceil(box.y); y < box.y + box.height; y++) {
    for (let x = Math.ceil(box.x); x < box.x + box.width; x++) {
      const offset = (y * png.width + x) * 4;
      for (let channel = 0; channel < 3; channel++) sum[channel] += png.data[offset + channel];
      count++;
    }
  }
  return sum.map(value => value / count);
}

try {
  await page.goto(url, { waitUntil: 'networkidle' });
  await wait(/Start a new movement|Start a New Game/);
  const chooser = page.waitForEvent('filechooser');
  await click('Import a Save');
  await (await chooser).setFiles(resolve(root, 'upstream/test/saves/felix_1_0.json'));
  await wait(/Save imported/);
  await page.keyboard.press('Enter');
  await wait(/Start a new movement|Start a New Game/);
  await click('Load & Manage Saves');
  await click(/^A(?:\s|$)/);
  await wait(/Manage .*Saved Game/);
  await click(/^L Load Game/);
  await journal();
  await page.waitForTimeout(1000);
  await shot('01-crew-portraits');
  const fixture = JSON.parse(await readFile(resolve(root, 'upstream/test/saves/felix_1_0.json'), 'utf8'));
  const original = typeof fixture.saveData === 'string' ? JSON.parse(fixture.saveData) : fixture.saveData;
  const originalCrew = original.lcs.pool.filter(person => person.alive && person.align === 'liberal' && !person.sleeperAgent);
  const captured = [];
  for (const person of originalCrew) {
    const escaped = person.name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    await click(new RegExp(`^Select crew ${escaped}(?:$|\\s)`));
    await page.waitForTimeout(400);
    const portrait = page.getByRole('button', { name: new RegExp(`^Inspect ${escaped}(?:$|\\s)`) }).first();
    const box = await portrait.boundingBox();
    assert.ok(box && box.width > 12 && box.height > 12, `Visible portrait button for ${person.name}`);
    const pixels = PNG.sync.read(await page.screenshot({ clip: box, path: resolve(output, `portrait-${person.id}.png`) }));
    captured.push({ name: person.name, box, average: mean(pixels, { x: pixels.width * .2, y: pixels.height * .2, width: pixels.width * .6, height: pixels.height * .6 }) });
  }  const saved = await exportSave('crew-with-portrait-identities');
  const crew = saved.lcs.pool.filter(person => person.alive && person.align === 'liberal' && !person.sleeperAgent);
  assert.equal(crew.length, 5);
  assert.equal(new Set(crew.map(person => person.portraitId)).size, 5);
  report.crew = [];
  for (const person of crew) {
    assert.ok(Number.isInteger(person.portraitId) && person.portraitId >= 0 && person.portraitId < 250);
    const batch = String(Math.floor(person.portraitId / 16)).padStart(2, '0');
    const cell = person.portraitId % 16;
    const asset = `assets/modern/portraits_v2/batch_${batch}.png`;
    assert.ok(report.atlasResponses.some(response => response.url.endsWith(asset) && response.status === 200 && response.fromPage), `Application must request ${asset}`);
    const capture = captured.find(item => item.name === person.name);
    assert.ok(capture, `Visible image for ${person.name}`);
    const atlas = PNG.sync.read(await readFile(resolve(root, 'upstream', asset)));
    const width = atlas.width / 4, height = atlas.height / 4;
    const expected = mean(atlas, { x: (cell % 4 + .2) * width, y: (Math.floor(cell / 4) + .2) * height, width: width * .6, height: height * .6 });
    const difference = capture.average.map((value, index) => Math.abs(value - expected[index]));
    assert.ok(Math.max(...difference) < 18, `Rendered portrait must match atlas cell for ${person.name}: difference ${difference}`);
    report.crew.push({ id: person.id, name: person.name, portraitId: person.portraitId, asset, cell, averageRgbDifference: difference });
  }
  report.checks.push('Five saved distinct portrait IDs match the actual rendered atlas-cell colours.');
  await click(/^L Load Game/);
  await journal();
  await page.waitForTimeout(500);
  await shot('02-saved-portraits-reloaded');
  const reloaded = await exportSave('reloaded-portrait-identities');
  assert.deepEqual(reloaded.lcs.pool.map(person => [person.id, person.portraitId]), saved.lcs.pool.map(person => [person.id, person.portraitId]));
  report.checks.push('Saving and reloading preserves every crew portrait identity.');
  assert.deepEqual(report.pageErrors, []);
  assert.deepEqual(report.consoleErrors, []);
  assert.deepEqual(report.failedRequests, []);
  report.status = 'passed';
} catch (error) {
  report.status = 'failed';
  report.error = error.stack ?? String(error);
  process.exitCode = 1;
  try { await shot('FAILURE'); } catch {}
  console.error(report.error);
} finally {
  report.completed = new Date().toISOString();
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  await context.close();
  await browser.close();
  console.log(JSON.stringify({ output, status: report.status, checks: report.checks, mainJsSha256: report.mainJsSha256 }, null, 2));
}

