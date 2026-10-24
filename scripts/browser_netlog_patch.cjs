'use strict';

// One recorder per Playwright singleton prevents duplicate diagnostic flags.
const marker = Symbol.for('lcs.maintenance.bounded-netlog-preload');

module.exports = function install(chromium, prepareLog) {
  if (chromium[marker]) return false;
  const original = chromium.launch;
  if (typeof original !== 'function') throw TypeError('Expected the required Playwright chromium.launch method.');
  chromium.launch = function (options = {}, ...rest) {
    const args = options.args ?? [];
    if (!Array.isArray(args)) throw TypeError('Playwright launch args must be an array.');
    if (args.some(arg => /^(?:--?|\/)(?:log-net-log|net-log-max-size-mb|net-log-capture-mode)(?:=|$)/i.test(arg))) {
      throw Error('The helper already supplies NetLog flags; refuse conflicting diagnostic options.');
    }
    const directory = prepareLog(options);
    return Reflect.apply(original, this, [{ ...options, args: [...args,
      `--log-net-log=${directory}/netlog.json`, '--net-log-max-size-mb=32'] }, ...rest]);
  };
  Object.defineProperty(chromium, marker, { value: true });
  return true;
};
