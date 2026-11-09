// Guild Squads test runner: loads Core/*.lua into fengari (Lua 5.3 VM in JS) and runs tests/*_spec.lua.
// Usage: NODE_PATH=.node/node_modules node tests/run.js
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const root = path.resolve(__dirname, '..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function setGlobalTable(name, entries) {
  lua.lua_newtable(L);
  for (const [k, v] of entries) {
    if (typeof k === 'number') lua.lua_pushinteger(L, k); else lua.lua_pushstring(L, to_luastring(k));
    lua.lua_pushstring(L, to_luastring(v));
    lua.lua_settable(L, -3);
  }
  lua.lua_setglobal(L, to_luastring(name));
}

const core = ['Core/Serialize.lua', 'Core/Permissions.lua', 'Core/Chunk.lua', 'Core/Queue.lua', 'Core/Model.lua', 'Core/Match.lua', 'Core/Call.lua', 'Core/Content.lua', 'Core/Roster.lua', 'Core/Progress.lua', 'Core/Diag.lua', 'Core/Races.lua', 'Core/Catalog.lua', 'Core/Celebrate.lua', 'Core/Ed25519.lua', 'Core/Trust.lua', 'Core/Sig.lua', 'Core/Cert.lua', 'Core/P2P.lua'];
const wow = ['Locales/enUS.lua', 'Locales/esES.lua', 'Core/Logo.lua', 'Comm.lua', 'Sync.lua', 'UI/Widgets.lua', 'UI/Main.lua', 'GuildSquads.lua', 'Progress.lua', 'Hall.lua', 'Raids.lua', 'Diag.lua', 'UI/Panels.lua', 'UI/Ranking.lua', 'UI/Raids.lua', 'UI/Hall.lua', 'UI/Catalog.lua', 'UI/Minimap.lua'];
// Specs run in this order: several register SMOKE_CHECKS that run later inside zload_spec.lua (in registration
// order, sharing one fake client), so the order is part of the suite. A spec missing from the list fails the run.
const ORDER = [
  'regression_core_spec.lua',
  'regression_races_spec.lua',
  'regression_counters_spec.lua',
  'regression_rosters_spec.lua',
  'regression_model_spec.lua',
  'regression_glue_spec.lua',
  'regression_ui_spec.lua',
  'regression_wipes_spec.lua',
  'comm_spec.lua',
  'core_spec.lua',
  'progress_spec.lua',
  'wipes_seasons_spec.lua',
  'ui_layout_spec.lua',
  'squads_spec.lua',
  'sync_trust_spec.lua',
  'p2p_spec.lua',
  'ed25519_spec.lua',
  'trust_spec.lua',
  'keys_wire_spec.lua',
  'sig_spec.lua',
  'cert_spec.lua',
  'sigrules_spec.lua',
  'sigwire_spec.lua',
  'counters_spec.lua',
  'observations_spec.lua',
  'races_spec.lua',
  'sync_spec.lua',
  'peers_spec.lua',
  'robustness_spec.lua',
  'locales_spec.lua',
  'raids_attendance_spec.lua',
  'integrity_spec.lua',
  'convergence_spec.lua',
  'membership_spec.lua',
  'raids_spec.lua',
  'surnames_spec.lua',
  'ui_buttons_spec.lua',
  'pvp_rank_spec.lua',
  'catalog_spec.lua',
  'catalog_ui_spec.lua',
  'zload_spec.lua',
  'zzcold_spec.lua',
];
const found = fs.readdirSync(path.join(root, 'tests')).filter((f) => f.endsWith('_spec.lua')).sort();
const unlisted = found.filter((f) => !ORDER.includes(f)), missing = ORDER.filter((f) => !found.includes(f));
if (unlisted.length || missing.length) {
  console.error('tests/run.js ORDER is out of date. Not listed: ' + (unlisted.join(', ') || '-') + '. Missing: ' + (missing.join(', ') || '-'));
  process.exit(2);
}
const only = process.env.GSQ_ONLY ? process.env.GSQ_ONLY.split(',') : null; // iterate on a few specs
const specs = ORDER.filter((f) => !only || only.includes(f)).map((f) => 'tests/' + f);
const all = [...core, ...wow, ...specs, 'GuildSquads.toc'];
setGlobalTable('SOURCES', all.map((f) => [f, read(f)]));
setGlobalTable('CORE', core.map((f, i) => [i + 1, f]));
setGlobalTable('SPECS', specs.map((f, i) => [i + 1, f]));

// AF1 interop: fresh keys and signatures from node's crypto (OpenSSL), checked by the Lua port in ed25519_spec.lua
{
  const crypto = require('crypto');
  const fx = [];
  for (let i = 0; i < 2; i++) {
    const { privateKey, publicKey } = crypto.generateKeyPairSync('ed25519');
    const sk = privateKey.export({ format: 'der', type: 'pkcs8' }).subarray(-32);
    const pk = publicKey.export({ format: 'der', type: 'spki' }).subarray(-32);
    const msg = crypto.randomBytes(1 + i * 40);
    const sig = crypto.sign(null, msg, privateKey);
    fx.push([fx.length + 1, [sk, pk, msg, sig].map((b) => b.toString('hex')).join(':')]);
  }
  setGlobalTable('ED25519_NODE', fx);
}
const harness = read('tests/harness.lua');
if (lauxlib.luaL_loadbuffer(L, to_luastring(harness), null, to_luastring('@tests/harness.lua')) !== lua.LUA_OK ||
    lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
  console.error('harness error:', lua.lua_tojsstring(L, -1));
  process.exit(2);
}
lua.lua_getglobal(L, to_luastring('FAILED'));
const failed = lua.lua_tointeger(L, -1);
process.exit(failed === 0 ? 0 : 1);
