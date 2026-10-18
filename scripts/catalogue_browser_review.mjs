// Isolated, compiled-player visual review of catalogue art and read-only guides.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromiumLaunchOptions } from './browser_support.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const args = process.argv.slice(2);
const arg = (key, fallback) => args.includes(key) ? args[args.indexOf(key) + 1] : fallback;
const url = new URL(arg('--url', 'http://127.0.0.1:18883/'));
assert.equal(url.href, 'http://127.0.0.1:18883/', 'Use the separate catalogue QA origin; never player storage.');
const output = resolve(root, arg('--out', 'reports/catalogue-art-qa/browser'));
await mkdir(output, { recursive: true });
const expectedHash = arg('--expected-hash', '');
assert.match(expectedHash, /^[a-f0-9]{64}$/i);
const hash = data => createHash('sha256').update(data).digest('hex');
assert.equal(hash(Buffer.from(await (await fetch(new URL('main.dart.js', url))).arrayBuffer())), expectedHash);
const decode = envelope => typeof envelope.saveData === 'string' ? JSON.parse(envelope.saveData) : envelope.saveData;
const envelope = JSON.parse(await readFile(resolve(root, 'upstream/test/saves/felix_1_0.json'), 'utf8'));
const state = decode(envelope);
for (const person of state.lcs.pool) {
  person.wantedForCrimes = Object.fromEntries(Object.keys(person.wantedForCrimes).map(key => [key, 0]));
  person.heat = 0;
  person.activity = { type: 'none' };
}
const base = state.cities.flatMap(city => city.districts.flatMap(district => district.sites))
  .find(site => site.id === state.lcs.pool[0].baseId);
base.loot = [
  { typeName: 'WEAPON_9MM_HANDGUN', stackSize: 1, ammo: 0, loadedAmmoId: null },
  { typeName: 'WEAPON_COMBATKNIFE', stackSize: 1, ammo: 0, loadedAmmoId: null },
  { typeName: 'WEAPON_CROWBAR', stackSize: 1, ammo: 0, loadedAmmoId: null },
  { typeName: 'CLOTHING_CHEAPSUIT', stackSize: 1, bloody: false, damaged: false },
  { typeName: 'CLOTHING_LABCOAT', stackSize: 1, bloody: false, damaged: false },
  { typeName: 'AMMO_9MM', stackSize: 20 },
  { typeName: 'LOOT_COMPUTER', stackSize: 1 },
];
state.lcs.vehiclePool = ['BUG', 'HMMWV', 'JEEP', 'PICKUP', 'POLICECAR', 'AGENTCAR', 'SPORTSCAR', 'STATIONWAGON', 'SUV', 'TAXICAB', 'VAN']
  .map(typeName => ({ id: state.nextVehicleId++, typeName, color: 'Grey', year: 2020, heat: 0, locationId: base.id }));
state.lcs.pool[0].carId = state.lcs.vehiclePool[0].id;
state.lcs.pool[0].preferredCarId = state.lcs.vehiclePool[0].id;
state.lcs.pool[0].isDriver = true;
state.lcs.pool[0].preferredDriver = true;
envelope.saveData = typeof envelope.saveData === 'string' ? JSON.stringify(state) : state;
const fixture = resolve(output, 'prepared-catalogue-campaign.json');
await writeFile(fixture, JSON.stringify(envelope));
const report = {
  status: 'running', expectedHash,
  prepared: 'Bundled Felix campaign with charges/heat/orders cleared, seven stored items and eleven vehicles explicitly supplied for visual inspection. Founder is assigned the first vehicle. No earned equipment or vehicle outcomes are claimed. Fresh browser contexts only.',
  screens: [], loadedAtlases: [], loadedMainJsHashes: [], errors: [],
};
const browser = await chromium.launch(chromiumLaunchOptions({ args }));
const pendingHashes = [];
try {
  for (const large of [false, true]) {
    const context = await browser.newContext({ viewport: large ? { width: 800, height: 600 } : { width: 1440, height: 1000 }, acceptDownloads: true });
    const page = await context.newPage();
    page.setDefaultTimeout(15000);
    const prefix = large ? 'large' : 'desktop';
    page.on('pageerror', error => report.errors.push(String(error)));
    page.on('console', message => { if (message.type() === 'error') report.errors.push(message.text()); });
    page.on('response', response => {
      if (response.url().endsWith('/main.dart.js')) pendingHashes.push(response.body().then(body => report.loadedMainJsHashes.push(hash(body))));
      if (/journal_(?:equipment_(?:weapons|gear)|vehicles)_v1\.webp$/.test(response.url())) {
        assert.equal(response.status(), 200);
        report.loadedAtlases.push(response.url().split('/').at(-1));
      }
    });
    const uiText = () => page.locator('flt-semantics-host').evaluate(host => [host.innerText, ...[...host.querySelectorAll('[aria-label]')].map(node => node.getAttribute('aria-label'))].join('\n'));
    const wait = pattern => page.waitForFunction(source => {
      const host = document.querySelector('flt-semantics-host');
      return host && new RegExp(source, 'i').test([host.innerText, ...[...host.querySelectorAll('[aria-label]')].map(node => node.getAttribute('aria-label'))].join('\n'));
    }, pattern.source, { timeout: 30000 });
    const click = async name => {
      await page.getByRole('button', { name }).first().click();
      await page.mouse.move(2, 2);
      await page.waitForTimeout(200);
    };
    const reveal = async target => {
      await target.waitFor({ state: 'attached' });
      for (let attempt = 0; attempt < 35; attempt++) {
        const box = await target.boundingBox();
        if (box && box.y > 90 && box.y + box.height < page.viewportSize().height - 80) return;
        await page.mouse.move(page.viewportSize().width * 0.77, page.viewportSize().height * 0.57);
        await page.mouse.wheel(0, box && box.y < 90 ? -180 : 250);
        await page.waitForTimeout(120);
      }
      assert.fail('Expected catalogue control could not be brought fully into view.');
    };
    const capture = async name => {
      await page.mouse.move(2, 2);
      await page.waitForTimeout(600);
      const text = await uiText();
      assert.doesNotMatch(text, /A RenderFlex overflowed|Unhandled exception/i);
      const filename = `${prefix}-${name}`;
      await page.screenshot({ path: resolve(output, `${filename}.png`), fullPage: true });
      await writeFile(resolve(output, `${filename}.txt`), text);
      report.screens.push(filename);
      console.log(`PASS ${filename}`);
    };
    const exportGame = async name => {
      await click(/^Save & exit/); await wait(/Start a New Game/);
      await click(/^Load & Manage Saves/); await click(/^A(?:\s|$)/);
      const downloading = page.waitForEvent('download');
      await click(/Export Save File/);
      const filename = resolve(output, `${prefix}-${name}.json`);
      await (await downloading).saveAs(filename);
      const data = decode(JSON.parse(await readFile(filename, 'utf8')));
      await click(/^L Load Game/); await wait(/Save & exit/);
      return data;
    };
    await page.goto(url.href, { waitUntil: 'networkidle' }); await wait(/Start a New Game/);
    const choosing = page.waitForEvent('filechooser'); await click(/^Import a Save/);
    await (await choosing).setFiles(fixture); await wait(/Save imported/);
    await page.keyboard.press('Enter'); await wait(/Start a New Game/);
    await click(/^Load & Manage Saves/); await click(/^A(?:\s|$)/); await click(/^L Load Game/); await wait(/Save & exit/);
    if (large) {
      await click(/^Reading size/);
      await page.getByRole('menuitem', { name: '150%', exact: true }).click();
    }
    const before = await exportGame('before-inspection');
    await click(/^Weapons(?:$|[.\s])/); await wait(/Equip the Squad|Equipment/);
    for (const [guide, id] of [[/^Weapons guide/, 'weapons'], [/^Clothing & armour guide/, 'clothing']]) {
      await click(guide); await capture(`guide-${id}`);
      await page.getByRole('button', { name: 'Close decision guide', exact: true }).click();
    }
    await reveal(page.getByRole('button', { name: /^A 9mm Pistol/ }).first());
    await capture('equipment-inventory');
    await page.keyboard.press('Escape'); await wait(/Save & exit/);
    await click(/^Vehicles(?:$|[.\s])/);
    await click(/^Vehicles guide/); await capture('guide-vehicles');
    await page.getByRole('button', { name: 'Close decision guide', exact: true }).click();
    await reveal(page.getByRole('button', { name: /^A Grey 2020 Bug/ }).first());
    await capture('vehicle-choices');
    await reveal(page.getByRole('button', { name: /^K Grey 2020 Van/ }).first());
    await capture('vehicle-choices-last');
    await page.keyboard.press('Escape'); await wait(/Save & exit/);
    await click(/^Inspect Felix Kobayashi(?:$|\s)/);
    await click(/^Full dossier/); await capture('dossier');
    const dialog = page.getByRole('dialog').last();
    await reveal(dialog.getByRole('button', { name: /^Weapons guide/ }).first());
    await capture('dossier-equipment');
    await page.getByRole('dialog').getByRole('button', { name: 'Close dossier', exact: true }).last().click();
    const after = await exportGame('after-inspection');
    assert.deepEqual(after, before, `${prefix} inspection must preserve the complete campaign`);
    await context.close();
  }
  await Promise.all(pendingHashes);
  assert.ok(report.loadedMainJsHashes.length >= 2);
  assert.ok(report.loadedMainJsHashes.every(value => value === expectedHash));
  assert.equal(new Set(report.loadedAtlases).size, 3);
  assert.deepEqual(report.errors, []);
  report.status = 'passed';
} catch (error) {
  report.status = 'failed'; report.errors.push(String(error));
} finally {
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  await browser.close();
}
console.log(JSON.stringify({ status: report.status, screens: report.screens.length, errors: report.errors, output }));
if (report.status !== 'passed') process.exitCode = 1;
