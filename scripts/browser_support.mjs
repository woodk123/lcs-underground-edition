// Shared browser QA safeguards. Never reuse a player profile or download a browser.
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';

export const QA_URL = 'http://127.0.0.1:18879/';

export function assertQaUrl(rawUrl = QA_URL) {
  const url = new URL(rawUrl);
  assert.equal(url.href, QA_URL,
    `Browser reviews must use the isolated QA server at ${QA_URL}`);
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
