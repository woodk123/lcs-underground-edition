// Real stdio MCP -> isolated compiled Flutter -> original readers. No fixtures
// or supplied outcomes in the default fresh-founder journey.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { dependencyRequire } from './server.mjs';
import { ROOT } from './session.mjs';

const { Client } = dependencyRequire('@modelcontextprotocol/client');
const { StdioClientTransport } = dependencyRequire('@modelcontextprotocol/client/stdio');
const args = process.argv.slice(2);
const arg = (name, fallback) => args.includes(name) ? args[args.indexOf(name) + 1] : fallback;
const transport = new StdioClientTransport({ command: process.execPath, args: [resolve(ROOT, 'scripts/dev_mcp/server.mjs')], stderr: 'pipe' });
let stderr = '', output, observation;
transport.stderr?.on('data', bytes => { stderr += bytes; });
const client = new Client({ name: 'lcs-development-mcp-smoke', version: '1.0.0' }, { versionNegotiation: { mode: 'auto' } });
const report = { status: 'running', scope: 'Real stdio MCP fresh founder, ten source background choices, actual day advancement, save/continue. No supplied campaign, rewards or outcomes.', checks: [], calls: [], started: new Date().toISOString() };

async function call(name, params = {}, expectError = false) {
  const started = performance.now();
  const answer = await client.callTool({ name, arguments: params }, undefined, { timeout: 60000 });
  const data = answer.structuredContent;
  report.calls.push({ name, elapsedMs: Math.round(performance.now() - started), error: answer.isError ?? false });
  if (expectError) { assert.ok(answer.isError, `${name} should reject the stale request.`); return data; }
  assert.ok(!answer.isError, `${name}: ${JSON.stringify(data)}`);
  if (data.observation) observation = data.observation;
  if (name === 'lcs_observe' || name === 'lcs_wait') observation = data;
  if (observation) assert.doesNotMatch(`${observation.text}\n${observation.report}`, /CRASH REPORT/i, 'A painted engine crash must fail this journey.');
  return data;
}
function currentKey(key) { return observation.actions.find(action => action.enabled && action.key.toLowerCase() === key.toLowerCase()); }
async function key(key) {
  const action = currentKey(key);
  assert.ok(action, `No source ${key} in ${observation.screen}: ${JSON.stringify(observation.actions)}`);
  return call('lcs_act', { revision: observation.revision, actionId: action.id });
}
function passed(name) { report.checks.push(name); console.log(`PASS ${name}`); }
async function retainedSession(started) {
  const session = JSON.parse(await readFile(resolve(started.evidenceDirectory, 'session.json'), 'utf8'));
  const trace = (await readFile(resolve(started.evidenceDirectory, 'trace.jsonl'), 'utf8'))
    .trim().split('\n').map(line => JSON.parse(line));
  const startup = trace.find(event => event.operation === 'session_start');
  assert.ok(startup, 'The retained trace must identify the actual session startup.');
  for (const evidence of [session, startup]) {
    assert.deepEqual(evidence.compiledSource, started.compiledSource);
    assert.deepEqual(evidence.checkedSource, started.checkedSource);
  }
  assert.deepEqual(session.pageErrors, []); assert.deepEqual(session.consoleErrors, []);
  assert.deepEqual(session.failedRequests, []);
  return session;
}
async function label(pattern, options = {}) {
  const action = observation.actions.find(action => action.enabled && pattern.test(action.label));
  assert.ok(action, `No source action matching ${pattern}: ${JSON.stringify(observation.actions)}`);
  return call('lcs_act', { revision: observation.revision, actionId: action.id, ...options });
}

try {
  await client.connect(transport);
  assert.equal((await client.listTools()).tools.length, 9);
  const started = await call('lcs_start', { webRoot: arg('--web-root', '.local/dev-mcp/web'),
    ...(arg('--expected-hash') ? { expectedHash: arg('--expected-hash') } : {}),
    ...(arg('--out') ? { output: arg('--out') } : {}) });
  output = started.evidenceDirectory;
  report.mainJsSha256 = started.mainJsSha256; report.sourceFreshness = started.sourceFreshness;
  report.compiledSource = started.compiledSource; report.checkedSource = started.checkedSource;
  if (started.sourceFreshness === 'verified_current_inputs') {
    assert.equal(started.compiledSource.inputs_sha256, started.checkedSource.inputs_sha256);
    assert.equal(observation.build.source,
      `${started.compiledSource.commit.slice(0, 8)}-${started.compiledSource.inputs_sha256.slice(0, 8)}`);
  }
  await call('lcs_capture', { name: 'title' });
  const old = { revision: observation.revision, actionId: currentKey('n').id };
  await key('n');
  const rejected = await call('lcs_act', old, true);
  assert.match(rejected.error.code, /stale/);
  await call('lcs_observe');
  await key('Enter'); // Campaign settings -> founder identity.
  await key('Enter'); // Identity -> manual background.
  for (let question = 1; question <= 10; question++) await key(question === 10 ? 'd' : 'a');
  const briefing = observation.actions.find(action => action.kind === 'acknowledgement');
  assert.ok(briefing && observation.actions.length === 1, 'Original political briefing must expose a sole acknowledgement.');
  const briefingResult = await call('lcs_continue_reports', { revision: observation.revision, actionId: briefing.id });
  assert.equal(briefingResult.completedReports, 1);
  assert.equal(briefingResult.stopReason, 'text_input', 'Bounded continuation must stop at the public-name reader.');
  report.briefingReports = briefingResult.reports;
  passed('bounded-source-report-continuation-stops-at-text-entry');
  assert.ok(observation.textInput, 'Original public-name reader should be pending.');
  await call('lcs_input_text', { revision: observation.revision, text: 'MCP Development Founder', submit: 'Enter' });
  assert.ok(currentKey('w') && currentKey('x'), 'Created founder must reach original headquarters actions.');
  const summary = await call('lcs_inspect', { scope: 'summary' });
  assert.ok(summary.people.some(person => person.name === 'MCP Development Founder'));
  const context = await call('lcs_inspect', { scope: 'context' });
  assert.ok(context.locations.some(site => site.id === summary.people[0].baseId && site.name));
  await call('lcs_capture', { name: 'fresh-headquarters', includeCampaign: true });
  passed('real-source-creation-and-text-input');
  passed('captured-stale-source-action-rejected');

  const before = await call('lcs_inspect', { scope: 'campaign' });
  const readerBefore = await call('lcs_observe');
  for (let count = 0; count < 3; count++) { await call('lcs_observe'); await call('lcs_inspect', { scope: 'summary' }); }
  assert.deepEqual(await call('lcs_inspect', { scope: 'campaign' }), before);
  assert.deepEqual(await call('lcs_observe'), readerBefore);
  passed('repeated-inspection-preserves-complete-campaign-and-reader');

  await key('w');
  let acknowledgements = 0;
  while (!(currentKey('w') && currentKey('x'))) {
    assert.ok(acknowledgements++ < 30, 'Day must return through bounded source acknowledgements.');
    const action = observation.actions.find(action => action.enabled && action.kind === 'acknowledgement')
      ?? observation.actions.find(action => action.enabled && ['Enter', 'Space'].includes(action.key));
    assert.ok(action, `Unexpected required decision during day: ${JSON.stringify(observation)}`);
    if (action.kind === 'acknowledgement' && observation.actions.length === 1) {
      const result = await call('lcs_continue_reports', { revision: observation.revision, actionId: action.id, maxReports: 30 });
      assert.equal(result.stopReason, 'decision');
      assert.ok(result.completedReports > 0);
      report.continuedReports = result.reports;
    } else {
      await call('lcs_act', { revision: observation.revision, actionId: action.id });
    }
  }
  const after = await call('lcs_inspect', { scope: 'summary' });
  assert.notEqual(after.date, summary.date, 'A real day must advance.');
  report.day = { before: summary.date, after: after.date, acknowledgements };
  await call('lcs_capture', { name: 'after-actual-day', includeCampaign: true });
  passed('actual-day-and-required-source-report-acknowledgements');

  const beforeSave = await call('lcs_inspect', { scope: 'campaign' });
  await key('x');
  await key('c');
  assert.ok(currentKey('w') && currentKey('x'));
  const firstLoad = await call('lcs_inspect', { scope: 'campaign' });
  // The original load repair accesses these lazy NPC getters (save_load.dart),
  // creating CEO/president on a fresh campaign's first load. Record that exact
  // source behavior; all other saved fields must remain identical.
  const expectedFirstLoad = structuredClone(beforeSave);
  let generated = 0;
  for (const field of ['_ceo', '_president']) {
    if (beforeSave.campaign.uniqueCreatures[field] === null) {
      const person = firstLoad.campaign.uniqueCreatures[field];
      assert.ok(person && person.id === beforeSave.campaign.nextCreatureId + generated);
      expectedFirstLoad.campaign.uniqueCreatures[field] = person;
      generated++;
    }
  }
  expectedFirstLoad.campaign.nextCreatureId += generated;
  assert.deepEqual(firstLoad, expectedFirstLoad);
  report.firstLoadNormalization = { generatedLazyUniqueNpcs: generated, source: 'save_load.dart CEO/president location repair' };
  await key('x'); await key('c');
  assert.deepEqual(await call('lcs_inspect', { scope: 'campaign' }), firstLoad);
  await call('lcs_capture', { name: 'saved-and-continued', includeCampaign: true });
  passed('source-save-and-continue-preserve-complete-campaign');
  await key('x');
  await label(/Load & Manage Saves/);
  const savedCampaign = observation.actions.find(action => action.enabled
    && action.entityType === 'save' && action.entityId === `${firstLoad.campaign.uniqueGameId}`);
  assert.ok(savedCampaign?.entityLabel?.includes('MCP Development Founder'),
    'The observed source save action must identify the saved campaign and founder.');
  report.saveAction = { revision: observation.revision, ...savedCampaign };
  await call('lcs_act', { revision: observation.revision, actionId: savedCampaign.id });
  const exported = await label(/Export Save File/, { expectDownload: true });
  assert.equal(exported.downloads.length, 1);
  const artifact = exported.downloads[0];
  const bytes = await readFile(artifact.path);
  assert.equal(bytes.length, artifact.bytes);
  assert.equal(createHash('sha256').update(bytes).digest('hex'), artifact.sha256);
  const saved = JSON.parse(bytes);
  assert.equal(`${saved.gameId}`, `${firstLoad.campaign.uniqueGameId}`);
  report.export = artifact;
  const closed = await call('lcs_close');
  assert.deepEqual(closed.cleanupErrors, []);
  assert.deepEqual(await readFile(artifact.path), bytes, 'Original exported bytes must survive context close.');
  const imported = await call('lcs_start', { fixture: artifact.path,
    webRoot: arg('--web-root', '.local/dev-mcp/web'),
    ...(arg('--expected-hash') ? { expectedHash: arg('--expected-hash') } : {}) });
  report.importEvidenceDirectory = imported.evidenceDirectory;
  assert.deepEqual(imported.compiledSource, started.compiledSource);
  assert.deepEqual(imported.checkedSource, started.checkedSource);
  assert.deepEqual(await call('lcs_inspect', { scope: 'campaign' }), firstLoad);
  await call('lcs_capture', { name: 'fresh-import', includeCampaign: true });
  assert.deepEqual((await call('lcs_close')).cleanupErrors, []);
  passed('retained-native-export-and-fresh-import-preserve-complete-campaign');
  const session = await retainedSession(started);
  assert.deepEqual((await retainedSession(imported)).failures, []);
  passed('compiled-and-checked-source-identities-retained');
  assert.equal(session.failures.length, 1, 'Only the intentional stale-action rejection is expected.');
  assert.match(session.failures[0].code, /stale/);
  assert.equal(stderr, '');
  report.status = 'passed';
} catch (error) {
  report.status = 'failed'; report.error = error.stack ?? String(error); process.exitCode = 1;
  try { await call('lcs_capture', { name: 'smoke-failure', includeCampaign: true }); } catch { /* Session startup can fail before evidence exists. */ }
} finally {
  try { await call('lcs_close'); } catch { /* Preserve original failure. */ }
  await client.close();
  report.completed = new Date().toISOString(); report.stderr = stderr;
  if (output) await writeFile(resolve(output, 'smoke.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ status: report.status, output, checks: report.checks, error: report.error?.slice(0, 500) }));
}
