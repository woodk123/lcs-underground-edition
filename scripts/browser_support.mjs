// Shared browser QA safeguards. Never reuse a player profile or download a browser.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';

export const QA_URL = 'http://127.0.0.1:18879/';

// Flutter's accessible reader includes labels and editable values that aren't
// present in innerText. Wait on the same evidence that journey assertions use.
export async function waitForSemantics(page, pattern, { timeout = 20000 } = {}) {
  const handle = await page.waitForFunction(({ source, flags, exact }) => {
    const host = document.querySelector('flt-semantics-host');
    if (!host) return false;
    const text = [host.innerText,
      ...[...host.querySelectorAll('[aria-label]')].map(node => node.getAttribute('aria-label')),
      ...[...host.querySelectorAll('input,textarea')].map(node => node.value),
    ].filter(Boolean).join('\n');
    return exact === undefined ? new RegExp(source, flags).test(text) : text === exact;
  }, typeof pattern === 'string' ? { exact: pattern } : { source: pattern.source, flags: pattern.flags },
  { timeout, polling: 'raf' });
  await handle.dispose();
}

// For scrolling, resizing, screenshots and deliberately ignored keys there
// isn't always a new reader to wait for. Observe stable semantics/layout over
// rendered frames instead of sleeping a guessed number of milliseconds.
// Callers still wait for the expected reader/control after navigation.
export async function waitForUiSettled(page) {
  await page.evaluate(() => new Promise((resolve, reject) => {
    let previous, stable = 0, frame;
    const timer = setTimeout(() => {
      cancelAnimationFrame(frame);
      reject(new Error('Flutter semantics/layout did not settle within 10 seconds.'));
    }, 10000);
    function check() {
      const host = document.querySelector('flt-semantics-host');
      const snapshot = host?.outerHTML;
      stable = snapshot && snapshot === previous ? stable + 1 : 0;
      previous = snapshot;
      if (stable >= 3) {
        clearTimeout(timer);
        resolve();
      } else frame = requestAnimationFrame(check);
    }
    frame = requestAnimationFrame(check);
  }));
}

export async function revealPersonnelDossier(page, name) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const target = page.getByRole('button', { name: new RegExp(`^Open dossier for ${escaped}\\.`) }).first();
  for (let attempt = 0; attempt < 24; attempt++) {
    const viewport = page.viewportSize();
    const box = await target.count() ? await target.boundingBox() : null;
    if (box && box.height > 5 && box.y > 75 && box.y + Math.min(25, box.height / 2) < viewport.height - 70) return target;
    // Rows outside Flutter's clipped/virtualized reader need ordinary scrolling;
    // waiting for a locator alone cannot make an offscreen person appear.
    // At enlarged reading sizes the fixed People header can occupy over half
    // the viewport. Aim inside the list, above the persistent footer.
    await page.mouse.move(viewport.width * .76, viewport.height - 105);
    await page.mouse.wheel(0, box && box.y < 75 ? -180 : 180);
    await waitForUiSettled(page);
  }
  throw new Error(`Cannot reach personnel dossier for ${name}`);
}

// Prefetching a hash alone does not prove what the browser executed (including
// service-worker/cache responses). Observe the actual script in every profile.
export function observeMainScript(page, report) {
  const tasks = [], hashes = [], errors = [];
  report.loadedMainJsHashes ??= [];
  page.on('response', response => {
    if (new URL(response.url()).pathname.endsWith('/main.dart.js')) {
      tasks.push(response.body().then(body => {
        const hash = createHash('sha256').update(body).digest('hex');
        hashes.push(hash); report.loadedMainJsHashes.push(hash);
      }, error => { errors.push(String(error)); }));
    }
  });
  return async expectedHash => {
    await Promise.all(tasks);
    assert.deepEqual(errors, [], 'Read the actual browser-loaded JavaScript.');
    assert.ok(hashes.length, 'The browser must have loaded main.dart.js.');
    for (const hash of hashes) assert.equal(hash, expectedHash, 'Browser loaded a different compiled build.');
  };
}

export function assertQaUrl(rawUrl = QA_URL, defaultUrl = QA_URL) {
  const expected = process.env.LCS_ACCEPTANCE_QA_URL ?? defaultUrl;
  if (process.env.LCS_ACCEPTANCE_QA_URL) {
    const owned = new URL(expected);
    assert.ok(owned.hostname === '127.0.0.1' && owned.protocol === 'http:'
      && Number(owned.port) >= 18879 && Number(owned.port) <= 18999
      && owned.href === `${owned.origin}/`, 'Use an isolated QA server in the dedicated port range.');
  }
  const url = new URL(rawUrl);
  assert.equal(url.href, expected,
    `Browser reviews must use the isolated QA server at ${expected}`);
  return url.href;
}

export function chromiumLaunchOptions({
  channel = 'msedge', args = process.argv.slice(2), headless = true,
} = {}) {
  assert.ok(['msedge', 'chrome'].includes(channel), 'Use installed Microsoft Edge or Chrome.');
  const executableFlag = args.indexOf('--browser-executable');
  if (executableFlag >= 0) {
    const executable = args[executableFlag + 1];
    assert.ok(executable && !executable.startsWith('--'), '--browser-executable requires a path.');
    const executablePath = resolve(executable);
    assert.ok(existsSync(executablePath), `Browser executable not found: ${executablePath}`);
    return { channel, executablePath, headless };
  }

  // Playwright channel lookup can miss browsers installed system-wide on Windows.
  // Retain the requested browser while checking its standard installed locations.
  const relativePath = channel === 'msedge'
    ? 'Microsoft/Edge/Application/msedge.exe'
    : 'Google/Chrome/Application/chrome.exe';
  const roots = [process.env.LOCALAPPDATA, process.env.PROGRAMFILES,
    process.env['PROGRAMFILES(X86)']].filter(Boolean);
  const executablePath = process.platform === 'win32'
    ? roots.map(root => resolve(root, relativePath)).find(path => existsSync(path))
    : undefined;
  return { channel, ...(executablePath ? { executablePath } : {}), headless };
}
