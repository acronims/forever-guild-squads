// tests/tools/make-sv-200.js: builds tests/fixtures/sv-2.0.0.lua (SPEC-v2.1 AC3), the SavedVariables of the account of
// tests/fixtures/sv-1.2.2.lua AFTER the migration of the published 2.0.0 (main «Kas Pitas» logged in once with it),
// as the 2.1 finds them. Usage:
//   NODE_PATH=/path/to/node_modules node tests/tools/make-sv-200.js [--check]
//   --check regenerates in memory and exits 1 if tests/fixtures/sv-2.0.0.lua differs (byte for byte).
// Pinned: the Core modules (Serialize .. Catalog, Identity, Model) come from `git show v2.0.0:<file>`; the serializer
// is SIM_saveVars of tests/sim/fakewow.lua at v2.0.0. Deterministic (no keys are made: the migration only moves data).
// INJECT (before the 2.0.0 migration, documented below): 1.x local data the run of make-sv-122.js does not produce and
// that the 2.0.0 migration leaves on the old name (CHANGELOG 2.0.0, known limits): achievements won, known levels, a
// closed race, and an annulment and a confirmation of the main (as if he were the GM) that embed a name in their id.
'use strict';
process.env.TZ = 'UTC';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const REF = 'v2.0.0';
const ROOT = path.resolve(__dirname, '..', '..');
const IN = path.join(ROOT, 'tests', 'fixtures', 'sv-1.2.2.lua');
const OUT = path.join(ROOT, 'tests', 'fixtures', 'sv-2.0.0.lua');
const CHECK = process.argv.includes('--check');
const show = (f) => execFileSync('git', ['show', REF + ':' + f], { cwd: ROOT, maxBuffer: 64 << 20 });

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const doLua = (src, name) => {
  if (lauxlib.luaL_loadbuffer(L, src instanceof Uint8Array ? src : to_luastring(src), null, to_luastring('@' + name)) !== lua.LUA_OK ||
      lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) throw new Error(name + ': ' + lua.lua_tojsstring(L, -1));
  const out = lua.lua_isstring(L, -1) ? lua.lua_tojsstring(L, -1) : null;
  lua.lua_pop(L, 1);
  return out;
};
doLua('SIM_T = 0; SIM_CFG = { name = "Kas", realm = "Realm", grealm = "Realm", guild = "Forever", skew = 0, epoch = 1795000000, uptime0 = 1000 }; NS = {}', 'cfg');
doLua(show('tests/sim/fakewow.lua'), REF + ':tests/sim/fakewow.lua');
for (const f of ['Core/Serialize.lua', 'Core/Permissions.lua', 'Core/Chunk.lua', 'Core/Queue.lua', 'Core/Identity.lua', 'Core/Model.lua',
  'Core/Match.lua', 'Core/Call.lua', 'Core/Content.lua', 'Core/Roster.lua', 'Core/Progress.lua', 'Core/Diag.lua', 'Core/Races.lua',
  'Core/Catalog.lua']) {
  doLua(Buffer.concat([Buffer.from('return (function(...) '), show(f), Buffer.from('\nend)("GuildSquads", NS)')]), REF + ':' + f);
}
const src122 = fs.readFileSync(IN);
doLua(Buffer.concat([Buffer.from('GuildSquadsDB = (function() '), src122, Buffer.from(' end)()')]), 'sv-1.2.2.lua');
const summary = doLua(`
local M, I, P, R, Ro, Ca = NS.Model, NS.Identity, NS.Progress, NS.Races, NS.Roster, NS.Catalog
local db = GuildSquadsDB
local g = assert(db.guilds["Forever-Realm"], "partition")
-- INJECT (1.x data, old names): achievements won, known levels, a closed race, own annul + vconfirm
g.progress.ach = { char = { ["Kas-Realm"] = { first1 = 1795000100 }, ["Nc-Realm"] = { squad60 = 1795000200 } },
                   squad = { ["Kas-Realm:1795001009"] = { hallOfFame = 1795000300 } } }
g.progress.lvKnown = { ["Nc-Realm"] = 30, ["Mb-Realm"] = 20 }
g.races.ach = { char = { ["Mb-Realm"] = { top10class = 1795000500 } }, squad = {}, guild = g.races.ach and g.races.ach.guild or {} }
local rows = {}
for i = 1, R.def("lvl.all.10").size do
  local who = (i == 1) and "Nc-Realm" or (i == 2 and "Mb-Realm" or ("Mb" .. i .. " Ap" .. i))
  rows[i] = { key = who, ts = 1795000000 + i, chars = { who }, squads = (i == 1) and { "Mb-Realm:1795000050" } or {},
              sup = (i == 1) and { "Mb-Realm" } or {}, wit = 2 }
end
g.races.closed = { ["lvl.all.10"] = { rows = rows, at = 1795000900 } }
local oid
for id, o in pairs(g.races.obs) do if o.t == "kill" then oid = id end end
assert(oid, "a kill observation in the 1.2.2 fixture")
g.records[#g.records + 1] = { a = "Kas-Realm", k = "annul", id = "lvl.all.10|Nc-Realm", sq = 12, ts = 1795001030,
  d = { race = "lvl.all.10", key = "Nc-Realm", reason = "test", on = true } }
g.records[#g.records + 1] = { a = "Kas-Realm", k = "annul", id = "sq.kill.1|Mb-Realm:1795000050", sq = 13, ts = 1795001031,
  d = { race = "sq.kill.1", key = "Mb-Realm:1795000050", reason = "squad", on = true } }
g.records[#g.records + 1] = { a = "Kas-Realm", k = "vconfirm", id = oid, sq = 14, ts = 1795001032, d = { oid = oid } }
-- the 2.0.0 migration of the main, with the roster of migration_spec (forever mode, everyone on «Realm»)
local ix = I.newIndex()
for _, m in ipairs({ { "Kas", "Pitas" }, { "Kas", "Mora" }, { "Alt", "Apalt" }, { "Gm", "Apgm" }, { "Mb", "Apmb" }, { "Nc", "Apnc" } }) do
  I.indexAdd(ix, m[1] .. " " .. m[2], m[1], m[2], "Realm")
end
local ictx = { mode = "forever", myRealm = "Realm", index = ix }
local ctx = { mode = "forever", id = function(n) return I.id(n, nil, ictx) end, me = "Kas Pitas", oldMe = "Kas-Realm",
  now = 1795100000, eventId = P.eventId, obsId = R.obsId, rsvpId = Ro.rsvpId, grantId = Ca.grantId }
local r = M.migrateIdentity(db, g, ctx)
assert(r.guild and r.char, "the 2.0.0 migration ran")
local out = {}
for _, k in ipairs({ "swept", "dropped", "resign", "remapped", "removed", "resigned" }) do out[#out + 1] = k .. "=" .. tostring(r[k]) end
return table.concat(out, " ")`, 'inject+migrate');
const body = doLua('return SIM_saveVars()', 'save');
const header = [
  '-- GuildSquadsDB of the account of tests/fixtures/sv-1.2.2.lua after the migration of the published 2.0.0 (SPEC-v2.1',
  '-- AC3): the main «Kas Pitas» logged in once with ' + REF + '. Before the migration, INJECT adds 1.x data the 2.0.0 leaves',
  '-- on the old name (achievements, known levels, a closed race, an own annul and vconfirm): see tests/tools/make-sv-200.js.',
  '-- Generated file, do not edit: NODE_PATH=... node tests/tools/make-sv-200.js (--check compares byte for byte).',
  '',
].join('\n');
const text = header + body + '\n';
if (CHECK) {
  const cur = fs.existsSync(OUT) ? fs.readFileSync(OUT, 'utf8') : '';
  if (cur !== text) { console.error('tests/fixtures/sv-2.0.0.lua is out of date'); process.exit(1); }
  console.log('sv-2.0.0.lua up to date (' + summary + ')');
} else {
  fs.writeFileSync(OUT, text);
  console.log('wrote tests/fixtures/sv-2.0.0.lua (' + text.length + ' bytes); 2.0.0 migration: ' + summary);
}
