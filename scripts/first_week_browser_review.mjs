// Isolated onboarding journey through the shipped browser UI. Never connects
// to the player's normal port or profile. Reports and synthetic saves are local.
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
const args = process.argv.slice(2);
const arg = (flag, fallback) => args.includes(flag) ? args[args.indexOf(flag) + 1] : fallback;
const url = assertQaUrl(arg('--url', 'http://127.0.0.1:18879/'));
const output = resolve(root, arg('--out', '.local/reports/selection-preview/first-week'));
await mkdir(output, { recursive: true });
const decode = save => typeof save.saveData === 'string' ? JSON.parse(save.saveData) : save.saveData;
const campaignPath = arg('--campaign', null);
const envelope = JSON.parse(await readFile(resolve(root, campaignPath ?? 'upstream/test/saves/felix_1_0.json'), 'utf8'));
const fixture = decode(envelope);
// Declare a peaceful onboarding scenario and an explicitly ready prospect.
// This checks the actual join decision; it does not claim to earn persuasion.
for (const person of campaignPath ? [] : fixture.lcs.pool) {
  person.wantedForCrimes = Object.fromEntries(Object.keys(person.wantedForCrimes).map(key => [key, 0]));
  person.heat = 0;
  person.activity = { type: 'none' };
}
const recruiter = fixture.lcs.pool[0];
const fieldMember = fixture.lcs.pool.at(-1);
let prospect;
if (!campaignPath) {
  prospect = structuredClone(fieldMember);
  Object.assign(prospect, {
    id: fixture.nextCreatureId++, name: 'Casey Rivers', properName: 'Casey Rivers',
    typeId: 'CREATURE_HIPPIE', alreadyNamed: true, hireId: null, squadId: null,
    equippedWeapon: null, spareAmmo: null, daysSinceJoined: 0,
  });
  fixture.recruitmentSessions.push({ recruit: prospect, recruiter: recruiter.id, rawEagerness: 4 });
  envelope.saveData = typeof envelope.saveData === 'string' ? JSON.stringify(fixture) : fixture;
}
const fixturePath = campaignPath ? resolve(root, campaignPath) : resolve(output, 'synthetic-first-week.json');
if (!campaignPath) await writeFile(fixturePath, JSON.stringify(envelope));
const report = {
  status: 'running', url,
  scope: campaignPath
    ? 'Unmodified founder exported by the creation journey. Actual skill practice, seven daily turns, accounting and fresh-profile save transfer; no prepared people, rewards, dates or outcomes.'
    : 'Automated first-week browser journey. Isolated Felix campaign copy with old wanted crimes cleared and one ready prospect; no funds, skills, dates or outcomes patched. Recruit joining, formation, equipment transfer, orders, nearby shop travel and seven actual daily turns use the shipped UI and engine.',
  checks: [], screenshots: [], days: [], decisionFrames: [],
  pageErrors: [], consoleErrors: [], failedRequests: [],
};
const response = await fetch(new URL('main.dart.js', url));
assert.ok(response.ok);
report.mainJsSha256 = createHash('sha256').update(Buffer.from(await response.arrayBuffer())).digest('hex');
const expectedHash = arg('--expected-hash', null);
if (expectedHash) assert.equal(report.mainJsSha256, expectedHash.toLowerCase(), 'QA server must serve the requested compiled build.');
const browser = await chromium.launch(chromiumLaunchOptions({ args }));
let context;
let page;
let verifyLoadedScript;
const escape = text => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
async function newContext() {
  if (verifyLoadedScript) await verifyLoadedScript(expectedHash?.toLowerCase() ?? report.mainJsSha256);
  await context?.close();
  context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, acceptDownloads: true });
  page = await context.newPage();
  verifyLoadedScript = observeMainScript(page, report);
  page.setDefaultTimeout(10000);
  page.on('pageerror', error => report.pageErrors.push(String(error)));
  page.on('console', message => { if (message.type() === 'error') report.consoleErrors.push(message.text()); });
  page.on('requestfailed', request => report.failedRequests.push(request.url()));
  // Offline asset caching can continue after the game is usable. Wait for the
  // actual title controls rather than making profile transfer depend on idle
  // background downloads finishing inside Playwright's action timeout.
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await wait(/Start a New Game/);
}
async function uiText() {
  if (!await page.locator('flt-semantics-host').count()) return '';
  return page.locator('flt-semantics-host').evaluate(host => [host.innerText,
    ...[...host.querySelectorAll('[aria-label]')].map(node => node.getAttribute('aria-label')),
    ...[...host.querySelectorAll('input,textarea')].map(node => node.value),
  ].filter(Boolean).join('\n'));
}
async function wait(pattern) {
  await waitForSemantics(page, pattern);
}
async function click(name) {
  await page.getByRole('button', { name }).first().click();
  await page.mouse.move(2, 2);
  await waitForUiSettled(page);
}
async function capture(name) {
  await page.mouse.move(2, 2);
  await page.screenshot({ path: resolve(output, `${name}.png`), fullPage: true });
  report.screenshots.push(`${name}.png`);
  report.checks.push(name);
  console.log(`PASS ${name}`);
}
async function importAndLoad(path) {
  await wait(/Start a New Game/);
  const chooser = page.waitForEvent('filechooser');
  await click(/^Import a Save/);
  await (await chooser).setFiles(path);
  await wait(/Save imported/);
  await page.keyboard.press('Enter');
  await wait(/Start a New Game/);
  await click(/^Load & Manage Saves/);
  await click(/^A(?:\s|$)/);
  await wait(/Manage .*Saved Game/);
  await click(/^L Load Game/);
  await wait(/Save & exit/);
}
async function exportGame(name) {
  await click(/^Save & exit/);
  await wait(/Start a New Game/);
  await click(/^Load & Manage Saves/);
  await click(/^A(?:\s|$)/);
  await wait(/Manage .*Saved Game/);
  const downloading = page.waitForEvent('download');
  await click(/Export Save File/);
  const path = resolve(output, `${name}.json`);
  await (await downloading).saveAs(path);
  const state = decode(JSON.parse(await readFile(path, 'utf8')));
  await click(/^L Load Game/);
  await wait(/Save & exit/);
  return { path, state };
}
const nextDate = date => {
  const [y, m, d] = date.slice(0, 10).split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + 1)).toISOString().slice(0, 10);
};
const datePattern = date => {
  const [y, m, d] = date.slice(0, 10).split('-').map(Number);
  return new RegExp(`${d}\\s+${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1]}\\s+${y}`);
};
function verifyAccounting(state, baseline) {
  const ledger = state.ledger;
  assert.equal(ledger._funds,
    baseline.ledger._funds + ledger.totalIncome - baseline.ledger.totalIncome - (ledger.totalExpense - baseline.ledger.totalExpense),
    'Funds must equal the original balance plus actual engine income less expenses.');
}
async function advanceOneDay(previous, baseline) {
  const target = nextDate(previous.date);
  await click(/^(?:Wait a day|Carry out your plans)/);
  let arrived = false;
  let lastFrame;
  for (let prompt = 0; prompt < 80; prompt++) {
    const previousFrame = await page.locator('flt-semantics-host').innerHTML();
    const text = await uiText();
    const buttons = await page.getByRole('button').evaluateAll(nodes => nodes.map(node => node.getAttribute('aria-label') ?? node.textContent));
    const saveExit = page.getByRole('button', { name: /^Save & exit/ });
    if (datePattern(target).test(text) && await saveExit.count() && await saveExit.isEnabled()) {
      arrived = true;
      break;
    }
    if (text !== lastFrame) report.decisionFrames.push({ target, prompt, text, buttons });
    lastFrame = text;
    if (await page.getByRole('button', { name: /Offer to let .* join the LCS/ }).count()) {
      await click(/Offer to let .* join the LCS/);
    } else if (await page.getByRole('button', { name: /as a regular member/ }).count()) {
      await click(/as a regular member/);
    } else if (await page.getByRole('button', { name: /Leave|Done shopping|Done pawning/ }).count()) {
      await click(/Leave|Done shopping|Done pawning/);
    } else if (await page.getByRole('button', { name: /Continue|Read newspaper|Read the paper|Done|Next|Any other key/i }).count()) {
      await page.keyboard.press('Enter');
      await page.waitForFunction(previous => document.querySelector('flt-semantics-host')?.innerHTML !== previous,
        previousFrame);
    } else {
      // A rendered daily result can precede the next awaited engine frame.
      // Wait for its source action rather than sending a guessed command.
      await page.waitForFunction(previous => document.querySelector('flt-semantics-host')?.innerHTML !== previous,
        previousFrame);
    }
  }
  assert.ok(arrived, `Must return to headquarters on ${target}. Last frame: ${lastFrame}`);
  const { state } = await exportGame(`day-${report.days.length + 1}`);
  assert.equal(state.date.slice(0, 10), target);
  verifyAccounting(state, baseline);
  assert.ok(state.lcs.pool.every(person => person.alive), 'Peaceful onboarding must retain all crew.');
  for (const before of previous.lcs.pool) {
    const after = state.lcs.pool.find(person => person.id === before.id);
    assert.ok(after, `Retain crew id ${before.id}.`);
    assert.equal(after.daysSinceJoined, before.daysSinceJoined + 1, 'Exactly one daily age increment.');
  }
  report.days.push({ date: target, funds: state.ledger._funds, roster: state.lcs.pool.map(person => person.id), income: state.ledger.totalIncome, expenses: state.ledger.totalExpense });
  console.log(`PASS day ${report.days.length}: ${target}, $${state.ledger._funds}, ${state.lcs.pool.length} crew`);
  return state;
}
async function selectCrew(person) {
  await click(new RegExp(`^Select crew ${escape(person.name)}(?:$|\\s)`));
}
async function assignDonation(person) {
  await selectCrew(person);
  await click(/^Orders(?:$|\s)/);
  await click(/^Business(?:$|\s)/);
  await click(/^Prepare Solicit Donations(?:$|\s)/);
  await click('Confirm order');
  await wait(/Prepare Solicit Donations/);
}
async function assignSciencePractice(person) {
  await selectCrew(person);
  await click(/^Orders(?:$|\s)/);
  await click(/^Personnel(?:$|\s)/);
  await click('Education and Learning');
  await click(/^Prepare Practice a Skill/);
  await click('Confirm order');
  await wait(/What skill will .* practice/);
  await click(/^[A-Z] Science(?:$|\s)/);
  await click('Finish orders');
}
try {
  await newContext();
  await importAndLoad(fixturePath);
  const { state: baseline } = await exportGame('baseline');
  if (campaignPath) {
    // Continue the same founder created by the preceding browser helper. Keep
    // this branch free of the prepared recruitment/equipment fixture below.
    const founder = baseline.lcs.pool[0];
    assert.equal(baseline.lcs.pool.length, 1);
    assert.equal(founder.juice, 50, 'Manifesto Juice must survive a fresh-profile import.');
    await assignSciencePractice(founder);
    let current = (await exportGame('fresh-founder-practice-order')).state;
    assert.equal(current.lcs.pool[0].activity.type, 'study');
    assert.equal(current.lcs.pool[0].activity.skill, 'science');
    await capture('fresh-01-background-reward-and-confirmed-practice');
    while (report.days.length < 7) current = await advanceOneDay(current, baseline);
    const trained = current.lcs.pool.find(person => person.id === founder.id);
    assert.equal(trained.juice, founder.juice);
    assert.equal(trained.portraitId, founder.portraitId);
    assert.ok(trained.rawSkill.science > founder.rawSkill.science ||
      trained.rawSkill.science === founder.rawSkill.science && trained.rawSkillXP.science > founder.rawSkillXP.science,
    'The newly created founder must earn real training progress.');
    const exported = await exportGame('fresh-founder-week-completed');
    await newContext(); await importAndLoad(exported.path);
    const restored = (await exportGame('fresh-founder-week-reimported')).state;
    assert.deepEqual(restored, exported.state, 'Retain the entire fresh campaign across a second profile.');
    report.checks.push('fresh-founder-seven-real-days-background-reward-and-training',
      'fresh-founder-week-exact-save-continuity');
    await capture('fresh-02-week-complete-after-profile-transfer');
  } else {
  await capture('01-isolated-onboarding-campaign');
  let current = await advanceOneDay(baseline, baseline);
  const joined = current.lcs.pool.find(person => person.id === prospect.id);
  assert.ok(joined && joined.hireId === recruiter.id && joined.squadId == null);
  assert.equal(current.stats.recruits, baseline.stats.recruits + 1);
  assert.ok(!current.recruitmentSessions.some(session => session.recruit.id === prospect.id));
  await capture('02-ready-prospect-joins-through-real-meeting');

  await click('Assemble a new squad');
  for (const person of [fieldMember, prospect]) await click(new RegExp(`^Add ${escape(person.name)} to this squad$`));
  await click(/^Done$/);
  await wait(/What shall we designate/);
  await page.getByRole('textbox').fill('First-week field team');
  await page.keyboard.press('Enter');
  await wait(/Select squad First-week field team|[A-S] First-week field team Location:/);
  // The source squad reader may remain open after naming. Return through its
  // current Back action before using the headquarters squad-selection rail.
  if (!await page.getByRole('button', { name: /Select squad First-week field team/ }).count()) {
    await click(/^Back$/);
  }
  await wait(/Select squad First-week field team/);
  await click(/Select squad First-week field team/);
  await capture('03-form-new-two-person-squad');

  await click(/^Equipment(?:$|\s)/);
  await wait(/Increase ammo allocation/);
  await click(new RegExp(`^1 ${escape(fieldMember.name)}.*Unequip weapon`, 's'));
  const weaponName = current.lcs.pool.find(person => person.id === fieldMember.id).equippedWeapon.typeName;
  // The only weapon in this empty synthetic base's loot is the one just dropped.
  await click(/^Equip /);
  await wait(/Who receives /);
  await click(new RegExp(`^2 ${escape(prospect.name)}(?:$|\\s)`));
  await capture('04-equip-new-recruit-through-source-recipient-choice');
  await click(/^(?:Enter )?Done$/);
  const equipped = (await exportGame('after-equipment-transfer')).state;
  const fieldTeam = equipped.lcs.squads.find(team => team.name === 'First-week field team');
  assert.deepEqual(fieldTeam.members, [fieldMember.id, prospect.id]);
  assert.deepEqual(equipped.lcs.squads.find(team => team.id === baseline.lcs.squads[0].id).members,
    baseline.lcs.squads[0].members.filter(id => id !== fieldMember.id));
  assert.equal(equipped.lcs.pool.find(person => person.id === fieldMember.id).equippedWeapon, null);
  assert.equal(equipped.lcs.pool.find(person => person.id === prospect.id).equippedWeapon.typeName, weaponName);
  for (const person of current.lcs.pool.filter(person => ![fieldMember.id, prospect.id].includes(person.id))) {
    assert.deepEqual(equipped.lcs.pool.find(entry => entry.id === person.id), person,
      'Forming and equipping the field team must preserve every other crew member.');
  }
  assert.equal(equipped.ledger._funds, current.ledger._funds, 'Reassigning equipment costs no funds.');

  for (const person of [fieldMember, prospect]) await assignDonation(person);
  await click(/Select squad The Liberal Crime Squad/);
  for (const person of fixture.lcs.pool.slice(0, -1)) await assignDonation(person);
  const learner = fixture.lcs.pool[1];
  await assignSciencePractice(learner);
  const ordered = (await exportGame('after-assignments')).state;
  assert.ok(ordered.lcs.pool.every(person => person.id === learner.id
    ? person.activity.type === 'study' && person.activity.skill === 'science'
    : person.activity.type === 'donations'));
  await capture('05-confirmed-daily-orders-for-all-six-members');

  // Execute a real free local trip; a shop can be exited without combat/purchase.
  await click(/Select squad First-week field team/);
  await click(/^Orders(?:$|\s)/);
  await click(/^Operations(?:$|\s)/);
  await click('Visit a location');
  const homeSite = baseline.cities.flatMap(city => city.districts.flatMap(district => district.sites))
    .find(site => site.id === joined.baseId);
  const homeCity = baseline.cities.find(city => city.id === homeSite.cityId);
  const shopDistrict = homeCity.districts.find(district => district.area === homeCity.area && district.sites.some(site => site.type === 'departmentStore'));
  const shop = shopDistrict.sites.find(site => site.type === 'departmentStore');
  await click(new RegExp(`^${escape(shopDistrict.name)}\\.`));
  await click(new RegExp(`^${escape(shop.name)}\\.`));
  await click('Confirm order');
  await capture('06-queue-free-nearby-shop-trip');
  current = await advanceOneDay(ordered, baseline);
  assert.equal(current.ledger.expense.travel, baseline.ledger.expense.travel);
  assert.equal(current.ledger.expense.shopping, baseline.ledger.expense.shopping);
  for (const id of [fieldMember.id, prospect.id]) {
    const person = current.lcs.pool.find(entry => entry.id === id);
    assert.equal(person.locationId, `Site${person.baseId}`, 'Travellers return to base.');
  }
  await capture('07-returned-from-trip-with-no-travel-or-shopping-charge');
  for (const person of [fieldMember, prospect]) await assignDonation(person);
  while (report.days.length < 7) current = await advanceOneDay(current, baseline);
  assert.ok(current.ledger.totalIncome > baseline.ledger.totalIncome, 'Daily assignments earn real funds.');
  assert.equal(current.lcs.pool.length, baseline.lcs.pool.length + 1);
  assert.equal(current.lcs.squads.length, baseline.lcs.squads.length + 1);
  assert.deepEqual(current.lcs.squads.find(team => team.id === fieldTeam.id).members, fieldTeam.members);
  assert.equal(current.lcs.pool.find(person => person.id === prospect.id).equippedWeapon.typeName, weaponName);
  const trained = current.lcs.pool.find(person => person.id === learner.id);
  const learnerBefore = baseline.lcs.pool.find(person => person.id === learner.id);
  assert.ok(trained.rawSkill.science > learnerBefore.rawSkill.science ||
    trained.rawSkill.science === learnerBefore.rawSkill.science && trained.rawSkillXP.science > learnerBefore.rawSkillXP.science,
  'The study assignment must produce real skill or experience progress.');
  report.training = {
    personId: learner.id, skill: 'science',
    before: { level: learnerBefore.rawSkill.science, xp: learnerBefore.rawSkillXP.science },
    after: { level: trained.rawSkill.science, xp: trained.rawSkillXP.science },
  };
  report.fieldTeam = { id: fieldTeam.id, members: fieldTeam.members, transferredWeapon: weaponName };
  await capture('08-seven-days-retain-roster-squads-and-equipment');
  const exported = await exportGame('first-week-completed');
  await newContext();
  await importAndLoad(exported.path);
  const restored = (await exportGame('first-week-reimported')).state;
  assert.deepEqual(restored, exported.state, 'Fresh-profile import/export must retain the whole completed campaign exactly.');
  await capture('09-fresh-profile-import-preserves-entire-week');
  report.checks.push('seven-consecutive-calendar-days-and-accounting-verified', 'completed-save-exactly-identical-after-fresh-profile-import');
  }
  await verifyLoadedScript(expectedHash?.toLowerCase() ?? report.mainJsSha256);
  assert.deepEqual(report.pageErrors, []);
  assert.deepEqual(report.consoleErrors, []);
  assert.deepEqual(report.failedRequests, []);
  report.status = 'passed';
} catch (error) {
  report.status = 'failed';
  report.error = error.stack ?? String(error);
  process.exitCode = 1;
  if (page) {
    await page.screenshot({ path: resolve(output, 'FAILURE.png'), fullPage: true });
    await writeFile(resolve(output, 'FAILURE.txt'), await uiText());
    await writeFile(resolve(output, 'FAILURE.html'), await page.locator('flt-semantics-host').innerHTML());
  }
} finally {
  await context?.close();
  await browser.close();
  await writeFile(resolve(output, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ status: report.status, output, checks: report.checks.length, days: report.days.length, error: report.error }));
}
