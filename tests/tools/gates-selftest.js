// Self-test for tests/gates.js: a call used as a condition / operand is NOT a guard.
// Copies the addon to a temp dir, appends one fixture to UI/Widgets.lua and runs the gate on it.
// Usage: NODE_PATH=/tmp/gsq-node/node_modules node tests/tools/gates-selftest.js
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const root = path.resolve(__dirname, '..', '..');
const gates = path.join(root, 'tests', 'gates.js');
const cases = [
  // [lua appended, expected exit code]
  ['if GsqFakeApiA() then end', 1],
  ['local _x = GsqFakeApiB() or 0', 1],
  ['local _y = not GsqFakeApiC()', 1],
  ['local _z = GsqFakeApiD() and 1', 1],
  ['if GsqFakeApiE then GsqFakeApiE() end', 0],
];
let failed = 0;
for (const [lua, want] of cases) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'gsq-gates-'));
  fs.cpSync(root, tmp, { recursive: true, filter: (src) => !/[\\/](\.git|\.node|node_modules)$/.test(src) });
  fs.appendFileSync(path.join(tmp, 'UI', 'Widgets.lua'), '\n' + lua + '\n');
  const r = spawnSync(process.execPath, [gates], { env: { ...process.env, GSQ_GATES_ROOT: tmp }, encoding: 'utf8' });
  fs.rmSync(tmp, { recursive: true, force: true });
  const name = /GsqFakeApi[A-Z]/.exec(lua)[0];
  const flagged = (r.stdout || '').includes('API unguarded call not in 16001 list: ' + name);
  const ok = r.status === want && flagged === (want === 1);
  if (!ok) failed++;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${JSON.stringify(lua)} -> exit ${r.status} (want ${want})${flagged ? ', flagged' : ''}`);
}
console.log(failed === 0 ? 'GATES SELFTEST: OK' : `GATES SELFTEST: ${failed} failure(s)`);
process.exit(failed === 0 ? 0 : 1);
