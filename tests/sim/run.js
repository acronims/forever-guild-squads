// Simulator runner. Usage: NODE_PATH=... node tests/sim/run.js [S1 S2 ...] [--seed N] [--s5seeds N] [--s9seeds N]
//   [--s8min N] [--s9min N] [--realm] [--json file]. Exit code 1 when any scenario fails or any server
//   «No hay ningún jugador» line reached a chat (SYSSHOWN total). --realm: the 1.2.x world (no WoW Forever names) for
//   the scenarios that do not pick a mode themselves (same as GSQ_SIM_FOREVER=0).
'use strict';
const fs = require('fs');
const SC = require('./scenarios.js');
const { Sim } = require('./sim.js');
const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf('--' + k); return i >= 0 ? args[i + 1] : d; };
const FLAGS = new Set(['--realm']);   // options without a value
const skip = new Set(); args.forEach((a, i) => { if (a.startsWith('--')) { skip.add(i); if (!FLAGS.has(a)) skip.add(i + 1); } });
if (args.includes('--realm')) Sim.FOREVER_DEFAULT = false;
let list = args.filter((a, i) => !skip.has(i));
if (list.length === 0) list = ['S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8', 'S9'];   // S10 only on demand: it needs GSQ_COMPAT_REF
const seed = Number(opt('seed', 7303));
const out = [];
let fails = 0;
for (const name of list) {
  const seeds = name === 'S9' ? Number(opt('s9seeds', 1)) : 1;
  for (let k = 0; k < seeds; k++) {
    const s = seed + k * 1000;
    const t0 = Date.now(), shown0 = Sim.sysShownTotal;
    let r;
    try {
      if (name === 'S5') r = SC.S5(s, Number(opt('s5seeds', 100)));
      else if (name === 'S8') r = SC.S8(s, Number(opt('s8min', 15)));
      else if (name === 'S9') r = SC.S9(s, Number(opt('s9min', 60)));
      else if (name === 'S8g') r = SC.S8g(s, Number(opt('s8gmin', 15)));
      else if (name === 'S13') r = SC.S13(s, Number(opt('s13min', 15)));
      else r = SC[name](s);
    } catch (e) { r = { pass: false, checks: [['exception', false, String(e && e.stack || e).slice(0, 600)]], metrics: {} }; }
    const secs = (Date.now() - t0) / 1000;
    const shown = Sim.sysShownTotal - shown0;
    console.log(`SIM ${name} seed=${s} ${r.pass ? 'PASS' : 'FAIL'} (${secs.toFixed(1)} s real) sysShown=${shown}`);
    for (const [label, ok, detail] of r.checks) console.log(`  ${ok ? 'ok ' : 'NO '} ${label}${detail !== '' ? ' -> ' + detail : ''}`);
    console.log('  metrics ' + JSON.stringify(r.metrics));
    if (!r.pass) fails++;
    out.push({ name, seed: s, pass: r.pass, secs, sysShown: shown, checks: r.checks, metrics: r.metrics });
  }
}
console.log(`SIM RESULT: ${out.length - fails}/${out.length} pass`);
// 2.0 (SPEC-v2.0-identidad AC8): the server's «No hay ningún jugador con el nombre X.» lines that reached a chat in
// the whole run (every scenario above); any line fails the run
console.log(`SYSSHOWN total=${Sim.sysShownTotal}`);
if (opt('json')) fs.writeFileSync(opt('json'), JSON.stringify(out, null, 1));
process.exit(fails || Sim.sysShownTotal !== 0 ? 1 : 0);
