// AF4 / AC5 (QA r2 D8): the part count of an S8 tally, checked against a cap.
// usage: node tests/tools/parts-check.js <tally5 log> <max parts>
// P = sum of the "P:..." lines of the last "--- end" block (tools/tally5.js). Exit 0 if P <= max, 1 if over, 2 on a bad log.
const fs = require('fs');
const [log, maxS] = process.argv.slice(2);
const max = Number(maxS);
if (!log || !Number.isFinite(max)) { console.error('usage: parts-check.js <log> <max>'); process.exit(2); }
const text = fs.readFileSync(log, 'utf8');
const i = text.lastIndexOf('--- end');
if (i < 0) { console.error('no "--- end" block in ' + log); process.exit(2); }
let P = 0, n = 0;
for (const line of text.slice(i).split('\n')) {
  const m = line.match(/^P:[^=]+=(\d+)$/);
  if (m) { P += Number(m[1]); n++; }
}
if (n === 0) { console.error('no P: lines in the last end block'); process.exit(2); }
const pass = /^true \{/m.test(text.slice(i)) && /model converged/.test(text);
console.log(`parts P=${P} (${n} lines) max=${max} -> ${P <= max ? 'OK' : 'OVER'}; S8 ${pass ? 'PASS' : 'not PASS'}`);
process.exit(P <= max && pass ? 0 : 1);
