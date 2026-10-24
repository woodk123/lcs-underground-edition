'use strict';

const { mkdirSync, mkdtempSync, writeFileSync } = require('node:fs');
const { createRequire } = require('node:module');
const { join, resolve } = require('node:path');
const install = require('./browser_netlog_patch.cjs');

const root = resolve(__dirname, '..');
// Resolve the same Playwright singleton used by the standalone browser helpers.
const helperRequire = createRequire(join(root, 'upstream/tool/offline_test/package.json'));
const { chromium } = helperRequire('playwright');
install(chromium, options => {
  const parent = join(root, '.local', 'browser-netlog');
  mkdirSync(parent, { recursive: true });
  const directory = mkdtempSync(join(parent, `launch-${process.pid}-`));
  writeFileSync(join(directory, 'launch.json'), JSON.stringify({
    createdAt: new Date().toISOString(), nodePid: process.pid, helperArgv: process.argv.slice(1),
    playwrightModule: helperRequire.resolve('playwright'),
    channel: options.channel ?? null, executablePath: options.executablePath ?? null,
    originalArgs: options.args ?? [],
    appendedFlags: [`--log-net-log=${directory}/netlog.json`, '--net-log-max-size-mb=32'],
    logLimitMiB: 32, rolling: true,
    captureMode: 'Chromium default redaction; no capture-mode override',
  }, null, 2) + '\n');
  process.stderr.write(`Rolling 32 MiB browser NetLog: ${directory}\n`);
  return directory;
});
