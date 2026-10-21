// One owned QA browser and server. No player origins, profiles or campaign edits.
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { execFile } from 'node:child_process';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { appendFile, mkdir, readFile, realpath, stat, writeFile } from 'node:fs/promises';
import { dirname, extname, isAbsolute, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { chromiumLaunchOptions, observeMainScript, waitForSemantics } from '../browser_support.mjs';

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const browserRequire = createRequire(resolve(ROOT, 'upstream/tool/offline_test/package.json'));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const contained = (root, path) => { const part = relative(root, path); return part !== '..' && !part.startsWith(`..${sep}`) && !isAbsolute(part); };
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const runFile = promisify(execFile);

export class BridgeError extends Error {
  constructor(error, observation) { super(error.message); this.code = error.code; this.observation = observation; }
}

export async function evidenceDirectory(root, requested) {
  const target = resolve(root, requested ?? `reports/dev-mcp/${new Date().toISOString().replaceAll(':', '-')}-${randomUUID().slice(0, 8)}`);
  assert.ok(['reports', '.local'].some(name => contained(resolve(root, name), target) && target !== resolve(root, name)),
    'Evidence output must be a new child directory under reports/ or .local/.');
  // Check existing ancestors before mkdir so a symlink cannot create files elsewhere.
  let ancestor = dirname(target);
  const canonicalRoot = await realpath(root);
  while (true) {
    try {
      const actual = await realpath(ancestor);
      const expected = resolve(canonicalRoot, relative(resolve(root), ancestor));
      assert.ok(contained(canonicalRoot, actual) && relative(expected, actual) === '', 'Evidence path escapes its ignored directory through a symlink.');
      break;
    }
    catch (error) { if (error.code !== 'ENOENT') throw error; ancestor = dirname(ancestor); }
  }
  await mkdir(dirname(target), { recursive: true });
  await mkdir(target, { recursive: false });
  return target;
}

// Dedicated server binds an OS-assigned loopback port and serves only this build.
export async function serveBuild(directory) {
  const root = await realpath(directory);
  const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json',
    '.wasm': 'application/wasm', '.png': 'image/png', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.css': 'text/css', '.ttf': 'font/ttf', '.otf': 'font/otf' };
  const server = createServer(async (request, response) => {
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    try {
      if (!['GET', 'HEAD'].includes(request.method)) { response.writeHead(405).end(); return; }
      const pathname = decodeURIComponent(new URL(request.url, 'http://127.0.0.1').pathname);
      if (pathname === '/__lcs_launcher_health') {
        response.setHeader('Content-Type', 'application/json');
        response.end(JSON.stringify({ application: 'lcs-dev-mcp', directory: root })); return;
      }
      const candidate = resolve(root, `.${pathname === '/' ? '/index.html' : pathname}`);
      if (!contained(root, candidate)) { response.writeHead(404).end(); return; }
      const file = await realpath(candidate);
      if (!contained(root, file) || !(await stat(file)).isFile()) { response.writeHead(404).end(); return; }
      const bytes = await readFile(file);
      response.setHeader('Content-Type', types[extname(file)] ?? 'application/octet-stream');
      response.setHeader('Content-Length', bytes.length);
      response.end(request.method === 'HEAD' ? undefined : bytes);
    } catch (error) { response.writeHead(error instanceof URIError ? 400 : 404).end(); }
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  return { url: `http://127.0.0.1:${server.address().port}/`, directory: root,
    close: () => new Promise((resolve, reject) => { server.close(error => error ? reject(error) : resolve()); server.closeAllConnections(); }) };
}

export class DevelopmentSession {
  constructor({ root = ROOT, launchBrowser, validatePrepared } = {}) {
    this.root = root;
    this.launchBrowser = launchBrowser ?? (async options => browserRequire('playwright').chromium.launch(options));
    this.validatePrepared = validatePrepared ?? (async webRoot => {
      const { stdout } = await runFile(process.env.PYTHON ?? 'python', [resolve(this.root, 'scripts/prepare_dev_mcp.py'), '--check', '--out', dirname(webRoot)],
        { cwd: this.root, timeout: 15000, maxBuffer: 1024 * 1024 });
      return JSON.parse(stdout);
    });
    this.queue = Promise.resolve();
  }

  _serial(operation) {
    const pending = this.queue.then(operation);
    this.queue = pending.catch(() => {});
    return pending;
  }

  async _record(operation, data) {
    if (this.output) await appendFile(resolve(this.output, 'trace.jsonl'), `${JSON.stringify({ time: new Date().toISOString(), operation, ...data })}\n`);
  }

  async _report() {
    if (this.output && this.report) await writeFile(resolve(this.output, 'session.json'), JSON.stringify(this.report, null, 2));
  }

  async _bridge(method, params = {}, timeoutMs = 30000) {
    assert.ok(this.page, 'Start a development session first.');
    const response = await this.page.evaluate(async ({ request, timeoutMs }) => {
      if (!globalThis.lcsDev?.request) throw Error('Development bridge missing. Build with --dart-define=LCS_DEVTOOLS=true.');
      let timer;
      try {
        return await Promise.race([globalThis.lcsDev.request(JSON.stringify(request)),
          new Promise((_, reject) => { timer = setTimeout(() => reject(Error('Development bridge request timed out; do not blindly retry an action.')), timeoutMs); })]);
      } finally { clearTimeout(timer); }
    }, { request: { method, params }, timeoutMs });
    const envelope = JSON.parse(response);
    if (!envelope.ok) throw new BridgeError(envelope.error, envelope.observation);
    return envelope.result;
  }

  async _failure(operation, error, params) {
    if (!error.observation && this.page) {
      try { error.observation = await this._bridge('observe', {}, 2000); } catch { /* Retain original failure. */ }
    }
    await this._record(operation, { params, error: { code: error.code ?? 'session_error', message: error.message }, observation: error.observation });
    if (this.report) { this.report.failures.push({ operation, code: error.code ?? 'session_error', message: error.message }); await this._report(); }
    // Keep evidence even if a reader or input request failed.
    if (this.page && this.output) {
      try { await this.page.screenshot({ path: resolve(this.output, 'last-failure.png') }); } catch { /* Browser may already have exited. */ }
    }
  }

  start(options) { return this._serial(async () => {
    const startedAt = performance.now();
    assert.ok(!this.disconnected, 'MCP client disconnected.');
    assert.ok(!this.page && !this.server, 'Close the current session before starting another.');
    this.output = undefined; this.report = undefined;
    try {
      const webRoot = await realpath(resolve(this.root, options.webRoot ?? '.local/dev-mcp/web'));
      await stat(resolve(webRoot, 'index.html'));
      const expected = hash(await readFile(resolve(webRoot, 'main.dart.js')));
      if (options.expectedHash) assert.equal(expected, options.expectedHash.toLowerCase(), 'Local web build does not match expectedHash.');
      // Windows TEMP may use an 8.3 alias (RUNNER~1), and a checkout may be
      // reached through a junction. Compare canonical paths on both sides so
      // those spellings cannot bypass the default build's freshness check.
      let defaultWebRoot;
      try { defaultWebRoot = await realpath(resolve(this.root, '.local/dev-mcp/web')); }
      catch (error) { if (error.code !== 'ENOENT') throw error; }
      const currentPrepared = defaultWebRoot && relative(defaultWebRoot, webRoot) === ''
        ? await this.validatePrepared(webRoot) : undefined;
      const requested = options.output ?? `reports/dev-mcp/${new Date().toISOString().replaceAll(':', '-')}-${randomUUID().slice(0, 8)}`;
      this.output = await evidenceDirectory(this.root, requested);
      this.report = { schema: 1, status: 'starting', started: new Date().toISOString(), webRoot,
        sourceFreshness: currentPrepared ? 'verified_current_checkout' : 'not_checked_custom_build',
        mainJsSha256: expected, loadedMainJsHashes: [], failures: [], pageErrors: [], consoleErrors: [], failedRequests: [],
        preparedFixture: options.fixture ? resolve(this.root, options.fixture) : null,
        scope: 'Disposable browser; source actions only. Any imported fixture is supplied setup, not an earned campaign.' };
      try {
        const prepared = JSON.parse(await readFile(resolve(webRoot, '../build.json'), 'utf8'));
        if (resolve(prepared.web_root ?? '') === webRoot) {
          assert.equal(prepared.status, 'ready', 'Prepared build is not ready. Run prepare_dev_mcp.py.');
          assert.equal(prepared.main_js_sha256, expected, 'Prepared build metadata is stale. Run prepare_dev_mcp.py.');
          this.report.preparedBuild = prepared;
        }
      } catch (error) { if (error.code !== 'ENOENT') throw error; }
      this.server = await serveBuild(webRoot);
      assert.ok(!this.disconnected, 'MCP client disconnected.');
      this.report.url = this.server.url;
      const args = options.browserExecutable ? ['--browser-executable', options.browserExecutable] : [];
      this.browser = await this.launchBrowser(chromiumLaunchOptions({ args, channel: options.browser ?? 'msedge', headless: !options.headed }));
      assert.ok(!this.disconnected, 'MCP client disconnected.');
      this.context = await this.browser.newContext({ viewport: { width: options.width ?? 1440, height: options.height ?? 1000 }, acceptDownloads: true, serviceWorkers: 'block' });
      this.page = await this.context.newPage();
      this.page.setDefaultTimeout(20000);
      const verify = observeMainScript(this.page, this.report);
      this.page.on('pageerror', error => this.report.pageErrors.push(String(error)));
      this.page.on('console', message => { if (message.type() === 'error') this.report.consoleErrors.push(message.text()); });
      this.page.on('requestfailed', request => this.report.failedRequests.push(request.url()));
      await this.page.goto(this.server.url, { waitUntil: 'domcontentloaded' });
      await this.page.waitForFunction(() => !!globalThis.lcsDev?.request, null, { timeout: 30000 });
      let observation = await this._wait({ timeoutMs: 30000 });
      assert.equal(observation.bridgeVersion, 1, 'Unsupported development bridge version.');
      await verify(expected);
      this.report.build = observation.build;
      if (options.fixture) { await this._importFixture(resolve(this.root, options.fixture)); observation = await this._wait({ timeoutMs: 30000 }); }
      this.report.status = 'active';
      this.report.startupElapsedMs = Math.round(performance.now() - startedAt);
      await this._record('session_start', { build: this.report.build, mainJsSha256: expected, fixture: this.report.preparedFixture, observation, elapsedMs: this.report.startupElapsedMs });
      await this._report();
      return { evidenceDirectory: this.output, mainJsSha256: expected, sourceFreshness: this.report.sourceFreshness, url: this.server.url, observation };
    } catch (error) {
      await this._failure('session_start', error, options);
      await this._close('failed');
      throw error;
    }
  }); }

  async _importFixture(path) {
    await stat(path);
    // File import necessarily uses Flutter's actual browser picker, then all
    // loading choices return to source actions. No localStorage injection.
    await waitForSemantics(this.page, /Start a New Game/);
    const chooser = this.page.waitForEvent('filechooser');
    await this.page.getByRole('button', { name: /^Import a Save/ }).first().click();
    await (await chooser).setFiles(path);
    await waitForSemantics(this.page, /Save imported/);
    await this._select(/continue|enter|any key/i, 'Enter');
    await waitForSemantics(this.page, /Start a New Game/);
    await this._select(/Load & Manage Saves/);
    await this._select(/^A(?:\s|$)/, 'A');
    await this._select(/Load Game/, 'L');
    await waitForSemantics(this.page, /Save & exit/);
    await this._record('fixture_import', { path, sha256: hash(await readFile(path)) });
  }

  async _select(pattern, key) {
    const observation = await this._wait({ timeoutMs: 30000 });
    const action = observation.actions.find(action => action.enabled && pattern.test(action.label))
      ?? observation.actions.find(action => action.enabled && action.key === key);
    assert.ok(action, `No current source action matches ${pattern}.`);
    await this._bridge('act', { revision: observation.revision, actionId: action.id });
  }

  observe() { return this._serial(() => this._bridge('observe')); }
  inspect(params = {}) { return this._serial(() => this._bridge('inspect', params)); }

  async _wait({ afterRevision, timeoutMs = 10000, screen } = {}) {
    const deadline = Date.now() + timeoutMs;
    let observation;
    do {
      observation = await this._bridge('observe');
      if (observation.awaitingInput && (afterRevision === undefined || observation.revision !== afterRevision)
        && (screen === undefined || observation.screen === screen)) return observation;
      if (Date.now() >= deadline) break;
      await sleep(40);
    } while (true);
    throw new BridgeError({ code: 'wait_timeout', message: `No matching input-ready reader within ${timeoutMs}ms.` }, observation);
  }

  wait(params) { return this._serial(async () => {
    try { return await this._wait(params); }
    catch (error) { await this._failure('wait', error, params); throw error; }
  }); }

  command(method, params) { return this._serial(async () => {
    const startedAt = performance.now();
    let before, beforeSummary;
    try {
      before = await this._bridge('observe');
      beforeSummary = await this._bridge('inspect', { scope: 'summary' });
      const result = await this._bridge(method, params);
      const observation = await this._wait({ timeoutMs: 30000 });
      const afterSummary = await this._bridge('inspect', { scope: 'summary' });
      const changedFields = [...new Set([...Object.keys(beforeSummary), ...Object.keys(afterSummary)])]
        .filter(key => JSON.stringify(beforeSummary[key]) !== JSON.stringify(afterSummary[key]));
      const elapsedMs = Math.round(performance.now() - startedAt);
      await this._record(method, { params, before, result, observation, beforeSummary, afterSummary, changedFields, elapsedMs });
      await this._report();
      const { observation: _alreadyReturned, ...accepted } = result;
      return { result: accepted, observation, changedFields, elapsedMs };
    } catch (error) { await this._failure(method, error, { ...params, elapsedMs: Math.round(performance.now() - startedAt) }); throw error; }
  }); }

  capture({ name = 'capture', includeCampaign = false } = {}) { return this._serial(async () => {
    assert.match(name, /^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/, 'Use a short filename without path characters.');
    assert.ok(this.page && this.output, 'Start a development session first.');
    const observation = await this._bridge('observe');
    const inspection = await this._bridge('inspect', { scope: includeCampaign ? 'campaign' : 'summary' });
    const stem = `${Date.now()}-${name}`;
    const screenshot = resolve(this.output, `${stem}.png`), snapshot = resolve(this.output, `${stem}.json`);
    await this.page.screenshot({ path: screenshot });
    await writeFile(snapshot, JSON.stringify({ mainJsSha256: this.report.mainJsSha256, observation, inspection }, null, 2));
    await this._record('capture', { screenshot, snapshot });
    await this._report();
    return { screenshot, snapshot, trace: resolve(this.output, 'trace.jsonl'), session: resolve(this.output, 'session.json'), observation };
  }); }

  async _close(status = 'closed') {
    if (!this.context && !this.browser && !this.server && this.report?.closed) {
      return { status: this.report.status, evidenceDirectory: this.output, cleanupErrors: this.report.cleanupErrors ?? [] };
    }
    const failures = [];
    for (const [field, close] of [['context', value => value.close()], ['browser', value => value.close()], ['server', value => value.close()]]) {
      if (this[field]) { try { await close(this[field]); } catch (error) { failures.push(error.message); } this[field] = undefined; }
    }
    this.page = undefined;
    if (this.report) {
      this.report.status = status;
      this.report.hasErrors = Boolean(this.report.failures.length || this.report.pageErrors.length || this.report.consoleErrors.length || failures.length);
      this.report.closed = new Date().toISOString(); this.report.cleanupErrors = failures; await this._report();
    }
    return { status, evidenceDirectory: this.output, cleanupErrors: failures };
  }
  close() { return this._serial(() => this._close()); }
  // A lost host must release browser/server handles even if an input wait is
  // currently queued. Closing the page makes the in-flight call fail promptly.
  shutdown() { this.disconnected = true; return this._close('disconnected'); }
}
