// Real new-campaign UI review in an isolated headless Chrome profile.
// Does not operate a human browser profile or stop the user's game server.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertQaUrl, chromiumLaunchOptions, observeMainScript, waitForSemantics, waitForUiSettled } from './browser_support.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = require('playwright');
const { PNG } = require('pngjs');
const args = process.argv.slice(2);
const expectedHash = args[args.indexOf('--expected-hash') + 1];
assert.ok(args.includes('--expected-hash'));
assert.match(expectedHash, /^[a-f0-9]{64}$/);
const url = assertQaUrl(args.includes('--url') ? args[args.indexOf('--url') + 1] : 'http://127.0.0.1:18879/');
const stamp = new Date().toISOString().replaceAll(':', '-').replaceAll('.', '-');
const output = resolve(root, args.includes('--out') ? args[args.indexOf('--out') + 1]
  : `reports/browser/creation-${stamp}`);
const profile = resolve(root, `.local/browser-profiles/creation-${stamp}`);
await mkdir(output, { recursive: true });
await mkdir(profile, { recursive: true });
const report = { status: 'running', started: new Date().toISOString(), expectedHash, url,
  scope: 'Real original new-game settings, identity, ten background questions, briefing, public-name entry and playable HQ. Normal and150%/1024x720 manual/fate journeys in an isolated profile.',
  checks: [], screenshots: [], pageErrors: [], consoleErrors: [], failedRequests: [],
  portraitReadiness: [], portraitResponses: [] };
let context, page, verifyLoadedScript;
async function text() {
  return page.locator('flt-semantics-host').evaluate(host => [host.innerText,
    ...[...host.querySelectorAll('[aria-label]')].map(n => n.getAttribute('aria-label')),
    ...[...host.querySelectorAll('input,textarea')].map(n => n.value),
  ].filter(Boolean).join('\n'));
}
async function wait(pattern) {
  await waitForSemantics(page, pattern);
}
async function click(pattern) {
  const target = page.getByRole('button', { name: pattern }).first();
  for (let attempt = 0; attempt < 18; attempt++) {
    const box = await target.count() ? await target.boundingBox() : null, viewport = page.viewportSize();
    if (box && box.height > 5 && box.y >= 0 && box.y + Math.min(box.height / 2, 35) < viewport.height - 4) {
      await target.click({ position: { x: Math.min(20, box.width / 2), y: Math.min(25, box.height / 2) } });
      await waitForUiSettled(page); return;
    }
    if (!box || box.height <= 5 || box.y > viewport.height - 80) {
      await page.mouse.move(viewport.width * .3, viewport.height * .5);
      await page.mouse.wheel(0, 240); await waitForUiSettled(page);
    } else {
      await target.scrollIntoViewIfNeeded(); await waitForUiSettled(page);
    }
  }
  throw new Error(`Cannot reach ${pattern}`);
}
async function capture(name) {
  await page.mouse.move(2, 2); await waitForUiSettled(page);
  assert.equal(await page.getByRole('dialog').count(), 0);
  assert.doesNotMatch(await text(), /AVAILABLE CHOICES/);
  const bytes = await page.screenshot({ path: resolve(output, `${name}.png`), fullPage: true });
  assert.deepEqual({width:bytes.readUInt32BE(16),height:bytes.readUInt32BE(20)}, page.viewportSize());
  await writeFile(resolve(output, `${name}.txt`), await text());
  report.screenshots.push(`${name}.png`);
  report.checks.push({ name, status: 'passed', viewport: page.viewportSize() });
  console.log(`PASS ${name}`);
}
async function paintedPortrait(preview, identity, name) {
  const started = Date.now(), deadline = started + 30000;
  const evidence = { name, identity, status: 'waiting', timeoutMs: 30000,
    tolerance: { meanRgb: 6, maxChannel: 24, mismatchFraction: .05, alignmentPixels: 1 }, samples: [] };
  report.portraitReadiness.push(evidence);
  let first, last;
  const remaining = () => Math.max(1, deadline - Date.now());
  try {
    assert.match(identity ?? '', /^founder-preview:\d+$/);
    const id = Number(identity.split(':')[1]);
    const batch = id < 250 ? Math.floor(id / 16) : 16 + Math.floor((id - 250) / 16);
    const cell = id < 250 ? id % 16 : (id - 250) % 16;
    const assetUrl = new URL(`assets/assets/modern/portraits_v2/batch_${String(batch).padStart(2, '0')}.webp`, url).href;
    Object.assign(evidence, { portraitId: id, batch, cell, assetUrl });
    const box = await preview.boundingBox({ timeout: remaining() });
    assert.ok(box?.width && box?.height, 'Founder preview must have visible bounds.');
    first = last = await preview.screenshot({ timeout: remaining() });
    evidence.firstCapture = `${name}-first.png`;
    await writeFile(resolve(output, evidence.firstCapture), first);
    const size = PNG.sync.read(first);
    evidence.geometry = { width: size.width, height: size.height, cssWidth: box.width, cssHeight: box.height, padding: 2 };
    // FounderPortraitPreview paints one 4x4 atlas cell inside two logical pixels
    // of padding. Decode that exact cell independently; semantics can precede
    // painting, and a FutureBuilder can temporarily retain an older atlas.
    const reference = await page.evaluate(async ({ assetUrl, cell, width, height, paddingX, paddingY, timeoutMs }) => {
      const controller = new AbortController();
      let timer, status;
      const decode = (async () => {
        const response = await fetch(assetUrl, { signal: controller.signal });
        status = response.status;
        if (!response.ok) throw Error(`Portrait reference HTTP ${status}`);
        const blob = await response.blob(), image = await createImageBitmap(blob);
        try {
          const canvas = document.createElement('canvas');
          canvas.width = width; canvas.height = height;
          const paint = canvas.getContext('2d');
          paint.fillStyle = '#e1dfc4'; paint.fillRect(0, 0, width, height);
          paint.imageSmoothingEnabled = true; paint.imageSmoothingQuality = 'medium';
          paint.drawImage(image, cell % 4 * image.width / 4, Math.floor(cell / 4) * image.height / 4,
            image.width / 4, image.height / 4, paddingX, paddingY, width - 2 * paddingX, height - 2 * paddingY);
          return { status, bytes: blob.size, atlasWidth: image.width, atlasHeight: image.height, png: canvas.toDataURL('image/png').split(',')[1] };
        } finally { image.close(); }
      })();
      try {
        return await Promise.race([decode, new Promise((_, reject) => {
          timer = setTimeout(() => { controller.abort(); reject(Error('Portrait reference decode timed out.')); }, timeoutMs);
        })]);
      } catch (error) { return { status, error: String(error) }; }
      finally { clearTimeout(timer); }
    }, { assetUrl, cell, width: size.width, height: size.height,
      paddingX: 2 * size.width / box.width, paddingY: 2 * size.height / box.height, timeoutMs: remaining() });
    const { png, ...referenceInfo } = reference;
    evidence.reference = referenceInfo;
    assert.ok(png, reference.error ?? 'Portrait reference must decode.');
    const expectedBytes = Buffer.from(png, 'base64'), expected = PNG.sync.read(expectedBytes);
    evidence.expectedCapture = `${name}-expected.png`;
    await writeFile(resolve(output, evidence.expectedCapture), expectedBytes);
    const inset = Math.ceil(4 * Math.max(size.width / box.width, size.height / box.height));
    assert.ok(inset * 2 < size.width && inset * 2 < size.height, 'Portrait comparison needs a painted interior.');
    while (true) {
      assert.equal(await preview.getAttribute('flt-semantics-identifier', { timeout: remaining() }), identity, 'Portrait identity changed while awaiting its paint.');
      const actual = PNG.sync.read(last);
      assert.deepEqual([actual.width, actual.height], [expected.width, expected.height], 'Preview bounds changed during portrait decoding.');
      let best = { meanRgb: Infinity, mismatchFraction: 1 };
      // Ignore the border and permit one capture-alignment pixel. Canvas2D and
      // Flutter's medium filter need not produce byte-identical resampling.
      for (const dy of [-1, 0, 1]) for (const dx of [-1, 0, 1]) {
        let distance = 0, mismatched = 0, pixels = 0;
        for (let y = inset; y < actual.height - inset; y++) for (let x = inset; x < actual.width - inset; x++) {
          const a = (y * actual.width + x) * 4, b = ((y + dy) * expected.width + x + dx) * 4;
          const red = Math.abs(actual.data[a] - expected.data[b]);
          const green = Math.abs(actual.data[a + 1] - expected.data[b + 1]);
          const blue = Math.abs(actual.data[a + 2] - expected.data[b + 2]);
          distance += red + green + blue;
          if (Math.max(red, green, blue) > evidence.tolerance.maxChannel) mismatched++;
          pixels++;
        }
        const meanRgb = distance / (pixels * 3), mismatchFraction = mismatched / pixels;
        if (meanRgb < best.meanRgb) best = { meanRgb, mismatchFraction, dx, dy };
      }
      evidence.samples.push({ elapsedMs: Date.now() - started, ...best });
      if (best.meanRgb <= evidence.tolerance.meanRgb && best.mismatchFraction <= evidence.tolerance.mismatchFraction) {
        evidence.status = 'passed';
        return last;
      }
      assert.ok(Date.now() < deadline, `Founder portrait ${id} did not paint its expected atlas cell within 30 seconds: ${JSON.stringify(best)}`);
      last = await preview.screenshot({ timeout: remaining() });
    }
  } catch (error) {
    evidence.status = 'failed'; evidence.error = String(error);
    throw error;
  } finally {
    evidence.elapsedMs = Date.now() - started;
    evidence.network = report.portraitResponses.filter(response => response.url === evidence.assetUrl);
    if (last) {
      evidence.lastCapture = `${name}-last.png`;
      evidence.firstSha256 = createHash('sha256').update(first).digest('hex');
      evidence.lastSha256 = createHash('sha256').update(last).digest('hex');
      await writeFile(resolve(output, evidence.lastCapture), last);
    }
  }
}
async function rerollPortrait(prefix) {
  const preview = page.getByRole('img', { name: 'Founder portrait preview', exact: true });
  await preview.waitFor();
  await waitForUiSettled(page);
  const beforeText = await text();
  const beforeIdentity = await preview.getAttribute('flt-semantics-identifier');
  const before = createHash('sha256').update(await paintedPortrait(preview, beforeIdentity, `${prefix}-portrait-before`)).digest('hex');
  await click(/^Reroll portrait$/);
  await page.mouse.move(2, 2);
  await page.waitForFunction(previous => {
    const preview = document.querySelector('[flt-semantics-identifier^="founder-preview:"]');
    return preview && preview.getAttribute('flt-semantics-identifier') !== previous;
  }, beforeIdentity);
  await waitForUiSettled(page);
  const identity = await preview.getAttribute('flt-semantics-identifier');
  const after = createHash('sha256').update(await paintedPortrait(preview, identity, `${prefix}-portrait-after`)).digest('hex');
  assert.notEqual(identity, beforeIdentity, 'Reroll must change the source portrait identity');
  assert.notEqual(after, before, 'Reroll must visibly change the portrait');
  assert.equal(await text(), beforeText, 'Reroll must leave names and settings unchanged');
  assert.match(identity ?? '', /^founder-preview:\d+$/);
  report.checks.push({ name: `${prefix}-portrait-reroll`, status: 'passed', beforeIdentity, identity });
  return { portrait: Number(identity.split(':')[1]), person: null };
}
async function checkPortrait(identity, stage) {
  const visible = await page.locator('[flt-semantics-identifier^="crew-portrait:"]')
    .evaluateAll(nodes => nodes.map(node => node.getAttribute('flt-semantics-identifier')));
  assert.ok(visible.length, `No crew portrait at ${stage}`);
  if (identity.person === null) identity.person = Number(visible[0].split(':')[1]);
  const founder = visible.filter(value => Number(value.split(':')[1]) === identity.person);
  assert.ok(founder.length, `Founder portrait missing at ${stage}`);
  assert.ok(founder.every(value => Number(value.split(':')[2]) === identity.portrait),
    `Founder face changed at ${stage}: expected ${identity.portrait}, got ${founder}`);
  report.checks.push({ name: `portrait-${stage}`, status: 'passed', ...identity });
}
async function checkNameLocation() {
  const field = await page.getByRole('textbox').first().boundingBox();
  const question = await page.getByText('What is your name to the people?', { exact: true }).boundingBox();
  const begin = await page.getByRole('button', { name: /^Begin campaign/ }).boundingBox();
  assert.ok(field && question && begin);
  assert.ok(field.y >= question.y + question.height && field.x >= question.x - 2);
  assert.ok(field.x + field.width < page.viewportSize().width * .8, 'Name input must stay in the left page');
  assert.ok(begin.y >= field.y + field.height && begin.x + begin.width <= field.x + field.width + 2);
  report.checks.push({ name: 'name-field-below-question', status: 'passed', field });
}
async function waitForBonusPopup(message, timeout = 1000, visible = true) {
  const handle = await page.waitForFunction(({ source, flags, visible }) => {
    const pattern = new RegExp(source, flags);
    const present = [...document.querySelectorAll('flt-semantics-host *')].some(node => {
      const bounds = node.getBoundingClientRect();
      return bounds.width > 200 && bounds.height > 60
        && pattern.test(node.innerText ?? '') && getComputedStyle(node).visibility !== 'hidden'
        && !node.children.length;
    });
    return present === visible;
  }, { source: message.source, flags: message.flags, visible }, { polling: 'raf', timeout });
  await handle.dispose();
}
async function bonusHelp(prefix, scale, choice = 'A', stats = [
  ['law', /Choosing this: Law/], ['agility', /Choosing this: Agility/],
]) {
  await page.mouse.move(2, 2);
  await waitForBonusPopup(/Choosing this:/, 10000, false);
  await waitForUiSettled(page);
  const answer = page.getByRole('button', { name: new RegExp(`^${choice}(?:\\s|$)`) }).first();
  let box;
  for (let attempt = 0; attempt < 18; attempt++) {
    box = await answer.count() ? await answer.boundingBox() : null;
    // Flutter clips semantics bounds for partially visible cards. The effect
    // line is at the bottom, so a visible question heading alone isn't enough.
    if (box && box.height > 60 * scale && box.y >= 0 && box.y + box.height < page.viewportSize().height - 70) break;
    await page.mouse.move(page.viewportSize().width * .3, page.viewportSize().height * .5);
    await page.mouse.wheel(0, 200);
    await waitForUiSettled(page);
  }
  assert.ok(box);
  const before = await text();
  const y = box.y + box.height - 12 - 8.4 * scale;
  let previousX = box.x + 40;
  let lastPoint;
  for (const [name, message] of stats) {
    let popup;
    for (let x = previousX; x < Math.min(box.x + box.width - 12, box.x + 380 * scale); x += 12) {
      await page.mouse.move(x, y);
      try {
        await waitForBonusPopup(message);
      } catch (error) {
        if (error.name === 'TimeoutError') continue;
        throw error;
      }
      const candidates = page.getByText(message);
      for (const candidate of await candidates.all()) {
        // Sidebar rows expose the same help in their accessibility labels.
        // The actual popup is a multiline box, not a single sidebar stat row.
        const bounds = await candidate.boundingBox({ timeout: 500 }).catch(() => null);
        if (bounds && bounds.width > 200 && bounds.height > 60
            && await candidate.isVisible()) {
          // A popup adds/removes semantics nodes during its fade. Keep its
          // exact text instead of a positional locator that can shift mid-frame.
          popup = page.getByText(await candidate.innerText(), { exact: true }).last();
          previousX = x + 12;
          lastPoint = { x, y };
          break;
        }
      }
      if (popup) break;
    }
    assert.ok(popup, `No ${name} tooltip over the answer bonus`);
    await waitForUiSettled(page);
    const bounds = await popup.boundingBox();
    const viewport = page.viewportSize();
    assert.ok(bounds && bounds.x >= 0 && bounds.y >= 0
      && bounds.x + bounds.width <= viewport.width && bounds.y + bounds.height <= viewport.height);
    const image = `${prefix}-bonus-${name}.png`;
    await page.screenshot({ path: resolve(output, image), fullPage: true });
    report.screenshots.push(image);
    report.checks.push({ name: `${prefix}-bonus-${name}`, status: 'passed', bounds, target: lastPoint });
    console.log(`PASS ${prefix}-bonus-${name}`);
  }
  await page.mouse.move(2, 2);
  await waitForSemantics(page, before);
  assert.equal(await text(), before, 'Inspecting bonuses must not select an answer or change founder facts');
  await page.mouse.move(lastPoint.x, lastPoint.y);
  await waitForBonusPopup(stats.at(-1)[1]);
  await waitForUiSettled(page);
  return lastPoint;
}
async function founderFlow({ fate, prefix, name }) {
  await click(/^Start a New Game/); await wait(/Campaign dossier/);
  await capture(`${prefix}-01-settings`);
  await click(/^Continue to founder/); await wait(/The founder/);
  assert.match(await text(), /Given name/);
  assert.doesNotMatch(await text(), /Founder dossier/);
  const identity = await rerollPortrait(prefix);
  if (fate) {
    await click(/^Tragic origin/); await wait(/Let Fate Decide/);
  }
  await capture(`${prefix}-02-identity`);
  await click(/^Begin background/);
  for (let step = 1; step <= 10; step++) {
    await wait(new RegExp(`${step}\\s*/\\s*10`));
    assert.match(await text(), /Founder dossier/);
    if (step === 1 || step === 10) await checkPortrait(identity, `${prefix}-background-${step}`);
    if (step === 1 || step === 10) await capture(`${prefix}-03-background-${step}`);
    if (fate) {
      assert.equal(await page.getByRole('button', { name: /^A(?:\s|$)/ }).count(), 0);
      await click(/^Continue/);
    } else {
      assert.equal(await page.getByRole('button', { name: /^[A-E](?:\s|$)/ }).count(), 5);
      if (step === 4) {
        await bonusHelp('normal', 1);
        await bonusHelp('computers-normal', 1, 'C', [['computers', /Choosing this: Computers/]]);
        await page.mouse.move(2, 2);
        await waitForUiSettled(page);
        await click(/^Reading size/);
        await page.getByRole('menuitem', { name: '150%', exact: true }).click();
        await page.setViewportSize({ width: 1024, height: 720 });
        await waitForUiSettled(page);
        await bonusHelp('large', 1.5);
        const bonus = await bonusHelp('computers-large', 1.5, 'C', [['computers', /Choosing this: Computers/]]);
        await page.mouse.click(bonus.x, bonus.y);
        await wait(/5\s*\/\s*10/);
        assert.match(await text(), /Computers: 1\b/);
        await click(/^Reading size/);
        await page.getByRole('menuitem', { name: '100%', exact: true }).click();
        await page.setViewportSize({ width: 1280, height: 720 });
        await waitForUiSettled(page);
        continue;
      }
      // Include the advertised manifesto reward in the real creation/save path.
      await click(step === 10 ? /^D(?:\s|$)/ : /^A(?:\s|$)/);
    }
  }
  await wait(/A new Conservative era/); await capture(`${prefix}-04-briefing`);
  await checkPortrait(identity, `${prefix}-briefing`);
  await click(/^Continue/); await wait(/Sign the founding record/);
  await checkPortrait(identity, `${prefix}-public-name`);
  await checkNameLocation();
  const field = page.getByRole('textbox').first(); await field.waitFor();
  assert.ok(await field.inputValue());
  await field.fill(name);
  await capture(`${prefix}-05-public-name`);
  const begin = page.getByRole('button', {name:/^Begin campaign/});
  const bounds = await begin.boundingBox();
  assert.ok(bounds && bounds.y >= 0 && bounds.y + bounds.height <= page.viewportSize().height);
  await begin.click(); await wait(/Save & exit/);
  assert.match(await text(), new RegExp(name));
  await checkPortrait(identity, `${prefix}-headquarters`);
  await capture(`${prefix}-06-playable-organisation`);
  await click(/^Save & exit/); await wait(/Start a New Game/);
  if (!fate) {
    await click(/^Load & Manage Saves/);
    await click(/^A(?:\s|$)/);
    await wait(/Manage .*Saved Game/);
    const downloading = page.waitForEvent('download');
    await click(/Export Save File/);
    const savedPath = resolve(output, 'manual-founder.json');
    await (await downloading).saveAs(savedPath);
    const envelope = JSON.parse(await readFile(savedPath, 'utf8'));
    const state = typeof envelope.saveData === 'string' ? JSON.parse(envelope.saveData) : envelope.saveData;
    const founder = state.lcs.pool.find(person => person.id === identity.person);
    assert.ok(founder, 'Find the actual created founder in the exported save.');
    assert.equal(founder.juice, 50, 'The manifesto reward must survive creation and saving.');
    assert.equal(founder.rawSkill.computers, 1, 'The clicked background skill bonus must persist.');
    assert.equal(founder.portraitId, identity.portrait);
    report.manualFounder = { path: savedPath, personId: founder.id, juice: founder.juice };
    report.checks.push({ name: 'manual-background-rewards-and-portrait-persist-in-export', status: 'passed' });
    await click(/^L Load Game/); await wait(/Save & exit/);
    await click(/^Save & exit/); await wait(/Start a New Game/);
  }
  await click(/^Continue as/); await wait(/Save & exit/);
  await checkPortrait(identity, `${prefix}-reloaded`);
  await click(/^Save & exit/); await wait(/Start a New Game/);
}
try {
  const response = await fetch(new URL('main.dart.js', url));
  report.mainJsSha256 = createHash('sha256').update(Buffer.from(await response.arrayBuffer())).digest('hex');
  assert.equal(report.mainJsSha256, expectedHash);
  context = await chromium.launchPersistentContext(profile, {
    ...chromiumLaunchOptions({ channel: 'chrome', args }), viewport:{width:1280,height:720},
  });
  report.browserVersion = context.browser().version();
  page = await context.newPage();
  verifyLoadedScript = observeMainScript(page, report);
  page.on('pageerror', error => report.pageErrors.push(error.stack ?? error.message));
  page.on('console', message => {if(message.type()==='error') report.consoleErrors.push(message.text());});
  page.on('requestfailed', request => {
    const failed = { url: request.url(), failure: request.failure()?.errorText };
    report.failedRequests.push(failed);
    if (/\/portraits_v2\/batch_\d+\.webp$/.test(new URL(request.url()).pathname)) {
      report.portraitResponses.push({ ...failed, status: null, elapsedMs: Date.now() - Date.parse(report.started) });
    }
  });
  page.on('response', response => {
    if (/\/portraits_v2\/batch_\d+\.webp$/.test(new URL(response.url()).pathname)) {
      report.portraitResponses.push({ url: response.url(), status: response.status(),
        fromServiceWorker: response.fromServiceWorker(), elapsedMs: Date.now() - Date.parse(report.started) });
    }
  });
  await page.goto(url, {waitUntil:'domcontentloaded'}); await wait(/Start a New Game/);
  if(!args.includes('--large-only'))await founderFlow({fate:false,prefix:'manual',name:'Journal Founder Review'});
  await click(/^Start a New Game/); await wait(/Campaign dossier/);
  await click(/^Reading size/);
  await writeFile(resolve(output,'reading-menu.html'),await page.locator('flt-semantics-host').innerHTML());
  await page.getByRole('menuitem',{name:'150%',exact:true}).click();await waitForUiSettled(page);
  await page.setViewportSize({width: 1024, height: 720});await waitForUiSettled(page);
  await capture('large-01-settings');
  await click(/^Continue to founder/);await wait(/The founder/);
  const largeIdentity = await rerollPortrait('large');
  await click(/^Tragic origin/);await wait(/Let Fate Decide/);
  await capture('large-02-identity');await click(/^Begin background/);
  for(let step=1;step<=10;step++) {
    await wait(new RegExp(`${step}\\s*/\\s*10`));
    if (step === 1 || step === 10) await checkPortrait(largeIdentity, `large-fate-${step}`);
    if(step===1||step===10)await capture(`large-03-fate-${step}`);
    assert.equal(await page.getByRole('button',{name:/^[A-E](?:\s|$)/}).count(),0);
    await click(/^Continue/);
  }
  await wait(/A new Conservative era/);await capture('large-04-briefing');
  await click(/^Continue/);await wait(/Sign the founding record/);
  await checkPortrait(largeIdentity, 'large-public-name');
  await checkNameLocation();
  await page.getByRole('textbox').first().fill('Large Founder Review');
  await capture('large-05-public-name');
  await page.getByRole('button',{name:/^Begin campaign/}).click();await wait(/Save & exit/);
  assert.match(await text(),/Large Founder Review/);await capture('large-06-playable-organisation');
  await checkPortrait(largeIdentity, 'large-headquarters');
  await click(/^Save & exit/);await wait(/Start a New Game/);
  await click(/^Continue as/);await wait(/Save & exit/);
  await checkPortrait(largeIdentity, 'large-reloaded');
  await verifyLoadedScript(expectedHash);
  assert.deepEqual(report.pageErrors,[]);assert.deepEqual(report.consoleErrors,[]);assert.deepEqual(report.failedRequests,[]);
  report.status='passed';
} catch(error) {
  report.status='failed';report.error=error.stack??String(error);process.exitCode=1;
  if(page){await page.screenshot({path:resolve(output,'FAILURE.png')});await writeFile(resolve(output,'FAILURE.txt'),await text());}
} finally {
  if(context)await context.close();report.completed=new Date().toISOString();
  await writeFile(resolve(output,'report.json'),JSON.stringify(report,null,2));
  console.log(JSON.stringify({status:report.status,output,checks:report.checks.length,error:report.error}));
}
