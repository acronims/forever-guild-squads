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

// S24 (2.0.1, docs/SPEC-v2.0.1-sin-perfil.md AC2/AC6-AC9 end to end, real signatures): 4 clients on WoW Forever.
// Gm and Mb3 fill their profiles, Mb1 and Mb2 never touch theirs (only the automatic one of the login). The Gm's
// Buscador lists Mb1 and Mb2 as «No profile yet» and Mb3 as a profile; the Gm invites Mb1 and Mb2. Mb1 accepts with
// the automatic profile: nothing is signed (his db.seq does not move) and nobody counts him; then he saves a filled
// profile and that save joins: within 120 s the 4 clients count him a member. Mb2 never acts: after 240 s nobody
// counts him and his profile never pointed at the squad; the Gm's Buscador still lists him «No profile yet».
function S24(seed) {
  const sim = new Sim({ seed, forever: true });
  const { check, checks, pass } = checker();
  for (const [n, r] of [['Gm', 0], ['Mb1', 5], ['Mb2', 5], ['Mb3', 5]]) sim.addMember(n, r);
  const cs = sim.roster.map((r) => sim.client(r.name, {}));
  const [gm, mb1, mb2, mb3] = cs;
  for (const c of cs) { c.login(); sim.run(2 + sim.rand() * 3); }
  sim.run(60);
  gm.run('return A.SaveSettings({ squadsEnabled = true, bench = 2, minCreateRank = 9, officerRanks = { 1 }, banned = {} })');
  sim.run(20);
  check('Gm and Mb3 fill their profiles', gm.run('return A.SaveProfile({ role = "TANK", goals = { "raid" } })')[0] === true &&
    mb3.run('return A.SaveProfile({ role = "HEALER", goals = { "dungeons" } })')[0] === true);
  check('Gm creates a squad', gm.run('return A.CreateSquad({ name = "Los Lobos", icon = 1, color = 1, border = 1, tags = {}, open = false })')[0] === true);
  sim.run(90);
  const sid = s(gm, 'A.MySquadId()');
  const list = () => s(gm, `(function() local fd = NS.UI.FinderState(); fd.mode = "players"; NS.UI.Open("finder"); NS.UI.Select("finder")
      local t = {} for _, it in ipairs(fd.grid.items) do t[#t + 1] = it.player.name .. (it.player.noProfile and "*" or "") .. (it.player.unverified and "?" or "") end
      return table.concat(t, ",") end)()`);
  const l0 = list();
  check('the Gm\'s Buscador: Mb3 with a profile, then Mb1 and Mb2 «No profile yet»', l0 === 'Mb3 Apmb3,Mb1 Apmb1*,Mb2 Apmb2*', l0);
  check('Gm invites Mb1 and Mb2', gm.run('return A.AddMember(A.MySquadId(), "Mb1 Apmb1")')[0] === true &&
    gm.run('return A.AddMember(A.MySquadId(), "Mb2 Apmb2")')[0] === true);
  sim.run(90);
  check('Mb1 and Mb2 see the invitation', s(mb1, `table.concat(NS.Model.invites(NS.state, NS.me()), ",")`) === sid &&
    s(mb2, `table.concat(NS.Model.invites(NS.state, NS.me()), ",")`) === sid, sid);
  const seq0 = num(mb1, 'GuildSquadsDB.seq or 0');
  const r1 = mb1.run(`local ok, why = A.RequestJoin(${luaStr(sid)}); return tostring(ok) .. "|" .. tostring(why)`)[0];
  check('Mb1 accepts with the automatic profile: refused with profileIncomplete, Mi perfil open', r1 === 'false|profileIncomplete' && s(mb1, 'NS.UI.Current()') === 'profile',
    r1 + ' tab=' + s(mb1, 'NS.UI.Current()'));
  check('Mb1 signed nothing (db.seq unchanged)', num(mb1, 'GuildSquadsDB.seq or 0') === seq0, seq0 + ' -> ' + num(mb1, 'GuildSquadsDB.seq or 0'));
  sim.run(60);
  const member = (c, who) => s(c, `tostring(NS.Model.isMember(NS.state, ${luaStr(sid)}, ${luaStr(who)}))`);
  check('nobody counts Mb1 before his profile', cs.every((c) => member(c, 'Mb1 Apmb1') === 'false'), cs.map((c) => member(c, 'Mb1 Apmb1')).join(','));
  const t0 = sim.t;
  check('Mb1 saves a filled profile from Mi perfil (that save joins)', mb1.run('return A.SaveProfileDraft({ role = "DAMAGER", goals = { "raid" } })')[0] === true);
  check('Mb1 signed exactly one record for it', num(mb1, 'GuildSquadsDB.seq or 0') === seq0 + 1, num(mb1, 'GuildSquadsDB.seq or 0') - seq0);
  let tJoin = null;
  for (let k = 0; k < 24 && tJoin === null; k++) { sim.run(5); if (cs.every((c) => member(c, 'Mb1 Apmb1') === 'true')) tJoin = Math.round(sim.t - t0); }
  check('the 4 clients count Mb1 a member, <= 120 s', tJoin !== null, tJoin === null ? cs.map((c) => member(c, 'Mb1 Apmb1')).join(',') : tJoin + ' s');
  check('Mb1\'s profile is complete on the 4', cs.every((c) => s(c, 'tostring(NS.Model.profileComplete(NS.state.profiles["Mb1 Apmb1"].d))') === 'true'));
  sim.run(120);
  check('Mb2 never acted: nobody counts him, his profile never points at the squad', cs.every((c) => member(c, 'Mb2 Apmb2') === 'false' &&
    s(c, 'tostring(NS.state.profiles["Mb2 Apmb2"] and NS.state.profiles["Mb2 Apmb2"].d.squad)') !== sid), cs.map((c) => member(c, 'Mb2 Apmb2')).join(','));
  const l1 = list();
  check('the Gm\'s Buscador now: Mb3 and Mb2 «No profile yet» (Mb1 is in the squad)', l1 === 'Mb3 Apmb3,Mb2 Apmb2*', l1);
  errorsCheck(sim, check);
  return { pass: pass(), checks, metrics: { tJoin, t: Math.round(sim.t), ...sim.stats } };
}

module.exports = { S23, S17v2, S24 };
