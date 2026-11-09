// Self-test for tests/gates.js:
//   API       a call used as a condition / operand is NOT a guard (fixture appended to UI/Widgets.lua);
//   IDENTITY  (2.0, AC9) a unit name API read outside the identity code fails unless its line says `-- id-ok`
//             (fixture put at the top of the file: Hall.lua ends with `return H`).
// Copies the addon to a temp dir per case, adds one fixture and runs the gate on it.
// Usage: NODE_PATH=/tmp/gsq-node/node_modules node tests/tools/gates-selftest.js
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const root = path.resolve(__dirname, '..', '..');
const gates = path.join(root, 'tests', 'gates.js');
const API = (name) => 'API unguarded call not in 16001 list: ' + name;
const ID = (name, file) => `IDENTITY ${name} outside the identity code without "-- id-ok": ${file}:1 `;
const cases = [
  // [file, lua, where ('append' | 'top'), expected exit code, line the gate must print (expected exit 1) or must not print]
  ['UI/Widgets.lua', 'if GsqFakeApiA() then end', 'append', 1, API('GsqFakeApiA')],
  ['UI/Widgets.lua', 'local _x = GsqFakeApiB() or 0', 'append', 1, API('GsqFakeApiB')],
  ['UI/Widgets.lua', 'local _y = not GsqFakeApiC()', 'append', 1, API('GsqFakeApiC')],
  ['UI/Widgets.lua', 'local _z = GsqFakeApiD() and 1', 'append', 1, API('GsqFakeApiD')],
  ['UI/Widgets.lua', 'if GsqFakeApiE then GsqFakeApiE() end', 'append', 0, API('GsqFakeApiE')],
  ['Hall.lua', 'local _gsqA = UnitName("party1")', 'top', 1, ID('UnitName', 'Hall.lua')],
  ['Hall.lua', 'local _gsqB, _gsqB2 = pcall(UnitName, "party1")', 'top', 1, ID('UnitName', 'Hall.lua')],
  ['Progress.lua', 'local _gsqC = UnitFullName("party1")', 'top', 1, ID('UnitFullName', 'Progress.lua')],
  ['UI/Panels.lua', 'local _gsqD = _G.UnitNameUnmodified', 'top', 1, ID('UnitNameUnmodified', 'UI/Panels.lua')],
  ['Raids.lua', 'local _gsqE = ns and ns.apiFn and ns.apiFn("UnitName")', 'top', 1, ID('UnitName', 'Raids.lua')],
  ['Hall.lua', 'local _gsqF = UnitName("player") -- id-ok: selftest', 'top', 0, ID('UnitName', 'Hall.lua')],
  // GuildSquads.lua: only its identity functions (unitName, ns.idFromUnit, ns.me) may read the unit name
  ['GuildSquads.lua', 'local _gsqG = UnitName("player")', 'top', 1, ID('UnitName', 'GuildSquads.lua')],
  ['Core/Identity.lua', 'local _gsqH = UnitName', 'top', 0, ID('UnitName', 'Core/Identity.lua')],
];
let failed = 0;
for (const [file, lua, where, want, line] of cases) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'gsq-gates-'));
  fs.cpSync(root, tmp, { recursive: true, filter: (src) => !/[\\/](\.git|\.node|node_modules)$/.test(src) });
  const target = path.join(tmp, ...file.split('/'));
  const src = fs.readFileSync(target, 'utf8');
  fs.writeFileSync(target, where === 'top' ? lua + '\n' + src : src + '\n' + lua + '\n');
  const r = spawnSync(process.execPath, [gates], { env: { ...process.env, GSQ_GATES_ROOT: tmp }, encoding: 'utf8' });
  fs.rmSync(tmp, { recursive: true, force: true });
  const flagged = (r.stdout || '').includes(line);
  const ok = r.status === want && flagged === (want === 1);
  if (!ok) failed++;
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${file}: ${JSON.stringify(lua)} -> exit ${r.status} (want ${want})${flagged ? ', flagged' : ''}`);
}
console.log(failed === 0 ? 'GATES SELFTEST: OK' : `GATES SELFTEST: ${failed} failure(s)`);
process.exit(failed === 0 ? 0 : 1);
