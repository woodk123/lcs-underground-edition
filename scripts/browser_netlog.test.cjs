'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const install = require('./browser_netlog_patch.cjs');

test('launch preserves options, receiver, extra arguments and the exact returned promise', () => {
  const result = Promise.resolve('same returned promise'), receiver = {}, env = { EXAMPLE: 'kept' };
  let observed, prepared = 0;
  const chromium = { launch(options, extra) { observed = { options, extra, receiver: this }; return result; } };
  assert.equal(install(chromium, original => { prepared++; assert.equal(original, options); return 'C:/ignored/log space'; }), true);
  const options = { channel: 'msedge', executablePath: 'C:/browser path/msedge.exe', headless: true,
    timeout: 15000, env, ignoreDefaultArgs: ['--example'], args: ['--existing=unchanged', '--other'] };
  const before = structuredClone(options);
  assert.equal(chromium.launch.call(receiver, options, 'extra'), result);
  assert.equal(observed.receiver, receiver);
  assert.equal(observed.extra, 'extra');
  assert.equal(observed.options.env, env);
  assert.deepEqual(options, before);
  assert.deepEqual(observed.options, { ...options, args: [...options.args,
    '--log-net-log=C:/ignored/log space/netlog.json', '--net-log-max-size-mb=32'] });
  assert.equal(prepared, 1);
});

test('double installation cannot replace the method or append flags twice', () => {
  let options;
  const chromium = { launch(value) { options = value; } };
  install(chromium, () => 'C:/first');
  const patched = chromium.launch;
  assert.equal(install(chromium, () => { throw Error('Must not prepare another log'); }), false);
  assert.equal(chromium.launch, patched);
  chromium.launch();
  assert.deepEqual(options.args, ['--log-net-log=C:/first/netlog.json', '--net-log-max-size-mb=32']);
});

test('conflicting NetLog flags and invalid args are rejected before preparation or launch', () => {
  const chromium = { launch() { throw Error('Must not launch'); } };
  install(chromium, () => { throw Error('Must not prepare'); });
  for (const flag of ['--log-net-log=old.json', '--net-log-max-size-mb=1', '--net-log-capture-mode=Everything',
    '--log-net-log', '--net-log-max-size-mb', '--net-log-capture-mode']) {
    assert.throws(() => chromium.launch({ args: [flag] }), /already supplies NetLog/);
  }
  assert.throws(() => chromium.launch({ args: '--not-an-array' }), /must be an array/);
});
