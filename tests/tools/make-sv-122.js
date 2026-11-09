// tests/tools/make-sv-122.js: builds tests/fixtures/sv-1.2.2.lua (SPEC-v2.0-identidad §8 AC5), the SavedVariables
// (GuildSquadsDB) of ONE account that played the 1.2.2 in WoW Forever, as the 2.0 migration (M.migrateIdentity) finds
// them. Usage:
//   NODE_PATH=/path/to/node_modules node tests/tools/make-sv-122.js [--check]
//   --check regenerates in memory and exits 1 if tests/fixtures/sv-1.2.2.lua differs (byte for byte).
// Pinned: the addon AND the simulator come from `git archive v1.2.2` into a temporary directory (GSQ_ROOT), so later
// changes to tests/sim/* or to the addon never change the fixture. Deterministic: seed 7303, simulated clock, keys from
// the addon's entropy pool fed by the fake (no real time), ed25519 / sha512 through node crypto (deterministic).
//
// What it plays (one guild «Forever» on «Realm», the 1.2.2 sim with senderFullName: senders «Name Surname»):
//   * this account: the main «Kas Pitas» (client "Kas") and the alt «Alt Apalt» (client "Alt"), never online together,
//     sharing one SavedVariables: Kas plays, logs out; Alt logs in with that file, plays, logs out; Kas again.
//   * a second «Kas» on the same realm, «Kas Mora» (another account, online in the roster, no addon). For the 1.2.2 both
//     are the key "Kas-Realm": ambiguous (GuildSquads.lua `ambig`), so the other clients ignore Kas Pitas; Kas Pitas
//     keeps his own entry.
//   * Gm (rank 0, settings), Mb (captain of a squad) and Nc (member of it), 1.2.2 clients: foreign signed records,
//     their manifests (sig.man), keys (trust.keys) and certificates (cert.crt).
//   * own records: Kas's profile, squad (members Kas + Gm, invited) and reject of Nc's request ("req"); Alt's profile
//     with a request to Mb's squad, which Mb rejects (a foreign record that names the alt).
//   * Kas writes his squad and reject in his LAST session: with the 1.2.2 the alt's session drops the main's records
//     from the file (for the alt "Kas-Realm" is ambiguous, out of the roster: notInGuild), so what Kas wrote before
//     the alt played is gone (measured in this run: only his key, his own manifest and later records survive).
// INJECT (after the run, documented below): what the 1.2.2 cannot keep on disk by itself. Its selectGuild sweeps the
// 1.2.0 keys «Name Surname-Realm» out of trust / sig / cert (M.sweepSurnames), and the two-Kas key is ambiguous, so
// no 1.2.2 data names it. Entries are built with the 1.2.2 functions (P.sanitize / P.eventId, R.sanitize / R.obsId).
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execSync } = require('child_process');

const REF = 'v1.2.2';
const SEED = 7303;
const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.join(ROOT, 'tests', 'fixtures', 'sv-1.2.2.lua');
const CHECK = process.argv.includes('--check');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'gsq-sv122-'));
let text, summary;
try {
  execSync(`git -C ${JSON.stringify(ROOT)} archive ${REF} | tar -x -C ${JSON.stringify(tmp)}`, { stdio: ['ignore', 'ignore', 'inherit'] });
  process.env.GSQ_ROOT = tmp;                        // read by sim.js when it is loaded (TOC and sources of v1.2.2)
  ({ text, summary } = generate(tmp));
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}

if (CHECK) {
  const cur = fs.existsSync(OUT) ? fs.readFileSync(OUT, 'utf8') : null;
  if (cur !== text) { console.log('make-sv-122 --check: ' + path.relative(ROOT, OUT) + ' differs from a fresh run'); process.exit(1); }
  console.log('make-sv-122 --check: ' + path.relative(ROOT, OUT) + ' is up to date (' + text.length + ' bytes)');
} else {
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, text);
  console.log('wrote ' + path.relative(ROOT, OUT) + ' (' + text.length + ' bytes)');
}
console.log(summary);

// "YYYY-MM-DD HH:MM:SS" (UTC) of a server time, like Diag.lua stamp()
function stampOf(ts) { return new Date(ts * 1000).toISOString().replace('T', ' ').slice(0, 19); }

function generate(tree) {
  const { Sim, luaStr } = require(path.join(tree, 'tests', 'sim', 'sim.js'));
  const { lua, lauxlib, lualib, to_luastring } = require('fengari');
  const log = [];
  const sim = new Sim({ seed: SEED, senderFullName: true });

  // ---- the 1.2.2 sim has one surname per first name (surnameOf) and keys clients by first name. Patched here, on this
  // instance only: a roster entry may carry `first` (the character's first name; `name` stays the unique key of its
  // client / presence) and `surname`. The server rules of the 1.2.2 sim (whisperSuffix 'never') are kept: a whisper
  // reaches only «Name Surname» exact, any other form is «not found».
  const firstOf = (r) => r.first || r.name;
  const surOf = (r) => r.surname || sim.surnameOf(firstOf(r));
  sim.rosterName = function (r) { return firstOf(r) + ' ' + surOf(r) + '-' + (r.realm || this.realm); };
  sim.senderName = function (from) {
    const r = this.roster.find((m) => m.name === from.name);
    return r ? firstOf(r) + ' ' + surOf(r) : from.full;
  };
  sim.whisperMember = function (from, target) {
    let name = target, realm = null;
    const dash = target.indexOf('-');
    if (dash >= 0) { name = target.slice(0, dash); realm = target.slice(dash + 1); }
    const sp = name.indexOf(' ');
    if (sp < 0 || realm !== null) return null;      // «Kas», «Kas-Realm», «Kas Pitas-Realm»: not found
    const first = name.slice(0, sp), surname = name.slice(sp + 1);
    return this.roster.find((m) => firstOf(m) === first && surOf(m) === surname) || null;
  };

  sim.addMember('Gm', 0);
  sim.addMember('Mb', 5);
  sim.addMember('Nc', 5);
  sim.roster.push({ name: 'Kas', first: 'Kas', surname: 'Pitas', rank: 5, level: 60, realm: null });      // this account
  sim.roster.push({ name: 'KasMora', first: 'Kas', surname: 'Mora', rank: 5, level: 60, realm: null });   // another one
  sim.addMember('Alt', 5);                                                                                  // this account
  sim.setPresent('KasMora', true);                   // online in the roster without the addon

  const run = (c, code) => { const r = c.run(code); log.push(c.name + ': ' + code.replace(/\s+/g, ' ').slice(0, 90) + ' -> ' + r.join(',')); return r; };
  const gm = sim.client('Gm'), mb = sim.client('Mb'), nc = sim.client('Nc'), kas = sim.client('Kas');
  for (const c of [gm, mb, nc, kas]) { c.login(); sim.run(1 + sim.rand() * 3); }
  sim.run(30);
  run(gm, 'return A.SaveSettings({ squadsEnabled = true, bench = 2, minCreateRank = 9, officerRanks = { 1 }, banned = {}, compEnabled = true })');
  sim.run(10);
  run(mb, 'return A.CreateSquad({ name = "Mb Squad", icon = 1, color = 1, border = 1, tags = {}, open = true })');
  sim.run(20);
  const mbSid = mb.val('A.MySquadId()')[0];
  run(nc, `return A.RequestJoin(${luaStr(mbSid)})`);
  sim.run(20);
  run(mb, `return A.AddMember(${luaStr(mbSid)}, "Nc")`);
  sim.run(400);
  kas.logout();
  log.push('Kas logout at t=' + Math.round(sim.t));

  const alt = sim.client('Alt', { saved: kas.saved });               // same account: the main's SavedVariables
  alt.login();
  sim.run(60);
  run(alt, `return A.RequestJoin(${luaStr(mbSid)})`);
  sim.run(30);
  run(mb, `return A.Reject(${luaStr(mbSid)}, "Alt", "req")`);       // foreign record naming the alt
  sim.run(400);
  alt.logout();
  log.push('Alt logout at t=' + Math.round(sim.t));

  kas.saved = alt.saved;                                             // the main again, with the alt's file
  const lastLoginAt = 1795000000 + Math.floor(sim.t);                // sim epoch + run time (Kas has no skew)
  kas.login();
  sim.run(30);
  run(kas, 'return A.CreateSquad({ name = "Kas Squad", icon = 2, color = 2, border = 1, tags = {}, open = true })');
  sim.run(10);
  const kasSid = kas.val('A.MySquadId()')[0];
  run(kas, `return A.AddMember(${luaStr(kasSid)}, "Gm")`);          // invited (Gm never sees it: Kas is ignored)
  run(kas, `return A.Reject(${luaStr(kasSid)}, "Nc", "req")`);      // a reject whose id names Nc
  sim.run(400);
  kas.logout();
  log.push('Kas logout at t=' + Math.round(sim.t));
  const errors = sim.errors();
  if (errors !== 0) throw new Error('caught Lua errors in the 1.2.2 run: ' + errors + '\n' + sim.errorText().slice(0, 800));

  // ---- INJECT + serialize in a fresh Lua state: the 1.2.2 fake (SIM_saveVars, the sim's own serializer) and the
  // 1.2.2 pure modules (P.eventId / R.obsId)
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const doLua = (src, name) => {
    if (lauxlib.luaL_loadbuffer(L, src instanceof Uint8Array ? src : to_luastring(src), null, to_luastring('@' + name)) !== lua.LUA_OK ||
        lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) throw new Error(name + ': ' + lua.lua_tojsstring(L, -1));
    const out = lua.lua_isstring(L, -1) ? lua.lua_tojsstring(L, -1) : null;
    lua.lua_pop(L, 1);
    return out;
  };
  const read = (f) => fs.readFileSync(path.join(tree, f));
  doLua('SIM_T = 0; SIM_CFG = { name = "Kas", realm = "Realm", grealm = "Realm", guild = "Forever", skew = 0, epoch = 1795000000, uptime0 = 1000 }; NS = {}', 'cfg');
  doLua(read('tests/sim/fakewow.lua'), 'tests/sim/fakewow.lua');
  for (const f of ['Core/Serialize.lua', 'Core/Permissions.lua', 'Core/Chunk.lua', 'Core/Queue.lua', 'Core/Model.lua', 'Core/Match.lua',
    'Core/Call.lua', 'Core/Content.lua', 'Core/Roster.lua', 'Core/Progress.lua', 'Core/Diag.lua', 'Core/Races.lua']) {
    const src = Buffer.concat([Buffer.from('return (function(...) '), read(f), Buffer.from('\nend)("GuildSquads", NS)')]);
    doLua(src, f);
  }
  doLua(Buffer.concat([Buffer.from('GuildSquadsDB = (function() '), Buffer.from(kas.saved), Buffer.from(' end)()')]), 'SavedVariables');
  const endTs = 1795000000 + Math.floor(sim.t);
  const injected = doLua(`
local P, R = NS.Progress, NS.Races
local db = GuildSquadsDB
local g = db.guilds and db.guilds["Forever-Realm"]
assert(g, "guild partition Forever-Realm")
local done = {}
local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end
-- (1) 1.2.0 leftovers: the 1.2.0 keyed trust, manifests and certificates by the roster form «Name Surname-Realm»
for _, w in ipairs({ { g.trust and g.trust.keys, "trust.keys" }, { g.sig and g.sig.man, "sig.man" }, { g.cert and g.cert.crt, "cert.crt" } }) do
  local t, label = w[1], w[2]
  assert(t and t["Mb-Realm"], label .. " has Mb-Realm")
  t["Mb Apmb-Realm"] = copy(t["Mb-Realm"])
  done[#done + 1] = label .. '["Mb Apmb-Realm"]'
end
-- (2) a progress event (party boss of Nc's squad) whose presence list holds the three forms the migration sees:
-- 1.2.0 «Mb Apmb-Realm», ambiguous «Kas-Realm» (Kas Pitas and Kas Mora) and the unambiguous old form «Nc-Realm»
g.progress = g.progress or {}
g.progress.events = g.progress.events or {}
local ev = assert(P.sanitize({ t = "boss", who = "Nc-Realm", ts = ${endTs - 300}, sid = ${luaStr(mbSid)}, it = "party",
  enc = 1443, inst = "Ragefire Chasm", boss = "Taragaman the Hungerer", pres = { "Nc-Realm", "Mb Apmb-Realm", "Kas-Realm" } }))
local evId = P.eventId(ev)
g.progress.events[evId] = ev
done[#done + 1] = "progress.events[" .. evId .. "]"
-- (3) race observations: a roster level report about the ambiguous «Kas-Realm» (by Mb) and Nc's own kill with a
-- 1.2.0 name among those present
g.races = g.races or {}
g.races.obs = g.races.obs or {}
local o1 = assert(R.sanitize({ t = "lv", who = "Kas-Realm", by = "Mb-Realm", src = "roster", lv = 30, ts = ${endTs - 250} }))
local o2 = assert(R.sanitize({ t = "kill", who = "Nc-Realm", by = "Nc-Realm", it = "party", enc = 1443, inst = "Ragefire Chasm",
  boss = "Taragaman the Hungerer", ts = ${endTs - 300}, pres = { "Nc-Realm", "Mb Apmb-Realm" }, sqm = {} }))
for _, o in ipairs({ o1, o2 }) do
  local id = R.obsId(o)
  g.races.obs[id] = o
  done[#done + 1] = "races.obs[" .. id .. "]"
end
-- (4) per-character counter state under the old key (Hall hkBase, Progress hkState), when the run left none
g.races.hkBase = type(g.races.hkBase) == "table" and g.races.hkBase or {}
if g.races.hkBase["Kas-Realm"] == nil then g.races.hkBase["Kas-Realm"] = 100; done[#done + 1] = 'races.hkBase["Kas-Realm"]' end
if g.progress.hkState == nil then
  g.progress.hkState = { who = "Kas-Realm:lifetime", v = 10, inst = false }
  done[#done + 1] = "progress.hkState"
end
-- NORMALIZE (not an injection): the fake's date() without a time reads the real clock, so diag.lastLogin (Diag.lua
-- stamp()) would change on every run; it gets the simulated time of the last login, in the same format (UTC)
if type(db.diag) == "table" and db.diag.lastLogin ~= nil then db.diag.lastLogin = ${luaStr(stampOf(lastLoginAt))} end
return table.concat(done, "\\n")`, 'inject');

  const body = doLua('return SIM_saveVars()', 'save');
  const header = [
    '-- GuildSquadsDB of ONE account after the 1.2.2 in WoW Forever (SPEC-v2.0-identidad §8 AC5): the main «Kas Pitas» and',
    '-- the alt «Alt Apalt» (same SavedVariables), a second «Kas» on the same realm («Kas Mora», another account), Gm, Mb',
    '-- and Nc on 1.2.2 clients. Played with the tag ' + REF + ' (addon and simulator), seed ' + SEED + ', plus the INJECT',
    '-- step (1.2.0 leftovers «Name Surname-Realm», names of the ambiguous «Kas-Realm»): see tests/tools/make-sv-122.js.',
    '-- Generated file, do not edit: NODE_PATH=... node tests/tools/make-sv-122.js (--check compares byte for byte).',
    '',
  ].join('\n');
  const out = header + body + '\n';

  // ---- load check and summary (from the final text)
  doLua(Buffer.concat([Buffer.from('FIX = (function() '), Buffer.from(out), Buffer.from(' end)()')]), 'fixture');
  const sum = doLua(`
local t = FIX
assert(type(t.guilds) == "table", "guilds")
local lines = {}
local function keys(x) local o = {} for k in pairs(type(x) == "table" and x or {}) do o[#o + 1] = tostring(k) end table.sort(o) return table.concat(o, ", ") end
local gk = {}
for k in pairs(t.guilds) do gk[#gk + 1] = k end
table.sort(gk)
lines[#lines + 1] = "guild partitions: " .. table.concat(gk, ", ")
lines[#lines + 1] = "ownKeys: " .. keys(t.ownKeys)
local g = t.guilds["Forever-Realm"]
local by = {}
for _, r in ipairs(g.records or {}) do local k = tostring(r.a) .. " " .. tostring(r.k); by[k] = (by[k] or 0) + 1 end
local bl = {}
for k, n in pairs(by) do bl[#bl + 1] = k .. "=" .. n end
table.sort(bl)
lines[#lines + 1] = "records (" .. #(g.records or {}) .. ") by author/kind: " .. table.concat(bl, ", ")
lines[#lines + 1] = "sig.own: " .. keys(g.sig and g.sig.own)
lines[#lines + 1] = "sig.man: " .. keys(g.sig and g.sig.man)
lines[#lines + 1] = "trust.keys: " .. keys(g.trust and g.trust.keys)
lines[#lines + 1] = "cert.crt: " .. keys(g.cert and g.cert.crt)
lines[#lines + 1] = "progress.events: " .. keys(g.progress and g.progress.events)
lines[#lines + 1] = "races.obs: " .. keys(g.races and g.races.obs)
lines[#lines + 1] = "races.hkBase: " .. keys(g.races and g.races.hkBase) .. " | progress.hkState.who: " .. tostring(g.progress and g.progress.hkState and g.progress.hkState.who)
return table.concat(lines, "\\n")`, 'summary');
  const summary = ['seed ' + SEED + ', ref ' + REF + ', simulated ' + Math.round(sim.t) + ' s, Lua errors 0',
    'squads: Mb ' + mbSid + ', Kas ' + kasSid, ...log.map((l) => '  ' + l), sum, 'injected:', ...injected.split('\n').map((l) => '  ' + l)].join('\n');
  return { text: out, summary };
}
