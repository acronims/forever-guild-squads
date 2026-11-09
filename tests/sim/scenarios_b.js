// 2.0 scenarios of task B (docs/SPEC-v2.0-identidad.md §8 AC5 / AC6): the 1.2.2 SavedVariables migrated on login (S23)
// and the cut between PROTO 3 and the 1.2.2 (S17v2). tests/sim/scenarios.js exports them with one line
// (Object.assign(module.exports, require('./scenarios_b.js'))); self-contained (no require of scenarios.js: no cycle).
'use strict';
const fs = require('fs');
const path = require('path');
const { Sim, luaStr, sourcesAt } = require('./sim.js');

function checker() {
  const checks = [];
  const check = (label, ok, detail) => { checks.push([label, !!ok, detail === undefined ? '' : String(detail)]); return !!ok; };
  return { checks, check, pass: () => checks.every((c) => c[1]) };
}
function errorsCheck(sim, check) {
  const n = sim.errors();
  check('caught Lua errors = 0', n === 0, n === 0 ? 0 : n + ': ' + sim.errorText().slice(0, 400));
}
const FIXTURE = path.join(__dirname, '..', 'fixtures', 'sv-1.2.2.lua');
const num = (c, expr) => Number(c.val(expr)[0]);
const s = (c, expr) => String(c.val(expr)[0]);

// S23 (AC5): three clients start with the 1.2.2 SavedVariables of tests/fixtures/sv-1.2.2.lua (each its own copy, as
// if it had played that account: tests/tools/make-sv-122.js) on a WoW Forever realm. Each one migrates as its own
// character (Model.migrateIdentity, step 1 + step 2), gets a new key, re-signs its records (first manifest n = 1) and
// they verify each other within 600 s. Then the alt of the account logs in on the main's file: his records waited in
// resign and are re-signed now. Criteria: 0 Lua errors; no old name («-») in trust / manifests / certificates of any
// of them; no 1.x key of a character that logged in; every pair verified (manifest + profile strong) in <= 600 s; the
// main's first manifest is n = 1; the alt's records wait (none loaded) until he logs in, then the others verify him.
function S23(seed) {
  const sim = new Sim({ seed, forever: true, epoch: 1795100000 });   // after the fixture (its records: ~1795001000)
  const { check, checks, pass } = checker();
  const saved = fs.readFileSync(FIXTURE);
  sim.addMember('Kas Pitas', 5); sim.addMember('Kas Mora', 5); sim.addMember('Alt Apalt', 5);
  sim.addMember('Gm', 0); sim.addMember('Mb', 5); sim.addMember('Nc', 5);
  sim.setPresent('Kas Mora', true);
  const names = ['Kas Pitas', 'Gm', 'Mb'];
  const cs = names.map((n) => sim.client(n, { saved }));
  for (const c of cs) { c.login(); sim.run(3 + sim.rand() * 4); }
  const t0 = sim.t;
  const oldLeft = (c) => num(c, `(function() local g, n = NS.gdb, 0
    for _, t in ipairs({ g.trust and g.trust.keys, g.trust and g.trust.pend, g.sig and g.sig.man, g.sig and g.sig.own, g.cert and g.cert.crt }) do
      for k in pairs(type(t) == "table" and t or {}) do if type(k) == "string" and k:find("-", 1, true) then n = n + 1 end end
    end return n end)()`);
  // the first own manifest of each one (n = 1 right after the migration)
  let firstN = {};
  const pairsOk = () => {
    const miss = [];
    for (const a of cs) for (const b of cs) {
      if (a === b) continue;
      const okV = s(a, `(function() local id = ${luaStr(b.full)}; local m = NS.sigDB and NS.sigDB.man[id]
        local p = NS.state.profiles and NS.state.profiles[id]
        return tostring(m ~= nil and p ~= nil and NS.Sig.status(NS.sigDB, p) == "strong") end)()`);
      if (okV !== 'true') miss.push(a.name + '<-' + b.name);
    }
    return miss;
  };
  let miss = ['?'], at = null;
  while (sim.t - t0 < 600) {
    sim.run(10);
    for (const c of cs) if (firstN[c.name] === undefined) {
      const n = s(c, '(function() local m = NS.sigDB and NS.sigDB.own and NS.sigDB.own[NS.me()]; return m and tostring(m.n) or "nil" end)()');
      if (n !== 'nil') firstN[c.name] = n;
    }
    miss = pairsOk();
    if (miss.length === 0) { at = sim.t - t0; break; }
  }
  check('every client is «Name Surname» (forever mode)', cs.every((c) => s(c, 'NS.me()') === c.full && s(c, 'NS.ID_MODE') === 'forever'), cs.map((c) => s(c, 'NS.me()')).join(','));
  check('every pair verified each other (manifest + profile strong) within 600 s', miss.length === 0, miss.length ? miss.join(',') : `${Math.round(at)} s`);
  check('the first own manifest after the migration is n = 1', cs.every((c) => firstN[c.name] === '1'), JSON.stringify(firstN));
  const olds = cs.map((c) => `${c.name}:${oldLeft(c)}`);
  check('no old name («-») in trust / manifests / certificates', cs.every((c) => oldLeft(c) === 0), olds.join(','));
  const keys = cs.map((c) => s(c, `(function() local k = {} for n in pairs(GuildSquadsDB.ownKeys or {}) do k[#k + 1] = n end table.sort(k) return table.concat(k, "|") end)()`));
  check('own keys: the new identity, never the 1.x key of a character that logged in', cs.every((c, i) => keys[i].split('|').includes(c.full) && !keys[i].split('|').includes(c.first + '-' + c.realm)), keys.join(' ; '));
  const foreign = cs.map((c) => num(c, `(function() local n = 0 for _, r in ipairs(NS.Model.allRecords(NS.state)) do if r.a:find("-", 1, true) then n = n + 1 end end return n end)()`));
  check('no record by an old name in any state (D1: the 1.x signatures of others are gone)', foreign.every((n) => n === 0), foreign.join(','));
  const kas = cs[0];
  const waiting = s(kas, `(function() local o = {} for _, r in ipairs(NS.gdb.resign or {}) do o[#o + 1] = r.a .. ":" .. tostring(r.resign) end return table.concat(o, ",") end)()`);
  check('the alt\'s records wait in resign on the main\'s file (none loaded)', /Alt Apalt:true/.test(waiting) && s(kas, 'tostring(NS.state.profiles["Alt Apalt"] ~= nil)') === 'false', waiting);
  // the alt logs in on the main's SavedVariables (same account): his records are re-signed and verified by the others
  kas.logout(); sim.run(5);
  const alt = sim.client('Alt Apalt', { saved: kas.saved });
  alt.login();
  let altAt = null;
  const t1 = sim.t;
  while (sim.t - t1 < 600) {
    sim.run(10);
    const okAlt = cs.slice(1).every((c) => s(c, `(function() local p = NS.state.profiles["Alt Apalt"]; return tostring(p ~= nil and NS.Sig.status(NS.sigDB, p) == "strong") end)()`) === 'true');
    if (okAlt) { altAt = sim.t - t1; break; }
  }
  check('the alt re-signs his records on login and the others verify him within 600 s', altAt !== null, altAt === null ? 'no' : `${Math.round(altAt)} s`);
  check('nothing waits on the alt\'s file for him any more', s(alt, `(function() for _, r in ipairs(NS.gdb.resign or {}) do if r.a == "Alt Apalt" then return "waiting" end end return "none" end)()`) === 'none');
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { verifiedAt: at, altAt, firstN, ...sim.stats } };
}

// S17v2 (AC6): PROTO 3 cuts the 1.2.2 off. 6 clients on a WoW Forever realm: Gm, Mb1, Mb2, Mb3 on the 2.0; Mb4, Mb5 on
// the 1.2.2 (GSQ_REF_122, default the tag v1.2.2). Everyone logs in, the GM writes the settings, everyone saves a
// profile, Mb1 and Mb4 reload. Criteria: 0 Lua errors in the 6; no 2.0 client holds a record authored by a 1.2.2 one
// and no 1.2.2 client holds anything written by a 2.0 one; the 2.0 clients sync among themselves and count old = 2.
const REF122 = process.env.GSQ_REF_122 || 'v1.2.2';
function S17v2(seed) {
  const sim = new Sim({ seed, forever: true });
  const { check, checks, pass } = checker();
  const v122 = sourcesAt(REF122);
  sim.addMember('Gm', 0);
  for (let i = 1; i <= 5; i++) sim.addMember('Mb' + i, 5);
  const olds = ['Mb4', 'Mb5'], news = ['Gm', 'Mb1', 'Mb2', 'Mb3'];
  const cs = {};
  for (const n of [...news, ...olds]) cs[n] = sim.client(n, olds.includes(n) ? { code: v122 } : {});
  for (const n of [...news, ...olds]) { cs[n].login(); sim.run(2 + sim.rand() * 3); }
  sim.run(20);
  check('GM settings written', cs.Gm.run('return A.SaveSettings({ squadsEnabled = true, bench = 2, minCreateRank = 9, officerRanks = { 1 }, banned = {}, compEnabled = true })')[0] === true);
  for (const n of [...news, ...olds]) { cs[n].run(`return A.SaveProfile({ note = ${luaStr('soy ' + n)} })`); sim.run(2); }
  sim.run(120);
  cs.Mb1.reload(); sim.run(3); cs.Mb4.reload();
  sim.run(300);
  // every note a client holds, with the author of its record
  const notes = (c) => s(c, `(function() local o = {} for _, p in pairs(NS.state.profiles or {}) do
    if type(p) == "table" and type(p.d) == "table" and p.d.note then o[#o + 1] = p.a .. "=" .. p.d.note end end
    table.sort(o) return table.concat(o, "|") end)()`).split('|').filter(Boolean);
  const leakNew = [], leakOld = [], missNew = [];
  for (const n of news) {
    const got = notes(cs[n]);
    for (const o of olds) if (got.some((x) => x.endsWith('=soy ' + o))) leakNew.push(`${n}<-${o}`);
    for (const m of news) if (m !== n && !got.includes(`${cs[m].full}=soy ${m}`)) missNew.push(`${n}<-${m}`);
  }
  for (const o of olds) {
    const got = notes(cs[o]);
    for (const n of news) if (got.some((x) => x.endsWith('=soy ' + n))) leakOld.push(`${o}<-${n}`);
    if (s(cs[o], '(function() local st = NS.state.settings; return tostring(st ~= nil) end)()') === 'true') leakOld.push(`${o}:settings`);
  }
  check('the 2.0 clients sync among themselves (every 2.0 profile, authored by «Name Surname»)', missNew.length === 0, missNew.join(','));
  check('no 2.0 client holds a record of a 1.2.2 client', leakNew.length === 0, leakNew.join(','));
  check('no 1.2.2 client holds anything of a 2.0 client (profiles, settings)', leakOld.length === 0, leakOld.join(','));
  const cnt = news.map((n) => `${n}:${num(cs[n], 'NS.Comm.OldPeerCount()')}`);
  // Mb1 reloaded after the old ones spoke: it counts the ones it heard again (Mb4 reloaded after it)
  check('the 2.0 clients count old = 2 (Comm.OldPeerCount, one per identity)', news.filter((n) => n !== 'Mb1').every((n) => num(cs[n], 'NS.Comm.OldPeerCount()') === 2), cnt.join(','));
  // the local OLD_PEERS line (§4.3: «... anterior a la 2.0 ...»), once per session
  const lines = news.map((n) => [n, (s(cs[n], '(function() local o = {} for _, e in ipairs(SIM_LOCAL or {}) do if type(e) == "table" and e.s then o[#o + 1] = e.s end end return table.concat(o, "\\n") end)()').match(/anterior a la 2\.0|older than 2\.0/g) || []).length]);
  check('every 2.0 client writes the OLD_PEERS line («... 2.0 ...») exactly once', lines.every((x) => x[1] === 1), lines.map((x) => x.join(':')).join(','));
  const diag = (c) => s(c, 'NS.Comm.ProtoDiag and NS.Comm.ProtoDiag() or "no ProtoDiag"');
  check('the diag line says proto v=3 old=N', news.every((n) => /^proto v=3 old=\d+$/.test(diag(cs[n]))), diag(cs.Gm));
  const badOld = olds.map((o) => `${o}:${num(cs[o], 'NS.Comm.stats.badProto')}`);
  check('the 1.2.2 clients drop the 2.0 messages (badProto > 0) without Lua errors', olds.every((o) => num(cs[o], 'NS.Comm.stats.badProto') > 0), badOld.join(','));
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { ref: REF122, oldPeers: cnt, ...sim.stats } };
}

module.exports = { S23, S17v2 };
